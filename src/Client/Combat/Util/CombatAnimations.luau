--!strict
--[[
	CombatAnimations — Motor de poses procedurales de cuerpo completo (sin assets subidos).
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como controlador.

	Cada pose rota las articulaciones (Motor6D.C0) sobre su pivote, en el espacio de la parte
	padre. El Animator solo escribe Motor6D.Transform, así que esto se suma a caminar/idle.
	Es local: cada cliente anima a todos los personajes según su Humanoid.CombatState
	(lo decide CombatController). R15 usa todas las articulaciones; R6 solo hombros, cuello,
	raíz y caderas (las que no existen se ignoran).

	Ángulos en grados, en el espacio de la parte padre de la articulación:
	  p (pitch, eje X)  Brazos/piernas: > 0 hacia adelante. Codos/rodillas: > 0 flexiona el codo,
	                    < 0 flexiona la rodilla. Cintura/cuello: > 0 inclina hacia atrás.
	  y (yaw, eje Y)    > 0 gira hacia la izquierda del personaje.
	  r (roll, eje Z)   Brazo derecho: > 0 lo abre hacia afuera. Brazo izquierdo: < 0 lo abre.
	                    Cintura/cuello: > 0 se ladea hacia la izquierda.
	  pos               Desplazamiento (studs) de la articulación. Solo se usa en Root para agacharse.

	Todas las poses están en la tabla POSES: para ajustar cómo se ve algo, se tocan los números ahí.
	CombatController / PosePreviewController llaman a la API de abajo.
]]

local TweenService = game:GetService("TweenService")

export type JointName =
	"RShoulder"
	| "LShoulder"
	| "RElbow"
	| "LElbow"
	| "RWrist"
	| "Waist"
	| "Neck"
	| "Root"
	| "RHip"
	| "LHip"
	| "RKnee"
	| "LKnee"
export type JointRotation = { p: number?, y: number?, r: number?, pos: Vector3? }
export type Pose = { [JointName]: JointRotation }
export type GuardMode = "None" | "Block" | "Parry" | "Stunned" | "Broken"
export type ImpactKind = "BlockJolt" | "ParryFlick" | "Flinch"
export type Weight = "Light" | "Medium" | "Heavy"

type Step = { pose: Pose, duration: number, style: Enum.EasingStyle, hold: number? }
type FreezeEntry = { untilTime: number, speeds: { [AnimationTrack]: number }, tweens: { Tween } }
type Rig = {
	character: Model,
	motors: { [JointName]: Motor6D },
	tweens: { Tween },
	token: number, -- secuencia en curso (windup/tajo/impacto)
	busy: boolean, -- true mientras una secuencia controla la pose
	mode: GuardMode,
	armed: boolean, -- arma en la mano → pose de guardia baja ("Listo")
	recoilUntil: number,
}

-- R15 primero, R6 después: { parte que contiene el Motor6D, nombre del Motor6D }
local JOINT_CANDIDATES: { [JointName]: { { string } } } = {
	RShoulder = { { "RightUpperArm", "RightShoulder" }, { "Torso", "Right Shoulder" } },
	LShoulder = { { "LeftUpperArm", "LeftShoulder" }, { "Torso", "Left Shoulder" } },
	RElbow = { { "RightLowerArm", "RightElbow" } },
	LElbow = { { "LeftLowerArm", "LeftElbow" } },
	RWrist = { { "RightHand", "RightWrist" } },
	Waist = { { "UpperTorso", "Waist" } },
	Neck = { { "Head", "Neck" }, { "Torso", "Neck" } },
	Root = { { "LowerTorso", "Root" }, { "HumanoidRootPart", "RootJoint" } },
	RHip = { { "RightUpperLeg", "RightHip" }, { "Torso", "Right Hip" } },
	LHip = { { "LeftUpperLeg", "LeftHip" }, { "Torso", "Left Hip" } },
	RKnee = { { "RightLowerLeg", "RightKnee" } },
	LKnee = { { "LeftLowerLeg", "LeftKnee" } },
}

-- ══════════════════ Poses ══════════════════

