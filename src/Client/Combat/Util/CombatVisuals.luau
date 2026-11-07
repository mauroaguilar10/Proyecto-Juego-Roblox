--!strict
--[[
	CombatVisuals — Efectos visuales del arma y del cuerpo según el estado de combate (solo cliente).
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como controlador.

	Todo es local y se dispara desde el Humanoid.CombatState de cada personaje, así que todos
	los jugadores ven los efectos de todos.

	  SlashTrail(character, color, duration) → estela en la hoja durante el tajo.
	  WindupGlint(character, heavy)           → destello en la punta al cargar (rojo = Heavy, hyperarmor).
	  ParryWindow(character, duration)        → la espada brilla blanco durante la ventana de parry.
	  SetGuardGlow(character, on)             → contorno azul en la espada mientras bloquea.
	  SetBrokenPulse(character, on)           → el cuerpo late en rojo mientras tiene la guardia rota.
	  Dash(character, direction, duration)    → imágenes residuales, polvo y (local) golpe de FOV.
	  HitSpark(position, color, count)        → chispas de impacto.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local TRAIL_LIFETIME = 0.18
local GUARD_COLOR = Color3.fromRGB(140, 200, 255)
local PARRY_COLOR = Color3.fromRGB(255, 255, 255)
local BROKEN_COLOR = Color3.fromRGB(255, 25, 25)
local GHOST_COLOR = Color3.fromRGB(130, 200, 255)
local GHOST_COUNT = 4
local GHOST_INTERVAL = 0.04
local GHOST_FADE = 0.3
local DASH_FOV_KICK = 8

type WeaponFx = {
	model: Model,
	trail: Trail,
	tip: Attachment,
	glow: Highlight,
}

local localPlayer = Players.LocalPlayer
local weaponFx: { [Model]: WeaponFx } = setmetatable({}, { __mode = "k" }) :: any
local guardOn: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local brokenFx: { [Model]: Highlight } = setmetatable({}, { __mode = "k" }) :: any
local trailTokens: { [Trail]: number } = setmetatable({}, { __mode = "k" }) :: any
local glowTweens: { [Highlight]: Tween } = setmetatable({}, { __mode = "k" }) :: any

local CombatVisuals = {}

-- ══════════════════ Helpers ══════════════════

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

local function burst(parent: Instance, texture: string, color: ColorSequence, count: number, settings: { [string]: any })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = color
	emitter.LightEmission = settings.lightEmission or 1
	emitter.LightInfluence = 0
	emitter.Size = settings.size or NumberSequence.new(0.4, 0)
	emitter.Transparency = settings.transparency or NumberSequence.new(0, 1)
	emitter.Lifetime = settings.lifetime or NumberRange.new(0.15, 0.35)
	emitter.Speed = settings.speed or NumberRange.new(20, 35)
	emitter.SpreadAngle = settings.spread or Vector2.new(180, 180)
	emitter.Acceleration = settings.acceleration or Vector3.new(0, -40, 0)
	emitter.Drag = settings.drag or 5
	emitter.EmissionDirection = settings.direction or Enum.NormalId.Top
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = parent
	emitter:Emit(count)
	Debris:AddItem(emitter, 1.5)
end

-- La parte más larga del arma (la hoja) y su eje largo.
local function findBlade(model: Model): (BasePart?, Vector3)
	local best: BasePart? = nil
	local bestLength = 0
	local axis = Vector3.yAxis
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 1 then
			continue
		end
		local size = part.Size
		local length = math.max(size.X, size.Y, size.Z)
		if length > bestLength then
			bestLength = length
			best = part
			axis = if length == size.Y then Vector3.yAxis elseif length == size.Z then Vector3.zAxis else Vector3.xAxis
		end
	end
	return best, axis
end

-- Prepara (una vez por modelo de arma) la estela, la punta y el brillo.
local function getWeaponFx(character: Model): WeaponFx?
	local model = character:FindFirstChild("Weapon")
	if not model or not model:IsA("Model") then
		return nil
	end
	local existing = weaponFx[model]
	if existing and existing.trail.Parent then
		return existing
	end

	local blade, axis = findBlade(model)
	if not blade then
		return nil
	end
	local half = math.max(blade.Size.X, blade.Size.Y, blade.Size.Z) / 2

	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = -axis * half * 0.6
	base.Parent = blade

	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.Position = axis * half
	tip.Parent = blade

	local trail = Instance.new("Trail")
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = TRAIL_LIFETIME
	trail.MinLength = 0
	trail.FaceCamera = false
	trail.LightEmission = 0.7
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, 0.3)
	trail.Enabled = false
	trail.Parent = blade

	local glow = Instance.new("Highlight")
	glow.Name = "CombatGlow"
	glow.Adornee = model
	glow.FillTransparency = 1
	glow.OutlineTransparency = 1
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = model

	local fx: WeaponFx = { model = model, trail = trail, tip = tip, glow = glow }
	weaponFx[model] = fx
	return fx
end

-- ══════════════════ Arma ══════════════════

function CombatVisuals.SlashTrail(character: Model, color: Color3, duration: number)
	local fx = getWeaponFx(character)
	if not fx then
		return
	end
	local trail = fx.trail
	local token = (trailTokens[trail] or 0) + 1
	trailTokens[trail] = token
	trail.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.5))
	trail.Enabled = true
	task.delay(duration, function()
		if trailTokens[trail] == token and trail.Parent then
			trail.Enabled = false
		end
	end)
