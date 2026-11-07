--!strict
--[[
	DuelController — Interacción mínima de duelos en el cliente.
	Owner: Dev A (Combat).

	- ProximityPrompt local "Desafiar a duelo" sobre cada otro jugador (oculto si alguno está en duelo).
	- Invitaciones y estados del duelo con notificaciones nativas de Roblox (SetCore).
	  La UI definitiva es de Dev B: puede escuchar "DuelInvite" y "DuelStateChanged" por su cuenta.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local PROMPT_NAME = "DuelPrompt"
local ACCEPT = "Aceptar"
local DECLINE = "Rechazar"

local localPlayer = Players.LocalPlayer
local prompts: { [Player]: ProximityPrompt } = {}

local DuelController = {}

local function notify(options: { [string]: any })
	-- SetCore puede fallar si el CoreScript todavía no registró la notificación.
	local ok = pcall(StarterGui.SetCore, StarterGui, "SendNotification", options)
	if not ok then
		task.delay(1, function()
			pcall(StarterGui.SetCore, StarterGui, "SendNotification", options)
		end)
	end
end

local function isInDuel(player: Player): boolean
	return player:GetAttribute("InDuel") == true
end

local function refreshPrompt(player: Player)
	local prompt = prompts[player]
	if prompt then
		prompt.Enabled = not isInDuel(player) and not isInDuel(localPlayer)
	end
end

local function attachPrompt(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Desafiar a duelo"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function()
		Remotes.GetEvent("DuelRequest"):FireServer(player)
	end)

	prompts[player] = prompt
	refreshPrompt(player)
end

local function watchPlayer(player: Player)
	if player == localPlayer then
		return
	end

	player.CharacterAdded:Connect(function(character)
		attachPrompt(player, character)
	end)
	if player.Character then
		task.spawn(attachPrompt, player, player.Character)
	end

	player:GetAttributeChangedSignal("InDuel"):Connect(function()
		refreshPrompt(player)
	end)
end

local function onInvite(challenger: unknown)
	if typeof(challenger) ~= "Instance" or not challenger:IsA("Player") then
		return
	end

	local callback = Instance.new("BindableFunction")
	callback.OnInvoke = function(choice: string)
		Remotes.GetEvent("DuelResponse"):FireServer(challenger, choice == ACCEPT)
		callback:Destroy()
	end

	notify({
		Title = "¡Desafío de duelo!",
		Text = `{challenger.DisplayName} te desafía a un duelo 1v1`,
		Duration = 15,
		Button1 = ACCEPT,
		Button2 = DECLINE,
		Callback = callback,
	})
end

local function onStateChanged(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local opponent = payload.Opponent
	local opponentName = if typeof(opponent) == "Instance" and opponent:IsA("Player")
		then opponent.DisplayName
		else "tu rival"

	local state = payload.State
	if state == "InviteSent" then
		notify({ Title = "Duelo", Text = `Desafío enviado a {opponentName}`, Duration = 3 })
	elseif state == "Declined" then
		notify({ Title = "Duelo", Text = `{opponentName} rechazó el desafío`, Duration = 3 })
	elseif state == "Countdown" then
		notify({ Title = `Duelo vs {opponentName}`, Text = `Empieza en {payload.Seconds or 3}...`, Duration = 3 })
	elseif state == "Fight" then
		notify({ Title = "¡A PELEAR!", Text = `vs {opponentName}`, Duration = 2 })
	elseif state == "End" then
		local text = if payload.Winner == nil
			then "Empate por tiempo"
			elseif payload.Winner == localPlayer then "¡Ganaste!"
			else "Perdiste"
		notify({ Title = "Fin del duelo", Text = text, Duration = 4 })
	end
end

function DuelController:Init()
	Remotes.GetEvent("DuelInvite").OnClientEvent:Connect(onInvite)
	Remotes.GetEvent("DuelStateChanged").OnClientEvent:Connect(onStateChanged)

	localPlayer:GetAttributeChangedSignal("InDuel"):Connect(function()
		for player in prompts do
			refreshPrompt(player)
		end
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		prompts[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(watchPlayer, player)
	end
end

return DuelController