local POSES = {
	Rest = {} :: Pose,

	-- Arma en la mano: espada adelante, rodillas apenas flexionadas.
	Ready = {
		RShoulder = { p = 25, r = 8 },
		RElbow = { p = 40 },
		RWrist = { p = -10 },
		LShoulder = { p = 12, r = -6 },
		LElbow = { p = 15 },
		Waist = { y = -10 },
		RHip = { p = 6 },
		RKnee = { p = -8 },
		LHip = { p = -4 },
		LKnee = { p = -6 },
	} :: Pose,

	-- Cargas del combo (se sostienen durante todo el WindupTime).
	Windup = {
		-- 1: tajo vertical, espada arriba-atrás
		{
			RShoulder = { p = 160, y = -10, r = 10 },
			RElbow = { p = 45 },
			RWrist = { p = 15 },
			LShoulder = { p = 45, r = -15 },
			LElbow = { p = 30 },
			Waist = { p = 8, y = -18 },
			Neck = { p = -4, y = 10 },
			RHip = { p = -8 },
			LHip = { p = 12 },
			LKnee = { p = -12 },
		},
		-- 2: tajo horizontal, espada a la derecha y el torso girado
		{
			RShoulder = { p = 85, y = -85, r = 10 },
			RElbow = { p = 35 },
			RWrist = { p = -15 },
			LShoulder = { p = 55, y = 35 },
			LElbow = { p = 40 },
			Waist = { y = -40, r = -6 },
			Neck = { y = 25 },
			RHip = { p = -10 },
			RKnee = { p = -15 },
			LHip = { p = 15 },
			LKnee = { p = -15 },
		},
		-- 3: golpe pesado a dos manos por arriba, agachándose
		{
			RShoulder = { p = 175, y = -5 },
			RElbow = { p = 65 },
			RWrist = { p = 20 },
			LShoulder = { p = 160, y = -25, r = 15 },
			LElbow = { p = 70 },
			Waist = { p = 18 },
			Neck = { p = 10 },
			Root = { pos = Vector3.new(0, -0.35, 0) },
			RHip = { p = 18 },
			RKnee = { p = -30 },
			LHip = { p = -12 },
			LKnee = { p = -20 },
		},
	} :: { Pose },

	-- Final de cada tajo (de la carga a esto en 0,07–0,11 s según el peso).
	Slash = {
		{
			RShoulder = { p = 15, y = 15, r = 5 },
			RElbow = { p = 10 },
			RWrist = { p = -20 },
			LShoulder = { p = -15, r = -10 },
			Waist = { p = -18, y = 18 },
			Neck = { p = -8, y = -10 },
			RHip = { p = 18 },
			RKnee = { p = -20 },
			LHip = { p = -12 },
		},
		{
			RShoulder = { p = 80, y = 75, r = -5 },
			RElbow = { p = 5 },
			RWrist = { p = 10 },
			LShoulder = { p = -20, r = -30 },
			Waist = { y = 45, r = 5 },
			Neck = { y = -25 },
			RHip = { p = 15 },
			RKnee = { p = -15 },
			LHip = { p = -10 },
		},
		{
			RShoulder = { p = 10 },
			RElbow = { p = 5 },
			RWrist = { p = -25 },
			LShoulder = { p = 25 },
			LElbow = { p = 25 },
			Waist = { p = -32 },
			Neck = { p = -12 },
			Root = { pos = Vector3.new(0, -0.45, 0) },
			RHip = { p = 30 },
			RKnee = { p = -40 },
			LHip = { p = -18 },
			LKnee = { p = -12 },
		},
	} :: { Pose },

	-- Guardia: espada cruzada frente a la cara, la mano izquierda la apuntala, base firme.
	Block = {
		RShoulder = { p = 95, y = 40 },
		RElbow = { p = 55 },
		RWrist = { p = 5 },
		LShoulder = { p = 85, y = -35 },
		LElbow = { p = 75 },
		Waist = { p = -6 },
		Neck = { p = -6 },
		Root = { pos = Vector3.new(0, -0.2, 0) },
		RHip = { p = 12 },
		RKnee = { p = -18 },
		LHip = { p = -8 },
		LKnee = { p = -12 },
	} :: Pose,

	-- Parry: desvío hacia afuera, más alto y abierto que la guardia.
	Parry = {
		RShoulder = { p = 115, y = 25, r = 15 },
		RElbow = { p = 25 },
		RWrist = { p = 20 },
		LShoulder = { p = 35, r = -25 },
		LElbow = { p = 20 },
		Waist = { y = 22, p = -4 },
		Neck = { y = -10 },
		RHip = { p = 10 },
		RKnee = { p = -12 },
	} :: Pose,

	-- Aturdido por un golpe: tronco doblado hacia atrás, brazos sueltos.
	Stagger = {
		RShoulder = { p = -12, r = 25 },
		RElbow = { p = 20 },
		LShoulder = { p = -8, r = -25 },
		LElbow = { p = 15 },
		Waist = { p = 15, r = 8 },
		Neck = { p = 14, r = -10 },
		RHip = { p = -8 },
		LHip = { p = 14 },
		LKnee = { p = -20 },
	} :: Pose,

	-- Le hicieron parry: brazos despedidos hacia arriba/atrás, pierde el equilibrio.
	Recoil = {
		RShoulder = { p = 150, y = -30, r = 35 },
		RElbow = { p = 10 },
		RWrist = { p = 30 },
		LShoulder = { p = 40, r = -55 },
		LElbow = { p = 10 },
		Waist = { p = 22, y = -18 },
		Neck = { p = 18 },
		RHip = { p = -12 },
		LHip = { p = 22 },
		LKnee = { p = -25 },
	} :: Pose,

	-- Guardia rota: rodilla al piso, cabeza gacha, espada colgando.
	Broken = {
		RShoulder = { p = -5, r = 12 },
		RElbow = { p = 15 },
		RWrist = { p = -20 },
		LShoulder = { p = 20, r = -10 },
		LElbow = { p = 50 },
		Waist = { p = -28, r = 6 },
		Neck = { p = -28 },
		Root = { pos = Vector3.new(0, -1, 0) },
		RHip = { p = 65 },
		RKnee = { p = -95 },
		LHip = { p = -25 },
		LKnee = { p = -70 },
	} :: Pose,

	-- Impactos cortos (van y vuelven a la pose base).
	BlockJolt = {
		RShoulder = { p = 80, y = 40 },
		RElbow = { p = 70 },
		LShoulder = { p = 70, y = -35 },
		LElbow = { p = 85 },
		Waist = { p = 14 },
		Neck = { p = 10 },
		Root = { pos = Vector3.new(0, -0.3, 0) },
		RHip = { p = 5 },
		RKnee = { p = -25 },
		LHip = { p = -18 },
		LKnee = { p = -10 },
	} :: Pose,
	ParryFlick = {
		RShoulder = { p = 145, y = 35, r = 25 },
		RElbow = { p = 15 },
		RWrist = { p = 35 },
		LShoulder = { p = 25, r = -35 },
		Waist = { y = 30, p = 6 },
		Neck = { y = -15 },
	} :: Pose,
	Flinch = {
		Waist = { p = 10, r = -6 },
		Neck = { p = 12 },
		RShoulder = { p = 15, r = 15 },
		LShoulder = { p = -5, r = -15 },
	} :: Pose,
}

