--!strict
--[[
	DuelController — Desafíos y HUD de duelos en el cliente.
	Owner: Dev A (Combat).

	- ProximityPrompt local "Desafiar a duelo" sobre cada otro jugador (oculto si alguno está en duelo).
	- Invitaciones y avisos breves con notificaciones nativas de Roblox (SetCore).
	- HUD del duelo: cuenta regresiva grande, barras de vida (vos y el rival), reloj,
	  resultado y botón de revancha (manda un DuelRequest; si los dos lo piden, empieza directo).
	Otras UIs pueden escuchar "DuelInvite" y "DuelStateChanged" por su cuenta.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local PROMPT_NAME = "DuelPrompt"
local ACCEPT = "Aceptar"
local DECLINE = "Rechazar"
local RESULT_DURATION = 15 -- s que se muestra el resultado / botón de revancha
local REASONS = {
	Defeat = "por derrota",
	Forfeit = "por abandono",
	Timeout = "se acabó el tiempo",
}

local FULL_COLOR = Color3.fromRGB(80, 220, 100)
local LOW_COLOR = Color3.fromRGB(230, 60, 60)
local WIN_COLOR = Color3.fromRGB(255, 210, 70)
local LOSE_COLOR = Color3.fromRGB(230, 80, 80)
local DRAW_COLOR = Color3.fromRGB(200, 200, 210)

type Hud = {
	screen: ScreenGui,
	top: Frame,
	timer: TextLabel,
	myName: TextLabel,
	myFill: Frame,
	foeName: TextLabel,
	foeFill: Frame,
	center: TextLabel,
	sub: TextLabel,
	rematch: TextButton,
}

local localPlayer = Players.LocalPlayer
local prompts: { [Player]: ProximityPrompt } = {}
local hud: Hud? = nil
local opponent: Player? = nil
local endsAt: number? = nil
local hudToken = 0

local DuelController = {}

-- ── Notificaciones ──

local function notify(options: { [string]: any })
	-- SetCore puede fallar si el CoreScript todavía no registró la notificación.
	local ok = pcall(StarterGui.SetCore, StarterGui, "SendNotification", options)
	if not ok then
		task.delay(1, function()
			pcall(StarterGui.SetCore, StarterGui, "SendNotification", options)
		end)
	end
end

-- ── HUD ──

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, size: UDim2, position: UDim2, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = font
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Parent = parent
	return l
end

local function healthBar(parent: Instance, position: UDim2, alignRight: boolean): (TextLabel, Frame)
	local name = label(parent, UDim2.new(0.42, 0, 0, 18), position, Enum.Font.GothamBold)
	name.TextXAlignment = if alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left

	local back = Instance.new("Frame")
	back.Size = UDim2.new(0.42, 0, 0, 14)
	back.Position = position + UDim2.fromOffset(0, 22)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	back.BorderSizePixel = 0
	corner(back, 5)
	back.Parent = parent

	local fill = Instance.new("Frame")
	fill.AnchorPoint = if alignRight then Vector2.new(1, 0) else Vector2.zero
	fill.Position = if alignRight then UDim2.fromScale(1, 0) else UDim2.fromScale(0, 0)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = FULL_COLOR
	fill.BorderSizePixel = 0
	corner(fill, 5)
	fill.Parent = back
	return name, fill
end

local function buildHud(): Hud
	local screen = Instance.new("ScreenGui")
	screen.Name = "DuelHud"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 5
	screen.Parent = localPlayer:WaitForChild("PlayerGui")

	local top = Instance.new("Frame")
	top.Name = "Top"
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 8)
	top.Size = UDim2.new(0.9, 0, 0, 44)
	top.BackgroundTransparency = 1
	top.Visible = false
	top.Parent = screen
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(560, 44)
	sizeLimit.Parent = top

	local myName, myFill = healthBar(top, UDim2.fromScale(0, 0), false)
	local foeName, foeFill = healthBar(top, UDim2.fromScale(0.58, 0), true)
	local timer = label(top, UDim2.new(0.14, 0, 0, 30), UDim2.new(0.43, 0, 0, 6), Enum.Font.GothamBlack)

	local center = label(screen, UDim2.new(0.8, 0, 0, 80), UDim2.new(0.1, 0, 0.3, 0), Enum.Font.GothamBlack)
	center.Visible = false
	local sub = label(screen, UDim2.new(0.8, 0, 0, 26), UDim2.new(0.1, 0, 0.3, 84), Enum.Font.GothamMedium)
	sub.Visible = false

	local rematch = Instance.new("TextButton")
	rematch.Name = "Rematch"
	rematch.AnchorPoint = Vector2.new(0.5, 0)
	rematch.Position = UDim2.new(0.5, 0, 0.3, 122)
	rematch.Size = UDim2.fromOffset(180, 44)
	rematch.BackgroundColor3 = Color3.fromRGB(235, 170, 40)
	rematch.Font = Enum.Font.GothamBold
	rematch.TextSize = 20
	rematch.TextColor3 = Color3.fromRGB(30, 20, 5)
	rematch.Text = "Revancha"
	rematch.Visible = false
	corner(rematch, 10)
	rematch.Parent = screen

	return {
		screen = screen,
		top = top,
		timer = timer,
		myName = myName,
		myFill = myFill,
		foeName = foeName,
		foeFill = foeFill,
		center = center,
		sub = sub,
		rematch = rematch,
	}
end

local function getHud(): Hud
	if not hud then
		hud = buildHud()
	end
	return hud :: Hud
end

local function showCenter(text: string, color: Color3, subText: string?)
	local h = getHud()
	h.center.Text = text
	h.center.TextColor3 = color
	h.center.Visible = true
	h.center.TextTransparency = 0
	h.center.Size = UDim2.new(0.8, 0, 0, 110)
	TweenService:Create(h.center, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.new(0.8, 0, 0, 80) }):Play()
	h.sub.Text = subText or ""
	h.sub.Visible = subText ~= nil
