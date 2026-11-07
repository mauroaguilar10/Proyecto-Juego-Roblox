--!strict
--[[
	CombatController — Input de combate y feedback de golpes.
	Owner: Dev A (Combat).

	El arma es una Tool de inventario (ver WeaponVisualService). Con ella en la mano:
	  - Atacar:   Tool.Activated (click izquierdo / toque / R2) → CombatAttack("Attack", aim)
	              (gira al personaje hacia el cursor/toque, o la cámara con gamepad)
	  - Bloquear: mantener F / L2 / botón táctil              → CombatAttack("Block", true/false)
	  - Esquivar: Q / L1 / botón táctil                        → CombatAttack("Dash")
	Cooldowns, combo y aguante se predicen en el cliente solo para responder al instante;
	el servidor (CombatService) es quien valida.

	Remotes "CombatFeedback" → números de daño, destellos, sonidos y empuje (CombatEffects).
	Animaciones procedurales del brazo: CombatAnimations (para todos los personajes).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = script.Parent:WaitForChild("Util")
local CombatAnimations = require(Util:WaitForChild("CombatAnimations"))
local CombatEffects = require(Util:WaitForChild("CombatEffects"))

-- Mantener iguales a CombatService (el servidor valida con sus propios valores).
local COMBO_LENGTH = 3
local COMBO_WINDOW = 0.6
local DASH_COST = 25
local DASH_COOLDOWN = 1
local KNOCKBACK_DURATION = 0.15

-- Solo cliente
local DASH_SPEED = 60
local DASH_DURATION = 0.18

local ACTION_BLOCK = "CombatBlock"
local ACTION_DASH = "CombatDash"

local localPlayer = Players.LocalPlayer
local lastAttackAt = -math.huge
local lastDashAt = -math.huge
local combo = 0
local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local CombatController = {}

-- ── Estado local ──

local function getLocalHumanoid(): (Model?, Humanoid?, BasePart?)
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if humanoid then humanoid.RootPart else nil
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function isFree(humanoid: Humanoid): boolean
	local state = humanoid:GetAttribute("CombatState")
	return state ~= "Stunned" and state ~= "Dead" and humanoid:GetAttribute("Blocking") ~= true
end

local function getStamina(humanoid: Humanoid): number
	local value = humanoid:GetAttribute("Stamina")
	return if typeof(value) == "number" then value else 0
end

local function getWeapon(): WeaponData.WeaponStats
	local equipped = localPlayer:GetAttribute("EquippedWeapon")
	return WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil)
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

-- ── Acciones ──

local function attack(attackEvent: RemoteEvent)
	local character, humanoid, root = getLocalHumanoid()
	if not character or not humanoid or not root or not isFree(humanoid) then
		return
	end

	local weapon = getWeapon()
	local now = os.clock()
	if now - lastAttackAt < weapon.AttackCooldown then
		return
	end
	combo = if now - lastAttackAt <= weapon.AttackCooldown + COMBO_WINDOW then combo % COMBO_LENGTH + 1 else 1
	lastAttackAt = now

	local aim = getAimDirection(root)
	if aim then
		-- Girar al personaje hacia el golpe para que lo que se ve coincida con lo que valida el servidor.
		root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)
	end
	attackEvent:FireServer("Attack", aim)
	CombatAnimations.PlaySwing(character, combo)
	CombatEffects.PlaySound(if combo == COMBO_LENGTH then "Heavy" else "Swing", root)
end

local function dash(attackEvent: RemoteEvent)
	local _, humanoid, root = getLocalHumanoid()
	if not humanoid or not root or not isFree(humanoid) then
		return
	end
	local now = os.clock()
	if now - lastDashAt < DASH_COOLDOWN or getStamina(humanoid) < DASH_COST then
		return
	end
	lastDashAt = now

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit

	attackEvent:FireServer("Dash")
	CombatEffects.PushLocalCharacter(direction * DASH_SPEED, DASH_DURATION)
	CombatEffects.PlaySound("Swing", root)
end

