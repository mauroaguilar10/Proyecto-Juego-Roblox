--!strict
--[[
	Sounds (cliente) — Sonidos que escucha solo este jugador: oro, tienda y ambiente de la mazmorra.
	Owner: Dev B (Economía).

	Mismos audios e IDs que src/Server/Economy/Util/Sounds.luau (ver ahí cómo se generan).
	Con un ID en 0 no suena nada (no da error).
]]
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Sounds = {}

local IDS = {
	Efectos = 80420814941625, -- assets/sounds/efectos.wav
	Ambiente = 137020759509134, -- assets/sounds/ambiente_loop.wav
}

type Effect = { start: number, length: number, volume: number }

-- start/length: regiones que imprime tools/generate-sounds.ps1.
local EFFECTS: { [string]: Effect } = {
	Moneda = { start = 0.100, length = 1.200, volume = 0.5 },
	Compra = { start = 1.700, length = 1.700, volume = 0.7 },
	Tienda = { start = 3.800, length = 1.000, volume = 0.5 },
}

local AMBIENT_VOLUME = 0.22
local ambient: Sound? = nil

local function asset(id: number): string?
	return if id > 0 then `rbxassetid://{id}` else nil
end

-- Efecto de interfaz (sin posición en el mundo).
function Sounds.Play(name: string, pitch: number?)
	local effect = EFFECTS[name]
	local id = asset(IDS.Efectos)
	if not effect or not id then return end
	local speed = pitch or 1
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(effect.start, effect.start + effect.length)
	sound.PlaybackSpeed = speed
	sound.Volume = effect.volume
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, effect.length / speed + 0.5)
end

-- Ambiente de la mazmorra: entra y sale con un fundido.
function Sounds.Ambient(on: boolean)
	local id = asset(IDS.Ambiente)
	if not id then return end
	local sound = ambient
	if not sound then
		local created = Instance.new("Sound")
		created.Name = "AmbienteMazmorra"
		created.SoundId = id
		created.Looped = true
		created.Volume = 0
		created.Parent = SoundService
		ambient = created
		sound = created
	end
	local target = sound :: Sound
	if on and not target.IsPlaying then target:Play() end
	local fade = TweenService:Create(target, TweenInfo.new(1.5), { Volume = if on then AMBIENT_VOLUME else 0 })
	fade:Play()
	if not on then
		fade.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and target.Volume == 0 then target:Pause() end
		end)
	end
end

-- Precarga los audios para que el primer sonido no llegue tarde.
function Sounds.Preload()
	local list = {}
	for _, id in { IDS.Efectos, IDS.Ambiente } do
		local soundId = asset(id)
		if soundId then
			local sound = Instance.new("Sound")
			sound.SoundId = soundId
			table.insert(list, sound)
		end
	end
	if #list > 0 then
		task.spawn(function() pcall(ContentProvider.PreloadAsync, ContentProvider, list) end)
	end
end

return Sounds
