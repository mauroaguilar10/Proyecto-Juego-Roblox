--!strict
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local Marketplace = game:GetService("MarketplaceService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript)
local WeaponData = require(Shared:WaitForChild("WeaponData") :: ModuleScript)
local Preview = require(script.Parent:WaitForChild("Util"):WaitForChild("WeaponPreview"))
local Sounds = require(script.Parent:WaitForChild("Util"):WaitForChild("Sounds"))
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
-- ── Estadísticas de armas (tienda) ──
local CAPTION = 112 -- alto del pie de cada tarjeta: nombre, estadísticas y acción
local BETTER = "#78D278"
local WORSE = "#E66E64"

local function fmt(value: number, decimals: number): string
	local text = string.format(`%.{decimals}f`, value):gsub("%.", ",")
	return text
end

-- "+8" en verde si es mejor, "−2" en rojo si es peor, nada si es igual.
local function delta(diff: number, decimals: number): string
	if math.abs(diff) < 0.5 * 10 ^ -decimals then return "" end
	local sign = if diff > 0 then "+" else "−"
	return `  <font color="{if diff > 0 then BETTER else WORSE}">{sign}{fmt(math.abs(diff), decimals)}</font>`
end

local function currentWeapon(): WeaponData.WeaponStats
	local equipped = Players.LocalPlayer:GetAttribute("EquippedWeapon")
	return WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil)
end

-- Daño, velocidad (golpes por segundo) y alcance; si `compare` existe, la diferencia contra esa arma.
local function statsText(w: WeaponData.WeaponStats, compare: WeaponData.WeaponStats?): string
	local speed = 1 / w.AttackCooldown
	local lines = {
		{ "Daño", fmt(w.Damage, 0), if compare then delta(w.Damage - compare.Damage, 0) else "" },
		{ "Velocidad", fmt(speed, 2) .. " golpes/s", if compare then delta(speed - 1 / compare.AttackCooldown, 2) else "" },
		{ "Alcance", fmt(w.Range, 0) .. " studs", if compare then delta(w.Range - compare.Range, 0) else "" },
	}
	local out = {}
	for _, line in lines do
		table.insert(out, `{line[1]} <b>{line[2]}</b>{line[3]}`)
	end
	return table.concat(out, "\n")
end

-- ── Iluminación de la mazmorra ──
-- Solo en este cliente: al entrar a la sala la luz general baja y queda la de las antorchas;
-- al salir se restaura lo que había.
local DUNGEON_LIGHT: { [string]: any } = {
	Ambient = Color3.fromRGB(26, 24, 32),
	OutdoorAmbient = Color3.fromRGB(30, 28, 38),
	Brightness = 0.35,
	ExposureCompensation = -0.25,
}
local savedLight: { [string]: any }? = nil
local function setDungeonLighting(on: boolean)
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Sine)
	local tint = Lighting:FindFirstChild("TonoMazmorra")
	if on ~= (savedLight ~= nil) then Sounds.Ambient(on) end
	if on and not savedLight then
		local saved = {}
		for property in DUNGEON_LIGHT do
			saved[property] = (Lighting :: any)[property]
		end
		savedLight = saved
		TweenService:Create(Lighting, info, DUNGEON_LIGHT):Play()
		if not tint then
			local effect = Instance.new("ColorCorrectionEffect")
			effect.Name = "TonoMazmorra"
			effect.TintColor = Color3.fromRGB(255, 226, 200)
			effect.Saturation, effect.Contrast = -0.15, 0.1
			effect.Parent = Lighting
		end
	elseif not on and savedLight then
		TweenService:Create(Lighting, info, savedLight):Play()
		savedLight = nil
		if tint then tint:Destroy() end
	end
end

-- ── Mensajes flotantes en la mazmorra ──
-- Mientras el jugador está en su sala, los avisos (Notify) no van al cartel de abajo: aparecen
-- como un texto grande sobre su personaje (lo sigue, siempre de frente y del mismo tamaño en
-- pantalla) durante FLOAT_TIME segundos, con colores según el tipo de mensaje.
local FLOAT_TIME = 1.5
local insideDungeon = false
local floatToken = 0

