--!strict
--[[
	CombatService — Núcleo del combate cuerpo a cuerpo. Autoritativo en servidor.
	Owner: Dev A (Combat).

	════ Máquina de estados (Humanoid.CombatState, jugadores) ════

	  Idle ──clic──► Windup ──WindupTime──► Attacking ──0,1 s──► Recovery ──► Idle
	   │  ▲            │ (golpeado: Stunned, salvo hyperarmor)        (corta si conectó)
	   │  └────────────┴──────────────────────────────────────────────────────┘
	   ├──F──► Parrying ──0,22 s──► Blocking (mientras se mantenga F)
	   ├──Q──► Dashing (0,25 s; i-frames los primeros 0,12 s)
	   └── golpe recibido ──► Stunned / PostureBroken (Posture llegó a 100)
	  "Dead" al morir. Enemigos (NPC) solo usan "Idle" | "Stunned" | "Dead".

	════ Remote "CombatAttack" (C→S), primer argumento = acción ════
	  ()  o  ("Attack", aim?) → atacar desde Idle o Blocking. aim: Vector3 opcional (cursor/toque/cámara);
	                            si falta o es inválido se usa hacia donde mira el personaje.
	  ("Block", boolean)      → mantener / soltar F. Los primeros PARRY_WINDOW s son "Parrying".
	  ("Dash")                → esquive. El movimiento lo hace el cliente (es dueño de su física);
	                            el servidor valida el cooldown, pone "Dashing" y da los i-frames.

	════ Resolución de un golpe ════
	  Defensor en i-frames      → "Dodge" (sin efecto).
	  "Parrying" y de frente    → PARRY: 0 daño. Atacante +35 de postura, ataque cancelado, Stunned 1,1 s
	                               y retroceso. Defensor −20 de postura y libre para contraatacar.
	  "Blocking" y de frente    → 0 daño, defensor + PostureDamage y empuje corto. Posture 100 → GuardBreak:
	                               "PostureBroken" 2 s (recibe ×1,5 de daño).
	  "Windup"                  → interrumpe (Stunned), salvo arma Heavy en sus últimos 0,15 s (hyperarmor).
	  Cualquier otro            → daño + Stunned + empuje.

	════ Compromiso físico al atacar ════
	  Windup/Attacking: sin salto, WalkSpeed reducida según Weight, orientación fija hacia el golpe
	  (AlignOrientation + AutoRotate = false). En el frame activo: paso hacia adelante con
	  ApplyPhysicalImpulse (LinearVelocity en el plano XZ). CombatService es dueño de WalkSpeed,
	  JumpPower/JumpHeight y AutoRotate de los personajes de jugadores (los guarda al spawnear).

	Attributes que ESCRIBE (ver ARCHITECTURE.md §3):
	  Humanoid.CombatState  : ver CombatState
	  Humanoid.Posture      : 0..100 (solo jugadores; 100 = guardia rota)
	  Humanoid.ComboStep    : 1..3, golpe del combo en curso (solo jugadores)
	  Humanoid.LastAttacker : UserId (solo enemigos, antes de aplicar el daño)
	Attributes que LEE: Player.EquippedWeapon (Economy), Player.InDuel (ArenaService)

	Remote "CombatFeedback" (S→C) a los jugadores cercanos: ver HitFeedback.
	API pública: CombatService.ApplyPhysicalImpulse(root, direction, force, duration).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local WeaponVisualService = require(script.Parent:WaitForChild("WeaponVisualService"))

export type CombatState =
	"Idle"
	| "Windup"
	| "Attacking"
	| "Recovery"
	| "Parrying"
	| "Blocking"
	| "PostureBroken"
	| "Stunned"
	| "Dashing"
	| "Dead"

export type HitKind = "Hit" | "Blocked" | "Parry" | "GuardBreak" | "Dodge"

export type HitFeedback = {
	Kind: HitKind,
	Attacker: Player,
	Target: Model,
	Damage: number, -- daño real a la vida (0 en Blocked / Parry / Dodge)
	Killed: boolean,
	WeaponId: string,
	Combo: number, -- 1..COMBO_LENGTH
	Interrupted: boolean, -- el golpe canceló el windup del objetivo
	Hyperarmor: boolean, -- el objetivo aguantó el golpe sin cancelar su ataque
	Intensity: number, -- 0..1, para hitstop y sacudida de cámara en el cliente
}

type AttackContext = {
	weapon: WeaponData.WeaponStats,
	combo: number,
	direction: Vector3, -- horizontal, unitario
	strikeAt: number, -- os.clock() en que sale el hitbox
	landed: boolean,
}

type BaseMovement = {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
}

type Fighter = {
	player: Player,
	humanoid: Humanoid?,
	root: BasePart?,
	base: BaseMovement?,
	stateToken: number,
	attack: AttackContext?,
	lastAttackAt: number?,
	comboUntil: number, -- hasta cuándo el próximo ataque continúa el combo
	combo: number,
	blockHeld: boolean,
	parryStartedAt: number?,
	parryDeflected: boolean,
	parryCooldownUntil: number,
	lastDashAt: number?,
	iframesUntil: number,
	postureCalmSince: number, -- último momento en que bloqueó o recibió un golpe
	aligner: AlignOrientation?,
}

type HitTarget = {
	humanoid: Humanoid,
	distance: number,
}

-- ══════════════════ Tuning ══════════════════

-- Hitbox
local HIT_ARC_DOT = math.cos(math.rad(70)) -- arco frontal de 140°
local RANGE_TOLERANCE = 1.5 -- studs extra para compensar latencia
local POINT_BLANK = 3 -- studs: a esta distancia no se exige el arco frontal
local MAX_TARGETS = 5
local COOLDOWN_TOLERANCE = 0.8 -- acepta acciones un 20% antes (jitter de red)
local FEEDBACK_RADIUS = 150 -- studs: jugadores que reciben el feedback visual

-- Ataque
local ACTIVE_TIME = 0.1 -- duración del frame activo (y del paso hacia adelante)
local LANDED_RECOVERY_MULT = 0.4 -- si el golpe conecta (o lo bloquean), la recuperación es más corta
local COMBO_LENGTH = 3
local COMBO_WINDOW = 0.6 -- s tras quedar libre para encadenar el siguiente golpe
local FINISHER_DAMAGE_MULT = 1.5
local FINISHER_POSTURE_MULT = 1.5
local HYPERARMOR_WINDOW = 0.15 -- últimos s del windup de un arma Heavy

-- Movilidad por estado (multiplicadores de la WalkSpeed base)
local WEIGHT_SPEED_MULT: { [WeaponData.WeaponWeight]: number } = {
	Light = 0.7,
	Medium = 0.5,
	Heavy = 0.3,
}
local RECOVERY_SPEED_MULT = 0.5
local STUN_SPEED_MULT = 0.35
local BROKEN_SPEED_MULT = 0.2
local BLOCK_WALKSPEED = 8

-- Estados de castigo
local HIT_STUN = 0.35
local INTERRUPT_STUN = 0.45

-- Parry y postura
local PARRY_WINDOW = 0.22
local PARRY_COOLDOWN = 1.2
local PARRY_STUN = 1.1
local PARRY_ATTACKER_POSTURE = 35
local PARRY_DEFENDER_RECOVER = 20
local BLOCK_ARC_DOT = 0 -- bloquea/desvía golpes de la mitad frontal
local POSTURE_MAX = 100
local POSTURE_REGEN_DELAY = 3
local POSTURE_REGEN_RATE = 20 -- por segundo
local POSTURE_BROKEN_TIME = 2
local POSTURE_BROKEN_DAMAGE_MULT = 1.5

-- Dash
local DASH_DURATION = 0.25
local DASH_IFRAMES = 0.12
local DASH_COOLDOWN = 2

-- Empujes: velocidad inicial (studs/s) y duración (s). Decaen con fricción.
local PUSH = {
	Hit = { force = 14, duration = 0.15 },
	Finisher = { force = 30, duration = 0.25 },
	Block = { force = 10, duration = 0.15 },
	Parry = { force = 22, duration = 0.2 },
	GuardBreak = { force = 28, duration = 0.3 },
}
local IMPULSE_MAX_ACCEL = 1500 -- studs/s²: fuerza máxima del LinearVelocity (× masa)

local TICK = 0.1

-- ══════════════════ Estado interno ══════════════════

local fighters: { [Player]: Fighter } = {}
local trackedHumanoids: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local npcStunTokens: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
local activeImpulses: { [BasePart]: Attachment } = setmetatable({}, { __mode = "k" }) :: any

local CombatService = {}

-- ══════════════════ Helpers ══════════════════

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getState(humanoid: Humanoid): CombatState
	local value = humanoid:GetAttribute("CombatState")
	if
		value == "Windup"
		or value == "Attacking"
		or value == "Recovery"
		or value == "Parrying"
		or value == "Blocking"
		or value == "PostureBroken"
		or value == "Stunned"
		or value == "Dashing"
		or value == "Dead"
	then
		return value :: CombatState
	end
	return "Idle"
end

local function getEquippedWeapon(player: Player): WeaponData.WeaponStats
	local equipped = player:GetAttribute("EquippedWeapon")
	return WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil)
end

local function getAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if humanoid then humanoid.RootPart else nil
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function getAliveFighter(player: Player): Fighter?
	local fighter = fighters[player]
	local _, humanoid = getAliveCharacter(player)
	if not fighter or not humanoid or fighter.humanoid ~= humanoid then
		return nil
	end
	return fighter
end

-- true si `root` mira hacia `fromPosition` (mitad frontal).
local function isFacing(root: BasePart, fromPosition: Vector3): boolean
	local toSource = flat(fromPosition - root.Position)
	local facing = flat(root.CFrame.LookVector)
	if toSource.Magnitude < 0.1 or facing.Magnitude < 0.1 then
		return true
	end
	return facing.Unit:Dot(toSource.Unit) >= BLOCK_ARC_DOT
end

-- PvP solo entre oponentes del mismo duelo. Enemigos (Humanoids sin jugador) solo fuera de duelo.
local function canDamage(attacker: Player, targetModel: Model): boolean
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	if targetPlayer then
		return ArenaService.AreOpponents(attacker, targetPlayer)
	end
	return attacker:GetAttribute("InDuel") ~= true
end

local function trackHumanoid(humanoid: Humanoid)
	if trackedHumanoids[humanoid] then
		return
	end
	trackedHumanoids[humanoid] = true
	if humanoid:GetAttribute("CombatState") == nil then
		humanoid:SetAttribute("CombatState", if humanoid.Health > 0 then "Idle" else "Dead")
	end
	humanoid.Died:Once(function()
		humanoid:SetAttribute("CombatState", "Dead")
	end)
end

-- ══════════════════ Física ══════════════════

--[[
	Empuja un HumanoidRootPart en el plano XZ manteniendo los pies en el piso (el eje Y queda
	libre para la gravedad, así no "vuela" en rampas). `force` es la velocidad inicial en studs/s;
	decae con una curva cuadrática (fricción) hasta 0 en `duration` s.
	Un nuevo impulso sobre la misma parte reemplaza al anterior.
	Funciona sobre personajes de jugadores: el constraint se replica y lo simula su dueño.
]]
function CombatService.ApplyPhysicalImpulse(targetRootPart: BasePart, directionVector: Vector3, force: number, duration: number)
	if not targetRootPart.Parent or targetRootPart.Anchored or force <= 0 or duration <= 0 then
		return
	end
	local direction = flat(directionVector)
	if direction.Magnitude < 1e-3 then
		return
	end
	direction = direction.Unit

	local previous = activeImpulses[targetRootPart]
	if previous then
		previous:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatImpulse"

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * force
	mover.MaxForce = targetRootPart.AssemblyMass * IMPULSE_MAX_ACCEL
	mover.Parent = attachment

	attachment.Parent = targetRootPart
	activeImpulses[targetRootPart] = attachment

	local elapsed = 0
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration or not attachment.Parent then
			if connection then
				connection:Disconnect()
			end
			attachment:Destroy()
			if activeImpulses[targetRootPart] == attachment then
				activeImpulses[targetRootPart] = nil
			end
			return
		end
		local falloff = (1 - elapsed / duration) ^ 2
		mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (force * falloff)
	end)
