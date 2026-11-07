--!strict
--[[
	DungeonService — Mazmorra con oleadas de guardianes.
	Owner: Dev B (Economía/Mazmorra).

	- Oleadas: al morir todos los guardianes empieza la siguiente, con más enemigos,
	  más vida, más daño y más oro por baja. Si la mazmorra queda vacía un rato, vuelve a la oleada 1.
	- IA (servidor): cada guardián persigue al jugador vivo más cercano dentro de la sala
	  y lo golpea cuerpo a cuerpo con un aviso previo (se ilumina antes de pegar).
	- Barra de vida: la dibuja HealthBarController (cliente, Combat) con el nombre del Model,
	  que incluye la oleada ("Guardián · Oleada N").

	Attributes que LEE: Humanoid.CombatState ("Stunned" frena al guardián), Humanoid.LastAttacker
	(recompensa), Player.InDuel.
]]
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Remotes)
local Data = require(script.Parent.DataService)
local DungeonService = {}

-- ── Tuning ──
local ARENA_SIZE = 54
local AI_TICK = 0.15
local WAVE_DELAY = 4 -- s entre oleadas
local EMPTY_RESET_TIME = 20 -- s sin jugadores para volver a la oleada 1
local ATTACK_RANGE = 4.5
local ATTACK_WINDUP = 0.4 -- s de aviso antes del golpe
local ATTACK_COOLDOWN = 1.4
local WARN_COLOR = Color3.fromRGB(255, 90, 60)

type WaveStats = { count: number, health: number, damage: number, speed: number, gold: number }

local function waveStats(wave: number): WaveStats
	local n = wave - 1
	return {
		count = math.min(3 + math.floor(n / 2) + (if n > 0 then 1 else 0), 10),
		health = math.floor(100 * (1 + 0.3 * n)),
		damage = 8 + 3 * n,
		speed = math.min(9 + n, 15),
		gold = 25 + 10 * n,
	}
end

type Enemy = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	torso: BasePart,
	stats: WaveStats,
	nextAttack: number,
	attacking: boolean,
}

local enemies: { Enemy } = {}
local wave = 0
local waveToken = 0
local center = Vector3.zero

