--!strict
--[[
	CombatStyles — Estilo visual de cada arma al atacar (solo cliente).
	Owner: Dev B (Economía) — complementa CombatAnimations / CombatVisuals de Dev A.

	Por arma: colores del arco de corte, tipo de impacto (Normal / Fire / Storm / Void / Frost),
	forma del arco por golpe del combo (Sweep) y, para las armas especiales (Robux / Void Pass),
	animaciones propias (cargas y tajos) y un efecto de remate en el golpe 3.

	Sweeps (vistos desde el personaje):
	  V     de arriba hacia abajo        VUp   de abajo hacia arriba
	  H     de derecha a izquierda        HRev  de izquierda a derecha
	  D     arriba-derecha → abajo-izq.   DL    arriba-izquierda → abajo-der.
	  DRev  abajo-izquierda → arriba-der. Spin  giro completo
]]
local CombatAnimations = require(script.Parent:WaitForChild("CombatAnimations"))

type Pose = CombatAnimations.Pose
export type Sweep = "V" | "VUp" | "H" | "HRev" | "D" | "DL" | "DRev" | "Spin"
export type Kind = "Normal" | "Fire" | "Storm" | "Void" | "Frost"
export type Finisher = "Shockwave" | "FirePillar" | "VoidRing"
export type Style = {
	color: Color3, -- borde del arco / chispas
	core: Color3, -- centro brillante del arco
	kind: Kind,
	width: number, -- grosor del arco
	sweeps: { Sweep },
	special: boolean, -- aura de carga + animaciones propias
	windup: { Pose }?, -- pose de carga por golpe del combo
	slash: { { Pose } }?, -- secuencia del tajo por golpe del combo
	finisher: Finisher?,
}

local V = Vector3.new

-- Giro completo para la guadaña: los mismos brazos con la raíz rotando 120° por paso.
local function spin(arms: Pose): { Pose }
	local steps: { Pose } = {}
	for i = 1, 3 do
		local pose = table.clone(arms)
		pose.Root = { y = 120 * i, pos = V(0, -0.3, 0) }
		table.insert(steps, pose)
	end
	return steps
end

local SCYTHE_WINDUP: { Pose } = {
	{ RShoulder = { p = 95, y = -75, r = 20 }, RElbow = { p = 30 }, RWrist = { p = -10 }, LShoulder = { p = 80, y = -35 }, LElbow = { p = 55 },
		Waist = { y = -55, p = 6 }, Neck = { y = 30 }, Root = { pos = V(0, -0.25, 0) }, RHip = { p = -10 }, RKnee = { p = -22 }, LHip = { p = 22 }, LKnee = { p = -28 } },
	{ RShoulder = { p = 155, y = 55, r = -10 }, RElbow = { p = 35 }, LShoulder = { p = 125, y = 40 }, LElbow = { p = 45 },
		Waist = { y = 40, p = 10 }, Neck = { y = -20, p = 6 }, RHip = { p = 12 }, LHip = { p = -8 }, LKnee = { p = -12 } },
	{ RShoulder = { p = 85, y = -95, r = 25 }, RElbow = { p = 20 }, LShoulder = { p = 70, y = -60 }, LElbow = { p = 40 },
		Waist = { y = -75, r = -8 }, Neck = { y = 45 }, Root = { pos = V(0, -0.5, 0) }, RHip = { p = 25 }, RKnee = { p = -45 }, LHip = { p = -10 }, LKnee = { p = -35 } },
}
local SCYTHE_SLASH: { { Pose } } = {
	{ { RShoulder = { p = 75, y = 85, r = -10 }, RElbow = { p = 8 }, RWrist = { p = 10 }, LShoulder = { p = 35, y = 65 }, LElbow = { p = 20 },
		Waist = { y = 60, r = 6 }, Neck = { y = -35 }, Root = { pos = V(0, -0.3, 0) }, RHip = { p = 20 }, RKnee = { p = -25 }, LHip = { p = -12 } } },
	{ { RShoulder = { p = 15, y = -55, r = 25 }, RElbow = { p = 10 }, LShoulder = { p = 10, y = -40 }, LElbow = { p = 30 },
		Waist = { y = -45, p = -22 }, Neck = { p = -10, y = 20 }, Root = { pos = V(0, -0.4, 0) }, RHip = { p = 30 }, RKnee = { p = -40 }, LHip = { p = -15 }, LKnee = { p = -10 } } },
	spin({ RShoulder = { p = 90, y = -10, r = 35 }, RElbow = { p = 5 }, LShoulder = { p = 60, r = -40 }, LElbow = { p = 20 },
		Waist = { p = -10 }, RHip = { p = 15 }, RKnee = { p = -30 }, LHip = { p = -10 }, LKnee = { p = -20 } }),
}

