--!strict
--[[
	Remotes — Registro central de RemoteEvents / RemoteFunctions.
	Owner: compartido (agregar un remote = PR revisado por ambos desarrolladores).

	- Servidor: `Remotes.Init()` (lo llama init.server.luau ANTES de cargar servicios)
	  crea la carpeta `ReplicatedStorage.Remotes` con todas las instancias declaradas abajo.
	- Cliente: `GetEvent` / `GetFunction` esperan (WaitForChild) a que el servidor las cree.

	La carpeta se crea en runtime fuera de `ReplicatedStorage.Shared` para que Rojo
	no la toque durante el live-sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ── Declaración de remotes (añadir aquí; el tipo de abajo debe coincidir) ──

export type EventName =
	-- Combat (Dev A)
	"CombatAttack" -- C→S: el cliente solicita atacar
	| "CombatFeedback" -- S→C: hit confirmado, daño, efectos
	| "DuelRequest" -- C→S: desafiar a otro jugador
	| "DuelInvite" -- S→C: notificar desafío recibido
	| "DuelResponse" -- C→S: aceptar / rechazar
	| "DuelStateChanged" -- S→C: inicio, cuenta regresiva, fin
	-- Economy (Dev B)
	| "EquipWeapon" -- C→S: equipar arma poseída
	| "Notify" -- S→C: mensajes genéricos para la UI

export type FunctionName =
	-- Economy (Dev B)
	"PurchaseWeapon" -- C→S→C: comprar arma, devuelve resultado
	| "GetInventory" -- C→S→C: lista de armas poseídas

local EVENT_NAMES: { EventName } = {
	"CombatAttack",
	"CombatFeedback",
	"DuelRequest",
	"DuelInvite",
	"DuelResponse",
	"DuelStateChanged",
	"EquipWeapon",
	"Notify",
}

local FUNCTION_NAMES: { FunctionName } = {
	"PurchaseWeapon",
	"GetInventory",
}

-- ── Implementación ──

local FOLDER_NAME = "Remotes"
local WAIT_TIMEOUT = 10

local IS_SERVER = RunService:IsServer()

local folder: Folder? = nil
local eventCache: { [string]: RemoteEvent } = {}
local functionCache: { [string]: RemoteFunction } = {}

local Remotes = {}

local function getFolder(): Folder
	if folder then
		return folder
	end

	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			local newFolder = Instance.new("Folder")
			newFolder.Name = FOLDER_NAME
			newFolder.Parent = ReplicatedStorage
			folder = newFolder
		end
	else
		local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
		assert(found and found:IsA("Folder"), `[Remotes] ReplicatedStorage.{FOLDER_NAME} no apareció`)
		folder = found
	end

	return folder :: Folder
end

local function createOrGet(className: "RemoteEvent" | "RemoteFunction", name: string): Instance
	local parent = getFolder()
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing.ClassName == className, `[Remotes] '{name}' existe pero no es {className}`)
		return existing
	end
	local instance: Instance = if className == "RemoteEvent"
		then Instance.new("RemoteEvent")
		else Instance.new("RemoteFunction")
	instance.Name = name
	instance.Parent = parent
	return instance
end

-- Solo servidor. Idempotente.
function Remotes.Init()
	assert(IS_SERVER, "[Remotes] Init() solo puede llamarse desde el servidor")

	for _, name in EVENT_NAMES do
		eventCache[name] = createOrGet("RemoteEvent", name) :: RemoteEvent
	end
	for _, name in FUNCTION_NAMES do
		functionCache[name] = createOrGet("RemoteFunction", name) :: RemoteFunction
	end
end

function Remotes.GetEvent(name: EventName): RemoteEvent
	local cached = eventCache[name]
	if cached then
		return cached
	end

	local instance: Instance?
	if IS_SERVER then
		assert(table.find(EVENT_NAMES, name), `[Remotes] RemoteEvent no declarado: {name}`)
		instance = createOrGet("RemoteEvent", name)
	else
		instance = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	end

	assert(instance and instance:IsA("RemoteEvent"), `[Remotes] RemoteEvent '{name}' no encontrado`)
	eventCache[name] = instance
	return instance
end

function Remotes.GetFunction(name: FunctionName): RemoteFunction
	local cached = functionCache[name]
	if cached then
		return cached
	end

	local instance: Instance?
	if IS_SERVER then
		assert(table.find(FUNCTION_NAMES, name), `[Remotes] RemoteFunction no declarada: {name}`)
		instance = createOrGet("RemoteFunction", name)
	else
		instance = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	end

	assert(instance and instance:IsA("RemoteFunction"), `[Remotes] RemoteFunction '{name}' no encontrada`)
	functionCache[name] = instance
	return instance
end

return Remotes
