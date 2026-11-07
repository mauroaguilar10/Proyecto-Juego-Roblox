--!strict
--[[
	LobbyService — La ciudadela: el lobby completo, armado por código alrededor del spawn.
	Owner: Dev B (Economía).

	Distribución (relativa al SpawnLocation; -Z es "norte"):
	  Centro      Plaza con mosaico y cuatro obeliscos con fuego.
	  Este  (+X)  Arco de la mazmorra (lo arma DungeonService).
	  Oeste (-X)  Salón de la fama alrededor del tablero de récords (el tablero lo arma RecordsService).
	  Norte (-Z)  Puesto de la tienda: su ProximityPrompt tiene OpenShop = true y UIController
	              abre la tienda al activarlo (no pasa por el servidor).
	  Sur   (+Z)  Estatua del campeón y portón de la fortaleza.
	  Sudoeste    Campo de entrenamiento con muñecos de práctica: se les puede pegar (CombatService
	              los trata como enemigos), muestran el daño y se curan solos. No dan oro.
	  Sudeste     Arena de duelos decorativa (los duelos se piden desde el menú).
	  Noroeste    Herrería.   Noreste: campamento.
	  Alrededor   Muralla con almenas, torres, estandartes y antorchas; montañas de terreno a lo lejos.

	También ajusta la iluminación general (atardecer cálido con bruma). Si alguien configura
	Lighting a mano en Studio, este servicio lo pisa al arrancar: ver setupLighting().
]]
local Lighting = game:GetService("Lighting")
local Kit = require(script.Parent:WaitForChild("Lobby"):WaitForChild("Kit"))
local LobbyService = {}

local C = Kit.Colors
local HALF = 66 -- media distancia entre murallas
local WALL_HEIGHT = 16
local WALL_THICK = 3
local PLAZA_RADIUS = 26

local origin = Vector3.zero -- posición del spawn
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

-- ── Plaza ──

local function ring(parent: Instance, radius: number, y: number, width: number, color: Color3, material: Enum.Material)
	local count = math.max(16, math.floor(radius * 3.2))
	local length = 2 * math.pi * radius / count + 0.1
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local cf = CFrame.new(at(math.cos(a) * radius, y, math.sin(a) * radius)) * CFrame.Angles(0, -a, 0)
		Kit.part(parent, "Anillo", cf, Vector3.new(width, 0.06, length), color, material, false)
	end
end

local function plaza(parent: Instance)
	Kit.part(parent, "Suelo", CFrame.new(at(0, 0.1, 0)), Vector3.new(HALF * 2, 0.2, HALF * 2), Color3.fromRGB(92, 86, 80), Enum.Material.Slate)
	Kit.cylinder(parent, "BordePlaza", at(0, 0.24, 0), 0.08, (PLAZA_RADIUS + 1.2) * 2, C.DarkStone, Enum.Material.Basalt)
	Kit.cylinder(parent, "Plaza", at(0, 0.27, 0), 0.08, PLAZA_RADIUS * 2, Color3.fromRGB(128, 118, 104), Enum.Material.Cobblestone)
	Kit.cylinder(parent, "Centro", at(0, 0.3, 0), 0.08, 20, Color3.fromRGB(198, 188, 168), Enum.Material.Marble)
	ring(parent, 10.4, 0.34, 0.5, C.Gold, Enum.Material.Foil)
	ring(parent, PLAZA_RADIUS - 1, 0.32, 0.6, C.Gold, Enum.Material.Foil)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + math.pi / 8
		local mid = (11 + PLAZA_RADIUS - 1.5) / 2
		local cf = CFrame.new(at(math.cos(a) * mid, 0.33, math.sin(a) * mid)) * CFrame.Angles(0, -a, 0)
		Kit.part(parent, "Rayo", cf, Vector3.new(PLAZA_RADIUS - 12.5, 0.06, 0.9), Color3.fromRGB(200, 190, 170), Enum.Material.Marble, false)
	end
	-- Caminos empedrados desde la plaza hasta la muralla.
	local length = HALF - PLAZA_RADIUS
	local mid = PLAZA_RADIUS + length / 2
	for _, dir in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local along = dir.X ~= 0
		local size = if along then Vector3.new(length, 0.08, 8) else Vector3.new(8, 0.08, length)
		local edge = if along then Vector3.new(length, 0.06, 0.5) else Vector3.new(0.5, 0.06, length)
		Kit.part(parent, "Camino", CFrame.new(at(dir.X * mid, 0.26, dir.Z * mid)), size, Color3.fromRGB(140, 128, 112), Enum.Material.Cobblestone, false)
		for _, side in { -4.2, 4.2 } do
			local offset = if along then Vector3.new(0, 0, side) else Vector3.new(side, 0, 0)
			Kit.part(parent, "BordeCamino", CFrame.new(at(dir.X * mid, 0.28, dir.Z * mid) + offset), edge, C.DarkStone, Enum.Material.Basalt, false)
		end
	end
	-- Obeliscos con fuego en las diagonales.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local p = at(sx * 15.6, 0, sz * 15.6)
			Kit.part(parent, "Basamento", CFrame.new(p + Vector3.new(0, 0.6, 0)), Vector3.new(3.4, 1.2, 3.4), C.DarkStone, Enum.Material.Slate)
			Kit.part(parent, "Obelisco", CFrame.new(p + Vector3.new(0, 5.7, 0)), Vector3.new(1.8, 9, 1.8), Color3.fromRGB(70, 66, 64), Enum.Material.Basalt)
			for _, face in { 0, 90, 180, 270 } do
				local cf = CFrame.new(p + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(face), 0) * CFrame.new(0, 0, -0.91)
				Kit.part(parent, "Runa", cf, Vector3.new(0.25, 5, 0.05), Color3.fromRGB(255, 150, 70), Enum.Material.Neon, false)
			end
			Kit.brazier(parent, p + Vector3.new(0, 10.2, 0), 0.6)
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

