--!strict
--[[
	LobbyService — La ciudadela: el lobby completo, armado por código.
	Owner: Dev B (Economía).

	Distribución (posiciones en Lobby/Layout; -Z es "norte"). El spawn queda al sur, junto al
	portón, en una rosa de los vientos; desde ahí salen caminos con bordes dorados:
	  Norte       Arena de duelos: al pisarla se abre el menú de duelo (DuelZoneCenter/Radius).
	  Noroeste    Salón de la fama alrededor del tablero de récords (el tablero lo arma RecordsService).
	  Noreste     Arco de la mazmorra (lo arma DungeonService) con cristales del vacío.
	  Oeste       Mercado con la tienda de armas (OpenShop = true → UIController) y la armería
	              (OpenArmorShop = true → ArmorController); arco "TIENDAS".
	  Este        Zona de práctica con muñecos: se les puede pegar (CombatService los trata como
	              enemigos), muestran el daño y se curan solos. No dan oro.
	  Entre medio Jardines con árboles, arbustos, rocas y estandartes.
	  Alrededor   Muralla con almenas, torres, estandartes y antorchas; montañas de terreno a lo lejos.

	También ajusta la iluminación general (atardecer cálido con bruma). Si alguien configura
	Lighting a mano en Studio, este servicio lo pisa al arrancar: ver setupLighting().
]]
local Lighting = game:GetService("Lighting")
local Kit = require(script.Parent:WaitForChild("Lobby"):WaitForChild("Kit"))
local Layout = require(script.Parent:WaitForChild("Lobby"):WaitForChild("Layout"))
local LobbyService = {}

local C = Kit.Colors
local HALF = 66 -- media distancia entre murallas
local WALL_HEIGHT = 16
local WALL_THICK = 3

local origin = Vector3.zero -- centro del lobby (Layout.Base)
local ground = 0 -- altura del piso

local function at(x: number, y: number, z: number): Vector3
	return Vector3.new(origin.X + x, ground + y, origin.Z + z)
end

-- CFrame a ras del piso en (x, z) mirando hacia el punto (tx, tz) del lobby.
local function facing(x: number, z: number, tx: number, tz: number): CFrame
	return CFrame.lookAt(at(x, 0, z), at(tx, 0, tz))
end

-- ── Iluminación ──

local function setupLighting()
	Lighting.ClockTime = 17.4
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 62, 62)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 104, 98)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 205, 160)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	local function effect(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing then return existing end
		local e = Instance.new(className)
		e.Name = name
		e.Parent = Lighting
		return e
	end
	local atmosphere = effect("Atmosphere", "AtmosferaLobby") :: Atmosphere
	atmosphere.Density, atmosphere.Offset = 0.33, 0.12
	atmosphere.Color, atmosphere.Decay = Color3.fromRGB(205, 172, 140), Color3.fromRGB(104, 86, 112)
	atmosphere.Glare, atmosphere.Haze = 0.5, 1.8
	local bloom = effect("BloomEffect", "BrilloLobby") :: BloomEffect
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.5, 24, 1.3
	local rays = effect("SunRaysEffect", "RayosLobby") :: SunRaysEffect
	rays.Intensity, rays.Spread = 0.07, 0.6
	local grade = effect("ColorCorrectionEffect", "TonoLobby") :: ColorCorrectionEffect
	grade.Contrast, grade.Saturation, grade.TintColor = 0.08, 0.05, Color3.fromRGB(255, 244, 232)
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover, clouds.Density = 0.55, 0.7
	clouds.Color = Color3.fromRGB(255, 226, 205)
	clouds.Parent = workspace.Terrain
end

-- Montañas de roca en el horizonte, fuera de la muralla.
local function mountains()
	local terrain = workspace.Terrain
	local rng = Random.new(42)
	for i = 0, 17 do
		local angle = i / 18 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local distance = rng:NextNumber(190, 250)
		local radius = rng:NextNumber(45, 85)
		local center = at(math.cos(angle) * distance, -radius * 0.35, math.sin(angle) * distance)
		terrain:FillBall(center, radius, if i % 3 == 0 then Enum.Material.Basalt else Enum.Material.Rock)
		-- Un pico más chico encima, corrido, para que no sean cúpulas perfectas.
		terrain:FillBall(center + Vector3.new(rng:NextNumber(-15, 15), radius * 0.45, rng:NextNumber(-15, 15)), radius * 0.45, Enum.Material.Rock)
	end
end

-- ── Caminos, spawn y jardines ──
--[[
	Plano (ver Lobby/Layout): el spawn al sur, junto al portón, en una rosa de los vientos.
	Del spawn sale el camino principal hacia el norte (arena de duelos) y el camino de abajo
	hacia el oeste (tiendas) y el este (zona de práctica). Arriba, un camino este-oeste lleva a
	los récords (noroeste) y a las mazmorras (noreste). Los caminos tienen bordes dorados que
	brillan; entre ellos hay jardines con árboles, arbustos y rocas.
]]
local GLOW = Color3.fromRGB(255, 190, 80)
local COBBLE = Color3.fromRGB(140, 128, 112)
local GRASS = Color3.fromRGB(84, 116, 56)

-- Anillo de piezas tangentes alrededor de (cx, cz).
local function ringAt(parent: Instance, cx: number, cz: number, radius: number, y: number, width: number, color: Color3, material: Enum.Material)
	local count = math.max(16, math.floor(radius * 3.2))
	local length = 2 * math.pi * radius / count + 0.1
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local cf = CFrame.new(at(cx + math.cos(a) * radius, y, cz + math.sin(a) * radius)) * CFrame.Angles(0, -a, 0)
		Kit.part(parent, "Anillo", cf, Vector3.new(width, 0.06, length), color, material, false)
	end
end

-- Borde de camino recto: cordón oscuro + línea dorada que brilla. `gaps` = tramos [a, b] (sobre el
-- eje del borde) donde se corta porque llega otro camino.
local function edge(parent: Instance, along: "X" | "Z", fixed: number, from: number, to: number, inward: number, gaps: { { number } }?)
	local pieces = { { from, to } }
	for _, gap in gaps or {} do
		local nextPieces = {}
		for _, piece in pieces do
			if gap[2] <= piece[1] or gap[1] >= piece[2] then
				table.insert(nextPieces, piece)
			else
				if gap[1] > piece[1] then table.insert(nextPieces, { piece[1], gap[1] }) end
				if gap[2] < piece[2] then table.insert(nextPieces, { gap[2], piece[2] }) end
			end
		end
		pieces = nextPieces
	end
	for _, piece in pieces do
		local mid, length = (piece[1] + piece[2]) / 2, piece[2] - piece[1]
		local function place(name: string, offset: number, y: number, size: Vector2, color: Color3, material: Enum.Material)
			local pos = if along == "X" then at(mid, y, fixed + offset) else at(fixed + offset, y, mid)
			local dims = if along == "X" then Vector3.new(length, size.Y, size.X) else Vector3.new(size.X, size.Y, length)
			Kit.part(parent, name, CFrame.new(pos), dims, color, material, false)
		end
		place("Cordon", 0, 0.31, Vector2.new(0.5, 0.12), C.DarkStone, Enum.Material.Basalt)
		place("Luz", inward * 0.6, 0.31, Vector2.new(0.18, 0.06), GLOW, Enum.Material.Neon)
	end
end

-- Camino recto de ancho 8 entre dos puntos alineados a un eje, con bordes.
local function road(parent: Instance, along: "X" | "Z", fixed: number, from: number, to: number, gapsLow: { { number } }?, gapsHigh: { { number } }?)
	local mid, length = (from + to) / 2, to - from
	local pos = if along == "X" then at(mid, 0.26, fixed) else at(fixed, 0.26, mid)
	local size = if along == "X" then Vector3.new(length, 0.08, 8) else Vector3.new(8, 0.08, length)
	Kit.part(parent, "Camino", CFrame.new(pos), size, COBBLE, Enum.Material.Cobblestone, false)
	edge(parent, along, fixed - 4, from, to, 1, gapsLow)
	edge(parent, along, fixed + 4, from, to, -1, gapsHigh)
end

local function tree(parent: Instance, x: number, z: number, s: number, leaves: Color3)
	Kit.cylinder(parent, "Tronco", at(x, 2 * s, z), 4 * s, 0.9 * s, C.DarkWood, Enum.Material.Wood)
	for i, offset in { Vector3.new(0, 5.2, 0), Vector3.new(1.3, 4.3, 0.6), Vector3.new(-1.1, 4.5, -0.8), Vector3.new(0.2, 6.4, 0.3) } do
		local size = (if i == 4 then 2.6 else 3.6) * s
		local leaf = Kit.part(parent, "Copa", CFrame.new(at(x, 0, z) + offset * s), Vector3.new(size, size, size), leaves:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.12), Enum.Material.LeafyGrass, false)
		leaf.Shape = Enum.PartType.Ball
	end