local function part(parent: Instance, name: string, position: Vector3, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Parent = parent
	return p
end

local function inArena(position: Vector3): boolean
	local offset = position - center
	local half = ARENA_SIZE / 2
	return math.abs(offset.X) <= half and math.abs(offset.Z) <= half and offset.Y > -5 and offset.Y < 25
end

local function playersInArena(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		local root = if hum then hum.RootPart else nil
		if hum and root and hum.Health > 0 and player:GetAttribute("InDuel") ~= true and inArena(root.Position) then
			table.insert(list, player)
		end
	end
	return list
end

local function notifyArena(message: string)
	for _, player in playersInArena() do
		Remotes.GetEvent("Notify"):FireClient(player, message)
	end
end

local function reward(humanoid: Humanoid, gold: number)
	local attacker = humanoid:GetAttribute("LastAttacker")
	if typeof(attacker) ~= "number" or attacker == 0 or attacker % 1 ~= 0 then return end
	local player = Players:GetPlayerByUserId(attacker)
	if not player then return end
	-- Solo oro: las armas se consiguen únicamente en la tienda (no hay drops).
	if not Data.ChangeGold(player, gold) then return end
	Remotes.GetEvent("Notify"):FireClient(player, `+{gold} de oro`)
end

local startWave: (number) -> ()

local function onEnemyDied(enemy: Enemy, token: number)
	local index = table.find(enemies, enemy)
	if index then table.remove(enemies, index) end
	task.delay(2, function() enemy.model:Destroy() end)

	local waveCleared = token == waveToken and #enemies == 0
	if waveCleared then
		local bonus = 10 * wave
		for _, player in playersInArena() do
			if Data.Profile(player) and Data.ChangeGold(player, bonus) then
				Remotes.GetEvent("Notify"):FireClient(player, `¡Oleada {wave} superada! +{bonus} de oro`)
			end
		end
	end
	-- Oro por la baja (solo para quien dio el último golpe).
	reward(enemy.humanoid, enemy.stats.gold)

	if not waveCleared then return end
	local cleared = wave
	task.delay(WAVE_DELAY, function()
		if token == waveToken then startWave(cleared + 1) end
	end)
end

local function spawnEnemy(parent: Instance, position: Vector3, stats: WaveStats, token: number)
	local model = Instance.new("Model")
	model.Name = `Guardián · Oleada {wave}` -- HealthBarController (cliente) muestra este nombre con la barra
	-- El torso apoya en el piso; el root flota HipHeight por encima para que el Humanoid camine.
	local root = part(model, "HumanoidRootPart", position, Vector3.new(2, 2, 1), Color3.new())
	root.Transparency = 1
	local torso = part(model, "Torso", position, Vector3.new(3, 3, 2), Color3.fromRGB(83, 104, 102))
	local head = part(model, "Head", position + Vector3.new(0, 2.35, 0), Vector3.new(1.8, 1.7, 1.7), Color3.fromRGB(133, 155, 138))
	for _, piece in {torso, head} do
		local base = if piece == torso then root else torso
		local joint = Instance.new("Motor6D")
		joint.Name = if piece == torso then "RootJoint" else "Neck"
		joint.Part0 = base
		joint.Part1 = piece
		joint.C0 = base.CFrame:ToObjectSpace(piece.CFrame)
		joint.Parent = base
		piece.Anchored = false
		piece.CanCollide = false
	end
	root.Anchored = false
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 0.5
	humanoid.MaxHealth = stats.health
	humanoid.Health = stats.health
	humanoid.WalkSpeed = stats.speed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	local enemy: Enemy = {
		model = model, humanoid = humanoid, root = root, torso = torso,
		stats = stats, nextAttack = 0, attacking = false,
	}
	table.insert(enemies, enemy)
	humanoid.Died:Once(function() onEnemyDied(enemy, token) end)

	model.Parent = parent
	root:SetNetworkOwner(nil) -- el servidor mueve a los guardianes
end

local function closestTarget(from: Vector3, candidates: { Player }): (Humanoid?, BasePart?, number)
	local bestHum, bestRoot, bestDist = nil, nil, math.huge
	for _, player in candidates do
		local char = player.Character :: Model
		local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
		local root = hum.RootPart :: BasePart
		local dist = (root.Position - from).Magnitude
		if dist < bestDist then
			bestHum, bestRoot, bestDist = hum, root, dist
		end
	end
	return bestHum, bestRoot, bestDist
end

local function attack(enemy: Enemy, target: Humanoid, targetRoot: BasePart)
	enemy.attacking = true
	enemy.nextAttack = os.clock() + ATTACK_COOLDOWN
	local original = enemy.torso.Color
	enemy.torso.Color = WARN_COLOR
	task.delay(ATTACK_WINDUP, function()
		enemy.attacking = false
		if enemy.torso.Parent then enemy.torso.Color = original end
		local hum = enemy.humanoid
		if hum.Health <= 0 or hum:GetAttribute("CombatState") == "Stunned" then return end
		if target.Health <= 0 or not targetRoot.Parent then return end
		-- El jugador puede esquivar alejándose durante el aviso.
		if (targetRoot.Position - enemy.root.Position).Magnitude > ATTACK_RANGE + 1 then return end
		local victim = Players:GetPlayerFromCharacter(target.Parent)
		if not victim or victim:GetAttribute("InDuel") == true then return end
		local before = target.Health
		target:TakeDamage(enemy.stats.damage)
		if target.Health < before then
			Remotes.GetEvent("CombatFeedback"):FireClient(victim, {
				Target = target.Parent, Damage = before - target.Health, Killed = target.Health <= 0,
			})
		end
	end)
end

local function updateEnemies()
	local targets = playersInArena()
	for _, enemy in enemies do
		local hum = enemy.humanoid
		if hum.Health <= 0 or not enemy.root.Parent then continue end
		local stunned = hum:GetAttribute("CombatState") == "Stunned"
		local target, targetRoot, dist = closestTarget(enemy.root.Position, targets)
		if not target or not targetRoot or stunned or enemy.attacking then
			hum:Move(Vector3.zero)
			continue
		end
		if dist > ATTACK_RANGE - 1 then
			hum:MoveTo(targetRoot.Position)
		else
			hum:Move(Vector3.zero)
			local flat = Vector3.new(targetRoot.Position.X, enemy.root.Position.Y, targetRoot.Position.Z)
			if (flat - enemy.root.Position).Magnitude > 0.1 then
				enemy.root.CFrame = CFrame.lookAt(enemy.root.Position, flat)
			end
		end
		if dist <= ATTACK_RANGE and os.clock() >= enemy.nextAttack then
			attack(enemy, target, targetRoot)
		end
	end
end

local function portal(parent: Instance, name: string, pos: Vector3, target: Vector3, entering: boolean)
	local stone = part(parent, name, pos, Vector3.new(4, 4, 2), Color3.fromRGB(64, 104, 119))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Mazmorra"
	prompt.ActionText = name
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = stone
	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if not char or not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then return end
		if (root.Position - stone.Position).Magnitude > prompt.MaxActivationDistance + 1 then return end
		if entering and (player:GetAttribute("InDuel") == true or not Data.Profile(player)) then
			Remotes.GetEvent("Notify"):FireClient(player, "Entrada bloqueada durante un duelo o mientras se carga tu inventario.")
			return
		end
		char:PivotTo(CFrame.new(target))
		if entering then
			Remotes.GetEvent("Notify"):FireClient(player, `Oleada {wave} en curso`)
		end
	end)
end

function DungeonService:Init()
	local folder = Instance.new("Folder")
	folder.Name = "Mazmorra"
	folder.Parent = workspace
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	center = origin + Vector3.new(0, 160, 0)
	local entrance = origin + Vector3.new(10, 2, 0)
	part(folder, "Piso", center, Vector3.new(ARENA_SIZE, 2, ARENA_SIZE), Color3.fromRGB(64, 70, 75))
	-- Paredes bajas para que nadie se caiga (ni guardianes ni jugadores).
	for _, side in {Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)} do
		local size = if side.X ~= 0 then Vector3.new(2, 6, ARENA_SIZE) else Vector3.new(ARENA_SIZE, 6, 2)
		local wall = part(folder, "Pared", center + side * (ARENA_SIZE / 2 + 1) + Vector3.new(0, 3, 0), size, Color3.fromRGB(52, 57, 61))
		wall.Transparency = 0.3
	end
	portal(folder, "Entrar", entrance, center + Vector3.new(0, 5, 15), true)
	portal(folder, "Salir", center + Vector3.new(0, 3, 21), entrance + Vector3.new(0, 2, 5), false)

	startWave = function(number: number)
		waveToken += 1
		wave = number
		local stats = waveStats(number)
		for i = 1, stats.count do
			local x = (i - (stats.count + 1) / 2) * 4.5
			local z = -8 - (i % 2) * 5
			spawnEnemy(folder, center + Vector3.new(x, 2.5, z), stats, waveToken)
		end
		notifyArena(`Oleada {number}: {stats.count} guardianes`)
	end
	startWave(1)

	-- Si nadie está en la mazmorra durante un rato, se reinicia en la oleada 1.
	local emptySince: number? = nil
	task.spawn(function()
		while true do
			task.wait(AI_TICK)
			updateEnemies()
			if #playersInArena() > 0 then
				emptySince = nil
			elseif wave > 1 then
				emptySince = emptySince or os.clock()
				if os.clock() - (emptySince :: number) >= EMPTY_RESET_TIME then
					emptySince = nil
					for _, enemy in table.clone(enemies) do enemy.model:Destroy() end
					table.clear(enemies)
					startWave(1)
				end
			end
		end
	end)
end

return DungeonService
