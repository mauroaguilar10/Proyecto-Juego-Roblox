--!strict
--[[
	ArmorArt — Aspecto de cada pieza de armadura, armado sobre el cuerpo del personaje.
	Owner: Dev B (Economía). Lo usan ArmorService (en el personaje) y ArmorController /
	PremiumShopController (maniquí de las fichas).

	Build(pieceId, slot, body) devuelve un Model "Armadura_<Slot>" con piezas soldadas a las partes
	del cuerpo (`body` es el personaje o un maniquí con las mismas partes). Todas las medidas son
	relativas al tamaño de cada parte, así la armadura se ajusta a avatares de distinto tamaño.

	Estilo: placas ajustadas a cada parte (como el avatar en bloques), con bordes, remaches,
	hombreras en capas y detalles redondeados. Formas disponibles:
	  "Box"   → placa (por defecto).
	  "Ball"  → elipsoide (Part + SpecialMesh Sphere): cúpulas, hombreras, punteras.
	  "Cyl"   → cilindro, eje vertical por defecto (bandas, cuellos, discos con `rot`).
	  "Spike" → púa piramidal (cuatro WedgePart cruzadas), base = scale.X, alto = scale.Y.
	Pensado para R15; en R6 usa las partes equivalentes (queda aproximado). El frente es -Z.
]]
local ArmorArt = {}

local R6: { [string]: string } = {
	UpperTorso = "Torso", LowerTorso = "Torso",
	LeftUpperArm = "Left Arm", RightUpperArm = "Right Arm",
	LeftUpperLeg = "Left Leg", LeftLowerLeg = "Left Leg", LeftFoot = "Left Leg",
	RightUpperLeg = "Right Leg", RightLowerLeg = "Right Leg", RightFoot = "Right Leg",
}

type Opts = { shape: string?, rot: CFrame?, transparency: number?, reflect: number? }
type Plate = (bodyName: string, name: string, scale: Vector3, offset: Vector3, color: Color3, material: Enum.Material, opts: Opts?) -> BasePart?

local function newPlate(model: Model, body: Instance): Plate
	return function(bodyName, name, scale, offset, color, material, opts)
		local part = body:FindFirstChild(bodyName) or body:FindFirstChild(R6[bodyName] or "")
		if not part or not part:IsA("BasePart") then return nil end
		local o: Opts = opts or {}
		local shape = o.shape or "Box"
		local s = part.Size
		local base = CFrame.new(s * offset) * (o.rot or CFrame.identity)

		local function make(className: string, size: Vector3, c0: CFrame): BasePart
			local p = Instance.new(className) :: BasePart
			p.Name, p.Size = name, size
			p.Color, p.Material = color, material
			p.Transparency = o.transparency or 0
			p.Reflectance = o.reflect or 0
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			p.CFrame = part.CFrame * c0
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1, weld.C0 = part, p, c0
			weld.Parent = p
			p.Parent = model
			return p
		end

		if shape == "Spike" then
			-- Dos pares de cuñas espalda con espalda, cruzados: punta en +Y.
			local b, h = math.min(s.X, s.Z) * scale.X, s.Y * scale.Y
			local first: BasePart? = nil
			for _, turn in { 0, math.pi / 2 } do
				local r = base * CFrame.Angles(0, turn, 0)
				local a = make("WedgePart", Vector3.new(b, h, b / 2), r * CFrame.new(0, 0, -b / 4))
				make("WedgePart", Vector3.new(b, h, b / 2), r * CFrame.new(0, 0, b / 4) * CFrame.Angles(0, math.pi, 0))
				first = first or a
			end
			return first
		elseif shape == "Cyl" then
			-- Alto relativo a Y, diámetro relativo al lado más ancho de la parte.
			local d = math.max(s.X, s.Z) * scale.X
			local p = make("Part", Vector3.new(s.Y * scale.Y, d, d), base * CFrame.Angles(0, 0, math.rad(90)))
			;(p :: Part).Shape = Enum.PartType.Cylinder
			return p
		end
		local p = make(if shape == "Wedge" then "WedgePart" else "Part", s * scale, base)
		if shape == "Ball" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		return p
	end
end

local V = Vector3.new
local BALL: Opts = { shape = "Ball" }
local CYL: Opts = { shape = "Cyl" }
local SIDES = { { "Left", -1 }, { "Right", 1 } }
local NEON = Enum.Material.Neon
local DIAMOND = CFrame.Angles(0, 0, math.rad(45))
local FACING = CFrame.Angles(math.rad(90), 0, 0) -- con "Cyl": disco que mira al frente
local SIDEWAYS = CFrame.Angles(0, 0, math.rad(-90)) -- con "Cyl": disco que mira al costado

local function glow(part: BasePart?, color: Color3, range: number, brightness: number?)
	if not part then return end
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, brightness or 1.2, false
	l.Parent = part
end

local function sparkles(part: BasePart?, colors: ColorSequence, rate: number, size: number, rise: number)
	if not part then return end
	local e = Instance.new("ParticleEmitter")
	e.Color, e.LightEmission = colors, 0.8
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Rate, e.Speed = rate, NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, rise, 0)
	e.Parent = part
end

