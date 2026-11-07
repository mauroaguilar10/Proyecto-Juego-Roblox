--!strict
--[[
	CombatService — Combate cuerpo a cuerpo, autoritativo en servidor.
	Owner: Dev A (Combat).

	Remote "CombatAttack" (C→S), el primer argumento es la acción:
	  ()  o  ("Attack", aim?) → atacar (combo de 3 golpes; el 3.º pega más fuerte y empuja más).
	                            aim: Vector3 opcional, dirección hacia donde apunta (cursor/toque/cámara);
	                            si falta o es inválida se usa hacia donde mira el personaje.
	  ("Block", true/false)   → empezar / soltar el bloqueo
	  ("Dash")                → esquive: gasta aguante y da invulnerabilidad breve.
	                            El movimiento lo hace el cliente (es dueño de la física de su personaje).
	El servidor no confía en datos del cliente: valida estado, arma en la mano, cooldowns y aguante.

	Bloqueo (solo golpes de frente):
	  - En los primeros PARRY_WINDOW s es un parry: 0 daño y el atacante queda aturdido.
	  - Después reduce el daño y gasta aguante. Sin aguante suficiente → guardia rota (daño completo + aturdido).

	Remote "CombatFeedback" (S→C) al atacante y a la víctima (si es jugador): ver HitFeedback.

	Attributes que ESCRIBE (ver ARCHITECTURE.md §3):
	  Humanoid.CombatState  : "Idle" | "Attacking" | "Stunned" | "Dead"
	  Humanoid.LastAttacker : UserId (solo en Humanoids de enemigos, antes de aplicar el daño)
	  Humanoid.Stamina      : 0..MAX_STAMINA (solo jugadores)
	  Humanoid.Blocking     : boolean (solo jugadores)
	  Humanoid.ComboStep    : 1..COMBO_LENGTH, golpe del combo en curso (solo jugadores)

	Attributes que LEE:
	  Player.EquippedWeapon (Economy), Player.InDuel (ArenaService)

	Requiere que la Tool del arma esté en la mano (WeaponVisualService.IsWeaponHeld).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local WeaponVisualService = require(script.Parent:WaitForChild("WeaponVisualService"))

type CombatState = "Idle" | "Attacking" | "Stunned" | "Dead"
type HitKind = "Hit" | "Blocked" | "Parry" | "GuardBreak"

type HitTarget = {
	humanoid: Humanoid,
	distance: number,
}

type Fighter = {
	humanoid: Humanoid?,
	lastAttackAt: number?,
	combo: number,
	lastSpendAt: number,
	blockStartedAt: number?,
	savedWalkSpeed: number?,
	lastDashAt: number?,
}

export type HitFeedback = {
	Kind: HitKind,
	Attacker: Player,
	Target: Model,
	Damage: number, -- daño real aplicado (0 en Parry)
	Killed: boolean,
	WeaponId: string,
	Combo: number, -- 1..COMBO_LENGTH
	Knockback: Vector3?, -- solo en el payload a la víctima: velocidad horizontal + vertical a aplicar
}

-- ── Tuning ──
local ATTACK_STATE_DURATION = 0.25 -- s que el atacante queda en "Attacking"
local HIT_STUN_DURATION = 0.3 -- s que la víctima queda en "Stunned"
local HIT_ARC_DOT = math.cos(math.rad(70)) -- arco frontal de 140°
local RANGE_TOLERANCE = 1.5 -- studs extra para compensar latencia
local COOLDOWN_TOLERANCE = 0.8 -- acepta acciones un 20% antes (jitter de red)
local MAX_TARGETS = 5
local POINT_BLANK = 3 -- studs: a esta distancia no se exige el arco frontal

-- Combo (mantener COMBO_LENGTH y COMBO_WINDOW iguales en CombatController)
local COMBO_LENGTH = 3
local COMBO_WINDOW = 0.6 -- s extra tras el cooldown para encadenar el siguiente golpe
local FINISHER_DAMAGE_MULT = 1.5

-- Empuje
local KNOCKBACK_SPEED = 16
local FINISHER_KNOCKBACK_SPEED = 38
local KNOCKBACK_LIFT = 10
local KNOCKBACK_DURATION = 0.15

-- Aguante, bloqueo y esquive
local MAX_STAMINA = 100
local STAMINA_REGEN = 25 -- por segundo
local STAMINA_REGEN_DELAY = 0.8 -- s sin gastar antes de regenerar
local STAMINA_TICK = 0.1
local BLOCK_ARC_DOT = 0 -- bloquea golpes que vienen de la mitad frontal
local BLOCK_DAMAGE_MULT = 0.2
local BLOCK_STAMINA_PER_DAMAGE = 1.5
local BLOCK_WALK_MULT = 0.5
local PARRY_WINDOW = 0.2
local PARRY_STUN_DURATION = 0.7
local GUARD_BREAK_STUN_DURATION = 0.9
local DASH_COST = 25
local DASH_COOLDOWN = 1
local DASH_IFRAMES = 0.35 -- incluye margen de latencia

-- ── Estado interno ──
local fighters: { [Player]: Fighter } = {}
local stateTokens: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
local trackedHumanoids: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local dodgeUntil: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any

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

-- ── Fighters (estado por jugador) ──

local function getFighter(player: Player): Fighter
	local fighter = fighters[player]
	if not fighter then
		fighter = { combo = 0, lastSpendAt = 0 }
		fighters[player] = fighter
	end
	return fighter
end

local function getStamina(humanoid: Humanoid): number
	local value = humanoid:GetAttribute("Stamina")
	return if typeof(value) == "number" then value else MAX_STAMINA
end

local function spendStamina(fighter: Fighter, humanoid: Humanoid, amount: number)
	humanoid:SetAttribute("Stamina", math.max(0, getStamina(humanoid) - amount))
	fighter.lastSpendAt = os.clock()
end

local function stopBlocking(fighter: Fighter)
	if not fighter.blockStartedAt then
		return
	end
	fighter.blockStartedAt = nil
	local humanoid = fighter.humanoid
	if humanoid and humanoid.Parent then
		humanoid:SetAttribute("Blocking", false)
		if fighter.savedWalkSpeed then
			humanoid.WalkSpeed = fighter.savedWalkSpeed
		end
	end
	fighter.savedWalkSpeed = nil
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

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
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
-- la rotación de su propio personaje; alcance y cooldown se siguen validando aquí.
local function attackDirection(root: BasePart, aim: unknown): Vector3
	if typeof(aim) == "Vector3" then
		local direction = flat(aim)
		local magnitude = direction.Magnitude
		if magnitude == magnitude and magnitude > 0.1 and magnitude < math.huge then
			return direction.Unit
		end
	end
	return flat(root.CFrame.LookVector).Unit
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

		local flatOffset = flat(offset)
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

-- Empuja un enemigo (NPC) desde el servidor. A los jugadores los empuja su propio cliente.
local function pushNpc(root: BasePart, velocity: Vector3)
	if root.Anchored then
		return
	end
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	mover.MaxForce = math.huge
	mover.Parent = root

	root.AssemblyLinearVelocity += Vector3.new(0, velocity.Y, 0)
	task.delay(KNOCKBACK_DURATION, function()
		mover:Destroy()
		attachment:Destroy()
	end)
end

-- ── Golpe ──

type Strike = {
	player: Player,
	humanoid: Humanoid,
	root: BasePart,
	weapon: WeaponData.WeaponStats,
	damage: number,
	combo: number,
}

-- Decide si el objetivo bloquea / hace parry. Devuelve el tipo de golpe y el daño a aplicar.
local function resolveDefense(strike: Strike, targetPlayer: Player?, targetHumanoid: Humanoid, targetRoot: BasePart): (HitKind, number)
	local fighter = if targetPlayer then fighters[targetPlayer] else nil
	local blockStartedAt = if fighter then fighter.blockStartedAt else nil
	if not fighter or not blockStartedAt then
		return "Hit", strike.damage
	end

	local toAttacker = flat(strike.root.Position - targetRoot.Position)
	local facing = flat(targetRoot.CFrame.LookVector)
	if toAttacker.Magnitude > 0.1 and facing.Magnitude > 0.1 and facing.Unit:Dot(toAttacker.Unit) < BLOCK_ARC_DOT then
		return "Hit", strike.damage -- golpe por la espalda
	end

	if os.clock() - blockStartedAt <= PARRY_WINDOW then
		return "Parry", 0
	end

	local cost = strike.damage * BLOCK_STAMINA_PER_DAMAGE
	if getStamina(targetHumanoid) >= cost then
		spendStamina(fighter, targetHumanoid, cost)
		return "Blocked", strike.damage * BLOCK_DAMAGE_MULT
	end

	spendStamina(fighter, targetHumanoid, MAX_STAMINA)
	stopBlocking(fighter)
	return "GuardBreak", strike.damage
end

local function applyHit(strike: Strike, targetHumanoid: Humanoid, targetModel: Model, feedbackEvent: RemoteEvent)
	local targetRoot = targetHumanoid.RootPart
	if not targetRoot then
		return
	end
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	local kind, damage = resolveDefense(strike, targetPlayer, targetHumanoid, targetRoot)

	local feedback: HitFeedback = {
		Kind = kind,
		Attacker = strike.player,
		Target = targetModel,
		Damage = 0,
		Killed = false,
		WeaponId = strike.weapon.Id,
		Combo = strike.combo,
	}

	if kind == "Parry" then
		setTemporaryState(strike.humanoid, "Stunned", PARRY_STUN_DURATION)
		local attackerFighter = fighters[strike.player]
		if attackerFighter then
			attackerFighter.combo = 0
		end
		feedbackEvent:FireClient(strike.player, feedback)
		if targetPlayer then
			feedbackEvent:FireClient(targetPlayer, feedback)
		end
		return
	end

	if not targetPlayer then
		-- Contrato: LastAttacker se escribe ANTES del daño para que DungeonService lo lea en Died.
		targetHumanoid:SetAttribute("LastAttacker", strike.player.UserId)
	end

	local healthBefore = targetHumanoid.Health
	-- Armadura (Humanoid.Armor, la escribe ArmorService de Economía): reduce el daño recibido.
	local armor = targetHumanoid:GetAttribute("Armor")
	if typeof(armor) == "number" then damage *= 1 - math.clamp(armor, 0, 0.9) end
	targetHumanoid:TakeDamage(damage)
	local dealt = healthBefore - targetHumanoid.Health
	if dealt <= 0 then
		return -- ForceField u otro bloqueo: sin stun ni feedback
	end

	local killed = targetHumanoid.Health <= 0
	feedback.Damage = dealt
	feedback.Killed = killed

	if not killed then
		if kind == "GuardBreak" then
			setTemporaryState(targetHumanoid, "Stunned", GUARD_BREAK_STUN_DURATION)
		elseif kind == "Hit" then
			setTemporaryState(targetHumanoid, "Stunned", HIT_STUN_DURATION)
		end
		local targetFighter = if targetPlayer then fighters[targetPlayer] else nil
		if targetFighter and kind ~= "Blocked" then
			targetFighter.combo = 0 -- un golpe recibido corta tu combo
		end
	end

	local knockback: Vector3? = nil
	if kind ~= "Blocked" then
		local direction = flat(targetRoot.Position - strike.root.Position)
		if direction.Magnitude < 0.1 then
			direction = flat(strike.root.CFrame.LookVector)
		end
		local speed = if strike.combo == COMBO_LENGTH or kind == "GuardBreak" then FINISHER_KNOCKBACK_SPEED else KNOCKBACK_SPEED
		knockback = direction.Unit * speed + Vector3.new(0, KNOCKBACK_LIFT, 0)
	end

	feedbackEvent:FireClient(strike.player, feedback)
	if targetPlayer then
		local victimFeedback = table.clone(feedback)
		victimFeedback.Knockback = knockback
		feedbackEvent:FireClient(targetPlayer, victimFeedback)
	elseif knockback and not killed then
		pushNpc(targetRoot, knockback)
	end
end

-- ── Acciones ──

local function onAttack(player: Player, aim: unknown)
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

	local fighter = getFighter(player)
	if fighter.blockStartedAt then
		return
	end

	local weapon = getEquippedWeapon(player)
	local now = os.clock()
	local last = fighter.lastAttackAt
	if last and now - last < weapon.AttackCooldown * COOLDOWN_TOLERANCE then
		return
	end

	if last and now - last <= weapon.AttackCooldown + COMBO_WINDOW then
		fighter.combo = fighter.combo % COMBO_LENGTH + 1
	else
		fighter.combo = 1
	end
	fighter.lastAttackAt = now

	local strike: Strike = {
		player = player,
		humanoid = humanoid,
		root = root,
		weapon = weapon,
		damage = if fighter.combo == COMBO_LENGTH then weapon.Damage * FINISHER_DAMAGE_MULT else weapon.Damage,
		combo = fighter.combo,
	}

	humanoid:SetAttribute("ComboStep", strike.combo)
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
		if (dodgeUntil[targetHumanoid] or 0) > now then
			continue -- esquivó
		end

		hits += 1
		trackHumanoid(targetHumanoid)
		applyHit(strike, targetHumanoid, targetModel, feedbackEvent)
		if getState(humanoid) == "Stunned" then
			break -- le hicieron parry: el golpe se corta
		end
	end
end

local function onBlock(player: Player, wantsBlock: boolean)
	local fighter = getFighter(player)
	if not wantsBlock then
		stopBlocking(fighter)
		return
	end

	local _, humanoid = getAliveCharacter(player)
	if not humanoid or fighter.blockStartedAt or not WeaponVisualService.IsWeaponHeld(player) then
		return
	end
	local state = getState(humanoid)
	if state == "Stunned" or state == "Dead" or getStamina(humanoid) <= 0 then
		return
	end

	fighter.humanoid = humanoid
	fighter.blockStartedAt = os.clock()
	fighter.savedWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed *= BLOCK_WALK_MULT
	humanoid:SetAttribute("Blocking", true)
end

local function onDash(player: Player)
	local _, humanoid = getAliveCharacter(player)
	if not humanoid then
		return
	end
	local state = getState(humanoid)
	if state == "Stunned" or state == "Dead" then
		return
	end

	local fighter = getFighter(player)
	local now = os.clock()
	if fighter.blockStartedAt or getStamina(humanoid) < DASH_COST then
		return
	end
	if fighter.lastDashAt and now - fighter.lastDashAt < DASH_COOLDOWN * COOLDOWN_TOLERANCE then
		return
	end

	fighter.lastDashAt = now
	spendStamina(fighter, humanoid, DASH_COST)
	dodgeUntil[humanoid] = now + DASH_IFRAMES
end

local function onCombatAction(player: Player, action: unknown, value: unknown)
	if action == nil or action == "Attack" then
		onAttack(player, value)
	elseif action == "Block" then
		onBlock(player, value == true)
	elseif action == "Dash" then
		onDash(player)
	end
end

-- ── Aguante ──

local function tickStamina(dt: number)
	local now = os.clock()
	for player, fighter in fighters do
		local humanoid = fighter.humanoid
		if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
			continue
		end

		if fighter.blockStartedAt and (not WeaponVisualService.IsWeaponHeld(player) or getState(humanoid) == "Stunned") then
			stopBlocking(fighter)
		end

		if not fighter.blockStartedAt and now - fighter.lastSpendAt >= STAMINA_REGEN_DELAY then
			local stamina = getStamina(humanoid)
			if stamina < MAX_STAMINA then
				humanoid:SetAttribute("Stamina", math.min(MAX_STAMINA, stamina + STAMINA_REGEN * dt))
			end
		end
	end
end

-- ── Ciclo de vida ──

local function onPlayerAdded(player: Player)
	local function onCharacterAdded(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
			return
		end
		trackHumanoid(humanoid)

		local fighter = getFighter(player)
		fighter.humanoid = humanoid
		fighter.blockStartedAt = nil
		fighter.savedWalkSpeed = nil
		fighter.combo = 0
		humanoid:SetAttribute("Stamina", MAX_STAMINA)
		humanoid:SetAttribute("Blocking", false)
		humanoid:SetAttribute("ComboStep", 0)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

function CombatService:Init()
	Remotes.GetEvent("CombatAttack").OnServerEvent:Connect(onCombatAction)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		fighters[player] = nil
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= STAMINA_TICK then
			tickStamina(elapsed)
			elapsed = 0
		end
	end)
end

return CombatService
