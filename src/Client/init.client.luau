--!strict
--[[
	Client bootstrap — NO agregar lógica de juego aquí.
	Carga cada ModuleScript de las carpetas en LOAD_ORDER y ejecuta su :Init()
	de forma aislada (pcall + task.spawn): si un controlador falla o está vacío,
	los demás siguen funcionando.

	Los remotes los crea el servidor; los controladores usan
	Remotes.GetEvent / GetFunction, que esperan a que existan.
]]

local LOAD_ORDER = { "Combat", "Economy" }
local TAG = "[Client]"

local function loadModule(moduleScript: ModuleScript)
	local fullName = moduleScript:GetFullName()

	-- require dinámico: tipado como `any` a propósito (cada módulo define su propio tipo)
	local okRequire, controller = pcall((require :: any), moduleScript)
	if not okRequire then
		warn(`{TAG} require falló en {fullName}: {controller}`)
		return
	end

	if type(controller) ~= "table" or type(controller.Init) ~= "function" then
		warn(`{TAG} {fullName} no devuelve una tabla con :Init() — omitido`)
		return
	end

	task.spawn(function()
		local okInit, initErr = pcall(controller.Init, controller)
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