end

-- ══════════════════ Movilidad y orientación ══════════════════

local function applyMovement(fighter: Fighter, state: CombatState)
	local humanoid, base = fighter.humanoid, fighter.base
	if not humanoid or not base or not humanoid.Parent then
		return
	end

	local walk, canJump = base.walkSpeed, true
	if state == "Windup" or state == "Attacking" then
		local weapon = if fighter.attack then fighter.attack.weapon else getEquippedWeapon(fighter.player)
		walk *= WEIGHT_SPEED_MULT[weapon.Weight]
		canJump = false
	elseif state == "Recovery" then
		walk *= RECOVERY_SPEED_MULT
		canJump = false
	elseif state == "Parrying" or state == "Blocking" then
		walk = math.min(walk, BLOCK_WALKSPEED)
	elseif state == "Stunned" then
		walk *= STUN_SPEED_MULT
		canJump = false
	elseif state == "PostureBroken" then
		walk *= BROKEN_SPEED_MULT
		canJump = false
	end

	humanoid.WalkSpeed = walk
	humanoid.JumpPower = if canJump then base.jumpPower else 0
	humanoid.JumpHeight = if canJump then base.jumpHeight else 0
end

-- Con dirección: fija la orientación del personaje hacia el golpe. Sin dirección: la libera.
local function lockFacing(fighter: Fighter, direction: Vector3?)
	local humanoid, root = fighter.humanoid, fighter.root
	if not humanoid or not root or not humanoid.Parent then
		return
	end

	if not direction then
		if fighter.aligner then
			fighter.aligner.Enabled = false
		end
		humanoid.AutoRotate = true
		return
	end

	local aligner = fighter.aligner
	if not aligner or not aligner.Parent then
		local attachment = Instance.new("Attachment")
		attachment.Name = "CombatAlign"
		attachment.Parent = root

		local newAligner = Instance.new("AlignOrientation")
		newAligner.Name = "CombatFacing"
		newAligner.Mode = Enum.OrientationAlignmentMode.OneAttachment
		newAligner.Attachment0 = attachment
		newAligner.MaxTorque = math.huge
		newAligner.Responsiveness = 80
		newAligner.Parent = root
		fighter.aligner = newAligner
		aligner = newAligner
	end

	local target = aligner :: AlignOrientation
	target.CFrame = CFrame.lookAt(Vector3.zero, direction)
	target.Enabled = true
	humanoid.AutoRotate = false
