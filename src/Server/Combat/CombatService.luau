--!strict
--[[
	CombatService — Combate cuerpo a cuerpo, autoritativo en servidor.
	Owner: Dev A (Combat).

	Flujo:
	  Cliente → Remotes "CombatAttack"(aim: Vector3) — solo la dirección hacia donde apunta;
	  daño, alcance y cooldown los decide el servidor (aim inválido → se usa hacia donde mira el personaje)
	  Servidor valida (vivo, estado, cooldown del arma) → busca objetivos en un arco frontal
	  → aplica daño → Remotes "CombatFeedback" al atacante y a la víctima (si es jugador).

	Attributes que ESCRIBE (ver ARCHITECTURE.md §3):
	  Humanoid.CombatState  : "Idle" | "Attacking" | "Stunned" | "Dead"
	  Humanoid.LastAttacker : UserId (solo en Humanoids de enemigos, antes de aplicar el daño)

	Attributes que LEE:
	  Player.EquippedWeapon (Economy), Player.InDuel (ArenaService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local WeaponVisualService = require(script.Parent:WaitForChild("WeaponVisualService"))

type CombatState = "Idle" | "Attacking" | "Stunned" | "Dead"

type HitTarget = {
	humanoid: Humanoid,
	distance: number,
}

export type HitFeedback = {
	Attacker: Player,
	Target: Model,
	Damage: number,
	Killed: boolean,
	WeaponId: string,
}

-- ── Tuning ──
local ATTACK_STATE_DURATION = 0.25 -- s que el atacante queda en "Attacking"
local HIT_STUN_DURATION = 0.3 -- s que la víctima queda en "Stunned"
local HIT_ARC_DOT = math.cos(math.rad(70)) -- arco frontal de 140°
local RANGE_TOLERANCE = 1.5 -- studs extra para compensar latencia
local COOLDOWN_TOLERANCE = 0.8 -- acepta ataques un 20% antes (jitter de red)
local MAX_TARGETS = 5
local POINT_BLANK = 3 -- studs: a esta distancia no se exige el arco frontal

-- ── Estado interno ──
local lastAttackAt: { [Player]: number } = {}
local stateTokens: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
local trackedHumanoids: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local CombatService = {}

-- ── CombatState ──

local function getState(humanoid: Humanoid): CombatState
	local value = humanoid:GetAttribute("CombatState")
	if value == "Attacking" then
		return "Attacking"
	elseif value == "Stunned" then
		return "Stunned"
	elseif value == "Dead" then
		return "Dead"
	end
	return "Idle"
end

local function setState(humanoid: Humanoid, state: CombatState)
	humanoid:SetAttribute("CombatState", state)
end

-- Pone un estado temporal y vuelve a "Idle" al terminar, salvo que otro estado lo haya pisado.
local function setTemporaryState(humanoid: Humanoid, state: CombatState, duration: number)
	if getState(humanoid) == "Dead" then
		return
	end

	local token = (stateTokens[humanoid] or 0) + 1
	stateTokens[humanoid] = token
	setState(humanoid, state)

	task.delay(duration, function()
		if stateTokens[humanoid] == token and humanoid.Parent and getState(humanoid) == state then
			setState(humanoid, "Idle")
		end
	end)
end

local function trackHumanoid(humanoid: Humanoid)
	if trackedHumanoids[humanoid] then
		return
	end
	trackedHumanoids[humanoid] = true

	if humanoid:GetAttribute("CombatState") == nil then
		setState(humanoid, if humanoid.Health > 0 then "Idle" else "Dead")
	end

	humanoid.Died:Once(function()
		stateTokens[humanoid] = nil
		setState(humanoid, "Dead")
	end)
end

-- ── Helpers ──

local function getAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end

	return character, humanoid, root
end

local function getEquippedWeapon(player: Player): WeaponData.WeaponStats
	local equipped = player:GetAttribute("EquippedWeapon")
	return WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil)
end

-- PvP solo entre oponentes del mismo duelo. Enemigos (Humanoids sin jugador) solo fuera de duelo.
local function canDamage(attacker: Player, targetModel: Model): boolean
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	if targetPlayer then
		return ArenaService.AreOpponents(attacker, targetPlayer)
	end
	return attacker:GetAttribute("InDuel") ~= true
end

-- Dirección de ataque: la que manda el cliente (hacia donde apunta) o, si no es válida,
-- hacia donde mira el personaje. Confiar en ella no da ventaja: el cliente ya controla
-- la rotación de su propio personaje; el alcance y el cooldown se siguen validando aquí.
local function attackDirection(root: BasePart, aim: any): Vector3
	if typeof(aim) == "Vector3" then
		local flat = Vector3.new(aim.X, 0, aim.Z)
		local magnitude = flat.Magnitude
		if magnitude == magnitude and magnitude > 0.1 and magnitude < math.huge then
			return flat.Unit
		end
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function findTargets(attackerCharacter: Model, root: BasePart, range: number, flatLook: Vector3): { HitTarget }
	local maxDistance = range + RANGE_TOLERANCE

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }

	-- Por cada Humanoid, la parte más cercana: los enemigos grandes se golpean por el borde,
	-- no solo por el centro del HumanoidRootPart.
	local closest: { [Humanoid]: Vector3 } = {}
	for _, part in workspace:GetPartBoundsInRadius(root.Position, maxDistance, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
		if not humanoid or humanoid.Health <= 0 or not humanoid.RootPart then
			continue
		end
		local offset = part.Position - root.Position
		local best = closest[humanoid]
		if not best or offset.Magnitude < best.Magnitude then
			closest[humanoid] = offset
		end
	end

	local results: { HitTarget } = {}
	for humanoid, offset in closest do
		local distance = offset.Magnitude
		if distance > maxDistance then
			continue
		end

		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		if flatOffset.Magnitude > POINT_BLANK and flatLook:Dot(flatOffset.Unit) < HIT_ARC_DOT then
			continue
		end

		table.insert(results, { humanoid = humanoid, distance = distance })
	end

	table.sort(results, function(a, b)
		return a.distance < b.distance
	end)

	return results
end

-- ── Ataque ──

local function onAttackRequested(player: Player, aim: any)
	local character, humanoid, root = getAliveCharacter(player)
	if not character or not humanoid or not root then
		return
	end

	-- Solo se ataca con el arma en la mano (Tool de inventario, ver WeaponVisualService).
	if not WeaponVisualService.IsWeaponHeld(player) then
		return
	end

	trackHumanoid(humanoid)
	local state = getState(humanoid)
	if state == "Stunned" or state == "Dead" then
		return
	end

	local weapon = getEquippedWeapon(player)
	local now = os.clock()
	local last = lastAttackAt[player]
	if last and now - last < weapon.AttackCooldown * COOLDOWN_TOLERANCE then
		return
	end
	lastAttackAt[player] = now

	setTemporaryState(humanoid, "Attacking", math.min(ATTACK_STATE_DURATION, weapon.AttackCooldown))

	local feedbackEvent = Remotes.GetEvent("CombatFeedback")
	local hits = 0

	for _, target in findTargets(character, root, weapon.Range, attackDirection(root, aim)) do
		if hits >= MAX_TARGETS then
			break
		end

		local targetHumanoid = target.humanoid
		local targetModel = targetHumanoid.Parent
		if not targetModel or not targetModel:IsA("Model") or not canDamage(player, targetModel) then
			continue
		end

		hits += 1
		trackHumanoid(targetHumanoid)

		local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
		if not targetPlayer then
			-- Contrato: LastAttacker se escribe ANTES del daño para que DungeonService lo lea en Died.
			targetHumanoid:SetAttribute("LastAttacker", player.UserId)
		end

		local healthBefore = targetHumanoid.Health
		targetHumanoid:TakeDamage(weapon.Damage)
		local dealt = healthBefore - targetHumanoid.Health
		local killed = targetHumanoid.Health <= 0

		if dealt <= 0 then
			continue -- ForceField u otro bloqueo: sin stun ni feedback
		end

		if not killed then
			setTemporaryState(targetHumanoid, "Stunned", HIT_STUN_DURATION)
		end

		local feedback: HitFeedback = {
			Attacker = player,
			Target = targetModel,
			Damage = dealt,
			Killed = killed,
			WeaponId = weapon.Id,
		}
		feedbackEvent:FireClient(player, feedback)
		if targetPlayer then
			feedbackEvent:FireClient(targetPlayer, feedback)
		end
	end
end

-- ── Ciclo de vida ──

local function onPlayerAdded(player: Player)
	local function onCharacterAdded(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			trackHumanoid(humanoid)
		end
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

function CombatService:Init()
	Remotes.GetEvent("CombatAttack").OnServerEvent:Connect(onAttackRequested)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastAttackAt[player] = nil
	end)
end

return CombatService
