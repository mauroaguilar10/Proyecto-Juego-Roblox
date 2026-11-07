--!strict
--[[
	CombatEffects — Feedback visual y sonoro de los golpes (solo cliente).
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como controlador.

	- PlaySound: sonidos que trae el cliente de Roblox (rbxasset://). Para sonidos propios,
	  subirlos y reemplazar los IDs en SOUNDS.
	- Flash / Popup: destello sobre el modelo y texto flotante (daño, "¡Parry!", etc.).
	- Shake: sacudida procedural de cámara (vía Humanoid.CameraOffset del jugador local,
	  así no se acumula sobre el CFrame de la cámara).
	- ParrySpark: destello de luz + chispas amarillas/naranjas en un punto.
	- GuardBreakBurst: efecto rojo intenso sobre el personaje con la guardia rota.
	- DashMove: física del dash local (LinearVelocity en XZ con fricción).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

export type SoundName = "Swing" | "Heavy" | "Hit" | "Block" | "Parry" | "GuardBreak" | "Equip" | "Dash"

local SOUNDS: { [SoundName]: { id: string, volume: number, speed: number } } = {
	Swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.5, speed = 1.1 },
	Heavy = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.6, speed = 0.9 },
	Hit = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.7, speed = 1.5 },
	Block = { id = "rbxasset://sounds/swordslash.wav", volume = 0.7, speed = 0.6 },
	Parry = { id = "rbxasset://sounds/unsheath.wav", volume = 1, speed = 1.4 },
	GuardBreak = { id = "rbxasset://sounds/swordlunge.wav", volume = 1, speed = 0.55 },
	Equip = { id = "rbxasset://sounds/unsheath.wav", volume = 0.5, speed = 1 },
	Dash = { id = "rbxasset://sounds/swordslash.wav", volume = 0.35, speed = 1.6 },
}

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local FLASH_DURATION = 0.15
local POPUP_DURATION = 0.75
local POPUP_RISE = 2.5
local SHAKE_BIND = "CombatCameraShake"

local COLORS = {
	Hit = Color3.fromRGB(255, 60, 60),
	Damage = Color3.fromRGB(255, 255, 255),
	Finisher = Color3.fromRGB(255, 170, 40),
	Blocked = Color3.fromRGB(160, 175, 200),
	Parry = Color3.fromRGB(255, 210, 90),
	GuardBreak = Color3.fromRGB(255, 30, 30),
	Info = Color3.fromRGB(150, 220, 255),
}

local localPlayer = Players.LocalPlayer
local random = Random.new()

local shakeUntil = 0
local shakeDuration = 1
local shakeIntensity = 0
local shakeBound = false

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

local function effectPart(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "CombatFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	return part
end

local function burstLight(parent: Instance, color: Color3, brightness: number, range: number, duration: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(light, duration + 0.05)
end

local function emitSparks(parent: Attachment | BasePart, from: Color3, to: Color3, count: number, speed: NumberRange, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = ColorSequence.new(from, to)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(size, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = speed
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Drag = 6
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = parent
	emitter:Emit(count)
	Debris:AddItem(emitter, 0.6)
end

-- ── Sonido y texto ──

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

-- Texto flotante sobre un modelo. big = remate / eventos importantes.
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
	gui.Size = UDim2.fromOffset(180, if big then 48 else 34)
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

-- ── Cámara ──

--[[
	Sacudida de cámara. intensity en studs (0,1 suave · 0,25 golpe · 0,6 parry/guard break).
	Si ya hay una sacudida más fuerte en curso, se conserva la mayor.
]]
function CombatEffects.Shake(intensity: number, duration: number)
	local now = os.clock()
	local remaining = math.max(0, shakeUntil - now)
	local currentStrength = if remaining > 0 then shakeIntensity * (remaining / shakeDuration) else 0
	if intensity < currentStrength then
		return
	end
	shakeIntensity = intensity
	shakeDuration = duration
	shakeUntil = now + duration

	if shakeBound then
		return
	end
	shakeBound = true
	-- Antes que la cámara: el script de cámara usa el CameraOffset de este frame.
	RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value - 1, function()
		local character = localPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local left = shakeUntil - os.clock()
		if left <= 0 then
			if humanoid then
				humanoid.CameraOffset = Vector3.zero
			end
			RunService:UnbindFromRenderStep(SHAKE_BIND)
			shakeBound = false
			return
		end
		if humanoid then
			local m = shakeIntensity * (left / shakeDuration)
			humanoid.CameraOffset = Vector3.new(random:NextNumber(-m, m), random:NextNumber(-m, m), random:NextNumber(-m, m) * 0.5)
		end
	end)
end

-- ── Efectos de choque ──

-- Choque de espadas en un parry: destello de luz + chispas amarillas/naranjas.
function CombatEffects.ParrySpark(position: Vector3)
	local part = effectPart(position)
	burstLight(part, Color3.fromRGB(255, 200, 90), 10, 18, 0.3)
	emitSparks(part, Color3.fromRGB(255, 245, 160), Color3.fromRGB(255, 120, 20), 45, NumberRange.new(28, 46), 0.35)

	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 230, 140)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Size = Vector3.one * 0.6
	flash.CFrame = CFrame.new(position)
	flash.Parent = part
	TweenService:Create(flash, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 3.2,
		Transparency = 1,
	}):Play()

	Debris:AddItem(part, 1)
end

-- Guard break: el personaje se tiñe de rojo intenso, luz roja y chispas rojas.
function CombatEffects.GuardBreakBurst(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = COLORS.GuardBreak
	highlight.OutlineColor = Color3.fromRGB(255, 120, 120)
	highlight.FillTransparency = 0.05
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	TweenService:Create(highlight, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()
	Debris:AddItem(highlight, 0.65)

	local root = anchorPart(model)
	if root then
		local part = effectPart(root.Position)
		burstLight(part, COLORS.GuardBreak, 8, 16, 0.5)
		emitSparks(part, Color3.fromRGB(255, 90, 70), Color3.fromRGB(140, 0, 0), 60, NumberRange.new(18, 34), 0.5)
		Debris:AddItem(part, 1)
	end
end


-- ── Movimiento ──

--[[
	Dash local (el cliente es dueño de la física de su personaje): LinearVelocity en el plano XZ
	(Y libre: no vuela en rampas) con arranque explosivo que decae con fricción (curva cuadrática).
]]
function CombatEffects.DashMove(root: BasePart, direction: Vector3, speed: number, duration: number, maxAccel: number)
	local previous = root:FindFirstChild("CombatDash")
	if previous then
		previous:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatDash"

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
	mover.MaxForce = root.AssemblyMass * maxAccel
	mover.Parent = attachment
	attachment.Parent = root

	local elapsed = 0
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration or not attachment.Parent then
			if connection then
				connection:Disconnect()
			end
			attachment:Destroy()
			return
		end
		local falloff = (1 - elapsed / duration) ^ 2
		mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (speed * falloff)
	end)
end

return CombatEffects
