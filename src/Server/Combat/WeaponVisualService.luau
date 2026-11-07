--!strict
--[[
	WeaponVisualService — Pone en la mano del personaje el modelo del arma equipada.
	Owner: Dev A (Combat).

	- Reconstruye el arma en CharacterAdded y cada vez que cambia Player.EquippedWeapon.
	- El arma es un Model "Weapon" dentro del personaje, unido a la mano con un Weld
	  llamado "WeaponGrip". CombatController anima el C0 de ese Weld para el swing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local WeaponModels = require(script.Parent:WaitForChild("Util"):WaitForChild("WeaponModels"))

local HAND_NAMES = { "RightHand", "Right Arm" } -- R15, R6
local HAND_TIMEOUT = 10
local FALLBACK_GRIP = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

local WeaponVisualService = {}

local function findHand(character: Model): BasePart?
	for _, name in HAND_NAMES do
		local hand = character:FindFirstChild(name)
		if hand and hand:IsA("BasePart") then
			return hand
		end
	end
	return nil
end

local function waitForHand(character: Model): BasePart?
	local deadline = os.clock() + HAND_TIMEOUT
	repeat
		local hand = findHand(character)
		if hand then
			return hand
		end
		character.ChildAdded:Wait()
	until os.clock() > deadline or not character.Parent
	return nil
end

local function equipVisual(player: Player, character: Model)
	local hand = waitForHand(character)
	if not hand or player.Character ~= character then
		return
	end

	local equipped = player:GetAttribute("EquippedWeapon")
	local weapon = WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil)

	local existing = character:FindFirstChild("Weapon")
	if existing then
		if existing:GetAttribute("WeaponId") == weapon.Id then
			return
		end
		existing:Destroy()
	end

	local model = WeaponModels.Build(weapon.Id)
	local grip = model.PrimaryPart :: BasePart

	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local weld = Instance.new("Weld")
	weld.Name = "WeaponGrip"
	weld.Part0 = hand
	weld.Part1 = grip
	weld.C0 = if gripAttachment and gripAttachment:IsA("Attachment") then gripAttachment.CFrame else FALLBACK_GRIP
	weld.Parent = grip

	model.Parent = character
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		equipVisual(player, character)
	end)

	player:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
		local character = player.Character
		if character then
			equipVisual(player, character)
		end
	end)

	if player.Character then
		task.spawn(equipVisual, player, player.Character)
	end
end

function WeaponVisualService:Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return WeaponVisualService
