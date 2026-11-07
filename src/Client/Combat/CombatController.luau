--!strict
--[[
	CombatController — Input de ataque y feedback visual de golpes.
	Owner: Dev A (Combat).

	- El arma es una Tool de inventario (ver WeaponVisualService). Con ella en la mano,
	  Tool.Activated (click izquierdo / toque / R2) → Remotes "CombatAttack"(aim), girando al
	  personaje hacia el cursor/toque (o la cámara con gamepad).
	- Cooldown predicho en cliente solo para no spamear; el servidor es quien valida.
	- Remotes "CombatFeedback" → destello rojo sobre el objetivo golpeado.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HIT_FLASH_DURATION = 0.15
local HIT_FLASH_COLOR = Color3.fromRGB(255, 60, 60)

-- Swing placeholder: rota el Weld "WeaponGrip" (ver WeaponVisualService) sobre el eje X del agarre.
-- Ángulo positivo = el arma sube; negativo = baja.
local SWING_KEYFRAMES: { { angle: number, duration: number, style: Enum.EasingStyle } } = {
	{ angle = 70, duration = 0.06, style = Enum.EasingStyle.Quad }, -- preparación
	{ angle = -45, duration = 0.09, style = Enum.EasingStyle.Quad }, -- tajo
	{ angle = 0, duration = 0.12, style = Enum.EasingStyle.Sine }, -- recuperación
}

local localPlayer = Players.LocalPlayer
local lastAttackAt = -math.huge
local swingTokens: { [Weld]: number } = setmetatable({}, { __mode = "k" }) :: any
local restC0: { [Weld]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local CombatController = {}

local function playSwing(character: Model)
	local weapon = character:FindFirstChild("Weapon")
	local grip = if weapon then weapon:FindFirstChild("Grip") else nil
	local weld = if grip then grip:FindFirstChild("WeaponGrip") else nil
	if not weld or not weld:IsA("Weld") then
		return
	end

	local rest = restC0[weld] or weld.C0
	restC0[weld] = rest
	local token = (swingTokens[weld] or 0) + 1
	swingTokens[weld] = token

	task.spawn(function()
		for _, keyframe in SWING_KEYFRAMES do
			if swingTokens[weld] ~= token or not weld.Parent then
				return
			end
			local tween = TweenService:Create(
				weld,
				TweenInfo.new(keyframe.duration, keyframe.style, Enum.EasingDirection.Out),
				{ C0 = rest * CFrame.Angles(math.rad(keyframe.angle), 0, 0) }
			)
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

-- Swing de otros jugadores: se dispara cuando el servidor pone CombatState = "Attacking".
-- El jugador local hace el swing al instante (predicción) y se ignora aquí.
local function watchCharacter(player: Player, character: Model)
	if player == localPlayer then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid:GetAttributeChangedSignal("CombatState"):Connect(function()
		if humanoid:GetAttribute("CombatState") == "Attacking" then
			playSwing(character)
		end
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

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

-- Dirección horizontal hacia donde apunta el jugador: el punto del piso bajo el cursor/toque
-- (a la altura del personaje); con gamepad, hacia donde mira la cámara.
local function getAimDirection(root: BasePart): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local direction: Vector3
	if UserInputService:GetLastInputType().Name:find("Gamepad") then
		direction = camera.CFrame.LookVector
	else
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		if math.abs(ray.Direction.Y) > 1e-3 then
			local t = (root.Position.Y - ray.Origin.Y) / ray.Direction.Y
			direction = if t > 0 then ray.Origin + ray.Direction * t - root.Position else ray.Direction
		else
			direction = ray.Direction
		end
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else nil
end

-- Conecta Activated de la Tool del arma (Attribute "WeaponId") una sola vez por Tool.
local function hookWeaponTool(child: Instance, attackEvent: RemoteEvent)
	if not child:IsA("Tool") or child:GetAttribute("WeaponId") == nil or hookedTools[child] then
		return
	end
	hookedTools[child] = true
	child.Activated:Connect(function()
		local character = localPlayer.Character
		if not character or child.Parent ~= character or not canAttack() then
			return
		end
		lastAttackAt = os.clock()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = if humanoid then humanoid.RootPart else nil
		local aim = if root then getAimDirection(root) else nil
		if root and aim then
			-- Girar al personaje hacia el golpe para que lo que se ve coincida con lo que valida el servidor.
			root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)
		end
		attackEvent:FireServer(aim)
		playSwing(character)
	end)
end

function CombatController:Init()
	local attackEvent = Remotes.GetEvent("CombatAttack")
	local feedbackEvent = Remotes.GetEvent("CombatFeedback")

	-- La Tool se equipa moviéndose al personaje: basta con vigilar sus hijos.
	local function watchOwnCharacter(character: Model)
		character.ChildAdded:Connect(function(child)
			hookWeaponTool(child, attackEvent)
		end)
		for _, child in character:GetChildren() do
			hookWeaponTool(child, attackEvent)
		end
	end
	localPlayer.CharacterAdded:Connect(watchOwnCharacter)
	if localPlayer.Character then
		task.spawn(watchOwnCharacter, localPlayer.Character)
	end

	feedbackEvent.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local target = payload.Target
		if typeof(target) == "Instance" and target:IsA("Model") and target.Parent then
			flashTarget(target)
		end
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(watchPlayer, player)
	end
end

return CombatController
