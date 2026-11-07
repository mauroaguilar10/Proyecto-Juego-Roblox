--!strict
--[[
	LobbyService — Decorado del lobby que pertenece a Economía: el puesto de la tienda.
	Owner: Dev B (Economía).

	- Un mostrador con toldo y cartel frente al spawn. Su ProximityPrompt tiene el
	  Attribute OpenShop = true: UIController (cliente) abre la tienda al activarlo.
	  No pasa nada por el servidor: abrir la tienda no cambia datos (comprar sigue siendo PurchaseWeapon).
	- La entrada a la mazmorra la arma DungeonService; el tablero de récords, RecordsService.
]]
local LobbyService = {}

local WOOD = Color3.fromRGB(120, 84, 54)
local DARK_WOOD = Color3.fromRGB(78, 54, 36)
local AWNING = { Color3.fromRGB(176, 52, 48), Color3.fromRGB(236, 222, 196) }
local GOLD = Color3.fromRGB(237, 197, 118)

local function block(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material): Part
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
	p.Parent = parent
	return p
end

-- `cf` está a ras del piso; el frente del puesto (-Z local) mira hacia el spawn.
local function buildStall(parent: Instance, cf: CFrame)
	local counter = block(parent, "Mostrador", cf * CFrame.new(0, 1.5, 0), Vector3.new(9, 3, 2.4), WOOD, Enum.Material.WoodPlanks)
	block(parent, "Tablero", cf * CFrame.new(0, 3.1, 0), Vector3.new(9.4, 0.2, 2.8), DARK_WOOD, Enum.Material.Wood)
	block(parent, "Estante", cf * CFrame.new(0, 3.5, 3.4), Vector3.new(9, 7, 0.6), DARK_WOOD, Enum.Material.WoodPlanks)
	for _, y in { 2.6, 4.6 } do
		block(parent, "Repisa", cf * CFrame.new(0, y, 2.9), Vector3.new(8.6, 0.25, 0.9), WOOD, Enum.Material.Wood)
	end
	for _, x in { -4.6, 4.6 } do
		for _, z in { -1.2, 3.4 } do
			block(parent, "Poste", cf * CFrame.new(x, 4.25, z), Vector3.new(0.5, 8.5, 0.5), DARK_WOOD, Enum.Material.Wood)
		end
	end
	-- Toldo a rayas, un poco inclinado hacia adelante.
	local stripes = 7
	local width = 10.4 / stripes
	for i = 1, stripes do
		local x = -5.2 + width * (i - 0.5)
		block(parent, "Toldo", cf * CFrame.new(x, 8.7, 1.1) * CFrame.Angles(math.rad(-12), 0, 0),
			Vector3.new(width, 0.25, 5.6), AWNING[(i % 2) + 1], Enum.Material.Fabric)
	end
	-- Mercadería: espadas de exhibición en las repisas.
	for i, x in { -3, 0, 3 } do
		local blade = Color3.fromRGB(200, 205, 212):Lerp(GOLD, (i - 1) / 2)
		block(parent, "Hoja", cf * CFrame.new(x, 5.6, 2.9) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(0.25, 1.8, 0.1), blade, Enum.Material.Metal)
		block(parent, "Empuñadura", cf * CFrame.new(x + 0.3, 4.95, 2.9) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(0.7, 0.18, 0.15), DARK_WOOD, Enum.Material.Wood)
	end
	-- Monedas sobre el mostrador.
	for i = 1, 4 do
		local coin = block(parent, "Moneda", cf * CFrame.new(-2.6 + i * 0.35, 3.25 + (i % 2) * 0.1, -0.4) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.1, 0.5, 0.5), GOLD, Enum.Material.Metal)
		coin.Shape = Enum.PartType.Cylinder
	end

	-- Cartel sobre el toldo, con dos soportes.
	local sign = block(parent, "Cartel", cf * CFrame.new(0, 10.1, -1.4), Vector3.new(6, 1.6, 0.25), DARK_WOOD, Enum.Material.Wood)
	for _, x in { -2.4, 2.4 } do
		block(parent, "Soporte", cf * CFrame.new(x, 8.9, -1.4), Vector3.new(0.2, 1.4, 0.2), DARK_WOOD, Enum.Material.Wood)
	end
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Antique
	text.TextScaled = true
	text.TextColor3 = GOLD
	text.Text = "TIENDA"
	text.Parent = surface
	local lamp = Instance.new("PointLight")
	lamp.Color, lamp.Range, lamp.Brightness = Color3.fromRGB(255, 210, 150), 14, 1.2
	lamp.Parent = sign

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AbrirTienda"
	prompt.ObjectText = "Tienda"
	prompt.ActionText = "Abrir tienda"
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenShop", true)
	prompt.Parent = counter
end

function LobbyService:Init()
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local ground = if spawn then origin.Y - spawn.Size.Y / 2 else 0
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	local base = Vector3.new(origin.X, ground, origin.Z - 16)
	buildStall(folder, CFrame.lookAt(base, Vector3.new(origin.X, ground, origin.Z)))
	folder.Parent = workspace
end

return LobbyService