-- Puesto de la tienda. `cf` a ras del piso; el frente (-Z local) mira hacia el spawn.
local function shopStall(parent: Instance, cf: CFrame)
	local awning = { Color3.fromRGB(176, 52, 48), Color3.fromRGB(236, 222, 196) }
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
	for i, x in { -3, 0, 3 } do
		Kit.sword(parent, cf * CFrame.new(x, 4.85, 2.9) * CFrame.Angles(0, 0, math.rad(20)), 2.4, Color3.fromRGB(200, 205, 212):Lerp(C.Gold, (i - 1) / 2))
	end
	for i = 1, 4 do
		local coin = Kit.part(parent, "Moneda", cf * CFrame.new(-2.6 + i * 0.35, 3.25 + (i % 2) * 0.1, -0.4) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.1, 0.5, 0.5), C.Gold, Enum.Material.Metal, false)
		coin.Shape = Enum.PartType.Cylinder
	end
	local sign = Kit.sign(parent, cf * CFrame.new(0, 10.1, -1.4), Vector3.new(6, 1.6, 0.25), "TIENDA")
	for _, x in { -2.4, 2.4 } do
		Kit.part(parent, "Soporte", cf * CFrame.new(x, 8.9, -1.4), Vector3.new(0.2, 1.4, 0.2), C.DarkWood, Enum.Material.Wood, false)
	end
	local lamp = Instance.new("PointLight")
	lamp.Color, lamp.Range, lamp.Brightness = Color3.fromRGB(255, 210, 150), 14, 1.2
	lamp.Parent = sign
	-- Mercadería alrededor.
	Kit.barrel(parent, (cf * CFrame.new(-6.4, 0, 0.5)).Position)
	Kit.barrel(parent, (cf * CFrame.new(-6.2, 0, 3)).Position)
	Kit.crate(parent, cf * CFrame.new(6.5, 0, 1) * CFrame.Angles(0, math.rad(12), 0), 2.6)
	Kit.crate(parent, cf * CFrame.new(6.4, 2.6, 1.2) * CFrame.Angles(0, math.rad(-8), 0), 1.8)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AbrirTienda"
	prompt.ObjectText = "Tienda"
	prompt.ActionText = "Abrir tienda"
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenShop", true)
	prompt.Parent = counter
end

-- Pórtico del salón de la fama alrededor del tablero de récords (RecordsService lo pone en x = -14).
local function hallOfFame(parent: Instance)
	local cf = facing(-14, 0, 0, 0)
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

