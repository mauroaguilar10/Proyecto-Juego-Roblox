--!strict
--[[
	ArmorData — Piezas de armadura (fuente única de verdad).
	Owner: Dev B (Economía). Lectores: ArmorService / MonetizationService (servidor),
	ArmorController / PremiumShopController / HealthHUD (cliente), y CombatService / DungeonService
	vía el Attribute Humanoid.Armor que escribe ArmorService.

	Cada pieza ocupa un lugar (Casco, Pechera, Pantalón) y suma:
	  Health: vida máxima extra (sobre BASE_HEALTH).
	  Armor : reducción del daño recibido (0.05 = 5 %). La suma se limita a MAX_ARMOR.

	Cómo se consigue cada set (Acquisition):
	  "Gold"     → se compra pieza por pieza en la armería.
	  "VoidPass" → viene con el Void Pass (se tiene mientras se tenga el pase).
	  "Robux"    → set completo en la tienda de Robux (StoreData, producto con ArmorSet = Id).
]]

export type Slot = "Head" | "Chest" | "Legs"
export type Acquisition = "Gold" | "VoidPass" | "Robux"

export type ArmorPiece = {
	Id: string,
	DisplayName: string,
	Set: string,
	Slot: Slot,
	Health: number,
	Armor: number,
	Price: number, -- oro (solo sets "Gold")
	Acquisition: Acquisition,
}

export type ArmorSet = { Id: string, Name: string, Acquisition: Acquisition }

local SETS: { ArmorSet } = {
	{ Id = "Leather", Name = "Cuero curtido", Acquisition = "Gold" },
	{ Id = "Steel", Name = "Acero del Guardián", Acquisition = "Gold" },
	{ Id = "Ember", Name = "Brasa de Obsidiana", Acquisition = "Gold" },
	{ Id = "Storm", Name = "Armadura de la Tormenta", Acquisition = "Robux" },
	{ Id = "Void", Name = "Armadura del Vacío", Acquisition = "VoidPass" },
}

local acquisitionOf: { [string]: Acquisition } = {}
for _, set in SETS do acquisitionOf[set.Id] = set.Acquisition end

local function piece(id: string, name: string, set: string, slot: Slot, health: number, armor: number, price: number): ArmorPiece
	return table.freeze({
		Id = id, DisplayName = name, Set = set, Slot = slot, Health = health, Armor = armor, Price = price,
		Acquisition = acquisitionOf[set],
	})
end

local Pieces: { [string]: ArmorPiece } = {
	LeatherHelm = piece("LeatherHelm", "Capucha de cuero", "Leather", "Head", 15, 0.03, 150),
	LeatherChest = piece("LeatherChest", "Jubón de cuero", "Leather", "Chest", 25, 0.05, 250),
	LeatherLegs = piece("LeatherLegs", "Grebas de cuero", "Leather", "Legs", 20, 0.04, 200),
	SteelHelm = piece("SteelHelm", "Yelmo de acero", "Steel", "Head", 35, 0.07, 1200),
	SteelChest = piece("SteelChest", "Coraza de acero", "Steel", "Chest", 60, 0.10, 2000),
	SteelLegs = piece("SteelLegs", "Quijotes de acero", "Steel", "Legs", 45, 0.08, 1600),
	EmberHelm = piece("EmberHelm", "Yelmo de brasa", "Ember", "Head", 70, 0.12, 6000),
	EmberChest = piece("EmberChest", "Coraza de brasa", "Ember", "Chest", 120, 0.16, 10000),
	EmberLegs = piece("EmberLegs", "Grebas de brasa", "Ember", "Legs", 90, 0.13, 8000),
	-- Sets premium.
	StormHelm = piece("StormHelm", "Yelmo de la tormenta", "Storm", "Head", 100, 0.14, 0),
	StormChest = piece("StormChest", "Coraza de la tormenta", "Storm", "Chest", 170, 0.19, 0),
	StormLegs = piece("StormLegs", "Grebas de la tormenta", "Storm", "Legs", 130, 0.16, 0),
	VoidHelm = piece("VoidHelm", "Corona del vacío", "Void", "Head", 110, 0.15, 0),
	VoidChest = piece("VoidChest", "Coraza del vacío", "Void", "Chest", 180, 0.20, 0),
	VoidLegs = piece("VoidLegs", "Grebas del vacío", "Void", "Legs", 140, 0.17, 0),
}
table.freeze(Pieces)

local ArmorData = {
	BASE_HEALTH = 100,
	MAX_ARMOR = 0.6,
	SLOTS = table.freeze({ "Head", "Chest", "Legs" }) :: { Slot },
	SLOT_NAMES = table.freeze({ Head = "Casco", Chest = "Pechera", Legs = "Pantalón" }) :: { [Slot]: string },
	SETS = table.freeze(SETS),
	Pieces = Pieces,
}

function ArmorData.Get(id: any): ArmorPiece?
	return if typeof(id) == "string" then Pieces[id] else nil
end

-- Las tres piezas de un set, en orden Casco / Pechera / Pantalón.
function ArmorData.SetPieces(setId: string): { ArmorPiece }
	local list = {}
	for _, slot in ArmorData.SLOTS do
		for _, p in Pieces do
			if p.Set == setId and p.Slot == slot then table.insert(list, p) end
		end
	end
	return list
end

-- Vida extra y armadura totales de lo equipado ({ Head = id, Chest = id, Legs = id }).
function ArmorData.Totals(equipped: { [string]: string }): (number, number)
	local health, armor = 0, 0
	for _, id in equipped do
		local p = Pieces[id]
		if p then
			health += p.Health
			armor += p.Armor
		end
	end
	return health, math.min(armor, ArmorData.MAX_ARMOR)
end

return table.freeze(ArmorData)
