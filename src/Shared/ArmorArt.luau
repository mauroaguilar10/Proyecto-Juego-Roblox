--!strict
--[[
	ArmorArt — Aspecto de cada pieza de armadura, armado con Parts sobre el cuerpo.
	Owner: Dev B (Economía). Lo usan ArmorService (en el personaje) y ArmorController
	(maniquí de la ficha de la armería).

	Build(pieceId, body) devuelve un Model "Armadura_<Slot>" con placas soldadas a las partes del
	cuerpo (`body` es el personaje o un maniquí con las mismas partes). Las medidas son relativas al
	tamaño de cada parte, así la armadura se ajusta a avatares de distinto tamaño.
	Pensado para R15; en R6 usa las partes equivalentes (queda aproximado).
	Convención de Roblox: el frente del cuerpo es -Z.
]]
local ArmorArt = {}

-- Equivalencias R6 de las partes R15.
local R6: { [string]: string } = {
	UpperTorso = "Torso", LowerTorso = "Torso",
	LeftUpperArm = "Left Arm", RightUpperArm = "Right Arm",
	LeftUpperLeg = "Left Leg", LeftLowerLeg = "Left Leg", LeftFoot = "Left Leg",
	RightUpperLeg = "Right Leg", RightLowerLeg = "Right Leg", RightFoot = "Right Leg",
}

type Plate = (bodyName: string, name: string, scale: Vector3, offset: Vector3, color: Color3, material: Enum.Material, rotation: CFrame?, pad: Vector3?) -> BasePart?

local function newPlate(model: Model, body: Instance): Plate
	return function(bodyName, name, scale, offset, color, material, rotation, pad)
		local part = body:FindFirstChild(bodyName) or body:FindFirstChild(R6[bodyName] or "")
		if not part or not part:IsA("BasePart") then return nil end
		local s = part.Size
		local p = Instance.new("Part")
		p.Name = name
		p.Size = s * scale + (pad or Vector3.zero)
		p.Color, p.Material = color, material
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		local c0 = CFrame.new(s * offset) * (rotation or CFrame.identity)
		p.CFrame = part.CFrame * c0
		local weld = Instance.new("Weld")
		weld.Part0, weld.Part1, weld.C0 = part, p, c0
		weld.Parent = p
		p.Parent = model
		return p
	end
end

local function light(part: BasePart?, color: Color3, range: number)
	if not part then return end
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, 1.2, false
	l.Parent = part
end

local LEATHER = Color3.fromRGB(116, 78, 48)
local DARK_LEATHER = Color3.fromRGB(78, 50, 32)
local STRAP = Color3.fromRGB(60, 40, 26)
local BRASS = Color3.fromRGB(196, 156, 82)
local STEEL = Color3.fromRGB(176, 182, 192)
local DARK_STEEL = Color3.fromRGB(104, 108, 118)
local OBSIDIAN = Color3.fromRGB(34, 28, 34)
local EMBER = Color3.fromRGB(255, 110, 30)
local V = Vector3.new
local LEGS = { "Left", "Right" }

