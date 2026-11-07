--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local WeaponData = require(Shared.WeaponData)
local Data = require(script.Parent.DataService)
local DungeonService = {}
local random = Random.new()
local GOLD_PER_ENEMY = 25

local function part(parent: Instance, name: string, position: Vector3, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Parent = parent
	return p
end

local function spawnEnemy(parent: Instance, position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Guardián de piedra"
	local root = part(model, "HumanoidRootPart", position, Vector3.new(2, 2, 1), Color3.new())
	root.Transparency = 1
	root.CanCollide = false
	local torso = part(model, "Torso", position, Vector3.new(3, 3, 2), Color3.fromRGB(83, 104, 102))
	local head = part(model, "Head", position + Vector3.new(0, 2.35, 0), Vector3.new(1.8, 1.7, 1.7), Color3.fromRGB(133, 155, 138))
	for _, piece in {torso, head} do
		local base = if piece == torso then root else torso
		local joint = Instance.new("Motor6D")
		joint.Name = if piece == torso then "RootJoint" else "Neck"
		joint.Part0 = base
		joint.Part1 = piece
		joint.C0 = base.CFrame:ToObjectSpace(piece.CFrame)
		joint.Parent = base
		piece.Anchored = false
	end
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	humanoid.Died:Once(function()
		task.delay(2, function() model:Destroy() end)
		task.delay(8, function()
			if parent.Parent then spawnEnemy(parent, position) end
		end)
		local attacker = humanoid:GetAttribute("LastAttacker")
		if typeof(attacker) ~= "number" or attacker == 0 or attacker % 1 ~= 0 then return end
		local player = Players:GetPlayerByUserId(attacker)
		if not player then return end
		local profile = Data.Profile(player)
		if not profile or not Data.ChangeGold(player, GOLD_PER_ENEMY) then return end
		local message = "+" .. GOLD_PER_ENEMY .. " de oro"
		for id, weapon in WeaponData.Weapons do
			if weapon.Acquisition ~= "GamePass" and weapon.DropChance > 0 and not profile.owned[id]
				and random:NextNumber() < weapon.DropChance then
				profile.owned[id] = true
				message ..= " · Encontraste " .. weapon.DisplayName
			end
		end
		Remotes.GetEvent("Notify"):FireClient(player, message)
	end)
	model.Parent = parent
end

local function portal(parent: Instance, name: string, pos: Vector3, target: Vector3, entering: boolean)
	local stone = part(parent, name, pos, Vector3.new(4, 4, 2), Color3.fromRGB(64, 104, 119))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Mazmorra"
	prompt.ActionText = name
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = stone
	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if not char or not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then return end
		if (root.Position - stone.Position).Magnitude > prompt.MaxActivationDistance + 1 then return end
		if entering and (player:GetAttribute("InDuel") == true or not Data.Profile(player)) then
			Remotes.GetEvent("Notify"):FireClient(player, "Entrada bloqueada durante un duelo o mientras se carga tu inventario.")
			return
		end
		char:PivotTo(CFrame.new(target))
	end)
end

function DungeonService:Init()
	local folder = Instance.new("Folder")
	folder.Name = "Mazmorra"
	folder.Parent = workspace
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local center = origin + Vector3.new(0, 160, 0)
	local entrance = origin + Vector3.new(10, 2, 0)
	part(folder, "Piso", center, Vector3.new(54, 2, 54), Color3.fromRGB(64, 70, 75))
	portal(folder, "Entrar", entrance, center + Vector3.new(0, 5, 15), true)
	portal(folder, "Salir", center + Vector3.new(0, 3, 21), entrance + Vector3.new(0, 2, 5), false)
	for _, x in {-12, 0, 12} do
		spawnEnemy(folder, center + Vector3.new(x, 2.5, -8))
	end
end

return DungeonService
