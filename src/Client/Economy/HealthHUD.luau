--!strict
--[[
	HealthHUD — Barra de vida propia del jugador (reemplaza la de Roblox).
	Owner: Dev B (Economía).

	- Abajo al centro, encima de la barra de aguante (HealthBarController, Combat).
	- Dentro de la barra: "180/200 HP". El color cambia según el %: verde, amarillo, naranja, rojo
	  (y titila cuando queda poca vida).
	- A la izquierda, un escudo con la armadura (Humanoid.Armor, ArmorService) si tenés alguna.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local HealthHUD = {}

local BAR_WIDTH, BAR_HEIGHT = 300, 26
local LOW = 0.25 -- debajo de esto titila

-- Color según el porcentaje de vida.
local function colorFor(ratio: number): Color3
	if ratio > 0.6 then
		return Color3.fromRGB(70, 200, 90)
	elseif ratio > 0.35 then
		return Color3.fromRGB(235, 200, 60)
	elseif ratio > LOW then
		return Color3.fromRGB(240, 130, 40)
	end
	return Color3.fromRGB(220, 50, 50)
end

-- La barra de Roblox se apaga con SetCore; puede fallar si el CoreGui todavía no cargó.
local function hideDefaultBar()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false) then return end
		task.wait(0.5)
	end
end

function HealthHUD:Init()
	task.spawn(hideDefaultBar)
	local player = Players.LocalPlayer
	local screen = Instance.new("ScreenGui")
	screen.Name = "BarraDeVida"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true

	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -92)
	back.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	back.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	back.BorderSizePixel = 0
	back.Parent = screen
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 6)
	local outline = Instance.new("UIStroke")
	outline.Color, outline.Thickness = Color3.fromRGB(10, 10, 12), 2
	outline.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = colorFor(1)
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	shine.Rotation = 90
	shine.Parent = fill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.ZIndex = 3
	label.Parent = back

	local shield = Instance.new("TextLabel")
	shield.AnchorPoint = Vector2.new(1, 0.5)
	shield.Position = UDim2.new(0, -8, 0.5, 0)
	shield.Size = UDim2.fromOffset(70, BAR_HEIGHT)
	shield.BackgroundTransparency = 1
	shield.Font = Enum.Font.GothamBold
	shield.TextSize = 15
	shield.TextColor3 = Color3.fromRGB(140, 180, 245)
	shield.TextStrokeTransparency = 0.3
	shield.TextXAlignment = Enum.TextXAlignment.Right
	shield.Parent = back

	local humanoid: Humanoid? = nil
	local connections: { RBXScriptConnection } = {}
	local function update()
		local hum = humanoid
		if not hum then return end
		local max = math.max(1, hum.MaxHealth)
		local health = math.clamp(hum.Health, 0, max)
		local ratio = health / max
		label.Text = `{math.ceil(health)}/{math.floor(max)} HP`
		TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = colorFor(ratio),
		}):Play()
		local armor = hum:GetAttribute("Armor")
		shield.Text = if typeof(armor) == "number" and armor > 0 then `🛡 {math.round(armor * 100)}%` else ""
	end
	local function bind(character: Model)
		for _, c in connections do c:Disconnect() end
		table.clear(connections)
		local hum = character:WaitForChild("Humanoid", 10)
		if not hum or not hum:IsA("Humanoid") then return end
		humanoid = hum
		table.insert(connections, hum.HealthChanged:Connect(update))
		table.insert(connections, hum:GetPropertyChangedSignal("MaxHealth"):Connect(update))
		table.insert(connections, hum:GetAttributeChangedSignal("Armor"):Connect(update))
		update()
	end
	player.CharacterAdded:Connect(bind)
	if player.Character then task.spawn(bind, player.Character) end

	-- Con poca vida la barra titila.
	RunService.RenderStepped:Connect(function()
		local hum = humanoid
		local low = hum ~= nil and hum.Health > 0 and hum.Health / math.max(1, hum.MaxHealth) <= LOW
		fill.BackgroundTransparency = if low then 0.25 + 0.25 * math.sin(os.clock() * 8) else 0
	end)
	screen.Parent = player:WaitForChild("PlayerGui")
end

return HealthHUD