-- Poste indicador con flechas hacia cada lugar.
local function signpost(parent: Instance, x: number, z: number)
	local base = at(x, 0, z)
	Kit.cylinder(parent, "Poste", base + Vector3.new(0, 4, 0), 8, 0.6, C.DarkWood, Enum.Material.Wood)
	local targets = {
		{ "MAZMORRA", 14, 0 }, { "TIENDA", 0, -16 }, { "RÉCORDS", -14, 0 },
		{ "ENTRENAMIENTO", -34, 30 }, { "DUELOS", 34, 30 },
	}
	for i, t in targets do
		local target = at(t[2] :: number, 0, t[3] :: number)
		local dir = Vector3.new(target.X - base.X, 0, target.Z - base.Z).Unit
		local y = 7.4 - (i - 1) * 1.1
		local cf = CFrame.lookAt(base + Vector3.new(0, y, 0), base + Vector3.new(0, y, 0) + dir) * CFrame.Angles(0, math.rad(90), 0)
		local text = t[1] :: string
		local length = 1.2 + #text * 0.32
		Kit.sign(parent, cf * CFrame.new(length / 2 + 0.3, 0, 0), Vector3.new(length, 0.85, 0.15), text, true)
	end
end

-- ── Estatua del campeón ──

local function statue(parent: Instance)
	local cf = facing(0, 46, 0, 0)
	local marble = Color3.fromRGB(206, 200, 188)
	local k = 2.6
	Kit.part(parent, "Pedestal", cf * CFrame.new(0, 0.5, 0), Vector3.new(15, 1, 15), C.DarkStone, Enum.Material.Slate)
	Kit.part(parent, "Pedestal", cf * CFrame.new(0, 3, 0), Vector3.new(11, 4, 11), Color3.fromRGB(86, 80, 76), Enum.Material.Basalt)
	Kit.part(parent, "Pedestal", cf * CFrame.new(0, 5.4, 0), Vector3.new(12, 0.8, 12), C.DarkStone, Enum.Material.Slate)
	Kit.sign(parent, cf * CFrame.new(0, 3, -5.62), Vector3.new(8, 1.6, 0.2), "EL PRIMER CAMPEÓN")
	local y0 = 5.8
	local function block(name: string, local_: CFrame, size: Vector3, color: Color3?, material: Enum.Material?)
		Kit.part(parent, name, cf * local_, size * k, color or marble, material or Enum.Material.Marble)
	end
	-- Piernas en guardia (la izquierda adelantada).
	block("Pierna", CFrame.new(-0.55 * k, y0 + 1 * k, -0.35 * k), Vector3.new(0.95, 2, 1))
	block("Pierna", CFrame.new(0.55 * k, y0 + 1 * k, 0.25 * k), Vector3.new(0.95, 2, 1))
	block("Torso", CFrame.new(0, y0 + 3 * k, 0), Vector3.new(2.1, 2, 1.1))
	block("Cinturon", CFrame.new(0, y0 + 2.15 * k, 0), Vector3.new(2.2, 0.3, 1.2), C.Gold, Enum.Material.Foil)
	block("Hombrera", CFrame.new(-1.15 * k, y0 + 3.9 * k, 0), Vector3.new(1.2, 0.5, 1.3))
	block("Hombrera", CFrame.new(1.15 * k, y0 + 3.9 * k, 0), Vector3.new(1.2, 0.5, 1.3))
	block("Cabeza", CFrame.new(0, y0 + 4.6 * k, 0), Vector3.new(1.1, 1.1, 1.1))
	block("Casco", CFrame.new(0, y0 + 4.85 * k, 0), Vector3.new(1.3, 0.8, 1.3))
	block("Penacho", CFrame.new(0, y0 + 5.45 * k, 0.1 * k), Vector3.new(0.2, 0.8, 1.3), C.Gold, Enum.Material.Foil)
	block("Capa", CFrame.new(0, y0 + 2.3 * k, 0.62 * k) * CFrame.Angles(math.rad(8), 0, 0), Vector3.new(2.2, 3.2, 0.15))
	-- Brazo derecho en alto con la espada.
	block("Brazo", CFrame.new(1.55 * k, y0 + 4.8 * k, 0), Vector3.new(0.9, 2, 0.9))
	Kit.sword(parent, cf * CFrame.new(1.55 * k, y0 + 5.7 * k, 0), 3.6 * k, C.Gold)
	-- Brazo izquierdo al frente con el escudo.
	local arm = CFrame.new(-1.55 * k, y0 + 3.8 * k, 0) * CFrame.Angles(math.rad(70), 0, 0) * CFrame.new(0, -1 * k, 0)
	block("Brazo", arm, Vector3.new(0.9, 2, 0.9))
	local hand = cf * arm * CFrame.new(0, -1 * k, 0)
	local shield = Kit.part(parent, "Escudo", CFrame.new(hand.Position + cf.LookVector * 0.5 * k) * cf.Rotation * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(0.3, 2.6, 2.6) * k, marble, Enum.Material.Marble)
	shield.Shape = Enum.PartType.Cylinder
	Kit.part(parent, "Umbo", CFrame.new(hand.Position + cf.LookVector * 0.95 * k) * cf.Rotation, Vector3.new(0.6, 0.6, 0.3) * k, C.Gold, Enum.Material.Foil, false)
	-- Reflectores al pie que la iluminan desde abajo.
	for _, x in { -5, 5 } do
		local from = (cf * CFrame.new(x, 1.2, -7.5)).Position
		local lamp = Kit.part(parent, "Reflector", CFrame.lookAt(from, (cf * CFrame.new(0, y0 + 3 * k, 0)).Position), Vector3.new(0.8, 0.8, 0.8), C.Iron, Enum.Material.Metal)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Color, spot.Range, spot.Angle, spot.Brightness = Color3.fromRGB(255, 214, 160), 32, 50, 3
		spot.Parent = lamp
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