end

local function hideCenter()
	local h = getHud()
	h.center.Visible = false
	h.sub.Visible = false
	h.rematch.Visible = false
end

local function healthRatio(player: Player?): number
	local character = if player then player.Character else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.MaxHealth <= 0 then
		return 0
	end
	return math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
end

local function setFill(fill: Frame, ratio: number)
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = LOW_COLOR:Lerp(FULL_COLOR, ratio)
end

local function updateHud()
	local h = hud
	if not h or not h.top.Visible then
		return
	end
	setFill(h.myFill, healthRatio(localPlayer))
	setFill(h.foeFill, healthRatio(opponent))
	if endsAt then
		local remaining = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
		h.timer.Text = string.format("%d:%02d", remaining // 60, remaining % 60)
		h.timer.TextColor3 = if remaining <= 10 then LOSE_COLOR else Color3.new(1, 1, 1)
	else
		h.timer.Text = ""
	end
end

local function startCountdown(seconds: number, token: number)
	task.spawn(function()
		for n = seconds, 1, -1 do
			if hudToken ~= token then
				return
			end
			showCenter(tostring(n), Color3.new(1, 1, 1))
			task.wait(1)
		end
	end)
end

local function showResult(winner: any, reason: any, foe: Player?, token: number)
	local h = getHud()
	h.top.Visible = false
	endsAt = nil

	local reasonText = if typeof(reason) == "string" then REASONS[reason] else nil
	if winner == nil then
		showCenter("EMPATE", DRAW_COLOR, reasonText)
	elseif winner == localPlayer then
		showCenter("¡GANASTE!", WIN_COLOR, reasonText)
	else
		showCenter("PERDISTE", LOSE_COLOR, reasonText)
	end

	h.rematch.Visible = foe ~= nil and foe.Parent == Players
	h.rematch.Text = "Revancha"
	h.rematch.AutoButtonColor = true
	h.rematch.Active = true

	task.delay(RESULT_DURATION, function()
		if hudToken == token then
			hideCenter()
		end
	end)
end

local function onStateChanged(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local foe = payload.Opponent
	local foePlayer: Player? = if typeof(foe) == "Instance" and foe:IsA("Player") then foe else nil
	local foeName = if foePlayer then foePlayer.DisplayName else "tu rival"

	local state = payload.State
	if state == "InviteSent" then
		notify({ Title = "Duelo", Text = `Desafío enviado a {foeName}`, Duration = 3 })
	elseif state == "Declined" then
		notify({ Title = "Duelo", Text = `{foeName} rechazó el desafío`, Duration = 3 })
	elseif state == "Unavailable" then
		notify({ Title = "Duelo", Text = `{foeName} no está disponible ahora (o vos no lo estás)`, Duration = 3 })
		local h = hud
		if h and h.rematch.Visible then
			h.rematch.Text = "Revancha"
			h.rematch.Active = true
		end
	elseif state == "Countdown" then
		hudToken += 1
		opponent = foePlayer
		endsAt = nil
		local h = getHud()
		hideCenter()
		h.myName.Text = localPlayer.DisplayName
		h.foeName.Text = foeName
		h.top.Visible = true
		startCountdown(if typeof(payload.Seconds) == "number" then payload.Seconds else 3, hudToken)
	elseif state == "Fight" then
		hudToken += 1
		opponent = foePlayer
		endsAt = if typeof(payload.EndsAt) == "number" then payload.EndsAt else nil
		getHud().top.Visible = true
		showCenter("¡A PELEAR!", WIN_COLOR)
		local token = hudToken
		task.delay(1, function()
			if hudToken == token then
				hideCenter()
			end
		end)
	elseif state == "End" then
		hudToken += 1
		showResult(payload.Winner, payload.Reason, foePlayer, hudToken)
	end
end

-- ── Desafíos ──

local function isInDuel(player: Player): boolean
	return player:GetAttribute("InDuel") == true
end

local function refreshPrompt(player: Player)
	local prompt = prompts[player]
	if prompt then
		prompt.Enabled = not isInDuel(player) and not isInDuel(localPlayer)
	end
end

local function attachPrompt(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Desafiar a duelo"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function()
		Remotes.GetEvent("DuelRequest"):FireServer(player)
	end)

	prompts[player] = prompt
	refreshPrompt(player)
end

local function watchPlayer(player: Player)
	if player == localPlayer then
		return
	end

	player.CharacterAdded:Connect(function(character)
		attachPrompt(player, character)
	end)
	if player.Character then
		task.spawn(attachPrompt, player, player.Character)
	end

	player:GetAttributeChangedSignal("InDuel"):Connect(function()
		refreshPrompt(player)
	end)
end

local function onInvite(challenger: unknown)
	if typeof(challenger) ~= "Instance" or not challenger:IsA("Player") then
		return
	end

	local callback = Instance.new("BindableFunction")
	callback.OnInvoke = function(choice: string)
		Remotes.GetEvent("DuelResponse"):FireServer(challenger, choice == ACCEPT)
		callback:Destroy()
	end

	local isRematch = challenger == opponent
	notify({
		Title = if isRematch then "¡Piden revancha!" else "¡Desafío de duelo!",
		Text = if isRematch
			then `{challenger.DisplayName} quiere la revancha`
			else `{challenger.DisplayName} te desafía a un duelo 1v1`,
		Duration = 15,
		Button1 = ACCEPT,
		Button2 = DECLINE,
		Callback = callback,
	})
end

local function requestRematch()
	local h = hud
	local foe = opponent
	if not h or not foe or foe.Parent ~= Players or not h.rematch.Active then
		return
	end
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		notify({ Title = "Duelo", Text = "Esperá a reaparecer para pedir la revancha", Duration = 3 })
		return
	end
	h.rematch.Active = false
	h.rematch.AutoButtonColor = false
	h.rematch.Text = "Esperando..."
	Remotes.GetEvent("DuelRequest"):FireServer(foe)
	task.delay(3, function()
		if hud == h and h.rematch.Visible and not h.rematch.Active then
			h.rematch.Text = "Revancha"
			h.rematch.Active = true
			h.rematch.AutoButtonColor = true
		end
	end)
end

function DuelController:Init()
	Remotes.GetEvent("DuelInvite").OnClientEvent:Connect(onInvite)
	Remotes.GetEvent("DuelStateChanged").OnClientEvent:Connect(onStateChanged)

	getHud().rematch.Activated:Connect(requestRematch)
	RunService.Heartbeat:Connect(updateHud)

	localPlayer:GetAttributeChangedSignal("InDuel"):Connect(function()
		for player in prompts do
			refreshPrompt(player)
		end
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		prompts[player] = nil
		local h = hud
		if player == opponent and h then
			h.rematch.Visible = false
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(watchPlayer, player)
	end
end

return DuelController
