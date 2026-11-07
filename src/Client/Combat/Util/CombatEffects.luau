--!strict
--[[
	CombatEffects — Feedback visual y sonoro de los golpes (solo cliente).
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como controlador.

	- Números de daño flotantes y textos ("¡Parry!", "Bloqueado", "¡Guardia rota!").
	- Destello (Highlight) sobre el objetivo.
	- Sonidos: usan los sonidos que trae el cliente de Roblox (rbxasset://). Para sonidos
	  propios, subirlos y reemplazar los IDs en SOUNDS.
	- Empuje del personaje local (el cliente es dueño de su física).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

export type SoundName = "Swing" | "Heavy" | "Hit" | "Block" | "Parry" | "Equip"

local SOUNDS: { [SoundName]: { id: string, volume: number, speed: number } } = {
	Swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.5, speed = 1.1 },
	Heavy = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.6, speed = 0.9 },
	Hit = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.7, speed = 1.5 },
	Block = { id = "rbxasset://sounds/swordslash.wav", volume = 0.7, speed = 0.6 },
	Parry = { id = "rbxasset://sounds/unsheath.wav", volume = 0.9, speed = 1.3 },
	Equip = { id = "rbxasset://sounds/unsheath.wav", volume = 0.5, speed = 1 },
}

local FLASH_DURATION = 0.15
local POPUP_DURATION = 0.75
local POPUP_RISE = 2.5

local COLORS = {
	Hit = Color3.fromRGB(255, 60, 60),
	Damage = Color3.fromRGB(255, 255, 255),
	Finisher = Color3.fromRGB(255, 170, 40),
	Blocked = Color3.fromRGB(160, 175, 200),
	Parry = Color3.fromRGB(80, 220, 255),
	GuardBreak = Color3.fromRGB(255, 120, 40),
}

local localPlayer = Players.LocalPlayer
local random = Random.new()

local CombatEffects = {}
CombatEffects.Colors = COLORS

local function anchorPart(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.RootPart else model.PrimaryPart
end

function CombatEffects.PlaySound(name: SoundName, at: Instance?)
	local spec = SOUNDS[name]
	local sound = Instance.new("Sound")
	sound.SoundId = spec.id
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed * random:NextNumber(0.95, 1.05)
	sound.RollOffMaxDistance = 80
	sound.Parent = if at and at:IsA("BasePart") then at else workspace
	sound:Play()
	Debris:AddItem(sound, 3)
end

function CombatEffects.Flash(model: Model, color: Color3)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.4
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	Debris:AddItem(highlight, FLASH_DURATION)
end

-- Texto flotante sobre un modelo. big = remate del combo / eventos importantes.
function CombatEffects.Popup(model: Model, text: string, color: Color3, big: boolean?)
	local part = anchorPart(model)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not part or not playerGui then
		return
	end

	local startOffset = Vector3.new(random:NextNumber(-1, 1), 1.5, 0)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CombatPopup"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Size = UDim2.fromOffset(160, if big then 48 else 34)
	gui.StudsOffsetWorldSpace = startOffset

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = playerGui

	local info = TweenInfo.new(POPUP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = startOffset + Vector3.new(0, POPUP_RISE, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(POPUP_DURATION * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, POPUP_DURATION * 0.5), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(gui, POPUP_DURATION + 0.1)
end

-- Empuja el personaje local con una velocidad horizontal por `duration` s + impulso vertical.
function CombatEffects.PushLocalCharacter(velocity: Vector3, duration: number)
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if humanoid then humanoid.RootPart else nil
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "PushAttachment"
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

	if velocity.Y > 0 then
		root.AssemblyLinearVelocity += Vector3.new(0, velocity.Y, 0)
	end
	Debris:AddItem(mover, duration)
	Debris:AddItem(attachment, duration)
end

return CombatEffects
