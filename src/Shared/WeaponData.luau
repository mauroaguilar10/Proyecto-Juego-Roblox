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

export type AcquisitionType = "Free" | "Gold" | "GamePass"

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
