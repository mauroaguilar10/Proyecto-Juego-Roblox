--!strict
--[[
	WeaponArt — Modelos detallados de armas, armados con Parts. Los usan el servidor
	(WeaponModels: el arma en la mano) y el cliente (WeaponPreview: la ficha de la tienda),
	así se dibujan una sola vez.
	Owner: compartido (lo agregó Dev B para las armas nuevas de la tienda).

	Mismo contrato que WeaponModels.Build: Model "Weapon" con Attribute WeaponId y PrimaryPart
	"Grip" (invisible) en el punto de agarre. El arma se extiende hacia +Y; el filo/ancho va en Z
	y el grosor en X. Cada pieza queda ya en su CFrame (sirve en un ViewportFrame, sin física)
	y soldada al Grip con un Weld (sirve en la mano).
]]
local WeaponArt = {}

type Builder = {
	add: (name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material) -> BasePart,
	ball: (name: string, diameter: number, offset: CFrame, color: Color3, material: Enum.Material) -> BasePart,
	rod: (name: string, length: number, diameter: number, offset: CFrame, color: Color3, material: Enum.Material) -> BasePart,
	wedge: (name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material) -> BasePart,
	tip: (base: CFrame, width: number, length: number, thickness: number, color: Color3, material: Enum.Material) -> (),
}

