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
		DropChance = 0, -- sin drops: las armas solo se compran en la tienda
		GamePassId = nil,
	},

	-- Armas detalladas (modelo en Shared/WeaponArt).
	FrostFang = {
		Id = "FrostFang",
		DisplayName = "Colmillo de Escarcha",
		Damage = 21,
		AttackCooldown = 0.7,
		Range = 7.5,
		Acquisition = "Gold",
		Price = 1500,
		DropChance = 0,
		GamePassId = nil,
	},

	DawnSpear = {
		Id = "DawnSpear",
		DisplayName = "Lanza del Alba",
		Damage = 19,
		AttackCooldown = 0.6,
		Range = 10,
		Acquisition = "Gold",
		Price = 3000,
		DropChance = 0,
		GamePassId = nil,
	},

	ColossusAxe = {
		Id = "ColossusAxe",
		DisplayName = "Hacha del Coloso",
		Damage = 38,
		AttackCooldown = 1.1,
		Range = 7,
		Acquisition = "Gold",
		Price = 6000,
		DropChance = 0,
		GamePassId = nil,
	},

	-- Arma del Pase del Vacío (el pase además duplica el oro de la mazmorra: ver DataService).
	VoidScythe = {
		Id = "VoidScythe",
		DisplayName = "Guadaña del Vacío",
		Damage = 30,
		AttackCooldown = 0.85,
		Range = 9,
		Acquisition = "GamePass",
		Price = 0,
		DropChance = 0,
		GamePassId = 2075385839, -- "Void pass" en Roblox
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
