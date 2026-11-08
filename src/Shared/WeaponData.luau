--!strict
--[[
	WeaponData — Fuente única de verdad para las estadísticas de armas.
	Owner: compartido (cambios solo vía PR revisado por ambos desarrolladores).

	Lectores:
	  - Combat  (CombatService / CombatController): Damage, AttackCooldown, Range y las
	    físicas del golpe (Weight, WindupTime, RecoveryTime, PostureDamage, StepForwardForce).
	  - Economy (ShopService / DungeonService / UIController): Acquisition, Price, DropChance,
	    GamePassId (y Damage / AttackCooldown / Range para mostrar estadísticas).

	Ciclo de un ataque (ver CombatService):
	  Windup (WindupTime) → Attacking (frame activo, ~0,1 s) → Recovery (RecoveryTime si falla;
	  más corta si conecta). AttackCooldown es el mínimo entre dos inicios de ataque y debe ser
	  ≥ WindupTime + 0,1.

	El Attribute `Player.EquippedWeapon` SIEMPRE contiene una clave válida de `Weapons`.
]]

-- "Robux": producto de desarrollador de la tienda de Robux (Shared/StoreData, WeaponId = Id).
export type AcquisitionType = "Free" | "Gold" | "GamePass" | "Robux"

-- Light: rápida, poca inercia. Heavy: lenta, mucho compromiso, hyperarmor al final del windup.
export type WeaponWeight = "Light" | "Medium" | "Heavy"

export type WeaponStats = {
	Id: string,
	DisplayName: string,
	Damage: number, -- daño por golpe
	AttackCooldown: number, -- segundos mínimos entre el inicio de dos ataques
	Range: number, -- studs
	Acquisition: AcquisitionType,
	Price: number, -- oro (0 si no se compra con oro)
	DropChance: number, -- 0..1, probabilidad de drop en mazmorra (0 = no dropea)
	GamePassId: number?, -- solo si Acquisition == "GamePass"

	-- Físicas del golpe
	Weight: WeaponWeight, -- define cuánto se frena el jugador al atacar y si tiene hyperarmor
	WindupTime: number, -- s desde el clic hasta que sale el hitbox
	RecoveryTime: number, -- s de castigo si el golpe no conecta (whiff punish)
	PostureDamage: number, -- postura que suma al rival que bloquea (0..100)
	StepForwardForce: number, -- velocidad (studs/s) del paso hacia adelante en el frame activo
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

		Weight = "Light",
		WindupTime = 0.2,
		RecoveryTime = 0.35,
		PostureDamage = 16,
		StepForwardForce = 14,
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

		Weight = "Medium",
		WindupTime = 0.3,
		RecoveryTime = 0.45,
		PostureDamage = 24,
		StepForwardForce = 18,
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

		Weight = "Medium",
		WindupTime = 0.28,
		RecoveryTime = 0.42,
		PostureDamage = 22,
		StepForwardForce = 17,
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

		-- Lanza: ataque rápido y de lejos, poca presión sobre la guardia.
		Weight = "Light",
		WindupTime = 0.22,
		RecoveryTime = 0.38,
		PostureDamage = 18,
		StepForwardForce = 20,
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

		-- Hacha: golpe lento y muy pesado; rompe guardias y tiene hyperarmor.
		Weight = "Heavy",
		WindupTime = 0.5,
		RecoveryTime = 0.65,
		PostureDamage = 40,
		StepForwardForce = 26,
	},

	-- Armas de la tienda de Robux (modelo en Shared/WeaponArt, con efectos).
	PhoenixBlade = {
		Id = "PhoenixBlade",
		DisplayName = "Hoja del Fénix",
		Damage = 34,
		AttackCooldown = 0.7,
		Range = 8,
		Acquisition = "Robux",
		Price = 0,
		DropChance = 0,
		GamePassId = nil,

		Weight = "Medium",
		WindupTime = 0.26,
		RecoveryTime = 0.4,
		PostureDamage = 28,
		StepForwardForce = 20,
	},

	StormHammer = {
		Id = "StormHammer",
		DisplayName = "Martillo del Trueno",
		Damage = 58,
		AttackCooldown = 1.25,
		Range = 7.5,
		Acquisition = "Robux",
		Price = 0,
		DropChance = 0,
		GamePassId = nil,

		-- Martillo: el golpe más pesado del juego; rompe guardias con facilidad.
		Weight = "Heavy",
		WindupTime = 0.55,
		RecoveryTime = 0.7,
		PostureDamage = 48,
		StepForwardForce = 28,
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

		Weight = "Heavy",
		WindupTime = 0.45,
		RecoveryTime = 0.6,
		PostureDamage = 34,
		StepForwardForce = 24,
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
