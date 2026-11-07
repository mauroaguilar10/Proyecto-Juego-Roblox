--!strict
--[[
	Kit — Piezas reutilizables para armar el lobby por código (Dev B).
	Todas las partes son ancladas. Las decorativas tienen CanQuery = false para que
	los golpes (CombatService) no pierdan tiempo revisándolas.
]]
local Sounds = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Sounds"))
local Kit = {}

Kit.Colors = {
	Stone = Color3.fromRGB(118, 110, 100),
	DarkStone = Color3.fromRGB(78, 73, 68),
	Wood = Color3.fromRGB(110, 76, 48),
	DarkWood = Color3.fromRGB(70, 48, 32),
	Iron = Color3.fromRGB(62, 62, 66),
	Gold = Color3.fromRGB(237, 197, 118),
	Crimson = Color3.fromRGB(132, 26, 30),
	Ivory = Color3.fromRGB(240, 228, 205),
	Fire = Color3.fromRGB(255, 150, 60),
}

-- Parte anclada y lisa. `solid = false` la deja sin colisión (decoración que se atraviesa).
function Kit.part(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CFrame = cf
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanQuery = false
	p.CanTouch = false
	p.CanCollide = solid ~= false
	p.Parent = parent
	return p
end

-- Cilindro con el eje vertical (Roblox los acuesta en X: se gira 90°).
function Kit.cylinder(parent: Instance, name: string, at: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material, solid: boolean?): Part
	local p = Kit.part(parent, name, CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(height, diameter, diameter), color, material, solid)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Kit.wedge(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CFrame = cf
	w.Size = size
	w.Color = color
	w.Material = material
	w.CanQuery = false
	w.CanTouch = false
	w.Parent = parent
	return w
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = color, range, brightness
	l.Shadows = false
	l.Parent = parent
end

local function fire(parent: Instance, size: number)
	local f = Instance.new("Fire")
	f.Size, f.Heat = size, size * 2
	f.Color, f.SecondaryColor = Color3.fromRGB(255, 140, 50), Color3.fromRGB(255, 220, 120)
	f.Parent = parent
end

-- Chispas que suben desde un fuego.
function Kit.embers(parent: BasePart, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Brasas"
	e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 30))
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.Lifetime = NumberRange.new(1.2, 2.4)
	e.Rate = rate
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Parent = parent
end

-- Antorcha de pared: `cf` en el punto de la pared, mirando hacia afuera de ella.
function Kit.torch(parent: Instance, cf: CFrame)
	local c = Kit.Colors
	Kit.part(parent, "Soporte", cf * CFrame.new(0, 0, -0.3), Vector3.new(0.4, 0.4, 0.6), c.Iron, Enum.Material.Metal, false)
	Kit.part(parent, "Antorcha", cf * CFrame.new(0, 0.5, -0.6) * CFrame.Angles(math.rad(-15), 0, 0), Vector3.new(0.4, 1.6, 0.4), c.DarkWood, Enum.Material.Wood, false)
	local flame = Kit.part(parent, "Llama", cf * CFrame.new(0, 1.5, -0.85), Vector3.new(0.5, 0.5, 0.5), c.Fire, Enum.Material.Neon, false)
	flame.Transparency = 0.25
	fire(flame, 2.5)
	light(flame, Color3.fromRGB(255, 160, 80), 18, 1.8)
	Sounds.Torch(flame)
end

-- Brasero de pie con fuego, luz y chispas. `scale` agranda todo.
function Kit.brazier(parent: Instance, base: Vector3, scale: number?)
	local s = scale or 1
	local c = Kit.Colors
	Kit.cylinder(parent, "Pie", base + Vector3.new(0, 0.3 * s, 0), 0.6 * s, 2.2 * s, c.Iron, Enum.Material.Metal)
	Kit.cylinder(parent, "Columna", base + Vector3.new(0, 2 * s, 0), 3 * s, 0.7 * s, c.Iron, Enum.Material.Metal)
	Kit.cylinder(parent, "Cuenco", base + Vector3.new(0, 3.6 * s, 0), 0.8 * s, 2.6 * s, c.Iron, Enum.Material.Metal)
	local coals = Kit.cylinder(parent, "Brasas", base + Vector3.new(0, 4 * s, 0), 0.2, 2.1 * s, Color3.fromRGB(255, 110, 40), Enum.Material.Neon, false)
	fire(coals, 4 * s)
	light(coals, Color3.fromRGB(255, 150, 70), 22 * s, 2.2)
	Kit.embers(coals, 6 * s)
	Sounds.Torch(coals)
end

-- Emblema de espadas cruzadas sobre un escudo, dibujado en una SurfaceGui.
local function emblem(gui: SurfaceGui, color: Color3)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.42)
	holder.Size = UDim2.fromScale(0.75, 0.4)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = holder
	local shield = Instance.new("Frame")
	shield.AnchorPoint = Vector2.new(0.5, 0.5)
	shield.Position = UDim2.fromScale(0.5, 0.5)
	shield.Size = UDim2.fromScale(0.62, 0.62)
	shield.BackgroundColor3 = Color3.fromRGB(30, 20, 18)
	shield.Parent = holder
	Instance.new("UICorner", shield).CornerRadius = UDim.new(0.5, 0)
	local ring = Instance.new("UIStroke")
	ring.Color, ring.Thickness = color, 6
	ring.Parent = shield
	for _, angle in { 45, -45 } do
		local blade = Instance.new("Frame")
		blade.AnchorPoint = Vector2.new(0.5, 0.5)
		blade.Position = UDim2.fromScale(0.5, 0.5)
		blade.Size = UDim2.fromScale(0.09, 1)
		blade.Rotation = angle
		blade.BackgroundColor3 = color
		blade.BorderSizePixel = 0
		blade.Parent = holder
		local guard = Instance.new("Frame")
		guard.AnchorPoint = Vector2.new(0.5, 0.5)
		guard.Position = UDim2.fromScale(0.5, 0.78)
		guard.Size = UDim2.fromScale(3.4, 0.05)
		guard.BackgroundColor3 = color
		guard.BorderSizePixel = 0
		guard.Parent = blade
	end
