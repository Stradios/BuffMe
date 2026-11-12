--[[ Buff Me - Paladin
     1. Assignment plan: who casts which blessing on which class, worked out
        automatically from the group's classes, roles and the paladins' specs.
        Every Buff Me client runs the same deterministic algorithm on the same
        shared data, so nobody has to press "Auto-Assign".
     2. Smart cast: each click picks the next person that needs a buff.
        No modifier   -> the assigned (Greater) blessing for whoever needs it next
        Shift         -> Blessing of Kings   on your target / mouseover / yourself
        Ctrl          -> Blessing of Might   (same targeting)
        Alt           -> Blessing of Wisdom  (same targeting)
        Shift + Ctrl  -> Blessing of Sanctuary
]]

local BM = BuffMe
local ipairs, pairs, tinsert, sort = ipairs, pairs, table.insert, table.sort

local HOLY, PROT, RET = 1, 2, 3
local PHYS = { tank = true, melee = true, ranged = true }

-- What each role really wants, best first (used for per-player exceptions)
local IDEAL = {
	tank   = { "kings", "sanctuary", "might" },
	melee  = { "kings", "might" },
	ranged = { "kings", "might" },
	healer = { "kings", "wisdom" },
	caster = { "kings", "wisdom" },
}

-- Classes whose needs don't depend on spec
local FIXED_PRIORITY = {
	WARRIOR = { "kings", "might" }, ROGUE = { "kings", "might" }, DEATHKNIGHT = { "kings", "might" },
	HUNTER = { "kings", "might", "wisdom" },
	PRIEST = { "kings", "wisdom" }, MAGE = { "kings", "wisdom" }, WARLOCK = { "kings", "wisdom" },
}

local function InList(list, v)
	for i = 1, #list do if list[i] == v then return true end end
	return false
end

