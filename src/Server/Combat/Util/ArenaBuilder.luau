--!strict
--[[
	ArenaBuilder — Coliseo de duelo 1v1, armado por código (una copia por duelo).
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como servicio.
	Reusa las piezas del lobby (Economy/Lobby/Kit) para mantener el mismo estilo.

	Vista desde arriba (Z+ = puerta azul, Z− = puerta roja):

	            ┌──── gradas con público (TIERS escalones) ────┐
	            │   ╭──────── muro de piedra + estandartes ──╮  │
	   palco ◄──│   │  ◯ spawn rojo   ✦ centro   spawn azul ◯ │  │
	            │   ╰─── puerta roja ─────────── puerta azul ─╯  │
	            └── braseros arriba, muro exterior que cierra ──┘

	Jugable: círculo de radio FIGHT_RADIUS. Una barrera invisible sobre el muro evita salir
	saltando. Todo lo decorativo es CanQuery = false (Kit), salvo el piso: los efectos del
	cliente (CombatFx) hacen raycast hacia abajo para encontrarlo.
]]

local Kit = require(script.Parent.Parent.Parent:WaitForChild("Economy"):WaitForChild("Lobby"):WaitForChild("Kit"))

local ArenaBuilder = {}

-- ── Medidas (studs) ──
local FIGHT_RADIUS = 32 -- cara interna del muro
local SPAWN_DISTANCE = 21 -- desde el centro, sobre el eje Z
local SEGMENTS = 32 -- piezas por anillo (muro, barrera, gradas)
local WALL_HEIGHT = 16 -- el salto normal llega a ~7 studs: no se puede trepar
local WALL_THICKNESS = 2
local BARRIER_HEIGHT = 60 -- altura total de la barrera invisible
local GATE_HEIGHT = 10
local TIERS = 5
local TIER_DEPTH = 3.5
local TIER_RISE = 2.5
local OUTER_WALL_THICKNESS = 1.5
local CROWD_PER_TIER = 20
local GATE_INDEX = { Blue = 0, Red = SEGMENTS // 2 } -- θ = 0 → +Z, θ = π → −Z

-- ── Colores ──
local c = Kit.Colors
local SAND = Color3.fromRGB(214, 186, 140)
local DARK_SAND = Color3.fromRGB(176, 146, 104)
local RED = Color3.fromRGB(150, 32, 34)
local BLUE = Color3.fromRGB(40, 72, 150)
local TUNNEL = Color3.fromRGB(14, 11, 10)
local SHIRTS = {
	Color3.fromRGB(150, 32, 34), Color3.fromRGB(40, 72, 150), Color3.fromRGB(196, 160, 80),
	Color3.fromRGB(90, 110, 60), Color3.fromRGB(120, 70, 120), Color3.fromRGB(220, 210, 190),
	Color3.fromRGB(160, 90, 40), Color3.fromRGB(70, 70, 80),
}
local SKINS = {
	Color3.fromRGB(255, 220, 185), Color3.fromRGB(234, 184, 146), Color3.fromRGB(196, 140, 100),
	Color3.fromRGB(140, 94, 64), Color3.fromRGB(96, 64, 44),
}

local TAU = math.pi * 2
local SEGMENT_ANGLE = TAU / SEGMENTS

-- ── Helpers ──

-- CFrame en el anillo: ángulo θ (0 = +Z), a `radius` del centro y altura `y`. Local +Z mira
-- hacia afuera (radial), local X es tangente.
local function onRing(center: Vector3, theta: number, radius: number, y: number): CFrame
	return CFrame.new(center + Vector3.new(math.sin(theta) * radius, y, math.cos(theta) * radius))
		* CFrame.Angles(0, theta, 0)
end

-- Mirando hacia el centro de la arena (para antorchas/estandartes: su -Z apunta al centro).
local function facingCenter(center: Vector3, theta: number, radius: number, y: number): CFrame
	local at = center + Vector3.new(math.sin(theta) * radius, y, math.cos(theta) * radius)
	return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
end

-- Un anillo de bloques entre `inner` y `inner + depth`, de `bottom` a `bottom + height`.
-- `skip`: índices de segmento que se dejan vacíos (puertas).
local function ring(parent: Instance, name: string, center: Vector3, inner: number, depth: number,
	bottom: number, height: number, color: Color3, material: Enum.Material, solid: boolean, skip: { [number]: boolean }?): { Part }
	local parts = {}
	local mid = inner + depth / 2
	local length = TAU * (inner + depth) / SEGMENTS + 0.15 -- medido en el borde externo: sin huecos
	for i = 0, SEGMENTS - 1 do
		if skip and skip[i] then
			continue
		end
		local cf = onRing(center, i * SEGMENT_ANGLE, mid, bottom + height / 2)
		table.insert(parts, Kit.part(parent, name, cf, Vector3.new(length, height, depth), color, material, solid))
	end
	return parts
end

-- Disco plano sobre el piso (decoración, sin colisión).
local function disc(parent: Instance, name: string, at: Vector3, diameter: number, color: Color3, material: Enum.Material)
	Kit.cylinder(parent, name, at, 0.1, diameter, color, material, false)
end

-- ── Partes de la arena ──

local function buildFloor(model: Model, center: Vector3, ground: number)
	local outer = FIGHT_RADIUS + TIERS * TIER_DEPTH + WALL_THICKNESS + OUTER_WALL_THICKNESS
	Kit.cylinder(model, "Cimientos", center + Vector3.new(0, ground - 1.5, 0), 2, outer * 2 + 1, c.DarkStone, Enum.Material.Slate)
	local floor = Kit.cylinder(model, "Piso", center + Vector3.new(0, ground - 0.5, 0), 1, (FIGHT_RADIUS + WALL_THICKNESS) * 2, SAND, Enum.Material.Sand)
	floor.CanQuery = true -- CombatFx busca el piso con raycast

	-- Marcas en la arena: anillo central con un emblema y los círculos de cada puerta.
	local y = ground + 0.05
	disc(model, "AnilloCentral", center + Vector3.new(0, y, 0), 16, DARK_SAND, Enum.Material.Sand)
	disc(model, "Centro", center + Vector3.new(0, y + 0.02, 0), 14, SAND, Enum.Material.Sand)
	disc(model, "Sello", center + Vector3.new(0, y + 0.04, 0), 4, c.Gold, Enum.Material.Metal)
	disc(model, "SelloInterior", center + Vector3.new(0, y + 0.06, 0), 3, c.DarkStone, Enum.Material.Slate)
	for _, angle in { 0, 90 } do
		Kit.part(model, "LineaCentral", CFrame.new(center + Vector3.new(0, y + 0.01, 0)) * CFrame.Angles(0, math.rad(angle), 0),
			Vector3.new(0.4, 0.1, FIGHT_RADIUS * 1.6), DARK_SAND, Enum.Material.Sand, false)
	end
	for side, z in { Red = -SPAWN_DISTANCE, Blue = SPAWN_DISTANCE } do
		local color = if side == "Red" then RED else BLUE
		local at = center + Vector3.new(0, y + 0.08, z)
		disc(model, `Marca{side}`, at, 7, color, Enum.Material.Fabric)
		disc(model, `MarcaInterior{side}`, at + Vector3.new(0, 0.02, 0), 5.6, SAND, Enum.Material.Sand)
	end
end

-- Puerta con rastrillo: hueco en el muro, columnas, dintel con cartel, rejas y túnel oscuro.
local function buildGate(model: Model, center: Vector3, ground: number, index: number, color: Color3, label: string)
	local theta = index * SEGMENT_ANGLE
	local width = TAU * (FIGHT_RADIUS + WALL_THICKNESS) / SEGMENTS + 0.15
	local mid = FIGHT_RADIUS + WALL_THICKNESS / 2
	local gateHeight = GATE_HEIGHT
	local base = onRing(center, theta, mid, ground)

	-- Muro encima de la puerta, hasta la altura del resto.
	Kit.part(model, "MuroPuerta", base * CFrame.new(0, (gateHeight + WALL_HEIGHT) / 2, 0),
		Vector3.new(width, WALL_HEIGHT - gateHeight, WALL_THICKNESS), c.Stone, Enum.Material.Cobblestone)

	-- Fondo oscuro justo detrás de las rejas (antes de la cara de las gradas): se ve como túnel.
	Kit.part(model, "Tunel", base * CFrame.new(0, gateHeight / 2, WALL_THICKNESS / 2 - 0.1),
		Vector3.new(width, gateHeight, 0.2), TUNNEL, Enum.Material.Slate, false)
	for _, x in { -1, 1 } do
		local pillar = base * CFrame.new(x * (width / 2 + 0.6), 0, 0)
		-- Columnas de toda la altura del muro, con un brasero arriba.
		Kit.part(model, "Columna", pillar * CFrame.new(0, (WALL_HEIGHT + 1) / 2, 0), Vector3.new(1.6, WALL_HEIGHT + 1, WALL_THICKNESS + 0.6), c.DarkStone, Enum.Material.Cobblestone)
		Kit.brazier(model, (pillar * CFrame.new(0, WALL_HEIGHT + 1, 0)).Position, 0.7)
	end
	Kit.part(model, "Dintel", base * CFrame.new(0, gateHeight - 0.6, 0), Vector3.new(width + 1.4, 1.2, WALL_THICKNESS + 0.4), c.DarkStone, Enum.Material.Slate)
	Kit.part(model, "Franja", base * CFrame.new(0, gateHeight - 1.35, -WALL_THICKNESS / 2 - 0.2), Vector3.new(width + 1.4, 0.3, 0.1), color, Enum.Material.Fabric, false)

	-- Rejas: sólidas, así la puerta también cierra la arena.
	local bars = 7
	for i = 1, bars do
		local x = -width / 2 + width * (i - 0.5) / bars
		Kit.part(model, "Reja", base * CFrame.new(x, (gateHeight - 1.2) / 2, 0), Vector3.new(0.35, gateHeight - 1.2, 0.35), c.Iron, Enum.Material.Metal)
	end
	for _, y in { 2, gateHeight - 3 } do
		Kit.part(model, "Travesaño", base * CFrame.new(0, y, 0), Vector3.new(width, 0.3, 0.3), c.Iron, Enum.Material.Metal, false)
	end

	-- Cartel sobre el dintel, mirando al centro.
	local sign = facingCenter(center, theta, FIGHT_RADIUS - 0.1, ground + gateHeight + 0.9)
	local board = Kit.sign(model, sign, Vector3.new(6, 1.4, 0.3), label)
	board.CanCollide = false
end

local function buildWall(model: Model, center: Vector3, ground: number)
	local skip = { [GATE_INDEX.Blue] = true, [GATE_INDEX.Red] = true }
	ring(model, "Muro", center, FIGHT_RADIUS, WALL_THICKNESS, ground, WALL_HEIGHT, c.Stone, Enum.Material.Cobblestone, true, skip)
	ring(model, "Remate", center, FIGHT_RADIUS - 0.3, WALL_THICKNESS + 0.6, ground + WALL_HEIGHT, 0.6, c.DarkStone, Enum.Material.Slate, false, skip)
	ring(model, "Zocalo", center, FIGHT_RADIUS - 0.4, 0.4, ground, 0.8, c.DarkStone, Enum.Material.Slate, false, skip)

	-- Barrera invisible encima del muro (hasta BARRIER_HEIGHT) para no salir saltando.
	for _, part in ring(model, "Barrera", center, FIGHT_RADIUS + 0.5, 1, ground + WALL_HEIGHT, BARRIER_HEIGHT - WALL_HEIGHT, c.Stone, Enum.Material.SmoothPlastic, true) do
		part.Transparency = 1
		part.CastShadow = false
	end

	-- Estandartes rojos y azules entre las puertas y antorchas en el medio.
	for k = 0, 7 do
		local theta = math.rad(22.5 + k * 45)
		local color = if math.cos(theta) < 0 then RED else BLUE -- del lado de cada puerta
		Kit.banner(model, facingCenter(center, theta, FIGHT_RADIUS - 0.15, ground + WALL_HEIGHT - 1), 4, 9, color)
	end
	for k = 0, 7 do
		if k == 0 or k == 4 then
			continue -- puertas
		end
		for _, y in { 3.6, 10 } do -- dos filas de antorchas
			Kit.torch(model, facingCenter(center, math.rad(k * 45), FIGHT_RADIUS, ground + y))
		end
	end

	-- Luz de luna sobre la arena (de noche las antorchas solas no llegan al centro).
	local moon = Kit.part(model, "LuzLuna", CFrame.new(center + Vector3.new(0, ground + 28, 0)), Vector3.one, c.Stone, Enum.Material.SmoothPlastic, false)
	moon.Transparency = 1
	moon.CastShadow = false
	local moonLight = Instance.new("PointLight")
	moonLight.Color = Color3.fromRGB(170, 185, 255)
	moonLight.Range = 60
	moonLight.Brightness = 1.2
	moonLight.Shadows = false
	moonLight.Parent = moon
end

-- Gradas escalonadas con público mirando al centro.
local function buildStands(model: Model, center: Vector3, ground: number, random: Random)
	local first = FIGHT_RADIUS + WALL_THICKNESS
	local crowd = Instance.new("Folder")
	crowd.Name = "Publico"
	crowd.Parent = model

	for tier = 0, TIERS - 1 do
		local inner = first + tier * TIER_DEPTH
		local top = WALL_HEIGHT + 1.5 + tier * TIER_RISE
		local color = if tier % 2 == 0 then c.Stone else c.DarkStone
		ring(model, `Grada{tier + 1}`, center, inner, TIER_DEPTH, ground, top, color, Enum.Material.Concrete, false)
		ring(model, `Borde{tier + 1}`, center, inner - 0.1, 0.5, ground + top, 0.25, c.Ivory, Enum.Material.Marble, false)

		for _ = 1, CROWD_PER_TIER do
			local theta = random:NextNumber() * TAU
			-- Que nadie tape las puertas ni el palco.
			local fromBlue = math.abs(math.atan2(math.sin(theta), math.cos(theta)))
			local fromEast = math.abs(math.atan2(math.sin(theta - math.pi / 2), math.cos(theta - math.pi / 2)))
			if (tier < 2 and (fromBlue < 0.25 or fromBlue > math.pi - 0.25)) or fromEast < 0.3 then
				continue
			end
			local radius = inner + TIER_DEPTH * (0.35 + random:NextNumber() * 0.3)
			local foot = facingCenter(center, theta, radius, ground + top)
			local scale = 0.9 + random:NextNumber() * 0.25
			Kit.part(crowd, "Cuerpo", foot * CFrame.new(0, 0.9 * scale, 0), Vector3.new(1.4, 1.8, 0.9) * scale,
				SHIRTS[random:NextInteger(1, #SHIRTS)], Enum.Material.Fabric, false)
			local head = Kit.part(crowd, "Cabeza", foot * CFrame.new(0, 2.35 * scale, 0), Vector3.one * 1.1 * scale,
				SKINS[random:NextInteger(1, #SKINS)], Enum.Material.SmoothPlastic, false)
			head.Shape = Enum.PartType.Ball
			if random:NextNumber() < 0.3 then -- algunos con el brazo en alto
				Kit.part(crowd, "Brazo", foot * CFrame.new(0.85 * scale, 2.3 * scale, 0) * CFrame.Angles(0, 0, math.rad(-15)),
					Vector3.new(0.4, 1.5, 0.4) * scale, head.Color, Enum.Material.SmoothPlastic, false)
			end
		end
	end

	-- Muro exterior que cierra las gradas, con braseros arriba.
	local outer = first + TIERS * TIER_DEPTH
	local outerTop = WALL_HEIGHT + 1.5 + TIERS * TIER_RISE + 4
	ring(model, "MuroExterior", center, outer, OUTER_WALL_THICKNESS, ground, outerTop, c.DarkStone, Enum.Material.Cobblestone, false)
	ring(model, "Almenas", center, outer, OUTER_WALL_THICKNESS, ground + outerTop, 1, c.Stone, Enum.Material.Cobblestone, false)
	for k = 0, 7 do
		local theta = math.rad(22.5 + k * 45)
		Kit.brazier(model, (onRing(center, theta, outer - 1.2, ground + WALL_HEIGHT + 1.5 + (TIERS - 1) * TIER_RISE)).Position, 1.2)
	end
end

-- Palco de honor en el lado este (+X): toldo carmesí, columnas de mármol y estandarte.
local function buildBox(model: Model, center: Vector3, ground: number)
	local theta = math.pi / 2
	local first = FIGHT_RADIUS + WALL_THICKNESS
	-- Ocupa las gradas 2 a 4: el piso queda a la altura de la 4 y abajo va un bloque macizo.
	local floorY = ground + WALL_HEIGHT + 1.5 + 3 * TIER_RISE
	local depth = TIER_DEPTH * 3
	local radius = first + TIER_DEPTH + depth / 2
	local base = onRing(center, theta, radius, floorY)
	local width = 12

	Kit.part(model, "PalcoBase", onRing(center, theta, radius, (ground + floorY) / 2), Vector3.new(width, floorY - ground, depth), c.DarkStone, Enum.Material.Cobblestone, false)
	Kit.part(model, "PalcoPiso", base * CFrame.new(0, 0.2, 0), Vector3.new(width, 0.4, depth), c.Crimson, Enum.Material.Fabric, false)
	Kit.part(model, "PalcoBaranda", base * CFrame.new(0, 1.2, -depth / 2 + 0.3), Vector3.new(width, 0.4, 0.4), c.Gold, Enum.Material.Metal, false)
	for _, x in { -width / 2 + 0.5, width / 2 - 0.5 } do
		for _, z in { -depth / 2 + 0.5, depth / 2 - 0.5 } do
			Kit.part(model, "PalcoColumna", base * CFrame.new(x, 4, z), Vector3.new(0.8, 8, 0.8), c.Ivory, Enum.Material.Marble, false)
		end
	end
	Kit.part(model, "Toldo", base * CFrame.new(0, 8.3, 0) * CFrame.Angles(math.rad(-8), 0, 0), Vector3.new(width + 1.5, 0.4, depth + 1), c.Crimson, Enum.Material.Fabric, false)
	Kit.part(model, "ToldoBorde", base * CFrame.new(0, 7.75, -depth / 2 - 0.4), Vector3.new(width + 1.5, 0.5, 0.2), c.Gold, Enum.Material.Fabric, false)
	Kit.part(model, "Trono", base * CFrame.new(0, 1.6, depth / 2 - 1.5), Vector3.new(2.4, 3, 1.6), c.Gold, Enum.Material.Metal, false)
	Kit.banner(model, facingCenter(center, theta, first + TIER_DEPTH - 0.1, floorY - 0.2), 4, 4.5, c.Crimson)
end

-- ── API ──

--[[
	Arma la arena con el centro del piso en `origin` (la superficie queda en origin.Y + 0.5).
	Devuelve el Model (ya en workspace) y los dos spawns: [1] = puerta roja (−Z), [2] = puerta azul (+Z),
	ambos mirando al centro.
]]
function ArenaBuilder.Build(origin: Vector3, name: string): (Model, { CFrame })
	local model = Instance.new("Model")
	model.Name = name
	local center = Vector3.new(origin.X, 0, origin.Z)
	local ground = origin.Y + 0.5
	local random = Random.new()

	buildFloor(model, center, ground)
	buildWall(model, center, ground)
	buildGate(model, center, ground, GATE_INDEX.Red, RED, "ROJO")
	buildGate(model, center, ground, GATE_INDEX.Blue, BLUE, "AZUL")
	buildStands(model, center, ground, random)
	buildBox(model, center, ground)
	model.Parent = workspace

	local middle = Vector3.new(origin.X, ground + 2.5, origin.Z)
	local spawnRed = middle + Vector3.new(0, 0, -SPAWN_DISTANCE)
	local spawnBlue = middle + Vector3.new(0, 0, SPAWN_DISTANCE)
	return model, { CFrame.lookAt(spawnRed, middle), CFrame.lookAt(spawnBlue, middle) }
end

ArenaBuilder.FightRadius = FIGHT_RADIUS

return ArenaBuilder
