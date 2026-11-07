--!strict
--[[
	ArmorController — Ventana de la armería (cliente).
	Owner: Dev B (Economía).

	Se abre desde el puesto del lobby (ProximityPrompt con OpenArmorShop = true, lo arma LobbyService).
	Muestra los 3 sets en filas (Casco, Pechera, Pantalón) con un maniquí que lleva la pieza,
	sus bonos y un botón Comprar / Equipar / Quitar. Todo pasa por el remote "ArmorShop" (ArmorService).
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArmorData = require(Shared:WaitForChild("ArmorData"))
local ArmorArt = require(Shared:WaitForChild("ArmorArt"))
local Sounds = require(script.Parent:WaitForChild("Util"):WaitForChild("Sounds"))
local ArmorController = {}

local INK = Color3.fromRGB(15, 19, 26)
local SLATE = Color3.fromRGB(30, 36, 45)
local GOLD = Color3.fromRGB(237, 197, 118)
local IVORY = Color3.fromRGB(246, 237, 216)
local MUTED = Color3.fromRGB(170, 178, 186)
local EDGE = Color3.fromRGB(71, 76, 82)
local STEEL_BLUE = Color3.fromRGB(120, 160, 230)
local SET_COLORS: { [string]: Color3 } = {
	Leather = Color3.fromRGB(196, 150, 100),
	Steel = Color3.fromRGB(190, 200, 215),
	Ember = Color3.fromRGB(255, 130, 60),
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
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

local function stroke(obj: GuiObject, color: Color3)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode, s.Color, s.Parent = Enum.ApplyStrokeMode.Border, color, obj
end

-- Maniquí gris con partes R15 (los mismos nombres que usa ArmorArt).
local MANNEQUIN: { [string]: { Vector3 } } = {
	Head = { Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0) },
	UpperTorso = { Vector3.new(2, 1.6, 1), Vector3.new(0, 3.2, 0) },
	LowerTorso = { Vector3.new(2, 0.4, 1), Vector3.new(0, 2.2, 0) },
	LeftUpperArm = { Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 3.4, 0) },
	RightUpperArm = { Vector3.new(1, 1.2, 1), Vector3.new(1.5, 3.4, 0) },
	LeftLowerArm = { Vector3.new(1, 1.1, 1), Vector3.new(-1.5, 2.25, 0) },
	RightLowerArm = { Vector3.new(1, 1.1, 1), Vector3.new(1.5, 2.25, 0) },
	LeftUpperLeg = { Vector3.new(1, 1.2, 1), Vector3.new(-0.5, 1.4, 0) },
	RightUpperLeg = { Vector3.new(1, 1.2, 1), Vector3.new(0.5, 1.4, 0) },
	LeftLowerLeg = { Vector3.new(1, 1.1, 1), Vector3.new(-0.5, 0.25, 0) },
	RightLowerLeg = { Vector3.new(1, 1.1, 1), Vector3.new(0.5, 0.25, 0) },
	LeftFoot = { Vector3.new(1, 0.3, 1), Vector3.new(-0.5, -0.45, 0) },
	RightFoot = { Vector3.new(1, 0.3, 1), Vector3.new(0.5, -0.45, 0) },
}

local function preview(parent: GuiObject, pieceId: string, slot: string)
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.new(1, -8, 1, -76)
	view.Position = UDim2.fromOffset(4, 4)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(150, 150, 160)
	view.LightColor = Color3.fromRGB(255, 240, 220)
	view.LightDirection = Vector3.new(-0.5, -0.8, 0.6)
	view.Parent = parent
	local body = Instance.new("Model")
	for name, spec in MANNEQUIN do
		local p = Instance.new("Part")
		p.Name, p.Size, p.Anchored = name, spec[1], true
		p.CFrame = CFrame.new(spec[2])
		p.Color, p.Material = Color3.fromRGB(96, 100, 108), Enum.Material.SmoothPlastic
		p.Parent = body
	end
	body.Parent = view
	local armor = ArmorArt.Build(pieceId, slot, body)
	for _, d in armor:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true elseif d:IsA("Weld") or d:IsA("Light") then d:Destroy() end
	end
	armor.Parent = view
	-- Encuadre de 3/4 sobre la pieza.
	local box, size = armor:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.62
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = radius / math.tan(math.rad(20)) + 0.5
	local dir = Vector3.new(math.sin(math.rad(-28)), 0.25, -math.cos(math.rad(28))).Unit
	camera.CFrame = CFrame.lookAt(box.Position + dir * distance, box.Position)
	view.CurrentCamera = camera
	camera.Parent = view
end

type Card = { piece: ArmorData.ArmorPiece, action: TextButton, border: UIStroke }

function ArmorController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn = "Armeria", false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local shade = Instance.new("TextButton")
	shade.Text, shade.AutoButtonColor = "", false
	shade.Size, shade.BackgroundColor3, shade.BackgroundTransparency = UDim2.fromScale(1, 1), Color3.new(), 0.3
	shade.Parent = gui
	local panel = frame(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.94, 0.9), INK)
	panel.AnchorPoint, panel.Active = Vector2.new(0.5, 0.5), true
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize, limit.Parent = Vector2.new(820, 560), panel
	stroke(panel, EDGE)
	frame(panel, UDim2.new(), UDim2.new(1, 0, 0, 2), STEEL_BLUE)
	text(panel, "Armería", UDim2.fromOffset(18, 8), UDim2.new(0.5, 0, 0, 44), Enum.Font.Antique, 34, IVORY)
	local totals = text(panel, "", UDim2.fromOffset(18, 52), UDim2.new(1, -36, 0, 20), Enum.Font.GothamMedium, 14, MUTED)
	totals.RichText = true
	local goldLabel = text(panel, "", UDim2.new(1, -190, 0, 18), UDim2.fromOffset(130, 30), Enum.Font.GothamBold, 18, GOLD)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right
	local close = Instance.new("TextButton")
	close.Text, close.TextSize, close.Font, close.TextColor3 = "×", 26, Enum.Font.GothamBold, IVORY
	close.Position, close.Size = UDim2.new(1, -52, 0, 12), UDim2.fromOffset(40, 40)
	close.BackgroundColor3, close.BorderSizePixel = Color3.fromRGB(66, 35, 42), 0
	close.Parent = panel
	local message = text(panel, "", UDim2.new(0, 18, 1, -30), UDim2.new(1, -36, 0, 22), Enum.Font.GothamMedium, 14, MUTED)
	message.TextXAlignment = Enum.TextXAlignment.Center

	local list = Instance.new("ScrollingFrame")
	list.Position, list.Size = UDim2.fromOffset(16, 80), UDim2.new(1, -32, 1, -116)
	list.BackgroundTransparency, list.BorderSizePixel = 1, 0
	list.ScrollBarThickness, list.ScrollBarImageColor3 = 3, GOLD
	list.AutomaticCanvasSize, list.CanvasSize = Enum.AutomaticSize.Y, UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder, layout.Padding = Enum.SortOrder.LayoutOrder, UDim.new(0, 10)
	layout.Parent = list

	local cards: { Card } = {}
	local owned: { [string]: boolean } = {}
	local equipped: { [string]: string } = {}

	local function render()
		local value = player:GetAttribute("Gold")
		goldLabel.Text = if typeof(value) == "number" then `{value} oro` else ""
		local health, armor = ArmorData.Totals(equipped)
		totals.Text = `Vida máxima <b><font color="#78D278">{ArmorData.BASE_HEALTH + health}</font></b>   ·   `
			.. `Armadura <b><font color="#7AA8E6">{math.round(armor * 100)}%</font></b> (reduce el daño recibido)`
		for _, card in cards do
			local p = card.piece
			local isOn = equipped[p.Slot] == p.Id
			if isOn then
				card.action.Text = "✓ Puesta · Quitar"
				card.action.BackgroundColor3 = Color3.fromRGB(44, 86, 60)
			elseif owned[p.Id] then
				card.action.Text = "Equipar"
				card.action.BackgroundColor3 = Color3.fromRGB(46, 64, 100)
			else
				card.action.Text = `Comprar · {p.Price} oro`
				card.action.BackgroundColor3 = Color3.fromRGB(92, 68, 28)
			end
			card.border.Color = if isOn then GOLD else EDGE
		end
	end

	local busy = false
	local function call(action: string, id: string?)
		if busy then return end
		busy = true
		local ok, success, msg, current = pcall(function()
			return Remotes.GetFunction("ArmorShop"):InvokeServer(action, id)
		end)
		busy = false
		if ok and typeof(current) == "table" then
			owned = if typeof(current.owned) == "table" then current.owned else {}
			equipped = if typeof(current.equipped) == "table" then current.equipped else {}
		end
		if action ~= "Get" then
			message.Text = if ok and typeof(msg) == "string" then msg else "No se pudo conectar con la armería."
			message.TextColor3 = if ok and success then Color3.fromRGB(120, 220, 120) else Color3.fromRGB(235, 110, 100)
			if ok and success and action == "Buy" then Sounds.Play("Compra") end
		end
		render()
	end

	-- Una fila por set, con sus tres piezas en orden Casco / Pechera / Pantalón.
	for setIndex, set in ArmorData.SETS do
		local row = frame(list, UDim2.new(), UDim2.new(1, -6, 0, 268), SLATE)
		row.BackgroundTransparency, row.LayoutOrder = 0.4, setIndex
		text(row, set.Name, UDim2.fromOffset(12, 4), UDim2.new(1, -24, 0, 26), Enum.Font.Antique, 22, SET_COLORS[set.Id] or IVORY)
		local cardsHolder = frame(row, UDim2.fromOffset(8, 34), UDim2.new(1, -16, 1, -42), SLATE)
		cardsHolder.BackgroundTransparency = 1
		local grid = Instance.new("UIGridLayout")
		grid.CellSize, grid.CellPadding = UDim2.new(1 / 3, -6, 1, 0), UDim2.fromOffset(8, 0)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = cardsHolder
		for slotIndex, slot in ArmorData.SLOTS do
			local piece: ArmorData.ArmorPiece? = nil
			for _, p in ArmorData.Pieces do
				if p.Set == set.Id and p.Slot == slot then piece = p end
			end
			if not piece then continue end
			local p = piece :: ArmorData.ArmorPiece
			local card = frame(cardsHolder, UDim2.new(), UDim2.new(), INK)
			card.LayoutOrder, card.ClipsDescendants = slotIndex, true
			local border = Instance.new("UIStroke")
			border.ApplyStrokeMode, border.Color, border.Parent = Enum.ApplyStrokeMode.Border, EDGE, card
			preview(card, p.Id, p.Slot)
			text(card, p.DisplayName, UDim2.new(0, 8, 1, -72), UDim2.new(1, -16, 0, 20), Enum.Font.GothamBold, 15, IVORY)
			local info = text(card, `{ArmorData.SLOT_NAMES[p.Slot]} · <font color="#78D278">+{p.Health} HP</font> · <font color="#7AA8E6">+{math.round(p.Armor * 100)}%</font>`,
				UDim2.new(0, 8, 1, -52), UDim2.new(1, -16, 0, 16), Enum.Font.Gotham, 13, MUTED)
			info.RichText = true
			local action = Instance.new("TextButton")
			action.Position, action.Size = UDim2.new(0, 6, 1, -32), UDim2.new(1, -12, 0, 26)
			action.Font, action.TextSize, action.TextColor3 = Enum.Font.GothamBold, 13, IVORY
			action.BorderSizePixel = 0
			action.Parent = card
			table.insert(cards, { piece = p, action = action, border = border })
			action.Activated:Connect(function()
				if equipped[p.Slot] == p.Id then
					call("Unequip", p.Id)
				elseif owned[p.Id] then
					call("Equip", p.Id)
				else
					call("Buy", p.Id)
				end
			end)
		end
	end

	local function show(open: boolean)
		gui.Enabled = open
		if open then
			message.Text = ""
			Sounds.Play("Tienda")
			call("Get")
		end
	end
	close.Activated:Connect(function() show(false) end)
	shade.Activated:Connect(function() show(false) end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("OpenArmorShop") == true then show(true) end
	end)
	player:GetAttributeChangedSignal("Gold"):Connect(function()
		if gui.Enabled then render() end
	end)
	render()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return ArmorController
