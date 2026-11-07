--!strict
--[[
	CombatAnimations — Animaciones procedurales del brazo del arma (sin assets subidos).
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como controlador.

	Rota el C0 del hombro derecho (R15 "RightShoulder" / R6 "Right Shoulder") sobre el pivote
	del hombro, en el espacio del torso. El Animator solo escribe Motor6D.Transform, así que
	esto se suma a caminar/idle sin pisarlo. Es local: cada cliente anima a todos los personajes.

	Ángulos: pitch > 0 levanta el brazo hacia adelante (90 = horizontal, 180 = arriba).
	         yaw   > 0 lleva el brazo hacia la izquierda del personaje.
	Cuando haya animaciones reales, reemplazar PlaySwing / SetBlocking por AnimationTracks.
]]

local TweenService = game:GetService("TweenService")

type Keyframe = { pitch: number, yaw: number, duration: number, style: Enum.EasingStyle }

local SWINGS: { [number]: { Keyframe } } = {
	-- 1: tajo vertical
	{
		{ pitch = 150, yaw = -10, duration = 0.07, style = Enum.EasingStyle.Quad },
		{ pitch = 25, yaw = 10, duration = 0.08, style = Enum.EasingStyle.Quad },
	},
	-- 2: tajo horizontal de derecha a izquierda
	{
		{ pitch = 90, yaw = -75, duration = 0.07, style = Enum.EasingStyle.Quad },
		{ pitch = 80, yaw = 65, duration = 0.09, style = Enum.EasingStyle.Quad },
	},
	-- 3: golpe pesado por arriba (remate del combo)
	{
		{ pitch = 175, yaw = 0, duration = 0.12, style = Enum.EasingStyle.Back },
		{ pitch = 15, yaw = 0, duration = 0.07, style = Enum.EasingStyle.Quad },
	},
}
local RECOVER_DURATION = 0.15
local BLOCK_POSE = { pitch = 85, yaw = 50 }
local BLOCK_TWEEN = 0.08

local restC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local tokens: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any
local blocking: { [Motor6D]: boolean } = setmetatable({}, { __mode = "k" }) :: any

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

local function pose(motor: Motor6D, pitch: number, yaw: number): CFrame
	local rest = restC0[motor]
	local rotation = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	return CFrame.new(rest.Position) * rotation * rest.Rotation
end

local function basePose(motor: Motor6D): CFrame
	return if blocking[motor] then pose(motor, BLOCK_POSE.pitch, BLOCK_POSE.yaw) else restC0[motor]
end

local function tweenTo(motor: Motor6D, target: CFrame, duration: number, style: Enum.EasingStyle): Tween
	local tween = TweenService:Create(motor, TweenInfo.new(duration, style, Enum.EasingDirection.Out), { C0 = target })
	tween:Play()
	return tween
end

-- combo: 1..3 (cualquier otro valor usa el tajo 1).
function CombatAnimations.PlaySwing(character: Model, combo: number)
	local motor = findShoulder(character)
	if not motor then
		return
	end
	local token = (tokens[motor] or 0) + 1
	tokens[motor] = token
	local keyframes = SWINGS[combo] or SWINGS[1]

	task.spawn(function()
		for _, keyframe in keyframes do
			if tokens[motor] ~= token or not motor.Parent then
				return
			end
			tweenTo(motor, pose(motor, keyframe.pitch, keyframe.yaw), keyframe.duration, keyframe.style).Completed:Wait()
		end
		if tokens[motor] == token and motor.Parent then
			tweenTo(motor, basePose(motor), RECOVER_DURATION, Enum.EasingStyle.Sine)
		end
	end)
end

function CombatAnimations.SetBlocking(character: Model, isBlocking: boolean)
	local motor = findShoulder(character)
	if not motor or blocking[motor] == isBlocking then
		return
	end
	blocking[motor] = isBlocking
	tokens[motor] = (tokens[motor] or 0) + 1 -- cancela un swing en curso
	tweenTo(motor, basePose(motor), BLOCK_TWEEN, Enum.EasingStyle.Quad)
end

return CombatAnimations
