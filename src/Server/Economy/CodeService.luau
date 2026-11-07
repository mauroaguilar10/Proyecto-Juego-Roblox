--!strict
--[[
	CodeService — Canje de códigos promocionales.
	Owner: Dev B (Economía).

	- Los códigos viven SOLO en el servidor (no se pueden ver inspeccionando el cliente).
	- No distingue mayúsculas ni espacios: "freepass26" y " FreePass26 " son el mismo código.
	- Cada código se canjea una vez por jugador (queda guardado en el perfil: DataService.redeemed).
	- Remote "RedeemCode" (C→S→C): recibe el texto y devuelve (ok, mensaje). Lo usa UIController.

	Para agregar un código: sumar una entrada a CODES (la clave en MAYÚSCULAS).
	Para retirarlo: borrarlo de CODES (quien ya lo canjeó conserva la recompensa).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local Data = require(script.Parent:WaitForChild("DataService"))
local CodeService = {}

type Reward = { kind: "Gold", amount: number } | { kind: "VoidPass" }

local CODES: { [string]: Reward } = {
	FREEPASS26 = { kind = "VoidPass" }, -- Void Pass gratis (Guadaña del Vacío + oro x2 en la mazmorra)
	FREE5K = { kind = "Gold", amount = 5000 },
}

local ATTEMPT_COOLDOWN = 1.5 -- s entre intentos (evita probar códigos a lo bruto)
local MAX_LENGTH = 32
local lastAttempt: { [Player]: number } = {}

local function normalize(text: string): string
	return (text:gsub("%s", "")):upper()
end

local function redeem(player: Player, raw: any): (boolean, string)
	local now = os.clock()
	if now < (lastAttempt[player] or -math.huge) + ATTEMPT_COOLDOWN then
		return false, "Esperá un momento antes de probar otro código."
	end
	lastAttempt[player] = now
	if typeof(raw) ~= "string" or #raw == 0 or #raw > MAX_LENGTH then
		return false, "Escribí un código."
	end
	local code = normalize(raw)
	local reward = CODES[code]
	if not reward then return false, "Ese código no existe o ya venció." end

	local already = Data.HasRedeemed(player, code)
	if already == nil then return false, "Tu inventario todavía se está cargando. Probá en unos segundos." end
	if already then return false, "Ya canjeaste este código." end

	if reward.kind == "Gold" then
		if not Data.ChangeGold(player, reward.amount) then return false, "No se pudo canjear el código." end
		Data.MarkRedeemed(player, code)
		return true, `¡Código canjeado! +{reward.amount} de oro`
	else
		local passId = Data.VOID_PASS
		if passId <= 0 then return false, "Este código todavía no está disponible." end
		if Data.OwnsPass(player, passId) then return false, "Ya tenés el Void Pass." end
		if not Data.GrantPass(player, passId, true) then return false, "No se pudo canjear el código." end
		Data.MarkRedeemed(player, code)
		if player:GetAttribute("InDuel") ~= true then
			for id, weapon in WeaponData.Weapons do
				if weapon.GamePassId == passId then Data.Equip(player, id) end
			end
		end
		return true, "¡Código canjeado! Void Pass activado: Guadaña del Vacío equipada y oro x2 en la mazmorra."
	end
end

function CodeService:Init()
	Remotes.GetFunction("RedeemCode").OnServerInvoke = function(player: Player, text: any)
		local ok, success, message = pcall(redeem, player, text)
		if not ok then
			warn("[Codes] Falló un canje", success)
			return false, "No se pudo canjear el código."
		end
		return success, message
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAttempt[player] = nil
	end)
end

return CodeService