-- `orient` gira el arma entera alrededor del agarre (por ejemplo, media vuelta en Y para
-- que el filo de un hacha mire hacia donde se golpea).
local function newBuilder(model: Model, grip: BasePart, orient: CFrame): Builder
	local function attach(p: BasePart, local_: CFrame)
		local offset = orient * local_
		p.CFrame = offset
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false -- invisible para el hit detection de CombatService
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		local weld = Instance.new("Weld")
		weld.Part0 = grip
		weld.Part1 = p
		weld.C0 = offset
		weld.Parent = p
		p.Parent = model
	end
	local b = {} :: Builder
	function b.add(name, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color, p.Material = name, size, color, material
		attach(p, offset)
		return p
	end
	function b.ball(name, diameter, offset, color, material)
		local p = b.add(name, Vector3.one * diameter, offset, color, material)
		;(p :: Part).Shape = Enum.PartType.Ball
		return p
	end
	-- Cilindro a lo largo de +Y (Roblox los acuesta en X).
	function b.rod(name, length, diameter, offset, color, material)
		local p = b.add(name, Vector3.new(length, diameter, diameter), offset * CFrame.Angles(0, 0, math.rad(90)), color, material)
		;(p :: Part).Shape = Enum.PartType.Cylinder
		return p
	end
	-- Cuña de Roblox: cara alta en +Z y pendiente que baja hacia -Z.
	function b.wedge(name, size, offset, color, material)
		local w = Instance.new("WedgePart")
		w.Name, w.Size, w.Color, w.Material = name, size, color, material
		attach(w, offset)
		return w
	end
	-- Punta simétrica hacia +Y de `base`, con el ancho en Z: dos cuñas espejadas.
	function b.tip(base, width, length, thickness, color, material)
		for _, side in { -1, 1 } do
			local cf = base * CFrame.new(0, length / 2, side * width / 4)
			if side > 0 then cf *= CFrame.Angles(0, math.pi, 0) end
			b.wedge("Punta", Vector3.new(thickness, length, width / 2), cf, color, material)
		end
	end
	return b
end

local function glow(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = color, range, brightness
	light.Shadows = false
	light.Parent = part
end

local function particles(part: BasePart, colors: ColorSequence, rate: number, size: number, speed: number, rise: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = colors
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, rise, 0)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Parent = part
end

-- ── Colmillo de Escarcha: espada larga de acero helado con runas que brillan ──
local function frostFang(b: Builder)
	local leather = Color3.fromRGB(38, 40, 52)
	local silver = Color3.fromRGB(205, 214, 224)
	local frost = Color3.fromRGB(196, 226, 242)
	local ice = Color3.fromRGB(120, 220, 255)
	b.rod("Empuñadura", 1.15, 0.22, CFrame.new(0, 0, 0), leather, Enum.Material.Fabric)
	for i = 0, 3 do
		b.rod("Atadura", 0.06, 0.25, CFrame.new(0, -0.42 + i * 0.28, 0), silver, Enum.Material.Metal)
	end
	b.ball("Pomo", 0.38, CFrame.new(0, -0.68, 0), silver, Enum.Material.Metal)
	b.ball("Gema", 0.2, CFrame.new(0, -0.68, 0) * CFrame.new(0.12, 0, 0), ice, Enum.Material.Neon)
	b.add("Guarda", Vector3.new(0.3, 0.22, 0.5), CFrame.new(0, 0.68, 0), silver, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		-- Gavilanes curvados hacia la hoja, con un cristal en la punta.
		b.add("Gavilan", Vector3.new(0.12, 0.13, 0.75), CFrame.new(0, 0.74, side * 0.55) * CFrame.Angles(side * math.rad(-18), 0, 0), silver, Enum.Material.Metal)
		b.add("Cristal", Vector3.new(0.12, 0.3, 0.12), CFrame.new(0, 0.95, side * 0.92) * CFrame.Angles(side * math.rad(25), 0, 0), ice, Enum.Material.Glass)
	end
	-- Hoja con lomo central, canal de runas y punta.
	local length, width = 3.7, 0.44
	local blade = b.add("Hoja", Vector3.new(0.08, length, width), CFrame.new(0, 0.8 + length / 2, 0), frost, Enum.Material.Metal)
	b.add("Lomo", Vector3.new(0.11, length, 0.1), CFrame.new(0, 0.8 + length / 2, 0), silver, Enum.Material.Metal)
	b.add("Runas", Vector3.new(0.12, length * 0.72, 0.05), CFrame.new(0, 0.95 + length * 0.36, 0), ice, Enum.Material.Neon)
	b.tip(CFrame.new(0, 0.8 + length, 0), width, 0.75, 0.08, frost, Enum.Material.Metal)
	b.tip(CFrame.new(0, 0.8 + length, 0), 0.1, 0.5, 0.11, silver, Enum.Material.Metal)
	glow(blade, ice, 7, 0.7)
	particles(blade, ColorSequence.new(Color3.fromRGB(220, 245, 255), ice), 7, 0.16, 0.6, -0.6)
end

-- ── Lanza del Alba: asta de marfil con anillos de oro y una moharra con disco solar ──
local function dawnSpear(b: Builder)
	local ivory = Color3.fromRGB(232, 222, 198)
	local gold = Color3.fromRGB(232, 184, 86)
	local sun = Color3.fromRGB(255, 196, 90)
	local steel = Color3.fromRGB(226, 228, 232)
	b.rod("Asta", 6.8, 0.18, CFrame.new(0, 1.6, 0), ivory, Enum.Material.Wood)
	for _, y in { -1.6, -0.3, 0.35, 1.8, 3.3, 4.6 } do
		b.rod("Anillo", 0.12, 0.23, CFrame.new(0, y, 0), gold, Enum.Material.Foil)
	end
	b.rod("Regaton", 0.35, 0.24, CFrame.new(0, -1.9, 0), gold, Enum.Material.Foil)
	b.tip(CFrame.new(0, -2.05, 0) * CFrame.Angles(0, 0, math.pi), 0.24, 0.3, 0.24, gold, Enum.Material.Foil)
	-- Cubo, disco solar detrás de la hoja y moharra en forma de hoja de laurel.
	b.rod("Cubo", 0.55, 0.27, CFrame.new(0, 5.2, 0), gold, Enum.Material.Foil)
	local disc = b.add("Sol", Vector3.new(0.06, 1, 1), CFrame.new(0, 5.55, 0), gold, Enum.Material.Foil)
	;(disc :: Part).Shape = Enum.PartType.Cylinder
	local core = b.add("Nucleo", Vector3.new(0.08, 0.45, 0.45), CFrame.new(0, 5.55, 0), sun, Enum.Material.Neon)
	;(core :: Part).Shape = Enum.PartType.Cylinder
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		b.add("Rayo", Vector3.new(0.05, 0.32, 0.07), CFrame.new(0, 5.55, 0) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.62, 0), gold, Enum.Material.Foil)
	end
	local head = b.add("Moharra", Vector3.new(0.07, 0.95, 0.56), CFrame.new(0, 5.95, 0), steel, Enum.Material.Metal)
	b.add("Nervio", Vector3.new(0.1, 1.5, 0.08), CFrame.new(0, 6.2, 0), gold, Enum.Material.Foil)
	b.tip(CFrame.new(0, 6.42, 0), 0.56, 0.95, 0.07, steel, Enum.Material.Metal)
	b.tip(CFrame.new(0, 5.47, 0) * CFrame.Angles(0, 0, math.pi), 0.56, 0.2, 0.07, steel, Enum.Material.Metal)
	glow(core, sun, 8, 1)
	particles(head, ColorSequence.new(Color3.fromRGB(255, 240, 180), sun), 5, 0.14, 0.8, 0.8)
end

-- ── Hacha del Coloso: gran hacha de hierro negro con grietas de brasa ──
local function colossusAxe(b: Builder)
	local haft = Color3.fromRGB(62, 44, 32)
	local iron = Color3.fromRGB(58, 58, 64)
	local edge = Color3.fromRGB(170, 172, 178)
	local ember = Color3.fromRGB(255, 110, 30)
	b.rod("Mango", 5.3, 0.26, CFrame.new(0, 1.55, 0), haft, Enum.Material.Wood)
	for _, y in { -0.5, 0.1, 2.4 } do
		b.rod("Fleje", 0.14, 0.31, CFrame.new(0, y, 0), iron, Enum.Material.Metal)
	end
	b.rod("Cuero", 0.9, 0.29, CFrame.new(0, -0.2, 0), Color3.fromRGB(70, 36, 26), Enum.Material.Fabric)
	b.tip(CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, math.pi), 0.3, 0.45, 0.3, iron, Enum.Material.Metal)
	-- Cabeza: ojo, hoja con barba y filo claro, pico trasero y punta superior.
	local y = 3.75
	b.add("Ojo", Vector3.new(0.42, 0.95, 0.46), CFrame.new(0, y, 0), iron, Enum.Material.Metal)
	local plate = b.add("Hoja", Vector3.new(0.13, 1.5, 1.15), CFrame.new(0, y, 0.8), iron, Enum.Material.Metal)
	-- Cuñas arriba y abajo que abren la hoja hacia el filo (forma de media luna).
	for _, side in { 1, -1 } do
		local cf = CFrame.new(0, y + side * 1, 0.8)
		if side < 0 then cf *= CFrame.Angles(0, 0, math.pi) end
		b.wedge("Barba", Vector3.new(0.13, 0.5, 1.15), cf, iron, Enum.Material.Metal)
	end
	b.add("Filo", Vector3.new(0.14, 2.45, 0.16), CFrame.new(0, y, 1.42), edge, Enum.Material.Metal)
	for i, angle in { 25, -35, 10 } do
		b.add("Grieta", Vector3.new(0.14, 0.55, 0.05), CFrame.new(0, y - 0.45 + i * 0.25, 0.55 + i * 0.18) * CFrame.Angles(math.rad(angle), 0, 0), ember, Enum.Material.Neon)
	end
	b.tip(CFrame.new(0, y, -0.23) * CFrame.Angles(math.rad(-90), 0, 0), 0.6, 0.75, 0.16, iron, Enum.Material.Metal)
	b.tip(CFrame.new(0, y + 0.47, 0), 0.32, 0.55, 0.2, iron, Enum.Material.Metal)
	glow(plate, ember, 6, 0.8)
	particles(plate, ColorSequence.new(Color3.fromRGB(255, 200, 90), ember), 6, 0.12, 1.2, 2)
end

-- ── Espada de madera: espada de práctica de novato, tallada a mano y atada con soga ──
local function woodenSword(b: Builder)
	local pine = Color3.fromRGB(190, 146, 94)
	local darkPine = Color3.fromRGB(128, 90, 56)
	local rope = Color3.fromRGB(200, 176, 128)
	local cloth = Color3.fromRGB(150, 128, 102)
	b.rod("Mango", 1.05, 0.24, CFrame.new(0, 0, 0), darkPine, Enum.Material.Wood)
	-- Venda de tela gastada en el mango, un poco torcida.
	for i = 0, 2 do
		b.add("Venda", Vector3.new(0.27, 0.16, 0.27), CFrame.new(0, -0.32 + i * 0.3, 0) * CFrame.Angles(0, 0, math.rad(8 - i * 7)), cloth, Enum.Material.Fabric)
	end
	b.add("Pomo", Vector3.new(0.3, 0.2, 0.3), CFrame.new(0, -0.6, 0), darkPine, Enum.Material.Wood)
	-- Guarda: un listón cruzado y atado con soga, sin metal.
	b.add("Guarda", Vector3.new(0.16, 0.16, 0.95), CFrame.new(0, 0.6, 0), darkPine, Enum.Material.Wood)
	for _, angle in { 40, -40 } do
		b.add("Soga", Vector3.new(0.2, 0.06, 0.34), CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(angle), 0, 0), rope, Enum.Material.Fabric)
	end
	-- Hoja de madera gruesa y sin filo, con la punta redondeada y una muesca de uso.
	local length, width = 2.9, 0.36
	b.add("Hoja", Vector3.new(0.16, length, width), CFrame.new(0, 0.68 + length / 2, 0), pine, Enum.Material.WoodPlanks)
	b.add("Muesca", Vector3.new(0.17, 0.12, 0.08), CFrame.new(0, 2.2, width / 2 - 0.03), darkPine, Enum.Material.Wood)
	b.add("Clavo", Vector3.new(0.18, 0.06, 0.06), CFrame.new(0, 0.6, 0.3), Color3.fromRGB(110, 106, 100), Enum.Material.Metal)
	b.tip(CFrame.new(0, 0.68 + length, 0), width, 0.22, 0.16, pine, Enum.Material.WoodPlanks)
