--!strict
-- Modelos de exhibición locales al ViewportFrame de cada ficha.
local Preview = {}

local function segment(view: ViewportFrame, a: Vector3, b: Vector3, width: number, depth: number, color: Color3, material: Enum.Material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.new(width, (b-a).Magnitude, depth)
	local up = (b-a).Unit
	p.CFrame = CFrame.fromMatrix((a+b)/2, Vector3.new(up.Y, -up.X, 0), up)
	p.Color = color
	p.Material = material
	p.Parent = view
end

-- captionHeight: alto del pie de la tarjeta (nombre, estadísticas, acción) que queda debajo del dibujo.
function Preview.draw(parent: Instance, id: string, captionHeight: number)
	local view = Instance.new("ViewportFrame")
	view.Name = "WeaponPreview"
	view.Size = UDim2.new(1, -12, 1, -(captionHeight + 7))
	view.Position = UDim2.fromOffset(6, 5)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(161, 158, 156)
	view.LightColor = Color3.fromRGB(255, 236, 196)
	view.LightDirection = Vector3.new(-0.7, -0.8, -1)
	view.Parent = parent
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.55, 10), Vector3.new(0, 0.55, 0))
	view.CurrentCamera = camera
	camera.Parent = view

	local wood = Color3.fromRGB(193, 135, 73)
	local steel = Color3.fromRGB(182, 199, 211)
	local brass = Color3.fromRGB(217, 168, 89)
	local tilt = CFrame.Angles(0, 0, math.rad(-35))
	local function line(x: number, y: number, xx: number, yy: number, width: number, color: Color3, material: Enum.Material)
		segment(view, tilt * Vector3.new(x, y, 0), tilt * Vector3.new(xx, yy, 0), width, 0.18, color, material)
	end
	if id == "VoidScythe" then
		local violet = Color3.fromRGB(161, 114, 201)
		line(0, -2.2, 0, 2.0, 0.16, Color3.fromRGB(119, 98, 130), Enum.Material.Metal)
		for i = 0, 4 do
			line(0, -1.6+i*0.17, 0, -1.54+i*0.17, 0.22, brass, Enum.Material.Metal)
		end
		line(0, 1.87, -0.7, 2.14, 0.57, violet, Enum.Material.Metal)
		line(-0.7, 2.14, -1.43, 1.99, 0.41, violet, Enum.Material.Metal)
		line(-1.43, 1.99, -2.1, 1.47, 0.21, violet, Enum.Material.Metal)
		line(-2.1, 1.47, -2.39, 1.04, 0.08, violet, Enum.Material.Metal)
	else
		local wooden = id == "WoodenSword"
		local blade = if wooden then wood else steel
		local mat = if wooden then Enum.Material.Wood else Enum.Material.Metal
		line(0,-1.85,0,-0.9,0.25, Color3.fromRGB(115, 76, 51), Enum.Material.Wood)
		for i = 0, 3 do
			line(0,-1.75+i*0.21,0,-1.69+i*0.21,0.29,brass,Enum.Material.Metal)
		end
		line(-0.59,-0.84,0.59,-0.84,0.19,brass,Enum.Material.Metal)
		line(0,-0.78,0,1.9,if wooden then 0.35 else 0.52,blade,mat)
		line(0,1.9,0,2.16,0.26,blade,mat)
		line(0,2.16,0,2.34,0.12,blade,mat)
	end
end

function Preview:Init() end
return Preview
