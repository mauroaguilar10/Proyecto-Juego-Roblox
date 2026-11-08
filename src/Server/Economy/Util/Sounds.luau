--!strict
--[[
	Sounds (servidor) — Sonidos de la mazmorra que escuchan todos los que están cerca.
	Owner: Dev B (Economía/Mazmorra).

	Los audios se generan con tools/generate-sounds.ps1 (assets/sounds/) y se suben a Roblox.
	Los efectos cortos están todos en efectos.wav: cada uno se reproduce con PlaybackRegion
	(inicio, duración en segundos), así se sube un solo audio en vez de doce.
	Con un ID en 0 no suena nada (no da error): sirve mientras los audios no están subidos.
	Los mismos IDs están en src/Client/Economy/Util/Sounds.luau.
]]
local Debris = game:GetService("Debris")
local Sounds = {}

local IDS = {
	Efectos = 80420814941625, -- assets/sounds/efectos.wav
	Antorcha = 132399242889240, -- assets/sounds/antorcha_loop.wav
}

type Effect = { start: number, length: number, volume: number, range: number }

-- start/length: regiones que imprime tools/generate-sounds.ps1. range: distancia máxima (studs).
local EFFECTS: { [string]: Effect } = {
	Piedras = { start = 5.200, length = 1.300, volume = 0.7, range = 60 },
	AvisoGolpe = { start = 6.900, length = 0.500, volume = 0.6, range = 45 },
	GolpeRecibido = { start = 7.800, length = 0.350, volume = 0.8, range = 40 },
	JefeCarga = { start = 8.550, length = 1.250, volume = 1, range = 90 },
	JefeGolpe = { start = 10.200, length = 4.000, volume = 1, range = 120 },
	Portal = { start = 14.600, length = 2.500, volume = 0.7, range = 50 },
	Oleada = { start = 17.500, length = 3.800, volume = 0.8, range = 80 },
	OleadaSuperada = { start = 21.700, length = 2.600, volume = 0.8, range = 80 },
	JefeAparece = { start = 24.700, length = 5.700, volume = 1, range = 80 },
}

local function asset(id: number): string?
	return if id > 0 then `rbxassetid://{id}` else nil
end

-- Reproduce un efecto pegado a `parent` (una parte o un Attachment). pitch < 1 = más grave.
function Sounds.Play(name: string, parent: Instance, pitch: number?, volume: number?)
	local effect = EFFECTS[name]
	local id = asset(IDS.Efectos)
	if not effect or not id or not parent.Parent then return end
	local speed = pitch or 1
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(effect.start, effect.start + effect.length)
	sound.PlaybackSpeed = speed
	sound.Volume = effect.volume * (volume or 1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = effect.range * 0.3
	sound.RollOffMaxDistance = effect.range
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, effect.length / speed + 0.5)
end

-- Igual que Play, en un punto del mundo (sirve aunque el objeto que lo causó desaparezca).
function Sounds.PlayAt(name: string, position: Vector3, pitch: number?, volume: number?)
	if not EFFECTS[name] or IDS.Efectos <= 0 then return end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	Sounds.Play(name, anchor, pitch, volume)
	Debris:AddItem(anchor, EFFECTS[name].length / (pitch or 1) + 0.6)
end

-- Todos los fuegos suenan por un mismo SoundGroup con compresor: aunque se escuchen muchas
-- antorchas a la vez, la suma no satura (antes se "rompía" el audio cerca de la arena).
local fireGroup: SoundGroup? = nil
local function getFireGroup(): SoundGroup
	if fireGroup and fireGroup.Parent then return fireGroup end
	local SoundService = game:GetService("SoundService")
	local group = Instance.new("SoundGroup")
	group.Name = "Fuegos"
	group.Volume = 0.6
	local compressor = Instance.new("CompressorSoundEffect")
	compressor.Threshold, compressor.Ratio = -24, 6
	compressor.Attack, compressor.Release = 0.05, 0.4
	compressor.GainMakeup = 0
	compressor.Parent = group
	local soften = Instance.new("EqualizerSoundEffect") -- recorta los agudos del chisporroteo
	soften.HighGain, soften.MidGain, soften.LowGain = -8, -2, 0
	soften.Parent = group
	group.Parent = SoundService
	fireGroup = group
	return group
end

-- Crepitar de fuego en loop para una antorcha o brasero (sutil: solo se oye de cerca).
function Sounds.Torch(parent: Instance, volume: number?)
	local id = asset(IDS.Antorcha)
	if not id then return end
	local sound = Instance.new("Sound")
	sound.Name = "Fuego"
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = volume or 0.14
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2 -- que no suenen todas iguales
	sound.TimePosition = math.random() * 3
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 3
	sound.RollOffMaxDistance = 18
	sound.SoundGroup = getFireGroup()
	sound.Parent = parent
	sound:Play()
end

return Sounds
