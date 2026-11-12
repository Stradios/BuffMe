--[[ Buff Me - Roster
     Who is in the group, what they play (spec / role), and the small
     addon-message protocol that lets every Buff Me user share their spec,
     paladin capabilities and manual assignment overrides.
]]

local BM = BuffMe
local tinsert, tconcat = table.insert, table.concat

BM.roster = {}      -- array of members
BM.members = {}     -- name -> member
BM.byClass = {}     -- class token -> array of members
BM.comm = {}        -- name -> info broadcast by that player's Buff Me
BM.overrides = {}   -- paladin name -> class token -> blessing key | "none"
BM.myOverrides = {} -- class token -> value (the ones I set for myself; re-sent on join)
BM.mySpec = 0
BM.myRole = nil
BM.inspected = {}   -- name -> { spec, class } read from the talent window of players without Buff Me
BM.playerPref = {}  -- name -> blessing key chosen by right-clicking that player's button (this session)

-- Self ----------------------------------------------------------------------
function BM:MyCaps()
	local caps = {}
	for key, def in pairs(self.BLESSINGS) do
		if self:Knows(def.normal) then caps[key] = true end
	end
	return caps
end

function BM:DetectSelfSpec()
	local best, apiRole = self.API.SelfSpec()
	local roles = (self.modern and self.SPEC_ROLE_MODERN[self.playerClass]) or self.SPEC_ROLE[self.playerClass]
	local role = apiRole or (roles and roles[best])
	if UnitGroupRolesAssigned then
		local r = UnitGroupRolesAssigned("player")
		if r == "TANK" then role = "tank" elseif r == "HEALER" then role = "healer" end
	end
	-- talents unreadable (or not spent yet): look at what you are doing right now
	local hint = self.API.RoleHint(self.playerClass)
	if hint then role = hint end
	-- a role chosen by hand in the settings always wins
	local manual = self.db and self.db.myRole
	if manual and manual ~= "auto" then role = manual end
	-- the paladin plan scores blessings by spec, so give a role-only paladin a matching spec
	if (not best or best == 0) and self.playerClass == "PALADIN" and role then
		best = (role == "healer" and 1) or (role == "tank" and 2) or ((role == "melee" or role == "ranged") and 3) or 0
	end
	self.mySpec = best or 0
	self.myRole = role
	return self.mySpec
end

-- Roster scan ---------------------------------------------------------------
local function GuessRole(m, rosterRole)
	if rosterRole == "MAINTANK" or rosterRole == "maintank" then return "tank", true end
	if UnitGroupRolesAssigned then
		local r = UnitGroupRolesAssigned(m.unit)
		if r == "TANK" then return "tank", true end
		if r == "HEALER" then return "healer", true end
		if r == "DAMAGER" then
			local d = BM.DAMAGE_ROLE[m.class]
			if d then return d, true end
		end
	end
	return BM.DEFAULT_ROLE[m.class] or "melee", false
end