--- Blessings a class benefits from at class level, best first.
local function ClassPriority(class, members)
	local fixed = FIXED_PRIORITY[class]
	if fixed then return fixed end
	local phys, mana, unknown = 0, 0, 0
	for _, m in ipairs(members) do
		if m.class == class then
			if not m.roleKnown then unknown = unknown + 1
			elseif PHYS[m.role] then phys = phys + 1
			else mana = mana + 1 end
		end
	end
	local wantMight = phys > 0 or unknown > 0
	local wantWisdom = mana > 0 or unknown > 0
	local list = { "kings" }
	if phys >= mana then
		if wantMight then list[#list + 1] = "might" end
		if wantWisdom then list[#list + 1] = "wisdom" end
	else
		if wantWisdom then list[#list + 1] = "wisdom" end
		if wantMight then list[#list + 1] = "might" end
	end
	return list
end

-- Assignment plan -----------------------------------------------------------
function BM:ComputePlan()
	local members = self.roster
	local db = self.db or BM.defaults
	local plan = { pals = {}, class = {}, single = {}, owner = {}, present = {} }
	self.plan = plan

	for _, m in ipairs(members) do
		if m.class == "PALADIN" and m.caps then tinsert(plan.pals, m) end
	end
	sort(plan.pals, function(a, b) return a.name < b.name end)
	local pals = plan.pals
	local n = #pals
	if n == 0 then return plan end

	-- group composition
	local phys, mana, tanks = 0, 0, 0
	for _, m in ipairs(members) do
		plan.present[m.class] = true
		if PHYS[m.role] then phys = phys + 1 else mana = mana + 1 end
		if m.roleKnown and m.role == "tank" then tanks = tanks + 1 end
	end

	-- blessings worth casting for this group, most important first
	local B
	if n == 1 then
		B = { db.singlePaladinKings and "kings" or "auto" }
	else
		B = { "kings" }
		local first, second, nfirst, nsecond = "might", "wisdom", phys, mana
		if mana > phys then first, second, nfirst, nsecond = "wisdom", "might", mana, phys end
		if nfirst > 0 then B[#B + 1] = first end
		if nsecond > 0 then B[#B + 1] = second end
		if tanks > 0 then B[#B + 1] = "sanctuary" end
	end
	local Bn = {}
	for i = 1, math.min(n, #B) do Bn[i] = B[i] end

	-- decide which paladin owns which blessing (specs first, Kings takes whoever is left)
	local RANK = { sanctuary = 1, might = 2, wisdom = 3, kings = 4, auto = 5 }
	local procOrder = {}
	for _, b in ipairs(Bn) do procOrder[#procOrder + 1] = b end
	sort(procOrder, function(a, b) return RANK[a] < RANK[b] end)

	local function score(b, p)
		if b == "auto" then return 1 end
		if not p.caps[b] then return nil end
		if (b == "might" and p.spec == RET) or (b == "wisdom" and p.spec == HOLY) or (b == "sanctuary" and p.spec == PROT) then
			return 3
		end
		return 1
	end

	local owners, used = {}, {}
	for _, b in ipairs(procOrder) do
		local best, bestScore
		for _, p in ipairs(pals) do
			if not used[p.name] then
				local s = score(b, p)
				if s and (not bestScore or s > bestScore) then best, bestScore = p, s end
			end
		end
		if best then
			owners[b] = best
			used[best.name] = true
			plan.owner[best.name] = b
		end
	end

	local order = {}
	for _, b in ipairs(Bn) do
		if owners[b] then order[#order + 1] = { pal = owners[b], b = b } end
	end

	-- class level assignment (these become Greater Blessings in bigger groups).
	-- Pass 1: every paladin takes the blessing he owns wherever the class benefits from it.
	-- Pass 2: paladins whose blessing is useless for that class fill whatever gap is left.
	for class in pairs(plan.present) do
		local P = ClassPriority(class, members)
		local covered = {}

		local function assign(pal, pick)
			covered[pick] = true
			plan.class[pal.name] = plan.class[pal.name] or {}
			plan.class[pal.name][class] = pick
		end

		local leftover = {}
		for _, o in ipairs(order) do
			local pal, b = o.pal, o.b
			if b == "auto" then
				local pick = P[2] or P[1]
				if not pal.caps[pick] then pick = "kings" end
				assign(pal, pick)
			elseif b ~= "sanctuary" then
				if InList(P, b) and not covered[b] and pal.caps[b] then
					assign(pal, b)
				else
					leftover[#leftover + 1] = o
				end
			end
		end
		for _, o in ipairs(leftover) do
			for _, x in ipairs(P) do
				if not covered[x] and o.pal.caps[x] then
					assign(o.pal, x)
					break
				end
			end
		end
	end

	-- manual overrides win over the automatic choice
	for _, pal in ipairs(pals) do
		local ov = self.overrides[pal.name]
		if ov then
			plan.class[pal.name] = plan.class[pal.name] or {}
			for class, value in pairs(ov) do
				if value == "none" then
					plan.class[pal.name][class] = nil
				elseif self.BLESSINGS[value] then
					plan.class[pal.name][class] = value
				end
			end
		end
	end

	-- per-player exceptions: someone whose spec needs something the class-wide
	-- blessings don't give them (tank -> Sanctuary, healer paladin -> Wisdom, ...).
	-- A paladin can only keep ONE of his blessings on a target, so an exception
	-- always takes the place of his class-wide blessing on that person.
	local function hasSingle(pal, u)
		return plan.single[pal.name] and plan.single[pal.name][u.name]
	end

	local function pickCaster(want, u, ideal)
		if want == "sanctuary" and owners.sanctuary and not hasSingle(owners.sanctuary, u) then
			return owners.sanctuary
		end
		for _, pal in ipairs(pals) do
			if pal.caps[want] and not hasSingle(pal, u) then
				local cb = plan.class[pal.name] and plan.class[pal.name][u.class]
				if cb == nil or not InList(ideal, cb) then return pal end
			end
		end
		-- a paladin who tanks swaps his own class blessing for Sanctuary on himself
		if want == "sanctuary" and u.class == "PALADIN" and u.caps and u.caps.sanctuary and not hasSingle(u, u) then
			return u
		end
	end

	for _, u in ipairs(members) do
		local ideal = u.roleKnown and IDEAL[u.role]
		if ideal then
			local got = {}
			for _, pal in ipairs(pals) do
				local x = plan.class[pal.name] and plan.class[pal.name][u.class]
				if x then got[x] = true end
			end
			for _, want in ipairs(ideal) do
				if want ~= "kings" and not got[want] then
					local pal = pickCaster(want, u, ideal)
					if pal then
						plan.single[pal.name] = plan.single[pal.name] or {}
						plan.single[pal.name][u.name] = want
						got[want] = true
					end
				end
			end
		end
	end

	return plan
end

-- Casting -------------------------------------------------------------------
function BM:UseGreater(key)
	local db = self.db
	local def = self.BLESSINGS[key]
	if not def or db.greaterMode == "normal" then return false end
	if not self:Knows(def.greater) then return false end
	if BM.API.GetItemCount(self.SYMBOL_OF_KINGS) == 0 then return false end
	if db.greaterMode == "greater" then return true end
	return self:GroupSize() >= db.greaterMinGroup
end

local P = { class = "PALADIN" }
BM.providers = BM.providers or {}
BM.providers.PALADIN = P

local recent = {}
local function IsRecent(key)
	local t = recent[key]
	return t and (GetTime() - t) < 3
end

local function GCDActive(spell)
	local s, d = BM.API.GetSpellCooldown(spell)
	return s and s > 0 and d and d > 0 and (s + d - GetTime()) > 0.25
end

local function SpellFor(key, wantGreater)
	local def = BM.BLESSINGS[key]
	if not def then return nil end
	if wantGreater and BM:Knows(def.greater) then return def.greater, true end
	if BM:Knows(def.normal) then return def.normal, false end
	return nil
end

local function NamesFor(key)
	local def = BM.BLESSINGS[key]
	return { BM:SpellName(def.normal), BM:SpellName(def.greater) }
end

function P:IsAvailable()
	return BM:Knows(BM.BLESSINGS.kings.normal) or BM:Knows(BM.BLESSINGS.might.normal) or BM:Knows(BM.BLESSINGS.wisdom.normal)
end

--- The one blessing I should have on each person, and whether each class gets
--  Greater Blessings. A Greater Blessing hits a whole class, so it is only used
--  when everyone of that class is meant to get the same blessing; a class that
--  has individual exceptions (a tank next to DPS, say) gets normal blessings.
function P:Wanted()
	local plan = BM.plan
	local me = BM.playerName
	local mine = (plan and plan.class[me]) or {}
	local singles = {}
	for name, key in pairs((plan and plan.single[me]) or {}) do singles[name] = key end
	-- blessings picked by hand on a player's button win over the automatic choice
	for name, key in pairs(BM.playerPref) do
		local m = BM.members[name]
		if m and BM.BLESSINGS[key] and mine[m.class] ~= key then singles[name] = key end
	end
	local wanted, greater = {}, {}
	for class, list in pairs(BM.byClass) do
		local ex, first, same = 0, nil, true
		for _, m in ipairs(list) do
			local s = singles[m.name]
			if s then
				ex = ex + 1
				if first and first ~= s then same = false end
				first = first or s
			end
		end
		local classKey = mine[class]
		for _, m in ipairs(list) do wanted[m.name] = singles[m.name] or classKey end
		if ex == 0 then
			greater[class] = (classKey and BM:UseGreater(classKey)) or false
		elseif ex == #list and same then
			greater[class] = BM:UseGreater(first)
		else
			greater[class] = false
		end
	end
	return wanted, greater
end

--- Returns (result) or (nil, message).
--  mod: nil | "shift" | "ctrl" | "alt" | "ctrlshift"; commit: remember the pick (real click)
function P:Select(mod, commit)
	local db = BM.db
	if mod and db.mods[mod] then return self:SelectManual(mod) end
	if not BM.plan then return nil, "Not ready yet." end

	local wanted, greaterOf = self:Wanted()
	local minLeft = (db.rebuffMinutes or 2) * 60
	local cache = {}
	local function auras(m)
		local a = cache[m.name]
		if not a then a = BM:ReadAuras(m.unit); cache[m.name] = a end
		return a
	end

	local cands, pending, far = {}, 0, 0
	for class, list in pairs(BM.byClass) do
		local groupCand
		for _, m in ipairs(list) do
			local key = wanted[m.name]
			if key and BM:UnitUsable(m.unit) then
				local sdef, isGreater = SpellFor(key, greaterOf[class])
				if sdef then
					local spell = BM:SpellName(sdef)
					if not BM:HasAny(auras(m), NamesFor(key), minLeft) then
						if BM.API.IsSpellInRange(spell, m.unit) == 1 then
							if not IsRecent(m.name .. "|" .. spell) then
								pending = pending + 1
								if isGreater then
									if not groupCand then
										groupCand = {
											unit = m.unit, name = m.name, class = class, spell = spell,
											texture = BM:SpellTexture(sdef), count = 0, greater = true,
											key = m.name .. "|" .. spell,
										}
									end
									groupCand.count = groupCand.count + 1
								else
									cands[#cands + 1] = {
										unit = m.unit, name = m.name, class = class, spell = spell,
										texture = BM:SpellTexture(sdef), count = 1, greater = false,
										key = m.name .. "|" .. spell,
									}
								end
							end
						else
							far = far + 1
						end
					end
				end
			end
		end
		if groupCand then cands[#cands + 1] = groupCand end
	end

	if #cands == 0 then
		if far > 0 then return nil, "Nobody in range needs a buff.", far end
		return nil, "Everyone is buffed.", 0
	end

	sort(cands, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		if a.name ~= b.name then return a.name < b.name end
		return a.spell < b.spell
	end)
	local c = cands[1]
	if commit and not GCDActive(c.spell) then recent[c.key] = GetTime() end
	c.pending = pending
	return c
end

--- Shift / Ctrl / Alt click on the main button: one specific blessing on target / mouseover / you.
function P:SelectManual(mod, unitOverride)
	local key = BM.db.mods[mod]
	local def = key and BM.BLESSINGS[key]
	if not def then return nil, "No blessing is set for that key combination." end
	if not BM:Knows(def.normal) then return nil, "You don't know " .. BM:BlessingName(key) .. "." end
	local unit = unitOverride or BM:ResolveManualUnit()
	return {
		spell = BM:SpellName(def.normal), unit = unit, texture = BM:SpellTexture(def.normal),
		name = UnitName(unit), manual = true, pending = 0, count = 1,
	}
end

--- Click on one person's own button.
function P:SelectUnit(m, mod)
	if mod and BM.db.mods[mod] then return self:SelectManual(mod, m.unit) end
	if not BM.plan then return nil, "Not ready yet." end
	local wanted, greaterOf = self:Wanted()
	local key = wanted[m.name]
	if not key then return nil, "Nothing is assigned to you for " .. m.name .. "'s class." end
	local sdef = SpellFor(key, greaterOf[m.class])
	if not sdef then return nil, "You don't know " .. BM:BlessingName(key) .. "." end
	return {
		spell = BM:SpellName(sdef), unit = m.unit, texture = BM:SpellTexture(sdef),
		name = m.name, class = m.class, pending = 0, count = 1,
	}
end

--- name -> "need" | "ok" | "far" | "off" | "na", for the colouring of the player buttons.
function P:UnitStates()
	local out = {}
	if not BM.plan then return out end
	local wanted, greaterOf = self:Wanted()
	local minLeft = (BM.db.rebuffMinutes or 2) * 60
	for _, m in ipairs(BM.roster) do
		local key = wanted[m.name]
		if not BM:UnitUsable(m.unit) then
			out[m.name] = "off"
		elseif not key then
			out[m.name] = "na"
		else
			local sdef = SpellFor(key, greaterOf[m.class])
			if not sdef then
				out[m.name] = "na"
			elseif BM:HasAny(BM:ReadAuras(m.unit), NamesFor(key), minLeft) then
				out[m.name] = "ok"
			else
				out[m.name] = (BM.API.IsSpellInRange(BM:SpellName(sdef), m.unit) == 1) and "need" or "far"
			end
		end
	end
	return out
end

function P:DefaultTexture()
	local mine = BM.plan and BM.plan.class[BM.playerName]
	local key = "kings"
	if mine then
		for _, class in ipairs(BM.CLASS_ORDER) do
			if mine[class] then key = mine[class] break end
		end
	end
	return BM:BlessingTexture(key)
end

--- Lines for the tooltip: { left, right } pairs.
function P:ModLines()
	local out = {}
	local db = BM.db
	local labels = { { "shift", "Shift" }, { "ctrl", "Ctrl" }, { "alt", "Alt" }, { "ctrlshift", "Shift+Ctrl" } }
	for _, e in ipairs(labels) do
		local key = db.mods[e[1]]
		if key then out[#out + 1] = { e[2] .. " + click", BM:BlessingName(key) .. " (normal)" } end
	end
	return out
end

function P:PlanLines()
	local out = {}
	local plan = BM.plan
	local mine = plan and plan.class[BM.playerName]
	local _, greaterOf = self:Wanted()
	if mine then
		for _, class in ipairs(BM.CLASS_ORDER) do
			local b = mine[class]
			if b then
				local loc = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
				local greater = greaterOf[class]
				if greater == nil then greater = BM:UseGreater(b) end
				out[#out + 1] = { loc, BM:BlessingName(b) .. (greater and " (Greater)" or ""), class }
			end
		end
	end
	for who, b in pairs((plan and plan.single[BM.playerName]) or {}) do
		out[#out + 1] = { who, BM:BlessingName(b), (BM.members[who] or {}).class }
	end
	return out
end

function P:ReagentText()
	local n = BM.API.GetItemCount(BM.SYMBOL_OF_KINGS)
	return "Symbol of Kings: " .. n, n
end