end

-- ══════════════════ Máquina de estados ══════════════════

local settle: (fighter: Fighter) -> ()

--[[
	Cambia el estado del jugador y aplica movilidad/orientación. Con `duration`, al vencer llama
	a `onExpire` (o vuelve a Idle/Blocking), salvo que otro estado lo haya pisado antes.
]]
local function enterState(fighter: Fighter, state: CombatState, duration: number?, onExpire: (() -> ())?)
	local humanoid = fighter.humanoid
	if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
		return
	end

	fighter.stateToken += 1
	local token = fighter.stateToken
	humanoid:SetAttribute("CombatState", state)
	applyMovement(fighter, state)

	local attack = fighter.attack
	lockFacing(fighter, if attack and (state == "Windup" or state == "Attacking") then attack.direction else nil)

	if duration then
		task.delay(duration, function()
			if fighter.stateToken ~= token then
				return
			end
			if onExpire then
				onExpire()
			else
				settle(fighter)
			end
		end)
	end
end

-- Estado de reposo: Blocking si sigue manteniendo F con el arma en la mano, si no Idle.
settle = function(fighter: Fighter)
	if fighter.blockHeld and WeaponVisualService.IsWeaponHeld(fighter.player) then
		enterState(fighter, "Blocking")
	else
		enterState(fighter, "Idle")
	end
