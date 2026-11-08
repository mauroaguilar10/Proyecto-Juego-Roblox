--!strict
--[[
	DuelMenuController — Menú de duelo de la arena del lobby + invitación entrante.
	Owner: Dev B (UI). Las imágenes están en Util/DuelMenuAssets (si falta un ID, hay reemplazo).

	- Al pisar la arena (DuelRules.InZone) se abre "MENÚ DE DUELO": vos vs. el rival elegido,
	  buscador de jugadores del servidor, modo Informal (1 round, sin premio) o Duelo (apuesta de
	  oro; el ganador cobra el pozo - 10 %), reloj del desafío y botón DESAFIAR.
	  Se cierra con la X (no se vuelve a abrir hasta salir y volver a entrar) o al salir de la arena.
	- "DuelInvite"(challenger, info) → tarjeta con modo, apuesta, premio, tiempo y Aceptar / Rechazar.
	- Escucha "DuelStateChanged" para mostrar el estado del desafío dentro del menú.

	Diseño: todo se posiciona en píxeles sobre el lienzo original del marco (868x558) y un UIScale
	lo achica para que entre entero en PC, tablet y celular sin tapar la barra de herramientas ni
	el cartel del arma. Sin emojis: todos los íconos son imágenes.
	Animaciones: aparece con rebote de escala (y desaparece con la inversa), el modo elegido
	pulsa, los botones crecen con el mouse y se hunden al tocarlos, el brillo del VS gira y el
	reloj se da vuelta cada segundo.
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local DuelRules = require(Shared:WaitForChild("DuelRules"))
local Assets = require(script.Parent:WaitForChild("Util"):WaitForChild("DuelMenuAssets"))

type Key = Assets.Key
type Mode = DuelRules.Mode

local localPlayer = Players.LocalPlayer

-- ── Estilo ──
local TITLE_FONT = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local BUTTON_FONT = Font.fromEnum(Enum.Font.LuckiestGuy)
local LABEL_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local INK = Color3.fromRGB(84, 50, 22)
local DARK = Color3.fromRGB(56, 30, 10)
local GOLD_TOP = Color3.fromRGB(255, 244, 180)
local GOLD_BOTTOM = Color3.fromRGB(232, 168, 46)
local GREEN = Color3.fromRGB(64, 176, 72)
local RED = Color3.fromRGB(200, 48, 38)
local PURPLE = Color3.fromRGB(150, 84, 230)
local ORANGE = Color3.fromRGB(230, 150, 30)
local GREY = Color3.fromRGB(120, 120, 126)
local PARCH = Color3.fromRGB(250, 238, 210)

local CANVAS = Vector2.new(868, 558) -- tamaño del marco: todas las posiciones son sobre esto
local PARCHMENT = Rect.new(70, 60, 800, 500) -- zona del pergamino dentro del marco
local CONTENT_PAD = 10 -- UIPadding del contenido dentro del pergamino
local OVER_TOP, OVER_BOTTOM = 58, 4 -- lo que sobresalen del marco el cartel del título y la X
local BUTTON_PAD, ICON_GAP = 14, 8
local FACE_LIFT, TEXT_DROP = 3, 3 -- ver makeButton
local MODE_ZONE_HEIGHT = 34 -- igual en los dos modos
local LIGHT_INK = Color3.fromRGB(150, 110, 72)
local BOLD_FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local BOTTOM_RESERVE = 132 -- barra de herramientas + cartel del arma
local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local DuelMenuController = {}

-- ══════════════════ Helpers ══════════════════

local function px(x: number, y: number): UDim2
	return UDim2.fromOffset(x, y)
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = if radius >= 999 then UDim.new(1, 0) else UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness = color, thickness
	s.Parent = parent
	return s
end

local function textLabel(parent: Instance, value: string, position: UDim2, size: UDim2, font: Font, maxSize: number, color: Color3, outline: Color3?, anchor: Vector2?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position, l.Size, l.AnchorPoint = position, size, anchor or Vector2.zero
	l.FontFace, l.TextColor3, l.Text = font, color, value
	l.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = l
	if outline then stroke(l, outline, 2.5) end
	l.Parent = parent
	return l
end

-- Título: Merriweather Bold con degradé dorado y contorno marrón oscuro.
local function title(parent: Instance, value: string, position: UDim2, size: UDim2, maxSize: number, anchor: Vector2?): TextLabel
	local l = textLabel(parent, value, position, size, TITLE_FONT, maxSize, Color3.new(1, 1, 1), nil, anchor)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(GOLD_TOP, GOLD_BOTTOM)
	g.Rotation = 90
	g.Parent = l
	stroke(l, DARK, 3)
	return l
end

local thumbCache: { [number]: string } = {}
local function setThumbnail(image: ImageLabel, userId: number)
	local cached = thumbCache[userId]
	if cached then
		image.Image = cached
		return
	end
	image.Image = ""
	task.spawn(function()
		local ok, url = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		if ok and typeof(url) == "string" then
			thumbCache[userId] = url
			image.Image = url
		end
	end)
end

local function goldOf(player: Player): number
	local g = player:GetAttribute("Gold")
	return if typeof(g) == "number" then g else 0
end

local function formatGold(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

-- ── Botones: holder (hover / hundirse) > ImageButton (pulso) ──
type Btn = { holder: Frame, button: ImageButton, label: TextLabel, pulse: UIScale, pulseTween: Tween?, enabled: boolean }

local function makeButton(parent: Instance, key: Key, center: UDim2, size: Vector2, text: string, textSize: number, icon: Key?): Btn
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position, holder.Size = center, UDim2.fromOffset(size.X, size.Y)
	holder.Parent = parent
	local hover = Instance.new("UIScale")
	hover.Parent = holder

	local button = Instance.new("ImageButton")
	button.Name = "Boton"
	button.AutoButtonColor = false
	button.Size = UDim2.fromScale(1, 1)
	Assets.Apply(button, key, size.Y)
	button.Parent = holder
	local pulse = Instance.new("UIScale")
	pulse.Parent = button

	-- Ícono + texto centrados como grupo ("Contenido" con UIListLayout horizontal). El grupo sube
	-- FACE_LIFT px (la cara del botón está más arriba: el borde inferior es más grueso) y el texto
	-- baja TEXT_DROP px porque LuckiestGuy dibuja las letras por encima del centro.
	local group = Instance.new("Frame")
	group.Name = "Contenido"
	group.BackgroundTransparency = 1
	group.AutomaticSize = Enum.AutomaticSize.X
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.new(0.5, 0, 0.5, -FACE_LIFT)
	group.Size = UDim2.fromOffset(0, size.Y)
	group.Parent = button
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ICON_GAP)
	layout.Parent = group
	if icon then
		local s = math.floor(size.Y * 0.6)
		Assets.Image(group, icon, px(0, 0), px(s, s)).LayoutOrder = 1
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, size.Y)
	label.FontFace, label.Text = BUTTON_FONT, text
	label.TextSize = math.min(textSize, math.floor(size.Y * 0.5))
	label.TextColor3 = Color3.new(1, 1, 1)
	label.LayoutOrder = 2
	local drop = Instance.new("UIPadding")
	drop.PaddingTop = UDim.new(0, TEXT_DROP * 2) -- centrado en lo que queda: baja TEXT_DROP px
	drop.Parent = label
	stroke(label, DARK, 2)
	label.Parent = group

	local btn: Btn = { holder = holder, button = button, label = label, pulse = pulse, pulseTween = nil, enabled = true }
	local hovered = false
	local function to(scale: number)
		TweenService:Create(hover, QUICK, { Scale = scale }):Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		if btn.enabled then to(1.06) end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		to(1)
	end)
	button.InputBegan:Connect(function(input)
		if btn.enabled and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			to(0.92)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			to(if hovered and btn.enabled then 1.06 else 1)
		end
	end)
	return btn
end

local function setPulse(btn: Btn, on: boolean)
	if btn.pulseTween then
		btn.pulseTween:Cancel()
		btn.pulseTween = nil
	end
	btn.pulse.Scale = 1
	if on then
		local t = TweenService:Create(btn.pulse, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 })
		btn.pulseTween = t
		t:Play()
	end
