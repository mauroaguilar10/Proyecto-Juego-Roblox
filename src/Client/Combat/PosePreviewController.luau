--!strict
--[[
	PosePreviewController — Vista previa de poses y efectos de combate. SOLO EN STUDIO.
	Owner: Dev A (Combat).

	Sirve para ver y ajustar cada cosa que hace el personaje sin necesitar un rival:
	  P        → siguiente   ·   Shift+P → anterior
	  R        → repetir la actual
	  X        → salir de la vista previa (vuelve todo a normal)
	Todo es local (no pasa por el servidor). Para retocar una pose, cambiar sus números en
	CombatAnimations (tabla POSES) y repetir con R: Rojo sincroniza el cambio al instante
	si se vuelve a entrar al Play.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Util = script.Parent:WaitForChild("Util")
local CombatAnimations = require(Util:WaitForChild("CombatAnimations"))
local CombatEffects = require(Util:WaitForChild("CombatEffects"))
local CombatVisuals = require(Util:WaitForChild("CombatVisuals"))
local WeaponData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponData"))

type Entry = { name: string, run: (character: Model, root: BasePart) -> () }

local ACTION_NEXT = "PosePreviewNext"
local ACTION_REPLAY = "PosePreviewReplay"
local ACTION_EXIT = "PosePreviewExit"
local DASH_DURATION = 0.25

local localPlayer = Players.LocalPlayer
local poses = CombatAnimations.Poses
local index = 0
local label: TextLabel? = nil

local PosePreviewController = {}

local function weight(): WeaponData.WeaponWeight
	local equipped = localPlayer:GetAttribute("EquippedWeapon")
	return WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil).Weight
end

local function clearEffects(character: Model)
	CombatVisuals.SetGuardGlow(character, false)
	CombatVisuals.SetBrokenPulse(character, false)
end

local function slash(combo: number): Entry
	return {
		name = `Tajo {combo} (carga → golpe + estela)`,
		run = function(character, root)
			CombatAnimations.PlayWindup(character, combo, 0.35)
			CombatVisuals.WindupGlint(character, combo == 3)
			task.delay(0.35, function()
				CombatAnimations.PlaySlash(character, combo, weight())
				CombatVisuals.SlashTrail(character, if combo == 3 then Color3.fromRGB(255, 185, 80) else Color3.fromRGB(235, 240, 255), 0.2)
				CombatEffects.PlaySound(if combo == 3 then "Heavy" else "Swing", root)
			end)
		end,
	}
end

local function windup(combo: number): Entry
	return {
		name = `Carga {combo} (pose sostenida)`,
		run = function(character)
			CombatAnimations.ShowPose(character, poses.Windup[combo], 0.25)
			CombatVisuals.WindupGlint(character, combo == 3)
		end,
	}
end

local function dash(name: string, localDirection: Vector3): Entry
	return {
		name = name,
		run = function(character, root)
			local direction = root.CFrame:VectorToWorldSpace(localDirection)
			CombatEffects.DashMove(root, direction, 64, DASH_DURATION, 2000)
			CombatEffects.PlaySound("Dash", root)
			CombatAnimations.PlayDash(character, localDirection, DASH_DURATION)
			CombatVisuals.Dash(character, direction, DASH_DURATION)
		end,
	}
end

local ENTRIES: { Entry } = {
	{ name = "Reposo (sin arma)", run = function(character)
		CombatAnimations.ShowPose(character, poses.Rest)
	end },
	{ name = "Listo (arma en la mano)", run = function(character)
		CombatAnimations.ShowPose(character, poses.Ready)
	end },
	windup(1),
	windup(2),
	windup(3),
	slash(1),
	slash(2),
	slash(3),
	{ name = "Parry: ventana activa (espada blanca)", run = function(character)
		CombatAnimations.ShowPose(character, poses.Parry, 0.05)
		CombatVisuals.ParryWindow(character, 0.6)
	end },
	{ name = "Parry exitoso (defensor desvía)", run = function(character, root)
		CombatAnimations.ShowPose(character, poses.Parry, 0.05)
		task.delay(0.1, function()
			CombatAnimations.PlayImpact(character, "ParryFlick")
			CombatEffects.ParrySpark(root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1, 0))
			CombatEffects.PlaySound("Parry", root)
			CombatAnimations.Freeze(character, 0.14)
		end)
	end },
	{ name = "Le hicieron parry (retroceso del atacante)", run = function(character, root)
		CombatAnimations.PlayRecoil(character)
		CombatEffects.ParrySpark(root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1, 0))
		CombatEffects.PlaySound("Parry", root)
	end },
	{ name = "Guardia (contorno azul)", run = function(character)
		CombatAnimations.ShowPose(character, poses.Block, 0.08)
		CombatVisuals.SetGuardGlow(character, true)
	end },
	{ name = "Golpe bloqueado (sacudón)", run = function(character, root)
		CombatAnimations.SetMode(character, "Block")
		CombatVisuals.SetGuardGlow(character, true)
		task.delay(0.15, function()
			CombatAnimations.PlayImpact(character, "BlockJolt")
			CombatVisuals.HitSpark(root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 1, 0), CombatEffects.Colors.Blocked, 14)
			CombatEffects.PlaySound("Block", root)
		end)
	end },
	{ name = "Aturdido por un golpe", run = function(character, root)
		CombatAnimations.ShowPose(character, poses.Stagger, 0.06)
		CombatEffects.Flash(character, CombatEffects.Colors.Hit)
		CombatVisuals.HitSpark(root.Position + Vector3.new(0, 0.5, 0), CombatEffects.Colors.Hit, 10)
		CombatEffects.Popup(character, "-10", CombatEffects.Colors.Damage)
	end },
	{ name = "Guardia rota (rodilla al piso + pulso rojo)", run = function(character, root)
		CombatAnimations.ShowPose(character, poses.Broken, 0.3)
		CombatEffects.GuardBreakBurst(character)
		CombatVisuals.SetBrokenPulse(character, true)
		CombatEffects.Popup(character, "¡GUARDIA ROTA!", CombatEffects.Colors.GuardBreak, true)
		CombatEffects.PlaySound("GuardBreak", root)
	end },
	dash("Dash adelante", Vector3.new(0, 0, -1)),
	dash("Dash atrás", Vector3.new(0, 0, 1)),
	dash("Dash izquierda", Vector3.new(-1, 0, 0)),
	dash("Dash derecha", Vector3.new(1, 0, 0)),
}