local function smoke(part: BasePart?, color: Color3, rate: number)
	if not part then return end
	local e = Instance.new("ParticleEmitter")
	e.Color, e.LightEmission = ColorSequence.new(color), 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.8) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate, e.Speed = rate, NumberRange.new(0.2, 0.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -0.4, 0)
	e.Parent = part
end

-- ── Set de cuero (gorro de gajos, chaleco con correas y bandolera, pantalón con rodilleras y botas) ──

local LEATHER = Enum.Material.Leather
local METAL = Enum.Material.Metal
local L = {
	main = Color3.fromRGB(166, 94, 50), -- cuero claro
	pad = Color3.fromRGB(142, 78, 42), -- paneles y rodilleras
	dark = Color3.fromRGB(92, 54, 32), -- hombreras, cinturones, botas
	darker = Color3.fromRGB(70, 42, 26),
	strap = Color3.fromRGB(204, 148, 88), -- correas de los muslos
	stitch = Color3.fromRGB(234, 184, 116), -- costuras
	sleeve = Color3.fromRGB(52, 42, 38),
	sole = Color3.fromRGB(40, 30, 22),
	iron = Color3.fromRGB(176, 176, 182),
	brass = Color3.fromRGB(214, 170, 78),
}

-- Hebilla rectangular: marco de metal con el hueco oscuro adelante (z = frente de la superficie).
local function buckle(plate: Plate, bodyName: string, size: Vector3, offset: Vector3, metal: Color3, opts: Opts?)
	plate(bodyName, "Hebilla", size, offset, metal, METAL, opts)
	plate(bodyName, "Hebilla", V(size.X * 0.55, size.Y * 0.5, size.Z * 1.2), offset, L.darker, LEATHER, opts)
end

local function leatherHelm(plate: Plate)
	-- Gorro de gajos: cúpula, 4 costuras en relieve, botón arriba, banda con remaches y orejeras.
	plate("Head", "Cupula", V(1.12, 0.8, 1.12), V(0, 0.3, 0.02), L.main, LEATHER, BALL)
	for i = 0, 3 do
		plate("Head", "Gajo", V(0.05, 0.82, 1.15), V(0, 0.31, 0.02), L.dark, LEATHER, { shape = "Ball", rot = CFrame.Angles(0, math.rad(i * 45), 0) })
	end
	plate("Head", "Boton", V(0.16, 0.1, 0.16), V(0, 0.71, 0.02), L.dark, LEATHER, BALL)
	plate("Head", "Banda", V(1.1, 0.14, 0), V(0, 0.17, 0.02), L.main, LEATHER, CYL)
	for _, y in { 0.105, 0.235 } do
		plate("Head", "Costura", V(1.11, 0.015, 0), V(0, y, 0.02), L.stitch, LEATHER, CYL)
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		plate("Head", "Remache", V(0.07, 0.07, 0.07), V(math.sin(a) * 0.56, 0.17, 0.02 - math.cos(a) * 0.56), L.iron, METAL, BALL)
	end
	for _, side in SIDES do
		local x = side[2] :: number
		local tilt = { rot = CFrame.Angles(0, 0, x * math.rad(4)) }
		plate("Head", "Orejera", V(0.08, 0.52, 0.46), V(x * 0.56, -0.12, 0.06), L.main, LEATHER, tilt)
		plate("Head", "Orejera", V(0.08, 0.24, 0.46), V(x * 0.565, -0.38, 0.06), L.main, LEATHER, BALL)
		plate("Head", "Costura", V(0.085, 0.012, 0.4), V(x * 0.56, -0.3, 0.06), L.stitch, LEATHER, tilt)
		plate("Head", "Remache", V(0.06, 0.06, 0.06), V(x * 0.605, -0.08, 0.06), L.iron, METAL, BALL)
	end
	plate("Head", "Nuca", V(0.84, 0.42, 0.08), V(0, -0.08, 0.56), L.main, LEATHER, { rot = CFrame.Angles(math.rad(-8), 0, 0) })
end