end

-- Estandarte colgante: tela con borde dorado y emblema en las dos caras. `cf` = arriba al centro.
function Kit.banner(parent: Instance, cf: CFrame, width: number, height: number, color: Color3)
	local c = Kit.Colors
	Kit.part(parent, "Barra", cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.3, width + 1.2, 0.3), c.DarkWood, Enum.Material.Wood, false)
	local cloth = Kit.part(parent, "Estandarte", cf * CFrame.new(0, -height / 2, 0), Vector3.new(width, height, 0.15), color, Enum.Material.Fabric, false)
	Kit.part(parent, "Borde", cf * CFrame.new(0, -height + 0.15, 0), Vector3.new(width, 0.3, 0.18), c.Gold, Enum.Material.Fabric, false)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 1
		gui.Parent = cloth
		emblem(gui, c.Gold)
	end
end

-- Cartel de madera con texto en la cara frontal (-Z local) y, si `both`, también atrás.
function Kit.sign(parent: Instance, cf: CFrame, size: Vector3, text: string, both: boolean?): Part
	local c = Kit.Colors
	local board = Kit.part(parent, "Cartel", cf, size, c.DarkWood, Enum.Material.Wood)
	local faces = if both then { Enum.NormalId.Front, Enum.NormalId.Back } else { Enum.NormalId.Front }
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.3
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.92, 0.8)
		label.Position = UDim2.fromScale(0.04, 0.1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Antique
		label.TextScaled = true
		label.TextColor3 = c.Gold
		label.TextStrokeColor3, label.TextStrokeTransparency = Color3.fromRGB(30, 18, 8), 0.4
		label.Text = text
		label.Parent = gui
	end
	return board
end

-- Barril de madera con zunchos de hierro.
function Kit.barrel(parent: Instance, base: Vector3)
	local c = Kit.Colors
	Kit.cylinder(parent, "Barril", base + Vector3.new(0, 1.5, 0), 3, 2.2, c.Wood, Enum.Material.WoodPlanks)
	for _, y in { 0.5, 2.5 } do
		Kit.cylinder(parent, "Zuncho", base + Vector3.new(0, y, 0), 0.2, 2.3, c.Iron, Enum.Material.Metal, false)
	end
end

function Kit.crate(parent: Instance, cf: CFrame, size: number)
	local c = Kit.Colors
	Kit.part(parent, "Cajon", cf * CFrame.new(0, size / 2, 0), Vector3.new(size, size, size), c.Wood, Enum.Material.WoodPlanks)
	for _, angle in { 45, -45 } do
		Kit.part(parent, "Refuerzo", cf * CFrame.new(0, size / 2, -size / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(angle)),
			Vector3.new(0.3, size * 1.3, 0.1), c.DarkWood, Enum.Material.Wood, false)
	end
end

-- Espada decorativa (punta hacia arriba). `cf` = base de la empuñadura.
function Kit.sword(parent: Instance, cf: CFrame, length: number, blade: Color3)
	local c = Kit.Colors
	Kit.part(parent, "Mango", cf * CFrame.new(0, length * 0.08, 0), Vector3.new(0.2, length * 0.16, 0.2), c.DarkWood, Enum.Material.Wood, false)
	Kit.part(parent, "Guarda", cf * CFrame.new(0, length * 0.17, 0), Vector3.new(length * 0.28, 0.18, 0.22), c.Gold, Enum.Material.Metal, false)
	Kit.part(parent, "Hoja", cf * CFrame.new(0, length * 0.58, 0), Vector3.new(length * 0.09, length * 0.8, 0.08), blade, Enum.Material.Metal, false)
end

return Kit
