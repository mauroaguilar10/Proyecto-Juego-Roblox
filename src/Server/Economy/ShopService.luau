--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Data = require(script.Parent:WaitForChild("DataService"))
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
		-- Primero lo que ya se verificó en esta sesión (al entrar o al comprarlo recién).
		if not Data.OwnsPass(player, passId) then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
			if not ok then return false, "No se pudo verificar el pase." end
			if not owns then return false, "Se necesita el pase de esta arma." end
			if Data.Profile(player) ~= p or player:GetAttribute("InDuel") == true then return false, "Acción no disponible." end
			Data.GrantPass(player, passId)
		end
		p.owned[requested] = true
	end
	if purchase then
		if p.owned[requested] then return true, "El arma ya está en tu inventario." end
		-- Las armas de Robux se entregan solo desde MonetizationService (ProcessReceipt).
		if weapon.Acquisition == "Robux" then return false, "Esta arma se consigue en la Tienda (Robux)." end
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
	-- Compra de un pase: se activa enseguida (UserOwnsGamePassAsync puede tardar en reflejarla)
	-- y, si trae un arma, se la equipa.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased or player.Parent ~= Players then return end
		if not Data.GrantPass(player, passId) then
			notify:FireClient(player, "¡Gracias por tu compra! El pase se activa la próxima vez que entres.")
			return
		end
		for id, weapon in WeaponData.Weapons do
			if weapon.GamePassId == passId and player:GetAttribute("InDuel") ~= true then
				Data.Equip(player, id)
			end
		end
		if passId == Data.VOID_PASS then
			notify:FireClient(player, "¡Void Pass activado! Guadaña del Vacío equipada y oro x2 en la mazmorra.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		busy[player] = nil
	end)
end

return ShopService
