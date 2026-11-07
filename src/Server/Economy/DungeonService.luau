--!strict
--[[
	DungeonService — Mazmorras individuales con oleadas de guardianes.
	Owner: Dev B (Economía/Mazmorra).

	- Cada jugador que cruza el arco del lobby recibe SU PROPIA sala (Room), armada solo para él
	  en un lugar aparte del cielo, y empieza siempre en la oleada 1. Nadie más entra ni la ve
	  pelear: el progreso de un jugador no afecta al de los demás.
	- No hay portal de salida: se sale con el botón "Exit" del HUD (remote LeaveDungeon, lo manda
	  UIController). La sala se cierra (y se borra) cuando el dueño toca "Exit", cuando pasa ROOM_TIMEOUT
	  segundos fuera de ella (por ejemplo, porque murió y reapareció en el lobby) o cuando se va del juego.
	  Volver a entrar arranca de nuevo en la oleada 1.
	- Oleadas: al morir todos los guardianes empieza la siguiente, con más enemigos,
	  más vida, más daño y más oro por baja.
	- Tipos de guardián (KINDS): normal, centinela veloz (rápido y frágil, desde la oleada 2) y
	  coloso (lento y muy resistente, desde la oleada 3). Cada BOSS_EVERY oleadas aparece un jefe,
	  más grande, con un golpe en área que se anuncia con un círculo rojo en el piso.
	- IA (servidor): los guardianes persiguen al dueño de la sala y lo golpean cuerpo a cuerpo
	  con un aviso previo (se iluminan antes de pegar).
	- Al morir, el guardián se desarma en piedras.
	- Ambientación: sala cerrada de piedra con antorchas; portales con partículas.
	  La iluminación oscura de adentro la aplica UIController (cliente) al entrar.
	- Barra de vida: la dibuja HealthBarController (cliente, Combat) con el nombre del Model,
	  que incluye el tipo y la oleada ("Coloso · Oleada 4").

	- Progreso: cada baja suma a Guardianes; llegar a una oleada cuenta para Mejor oleada.
	- Oro: cada baja manda Notify {Kind = "Gold", Amount, Position} al jugador
	  (UIController muestra el "+N" flotando y las monedas volando al contador).

	Attributes que LEE: Humanoid.CombatState ("Stunned" frena al guardián), Humanoid.LastAttacker
	(recompensa), Player.InDuel.

	Attributes que ESCRIBE en la carpeta de cada sala, workspace.Mazmorra.Sala_<UserId>
	(los lee UIController del dueño para el panel):
	  Wave        : number  — oleada actual (0 = todavía no empezó)
	  EnemiesLeft : number  — guardianes vivos de la oleada
	  NextWaveAt  : number  — workspace:GetServerTimeNow() en que empieza la próxima oleada (0 = ninguna)
	  Center      : Vector3 — centro de la sala; Size: number — lado de la sala (para saber si estás adentro)
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Data = require(script.Parent:WaitForChild("DataService"))
local Sounds = require(script.Parent:WaitForChild("Util"):WaitForChild("Sounds"))
local DungeonService = {}
local random = Random.new()

-- ── Tuning ──
local ARENA_SIZE = 54
local ROOM_HEIGHT = 20 -- alto de las paredes hasta el techo
local ROOM_SPACING = 160 -- distancia entre salas (lejos para que no se escuchen entre sí)
local ROOM_TIMEOUT = 8 -- s que el dueño puede estar fuera de su sala antes de que se cierre
local START_DELAY = 3 -- s desde que entrás hasta que aparece la oleada 1
local AI_TICK = 0.15
local WAVE_DELAY = 4 -- s entre oleadas
local ATTACK_WINDUP = 0.4 -- s de aviso antes del golpe
local WARN_COLOR = Color3.fromRGB(255, 90, 60)
local BOSS_EVERY = 5
local SLAM_WINDUP = 1.2 -- s que el círculo rojo avisa antes del golpe en área
local SLAM_RADIUS = 11
local SLAM_COOLDOWN = 6
local SLAM_DAMAGE_MULT = 1.6
local SLAM_COLOR = Color3.fromRGB(255, 60, 40)

-- Números base de la oleada; cada tipo de guardián los multiplica.
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

type Kind = {
	name: string,
	scale: number, -- tamaño del cuerpo
	health: number, damage: number, speed: number, gold: number, -- multiplicadores sobre WaveStats
	cooldown: number, -- s entre golpes cuerpo a cuerpo
	body: Color3, head: Color3, eyes: Color3,
	boss: boolean,
}

local KINDS: { [string]: Kind } = {
	Guardian = {
		name = "Guardián", scale = 1, health = 1, damage = 1, speed = 1, gold = 1, cooldown = 1.4,
		body = Color3.fromRGB(83, 104, 102), head = Color3.fromRGB(133, 155, 138), eyes = Color3.fromRGB(120, 230, 255),
		boss = false,
	},
	Swift = {
		name = "Centinela veloz", scale = 0.75, health = 0.5, damage = 0.6, speed = 1.6, gold = 0.8, cooldown = 0.9,
		body = Color3.fromRGB(70, 92, 120), head = Color3.fromRGB(120, 150, 185), eyes = Color3.fromRGB(255, 240, 120),
		boss = false,
	},
	Colossus = {
		name = "Coloso", scale = 1.45, health = 2.4, damage = 1.5, speed = 0.6, gold = 2, cooldown = 2,
		body = Color3.fromRGB(96, 84, 74), head = Color3.fromRGB(140, 122, 104), eyes = Color3.fromRGB(255, 150, 60),
		boss = false,
	},
	Boss = {
		name = "Gólem ancestral (jefe)", scale = 2.2, health = 8, damage = 1.6, speed = 0.75, gold = 10, cooldown = 1.8,
		body = Color3.fromRGB(58, 52, 66), head = Color3.fromRGB(104, 92, 120), eyes = Color3.fromRGB(255, 70, 70),
		boss = true,
	},
}

-- Sala individual de un jugador.
type Room = {
	owner: Player,
	folder: Folder,
	center: Vector3,
	slot: number, -- lugar en el cielo que ocupa (se reutiliza al cerrarse)
	enemies: { Enemy },
	wave: number,
	token: number, -- cambia en cada oleada y al cerrar: invalida tareas pendientes de la anterior
	closed: boolean,
	awaySince: number?,
}

type Enemy = {
	room: Room,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	torso: BasePart,
	kind: Kind,
	damage: number,
	gold: number,
	reach: number,
	nextAttack: number,
	nextSlam: number,
	attacking: boolean,
}

local rooms: { [Player]: Room } = {}
local usedSlots: { [number]: boolean } = {}
local dungeonFolder: Folder? = nil
local roomsOrigin = Vector3.zero -- centro de la sala 0; las demás se corren ROOM_SPACING en X
local lobbyReturn = Vector3.zero -- donde aparece el jugador al salir (delante del arco)

local function publish(room: Room, attributes: { [string]: any })
	for name, value in attributes do
		room.folder:SetAttribute(name, value)
	end
end

local function part(parent: Instance, name: string, position: Vector3, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Parte decorativa: no la encuentran los golpes.
local function decor(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = part(parent, name, cf.Position, size, color)
	p.CFrame = cf
	p.Material = material
	p.CanQuery = false
	return p
end

local function torch(parent: Instance, position: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(position, position + facing)
	local bracket = decor(parent, "Antorcha", cf, Vector3.new(0.5, 1.6, 0.5), Color3.fromRGB(60, 45, 35), Enum.Material.Wood)
	bracket.CanCollide = false
	local flame = decor(parent, "Llama", cf * CFrame.new(0, 1, 0), Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 150, 60), Enum.Material.Neon)
	flame.CanCollide = false
	flame.Transparency = 0.2
	local fire = Instance.new("Fire")
	fire.Size, fire.Heat = 3, 6
	fire.Color, fire.SecondaryColor = Color3.fromRGB(255, 140, 50), Color3.fromRGB(255, 220, 120)
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range, light.Brightness = 22, 2.2
	light.Parent = flame
	Sounds.Torch(flame)
end

-- Tono según el tamaño: los grandes suenan más graves.
local function pitchFor(kind: Kind): number
	return 1.15 - 0.2 * kind.scale
end

local function inRoom(room: Room, position: Vector3): boolean
	local offset = position - room.center
	local half = ARENA_SIZE / 2
	return math.abs(offset.X) <= half and math.abs(offset.Z) <= half and offset.Y > -5 and offset.Y < 25
end

-- El dueño, si está vivo, fuera de duelo y dentro de su sala.
local function ownerInside(room: Room): (Humanoid?, BasePart?)
	local player = room.owner
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local root = if hum then hum.RootPart else nil
	if hum and root and hum.Health > 0 and player:GetAttribute("InDuel") ~= true and inRoom(room, root.Position) then
		return hum, root
	end
	return nil, nil
end

local function notify(room: Room, message: string)
	if room.owner.Parent == Players then
		Remotes.GetEvent("Notify"):FireClient(room.owner, message)
	end
end

-- Mejor oleada: llegar a una oleada en tu sala cuenta como alcanzarla.
local function recordWave(room: Room)
	if room.wave > 0 and Data.RecordWave(room.owner, room.wave) and room.wave > 1 then
		notify(room, `¡Nuevo récord: oleada {room.wave}!`)
	end
end

local function reward(enemy: Enemy)
	local attacker = enemy.humanoid:GetAttribute("LastAttacker")
	if typeof(attacker) ~= "number" or attacker == 0 or attacker % 1 ~= 0 then return end
	local player = Players:GetPlayerByUserId(attacker)
	if not player then return end
	Data.AddKill(player)
	-- Solo oro: las armas se consiguen únicamente en la tienda (no hay drops).
	local gold = enemy.gold * Data.GoldMultiplier(player) -- x2 con el Pase del Vacío
	if not Data.ChangeGold(player, gold) then return end
	Remotes.GetEvent("Notify"):FireClient(player, {
		Kind = "Gold",
		Amount = gold,
		Position = enemy.torso.Position + Vector3.new(0, 2 * enemy.kind.scale, 0),
	})
end

-- El guardián se desarma: sus partes se esconden y en su lugar caen piedras sueltas.
local function crumble(enemy: Enemy)
	local parent = enemy.room.folder
	local scale = enemy.kind.scale
	Sounds.PlayAt("Piedras", enemy.torso.Position, pitchFor(enemy.kind), math.min(1.5, 0.7 + 0.3 * scale))
	for _, piece in enemy.model:GetDescendants() do
		if not piece:IsA("BasePart") or piece.Transparency >= 1 then continue end
		piece.Transparency = 1
		piece.CanCollide, piece.CanQuery, piece.CanTouch = false, false, false
		local rocks = math.clamp(math.floor(piece.Size.X * piece.Size.Y * piece.Size.Z / 3), 1, 6)
		for _ = 1, rocks do
			local size = random:NextNumber(0.4, 0.9) * scale
			local rock = Instance.new("Part")
			rock.Name = "Piedra"
			rock.Size = Vector3.new(size, size * random:NextNumber(0.6, 1), size)
			rock.Color = piece.Color
			rock.Material = if piece.Material == Enum.Material.Neon then Enum.Material.Neon else Enum.Material.Slate
			rock.CFrame = CFrame.new(piece.Position + random:NextUnitVector() * piece.Size.Magnitude * 0.25)
				* CFrame.Angles(random:NextNumber(0, 6.3), random:NextNumber(0, 6.3), random:NextNumber(0, 6.3))
			rock.CanQuery, rock.CanTouch = false, false
			rock.Parent = parent
			rock.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-12, 12), random:NextNumber(8, 18), random:NextNumber(-12, 12))
			task.delay(2.2, function()
				if rock.Parent then
					TweenService:Create(rock, TweenInfo.new(0.8), { Transparency = 1, Size = rock.Size * 0.3 }):Play()
				end
			end)
			Debris:AddItem(rock, 3)
		end
	end
end

local startWave: (Room, number) -> ()

local function onEnemyDied(enemy: Enemy, token: number)
	local room = enemy.room
	local index = table.find(room.enemies, enemy)
	if index then table.remove(room.enemies, index) end
	if room.closed then return end
	crumble(enemy)
	task.delay(1.5, function() enemy.model:Destroy() end)
	if token == room.token then publish(room, { EnemiesLeft = #room.enemies }) end

	local waveCleared = token == room.token and #room.enemies == 0
	if waveCleared then
		Sounds.PlayAt("OleadaSuperada", room.center + Vector3.new(0, 6, 0))
		local multiplier = Data.GoldMultiplier(room.owner)
		local bonus = 10 * room.wave * multiplier
		if ownerInside(room) and Data.Profile(room.owner) and Data.ChangeGold(room.owner, bonus) then
			local tag = if multiplier > 1 then ` (x{multiplier} Void Pass)` else ""
			notify(room, `¡Oleada {room.wave} superada! +{bonus} de oro{tag}`)
		end
	end
	-- Oro por la baja (solo para quien dio el último golpe).
	reward(enemy)

	if not waveCleared then return end
	local cleared = room.wave
	publish(room, { NextWaveAt = workspace:GetServerTimeNow() + WAVE_DELAY })
	task.delay(WAVE_DELAY, function()
		if token == room.token and not room.closed then startWave(room, cleared + 1) end
	end)
end

-- Arma el cuerpo con piezas soldadas al HumanoidRootPart. El frente del guardián es -Z.
local function spawnEnemy(room: Room, x: number, z: number, kind: Kind, base: WaveStats)
	local s = kind.scale
	local center = room.center
	local floorTop = center.Y + 1
	-- El torso apoya en el piso; el root flota HipHeight (0.5·s) por encima para que el Humanoid camine.
	local position = Vector3.new(center.X + x, floorTop + 1.5 * s, center.Z + z)
	local model = Instance.new("Model")
	model.Name = `{kind.name} · Oleada {room.wave}` -- HealthBarController (cliente) muestra este nombre con la barra
	local root = part(model, "HumanoidRootPart", position, Vector3.new(2, 2, 1) * s, Color3.new())
	root.Transparency = 1
	root.Anchored = false

	local function piece(name: string, offset: Vector3, size: Vector3, color: Color3, material: Enum.Material): Part
		local p = part(model, name, position + offset * s, size * s, color)
		p.Material = material
		p.CanCollide = false
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = root, p
		weld.Parent = p
		return p
	end
	local torso = piece("Torso", Vector3.zero, Vector3.new(3, 3, 2), kind.body, Enum.Material.Slate)
	piece("Head", Vector3.new(0, 2.35, 0), Vector3.new(1.8, 1.7, 1.7), kind.head, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		piece("Ojo", Vector3.new(0.4 * side, 2.5, -0.86), Vector3.new(0.35, 0.22, 0.1), kind.eyes, Enum.Material.Neon)
		piece("Brazo", Vector3.new(2 * side, 0.2, 0), Vector3.new(1, 2.6, 1.2), kind.head, Enum.Material.Slate)
	end
	if kind.boss then
		for _, side in { -1, 1 } do
			piece("Hombrera", Vector3.new(1.9 * side, 1.7, 0), Vector3.new(1.6, 0.8, 1.6), kind.body, Enum.Material.Basalt)
		end
		piece("Corona", Vector3.new(0, 3.35, 0), Vector3.new(1.4, 0.35, 1.4), kind.eyes, Enum.Material.Neon)
	end
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 0.5 * s
	humanoid.MaxHealth = math.floor(base.health * kind.health)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = math.clamp(base.speed * kind.speed, 5, 24)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	local enemy: Enemy = {
		room = room, model = model, humanoid = humanoid, root = root, torso = torso, kind = kind,
		damage = math.floor(base.damage * kind.damage), gold = math.floor(base.gold * kind.gold),
		reach = 3 + 1.5 * s, nextAttack = 0, nextSlam = os.clock() + 3, attacking = false,
	}
	table.insert(room.enemies, enemy)
	local token = room.token
	humanoid.Died:Once(function() onEnemyDied(enemy, token) end)

	model.Parent = room.folder
	root:SetNetworkOwner(nil) -- el servidor mueve a los guardianes
end

-- Composición de la oleada: un jefe cada BOSS_EVERY oleadas; si no, mezcla de tipos.
local function roster(number: number, base: WaveStats): { Kind }
	local list: { Kind } = {}
	local count = base.count
	if number % BOSS_EVERY == 0 then
		table.insert(list, KINDS.Boss)
		count = math.floor(count / 2)
	end
	for _ = 1, count do
		local roll = random:NextNumber()
		if number >= 3 and roll < 0.2 then
			table.insert(list, KINDS.Colossus)
		elseif number >= 2 and roll < 0.5 then
			table.insert(list, KINDS.Swift)
		else
			table.insert(list, KINDS.Guardian)
		end
	end
	return list
end

local function hitPlayer(target: Humanoid, amount: number)
	local victim = Players:GetPlayerFromCharacter(target.Parent)
	if not victim or victim:GetAttribute("InDuel") == true or target.Health <= 0 then return end
	local before = target.Health
	-- Armadura del jugador (Humanoid.Armor, la escribe ArmorService): reduce el daño recibido.
	local armor = target:GetAttribute("Armor")
	if typeof(armor) == "number" then amount *= 1 - math.clamp(armor, 0, 0.9) end
	target:TakeDamage(amount)
	if target.Health < before then
		local root = target.RootPart
		if root then Sounds.Play("GolpeRecibido", root, 0.9 + math.random() * 0.2) end
		Remotes.GetEvent("CombatFeedback"):FireClient(victim, {
			Target = target.Parent, Damage = before - target.Health, Killed = target.Health <= 0,
		})
	end
end

local function attack(enemy: Enemy, target: Humanoid, targetRoot: BasePart)
	enemy.attacking = true
	enemy.nextAttack = os.clock() + enemy.kind.cooldown
	local original = enemy.torso.Color
	enemy.torso.Color = WARN_COLOR
	Sounds.Play("AvisoGolpe", enemy.torso, pitchFor(enemy.kind))
	task.delay(ATTACK_WINDUP, function()
		enemy.attacking = false
		if enemy.torso.Parent then enemy.torso.Color = original end
		local hum = enemy.humanoid
		if enemy.room.closed or hum.Health <= 0 or hum:GetAttribute("CombatState") == "Stunned" then return end
		if not targetRoot.Parent then return end
		-- El jugador puede esquivar alejándose durante el aviso.
		if (targetRoot.Position - enemy.root.Position).Magnitude > enemy.reach + 1 then return end
		hitPlayer(target, enemy.damage)
	end)
end

-- Golpe en área del jefe: un círculo rojo crece en el piso durante SLAM_WINDUP y después pega
-- al dueño de la sala si sigue adentro del círculo.
local function slam(enemy: Enemy)
	local room = enemy.room
	local parent = room.folder
	enemy.attacking = true
	enemy.nextSlam = os.clock() + SLAM_COOLDOWN
	enemy.nextAttack = os.clock() + SLAM_WINDUP + 0.6
	local at = Vector3.new(enemy.root.Position.X, room.center.Y + 1.05, enemy.root.Position.Z)
	local flat = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)) -- cilindro acostado = disco en el piso
	local warning = decor(parent, "AvisoGolpe", flat, Vector3.new(0.1, 1, 1), SLAM_COLOR, Enum.Material.Neon)
	warning.Shape = Enum.PartType.Cylinder
	warning.CanCollide, warning.CanTouch = false, false
	warning.Transparency = 0.55
	TweenService:Create(warning, TweenInfo.new(SLAM_WINDUP, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.1, SLAM_RADIUS * 2, SLAM_RADIUS * 2),
	}):Play()
	local original = enemy.torso.Color
	enemy.torso.Color = SLAM_COLOR
	Sounds.Play("JefeCarga", enemy.torso)

	task.delay(SLAM_WINDUP, function()
		enemy.attacking = false
		if enemy.torso.Parent then enemy.torso.Color = original end
		warning:Destroy()
		if room.closed or enemy.humanoid.Health <= 0 then return end
		Sounds.PlayAt("JefeGolpe", at + Vector3.new(0, 1, 0))
		local hum, root = ownerInside(room)
		if hum and root then
			local offset = root.Position - at
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= SLAM_RADIUS and offset.Y < 8 then
				hitPlayer(hum, enemy.damage * SLAM_DAMAGE_MULT)
			end
		end
		-- Onda expansiva que se desvanece.
		local shock = decor(parent, "Onda", flat, Vector3.new(0.1, SLAM_RADIUS * 1.6, SLAM_RADIUS * 1.6), Color3.fromRGB(255, 200, 150), Enum.Material.Neon)
		shock.Shape = Enum.PartType.Cylinder
		shock.CanCollide, shock.CanTouch = false, false
		shock.Transparency = 0.3
		TweenService:Create(shock, TweenInfo.new(0.4), {
			Size = Vector3.new(0.1, SLAM_RADIUS * 2.3, SLAM_RADIUS * 2.3), Transparency = 1,
		}):Play()
		Debris:AddItem(shock, 0.5)
	end)
end

local function updateRoom(room: Room)
	local target, targetRoot = ownerInside(room)
	local now = os.clock()
	for _, enemy in room.enemies do
		local hum = enemy.humanoid
		if hum.Health <= 0 or not enemy.root.Parent then continue end
		local stunned = hum:GetAttribute("CombatState") == "Stunned"
		if not target or not targetRoot or stunned or enemy.attacking then
			hum:Move(Vector3.zero)
			continue
		end
		local dist = (targetRoot.Position - enemy.root.Position).Magnitude
		if dist > enemy.reach - 1 then
			hum:MoveTo(targetRoot.Position)
		else
			hum:Move(Vector3.zero)
			local flat = Vector3.new(targetRoot.Position.X, enemy.root.Position.Y, targetRoot.Position.Z)
			if (flat - enemy.root.Position).Magnitude > 0.1 then
				enemy.root.CFrame = CFrame.lookAt(enemy.root.Position, flat)
			end
		end
		if enemy.kind.boss and now >= enemy.nextSlam and dist <= SLAM_RADIUS then
			slam(enemy)
		elseif dist <= enemy.reach and now >= enemy.nextAttack then
			attack(enemy, target, targetRoot)
		end
	end
end

-- Arco de portal. `cf` está a ras del piso y mira hacia donde llega el jugador (-Z local).
-- Devuelve el velo (la parte con el ProximityPrompt) y el prompt.
local function portal(parent: Instance, name: string, cf: CFrame, width: number, height: number): (Part, ProximityPrompt)
	local stone = Color3.fromRGB(78, 80, 86)
	for _, side in { -1, 1 } do
		decor(parent, "Columna", cf * CFrame.new(side * (width / 2 + 0.75), height / 2, 0), Vector3.new(1.5, height, 1.5), stone, Enum.Material.Cobblestone)
	end
	decor(parent, "Dintel", cf * CFrame.new(0, height + 0.6, 0), Vector3.new(width + 3, 1.2, 1.8), stone, Enum.Material.Cobblestone)

	local veil = decor(parent, name, cf * CFrame.new(0, height / 2, 0), Vector3.new(width, height, 0.3), Color3.fromRGB(80, 200, 255), Enum.Material.ForceField)
	veil.CanCollide = false
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = Color3.fromRGB(90, 200, 255), 14, 1.5
	glow.Parent = veil
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(190, 120, 255))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0.2, 1)
	sparks.Lifetime = NumberRange.new(1, 1.8)
	sparks.Rate = 28
	sparks.Speed = NumberRange.new(0.5, 1.5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.RotSpeed = NumberRange.new(-90, 90)
	sparks.Parent = veil

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Mazmorra"
	prompt.ActionText = name
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = veil
	return veil, prompt
end

-- Personaje vivo y cerca del portal (el servidor no confía en que el prompt llegó de cerca).
local function nearPortal(player: Player, veil: BasePart, prompt: ProximityPrompt): (Model?, BasePart?)
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not char or not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then return nil, nil end
	if (root.Position - veil.Position).Magnitude > prompt.MaxActivationDistance + veil.Size.Y / 2 then return nil, nil end
	return char, root
end

-- Sala cerrada: piso, paredes de piedra con columnas, techo y antorchas.
local function buildRoom(parent: Instance, center: Vector3)
	local half = ARENA_SIZE / 2
	local floorTop = center.Y + 1
	local wallColor = Color3.fromRGB(74, 70, 66)
	local floor = part(parent, "Piso", center, Vector3.new(ARENA_SIZE, 2, ARENA_SIZE), Color3.fromRGB(52, 54, 58))
	floor.Material = Enum.Material.Slate
	for _, side in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local size = if side.X ~= 0 then Vector3.new(2, ROOM_HEIGHT, ARENA_SIZE + 4) else Vector3.new(ARENA_SIZE + 4, ROOM_HEIGHT, 2)
		local wall = part(parent, "Pared", center + side * (half + 1) + Vector3.new(0, 1 + ROOM_HEIGHT / 2, 0), size, wallColor)
		wall.Material = Enum.Material.Cobblestone
		-- Columnas y antorchas a lo largo de la pared, mirando hacia adentro.
		local along = Vector3.new(side.Z, 0, side.X)
		for _, t in { -0.5, 0, 0.5 } do
			local base = center + side * (half - 0.5) + along * (t * ARENA_SIZE)
			decor(parent, "Columna", CFrame.new(Vector3.new(base.X, floorTop + ROOM_HEIGHT / 2, base.Z)), Vector3.new(2, ROOM_HEIGHT, 2), Color3.fromRGB(62, 60, 58), Enum.Material.Slate)
			local between = base + along * (ARENA_SIZE / 4)
			if math.abs(t - 0.5) > 0.01 then
				torch(parent, Vector3.new(between.X, floorTop + 7, between.Z) + side * 0.2, -side) -- pegada a la pared
			end
		end
	end
	local ceiling = part(parent, "Techo", center + Vector3.new(0, 2 + ROOM_HEIGHT, 0), Vector3.new(ARENA_SIZE + 4, 2, ARENA_SIZE + 4), Color3.fromRGB(40, 40, 44))
	ceiling.Material = Enum.Material.Slate
end

-- Brasero de pie para la entrada del lobby.
local function brazier(parent: Instance, position: Vector3)
	decor(parent, "Brasero", CFrame.new(position + Vector3.new(0, 1.5, 0)), Vector3.new(0.8, 3, 0.8), Color3.fromRGB(50, 46, 44), Enum.Material.Metal)
	decor(parent, "Cuenco", CFrame.new(position + Vector3.new(0, 3.2, 0)), Vector3.new(1.8, 0.5, 1.8), Color3.fromRGB(50, 46, 44), Enum.Material.Metal)
	torch(parent, position + Vector3.new(0, 2.9, 0), Vector3.new(0, 0, -1))
end

-- ── Salas ──

local function closeRoom(room: Room)
	if room.closed then return end
	room.closed = true
	room.token += 1 -- cancela la próxima oleada pendiente y los golpes en curso
	table.clear(room.enemies)
	room.folder:Destroy()
	usedSlots[room.slot] = nil
	if rooms[room.owner] == room then rooms[room.owner] = nil end
end

startWave = function(room: Room, number: number)
	if room.closed then return end
	room.token += 1
	room.wave = number
	local base = waveStats(number)
	local list = roster(number, base)
	for i, kind in list do
		local x: number, z: number
		if kind.boss then
			x, z = 0, -12
		else
			x = (i - (#list + 1) / 2) * 5
			z = -6 - (i % 2) * 5
		end
		spawnEnemy(room, x, z, kind, base)
	end
	publish(room, { Wave = number, EnemiesLeft = #room.enemies, NextWaveAt = 0 })
	Sounds.PlayAt(if number % BOSS_EVERY == 0 then "JefeAparece" else "Oleada", room.center + Vector3.new(0, 6, 0))
	if number % BOSS_EVERY == 0 then
		notify(room, `¡Oleada {number}: aparece el {KINDS.Boss.name}! Cuidado con su golpe en área.`)
	else
		notify(room, `Oleada {number}: {#list} guardianes`)
	end
	if ownerInside(room) then recordWave(room) end
end

-- Arma una sala nueva para el jugador (si ya tenía una, la cierra: siempre se empieza de cero).
local function openRoom(player: Player): Room
	local previous = rooms[player]
	if previous then closeRoom(previous) end
	local parent = dungeonFolder :: Folder

	local slot = 0
	while usedSlots[slot] do slot += 1 end
	usedSlots[slot] = true
	local center = roomsOrigin + Vector3.new(slot * ROOM_SPACING, 0, 0)

	local folder = Instance.new("Folder")
	folder.Name = `Sala_{player.UserId}`
	local room: Room = {
		owner = player, folder = folder, center = center, slot = slot,
		enemies = {}, wave = 0, token = 0, closed = false, awaySince = nil,
	}
	rooms[player] = room
	publish(room, {
		Center = center, Size = ARENA_SIZE, Wave = 0, EnemiesLeft = 0,
		NextWaveAt = workspace:GetServerTimeNow() + START_DELAY,
	})
	buildRoom(folder, center)
	-- Sin portal de salida: se sale con el botón "Exit" del HUD (remote LeaveDungeon).
	folder.Parent = parent

	local token = room.token
	task.delay(START_DELAY, function()
		if room.token == token then startWave(room, 1) end
	end)
	return room
end

function DungeonService:Init()
	local dungeon = Instance.new("Folder")
	dungeon.Name = "Mazmorra"
	dungeonFolder = dungeon
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawn then spawn.Position else Vector3.zero
	local ground = if spawn then origin.Y - spawn.Size.Y / 2 else 0
	roomsOrigin = origin + Vector3.new(0, 160, 0)
	dungeon.Parent = workspace

	-- Entrada en el lobby: arco grande mirando al spawn, con braseros a los costados y un cartel.
	local entrance = Instance.new("Folder")
	entrance.Name = "Entrada"
	entrance.Parent = dungeon
	local gateBase = Vector3.new(origin.X + 14, ground, origin.Z)
	local gate = CFrame.lookAt(gateBase, Vector3.new(origin.X, ground, origin.Z))
	lobbyReturn = (gate * CFrame.new(0, 3, -5)).Position -- delante del arco
	local veil, prompt = portal(entrance, "Entrar", gate, 6, 9)
	for _, side in { -1, 1 } do
		brazier(entrance, (gate * CFrame.new(side * 6, 0, -1.5)).Position)
	end
	local sign = decor(entrance, "Cartel", gate * CFrame.new(0, 10.9, -0.95), Vector3.new(8, 1.6, 0.1), Color3.fromRGB(30, 26, 24), Enum.Material.Wood)
	sign.CanCollide = false
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Antique
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(237, 197, 118)
	text.Text = "MAZMORRA"
	text.Parent = surface

	prompt.Triggered:Connect(function(player)
		local char, root = nearPortal(player, veil, prompt)
		if not char or not root then return end
		if player:GetAttribute("InDuel") == true or not Data.Profile(player) then
			Remotes.GetEvent("Notify"):FireClient(player, "Entrada bloqueada durante un duelo o mientras se carga tu inventario.")
			return
		end
		local room = openRoom(player)
		Sounds.PlayAt("Portal", veil.Position)
		char:PivotTo(CFrame.new(room.center + Vector3.new(0, 5, 15)))
		Sounds.Play("Portal", root, 1.1)
		Remotes.GetEvent("Notify"):FireClient(player, "Tu mazmorra: ¡preparate para la oleada 1!")
	end)

	-- Botón "Exit" (UIController): vuelve al lobby, delante del arco, y cierra la sala.
	Remotes.GetEvent("LeaveDungeon").OnServerEvent:Connect(function(player)
		local room = rooms[player]
		if not room or room.closed then return end
		local char = player.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		local root = if hum then hum.RootPart else nil
		if char and hum and root and hum.Health > 0 and inRoom(room, root.Position) then
			Sounds.PlayAt("Portal", root.Position)
			char:PivotTo(CFrame.new(lobbyReturn))
			Sounds.Play("Portal", root, 1.1)
		end
		closeRoom(room)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local room = rooms[player]
		if room then closeRoom(room) end
	end)

	-- IA de cada sala; si el dueño pasa ROOM_TIMEOUT s afuera (murió, se fue, entró a un duelo), se cierra.
	task.spawn(function()
		while true do
			task.wait(AI_TICK)
			local now = os.clock()
			for _, room in table.clone(rooms) do
				if room.closed then continue end
				updateRoom(room)
				if ownerInside(room) then
					room.awaySince = nil
				else
					room.awaySince = room.awaySince or now
					if now - (room.awaySince :: number) >= ROOM_TIMEOUT then
						closeRoom(room)
						notify(room, "Tu mazmorra se cerró. Al volver a entrar empezás de nuevo en la oleada 1.")
					end
				end
			end
		end
	end)
end

return DungeonService