end

-- ══════════════════ Postura ══════════════════

local function getPosture(humanoid: Humanoid): number
	local value = humanoid:GetAttribute("Posture")
	return if typeof(value) == "number" then value else 0
end

-- Suma (o resta) postura. Devuelve true si llegó al máximo.
local function addPosture(fighter: Fighter, amount: number): boolean
	local humanoid = fighter.humanoid
	if not humanoid then
		return false
	end
	local value = math.clamp(getPosture(humanoid) + amount, 0, POSTURE_MAX)
	humanoid:SetAttribute("Posture", value)
	if amount > 0 then
		fighter.postureCalmSince = os.clock()
	end
	return value >= POSTURE_MAX
end

local function closeParryWindow(fighter: Fighter)
	if fighter.parryStartedAt and not fighter.parryDeflected then
		fighter.parryCooldownUntil = os.clock() + PARRY_COOLDOWN -- anti-spam
	end
	fighter.parryStartedAt = nil
end

local function breakPosture(fighter: Fighter)
	local humanoid = fighter.humanoid
	if not humanoid then
		return
	end
	fighter.attack = nil
	fighter.parryStartedAt = nil
	fighter.combo = 0
	humanoid:SetAttribute("Posture", POSTURE_MAX)
	enterState(fighter, "PostureBroken", POSTURE_BROKEN_TIME, function()
		if humanoid.Parent then
			humanoid:SetAttribute("Posture", 0)
		end
		settle(fighter)
	end)