end

function CombatVisuals.WindupGlint(character: Model, heavy: boolean)
	local fx = getWeaponFx(character)
	if not fx then
		return
	end
	local color = if heavy then Color3.fromRGB(255, 50, 30) else Color3.fromRGB(255, 255, 230)
	burst(fx.tip, SPARK_TEXTURE, ColorSequence.new(color), 1, {
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.3, if heavy then 3.2 else 2.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		lifetime = NumberRange.new(0.3),
		speed = NumberRange.new(0),
		acceleration = Vector3.zero,
		transparency = NumberSequence.new(0, 0.2),
	})
	if heavy then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Brightness = 4
		light.Range = 10
		light.Parent = fx.tip
		TweenService:Create(light, TweenInfo.new(0.35), { Brightness = 0 }):Play()
		Debris:AddItem(light, 0.4)
	end
end

local function setGlow(fx: WeaponFx, color: Color3, fill: number, outline: number, fade: number?)
	local glow = fx.glow
	local running = glowTweens[glow]
	if running then
		running:Cancel()
		glowTweens[glow] = nil
	end
	glow.FillColor = color
	glow.OutlineColor = color
	glow.FillTransparency = fill
	glow.OutlineTransparency = outline
	if fade then
		local owner = fx.model.Parent
		local guarded = owner ~= nil and owner:IsA("Model") and guardOn[owner] == true
		local tween = TweenService:Create(glow, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FillTransparency = if guarded then 0.85 else 1,
			OutlineTransparency = if guarded then 0.2 else 1,
		})
		glowTweens[glow] = tween
		tween:Play()
	end
end

function CombatVisuals.ParryWindow(character: Model, duration: number)
	local fx = getWeaponFx(character)
	if not fx then
		return
	end
	setGlow(fx, PARRY_COLOR, 0.2, 0, duration)
	burst(fx.tip, SPARK_TEXTURE, ColorSequence.new(PARRY_COLOR), 6, {
		size = NumberSequence.new(0.25, 0),
		speed = NumberRange.new(6, 12),
		lifetime = NumberRange.new(0.15, 0.25),
	})
end

function CombatVisuals.SetGuardGlow(character: Model, on: boolean)
	guardOn[character] = on
	local fx = getWeaponFx(character)
	if not fx then
		return
	end
	if on then
		setGlow(fx, GUARD_COLOR, 0.85, 0.2)
	else
		setGlow(fx, GUARD_COLOR, 1, 1)
	end
