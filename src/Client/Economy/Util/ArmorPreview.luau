--!strict
-- Maniquí con armadura dentro de un ViewportFrame (fichas de la armería y de la tienda de Robux).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmorArt = require(Shared:WaitForChild("ArmorArt"))
local ArmorData = require(Shared:WaitForChild("ArmorData"))
local ArmorPreview = {}

-- Partes R15 con los mismos nombres que usa ArmorArt.
local MANNEQUIN: { [string]: { Vector3 } } = {
	Head = { Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0) },
	UpperTorso = { Vector3.new(2, 1.6, 1), Vector3.new(0, 3.2, 0) },
	LowerTorso = { Vector3.new(2, 0.4, 1), Vector3.new(0, 2.2, 0) },
	LeftUpperArm = { Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 3.4, 0) },
	RightUpperArm = { Vector3.new(1, 1.2, 1), Vector3.new(1.5, 3.4, 0) },
	LeftLowerArm = { Vector3.new(1, 1.1, 1), Vector3.new(-1.5, 2.25, 0) },
	RightLowerArm = { Vector3.new(1, 1.1, 1), Vector3.new(1.5, 2.25, 0) },
	LeftUpperLeg = { Vector3.new(1, 1.2, 1), Vector3.new(-0.5, 1.4, 0) },
	RightUpperLeg = { Vector3.new(1, 1.2, 1), Vector3.new(0.5, 1.4, 0) },
	LeftLowerLeg = { Vector3.new(1, 1.1, 1), Vector3.new(-0.5, 0.25, 0) },
	RightLowerLeg = { Vector3.new(1, 1.1, 1), Vector3.new(0.5, 0.25, 0) },
	LeftFoot = { Vector3.new(1, 0.3, 1), Vector3.new(-0.5, -0.45, 0) },
	RightFoot = { Vector3.new(1, 0.3, 1), Vector3.new(0.5, -0.45, 0) },
}

-- Dibuja el maniquí con las piezas dadas y encuadra la cámara (3/4) sobre ellas.
-- `bottomInset`: píxeles libres debajo del dibujo (para el texto de la ficha).
function ArmorPreview.draw(parent: GuiObject, pieceIds: { string }, bottomInset: number): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.new(1, -8, 1, -(bottomInset + 4))
	view.Position = UDim2.fromOffset(4, 4)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(150, 150, 160)
	view.LightColor = Color3.fromRGB(255, 240, 220)
	view.LightDirection = Vector3.new(-0.5, -0.8, 0.6)
	view.Parent = parent
	local body = Instance.new("Model")
	for name, spec in MANNEQUIN do
		local p = Instance.new("Part")
		p.Name, p.Size, p.Anchored = name, spec[1], true
		p.CFrame = CFrame.new(spec[2])
		p.Color, p.Material = Color3.fromRGB(96, 100, 108), Enum.Material.SmoothPlastic
		p.Parent = body
	end
	body.Parent = view
	local armor = Instance.new("Model")
	for _, id in pieceIds do
		local piece = ArmorData.Get(id)
		if piece then
			local m = ArmorArt.Build(id, piece.Slot, body)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then d.Anchored = true elseif d:IsA("Weld") or d:IsA("Light") then d:Destroy() end
			end
			m.Parent = armor
		end
	end
	armor.Parent = view
	local box, size = armor:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.62
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = radius / math.tan(math.rad(20)) + 0.5
	local dir = Vector3.new(math.sin(math.rad(-28)), 0.25, -math.cos(math.rad(28))).Unit
	camera.CFrame = CFrame.lookAt(box.Position + dir * distance, box.Position)
	view.CurrentCamera = camera
	camera.Parent = view
	return view
end

return ArmorPreview
