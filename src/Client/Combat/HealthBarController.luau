--!strict
--[[
	HealthBarController — Barras de vida sobre personajes y barra de aguante propia.
	Owner: Dev A (Combat).

	- Enemigos (Humanoid sin jugador): barra con nombre, siempre visible de cerca.
	- Otros jugadores: barra solo cuando tienen menos vida que el máximo (el nombre ya lo pone Roblox).
	  Oculta la barra de vida por defecto de Roblox (solo en este cliente) para no duplicarla.
	- Jugador local: barra de aguante (Humanoid.Stamina, la escribe CombatService) sobre la hotbar,
	  visible con el arma en la mano o mientras no esté llena.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MAX_DISTANCE = 70
local BAR_SIZE = UDim2.fromOffset(110, 12)
local BAR_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FULL_COLOR = Color3.fromRGB(80, 220, 100)
local LOW_COLOR = Color3.fromRGB(230, 60, 60)
local MAX_STAMINA = 100 -- igual que CombatService
local STAMINA_COLOR = Color3.fromRGB(255, 205, 60)
local STAMINA_EMPTY_COLOR = Color3.fromRGB(200, 110, 40)

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
	gui.Size = UDim2.fromOffset(BAR_SIZE.X.Offset, if owner then BAR_SIZE.Y.Offset else 32)
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
	local _, fill = makeBar(gui, UDim2.new(1, 0, 0, BAR_SIZE.Y.Offset), UDim2.new(0, 0, 1, -BAR_SIZE.Y.Offset))

	local function refresh()
		local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		TweenService:Create(fill, BAR_TWEEN, {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = LOW_COLOR:Lerp(FULL_COLOR, ratio),
		}):Play()
		gui.Enabled = not owner or ratio < 1
	end
	refresh()
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
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

-- ── Aguante ──

local function buildStaminaBar(): (ScreenGui, Frame)
	local screen = Instance.new("ScreenGui")
	screen.Name = "CombatStamina"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true

	local back, fill = makeBar(screen, UDim2.fromOffset(220, 8), UDim2.new(0.5, -110, 1, -84))
	back.Name = "Stamina"
	fill.BackgroundColor3 = STAMINA_COLOR
	screen.Parent = localPlayer:WaitForChild("PlayerGui")
	return screen, fill
end

local function hasWeaponInHand(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("WeaponId") ~= nil
end

function HealthBarController:Init()
	workspace.DescendantAdded:Connect(onDescendantAdded)
	for _, instance in workspace:GetDescendants() do
		onDescendantAdded(instance)
	end

	local screen, fill = buildStaminaBar()
	RunService.RenderStepped:Connect(function()
		local character = localPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local stamina = if humanoid then humanoid:GetAttribute("Stamina") else nil
		if not character or not humanoid or typeof(stamina) ~= "number" or humanoid.Health <= 0 then
			screen.Enabled = false
			return
		end
		local ratio = math.clamp(stamina / MAX_STAMINA, 0, 1)
		screen.Enabled = ratio < 1 or hasWeaponInHand(character)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = STAMINA_EMPTY_COLOR:Lerp(STAMINA_COLOR, ratio)
	end)
end

return HealthBarController
