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

	Modos y apuestas (DuelRules): "DuelRequest"(B, { Mode = "Informal" | "Duel", Bet }) y
	"DuelInvite"(A, DuelInviteInfo). Solo se desafía parado en la arena del lobby (salvo la revancha
	al último rival). Con apuesta, DuelWagerService (Economía) cobra a los dos al empezar, paga
	DuelRules.Prize(bet) al ganador (pozo − 10 %) y devuelve la apuesta si hay empate.

	Attributes que ESCRIBE: Player.InDuel (boolean). Es true desde la cuenta regresiva hasta el fin.
	Payload de "DuelStateChanged": ver DuelStatePayload (documentado en ARCHITECTURE.md).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DuelRules = require(Shared:WaitForChild("DuelRules"))
local DuelWagerService = require(script.Parent.Parent:WaitForChild("Economy"):WaitForChild("DuelWagerService"))

type DuelPhase = "Countdown" | "Fighting" | "Ended"
type EndReason = "Defeat" | "Forfeit" | "Timeout"
type Mode = DuelRules.Mode

type Duel = {
	players: { Player },
	phase: DuelPhase,
	slot: number,
	arena: Model,
	returnCFrames: { [Player]: CFrame },
	connections: { RBXScriptConnection },
	mode: Mode,
	bet: number, -- 0 en "Informal"
}

type Invite = {
	from: Player,
	expiresAt: number,
	mode: Mode,
	bet: number,
}

-- Segundo argumento de "DuelInvite".
export type DuelInviteInfo = { Mode: Mode, Bet: number, Prize: number, Seconds: number }

export type DuelStatePayload = {
	State: "InviteSent" | "Declined" | "Unavailable" | "Countdown" | "Fight" | "End",
	Opponent: Player?,
	Seconds: number?, -- en "Countdown" (cuenta regresiva) y en "InviteSent" (tiempo para aceptar)
	EndsAt: number?, -- solo en "Fight": workspace:GetServerTimeNow() en que termina por tiempo
	Winner: Player?, -- solo en "End" (nil = empate)
	Reason: EndReason?, -- solo en "End"
	Mode: Mode?, -- modo del desafío / duelo
	Bet: number?, -- apuesta por jugador (0 = informal)
	Prize: number?, -- en "End": oro que cobró el ganador (0 si no hubo apuesta o fue empate)
	Message: string?, -- en "Unavailable": motivo para mostrar
}

-- ── Tuning ──
local INVITE_TTL = DuelRules.INVITE_TTL
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
local lastOpponent: { [Player]: Player } = {} -- para permitir la revancha fuera de la arena
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

	-- Apuesta: premio al ganador, o devolución si fue empate.
	local prize = 0
	if duel.bet > 0 then
		if winner then
			prize = DuelWagerService.Payout(winner, duel.bet)
		else
			DuelWagerService.Refund(duel.players, duel.bet)
		end
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
			Mode = duel.mode,
			Bet = duel.bet,
			Prize = prize,
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

local function startDuel(a: Player, b: Player, mode: Mode, bet: number)
	local _, rootA = getAliveParts(a)
	local _, rootB = getAliveParts(b)
	if not rootA or not rootB then
		return
	end

	-- Modo "Duel": se cobra la apuesta a los dos antes de empezar (todo o nada).
	if bet > 0 and not DuelWagerService.Escrow(a, b, bet) then
		for _, player in { a, b } do
			sendState(player, {
				State = "Unavailable",
				Opponent = if player == a then b else a,
				Message = `Alguno de los dos no tiene {bet} de oro para apostar`,
			})
		end
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
		mode = mode,
		bet = bet,
	}
	lastOpponent[a], lastOpponent[b] = b, a

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
			Mode = mode,
			Bet = bet,
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

local function onDuelRequest(challenger: Player, target: unknown, options: unknown)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == challenger then
		return
	end

	local now = os.clock()
	local last = lastRequestAt[challenger]
	if last and now - last < REQUEST_COOLDOWN then
		return
	end
	lastRequestAt[challenger] = now

	local function refuse(message: string)
		sendState(challenger, { State = "Unavailable", Opponent = target, Message = message })
	end

	-- Modo y apuesta. Sin opciones (clientes viejos) = informal.
	local opts = if typeof(options) == "table" then options :: { [string]: unknown } else {}
	local mode: Mode = if DuelRules.IsMode(opts.Mode) then (opts.Mode :: any) :: Mode else "Informal"
	local bet = 0
	if mode == "Duel" then
		local valid = DuelRules.ValidBet(opts.Bet)
		if not valid then
			refuse(`La apuesta debe ser entre {DuelRules.MIN_BET} y {DuelRules.MAX_BET} de oro`)
			return
		end
		bet = valid
	end

	-- Solo se desafía parado en la arena del lobby (la revancha al último rival, desde donde sea).
	local _, root = getAliveParts(challenger)
	if lastOpponent[challenger] ~= target and not (root and DuelRules.InZone(root.Position, 4)) then
		refuse("Tenés que estar en la arena de duelos para desafiar")
		return
	end

	if not isAvailable(challenger) or not isAvailable(target) then
		refuse(`{target.DisplayName} no está disponible ahora (o vos no lo estás)`)
		return
	end
	if bet > 0 and not DuelWagerService.CanAfford(challenger, bet) then
		refuse(`No tenés {bet} de oro para apostar`)
		return
	end

	-- Desafío cruzado (p. ej. los dos pidieron revancha): empieza sin esperar respuesta.
	local reverse = invites[challenger]
	if reverse and reverse.from == target and reverse.expiresAt > now and reverse.mode == mode and reverse.bet == bet then
		invites[challenger] = nil
		startDuel(target, challenger, mode, bet)
		return
	end

	local pending = invites[target]
	if pending and pending.expiresAt > now and pending.from ~= challenger then
		refuse(`{target.DisplayName} ya tiene un desafío pendiente`)
		return
	end

	invites[target] = { from = challenger, expiresAt = now + INVITE_TTL, mode = mode, bet = bet }
	local info: DuelInviteInfo = { Mode = mode, Bet = bet, Prize = if bet > 0 then DuelRules.Prize(bet) else 0, Seconds = INVITE_TTL }
	Remotes.GetEvent("DuelInvite"):FireClient(target, challenger, info)
	sendState(challenger, { State = "InviteSent", Opponent = target, Seconds = INVITE_TTL, Mode = mode, Bet = bet })
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
		sendState(challenger, { State = "Declined", Opponent = target, Mode = invite.mode, Bet = invite.bet })
		return
	end

	if isAvailable(challenger) and isAvailable(target) then
		startDuel(challenger, target, invite.mode, invite.bet)
	else
		for _, player in { challenger, target } do
			sendState(player, {
				State = "Unavailable",
				Opponent = if player == target then challenger else target,
				Message = "El duelo no pudo empezar (alguno está ocupado)",
			})
		end
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
		lastOpponent[player] = nil
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