local function leatherChest(plate: Plate)
	-- Chaleco: dos paneles cosidos, cuello alto y tres cierres de correa con hebilla.
	plate("UpperTorso", "Chaleco", V(1.04, 0.98, 1.08), V(0, 0, 0), L.main, LEATHER)
	for _, z in { -0.545, 0.545 } do
		plate("UpperTorso", "Union", V(0.012, 0.96, 0.01), V(0, 0, z), L.darker, LEATHER)
	end
	for _, x in { -0.1, 0.1, -0.47, 0.47 } do
		plate("UpperTorso", "Costura", V(0.006, 0.9, 0.01), V(x, 0, -0.545), L.stitch, LEATHER)
	end
	plate("UpperTorso", "Costura", V(0.94, 0.008, 0.01), V(0, -0.44, -0.545), L.stitch, LEATHER)
	for i = 0, 2 do
		local y = 0.32 - i * 0.26
		plate("UpperTorso", "Correa", V(0.17, 0.055, 0.02), V(0, y, -0.55), L.dark, LEATHER)
		buckle(plate, "UpperTorso", V(0.045, 0.085, 0.025), V(-0.035, y, -0.553), L.iron)
		plate("UpperTorso", "Remache", V(0.022, 0.035, 0.03), V(0.065, y, -0.55), L.iron, METAL, BALL)
	end
	plate("UpperTorso", "Cuello", V(0.44, 0.16, 0), V(0, 0.56, 0), L.main, LEATHER, CYL)
	plate("UpperTorso", "Cuello", V(0.455, 0.04, 0), V(0, 0.62, 0), L.dark, LEATHER, CYL)
	-- Bandolera cruzada (del hombro derecho del dibujo a la cadera opuesta) con su hebilla.
	local diag = CFrame.Angles(0, 0, math.rad(36))
	plate("UpperTorso", "Bandolera", V(0.1, 1.3, 1.14), V(0, 0, 0), L.dark, LEATHER, { rot = diag })
	buckle(plate, "UpperTorso", V(0.1, 0.11, 0.02), V(-0.174, 0.3, -0.578), L.iron, { rot = diag })
	for _, side in SIDES do
		local name, x = side[1] :: string, side[2] :: number
		local arm = name .. "UpperArm"
		plate(arm, "Manga", V(1.05, 0.72, 1.05), V(0, -0.12, 0), L.sleeve, Enum.Material.Fabric)
		plate(arm, "Puno", V(1.09, 0.1, 1.09), V(0, -0.46, 0), Color3.fromRGB(38, 30, 28), Enum.Material.Fabric)
		-- Hombrera de dos capas con costura y remaches.
		plate(arm, "Hombrera", V(1.46, 0.58, 1.38), V(x * 0.1, 0.4, 0), L.dark, LEATHER, BALL)
		plate(arm, "Lama", V(1.32, 0.4, 1.26), V(x * 0.07, 0.17, 0), L.darker, LEATHER, BALL)
		plate(arm, "Costura", V(1.47, 0.03, 1.39), V(x * 0.1, 0.33, 0), L.stitch, LEATHER, BALL)
		for _, pos in { V(x * 0.1, 0.5, -0.65), V(x * 0.1, 0.5, 0.65), V(x * 0.79, 0.5, 0) } do
			plate(arm, "Remache", V(0.1, 0.08, 0.1), pos, L.iron, METAL, BALL)
		end
	end
	-- Faldón con cinturón ancho y hebilla dorada.
	plate("LowerTorso", "Faldon", V(1.04, 1.0, 1.07), V(0, 0, 0), L.main, LEATHER)
	plate("LowerTorso", "Cinturon", V(1.07, 0.62, 1.1), V(0, 0.12, 0), L.dark, LEATHER)
	buckle(plate, "LowerTorso", V(0.13, 0.56, 0.03), V(0, 0.12, -0.565), L.brass)
	for _, bx in { -0.38, -0.24, 0.24, 0.38 } do
		plate("LowerTorso", "Remache", V(0.025, 0.12, 0.03), V(bx, 0.12, -0.55), L.iron, METAL, BALL)
	end
end

local function leatherLegs(plate: Plate)
	-- Cintura con cinto propio (más abajo que el cinturón de la pechera para no pisarse).
	plate("LowerTorso", "Cintura", V(1.06, 0.55, 1.08), V(0, -0.22, 0), L.main, LEATHER)
	plate("LowerTorso", "Cinto", V(1.09, 0.28, 1.12), V(0, -0.32, 0), L.dark, LEATHER)
	buckle(plate, "LowerTorso", V(0.07, 0.24, 0.03), V(0, -0.32, -0.575), L.iron)
	for _, bx in { -0.3, 0.3 } do
		plate("LowerTorso", "Remache", V(0.025, 0.1, 0.03), V(bx, -0.32, -0.565), L.iron, METAL, BALL)
	end
	-- Rodillera: disco que mira al frente (cilindro girado), con borde oscuro y 4 remaches.
	local facing = CFrame.Angles(math.rad(90), 0, 0)
	for _, side in SIDES do
		local name, x = side[1] :: string, side[2] :: number
		local ul, ll, ft = name .. "UpperLeg", name .. "LowerLeg", name .. "Foot"
		plate(ul, "Pernera", V(1.07, 1.0, 1.07), V(0, 0, 0), L.main, LEATHER)
		plate(ul, "Costura", V(0.01, 0.96, 0.03), V(x * 0.537, 0, 0), L.stitch, LEATHER)
		plate(ul, "Correa", V(1.1, 0.12, 1.1), V(0, -0.28, 0), L.strap, LEATHER)
		buckle(plate, ul, V(0.03, 0.16, 0.16), V(x * 0.555, -0.28, -0.15), L.iron)
		plate(ll, "Pernera", V(1.07, 0.56, 1.07), V(0, 0.22, 0), L.main, LEATHER)
		plate(ll, "Rodillera", V(0.68, 0.1, 0), V(0, 0.3, -0.56), L.dark, LEATHER, { shape = "Cyl", rot = facing })
		plate(ll, "Rodillera", V(0.58, 0.12, 0), V(0, 0.3, -0.56), L.pad, LEATHER, { shape = "Cyl", rot = facing })
		for _, d in { V(-1, 1, 0), V(1, 1, 0), V(-1, -1, 0), V(1, -1, 0) } do
			plate(ll, "Remache", V(0.06, 0.055, 0.04), V(d.X * 0.2, 0.3 + d.Y * 0.18, -0.625), L.iron, METAL, BALL)
		end
		-- Bota alta con vuelta, costura, puntera redondeada y suela.
		plate(ll, "Bota", V(1.12, 0.6, 1.12), V(0, -0.2, 0), L.dark, LEATHER)
		plate(ll, "Vuelta", V(1.16, 0.12, 1.16), V(0, 0.08, 0), L.darker, LEATHER)
		plate(ll, "Costura", V(1.125, 0.012, 1.125), V(0, -0.12, 0), L.stitch, LEATHER)
		plate(ft, "Bota", V(1.12, 1.4, 1.16), V(0, 0.15, 0.02), L.dark, LEATHER)
		plate(ft, "Puntera", V(1.1, 1.5, 0.5), V(0, 0.05, -0.5), L.dark, LEATHER, BALL)
		plate(ft, "Suela", V(1.15, 0.4, 1.22), V(0, -0.4, 0), L.sole, Enum.Material.Rubber)
		plate(ft, "Suela", V(1.13, 0.4, 0.5), V(0, -0.4, -0.5), L.sole, Enum.Material.Rubber, BALL)
	end