end

-- Activado: color normal, texto blanco con contorno marrón oscuro. Desactivado: gris,
-- semitransparente, texto gris claro y sin animación al pasar el mouse.
local function setEnabled(btn: Btn, on: boolean)
	btn.enabled = on
	btn.button.Active = on
	btn.button.ImageColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(170, 170, 170)
	btn.button.ImageTransparency = if on then 0 else 0.25
	btn.label.TextColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(215, 215, 215)
	local s = btn.label:FindFirstChildOfClass("UIStroke")
	if s then s.Transparency = if on then 0 else 0.5 end
	if not on then
		local hover = btn.holder:FindFirstChildOfClass("UIScale")
		if hover then hover.Scale = 1 end
	end
end

-- Píldora de estado (Listo / Esperando...) con ícono de check.
type PillT = { frame: Frame, label: TextLabel, check: ImageLabel }
local function pill(parent: Instance, center: UDim2): PillT
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position, f.Size = center, UDim2.fromOffset(140, 30)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	corner(f, 999)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Parent = f
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.ApplyStrokeMode = Color3.fromRGB(255, 250, 230), 2.5, Enum.ApplyStrokeMode.Border
	s.Parent = f
	f.Parent = parent
	local check = Assets.Image(f, "check", UDim2.new(0, 5, 0.5, 0), UDim2.fromOffset(24, 24), Vector2.new(0, 0.5))
	local label = textLabel(f, "", UDim2.new(0, 34, 0.12, 0), UDim2.new(1, -44, 0.76, 0), LABEL_FONT, 20, Color3.new(1, 1, 1), Color3.fromRGB(20, 50, 20))
	return { frame = f, label = label, check = check }
end

local function setPill(p: PillT, value: string, color: Color3, showCheck: boolean)
	local g = p.frame:FindFirstChildOfClass("UIGradient")
	if g then g.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color) end
	p.label.Text = value
	p.check.Visible = showCheck
	p.label.Position = if showCheck then UDim2.new(0, 34, 0.12, 0) else UDim2.new(0, 10, 0.12, 0)
	p.label.Size = if showCheck then UDim2.new(1, -44, 0.76, 0) else UDim2.new(1, -20, 0.76, 0)
end

