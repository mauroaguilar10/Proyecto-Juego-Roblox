--!strict
--[[
	DuelRules — Reglas compartidas de los desafíos de duelo (servidor y cliente).

	Modos:
	  "Informal" → 1v1 a un round, sin apuesta: el ganador no recibe nada.
	  "Duel"     → cada jugador apuesta la misma cantidad de oro (se descuenta al empezar).
	               El ganador se lleva el pozo menos el impuesto (TAX), que frena el traspaso
	               de oro entre cuentas. Empate (tiempo) = se devuelve la apuesta a ambos.
	               Ej.: 250 + 250 = 500 → premio 450.

	Zona: la arena del lobby publica su centro y radio como Attributes de workspace
	(DuelZoneCenter: Vector3, DuelZoneRadius: number). Al pisarla se abre el menú de duelo y
	el servidor solo acepta desafíos enviados desde ahí (salvo la revancha).
]]
local DuelRules = {}

export type Mode = "Informal" | "Duel"

DuelRules.TAX = 0.10
DuelRules.MIN_BET = 10
DuelRules.MAX_BET = 1_000_000
DuelRules.INVITE_TTL = 30 -- s para aceptar un desafío
DuelRules.ZONE_CENTER_ATTR = "DuelZoneCenter"
DuelRules.ZONE_RADIUS_ATTR = "DuelZoneRadius"

-- Premio del ganador para una apuesta por jugador.
function DuelRules.Prize(bet: number): number
	return math.floor(bet * 2 * (1 - DuelRules.TAX))
end

function DuelRules.IsMode(value: unknown): boolean
	return value == "Informal" or value == "Duel"
end

-- Apuesta válida (entero en rango) o nil.
function DuelRules.ValidBet(value: unknown): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	if value < DuelRules.MIN_BET or value > DuelRules.MAX_BET then
		return nil
	end
	return value
end

-- true si `position` está dentro de la arena de duelos del lobby (margen extra en studs).
function DuelRules.InZone(position: Vector3, margin: number?): boolean
	local center = workspace:GetAttribute(DuelRules.ZONE_CENTER_ATTR)
	local radius = workspace:GetAttribute(DuelRules.ZONE_RADIUS_ATTR)
	if typeof(center) ~= "Vector3" or typeof(radius) ~= "number" then
		return false
	end
	local offset = position - center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius + (margin or 0) and math.abs(offset.Y) < 12
end

return DuelRules