local function trainingGround(parent: Instance)
	local cx, cz = -34, 30
	Kit.part(parent, "Tierra", CFrame.new(at(cx, 0.24, cz)), Vector3.new(22, 0.08, 18), Color3.fromRGB(120, 96, 70), Enum.Material.Ground, false)
	local x0, x1, z0, z1 = cx - 11, cx + 11, cz - 9, cz + 9
	fence(parent, at(x0, 0, z0), at(x1, 0, z0))
	fence(parent, at(x0, 0, z1), at(x1, 0, z1))
	fence(parent, at(x0, 0, z0), at(x0, 0, z1))
	-- Lado que da a la plaza (este) con entrada en el medio.
	fence(parent, at(x1, 0, z0), at(x1, 0, cz - 3))
	fence(parent, at(x1, 0, cz + 3), at(x1, 0, z1))
	for _, dz in { -5, 0, 5 } do
		dummy(parent, facing(cx - 4, cz + dz, cx + 20, cz + dz))
	end
	-- Estante de armas contra la valla del fondo.
	local rack = facing(cx - 9.5, cz, cx, cz)
	for _, x in { -2.5, 2.5 } do
		Kit.part(parent, "Estante", rack * CFrame.new(x, 1.75, 0), Vector3.new(0.4, 3.5, 0.4), C.DarkWood, Enum.Material.Wood)
	end
	Kit.part(parent, "Estante", rack * CFrame.new(0, 3.3, 0), Vector3.new(5.4, 0.3, 0.4), C.DarkWood, Enum.Material.Wood)
	for i = -2, 2 do
		Kit.sword(parent, rack * CFrame.new(i * 1, 0.2, -0.3) * CFrame.Angles(math.rad(-10), 0, 0), 3.4, Color3.fromRGB(190, 194, 200))
	end
	Kit.sign(parent, facing(x1 + 0.6, cz - 4, 0, 0) * CFrame.new(0, 4.2, 0), Vector3.new(7, 1.4, 0.25), "CAMPO DE ENTRENAMIENTO")
	Kit.part(parent, "Poste", facing(x1 + 0.6, cz - 4, 0, 0) * CFrame.new(0, 1.8, 0.3), Vector3.new(0.4, 3.6, 0.4), C.DarkWood, Enum.Material.Wood)
end

-- ── Arena de duelos (decorativa) ──