local HAMMER_WINDUP: { Pose } = {
	{ RShoulder = { p = 170, y = -5 }, RElbow = { p = 80 }, RWrist = { p = 20 }, LShoulder = { p = 165, y = -25, r = 15 }, LElbow = { p = 80 },
		Waist = { p = 22 }, Neck = { p = 12 }, RHip = { p = -6 }, LHip = { p = 10 }, LKnee = { p = -10 } },
	{ RShoulder = { p = 80, y = -100, r = 20 }, RElbow = { p = 25 }, LShoulder = { p = 70, y = -55 }, LElbow = { p = 50 },
		Waist = { y = -65, r = -10 }, Neck = { y = 40 }, Root = { pos = V(0, -0.2, 0) }, RHip = { p = -12 }, RKnee = { p = -22 }, LHip = { p = 18 }, LKnee = { p = -18 } },
	-- Salto: el torso sube y las piernas se recogen.
	{ RShoulder = { p = 175 }, RElbow = { p = 60 }, LShoulder = { p = 170, y = -20, r = 10 }, LElbow = { p = 60 },
		Waist = { p = 25 }, Neck = { p = 18 }, Root = { pos = V(0, 0.9, 0) }, RHip = { p = 55 }, RKnee = { p = -85 }, LHip = { p = 45 }, LKnee = { p = -80 } },
}
local HAMMER_SLASH: { { Pose } } = {
	{ { RShoulder = { p = 35 }, RElbow = { p = 5 }, RWrist = { p = -20 }, LShoulder = { p = 40, y = -20 }, LElbow = { p = 15 },
		Waist = { p = -40 }, Neck = { p = -15 }, Root = { pos = V(0, -0.6, 0) }, RHip = { p = 40 }, RKnee = { p = -55 }, LHip = { p = -20 }, LKnee = { p = -20 } } },
	{ { RShoulder = { p = 85, y = 95, r = -5 }, RElbow = { p = 5 }, LShoulder = { p = 70, y = 75 }, LElbow = { p = 15 },
		Waist = { y = 65, r = 8 }, Neck = { y = -35 }, Root = { pos = V(0, -0.25, 0) }, RHip = { p = 18 }, RKnee = { p = -20 }, LHip = { p = -12 } } },
	{ { RShoulder = { p = 20 }, RElbow = { p = 5 }, RWrist = { p = -25 }, LShoulder = { p = 25, y = -15 }, LElbow = { p = 10 },
		Waist = { p = -48 }, Neck = { p = -18 }, Root = { pos = V(0, -0.9, 0) }, RHip = { p = 55 }, RKnee = { p = -80 }, LHip = { p = -25 }, LKnee = { p = -40 } } },
}

