--!strict
--[[
	StoreData — Catálogo de la tienda de Robux (productos de desarrollador).
	Owner: Dev B (Economía). Lectores: MonetizationService (servidor, entrega lo comprado)
	y PremiumShopController (cliente, muestra la tienda y abre la compra).

	ProductId: ID del producto de desarrollador creado en el Creator Hub
	(Monetización → Productos de desarrollador). Con 0 el producto aparece como "Próximamente".
	Los sets y las armas son compras permanentes (se guardan en el perfil); oro y potenciadores
	se pueden comprar las veces que se quiera.
]]

export type Category = "Sets" | "Armas" | "Potenciadores" | "Oro"

export type Product = {
	Key: string,
	ProductId: number,
	Category: Category,
	DisplayName: string,
	Description: string,
	SuggestedPrice: number, -- Robux sugeridos al crear el producto (el precio real lo da Roblox)
	-- Qué entrega (uno de estos):
	Gold: number?,
	Boost: string?, -- "Gold" | "Damage"
	BoostSeconds: number?,
	WeaponId: string?,
	ArmorSet: string?,
}

local Products: { Product } = {
	{
		Key = "StormSet", ProductId = 3729536652, Category = "Sets", SuggestedPrice = 799,
		DisplayName = "Armadura de la Tormenta",
		Description = "Set completo (casco, pechera y pantalón) de acero tormenta con runas de rayo.",
		ArmorSet = "Storm",
	},
	{
		Key = "PhoenixBlade", ProductId = 3729537758, Category = "Armas", SuggestedPrice = 499,
		DisplayName = "Hoja del Fénix",
		Description = "Espada de llamas vivas: fuego, brasas y una estela ardiente en cada golpe.",
		WeaponId = "PhoenixBlade",
	},
	{
		Key = "StormHammer", ProductId = 3729537921, Category = "Armas", SuggestedPrice = 599,
		DisplayName = "Martillo del Trueno",
		Description = "Martillo de guerra cargado de rayos: chispas, runas eléctricas y estela.",
		WeaponId = "StormHammer",
	},
	{
		Key = "GoldBoost10", ProductId = 3729545023, Category = "Potenciadores", SuggestedPrice = 49,
		DisplayName = "Oro x2 · 10 min",
		Description = "Durante 10 minutos ganás el doble de oro en la mazmorra. Se acumula.",
		Boost = "Gold", BoostSeconds = 600,
	},
	{
		Key = "DamageBoost10", ProductId = 3729545306, Category = "Potenciadores", SuggestedPrice = 49,
		DisplayName = "Daño x2 · 10 min",
		Description = "Durante 10 minutos hacés el doble de daño a los enemigos de la mazmorra. Se acumula.",
		Boost = "Damage", BoostSeconds = 600,
	},
	{
		Key = "Gold5k", ProductId = 3729541951, Category = "Oro", SuggestedPrice = 49,
		DisplayName = "5.000 de oro", Description = "Una bolsa de oro.", Gold = 5000,
	},
	{
		Key = "Gold20k", ProductId = 3729542068, Category = "Oro", SuggestedPrice = 149,
		DisplayName = "20.000 de oro", Description = "Un cofre de oro.", Gold = 20000,
	},
	{
		Key = "Gold100k", ProductId = 3729542204, Category = "Oro", SuggestedPrice = 499,
		DisplayName = "100.000 de oro", Description = "El tesoro del dragón.", Gold = 100000,
	},
}

local StoreData = {
	CATEGORIES = { "Sets", "Armas", "Potenciadores", "Oro" } :: { Category },
	Products = Products,
}

function StoreData.ByProductId(productId: number): Product?
	if productId <= 0 then return nil end
	for _, p in Products do
		if p.ProductId == productId then return p end
	end
	return nil
end

function StoreData.ByKey(key: string): Product?
	for _, p in Products do
		if p.Key == key then return p end
	end
	return nil
end

return StoreData
