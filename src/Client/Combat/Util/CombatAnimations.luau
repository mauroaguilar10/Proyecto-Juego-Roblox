--!strict
--[[
	CombatAnimations — Animaciones procedurales del brazo del arma (sin assets subidos).
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como controlador.

	Rota el C0 del hombro derecho (R15 "RightShoulder" / R6 "Right Shoulder") sobre el pivote
	del hombro, en el espacio del torso. El Animator solo escribe Motor6D.Transform, así que
	esto se suma a caminar/idle sin pisarlo. Es local: cada cliente anima a todos los personajes
	según su Humanoid.CombatState (lo maneja CombatController).

	Ángulos: pitch > 0 levanta el brazo hacia adelante (90 = horizontal, 180 = arriba).
	         yaw   > 0 lleva el brazo hacia la izquierda del personaje.

	  PlayWindup(character, combo, duration) → carga el golpe durante el windup.
	  PlaySlash(character, combo)            → tajo + vuelta a la pose base.
	  SetGuard(character, guarding)          → pose de guardia (Parrying / Blocking).
	  Stagger(character, broken)             → pose de aturdido / guardia rota.
	  Reset(character)                       → vuelve a la pose base.
	  Freeze(character, duration)            → hitstop: congela tween y AnimationTracks.
	Cuando haya animaciones reales, reemplazar estas funciones por AnimationTracks.
]]

local TweenService = game:GetService("TweenService")

type Pose = { pitch: number, yaw: number }
type Keyframe = { pitch: number, yaw: number, duration: number, style: Enum.EasingStyle }
type Swing = { windup: Pose, slash: { Keyframe } }
type FreezeEntry = { untilTime: number, speeds: { [AnimationTrack]: number }, tween: Tween? }

local SWINGS: { [number]: Swing } = {
	-- 1: tajo vertical
	{
		windup = { pitch = 150, yaw = -10 },
		slash = { { pitch = 25, yaw = 10, duration = 0.08, style = Enum.EasingStyle.Quad } },
	},
	-- 2: tajo horizontal de derecha a izquierda
	{
		windup = { pitch = 90, yaw = -75 },
		slash = { { pitch = 80, yaw = 65, duration = 0.09, style = Enum.EasingStyle.Quad } },
	},
	-- 3: golpe pesado por arriba (remate del combo)
	{
		windup = { pitch = 175, yaw = 0 },
		slash = { { pitch = 15, yaw = 0, duration = 0.08, style = Enum.EasingStyle.Quad } },
	},
}
local GUARD_POSE: Pose = { pitch = 85, yaw = 50 }
local STAGGER_POSE: Pose = { pitch = -20, yaw = -20 }
local BROKEN_POSE: Pose = { pitch = -35, yaw = -45 }
local RECOVER_DURATION = 0.2
local GUARD_TWEEN = 0.07

local restC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any
local guarding: { [Motor6D]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local currentTween: { [Motor6D]: Tween } = setmetatable({}, { __mode = "k" }) :: any
local frozen: { [Model]: FreezeEntry } = setmetatable({}, { __mode = "k" }) :: any

local CombatAnimations = {}

local function findShoulder(character: Model): Motor6D?
	local upperArm = character:FindFirstChild("RightUpperArm")
	local motor = if upperArm then upperArm:FindFirstChild("RightShoulder") else nil
	if not motor then
		local torso = character:FindFirstChild("Torso")
		motor = if torso then torso:FindFirstChild("Right Shoulder") else nil
	end
	if motor and motor:IsA("Motor6D") then
		if not restC0[motor] then
			restC0[motor] = motor.C0
		end
		return motor
	end
	return nil
end

local function pose(motor: Motor6D, target: Pose): CFrame
	local rest = restC0[motor]
	local rotation = CFrame.Angles(0, math.rad(target.yaw), 0) * CFrame.Angles(math.rad(target.pitch), 0, 0)
	return CFrame.new(rest.Position) * rotation * rest.Rotation
end

local function basePose(motor: Motor6D): CFrame
	return if guarding[motor] then pose(motor, GUARD_POSE) else restC0[motor]
end

local function tweenTo(motor: Motor6D, target: CFrame, duration: number, style: Enum.EasingStyle): Tween
	local previous = currentTween[motor]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(motor, TweenInfo.new(duration, style, Enum.EasingDirection.Out), { C0 = target })
	currentTween[motor] = tween
	tween:Play()
	return tween
end

local function newToken(motor: Motor6D): number
	local token = (tokens[motor] or 0) + 1
	tokens[motor] = token
	return token
end

function CombatAnimations.PlayWindup(character: Model, combo: number, duration: number)
	local motor = findShoulder(character)
	if not motor then
		return
	end
	newToken(motor)
	local swing = SWINGS[combo] or SWINGS[1]
	tweenTo(motor, pose(motor, swing.windup), math.max(duration, 0.05), Enum.EasingStyle.Quad)
end

function CombatAnimations.PlaySlash(character: Model, combo: number)
	local motor = findShoulder(character)
	if not motor then
		return
	end
	local token = newToken(motor)
	local swing = SWINGS[combo] or SWINGS[1]

	task.spawn(function()
		for _, keyframe in swing.slash do
			if tokens[motor] ~= token or not motor.Parent then
				return
			end
			local tween = tweenTo(motor, pose(motor, keyframe :: any), keyframe.duration, keyframe.style)
			if tween.PlaybackState ~= Enum.PlaybackState.Completed then
				tween.Completed:Wait()
			end
		end
		if tokens[motor] == token and motor.Parent then
			tweenTo(motor, basePose(motor), RECOVER_DURATION, Enum.EasingStyle.Sine)
		end
	end)
end

function CombatAnimations.SetGuard(character: Model, isGuarding: boolean)
	local motor = findShoulder(character)
	if not motor or (guarding[motor] or false) == isGuarding then
		return
	end
	guarding[motor] = isGuarding
	newToken(motor) -- cancela un tajo en curso
	tweenTo(motor, basePose(motor), GUARD_TWEEN, Enum.EasingStyle.Quad)
end

function CombatAnimations.Stagger(character: Model, broken: boolean)
	local motor = findShoulder(character)
	if not motor then
		return
	end
	guarding[motor] = false
	newToken(motor)
	tweenTo(motor, pose(motor, if broken then BROKEN_POSE else STAGGER_POSE), 0.1, Enum.EasingStyle.Quad)
end

function CombatAnimations.Reset(character: Model)
	local motor = findShoulder(character)
	if not motor then
		return
	end
	newToken(motor)
	tweenTo(motor, basePose(motor), RECOVER_DURATION, Enum.EasingStyle.Sine)
end

-- Hitstop: congela el tween del brazo y las AnimationTracks del personaje por `duration` s.
-- Si ya estaba congelado, extiende el congelamiento.
function CombatAnimations.Freeze(character: Model, duration: number)
	local untilTime = os.clock() + duration
	local entry = frozen[character]
	if entry then
		entry.untilTime = math.max(entry.untilTime, untilTime)
		return
	end

	local newEntry: FreezeEntry = { untilTime = untilTime, speeds = {} }
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			newEntry.speeds[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
	local motor = findShoulder(character)
	local tween = if motor then currentTween[motor] else nil
	if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
		tween:Pause()
		newEntry.tween = tween
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
		local paused = newEntry.tween
		if paused and paused.PlaybackState == Enum.PlaybackState.Paused then
			paused:Play()
		end
	end)
end

return CombatAnimations
