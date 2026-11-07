--!strict
--[[
	HealthBarController — Barras de vida y de postura sobre personajes, y barra de postura propia.
	Owner: Dev A (Combat).

	- Enemigos (Humanoid sin jugador): barra con nombre, siempre visible de cerca.
	- Otros jugadores: vida + postura (Humanoid.Posture, crece desde el centro como en un duelo de
	  postura), visibles cuando están heridos o con postura acumulada (el nombre ya lo pone Roblox).
	  Oculta la barra de vida por defecto de Roblox (solo en este cliente) para no duplicarla.
	- Jugador local: barra de postura sobre la hotbar, visible mientras tenga postura acumulada.
	  Parpadea en rojo con la guardia rota (CombatState "PostureBroken").
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MAX_DISTANCE = 70
local BAR_SIZE = UDim2.fromOffset(110, 12)
local BAR_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FULL_COLOR = Color3.fromRGB(80, 220, 100)
local LOW_COLOR = Color3.fromRGB(230, 60, 60)
local MAX_POSTURE = 100 -- igual que CombatService
local POSTURE_LOW_COLOR = Color3.fromRGB(255, 215, 90)
local POSTURE_HIGH_COLOR = Color3.fromRGB(255, 70, 30)
local POSTURE_BAR_HEIGHT = 6
local BAR_GAP = 3

local function postureRatio(humanoid: Humanoid): number
	local value = humanoid:GetAttribute("Posture")
	return if typeof(value) == "number" then math.clamp(value / MAX_POSTURE, 0, 1) else 0
end

local function postureColor(ratio: number): Color3
	return POSTURE_LOW_COLOR:Lerp(POSTURE_HIGH_COLOR, ratio)
end

local localPlayer = Players.LocalPlayer
local bars: { [Humanoid]: BillboardGui } = {}

local HealthBarController = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeBar(parent: Instance, size: UDim2, position: UDim2): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Size = size
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	corner(back, 4)
	back.Parent = parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	corner(fill, 4)
	fill.Parent = back
	return back, fill
end

local function removeBar(humanoid: Humanoid)
	local gui = bars[humanoid]
	if gui then
		gui:Destroy()
		bars[humanoid] = nil
	end
end

local function attachBar(humanoid: Humanoid)
	local model = humanoid.Parent
	if bars[humanoid] or not model or not model:IsA("Model") or model == localPlayer.Character then
		return
	end
	local head = model:WaitForChild("Head", 5)
	if not head or not head:IsA("BasePart") or humanoid.Parent ~= model then
		return
	end

	local owner = Players:GetPlayerFromCharacter(model)
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	if not owner then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DISTANCE
	gui.Size = UDim2.fromOffset(BAR_SIZE.X.Offset, if owner then BAR_SIZE.Y.Offset + BAR_GAP + POSTURE_BAR_HEIGHT else 32)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if owner then 3.4 else 2.4, 0)

	if not owner then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 18)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = model.Name
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
	end
	local healthPosition = if owner then UDim2.fromScale(0, 0) else UDim2.new(0, 0, 1, -BAR_SIZE.Y.Offset)
	local _, fill = makeBar(gui, UDim2.new(1, 0, 0, BAR_SIZE.Y.Offset), healthPosition)

	-- Postura (solo jugadores): crece desde el centro hacia los lados.
	local postureFill: Frame? = nil
	if owner then
		local _, pFill = makeBar(gui, UDim2.new(1, 0, 0, POSTURE_BAR_HEIGHT), UDim2.new(0, 0, 1, -POSTURE_BAR_HEIGHT))
		pFill.AnchorPoint = Vector2.new(0.5, 0)
		pFill.Position = UDim2.fromScale(0.5, 0)
		pFill.Size = UDim2.fromScale(0, 1)
		postureFill = pFill
	end

	local function refresh()
		local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		TweenService:Create(fill, BAR_TWEEN, {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = LOW_COLOR:Lerp(FULL_COLOR, ratio),
		}):Play()
		local posture = postureRatio(humanoid)
		if postureFill then
			TweenService:Create(postureFill, BAR_TWEEN, {
				Size = UDim2.fromScale(posture, 1),
				BackgroundColor3 = postureColor(posture),
			}):Play()
		end
		gui.Enabled = not owner or ratio < 1 or posture > 0
	end
	refresh()
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	humanoid:GetAttributeChangedSignal("Posture"):Connect(refresh)
	humanoid.Died:Once(function()
		task.delay(1, removeBar, humanoid)
	end)
	humanoid.AncestryChanged:Connect(function()
		if not humanoid:IsDescendantOf(workspace) then
			removeBar(humanoid)
		end
	end)

	gui.Parent = localPlayer:FindFirstChildOfClass("PlayerGui")
	bars[humanoid] = gui
end

local function onDescendantAdded(instance: Instance)
	if instance:IsA("Humanoid") then
		task.spawn(attachBar, instance)
	end
end

-- ── Postura propia ──

local function buildPostureBar(): (ScreenGui, Frame)
	local screen = Instance.new("ScreenGui")
	screen.Name = "CombatPosture"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true

	local back, fill = makeBar(screen, UDim2.fromOffset(240, 8), UDim2.new(0.5, -120, 1, -84))
	back.Name = "Posture"
	fill.AnchorPoint = Vector2.new(0.5, 0)
	fill.Position = UDim2.fromScale(0.5, 0)
	screen.Parent = localPlayer:WaitForChild("PlayerGui")
	return screen, fill
end

function HealthBarController:Init()
	workspace.DescendantAdded:Connect(onDescendantAdded)
	for _, instance in workspace:GetDescendants() do
		onDescendantAdded(instance)
	end

	local screen, fill = buildPostureBar()
	RunService.RenderStepped:Connect(function()
		local character = localPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not humanoid or humanoid.Health <= 0 then
			screen.Enabled = false
			return
		end
		local ratio = postureRatio(humanoid)
		screen.Enabled = ratio > 0
		fill.Size = UDim2.fromScale(ratio, 1)
		if humanoid:GetAttribute("CombatState") == "PostureBroken" then
			local blink = math.sin(os.clock() * 20) > 0
			fill.BackgroundColor3 = if blink then POSTURE_HIGH_COLOR else Color3.new(1, 1, 1)
		else
			fill.BackgroundColor3 = postureColor(ratio)
		end
	end)
end

return HealthBarController