local BUILDERS: { [string]: (Plate) -> () } = {
	-- ── Cuero curtido ──
	LeatherHelm = function(plate)
		plate("Head", "Capucha", V(1.12, 0.62, 1.14), V(0, 0.22, 0.02), LEATHER, Enum.Material.Fabric)
		plate("Head", "Borde", V(1.16, 0.12, 1.18), V(0, -0.06, 0.02), DARK_LEATHER, Enum.Material.Fabric)
		for _, side in { -1, 1 } do
			plate("Head", "Orejera", V(0.12, 0.5, 0.55), V(side * 0.56, -0.2, 0.05), LEATHER, Enum.Material.Fabric)
		end
		plate("Head", "Costura", V(0.06, 0.08, 1.16), V(0, 0.53, 0.02), STRAP, Enum.Material.Fabric)
	end,
	LeatherChest = function(plate)
		plate("UpperTorso", "Jubon", V(1.1, 1.03, 1.22), V(0, 0, 0), LEATHER, Enum.Material.Fabric)
		plate("UpperTorso", "Cordones", V(0.12, 0.8, 0.04), V(0, 0, -0.62), STRAP, Enum.Material.Fabric)
		plate("UpperTorso", "Tahali", V(0.18, 1.25, 1.24), V(0, 0, 0), STRAP, Enum.Material.Fabric, CFrame.Angles(0, 0, math.rad(35)))
		plate("LowerTorso", "Cinturon", V(1.12, 0.55, 1.26), V(0, 0, 0), DARK_LEATHER, Enum.Material.Fabric)
		plate("LowerTorso", "Hebilla", V(0.22, 0.4, 0.04), V(0, 0, -0.64), BRASS, Enum.Material.Metal)
		for _, side in LEGS do
			plate(side .. "UpperArm", "Hombrera", V(1.18, 0.32, 1.2), V(0, 0.36, 0), DARK_LEATHER, Enum.Material.Fabric)
		end
	end,
	LeatherLegs = function(plate)
		for _, side in LEGS do
			plate(side .. "UpperLeg", "Pernera", V(1.12, 1.0, 1.14), V(0, 0, 0), LEATHER, Enum.Material.Fabric)
			plate(side .. "UpperLeg", "Correa", V(1.15, 0.12, 1.17), V(0, -0.15, 0), STRAP, Enum.Material.Fabric)
			plate(side .. "LowerLeg", "Bota", V(1.14, 0.95, 1.16), V(0, -0.02, 0), DARK_LEATHER, Enum.Material.Fabric)
			plate(side .. "Foot", "Pie", V(1.15, 1.12, 1.1), V(0, 0.02, 0), DARK_LEATHER, Enum.Material.Fabric)
		end
	end,

	-- ── Acero del Guardián ──
	SteelHelm = function(plate)
		plate("Head", "Yelmo", V(1.16, 1.12, 1.16), V(0, 0.04, 0), STEEL, Enum.Material.Metal)
		plate("Head", "Visera", V(0.86, 0.07, 0.04), V(0, 0.08, -0.59), Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic)
		for i = 0, 3 do
			plate("Head", "Respiradero", V(0.06, 0.06, 0.04), V(-0.18 + i * 0.12, -0.22, -0.59), Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic)
		end
		plate("Head", "Cresta", V(0.12, 0.16, 1.18), V(0, 0.62, 0), DARK_STEEL, Enum.Material.Metal)
		plate("Head", "Gola", V(1.2, 0.14, 1.2), V(0, -0.5, 0), DARK_STEEL, Enum.Material.Metal)
	end,
	SteelChest = function(plate)
		plate("UpperTorso", "Coraza", V(1.13, 1.06, 1.3), V(0, 0, 0), STEEL, Enum.Material.Metal)
		plate("UpperTorso", "Arista", V(0.07, 0.95, 0.05), V(0, 0, -0.66), DARK_STEEL, Enum.Material.Metal)
		plate("UpperTorso", "Gorjal", V(0.7, 0.16, 1.1), V(0, 0.55, 0), DARK_STEEL, Enum.Material.Metal)
		plate("LowerTorso", "Faldar", V(1.16, 0.9, 1.32), V(0, -0.05, 0), DARK_STEEL, Enum.Material.Metal)
		for _, side in LEGS do
			plate(side .. "UpperArm", "Hombrera", V(1.4, 0.45, 1.38), V(0, 0.36, 0), STEEL, Enum.Material.Metal)
			plate(side .. "UpperArm", "Lamina", V(1.32, 0.22, 1.3), V(0, 0.05, 0), DARK_STEEL, Enum.Material.Metal)
		end
	end,
	SteelLegs = function(plate)
		for _, side in LEGS do
			plate(side .. "UpperLeg", "Quijote", V(1.15, 1.02, 1.18), V(0, 0, 0), STEEL, Enum.Material.Metal)
			plate(side .. "LowerLeg", "Rodillera", V(0.75, 0.32, 0.3), V(0, 0.42, -0.55), DARK_STEEL, Enum.Material.Metal)
			plate(side .. "LowerLeg", "Greba", V(1.15, 0.95, 1.2), V(0, -0.02, 0), STEEL, Enum.Material.Metal)
			plate(side .. "Foot", "Escarpe", V(1.2, 1.18, 1.14), V(0, 0.03, 0), DARK_STEEL, Enum.Material.Metal)
		end
	end,

	-- ── Brasa de Obsidiana (con grietas que brillan) ──
	EmberHelm = function(plate)
		plate("Head", "Yelmo", V(1.17, 1.13, 1.17), V(0, 0.04, 0), OBSIDIAN, Enum.Material.Basalt)
		local visor = plate("Head", "Visera", V(0.9, 0.08, 0.04), V(0, 0.08, -0.6), EMBER, Enum.Material.Neon)
		for _, side in { -1, 1 } do
			-- Cuernos curvados hacia arriba.
			plate("Head", "Cuerno", V(0.16, 0.45, 0.16), V(side * 0.6, 0.45, 0.05), OBSIDIAN, Enum.Material.Basalt, CFrame.Angles(0, 0, side * math.rad(-28)))
			plate("Head", "Punta", V(0.1, 0.3, 0.1), V(side * 0.78, 0.82, 0.05), EMBER, Enum.Material.Neon, CFrame.Angles(0, 0, side * math.rad(-12)))
		end
		plate("Head", "Grieta", V(0.04, 0.5, 0.04), V(0.2, 0.35, -0.59), EMBER, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(20)))
		light(visor, EMBER, 6)
	end,
	EmberChest = function(plate)
		plate("UpperTorso", "Coraza", V(1.15, 1.08, 1.32), V(0, 0, 0), OBSIDIAN, Enum.Material.Basalt)
		local core = plate("UpperTorso", "Nucleo", V(0.26, 0.26, 0.05), V(0, 0.12, -0.67), EMBER, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(45)))
		for i, angle in { 30, -40, 15, -20 } do
			local x = if i % 2 == 0 then 0.25 else -0.25
			plate("UpperTorso", "Grieta", V(0.04, 0.35, 0.04), V(x, -0.25 + (i // 3) * 0.3, -0.66), EMBER, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(angle)))
		end
		plate("LowerTorso", "Faldar", V(1.18, 0.92, 1.34), V(0, -0.05, 0), OBSIDIAN, Enum.Material.Basalt)
		plate("LowerTorso", "Franja", V(1.2, 0.08, 1.36), V(0, -0.3, 0), EMBER, Enum.Material.Neon)
		for _, side in LEGS do
			local arm = side .. "UpperArm"
			plate(arm, "Hombrera", V(1.5, 0.5, 1.45), V(0, 0.38, 0), OBSIDIAN, Enum.Material.Basalt)
			local sign = if side == "Left" then -1 else 1
			plate(arm, "Pua", V(0.18, 0.5, 0.18), V(sign * 0.25, 0.75, 0), OBSIDIAN, Enum.Material.Basalt, CFrame.Angles(0, 0, sign * math.rad(-25)))
			plate(arm, "Borde", V(1.52, 0.07, 1.47), V(0, 0.14, 0), EMBER, Enum.Material.Neon)
		end
		light(core, EMBER, 8)
	end,
	EmberLegs = function(plate)
		for _, side in LEGS do
			plate(side .. "UpperLeg", "Quijote", V(1.16, 1.03, 1.2), V(0, 0, 0), OBSIDIAN, Enum.Material.Basalt)
			plate(side .. "UpperLeg", "Grieta", V(0.04, 0.6, 0.04), V(0.15, 0, -0.61), EMBER, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(15)))
			plate(side .. "LowerLeg", "Rodillera", V(0.8, 0.34, 0.32), V(0, 0.42, -0.56), EMBER, Enum.Material.Neon)
			plate(side .. "LowerLeg", "Greba", V(1.16, 0.96, 1.22), V(0, -0.02, 0), OBSIDIAN, Enum.Material.Basalt)
			plate(side .. "Foot", "Escarpe", V(1.22, 1.2, 1.15), V(0, 0.03, 0), OBSIDIAN, Enum.Material.Basalt)
		end
	end,
}

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
