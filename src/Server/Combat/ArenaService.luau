--!strict
--[[
	ArenaService — Duelos 1v1.
	Owner: Dev A (Combat).

	Estado actual: solo expone la API que necesita CombatService.
	Sin duelos activos, AreOpponents() siempre devuelve false → PvP deshabilitado.
	El flujo de desafío/arena/cuenta regresiva llega en el próximo paso.

	Attributes que ESCRIBE: Player.InDuel (boolean)
]]

local Players = game:GetService("Players")

local opponents: { [Player]: Player } = {}

local ArenaService = {}

-- true si `a` y `b` están en el mismo duelo activo.
function ArenaService.AreOpponents(a: Player, b: Player): boolean
	return opponents[a] == b and a:GetAttribute("InDuel") == true and b:GetAttribute("InDuel") == true
end

function ArenaService:Init()
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("InDuel", false)
	end)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("InDuel") == nil then
			player:SetAttribute("InDuel", false)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		local opponent = opponents[player]
		opponents[player] = nil
		if opponent then
			opponents[opponent] = nil
			opponent:SetAttribute("InDuel", false)
		end
	end)
end

return ArenaService
