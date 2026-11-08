--!strict
-- Señales entre controladores del cliente (Economía).
-- OpenPremiumShop:Fire(categoria?) abre la tienda de Robux (PremiumShopController) en esa sección.
local Signals = {
	OpenPremiumShop = Instance.new("BindableEvent"),
}
return Signals