-- Inclinación del dash según la dirección local (adelante = -Z).
local DASH_LEAN = {
	Forward = { Waist = { p = -28 }, Neck = { p = -10 }, RShoulder = { p = -35, r = 15 }, LShoulder = { p = -35, r = -15 }, RHip = { p = -25 }, LHip = { p = 30 }, LKnee = { p = -35 } } :: Pose,
	Back = { Waist = { p = 18 }, Neck = { p = 8 }, RShoulder = { p = 40, r = 20 }, LShoulder = { p = 40, r = -20 }, RHip = { p = 30 }, RKnee = { p = -40 }, LHip = { p = -15 } } :: Pose,
	Left = { Waist = { r = 22 }, Neck = { r = -10 }, RShoulder = { r = 45 }, LShoulder = { r = -15 }, RHip = { r = 20 }, LHip = { r = 10 } } :: Pose,
	Right = { Waist = { r = -22 }, Neck = { r = 10 }, RShoulder = { r = 15 }, LShoulder = { r = -45 }, RHip = { r = -10 }, LHip = { r = -20 } } :: Pose,
}

local SLASH_TIME: { [Weight]: number } = { Light = 0.07, Medium = 0.09, Heavy = 0.11 }
local SLASH_HOLD = 0.08
local RETURN_TIME = 0.22
local MODE_TWEEN: { [GuardMode]: number } = { None = 0.2, Block = 0.08, Parry = 0.05, Stunned = 0.06, Broken = 0.3 }

-- ══════════════════ Rig ══════════════════

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any
local restC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local frozen: { [Model]: FreezeEntry } = setmetatable({}, { __mode = "k" }) :: any

local CombatAnimations = {}
CombatAnimations.Poses = POSES

