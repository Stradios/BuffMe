--[[ Buff Me - Options
     Everything lives in Interface > AddOns > Buff Me:
       Buff Me (general) / Appearance / Buffs / How To
]]

local BM = BuffMe
local S = BM.Skin
local tinsert = table.insert

local counter = 0
local function GName(prefix)
	counter = counter + 1
	return "BuffMeOpt" .. prefix .. counter
end

local function Changed()
	BM:ApplySettings()
end

-- Widgets -------------------------------------------------------------------
local PANEL_W = 380 -- the AddOns settings area is narrow (~395 units); never assume more

local function NewPanel(name, parent, title, subtitle)
	local p = CreateFrame("Frame", nil, UIParent)
	p.name = name
	p.parent = parent
	p.widgets = {}
	p.wraps = {}

	--- Text that must wrap inside the panel instead of running off its edge.
	function p:Wrap(fs, margin)
		margin = margin or 0
		fs:SetJustifyH("LEFT")
		fs:SetWidth(PANEL_W - 32 - margin)
		self.wraps[#self.wraps + 1] = { fs, margin }
	end
	function p:FitWraps()
		local w = self:GetWidth()
		if not w or w < 200 then w = PANEL_W end
		for _, e in ipairs(self.wraps) do e[1]:SetWidth(w - 32 - e[2]) end
	end

	p.title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
	p.title:SetText(title)
	if subtitle then
		p.sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -8)
		p.sub:SetText(subtitle)
		p:Wrap(p.sub)
	end
	p.refresh = function()
		p:FitWraps()
		for _, w in ipairs(p.widgets) do w:Refresh() end
	end
	p:SetScript("OnShow", p.refresh)
	p:SetScript("OnSizeChanged", function() p:FitWraps() end)
	p.okay = function() end
	p.cancel = function() end
	p.default = function() end
	BM.API.AddOptionsPanel(p, parent and BM.optionsPanel or nil)
	return p
end

local function Tip(frame, title, text)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, 1, 1, 1)
		GameTooltip:AddLine(text, 0.8, 0.8, 0.8, 1)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Check(p, x, y, label, tip, get, set)
	local name = GName("Check")
	local cb = BM.API.CreateWithTemplate("CheckButton", name, p,
		{ "InterfaceOptionsCheckButtonTemplate", "UICheckButtonTemplate", "ChatConfigCheckButtonTemplate" })
	cb:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
	local text = _G[name .. "Text"] or cb.Text or cb.text
	if not text then
		text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	end
	text:SetText(label)
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	Tip(cb, label, tip)
	function cb:Refresh() self:SetChecked(get() and true or false) end
	tinsert(p.widgets, cb)
	return cb
end

local function Slider(p, x, y, label, minv, maxv, step, get, set, fmt)
	local name = GName("Slider")
	local s = BM.API.CreateWithTemplate("Slider", name, p, { "OptionsSliderTemplate" })
	if not _G[name .. "Text"] then
		-- template missing: build the pieces ourselves
		s:SetOrientation("HORIZONTAL")
		s:SetHeight(16)
		s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local bar = s:CreateTexture(nil, "BACKGROUND")
		bar:SetPoint("LEFT"); bar:SetPoint("RIGHT"); bar:SetHeight(4)
		BM.API.Solid(bar, 0.3, 0.3, 0.3, 1)
		_G[name .. "Text"] = s:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		_G[name .. "Text"]:SetPoint("BOTTOM", s, "TOP", 0, 2)
		_G[name .. "Low"] = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		_G[name .. "Low"]:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
		_G[name .. "High"] = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		_G[name .. "High"]:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
	end
	s:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
	s:SetWidth(200)
	s:SetMinMaxValues(minv, maxv)
	s:SetValueStep(step)
	fmt = fmt or "%s"
	_G[name .. "Low"]:SetText(format(fmt, minv))
	_G[name .. "High"]:SetText(format(fmt, maxv))
	local text = _G[name .. "Text"]
	s:SetScript("OnValueChanged", function(self, v)
		if self.refreshing then return end
		v = math.floor(v / step + 0.5) * step
		text:SetText(label .. ": " .. format(fmt, v))
		set(v)
	end)
	function s:Refresh()
		self.refreshing = true
		local v = get()
		self:SetValue(v)
		text:SetText(label .. ": " .. format(fmt, v))
		self.refreshing = false
	end
	tinsert(p.widgets, s)
	return s
