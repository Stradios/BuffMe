--[[ Buff Me - UI
     * The one smart buff button (secure, so it can cast)
     * Minimap icon: left-click lock/unlock, right-click settings, middle-click assignments
     * Assignment window (paladins): live view, click a cell to override
]]

local BM = BuffMe
local S = BM.Skin
local UI = {}
BM.UI = UI

local btn, mini, grid
local ClassColorStr

local function Provider()
	return BM.providers and BM.providers[BM.playerClass]
end

-- Main button ---------------------------------------------------------------
local function SavePosition(self)
	local point, _, relPoint, x, y = self:GetPoint(1)
	if point then BM.db.pos = { point, relPoint, x, y } end
end

function UI:ApplyPosition()
	if not btn then return end
	btn:ClearAllPoints()
	local pos = BM.db.pos
	if pos then
		btn:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		btn:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
end

function UI:Layout()
	if not btn then return end
	local db = BM.db
	local size = db.iconSize or 44
	local inset = S:IconInset()
	btn:SetScale(db.scale or 1)
	btn:SetSize(size, size)
	btn:SetAlpha(db.alpha or 1)
	btn.icon:ClearAllPoints()
	btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
	btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
	btn.count:ClearAllPoints()
	btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset - 1, inset + 1)
	S:Font(btn.count, math.max(11, math.floor(size * 0.34)), "OUTLINE")
	btn.label:ClearAllPoints()
	btn.label:SetPoint("TOP", btn, "BOTTOM", 0, -3)
	S:Font(btn.label, 10, "OUTLINE")
end

--- Tell a secure button what to cast. "spell" mode uses the plain secure spell action;
--  "macro" mode runs "/cast [@unit] Spell" instead (a fallback for clients where the
--  spell action does not fire; switch with /bm cast macro).
local function ApplyCast(self, res)
	if not res then
		self:SetAttribute("spell", nil)
		self:SetAttribute("unit", nil)
		self:SetAttribute("macrotext", nil)
		return
	end
	if BM.db.castMode == "macro" then
		self:SetAttribute("type", "macro")
		self:SetAttribute("macrotext", "/cast [@" .. res.unit .. "] " .. res.spell)
		self:SetAttribute("spell", nil)
		self:SetAttribute("unit", nil)
	else
		self:SetAttribute("type", "spell")
		self:SetAttribute("macrotext", nil)
		self:SetAttribute("spell", res.spell)
		self:SetAttribute("unit", res.unit)
	end
end
UI.ApplyCast = ApplyCast

--- Newer clients fire secure buttons on key DOWN when the ActionButtonUseKeyDown option is on,
--  and ignore buttons that only listen for the release. Listen for both and always act on the
--  release so a click is one cast on every client.
local function RegisterClicks(b, kind)
	if BM.modern then
		if kind == "left" then b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
		else b:RegisterForClicks("AnyUp", "AnyDown") end
		b:SetAttribute("useOnKeyDown", false)
	else
		if kind == "left" then b:RegisterForClicks("LeftButtonUp") else b:RegisterForClicks("AnyUp") end
	end
end

local function PreClick(self, button, down)
	if down then return end -- decide on the release only (see RegisterClicks)
	if InCombatLockdown() then return end
	local p = Provider()
	if not p then return end
	local res, msg = p:Select(BM:GetModifier(), true)
	ApplyCast(self, res)
	if not res and msg then BM:Notice(msg) end
	if BM.debugOn then BM:DebugClick(self, res, msg) end
end

local function PostClick(self, button, down)
	if down then return end
	BM:Schedule("postclick", 0.35, function() UI:Update() end)
end

local function CreateButton()
	btn = CreateFrame("Button", "BuffMeButton", UIParent, "SecureActionButtonTemplate")
	btn:SetFrameStrata("MEDIUM")
	btn:SetClampedToScreen(true)
	btn:SetMovable(true)
	RegisterClicks(btn, "any")
	btn:RegisterForDrag("LeftButton")
	btn:SetAttribute("type", "spell")

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
	btn.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	btn.hl:SetBlendMode("ADD")
	btn.hl:SetAllPoints(btn.icon)

	btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

	btn:SetScript("PreClick", PreClick)
	btn:SetScript("PostClick", PostClick)

	btn:SetScript("OnDragStart", function(self)
		if not BM.db.locked and not InCombatLockdown() then self:StartMoving() end
	end)
	btn:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)

	btn:SetScript("OnEnter", function(self)
		UI:ShowTooltip()
		if BM.db.wheelCast and not InCombatLockdown() then
			SetOverrideBindingClick(self, true, "MOUSEWHEELUP", "BuffMeButton", "LeftButton")
			SetOverrideBindingClick(self, true, "MOUSEWHEELDOWN", "BuffMeButton", "LeftButton")
		end
	end)
	btn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if not InCombatLockdown() then ClearOverrideBindings(self) end
	end)

	S:Apply(btn, "button")
	UI:Layout()
	UI:ApplyPosition()
