--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponData = require(ReplicatedStorage.Shared.WeaponData)
local EquipmentService = {}

local function woodenSword(): Tool
	local tool = Instance.new("Tool")
	tool.Name = WeaponData.DEFAULT_WEAPON
	tool.ToolTip = WeaponData.Weapons[WeaponData.DEFAULT_WEAPON].DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("EconomyWeapon", true)

	local function part(name: string, size: Vector3, y: number, color: Color3): Part
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size
		piece.CFrame = CFrame.new(0, y, 0)
		piece.Color = color
		piece.Material = Enum.Material.Wood
		piece.Massless = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.Parent = tool
		return piece
	end

	local handle = part("Handle", Vector3.new(0.26, 1, 0.26), 0, Color3.fromRGB(88, 52, 32))
	local guard = part("Guard", Vector3.new(1.15, 0.22, 0.31), 0.55, Color3.fromRGB(131, 78, 39))
	local blade = part("Blade", Vector3.new(0.42, 2.7, 0.18), 1.99, Color3.fromRGB(194, 141, 81))
	for _, piece in {guard, blade} do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.Parent = piece
	end
	return tool
end

local function watchPlayer(player: Player)
	local function equip(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		local backpack = player:WaitForChild("Backpack", 10)
		if not humanoid or not humanoid:IsA("Humanoid") or not backpack or player.Character ~= character or humanoid.Health <= 0 then
			return
		end
		local existing = character:FindFirstChild(WeaponData.DEFAULT_WEAPON) or backpack:FindFirstChild(WeaponData.DEFAULT_WEAPON)
		if player:GetAttribute("EquippedWeapon") ~= WeaponData.DEFAULT_WEAPON then
			if existing and existing:GetAttribute("EconomyWeapon") then
				existing:Destroy()
			end
			return
		end
		if existing then
			return
		end
		local sword = woodenSword()
		sword.Parent = backpack
		humanoid:EquipTool(sword)
	end

	player.CharacterAdded:Connect(equip)
	player:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
		if player.Character then
			equip(player.Character)
		end
	end)
	if player.Character then
		task.spawn(equip, player.Character)
	end
end

function EquipmentService:Init()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return EquipmentService
