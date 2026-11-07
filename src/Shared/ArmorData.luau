--!strict
--[[
	ArmorData — Piezas de armadura de la armería (fuente única de verdad).
	Owner: Dev B (Economía). Lectores: ArmorService (servidor), ArmorController y HealthHUD (cliente),
	CombatService / DungeonService (vía el Attribute Humanoid.Armor que escribe ArmorService).

	Cada pieza ocupa un lugar (Casco, Pechera, Pantalón) y suma:
	  Health: vida máxima extra (sobre BASE_HEALTH).
	  Armor : reducción del daño recibido (0.05 = 5 %). La suma se limita a MAX_ARMOR.
]]

export type Slot = "Head" | "Chest" | "Legs"

export type ArmorPiece = {
	Id: string,
	DisplayName: string,
	Set: string,
	Slot: Slot,
	Health: number,
	Armor: number,
	Price: number, -- oro
}

local SETS = {
	{ Id = "Leather", Name = "Cuero curtido" },
	{ Id = "Steel", Name = "Acero del Guardián" },
	{ Id = "Ember", Name = "Brasa de Obsidiana" },
}

local function piece(id: string, name: string, set: string, slot: Slot, health: number, armor: number, price: number): ArmorPiece
	return table.freeze({ Id = id, DisplayName = name, Set = set, Slot = slot, Health = health, Armor = armor, Price = price })
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
