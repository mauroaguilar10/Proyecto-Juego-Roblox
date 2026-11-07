--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponData = require(ReplicatedStorage.Shared.WeaponData)
local DataService = {}

local function initializePlayer(player: Player)
	if player:GetAttribute("Gold") == nil then
		player:SetAttribute("Gold", 0)
	end

	local equipped = player:GetAttribute("EquippedWeapon")
	if typeof(equipped) ~= "string" or not WeaponData.IsValid(equipped) then
		player:SetAttribute("EquippedWeapon", WeaponData.DEFAULT_WEAPON)
	end
end

function DataService:Init()
	Players.PlayerAdded:Connect(initializePlayer)
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end
end

return DataService
