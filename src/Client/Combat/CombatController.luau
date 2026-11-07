--!strict
--[[
	CombatController — Input de ataque y feedback visual de golpes.
	Owner: Dev A (Combat).

	- Click izquierdo / R2 / botón táctil → Remotes "CombatAttack".
	- Cooldown predicho en cliente solo para no spamear; el servidor es quien valida.
	- Remotes "CombatFeedback" → destello rojo sobre el objetivo golpeado.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ACTION_ATTACK = "CombatAttack"
local HIT_FLASH_DURATION = 0.15
local HIT_FLASH_COLOR = Color3.fromRGB(255, 60, 60)

local localPlayer = Players.LocalPlayer
local lastAttackAt = -math.huge

local CombatController = {}

local function canAttack(): boolean
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local state = humanoid:GetAttribute("CombatState")
	if state == "Stunned" or state == "Dead" then
		return false
	end

	local equipped = localPlayer:GetAttribute("EquippedWeapon")
	local weapon = WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil)
	return os.clock() - lastAttackAt >= weapon.AttackCooldown
end

local function flashTarget(target: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = HIT_FLASH_COLOR
	highlight.FillTransparency = 0.4
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = target
	Debris:AddItem(highlight, HIT_FLASH_DURATION)
end

function CombatController:Init()
	local attackEvent = Remotes.GetEvent("CombatAttack")
	local feedbackEvent = Remotes.GetEvent("CombatFeedback")

	ContextActionService:BindAction(
		ACTION_ATTACK,
		function(_actionName: string, inputState: Enum.UserInputState, _input: InputObject)
			if inputState == Enum.UserInputState.Begin and canAttack() then
				lastAttackAt = os.clock()
				attackEvent:FireServer()
			end
			return Enum.ContextActionResult.Pass
		end,
		true, -- botón táctil en mobile
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:SetTitle(ACTION_ATTACK, "Atacar")

	feedbackEvent.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local target = payload.Target
		if typeof(target) == "Instance" and target:IsA("Model") and target.Parent then
			flashTarget(target)
		end
	end)
end

return CombatController
