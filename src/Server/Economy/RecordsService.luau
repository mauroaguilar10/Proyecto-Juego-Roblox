--!strict
--[[
	RecordsService — Tablero de récords global en el lobby (mejor oleada de la mazmorra).
	Owner: Dev B (Economía/Mazmorra).

	- Guarda la mejor oleada de cada jugador en un OrderedDataStore y muestra el top 10
	  en un cartel junto al spawn. Se actualiza cada REFRESH_SECONDS.
	- En un place sin publicar (DataService.IsPersistent() == false) no hay DataStores:
	  el cartel muestra solo a los jugadores conectados.
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Data = require(script.Parent:WaitForChild("DataService"))
local Layout = require(script.Parent:WaitForChild("Lobby"):WaitForChild("Layout"))
local RecordsService = {}

local REFRESH_SECONDS = 60
local TOP = 10
local BOARD_SIZE = Vector3.new(10, 9, 0.6)

type Entry = { name: string, wave: number }

local written: { [number]: number } = {} -- userId → última oleada guardada
local names: { [number]: string } = {}
local store: OrderedDataStore? = nil
local uploading = 0 -- guardados en curso (BindToClose espera a que llegue a 0)

local function getName(userId: number): string
	local cached = names[userId]
	if cached then return cached end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok and typeof(name) == "string" then name else "Jugador"
	names[userId] = result
	return result
end

-- Se lee de leaderstats (lo mantiene DataService) porque al salir el jugador el perfil
-- puede estar ya cerrado, pero el IntValue sigue existiendo.
local function bestWave(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	local stat = if stats then stats:FindFirstChild(Data.STAT_BEST_WAVE) else nil
	return if stat and stat:IsA("IntValue") then stat.Value else 0
end

-- Sube a la tabla global la mejor oleada del jugador si mejoró desde la última vez.
local function upload(player: Player)
	local value = bestWave(player)
	local userId = player.UserId
	if not store or value <= 0 or value <= (written[userId] or 0) then return end
	uploading += 1
	local ok, err = pcall(function()
		(store :: OrderedDataStore):UpdateAsync(tostring(userId), function(old: any)
			return math.max(if typeof(old) == "number" then old else 0, value)
		end)
	end)
	uploading -= 1
	if ok then
		written[userId] = value
	else
		warn("[Records] No se pudo guardar el récord", userId, err)
	end
end

local function fetchTop(): { Entry }
	local entries: { Entry } = {}
	if store then
		local ok, page = pcall(function()
			return (store :: OrderedDataStore):GetSortedAsync(false, TOP, 1):GetCurrentPage()
		end)
		if ok then
			for _, row in page do
				local userId = tonumber(row.key)
				if userId then
					table.insert(entries, { name = getName(userId), wave = row.value })
				end
			end
			return entries
		end
		warn("[Records] No se pudo leer el top", page)
	end
	-- Sin DataStore (o si falló): jugadores conectados.
	for _, player in Players:GetPlayers() do
		local wave = bestWave(player)
		if wave > 0 then table.insert(entries, { name = player.DisplayName, wave = wave }) end
	end
	table.sort(entries, function(a, b) return a.wave > b.wave end)
	while #entries > TOP do table.remove(entries) end
	return entries
end

local function buildBoard(): { TextLabel }
	local board = Instance.new("Part")
	board.Name = "TablaDeRecords"
	board.Anchored = true
	board.Size = BOARD_SIZE
	board.Color = Color3.fromRGB(15, 19, 26)
	board.Material = Enum.Material.SmoothPlastic
	-- Posición según el plano del lobby (Lobby/Layout): noroeste; la cara frontal mira al camino.
	board.CFrame = Layout.Facing(Layout.RECORDS, BOARD_SIZE.Y / 2 + 1.5)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = board

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.Parent = gui

	local function row(order: number, height: number, size: number, color: Color3): TextLabel
		local text = Instance.new("TextLabel")
		text.LayoutOrder = order
		text.Size = UDim2.new(1, -40, 0, height)
		text.BackgroundTransparency = 1
		text.Font = if order == 0 then Enum.Font.Antique else Enum.Font.GothamMedium
		text.TextSize = size
		text.TextColor3 = color
		text.TextXAlignment = if order == 0 then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		text.Text = ""
		text.Parent = gui
		return text
	end
	row(0, 60, 44, Color3.fromRGB(237, 197, 118)).Text = "Récords · Mazmorra"
	local rows = {}
	for i = 1, TOP do
		table.insert(rows, row(i, 34, 26, Color3.fromRGB(246, 237, 216)))
	end
	board.Parent = workspace
	return rows
end

local function render(rows: { TextLabel }, entries: { Entry })
	for i, text in rows do
		local entry = entries[i]
		if entry then
			text.Text = `{i}.  {entry.name}  —  oleada {entry.wave}`
		elseif i == 1 then
			text.Text = "Todavía no hay récords. ¡Entrá a la mazmorra!"
		else
			text.Text = ""
		end
	end
end

function RecordsService:Init()
	if Data.IsPersistent() then
		local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "BestWave_v1")
		if ok then store = result else warn("[Records] OrderedDataStore no disponible", result) end
	end
	local rows = buildBoard()
	Players.PlayerRemoving:Connect(function(player)
		upload(player)
		written[player.UserId] = nil
	end)
	-- Al cerrar el servidor, esperar a que terminen TODOS los guardados en curso, también los
	-- que lanzó PlayerRemoving (al apagarse, los jugadores suelen salir antes de BindToClose).
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do task.spawn(upload, player) end
		local deadline = os.clock() + 25
		while uploading > 0 and os.clock() < deadline do task.wait(0.1) end
	end)
	-- Sin DataStore el cartel solo lee memoria: se puede refrescar seguido (útil para probar en Studio).
	local interval = if store then REFRESH_SECONDS else 5
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do upload(player) end
			render(rows, fetchTop())
			task.wait(interval)
		end
	end)
end

return RecordsService
