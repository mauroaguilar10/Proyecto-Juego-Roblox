--!strict
--[[
	DuelMenuAssets — Imágenes del menú de duelo (subidas a Roblox) y cómo se dibujan.
	Owner: Dev B (UI). Lo usa DuelMenuController.

	Cada pieza: ID, tamaño original (px) y modo:
	  "Fit"   → ImageLabel con ScaleType Fit (y UIAspectRatioConstraint si `ratio`).
	  "Slice" → 9-slice con SliceCenter (botones: se estiran a lo ancho sin deformar las puntas).
	Si un ID es 0, se dibuja un reemplazo con Frame + UIGradient (+ borde), para que el menú
	funcione aunque falte subir alguna imagen.
]]
local Assets = {}

export type Key =
	"marco_panel" | "titulo_cartel" | "boton_amarillo" | "boton_gris" | "boton_violeta" | "boton_cerrar"
	| "marco_avatar" | "escudo_vs" | "reloj_arena" | "cinta" | "gema" | "espadas" | "moneda" | "trofeo" | "check"

type Spec = {
	id: number,
	size: Vector2,
	mode: "Fit" | "Slice",
	ratio: number?,
	slice: Rect?,
	fallback: { Color3 }, -- arriba, abajo (y borde si hay un tercero)
	round: number?, -- radio del reemplazo (999 = círculo)
}

local SPECS: { [Key]: Spec } = {
	marco_panel = { id = 114722404265255, size = Vector2.new(868, 558), mode = "Fit", ratio = 1.556,
		fallback = { Color3.fromRGB(248, 234, 204), Color3.fromRGB(226, 202, 156), Color3.fromRGB(196, 146, 54) }, round = 26 },
	titulo_cartel = { id = 74098603546031, size = Vector2.new(609, 238), mode = "Fit", ratio = 2.559,
		fallback = { Color3.fromRGB(140, 86, 44), Color3.fromRGB(70, 40, 20), Color3.fromRGB(236, 184, 64) }, round = 16 },
	boton_amarillo = { id = 124180014399412, size = Vector2.new(384, 104), mode = "Slice", slice = Rect.new(36, 51, 348, 53),
		fallback = { Color3.fromRGB(255, 226, 90), Color3.fromRGB(240, 170, 20), Color3.fromRGB(150, 90, 10) }, round = 16 },
	boton_gris = { id = 110082014625853, size = Vector2.new(388, 105), mode = "Slice", slice = Rect.new(36, 51, 352, 53),
		fallback = { Color3.fromRGB(150, 150, 156), Color3.fromRGB(96, 96, 102), Color3.fromRGB(56, 56, 60) }, round = 16 },
	boton_violeta = { id = 89356319170179, size = Vector2.new(389, 110), mode = "Slice", slice = Rect.new(36, 54, 353, 56),
		fallback = { Color3.fromRGB(186, 126, 255), Color3.fromRGB(110, 50, 190), Color3.fromRGB(236, 184, 64) }, round = 16 },
	boton_cerrar = { id = 93756222613490, size = Vector2.new(139, 130), mode = "Fit",
		fallback = { Color3.fromRGB(240, 90, 70), Color3.fromRGB(160, 30, 20), Color3.fromRGB(236, 184, 64) }, round = 999 },
	marco_avatar = { id = 127434739576299, size = Vector2.new(326, 361), mode = "Fit", ratio = 0.903,
		fallback = { Color3.fromRGB(110, 190, 255), Color3.fromRGB(40, 110, 210), Color3.fromRGB(104, 62, 32) }, round = 18 },
	escudo_vs = { id = 83169103289332, size = Vector2.new(407, 345), mode = "Fit",
		fallback = { Color3.fromRGB(150, 92, 44), Color3.fromRGB(70, 40, 20), Color3.fromRGB(236, 184, 64) }, round = 22 },
	reloj_arena = { id = 104743767889684, size = Vector2.new(171, 221), mode = "Fit",
		fallback = { Color3.fromRGB(140, 220, 255), Color3.fromRGB(60, 150, 220) }, round = 8 },
	cinta = { id = 126303618386084, size = Vector2.new(190, 203), mode = "Fit",
		fallback = { Color3.fromRGB(176, 110, 250), Color3.fromRGB(96, 40, 170), Color3.fromRGB(236, 184, 64) }, round = 6 },
	gema = { id = 120526960131790, size = Vector2.new(130, 180), mode = "Fit",
		fallback = { Color3.fromRGB(200, 140, 255), Color3.fromRGB(110, 50, 190) }, round = 10 },
	espadas = { id = 129111349824153, size = Vector2.new(154, 143), mode = "Fit",
		fallback = { Color3.fromRGB(230, 232, 240), Color3.fromRGB(150, 156, 170) }, round = 8 },
	moneda = { id = 85263808537416, size = Vector2.new(144, 145), mode = "Fit",
		fallback = { Color3.fromRGB(255, 226, 110), Color3.fromRGB(214, 150, 30) }, round = 999 },
	trofeo = { id = 94584498512744, size = Vector2.new(166, 147), mode = "Fit",
		fallback = { Color3.fromRGB(255, 226, 110), Color3.fromRGB(214, 150, 30) }, round = 8 },
	check = { id = 108063281165473, size = Vector2.new(137, 138), mode = "Fit",
		fallback = { Color3.fromRGB(110, 220, 110), Color3.fromRGB(40, 140, 50) }, round = 999 },
}

