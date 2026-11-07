--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local WeaponData = require(game:GetService("ReplicatedStorage").Shared.WeaponData)

local StudioSword = {}

local function makeSword(): Tool
	local sword = Instance.new("Tool")
	sword.Name = "Espada de prueba"
	sword.ToolTip = "Acercate y hacé clic mirando a un guardián"
	sword.CanBeDropped = false
	local function piece(name: string, y: number, size: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Position = Vector3.new(0, y, 0)
		part.Color = color
		part.Material = Enum.Material.Wood
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Parent = sword
		return part
	end
	local handle = piece("Handle", 0, Vector3.new(0.25, 0.95, 0.25), Color3.fromRGB(89, 51, 30))
	local guard = piece("Guard", 0.52, Vector3.new(1.1, 0.2, 0.28), Color3.fromRGB(146, 89, 46))
	local blade = piece("Blade", 1.9, Vector3.new(0.38, 2.6, 0.18), Color3.fromRGB(204, 151, 84))
	for _, part in {guard, blade} do
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = handle, part, handle
	end
	return sword
end

local function hitGuardian(player: Player, character: Model, range: number, damage: number)
	local dungeon = workspace:FindFirstChild("Mazmorra")
	local origin = character:FindFirstChild("HumanoidRootPart")
	if not dungeon or not origin or not origin:IsA("BasePart") then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local target: Humanoid? = nil
	local closest = range
	for _, model in dungeon:GetChildren() do
		if not model:IsA("Model") or model.Name ~= "Guardián de piedra" or Players:GetPlayerFromCharacter(model) then continue end
		local enemy = model:FindFirstChildOfClass("Humanoid")
		local root = if enemy then enemy.RootPart else nil
		if not enemy or enemy.Health <= 0 or not root then continue end
		local offset = root.Position - origin.Position
		local distance = offset.Magnitude
		if distance < 0.01 or distance > closest or origin.CFrame.LookVector:Dot(offset.Unit) < 0.35 then continue end
		local obstacle = workspace:Raycast(origin.Position, offset, params)
		if obstacle and not obstacle.Instance:IsDescendantOf(model) then continue end
		target = enemy
		closest = distance
	end
	if target then
		target:SetAttribute("LastAttacker", player.UserId)
		target:TakeDamage(damage)
	end
end

local function give(player: Player, character: Model)
	local backpack = player:WaitForChild("Backpack", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if player.Character ~= character or not backpack or not humanoid or not humanoid:IsA("Humanoid") then return end
	if character:FindFirstChild("Espada de prueba") or backpack:FindFirstChild("Espada de prueba") then return end
	local sword = makeSword()
	local nextStrike = 0
	sword.Activated:Connect(function()
		if sword.Parent ~= character or player.Character ~= character or humanoid.Health <= 0 then return end
		if player:GetAttribute("InDuel") == true or player:GetAttribute("EquippedWeapon") ~= WeaponData.DEFAULT_WEAPON then return end
		local weapon = WeaponData.Weapons[WeaponData.DEFAULT_WEAPON]
		if os.clock() < nextStrike then return end
		nextStrike = os.clock() + weapon.AttackCooldown
		local motion = TweenService:Create(sword, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
			Grip = CFrame.Angles(math.rad(-65), 0, math.rad(-25)),
		})
		motion:Play()
		hitGuardian(player, character, weapon.Range, weapon.Damage)
	end)
	sword.Parent = backpack
	if player:GetAttribute("InDuel") ~= true then humanoid:EquipTool(sword) end
end

function StudioSword:Init()
	if not RunService:IsStudio() or game.GameId ~= 0 then return end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character) give(player, character) end)
		if player.Character then task.spawn(give, player, player.Character) end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do watch(player) end
end

return StudioSword
