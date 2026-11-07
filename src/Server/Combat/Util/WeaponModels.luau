--!strict
--[[
	WeaponModels — Modelos placeholder construidos con Parts, uno por WeaponId.
	Owner: Dev A (Combat). Vive en Util/ para que el cargador no lo trate como servicio.

	Sistema de coordenadas: el origen es el punto de agarre (la mano) y el arma se
	extiende hacia +Y. Con RightGripAttachment, +Y apunta hacia adelante con el brazo abajo.

	Cuando haya modelos reales (.rbxm), reemplazar Build() por un Clone() del asset.
]]

local WeaponArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("WeaponArt"))

type PartSpec = {
	Name: string,
	Size: Vector3,
	Offset: CFrame,
	Color: Color3,
	Material: Enum.Material,
}

local WOOD = Color3.fromRGB(150, 105, 60)
local DARK_WOOD = Color3.fromRGB(90, 60, 35)
local IRON = Color3.fromRGB(190, 195, 205)
local DARK_METAL = Color3.fromRGB(60, 60, 70)
local VOID = Color3.fromRGB(140, 60, 255)
local VOID_DARK = Color3.fromRGB(35, 20, 50)

local SPECS: { [string]: { PartSpec } } = {
	WoodenSword = {
		{ Name = "Handle", Size = Vector3.new(0.25, 1, 0.25), Offset = CFrame.new(0, 0, 0), Color = DARK_WOOD, Material = Enum.Material.Wood },
		{ Name = "Guard", Size = Vector3.new(0.9, 0.2, 0.3), Offset = CFrame.new(0, 0.6, 0), Color = DARK_WOOD, Material = Enum.Material.Wood },
		{ Name = "Blade", Size = Vector3.new(0.15, 3, 0.4), Offset = CFrame.new(0, 2.2, 0), Color = WOOD, Material = Enum.Material.Wood },
	},
	IronBlade = {
		{ Name = "Handle", Size = Vector3.new(0.25, 1.1, 0.25), Offset = CFrame.new(0, 0, 0), Color = DARK_METAL, Material = Enum.Material.Metal },
		{ Name = "Guard", Size = Vector3.new(1.2, 0.2, 0.35), Offset = CFrame.new(0, 0.65, 0), Color = DARK_METAL, Material = Enum.Material.Metal },
		{ Name = "Blade", Size = Vector3.new(0.12, 3.6, 0.5), Offset = CFrame.new(0, 2.55, 0), Color = IRON, Material = Enum.Material.Metal },
	},
	VoidScythe = {
		{ Name = "Handle", Size = Vector3.new(0.2, 5, 0.2), Offset = CFrame.new(0, 1.5, 0), Color = VOID_DARK, Material = Enum.Material.Metal },
		{ Name = "Blade", Size = Vector3.new(0.1, 0.45, 2.6), Offset = CFrame.new(0, 3.85, 1.1), Color = VOID, Material = Enum.Material.Neon },
		{ Name = "Tip", Size = Vector3.new(0.1, 0.8, 0.3), Offset = CFrame.new(0, 3.55, 2.3), Color = VOID, Material = Enum.Material.Neon },
	},
}

local DEFAULT_SPEC = SPECS.WoodenSword

local WeaponModels = {}

-- Devuelve un Model cuyo PrimaryPart ("Grip", invisible) está en el origen del agarre.
function WeaponModels.Build(weaponId: string): Model
	-- Armas con modelo detallado compartido con la tienda (mismo contrato: Model "Weapon" + Grip).
	if WeaponArt.Has(weaponId) then
		return WeaponArt.Build(weaponId)
	end

	local model = Instance.new("Model")
	model.Name = "Weapon"
	model:SetAttribute("WeaponId", weaponId)

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.2, 0.2, 0.2)
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.Parent = model
	model.PrimaryPart = grip

	for _, spec in SPECS[weaponId] or DEFAULT_SPEC do
		local part = Instance.new("Part")
		part.Name = spec.Name
		part.Size = spec.Size
		part.Color = spec.Color
		part.Material = spec.Material
		part.CanCollide = false
		part.CanQuery = false -- invisible para el hit detection de CombatService
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false

		local weld = Instance.new("Weld")
		weld.Part0 = grip
		weld.Part1 = part
		weld.C0 = spec.Offset
		weld.Parent = part

		part.Parent = model
	end

	return model
end

return WeaponModels