end

local function stun(fighter: Fighter, duration: number)
	local humanoid = fighter.humanoid
	if not humanoid or getState(humanoid) == "PostureBroken" then
		return -- no acortar una guardia rota
	end
	fighter.attack = nil
	fighter.parryStartedAt = nil
	fighter.combo = 0
	enterState(fighter, "Stunned", duration)
end

local function stunNpc(humanoid: Humanoid, duration: number)
	if getState(humanoid) == "Dead" then
		return
	end
	local token = (npcStunTokens[humanoid] or 0) + 1
	npcStunTokens[humanoid] = token
	humanoid:SetAttribute("CombatState", "Stunned")
	task.delay(duration, function()
		if npcStunTokens[humanoid] == token and humanoid.Parent and getState(humanoid) == "Stunned" then
			humanoid:SetAttribute("CombatState", "Idle")
		end
	end)
end

-- ══════════════════ Hitbox ══════════════════

-- Dirección de ataque: la que manda el cliente (hacia donde apunta) o, si no es válida,
-- hacia donde mira el personaje. Confiar en ella no da ventaja: el cliente ya controla
-- la rotación de su propio personaje; alcance y tiempos se validan aquí.
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

	-- Por cada Humanoid, la parte más cercana: los enemigos grandes se golpean por el borde.
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

-- ══════════════════ Feedback ══════════════════

local function sendFeedback(feedback: HitFeedback)
	local event = Remotes.GetEvent("CombatFeedback")
	local origin = feedback.Target:GetPivot().Position
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local near = character ~= nil and (character:GetPivot().Position - origin).Magnitude <= FEEDBACK_RADIUS
		if near or player == feedback.Attacker then
			event:FireClient(player, feedback)
		end
	end
end

-- ══════════════════ Resolución del impacto ══════════════════