-- Retrato: foto del avatar DEBAJO del marco (centro transparente) + nombre en la placa.
type Portrait = { card: TextButton, photo: ImageLabel, name: TextLabel, mystery: TextLabel, hover: UIScale }
local function portrait(parent: Instance, center: UDim2): Portrait
	local size = Vector2.new(132, 146)
	local card = Instance.new("TextButton")
	card.Text, card.AutoButtonColor = "", false
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position, card.Size = center, UDim2.fromOffset(size.X, size.Y)
	card.Parent = parent
	local hover = Instance.new("UIScale")
	hover.Parent = card
	local photo = Instance.new("ImageLabel")
	photo.Name = "Foto"
	photo.Position, photo.Size = UDim2.fromScale(0.12, 0.09), UDim2.fromScale(0.76, 0.66)
	photo.BackgroundColor3 = Color3.fromRGB(70, 150, 235)
	photo.BorderSizePixel = 0
	photo.Parent = card
	local sky = Instance.new("UIGradient")
	sky.Color = ColorSequence.new(Color3.fromRGB(140, 205, 255), Color3.fromRGB(50, 120, 220))
	sky.Rotation = 90
	sky.Parent = photo
	local mystery = textLabel(photo, "?", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BUTTON_FONT, 80, Color3.new(1, 1, 1), DARK)
	Assets.Image(card, "marco_avatar", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	local name = textLabel(card, "", UDim2.fromScale(0.14, 0.79), UDim2.fromScale(0.72, 0.13), LABEL_FONT, 24, Color3.new(1, 1, 1), DARK)
	return { card = card, photo = photo, name = name, mystery = mystery, hover = hover }
end

-- ══════════════════ Estado ══════════════════

local gui: ScreenGui
local backdrop: Frame
local root: Frame
local fitScale: UIScale
local animScale: UIScale
local me: Portrait
local foe: Portrait
local foePill: PillT
local hourglass: ImageLabel
local timerText: TextLabel
local informalBtn: Btn
local duelBtn: Btn
local sendBtn: Btn
local betRow: Frame
local betBox: TextBox
local prizeText: TextLabel
local infoText: TextLabel
local statusText: TextLabel -- mensaje breve (enviado, error...) que ocupa la zona del modo
local betStroke: UIStroke
local picker: Frame
local search: TextBox
local list: ScrollingFrame

local selected: Player? = nil
local mode: Mode = "Informal"
local inviteDeadline: number? = nil -- os.clock() en que vence el desafío enviado
local isOpen = false
local closing = false
local dismissed = false -- cerró con la X: no reabrir hasta salir de la arena
local shownSeconds = -1
local flipAngle = 0

local function showModeZone()
	statusText.Visible = false
	betRow.Visible = mode == "Duel"
	infoText.Visible = mode == "Informal"
end

-- Mensaje breve en la zona del modo (misma altura: nada se mueve); vuelve solo a los 2,5 s.
local statusToken = 0
local function setFooter(value: string, color: Color3?)
	statusToken += 1
	local token = statusToken
	statusText.Text = value
	statusText.TextColor3 = color or LIGHT_INK
	statusText.Visible = true
	betRow.Visible, infoText.Visible = false, false
	task.delay(2.5, function()
		if statusToken == token then showModeZone() end
	end)
end

local function currentBet(): number?
	if mode ~= "Duel" then return 0 end
	return DuelRules.ValidBet(tonumber(betBox.Text))
end

-- Al terminar de escribir: si la apuesta es menor al mínimo o mayor al oro del jugador (o al
-- máximo), se ajusta al límite y el borde del campo parpadea en rojo.
local refresh: () -> ()
local function clampBet()
	local value = tonumber(betBox.Text) or 0
	local limit = math.clamp(goldOf(localPlayer), DuelRules.MIN_BET, DuelRules.MAX_BET)
	local fixed = math.clamp(math.floor(value), DuelRules.MIN_BET, limit)
	if fixed ~= value then
		betBox.Text = tostring(fixed)
		betStroke.Color = RED
		TweenService:Create(betStroke, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Color = GOLD_BOTTOM }):Play()
	end
	refresh()
end

refresh = function()
	-- Modo elegido: amarillo y pulsando; el otro, gris.
	for _, pair in { { informalBtn, "Informal" }, { duelBtn, "Duel" } } do
		local btn, value = pair[1] :: Btn, pair[2] :: string
		local active = mode == value
		local key: Key = if active then "boton_amarillo" else "boton_gris"
		if btn.button:GetAttribute("Key") ~= key then
			btn.button:SetAttribute("Key", key)
			Assets.Apply(btn.button, key, btn.holder.Size.Y.Offset)
		end
		btn.label.TextColor3 = if active then Color3.fromRGB(255, 252, 235) else Color3.fromRGB(235, 235, 240)
		if active ~= (btn.pulseTween ~= nil) then setPulse(btn, active) end
	end
	if not statusText.Visible then showModeZone() end

	local bet = currentBet()
	if mode == "Duel" then
		prizeText.Text = `Premio: {formatGold(DuelRules.Prize(bet or 0))}`
		prizeText.TextColor3 = if bet and goldOf(localPlayer) >= bet then INK else RED
	end

	local target = selected
	if target and target.Parent == Players then
		setThumbnail(foe.photo, target.UserId)
		foe.mystery.Visible = false
		foe.name.Text = target.DisplayName
		if not inviteDeadline then
			local busy = target:GetAttribute("InDuel") == true
			setPill(foePill, if busy then "En duelo" else "Elegido", if busy then RED else PURPLE, false)
		end
	else
		selected = nil
		foe.photo.Image = ""
		foe.mystery.Visible = true
		foe.name.Text = "RIVAL"
		setPill(foePill, "Tocá para buscar", GREY, false)
	end

	local ready = selected ~= nil and bet ~= nil and not inviteDeadline
	if ready ~= sendBtn.enabled or sendBtn.button:GetAttribute("Styled") == nil then
		sendBtn.button:SetAttribute("Styled", true)
		setEnabled(sendBtn, ready)
		setPulse(sendBtn, ready)
	end
	sendBtn.label.Text = if inviteDeadline then "ESPERANDO" else "DESAFIAR"