end

local function bush(parent: Instance, x: number, z: number, s: number, color: Color3)
	local b = Kit.part(parent, "Arbusto", CFrame.new(at(x, 0.6 * s, z)), Vector3.new(2.2 * s, 1.8 * s, 2.2 * s), color, Enum.Material.LeafyGrass, false)
	b.Shape = Enum.PartType.Ball
end

local function rock(parent: Instance, x: number, z: number, s: number, turn: number)
	local stone = Color3.fromRGB(112, 106, 100)
	Kit.part(parent, "Roca", CFrame.new(at(x, 0.9 * s, z)) * CFrame.Angles(math.rad(12), math.rad(turn), math.rad(-8)), Vector3.new(3.2, 2.2, 2.6) * s, stone, Enum.Material.Slate)
	Kit.part(parent, "Roca", CFrame.new(at(x + 1.4 * s, 0.6 * s, z + 0.8 * s)) * CFrame.Angles(math.rad(-10), math.rad(turn + 40), math.rad(14)), Vector3.new(2, 1.5, 1.8) * s, stone:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Slate)
end

-- Poste con estandarte.
local function bannerPole(parent: Instance, x: number, z: number, color: Color3)
	local base = at(x, 0, z)
	Kit.cylinder(parent, "Mastil", base + Vector3.new(0, 4.5, 0), 9, 0.35, C.DarkWood, Enum.Material.Wood)
	Kit.part(parent, "Punta", CFrame.new(base + Vector3.new(0, 9.2, 0)), Vector3.new(0.5, 0.5, 0.5), C.Gold, Enum.Material.Metal, false)
	local toCenter = Vector3.new(-x, 0, Layout.SPAWN.Y - z)
	local look = if toCenter.Magnitude > 0.1 then toCenter.Unit else Vector3.zAxis
	Kit.banner(parent, CFrame.lookAt(base + Vector3.new(0, 8.4, 0), base + Vector3.new(0, 8.4, 0) + look) * CFrame.new(0, 0, -0.3), 2, 4.2, color)
end

-- Arco con cartel sobre un camino (zona). `cf` a ras del piso, mirando hacia donde se lee.
local function zoneArch(parent: Instance, cf: CFrame, title: string, subtitle: string?)
	for _, s in { -1, 1 } do
		Kit.part(parent, "Poste", cf * CFrame.new(s * 4.6, 3.6, 0), Vector3.new(0.8, 7.2, 0.8), C.DarkWood, Enum.Material.Wood)
		Kit.part(parent, "Punta", cf * CFrame.new(s * 4.6, 7.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(0.6, 0.6, 0.6), C.Gold, Enum.Material.Metal, false)
	end
	Kit.part(parent, "Marco", cf * CFrame.new(0, 6.4, 0.02), Vector3.new(8.8, 2.2, 0.3), C.Gold, Enum.Material.Foil, false)
	local board = Kit.sign(parent, cf * CFrame.new(0, 6.4, 0), Vector3.new(8.4, 1.8, 0.4), title, true)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 200, 130), 10, 0.8
	light.Parent = board
	if subtitle then
		Kit.sign(parent, cf * CFrame.new(0, 4.9, 0), Vector3.new(6, 0.8, 0.3), subtitle, true)
	end
end