local function duelPit(parent: Instance)
	local cx, cz, radius = 34, 30, 12
	Kit.cylinder(parent, "Arena", at(cx, 0.3, cz), 0.12, radius * 2, Color3.fromRGB(200, 174, 124), Enum.Material.Sand)
	ring(parent, radius, 0.36, 0.8, C.DarkStone, Enum.Material.Slate)
	-- Cerco de postes con cuerda; abierto hacia la plaza.
	local count = 18
	local center = at(cx, 0, cz)
	local openAngle = math.atan2(origin.Z - center.Z, origin.X - center.X)
	local function postAt(i: number): Vector3
		local a = openAngle + (i + 1) / count * math.pi * 2
		return center + Vector3.new(math.cos(a) * (radius + 0.8), 0, math.sin(a) * (radius + 0.8))
	end
	for i = 0, count - 3 do
		local p = postAt(i)
		Kit.part(parent, "Poste", CFrame.new(p + Vector3.new(0, 1.6, 0)), Vector3.new(0.5, 3.2, 0.5), C.DarkWood, Enum.Material.Wood)
		if i < count - 3 then
			local q = postAt(i + 1)
			local mid = (p + q) / 2 + Vector3.new(0, 2.4, 0)
			Kit.part(parent, "Cuerda", CFrame.lookAt(mid, q + Vector3.new(0, 2.4, 0)), Vector3.new(0.15, 0.15, (q - p).Magnitude), Color3.fromRGB(206, 186, 140), Enum.Material.Fabric, false)
		end
	end
	-- Braseros a los dos lados de la entrada (afuera del cerco).
	for _, side in { -1, 1 } do
		local a = openAngle + side * 1.6 / count * math.pi * 2
		Kit.brazier(parent, center + Vector3.new(math.cos(a) * (radius + 2.6), 0, math.sin(a) * (radius + 2.6)), 0.9)
	end
	-- Armas clavadas en la arena.
	Kit.sword(parent, CFrame.new(at(cx - 3, 0, cz + 2)) * CFrame.Angles(math.rad(14), 0, math.rad(-10)), 4.5, Color3.fromRGB(190, 194, 200))
	Kit.sword(parent, CFrame.new(at(cx + 2, 0, cz - 3)) * CFrame.Angles(math.rad(-12), 0, math.rad(16)), 4.5, Color3.fromRGB(190, 194, 200))
	local signCf = facing(cx - 15, cz - 9, 0, 0)
	Kit.part(parent, "Poste", signCf * CFrame.new(0, 2, 0.3), Vector3.new(0.4, 4, 0.4), C.DarkWood, Enum.Material.Wood)
	Kit.sign(parent, signCf * CFrame.new(0, 4.6, 0), Vector3.new(6, 1.4, 0.25), "ARENA DE DUELOS")
	Kit.sign(parent, signCf * CFrame.new(0, 3.5, 0), Vector3.new(6, 0.7, 0.2), "Desafiá a otro jugador desde el menú")
	Kit.banner(parent, signCf * CFrame.new(-3.6, 5.6, 0.3), 2, 3.5, C.Crimson)
end

-- ── Herrería y campamento ──

local function forge(parent: Instance)
	local cf = facing(-38, -36, 0, 0)
	Kit.part(parent, "Fragua", cf * CFrame.new(0, 2.5, 0), Vector3.new(8, 5, 6), C.DarkStone, Enum.Material.Cobblestone)
	local mouth = Kit.part(parent, "Boca", cf * CFrame.new(0, 2.2, -2.95), Vector3.new(4, 2.4, 0.2), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, false)
	local f = Instance.new("Fire")
	f.Size, f.Heat = 4, 4
	f.Color, f.SecondaryColor = Color3.fromRGB(255, 140, 50), Color3.fromRGB(255, 220, 120)
	f.Parent = mouth
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = Color3.fromRGB(255, 140, 60), 20, 2.5
	glow.Parent = mouth
	Kit.embers(mouth, 10)
	local chimney = Kit.part(parent, "Chimenea", cf * CFrame.new(0, 9, 1.5), Vector3.new(2.6, 8, 2.6), Color3.fromRGB(70, 66, 62), Enum.Material.Cobblestone)
	local smoke = Instance.new("Smoke")
	smoke.Color, smoke.Opacity, smoke.RiseVelocity, smoke.Size = Color3.fromRGB(90, 86, 84), 0.15, 4, 2
	smoke.Parent = chimney
	-- Yunque con martillo.
	local anvil = cf * CFrame.new(0, 0, -6.5)
	Kit.part(parent, "Tronco", anvil * CFrame.new(0, 0.9, 0), Vector3.new(1.8, 1.8, 1.8), C.DarkWood, Enum.Material.Wood)
	Kit.part(parent, "Yunque", anvil * CFrame.new(0, 2.15, 0), Vector3.new(1, 0.7, 0.8), C.Iron, Enum.Material.Metal)
	Kit.part(parent, "Yunque", anvil * CFrame.new(0, 2.75, 0), Vector3.new(2.6, 0.5, 1.1), C.Iron, Enum.Material.Metal)
	Kit.part(parent, "Martillo", anvil * CFrame.new(0.4, 3.15, 0.1) * CFrame.Angles(0, math.rad(30), 0), Vector3.new(1.6, 0.18, 0.18), C.DarkWood, Enum.Material.Wood, false)
	Kit.part(parent, "Martillo", anvil * CFrame.new(-0.3, 3.2, -0.3) * CFrame.Angles(0, math.rad(30), 0), Vector3.new(0.35, 0.35, 0.6), C.Iron, Enum.Material.Metal, false)
	-- Tina de agua para templar.
	Kit.barrel(parent, (cf * CFrame.new(4.5, 0, -5.5)).Position)
	Kit.cylinder(parent, "Agua", (cf * CFrame.new(4.5, 2.9, -5.5)).Position, 0.1, 1.9, Color3.fromRGB(60, 100, 130), Enum.Material.Glass, false)
	-- Armas terminadas apoyadas en la pared de la fragua.
	for i = -1, 1 do
		Kit.sword(parent, cf * CFrame.new(-6 + i * 0.9, 0, -1) * CFrame.Angles(math.rad(-12), 0, 0), 3.6, Color3.fromRGB(196, 200, 206))
	end
	local signCf = cf * CFrame.new(0, 0, -3.1)
	Kit.sign(parent, signCf * CFrame.new(0, 5.8, 0), Vector3.new(5, 1.2, 0.25), "HERRERÍA")
