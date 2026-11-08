--!strict
--[[
	MonetizationService — Entrega las compras de la tienda de Robux (productos de desarrollador).
	Owner: Dev B (Economía).

	Es el ÚNICO lugar del juego que define MarketplaceService.ProcessReceipt (Roblox admite uno solo).
	Productos: Shared/StoreData (oro, potenciadores, armas y sets de armadura).

	Reglas de Roblox para no perder ni duplicar compras:
	  - Si el perfil del jugador no cargó (o se fue), se devuelve NotProcessedYet y Roblox reintenta.
	  - Cada PurchaseId se anota en el perfil: una compra reintentada no se entrega dos veces.
	  - Se guarda el perfil antes de devolver PurchaseGranted.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreData = require(Shared:WaitForChild("StoreData"))
local ArmorData = require(Shared:WaitForChild("ArmorData"))
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Data = require(script.Parent:WaitForChild("DataService"))
local MonetizationService = {}

-- Entrega el producto. Devuelve el mensaje para el jugador, o nil si no se pudo.
local function deliver(player: Player, product: StoreData.Product): string?
	local p = Data.Profile(player)
	if not p then return nil end
	if product.Gold then
		if not Data.ChangeGold(player, product.Gold) then return nil end
		return `¡Gracias! +{product.Gold} de oro`
	elseif product.Boost and product.BoostSeconds then
		if not Data.AddBoost(player, product.Boost, product.BoostSeconds) then return nil end
		return `¡{product.DisplayName} activado! Se suma a lo que te quedaba.`
	elseif product.WeaponId then
		local weapon = WeaponData.Get(product.WeaponId)
		if not weapon then return nil end
		p.owned[weapon.Id] = true
		if player:GetAttribute("InDuel") ~= true then Data.Equip(player, weapon.Id) end
		return `¡{weapon.DisplayName} es tuya! Ya la tenés equipada.`
	elseif product.ArmorSet then
		for _, piece in ArmorData.SetPieces(product.ArmorSet) do
			p.armorOwned[piece.Id] = true
		end
		return `¡{product.DisplayName} es tuya! Equipala desde la armería.`
	end
	return nil
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local purchaseId = tostring(receipt.PurchaseId)
	local already = Data.HasReceipt(player, purchaseId)
	if already == nil then return Enum.ProductPurchaseDecision.NotProcessedYet end -- perfil sin cargar
	if already then return Enum.ProductPurchaseDecision.PurchaseGranted end

	local product = StoreData.ByProductId(receipt.ProductId)
	if not product then
		warn("[Store] Producto desconocido", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local message = deliver(player, product)
	if not message then return Enum.ProductPurchaseDecision.NotProcessedYet end
	Data.MarkReceipt(player, purchaseId)
	Data.SaveNow(player)
	Remotes.GetEvent("Notify"):FireClient(player, message)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService:Init()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(processReceipt, receipt)
		if not ok then
			warn("[Store] Falló la entrega de una compra", decision)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
end

return MonetizationService