end


-- ── Sets de placas (Acero, Obsidiana, Tormenta, Vacío) ──

type Palette = {
	main: Color3, -- placas
	trim: Color3, -- remaches, crestas, detalles secundarios
	frame: Color3, -- bordes de placas y marco de la visera
	frameMaterial: Enum.Material,
	under: Color3, -- tela o malla debajo de las placas
	belt: Color3,
	accent: Color3, -- color de energía (neón)
	material: Enum.Material,
	trimMaterial: Enum.Material,
	reflect: number,
	glowing: boolean,
}

local PALETTES: { [string]: Palette } = {
	Steel = { main = Color3.fromRGB(150, 156, 166), trim = Color3.fromRGB(196, 160, 80), frame = Color3.fromRGB(196, 160, 80),
		frameMaterial = Enum.Material.Metal, under = Color3.fromRGB(74, 58, 46), belt = Color3.fromRGB(92, 54, 32),
		accent = Color3.fromRGB(196, 160, 80), material = Enum.Material.Metal, trimMaterial = Enum.Material.Metal, reflect = 0.08, glowing = false },
	Ember = { main = Color3.fromRGB(42, 36, 44), trim = Color3.fromRGB(26, 22, 26), frame = Color3.fromRGB(26, 22, 26),
		frameMaterial = Enum.Material.Slate, under = Color3.fromRGB(30, 26, 30), belt = Color3.fromRGB(26, 22, 26),
		accent = Color3.fromRGB(255, 110, 30), material = Enum.Material.Basalt, trimMaterial = Enum.Material.Slate, reflect = 0, glowing = true },
	Storm = { main = Color3.fromRGB(84, 98, 124), trim = Color3.fromRGB(214, 176, 96), frame = Color3.fromRGB(214, 176, 96),
		frameMaterial = Enum.Material.Metal, under = Color3.fromRGB(44, 52, 68), belt = Color3.fromRGB(214, 176, 96),
		accent = Color3.fromRGB(110, 220, 255), material = Enum.Material.Metal, trimMaterial = Enum.Material.Metal, reflect = 0.1, glowing = true },
	Void = { main = Color3.fromRGB(40, 26, 56), trim = Color3.fromRGB(22, 14, 32), frame = Color3.fromRGB(225, 90, 255),
		frameMaterial = NEON, under = Color3.fromRGB(24, 18, 30), belt = Color3.fromRGB(22, 14, 32),
		accent = Color3.fromRGB(225, 90, 255), material = Enum.Material.Metal, trimMaterial = Enum.Material.Basalt, reflect = 0.05, glowing = true },
}

-- Gema en rombo (neón) sobre un engaste del color de los bordes.
local function gem(plate: Plate, bodyName: string, size: Vector3, offset: Vector3, c: Palette): BasePart?
	local setting = if c.frameMaterial == NEON then c.trim else c.frame
	plate(bodyName, "Engaste", V(size.X * 1.45, size.Y * 1.45, size.Z * 0.7), offset, setting, c.trimMaterial, { rot = DIAMOND })
	return plate(bodyName, "Gema", size, offset, c.accent, NEON, { rot = DIAMOND })
end

-- Línea fina (grieta, veta, runa) sobre una superficie.
local function line(plate: Plate, bodyName: string, size: Vector3, offset: Vector3, angle: number, color: Color3)
	plate(bodyName, "Veta", size, offset, color, NEON, { rot = CFrame.Angles(0, 0, math.rad(angle)) })
end