local function resolveParry(attacker: Fighter, defender: Fighter, feedback: HitFeedback, pushDirection: Vector3)
	defender.parryDeflected = true
	defender.lastAttackAt = nil -- contraataque inmediato
	addPosture(defender, -PARRY_DEFENDER_RECOVER)
	closeParryWindow(defender)
	settle(defender)

	attacker.attack = nil
	if addPosture(attacker, PARRY_ATTACKER_POSTURE) then
		breakPosture(attacker)
	else
		stun(attacker, PARRY_STUN)
	end
	local attackerRoot = attacker.root
	if attackerRoot then
		CombatService.ApplyPhysicalImpulse(attackerRoot, -pushDirection, PUSH.Parry.force, PUSH.Parry.duration)
	end

	feedback.Kind = "Parry"
	feedback.Intensity = 1
end

local function resolveBlock(ctx: AttackContext, defender: Fighter, defenderRoot: BasePart, feedback: HitFeedback, pushDirection: Vector3)
	local postureDamage = ctx.weapon.PostureDamage * (if ctx.combo == COMBO_LENGTH then FINISHER_POSTURE_MULT else 1)
	if addPosture(defender, postureDamage) then
		breakPosture(defender)
		CombatService.ApplyPhysicalImpulse(defenderRoot, pushDirection, PUSH.GuardBreak.force, PUSH.GuardBreak.duration)
		feedback.Kind = "GuardBreak"
		feedback.Intensity = 1
	else
		CombatService.ApplyPhysicalImpulse(defenderRoot, pushDirection, PUSH.Block.force, PUSH.Block.duration)
		feedback.Kind = "Blocked"
		feedback.Intensity = math.clamp(0.2 + postureDamage / 80, 0.2, 0.6)
	end
end

local function resolveHit(attacker: Fighter, ctx: AttackContext, targetHumanoid: Humanoid, targetModel: Model)
	local attackerRoot = attacker.root
	local targetRoot = targetHumanoid.RootPart
	if not attackerRoot or not targetRoot then
		return
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	local defender = if targetPlayer then fighters[targetPlayer] else nil
	if defender and defender.humanoid ~= targetHumanoid then
		defender = nil
	end

	local now = os.clock()
	local finisher = ctx.combo == COMBO_LENGTH
	local pushDirection = flat(targetRoot.Position - attackerRoot.Position)
	if pushDirection.Magnitude < 0.1 then
		pushDirection = ctx.direction
	end

	local feedback: HitFeedback = {
		Kind = "Hit",
		Attacker = attacker.player,
		Target = targetModel,
		Damage = 0,
		Killed = false,
		WeaponId = ctx.weapon.Id,
		Combo = ctx.combo,
		Interrupted = false,
		Hyperarmor = false,
		Intensity = if finisher then 0.7 else 0.45,
	}

	-- ── Defensas (solo jugadores) ──
	if defender then
		if now < defender.iframesUntil then
			feedback.Kind = "Dodge"
			feedback.Intensity = 0
			sendFeedback(feedback)
			return
		end

		local state = getState(targetHumanoid)
		local facing = isFacing(targetRoot, attackerRoot.Position)
		if state == "Parrying" and facing then
			resolveParry(attacker, defender, feedback, pushDirection)
			sendFeedback(feedback)
			return
		elseif state == "Blocking" and facing then
			ctx.landed = true
			resolveBlock(ctx, defender, targetRoot, feedback, pushDirection)
			sendFeedback(feedback)
			return
		end
	end

	-- ── Golpe limpio ──
	local targetState = getState(targetHumanoid)
	local damage = ctx.weapon.Damage * (if finisher then FINISHER_DAMAGE_MULT else 1)
	if targetState == "PostureBroken" then
		damage *= POSTURE_BROKEN_DAMAGE_MULT
	end

	if not targetPlayer then
		-- Contrato: LastAttacker se escribe ANTES del daño para que DungeonService lo lea en Died.
		targetHumanoid:SetAttribute("LastAttacker", attacker.player.UserId)
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

	ctx.landed = true
	feedback.Damage = dealt
	feedback.Killed = targetHumanoid.Health <= 0

	if not feedback.Killed then
		if defender then
			defender.postureCalmSince = now
			local defenderAttack = defender.attack
			if targetState == "Windup" and defenderAttack then
				local hyperarmor = defenderAttack.weapon.Weight == "Heavy"
					and defenderAttack.strikeAt - now <= HYPERARMOR_WINDOW
				if hyperarmor then
					feedback.Hyperarmor = true
				else
					feedback.Interrupted = true
					stun(defender, INTERRUPT_STUN)
				end
			elseif targetState ~= "PostureBroken" then
				stun(defender, HIT_STUN)
			end
		else
			stunNpc(targetHumanoid, HIT_STUN)
		end

		if not feedback.Hyperarmor then
			local push = if finisher then PUSH.Finisher else PUSH.Hit
			CombatService.ApplyPhysicalImpulse(targetRoot, pushDirection, push.force, push.duration)
		end
	end

	sendFeedback(feedback)