end

local function tent(parent: Instance, cf: CFrame, color: Color3)
	local half, height = 3, 4.5
	local slope = math.sqrt(half * half + height * height)
	local angle = math.atan2(height, half)
	for _, side in { -1, 1 } do
		Kit.part(parent, "Lona", cf * CFrame.new(0, height / 2, side * half / 2) * CFrame.Angles(side * (math.pi / 2 - angle), 0, 0),
			Vector3.new(6, 0.2, slope), color, Enum.Material.Fabric)
	end
	Kit.part(parent, "Cumbrera", cf * CFrame.new(0, height, 0), Vector3.new(6.6, 0.3, 0.3), C.DarkWood, Enum.Material.Wood, false)
	for _, x in { -3.2, 3.2 } do
		Kit.part(parent, "Palo", cf * CFrame.new(x, height / 2, 0), Vector3.new(0.25, height, 0.25), C.DarkWood, Enum.Material.Wood, false)
	end
end

local function camp(parent: Instance)
	local center = at(36, 0, -32)
	tent(parent, facing(30, -38, 36, -32), C.Crimson)
	tent(parent, facing(43, -36, 36, -32), C.Ivory)
	-- Fogata.
	for i = 0, 3 do
		local a = i / 4 * math.pi
		Kit.part(parent, "Leño", CFrame.new(center + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, a, math.rad(15)), Vector3.new(2.6, 0.45, 0.45), C.DarkWood, Enum.Material.Wood, false)
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Kit.part(parent, "Piedra", CFrame.new(center + Vector3.new(math.cos(a) * 1.8, 0.3, math.sin(a) * 1.8)), Vector3.new(0.8, 0.6, 0.8), C.DarkStone, Enum.Material.Slate, false)
	end
	local flame = Kit.part(parent, "Fogata", CFrame.new(center + Vector3.new(0, 0.8, 0)), Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, false)
	flame.Transparency = 0.4
	local f = Instance.new("Fire")
	f.Size, f.Heat = 5, 8
	f.Parent = flame
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = Color3.fromRGB(255, 150, 70), 22, 2.4
	glow.Parent = flame
	Kit.embers(flame, 8)
	-- Bancos de tronco y provisiones.
	for _, offset in { Vector3.new(-3.5, 0, 2.5), Vector3.new(3.5, 0, 2.5) } do
		local log = Kit.cylinder(parent, "Banco", center + offset + Vector3.new(0, 0.5, 0), 3, 1, C.Wood, Enum.Material.Wood)
		log.CFrame = CFrame.new(log.Position) * CFrame.Angles(0, math.rad(90), 0)
	end
	Kit.crate(parent, facing(47, -26, 36, -32), 2.8)
	Kit.crate(parent, facing(49, -29, 36, -32) * CFrame.Angles(0, math.rad(20), 0), 2.2)
	Kit.barrel(parent, at(26, 0, -27))
	Kit.barrel(parent, at(27.5, 0, -25))
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
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	origin = if spawn then spawn.Position else Vector3.zero
	ground = if spawn then origin.Y - spawn.Size.Y / 2 else 0

	setupLighting()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	plaza(folder)
	fortress(folder)
	shopStall(folder, facing(0, -16, 0, 0))
	hallOfFame(folder)
	signpost(folder, 10, -10)
	statue(folder)
	trainingGround(folder)
	duelPit(folder)
	forge(folder)
	camp(folder)
	dust(folder)
	folder.Parent = workspace
	task.spawn(mountains) -- el terreno tarda un poco; no frena el resto
end

return LobbyService