-- Yelmo cerrado: caja ajustada a la cabeza, cúpula, cresta, visera enmarcada con ranura,
-- respiraderos, bisagras laterales y gola. Devuelve (cúpula, ranura) para efectos.
local function plateHelm(plate: Plate, c: Palette): (BasePart?, BasePart?)
	local r: Opts = { reflect = c.reflect }
	plate("Head", "Yelmo", V(1.1, 1.06, 1.1), V(0, 0.04, 0), c.main, c.material, r)
	local dome = plate("Head", "Cupula", V(1.1, 0.5, 1.1), V(0, 0.5, 0), c.main, c.material, { shape = "Ball", reflect = c.reflect })
	plate("Head", "Cresta", V(0.1, 0.56, 1.14), V(0, 0.5, 0), c.trim, c.trimMaterial, BALL)
	plate("Head", "Visera", V(0.9, 0.62, 0.06), V(0, -0.06, -0.57), c.main, c.material, r)
	for _, bar in { { V(0.92, 0.05, 0.07), V(0, 0.23, -0.575) }, { V(0.92, 0.05, 0.07), V(0, -0.36, -0.575) },
		{ V(0.05, 0.62, 0.07), V(-0.45, -0.06, -0.575) }, { V(0.05, 0.62, 0.07), V(0.45, -0.06, -0.575) } } do
		plate("Head", "Marco", bar[1], bar[2], c.frame, c.frameMaterial)
	end
	local slit = plate("Head", "Ranura", V(0.7, 0.08, 0.02), V(0, 0.1, -0.605),
		if c.glowing then c.accent else Color3.fromRGB(14, 14, 18), if c.glowing then NEON else Enum.Material.SmoothPlastic)
	for i = -1, 1 do
		plate("Head", "Respiro", V(0.06, 0.2, 0.02), V(i * 0.15, -0.18, -0.605), Color3.fromRGB(14, 14, 18), Enum.Material.SmoothPlastic)
	end
	for _, side in SIDES do
		plate("Head", "Bisagra", V(0.3, 0.06, 0), V(side[2] :: number * 0.56, 0.05, 0), c.trim, c.trimMaterial, { shape = "Cyl", rot = SIDEWAYS })
	end
	plate("Head", "Gola", V(1.14, 0.08, 1.14), V(0, -0.47, 0), c.frame, c.frameMaterial)
	return dome, slit
end

-- Coraza: peto ajustado, pectoral en relieve con borde en V, cuello, hombreras de dos capas
-- con borde, mangas, faldón con cinturón y escarcelas. Devuelve el pectoral para efectos.
local function plateChest(plate: Plate, c: Palette): BasePart?
	local r: Opts = { reflect = c.reflect }
	plate("UpperTorso", "Peto", V(1.06, 1.0, 1.1), V(0, 0, 0), c.main, c.material, r)
	local chest = plate("UpperTorso", "Pectoral", V(0.86, 0.56, 0.05), V(0, 0.16, -0.57), c.main, c.material, r)
	plate("UpperTorso", "Arista", V(0.025, 0.5, 0.06), V(0, 0.2, -0.575), c.frame, c.frameMaterial)
	for _, side in SIDES do
		local x = side[2] :: number
		plate("UpperTorso", "Borde", V(0.44, 0.035, 0.06), V(x * 0.22, -0.04, -0.57), c.frame, c.frameMaterial,
			{ rot = CFrame.Angles(0, 0, x * math.rad(18)) })
	end
	plate("UpperTorso", "Cuello", V(0.44, 0.14, 0), V(0, 0.56, 0), c.frame, c.frameMaterial, CYL)
	plate("UpperTorso", "Ribete", V(1.08, 0.06, 1.12), V(0, -0.47, 0), c.frame, c.frameMaterial)
	for _, side in SIDES do
		local name, x = side[1] :: string, side[2] :: number
		local arm = name .. "UpperArm"
		plate(arm, "Manga", V(1.05, 0.62, 1.05), V(0, -0.16, 0), c.under, c.trimMaterial)
		plate(arm, "Hombrera", V(1.42, 0.42, 1.32), V(x * 0.12, 0.42, 0), c.main, c.material, r)
		plate(arm, "Hombrera", V(1.44, 0.3, 1.34), V(x * 0.12, 0.66, 0), c.main, c.material, { shape = "Ball", reflect = c.reflect })
		plate(arm, "Lama", V(1.32, 0.3, 1.26), V(x * 0.1, 0.14, 0), c.main, c.material, r)
		plate(arm, "Filo", V(1.45, 0.05, 1.35), V(x * 0.12, 0.22, 0), c.frame, c.frameMaterial)
		plate(arm, "Filo", V(1.34, 0.05, 1.28), V(x * 0.1, -0.01, 0), c.frame, c.frameMaterial)
		plate(arm, "Remache", V(0.1, 0.08, 0.06), V(x * 0.12, 0.45, -0.67), c.trim, c.trimMaterial, BALL)
	end
	plate("LowerTorso", "Faldon", V(1.04, 1.0, 1.07), V(0, 0, 0), c.under, c.trimMaterial)
	plate("LowerTorso", "Cinturon", V(1.07, 0.62, 1.1), V(0, 0.12, 0), c.belt, if c.belt == L.dark then LEATHER else c.trimMaterial)
	for _, side in SIDES do
		local x = side[2] :: number
		plate("LowerTorso", "Escarcela", V(0.44, 1.3, 0.05), V(x * 0.24, -1.05, -0.56), c.main, c.material, r)
		plate("LowerTorso", "Borde", V(0.45, 0.12, 0.06), V(x * 0.24, -1.65, -0.56), c.frame, c.frameMaterial)
	end
	return chest