end

function UI:ShowTooltip()
	if not BM.db.tooltips or not btn then return end
	local p = Provider()
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Buff Me", 0.2, 0.72, 0.95)
	local last = self.last
	if last then
		if last.res then
			local r = last.res
			local who = r.aoe and "your group" or (r.name or "?")
			GameTooltip:AddDoubleLine("Next", r.spell .. "  >  " .. who, 0.7, 0.7, 0.7, 1, 1, 1)
			if r.pending and r.pending > 1 then
				GameTooltip:AddDoubleLine("Still needing a buff", tostring(r.pending), 0.7, 0.7, 0.7, 1, 1, 1)
			end
		elseif last.msg then
			GameTooltip:AddLine(last.msg, 0.4, 1, 0.5)
		end
	end
	if p and p.PlanLines then
		local lines = p:PlanLines()
		if #lines > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Your assignments", 1, 0.82, 0)
			for _, l in ipairs(lines) do
				local r, g, b = 1, 1, 1
				if l[3] then r, g, b = BM:ClassColor(l[3]) end
				GameTooltip:AddDoubleLine(l[1], l[2], r, g, b, 1, 1, 1)
			end
		end
	end
	if p and p.ReagentText then
		local text, n = p:ReagentText()
		GameTooltip:AddLine(text, n > 0 and 0.7 or 1, n > 0 and 0.7 or 0.3, n > 0 and 0.7 or 0.3)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click: cast on the next person who needs it", 0.8, 0.8, 0.8)
	if p and p.ModLines then
		for _, l in ipairs(p:ModLines()) do
			GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1)
		end
	end
	if BM.db.wheelCast then GameTooltip:AddLine("Mouse wheel over the button also casts", 0.6, 0.6, 0.6) end
	if not BM.db.locked then GameTooltip:AddLine("Unlocked: drag to move", 1, 0.82, 0.2) end
	GameTooltip:Show()
end

-- State refresh -------------------------------------------------------------
local function SetButtonShown(on)
	BM:AfterCombat("btnshown", function()
		if on then btn:Show() else btn:Hide() end
	end)
end

function UI:Update()
	if not btn then return end
	local db = BM.db
	local p = Provider()

	if not p or not p:IsAvailable() then
		SetButtonShown(false)
		self:LayoutPlayers()
		self:UpdateMinimap()
		return
	end

	local res, msg
	if InCombatLockdown() and self.last then
		res, msg = self.last.res, self.last.msg
	else
		res, msg = p:Select(nil, false)
		self.last = { res = res, msg = msg }
	end

	btn.icon:SetTexture((res and res.texture) or p:DefaultTexture())
	btn.icon:SetDesaturated(not res and true or false)
	btn.icon:SetAlpha(res and 1 or 0.55)

	if db.showCount and res and res.pending and res.pending > 0 then
		btn.count:SetText(res.pending)
	else
		btn.count:SetText("")
	end

	if db.showTargetName then
		if res then
			if res.aoe then
				btn.label:SetText("Group")
				btn.label:SetTextColor(1, 1, 1)
			else
				btn.label:SetText(res.name or "")
				if res.class then btn.label:SetTextColor(BM:ClassColor(res.class)) else btn.label:SetTextColor(1, 1, 1) end
			end
		else
			btn.label:SetText(msg and (msg == "Everyone is buffed." and "Buffed" or "") or "")
			btn.label:SetTextColor(0.4, 1, 0.5)
		end
	else
		btn.label:SetText("")
	end

	local state = res and "accent" or "good"
	if not db.locked then state = "unlocked" end
	S:Border(btn, state)

	local show = true
	if db.locked and not BM.sim.on then
		if db.showButton == "group" then show = BM:InGroup()
		elseif db.showButton == "needed" then show = res ~= nil end
	end
	SetButtonShown(show)
	self:UpdateMinimap()
	self:UpdateGrid()
	self:LayoutPlayers()
	self:UpdatePlayers()
