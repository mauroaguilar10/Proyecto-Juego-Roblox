--!strict
--[[
	Layout — Dónde va cada zona del lobby (Dev B). Lo usan LobbyService, DungeonService y
	RecordsService para que todo quede alineado con los caminos.

	Las coordenadas son (x, z) relativas al CENTRO del lobby (-Z = norte, +X = este). El centro
	se calcula desde el SpawnLocation: el spawn queda al sur (SPAWN), cerca del portón.

	        RÉCORDS (NO)      ARENA DE DUELOS (N)      MAZMORRAS (NE)
	              \________________|_________________/      ← camino de arriba
	                               |
	        TIENDAS (O) ______ SPAWN (S) ______ ZONA DE PRÁCTICA (E)
	                               |
	                         portón (sur)
]]
local Layout = {}

export type Spot = { x: number, z: number, lookX: number, lookZ: number }

Layout.SPAWN = Vector2.new(0, 44) -- el SpawnLocation, relativo al centro
Layout.UPPER_ROAD_Z = 4 -- camino este-oeste de arriba (récords / mazmorras)
Layout.LOWER_ROAD_Z = 44 -- camino este-oeste de abajo (tiendas / práctica), pasa por el spawn
Layout.SIDE_ROAD_X = 42 -- tramos que suben hacia récords y mazmorras

Layout.ARENA = Vector2.new(0, -38) -- centro de la arena de duelos (se abre hacia el sur)
Layout.RECORDS = { x = -42, z = -34, lookX = -42, lookZ = 0 } :: Spot -- tablero + pórtico, mirando al sur
Layout.DUNGEON = { x = 42, z = -34, lookX = 42, lookZ = 0 } :: Spot -- arco del portal, mirando al sur
Layout.TRAINING = Vector2.new(44, 44) -- zona de práctica (entrada al oeste)
Layout.WEAPON_SHOP = { x = -48, z = 31, lookX = 0, lookZ = 31 } :: Spot -- puestos mirando al este
Layout.ARMOR_SHOP = { x = -48, z = 56, lookX = 0, lookZ = 56 } :: Spot

local cachedCenter: Vector3? = nil
local cachedGround = 0

-- Centro del lobby a ras del piso y altura del piso. Se calcula una vez desde el SpawnLocation.
function Layout.Base(): (Vector3, number)
	if cachedCenter then
		return cachedCenter, cachedGround
	end
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local spawnPos = if spawn and spawn:IsA("BasePart") then spawn.Position else Vector3.zero
	local ground = if spawn and spawn:IsA("BasePart") then spawnPos.Y - spawn.Size.Y / 2 else 0
	local center = Vector3.new(spawnPos.X - Layout.SPAWN.X, ground, spawnPos.Z - Layout.SPAWN.Y)
	cachedCenter, cachedGround = center, ground
	return center, ground
end

-- Punto del lobby a ras del piso (+ y).
function Layout.At(x: number, z: number, y: number?): Vector3
	local center = Layout.Base()
	return Vector3.new(center.X + x, center.Y + (y or 0), center.Z + z)
end

-- CFrame a ras del piso en un Spot, mirando hacia su punto `look`.
function Layout.Facing(spot: Spot, y: number?): CFrame
	local from = Layout.At(spot.x, spot.z, y)
	local to = Layout.At(spot.lookX, spot.lookZ, y)
	return CFrame.lookAt(from, to)
end

return Layout
