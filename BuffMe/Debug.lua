--[[ Buff Me - Debug
     /bm spells : which buff spells (and ranks) Buff Me found in your spellbook
     /bm debug  : one-screen report to paste into a bug report; "/bm debug on" also logs
                  every click and every cast event until "/bm debug off"
]]

local BM = BuffMe

local function S(v)
	local ok, r = pcall(tostring, v)
	return ok and r or "?"
end

--- All spell definitions of the player's class (blessings, buffs).
local function MyDefs()
	local out = {}
	if BM.playerClass == "PALADIN" then
		for _, key in ipairs(BM.BLESSING_ORDER) do
			local d = BM.BLESSINGS[key]
			out[#out + 1] = d.normal
			out[#out + 1] = d.greater
		end
	else
		local p = BM.providers and BM.providers[BM.playerClass]
		for _, def in ipairs((p and p.defs) or {}) do
			for _, k in ipairs({ "single", "group", "aoe" }) do
				if def[k] then out[#out + 1] = def[k] end
			end
		end
	end
	return out
end

function BM:DumpSpells()
	self:Print("Spells for your class (" .. S(self.playerClass) .. "):")
	local any = false
	for _, def in ipairs(MyDefs()) do
		if self:Knows(def) then
			any = true
			self:Print("  |cff66ff66known|r  " .. self:SpellLabel(def))
		else
			self:Print("  |cff888888not learned|r  " .. self:SpellName(def))
		end
	end
	if not any then self:Print("  none of this class's buff spells are in your spellbook yet.") end
end

function BM:DebugReport()
	local ver, build, _, toc = GetBuildInfo()
	self:Print("--- Buff Me report (paste this when something does not work) ---")
	self:Print(("Buff Me %s | client %s build %s toc %s | forever=%s modern=%s | project=%s"):format(
		S(self.version), S(ver), S(build), S(toc), S(self.forever), S(self.modern), S(WOW_PROJECT_ID)))
	self:Print(("class=%s level=%s | spec=%s role=%s (setting: %s) | castMode=%s | KeyDownCVar=%s"):format(
		S(self.playerClass), S(UnitLevel("player")), S(self.mySpec), S(self.myRole), S(self.db.myRole),
		S(self.db.castMode), S(GetCVar and GetCVar("ActionButtonUseKeyDown"))))
	local api = {}
	for _, n in ipairs({ "C_Spell", "C_SpellBook", "C_UnitAuras", "C_Item", "Settings", "GetTalentTabInfo", "GetSpecialization", "UnitBuff" }) do
		api[#api + 1] = n .. "=" .. (_G[n] and "yes" or "no")
	end
	self:Print("API: " .. table.concat(api, " "))
	self:DumpSpells()

	-- what the talent / spec readers return, and which talent-ish functions this client has
	local gs = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
	local okS, sv = false, nil
	if gs then okS, sv = pcall(gs) end
	local ut = {}
	for k, v in pairs(_G) do
		if type(v) == "function" and type(k) == "string" and (k:find("Talent") or k:find("Specializ")) and #ut < 40 then
			ut[#ut + 1] = k
		end
	end
	table.sort(ut)
	local tabs = {}
	if GetTalentTabInfo then
		for i = 1, 3 do
			local okT, a, b, c, d, e = pcall(GetTalentTabInfo, i)
			tabs[#tabs + 1] = i .. "=" .. S(okT) .. "/" .. S(a) .. "/" .. S(c) .. "/" .. S(e)
		end
	end
	self:Print(("spec readers: getSpec=%s -> %s | roleHint=%s | groupRole=%s | tabs: %s"):format(
		S(gs ~= nil), S(sv), S(self.API.RoleHint(self.playerClass)),
		S(UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")), table.concat(tabs, " ")))
	self:Print("talent functions: " .. table.concat(ut, ", "))

	local btn = _G.BuffMeButton
	if btn then
		self:Print(("button: shown=%s type=%s spell=%s unit=%s macrotext=%s useOnKeyDown=%s"):format(
			S(btn:IsShown()), S(btn:GetAttribute("type")), S(btn:GetAttribute("spell")), S(btn:GetAttribute("unit")),
			S(btn:GetAttribute("macrotext")), S(btn:GetAttribute("useOnKeyDown"))))
	end
	local last = self.UI and self.UI.last
	if last then
		self:Print(("next: %s -> %s | message: %s"):format(
			S(last.res and last.res.spell), S(last.res and last.res.name), S(last.msg)))
	end
	local plan = self.plan
	if plan and plan.class and plan.class[self.playerName] then
		local parts = {}
		for _, class in ipairs(self.CLASS_ORDER) do
			local b = plan.class[self.playerName][class]
			if b then parts[#parts + 1] = class:sub(1, 4) .. "=" .. b end
		end
		self:Print("my plan: " .. (#parts > 0 and table.concat(parts, " ") or "(nothing assigned)"))
	end
	self:Print("Logging is " .. (self.debugOn and "ON (clicks and cast events are printed)" or "off") .. ".  /bm debug on | off")
end

function BM:DebugClick(frame, res, msg)
	self:Print(("click %s: type=%s spell=%s unit=%s macro=%s | pick=%s%s"):format(
		S(frame:GetName()), S(frame:GetAttribute("type")), S(frame:GetAttribute("spell")), S(frame:GetAttribute("unit")),
		S(frame:GetAttribute("macrotext")), S(res and res.spell), msg and (" msg=" .. S(msg)) or ""))
end

for _, ev in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED",
		"UNIT_SPELLCAST_INTERRUPTED", "UI_ERROR_MESSAGE" }) do
	BM:On(ev, function(e, a, b, c, d)
		if not BM.debugOn then return end
		if e:find("^UNIT_SPELLCAST") and a ~= "player" then return end
		BM:Print("event " .. e .. " " .. S(a) .. " " .. S(b) .. " " .. S(c) .. " " .. S(d))
	end)
end
