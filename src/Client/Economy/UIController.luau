--!strict
local Players = game:GetService("Players")
local Marketplace = game:GetService("MarketplaceService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local WeaponData = require(Shared:WaitForChild("WeaponData") :: ModuleScript)
local Preview = require(script.Parent.Util.WeaponPreview)
local UIController = {}

local ink = Color3.fromRGB(15, 19, 26)
local slate = Color3.fromRGB(30, 36, 45)
local gold = Color3.fromRGB(237, 197, 118)
local ivory = Color3.fromRGB(246, 237, 216)
local muted = Color3.fromRGB(170, 178, 186)
local edge = Color3.fromRGB(71, 76, 82)
local function frame(parent: Instance, pos: UDim2, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position, f.Size, f.Parent = pos, size, parent
	return f
end
local function stroke(obj: GuiObject, color: Color3): UIStroke
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color, st.Parent = color, obj
	return st
end
local function label(parent: Instance, value: string, pos: UDim2, size: UDim2, font: Enum.Font, points: number, color: Color3): TextLabel
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
	b.BackgroundColor3, b.TextColor3 = color, ivory
	b.Font, b.TextSize = Enum.Font.GothamBold, 15
	b.BorderSizePixel = 0
	b.Parent = parent
	return b
end
local function balance(parent: Instance, pos: UDim2): TextLabel
	local box = frame(parent, pos, UDim2.fromOffset(109, 34), ink)
	box.AnchorPoint = Vector2.new(1, 0)
	stroke(box, gold)
	local coin = frame(box, UDim2.fromOffset(10, 8), UDim2.fromOffset(18, 18), gold)
	Instance.new("UICorner", coin).CornerRadius = UDim.new(1, 0)
	local hole = frame(coin, UDim2.fromOffset(6, 6), UDim2.fromOffset(6, 6), Color3.fromRGB(127, 86, 37))
	hole.Rotation = 45
	return label(box,"",UDim2.fromOffset(35,0),UDim2.new(1,-38,1,0),Enum.Font.GothamBold,17,gold)
end
local function cart(parent: GuiObject)
	local function bar(x: number, y: number, w: number, h: number, r: number)
		local f = frame(parent, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h), gold)
		f.Rotation = r
		return f
	end
	bar(7,13,9,3,12)
	bar(14,19,13,3,68)
	bar(17,17,23,3,0)
	bar(17,25,19,3,0)
	bar(32,21,11,3,-67)
	bar(20,29,15,2,0)
	for _, x in {20,31} do
		Instance.new("UICorner",bar(x,33,5,5,0)).CornerRadius = UDim.new(1,0)
	end
end

function UIController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn = "EconomyHUD", false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local hudGold = balance(gui, UDim2.new(1,-14,0,10))
	local toggle = button(gui, "", UDim2.new(0.5,0,1,-68), UDim2.fromOffset(122,48),ink)
	toggle.Name = "Tienda"
	toggle.AnchorPoint = Vector2.new(0.5,1)
	stroke(toggle,gold)
	cart(toggle)
	label(toggle,"Tienda",UDim2.fromOffset(47,0),UDim2.new(1,-49,1,0),Enum.Font.GothamBold,17,ivory)
	local shade = button(gui,"",UDim2.new(),UDim2.fromScale(1,1),Color3.new())
	shade.AutoButtonColor = false
	shade.BackgroundTransparency = 0.28
	shade.Visible = false
	local panel = frame(gui,UDim2.fromScale(0.5,0.5),UDim2.fromScale(0.94,0.9),ink)
	panel.AnchorPoint = Vector2.new(0.5,0.5)
	panel.Active, panel.Visible = true, false
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize, limit.Parent = Vector2.new(900,512),panel
	stroke(panel, edge)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(179,189,205))
	gradient.Rotation, gradient.Parent = 25, panel
	frame(panel,UDim2.new(),UDim2.new(1,0,0,2),gold)
	label(panel,"Tienda",UDim2.fromOffset(18,10),UDim2.new(0.47,0,0,48),Enum.Font.Antique,34,ivory)
	local shopGold = balance(panel,UDim2.new(1,-72,0,17))
	local close = button(panel,"×",UDim2.new(1,-54,0,13),UDim2.fromOffset(40,40),Color3.fromRGB(66,35,42))
	close.TextSize = 27
	stroke(close, Color3.fromRGB(151,77,80))
	frame(panel,UDim2.fromOffset(16,64),UDim2.new(1,-32,0,1),edge)
	local all = button(panel,"Armas",UDim2.fromOffset(16,71),UDim2.fromOffset(102,36),slate)
	local mine = button(panel,"Inventario",UDim2.fromOffset(124,71),UDim2.fromOffset(112,36),slate)
	local underline = frame(panel,UDim2.fromOffset(16,107),UDim2.fromOffset(102,2),gold)
	local list = Instance.new("ScrollingFrame")
	list.Name = "Catalogo"
	list.Position, list.Size = UDim2.fromOffset(16,120), UDim2.new(1,-32,1,-134)
	list.BorderSizePixel, list.BackgroundTransparency = 0, 1
	list.ScrollBarThickness, list.ScrollBarImageColor3 = 3,gold
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize, list.CanvasSize = Enum.AutomaticSize.Y,UDim2.new()
	list.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromOffset(9,9)
	grid.Parent = list
	local function resize()
		local width = list.AbsoluteSize.X
		local columns = if width >= 570 then 3 elseif width >= 265 then 2 else 1
		local cell = math.max(1,math.floor((width-5-(columns-1)*9)/columns))
		grid.CellSize = UDim2.fromOffset(cell,math.clamp(cell+45,189,285))
	end
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	local message = label(gui,"",UDim2.new(0.5,0,1,-12),UDim2.new(0.86,0,0,43),Enum.Font.GothamMedium,15,ivory)
	message.AnchorPoint = Vector2.new(0.5,1)
	message.TextXAlignment, message.TextWrapped = Enum.TextXAlignment.Center,true
	message.BackgroundColor3, message.BackgroundTransparency = slate,0
	message.ZIndex, message.Visible = 5,false
	local ml = Instance.new("UISizeConstraint")
	ml.MaxSize, ml.Parent = Vector2.new(490,65),message
	stroke(message,gold)
	local messageId = 0
	local function notify(text: string)
		messageId += 1
		local current = messageId
		message.Text, message.Visible = text, true
		task.delay(5, function()
			if current == messageId then message.Visible = false end
		end)
	end

	local owned: {[string]: boolean}? = nil
	local inventoryOnly = false
	type Card = {button: TextButton, state: TextLabel, border: UIStroke}
	local rows: {[string]: Card} = {}
	local function render()
		local value = player:GetAttribute("Gold")
		local amount = if typeof(value) == "number" then tostring(value) else "…"
		hudGold.Text, shopGold.Text = amount, amount
		all.TextColor3 = if inventoryOnly then muted else gold
		mine.TextColor3 = if inventoryOnly then gold else muted
		underline.Position = UDim2.fromOffset(if inventoryOnly then 124 else 16,107)
		underline.Size = UDim2.fromOffset(if inventoryOnly then 112 else 102,2)
		for id, card in rows do
			local w = WeaponData.Weapons[id]
			local equipped = player:GetAttribute("EquippedWeapon") == id
			local available = true
			local action: string
			if equipped then
				action, available = "✓  Equipada", false
			elseif player:GetAttribute("InDuel") == true then
				action, available = "En duelo", false
			elseif not owned then
				action, available = "Cargando…", false
			elseif owned[id] then
				action = "Equipar"
			elseif w.Acquisition == "GamePass" then
				available = (w.GamePassId or 0) > 0
				action = if available then "Ver pase" else "Pase pendiente"
			elseif w.Acquisition == "Gold" then
				action = "Comprar · " .. tostring(w.Price) .. " oro"
			else
				action = "Obtener"
			end
			card.button.Visible = not inventoryOnly or equipped or (owned ~= nil and owned[id] == true)
			card.button.Interactable = available
			card.state.Text = action
			card.state.TextColor3 = if equipped or available then gold else muted
			card.border.Color = if equipped then gold else edge
		end
	end
	local generation = 0
	local function refresh()
		generation += 1
		local version = generation
		local ok, result = pcall(function() return Remotes.GetFunction("GetInventory"):InvokeServer() end)
		if version ~= generation then return end
		owned = if ok and typeof(result) == "table" then result else nil
		render()
		if not owned and panel.Visible then
			task.delay(2, function()
				if panel.Visible and generation == version then refresh() end
			end)
		end
	end

	local ids = {}
	for id in WeaponData.Weapons do table.insert(ids, id) end
	table.sort(ids, function(a, b)
		if a == b then return false end
		if a == WeaponData.DEFAULT_WEAPON then return true end
		if b == WeaponData.DEFAULT_WEAPON then return false end
		return a < b
	end)
	for order, id in ids do
		local w = WeaponData.Weapons[id]
		local row = button(list,"",UDim2.new(),UDim2.new(),slate)
		row.Name, row.LayoutOrder, row.ClipsDescendants = id,order,true
		local art = Instance.new("UIGradient")
		art.Color = ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(105,113,133))
		art.Rotation, art.Parent = 65,row
		Preview.draw(row,id)
		local caption = frame(row,UDim2.new(0,0,1,-72),UDim2.new(1,0,0,72),ink)
		frame(caption,UDim2.new(),UDim2.new(1,0,0,1),edge)
		local title = label(caption,w.DisplayName,UDim2.fromOffset(9,2),UDim2.new(1,-18,0,41),Enum.Font.Antique,20,ivory)
		title.TextWrapped = true
		local state = label(caption,"",UDim2.fromOffset(9,44),UDim2.new(1,-18,0,24),Enum.Font.GothamMedium,14,gold)
		rows[id] = {button=row,state=state,border=stroke(row,edge)}
		row.Activated:Connect(function()
			if not owned or player:GetAttribute("InDuel") == true then return end
			if owned[id] then
				Remotes.GetEvent("EquipWeapon"):FireServer(id)
				return
			end
			local ok, bought, reason = pcall(function()
				return Remotes.GetFunction("PurchaseWeapon"):InvokeServer(id)
			end)
			if ok and not bought and w.Acquisition == "GamePass" and reason == "Se necesita el pase de esta arma." and w.GamePassId then
				Marketplace:PromptGamePassPurchase(player, w.GamePassId)
			else
				notify(if ok then reason else "No se pudo consultar la tienda.")
			end
			refresh()
		end)
	end
	Marketplace.PromptGamePassPurchaseFinished:Connect(function(buyer, passId, purchased)
		if buyer ~= player or not purchased then return end
		for _, id in ids do
			if WeaponData.Weapons[id].GamePassId == passId then
				local ok, _, reason = pcall(function() return Remotes.GetFunction("PurchaseWeapon"):InvokeServer(id) end)
				notify(if ok then reason else "Volvé a consultar el pase en la tienda.")
				refresh()
				return
			end
		end
	end)
	local function show(open: boolean)
		panel.Visible, shade.Visible = open, open
		toggle.Visible = not open
		if hudGold.Parent and hudGold.Parent:IsA("GuiObject") then hudGold.Parent.Visible = not open end
		if open then
			resize()
			render()
			refresh()
		end
	end
	toggle.Activated:Connect(function() show(true) end)
	close.Activated:Connect(function() show(false) end)
	shade.Activated:Connect(function() show(false) end)
	local function filter(onlyOwned: boolean)
		inventoryOnly = onlyOwned
		list.CanvasPosition = Vector2.zero
		render()
	end
	all.Activated:Connect(function() filter(false) end)
	mine.Activated:Connect(function() filter(true) end)
	for _, attr in {"Gold", "EquippedWeapon", "InDuel"} do player:GetAttributeChangedSignal(attr):Connect(render) end
	Remotes.GetEvent("Notify").OnClientEvent:Connect(function(text)
		if typeof(text) == "string" then notify(text) end
		if panel.Visible then refresh() end
	end)
	render()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return UIController