local function bindActions(attackEvent: RemoteEvent)
	ContextActionService:BindAction(ACTION_BLOCK, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			attackEvent:FireServer("Block", true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			attackEvent:FireServer("Block", false)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL2)
	ContextActionService:SetTitle(ACTION_BLOCK, "Bloquear")
	ContextActionService:SetPosition(ACTION_BLOCK, UDim2.new(1, -170, 1, -150))

	ContextActionService:BindAction(ACTION_DASH, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			dash(attackEvent)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:SetTitle(ACTION_DASH, "Esquivar")
	ContextActionService:SetPosition(ACTION_DASH, UDim2.new(1, -230, 1, -90))
end

local function unbindActions(attackEvent: RemoteEvent)
	ContextActionService:UnbindAction(ACTION_BLOCK)
	ContextActionService:UnbindAction(ACTION_DASH)
	attackEvent:FireServer("Block", false)
end

-- Conecta la Tool del arma (Attribute "WeaponId") una sola vez por Tool.
local function hookWeaponTool(child: Instance, attackEvent: RemoteEvent)
	if not child:IsA("Tool") or child:GetAttribute("WeaponId") == nil or hookedTools[child] then
		return
	end
	hookedTools[child] = true

	child.Activated:Connect(function()
		if child.Parent == localPlayer.Character then
			attack(attackEvent)
		end
	end)
	child.Equipped:Connect(function()
		bindActions(attackEvent)
		local _, _, root = getLocalHumanoid()
		CombatEffects.PlaySound("Equip", root)
	end)
	child.Unequipped:Connect(function()
		unbindActions(attackEvent)
	end)

	if child.Parent == localPlayer.Character then
		bindActions(attackEvent) -- ya estaba en la mano al conectarla
	end
end

-- ── Personajes (animaciones de todos) ──

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid:GetAttributeChangedSignal("Blocking"):Connect(function()
		CombatAnimations.SetBlocking(character, humanoid:GetAttribute("Blocking") == true)
	end)

	-- El jugador local hace el swing al instante (predicción); el resto, cuando el servidor lo confirma.
	if player == localPlayer then
		return
	end
	humanoid:GetAttributeChangedSignal("CombatState"):Connect(function()
		if humanoid:GetAttribute("CombatState") ~= "Attacking" then
			return
		end
		local step = humanoid:GetAttribute("ComboStep")
		local stepNumber = if typeof(step) == "number" then step else 1
		CombatAnimations.PlaySwing(character, stepNumber)
		CombatEffects.PlaySound(if stepNumber == COMBO_LENGTH then "Heavy" else "Swing", humanoid.RootPart)
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

-- ── Feedback de golpes ──

local function onFeedback(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local target = payload.Target
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not target.Parent then
		return
	end

	local colors = CombatEffects.Colors
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local at = if humanoid then humanoid.RootPart else nil
	local damage = if typeof(payload.Damage) == "number" then math.floor(payload.Damage + 0.5) else 0
	local finisher = payload.Combo == COMBO_LENGTH
	local kind = payload.Kind

	if kind == "Parry" then
		CombatEffects.Flash(target, colors.Parry)
		CombatEffects.Popup(target, "¡Parry!", colors.Parry, true)
		CombatEffects.PlaySound("Parry", at)
		local attacker = payload.Attacker
		if attacker == localPlayer then
			combo = 0
		end
	elseif kind == "Blocked" then
		CombatEffects.Flash(target, colors.Blocked)
		CombatEffects.Popup(target, `-{damage} bloqueado`, colors.Blocked)
		CombatEffects.PlaySound("Block", at)
	elseif kind == "GuardBreak" then
		CombatEffects.Flash(target, colors.GuardBreak)
		CombatEffects.Popup(target, `¡Guardia rota! -{damage}`, colors.GuardBreak, true)
		CombatEffects.PlaySound("Hit", at)
	else
		CombatEffects.Flash(target, colors.Hit)
		CombatEffects.Popup(target, `-{damage}`, if finisher then colors.Finisher else colors.Damage, finisher or payload.Killed == true)
		CombatEffects.PlaySound(if finisher then "Heavy" else "Hit", at)
	end

	if target == localPlayer.Character then
		if kind ~= "Blocked" then
			combo = 0 -- un golpe recibido corta tu combo (igual que en el servidor)
		end
		local knockback = payload.Knockback
		if typeof(knockback) == "Vector3" then
			CombatEffects.PushLocalCharacter(knockback, KNOCKBACK_DURATION)
		end
	end
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
		combo = 0
	end
	-- También en la mochila, para conectar Equipped antes del primer equipamiento.
	local function watchBackpack(backpack: Instance)
		backpack.ChildAdded:Connect(function(child)
			hookWeaponTool(child, attackEvent)
		end)
		for _, child in backpack:GetChildren() do
			hookWeaponTool(child, attackEvent)
		end
	end
	localPlayer.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchBackpack(child)
		end
	end)
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		watchBackpack(backpack)
	end

	localPlayer.CharacterAdded:Connect(watchOwnCharacter)
	localPlayer.CharacterRemoving:Connect(function()
		ContextActionService:UnbindAction(ACTION_BLOCK)
		ContextActionService:UnbindAction(ACTION_DASH)
	end)
	if localPlayer.Character then
		task.spawn(watchOwnCharacter, localPlayer.Character)
	end

	feedbackEvent.OnClientEvent:Connect(onFeedback)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(watchPlayer, player)
	end
end

return CombatController