local function messageColors(text: string): ColorSequence
	local lower = text:lower()
	if lower:find("jefe") then
		return ColorSequence.new(Color3.fromRGB(215, 120, 255), Color3.fromRGB(255, 70, 90))
	elseif lower:find("superada") or lower:find("récord") then
		return ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(110, 255, 140))
	elseif lower:find("oleada") then
		return ColorSequence.new(Color3.fromRGB(255, 200, 70), Color3.fromRGB(255, 80, 50))
	end
	return ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 180, 60))
end

local function floatingMessage(text: string)
	local char = Players.LocalPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then return end
	floatToken += 1
	local token = floatToken
	local old = root:FindFirstChild("AvisoFlotante")
	if old then old:Destroy() end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AvisoFlotante"
	billboard.Size = UDim2.fromOffset(560, 96) -- en píxeles: legible a cualquier distancia de cámara
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = math.huge
	local pop = Instance.new("UIScale")
	pop.Scale = 0.4
	pop.Parent = billboard
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBlack
	textLabel.TextScaled = true
	textLabel.TextWrapped = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.Text = text
	textLabel.Parent = billboard
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 40
	limit.Parent = textLabel
	local outline = Instance.new("UIStroke")
	outline.Color, outline.Thickness = Color3.fromRGB(30, 10, 10), 3
	outline.Parent = textLabel
	local gradient = Instance.new("UIGradient")
	gradient.Color = messageColors(text)
	gradient.Rotation = 90
	gradient.Parent = textLabel
	billboard.Parent = root

	TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(billboard, TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 5.5, 0) }):Play()
	local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, FLOAT_TIME - 0.35)
	TweenService:Create(textLabel, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(outline, fade, { Transparency = 1 }):Play()
	task.delay(FLOAT_TIME, function()
		if floatToken == token then billboard:Destroy() end
	end)
end

-- ── Panel de la mazmorra ──
-- Lee los Attributes que publica DungeonService en workspace.Mazmorra y se muestra
-- solo mientras el jugador está dentro de la sala.
local function dungeonPanel(gui: ScreenGui)
	local box = frame(gui, UDim2.new(0.5, 0, 0, 10), UDim2.fromOffset(240, 62), ink)
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.BackgroundTransparency = 0.1
	box.Visible = false
	stroke(box, gold)
	frame(box, UDim2.new(), UDim2.new(1, 0, 0, 2), gold)
	local title = label(box, "", UDim2.fromOffset(0, 6), UDim2.new(1, 0, 0, 28), Enum.Font.Antique, 24, ivory)
	local detail = label(box, "", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 0, 20), Enum.Font.GothamMedium, 14, gold)
	title.TextXAlignment, detail.TextXAlignment = Enum.TextXAlignment.Center, Enum.TextXAlignment.Center

	-- Botón rojo "Exit" (debajo del panel de la oleada): el primer toque pide confirmación
	-- ("Sure?") y el segundo, dentro de CONFIRM_TIME, te saca de la mazmorra (remote LeaveDungeon).
	local CONFIRM_TIME = 3
	local exit = button(gui, "Exit", UDim2.new(0.5, 0, 0, 80), UDim2.fromOffset(122, 40), Color3.fromRGB(150, 30, 34))
	exit.Name = "SalirMazmorra"
	exit.AnchorPoint = Vector2.new(0.5, 0)
	exit.TextSize = 20
	exit.Visible = false
	stroke(exit, Color3.fromRGB(235, 96, 90))
	local armedAt: number? = nil
	local leavingUntil = 0 -- tras confirmar, no volver a mostrarlo mientras llega el teletransporte
	local function disarm()
		armedAt = nil
		exit.Text = "Exit"
		exit.BackgroundColor3 = Color3.fromRGB(150, 30, 34)
	end
	exit.Activated:Connect(function()
		local now = os.clock()
		if armedAt and now - armedAt <= CONFIRM_TIME then
			disarm()
			exit.Visible = false
			leavingUntil = now + 2
			Remotes.GetEvent("LeaveDungeon"):FireServer()
			return
		end
		armedAt = now
		exit.Text = "Sure?"
		exit.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
		task.delay(CONFIRM_TIME, function()
			if armedAt == now then disarm() end
		end)
	end)

	task.spawn(function()
		local mazmorra = workspace:WaitForChild("Mazmorra")
		local player = Players.LocalPlayer
		local roomName = `Sala_{player.UserId}` -- cada jugador tiene su propia sala (DungeonService)
		while true do
			local dungeon = mazmorra:FindFirstChild(roomName)
			local center = if dungeon then dungeon:GetAttribute("Center") else nil
			local size = if dungeon then dungeon:GetAttribute("Size") else nil
			local char = player.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
			local inside = false
			if dungeon and typeof(center) == "Vector3" and typeof(size) == "number" and root and root:IsA("BasePart") then
				local offset = root.Position - center
				inside = math.abs(offset.X) <= size / 2 and math.abs(offset.Z) <= size / 2 and offset.Y > -5 and offset.Y < 25
			end
			box.Visible = inside
			insideDungeon = inside
			local showExit = inside and os.clock() >= leavingUntil
			if exit.Visible ~= showExit then
				exit.Visible = showExit
				disarm()
			end
			setDungeonLighting(inside)
			if inside and dungeon then
				local wave = dungeon:GetAttribute("Wave")
				local left = dungeon:GetAttribute("EnemiesLeft")
				local nextAt = dungeon:GetAttribute("NextWaveAt")
				local remaining = if typeof(nextAt) == "number" and nextAt > 0 then nextAt - workspace:GetServerTimeNow() else 0
				if remaining > 0 then
					title.Text = `Oleada {(if typeof(wave) == "number" then wave else 0) + 1}`
					detail.Text = `Empieza en {math.ceil(remaining)}…`
				else
					title.Text = `Oleada {if typeof(wave) == "number" then wave else "—"}`
					local count = if typeof(left) == "number" then left else 0
					detail.Text = if count == 1 then "Queda 1 guardián" else `Quedan {count} guardianes`
				end
			end
			task.wait(0.2)
		end
	end)