end

-- ══════════════════ Ataque ══════════════════

local function finishAttack(fighter: Fighter, ctx: AttackContext)
	if fighter.attack ~= ctx then
		return
	end
	fighter.attack = nil
	local recovery = if ctx.landed then ctx.weapon.RecoveryTime * LANDED_RECOVERY_MULT else ctx.weapon.RecoveryTime
	fighter.comboUntil = os.clock() + recovery + COMBO_WINDOW
	enterState(fighter, "Recovery", recovery)
end

local function strike(fighter: Fighter, ctx: AttackContext)
	local player = fighter.player
	local character, _, root = getAliveCharacter(player)
	if not character or not root or not WeaponVisualService.IsWeaponHeld(player) then
		fighter.attack = nil
		settle(fighter)
		return
	end

	enterState(fighter, "Attacking", ACTIVE_TIME, function()
		finishAttack(fighter, ctx)
	end)
	CombatService.ApplyPhysicalImpulse(root, ctx.direction, ctx.weapon.StepForwardForce, ACTIVE_TIME)

	local hits = 0
	for _, target in findTargets(character, root, ctx.weapon.Range, ctx.direction) do
		if hits >= MAX_TARGETS or fighter.attack ~= ctx then
			break -- máximo alcanzado o le hicieron parry
		end
		local targetModel = target.humanoid.Parent
		if not targetModel or not targetModel:IsA("Model") or not canDamage(player, targetModel) then
			continue
		end
		hits += 1
		trackHumanoid(target.humanoid)
		resolveHit(fighter, ctx, target.humanoid, targetModel)
	end
end

local function onAttack(player: Player, aim: unknown)
	local fighter = getAliveFighter(player)
	local humanoid = if fighter then fighter.humanoid else nil
	local root = if fighter then fighter.root else nil
	if not fighter or not humanoid or not root or not WeaponVisualService.IsWeaponHeld(player) then
		return
	end

	local state = getState(humanoid)
	if state ~= "Idle" and state ~= "Blocking" then
		return
	end

	local weapon = getEquippedWeapon(player)
	local now = os.clock()
	local last = fighter.lastAttackAt
	if last and now - last < weapon.AttackCooldown * COOLDOWN_TOLERANCE then
		return
	end

	fighter.combo = if now <= fighter.comboUntil then fighter.combo % COMBO_LENGTH + 1 else 1
	fighter.lastAttackAt = now

	local ctx: AttackContext = {
		weapon = weapon,
		combo = fighter.combo,
		direction = attackDirection(root, aim),
		strikeAt = now + weapon.WindupTime,
		landed = false,
	}
	fighter.attack = ctx
	humanoid:SetAttribute("ComboStep", ctx.combo)

	enterState(fighter, "Windup", weapon.WindupTime, function()
		if fighter.attack == ctx then
			strike(fighter, ctx)
		end
	end)
end

-- ══════════════════ Guardia y dash ══════════════════