end

-- ══════════════════ Cuerpo ══════════════════

function CombatVisuals.SetBrokenPulse(character: Model, on: boolean)
	local current = brokenFx[character]
	if current then
		current:Destroy()
		brokenFx[character] = nil
	end
	if not on then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "PostureBroken"
	highlight.FillColor = BROKEN_COLOR
	highlight.OutlineColor = BROKEN_COLOR
	highlight.FillTransparency = 0.25
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	TweenService:Create(highlight, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		FillTransparency = 0.75,
	}):Play()
	brokenFx[character] = highlight
	Debris:AddItem(highlight, 5) -- por si nunca llega el fin del estado
end

-- Copia fantasma del personaje en su posición actual que se desvanece.
local function afterimage(character: Model)
	local folder = Instance.new("Folder")
	folder.Name = "DashGhost"
	for _, part in character:GetDescendants() do
		if not part:IsA("BasePart") or part.Name == "HumanoidRootPart" or part.Transparency >= 0.9 then
			continue
		end
		local ok, ghost = pcall(function()
			return part:Clone()
		end)
		if not ok or not ghost then
			continue
		end
		local copy = ghost :: BasePart
		copy:ClearAllChildren()
		if copy:IsA("MeshPart") then
			copy.TextureID = ""
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.CastShadow = false
		copy.Material = Enum.Material.Neon
		copy.Color = GHOST_COLOR
		copy.Transparency = 0.55
		copy.CFrame = part.CFrame
		copy.Parent = folder
		TweenService:Create(copy, TweenInfo.new(GHOST_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	end
	folder.Parent = workspace
	Debris:AddItem(folder, GHOST_FADE + 0.05)
end

function CombatVisuals.Dash(character: Model, direction: Vector3, duration: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not humanoid or not root then
		return
	end

	-- Imágenes residuales durante el dash.
	task.spawn(function()
		for _ = 1, GHOST_COUNT do
			if not character.Parent then
				return
			end
			afterimage(character)
			task.wait(GHOST_INTERVAL)
		end
	end)

	-- Polvo en los pies, despedido hacia atrás.
	local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - 0.2, 0)
	local dust = effectPart(feet)
	if direction.Magnitude > 0.1 then
		dust.CFrame = CFrame.lookAt(feet, feet - direction)
	end
	burst(dust, SMOKE_TEXTURE, ColorSequence.new(Color3.fromRGB(210, 205, 195)), 14, {
		lightEmission = 0,
		size = NumberSequence.new(1, 3.5),
		transparency = NumberSequence.new(0.45, 1),
		lifetime = NumberRange.new(0.35, 0.6),
		speed = NumberRange.new(8, 16),
		spread = Vector2.new(35, 15),
		acceleration = Vector3.new(0, 2, 0),
		drag = 4,
		direction = Enum.NormalId.Front,
	})
	Debris:AddItem(dust, 1.2)

	-- Golpe de FOV solo para el que hace el dash.
	if character == localPlayer.Character then
		local camera = workspace.CurrentCamera
		if camera then
			local baseFov = camera.FieldOfView
			TweenService:Create(camera, TweenInfo.new(duration * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = baseFov + DASH_FOV_KICK,
			}):Play()
			task.delay(duration * 0.3, function()
				TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					FieldOfView = baseFov,
				}):Play()
			end)
		end
	end
end

function CombatVisuals.HitSpark(position: Vector3, color: Color3, count: number)
	local part = effectPart(position)
	burst(part, SPARK_TEXTURE, ColorSequence.new(Color3.new(1, 1, 1), color), count, {
		size = NumberSequence.new(0.3, 0),
		speed = NumberRange.new(15, 28),
	})
	Debris:AddItem(part, 1)
end

return CombatVisuals
