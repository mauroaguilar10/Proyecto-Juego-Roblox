--!strict
--[[
	WeaponData — Fuente única de verdad para las estadísticas de armas.
	Owner: compartido (cambios solo vía PR revisado por ambos desarrolladores).

	Lectores:
	  - Combat  (CombatService / CombatController): Damage, Cooldown, Range.
	  - Economy (ShopService / DungeonService / UIController): Acquisition, Price, DropChance, GamePassId.

	El Attribute `Player.EquippedWeapon` SIEMPRE contiene una clave válida de `Weapons`.
]]

export type AcquisitionType = "Free" | "Gold" | "GamePass"

export type WeaponStats = {
	Id: string,
	DisplayName: string,
	Damage: number, -- daño por golpe
	AttackCooldown: number, -- segundos entre ataques
	Range: number, -- studs
	Acquisition: AcquisitionType,
	Price: number, -- oro (0 si no se compra con oro)
	DropChance: number, -- 0..1, probabilidad de drop en mazmorra (0 = no dropea)
	GamePassId: number?, -- solo si Acquisition == "GamePass"
}

local Weapons: { [string]: WeaponStats } = {
	WoodenSword = {
		Id = "WoodenSword",
		DisplayName = "Espada de Madera",
		Damage = 10,
		AttackCooldown = 0.6,
		Range = 6,
		Acquisition = "Free",
		Price = 0,
		DropChance = 0,
		GamePassId = nil,
	},

	IronBlade = {
		Id = "IronBlade",
		DisplayName = "Hoja de Hierro",
		Damage = 18,
		AttackCooldown = 0.75,
		Range = 7,
		Acquisition = "Gold",
		Price = 500,
		DropChance = 0.05,
		GamePassId = nil,
	},

	VoidScythe = {
		Id = "VoidScythe",
		DisplayName = "Guadaña del Vacío",
		Damage = 24,
		AttackCooldown = 0.9,
		Range = 9,
		Acquisition = "GamePass",
		Price = 0,
		DropChance = 0,
		GamePassId = 0, -- TODO: reemplazar por el ID real del GamePass
	},
}

for _, weapon in Weapons do
	table.freeze(weapon)
end
table.freeze(Weapons)

local WeaponData = {
	DEFAULT_WEAPON = "WoodenSword",
	Weapons = Weapons,
}

function WeaponData.Get(weaponId: string): WeaponStats?
	return Weapons[weaponId]
end

-- Devuelve el arma pedida o, si el Id es inválido, el arma por defecto. Nunca nil.
function WeaponData.GetOrDefault(weaponId: string?): WeaponStats
	local weapon = if weaponId then Weapons[weaponId] else nil
	return weapon or Weapons[WeaponData.DEFAULT_WEAPON]
end

function WeaponData.IsValid(weaponId: string): boolean
	return Weapons[weaponId] ~= nil
end

return table.freeze(WeaponData)