end

-- ── Buscador de jugadores ──

local function rebuildList()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local query = string.lower(search.Text)
	local count = 0
	for _, player in Players:GetPlayers() do
		if player == localPlayer then continue end
		local name, display = string.lower(player.Name), string.lower(player.DisplayName)
		if query ~= "" and not string.find(name, query, 1, true) and not string.find(display, query, 1, true) then
			continue
		end
		count += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 70)
		row.BackgroundColor3 = PARCH
		row.LayoutOrder = count
		corner(row, 14)
		local rs = Instance.new("UIStroke")
		rs.Color, rs.Thickness, rs.ApplyStrokeMode = Color3.fromRGB(200, 160, 100), 2, Enum.ApplyStrokeMode.Border
		rs.Parent = row
		row.Parent = list
		local avatar = Instance.new("ImageLabel")
		avatar.Position, avatar.Size = px(8, 7), px(56, 56)
		avatar.BackgroundColor3 = Color3.fromRGB(70, 150, 235)
		corner(avatar, 12)
		avatar.Parent = row
		setThumbnail(avatar, player.UserId)
		textLabel(row, player.DisplayName, px(76, 10), UDim2.new(1, -250, 0, 28), LABEL_FONT, 24, INK).TextXAlignment = Enum.TextXAlignment.Left
		textLabel(row, `@{player.Name}`, px(76, 40), UDim2.new(1, -250, 0, 20), LABEL_FONT, 16, Color3.fromRGB(140, 104, 70)).TextXAlignment = Enum.TextXAlignment.Left
		local busy = player:GetAttribute("InDuel") == true
		local pick = makeButton(row, if busy then "boton_gris" else "boton_violeta", UDim2.new(1, -86, 0.5, 0), Vector2.new(150, 52), if busy then "En duelo" else "Elegir", 24)
		setEnabled(pick, not busy)
		pick.button.Activated:Connect(function()
			if busy then return end
			selected = player
			inviteDeadline = nil
			picker.Visible = false
			statusToken += 1
			showModeZone()
			refresh()
		end)
	end
	if count == 0 then
		local empty = textLabel(list, if #Players:GetPlayers() <= 1 then "No hay otros jugadores en el servidor" else "Nadie coincide con la búsqueda",
			px(0, 0), UDim2.new(1, -12, 0, 60), LABEL_FONT, 22, Color3.fromRGB(140, 104, 70))
		empty.LayoutOrder = 0
	end
end

local function openPicker()
	if inviteDeadline then return end
	search.Text = ""
	rebuildList()
	picker.Visible = true
end

