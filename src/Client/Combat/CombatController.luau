--!strict
--[[
	CombatController — Input de combate y feedback visceral en el cliente.
	Owner: Dev A (Combat).

	El arma es una Tool de inventario (ver WeaponVisualService). Con ella en la mano:
	  - Atacar:   Tool.Activated (click / toque / R2) → CombatAttack("Attack", aim)
	              Gira al personaje hacia el cursor/toque (o la cámara con gamepad).
	  - Guardia:  mantener F / L2 / botón táctil → CombatAttack("Block", true/false)
	              Los primeros 0,22 s son parry; soltar sin desviar nada pone el parry en cooldown.
	  - Dash:     Q / L1 / botón táctil → CombatAttack("Dash"). Dirección relativa a la cámara
	              (adelante/atrás/izquierda/derecha; sin input = atrás). Física local con curva
	              explosiva que decae en 0,25 s; el servidor da los i-frames.
	El servidor (CombatService) valida todo. Acá solo se predicen cooldowns para no spamear.

	Animaciones: se disparan con Humanoid.CombatState de CADA personaje (Windup → carga,
	Attacking → tajo, Parrying/Blocking → guardia, Stunned/PostureBroken → tambaleo).

	"CombatFeedback" → número/texto, destello, sonido, hitstop (congela las animaciones de
	atacante y objetivo) y, si el jugador local está involucrado, sacudida de cámara.
	Parry: destello de luz + chispas en el punto medio. Guard break: efecto rojo intenso.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Util = script.Parent:WaitForChild("Util")
local CombatAnimations = require(Util:WaitForChild("CombatAnimations"))
local CombatEffects = require(Util:WaitForChild("CombatEffects"))

-- Mantener iguales a CombatService (el servidor valida con sus propios valores).
local COMBO_LENGTH = 3
local DASH_COOLDOWN = 2
local DASH_DURATION = 0.25

-- Solo cliente
local DASH_SPEED = 64 -- velocidad inicial del dash (studs/s)
local DASH_MAX_ACCEL = 2000
local FREE_STATES: { [string]: boolean } = { Idle = true, Blocking = true }

-- Hitstop (s) y sacudida de cámara (studs, s) por tipo de impacto
local HITSTOP = {
	Hit = 0.06,
	Finisher = 0.09,
	Blocked = 0.04,
	Parry = 0.14,
	GuardBreak = 0.12,
}
local SHAKE: { [string]: { number } } = {
	Hit = { 0.22, 0.18 },
	Finisher = { 0.38, 0.25 },
	Blocked = { 0.1, 0.12 },
	Parry = { 0.6, 0.3 },
	GuardBreak = { 0.7, 0.4 },
}

local ACTION_BLOCK = "CombatBlock"
local ACTION_DASH = "CombatDash"

local localPlayer = Players.LocalPlayer
local lastAttackAt = -math.huge
local lastDashAt = -math.huge
local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local CombatController = {}

-- ══════════════════ Helpers ══════════════════

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

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
	return typeof(state) == "string" and FREE_STATES[state] == true
end

local function weaponOf(player: Player?): WeaponData.WeaponStats
	local equipped = if player then player:GetAttribute("EquippedWeapon") else nil
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
	local horizontal = flat(direction)
	return if horizontal.Magnitude > 0.1 then horizontal.Unit else nil
end

-- Dirección del dash relativa a la cámara, ajustada a 4 ejes. Sin input: hacia atrás.
local function getDashDirection(humanoid: Humanoid, root: BasePart): Vector3
	local camera = workspace.CurrentCamera
	local look = flat(if camera then camera.CFrame.LookVector else root.CFrame.LookVector)
	if look.Magnitude < 0.1 then
		look = flat(root.CFrame.LookVector)
	end
	look = look.Unit
	local right = Vector3.new(-look.Z, 0, look.X)

	local move = flat(humanoid.MoveDirection)
	if move.Magnitude < 0.1 then
		return -look
	end
	local forwardAmount = move:Dot(look)
	local rightAmount = move:Dot(right)
	if math.abs(forwardAmount) >= math.abs(rightAmount) then
		return if forwardAmount > 0 then look else -look
	end
	return if rightAmount > 0 then right else -right
end

-- ══════════════════ Física del dash (local: el cliente es dueño de su personaje) ══════════════════

local function applyDashPhysics(root: BasePart, direction: Vector3)
	local previous = root:FindFirstChild("CombatDash")
	if previous then
		previous:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatDash"

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane -- Y libre: no vuela en rampas
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * DASH_SPEED
	mover.MaxForce = root.AssemblyMass * DASH_MAX_ACCEL
	mover.Parent = attachment
	attachment.Parent = root

	local elapsed = 0
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= DASH_DURATION or not attachment.Parent then
			if connection then
				connection:Disconnect()
			end
			attachment:Destroy()
			return
		end
		-- Arranque explosivo y frenado por fricción (curva cuadrática).
		local falloff = (1 - elapsed / DASH_DURATION) ^ 2
		mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (DASH_SPEED * falloff)
	end)
end

-- ══════════════════ Acciones ══════════════════

local function attack(attackEvent: RemoteEvent)
	local _, humanoid, root = getLocalHumanoid()
	if not humanoid or not root or not isFree(humanoid) then
		return
	end
	local now = os.clock()
	if now - lastAttackAt < weaponOf(localPlayer).AttackCooldown then
		return
	end
	lastAttackAt = now

	local aim = getAimDirection(root)
	if aim then
		-- Girar al personaje hacia el golpe para que lo que se ve coincida con lo que valida el servidor.
		root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)
	end
	attackEvent:FireServer("Attack", aim)
