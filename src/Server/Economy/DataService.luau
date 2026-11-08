--!strict
--[[
	DataService — Perfil persistente de cada jugador (oro, armas, progreso en la mazmorra).
	Owner: Dev B (Economía).

	- Progreso: bestWave (mejor oleada alcanzada) y kills (guardianes derrotados en total).
	  Se muestran en la lista de jugadores (leaderstats) y en el tablero de récords (RecordsService).
	- Las armas de GamePass NO se guardan como propias: se vuelven a verificar con
	  MarketplaceService cada vez que el jugador entra (reembolsos / pases quitados).
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Marketplace = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local ArmorData = require(Shared:WaitForChild("ArmorData"))

type Profile = {gold: number, owned: {[string]: boolean}, equipped: string, bestWave: number, kills: number,
	redeemed: {[string]: boolean}, bonusPasses: {[string]: boolean},
	armorOwned: {[string]: boolean}, armorEquipped: {[string]: string},
	boosts: {[string]: number}, -- potenciador → os.time() en que vence ("Gold", "Damage")
	receipts: {[string]: boolean}} -- compras de Robux ya entregadas (PurchaseId)
type Session = {profile: Profile?, token: string, closing: boolean, saving: boolean, lease: number}
local sessions: {[Player]: Session} = {}
local memoryOnly = RunService:IsStudio() and game.GameId == 0
local store: GlobalDataStore? = nil
local LEASE_SECONDS = 180
local STAT_BEST_WAVE = "Mejor oleada"
local STAT_KILLS = "Guardianes"
-- Pase del Vacío: da la Guadaña del Vacío y duplica el oro de la mazmorra.
-- Su ID es el GamePassId de la guadaña en WeaponData (0 = todavía no creado).
local VOID_PASS = WeaponData.Weapons.VoidScythe.GamePassId or 0
local VOID_GOLD_MULTIPLIER = 2
local DataService = {
	STAT_BEST_WAVE = STAT_BEST_WAVE, -- nombre del IntValue en leaderstats (lo lee RecordsService)
	VOID_PASS = VOID_PASS,
}
-- Pases verificados en esta sesión (no se guardan: se vuelven a consultar al entrar).
local passOwners: {[Player]: {[number]: boolean}} = {}

local function markPass(player: Player, passId: number)
	local owned = passOwners[player] or {}
	passOwners[player] = owned
	owned[passId] = true
	if passId == VOID_PASS then player:SetAttribute("VoidPass", true) end
end

local function count(value: any): number
	return if typeof(value) == "number" and value >= 0 and value < math.huge then math.floor(value) else 0
end

-- Conjunto de textos guardado como { [texto] = true }.
local function flags(value: any): {[string]: boolean}
	local out = {}
	if typeof(value) == "table" then
		for key, v in value do
			if typeof(key) == "string" and v == true then out[key] = true end
		end
	end
	return out
end

local function decode(raw: any): Profile
	local data = if typeof(raw) == "table" then raw else {}
	local owned = {[WeaponData.DEFAULT_WEAPON] = true}
	if typeof(data.owned) == "table" then
		for id, value in data.owned do
			if typeof(id) == "string" and value == true and WeaponData.IsValid(id) then
				owned[id] = true
			end
		end
	end
	local equipped = data.equipped
	-- Armadura: solo piezas que existen; lo equipado tiene que ser propio y estar en su lugar.
	local armorOwned = {}
	for id in flags(data.armorOwned) do
		if ArmorData.Get(id) then armorOwned[id] = true end
	end
	local armorEquipped = {}
	if typeof(data.armorEquipped) == "table" then
		for slot, id in data.armorEquipped do
			local piece = ArmorData.Get(id)
			-- Las del Void Pass no están en armorOwned: su dueño se comprueba en el momento (OwnsArmor).
			if piece and piece.Slot == slot and (armorOwned[id] or piece.Acquisition == "VoidPass") then
				armorEquipped[slot] = id
			end
		end
	end
	return {
		armorOwned = armorOwned,
		armorEquipped = armorEquipped,
		boosts = {
			Gold = if typeof(data.boosts) == "table" then count(data.boosts.Gold) else 0,
			Damage = if typeof(data.boosts) == "table" then count(data.boosts.Damage) else 0,
		},
		receipts = flags(data.receipts),
		gold = count(data.gold),
		owned = owned,
		equipped = if typeof(equipped) == "string" and owned[equipped] then equipped else WeaponData.DEFAULT_WEAPON,
		bestWave = count(data.bestWave),
		kills = count(data.kills),
		redeemed = flags(data.redeemed), -- códigos canjeados (CodeService)
		bonusPasses = flags(data.bonusPasses), -- pases dados por código, por ID en texto
	}
end

-- Armas de GamePass: se quitan las guardadas y se vuelven a dar solo si el pase se verifica ahora.
-- Si la consulta falla, el arma no queda disponible en esta sesión (se reintenta al volver a entrar).
local function verifyGamePasses(player: Player, profile: Profile)
	for id, weapon in WeaponData.Weapons do
		if weapon.Acquisition ~= "GamePass" then continue end
		profile.owned[id] = nil
		local passId = weapon.GamePassId
		if passId and passId > 0 and profile.bonusPasses[tostring(passId)] then
			-- Pase obtenido con un código: queda guardado en el perfil, no depende de Roblox.
			profile.owned[id] = true
			markPass(player, passId)
		elseif passId and passId > 0 then
			local ok, owns = pcall(Marketplace.UserOwnsGamePassAsync, Marketplace, player.UserId, passId)
			if ok and owns then
				profile.owned[id] = true
				markPass(player, passId)
			end
		end
	end
	if not profile.owned[profile.equipped] then profile.equipped = WeaponData.DEFAULT_WEAPON end
end

local function setStat(player: Player, name: string, value: number)
	local stats = player:FindFirstChild("leaderstats")
	local stat = if stats then stats:FindFirstChild(name) else nil
	if stat and stat:IsA("IntValue") then stat.Value = value end
end

local function createLeaderstats(player: Player, profile: Profile)
	local old = player:FindFirstChild("leaderstats")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	-- El orden de creación es el orden de las columnas en la lista de jugadores.
	for _, name in {STAT_BEST_WAVE, STAT_KILLS} do
		local stat = Instance.new("IntValue")
		stat.Name = name
		stat.Value = if name == STAT_BEST_WAVE then profile.bestWave else profile.kills
		stat.Parent = folder
	end
	folder.Parent = player
end

function DataService.Profile(player: Player): Profile?
	local s = sessions[player]
	if s and not s.closing and (memoryOnly or os.time() < s.lease) then
		return s.profile
	end
	return nil
end

function DataService.ChangeGold(player: Player, amount: number): boolean
	local p = DataService.Profile(player)
	if not p or amount % 1 ~= 0 or p.gold + amount < 0 then return false end
	p.gold += amount
	player:SetAttribute("Gold", p.gold)
	return true
end

-- Suma un guardián derrotado.
function DataService.AddKill(player: Player)
	local p = DataService.Profile(player)
	if not p then return end
	p.kills += 1
	setStat(player, STAT_KILLS, p.kills)
end

-- Registra que el jugador llegó a esta oleada; devuelve true si es un récord nuevo.
function DataService.RecordWave(player: Player, wave: number): boolean
	local p = DataService.Profile(player)
	if not p or wave % 1 ~= 0 or wave <= p.bestWave then return false end
	p.bestWave = wave
	setStat(player, STAT_BEST_WAVE, wave)
	return true
end

-- false en un place sin publicar (datos solo en memoria): no hay DataStores disponibles.
function DataService.OwnsPass(player: Player, passId: number): boolean
	local owned = passOwners[player]
	return passId > 0 and owned ~= nil and owned[passId] == true
end

-- Activa un pase: recién comprado (MarketplaceService puede tardar en reflejarlo en
-- UserOwnsGamePassAsync) o dado por un código (`permanent`: queda guardado en el perfil).
-- Marca el pase y da las armas que trae. false si el perfil no cargó.
function DataService.GrantPass(player: Player, passId: number, permanent: boolean?): boolean
	local p = DataService.Profile(player)
	if not p or passId <= 0 then return false end
	if permanent then p.bonusPasses[tostring(passId)] = true end
	markPass(player, passId)
	for id, weapon in WeaponData.Weapons do
		if weapon.Acquisition == "GamePass" and weapon.GamePassId == passId then
			p.owned[id] = true
		end
	end
	return true
end

-- Códigos promocionales (CodeService): cada código se canjea una sola vez por jugador.
-- nil si el perfil no cargó.
function DataService.HasRedeemed(player: Player, code: string): boolean?
	local p = DataService.Profile(player)
	if not p then return nil end
	return p.redeemed[code] == true
end

function DataService.MarkRedeemed(player: Player, code: string)
	local p = DataService.Profile(player)
	if p then p.redeemed[code] = true end
end

-- Multiplicador del oro que da la mazmorra (x2 con el Pase del Vacío).
-- Se multiplican: Void Pass (x2) y potenciador "Oro x2" (x2) juntos dan x4.
function DataService.GoldMultiplier(player: Player): number
	local multiplier = if DataService.OwnsPass(player, VOID_PASS) then VOID_GOLD_MULTIPLIER else 1
	local p = DataService.Profile(player)
	if p and (p.boosts.Gold or 0) > os.time() then multiplier *= 2 end
	return multiplier
end

-- ── Potenciadores (tienda de Robux) ──
-- El vencimiento se guarda en os.time() (sirve entre servidores) y se publica para el cliente como
-- Player.GoldBoostUntil / Player.DamageBoostUntil en workspace:GetServerTimeNow() (0 = sin potenciador).
local BOOST_ATTRIBUTES = { Gold = "GoldBoostUntil", Damage = "DamageBoostUntil" }

local function publishBoosts(player: Player, profile: Profile)
	local now = os.time()
	for kind, attribute in BOOST_ATTRIBUTES do
		local expires = profile.boosts[kind] or 0
		player:SetAttribute(attribute, if expires > now then workspace:GetServerTimeNow() + (expires - now) else 0)
	end
end

-- Suma `seconds` al potenciador (si ya estaba activo, se extiende). false si el perfil no cargó.
function DataService.AddBoost(player: Player, kind: string, seconds: number): boolean
	local p = DataService.Profile(player)
	if not p or not BOOST_ATTRIBUTES[kind] or seconds <= 0 then return false end
	p.boosts[kind] = math.max(p.boosts[kind] or 0, os.time()) + math.floor(seconds)
	publishBoosts(player, p)
	return true
end

-- ── Armaduras ──
-- Una pieza es tuya si la compraste, o si es del set del Void Pass y tenés el pase.
function DataService.OwnsArmor(player: Player, pieceId: string): boolean
	local p = DataService.Profile(player)
	local piece = ArmorData.Get(pieceId)
	if not p or not piece then return false end
	if piece.Acquisition == "VoidPass" then return DataService.OwnsPass(player, VOID_PASS) end
	return p.armorOwned[pieceId] == true
end

-- ── Compras de Robux ──
function DataService.HasReceipt(player: Player, purchaseId: string): boolean?
	local p = DataService.Profile(player)
	if not p then return nil end
	return p.receipts[purchaseId] == true
end

function DataService.MarkReceipt(player: Player, purchaseId: string)
	local p = DataService.Profile(player)
	if p then p.receipts[purchaseId] = true end
end

function DataService.IsPersistent(): boolean
	return not memoryOnly
end

function DataService.Equip(player: Player, id: string)
	local p = DataService.Profile(player)
	if not p or not p.owned[id] or player:GetAttribute("InDuel") == true then return end
	p.equipped = id
	player:SetAttribute("EquippedWeapon", id)
end

local function save(player: Player, s: Session, release: boolean)
	if not s.profile or memoryOnly or not store then return end
	if release then
		while s.saving do task.wait() end
	elseif s.saving then
		return
	end
	s.saving = true
	local key = tostring(player.UserId)
	for attempt = 1, 3 do
		local profile = s.profile :: Profile
		local expires = os.time() + LEASE_SECONDS
		local snapshot = {gold = profile.gold, owned = table.clone(profile.owned), equipped = profile.equipped,
			bestWave = profile.bestWave, kills = profile.kills,
			redeemed = table.clone(profile.redeemed), bonusPasses = table.clone(profile.bonusPasses),
			armorOwned = table.clone(profile.armorOwned), armorEquipped = table.clone(profile.armorEquipped),
			boosts = table.clone(profile.boosts), receipts = table.clone(profile.receipts),
			owner = if release then nil else s.token, expires = if release then 0 else expires}
		local ok, result = pcall(function()
			return (store :: GlobalDataStore):UpdateAsync(key, function(old: any)
				if not old or old.owner ~= s.token then return nil end
				return snapshot
			end)
		end)
		if ok then
			if result then
				s.lease = expires
				if release then
					print(`[Economy] Guardado al salir: {player.Name} · oro {profile.gold} · mejor oleada {profile.bestWave} · guardianes {profile.kills}`)
				end
			else
				s.lease = 0
				if not release and player.Parent == Players then player:Kick("La sesión de datos cambió. Volvé a entrar.") end
			end
			break
		end
		warn("[Economy] Falló el guardado", key, result)
		if attempt < 3 then task.wait(attempt) end
	end
	s.saving = false
end

-- Guarda ya (sin soltar la sesión). Lo usa MonetizationService después de entregar una compra.
function DataService.SaveNow(player: Player)
	local s = sessions[player]
	if s and not s.closing then save(player, s, false) end
end

local function loadPlayer(player: Player)
	if sessions[player] then return end
	local s: Session = {profile = nil, token = HttpService:GenerateGUID(false), closing = false, saving = false, lease = 0}
	sessions[player] = s
	player:SetAttribute("EquippedWeapon", WeaponData.DEFAULT_WEAPON)
	player:SetAttribute("Gold", 0)
	player:SetAttribute("VoidPass", false) -- true cuando se verifica el Pase del Vacío (lo lee UIController)
	player:SetAttribute("GoldBoostUntil", 0)
	player:SetAttribute("DamageBoostUntil", 0)
	local profile: Profile? = nil
	local failure = "sesión cerrada durante la carga"
	if memoryOnly then
		profile = decode(nil)
	else
		for attempt = 1, 4 do
			if s.closing then break end
			local expires = os.time() + LEASE_SECONDS
			local ok, raw = pcall(function()
				store = DataStoreService:GetDataStore("Economy_v1")
				return (store :: GlobalDataStore):UpdateAsync(tostring(player.UserId), function(old: any)
					if old and old.owner and old.owner ~= s.token and (old.expires or 0) > os.time() then return nil end
					local value: any = decode(old)
					value.owner = s.token
					value.expires = expires
					return value
				end)
			end)
			if ok and raw then
				profile = decode(raw)
				s.lease = expires
				local loaded = profile :: Profile
				local weapons = {}
				for id in loaded.owned do table.insert(weapons, id) end
				print(`[Economy] Datos cargados: {player.Name} · oro {loaded.gold} · armas {table.concat(weapons, ", ")} · mejor oleada {loaded.bestWave} · guardianes {loaded.kills}`)
				break
			end
			failure = if ok then "otra sesión tiene tus datos abiertos" else tostring(raw)
			warn(`[Economy] Carga intento {attempt}/4 de {player.Name}: {failure}`)
			if attempt < 4 then task.wait(attempt) end
		end
	end
	if not profile then
		sessions[player] = nil
		if player.Parent == Players then player:Kick(`No se pudieron cargar tus datos ({failure}). Volvé a entrar.`) end
		return
	end
	verifyGamePasses(player, profile)
	s.profile = profile
	if s.closing or player.Parent ~= Players then
		save(player, s, true)
		sessions[player] = nil
		return
	end
	player:SetAttribute("Gold", profile.gold)
	createLeaderstats(player, profile)
	publishBoosts(player, profile)
	if player:GetAttribute("InDuel") ~= true then player:SetAttribute("EquippedWeapon", profile.equipped) end
end

local function close(player: Player)
	local s = sessions[player]
	if not s or s.closing then return end
	s.closing = true
	passOwners[player] = nil
	if s.profile then
		save(player, s, true)
		sessions[player] = nil
	end
end

function DataService:Init()
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(close)
	for _, player in Players:GetPlayers() do task.spawn(loadPlayer, player) end
	game:BindToClose(function()
		for player in sessions do task.spawn(close, player) end
		local deadline = os.clock() + 27
		while next(sessions) and os.clock() < deadline do task.wait(0.1) end
	end)
	if memoryOnly then
		warn("[Economy] Place sin publicar: datos de prueba solo en memoria.")
	else
		task.spawn(function()
			while task.wait(45) do
				for player, s in sessions do
					if not s.closing then task.spawn(save, player, s, false) end
				end
			end
		end)
	end
end

return DataService
