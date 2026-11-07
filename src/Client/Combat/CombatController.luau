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

	Animaciones y efectos: se disparan con Humanoid.CombatState de CADA personaje
	(CombatAnimations = poses de cuerpo completo, CombatVisuals = estela, brillos, dash):
	  Windup → carga + destello en la punta (rojo si es Heavy) · Attacking → tajo + estela
	  Parrying → desvío + espada blanca · Blocking → guardia + contorno azul
	  Stunned → tambaleo (retroceso si fue por parry) · PostureBroken → rodilla al piso + pulso rojo
	  Dashing → inclinación, imágenes residuales, polvo y golpe de FOV.

	"CombatFeedback" → número/texto, destello, sonido, hitstop (congela las animaciones de
	atacante y objetivo) y, si el jugador local está involucrado, sacudida de cámara.
	Parry: destello de luz + chispas en el punto medio. Guard break: efecto rojo intenso.
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
local CombatVisuals = require(Util:WaitForChild("CombatVisuals"))

-- Mantener iguales a CombatService (el servidor valida con sus propios valores).
local COMBO_LENGTH = 3
local DASH_COOLDOWN = 2
local DASH_DURATION = 0.25
local PARRY_WINDOW = 0.22

-- Solo cliente
local DASH_SPEED = 64 -- velocidad inicial del dash (studs/s)
local DASH_MAX_ACCEL = 2000
local FREE_STATES: { [string]: boolean } = { Idle = true, Blocking = true }
local TRAIL_COLORS = { -- estela de la hoja por golpe del combo
	Color3.fromRGB(235, 240, 255),
	Color3.fromRGB(190, 225, 255),
	Color3.fromRGB(255, 185, 80),
}
local SLASH_TRAIL_TIME = 0.2

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
	local character, humanoid, root = getLocalHumanoid()
	if not character or not humanoid or not root or not isFree(humanoid) then
		return
	end
	local now = os.clock()
	if now - lastDashAt < DASH_COOLDOWN then
		return
	end
	lastDashAt = now

	local direction = getDashDirection(humanoid, root)
	attackEvent:FireServer("Dash")
	CombatEffects.DashMove(root, direction, DASH_SPEED, DASH_DURATION, DASH_MAX_ACCEL)
	CombatEffects.PlaySound("Dash", root)
	-- Visual inmediato para el jugador local (los demás lo ven al llegar el estado "Dashing").
	CombatAnimations.PlayDash(character, root.CFrame:VectorToObjectSpace(direction), DASH_DURATION)
	CombatVisuals.Dash(character, direction, DASH_DURATION)
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

-- ══════════════════ Animaciones y efectos por estado (todos los personajes) ══════════════════

