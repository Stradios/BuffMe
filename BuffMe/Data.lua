--[[ Buff Me - Data
     Spell definitions, class tables and small helpers.
     Spells are stored by ID so names come out right in every client language;
     the English name is only a fallback / sanity check.
]]

local BM = BuffMe

local function SP(id, en) return { id = id, en = en } end
BM.SP = SP

-- Spell helpers -------------------------------------------------------------
function BM:SpellName(def)
	if def.name then return def.name end
	local n = BM.API.GetSpellInfo(def.id)
	if not n or (GetLocale() == "enUS" and n ~= def.en) then n = def.en end
	def.name = n
	return n
end

function BM:SpellTexture(def)
	local _, _, tex = BM.API.GetSpellInfo(def.id)
	if not tex then _, _, tex = BM.API.GetSpellInfo(self:SpellName(def)) end
	return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local known, knownID = {}, {}
BM.known = known

function BM:ScanSpellbook()
	BM.API.ScanSpellbook(known, knownID)
end

function BM:Knows(def)
	if not def then return false end
	if knownID[def.id] or known[self:SpellName(def)] then return true end
	-- clients that can answer "do I know spell X" directly (ids may differ per client)
	return BM.API.IsSpellKnownByID(def.id) == true
end

BM:On("SPELLS_CHANGED", function() BM:ScanSpellbook() end)
BM:On("LEARNED_SPELL_IN_TAB", function() BM:ScanSpellbook() end)
BM:On("LEARNED_SPELL_IN_SKILL_LINE", function() BM:ScanSpellbook() end)

-- Classes -------------------------------------------------------------------
BM.CLASS_ORDER = {
	"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
	"DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

-- Paladin blessings ---------------------------------------------------------
BM.BLESSINGS = {
	kings     = { normal = SP(20217, "Blessing of Kings"),     greater = SP(25898, "Greater Blessing of Kings") },
	might     = { normal = SP(48932, "Blessing of Might"),     greater = SP(48934, "Greater Blessing of Might") },
	wisdom    = { normal = SP(48936, "Blessing of Wisdom"),    greater = SP(48938, "Greater Blessing of Wisdom") },
	sanctuary = { normal = SP(20911, "Blessing of Sanctuary"), greater = SP(25899, "Greater Blessing of Sanctuary") },
	light     = { normal = SP(19977, "Blessing of Light"),     greater = SP(25890, "Greater Blessing of Light") },
	salvation = { normal = SP(1038,  "Blessing of Salvation"), greater = SP(25895, "Greater Blessing of Salvation") },
}
BM.BLESSING_ORDER = { "kings", "might", "wisdom", "sanctuary", "light", "salvation" }
BM.SYMBOL_OF_KINGS = 21177

function BM:BlessingName(key)
	local def = self.BLESSINGS[key]
	return def and self:SpellName(def.normal) or tostring(key)
end

function BM:BlessingTexture(key)
	local def = self.BLESSINGS[key]
	return def and self:SpellTexture(def.normal) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Roles ---------------------------------------------------------------------
-- tank | melee | ranged | healer | caster
BM.DEFAULT_ROLE = {
	WARRIOR = "melee", ROGUE = "melee", DEATHKNIGHT = "melee", PALADIN = "melee",
	HUNTER = "ranged", MAGE = "caster", WARLOCK = "caster", PRIEST = "healer",
	SHAMAN = "caster", DRUID = "caster",
}

-- Role to assume when the dungeon finder says "DAMAGER" (nil = can't tell)
BM.DAMAGE_ROLE = {
	WARRIOR = "melee", ROGUE = "melee", DEATHKNIGHT = "melee", PALADIN = "melee",
	HUNTER = "ranged", MAGE = "caster", WARLOCK = "caster", PRIEST = "caster",
}

-- role by talent tree index (1..3)
BM.SPEC_ROLE = {
	WARRIOR     = { "melee", "melee", "tank" },
	PALADIN     = { "healer", "tank", "melee" },
	HUNTER      = { "ranged", "ranged", "ranged" },
	ROGUE       = { "melee", "melee", "melee" },
	PRIEST      = { "healer", "healer", "caster" },
	DEATHKNIGHT = { "tank", "melee", "melee" },
	SHAMAN      = { "caster", "melee", "healer" },
	MAGE        = { "caster", "caster", "caster" },
	WARLOCK     = { "caster", "caster", "caster" },
	DRUID       = { "caster", "melee", "healer" },
}

-- Same, for clients that use the specialization API (Druid has four specs there)
BM.SPEC_ROLE_MODERN = {
	WARRIOR     = { "melee", "melee", "tank" },
	PALADIN     = { "healer", "tank", "melee" },
	HUNTER      = { "ranged", "ranged", "ranged" },
	ROGUE       = { "melee", "melee", "melee" },
	PRIEST      = { "healer", "healer", "caster" },
	DEATHKNIGHT = { "tank", "melee", "melee" },
	SHAMAN      = { "caster", "melee", "healer" },
	MAGE        = { "caster", "caster", "caster" },
	WARLOCK     = { "caster", "caster", "caster" },
	DRUID       = { "caster", "melee", "tank", "healer" },
}

-- Helpers -------------------------------------------------------------------
function BM:GroupSize()
	local raid = BM.API.NumRaid()
	if raid > 0 then return raid end
	local party = BM.API.NumParty()
	if party > 0 then return party + 1 end
	return 1
end

function BM:InGroup()
	return self:GroupSize() > 1
end

--- Reads a unit's buffs into { [name] = remainingSeconds | true }.
--  `true` means "present but the client doesn't tell us the timer".
function BM:ReadAuras(unit)
	return BM.API.ReadAuras(unit)
end

--- True when the aura table has any of `names` with at least `minLeft` seconds left.
function BM:HasAny(auras, names, minLeft)
	-- aura data hidden by the client: never guess, treat as "already buffed"
	if auras.restricted then return true end
	for i = 1, #names do
		local v = auras[names[i]]
		if v then
			if v == true or v >= minLeft then return true end
		end
	end
	return false
end

function BM:UnitUsable(unit)
	return UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and UnitIsVisible(unit)
end

--- Which unit a Shift/Ctrl/Alt click should land on: target, then mouseover, then you.
function BM:ResolveManualUnit()
	if UnitExists("target") and UnitIsFriend("player", "target") and UnitIsPlayer("target") then
		return "target"
	end
	if UnitExists("mouseover") and UnitIsFriend("player", "mouseover") and UnitIsPlayer("mouseover") then
		return "mouseover"
	end
	return "player"
end

function BM:GetModifier()
	local s, c, a = IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()
	if s and c and not a then return "ctrlshift" end
	if s and not c and not a then return "shift" end
	if c and not s and not a then return "ctrl" end
	if a and not s and not c then return "alt" end
	return nil
end

function BM:ClassColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end
