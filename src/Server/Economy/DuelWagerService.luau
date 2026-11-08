--!strict
--[[
	DuelWagerService — Oro apostado en los duelos (modo "Duel").
	Owner: Dev B (Economía). Lo llama ArenaService (Combat), que nunca toca Gold directamente.

	  CanAfford(player, bet)   → tiene oro suficiente.
	  Escrow(a, b, bet)        → descuenta la apuesta a los dos (todo o nada).
	  Payout(winner, bet)      → paga el premio (pozo − impuesto, ver DuelRules.Prize).
	  Refund(players, bet)     → devuelve la apuesta (empate).
	Después de cada movimiento se guarda el perfil (DataService.SaveNow).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DuelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DuelRules"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local DuelWagerService = {}

local function gold(player: Player): number
	local profile = DataService.Profile(player)
	return if profile then profile.gold else 0
end

local function save(player: Player)
	if player.Parent then
		task.spawn(DataService.SaveNow, player)
	end
end

function DuelWagerService.CanAfford(player: Player, bet: number): boolean
	return DataService.Profile(player) ~= nil and gold(player) >= bet
end

function DuelWagerService.Escrow(a: Player, b: Player, bet: number): boolean
	if not DuelWagerService.CanAfford(a, bet) or not DuelWagerService.CanAfford(b, bet) then
		return false
	end
	if not DataService.ChangeGold(a, -bet) then
		return false
	end
	if not DataService.ChangeGold(b, -bet) then
		DataService.ChangeGold(a, bet)
		return false
	end
	save(a)
	save(b)
	print(`[Economy] Duelo: {a.Name} y {b.Name} apuestan {bet} de oro`)
	return true
end

function DuelWagerService.Payout(winner: Player, bet: number): number
	local prize = DuelRules.Prize(bet)
	if winner.Parent and DataService.ChangeGold(winner, prize) then
		save(winner)
		print(`[Economy] Duelo: {winner.Name} gana {prize} de oro`)
	end
	return prize
end

function DuelWagerService.Refund(players: { Player }, bet: number)
	for _, player in players do
		if player.Parent and DataService.ChangeGold(player, bet) then
			save(player)
		end
	end
end

function DuelWagerService:Init() end

return DuelWagerService