local function grounds(parent: Instance)
	Kit.part(parent, "Suelo", CFrame.new(at(0, 0.1, 0)), Vector3.new(HALF * 2, 0.2, HALF * 2), Color3.fromRGB(92, 86, 80), Enum.Material.Slate)

	local sx, sz = Layout.SPAWN.X, Layout.SPAWN.Y
	local upper, lower, side = Layout.UPPER_ROAD_Z, Layout.LOWER_ROAD_Z, Layout.SIDE_ROAD_X
	local arenaEdge = Layout.ARENA.Y + 17 -- borde sur de la plataforma de la arena

	-- Jardines (debajo de los caminos).
	for _, g in {
		{ -38, -5, upper + 5, lower - 5 }, { 5, 32, upper + 5, lower - 5 }, -- entre los dos caminos
		{ -37, -5, arenaEdge + 1, upper - 5 }, { 5, 37, arenaEdge + 1, upper - 5 }, -- junto a la arena
		{ -38, -11, lower + 5, HALF - 3 }, { 11, 32, lower + 5, HALF - 3 }, -- junto al portón
		{ -HALF + 2, -47, -HALF + 2, upper - 5 }, { 47, HALF - 2, -HALF + 2, upper - 5 }, -- detrás de récords / mazmorras
		{ -36, -23, -HALF + 2, arenaEdge }, { 23, 36, -HALF + 2, arenaEdge },
	} do
		local x0, x1, z0, z1 = g[1], g[2], g[3], g[4]
		Kit.part(parent, "Pasto", CFrame.new(at((x0 + x1) / 2, 0.22, (z0 + z1) / 2)), Vector3.new(x1 - x0, 0.1, z1 - z0), GRASS, Enum.Material.Grass, false)
	end

	-- Spawn: rosa de los vientos con anillos dorados.
	Kit.cylinder(parent, "BordeSpawn", at(sx, 0.26, sz), 0.1, 21.2, C.DarkStone, Enum.Material.Basalt)
	Kit.cylinder(parent, "PlazaSpawn", at(sx, 0.29, sz), 0.1, 20, COBBLE, Enum.Material.Cobblestone)
	Kit.cylinder(parent, "CentroSpawn", at(sx, 0.32, sz), 0.1, 9, Color3.fromRGB(198, 188, 168), Enum.Material.Marble)
	ringAt(parent, sx, sz, 9.4, 0.36, 0.3, GLOW, Enum.Material.Neon)
	ringAt(parent, sx, sz, 4.7, 0.39, 0.25, C.Gold, Enum.Material.Foil)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local length = if k % 2 == 0 then 8.6 else 5.4
		local cf = CFrame.new(at(sx + math.cos(a) * length / 2, 0.38, sz + math.sin(a) * length / 2)) * CFrame.Angles(0, -a, 0)
		Kit.part(parent, "Rosa", cf * CFrame.Angles(0, 0, 0), Vector3.new(length, 0.05, if k % 2 == 0 then 1.1 else 0.8), Color3.fromRGB(92, 84, 78), Enum.Material.Slate, false)
	end

	-- Caminos.
	road(parent, "Z", sx, arenaEdge, upper - 4) -- spawn → arena (tramo norte)
	road(parent, "Z", sx, upper + 4, sz - 10) -- spawn → arena (tramo sur)
	road(parent, "Z", sx, sz + 10, HALF - 1.5) -- spawn → portón
	road(parent, "X", upper, -side - 4, side + 4, { { -side - 4, -side + 4 }, { -4, 4 }, { side - 4, side + 4 } }, { { -4, 4 } })
	for _, s in { -1, 1 } do
		road(parent, "Z", s * side, Layout.RECORDS.z + 3, upper - 4) -- subidas a récords / mazmorras
	end
	road(parent, "X", lower, -38, sx - 9.2) -- spawn → tiendas
	road(parent, "X", lower, sx + 9.2, Layout.TRAINING.X - 11) -- spawn → zona de práctica
	-- Plaza del mercado (tiendas).
	Kit.part(parent, "Mercado", CFrame.new(at(-48, 0.25, 43.5)), Vector3.new(20, 0.08, 43), Color3.fromRGB(150, 136, 118), Enum.Material.Cobblestone, false)

	-- Arcos con cartel.
	zoneArch(parent, CFrame.lookAt(at(sx, 0, sz + 13), at(sx, 0, sz + 30)), "SPAWN")
	zoneArch(parent, CFrame.lookAt(at(-38.5, 0, lower), at(0, 0, lower)) * CFrame.Angles(0, 0, 0), "TIENDAS", "Armaduras · Armas")

	-- Braseros junto al spawn y estandartes a lo largo de los caminos.
	for _, s in { -1, 1 } do
		Kit.brazier(parent, at(s * 11.5, 0, sz + 9), 0.9)
		bannerPole(parent, s * 12.5, sz - 9, Color3.fromRGB(110, 50, 160))
		bannerPole(parent, s * 6.5, upper + 7, C.Crimson)
	end
	bannerPole(parent, -34, lower - 6, C.Crimson)
	bannerPole(parent, 31, lower - 6, C.Crimson)

	-- Árboles, arbustos y rocas en los jardines.
	local GREEN, DARK_GREEN, AUTUMN = Color3.fromRGB(78, 128, 52), Color3.fromRGB(56, 100, 44), Color3.fromRGB(176, 52, 44)
	for _, t in {
		{ -30, 16, 1, GREEN }, { -16, 30, 0.8, AUTUMN }, { 28, 16, 1, DARK_GREEN }, { 16, 30, 0.85, GREEN },
		{ -26, -8, 0.9, GREEN }, { -12, -14, 0.7, AUTUMN }, { 26, -10, 0.9, DARK_GREEN }, { 14, -15, 0.75, GREEN },
		{ -30, 58, 0.9, AUTUMN }, { 26, 58, 0.9, GREEN },
		{ -60, -12, 1.2, DARK_GREEN }, { -58, -56, 1.1, GREEN }, { 60, -12, 1.2, GREEN }, { 58, -56, 1.1, DARK_GREEN },
		{ -30, -50, 1, GREEN }, { 30, -52, 1, DARK_GREEN },
	} do
		tree(parent, t[1] :: number, t[2] :: number, t[3] :: number, t[4] :: Color3)
	end
	for _, b in {
		{ -22, 22, 1 }, { -10, 14, 0.8 }, { 22, 24, 1 }, { 10, 14, 0.8 }, { -32, -6, 0.9 }, { 32, -6, 0.9 },
		{ -18, 54, 0.9 }, { 18, 54, 0.9 }, { -8, -4, 0.7 }, { 8, -4, 0.7 },
	} do
		bush(parent, b[1], b[2], b[3], if b[1] < 0 then GREEN else DARK_GREEN)
	end
	for i, r in {
		{ -56, -30, 1.4 }, { -54, -44, 1.2 }, { -30, -36, 1 }, { 56, -30, 1.4 }, { 54, -44, 1.2 }, { 30, -38, 1 },
		{ -24, 34, 0.7 }, { 24, 36, 0.7 }, { -36, -22, 0.9 }, { 36, -22, 0.9 },
	} do
		rock(parent, r[1], r[2], r[3], i * 37)
	end
	-- Cristales del vacío junto al portal de las mazmorras.
	for i, c in { { 34, -40, 2.6 }, { 36, -28, 1.8 }, { 50, -40, 2.2 }, { 49, -27, 1.6 }, { 56, -36, 2.8 } } do
		local crystal = Kit.part(parent, "Cristal", CFrame.new(at(c[1], c[3] / 2, c[2])) * CFrame.Angles(math.rad(i * 9 - 20), math.rad(i * 50), math.rad(14 - i * 5)),
			Vector3.new(0.7, c[3], 0.7), Color3.fromRGB(190, 90, 255), Enum.Material.Neon, false)
		if i % 2 == 1 then
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness = Color3.fromRGB(190, 90, 255), 10, 1.2
			light.Parent = crystal
		end
	end
end

-- ── Muralla ──

-- Tramo de muralla. `cf` a ras del piso en el centro del tramo, con -Z mirando hacia adentro.
local function wall(parent: Instance, cf: CFrame, length: number)
	Kit.part(parent, "Muralla", cf * CFrame.new(0, WALL_HEIGHT / 2, 0), Vector3.new(length, WALL_HEIGHT, WALL_THICK), Color3.fromRGB(104, 97, 90), Enum.Material.Cobblestone)
	Kit.part(parent, "Zocalo", cf * CFrame.new(0, 1, -WALL_THICK / 2 - 0.3), Vector3.new(length, 2, 0.6), C.DarkStone, Enum.Material.Slate)
	local x = -length / 2 + 1
	while x <= length / 2 - 1 do
		Kit.part(parent, "Almena", cf * CFrame.new(x, WALL_HEIGHT + 1.5, 0), Vector3.new(2, 3, WALL_THICK), Color3.fromRGB(104, 97, 90), Enum.Material.Cobblestone)
		x += 4
	end
end

-- Decoración de la cara interna: estandartes y antorchas en las posiciones dadas (sobre el eje del tramo).
local function wallDecor(parent: Instance, cf: CFrame, banners: { number }, torches: { number })
	for _, x in banners do
		Kit.banner(parent, cf * CFrame.new(x, WALL_HEIGHT - 1.5, -WALL_THICK / 2 - 0.25), 5, 9, C.Crimson)
	end
	for _, x in torches do
		Kit.torch(parent, cf * CFrame.new(x, 8, -WALL_THICK / 2))
	end
end

local function tower(parent: Instance, base: Vector3, size: number, height: number)
	Kit.part(parent, "Torre", CFrame.new(base + Vector3.new(0, height / 2, 0)), Vector3.new(size, height, size), C.DarkStone, Enum.Material.Cobblestone)
	Kit.part(parent, "Cornisa", CFrame.new(base + Vector3.new(0, height + 0.4, 0)), Vector3.new(size + 1.2, 0.8, size + 1.2), Color3.fromRGB(64, 60, 56), Enum.Material.Slate)
	for _, side in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local along = Vector3.new(side.Z, 0, side.X)
		for _, t in { -0.375, -0.125, 0.125, 0.375 } do
			local p = base + side * (size / 2 + 0.2) + along * (t * size) + Vector3.new(0, height + 2.2, 0)
			Kit.part(parent, "Almena", CFrame.new(p), Vector3.new(1.6, 2.8, 1.6), C.DarkStone, Enum.Material.Cobblestone)
		end
	end
	Kit.brazier(parent, base + Vector3.new(0, height + 0.8, 0), 1.1)
	-- Mástil con bandera.
	local pole = base + Vector3.new(size / 2 - 1, height + 0.8, size / 2 - 1)
	Kit.cylinder(parent, "Mastil", pole + Vector3.new(0, 5, 0), 10, 0.35, C.DarkWood, Enum.Material.Wood)
	Kit.part(parent, "Bandera", CFrame.new(pole + Vector3.new(0, 8.6, 1.8)), Vector3.new(0.12, 2.4, 3.6), C.Crimson, Enum.Material.Fabric, false)
end