end

local function SetDropdownWidth(dd, width)
	if not UIDropDownMenu_SetWidth then return end
	-- the argument order differs between client versions; the wrong order just errors, so try both
	if not pcall(UIDropDownMenu_SetWidth, width, dd) then
		pcall(UIDropDownMenu_SetWidth, dd, width)
	end
end

local function Dropdown(p, x, y, label, items, get, set, width)
	local name = GName("DD")
	if not (UIDropDownMenu_Initialize and UIDropDownMenu_AddButton and pcall(CreateFrame, "Frame", nil, p, "UIDropDownMenuTemplate")) then
		-- the client has no classic dropdown: a button that cycles through the choices
		local function list() return type(items) == "function" and items() or items end
		local lab = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		lab:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
		lab:SetText(label)
		local btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		btn:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 14)
		btn:SetSize(width or 150, 24)
		function btn:Refresh()
			local cur, text = get(), ""
			for _, it in ipairs(list()) do if it.value == cur then text = it.text end end
			self:SetText(text .. "  >")
		end
		btn:SetScript("OnClick", function(self)
			local l, cur, idx = list(), get(), 1
			for i, it in ipairs(l) do if it.value == cur then idx = i end end
			local nxt = l[(idx % #l) + 1]
			if nxt then set(nxt.value) end
			self:Refresh()
		end)
		tinsert(p.widgets, btn)
		return btn
	end
	local dd = CreateFrame("Frame", name, p, "UIDropDownMenuTemplate")
	dd:SetPoint("TOPLEFT", p, "TOPLEFT", x - 16, y - 16)
	local lab = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	lab:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 20, 2)
	lab:SetText(label)
	SetDropdownWidth(dd, width or 150)

	local function list() return type(items) == "function" and items() or items end
	UIDropDownMenu_Initialize(dd, function(_, level)
		for _, it in ipairs(list()) do
			local info = {}
			info.text = it.text
			info.value = it.value
			info.checked = (get() == it.value)
			info.func = function()
				set(it.value)
				_G[name .. "Text"]:SetText(it.text)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	function dd:Refresh()
		local cur = get()
		local text = ""
		for _, it in ipairs(list()) do
			if it.value == cur then text = it.text end
		end
		_G[name .. "Text"]:SetText(text)
	end
	tinsert(p.widgets, dd)
	return dd
end

local function Button(p, x, y, label, width, onclick)
	local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
	b:SetWidth(width or 170)
	b:SetHeight(24)
	b:SetText(label)
	b:SetScript("OnClick", onclick)
	return b
end

local function Swatch(p, x, y, label, get, set)
	local b = CreateFrame("Button", nil, p)
	b:SetWidth(22)
	b:SetHeight(22)
	b:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
	b.edge = b:CreateTexture(nil, "BACKGROUND")
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	BM.API.Solid(b.edge, 1, 1, 1, 1)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", b, "RIGHT", 8, 0)
	fs:SetText(label)
	function b:Refresh()
		local c = get()
		BM.API.Solid(self.tex, c[1], c[2], c[3], 1)
	end
	b:SetScript("OnClick", function()
		local c = get()
		BM.API.PickColor(c[1], c[2], c[3],
			function(nr, ng, nb) set({ nr, ng, nb }); b:Refresh() end,
			function(pr, pg, pb) set({ pr, pg, pb }); b:Refresh() end)
	end)
	tinsert(p.widgets, b)
	return b
end

-- How-To text ---------------------------------------------------------------
local H1, H2, R = "|cff33b8f2", "|cffffd100", "|r"

local HOWTO = H1 .. "What is Buff Me?" .. R .. "\n" ..
"One add-on that buffs for every class that has group buffs. You get a single smart button. " ..
"Each click casts the next buff that is actually needed, so you just keep clicking until everyone is covered. " ..
"There is nothing to set up: no panels, no Auto-Assign button, no Refresh button.\n\n" ..

H1 .. "Casting" .. R .. "\n" ..
H2 .. "Click" .. R .. " the button: it picks the next player who needs a buff and casts on them. The count on the icon is how many people still need something; the name under it is who is next.\n" ..
H2 .. "Mouse wheel" .. R .. " while the pointer is over the button casts too, one cast per notch.\n" ..
H2 .. "Key binding:" .. R .. " Esc > Key Bindings > Buff Me. Bind a key, or a mouse-wheel direction, and you can hide the button if you like.\n" ..
H2 .. "Action bar:" .. R .. " put this in a macro (or on your bar) to cast from there:  /click BuffMeButton\n" ..
"The game only allows one cast per click or key press, so Buff Me cannot cast on its own. Each click already points at the next person, so just click again.\n\n" ..

H1 .. "Player buttons" .. R .. "\n" ..
"Under the main button there is one small button per group member (class icon), in columns of five: one column in a party, one per raid group in a raid. " ..
"A " .. H2 .. "green border" .. R .. " means that person has everything, the " .. H2 .. "accent border" .. R .. " means they still need a buff, and a dimmed icon means they are out of range or dead. " ..
"The icon is always the person's class. Click a button to buff that person with the buff Buff Me has chosen for them; hold Shift / Ctrl / Alt to cast a specific one. " ..
"Paladins can " .. H2 .. "right-click" .. R .. " a player button to choose that person's blessing by hand (a small yellow mark shows a manual choice); pick Automatic to go back. " ..
"You can turn the buttons off, or change their size, in the settings.\n\n" ..

H1 .. "Layout and simulation" .. R .. "\n" ..
"The Layout tab places the player buttons below, above, left or right of the main button, lined up with its start, centre or end. " ..
"Turn on " .. H2 .. "Group simulation" .. R .. " to fill the grid with a pretend party or raid (5 to 60 players) and arrange your interface without being in a group. " ..
"Simulated buttons only show the layout; they don't cast. Quick toggle: /bm sim (or /bm sim 40).\n\n" ..

H1 .. "How the right buff is chosen" .. R .. "\n" ..
"Buff Me reads each player's role and spec. People running Buff Me share theirs automatically; for everyone else it quietly looks at their talents when they are close enough (never in combat, one player every few seconds). " ..
"That is how a Balance or Restoration druid ends up with Wisdom and a Feral druid with Might. Until a player has been read, their class default is used.\n\n" ..

H1 .. "Modifier keys (a specific single buff)" .. R .. "\n" ..
"Hold a key while you click to cast one specific buff on " .. H2 .. "your target" .. R .. ", or the unit under your mouse if you have no target, or yourself if neither.\n" ..
H2 .. "Paladin:" .. R .. "  Shift = Kings,  Ctrl = Might,  Alt = Wisdom,  Shift+Ctrl = Sanctuary  (change them in the Buffs tab). These are the normal, single-target blessings.\n" ..
H2 .. "Priest:" .. R .. "  Shift = Fortitude,  Ctrl = Divine Spirit,  Alt = Shadow Protection.\n" ..
H2 .. "Druid:" .. R .. "  Shift = Mark of the Wild,  Ctrl = Thorns.\n" ..
H2 .. "Mage:" .. R .. "  Shift = Arcane Intellect.\n" ..
H2 .. "Warrior:" .. R .. "  Shift = Battle Shout,  Ctrl = Commanding Shout.\n" ..
(BM.forever and "" or (H2 .. "Death Knight:" .. R .. "  Shift = Horn of Winter.\n")) ..
"If your game is set to self-cast with Alt, an Alt click may land on you. Change that under Interface > Combat, or move the paladin Wisdom key to another combination.\n\n" ..

H1 .. "Spell ranks" .. R .. "\n" ..
"Buff Me finds the highest rank of every buff in your spellbook by itself and casts that one. After you learn a new rank at the trainer it is picked up automatically. " ..
"/bm spells lists what was found. If your role is wrong (for example a tank paladin), set it under General > My role, or /bm role tank. If clicking does nothing, try /bm cast macro and /bm debug.\n\n" ..

H1 .. "Paladin blessings: how they are assigned" .. R .. "\n" ..
"Buff Me works out the assignments by itself whenever the group changes. It looks at which classes are present, what role each player has, and which paladins are in the group. " ..
"Every paladin running Buff Me comes to the same result, so nothing needs to be sent around or confirmed.\n" ..
"- One paladin: Kings on everyone (you can switch this to a best-for-each-class choice in the settings).\n" ..
"- Two or more: Kings plus Might for melee classes and Wisdom for casters and healers. A Retribution paladin is picked for Might, a Holy paladin for Wisdom, a Protection paladin for Sanctuary.\n" ..
"- Tanks get Blessing of Sanctuary when a paladin has a blessing to spare. A protection paladin who tanks buffs himself with Sanctuary.\n" ..
"- A paladin can only keep one of his own blessings on a person, so Buff Me never gives one person two blessings from the same paladin.\n" ..
"- Anyone whose spec needs something different from the rest of their class (a healer paladin who would otherwise only get Might, say) receives the right single blessing from a paladin who has spare capacity.\n" ..
"Specs are shared automatically between players who run Buff Me. For everyone else Buff Me uses the dungeon-finder role, the main-tank flag, or the class default. A paladin who does not run Buff Me is not given any assignments, but whatever he casts counts as a buff already present.\n\n" ..

H1 .. "Greater or normal blessings?" .. R .. "\n" ..
"Groups of 4 or more (dungeons and raids) use Greater Blessings: one cast covers a whole class for a long time. Groups of 1 to 3 use the normal blessing on each player. " ..
"You can change the group size, or force one kind, in the settings. Greater Blessings need a Symbol of Kings; without one Buff Me falls back to normal blessings, and the tooltip shows how many you carry. " ..
"Modifier-key clicks always use the normal blessing.\n\n" ..

H1 .. "Assignment window" .. R .. "\n" ..
"Middle-click the minimap icon (or /bm grid) to see who casts what on which class. It is for looking, and for overrides: click a cell to change it, right-click to go back to automatic. " ..
"You can change your own row; raid leaders and assistants can change anyone's. Overrides last until you leave the group or reload.\n\n" ..

H1 .. "Minimap icon" .. R .. "\n" ..
H2 .. "Left-click:" .. R .. " lock / unlock the button. Unlocked, the button has a yellow border and can be dragged. The padlock on the icon shows the current state.\n" ..
H2 .. "Right-click:" .. R .. " open these settings.\n" ..
H2 .. "Middle-click:" .. R .. " assignment window.\n" ..
H2 .. "Drag:" .. R .. " move the icon around the minimap.\n\n" ..

H1 .. "Looks" .. R .. "\n" ..
"The Appearance tab has the scale, icon size, opacity, theme and accent colour. The Automatic theme matches ElvUI if it is loaded, uses a Retail style with DragonUI, and a plain dark style otherwise.\n\n" ..

H1 .. "Commands" .. R .. "\n" ..
"/bm  settings    /bm lock    /bm unlock    /bm grid    /bm reset  (button position)    /bm plan  (print the assignments)"

-- Build panels --------------------------------------------------------------
local function BuildGeneral()
	local p = NewPanel("Buff Me", nil, "Buff Me",
		"One-click buffing for every class. Changes apply immediately. The How To tab explains everything.")
	BM.optionsPanel = p
	local db = BM.db

	local x, y = 16, -76
	Check(p, x, y, "Lock the button", "Locked, the button cannot be dragged. You can also left-click the minimap icon.",
		function() return db.locked end,
		function(v) db.locked = v; BM.UI:Update(); BM.UI:UpdateMinimap() end)
	Check(p, x, y - 25, "Show the minimap icon", nil,
		function() return not db.minimap.hide end,
		function(v) db.minimap.hide = not v; BM.UI:UpdateMinimap() end)
	Check(p, x, y - 50, "Mouse wheel over the button casts", "One cast per scroll notch while the pointer is on the button.",
		function() return db.wheelCast end, function(v) db.wheelCast = v end)
	Check(p, x, y - 75, "Show how many still need a buff", nil,
		function() return db.showCount end, function(v) db.showCount = v; BM.UI:Update() end)
	Check(p, x, y - 100, "Show the next target's name", nil,
		function() return db.showTargetName end, function(v) db.showTargetName = v; BM.UI:Update() end)
	Check(p, x, y - 125, "Show tooltips", nil,
		function() return db.tooltips end, function(v) db.tooltips = v end)
	Check(p, x, y - 150, "Show a button for every group member",
		"A small button per player under the main button. Click one to buff that person; hold Shift / Ctrl / Alt for a specific buff.",
		function() return db.showPlayers end,
		function(v) db.showPlayers = v; BM.UI:LayoutPlayers(true); BM.UI:Update() end)

	Dropdown(p, x + 4, y - 175, "Show the button", {
		{ value = "always", text = "Always" },
		{ value = "group", text = "Only in a group" },
		{ value = "needed", text = "Only when someone needs a buff" },
	}, function() return db.showButton end,
		function(v) db.showButton = v; BM.UI:Update() end, 220)

	Dropdown(p, x + 4, y - 235, "My role (auto-detected from your spec)", {
		{ value = "auto", text = "Automatic" },
		{ value = "tank", text = "Tank" },
		{ value = "healer", text = "Healer" },
		{ value = "melee", text = "Melee damage" },
		{ value = "ranged", text = "Ranged damage" },
		{ value = "caster", text = "Caster damage" },
	}, function() return db.myRole or "auto" end,
		function(v) db.myRole = v; BM:DetectSelfSpec(); BM:SendHello(); BM:RequestRefresh(0.05) end, 220)

	Dropdown(p, x + 4, y - 290, "Cast method (try Macro if clicking does nothing)", {
		{ value = "spell", text = "Spell (default)" },
		{ value = "macro", text = "Macro" },
	}, function() return db.castMode or "spell" end,
		function(v) db.castMode = v end, 220)

	Button(p, x + 4, y - 345, "Reset button position", 170, function() BM:ResetPosition() end)
	Button(p, x + 182, y - 345, "Assignment window", 170, function() BM:ToggleGrid() end)
	Button(p, x + 4, y - 375, "Clear manual overrides", 170, function() BM:ClearOverrides() end)
	return p
end

local function BuildAppearance(parent)
	local p = NewPanel("Appearance", parent.name, "Appearance",
		"Size, scale and theme of the button and windows.")
	local db = BM.db
	local x, y = 16, -64

	local items = {}
	for _, key in ipairs(S.THEME_ORDER) do
		local text = (key == "auto") and "Automatic (ElvUI / DragonUI)" or S.THEMES[key].label
		items[#items + 1] = { value = key, text = text }
	end
	Dropdown(p, x + 4, y, "Theme", items,
		function() return db.theme end,
		function(v) db.theme = v; Changed() end, 210)

	Slider(p, x + 8, y - 78, "Scale", 0.5, 2, 0.05,
		function() return db.scale end, function(v) db.scale = v; Changed() end, "%.2f")
	Slider(p, x + 8, y - 126, "Main button size", 24, 96, 2,
		function() return db.iconSize end, function(v) db.iconSize = v; Changed() end, "%d")
	Slider(p, x + 8, y - 174, "Player button size", 16, 44, 2,
		function() return db.playerSize end, function(v) db.playerSize = v; Changed() end, "%d")
	Slider(p, x + 8, y - 222, "Opacity", 0.3, 1, 0.05,
		function() return db.alpha end, function(v) db.alpha = v; Changed() end, "%.2f")

	Swatch(p, x + 8, y - 268, "Accent colour",
		function() return db.accent end,
		function(c) db.accent = c; Changed() end)

	local info = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", p, "TOPLEFT", x + 4, y - 302)
	p:Wrap(info, 4)
	function info:Refresh()
		local detected = S:ElvUI() and "ElvUI" or (S:HasDragonUI() and "DragonUI" or "no UI replacement")
		local _, name = S:Theme()
		self:SetText("Detected: " .. detected .. ".  Active theme: " .. tostring(name) ..
			".")
	end
	tinsert(p.widgets, info)
	return p
end

local function BuildLayout(parent)
	local p = NewPanel("Layout", parent.name, "Layout & Simulation",
		"Decide where the player buttons sit around the main button, and preview any group size without being in a group.")
	local db = BM.db
	local x, y = 16, -58

	Dropdown(p, x + 4, y, "Player buttons are placed", {
		{ value = "below", text = "Below the main button" },
		{ value = "above", text = "Above the main button" },
		{ value = "right", text = "To the right" },
		{ value = "left", text = "To the left" },
	}, function() return db.placement end,
		function(v) db.placement = v; BM.UI:LayoutPlayers(true) end, 210)

	Dropdown(p, x + 4, y - 62, "Lined up with the main button's", {
		{ value = "start", text = "Start (left / top edge)" },
		{ value = "center", text = "Centre" },
		{ value = "finish", text = "End (right / bottom edge)" },
	}, function() return db.align end,
		function(v) db.align = v; BM.UI:LayoutPlayers(true) end, 210)

	Check(p, x, y - 135, "Group simulation (show fake players)",
		"Fills the player buttons with a pretend group so you can arrange your interface. Switches itself off when you log in again.",
		function() return BM.sim.on end,
		function(v) BM:SetSimulation(v) end)

	Dropdown(p, x + 4, y - 160, "Simulated group", {
		{ value = 5, text = "Party (5)" },
		{ value = 10, text = "10-man raid" },
		{ value = 25, text = "25-man raid" },
		{ value = 40, text = "40-man raid" },
		{ value = 60, text = "60-man raid" },
	}, function() return BM.sim.size end,
		function(v) BM:SetSimulation(BM.sim.on, v) end, 210)

	local note = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", p, "TOPLEFT", x + 4, y - 235)
	note:SetText("Unlock the main button (left-click the minimap icon) to drag it. The player buttons follow it. " ..
		"Simulated buttons only show the layout and the colours; they don't cast. Also: /bm sim")
	p:Wrap(note, 4)
	return p
end

local function BuildBuffs(parent)
	local p = NewPanel("Buffs", parent.name, "Buffs", nil)
	local db = BM.db
	local provider = BM.providers and BM.providers[BM.playerClass]
	local x, y = 16, -44

	local function Rebuff(py)
		Slider(p, x + 8, py, "Re-buff when under (min)", 0, 10, 1,
			function() return db.rebuffMinutes end,
			function(v) db.rebuffMinutes = v end)
	end

	if BM.playerClass == "PALADIN" then
		local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		sub:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
		sub:SetText("Hold a key while clicking to cast that single-target blessing on your target (or mouseover, or yourself). " ..
			"A plain click casts the assigned blessing on whoever needs it next.")
		p:Wrap(sub)
		local items = function()
			local out = {}
			for _, key in ipairs(BM.BLESSING_ORDER) do
				out[#out + 1] = { value = key, text = BM:BlessingName(key) }
			end
			return out
		end
		local function ModDD(mod, label, px, py)
			Dropdown(p, px, py, label, items,
				function() return db.mods[mod] end,
				function(v) db.mods[mod] = v end, 120)
		end
		ModDD("shift", "Shift + click", x + 4, y - 70)
		ModDD("ctrl", "Ctrl + click", x + 184, y - 70)
		ModDD("alt", "Alt + click", x + 4, y - 130)
		ModDD("ctrlshift", "Shift+Ctrl + click", x + 184, y - 130)
		Rebuff(y - 215)
	elseif provider then
		local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		sub:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
		sub:SetText("Choose which buffs the plain click works through, in this order. Shift / Ctrl / Alt + click always casts that one buff on your target.")
		p:Wrap(sub)
		local yy = y - 52
		for _, def in ipairs(provider.defs) do
			local label = provider:Label(def)
			if def.slot then
				local names = { shift = "Shift", ctrl = "Ctrl", alt = "Alt", ctrlshift = "Shift+Ctrl" }
				label = label .. "  (" .. names[def.slot] .. ")"
			end
			Check(p, x, yy, label, nil,
				function() return provider:Enabled(def) end,
				function(v) db.buffs[def.key] = v; BM.UI:Update() end)
			yy = yy - 26
		end
		Rebuff(yy - 24)
	else
		local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		sub:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
		sub:SetText("Your class has no group buffs for Buff Me to manage. You can still use the minimap icon and settings.")
		p:Wrap(sub)
	end
	return p
end

local function BuildGreater(parent)
	local p = NewPanel("Greater Blessings", parent.name, "Greater Blessings",
		"Paladin only. Greater Blessings cover a whole class for longer but cost a Symbol of Kings.")
	local db = BM.db
	local x, y = 16, -76

	Dropdown(p, x + 4, y, "Which blessings to use", {
		{ value = "auto", text = "Automatic (by group size)" },
		{ value = "greater", text = "Always Greater" },
		{ value = "normal", text = "Always normal" },
	}, function() return db.greaterMode end,
		function(v) db.greaterMode = v end, 210)

	Slider(p, x + 8, y - 78, "Greater from group size", 2, 5, 1,
		function() return db.greaterMinGroup end,
		function(v) db.greaterMinGroup = v end)

	Check(p, x, y - 120, "A lone paladin buffs Kings on everyone",
		"Off: a lone paladin buffs Might on physical classes and Wisdom on casters instead.",
		function() return db.singlePaladinKings end,
		function(v) db.singlePaladinKings = v; BM:RequestRefresh(0.05) end)

	local note = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", p, "TOPLEFT", x + 4, y - 160)
	note:SetText("Groups smaller than the chosen size use normal blessings. Without a Symbol of Kings, normal blessings are used automatically. " ..
		"Shift / Ctrl / Alt clicks always use the normal blessing.")
	p:Wrap(note, 4)
	return p
end

local function BuildHowTo(parent)
	local p = NewPanel("How To", parent.name, "How To", nil)
	local sf = CreateFrame("ScrollFrame", "BuffMeHowToScroll", p, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -46)
	sf:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -32, 12)
	local content = CreateFrame("Frame", nil, sf)
	content:SetWidth(PANEL_W - 52)
	content:SetHeight(10)
	sf:SetScrollChild(content)
	local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", content, "TOPLEFT", 4, 0)
	text:SetWidth(PANEL_W - 60)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetText(HOWTO)

	local function Fit(w)
		if not w or w < 120 then w = PANEL_W - 52 end
		content:SetWidth(w)
		text:SetWidth(w - 8)
		content:SetHeight(text:GetStringHeight() + 24)
	end
	sf:SetScript("OnSizeChanged", function(_, w) Fit(w) end)
	tinsert(p.widgets, { Refresh = function() Fit(sf:GetWidth()) end })
	return p
end

BM:OnInit(function()
	local main = BuildGeneral()
	BuildAppearance(main)
	BuildLayout(main)
	BuildBuffs(main)
	if BM.playerClass == "PALADIN" then BuildGreater(main) end
	BuildHowTo(main)
end)
