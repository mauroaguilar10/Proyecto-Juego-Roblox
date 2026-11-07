--!strict
--[[
	Server bootstrap — NO agregar lógica de juego aquí.
	1. Crea los remotes (Shared/Remotes).
	2. Carga cada ModuleScript de las carpetas en LOAD_ORDER y ejecuta su :Init()
	   de forma aislada (pcall + task.spawn): si un módulo falla o está vacío,
	   los demás siguen funcionando.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: any

local LOAD_ORDER = { "Combat", "Economy" }
local TAG = "[Server]"

local okRemotes, remotesErr = pcall(Remotes.Init)
if not okRemotes then
	warn(`{TAG} Remotes.Init falló: {remotesErr}`)
end

local function loadModule(moduleScript: ModuleScript)
	local fullName = moduleScript:GetFullName()

	-- require dinámico: tipado como `any` a propósito (cada módulo define su propio tipo)
	local okRequire, service = pcall((require :: any), moduleScript)
	if not okRequire then
		warn(`{TAG} require falló en {fullName}: {service}`)
		return
	end

	if type(service) ~= "table" or type(service.Init) ~= "function" then
		warn(`{TAG} {fullName} no devuelve una tabla con :Init() — omitido`)
		return
	end

	task.spawn(function()
		local okInit, initErr = pcall(service.Init, service)
		if okInit then
			print(`{TAG} ✓ {moduleScript.Name}`)
		else
			warn(`{TAG} ✗ {moduleScript.Name}:Init() falló: {initErr}`)
		end
	end)
end

for _, folderName in LOAD_ORDER do
	local folder = script:FindFirstChild(folderName)
	if not folder then
		warn(`{TAG} Carpeta '{folderName}' no encontrada — omitida`)
		continue
	end

	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			loadModule(child)
		end
	end
end
