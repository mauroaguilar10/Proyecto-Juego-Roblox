--!strict
--[[
	WeaponVisualService — El arma equipada como objeto de inventario (Tool) + su modelo en la mano.
	Owner: Dev A (Combat).

	- Cada personaje recibe en su Backpack una Tool (sin Handle) con el arma de Player.EquippedWeapon.
	  Aparece en la barra de inventario de Roblox: botón / tecla 1 para sacarla y guardarla.
	- La Tool lleva el Attribute "WeaponId". Al cambiar EquippedWeapon se reemplaza la Tool
	  (si estaba en la mano, la nueva queda en la mano).
	- Mientras la Tool está equipada, el modelo vive como Model "Weapon" dentro del personaje,
	  unido a la mano con un Weld "WeaponGrip" (CombatController anima su C0 para el swing).
	  Al guardarla, el modelo se destruye.
	- CombatService solo acepta ataques si la Tool del arma equipada está en la mano.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponData = require(Shared:WaitForChild("WeaponData"))
local WeaponModels = require(script.Parent:WaitForChild("Util"):WaitForChild("WeaponModels"))

local HAND_NAMES = { "RightHand", "Right Arm" } -- R15, R6
local WAIT_TIMEOUT = 10
local FALLBACK_GRIP = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

local WeaponVisualService = {}

local function findHand(character: Model): BasePart?
	for _, name in HAND_NAMES do
		local hand = character:FindFirstChild(name)
		if hand and hand:IsA("BasePart") then
			return hand
		end
	end
	return nil
end

local function waitForHand(character: Model): BasePart?
	local deadline = os.clock() + WAIT_TIMEOUT
	local hand = findHand(character)
	while not hand and os.clock() < deadline and character.Parent do
		task.wait(0.1)
		hand = findHand(character)
	end
	return hand
end

local function getWeaponId(player: Player): string
	local equipped = player:GetAttribute("EquippedWeapon")
	return WeaponData.GetOrDefault(if typeof(equipped) == "string" then equipped else nil).Id
end

-- ── Modelo en la mano ──

local function removeModel(character: Model)
	local existing = character:FindFirstChild("Weapon")
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end
end

local function attachModel(character: Model, weaponId: string)
	local hand = waitForHand(character)
	if not hand then
		return
	end

	removeModel(character)

	local model = WeaponModels.Build(weaponId)
	local grip = model.PrimaryPart :: BasePart

	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local weld = Instance.new("Weld")
	weld.Name = "WeaponGrip"
	weld.Part0 = hand
	weld.Part1 = grip
	weld.C0 = if gripAttachment and gripAttachment:IsA("Attachment") then gripAttachment.CFrame else FALLBACK_GRIP
	weld.Parent = grip

	model.Parent = character
end

-- ── Tool de inventario ──

local function findWeaponTools(player: Player, character: Model): { Tool }
	local tools: { Tool } = {}
	local containers: { Instance? } = { character, player:FindFirstChildOfClass("Backpack") }
	for _, container in containers do
		if not container then
			continue
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("WeaponId") ~= nil then
				table.insert(tools, child)
			end
		end
	end
	return tools
end

local function makeTool(player: Player, character: Model, weaponId: string): Tool
	local weapon = WeaponData.GetOrDefault(weaponId)

	local tool = Instance.new("Tool")
	tool.Name = weapon.DisplayName
	tool.ToolTip = `{weapon.DisplayName} — Daño {weapon.Damage}`
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", weapon.Id)

	tool.Equipped:Connect(function()
		if player.Character == character and tool.Parent == character then
			attachModel(character, weapon.Id)
		end
	end)
	tool.Unequipped:Connect(function()
		removeModel(character)
	end)

	return tool
end

-- Crea o reemplaza la Tool del arma equipada. Si la anterior estaba en la mano, la nueva también.
local function refreshTool(player: Player, character: Model)
	if player.Character ~= character then
		return
	end
	local backpack = player:WaitForChild("Backpack", WAIT_TIMEOUT)
	local humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT)
	if player.Character ~= character or not backpack or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local weaponId = getWeaponId(player)
	local wasHeld = false
	for _, tool in findWeaponTools(player, character) do
		if tool:GetAttribute("WeaponId") == weaponId then
			return -- ya tiene la Tool correcta
		end
		wasHeld = wasHeld or tool.Parent == character
		tool:Destroy()
	end
	removeModel(character)

	local tool = makeTool(player, character, weaponId)
	tool.Parent = backpack
	if wasHeld and humanoid.Health > 0 then
		humanoid:EquipTool(tool)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		refreshTool(player, character)
	end)

	player:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
		local character = player.Character
		if character then
			refreshTool(player, character)
		end
	end)

	if player.Character then
		task.spawn(refreshTool, player, player.Character)
	end
end

-- Devuelve true si el jugador tiene en la mano la Tool del arma equipada.
function WeaponVisualService.IsWeaponHeld(player: Player): boolean
	local character = player.Character
	local tool = if character then character:FindFirstChildOfClass("Tool") else nil
	return tool ~= nil and tool:GetAttribute("WeaponId") == getWeaponId(player)
end

function WeaponVisualService:Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return WeaponVisualService