end

local function dash(attackEvent: RemoteEvent)
	local _, humanoid, root = getLocalHumanoid()
	if not humanoid or not root or not isFree(humanoid) then
		return
	end
	local now = os.clock()
	if now - lastDashAt < DASH_COOLDOWN then
		return
	end
	lastDashAt = now

	attackEvent:FireServer("Dash")
	applyDashPhysics(root, getDashDirection(humanoid, root))
	CombatEffects.PlaySound("Dash", root)
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
	ContextActionService:SetTitle(ACTION_BLOCK, "Guardia")
	ContextActionService:SetPosition(ACTION_BLOCK, UDim2.new(1, -170, 1, -150))

	ContextActionService:BindAction(ACTION_DASH, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			dash(attackEvent)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:SetTitle(ACTION_DASH, "Dash")
	ContextActionService:SetPosition(ACTION_DASH, UDim2.new(1, -230, 1, -90))
end

local function unbindActions(attackEvent: RemoteEvent?)
	ContextActionService:UnbindAction(ACTION_BLOCK)
	ContextActionService:UnbindAction(ACTION_DASH)
	if attackEvent then
		attackEvent:FireServer("Block", false)
	end
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

-- ══════════════════ Animaciones por estado (todos los personajes) ══════════════════

local function onCombatState(player: Player, character: Model, humanoid: Humanoid, previous: string?)
	local state = humanoid:GetAttribute("CombatState")
	local step = humanoid:GetAttribute("ComboStep")
	local combo = if typeof(step) == "number" and step >= 1 then step else 1

	if state == "Windup" then
		CombatAnimations.SetGuard(character, false)
		CombatAnimations.PlayWindup(character, combo, weaponOf(player).WindupTime)
	elseif state == "Attacking" then
		CombatAnimations.PlaySlash(character, combo)
		CombatEffects.PlaySound(if combo == COMBO_LENGTH then "Heavy" else "Swing", humanoid.RootPart)
	elseif state == "Parrying" or state == "Blocking" then
		CombatAnimations.SetGuard(character, true)
	elseif state == "Stunned" or state == "PostureBroken" then
		CombatAnimations.Stagger(character, state == "PostureBroken")
	else
		-- Idle / Recovery / Dashing / Dead
		CombatAnimations.SetGuard(character, false)
		if previous == "Stunned" or previous == "PostureBroken" or previous == "Windup" then
			CombatAnimations.Reset(character)
		end
	end
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local previous: string? = nil
	humanoid:GetAttributeChangedSignal("CombatState"):Connect(function()
		onCombatState(player, character, humanoid, previous)
		local state = humanoid:GetAttribute("CombatState")
		previous = if typeof(state) == "string" then state else nil
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

-- ══════════════════ Feedback de impactos ══════════════════

local function rootOf(model: Model?): BasePart?
	local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
	return if humanoid then humanoid.RootPart else nil
end

local function hitstop(duration: number, attackerCharacter: Model?, target: Model)
	if attackerCharacter then
		CombatAnimations.Freeze(attackerCharacter, duration)
	end
	CombatAnimations.Freeze(target, duration)
end

local function onFeedback(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local target = payload.Target
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not target.Parent then
		return
	end
	local attacker = payload.Attacker
	local attackerPlayer: Player? = if typeof(attacker) == "Instance" and attacker:IsA("Player") then attacker else nil
	local attackerCharacter = if attackerPlayer then attackerPlayer.Character else nil

	local colors = CombatEffects.Colors
	local targetRoot = rootOf(target)
	local damage = if typeof(payload.Damage) == "number" then math.floor(payload.Damage + 0.5) else 0
	local finisher = payload.Combo == COMBO_LENGTH
	local involved = attackerPlayer == localPlayer or target == localPlayer.Character
	local kind = payload.Kind
	local shakeKey: string? = nil

	if kind == "Dodge" then
		CombatEffects.Popup(target, "¡Esquivado!", colors.Info)
		return
	elseif kind == "Parry" then
		local attackerRoot = rootOf(attackerCharacter)
		local midpoint = if attackerRoot and targetRoot
			then (attackerRoot.Position + targetRoot.Position) / 2 + Vector3.new(0, 1, 0)
			elseif targetRoot then targetRoot.Position
			else target:GetPivot().Position
		CombatEffects.ParrySpark(midpoint)
		CombatEffects.Popup(target, "¡PARRY!", colors.Parry, true)
		CombatEffects.PlaySound("Parry", targetRoot)
		hitstop(HITSTOP.Parry, attackerCharacter, target)
		shakeKey = "Parry"
	elseif kind == "Blocked" then
		CombatEffects.Flash(target, colors.Blocked)
		CombatEffects.Popup(target, "Bloqueado", colors.Blocked)
		CombatEffects.PlaySound("Block", targetRoot)
		hitstop(HITSTOP.Blocked, attackerCharacter, target)
		shakeKey = "Blocked"
	elseif kind == "GuardBreak" then
		CombatEffects.GuardBreakBurst(target)
		CombatEffects.Popup(target, "¡GUARDIA ROTA!", colors.GuardBreak, true)
		CombatEffects.PlaySound("GuardBreak", targetRoot)
		hitstop(HITSTOP.GuardBreak, attackerCharacter, target)
		shakeKey = "GuardBreak"
	else
		CombatEffects.Flash(target, colors.Hit)
		CombatEffects.Popup(target, `-{damage}`, if finisher then colors.Finisher else colors.Damage, finisher or payload.Killed == true)
		CombatEffects.PlaySound(if finisher then "Heavy" else "Hit", targetRoot)
		if payload.Interrupted == true then
			CombatEffects.Popup(target, "¡Interrumpido!", colors.Info)
		elseif payload.Hyperarmor == true then
			CombatEffects.Popup(target, "Hyperarmor", colors.Finisher)
		end
		hitstop(if finisher then HITSTOP.Finisher else HITSTOP.Hit, attackerCharacter, target)
		shakeKey = if finisher then "Finisher" else "Hit"
	end

	if involved and shakeKey then
		local shake = SHAKE[shakeKey]
		CombatEffects.Shake(shake[1], shake[2])
	end
end

-- ══════════════════ Init ══════════════════

function CombatController:Init()
	local attackEvent = Remotes.GetEvent("CombatAttack")
	local feedbackEvent = Remotes.GetEvent("CombatFeedback")

	-- La Tool se equipa moviéndose al personaje; también se vigila la mochila para
	-- conectar Equipped antes del primer equipamiento.
	local function watchContainer(container: Instance)
		container.ChildAdded:Connect(function(child)
			hookWeaponTool(child, attackEvent)
		end)
		for _, child in container:GetChildren() do
			hookWeaponTool(child, attackEvent)
		end
	end
	localPlayer.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchContainer(child)
		end
	end)
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(backpack)
	end

	localPlayer.CharacterAdded:Connect(watchContainer)
	localPlayer.CharacterRemoving:Connect(function()
		unbindActions(nil)
	end)
	if localPlayer.Character then
		task.spawn(watchContainer, localPlayer.Character)
	end

	feedbackEvent.OnClientEvent:Connect(onFeedback)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(watchPlayer, player)
	end
end

return CombatController