Assets.Specs = SPECS

function Assets.Size(key: Key): Vector2
	return SPECS[key].size
end

function Assets.Has(key: Key): boolean
	return SPECS[key].id ~= 0
end

local function applyFallback(object: GuiObject, spec: Spec)
	object.BackgroundTransparency = 0
	object.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Name = "Fallback"
	g.Color = ColorSequence.new(spec.fallback[1], spec.fallback[2])
	g.Rotation = 90
	g.Parent = object
	local c = Instance.new("UICorner")
	c.Name = "Fallback"
	c.CornerRadius = if spec.round == 999 then UDim.new(1, 0) else UDim.new(0, spec.round or 10)
	c.Parent = object
	local edge = spec.fallback[3]
	if edge then
		local s = Instance.new("UIStroke")
		s.Name = "Fallback"
		s.Color, s.Thickness = edge, 3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = object
	end
end

-- Pinta `object` (ImageLabel o ImageButton) con la pieza `key`. Para botones Slice, `height`
-- es la altura final en px: si es menor que la de la imagen, se usa SliceScale < 1 para que
-- las puntas no se deformen.
function Assets.Apply(object: ImageLabel | ImageButton, key: Key, height: number?)
	local spec = SPECS[key]
	for _, child in object:GetChildren() do
		if child.Name == "Fallback" or child:IsA("UIAspectRatioConstraint") then child:Destroy() end
	end
	object.BackgroundTransparency = 1
	if spec.id == 0 then
		object.Image = ""
		applyFallback(object, spec)
	else
		object.Image = `rbxassetid://{spec.id}`
		if spec.mode == "Slice" and spec.slice then
			object.ScaleType = Enum.ScaleType.Slice
			object.SliceCenter = spec.slice
			object.SliceScale = if height then math.min(1, height / spec.size.Y) else 1
		else
			object.ScaleType = Enum.ScaleType.Fit
		end
	end
	if spec.ratio then
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = spec.ratio
		ratio.Parent = object
	end
end

-- ImageLabel nuevo con la pieza `key`.
function Assets.Image(parent: Instance, key: Key, position: UDim2, size: UDim2, anchor: Vector2?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = key
	image.Position, image.Size = position, size
	image.AnchorPoint = anchor or Vector2.zero
	Assets.Apply(image, key)
	image.Parent = parent
	return image
end

return Assets