local function fortress(parent: Instance)
	local span = HALF - 6 -- el tramo termina donde empiezan las torres
	-- Norte, este y oeste: un tramo entero.
	local north = facing(0, -HALF, 0, 0)
	wall(parent, north, span * 2)
	wallDecor(parent, north, { -45, -15, 15, 45 }, { -30, 0, 30 })
	local east = facing(HALF, 0, 0, 0)
	wall(parent, east, span * 2)
	wallDecor(parent, east, { -45, -15, 15, 45 }, { -30, 30 })
	local west = facing(-HALF, 0, 0, 0)
	wall(parent, west, span * 2)
	wallDecor(parent, west, { -45, -15, 15, 45 }, { -30, 30 })
	-- Sur: dos tramos con el portón en el medio.
	local gap = 8
	local piece = span - gap
	for _, side in { -1, 1 } do
		local cf = facing(side * (gap + piece / 2), HALF, side * (gap + piece / 2), 0)
		wall(parent, cf, piece)
		wallDecor(parent, cf, { side * -(piece / 2 - 12) }, { side * (piece / 2 - 26) })
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			tower(parent, at(sx * HALF, 0, sz * HALF), 12, 26)
		end
	end
	-- Portón: dos torres chicas, arco, rastrillo de hierro y cartel.
	for _, side in { -1, 1 } do
		tower(parent, at(side * (gap + 1), 0, HALF), 7, 22)
	end
	local gate = facing(0, HALF, 0, 0)
	Kit.part(parent, "Arco", gate * CFrame.new(0, WALL_HEIGHT + 2, 0), Vector3.new(gap * 2 - 5, 6, WALL_THICK + 1), C.DarkStone, Enum.Material.Cobblestone)
	local bars = gap * 2 - 5
	for x = -bars / 2 + 0.7, bars / 2 - 0.7, 1.4 do
		Kit.part(parent, "Barrote", gate * CFrame.new(x, 7.5, 0.4), Vector3.new(0.3, 15, 0.3), C.Iron, Enum.Material.Metal)
	end
	for y = 2, 14, 3 do
		Kit.part(parent, "Travesano", gate * CFrame.new(0, y, 0.4), Vector3.new(bars, 0.3, 0.3), C.Iron, Enum.Material.Metal)
	end
	Kit.sign(parent, gate * CFrame.new(0, WALL_HEIGHT + 2, -WALL_THICK / 2 - 0.65), Vector3.new(9, 2, 0.25), "LA CIUDADELA")
	Kit.banner(parent, gate * CFrame.new(0, WALL_HEIGHT - 1, -WALL_THICK / 2 - 0.7), 6, 7, C.Crimson)
end

-- ── Estaciones ──

-- Puesto de la tienda de armas o de la armería (`armory`). `cf` a ras del piso; el frente
-- (-Z local) mira hacia el spawn. El ProximityPrompt lleva OpenShop u OpenArmorShop = true.
local function shopStall(parent: Instance, cf: CFrame, armory: boolean)
	local awning = if armory
		then { Color3.fromRGB(46, 74, 128), Color3.fromRGB(200, 206, 216) }
		else { Color3.fromRGB(176, 52, 48), Color3.fromRGB(236, 222, 196) }
	local counter = Kit.part(parent, "Mostrador", cf * CFrame.new(0, 1.5, 0), Vector3.new(9, 3, 2.4), C.Wood, Enum.Material.WoodPlanks)
	Kit.part(parent, "Tablero", cf * CFrame.new(0, 3.1, 0), Vector3.new(9.4, 0.2, 2.8), C.DarkWood, Enum.Material.Wood)
	Kit.part(parent, "Estante", cf * CFrame.new(0, 3.5, 3.4), Vector3.new(9, 7, 0.6), C.DarkWood, Enum.Material.WoodPlanks)
	for _, y in { 2.6, 4.6 } do
		Kit.part(parent, "Repisa", cf * CFrame.new(0, y, 2.9), Vector3.new(8.6, 0.25, 0.9), C.Wood, Enum.Material.Wood, false)
	end
	for _, x in { -4.6, 4.6 } do
		for _, z in { -1.2, 3.4 } do
			Kit.part(parent, "Poste", cf * CFrame.new(x, 4.25, z), Vector3.new(0.5, 8.5, 0.5), C.DarkWood, Enum.Material.Wood)
		end
	end
	local stripes = 7
	local width = 10.4 / stripes
	for i = 1, stripes do
		local x = -5.2 + width * (i - 0.5)
		Kit.part(parent, "Toldo", cf * CFrame.new(x, 8.7, 1.1) * CFrame.Angles(math.rad(-12), 0, 0),
			Vector3.new(width, 0.25, 5.6), awning[(i % 2) + 1], Enum.Material.Fabric)
	end
	if armory then
		-- Yelmos en las repisas y una coraza en un soporte al costado.
		for i, x in { -3, 0, 3 } do
			local metal = Color3.fromRGB(150, 156, 166):Lerp(Color3.fromRGB(60, 50, 56), (i - 1) / 2)
			Kit.part(parent, "Yelmo", cf * CFrame.new(x, 5.25, 2.9), Vector3.new(1, 1.05, 1), metal, Enum.Material.Metal, false)
			Kit.part(parent, "Visera", cf * CFrame.new(x, 5.35, 2.39), Vector3.new(0.75, 0.08, 0.04), Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic, false)
		end
		local stand = cf * CFrame.new(5.6, 0, -0.4)
		Kit.part(parent, "Soporte", stand * CFrame.new(0, 1.6, 0), Vector3.new(0.3, 3.2, 0.3), C.DarkWood, Enum.Material.Wood)
		Kit.part(parent, "Coraza", stand * CFrame.new(0, 3.6, 0), Vector3.new(2.2, 1.9, 1.2), Color3.fromRGB(170, 176, 186), Enum.Material.Metal)
		Kit.part(parent, "Hombreras", stand * CFrame.new(0, 4.45, 0), Vector3.new(3, 0.45, 1.3), Color3.fromRGB(110, 114, 124), Enum.Material.Metal)
	else
		for i, x in { -3, 0, 3 } do
			Kit.sword(parent, cf * CFrame.new(x, 4.85, 2.9) * CFrame.Angles(0, 0, math.rad(20)), 2.4, Color3.fromRGB(200, 205, 212):Lerp(C.Gold, (i - 1) / 2))
		end
	end
	for i = 1, 4 do
		local coin = Kit.part(parent, "Moneda", cf * CFrame.new(-2.6 + i * 0.35, 3.25 + (i % 2) * 0.1, -0.4) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.1, 0.5, 0.5), C.Gold, Enum.Material.Metal, false)
		coin.Shape = Enum.PartType.Cylinder
	end
	local sign = Kit.sign(parent, cf * CFrame.new(0, 10.1, -1.4), Vector3.new(6, 1.6, 0.25), if armory then "ARMERÍA" else "TIENDA")
	for _, x in { -2.4, 2.4 } do
		Kit.part(parent, "Soporte", cf * CFrame.new(x, 8.9, -1.4), Vector3.new(0.2, 1.4, 0.2), C.DarkWood, Enum.Material.Wood, false)
	end
	local lamp = Instance.new("PointLight")
	lamp.Color, lamp.Range, lamp.Brightness = Color3.fromRGB(255, 210, 150), 14, 1.2
	lamp.Parent = sign
	-- Mercadería alrededor.
	Kit.barrel(parent, (cf * CFrame.new(-6.4, 0, 0.5)).Position)
	Kit.barrel(parent, (cf * CFrame.new(-6.2, 0, 3)).Position)
	if not armory then
		Kit.crate(parent, cf * CFrame.new(6.5, 0, 1) * CFrame.Angles(0, math.rad(12), 0), 2.6)
		Kit.crate(parent, cf * CFrame.new(6.4, 2.6, 1.2) * CFrame.Angles(0, math.rad(-8), 0), 1.8)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = if armory then "AbrirArmeria" else "AbrirTienda"
	prompt.ObjectText = if armory then "Armería" else "Tienda"
	prompt.ActionText = if armory then "Abrir armería" else "Abrir tienda"
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(if armory then "OpenArmorShop" else "OpenShop", true)
	prompt.Parent = counter
end