-- ══════════════════ Construcción del menú ══════════════════

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DuelMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- Fondo negro de pantalla completa (aparece con fundido).
	backdrop = Instance.new("Frame")
	backdrop.Name = "Fondo"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
	root.Parent = gui
	fitScale = Instance.new("UIScale")
	fitScale.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundTransparency = 1
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = root
	animScale = Instance.new("UIScale")
	animScale.Parent = panel

	-- Marco (imagen) de fondo: ya trae sus cintas.
	Assets.Image(panel, "marco_panel", px(0, 0), UDim2.fromScale(1, 1))

	-- Título sobre el borde de arriba y la X en la esquina superior derecha del marco.
	local cartel = Assets.Image(panel, "titulo_cartel", px(434, 12), px(360, 141), Vector2.new(0.5, 0.5))
	title(cartel, "MENÚ DE DUELO", UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.66, 0.36), 38, Vector2.new(0.5, 0.5))
	local close = makeButton(panel, "boton_cerrar", px(CANVAS.X - 24, 26), Vector2.new(58, 54), if Assets.Has("boton_cerrar") then "" else "X", 28)
	close.button.Activated:Connect(function()
		dismissed = true
		DuelMenuController.Close()
	end)

	-- Contenido: todo dentro del pergamino, con UIPadding. `c(x, y)` convierte coordenadas
	-- del lienzo 868x558 a coordenadas dentro del contenido.
	local content = Instance.new("Frame")
	content.Name = "Contenido"
	content.BackgroundTransparency = 1
	content.Position = px(PARCHMENT.Min.X, PARCHMENT.Min.Y)
	content.Size = px(PARCHMENT.Width, PARCHMENT.Height)
	content.Parent = panel
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, CONTENT_PAD)
	end
	padding.Parent = content
	local function c(x: number, y: number): UDim2
		return px(x - PARCHMENT.Min.X - CONTENT_PAD, y - PARCHMENT.Min.Y - CONTENT_PAD)
	end

	-- Brillo radial detrás del VS: círculos concéntricos casi transparentes que se suman hacia
	-- el centro (≈0,55 en el centro → 1 en el borde).
	local glow = Instance.new("Frame")
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position, glow.Size = c(434, 182), px(220, 220)
	glow.Parent = content
	for i = 0, 6 do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(1 - i * 0.13, 1 - i * 0.13)
		ring.BackgroundColor3 = Color3.fromRGB(196, 140, 255)
		ring.BackgroundTransparency = 0.9
		ring.BorderSizePixel = 0
		corner(ring, 999)
		ring.Parent = glow
	end
	Assets.Image(content, "escudo_vs", c(434, 182), px(150, 127), Vector2.new(0.5, 0.5))

	-- Reloj + número: un grupo arriba del VS.
	local clock = Instance.new("Frame")
	clock.BackgroundTransparency = 1
	clock.AnchorPoint = Vector2.new(0.5, 0.5)
	clock.Position, clock.Size = c(434, 93), px(132, 50)
	clock.Parent = content
	hourglass = Assets.Image(clock, "reloj_arena", px(20, 25), px(38, 49), Vector2.new(0.5, 0.5))
	hourglass.ImageTransparency = 0
	timerText = textLabel(clock, tostring(DuelRules.INVITE_TTL), px(46, 0), px(86, 50), BUTTON_FONT, 46, GOLD_TOP, DARK)
	timerText.TextXAlignment = Enum.TextXAlignment.Left
	local timerGradient = Instance.new("UIGradient")
	timerGradient.Color = ColorSequence.new(GOLD_TOP, GOLD_BOTTOM)
	timerGradient.Rotation = 90
	timerGradient.Parent = timerText

	-- Retratos y estados
	me = portrait(content, c(236, 178))
	foe = portrait(content, c(632, 178))
	me.name.Text = "VOS"
	me.mystery.Visible = false
	setThumbnail(me.photo, localPlayer.UserId)
	foe.card.MouseEnter:Connect(function() TweenService:Create(foe.hover, QUICK, { Scale = 1.04 }):Play() end)
	foe.card.MouseLeave:Connect(function() TweenService:Create(foe.hover, QUICK, { Scale = 1 }):Play() end)
	foe.card.Activated:Connect(openPicker)
	local myPill = pill(content, c(236, 268))
	setPill(myPill, "Listo", GREEN, true)
	foePill = pill(content, c(632, 268))

	-- Modo
	local modeCartel = Assets.Image(content, "titulo_cartel", c(434, 297), px(140, 55), Vector2.new(0.5, 0.5))
	title(modeCartel, "Modo", UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.6, 0.42), 24, Vector2.new(0.5, 0.5))
	Assets.Image(content, "gema", c(344, 297), px(22, 30), Vector2.new(0.5, 0.5))
	Assets.Image(content, "gema", c(524, 297), px(22, 30), Vector2.new(0.5, 0.5))

	informalBtn = makeButton(content, "boton_gris", c(268, 354), Vector2.new(286, 56), "INFORMAL", 28, "espadas")
	duelBtn = makeButton(content, "boton_amarillo", c(600, 354), Vector2.new(286, 56), "DUELO", 28, "espadas")
	informalBtn.button.Activated:Connect(function()
		if inviteDeadline then return end
		mode = "Informal"
		refresh()
	end)
	duelBtn.button.Activated:Connect(function()
		if inviteDeadline then return end
		mode = "Duel"
		refresh()
	end)

	-- Zona del modo: misma altura en los dos modos (DESAFIAR no se mueve). Ancho 620: deja más
	-- de 40 px de margen a los lados del marco.
	local zone = Instance.new("Frame")
	zone.Name = "ZonaModo"
	zone.BackgroundTransparency = 1
	zone.AnchorPoint = Vector2.new(0.5, 0.5)
	zone.Position, zone.Size = c(434, 403), px(620, MODE_ZONE_HEIGHT)
	zone.Parent = content

	infoText = textLabel(zone, "Amistoso · sin apuesta", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BOLD_FONT, 24, INK)
	statusText = textLabel(zone, "", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BOLD_FONT, 22, INK)
	statusText.Visible = false

	betRow = Instance.new("Frame")
	betRow.BackgroundTransparency = 1
	betRow.Size = UDim2.fromScale(1, 1)
	betRow.Parent = zone
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.Parent = betRow
	local function rowText(value: string, order: number): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Size = UDim2.new(0, 0, 1, 0)
		l.FontFace, l.TextSize, l.TextColor3, l.Text = BOLD_FONT, 22, INK, value
		l.LayoutOrder = order
		l.Parent = betRow
		return l
	end
	Assets.Image(betRow, "moneda", px(0, 0), px(30, 30)).LayoutOrder = 1
	rowText("Apuesta", 2)
	local boxFrame = Instance.new("Frame")
	boxFrame.Size = px(110, 32)
	boxFrame.BackgroundColor3 = Color3.fromRGB(255, 251, 238)
	boxFrame.LayoutOrder = 3
	corner(boxFrame, 9)
	betStroke = Instance.new("UIStroke")
	betStroke.Color, betStroke.Thickness, betStroke.ApplyStrokeMode = GOLD_BOTTOM, 2.5, Enum.ApplyStrokeMode.Border
	betStroke.Parent = boxFrame
	boxFrame.Parent = betRow
	betBox = Instance.new("TextBox")
	betBox.BackgroundTransparency = 1
	betBox.Size = UDim2.fromScale(1, 1)
	betBox.FontFace, betBox.TextSize, betBox.TextColor3 = BUTTON_FONT, 22, INK
	betBox.PlaceholderText, betBox.Text = tostring(DuelRules.MIN_BET), "250"
	betBox.ClearTextOnFocus = false
	betBox.Parent = boxFrame
	betBox:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = betBox.Text:gsub("%D", ""):sub(1, 7)
		if digits ~= betBox.Text then
			betBox.Text = digits -- solo números
			return
		end
		refresh()
	end)
	betBox.FocusLost:Connect(clampBet)
	rowText("·", 4)
	Assets.Image(betRow, "trofeo", px(0, 0), px(32, 28)).LayoutOrder = 5
	prizeText = rowText("", 6)

	-- DESAFIAR: entero dentro del pergamino, abajo y centrado, a 12 px de la zona del modo.
	sendBtn = makeButton(content, "boton_violeta", c(434, 403 + MODE_ZONE_HEIGHT / 2 + 12 + 26), Vector2.new(236, 52), "DESAFIAR", 28, "espadas")
	sendBtn.button.Activated:Connect(function()
		local target, bet = selected, currentBet()
		if not sendBtn.enabled or not target or not bet then return end
		if bet > 0 and goldOf(localPlayer) < bet then
			setFooter(`No tenés {formatGold(bet)} de oro para apostar`, RED)
			return
		end
		Remotes.GetEvent("DuelRequest"):FireServer(target, { Mode = mode, Bet = bet })
		setFooter("Enviando desafío...")
	end)

	-- Buscador: ocupa todo el contenido, encima del resto.
	picker = Instance.new("Frame")
	picker.Size = UDim2.fromScale(1, 1)
	picker.BackgroundColor3 = Color3.new(1, 1, 1)
	corner(picker, 16)
	local pg = Instance.new("UIGradient")
	pg.Color = ColorSequence.new(Color3.fromRGB(250, 238, 210), Color3.fromRGB(232, 210, 166))
	pg.Rotation = 90
	pg.Parent = picker
	local ps = Instance.new("UIStroke")
	ps.Color, ps.Thickness, ps.ApplyStrokeMode = GOLD_BOTTOM, 3, Enum.ApplyStrokeMode.Border
	ps.Parent = picker
	picker.Visible = false
	picker.Parent = content
	title(picker, "Buscar jugador", px(18, 10), px(400, 40), 32).TextXAlignment = Enum.TextXAlignment.Left
	local back = makeButton(picker, "boton_gris", px(620, 32), Vector2.new(150, 48), "Volver", 24)
	back.button.Activated:Connect(function() picker.Visible = false end)
	local searchFrame = Instance.new("Frame")
	searchFrame.Position, searchFrame.Size = px(18, 64), px(674, 44)
	searchFrame.BackgroundColor3 = Color3.fromRGB(255, 251, 238)
	corner(searchFrame, 12)
	local ss = Instance.new("UIStroke")
	ss.Color, ss.Thickness, ss.ApplyStrokeMode = GOLD_BOTTOM, 2.5, Enum.ApplyStrokeMode.Border
	ss.Parent = searchFrame
	searchFrame.Parent = picker
	search = Instance.new("TextBox")
	search.BackgroundTransparency = 1
	search.Position, search.Size = px(16, 0), UDim2.new(1, -24, 1, 0)
	search.FontFace, search.TextSize, search.TextColor3 = LABEL_FONT, 22, INK
	search.PlaceholderText, search.Text = "Escribí un nombre...", ""
	search.PlaceholderColor3 = Color3.fromRGB(170, 140, 110)
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.ClearTextOnFocus = false
	search.Parent = searchFrame
	search:GetPropertyChangedSignal("Text"):Connect(rebuildList)
	list = Instance.new("ScrollingFrame")
	list.Position, list.Size = px(18, 118), UDim2.new(1, -30, 1, -128)
	list.BackgroundTransparency, list.BorderSizePixel = 1, 0
	list.ScrollBarThickness, list.ScrollBarImageColor3 = 8, Color3.fromRGB(140, 90, 40)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = picker
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop, listPad.PaddingLeft = UDim.new(0, 4), UDim.new(0, 4)
	listPad.Parent = list

	refresh()
