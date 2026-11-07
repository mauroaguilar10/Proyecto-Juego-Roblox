--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local WeaponData = require(Shared.WeaponData)
local Data = require(script.Parent.DataService)
local ShopService = {}
local lastAction: {[Player]: number} = {}
local busy: {[Player]: boolean} = {}

local function useWeapon(player: Player, requested: any, purchase: boolean): (boolean, string)
	if typeof(requested) ~= "string" then return false, "Arma inválida." end
	local weapon = WeaponData.Get(requested)
	if not weapon then return false, "Arma desconocida." end
	local p = Data.Profile(player)
	if not p then return false, "Inventario no disponible." end
	if player:GetAttribute("InDuel") == true then return false, "Esperá a que termine el duelo." end
	if weapon.Acquisition == "GamePass" then
		local passId = weapon.GamePassId
		if not passId or passId <= 0 then return false, "Este pase todavía no está disponible." end
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if not ok then return false, "No se pudo verificar el pase." end
		if not owns then return false, "Se necesita el pase de esta arma." end
		if Data.Profile(player) ~= p or player:GetAttribute("InDuel") == true then return false, "Acción no disponible." end
		p.owned[requested] = true
	end
	if purchase then
		if p.owned[requested] then return true, "El arma ya está en tu inventario." end
		if weapon.Acquisition == "Gold" and not Data.ChangeGold(player, -weapon.Price) then
			return false, "Oro insuficiente."
		end
		p.owned[requested] = true
		return true, "Agregaste " .. weapon.DisplayName .. " al inventario."
	end
	if not p.owned[requested] then return false, "Todavía no tenés esta arma." end
	Data.Equip(player, requested)
	return true, "Equipaste " .. weapon.DisplayName .. "."
end

local function request(player: Player, id: any, purchase: boolean): (boolean, string)
	local now = os.clock()
	if busy[player] or now < (lastAction[player] or -1) + 0.35 then return false, "Esperá un instante." end
	lastAction[player] = now
	busy[player] = true
	local ok, success, message = pcall(useWeapon, player, id, purchase)
	busy[player] = nil
	if not ok then
		warn("[Shop] Falló una solicitud", success)
		return false, "No se pudo procesar la solicitud."
	end
	return success, message
end

function ShopService:Init()
	local notify = Remotes.GetEvent("Notify")
	Remotes.GetFunction("GetInventory").OnServerInvoke = function(player: Player)
		local p = Data.Profile(player)
		return if p then table.clone(p.owned) else nil
	end
	Remotes.GetFunction("PurchaseWeapon").OnServerInvoke = function(player: Player, id: any)
		return request(player, id, true)
	end
	Remotes.GetEvent("EquipWeapon").OnServerEvent:Connect(function(player, id)
		local _, message = request(player, id, false)
		if player.Parent == Players then notify:FireClient(player, message) end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		busy[player] = nil
	end)
end

return ShopService
