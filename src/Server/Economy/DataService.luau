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

type Profile = {gold: number, owned: {[string]: boolean}, equipped: string, bestWave: number, kills: number}
type Session = {profile: Profile?, token: string, closing: boolean, saving: boolean, lease: number}
local sessions: {[Player]: Session} = {}
local memoryOnly = RunService:IsStudio() and game.GameId == 0
local store: GlobalDataStore? = nil
local LEASE_SECONDS = 180
local STAT_BEST_WAVE = "Mejor oleada"
local STAT_KILLS = "Guardianes"
local DataService = {
	STAT_BEST_WAVE = STAT_BEST_WAVE, -- nombre del IntValue en leaderstats (lo lee RecordsService)
}

local function count(value: any): number
	return if typeof(value) == "number" and value >= 0 and value < math.huge then math.floor(value) else 0
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
	return {
		gold = count(data.gold),
		owned = owned,
		equipped = if typeof(equipped) == "string" and owned[equipped] then equipped else WeaponData.DEFAULT_WEAPON,
		bestWave = count(data.bestWave),
		kills = count(data.kills),
	}
end

-- Armas de GamePass: se quitan las guardadas y se vuelven a dar solo si el pase se verifica ahora.
-- Si la consulta falla, el arma no queda disponible en esta sesión (se reintenta al volver a entrar).
local function verifyGamePasses(player: Player, profile: Profile)
	for id, weapon in WeaponData.Weapons do
		if weapon.Acquisition ~= "GamePass" then continue end
		profile.owned[id] = nil
		local passId = weapon.GamePassId
		if passId and passId > 0 then
			local ok, owns = pcall(Marketplace.UserOwnsGamePassAsync, Marketplace, player.UserId, passId)
			if ok and owns then profile.owned[id] = true end
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

local function loadPlayer(player: Player)
	if sessions[player] then return end
	local s: Session = {profile = nil, token = HttpService:GenerateGUID(false), closing = false, saving = false, lease = 0}
	sessions[player] = s
	player:SetAttribute("EquippedWeapon", WeaponData.DEFAULT_WEAPON)
	player:SetAttribute("Gold", 0)
	local profile: Profile? = nil
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
				break
			end
			if attempt < 4 then task.wait(attempt) end
		end
	end
	if not profile then
		sessions[player] = nil
		if player.Parent == Players then player:Kick("No se pudieron cargar tus datos. Volvé a entrar.") end
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
	if player:GetAttribute("InDuel") ~= true then player:SetAttribute("EquippedWeapon", profile.equipped) end
end

local function close(player: Player)
	local s = sessions[player]
	if not s or s.closing then return end
	s.closing = true
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