end

-- Escala y posición para que el panel entre entero entre la barra superior y la de herramientas.
local function fitToScreen()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local view = camera.ViewportSize
	local topInset = GuiService:GetGuiInset().Y + 6
	local bottom = if StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack) then BOTTOM_RESERVE else 24
	local availW = view.X - 24
	local availH = math.max(160, view.Y - topInset - bottom)
	local scale = math.clamp(math.min(availW / CANVAS.X, availH / (CANVAS.Y + OVER_TOP + OVER_BOTTOM)), 0.28, 1.15)
	fitScale.Scale = scale
	root.Position = UDim2.fromOffset(view.X / 2, topInset + availH / 2 + (OVER_TOP - OVER_BOTTOM) / 2 * scale)
end

function DuelMenuController.Open()
	if isOpen and not closing then return end
	isOpen, closing = true, false
	fitToScreen()
	gui.Enabled = true
	animScale.Scale = 0.55
	TweenService:Create(animScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
	setThumbnail(me.photo, localPlayer.UserId)
	refresh()
end

function DuelMenuController.Close()
	if not isOpen or closing then return end
	closing = true
	picker.Visible = false
	TweenService:Create(backdrop, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
	local t = TweenService:Create(animScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.55 })
	t.Completed:Connect(function()
		if closing then
			gui.Enabled = false
			isOpen, closing = false, false
		end
	end)
	t:Play()
end

-- ══════════════════ Invitación entrante ══════════════════

local inviteGui: ScreenGui? = nil
local inviteToken = 0

local function closeInvite(animated: boolean?)
	inviteToken += 1
	local screen = inviteGui
	inviteGui = nil
	if not screen then return end
	local scaleObj = screen:FindFirstChild("Anim", true)
	if animated and scaleObj and scaleObj:IsA("UIScale") then
		local t = TweenService:Create(scaleObj, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.5 })
		t.Completed:Connect(function() screen:Destroy() end)
		t:Play()
	else
		screen:Destroy()
	end
