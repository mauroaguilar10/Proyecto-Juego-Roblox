--!strict
local Players = game:GetService("Players")
local UIController = {}

function UIController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "EconomyHUD"
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Name = "Gold"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -16, 0, 12)
	label.Size = UDim2.fromOffset(154, 38)
	label.BackgroundColor3 = Color3.fromRGB(35, 29, 23)
	label.TextColor3 = Color3.fromRGB(255, 221, 145)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.Parent = label

	local function refresh()
		local gold = player:GetAttribute("Gold")
		label.Text = if typeof(gold) == "number" then "Oro: " .. tostring(gold) else "Oro: …"
	end
	player:GetAttributeChangedSignal("Gold"):Connect(refresh)
	refresh()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return UIController