end

-- ── Hoja de hierro: espada de armas sencilla y honesta; mejor que la de madera, sin lujos ──
local function ironBlade(b: Builder)
	local iron = Color3.fromRGB(158, 163, 170)
	local darkIron = Color3.fromRGB(92, 94, 100)
	local leather = Color3.fromRGB(92, 60, 38)
	b.rod("Empuñadura", 1.1, 0.22, CFrame.new(0, 0, 0), leather, Enum.Material.Fabric)
	for i = 0, 3 do
		b.rod("Tira", 0.05, 0.24, CFrame.new(0, -0.4 + i * 0.27, 0), Color3.fromRGB(70, 44, 28), Enum.Material.Fabric)
	end
	b.ball("Pomo", 0.32, CFrame.new(0, -0.66, 0), darkIron, Enum.Material.Metal)
	b.add("Guarda", Vector3.new(0.16, 0.16, 1.1), CFrame.new(0, 0.64, 0), darkIron, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		b.ball("Remate", 0.2, CFrame.new(0, 0.64, side * 0.56), darkIron, Enum.Material.Metal)
	end
	-- Hoja recta con un canal oscuro y punta en ángulo; acero gastado, sin brillo.
	local length, width = 3.5, 0.38
	b.add("Hoja", Vector3.new(0.07, length, width), CFrame.new(0, 0.72 + length / 2, 0), iron, Enum.Material.Metal)
	b.add("Canal", Vector3.new(0.08, length * 0.7, 0.07), CFrame.new(0, 0.85 + length * 0.35, 0), darkIron, Enum.Material.Metal)
	b.add("Ricasso", Vector3.new(0.09, 0.22, width), CFrame.new(0, 0.83, 0), darkIron, Enum.Material.Metal)
	b.tip(CFrame.new(0, 0.72 + length, 0), width, 0.55, 0.07, iron, Enum.Material.Metal)
end

-- ── Guadaña del Vacío: obsidiana y energía violeta, con estela al golpear ──
local function voidScythe(b: Builder)
	local obsidian = Color3.fromRGB(24, 14, 36)
	local voidMetal = Color3.fromRGB(46, 26, 70)
	local violet = Color3.fromRGB(170, 90, 255)
	local magenta = Color3.fromRGB(235, 90, 255)
	local silver = Color3.fromRGB(150, 140, 175)

	-- Asta de obsidiana con anillos y una espiral de runas que brillan.
	b.rod("Asta", 5.6, 0.2, CFrame.new(0, 1.6, 0), obsidian, Enum.Material.Basalt)
	for _, y in { -0.9, 0.4, 2.6, 4.1 } do
		b.rod("Anillo", 0.12, 0.26, CFrame.new(0, y, 0), silver, Enum.Material.Metal)
	end
	for i = 0, 9 do
		local a = i * math.rad(55)
		b.add("Runa", Vector3.new(0.05, 0.3, 0.05),
			CFrame.new(math.cos(a) * 0.105, 0.6 + i * 0.32, math.sin(a) * 0.105) * CFrame.Angles(0, -a, math.rad(25)), violet, Enum.Material.Neon)
	end
	-- Cristal del vacío en la base, con púa.
	b.ball("Cristal", 0.34, CFrame.new(0, -1.35, 0), magenta, Enum.Material.Neon)
	b.ball("Coraza", 0.46, CFrame.new(0, -1.35, 0), voidMetal, Enum.Material.Glass).Transparency = 0.45
	b.tip(CFrame.new(0, -1.55, 0) * CFrame.Angles(0, 0, math.pi), 0.22, 0.45, 0.22, voidMetal, Enum.Material.Metal)

	-- Cabeza: collar con un "ojo" de energía.
	b.add("Collar", Vector3.new(0.34, 0.5, 0.42), CFrame.new(0, 4.4, 0.05), voidMetal, Enum.Material.Metal)
	local eye = b.ball("Ojo", 0.3, CFrame.new(0.13, 4.4, 0.05), magenta, Enum.Material.Neon)
	b.ball("Iris", 0.42, CFrame.new(0.1, 4.4, 0.05), obsidian, Enum.Material.Glass).Transparency = 0.5

	-- Hoja curva hecha de tramos que se afinan, con filo de energía del lado de adentro.
	local points = {
		Vector2.new(4.35, 0.2), Vector2.new(4.6, 0.85), Vector2.new(4.58, 1.6),
		Vector2.new(4.3, 2.35), Vector2.new(3.78, 2.98), Vector2.new(3.1, 3.35),
	}
	local widths = { 0.78, 0.66, 0.52, 0.38, 0.22 }
	local root: BasePart? = nil
	local last: BasePart? = nil
	for i = 1, #points - 1 do
		local a, c = points[i], points[i + 1]
		local from, to = Vector3.new(0, a.X, a.Y), Vector3.new(0, c.X, c.Y)
		local dir = (to - from).Unit
		local inward = Vector3.new(0, -dir.Z, dir.Y) -- perpendicular dentro del plano YZ, hacia abajo
		local mid = (from + to) / 2
		local length = (to - from).Magnitude + 0.06
		local w = widths[i]
		local seg = b.add("Hoja", Vector3.new(0.09, w, length), CFrame.fromMatrix(mid, Vector3.xAxis, inward), voidMetal, Enum.Material.Metal)
		b.add("Filo", Vector3.new(0.11, 0.09, length), CFrame.fromMatrix(mid + inward * (w / 2), Vector3.xAxis, inward), violet, Enum.Material.Neon)
		-- Púas sobre el lomo de la hoja.
		if i <= 3 then
			b.tip(CFrame.fromMatrix(mid - inward * (w / 2), Vector3.xAxis, -inward), 0.3, 0.32, 0.09, voidMetal, Enum.Material.Metal)
		end
		root = root or seg
		last = seg
	end
	local tipBase = Vector3.new(0, points[#points].X, points[#points].Y)
	local tipDir = (tipBase - Vector3.new(0, points[#points - 1].X, points[#points - 1].Y)).Unit
	b.tip(CFrame.fromMatrix(tipBase, Vector3.xAxis, tipDir), 0.22, 0.45, 0.09, violet, Enum.Material.Neon)
	-- Contragancho corto hacia atrás.
	b.add("Gancho", Vector3.new(0.09, 0.28, 0.6), CFrame.new(0, 4.6, -0.42) * CFrame.Angles(math.rad(-35), 0, 0), voidMetal, Enum.Material.Metal)
	b.add("FiloGancho", Vector3.new(0.11, 0.07, 0.6), CFrame.new(0, 4.48, -0.45) * CFrame.Angles(math.rad(-35), 0, 0), violet, Enum.Material.Neon)

	-- Efectos: luz del ojo, jirones de vacío, humo oscuro y estela al moverla.
	glow(eye, magenta, 10, 1.6)
	if root and last then
		particles(root, ColorSequence.new(magenta, violet), 10, 0.22, 0.5, 0.4)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "HumoDelVacio"
		smoke.Color = ColorSequence.new(Color3.fromRGB(40, 10, 60), Color3.fromRGB(10, 0, 20))
		smoke.LightEmission = 0
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.6) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(0.8, 1.4)
		smoke.Rate = 8
		smoke.Speed = NumberRange.new(0.2, 0.5)
		smoke.SpreadAngle = Vector2.new(180, 180)
		smoke.Acceleration = Vector3.new(0, -0.5, 0)
		smoke.Parent = last
		local a0 = Instance.new("Attachment")
		a0.Name = "EstelaBase"
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "EstelaPunta"
		a1.Parent = last
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Color = ColorSequence.new(magenta, Color3.fromRGB(60, 10, 110))
		trail.Transparency = NumberSequence.new(0.15, 1)
		trail.LightEmission = 1
		trail.Lifetime = 0.25
		trail.MinLength = 0.05
		trail.FaceCamera = true
		trail.Parent = root
	end
end

local BUILDERS: { [string]: (Builder) -> () } = {
	WoodenSword = woodenSword,
	IronBlade = ironBlade,
	VoidScythe = voidScythe,
	FrostFang = frostFang,
	DawnSpear = dawnSpear,
	ColossusAxe = colossusAxe,
}

-- Armas con un lado de corte: media vuelta en Y para que el filo mire hacia donde se golpea.
local ORIENT: { [string]: CFrame } = {
	ColossusAxe = CFrame.Angles(0, math.pi, 0),
	VoidScythe = CFrame.Angles(0, math.pi, 0),
}

function WeaponArt.Has(weaponId: string): boolean
	return BUILDERS[weaponId] ~= nil
end

function WeaponArt.Build(weaponId: string): Model
	local model = Instance.new("Model")
	model.Name = "Weapon"
	model:SetAttribute("WeaponId", weaponId)
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.2, 0.2, 0.2)
	grip.Transparency = 1
	grip.CanCollide, grip.CanQuery, grip.CanTouch, grip.Massless = false, false, false, true
	grip.CFrame = CFrame.identity
	grip.Parent = model
	model.PrimaryPart = grip
	local build = BUILDERS[weaponId]
	if build then build(newBuilder(model, grip, ORIENT[weaponId] or CFrame.identity)) end
	return model
end

return WeaponArt
