--!strict
--[[
	ArenaService — Duelos 1v1.
	Owner: Dev A (Combat).

	Flujo:
	  1. Cliente A → "DuelRequest"(B)            → servidor valida y envía "DuelInvite"(A) a B
	  2. Cliente B → "DuelResponse"(A, accepted) → si acepta, empieza el duelo
	  3. Arena generada por código (una por duelo) → "Countdown" → "Fight" → "End"
	  Fin: muerte (Defeat), salida del juego / reset del personaje (Forfeit) o tiempo (Timeout = empate).
	Revancha: si A desafía a B mientras B tiene un desafío pendiente de A, el duelo empieza directo.

	Attributes que ESCRIBE: Player.InDuel (boolean). Es true desde la cuenta regresiva hasta el fin.
	Payload de "DuelStateChanged": ver DuelStatePayload (documentado en ARCHITECTURE.md).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

type DuelPhase = "Countdown" | "Fighting" | "Ended"
type EndReason = "Defeat" | "Forfeit" | "Timeout"

type Duel = {
	players: { Player },
	phase: DuelPhase,
	slot: number,
	arena: Model,
	returnCFrames: { [Player]: CFrame },
	connections: { RBXScriptConnection },
}

type Invite = {
	from: Player,
	expiresAt: number,
}

export type DuelStatePayload = {
	State: "InviteSent" | "Declined" | "Unavailable" | "Countdown" | "Fight" | "End",
	Opponent: Player?,
	Seconds: number?, -- solo en "Countdown"
	EndsAt: number?, -- solo en "Fight": workspace:GetServerTimeNow() en que termina por tiempo
	Winner: Player?, -- solo en "End" (nil = empate)
	Reason: EndReason?, -- solo en "End"
}

-- ── Tuning ──
local INVITE_TTL = 15
local REQUEST_COOLDOWN = 3
local COUNTDOWN_SECONDS = 3
local DUEL_TIMEOUT = 120
local END_RETURN_DELAY = 2.5

local ARENA_ORIGIN = Vector3.new(0, 1000, 0)
local ARENA_SPACING = 200
local ARENA_SIZE = 60
local WALL_HEIGHT = 20

-- ── Estado ──
local duelsByPlayer: { [Player]: Duel } = {}
local invites: { [Player]: Invite } = {} -- clave: jugador desafiado
local lastRequestAt: { [Player]: number } = {}
local usedSlots: { [number]: boolean } = {}

local ArenaService = {}

-- ── API pública (la usa CombatService) ──

-- true si `a` y `b` están en el mismo duelo y en fase de pelea.
function ArenaService.AreOpponents(a: Player, b: Player): boolean
	local duel = duelsByPlayer[a]
	return a ~= b and duel ~= nil and duelsByPlayer[b] == duel and duel.phase == "Fighting"
end

-- ── Helpers ──

local function getAliveParts(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if humanoid then humanoid.RootPart else nil
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil, nil
end

local function isAvailable(player: Player): boolean
	if player.Parent ~= Players or duelsByPlayer[player] then
		return false
	end
	local humanoid = getAliveParts(player)
	return humanoid ~= nil
end

local function sendState(player: Player, payload: DuelStatePayload)
	if player.Parent == Players then
		Remotes.GetEvent("DuelStateChanged"):FireClient(player, payload)
	end
end

-- El personaje por defecto trae un Script "Health" que regenera 1% de vida por segundo.
-- En duelo se desactiva; al volver se reactiva (si el jugador murió, el personaje nuevo ya lo trae activo).
local function setRegenEnabled(character: Model, enabled: boolean)
	local regen = character:FindFirstChild("Health")
	if regen and regen:IsA("Script") then
		regen.Enabled = enabled
	end
end

local function otherPlayer(duel: Duel, player: Player): Player
	return if duel.players[1] == player then duel.players[2] else duel.players[1]
end

-- ── Arena ──

local function allocateSlot(): number
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

local function buildArena(slot: number): (Model, { CFrame })
	local origin = ARENA_ORIGIN + Vector3.new(slot * ARENA_SPACING, 0, 0)
	local half = ARENA_SIZE / 2

	local model = Instance.new("Model")
	model.Name = `DuelArena_{slot}`

	local function addPart(name: string, size: Vector3, position: Vector3, transparency: number)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = size
		part.CFrame = CFrame.new(position)
		part.Transparency = transparency
		part.Material = Enum.Material.Slate
		part.Color = Color3.fromRGB(70, 70, 80)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.Parent = model
	end

	addPart("Floor", Vector3.new(ARENA_SIZE, 1, ARENA_SIZE), origin, 0)
	local wallY = WALL_HEIGHT / 2
	addPart("WallN", Vector3.new(ARENA_SIZE, WALL_HEIGHT, 1), origin + Vector3.new(0, wallY, -half), 0.7)
	addPart("WallS", Vector3.new(ARENA_SIZE, WALL_HEIGHT, 1), origin + Vector3.new(0, wallY, half), 0.7)
	addPart("WallE", Vector3.new(1, WALL_HEIGHT, ARENA_SIZE), origin + Vector3.new(half, wallY, 0), 0.7)
	addPart("WallW", Vector3.new(1, WALL_HEIGHT, ARENA_SIZE), origin + Vector3.new(-half, wallY, 0), 0.7)

	model.Parent = workspace

	local center = origin + Vector3.new(0, 3, 0)
	local spawnA = origin + Vector3.new(0, 3, -ARENA_SIZE * 0.35)
	local spawnB = origin + Vector3.new(0, 3, ARENA_SIZE * 0.35)
	return model, { CFrame.lookAt(spawnA, center), CFrame.lookAt(spawnB, center) }
end

-- ── Ciclo del duelo ──

local function endDuel(duel: Duel, winner: Player?, reason: EndReason)
	if duel.phase == "Ended" then
		return
	end
	duel.phase = "Ended"

	for _, connection in duel.connections do
		connection:Disconnect()
	end

	for _, player in duel.players do
		duelsByPlayer[player] = nil
		if player.Parent == Players then
			player:SetAttribute("InDuel", false)
		end
		sendState(player, {
			State = "End",
			Opponent = otherPlayer(duel, player),
			Winner = winner,
			Reason = reason,
		})
	end

	task.delay(END_RETURN_DELAY, function()
		-- Devuelve a los sobrevivientes (ganador, o ambos si fue empate) a donde estaban.
		for _, player in duel.players do
			local humanoid = getAliveParts(player)
			local character = player.Character
			if humanoid and character and not duelsByPlayer[player] then
				humanoid.Health = humanoid.MaxHealth
				character:PivotTo(duel.returnCFrames[player])
			end
			if character and not duelsByPlayer[player] then
				setRegenEnabled(character, true)
			end
		end
		duel.arena:Destroy()
		usedSlots[duel.slot] = nil
	end)
end

local function startDuel(a: Player, b: Player)
	local _, rootA = getAliveParts(a)
	local _, rootB = getAliveParts(b)
	if not rootA or not rootB then
		return
	end

	local slot = allocateSlot()
	local arena, spawns = buildArena(slot)

	local duel: Duel = {
		players = { a, b },
		phase = "Countdown",
		slot = slot,
		arena = arena,
		returnCFrames = { [a] = rootA.CFrame, [b] = rootB.CFrame },
		connections = {},
	}

	for index, player in duel.players do
		duelsByPlayer[player] = duel
		invites[player] = nil
		player:SetAttribute("InDuel", true)

		local humanoid = getAliveParts(player)
		local character = player.Character
		if humanoid and character then
			setRegenEnabled(character, false)
			humanoid.Health = humanoid.MaxHealth
			character:PivotTo(spawns[index])

			local opponent = otherPlayer(duel, player)
			table.insert(duel.connections, humanoid.Died:Connect(function()
				endDuel(duel, opponent, "Defeat")
			end))
			table.insert(duel.connections, player.CharacterRemoving:Connect(function()
				endDuel(duel, opponent, "Forfeit")
			end))
		end

		sendState(player, {
			State = "Countdown",
			Opponent = otherPlayer(duel, player),
			Seconds = COUNTDOWN_SECONDS,
		})
	end

	task.delay(COUNTDOWN_SECONDS, function()
		if duel.phase ~= "Countdown" then
			return
		end
		duel.phase = "Fighting"
		local endsAt = workspace:GetServerTimeNow() + DUEL_TIMEOUT
		for _, player in duel.players do
			sendState(player, { State = "Fight", Opponent = otherPlayer(duel, player), EndsAt = endsAt })
		end
	end)

	task.delay(COUNTDOWN_SECONDS + DUEL_TIMEOUT, function()
		endDuel(duel, nil, "Timeout")
	end)
end

-- ── Remotes ──

local function onDuelRequest(challenger: Player, target: unknown)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == challenger then
		return
	end

	local now = os.clock()
	local last = lastRequestAt[challenger]
	if last and now - last < REQUEST_COOLDOWN then
		return
	end
	lastRequestAt[challenger] = now

	if not isAvailable(challenger) or not isAvailable(target) then
		sendState(challenger, { State = "Unavailable", Opponent = target })
		return
	end

	-- Desafío cruzado (p. ej. los dos pidieron revancha): empieza sin esperar respuesta.
	local reverse = invites[challenger]
	if reverse and reverse.from == target and reverse.expiresAt > now then
		invites[challenger] = nil
		startDuel(target, challenger)
		return
	end

	local pending = invites[target]
	if pending and pending.expiresAt > now then
		return -- ya tiene un desafío pendiente
	end

	invites[target] = { from = challenger, expiresAt = now + INVITE_TTL }
	Remotes.GetEvent("DuelInvite"):FireClient(target, challenger)
	sendState(challenger, { State = "InviteSent", Opponent = target })
end

local function onDuelResponse(target: Player, challenger: unknown, accepted: unknown)
	if typeof(challenger) ~= "Instance" or not challenger:IsA("Player") then
		return
	end

	local invite = invites[target]
	if not invite or invite.from ~= challenger then
		return
	end
	invites[target] = nil

	if os.clock() > invite.expiresAt then
		return
	end

	if accepted ~= true then
		sendState(challenger, { State = "Declined", Opponent = target })
		return
	end

	if isAvailable(challenger) and isAvailable(target) then
		startDuel(challenger, target)
	end
end

-- ── Ciclo de vida ──

function ArenaService:Init()
	Remotes.GetEvent("DuelRequest").OnServerEvent:Connect(onDuelRequest)
	Remotes.GetEvent("DuelResponse").OnServerEvent:Connect(onDuelResponse)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("InDuel", false)
	end)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("InDuel") == nil then
			player:SetAttribute("InDuel", false)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
		invites[player] = nil
		for target, invite in invites do
			if invite.from == player then
				invites[target] = nil
			end
		end

		local duel = duelsByPlayer[player]
		if duel then
			endDuel(duel, otherPlayer(duel, player), "Forfeit")
		end
	end)
end

return ArenaService
