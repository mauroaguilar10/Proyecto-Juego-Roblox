--!strict
--[[
	PremiumShopController — Tienda de Robux (cliente).
	Owner: Dev B (Economía).

	- Botón "Tienda" al costado izquierdo, en el centro de la pantalla. Debajo, los potenciadores
	  activos con su tiempo restante (Player.GoldBoostUntil / DamageBoostUntil, en tiempo del servidor).
	- Ventana con secciones Sets, Armas, Potenciadores y Oro (Shared/StoreData). Cada ficha abre la
	  compra con MarketplaceService:PromptProductPurchase; la entrega la hace MonetizationService.
	  El set del Vacío no es un producto: viene con el Void Pass (abre la compra del pase).
	- También se abre desde otras ventanas con Signals.OpenPremiumShop:Fire(sección).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreData = require(Shared:WaitForChild("StoreData"))
local ArmorData = require(Shared:WaitForChild("ArmorData"))
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Util = script.Parent:WaitForChild("Util")
local Sounds = require(Util:WaitForChild("Sounds"))
local Signals = require(Util:WaitForChild("Signals"))
local ArmorPreview = require(Util:WaitForChild("ArmorPreview"))
local WeaponPreview = require(Util:WaitForChild("WeaponPreview"))
local PremiumShopController = {}

local INK = Color3.fromRGB(15, 19, 26)
local SLATE = Color3.fromRGB(30, 36, 45)
local GOLD = Color3.fromRGB(237, 197, 118)
local IVORY = Color3.fromRGB(246, 237, 216)
local MUTED = Color3.fromRGB(170, 178, 186)
local EDGE = Color3.fromRGB(71, 76, 82)
local ROBUX_GREEN = Color3.fromRGB(46, 160, 92)
local VIOLET = Color3.fromRGB(176, 120, 255)
local CAPTION = 118

local ICONS: { [string]: { string } } = {
	Gold = { "💰", "x2" },
	Damage = { "⚔️", "x2" },
}

local function frame(parent: Instance, pos: UDim2, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3, f.BorderSizePixel = color, 0
	f.Position, f.Size, f.Parent = pos, size, parent
	return f
end

local function text(parent: Instance, value: string, pos: UDim2, size: UDim2, font: Enum.Font, points: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text, t.Position, t.Size = value, pos, size
	t.Font, t.TextSize, t.TextColor3 = font, points, color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

local function button(parent: Instance, value: string, pos: UDim2, size: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Text, b.Position, b.Size = value, pos, size
	b.BackgroundColor3, b.TextColor3 = color, IVORY
	b.Font, b.TextSize, b.BorderSizePixel = Enum.Font.GothamBold, 15, 0
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local function stroke(obj: GuiObject, color: Color3, thickness: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode, s.Color, s.Thickness, s.Parent = Enum.ApplyStrokeMode.Border, color, thickness or 1, obj
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Ilustración de las fichas sin modelo (oro y potenciadores): ícono grande sobre un degradado.
local function badge(parent: GuiObject, icon: string, tag: string, colors: ColorSequence)
	local art = frame(parent, UDim2.fromOffset(6, 6), UDim2.new(1, -12, 1, -(CAPTION + 6)), Color3.new(1, 1, 1))
	Instance.new("UICorner", art).CornerRadius = UDim.new(0, 8)
	local gradient = Instance.new("UIGradient")
	gradient.Color, gradient.Rotation, gradient.Parent = colors, 45, art
	local big = text(art, icon, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.Font.GothamBlack, 60, IVORY)
	big.TextXAlignment = Enum.TextXAlignment.Center
	big.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize, limit.Parent = 72, big
	local label = text(art, tag, UDim2.new(1, -78, 1, -40), UDim2.fromOffset(70, 34), Enum.Font.GothamBlack, 28, IVORY)
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextStrokeTransparency = 0.3
end

type Card = { button: TextButton, owned: () -> boolean, product: StoreData.Product?, voidSet: boolean }

function PremiumShopController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn = "TiendaRobux", false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- ── Botón lateral y potenciadores activos ──
	local open = button(gui, "", UDim2.new(0, 14, 0.5, 0), UDim2.fromOffset(128, 56), Color3.fromRGB(28, 34, 44))
	open.Name = "AbrirTienda"
	open.AnchorPoint = Vector2.new(0, 0.5)
	stroke(open, GOLD, 2)
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 170, 130))
	shine.Rotation, shine.Parent = 90, open
	text(open, "🛒", UDim2.fromOffset(10, 0), UDim2.new(0, 36, 1, 0), Enum.Font.GothamBold, 26, GOLD)
	text(open, "Tienda", UDim2.fromOffset(48, 6), UDim2.new(1, -52, 0, 26), Enum.Font.GothamBlack, 20, IVORY)
	text(open, "Robux", UDim2.fromOffset(48, 30), UDim2.new(1, -52, 0, 18), Enum.Font.GothamBold, 13, Color3.fromRGB(110, 220, 140))

	local boostList = frame(gui, UDim2.new(0, 14, 0.5, 36), UDim2.fromOffset(170, 80), INK)
	boostList.BackgroundTransparency = 1
	local boostLayout = Instance.new("UIListLayout")
	boostLayout.Padding, boostLayout.Parent = UDim.new(0, 4), boostList
	local boostRows: { [string]: TextLabel } = {}
	for _, kind in { "Gold", "Damage" } do
		local row = text(boostList, "", UDim2.new(), UDim2.fromOffset(170, 26), Enum.Font.GothamBold, 14, IVORY)
		row.BackgroundColor3, row.BackgroundTransparency = if kind == "Gold" then Color3.fromRGB(120, 90, 20) else Color3.fromRGB(120, 30, 30), 0.15
		row.TextXAlignment = Enum.TextXAlignment.Center
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
		row.Visible = false
		boostRows[kind] = row
	end
	task.spawn(function()
		while true do
			local now = workspace:GetServerTimeNow()
			for kind, row in boostRows do
				local untilTime = player:GetAttribute(if kind == "Gold" then "GoldBoostUntil" else "DamageBoostUntil")
				local left = if typeof(untilTime) == "number" then untilTime - now else 0
				row.Visible = left > 0
				if left > 0 then
					row.Text = `{ICONS[kind][1]} {if kind == "Gold" then "Oro" else "Daño"} x2 · {clock(left)}`
				end
			end
			task.wait(1)
		end
	end)

	-- ── Ventana ──
	local shade = Instance.new("TextButton")
	shade.Text, shade.AutoButtonColor = "", false
	shade.Size, shade.BackgroundColor3, shade.BackgroundTransparency = UDim2.fromScale(1, 1), Color3.new(), 0.3
	shade.Visible, shade.ZIndex = false, 10
	shade.Parent = gui
	local panel = frame(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.94, 0.9), INK)
	panel.AnchorPoint, panel.Active, panel.Visible, panel.ZIndex = Vector2.new(0.5, 0.5), true, false, 11
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize, limit.Parent = Vector2.new(880, 580), panel
	stroke(panel, GOLD)
	frame(panel, UDim2.new(), UDim2.new(1, 0, 0, 3), GOLD)
	text(panel, "Tienda", UDim2.fromOffset(18, 8), UDim2.new(0.5, 0, 0, 44), Enum.Font.Antique, 36, IVORY)
	text(panel, "Objetos exclusivos, potenciadores y oro", UDim2.fromOffset(20, 50), UDim2.new(0.6, 0, 0, 18), Enum.Font.Gotham, 14, MUTED)
	local close = button(panel, "×", UDim2.new(1, -52, 0, 12), UDim2.fromOffset(40, 40), Color3.fromRGB(66, 35, 42))
	close.TextSize = 26
	local message = text(panel, "", UDim2.new(0, 18, 1, -28), UDim2.new(1, -36, 0, 22), Enum.Font.GothamMedium, 14, MUTED)
	message.TextXAlignment = Enum.TextXAlignment.Center

	local tabs: { [string]: TextButton } = {}
	local pages: { [string]: ScrollingFrame } = {}
	local current = "Sets"
	for i, category in StoreData.CATEGORIES do
		local tab = button(panel, category, UDim2.fromOffset(18 + (i - 1) * 132, 78), UDim2.fromOffset(124, 34), SLATE)
		tabs[category] = tab
		local page = Instance.new("ScrollingFrame")
		page.Position, page.Size = UDim2.fromOffset(16, 122), UDim2.new(1, -32, 1, -156)
		page.BackgroundTransparency, page.BorderSizePixel = 1, 0
		page.ScrollBarThickness, page.ScrollBarImageColor3 = 3, GOLD
		page.AutomaticCanvasSize, page.CanvasSize = Enum.AutomaticSize.Y, UDim2.new()
		page.Visible = false
		page.Parent = panel
		local grid = Instance.new("UIGridLayout")
		grid.CellPadding, grid.SortOrder = UDim2.fromOffset(10, 10), Enum.SortOrder.LayoutOrder
		grid.Parent = page
		page:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local width = page.AbsoluteSize.X
			local columns = if width >= 620 then 3 elseif width >= 400 then 2 else 1
			grid.CellSize = UDim2.fromOffset(math.floor((width - 6 - (columns - 1) * 10) / columns), 320)
		end)
		pages[category] = page
	end

	local function selectTab(category: string)
		current = category
		for name, tab in tabs do
			tab.BackgroundColor3 = if name == category then Color3.fromRGB(92, 68, 28) else SLATE
			pages[name].Visible = name == category
		end
	end
	for name, tab in tabs do
		tab.Activated:Connect(function() selectTab(name) end)
	end

	-- Estado de lo comprado (armas y armaduras), pedido al abrir.
	local ownedWeapons: { [string]: boolean } = {}
	local ownedArmor: { [string]: boolean } = {}
	local cards: { Card } = {}
	local prices: { [number]: number } = {}

	local function render()
		for _, card in cards do
			local b = card.button
			if card.owned() then
				b.Text, b.BackgroundColor3, b.Interactable = "Comprado ✓", Color3.fromRGB(44, 86, 60), false
			elseif card.voidSet then
				b.Text, b.BackgroundColor3, b.Interactable = "★ Void Pass", Color3.fromRGB(80, 40, 120), true
			elseif card.product and card.product.ProductId > 0 then
				local price = prices[card.product.ProductId]
				b.Text = if price then `R$ {price}` else "Comprar"
				b.BackgroundColor3, b.Interactable = ROBUX_GREEN, true
			else
				b.Text, b.BackgroundColor3, b.Interactable = "Próximamente", Color3.fromRGB(70, 74, 82), false
			end
		end
	end

	local function refresh()
		local okInv, inventory = pcall(function() return Remotes.GetFunction("GetInventory"):InvokeServer() end)
		if okInv and typeof(inventory) == "table" then ownedWeapons = inventory end
		local okArmor, _, _, state = pcall(function() return Remotes.GetFunction("ArmorShop"):InvokeServer("Get") end)
		if okArmor and typeof(state) == "table" and typeof(state.owned) == "table" then ownedArmor = state.owned end
		render()
	end

	local function newCard(category: string, order: number, title: string, description: string, accent: Color3): (Frame, TextButton)
		local card = frame(pages[category], UDim2.new(), UDim2.new(), SLATE)
		card.LayoutOrder, card.ClipsDescendants = order, true
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
		stroke(card, accent)
		local caption = frame(card, UDim2.new(0, 0, 1, -CAPTION), UDim2.new(1, 0, 0, CAPTION), INK)
		local name = text(caption, title, UDim2.fromOffset(10, 4), UDim2.new(1, -20, 0, 26), Enum.Font.GothamBlack, 17, accent)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local desc = text(caption, description, UDim2.fromOffset(10, 30), UDim2.new(1, -20, 0, 44), Enum.Font.Gotham, 13, MUTED)
		desc.TextWrapped, desc.TextYAlignment = true, Enum.TextYAlignment.Top
		local buy = button(caption, "", UDim2.new(0, 10, 1, -40), UDim2.new(1, -20, 0, 32), ROBUX_GREEN)
		return card, buy
	end

	local function hasPiecesOf(setId: string): boolean
		for _, p in ArmorData.SetPieces(setId) do
			if not ownedArmor[p.Id] then return false end
		end
		return true
	end

	-- Set del Vacío (viene con el Void Pass).
	do
		local voidPieces = {}
		for _, p in ArmorData.SetPieces("Void") do table.insert(voidPieces, p.Id) end
		local card, buy = newCard("Sets", 0, "Armadura del Vacío", "Set completo del vacío. Viene con el Void Pass junto a la Guadaña del Vacío y oro x2.", VIOLET)
		ArmorPreview.draw(card, voidPieces, CAPTION)
		table.insert(cards, { button = buy, owned = function() return player:GetAttribute("VoidPass") == true end, product = nil, voidSet = true })
		buy.Activated:Connect(function()
			local passId = WeaponData.Weapons.VoidScythe.GamePassId
			if passId and passId > 0 then MarketplaceService:PromptGamePassPurchase(player, passId) end
		end)
	end

	for order, product in StoreData.Products do
		local accent = if product.Category == "Oro" then GOLD elseif product.Category == "Potenciadores" then Color3.fromRGB(255, 150, 90) else Color3.fromRGB(120, 220, 255)
		local card, buy = newCard(product.Category, order, product.DisplayName, product.Description, accent)
		local owned: () -> boolean = function() return false end
		if product.ArmorSet then
			local ids = {}
			for _, p in ArmorData.SetPieces(product.ArmorSet) do table.insert(ids, p.Id) end
			ArmorPreview.draw(card, ids, CAPTION)
			local setId = product.ArmorSet
			owned = function() return hasPiecesOf(setId) end
		elseif product.WeaponId then
			WeaponPreview.draw(card, product.WeaponId, CAPTION)
			local weaponId = product.WeaponId
			owned = function() return ownedWeapons[weaponId] == true end
		elseif product.Boost then
			local icon = ICONS[product.Boost] or { "⭐", "" }
			badge(card, icon[1], `{icon[2]} · 10 min`, ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(150, 40, 40)))
		elseif product.Gold then
			local amount = product.Gold
			badge(card, if amount >= 100000 then "👑" elseif amount >= 20000 then "🪙" else "💰",
				if amount >= 1000 then `{amount // 1000}k` else tostring(amount), ColorSequence.new(Color3.fromRGB(255, 215, 90), Color3.fromRGB(170, 110, 20)))
		end
		table.insert(cards, { button = buy, owned = owned, product = product, voidSet = false })
		buy.Activated:Connect(function()
			if product.ProductId <= 0 or owned() then return end
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		end)
		-- Precio real en Robux (lo da Roblox).
		if product.ProductId > 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.ProductId, Enum.InfoType.Product)
				if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
					prices[product.ProductId] = info.PriceInRobux
					render()
				end
			end)
		end
	end

	-- Capas por encima de la sombra.
	for _, d in panel:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = 12 end
	end

	local function show(visible: boolean, category: string?)
		panel.Visible, shade.Visible = visible, visible
		open.Visible = not visible
		if visible then
			message.Text = ""
			selectTab(category or current)
			Sounds.Play("Tienda")
			task.spawn(refresh)
		end
	end
	open.Activated:Connect(function() show(true) end)
	close.Activated:Connect(function() show(false) end)
	shade.Activated:Connect(function() show(false) end)
	Signals.OpenPremiumShop.Event:Connect(function(category)
		show(true, if typeof(category) == "string" and pages[category] then category else nil)
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, purchased)
		if userId ~= player.UserId or not purchased then return end
		Sounds.Play("Compra")
		message.Text, message.TextColor3 = "¡Compra recibida! Se entrega en unos segundos.", Color3.fromRGB(120, 220, 120)
		task.delay(2, refresh)
	end)
	player:GetAttributeChangedSignal("VoidPass"):Connect(render)
	selectTab("Sets")
	render()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return PremiumShopController
