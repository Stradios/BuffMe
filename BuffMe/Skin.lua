--[[ Buff Me - Skin
     Themes. "Auto" follows whatever UI replacement is loaded:
       ElvUI    -> frames use ElvUI's own template (SetTemplate), fonts follow ElvUI
       DragonUI -> the "Retail" look (dark panel, thin gold edge)
       otherwise -> "Dark"
]]

local BM = BuffMe
local S = {}
BM.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8X8"

local THEMES = {
	dark = {
		label = "Dark", bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, inset = 1, iconInset = 3,
		bg = { 0.05, 0.05, 0.07, 0.92 }, btn = { 0.08, 0.08, 0.10, 0.95 }, border = { 0.24, 0.24, 0.30, 1 },
		text = { 1, 1, 1 },
	},
	retail = {
		label = "Retail", bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, inset = 1, iconInset = 3,
		bg = { 0.07, 0.06, 0.05, 0.93 }, btn = { 0.10, 0.09, 0.07, 0.95 }, border = { 0.72, 0.58, 0.22, 1 },
		text = { 1, 0.95, 0.8 },
	},
	classic = {
		label = "Classic (Blizzard)", bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, inset = 4, iconInset = 5,
		bg = { 0.1, 0.1, 0.2, 0.95 }, btn = { 0.1, 0.1, 0.2, 0.95 }, border = { 0.8, 0.8, 0.8, 1 },
		text = { 1, 0.82, 0 },
	},
	light = {
		label = "Light", bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, inset = 1, iconInset = 3,
		bg = { 0.90, 0.90, 0.93, 0.96 }, btn = { 0.82, 0.82, 0.86, 0.97 }, border = { 0.35, 0.35, 0.42, 1 },
		text = { 0.08, 0.08, 0.1 },
	},
	class = {
		label = "Class colour", bgFile = WHITE, edgeFile = WHITE, edgeSize = 2, inset = 2, iconInset = 4,
		bg = { 0.05, 0.05, 0.07, 0.92 }, btn = { 0.08, 0.08, 0.10, 0.95 }, border = { 0.24, 0.24, 0.30, 1 },
		text = { 1, 1, 1 }, classBorder = true,
	},
}
S.THEMES = THEMES
S.THEME_ORDER = { "auto", "dark", "retail", "classic", "light", "class" }

S.registry = {}

function S:ElvUI()
	local E = ElvUI and ElvUI[1]
	if E and E.media then return E end
	return nil
end

function S:HasDragonUI()
	return (DragonUI ~= nil) or (IsAddOnLoaded and IsAddOnLoaded("DragonUI")) or false
end

--- Resolved theme name.
function S:Name()
	local t = BM.db and BM.db.theme or "auto"
	if t == "auto" then
		if self:ElvUI() then return "elvui" end
		if self:HasDragonUI() then return "retail" end
		return "dark"
	end
	return THEMES[t] and t or "dark"
end

function S:Theme()
	local n = self:Name()
	return THEMES[n] or THEMES.dark, n
end

function S:Accent()
	local th, name = self:Theme()
	if name == "class" then return BM:ClassColor(BM.playerClass) end
	local a = BM.db.accent or BM.defaults.accent
	return a[1], a[2], a[3]
end

function S:IconInset()
	local th, name = self:Theme()
	if name == "elvui" then return 2 end
	return th.iconInset or 3
end

function S:TextColor()
	local th = self:Theme()
	return th.text[1], th.text[2], th.text[3]
end

--- Border colour for "state" highlighting (accent when something needs doing).
function S:Border(frame, state)
	local th, name = self:Theme()
	local r, g, b, a = th.border[1], th.border[2], th.border[3], th.border[4]
	if name == "elvui" then
		local E = self:ElvUI()
		local c = E and E.media and E.media.bordercolor
		if c then r, g, b = c[1] or c.r or r, c[2] or c.g or g, c[3] or c.b or b end
	end
	if state == "accent" or (th.classBorder and state ~= "good") then
		r, g, b = self:Accent()
	elseif state == "good" then
		r, g, b = 0.25, 0.75, 0.35
	elseif state == "unlocked" then
		r, g, b = 1, 0.82, 0.2
	end
	if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(r, g, b, a or 1) end
end

function S:Apply(frame, kind, state)
	self.registry[frame] = kind
	local th, name = self:Theme()

	if name == "elvui" and frame.SetTemplate then
		local ok = pcall(frame.SetTemplate, frame, kind == "window" and "Transparent" or "Default")
		if ok then
			self:Border(frame, state)
			return
		end
	end

	frame:SetBackdrop({
		bgFile = th.bgFile, edgeFile = th.edgeFile, tile = false, edgeSize = th.edgeSize,
		insets = { left = th.inset, right = th.inset, top = th.inset, bottom = th.inset },
	})
	local c = (kind == "button") and th.btn or th.bg
	frame:SetBackdropColor(c[1], c[2], c[3], c[4])
	self:Border(frame, state)
end

function S:Font(fs, size, flags)
	local E = self:ElvUI()
	local _, name = self:Theme()
	if name == "elvui" and E and E.media and E.media.normFont then
		pcall(fs.SetFont, fs, E.media.normFont, size or 12, flags or "OUTLINE")
		return
	end
	local path = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	fs:SetFont(path, size or 12, flags)
end

--- Re-apply everything registered; the UI hooks BM.Skin.onRefresh to recolour state.
function S:Refresh()
	for frame, kind in pairs(self.registry) do
		self:Apply(frame, kind)
	end
	if self.onRefresh then self.onRefresh() end
end

--- Square minimaps (ElvUI, DragonUI, SexyMap...) get buttons along the edge.
function S:MinimapIsSquare()
	if GetMinimapShape then
		local ok, shape = pcall(GetMinimapShape)
		if ok and shape and shape ~= "ROUND" then return true end
	end
	return false
end