end

-- Pantalón de placas: quijotes al frente y al costado, rodillera en rombo, grebas con borde
-- y escarpes con puntera. Devuelve las rodilleras para efectos.
local function plateLegs(plate: Plate, c: Palette): { BasePart }
	local r: Opts = { reflect = c.reflect }
	local knees = {}
	plate("LowerTorso", "Cintura", V(1.06, 0.55, 1.08), V(0, -0.22, 0), c.under, c.trimMaterial)
	plate("LowerTorso", "Cinto", V(1.09, 0.28, 1.12), V(0, -0.32, 0), c.belt, if c.belt == L.dark then LEATHER else c.trimMaterial)
	for _, side in SIDES do
		local name, x = side[1] :: string, side[2] :: number
		local ul, ll, ft = name .. "UpperLeg", name .. "LowerLeg", name .. "Foot"
		plate(ul, "Pernera", V(1.07, 1.0, 1.07), V(0, 0, 0), c.under, c.trimMaterial)
		plate(ul, "Quijote", V(0.9, 0.72, 0.06), V(0, 0.08, -0.565), c.main, c.material, r)
		plate(ul, "Quijote", V(0.06, 0.72, 0.9), V(x * 0.565, 0.08, 0), c.main, c.material, r)
		plate(ul, "Borde", V(0.92, 0.06, 0.07), V(0, -0.28, -0.565), c.frame, c.frameMaterial)
		plate(ul, "Borde", V(0.07, 0.06, 0.92), V(x * 0.565, -0.28, 0), c.frame, c.frameMaterial)
		plate(ll, "Pernera", V(1.07, 0.56, 1.07), V(0, 0.22, 0), c.under, c.trimMaterial)
		plate(ll, "Rodillera", V(0.5, 0.46, 0.08), V(0, 0.32, -0.56), c.frame, c.frameMaterial, { rot = DIAMOND })
		local knee = plate(ll, "Rodillera", V(0.4, 0.37, 0.1), V(0, 0.32, -0.56), c.main, c.material, { rot = DIAMOND, reflect = c.reflect })
		if knee then table.insert(knees, knee) end
		plate(ll, "Greba", V(1.12, 0.6, 1.12), V(0, -0.2, 0), c.main, c.material, r)
		plate(ll, "Borde", V(1.15, 0.07, 1.15), V(0, 0.1, 0), c.frame, c.frameMaterial)
		plate(ft, "Escarpe", V(1.12, 1.4, 1.16), V(0, 0.15, 0.02), c.main, c.material, r)
		plate(ft, "Puntera", V(1.1, 1.5, 0.5), V(0, 0.05, -0.5), c.main, c.material, { shape = "Ball", reflect = c.reflect })
		plate(ft, "Suela", V(1.15, 0.4, 1.22), V(0, -0.4, 0), c.trim, c.trimMaterial)
		plate(ft, "Suela", V(1.13, 0.4, 0.5), V(0, -0.4, -0.5), c.trim, c.trimMaterial, BALL)
	end
	return knees
end

local function pauldronSpikes(plate: Plate, c: Palette)
	for _, side in SIDES do
		local name, x = side[1] :: string, side[2] :: number
		local tilt = CFrame.Angles(0, 0, -x * math.rad(25))
		plate(name .. "UpperArm", "Pua", V(0.24, 0.5, 0), V(x * 0.3, 0.92, -0.18), c.main, c.material, { shape = "Spike", rot = tilt })
		plate(name .. "UpperArm", "Pua", V(0.18, 0.36, 0), V(x * 0.3, 0.86, 0.25), c.main, c.material, { shape = "Spike", rot = tilt })
	end
end