end

local function showInvite(challenger: Player, info: { [string]: any })
	closeInvite(false)
	local token = inviteToken
	local inviteMode: Mode = if info.Mode == "Duel" then "Duel" else "Informal"
	local bet = if typeof(info.Bet) == "number" then info.Bet else 0
	local prize = if typeof(info.Prize) == "number" then info.Prize else 0
	local seconds = if typeof(info.Seconds) == "number" then info.Seconds else DuelRules.INVITE_TTL

	local screen = Instance.new("ScreenGui")
	screen.Name = "DuelInvite"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 9
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = localPlayer:WaitForChild("PlayerGui")
	inviteGui = screen

	-- Mismo lienzo del marco a escala 0,6 (520x335).
	local W, H = 520, 335
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Size = UDim2.fromOffset(W, H)
	holder.Parent = screen
	local fit = Instance.new("UIScale")
	fit.Parent = holder
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local topInset = GuiService:GetGuiInset().Y
	fit.Scale = math.clamp(math.min((view.X - 20) / W, (view.Y * 0.5) / (H + 40)), 0.4, 1)
	holder.Position = UDim2.fromOffset(view.X / 2, topInset + 34 * fit.Scale)

	local card = Instance.new("Frame")
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(1, 1)
	card.Parent = holder
	local anim = Instance.new("UIScale")
	anim.Name = "Anim"
	anim.Scale = 0.5
	anim.Parent = card

	Assets.Image(card, "marco_panel", px(0, 0), UDim2.fromScale(1, 1))
	local cartel = Assets.Image(card, "titulo_cartel", px(W / 2, 6), px(250, 98), Vector2.new(0.5, 0.5))
	title(cartel, "DESAFÍO", UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.62, 0.38), 30, Vector2.new(0.5, 0.5))

	local avatarSize = Vector2.new(112, 124)
	local avatar = Instance.new("Frame")
	avatar.BackgroundTransparency = 1
	avatar.Position, avatar.Size = px(52, 58), UDim2.fromOffset(avatarSize.X, avatarSize.Y)
	avatar.Parent = card
	local photo = Instance.new("ImageLabel")
	photo.Position, photo.Size = UDim2.fromScale(0.12, 0.09), UDim2.fromScale(0.76, 0.66)
	photo.BackgroundColor3 = Color3.fromRGB(70, 150, 235)
	photo.BorderSizePixel = 0
	photo.Parent = avatar
	setThumbnail(photo, challenger.UserId)
	Assets.Image(avatar, "marco_avatar", px(0, 0), UDim2.fromScale(1, 1))
	textLabel(avatar, challenger.DisplayName, UDim2.fromScale(0.14, 0.79), UDim2.fromScale(0.72, 0.13), LABEL_FONT, 16, Color3.new(1, 1, 1), DARK)

	local who = textLabel(card, `{challenger.DisplayName} te desafía`, px(178, 58), px(300, 30), LABEL_FONT, 24, INK)
	who.TextXAlignment = Enum.TextXAlignment.Left
	local modeLine = textLabel(card, if inviteMode == "Duel" then "Modo: Duelo" else "Modo: Informal", px(178, 90), px(300, 24), LABEL_FONT, 20, PURPLE)
	modeLine.TextXAlignment = Enum.TextXAlignment.Left
	if inviteMode == "Duel" then
		Assets.Image(card, "moneda", px(178, 130), px(26, 26), Vector2.new(0, 0.5))
		local betLine = textLabel(card, `{formatGold(bet)} de oro cada uno`, px(210, 118), px(270, 24), LABEL_FONT, 20, INK)
		betLine.TextXAlignment = Enum.TextXAlignment.Left
		Assets.Image(card, "trofeo", px(178, 162), px(28, 25), Vector2.new(0, 0.5))
		local prizeLine = textLabel(card, `Premio: {formatGold(prize)} (-10%)`, px(210, 150), px(270, 24), LABEL_FONT, 20, INK)
		prizeLine.TextXAlignment = Enum.TextXAlignment.Left
		if goldOf(localPlayer) < bet then
			prizeLine.Text = "No tenés oro suficiente"
			prizeLine.TextColor3 = RED
		end
	else
		local line = textLabel(card, "1 round, sin apuesta y sin premio", px(178, 120), px(300, 24), LABEL_FONT, 20, INK)
		line.TextXAlignment = Enum.TextXAlignment.Left
	end

	local bar = Instance.new("Frame")
	bar.Position, bar.Size = px(56, 202), px(408, 10)
	bar.BackgroundColor3 = Color3.fromRGB(214, 190, 146)
	corner(bar, 999)
	bar.Parent = card
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = PURPLE
	corner(fill, 999)
	fill.Parent = bar
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	local function respond(accept: boolean)
		if inviteToken ~= token then return end
		Remotes.GetEvent("DuelResponse"):FireServer(challenger, accept)
		closeInvite(true)
	end
	local accept = makeButton(card, "boton_amarillo", px(160, 258), Vector2.new(200, 58), "Aceptar", 26, "check")
	local decline = makeButton(card, "boton_gris", px(362, 258), Vector2.new(200, 58), "Rechazar", 26)
	setPulse(accept, true)
	accept.button.Activated:Connect(function() respond(true) end)
	decline.button.Activated:Connect(function() respond(false) end)

	TweenService:Create(anim, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(seconds, function()
		if inviteToken == token then closeInvite(true) end
	end)
end

-- ══════════════════ Estado del desafío ══════════════════

local function onState(payload: any)
	if typeof(payload) ~= "table" then return end
	local state = payload.State
	local opponent = payload.Opponent
	local isTarget = typeof(opponent) == "Instance" and opponent == selected

	if state == "InviteSent" then
		inviteDeadline = os.clock() + (if typeof(payload.Seconds) == "number" then payload.Seconds else DuelRules.INVITE_TTL)
		refresh()
		setPill(foePill, "Esperando...", ORANGE, false)
		setFooter("Desafío enviado. Esperando respuesta...")
	elseif state == "Declined" and isTarget then
		inviteDeadline = nil
		refresh()
		setPill(foePill, "Rechazó", RED, false)
		setFooter("Tu rival rechazó el desafío", RED)
	elseif state == "Unavailable" then
		inviteDeadline = nil
		refresh()
		setFooter(if typeof(payload.Message) == "string" then payload.Message else "No disponible ahora", RED)
	elseif state == "Countdown" then
		inviteDeadline = nil
		setPill(foePill, "Listo", GREEN, true)
		closeInvite(true)
		DuelMenuController.Close()
		selected = nil
	end
end

-- ══════════════════ Init ══════════════════

function DuelMenuController:Init()
	build()

	Remotes.GetEvent("DuelInvite").OnClientEvent:Connect(function(challenger: unknown, info: unknown)
		if typeof(challenger) == "Instance" and challenger:IsA("Player") then
			showInvite(challenger, if typeof(info) == "table" then info :: { [string]: any } else {})
		end
	end)
	Remotes.GetEvent("DuelStateChanged").OnClientEvent:Connect(onState)

	Players.PlayerRemoving:Connect(function(player)
		if player == selected then
			selected = nil
			inviteDeadline = nil
			if isOpen then refresh() end
		end
		if picker.Visible then task.defer(rebuildList) end
	end)
	Players.PlayerAdded:Connect(function()
		if picker.Visible then rebuildList() end
	end)
	localPlayer:GetAttributeChangedSignal("Gold"):Connect(function()
		if isOpen then refresh() end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if isOpen then fitToScreen() end
		end)
	end

	-- Abrir/cerrar al pisar la arena + reloj del desafío (se da vuelta cada segundo).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		local seconds = if inviteDeadline then math.max(0, math.ceil(inviteDeadline - os.clock())) else DuelRules.INVITE_TTL
		if inviteDeadline and seconds <= 0 then
			inviteDeadline = nil
			setFooter("El desafío expiró", RED)
			refresh()
		end
		if seconds ~= shownSeconds then
			shownSeconds = seconds
			timerText.Text = tostring(seconds)
			if inviteDeadline and isOpen then
				flipAngle += 180
				TweenService:Create(hourglass, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = flipAngle }):Play()
			end
		end

		accumulator += dt
		if accumulator < 0.2 then return end
		accumulator = 0
		local character = localPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local rootPart = if humanoid and humanoid.Health > 0 then humanoid.RootPart else nil
		local inside = rootPart ~= nil and localPlayer:GetAttribute("InDuel") ~= true and DuelRules.InZone(rootPart.Position)
		if inside and not isOpen and not dismissed then
			DuelMenuController.Open()
		elseif not inside then
			dismissed = false
			if isOpen and not DuelRules.InZone(if rootPart then rootPart.Position else Vector3.zero, 3) then
				DuelMenuController.Close()
			end
		end
	end)
end

return DuelMenuController