end

function UIController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn = "EconomyHUD", false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local hudGold = balance(gui, UDim2.new(1,-14,0,10))
	dungeonPanel(gui)
	-- La tienda ya no tiene botón en el HUD: se abre desde su puesto del lobby (OpenShop).
	local shopOpen = false
	-- Botón del Void Pass, arriba a la derecha debajo de "Códigos". Se oculta cuando ya lo tenés (Player.VoidPass).
	local violet = Color3.fromRGB(176, 120, 255)
	local passButton = button(gui, "", UDim2.new(1,-14,0,88), UDim2.fromOffset(176,48), Color3.fromRGB(34,20,52))
	passButton.Name = "PaseDelVacio"
	passButton.AnchorPoint = Vector2.new(1,0)
	stroke(passButton, violet)
	label(passButton,"★ Void Pass",UDim2.fromOffset(12,4),UDim2.new(1,-16,0,22),Enum.Font.GothamBold,16,violet)
	label(passButton,"Guadaña del Vacío · Oro x2",UDim2.fromOffset(12,25),UDim2.new(1,-16,0,18),Enum.Font.Gotham,12,ivory)
	local function updatePassButton()
		passButton.Visible = not shopOpen and player:GetAttribute("VoidPass") ~= true
	end
	player:GetAttributeChangedSignal("VoidPass"):Connect(updatePassButton)
	updatePassButton()

	-- ── Canje de códigos (CodeService) ──
	local codesButton = button(gui, "🎟  Códigos", UDim2.new(1,-14,0,50), UDim2.fromOffset(109,30), ink)
	codesButton.Name = "Codigos"
	codesButton.AnchorPoint = Vector2.new(1,0)
	codesButton.TextSize = 14
	stroke(codesButton, gold)
	local codesPanel = frame(gui, UDim2.fromScale(0.5,0.5), UDim2.fromOffset(340,190), ink)
	codesPanel.AnchorPoint = Vector2.new(0.5,0.5)
	codesPanel.Active, codesPanel.Visible, codesPanel.ZIndex = true, false, 8
	stroke(codesPanel, gold)
	frame(codesPanel, UDim2.new(), UDim2.new(1,0,0,2), gold).ZIndex = 8
	label(codesPanel,"Canjear código",UDim2.fromOffset(16,10),UDim2.new(1,-70,0,34),Enum.Font.Antique,26,ivory)
	local codesClose = button(codesPanel,"×",UDim2.new(1,-46,0,10),UDim2.fromOffset(34,34),Color3.fromRGB(66,35,42))
	codesClose.TextSize = 24
	local codeBox = Instance.new("TextBox")
	codeBox.Position, codeBox.Size = UDim2.fromOffset(16,56), UDim2.new(1,-32,0,40)
	codeBox.BackgroundColor3, codeBox.BorderSizePixel = slate, 0
	codeBox.Font, codeBox.TextSize, codeBox.TextColor3 = Enum.Font.GothamBold, 18, ivory
	codeBox.PlaceholderText, codeBox.PlaceholderColor3 = "Escribí tu código", muted
	codeBox.Text, codeBox.ClearTextOnFocus = "", false
	codeBox.Parent = codesPanel
	stroke(codeBox, edge)
	local redeemButton = button(codesPanel,"Canjear",UDim2.fromOffset(16,106),UDim2.new(1,-32,0,38),Color3.fromRGB(92,68,28))
	stroke(redeemButton, gold)
	local codeResult = label(codesPanel,"",UDim2.fromOffset(16,150),UDim2.new(1,-32,0,32),Enum.Font.GothamMedium,13,muted)
	codeResult.TextWrapped, codeResult.TextXAlignment = true, Enum.TextXAlignment.Center
	for _, d in codesPanel:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = 9 end
	end

	local redeeming = false
	local function submitCode()
		if redeeming then return end
		local text = codeBox.Text
		if text:gsub("%s", "") == "" then
			codeResult.Text, codeResult.TextColor3 = "Escribí un código.", muted
			return
		end
		redeeming = true
		redeemButton.Text = "Canjeando…"
		local ok, success, message = pcall(function()
			return Remotes.GetFunction("RedeemCode"):InvokeServer(text)
		end)
		redeeming = false
		redeemButton.Text = "Canjear"
		local good = ok and success == true
		codeResult.Text = if ok and typeof(message) == "string" then message else "No se pudo canjear el código."
		codeResult.TextColor3 = if good then Color3.fromRGB(120, 220, 120) else Color3.fromRGB(235, 110, 100)
		if good then
			codeBox.Text = ""
			Sounds.Play("Compra")
		end
	end
	local function showCodes(open: boolean)
		codesPanel.Visible = open
		if open then
			codeResult.Text = ""
			codeBox:CaptureFocus()
		end
	end
	codesButton.Activated:Connect(function() showCodes(not codesPanel.Visible) end)
	codesClose.Activated:Connect(function() showCodes(false) end)
	redeemButton.Activated:Connect(submitCode)
	codeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then submitCode() end
	end)
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
		grid.CellSize = UDim2.fromOffset(cell,math.clamp(cell+CAPTION-27,229,325))
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
		-- En la mazmorra el aviso sale flotando sobre el personaje en vez de en el cartel de abajo.
		local mazmorra = workspace:FindFirstChild("Mazmorra")
		local hasRoom = mazmorra ~= nil and mazmorra:FindFirstChild(`Sala_{player.UserId}`) ~= nil
		if (insideDungeon or hasRoom) and not panel.Visible then
			message.Visible = false
			floatingMessage(text)
			return
		end
		messageId += 1
		local current = messageId
		message.Text, message.Visible = text, true
		task.delay(5, function()
			if current == messageId then message.Visible = false end
		end)
	end

	local owned: {[string]: boolean}? = nil
	local inventoryOnly = false
	type Card = {button: TextButton, state: TextLabel, stats: TextLabel, border: UIStroke}
	local rows: {[string]: Card} = {}
	-- Contador de oro animado: sube de a poco hasta el valor nuevo y el recuadro "late" al ganar.
	local goldBox = hudGold.Parent :: GuiObject
	local goldPop = Instance.new("UIScale")
	goldPop.Parent = goldBox
	local goldShown = Instance.new("NumberValue")
	local goldTarget: number? = nil
	local function writeGold(value: number)
		local text = tostring(math.floor(value + 0.5))
		hudGold.Text, shopGold.Text = text, text
	end
	goldShown.Changed:Connect(writeGold)
	local function updateGold()
		local value = player:GetAttribute("Gold")
		if typeof(value) ~= "number" then
			hudGold.Text, shopGold.Text = "…", "…"
			return
		end
		if goldTarget == nil then
			goldTarget = value
			goldShown.Value = value
			writeGold(value)
			return
		end
		if value == goldTarget then return end
		local gained = value > (goldTarget :: number)
		goldTarget = value
		TweenService:Create(goldShown, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = value }):Play()
		if gained then
			goldPop.Scale = 1.18
			TweenService:Create(goldPop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	-- "+N" flotando donde murió el guardián y monedas que vuelan hasta el contador.
	local function goldBurst(amount: number, position: Vector3)
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = position
		anchor.Parent = workspace.Terrain
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(140, 44)
		billboard.AlwaysOnTop, billboard.LightInfluence = true, 0
		billboard.Parent = anchor
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextSize = 30
		text.TextColor3 = gold
		text.TextStrokeColor3, text.TextStrokeTransparency = Color3.fromRGB(70, 45, 10), 0.2
		text.Text = `+{amount}`
		text.Parent = billboard
		local rise = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(billboard, rise, { StudsOffsetWorldSpace = Vector3.new(0, 3, 0) }):Play()
		TweenService:Create(text, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(anchor, 1.2)
		Sounds.Play("Moneda", 0.95 + math.random() * 0.13)

		local camera = workspace.CurrentCamera
		if not camera or not goldBox.Visible then return end
		local screen, onScreen = camera:WorldToScreenPoint(position)
		if not onScreen then return end
		local target = goldBox.AbsolutePosition + Vector2.new(22, goldBox.AbsoluteSize.Y / 2)
		for i = 1, math.clamp(2 + math.floor(amount / 25), 3, 8) do
			local coin = frame(gui, UDim2.fromOffset(screen.X, screen.Y), UDim2.fromOffset(16, 16), gold)
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.ZIndex = 6
			Instance.new("UICorner", coin).CornerRadius = UDim.new(1, 0)
			stroke(coin, Color3.fromRGB(150, 100, 30))
			local angle = math.random() * math.pi * 2
			local spread = Vector2.new(math.cos(angle), math.sin(angle)) * math.random(30, 70)
			local burst = TweenService:Create(coin, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(screen.X + spread.X, screen.Y + spread.Y) })
			burst:Play()
			burst.Completed:Once(function()
				task.wait(0.05 * i)
				local fly = TweenService:Create(coin, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(10, 10) })
				fly:Play()
				fly.Completed:Once(function() coin:Destroy() end)
			end)
		end
	end

	local function render()
		updateGold()
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
			card.stats.Text = statsText(w, if equipped then nil else currentWeapon())
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
	-- Orden: el arma inicial, después las de oro de la más barata a la más cara, y al final las de pase.
	table.sort(ids, function(a, b)
		if a == b then return false end
		if a == WeaponData.DEFAULT_WEAPON then return true end
		if b == WeaponData.DEFAULT_WEAPON then return false end
		local wa, wb = WeaponData.Weapons[a], WeaponData.Weapons[b]
		local pa, pb = wa.Acquisition == "GamePass", wb.Acquisition == "GamePass"
		if pa ~= pb then return pb end
		if wa.Price ~= wb.Price then return wa.Price < wb.Price end
		return a < b
	end)
	for order, id in ids do
		local w = WeaponData.Weapons[id]
		local row = button(list,"",UDim2.new(),UDim2.new(),slate)
		row.Name, row.LayoutOrder, row.ClipsDescendants = id,order,true
		local art = Instance.new("UIGradient")
		art.Color = ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(105,113,133))
		art.Rotation, art.Parent = 65,row
		Preview.draw(row,id,CAPTION)
		local caption = frame(row,UDim2.new(0,0,1,-CAPTION),UDim2.new(1,0,0,CAPTION),ink)
		frame(caption,UDim2.new(),UDim2.new(1,0,0,1),edge)
		local title = label(caption,w.DisplayName,UDim2.fromOffset(9,2),UDim2.new(1,-18,0,34),Enum.Font.Antique,20,ivory)
		title.TextWrapped = true
		local stats = label(caption,"",UDim2.fromOffset(9,36),UDim2.new(1,-18,0,48),Enum.Font.Gotham,13,muted)
		stats.RichText, stats.TextYAlignment = true, Enum.TextYAlignment.Top
		local state = label(caption,"",UDim2.fromOffset(9,CAPTION-28),UDim2.new(1,-18,0,24),Enum.Font.GothamMedium,14,gold)
		rows[id] = {button=row,state=state,stats=stats,border=stroke(row,edge)}
		row.Activated:Connect(function()
			if not owned or player:GetAttribute("InDuel") == true then return end
			if owned[id] then
				Remotes.GetEvent("EquipWeapon"):FireServer(id)
				return
			end
			local ok, bought, reason = pcall(function()
				return Remotes.GetFunction("PurchaseWeapon"):InvokeServer(id)
			end)
			if ok and bought then Sounds.Play("Compra") end
			if ok and not bought and w.Acquisition == "GamePass" and reason == "Se necesita el pase de esta arma." and w.GamePassId then
				Marketplace:PromptGamePassPurchase(player, w.GamePassId)
			else
				notify(if ok then reason else "No se pudo consultar la tienda.")
			end
			refresh()
		end)
	end
	-- El servidor activa el pase y equipa el arma (ShopService) y avisa por Notify; acá solo se actualiza.
	Marketplace.PromptGamePassPurchaseFinished:Connect(function(buyer, _, purchased)
		if buyer ~= player or not purchased then return end
		Sounds.Play("Compra")
		task.delay(1, refresh)
	end)
	local function show(open: boolean)
		panel.Visible, shade.Visible = open, open
		shopOpen = open
		updatePassButton()
		codesButton.Visible = not open
		if open then codesPanel.Visible = false end
		if hudGold.Parent and hudGold.Parent:IsA("GuiObject") then hudGold.Parent.Visible = not open end
		if open then
			Sounds.Play("Tienda")
			resize()
			render()
			refresh()
		end
	end
	passButton.Activated:Connect(function()
		local passId = WeaponData.Weapons.VoidScythe.GamePassId
		if not passId or passId <= 0 then
			notify("El Void Pass todavía no está a la venta.")
			return
		end
		Marketplace:PromptGamePassPurchase(player, passId)
	end)
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
	-- "Notify" trae texto, o una tabla {Kind = "Gold", Amount, Position} cuando un guardián da oro.
	Remotes.GetEvent("Notify").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "string" then
			notify(payload)
		elseif typeof(payload) == "table" and payload.Kind == "Gold"
			and typeof(payload.Amount) == "number" and typeof(payload.Position) == "Vector3" then
			goldBurst(payload.Amount, payload.Position)
		end
		if panel.Visible then refresh() end
	end)
	-- Mostrador de la tienda en el lobby (LobbyService): su ProximityPrompt tiene OpenShop = true.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("OpenShop") == true then show(true) end
	end)
	render()
	Sounds.Preload()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return UIController