local function findMotors(character: Model): { [JointName]: Motor6D }
	local motors: { [JointName]: Motor6D } = {}
	for joint, candidates in JOINT_CANDIDATES do
		for _, candidate in candidates do
			local part = character:FindFirstChild(candidate[1])
			local motor = if part then part:FindFirstChild(candidate[2]) else nil
			if motor and motor:IsA("Motor6D") then
				if not restC0[motor] then
					restC0[motor] = motor.C0
				end
				motors[joint] = motor
				break
			end
		end
	end
	return motors
end

local function getRig(character: Model): Rig?
	local rig = rigs[character]
	if rig then
		local shoulder = rig.motors.RShoulder
		if shoulder and shoulder.Parent then
			return rig
		end
	end
	local motors = findMotors(character)
	if not motors.RShoulder then
		return nil -- todavía no cargó el personaje
	end
	local newRig: Rig = {
		character = character,
		motors = motors,
		tweens = {},
		token = 0,
		busy = false,
		mode = if rig then rig.mode else "None",
		armed = if rig then rig.armed else false,
		recoilUntil = 0,
	}
	rigs[character] = newRig
	return newRig
end

local function jointTarget(motor: Motor6D, rotation: JointRotation?): CFrame
	local rest = restC0[motor]
	if not rotation then
		return rest
	end
	local offset = rotation.pos or Vector3.zero
	local turn = CFrame.Angles(0, math.rad(rotation.y or 0), 0)
		* CFrame.Angles(math.rad(rotation.p or 0), 0, 0)
		* CFrame.Angles(0, 0, math.rad(rotation.r or 0))
	return CFrame.new(rest.Position + offset) * turn * rest.Rotation
end

local function stopTweens(rig: Rig)
	for _, tween in rig.tweens do
		tween:Cancel()
	end
	table.clear(rig.tweens)
end

-- Lleva todas las articulaciones a `pose` (las que no figuran vuelven a reposo).
local function apply(rig: Rig, pose: Pose, duration: number, style: Enum.EasingStyle): Tween?
	stopTweens(rig)
	local info = TweenInfo.new(math.max(duration, 0.01), style, Enum.EasingDirection.Out)
	local last: Tween? = nil
	for joint, motor in rig.motors do
		if not motor.Parent then
			continue
		end
		local tween = TweenService:Create(motor, info, { C0 = jointTarget(motor, pose[joint]) })
		table.insert(rig.tweens, tween)
		tween:Play()
		last = tween
	end
	local freeze = frozen[rig.character]
	if freeze then
		for _, tween in rig.tweens do
			tween:Pause()
		end
		freeze.tweens = table.clone(rig.tweens)
	end
	return last
end

local function basePose(rig: Rig): Pose
	if rig.mode == "Block" then
		return POSES.Block
	elseif rig.mode == "Parry" then
		return POSES.Parry
	elseif rig.mode == "Stunned" then
		return POSES.Stagger
	elseif rig.mode == "Broken" then
		return POSES.Broken
	end
	return if rig.armed then POSES.Ready else POSES.Rest
end

local function returnToBase(rig: Rig, duration: number)
	rig.busy = false
	apply(rig, basePose(rig), duration, Enum.EasingStyle.Sine)
end

-- Reproduce pasos en orden; al terminar vuelve a la pose base (si `returnAfter`).
local function play(rig: Rig, steps: { Step }, returnAfter: boolean)
	rig.token += 1
	local token = rig.token
	rig.busy = true
	task.spawn(function()
		for _, step in steps do
			if rig.token ~= token then
				return
			end
			local tween = apply(rig, step.pose, step.duration, step.style)
			if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
				tween.Completed:Wait()
			end
			if step.hold and rig.token == token then
				task.wait(step.hold)
			end
		end
		if rig.token == token and returnAfter then
			returnToBase(rig, RETURN_TIME)
		end
	end)
end

-- ══════════════════ API ══════════════════

-- Arma en la mano (pose "Listo") o guardada (reposo).
function CombatAnimations.SetArmed(character: Model, armed: boolean)
	local rig = getRig(character)
	if not rig or rig.armed == armed then
		return
	end
	rig.armed = armed
	if not rig.busy and rig.mode == "None" then
		returnToBase(rig, 0.25)
	end
end

-- Postura base mientras dura un estado: guardia, parry, aturdido, guardia rota o nada.
function CombatAnimations.SetMode(character: Model, mode: GuardMode)
	local rig = getRig(character)
	if not rig then
		return
	end
	if rig.mode == mode then
		return
	end
	rig.mode = mode
	if mode == "None" and rig.busy then
		return -- un tajo en curso vuelve solo a la base
	end
	if mode == "Stunned" and os.clock() < rig.recoilUntil then
		return -- se está mostrando el retroceso por parry
	end
	rig.token += 1 -- cancela secuencias
	returnToBase(rig, MODE_TWEEN[mode])