local HELMS: { [string]: (Plate) -> () } = {
	LeatherHelm = leatherHelm,
	SteelHelm = function(plate)
		local c = PALETTES.Steel
		plateHelm(plate, c)
		for _, p in { V(-0.4, 0.23, -0.615), V(0.4, 0.23, -0.615), V(-0.4, -0.36, -0.615), V(0.4, -0.36, -0.615) } do
			plate("Head", "Remache", V(0.06, 0.06, 0.04), p, c.main, c.material, BALL)
		end
	end,
	EmberHelm = function(plate)
		local c = PALETTES.Ember
		local dome, slit = plateHelm(plate, c)
		-- Corona de púas y cuernos laterales.
		plate("Head", "Pua", V(0.22, 0.5, 0), V(0, 0.86, 0), c.main, c.material, { shape = "Spike" })
		for _, side in SIDES do
			local x = side[2] :: number
			plate("Head", "Pua", V(0.17, 0.36, 0), V(x * 0.24, 0.78, 0.05), c.main, c.material, { shape = "Spike", rot = CFrame.Angles(0, 0, -x * math.rad(14)) })
			plate("Head", "Cuerno", V(0.2, 0.5, 0), V(x * 0.64, 0.42, 0), c.main, c.material, { shape = "Spike", rot = CFrame.Angles(0, 0, -x * math.rad(50)) })
			line(plate, "Head", V(0.025, 0.3, 0.03), V(x * 0.3, 0.38, -0.555), x * 25, c.accent)
		end
		glow(slit, c.accent, 7)
		sparkles(dome, ColorSequence.new(Color3.fromRGB(255, 200, 90), c.accent), 3, 0.08, 2)
	end,
	StormHelm = function(plate)
		local c = PALETTES.Storm
		local dome, slit = plateHelm(plate, c)
		for _, side in SIDES do
			local x = side[2] :: number
			-- Alas de plumas metálicas abiertas hacia atrás y arriba.
			for i = 0, 3 do
				plate("Head", "Pluma", V(0.04, 0.11, 0.62 - i * 0.1), V(x * 0.62, 0.22 + i * 0.12, 0.25),
					if i % 2 == 0 then c.trim else c.accent, if i % 2 == 0 then c.trimMaterial else NEON,
					{ rot = CFrame.Angles(math.rad(-18 - i * 14), 0, 0) })
			end
		end
		gem(plate, "Head", V(0.16, 0.16, 0.05), V(0, 0.36, -0.57), c)
		glow(slit, c.accent, 7, 1.4)
		sparkles(dome, ColorSequence.new(Color3.new(1, 1, 1), c.accent), 4, 0.12, 0.5)
	end,
	VoidHelm = function(plate)
		local c = PALETTES.Void
		local dome, slit = plateHelm(plate, c)
		plate("Head", "Pua", V(0.18, 0.45, 0), V(0, 0.86, 0.05), c.trim, c.trimMaterial, { shape = "Spike" })
		for _, side in SIDES do
			local x = side[2] :: number
			plate("Head", "Antena", V(0.05, 0.4, 0), V(x * 0.3, 0.85, 0.1), c.trim, c.trimMaterial, CYL)
			plate("Head", "Antena", V(0.12, 0.1, 0.12), V(x * 0.3, 1.08, 0.1), c.accent, NEON, BALL)
		end
		-- Anillo del vacío en la frente.
		plate("Head", "Anillo", V(0.32, 0.05, 0), V(0, 0.37, -0.57), c.accent, NEON, { shape = "Cyl", rot = FACING })
		plate("Head", "Anillo", V(0.18, 0.06, 0), V(0, 0.37, -0.57), c.trim, c.trimMaterial, { shape = "Cyl", rot = FACING })
		glow(slit, c.accent, 8, 1.6)
		smoke(dome, Color3.fromRGB(40, 10, 60), 4)
	end,
}

local CHESTS: { [string]: (Plate) -> () } = {
	LeatherChest = leatherChest,
	SteelChest = function(plate)
		local c = PALETTES.Steel
		plateChest(plate, c)
		-- Correa de cuero cruzada con hebilla y remaches en el borde del pectoral.
		local diag = CFrame.Angles(0, 0, math.rad(36))
		plate("UpperTorso", "Correa", V(0.1, 1.3, 1.21), V(0, 0, 0), L.dark, LEATHER, { rot = diag })
		buckle(plate, "UpperTorso", V(0.1, 0.11, 0.02), V(-0.174, 0.3, -0.613), L.iron, { rot = diag })
		for i = 0, 4 do
			plate("UpperTorso", "Remache", V(0.025, 0.035, 0.03), V(-0.36 + i * 0.18, 0.42, -0.6), c.trim, c.trimMaterial, BALL)
		end
		buckle(plate, "LowerTorso", V(0.13, 0.56, 0.03), V(0, 0.12, -0.565), L.iron)
	end,
	EmberChest = function(plate)
		local c = PALETTES.Ember
		local chest = plateChest(plate, c)
		pauldronSpikes(plate, c)
		-- Grietas de lava: V sobre el pecho y vetas sueltas.
		for _, side in SIDES do
			local name, x = side[1] :: string, side[2] :: number
			line(plate, "UpperTorso", V(0.3, 0.022, 0.03), V(x * 0.13, 0.22, -0.6), x * 28, c.accent)
			line(plate, "UpperTorso", V(0.022, 0.22, 0.03), V(x * 0.32, -0.2, -0.555), x * -20, c.accent)
			plate(name .. "UpperArm", "Brasa", V(1.43, 0.03, 1.33), V(x * 0.12, 0.27, 0), c.accent, NEON)
		end
		local core = gem(plate, "LowerTorso", V(0.12, 0.5, 0.06), V(0, 0.12, -0.57), c)
		glow(chest, c.accent, 9)
		sparkles(core, ColorSequence.new(Color3.fromRGB(255, 200, 90), c.accent), 4, 0.1, 2)
	end,
	StormChest = function(plate)
		local c = PALETTES.Storm
		local chest = plateChest(plate, c)
		-- Rayo en zigzag con contorno dorado.
		for _, b in { { 0.06, 0.32, 30 }, { -0.03, 0.14, -28 }, { 0.05, -0.04, 30 } } do
			local rot = { rot = CFrame.Angles(0, 0, math.rad(b[3])) }
			plate("UpperTorso", "Rayo", V(0.075, 0.23, 0.02), V(b[1], b[2], -0.6), c.trim, c.trimMaterial, rot)
			plate("UpperTorso", "Rayo", V(0.05, 0.2, 0.03), V(b[1], b[2], -0.603), c.accent, NEON, rot)
		end
		for _, side in SIDES do
			local name, x = side[1] :: string, side[2] :: number
			plate(name .. "UpperArm", "Orbe", V(0.18, 0.15, 0.1), V(x * 0.12, 0.45, -0.68), c.accent, NEON, BALL)
		end
		gem(plate, "LowerTorso", V(0.12, 0.5, 0.06), V(0, 0.12, -0.57), c)
		glow(chest, c.accent, 10, 1.4)
		sparkles(chest, ColorSequence.new(Color3.new(1, 1, 1), c.accent), 6, 0.14, 0)
	end,
	VoidChest = function(plate)
		local c = PALETTES.Void
		local chest = plateChest(plate, c)
		pauldronSpikes(plate, c)
		-- Sol del vacío: orbe con cristal y ocho rayos.
		local orb = plate("UpperTorso", "Orbe", V(0.14, 0.2, 0.12), V(0, 0.18, -0.6), c.accent, NEON, BALL)
		plate("UpperTorso", "Cristal", V(0.18, 0.26, 0.15), V(0, 0.18, -0.6), Color3.fromRGB(80, 30, 120), Enum.Material.Glass, { shape = "Ball", transparency = 0.5 })
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			line(plate, "UpperTorso", V(0.018, 0.1, 0.03), V(math.sin(a) * 0.13, 0.18 + math.cos(a) * 0.17, -0.6), -math.deg(a), c.accent)
		end
		gem(plate, "LowerTorso", V(0.12, 0.5, 0.06), V(0, 0.12, -0.57), c)
		glow(orb, c.accent, 10, 1.6)
		smoke(chest, Color3.fromRGB(40, 10, 60), 5)
	end,
}

