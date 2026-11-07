--!strict
--[[
	ArmorService — Armería: comprar, equipar y quitar piezas de armadura, y aplicarlas al personaje.
	Owner: Dev B (Economía).

	Remote "ArmorShop" (C→S→C): (acción, pieceId) → (ok, mensaje, estado)
	  "Get"     → estado actual.
	  "Buy"     → cobra el oro, la agrega al inventario y la equipa.
	  "Equip"   → la equipa en su lugar (Casco / Pechera / Pantalón).
	  "Unequip" → la quita.
	  estado = { owned = { [pieceId] = true }, equipped = { [Slot] = pieceId } }
	No se puede cambiar la armadura durante un duelo.

	En el personaje:
	  - Cada pieza es un Model "Armadura_<Slot>" (Shared/ArmorArt) soldado al cuerpo.
	  - Los accesorios del avatar que chocarían con la pieza (sombreros y pelo con el casco, etc.)
	    se guardan aparte mientras la pieza está puesta y vuelven al quitarla.
	  - Humanoid.MaxHealth = ArmorData.BASE_HEALTH + vida de las piezas.
	  - Humanoid.Armor (Attribute, 0..MAX_ARMOR) = reducción del daño recibido; la aplican
	    DungeonService (golpes de guardianes) y CombatService (duelos).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArmorData = require(Shared:WaitForChild("ArmorData"))
local ArmorArt = require(Shared:WaitForChild("ArmorArt"))
local Data = require(script.Parent:WaitForChild("DataService"))
local ArmorService = {}

-- Tipos de accesorio que tapa cada lugar de la armadura.
local HIDES: { [string]: { Enum.AccessoryType } } = {
	Head = { Enum.AccessoryType.Hat, Enum.AccessoryType.Hair, Enum.AccessoryType.Face,
		Enum.AccessoryType.Eyebrow, Enum.AccessoryType.Eyelash },
	Chest = { Enum.AccessoryType.Neck, Enum.AccessoryType.Shoulder, Enum.AccessoryType.Front, Enum.AccessoryType.Back,
		Enum.AccessoryType.TShirt, Enum.AccessoryType.Shirt, Enum.AccessoryType.Jacket, Enum.AccessoryType.Sweater },
	Legs = { Enum.AccessoryType.Waist, Enum.AccessoryType.Pants, Enum.AccessoryType.Shorts,
		Enum.AccessoryType.DressSkirt, Enum.AccessoryType.LeftShoe, Enum.AccessoryType.RightShoe },
}

local hiddenRoot = Instance.new("Folder")
hiddenRoot.Name = "AccesoriosOcultos"
local lastAction: { [Player]: number } = {}

local function slotFor(accessory: Accessory): string?
	local kind = accessory.AccessoryType
	for slot, kinds in HIDES do
		if table.find(kinds, kind) then return slot end
	end
	return nil
end

local function hiddenFolder(player: Player): Folder
	local folder = hiddenRoot:FindFirstChild(tostring(player.UserId))
	if folder and folder:IsA("Folder") then return folder end
	local created = Instance.new("Folder")
	created.Name = tostring(player.UserId)
	created.Parent = hiddenRoot
	return created
end

local function state(player: Player): any
	local p = Data.Profile(player)
	if not p then return nil end
	return { owned = table.clone(p.armorOwned), equipped = table.clone(p.armorEquipped) }
end

-- Pone en el personaje exactamente lo que está equipado en el perfil.
local function apply(player: Player)
	local p = Data.Profile(player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not p or not character or not humanoid then return end
	local equipped = p.armorEquipped
	local folder = hiddenFolder(player)

	-- Accesorios: devolver los de lugares libres, esconder los que chocan con lo puesto.
	for _, item in folder:GetChildren() do
		local slot = item:GetAttribute("OcultoPor")
		if typeof(slot) == "string" and not equipped[slot] then
			item:SetAttribute("OcultoPor", nil)
			item.Parent = character
		end
	end
	for _, item in character:GetChildren() do
		if item:IsA("Accessory") then
			local slot = slotFor(item)
			if slot and equipped[slot] then
				item:SetAttribute("OcultoPor", slot)
				item.Parent = folder
			end
		end
	end

	-- Modelos de las piezas.
	for _, slot in ArmorData.SLOTS do
		local current = character:FindFirstChild(`Armadura_{slot}`)
		local id = equipped[slot]
		if current and (not id or current:GetAttribute("PieceId") ~= id) then
			current:Destroy()
			current = nil
		end
		if id and not current then
			ArmorArt.Build(id, slot, character).Parent = character
		end
	end

	-- Vida máxima y armadura.
	local bonus, armor = ArmorData.Totals(equipped)
	local newMax = ArmorData.BASE_HEALTH + bonus
	local oldMax = humanoid.MaxHealth
	humanoid.MaxHealth = newMax
	if humanoid.Health > 0 then
		humanoid.Health = math.clamp(humanoid.Health + math.max(0, newMax - oldMax), 1, newMax)
	end
	humanoid:SetAttribute("Armor", armor)
end

local function onCharacter(player: Player, character: Model)
	-- Esperar a que el perfil cargue y a que el avatar tenga sus accesorios.
	local deadline = os.clock() + 30
	while not Data.Profile(player) and os.clock() < deadline and player.Character == character do
		task.wait(0.5)
	end
	if not player:HasAppearanceLoaded() then
		local done = false
		local conn = player.CharacterAppearanceLoaded:Connect(function() done = true end)
		local limit = os.clock() + 5
		while not done and os.clock() < limit do task.wait(0.1) end
		conn:Disconnect()
	end
	if player.Character ~= character then return end
	apply(player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.Health = humanoid.MaxHealth end
	-- Accesorios que llegan tarde también se esconden si chocan.
	character.ChildAdded:Connect(function(child)
		if not child:IsA("Accessory") then return end
		local p = Data.Profile(player)
		local slot = slotFor(child)
		if p and slot and p.armorEquipped[slot] then
			task.defer(function()
				if child.Parent == character then
					child:SetAttribute("OcultoPor", slot)
					child.Parent = hiddenFolder(player)
				end
			end)
		end
	end)
end

local function handle(player: Player, action: any, id: any): (boolean, string, any)
	local now = os.clock()
	if action ~= "Get" and now < (lastAction[player] or -math.huge) + 0.3 then
		return false, "Esperá un instante.", state(player)
	end
	lastAction[player] = now
	local p = Data.Profile(player)
	if not p then return false, "Tu inventario todavía se está cargando.", nil end
	if action == "Get" then return true, "", state(player) end
	if player:GetAttribute("InDuel") == true then return false, "No podés cambiar la armadura en un duelo.", state(player) end
	local piece = ArmorData.Get(id)
	if not piece then return false, "Pieza desconocida.", state(player) end

	if action == "Buy" then
		if p.armorOwned[piece.Id] then return false, "Ya tenés esta pieza.", state(player) end
		if not Data.ChangeGold(player, -piece.Price) then return false, "Oro insuficiente.", state(player) end
		p.armorOwned[piece.Id] = true
		p.armorEquipped[piece.Slot] = piece.Id
		apply(player)
		return true, `Compraste {piece.DisplayName}: +{piece.Health} de vida y +{math.round(piece.Armor * 100)}% de armadura.`, state(player)
	elseif action == "Equip" then
		if not p.armorOwned[piece.Id] then return false, "Todavía no tenés esta pieza.", state(player) end
		p.armorEquipped[piece.Slot] = piece.Id
		apply(player)
		return true, `Te pusiste {piece.DisplayName}.`, state(player)
	elseif action == "Unequip" then
		if p.armorEquipped[piece.Slot] == piece.Id then p.armorEquipped[piece.Slot] = nil end
		apply(player)
		return true, `Te sacaste {piece.DisplayName}.`, state(player)
	end
	return false, "Acción inválida.", state(player)
end

function ArmorService:Init()
	hiddenRoot.Parent = ServerStorage
	Remotes.GetFunction("ArmorShop").OnServerInvoke = function(player: Player, action: any, id: any)
		local ok, success, message, current = pcall(handle, player, action, id)
		if not ok then
			warn("[Armor] Falló una solicitud", success)
			return false, "No se pudo procesar la solicitud.", nil
		end
		return success, message, current
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character) onCharacter(player, character) end)
		if player.Character then task.spawn(onCharacter, player, player.Character) end
		player.CharacterRemoving:Connect(function()
			local folder = hiddenRoot:FindFirstChild(tostring(player.UserId))
			if folder then folder:ClearAllChildren() end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do task.spawn(onPlayer, player) end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		local folder = hiddenRoot:FindFirstChild(tostring(player.UserId))
		if folder then folder:Destroy() end
	end)
end

return ArmorService