local PHOENIX_WINDUP: { Pose } = {
	{ RShoulder = { p = 145, y = -40, r = 30 }, RElbow = { p = 35 }, RWrist = { p = 20 }, LShoulder = { p = 40, r = -25 }, LElbow = { p = 30 },
		Waist = { y = -30, p = 8 }, Neck = { y = 15 }, RHip = { p = -6 }, LHip = { p = 12 }, LKnee = { p = -14 } },
	{ RShoulder = { p = 35, y = 65, r = -20 }, RElbow = { p = 25 }, RWrist = { p = -15 }, LShoulder = { p = 20, r = -30 },
		Waist = { y = 45, p = -6 }, Neck = { y = -20 }, Root = { pos = V(0, -0.25, 0) }, RHip = { p = 15 }, RKnee = { p = -25 }, LHip = { p = -10 }, LKnee = { p = -15 } },
	-- Agachado con la hoja baja y atrás, listo para el tajo ascendente.
	{ RShoulder = { p = -35, y = -10, r = 25 }, RElbow = { p = 15 }, RWrist = { p = -20 }, LShoulder = { p = 60, r = -20 }, LElbow = { p = 40 },
		Waist = { p = -22, y = -20 }, Neck = { p = -6 }, Root = { pos = V(0, -0.55, 0) }, RHip = { p = 40 }, RKnee = { p = -70 }, LHip = { p = -25 }, LKnee = { p = -35 } },
}
local PHOENIX_SLASH: { { Pose } } = {
	{ { RShoulder = { p = 25, y = 55, r = -10 }, RElbow = { p = 8 }, RWrist = { p = -15 }, LShoulder = { p = -10, r = -20 },
		Waist = { y = 40, p = -14 }, Neck = { y = -15, p = -6 }, RHip = { p = 20 }, RKnee = { p = -20 }, LHip = { p = -12 } } },
	{ { RShoulder = { p = 165, y = -45, r = 25 }, RElbow = { p = 10 }, RWrist = { p = 20 }, LShoulder = { p = 10, r = -35 },
		Waist = { y = -35, p = 12 }, Neck = { y = 15, p = 10 }, RHip = { p = -8 }, LHip = { p = 14 }, LKnee = { p = -10 } } },
	{ { RShoulder = { p = 178, y = -5 }, RElbow = { p = 5 }, RWrist = { p = 15 }, LShoulder = { p = 150, r = -35 }, LElbow = { p = 10 },
		Waist = { p = 16 }, Neck = { p = 18 }, Root = { pos = V(0, 0.7, 0) }, RHip = { p = -12 }, LHip = { p = 45 }, LKnee = { p = -70 } } },
}

local DEFAULT: Style = {
	color = Color3.fromRGB(210, 225, 255), core = Color3.new(1, 1, 1), kind = "Normal", width = 1,
	sweeps = { "V", "H", "V" }, special = false,
}

local STYLES: { [string]: Style } = {
	WoodenSword = { color = Color3.fromRGB(235, 215, 170), core = Color3.fromRGB(255, 250, 235), kind = "Normal", width = 0.8,
		sweeps = { "V", "H", "V" }, special = false },
	IronBlade = DEFAULT,
	FrostFang = { color = Color3.fromRGB(120, 210, 255), core = Color3.fromRGB(230, 250, 255), kind = "Frost", width = 1,
		sweeps = { "V", "H", "V" }, special = false },
	DawnSpear = { color = Color3.fromRGB(255, 214, 110), core = Color3.fromRGB(255, 250, 220), kind = "Normal", width = 0.8,
		sweeps = { "V", "H", "V" }, special = false },
	ColossusAxe = { color = Color3.fromRGB(255, 140, 60), core = Color3.fromRGB(255, 225, 180), kind = "Normal", width = 1.3,
		sweeps = { "V", "H", "V" }, special = false, finisher = "Shockwave" },
	PhoenixBlade = { color = Color3.fromRGB(255, 120, 30), core = Color3.fromRGB(255, 235, 140), kind = "Fire", width = 1.2,
		sweeps = { "D", "DRev", "VUp" }, special = true, windup = PHOENIX_WINDUP, slash = PHOENIX_SLASH, finisher = "FirePillar" },
	StormHammer = { color = Color3.fromRGB(90, 210, 255), core = Color3.fromRGB(235, 250, 255), kind = "Storm", width = 1.5,
		sweeps = { "V", "H", "V" }, special = true, windup = HAMMER_WINDUP, slash = HAMMER_SLASH, finisher = "Shockwave" },
	VoidScythe = { color = Color3.fromRGB(200, 70, 255), core = Color3.fromRGB(255, 200, 255), kind = "Void", width = 1.4,
		sweeps = { "H", "DL", "Spin" }, special = true, windup = SCYTHE_WINDUP, slash = SCYTHE_SLASH, finisher = "VoidRing" },
}

local CombatStyles = {}

function CombatStyles.Get(weaponId: string?): Style
	return if weaponId then STYLES[weaponId] or DEFAULT else DEFAULT
end

return CombatStyles
