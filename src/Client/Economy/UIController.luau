--!strict
local Players = game:GetService("Players")
local Marketplace = game:GetService("MarketplaceService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local WeaponData = require(Shared:WaitForChild("WeaponData") :: ModuleScript)
local UIController = {}

local function button(parent: Instance, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 42)
	b.BackgroundColor3 = Color3.fromRGB(44, 58, 68)
	b.TextColor3 = Color3.fromRGB(255, 244, 213)
	b.TextSize = 16
	b.Font = Enum.Font.GothamMedium
	b.Text = text
	b.Parent = parent
	return b
end

local function label(parent: Instance, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 0, height)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(255, 244, 213)
	text.TextWrapped = true
	text.TextSize = 16
	text.Font = Enum.Font.Gotham
	text.Text = ""
	text.Parent = parent
	return text
end

local function stack(parent: Instance)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = parent
end

function UIController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "EconomyHUD"
	gui.ResetOnSpawn = false
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 10)
	panel.Size = UDim2.new(0.85, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(26, 34, 40)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(315, 1000)
	limit.Parent = panel
	panel.Parent = gui
	stack(panel)
	local gold = label(panel, 32)
	gold.LayoutOrder = 1
	local toggle = button(panel, "Tienda e inventario")
	toggle.LayoutOrder = 2
	local list = Instance.new("ScrollingFrame")
	list.LayoutOrder = 3
	list.Size = UDim2.new(1, 0, 0, 142)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.BackgroundTransparency = 1
	list.ScrollBarThickness = 4
	list.Visible = false
	list.Parent = panel
	stack(list)
	local message = label(panel, 42)
	message.LayoutOrder = 4
	message.Visible = false
	local messageId = 0
	local function notify(text: string)
		messageId += 1
		local current = messageId
		message.Text = text
		message.Visible = true
		task.delay(5, function()
			if current == messageId then message.Visible = false end
		end)
	end

	local owned: {[string]: boolean}? = nil
	local rows: {[string]: TextButton} = {}
	local function render()
		local value = player:GetAttribute("Gold")
		gold.Text = if typeof(value) == "number" then "Oro: " .. tostring(value) else "Oro: …"
		for id, row in rows do
			local w = WeaponData.Weapons[id]
			local available = true
			local action: string
			if player:GetAttribute("EquippedWeapon") == id then
				action, available = "Equipada", false
			elseif player:GetAttribute("InDuel") == true then
				action, available = "En duelo", false
			elseif not owned then
				action, available = "Sin inventario", false
			elseif owned[id] then
				action = "Equipar"
			elseif w.Acquisition == "GamePass" then
				available = (w.GamePassId or 0) > 0
				action = if available then "Pase" else "Pase pendiente"
			elseif w.Acquisition == "Gold" then
				action = tostring(w.Price) .. " oro"
			else
				action = "Obtener"
			end
			row.Text = w.DisplayName .. "  ·  " .. action
			row.Interactable = available
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
		if not owned and list.Visible then
			task.delay(2, function()
				if list.Visible and generation == version then refresh() end
			end)
		end
	end

	local ids = {}
	for id in WeaponData.Weapons do table.insert(ids, id) end
	table.sort(ids)
	for order, id in ids do
		local w = WeaponData.Weapons[id]
		local row = button(list, w.DisplayName)
		row.LayoutOrder = order
		rows[id] = row
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
	toggle.Activated:Connect(function()
		list.Visible = not list.Visible
		if list.Visible then refresh() end
	end)
	for _, attr in {"Gold", "EquippedWeapon", "InDuel"} do player:GetAttributeChangedSignal(attr):Connect(render) end
	Remotes.GetEvent("Notify").OnClientEvent:Connect(function(text)
		if typeof(text) == "string" then notify(text) end
		if list.Visible then refresh() end
	end)
	render()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return UIController