-- Pórtico del salón de la fama alrededor del tablero de récords (los dos usan Layout.RECORDS).
local function hallOfFame(parent: Instance)
	local cf = Layout.Facing(Layout.RECORDS)
	Kit.part(parent, "Tarima", cf * CFrame.new(0, 0.3, 0.6), Vector3.new(17, 0.6, 5), Color3.fromRGB(196, 186, 166), Enum.Material.Marble)
	for _, x in { -7, 7 } do
		Kit.part(parent, "Basa", cf * CFrame.new(x, 1, 0.6), Vector3.new(2.4, 0.8, 2.4), Color3.fromRGB(196, 186, 166), Enum.Material.Marble)
		Kit.cylinder(parent, "Columna", (cf * CFrame.new(x, 6.8, 0.6)).Position, 11, 1.7, Color3.fromRGB(214, 206, 190), Enum.Material.Marble)
	end
	Kit.part(parent, "Friso", cf * CFrame.new(0, 13, 0.6), Vector3.new(17, 1.4, 2.6), Color3.fromRGB(196, 186, 166), Enum.Material.Marble)
	Kit.wedge(parent, "Fronton", cf * CFrame.new(-4.25, 14.6, 0.6) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(2.6, 1.8, 8.5), Color3.fromRGB(196, 186, 166), Enum.Material.Marble)
	Kit.wedge(parent, "Fronton", cf * CFrame.new(4.25, 14.6, 0.6) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(2.6, 1.8, 8.5), Color3.fromRGB(196, 186, 166), Enum.Material.Marble)
	Kit.sign(parent, cf * CFrame.new(0, 13, -0.75), Vector3.new(12, 1.2, 0.12), "SALÓN DE LA FAMA")
	for _, x in { -9.8, 9.8 } do
		Kit.brazier(parent, (cf * CFrame.new(x, 0, -1)).Position, 0.8)
	end
end

-- ── Campo de entrenamiento ──

-- Muñeco de práctica: Model con Humanoid, todo anclado. CombatService lo trata como enemigo
-- (fuera de duelo); no da oro porque DungeonService solo escucha a sus guardianes.
local DUMMY_HEALTH = 500
local DUMMY_REGEN_DELAY = 3