local function getLabel(): TextLabel
	if label then
		return label
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "PosePreview"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, 0, 0, 64)
	text.Size = UDim2.fromOffset(520, 52)
	text.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	text.BackgroundTransparency = 0.25
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 18
	text.TextWrapped = true
	text.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = text
	text.Parent = screen
	screen.Parent = localPlayer:WaitForChild("PlayerGui")
	label = text
	return text
end

local function runCurrent()
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if humanoid then humanoid.RootPart else nil
	if not character or not root then
		return
	end
	local entry = ENTRIES[index]
	clearEffects(character)
	CombatAnimations.Reset(character)
	task.delay(0.05, function()
		entry.run(character, root)
	end)

	local text = getLabel()
	text.Text = `Vista previa {index}/{#ENTRIES}: {entry.name}\nP siguiente · Shift+P anterior · R repetir · X salir`
	text.Visible = true
end

local function step(delta: number)
	index = ((index - 1 + delta) % #ENTRIES) + 1
	runCurrent()
end

local function exitPreview()
	index = 0
	if label then
		label.Visible = false
	end
	local character = localPlayer.Character
	if character then
		clearEffects(character)
		CombatAnimations.Reset(character)
	end
end

function PosePreviewController:Init()
	if not RunService:IsStudio() then
		return
	end

	ContextActionService:BindAction(ACTION_NEXT, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			step(if shift then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.P)

	ContextActionService:BindAction(ACTION_REPLAY, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin and index > 0 then
			runCurrent()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.R)

	ContextActionService:BindAction(ACTION_EXIT, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin and index > 0 then
			exitPreview()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.X)

	print("[PosePreview] Studio: apretá P para ver las poses y efectos de combate")
end

return PosePreviewController
