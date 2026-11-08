--!strict
--[[
	CombatFx — Efectos grandes y visibles de los ataques (solo cliente).
	Owner: Dev B (Economía) — complementa CombatVisuals (estela/brillos de Dev A).

	  SlashArc(root, style, sweep, range) → medialuna de neón que recorre el corte frente al personaje.
	  Charge(character, style, duration)   → aura de carga en los pies (armas especiales).
	  Finisher(character, style)            → remate del golpe 3 (onda expansiva, pilar de fuego, anillo del vacío).
	  Impact(position, style, big)          → estallido al conectar: esfera, onda, chispas, luz y
	                                          el extra del arma (fuego, rayo, implosión, escarcha).
	Todo son partes ancladas sin colisión dentro de workspace.CombatFx, con Debris.
]]
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CombatStyles = require(script.Parent:WaitForChild("CombatStyles"))

type Style = CombatStyles.Style

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local ARC_FADE = 0.24
local random = Random.new()

local CombatFx = {}

local folder: Folder? = nil
local function container(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "CombatFx"
	f.Parent = workspace
	folder = f
	return f
end

local function neon(size: Vector3, cframe: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color, p.Transparency = color, transparency
	if shape then p.Shape = shape end
	p.Size, p.CFrame = size, cframe
	p.Parent = container()
	return p
end

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function fade(part: BasePart, time: number, extra: { [string]: any }?)
	local goal: { [string]: any } = { Transparency = 1 }
	if extra then
		for k, v in extra do goal[k] = v end
	end
	tween(part, time, goal)
	Debris:AddItem(part, time + 0.05)
end

local function flashLight(parent: BasePart, color: Color3, brightness: number, range: number, time: number)
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range, l.Shadows = color, brightness, range, false
	l.Parent = parent
	tween(l, time, { Brightness = 0 })
end

type EmitOpts = { size: NumberSequence?, lifetime: NumberRange?, speed: NumberRange?, accel: Vector3?, light: number?, drag: number?, spread: Vector2?, transparency: NumberSequence? }
local function emit(parent: BasePart, texture: string, colors: ColorSequence, count: number, o: EmitOpts)
	local e = Instance.new("ParticleEmitter")
	e.Texture, e.Color = texture, colors
	e.LightEmission, e.LightInfluence = o.light or 1, 0
	e.Size = o.size or NumberSequence.new(0.5, 0)
	e.Transparency = o.transparency or NumberSequence.new(0, 1)
	e.Lifetime = o.lifetime or NumberRange.new(0.2, 0.45)
	e.Speed = o.speed or NumberRange.new(18, 34)
	e.SpreadAngle = o.spread or Vector2.new(180, 180)
	e.Acceleration = o.accel or Vector3.new(0, -35, 0)
	e.Drag = o.drag or 4
	e.Rate, e.Enabled = 0, false
	e.Parent = parent
	e:Emit(count)
end

-- Punto invisible para colgar luces y partículas.
local function anchor(position: Vector3, life: number): Part
	local p = neon(Vector3.one * 0.2, CFrame.new(position), Color3.new(1, 1, 1), 1)
	Debris:AddItem(p, life)
	return p
end

local function groundBelow(root: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { container() }
	if root.Parent then table.insert(exclude, root.Parent) end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	return if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
end

-- Anillo plano (cilindro acostado) que se expande y desaparece.
local function ring(center: Vector3, color: Color3, from: number, to: number, time: number, thickness: number?)
	local h = thickness or 0.12
	local p = neon(Vector3.new(h, from, from), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, 0.15, Enum.PartType.Cylinder)
	fade(p, time, { Size = Vector3.new(h, to, to) })
end

-- Rayo en zigzag entre dos puntos (dos destellos seguidos).
local function lightning(from: Vector3, to: Vector3, color: Color3)
	local function bolt()
		local points = { from }
		local n = 7
		local dir = to - from
		local side = dir:Cross(Vector3.yAxis)
		if side.Magnitude < 0.01 then side = Vector3.xAxis end
		side = side.Unit
		local other = dir:Cross(side).Unit
		for i = 1, n - 1 do
			local t = i / n
			local amp = math.sin(math.pi * t) * 1.4
			table.insert(points, from + dir * t + side * random:NextNumber(-amp, amp) + other * random:NextNumber(-amp, amp))
		end
		table.insert(points, to)
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local len = (b - a).Magnitude
			local cf = CFrame.lookAt((a + b) / 2, b)
			fade(neon(Vector3.new(0.3, 0.3, len + 0.15), cf, color, 0.2), 0.16)
			fade(neon(Vector3.new(0.12, 0.12, len + 0.1), cf, Color3.new(1, 1, 1), 0), 0.12)
		end
	end
	bolt()
	task.delay(0.06, bolt)
end

-- ══════════════════ Arco de corte ══════════════════

local A = math.rad(80)
local SWEEPS: { [string]: { u: Vector3, a0: number, a1: number } } = {
	V = { u = Vector3.yAxis, a0 = A, a1 = -A },
	VUp = { u = Vector3.yAxis, a0 = -A, a1 = A },
	H = { u = Vector3.xAxis, a0 = A, a1 = -A },
	HRev = { u = Vector3.xAxis, a0 = -A, a1 = A },
	D = { u = Vector3.new(1, 1, 0).Unit, a0 = A, a1 = -A },
	DL = { u = Vector3.new(-1, 1, 0).Unit, a0 = A, a1 = -A },
	DRev = { u = Vector3.new(1, 1, 0).Unit, a0 = -A, a1 = A },
	Spin = { u = -Vector3.xAxis, a0 = 0, a1 = math.pi * 2 },
}

function CombatFx.SlashArc(root: BasePart, style: Style, sweep: string, range: number)
	local spec = SWEEPS[sweep] or SWEEPS.V
	local spinning = sweep == "Spin"
	local radius = math.clamp(range * 0.55, 3, 6) * (if spinning then 1.1 else 1)
	local center = root.CFrame * CFrame.new(0, if spinning then -0.4 else 0.4, 0)
	local forward = -Vector3.zAxis
	local segments = if spinning then 26 else 13
	local sweepTime = if spinning then 0.3 else 0.09
	local step = (spec.a1 - spec.a0) / segments
	local segLen = radius * math.abs(step) * 1.3

	for i = 0, segments do
		local t = i / segments
		task.delay(t * sweepTime, function()
			local a = spec.a0 + step * i
			local localPos = (spec.u * math.sin(a) + forward * math.cos(a)) * radius
			localPos = Vector3.new(localPos.X, localPos.Y * 0.8, localPos.Z)
			local tangent = (spec.u * math.cos(a) - forward * math.sin(a)) * math.sign(step)
			local pos = center:PointToWorldSpace(localPos)
			local tw = center:VectorToWorldSpace(tangent).Unit
			local rw = center:VectorToWorldSpace(localPos).Unit
			local taper = if spinning then 0.7 else math.sin(math.pi * t)
			local width = (0.25 + 1.1 * taper) * style.width
			local cf = CFrame.lookAt(pos, pos + tw, rw)
			fade(neon(Vector3.new(0.08, width, segLen), cf, style.color, 0.1), ARC_FADE, { Size = Vector3.new(0.02, width * 0.4, segLen) })
			fade(neon(Vector3.new(0.12, width * 0.35, segLen), cf, style.core, 0), ARC_FADE * 0.7)
			if i == math.floor(segments / 2) then
				flashLight(anchor(pos, 0.5), style.color, 3, 12, 0.3)
			end
			if style.kind ~= "Normal" and i % 3 == 0 then
				local p = anchor(pos, 1.2)
				if style.kind == "Fire" then
					emit(p, FIRE, ColorSequence.new(style.core, style.color), 4, { size = NumberSequence.new(1.2, 0), speed = NumberRange.new(2, 5), accel = Vector3.new(0, 8, 0), lifetime = NumberRange.new(0.3, 0.6) })
				else
					emit(p, SPARK, ColorSequence.new(style.core, style.color), 3, { size = NumberSequence.new(0.4, 0), speed = NumberRange.new(4, 9) })
				end
			end
		end)
	end
end

-- ══════════════════ Carga y remates ══════════════════

function CombatFx.Charge(character: Model, style: Style, duration: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not root then return end
	local ground = groundBelow(root) + Vector3.new(0, 0.1, 0)
	local p = neon(Vector3.new(0.08, 7, 7), CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)), style.color, 0.9, Enum.PartType.Cylinder)
	tween(p, duration, { Size = Vector3.new(0.08, 2.5, 2.5), Transparency = 0.25 }, Enum.EasingStyle.Quad)
	task.delay(duration, function() fade(p, 0.15) end)
	Debris:AddItem(p, duration + 0.3)
	local a = anchor(root.Position, duration + 0.6)
	flashLight(a, style.color, 2, 10, duration + 0.2)
	emit(a, if style.kind == "Fire" then FIRE else SPARK, ColorSequence.new(style.core, style.color), 12, {
		size = NumberSequence.new(0.6, 0), speed = NumberRange.new(-6, -3), lifetime = NumberRange.new(0.3, 0.5), accel = Vector3.zero,
	})
end

function CombatFx.Finisher(character: Model, style: Style)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = if humanoid then humanoid.RootPart else nil
	if not root or not style.finisher then return end
	local front = root.Position + root.CFrame.LookVector * 3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, container() }
	local hit = workspace:Raycast(front + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local ground = (if hit then hit.Position else groundBelow(root)) + Vector3.new(0, 0.15, 0)
	local a = anchor(ground + Vector3.new(0, 1, 0), 1.5)

	if style.finisher == "Shockwave" then
		ring(ground, style.color, 1, 18, 0.45, 0.25)
		ring(ground, style.core, 1, 10, 0.3, 0.15)
		flashLight(a, style.color, 6, 20, 0.5)
		emit(a, SMOKE, ColorSequence.new(Color3.fromRGB(200, 195, 185)), 18, {
			light = 0, size = NumberSequence.new(1.5, 4), transparency = NumberSequence.new(0.4, 1),
			speed = NumberRange.new(12, 22), spread = Vector2.new(90, 5), accel = Vector3.new(0, 2, 0), lifetime = NumberRange.new(0.4, 0.7),
		})
		if style.kind == "Storm" then
			for i = 0, 2 do
				local angle = i / 3 * math.pi * 2 + random:NextNumber(0, 1)
				local spot = ground + Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 4)
				task.delay(i * 0.05, lightning, spot + Vector3.new(random:NextNumber(-2, 2), 20, random:NextNumber(-2, 2)), spot, style.color)
			end
		end
	elseif style.finisher == "FirePillar" then
		local pillar = neon(Vector3.new(10, 2.5, 2.5), CFrame.new(ground + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.rad(90)), style.color, 0.2, Enum.PartType.Cylinder)
		fade(pillar, 0.5, { Size = Vector3.new(14, 0.5, 0.5) })
		ring(ground, style.color, 1, 12, 0.4, 0.2)
		flashLight(a, style.color, 7, 22, 0.6)
		emit(a, FIRE, ColorSequence.new(style.core, style.color), 35, {
			size = NumberSequence.new(2, 0), speed = NumberRange.new(10, 22), spread = Vector2.new(20, 20),
			accel = Vector3.new(0, 20, 0), lifetime = NumberRange.new(0.4, 0.8),
		})
	elseif style.finisher == "VoidRing" then
		local center = root.Position - Vector3.new(0, 0.5, 0)
		ring(center, style.color, 2, 22, 0.5, 0.3)
		ring(center, style.core, 2, 14, 0.35, 0.15)
		local orb = neon(Vector3.one * 8, CFrame.new(root.Position), Color3.fromRGB(40, 0, 70), 0.6, Enum.PartType.Ball)
		fade(orb, 0.4, { Size = Vector3.one * 0.5 })
		flashLight(a, style.color, 6, 22, 0.6)
	end
end

-- ══════════════════ Impacto ══════════════════

function CombatFx.Impact(position: Vector3, style: Style, big: boolean)
	local size = if big then 5.5 else 3.5
	fade(neon(Vector3.one * 0.6, CFrame.new(position), style.core, 0.05, Enum.PartType.Ball), 0.18, { Size = Vector3.one * size })
	fade(neon(Vector3.one * 0.6, CFrame.new(position), style.color, 0.3, Enum.PartType.Ball), 0.25, { Size = Vector3.one * size * 1.3 })
	ring(position, style.color, 0.5, size * 2.2, 0.25)
	local a = anchor(position, 1.5)
	flashLight(a, style.color, if big then 8 else 5, if big then 20 else 14, 0.3)
	emit(a, SPARK, ColorSequence.new(style.core, style.color), if big then 45 else 28, { size = NumberSequence.new(0.55, 0) })

	if style.kind == "Fire" then
		emit(a, FIRE, ColorSequence.new(style.core, style.color), if big then 30 else 16, {
			size = NumberSequence.new(1.8, 0), speed = NumberRange.new(6, 14), accel = Vector3.new(0, 14, 0), lifetime = NumberRange.new(0.3, 0.6),
		})
	elseif style.kind == "Storm" then
		lightning(position + Vector3.new(random:NextNumber(-3, 3), 18, random:NextNumber(-3, 3)), position, style.color)
		for _ = 1, 3 do
			local dir = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.3, 0.6), random:NextNumber(-1, 1)).Unit
			lightning(position, position + dir * random:NextNumber(2, 3.5), style.color)
		end
	elseif style.kind == "Void" then
		local orb = neon(Vector3.one * (size * 1.6), CFrame.new(position), Color3.fromRGB(30, 0, 50), 0.55, Enum.PartType.Ball)
		fade(orb, 0.3, { Size = Vector3.one * 0.3 })
		emit(a, SMOKE, ColorSequence.new(Color3.fromRGB(60, 10, 90)), 12, {
			light = 0, size = NumberSequence.new(1, 2.5), transparency = NumberSequence.new(0.3, 1), speed = NumberRange.new(-8, -4),
			accel = Vector3.zero, lifetime = NumberRange.new(0.3, 0.5),
		})
	elseif style.kind == "Frost" then
		emit(a, SPARK, ColorSequence.new(Color3.new(1, 1, 1), style.color), 20, {
			size = NumberSequence.new(0.9, 0), speed = NumberRange.new(4, 10), accel = Vector3.new(0, -10, 0), lifetime = NumberRange.new(0.5, 0.9),
		})
	end
end

return CombatFx