local LEGS: { [string]: (Plate) -> () } = {
	LeatherLegs = leatherLegs,
	SteelLegs = function(plate)
		local c = PALETTES.Steel
		plateLegs(plate, c)
		buckle(plate, "LowerTorso", V(0.07, 0.24, 0.03), V(0, -0.32, -0.575), L.iron)
		for _, side in SIDES do
			plate(side[1] :: string .. "LowerLeg", "Remache", V(0.08, 0.07, 0.06), V(0, 0.32, -0.62), c.trim, c.trimMaterial, BALL)
		end
	end,
	EmberLegs = function(plate)
		local c = PALETTES.Ember
		local knees = plateLegs(plate, c)
		for _, side in SIDES do
			local name, x = side[1] :: string, side[2] :: number
			line(plate, name .. "UpperLeg", V(0.025, 0.4, 0.03), V(x * 0.15, 0.1, -0.6), x * 18, c.accent)
			line(plate, name .. "LowerLeg", V(0.025, 0.35, 0.03), V(-x * 0.2, -0.2, -0.565), x * -22, c.accent)
			gem(plate, name .. "LowerLeg", V(0.14, 0.13, 0.12), V(0, 0.32, -0.6), c)
		end
		glow(knees[1], c.accent, 5)
	end,
	StormLegs = function(plate)
		local c = PALETTES.Storm
		local knees = plateLegs(plate, c)
		for _, side in SIDES do
			local name, x = side[1] :: string, side[2] :: number
			line(plate, name .. "UpperLeg", V(0.025, 0.6, 0.03), V(x * 0.6, 0.08, -0.3), 0, c.accent)
			line(plate, name .. "LowerLeg", V(0.025, 0.5, 0.03), V(x * 0.575, -0.2, -0.3), 0, c.accent)
			gem(plate, name .. "LowerLeg", V(0.14, 0.13, 0.12), V(0, 0.32, -0.6), c)
		end
		glow(knees[1], c.accent, 5)
		sparkles(knees[2], ColorSequence.new(Color3.new(1, 1, 1), c.accent), 3, 0.08, 0)
	end,
	VoidLegs = function(plate)
		local c = PALETTES.Void
		local knees = plateLegs(plate, c)
		gem(plate, "LowerTorso", V(0.08, 0.3, 0.06), V(0, -0.32, -0.58), c)
		for _, side in SIDES do
			local name, x = side[1] :: string, side[2] :: number
			gem(plate, name .. "LowerLeg", V(0.14, 0.13, 0.12), V(0, 0.32, -0.6), c)
			line(plate, name .. "UpperLeg", V(0.025, 0.45, 0.03), V(-x * 0.15, 0.1, -0.6), x * -12, c.accent)
		end
		glow(knees[1], c.accent, 6)
		smoke(knees[2], Color3.fromRGB(40, 10, 60), 3)
	end,
}

local BUILDERS: { [string]: (Plate) -> () } = {}
for _, group in { HELMS, CHESTS, LEGS } do
	for id, build in group do BUILDERS[id] = build end
end

function ArmorArt.Has(pieceId: string): boolean
	return BUILDERS[pieceId] ~= nil
end

function ArmorArt.Build(pieceId: string, slot: string, body: Instance): Model
	local model = Instance.new("Model")
	model.Name = `Armadura_{slot}`
	model:SetAttribute("PieceId", pieceId)
	local build = BUILDERS[pieceId]
	if build then build(newPlate(model, body)) end
	return model
end

return ArmorArt