local function dummy(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Muñeco de práctica"
	local straw = Color3.fromRGB(196, 166, 98)
	Kit.cylinder(model, "Base", cf.Position + Vector3.new(0, 0.25, 0), 0.5, 2.6, C.DarkWood, Enum.Material.Wood)
	Kit.part(model, "Poste", cf * CFrame.new(0, 2, 0), Vector3.new(0.5, 4, 0.5), C.Wood, Enum.Material.Wood)
	local root = Kit.part(model, "HumanoidRootPart", cf * CFrame.new(0, 4.6, 0), Vector3.new(2, 2, 1), straw, Enum.Material.Fabric, false)
	root.Transparency = 1
	local torso = Kit.part(model, "Torso", cf * CFrame.new(0, 4.6, 0), Vector3.new(2.2, 2.8, 1.3), straw, Enum.Material.Fabric)
	local head = Kit.part(model, "Head", cf * CFrame.new(0, 6.7, 0), Vector3.new(1.5, 1.5, 1.5), Color3.fromRGB(170, 138, 96), Enum.Material.Fabric)
	head.Shape = Enum.PartType.Ball
	Kit.part(model, "Brazos", cf * CFrame.new(0, 5.4, 0), Vector3.new(4.6, 0.45, 0.45), C.Wood, Enum.Material.Wood)
	for _, y in { 3.7, 5.5 } do
		Kit.part(model, "Soga", cf * CFrame.new(0, y, 0), Vector3.new(2.3, 0.18, 1.4), Color3.fromRGB(120, 96, 60), Enum.Material.Fabric, false)
	end
	-- Los golpes buscan partes con CanQuery.
	for _, p in { root, torso, head } do p.CanQuery = true end
	-- Diana pintada en el pecho.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = torso
	for i, color in { Color3.fromRGB(170, 30, 30), Color3.fromRGB(235, 225, 205), Color3.fromRGB(170, 30, 30) } do
		local circle = Instance.new("Frame")
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.fromScale(0.5, 0.45)
		circle.Size = UDim2.fromScale(0.8 - (i - 1) * 0.26, 0.8 - (i - 1) * 0.26)
		circle.BackgroundColor3 = color
		circle.Parent = gui
		Instance.new("UIAspectRatioConstraint", circle)
		Instance.new("UICorner", circle).CornerRadius = UDim.new(0.5, 0)
	end
	model.PrimaryPart = root
	root.PivotOffset = root.CFrame:ToObjectSpace(cf) -- gira desde la base, no desde el centro

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = DUMMY_HEALTH
	humanoid.Health = DUMMY_HEALTH
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	model.Parent = parent

	local lastHit = 0
	local last = humanoid.Health
	local wobbling = false
	humanoid.HealthChanged:Connect(function(health)
		local hit = health < last
		last = health
		if not hit or wobbling then return end
		lastHit = os.clock()
		wobbling = true
		task.spawn(function()
			for _, angle in { -9, 6, -3, 1.5, 0 } do
				if not model.Parent then break end
				model:PivotTo(cf * CFrame.Angles(math.rad(angle), 0, 0))
				task.wait(0.05)
			end
			wobbling = false
		end)
	end)
	-- Se cura solo si nadie le pega durante un rato; si lo rompen, vuelve a aparecer.
	task.spawn(function()
		while model.Parent and humanoid.Health > 0 do
			task.wait(0.5)
			if os.clock() - lastHit >= DUMMY_REGEN_DELAY and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end)
	humanoid.Died:Once(function()
		task.delay(0.6, function() model:Destroy() end)
		task.delay(3, function() dummy(parent, cf) end)
	end)
end

local function fence(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local posts = math.max(1, math.floor(length / 3.5))
	for i = 0, posts do
		local p = from:Lerp(to, i / posts)
		Kit.part(parent, "Valla", CFrame.new(p + Vector3.new(0, 1.5, 0)), Vector3.new(0.5, 3, 0.5), C.DarkWood, Enum.Material.Wood)
	end
	for _, y in { 1.2, 2.4 } do
		local mid = (from + to) / 2 + Vector3.new(0, y, 0)
		Kit.part(parent, "Travesano", CFrame.lookAt(mid, (to + Vector3.new(0, y, 0))), Vector3.new(0.25, 0.3, length), C.Wood, Enum.Material.Wood)
	end
end

-- `dir` = lado de la entrada: +1 este, -1 oeste (mirando hacia el spawn).
local function trainingGround(parent: Instance, cx: number, cz: number, dir: number)
	Kit.part(parent, "Tierra", CFrame.new(at(cx, 0.24, cz)), Vector3.new(22, 0.08, 18), Color3.fromRGB(120, 96, 70), Enum.Material.Ground, false)
	local front, back, z0, z1 = cx + dir * 11, cx - dir * 11, cz - 9, cz + 9
	fence(parent, at(back, 0, z0), at(front, 0, z0))
	fence(parent, at(back, 0, z1), at(front, 0, z1))
	fence(parent, at(back, 0, z0), at(back, 0, z1))
	-- Lado que da al camino, con entrada en el medio.
	fence(parent, at(front, 0, z0), at(front, 0, cz - 3))
	fence(parent, at(front, 0, cz + 3), at(front, 0, z1))
	for _, dz in { -5, 0, 5 } do
		dummy(parent, facing(cx - 4 * dir, cz + dz, cx + 20 * dir, cz + dz))
	end
	-- Estante de armas contra la valla del fondo.
	local rack = facing(cx - 9.5 * dir, cz, cx, cz)
	for _, x in { -2.5, 2.5 } do
		Kit.part(parent, "Estante", rack * CFrame.new(x, 1.75, 0), Vector3.new(0.4, 3.5, 0.4), C.DarkWood, Enum.Material.Wood)
	end
	Kit.part(parent, "Estante", rack * CFrame.new(0, 3.3, 0), Vector3.new(5.4, 0.3, 0.4), C.DarkWood, Enum.Material.Wood)
	for i = -2, 2 do
		Kit.sword(parent, rack * CFrame.new(i * 1, 0.2, -0.3) * CFrame.Angles(math.rad(-10), 0, 0), 3.4, Color3.fromRGB(190, 194, 200))
	end
	local signCf = facing(front + 0.6 * dir, cz - 4, Layout.SPAWN.X, Layout.SPAWN.Y)
	Kit.sign(parent, signCf * CFrame.new(0, 4.2, 0), Vector3.new(7, 1.4, 0.25), "ZONA DE PRÁCTICA")
	Kit.part(parent, "Poste", signCf * CFrame.new(0, 1.8, 0.3), Vector3.new(0.4, 3.6, 0.4), C.DarkWood, Enum.Material.Wood)
end

-- ── Arena de duelos (zona del menú de duelo) ──
--[[
	Coliseo chico: plataforma de piedra en dos gradas, arena con espadas cruzadas y laureles,
	anillo dorado que brilla y runas en el borde, cerco de pilares de piedra (puntas y gemas
	doradas) con barandas de madera y estandartes, entrada hacia la plaza con cartel y brasero,
	y detrás una muralla curva con torre-portal, escaleras, nichos con armas, estandartes,
	enredaderas, antorchas y cuencos de fuego.
]]
local function duelPit(parent: Instance)
	local cx, cz, R = Layout.ARENA.X, Layout.ARENA.Y, 12
	local center = at(cx, 0, cz)
	-- Zona del menú de duelo (DuelRules.InZone): al pisar la arena se abre el menú.
	workspace:SetAttribute("DuelZoneCenter", center)
	workspace:SetAttribute("DuelZoneRadius", R)

	local STONE = Color3.fromRGB(124, 114, 102)
	local STONE_DARK = Color3.fromRGB(86, 80, 74)
	local WALL = Color3.fromRGB(110, 100, 92)
	local SAND = Color3.fromRGB(216, 182, 128)
	local SAND_DARK = Color3.fromRGB(178, 142, 94)
	local GLOW = Color3.fromRGB(255, 190, 80)
	local VINE = Color3.fromRGB(70, 112, 48)
	local LEAF = Color3.fromRGB(96, 146, 60)
	local SLATE, COBBLE, FOIL, NEON = Enum.Material.Slate, Enum.Material.Cobblestone, Enum.Material.Foil, Enum.Material.Neon
	local V = Vector3.new

	local openAngle = math.atan2(origin.Z - center.Z, origin.X - center.X) -- hacia la plaza
	local back = openAngle + math.pi

	local function polar(r: number, a: number, y: number): Vector3
		return center + V(math.cos(a) * r, y, math.sin(a) * r)
	end
	-- CFrame en (r, a) mirando hacia el centro de la arena (-Z = hacia adentro).
	local function inward(r: number, a: number, y: number): CFrame
		local p = polar(r, a, y)
		return CFrame.lookAt(p, V(center.X, p.Y, center.Z))
	end
	-- Anillo (o arco) de piezas tangentes.
	local function arc(radius: number, y: number, width: number, height: number, color: Color3, material: Enum.Material, from: number, to: number)
		local span = to - from
		local count = math.max(8, math.ceil(math.abs(span) * radius / 1.5))
		local seg = math.abs(span) * radius / count + 0.1
		for i = 0, count - 1 do
			local a = from + (i + 0.5) / count * span
			local p = polar(radius, a, y)
			Kit.part(parent, "Anillo", CFrame.lookAt(p, p + V(-math.sin(a), 0, math.cos(a))), V(width, height, seg), color, material, false)
		end
	end
	local function glowAt(part: BasePart, range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness, l.Shadows = GLOW, range, brightness, false
		l.Parent = part
	end
	-- Pedestal de piedra con bandas doradas, runa de rayo y cuenco de fuego.
	local function pedestal(base: Vector3, faceTo: Vector3)
		local cf = CFrame.lookAt(base, V(faceTo.X, base.Y, faceTo.Z))
		Kit.part(parent, "Pedestal", cf * CFrame.new(0, 1.5, 0), V(2.4, 3, 2.4), STONE, COBBLE)
		Kit.part(parent, "Zocalo", cf * CFrame.new(0, 0.2, 0), V(2.9, 0.4, 2.9), STONE_DARK, SLATE)
		Kit.part(parent, "Losa", cf * CFrame.new(0, 3.2, 0), V(2.9, 0.4, 2.9), STONE_DARK, SLATE)
		for _, y in { 0.55, 2.85 } do
			Kit.part(parent, "Banda", cf * CFrame.new(0, y, 0), V(2.5, 0.2, 2.5), C.Gold, FOIL, false)
		end
		for _, b in { { 0.12, 1.85, 25 }, { -0.12, 1.3, 25 } } do
			Kit.part(parent, "Rayo", cf * CFrame.new(b[1], b[2], -1.23) * CFrame.Angles(0, 0, math.rad(b[3])), V(0.22, 0.75, 0.05), GLOW, NEON, false)
		end
		Kit.part(parent, "Rayo", cf * CFrame.new(0, 1.58, -1.23) * CFrame.Angles(0, 0, math.rad(-60)), V(0.18, 0.5, 0.05), GLOW, NEON, false)
		Kit.fireBowl(parent, base + V(0, 3.4, 0), 1)
	end

	-- ── Plataforma, arena y runas ──
	Kit.cylinder(parent, "Grada", polar(0, 0, 0.25), 0.5, (R + 5) * 2, STONE_DARK, SLATE)
	Kit.cylinder(parent, "Grada", polar(0, 0, 0.5), 1, (R + 3) * 2, STONE, COBBLE)
	Kit.cylinder(parent, "BordeRunas", polar(0, 0, 0.55), 1.1, (R + 1.6) * 2, Color3.fromRGB(100, 92, 84), SLATE)
	Kit.cylinder(parent, "Arena", polar(0, 0, 0.57), 1.14, R * 2, SAND, Enum.Material.Sand)
	arc(R + 4.95, 0.52, 0.3, 0.05, C.Gold, FOIL, 0, math.pi * 2)
	arc(R + 2.95, 1.02, 0.3, 0.05, C.Gold, FOIL, 0, math.pi * 2)
	arc(R + 0.12, 1.15, 0.3, 0.04, GLOW, NEON, 0, math.pi * 2)
	arc(R + 1.48, 1.12, 0.12, 0.03, GLOW, NEON, 0, math.pi * 2)
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2
		local p = polar(R + 0.8, a, 1.12)
		local cf = CFrame.lookAt(p, p + V(-math.sin(a), 0, math.cos(a)))
		Kit.part(parent, "Runa", cf * CFrame.Angles(0, math.rad(45), 0), V(0.5, 0.04, 0.5), GLOW, NEON, false)
		Kit.part(parent, "Runa", cf * CFrame.Angles(0, math.rad(45), 0), V(0.26, 0.05, 0.26), STONE_DARK, SLATE, false)
		for _, s in { -1, 1 } do
			Kit.part(parent, "Runa", cf * CFrame.new(0, 0, s * 0.5), V(0.08, 0.04, 0.3), GLOW, NEON, false)
		end
	end
	-- Espadas cruzadas y laureles dibujados en la arena (mirando a la entrada).
	local emblem = CFrame.lookAt(polar(0, 0, 1.16), polar(1, openAngle, 1.16))
	for _, ang in { 32, -32 } do
		local blade = emblem * CFrame.Angles(0, math.rad(ang), 0)
		Kit.part(parent, "Dibujo", blade * CFrame.new(0, 0, -0.6), V(0.6, 0.04, 8.4), SAND_DARK, Enum.Material.Sand, false)
		Kit.part(parent, "Dibujo", blade * CFrame.new(0, 0, 3.5), V(2.4, 0.04, 0.4), SAND_DARK, Enum.Material.Sand, false)
		Kit.part(parent, "Dibujo", blade * CFrame.new(0, 0, 4.3), V(0.32, 0.04, 1.2), SAND_DARK, Enum.Material.Sand, false)
	end
	for _, side in { -1, 1 } do
		for j = 0, 6 do
			local a = math.pi / 2 + side * (0.55 + j * 0.3)
			local leaf = emblem * CFrame.new(math.cos(a) * 4.6, 0, math.sin(a) * 4.6) * CFrame.Angles(0, -a + side * 0.6, 0)
			Kit.part(parent, "Laurel", leaf, V(0.4, 0.04, 1), SAND_DARK, Enum.Material.Sand, false)
		end
	end

	-- ── Cerco: pilares de piedra + barandas de madera (abierto hacia la plaza) ──
	local N, FR = 18, R + 2.2
	local step = math.pi * 2 / N
	for k = 1, N - 1 do
		local a = openAngle + k * step
		local cf = inward(FR, a, 0)
		local tall = k == 1 or k == N - 1
		local h = if tall then 6.2 else 3.8
		Kit.part(parent, "BasePilar", cf * CFrame.new(0, 1.25, 0), V(1.5, 0.5, 1.5), STONE_DARK, SLATE)
		Kit.part(parent, "Pilar", cf * CFrame.new(0, 1.5 + h / 2, 0), V(1.1, h, 1.1), STONE, COBBLE)
		Kit.part(parent, "Banda", cf * CFrame.new(0, 1.5 + h - 0.35, 0), V(1.22, 0.18, 1.22), C.Gold, FOIL, false)
		Kit.part(parent, "Capitel", cf * CFrame.new(0, 1.7 + h, 0), V(1.4, 0.4, 1.4), STONE_DARK, SLATE)
		Kit.part(parent, "Punta", cf * CFrame.new(0, 2.25 + h, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), V(0.62, 0.62, 0.62), C.Gold, Enum.Material.Metal, false)
		for _, z in { -0.56, 0.56 } do
			local gem = Kit.part(parent, "Gema", cf * CFrame.new(0, 1.5 + h * 0.62, z) * CFrame.Angles(0, 0, math.rad(45)), V(0.36, 0.36, 0.06), GLOW, NEON, false)
			if tall then
				Kit.part(parent, "Veta", cf * CFrame.new(0, 1.5 + h * 0.32, z), V(0.12, h * 0.36, 0.06), GLOW, NEON, false)
				if z < 0 then glowAt(gem, 10, 1.2) end
			end
		end
	end
	for k = 1, N - 2 do
		local a0, a1 = openAngle + k * step, openAngle + (k + 1) * step
		local p0, p1 = polar(FR, a0, 0), polar(FR, a1, 0)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude - 1.1
		local base = CFrame.lookAt(mid, mid + (p1 - p0))
		for _, y in { 2.3, 3.6 } do
			Kit.part(parent, "Baranda", base * CFrame.new(0, y, 0), V(0.35, 0.5, len), C.Wood, Enum.Material.Wood)
			for _, s in { -1, 1 } do
				Kit.part(parent, "Herraje", base * CFrame.new(0, y, s * (len / 2 - 0.25)), V(0.45, 0.62, 0.22), C.Iron, Enum.Material.Metal, false)
			end
		end
		Kit.part(parent, "Listón", base * CFrame.new(0, 2.95, 0), V(0.3, 1.6, 0.3), C.DarkWood, Enum.Material.Wood)
		if k % 3 == 2 then
			local am = (a0 + a1) / 2
			Kit.banner(parent, CFrame.lookAt(polar(FR + 0.4, am, 3.85), polar(FR + 5, am, 3.85)), 1.5, 2.2, C.Crimson)
		end
	end

	-- ── Entrada: cartel a un lado, brasero en pedestal al otro ──
	local signA = openAngle - step * 1.15
	local scf = CFrame.lookAt(polar(R + 4.3, signA, 0.5), polar(R + 14, signA, 0.5))
	for _, s in { -1, 1 } do
		Kit.part(parent, "PilarCartel", scf * CFrame.new(s * 3.9, 2.6, 0), V(0.9, 5.2, 0.9), STONE, COBBLE)
		Kit.part(parent, "Banda", scf * CFrame.new(s * 3.9, 5.35, 0), V(1.1, 0.3, 1.1), C.Gold, FOIL, false)
		Kit.part(parent, "Veta", scf * CFrame.new(s * 3.9, 2.8, -0.46), V(0.14, 3, 0.04), GLOW, NEON, false)
	end
	Kit.part(parent, "MarcoCartel", scf * CFrame.new(0, 4, 0.02), V(7.4, 2.4, 0.3), C.Gold, FOIL, false)
	local board = Kit.sign(parent, scf * CFrame.new(0, 4, 0), V(7, 2, 0.4), "ARENA DE DUELOS", true)
	glowAt(board, 9, 0.8)
	Kit.sword(parent, scf * CFrame.new(-0.8, 4.9, -0.1) * CFrame.Angles(0, 0, math.rad(-35)), 2.4, C.Gold)
	Kit.sword(parent, scf * CFrame.new(0.8, 4.9, -0.1) * CFrame.Angles(0, 0, math.rad(35)), 2.4, C.Gold)
	for _, s in { -1.8, 1.8 } do
		Kit.banner(parent, scf * CFrame.new(s, 2.85, 0.1), 1.2, 1.8, C.Crimson)
	end
	Kit.sign(parent, scf * CFrame.new(0, 1.6, -0.1), V(5.6, 0.6, 0.2), "Pisá la arena para desafiar")
	pedestal(polar(R + 4.3, openAngle + step * 1.15, 0.5), polar(R + 14, openAngle + step * 1.15, 0.5))
	for _, side in { -1, 1 } do
		pedestal(polar(R + 4.6, openAngle + side * 1.75, 0), center)
	end

	-- ── Muralla curva del fondo ──
	local RW = R + 10
	local half = math.rad(80)
	local segments = 18
	local seg = 2 * half * RW / segments + 0.15
	for i = 0, segments - 1 do
		local a = back - half + (i + 0.5) / segments * 2 * half
		local cf = inward(RW, a, 0)
		Kit.part(parent, "Muro", cf * CFrame.new(0, 6, 0), V(seg, 12, 2.5), WALL, COBBLE)
		Kit.part(parent, "Zocalo", cf * CFrame.new(0, 1, -1.5), V(seg, 2, 0.6), STONE_DARK, SLATE)
		Kit.part(parent, "Cornisa", cf * CFrame.new(0, 12.2, -0.1), V(seg, 0.4, 2.9), STONE_DARK, SLATE)
		Kit.part(parent, "Friso", cf * CFrame.new(0, 10.6, -1.27), V(seg, 0.22, 0.06), C.Gold, FOIL, false)
		if i % 2 == 0 then
			Kit.part(parent, "Almena", cf * CFrame.new(0, 13.8, 0), V(seg * 0.6, 2.8, 2.5), WALL, COBBLE)
		end
	end

	-- Torre-portal: pilastras con vetas doradas, estandarte, puerta enmarcada y escalinata.
	local tcf = inward(RW - 1.2, back, 0)
	Kit.part(parent, "Torre", tcf * CFrame.new(0, 9, 0), V(9, 18, 4.4), STONE_DARK, COBBLE)
	Kit.part(parent, "Cornisa", tcf * CFrame.new(0, 18.2, 0), V(9.8, 0.5, 5), Color3.fromRGB(64, 60, 56), SLATE)
	for _, x in { -3.6, -1.2, 1.2, 3.6 } do
		Kit.part(parent, "Almena", tcf * CFrame.new(x, 19.7, 0), V(1.6, 2.6, 4.4), STONE_DARK, COBBLE)
	end
	for _, s in { -1, 1 } do
		Kit.part(parent, "Pilastra", tcf * CFrame.new(s * 3.6, 9, -2.4), V(1.4, 18, 0.6), STONE, COBBLE)
		Kit.part(parent, "Veta", tcf * CFrame.new(s * 3.6, 9.5, -2.72), V(0.2, 13, 0.06), GLOW, NEON, false)
		Kit.part(parent, "Capitel", tcf * CFrame.new(s * 3.6, 17.6, -2.4), V(1.7, 0.4, 0.9), C.Gold, FOIL, false)
	end
	Kit.banner(parent, tcf * CFrame.new(0, 17.4, -2.55), 4.4, 7.5, C.Crimson)
	local doorBottom = 1.7
	Kit.part(parent, "Puerta", tcf * CFrame.new(0, doorBottom + 3, -2.21), V(3.6, 6, 0.1), Color3.fromRGB(26, 18, 14), Enum.Material.SmoothPlastic, false)
	for _, s in { -1, 1 } do
		Kit.part(parent, "Marco", tcf * CFrame.new(s * 2, doorBottom + 3.1, -2.3), V(0.35, 6.2, 0.25), C.Gold, FOIL, false)
	end
	Kit.part(parent, "Dintel", tcf * CFrame.new(0, doorBottom + 6.2, -2.3), V(4.35, 0.4, 0.25), C.Gold, FOIL, false)
	local keystone = Kit.part(parent, "Gema", tcf * CFrame.new(0, doorBottom + 7, -2.3) * CFrame.Angles(0, 0, math.rad(45)), V(0.7, 0.7, 0.1), GLOW, NEON, false)
	glowAt(keystone, 10, 1)
	for j = 1, 3 do
		local h = 0.5 + j * 0.4
		Kit.part(parent, "Escalon", tcf * CFrame.new(0, h / 2, -2.2 - (4 - j) * 0.5), V(5, h, (4 - j) * 1.0), STONE, SLATE)
	end
	for _, s in { -1, 1 } do
		Kit.lantern(parent, tcf * CFrame.new(s * 2.2, doorBottom, -2.7))
		local spot = (tcf * CFrame.new(s * 5.8, 0, -3.6)).Position
		pedestal(spot, center)
	end

	-- Nichos con armas a los costados de la torre.
	for _, side in { -1, 1 } do
		local acf = inward(RW - 1.3, back + side * math.rad(36), 0)
		Kit.part(parent, "Nicho", acf * CFrame.new(0, 4.2, 0), V(4.2, 5, 0.12), Color3.fromRGB(42, 32, 28), SLATE, false)
		for _, s in { -1, 1 } do
			Kit.part(parent, "Jamba", acf * CFrame.new(s * 2.45, 4.2, -0.3), V(0.7, 5.6, 0.7), STONE, COBBLE)
		end
		Kit.part(parent, "Dintel", acf * CFrame.new(0, 7.3, -0.3), V(5.6, 0.8, 0.7), STONE, COBBLE)
		Kit.part(parent, "Gema", acf * CFrame.new(0, 7.3, -0.68) * CFrame.Angles(0, 0, math.rad(45)), V(0.45, 0.45, 0.05), GLOW, NEON, false)
		local shelf = Kit.part(parent, "Repisa", acf * CFrame.new(0, 1.6, -0.5), V(4.6, 0.3, 1.2), STONE_DARK, SLATE)
		glowAt(shelf, 8, 0.9)
		local foot = acf * CFrame.new(0, 1.75, -0.35)
		if side < 0 then
			Kit.sword(parent, foot * CFrame.new(-1.2, 0, 0), 3.8, Color3.fromRGB(205, 210, 220))
			Kit.sword(parent, foot * CFrame.new(0, 0, 0), 4.2, Color3.fromRGB(190, 194, 200))
			Kit.sword(parent, foot * CFrame.new(1.2, 0, 0), 3.8, C.Gold)
		else
			Kit.sword(parent, foot * CFrame.new(-1.2, 0, 0), 4.2, C.Gold)
			-- Martillo con runa de rayo.
			local hammer = foot * CFrame.new(0.3, 0, 0)
			Kit.part(parent, "Mango", hammer * CFrame.new(0, 1.6, 0), V(0.25, 3.2, 0.25), C.DarkWood, Enum.Material.Wood, false)
			Kit.part(parent, "Cabeza", hammer * CFrame.new(0, 3.3, 0), V(1.6, 0.9, 0.9), C.Iron, Enum.Material.Metal, false)
			Kit.part(parent, "Runa", hammer * CFrame.new(0, 3.3, 0), V(1.62, 0.18, 0.92), Color3.fromRGB(110, 220, 255), NEON, false)
			for _, s in { -1, 1 } do
				Kit.part(parent, "Tapa", hammer * CFrame.new(s * 0.82, 3.3, 0), V(0.08, 1, 1), C.Gold, FOIL, false)
			end
			Kit.sword(parent, foot * CFrame.new(1.4, 0, 0), 3.6, Color3.fromRGB(150, 156, 166))
		end
		for _, s in { -1, 1 } do
			Kit.lantern(parent, acf * CFrame.new(s * 1.9, 0, -1.1))
		end
	end

	-- Estandartes grandes y chicos, antorchas (pocas: el sonido queda sutil) y enredaderas.
	for _, side in { -1, 1 } do
		Kit.banner(parent, inward(RW - 1.3, back + side * math.rad(64), 0) * CFrame.new(0, 11.6, 0), 4, 8, C.Crimson)
		Kit.banner(parent, inward(RW - 1.3, back + side * math.rad(18), 0) * CFrame.new(0, 11.2, 0), 2, 5, C.Crimson)
		Kit.torch(parent, inward(RW - 1.25, back + side * math.rad(50), 0) * CFrame.new(0, 6.5, 0))
		for _, deg in { 24, 56, 76 } do
			local vcf = inward(RW - 1.32, back + side * math.rad(deg), 0)
			for j = -1, 1 do
				local len = 3 + (j + 2) * 1.3
				Kit.part(parent, "Enredadera", vcf * CFrame.new(j * 0.45, 12 - len / 2, 0), V(0.22, len, 0.12), VINE, Enum.Material.Grass, false)
				for t = 1, math.floor(len / 0.9) do
					local dx = if t % 2 == 0 then 0.2 else -0.2
					Kit.part(parent, "Hoja", vcf * CFrame.new(j * 0.45 + dx, 12 - t * 0.9, -0.05) * CFrame.Angles(0, 0, math.rad(dx * 120)), V(0.5, 0.32, 0.08), LEAF, Enum.Material.Grass, false)
				end
			end
		end
	end
end

-- Polvo flotando sobre toda la plaza, iluminado por el atardecer.
local function dust(parent: Instance)
	local volume = Kit.part(parent, "Polvo", CFrame.new(at(0, 9, 0)), Vector3.new(HALF * 2, 14, HALF * 2), Color3.new(), Enum.Material.SmoothPlastic, false)
	volume.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Color = ColorSequence.new(Color3.fromRGB(255, 226, 180))
	e.LightEmission = 0.4
	e.Size = NumberSequence.new(0.12)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(6, 10)
	e.Rate = 30
	e.Speed = NumberRange.new(0.2, 0.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = volume
end

function LobbyService:Init()
	-- Centro del lobby (el spawn queda al sur, ver Lobby/Layout).
	origin, ground = Layout.Base()

	setupLighting()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	grounds(folder)
	fortress(folder)
	shopStall(folder, Layout.Facing(Layout.WEAPON_SHOP), false) -- armas
	shopStall(folder, Layout.Facing(Layout.ARMOR_SHOP), true) -- armaduras
	hallOfFame(folder)
	trainingGround(folder, Layout.TRAINING.X, Layout.TRAINING.Y, -1)
	duelPit(folder)
	dust(folder)
	folder.Parent = workspace
	task.spawn(mountains) -- el terreno tarda un poco; no frena el resto
end

return LobbyService