local function hasWeaponTool(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("WeaponId") ~= nil
end

local function onCombatState(player: Player, character: Model, humanoid: Humanoid, previous: string?)
	local state = humanoid:GetAttribute("CombatState")
	local step = humanoid:GetAttribute("ComboStep")
	local combo = if typeof(step) == "number" and step >= 1 then step else 1
	local weapon = weaponOf(player)

	-- Apagar efectos del estado anterior.
	if (previous == "Blocking" or previous == "Parrying") and state ~= "Blocking" and state ~= "Parrying" then
		CombatVisuals.SetGuardGlow(character, false)
	end
	if previous == "PostureBroken" and state ~= "PostureBroken" then
		CombatVisuals.SetBrokenPulse(character, false)
	end

	if state == "Windup" then
		CombatAnimations.PlayWindup(character, combo, weapon.WindupTime)
		CombatVisuals.WindupGlint(character, weapon.Weight == "Heavy")
	elseif state == "Attacking" then
		CombatAnimations.PlaySlash(character, combo, weapon.Weight)
		CombatVisuals.SlashTrail(character, TRAIL_COLORS[combo] or TRAIL_COLORS[1], SLASH_TRAIL_TIME)
		CombatEffects.PlaySound(if combo == COMBO_LENGTH then "Heavy" else "Swing", humanoid.RootPart)
	elseif state == "Parrying" then
		CombatAnimations.SetMode(character, "Parry")
		CombatVisuals.ParryWindow(character, PARRY_WINDOW)
	elseif state == "Blocking" then
		CombatAnimations.SetMode(character, "Block")
		CombatVisuals.SetGuardGlow(character, true)
	elseif state == "Stunned" then
		CombatAnimations.SetMode(character, "Stunned")
	elseif state == "PostureBroken" then
		CombatAnimations.SetMode(character, "Broken")
		CombatVisuals.SetBrokenPulse(character, true)
	elseif state == "Dashing" then
		local root = humanoid.RootPart
		CombatAnimations.SetMode(character, "None")
		if root and player ~= localPlayer then -- el local ya lo mostró al apretar Q
			local velocity = flat(root.AssemblyLinearVelocity)
			local direction = if velocity.Magnitude > 2 then velocity.Unit else -flat(root.CFrame.LookVector).Unit
			CombatAnimations.PlayDash(character, root.CFrame:VectorToObjectSpace(direction), DASH_DURATION)
			CombatVisuals.Dash(character, direction, DASH_DURATION)
		end
	elseif state == "Dead" or previous == "Windup" then
		CombatAnimations.Reset(character) -- muerte o ataque cancelado sin pasar por otro estado
	else
		CombatAnimations.SetMode(character, "None") -- Idle / Recovery
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

	-- Pose "Listo" con el arma en la mano.
	local function refreshArmed()
		CombatAnimations.SetArmed(character, hasWeaponTool(character))
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(refreshArmed)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			refreshArmed()
		end
	end)
	refreshArmed()
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

local function midpoint(a: BasePart?, b: BasePart?, fallback: Model): Vector3
	if a and b then
		return (a.Position + b.Position) / 2 + Vector3.new(0, 1, 0)
	end
	return if b then b.Position else fallback:GetPivot().Position
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
		CombatEffects.ParrySpark(midpoint(rootOf(attackerCharacter), targetRoot, target))
		CombatAnimations.PlayImpact(target, "ParryFlick")
		local attackerHumanoid = if attackerCharacter then attackerCharacter:FindFirstChildOfClass("Humanoid") else nil
		if attackerCharacter and attackerHumanoid and attackerHumanoid:GetAttribute("CombatState") ~= "PostureBroken" then
			CombatAnimations.PlayRecoil(attackerCharacter)
		end
		CombatEffects.Popup(target, "¡PARRY!", colors.Parry, true)
		CombatEffects.PlaySound("Parry", targetRoot)
		hitstop(HITSTOP.Parry, attackerCharacter, target)
		shakeKey = "Parry"
	elseif kind == "Blocked" then
		CombatEffects.Flash(target, colors.Blocked)
		CombatEffects.Popup(target, "Bloqueado", colors.Blocked)
		CombatAnimations.PlayImpact(target, "BlockJolt")
		CombatVisuals.HitSpark(midpoint(rootOf(attackerCharacter), targetRoot, target), colors.Blocked, 14)
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
		if targetRoot then
			CombatVisuals.HitSpark(targetRoot.Position + Vector3.new(0, 0.5, 0), colors.Hit, if finisher then 18 else 10)
		end
		CombatEffects.Popup(target, `-{damage}`, if finisher then colors.Finisher else colors.Damage, finisher or payload.Killed == true)
		CombatEffects.PlaySound(if finisher then "Heavy" else "Hit", targetRoot)
		if payload.Interrupted == true then
			CombatEffects.Popup(target, "¡Interrumpido!", colors.Info)
		elseif payload.Hyperarmor == true then
			CombatEffects.Popup(target, "Hyperarmor", colors.Finisher)
			CombatAnimations.PlayImpact(target, "Flinch")
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