function BM:ScanRoster()
	local roster, members, byClass = {}, {}, {}
	local me = self.playerName

	local function add(unit, subgroup, rosterRole, rank)
		local name = UnitName(unit)
		if not name then return end
		local _, class = UnitClass(unit)
		if not class then return end
		local m = { name = name, unit = unit, class = class, subgroup = subgroup or 1, rank = rank or 0 }
		local info = self.comm[name]
		if name == me then
			m.unit = "player"
			m.isMe = true
			m.hasAddon = true
			m.spec = self.mySpec
			if self.myRole then
				m.role, m.roleKnown = self.myRole, true
			else
				m.role, m.roleKnown = GuessRole(m, rosterRole)
			end
			if class == "PALADIN" then m.caps = self:MyCaps() end
		elseif info then
			m.hasAddon = true
			m.spec = info.spec
			if info.role and info.role ~= "" then
				m.role, m.roleKnown = info.role, true
			else
				m.role, m.roleKnown = GuessRole(m, rosterRole)
			end
			if class == "PALADIN" then m.caps = info.caps end
		else
			local gRole, gKnown = GuessRole(m, rosterRole)
			local insp = self.inspected[name]
			local roles = self.SPEC_ROLE[class]
			if insp and insp.class == class and roles and roles[insp.spec] then
				m.spec = insp.spec
				m.role, m.roleKnown = roles[insp.spec], true
				if gKnown and gRole == "tank" then m.role = "tank" end
			else
				m.role, m.roleKnown = gRole, gKnown
			end
		end
		roster[#roster + 1] = m
		members[name] = m
		byClass[class] = byClass[class] or {}
		tinsert(byClass[class], m)
	end

	local nraid = self.API.NumRaid()
	if nraid > 0 then
		for i = 1, nraid do
			local name, rank, subgroup, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
			if name then add("raid" .. i, subgroup, role, rank) end
		end
	else
		add("player", 1, nil, self.API.IsLeader("player") and 2 or 0)
		for i = 1, self.API.NumParty() do
			add("party" .. i, 1, nil, self.API.IsLeader("party" .. i) and 2 or 0)
		end
	end
	if #roster == 0 then add("player", 1) end

	self.roster, self.members, self.byClass = roster, members, byClass

	-- forget people who left
	for name in pairs(self.comm) do
		if not members[name] then self.comm[name] = nil end
	end
	for pal in pairs(self.overrides) do
		if not members[pal] then self.overrides[pal] = nil end
	end
	for name in pairs(self.inspected) do
		if not members[name] then self.inspected[name] = nil end
	end
	for name in pairs(self.playerPref) do
		if not members[name] then self.playerPref[name] = nil end
	end
end

function BM:IsOfficer(name)
	local m = self.members[name]
	return m and m.rank and m.rank >= 1 or false
end

-- Messaging -----------------------------------------------------------------
function BM:Channel()
	return self.API.Channel()
end

function BM:Send(msg)
	local ch = self:Channel()
	if ch then self.API.SendAddon(self.PREFIX, msg, ch) end
end

function BM:SendHello()
	if not self:Channel() then return end
	local caps = {}
	if self.playerClass == "PALADIN" then
		for key in pairs(self:MyCaps()) do caps[#caps + 1] = key end
		table.sort(caps)
	end
	self:Send(tconcat({ "HI", self.version, self.playerClass, tostring(self.mySpec or 0), self.myRole or "", tconcat(caps, ",") }, "|"))
	for class, value in pairs(self.myOverrides) do
		self:Send(tconcat({ "OVR", self.playerName, class, value }, "|"))
	end
end

function BM:ScheduleHello()
	self:ScheduleOnce("hello", 1.5 + math.random() * 4, function() BM:SendHello() end)
end

local function ParseCaps(str)
	local caps = {}
	for key in (str or ""):gmatch("[^,]+") do caps[key] = true end
	return caps
end

BM:On("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
	sender = BM.API.ShortName(sender)
	if prefix ~= BM.PREFIX or sender == BM.playerName or not msg then return end
	local kind, a, b, c, d, e = strsplit("|", msg)
	if kind == "HI" then
		local isNew = BM.comm[sender] == nil
		BM.comm[sender] = {
			version = a, class = b, spec = tonumber(c) or 0, role = d,
			caps = ParseCaps(e),
		}
		if isNew then BM:ScheduleHello() end
		BM:RequestRefresh(0.4)
	elseif kind == "OVR" then
		-- a = paladin, b = class, c = blessing | "none" | "auto"
		if a and b and c and (sender == a or BM:IsOfficer(sender)) then
			BM:ApplyOverride(a, b, c)
			BM:RequestRefresh(0.2)
		end
	end
end)

-- Overrides -----------------------------------------------------------------
function BM:ApplyOverride(pal, class, value)
	if value == "auto" or value == "" then value = nil end
	self.overrides[pal] = self.overrides[pal] or {}
	self.overrides[pal][class] = value
	if not next(self.overrides[pal]) then self.overrides[pal] = nil end
end

function BM:SetOverride(pal, class, value)
	self:ApplyOverride(pal, class, value)
	if pal == self.playerName then
		self.myOverrides[class] = (value ~= "auto") and value or nil
	end
	self:Send(tconcat({ "OVR", pal, class, value or "auto" }, "|"))
	self:RequestRefresh(0.05)
end

function BM:ClearOverrides()
	local mine = {}
	for class in pairs(self.myOverrides) do mine[#mine + 1] = class end
	self.overrides = {}
	self.myOverrides = {}
	for _, class in ipairs(mine) do
		self:Send(tconcat({ "OVR", self.playerName, class, "auto" }, "|"))
	end
	self:RequestRefresh(0.05)
end


-- Quiet talent inspection ----------------------------------------------------
-- Players without Buff Me can't tell us their spec, so read it from their talent
-- window: one person every few seconds, never in combat, never while you have
-- the inspect window open, and each person only once.
local inspectName, inspectClass
local lastInspect, failedAt = 0, {}

function BM:InspectNext()
	if not self.API.CanInspectTalents() then return end
	if InCombatLockdown() or not self:InGroup() then return end
	if InspectFrame and InspectFrame:IsShown() then return end
	local now = GetTime()
	if now - lastInspect < 3 then return end
	for _, m in ipairs(self.roster) do
		if not m.isMe and not m.hasAddon and not self.inspected[m.name]
			and (not failedAt[m.name] or now - failedAt[m.name] > 120)
			and self:UnitUsable(m.unit) and CanInspect(m.unit) and CheckInteractDistance(m.unit, 1) then
			inspectName, inspectClass = m.name, m.class
			lastInspect = now
			failedAt[m.name] = now
			NotifyInspect(m.unit)
			return
		end
	end
end

BM:On("INSPECT_TALENT_READY", function()
	if not inspectName then return end
	local best, bestPts = 0, 0
	for i = 1, 3 do
		local _, _, pts = GetTalentTabInfo(i, true)
		if pts and pts > bestPts then best, bestPts = i, pts end
	end
	if best > 0 then
		BM.inspected[inspectName] = { spec = best, class = inspectClass }
		failedAt[inspectName] = nil
		BM:RequestRefresh(0.2)
	end
	inspectName, inspectClass = nil, nil
	if ClearInspectPlayer then ClearInspectPlayer() end
end)

local inspectTick, inspectAcc = CreateFrame("Frame"), 0
inspectTick:SetScript("OnUpdate", function(_, elapsed)
	inspectAcc = inspectAcc + elapsed
	if inspectAcc < 1 then return end
	inspectAcc = 0
	BM:InspectNext()
end)

-- Refresh pipeline ----------------------------------------------------------
function BM:Refresh()
	self:ScanRoster()
	if self.ComputePlan then self:ComputePlan() end
	if self.UI then self.UI:Update() end
end

function BM:RequestRefresh(delay)
	self:Schedule("refresh", delay or 0.5, function() BM:Refresh() end)
end

local function RosterChanged()
	BM:RequestRefresh(0.6)
	BM:ScheduleHello()
end

BM:On("RAID_ROSTER_UPDATE", RosterChanged)
BM:On("GROUP_ROSTER_UPDATE", RosterChanged)
BM:On("PARTY_MEMBERS_CHANGED", RosterChanged)
BM:On("PARTY_LEADER_CHANGED", function() BM:RequestRefresh(0.6) end)
BM:On("PLAYER_ENTERING_WORLD", function()
	BM:ScanSpellbook()
	BM:DetectSelfSpec()
	RosterChanged()
end)

local function SpecChanged()
	BM:Schedule("spec", 1.0, function()
		BM:DetectSelfSpec()
		BM:SendHello()
		BM:RequestRefresh(0.1)
	end)
end
BM:On("PLAYER_TALENT_UPDATE", SpecChanged)
-- stance / form / Righteous Fury changes can flip "tank" on and off
local function RoleMaybeChanged()
	BM:Schedule("rolecheck", 0.6, function()
		local old = BM.myRole
		BM:DetectSelfSpec()
		if BM.myRole ~= old then BM:SendHello(); BM:RequestRefresh(0.1) end
	end)
end
BM:On("UPDATE_SHAPESHIFT_FORM", RoleMaybeChanged)
BM:On("UNIT_AURA", function(_, unit) if unit == "player" and BM.playerClass == "PALADIN" then RoleMaybeChanged() end end)
BM:On("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
	if unit == nil or unit == "player" then SpecChanged() end
end)
BM:On("TRAIT_CONFIG_UPDATED", SpecChanged)
BM:On("ACTIVE_TALENT_GROUP_CHANGED", SpecChanged)
BM:On("SPELLS_CHANGED", function()
	BM:Schedule("spells", 1.0, function() BM:RequestRefresh(0.1); BM:SendHello() end)
end)

BM:On("UNIT_AURA", function(_, unit)
	if unit and (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then
		if BM.UI then BM:ScheduleOnce("auras", 0.25, function() BM.UI:Update() end) end
	end
end)

BM:OnInit(function()
	BM.API.RegisterPrefix(BM.PREFIX)
	BM:ScanSpellbook()
	BM:DetectSelfSpec()
	BM:Refresh()
	-- talent data is sometimes not ready right at login
	BM:Schedule("spec_login", 3, function()
		BM:DetectSelfSpec()
		BM:RequestRefresh(0.1)
	end)
end)

-- Debug ---------------------------------------------------------------------
function BM:DumpPlan()
	local plan = self.plan
	if not plan or #plan.pals == 0 then
		self:Print("No paladins using Buff Me in this group.")
		return
	end
	for _, pal in ipairs(plan.pals) do
		local parts = {}
		for _, class in ipairs(self.CLASS_ORDER) do
			local b = plan.class[pal.name] and plan.class[pal.name][class]
			if b then parts[#parts + 1] = class:sub(1, 4) .. "=" .. b end
		end
		local singles = {}
		for who, b in pairs(plan.single[pal.name] or {}) do singles[#singles + 1] = who .. "=" .. b end
		self:Print(pal.name .. " (" .. (plan.owner[pal.name] or "-") .. "): " .. tconcat(parts, " ") ..
			(#singles > 0 and ("  | single: " .. tconcat(singles, " ")) or ""))
	end
end