end

-- Player buttons ------------------------------------------------------------
-- One small button per group member under the main button, filling columns of five:
--   party: 1 column     10-man: 2     25-man: 5     40-man: 8 (one per raid group)
--   very big raids: ten columns, as many rows as needed
local pframe
local pbuttons = {}
local layoutSig
local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
local GAP = 2

--- list of members (already sorted) -> array of columns, each an array of members
function UI.BuildColumns(list, isRaid)
	local cols = {}
	if isRaid then
		local bySub, subs = {}, {}
		for _, m in ipairs(list) do
			local g = m.subgroup or 1
			if not bySub[g] then bySub[g] = {}; subs[#subs + 1] = g end
			table.insert(bySub[g], m)
		end
		table.sort(subs)
		local ok = #subs <= 10
		for _, g in ipairs(subs) do
			if #bySub[g] > 6 then ok = false end
		end
		if ok then
			for _, g in ipairs(subs) do cols[#cols + 1] = bySub[g] end
			return cols
		end
	end
	local n = #list
	local rows = 5
	if math.ceil(n / rows) > 10 then rows = math.ceil(n / 10) end
	for i, m in ipairs(list) do
		local c = math.floor((i - 1) / rows) + 1
		cols[c] = cols[c] or {}
		table.insert(cols[c], m)
	end
	return cols
end

local function PlayerTooltip(self)
	if self.sim then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.memberName, BM:ClassColor(self.class))
		GameTooltip:AddLine("Group simulation: this button is not live.", 1, 0.82, 0.2)
		GameTooltip:Show()
		return
	end
	local m = BM.members[self.memberName]
	if not m or not BM.db.tooltips then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(m.name, BM:ClassColor(m.class))
	GameTooltip:AddLine((m.role or "?") .. (m.roleKnown and "" or " (assumed)"), 0.7, 0.7, 0.7)
	local p = Provider()
	if p and p.SelectUnit then
		local res, msg = p:SelectUnit(m, nil)
		if res then
			GameTooltip:AddDoubleLine("Click", res.spell, 0.8, 0.8, 0.8, 1, 1, 1)
		elseif msg then
			GameTooltip:AddLine(msg, 0.4, 1, 0.5)
		end
		for _, l in ipairs(p:ModLines()) do
			GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if p == BM.providers.PALADIN then
			local pref = BM.playerPref[m.name]
			GameTooltip:AddDoubleLine("Right-click", pref and ("Chosen: " .. BM:BlessingName(pref)) or "Choose blessing",
				0.8, 0.8, 0.8, pref and 1 or 0.6, pref and 0.82 or 0.6, pref and 0.2 or 0.6)
		end
	end
	GameTooltip:Show()
end

local function PlayerPreClick(self, button, down)
	if down then return end
	if self.sim then
		ApplyCast(self, nil)
		BM:Notice("Group simulation: these buttons are not live.")
		return
	end
	if InCombatLockdown() then return end
	local p = Provider()
	local m = self.memberName and BM.members[self.memberName]
	if not (p and m and p.SelectUnit) then
		ApplyCast(self, nil)
		return
	end
	local res, msg = p:SelectUnit(m, BM:GetModifier(), true)
	ApplyCast(self, res)
	if not res and msg then BM:Notice(msg) end
	if BM.debugOn then BM:DebugClick(self, res, msg) end
end

local menuFrame
local function ShowPlayerMenu(b)
	local m = b.memberName and BM.members[b.memberName]
	if not m or b.sim or Provider() ~= BM.providers.PALADIN then return end
	if not UIDropDownMenu_Initialize and MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(b, function(_, root)
			root:CreateTitle(m.name)
			root:CreateRadio("Automatic", function() return BM.playerPref[m.name] == nil end,
				function() BM.playerPref[m.name] = nil; BM:RequestRefresh(0.05) end)
			for _, key in ipairs(BM.BLESSING_ORDER) do
				if BM:Knows(BM.BLESSINGS[key].normal) then
					root:CreateRadio(BM:BlessingName(key), function() return BM.playerPref[m.name] == key end,
						function() BM.playerPref[m.name] = key; BM:RequestRefresh(0.05) end)
				end
			end
		end)
		return
	end
	if not UIDropDownMenu_Initialize then return end
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "BuffMePlayerMenu", UIParent, "UIDropDownMenuTemplate")
	end
	UIDropDownMenu_Initialize(menuFrame, function(_, level)
		local info = {}
		info.text = m.name
		info.isTitle = true
		info.notCheckable = true
		UIDropDownMenu_AddButton(info, level)

		info = {}
		info.text = "Automatic"
		info.checked = (BM.playerPref[m.name] == nil)
		info.func = function() BM.playerPref[m.name] = nil; BM:RequestRefresh(0.05); CloseDropDownMenus() end
		UIDropDownMenu_AddButton(info, level)

		for _, key in ipairs(BM.BLESSING_ORDER) do
			if BM:Knows(BM.BLESSINGS[key].normal) then
				info = {}
				info.text = BM:BlessingName(key)
				info.checked = (BM.playerPref[m.name] == key)
				info.func = function() BM.playerPref[m.name] = key; BM:RequestRefresh(0.05); CloseDropDownMenus() end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end
UI.ShowPlayerMenu = ShowPlayerMenu

local function CreatePlayerButton(i)
	local b = CreateFrame("Button", "BuffMePlayer" .. i, pframe, "SecureActionButtonTemplate")
	RegisterClicks(b, "left")
	b:SetAttribute("type", "spell")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(CLASS_TEX)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	b.hl:SetBlendMode("ADD")
	b.hl:SetAllPoints()
	b.pref = b:CreateTexture(nil, "OVERLAY")
	BM.API.Solid(b.pref, 1, 0.82, 0.2, 1)
	b.pref:SetWidth(5)
	b.pref:SetHeight(5)
	b.pref:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
	b.pref:Hide()
	b:SetScript("PreClick", PlayerPreClick)
	b:SetScript("PostClick", PostClick)
	b:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then ShowPlayerMenu(self) end
	end)
	b:SetScript("OnEnter", PlayerTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	S:Apply(b, "button")
	return b
end

-- where the grid sits relative to the main button
local PLACE = {
	below = { pt = { start = "TOPLEFT", center = "TOP", finish = "TOPRIGHT" },
		rel = { start = "BOTTOMLEFT", center = "BOTTOM", finish = "BOTTOMRIGHT" }, dx = 0, dy = -1 },
	above = { pt = { start = "BOTTOMLEFT", center = "BOTTOM", finish = "BOTTOMRIGHT" },
		rel = { start = "TOPLEFT", center = "TOP", finish = "TOPRIGHT" }, dx = 0, dy = 1 },
	right = { pt = { start = "TOPLEFT", center = "LEFT", finish = "BOTTOMLEFT" },
		rel = { start = "TOPRIGHT", center = "RIGHT", finish = "BOTTOMRIGHT" }, dx = 1, dy = 0 },
	left = { pt = { start = "TOPRIGHT", center = "RIGHT", finish = "BOTTOMRIGHT" },
		rel = { start = "TOPLEFT", center = "LEFT", finish = "BOTTOMLEFT" }, dx = -1, dy = 0 },
}
UI.PLACE = PLACE

-- Group simulation: fake players so the layout can be tuned without a group -----
local SIM_CLASSES = {}
for _, c in ipairs({ "WARRIOR", "PALADIN", "PRIEST", "MAGE", "DRUID", "ROGUE", "HUNTER", "SHAMAN", "WARLOCK", "DEATHKNIGHT" }) do
	if BM:ClassExists(c) then SIM_CLASSES[#SIM_CLASSES + 1] = c end
end
BM.sim = { on = false, size = 25 }

local function SimRoster()
	local list = {}
	for i = 1, BM.sim.size do
		local class = (i == 1) and BM.playerClass or SIM_CLASSES[((i - 2) % #SIM_CLASSES) + 1]
		local state = "ok"
		if i % 5 == 2 then state = "need" elseif i % 9 == 0 then state = "far" elseif i % 13 == 0 then state = "off" end
		list[i] = {
			name = (i == 1) and BM.playerName or ("Sim" .. i), unit = "sim" .. i, class = class,
			subgroup = math.floor((i - 1) / 5) + 1, sim = true, simState = state, _order = i,
		}
	end
	return list
end

function BM:SetSimulation(on, size)
	self.sim.on = on and true or false
	if size then self.sim.size = size end
	UI:LayoutPlayers(true)
	UI:Update()
end

function UI:LayoutPlayers(force)
	if not pframe or not btn then return end
	local db = BM.db
	local sim = BM.sim.on
	local p = Provider()
	local show = db.showPlayers and (sim or BM:InGroup()) and p and p.SelectUnit and p:IsAvailable() and true or false

	local list = {}
	if show then
		if sim then
			list = SimRoster()
		else
			for i, m in ipairs(BM.roster) do
				m._order = i
				list[#list + 1] = m
			end
		end
		table.sort(list, function(a, b)
			local ga, gb = a.subgroup or 1, b.subgroup or 1
			if ga ~= gb then return ga < gb end
			return a._order < b._order
		end)
	end

	local parts = { show and "1" or "0", tostring(db.playerSize), tostring(db.scale), tostring(db.alpha),
		tostring(db.showTargetName), tostring(db.iconSize), tostring(db.placement), tostring(db.align),
		sim and "sim" or "live" }
	for _, m in ipairs(list) do
		parts[#parts + 1] = m.name .. ":" .. m.unit .. ":" .. (m.subgroup or 1) .. ":" .. m.class
	end
	local sig = table.concat(parts, ",")
	if sig == layoutSig and not force then return end
	layoutSig = sig

	BM:AfterCombat("players", function()
		if not show then
			pframe:Hide()
			for _, b in ipairs(pbuttons) do b:Hide() end
			return
		end
		local size = db.playerSize or 26
		local isRaid = sim and BM.sim.size > 5 or (not sim and BM.API.NumRaid() > 0)
		local cols = UI.BuildColumns(list, isRaid)
		local inset = math.max(1, S:IconInset() - 1)
		local idx, maxRows = 0, 0
		for c, col in ipairs(cols) do
			if #col > maxRows then maxRows = #col end
			for r, m in ipairs(col) do
				idx = idx + 1
				local b = pbuttons[idx]
				if not b then
					b = CreatePlayerButton(idx)
					pbuttons[idx] = b
				end
				b:SetSize(size, size)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", pframe, "TOPLEFT", (c - 1) * (size + GAP), -(r - 1) * (size + GAP))
				b.memberName = m.name
				b.class = m.class
				b.sim = m.sim and true or nil
				b.simState = m.simState
				b:SetAttribute("unit", (not m.sim) and m.unit or nil)
				local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class]
				if tc then b.icon:SetTexCoord(tc[1] + 0.02, tc[2] - 0.02, tc[3] + 0.02, tc[4] - 0.02) end
				b.icon:ClearAllPoints()
				b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
				b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
				b:Show()
			end
		end
		for i = idx + 1, #pbuttons do
			pbuttons[i].memberName = nil
			pbuttons[i].sim = nil
			pbuttons[i]:Hide()
		end
		pframe:SetSize(#cols * (size + GAP), maxRows * (size + GAP))
		pframe:SetScale(db.scale or 1)
		pframe:SetAlpha(db.alpha or 1)

		local place = PLACE[db.placement] or PLACE.below
		local align = db.align or "start"
		if not place.pt[align] then align = "start" end
		local gap = 4
		if place == PLACE.below and db.showTargetName then gap = 18 end
		pframe:ClearAllPoints()
		pframe:SetPoint(place.pt[align], btn, place.rel[align], place.dx * gap, place.dy * gap)
		pframe:Show()
	end)
end

--- Colour each player button by what that person still needs.
function UI:UpdatePlayers()
	if not pframe or not pframe:IsShown() or InCombatLockdown() then return end
	local p = Provider()
	if not (p and p.UnitStates) then return end
	local states = BM.sim.on and {} or p:UnitStates()
	for _, b in ipairs(pbuttons) do
		if b.memberName and b:IsShown() then
			local st = b.sim and b.simState or states[b.memberName] or "na"
			if BM.playerPref[b.memberName] and not b.sim then b.pref:Show() else b.pref:Hide() end
			if st == "need" then S:Border(b, "accent")
			elseif st == "ok" then S:Border(b, "good")
			else S:Border(b, nil) end
			b.icon:SetAlpha((st == "need" or st == "ok") and 1 or (st == "off" and 0.3 or 0.5))
			b.icon:SetDesaturated((st == "off") and true or false)
		end
	end
end

-- Minimap icon --------------------------------------------------------------
local function MinimapAngleFromCursor()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	return math.deg(math.atan2(py - my, px - mx)) % 360
end

function UI:PositionMinimap()
	if not mini then return end
	local angle = math.rad(BM.db.minimap.angle or 215)
	local x, y = math.cos(angle), math.sin(angle)
	local half = Minimap:GetWidth() / 2
	local radius
	if mini.square then
		local m = math.max(math.abs(x), math.abs(y))
		x, y = x / m, y / m
		radius = half + 2
	else
		radius = half + 5
	end
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

function UI:StyleMinimap()
	if not mini then return end
	local _, name = S:Theme()
	mini.square = S:MinimapIsSquare() or name == "elvui"
	mini.icon:ClearAllPoints()
	if mini.square then
		mini:SetSize(26, 26)
		mini.overlay:Hide()
		mini.background:Hide()
		S:Apply(mini, "button")
		local inset = S:IconInset()
		mini.icon:SetPoint("TOPLEFT", mini, "TOPLEFT", inset, -inset)
		mini.icon:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", -inset, inset)
		mini.lock:ClearAllPoints()
		mini.lock:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", 3, -3)
	else
		S.registry[mini] = nil
		if mini.SetBackdrop then mini:SetBackdrop(nil) end
		mini:SetSize(31, 31)
		mini.overlay:Show()
		mini.background:Show()
		mini.icon:SetSize(17, 17)
		mini.icon:SetPoint("TOPLEFT", mini, "TOPLEFT", 7, -6)
		mini.lock:ClearAllPoints()
		mini.lock:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", 0, 2)
	end
	self:PositionMinimap()
end

function UI:UpdateMinimap()
	if not mini then return end
	local p = Provider()
	local tex = (p and p.DefaultTexture and p:IsAvailable() and p:DefaultTexture())
		or "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings"
	mini.icon:SetTexture(tex)
	if BM.db.locked then
		mini.icon:SetVertexColor(1, 1, 1)
		mini.lock:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
	else
		mini.icon:SetVertexColor(1, 0.85, 0.4)
		mini.lock:SetTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
	end
	if BM.db.minimap.hide then mini:Hide() else mini:Show() end
end

local function CreateMinimapButton()
	mini = CreateFrame("Button", "BuffMeMinimapButton", Minimap)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:SetSize(31, 31)
	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	mini.background = mini:CreateTexture(nil, "BACKGROUND")
	mini.background:SetSize(20, 20)
	mini.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	mini.background:SetPoint("TOPLEFT", mini, "TOPLEFT", 7, -5)

	mini.icon = mini:CreateTexture(nil, "ARTWORK")
	mini.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	mini.overlay = mini:CreateTexture(nil, "OVERLAY")
	mini.overlay:SetSize(53, 53)
	mini.overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	mini.overlay:SetPoint("TOPLEFT")

	mini.lock = mini:CreateTexture(nil, "OVERLAY")
	mini.lock:SetSize(13, 13)

	mini:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			BM:OpenOptions()
		elseif button == "MiddleButton" then
			BM:ToggleGrid()
		else
			BM:ToggleLock()
		end
	end)

	mini:SetScript("OnDragStart", function(self)
		self.dragging = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			BM.db.minimap.angle = MinimapAngleFromCursor()
			UI:PositionMinimap()
		end)
	end)
	mini:SetScript("OnDragStop", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
	end)

	mini:SetScript("OnEnter", function(self)
		if self.dragging then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Buff Me", 0.2, 0.72, 0.95)
		GameTooltip:AddLine(BM.db.locked and "Button is locked" or "Button is UNLOCKED - drag it to move",
			BM.db.locked and 0.4 or 1, BM.db.locked and 1 or 0.82, BM.db.locked and 0.5 or 0.2)
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Left-click", "Lock / unlock", 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Right-click", "Settings", 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Middle-click", "Assignments", 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Drag", "Move this icon", 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

	UI:StyleMinimap()
	UI:UpdateMinimap()
end

-- Lock / position / misc ----------------------------------------------------
function BM:SetLocked(v)
	self.db.locked = v and true or false
	UI:Update()
	UI:UpdateMinimap()
	self:Print(self.db.locked and "Locked." or "Unlocked - drag the button to move it. Left-click the minimap icon to lock it again.")
end

function BM:ToggleLock()
	self:SetLocked(not self.db.locked)
end

function BM:ResetPosition()
	self.db.pos = nil
	self:AfterCombat("pos", function() UI:ApplyPosition() end)
	self:Print("Button position reset.")
end

function BM:OpenOptions()
	if BM.optionsPanel and BM.API.OpenOptions(BM.optionsPanel) then
		return
	else
		self:Print("Settings are not ready yet.")
	end
end

--- Re-apply every visual setting (called by the options panels).
function BM:ApplySettings()
	self:AfterCombat("layout", function()
		UI:Layout()
		UI:ApplyPosition()
		if btn then S:Apply(btn, "button") end
	end)
	S:Refresh()
	UI:StyleMinimap()
	UI:UpdateMinimap()
	UI:LayoutPlayers(true)
	UI:Update()
end

function UI:OnSkinChanged()
	if btn then S:Border(btn, BM.db.locked and "good" or "unlocked") end
	if grid then S:Apply(grid, "window") end
end
S.onRefresh = function() UI:OnSkinChanged() end

-- Assignment window ---------------------------------------------------------
local NAME_W, CELL, PAD, ROW_H, HEAD_H, MAXROWS = 120, 30, 12, 32, 34, 10
local ICONS = "Interface\\WorldStateFrame\\Icons-Classes"

local function CanEdit(pal)
	return pal == BM.playerName or BM:IsOfficer(BM.playerName) or not BM:InGroup()
end

local function CellClick(self, mouse)
	local pal, class = self.pal, self.class
	if not pal then return end
	if not CanEdit(pal) then
		BM:Notice("Only that paladin, or a raid leader / assistant, can change this.")
		return
	end
	if mouse == "RightButton" then
		BM:SetOverride(pal, class, "auto")
		return
	end
	local m = BM.members[pal]
	if not (m and m.caps) then return end
	local list = {}
	for _, k in ipairs(BM.BLESSING_ORDER) do
		if m.caps[k] then list[#list + 1] = k end
	end
	list[#list + 1] = "none"
	local cur = (BM.overrides[pal] and BM.overrides[pal][class])
		or (BM.plan and BM.plan.class[pal] and BM.plan.class[pal][class]) or "none"
	local idx = 0
	for i, k in ipairs(list) do if k == cur then idx = i break end end
	BM:SetOverride(pal, class, list[(idx % #list) + 1])
end

local function CellTooltip(self)
	if not self.pal then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local loc = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[self.class]) or self.class
	GameTooltip:AddLine(self.pal .. "  >  " .. loc, BM:ClassColor(self.class))
	local key = BM.plan and BM.plan.class[self.pal] and BM.plan.class[self.pal][self.class]
	GameTooltip:AddLine(key and BM:BlessingName(key) or "Nothing assigned", 1, 1, 1)
	if BM.overrides[self.pal] and BM.overrides[self.pal][self.class] then
		GameTooltip:AddLine("Manual override", 1, 0.82, 0.2)
	else
		GameTooltip:AddLine("Automatic", 0.4, 1, 0.5)
	end
	if CanEdit(self.pal) then
		GameTooltip:AddLine("Click: change   Right-click: back to automatic", 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

local function CreateGrid()
	grid = CreateFrame("Frame", "BuffMeGrid", UIParent)
	grid:SetFrameStrata("DIALOG")
	grid:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	grid:SetClampedToScreen(true)
	grid:EnableMouse(true)
	grid:SetMovable(true)
	grid:RegisterForDrag("LeftButton")
	grid:SetScript("OnDragStart", grid.StartMoving)
	grid:SetScript("OnDragStop", grid.StopMovingOrSizing)
	grid:SetWidth(PAD * 2 + NAME_W + CELL * #BM.CLASS_ORDER)
	grid:SetHeight(120)
	S:Apply(grid, "window")

	grid.title = grid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	grid.title:SetPoint("TOPLEFT", grid, "TOPLEFT", PAD, -10)
	grid.title:SetText("Buff Me - Paladin assignments")

	grid.close = CreateFrame("Button", nil, grid, "UIPanelCloseButton")
	grid.close:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 2, 2)

	grid.empty = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	grid.empty:SetPoint("TOP", grid, "TOP", 0, -64)
	grid.empty:SetText("No paladins using Buff Me in this group.")

	grid.hint = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	grid.hint:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", PAD, 8)
	grid.hint:SetText("Updates automatically. Click a cell to override it, right-click to go back to automatic.")

	grid.head = {}
	for j, class in ipairs(BM.CLASS_ORDER) do
		local t = grid:CreateTexture(nil, "ARTWORK")
		t:SetSize(22, 22)
		t:SetTexture(ICONS)
		local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if c then t:SetTexCoord(c[1], c[2], c[3], c[4]) end
		t:SetPoint("TOPLEFT", grid, "TOPLEFT", PAD + NAME_W + (j - 1) * CELL + 4, -34)
		grid.head[j] = t
	end

	grid.rows = {}
	for i = 1, MAXROWS do
		local row = {}
		row.name = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", grid, "TOPLEFT", PAD, -(34 + HEAD_H - 4 + (i - 1) * ROW_H) - 8)
		row.name:SetWidth(NAME_W - 4)
		row.name:SetJustifyH("LEFT")
		row.cells = {}
		for j, class in ipairs(BM.CLASS_ORDER) do
			local cell = CreateFrame("Button", nil, grid)
			cell:SetSize(CELL - 4, CELL - 4)
			cell:SetPoint("TOPLEFT", grid, "TOPLEFT", PAD + NAME_W + (j - 1) * CELL + 2, -(34 + HEAD_H - 4 + (i - 1) * ROW_H) - 2)
			cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			cell.icon = cell:CreateTexture(nil, "ARTWORK")
			cell.icon:SetAllPoints()
			cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			cell.edge = cell:CreateTexture(nil, "BORDER")
			cell.edge:SetPoint("TOPLEFT", -1, 1)
			cell.edge:SetPoint("BOTTOMRIGHT", 1, -1)
			BM.API.Solid(cell.edge, 1, 0.82, 0.2, 1)
			cell:SetScript("OnClick", CellClick)
			cell:SetScript("OnEnter", CellTooltip)
			cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
			cell.class = class
			row.cells[j] = cell
		end
		grid.rows[i] = row
	end

	if UISpecialFrames then table.insert(UISpecialFrames, "BuffMeGrid") end
	grid:Hide()
end

function UI:UpdateGrid()
	if not grid or not grid:IsShown() then return end
	local plan = BM.plan
	local pals = plan and plan.pals or {}
	local count = math.min(#pals, MAXROWS)
	if count == 0 then grid.empty:Show() else grid.empty:Hide() end
	for i = 1, MAXROWS do
		local row = grid.rows[i]
		local pal = pals[i]
		if pal and i <= count then
			row.name:SetText(pal.name)
			row.name:SetTextColor(BM:ClassColor("PALADIN"))
			row.name:Show()
			for j, class in ipairs(BM.CLASS_ORDER) do
				local cell = row.cells[j]
				cell.pal = pal.name
				local key = plan.class[pal.name] and plan.class[pal.name][class]
				local present = plan.present[class]
				if key then
					cell.icon:SetTexture(BM:BlessingTexture(key))
				else
					cell.icon:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
				end
				cell.icon:SetAlpha(present and 1 or 0.2)
				cell.icon:SetDesaturated(not present and true or false)
				local ov = BM.overrides[pal.name] and BM.overrides[pal.name][class]
				if ov then cell.edge:Show() else cell.edge:Hide() end
				cell:Show()
			end
		else
			row.name:Hide()
			for j = 1, #BM.CLASS_ORDER do
				row.cells[j].pal = nil
				row.cells[j]:Hide()
			end
		end
	end
	grid:SetHeight(34 + HEAD_H + math.max(count, 1) * ROW_H + 34)
end

function BM:ToggleGrid()
	if not grid then return end
	if grid:IsShown() then grid:Hide() else grid:Show(); UI:UpdateGrid() end
end

-- Misc events / init --------------------------------------------------------
local updater = CreateFrame("Frame")
local acc = 0
updater:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.6 then return end
	acc = 0
	if btn and not InCombatLockdown() then UI:Update() end
end)

BM:On("PLAYER_REGEN_DISABLED", function() if btn then UI:Update() end end)
BM:On("PLAYER_REGEN_ENABLED", function()
	if btn and not btn:IsMouseOver() then ClearOverrideBindings(btn) end
	UI:Update()
end)
BM:On("BAG_UPDATE", function() BM:ScheduleOnce("bags", 0.5, function() UI:Update() end) end)

BM:OnInit(function()
	CreateButton()
	pframe = CreateFrame("Frame", "BuffMePlayers", UIParent)
	pframe:SetFrameStrata("MEDIUM")
	pframe:Hide()
	CreateMinimapButton()
	CreateGrid()
	BM:Refresh()
end)