end

function CombatAnimations.PlayWindup(character: Model, combo: number, duration: number)
	local rig = getRig(character)
	if not rig then
		return
	end
	rig.mode = "None"
	rig.token += 1
	rig.busy = true
	apply(rig, POSES.Windup[combo] or POSES.Windup[1], duration, Enum.EasingStyle.Quad)
end

function CombatAnimations.PlaySlash(character: Model, combo: number, weight: Weight)
	local rig = getRig(character)
	if not rig then
		return
	end
	rig.mode = "None"
	play(rig, {
		{ pose = POSES.Slash[combo] or POSES.Slash[1], duration = SLASH_TIME[weight], style = Enum.EasingStyle.Quart, hold = SLASH_HOLD },
	}, true)
end

-- Impacto corto sobre la pose actual: ida rápida y vuelta a la base.
function CombatAnimations.PlayImpact(character: Model, kind: ImpactKind)
	local rig = getRig(character)
	if not rig then
		return
	end
	local pose = if kind == "BlockJolt" then POSES.BlockJolt elseif kind == "ParryFlick" then POSES.ParryFlick else POSES.Flinch
	play(rig, { { pose = pose, duration = 0.05, style = Enum.EasingStyle.Quad, hold = 0.05 } }, true)
end

-- Retroceso al recibir un parry: se sostiene hasta que termine el aturdimiento.
function CombatAnimations.PlayRecoil(character: Model)
	local rig = getRig(character)
	if not rig then
		return
	end
	rig.mode = "Stunned"
	rig.recoilUntil = os.clock() + 0.5
	rig.token += 1
	rig.busy = false
	apply(rig, POSES.Recoil, 0.08, Enum.EasingStyle.Back)
end

-- Inclinación del dash. localDirection: dirección del dash en el espacio del HumanoidRootPart.
function CombatAnimations.PlayDash(character: Model, localDirection: Vector3, duration: number)
	local rig = getRig(character)
	if not rig then
		return
	end
	local lean: Pose
	if math.abs(localDirection.Z) >= math.abs(localDirection.X) then
		lean = if localDirection.Z < 0 then DASH_LEAN.Forward else DASH_LEAN.Back
	else
		lean = if localDirection.X < 0 then DASH_LEAN.Left else DASH_LEAN.Right
	end
	play(rig, { { pose = lean, duration = 0.06, style = Enum.EasingStyle.Quad, hold = math.max(0, duration - 0.1) } }, true)
end

-- Muestra una pose fija (vista previa). Se libera con Reset().
function CombatAnimations.ShowPose(character: Model, pose: Pose, duration: number?)
	local rig = getRig(character)
	if not rig then
		return
	end
	rig.token += 1
	rig.busy = true
	apply(rig, pose, duration or 0.15, Enum.EasingStyle.Quad)
end

function CombatAnimations.Reset(character: Model)
	local rig = getRig(character)
	if not rig then
		return
	end
	rig.mode = "None"
	rig.recoilUntil = 0
	rig.token += 1
	returnToBase(rig, RETURN_TIME)
end

-- Hitstop: congela las poses y las AnimationTracks del personaje por `duration` s.
-- Si ya estaba congelado, extiende el congelamiento.
function CombatAnimations.Freeze(character: Model, duration: number)
	local untilTime = os.clock() + duration
	local entry = frozen[character]
	if entry then
		entry.untilTime = math.max(entry.untilTime, untilTime)
		return
	end

	local newEntry: FreezeEntry = { untilTime = untilTime, speeds = {}, tweens = {} }
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			newEntry.speeds[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
	local rig = rigs[character]
	if rig then
		for _, tween in rig.tweens do
			if tween.PlaybackState == Enum.PlaybackState.Playing then
				tween:Pause()
				table.insert(newEntry.tweens, tween)
			end
		end
	end
	frozen[character] = newEntry

	task.spawn(function()
		while os.clock() < newEntry.untilTime do
			task.wait()
		end
		frozen[character] = nil
		for track, speed in newEntry.speeds do
			if track.IsPlaying then
				track:AdjustSpeed(speed)
			end
		end
		for _, tween in newEntry.tweens do
			if tween.PlaybackState == Enum.PlaybackState.Paused then
				tween:Play()
			end
		end
	end)
end

return CombatAnimations