local function onBlock(player: Player, held: boolean)
	local fighter = getAliveFighter(player)
	if not fighter or not fighter.humanoid then
		local existing = fighters[player]
		if existing then
			existing.blockHeld = false
		end
		return
	end
	local humanoid = fighter.humanoid :: Humanoid
	fighter.blockHeld = held
	local state = getState(humanoid)

	if not held then
		if state == "Parrying" then
			closeParryWindow(fighter)
			enterState(fighter, "Idle")
		elseif state == "Blocking" then
			enterState(fighter, "Idle")
		end
		return
	end

	-- Desde otro estado, blockHeld queda "en buffer": settle() entra a Blocking (sin parry) al terminar.
	if state ~= "Idle" or not WeaponVisualService.IsWeaponHeld(player) then
		return
	end

	local now = os.clock()
	if now < fighter.parryCooldownUntil then
		enterState(fighter, "Blocking") -- parry en cooldown: solo guardia normal
		return
	end

	fighter.parryStartedAt = now
	fighter.parryDeflected = false
	enterState(fighter, "Parrying", PARRY_WINDOW, function()
		closeParryWindow(fighter)
		settle(fighter)
	end)
end

local function onDash(player: Player)
	local fighter = getAliveFighter(player)
	local humanoid = if fighter then fighter.humanoid else nil
	if not fighter or not humanoid then
		return
	end
	local state = getState(humanoid)
	if state ~= "Idle" and state ~= "Blocking" then
		return
	end

	local now = os.clock()
	local last = fighter.lastDashAt
	if last and now - last < DASH_COOLDOWN * COOLDOWN_TOLERANCE then
		return
	end

	fighter.lastDashAt = now
	fighter.iframesUntil = now + DASH_IFRAMES
	enterState(fighter, "Dashing", DASH_DURATION)
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

-- ══════════════════ Tick (postura y guardia) ══════════════════

local function tick(dt: number)
	local now = os.clock()
	for player, fighter in fighters do
		local humanoid = fighter.humanoid
		if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
			continue
		end
		local state = getState(humanoid)

		if state == "Parrying" or state == "Blocking" then
			fighter.postureCalmSince = now -- bloquear frena la regeneración
			if not WeaponVisualService.IsWeaponHeld(player) then
				fighter.blockHeld = false
				closeParryWindow(fighter)
				enterState(fighter, "Idle")
			end
		elseif state ~= "PostureBroken" and now - fighter.postureCalmSince >= POSTURE_REGEN_DELAY then
			local posture = getPosture(humanoid)
			if posture > 0 then
				humanoid:SetAttribute("Posture", math.max(0, posture - POSTURE_REGEN_RATE * dt))
			end
		end
	end
end

-- ══════════════════ Ciclo de vida ══════════════════

local function newFighter(player: Player): Fighter
	return {
		player = player,
		stateToken = 0,
		comboUntil = 0,
		combo = 0,
		blockHeld = false,
		parryDeflected = false,
		parryCooldownUntil = 0,
		iframesUntil = 0,
		postureCalmSince = 0,
	}
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end
	if player.Character ~= character then
		return
	end
	trackHumanoid(humanoid)

	local fighter = newFighter(player)
	fighter.humanoid = humanoid
	fighter.root = root
	fighter.base = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}
	fighters[player] = fighter

	humanoid:SetAttribute("Posture", 0)
	humanoid:SetAttribute("ComboStep", 0)
	enterState(fighter, "Idle")

	humanoid.Died:Once(function()
		if fighters[player] == fighter then
			fighter.stateToken += 1 -- cancela timers pendientes
			fighter.attack = nil
			fighter.blockHeld = false
		end
	end)
end

function CombatService:Init()
	Remotes.GetEvent("CombatAttack").OnServerEvent:Connect(onCombatAction)

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
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
		if elapsed >= TICK then
			tick(elapsed)
			elapsed = 0
		end
	end)
end

return CombatService
