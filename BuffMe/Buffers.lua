--[[ Buff Me - Buffers
     Data-driven buffing for every other class that has raid buffs.
     Same controls as the paladin: plain click = next person who needs a buff,
     Shift / Ctrl / Alt + click = a specific single buff on your target.
]]

local BM = BuffMe
local ipairs, pairs, tinsert, sort = ipairs, pairs, table.insert, table.sort
local SP = BM.SP

local MANA = { PALADIN = true, HUNTER = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }

-- single = one-target spell, group = party-wide version, aoe = self-centred shout/horn
-- slot  = modifier that casts it on its own (shift | ctrl | alt | ctrlshift)
local DEFS = {
	MAGE = {
		{ key = "int", single = SP(42995, "Arcane Intellect"), group = SP(43002, "Arcane Brilliance"),
		  slot = "shift", classes = MANA, default = true },
	},
	PRIEST = {
		{ key = "fort", single = SP(48161, "Power Word: Fortitude"), group = SP(48162, "Prayer of Fortitude"),
		  slot = "shift", default = true },
		{ key = "spirit", single = SP(48073, "Divine Spirit"), group = SP(48074, "Prayer of Spirit"),
		  slot = "ctrl", classes = MANA, default = true },
		{ key = "shadow", single = SP(48169, "Shadow Protection"), group = SP(48170, "Prayer of Shadow Protection"),
		  slot = "alt", default = false },
	},
	DRUID = {
		{ key = "motw", single = SP(48469, "Mark of the Wild"), group = SP(48470, "Gift of the Wild"),
		  slot = "shift", default = true },
		{ key = "thorns", single = SP(53307, "Thorns"), slot = "ctrl", roles = { tank = true }, default = false },
	},
	WARRIOR = {
		{ key = "battle", aoe = SP(47436, "Battle Shout"), slot = "shift", default = true },
		{ key = "command", aoe = SP(47440, "Commanding Shout"), slot = "ctrl", default = false },
	},
	DEATHKNIGHT = {
		{ key = "horn", aoe = SP(57623, "Horn of Winter"), slot = "shift", default = true },
	},
}

local recent = {}
local function IsRecent(key)
	local t = recent[key]
	return t and (GetTime() - t) < 3
end

local function GCDActive(spell)
	local s, d = BM.API.GetSpellCooldown(spell)
	return s and s > 0 and d and d > 0 and (s + d - GetTime()) > 0.25
end

local function Matches(def, m)
	if def.classes and not def.classes[m.class] then return false end
	if def.roles and not (m.roleKnown and def.roles[m.role]) then return false end
	return true
end

local function Build(class, defs)
	local P = { class = class, defs = defs }

	local function primary(def) return def.single or def.aoe or def.group end

	function P:Enabled(def)
		local v = BM.db.buffs[def.key]
		if v == nil then return def.default end
		return v
	end

	function P:IsAvailable()
		for _, def in ipairs(defs) do
			if BM:Knows(def.single) or BM:Knows(def.aoe) or BM:Knows(def.group) then return true end
		end
		return false
	end

	function P:Label(def)
		return BM:SpellName(primary(def))
	end

	function P:DefaultTexture()
		for _, def in ipairs(defs) do
			local sd = primary(def)
			if BM:Knows(sd) or BM:Knows(def.group) then return BM:SpellTexture(sd) end
		end
		return BM:SpellTexture(primary(defs[1]))
	end

	function P:SelectManual(def, unitOverride)
		local sd = def.single or def.aoe or def.group
		if not BM:Knows(sd) then
			sd = def.group
			if not BM:Knows(sd) then return nil, "You don't know " .. BM:SpellName(primary(def)) .. "." end
		end
		local unit = def.aoe and "player" or unitOverride or BM:ResolveManualUnit()
		return {
			spell = BM:SpellName(sd), unit = unit, texture = BM:SpellTexture(sd),
			name = UnitName(unit), manual = true, pending = 0, count = 1,
		}
	end

	function P:Select(mod, commit)
		if mod then
			for _, def in ipairs(defs) do
				if def.slot == mod then return self:SelectManual(def) end
			end
		end

		local db = BM.db
		local minLeft = (db.rebuffMinutes or 2) * 60
		local cache = {}
		local function auras(m)
			local a = cache[m.name]
			if not a then a = BM:ReadAuras(m.unit); cache[m.name] = a end
			return a
		end

		local cands, pending, far = {}, 0, 0

		for _, def in ipairs(defs) do
			if self:Enabled(def) then
				if def.aoe and BM:Knows(def.aoe) then
					local spell = BM:SpellName(def.aoe)
					local count = 0
					for _, m in ipairs(BM.roster) do
						if Matches(def, m) and BM:UnitUsable(m.unit) and not BM:HasAny(auras(m), { spell }, minLeft) then
							if m.isMe or CheckInteractDistance(m.unit, 4) then count = count + 1 else far = far + 1 end
						end
					end
					if count > 0 and not IsRecent("aoe|" .. spell) then
						pending = pending + count
						cands[#cands + 1] = {
							unit = "player", name = UnitName("player"), spell = spell, texture = BM:SpellTexture(def.aoe),
							count = count, key = "aoe|" .. spell, aoe = true,
						}
					end
				elseif def.single or def.group then
					local knowsSingle, knowsGroup = BM:Knows(def.single), BM:Knows(def.group)
					if knowsSingle or knowsGroup then
						local sDef = knowsSingle and def.single or def.group
						local sName = BM:SpellName(sDef)
						local names = { BM:SpellName(def.single or def.group) }
						if def.group then names[#names + 1] = BM:SpellName(def.group) end

						local lacking, perGroup = {}, {}
						for _, m in ipairs(BM.roster) do
							if Matches(def, m) and BM:UnitUsable(m.unit) and not BM:HasAny(auras(m), names, minLeft) then
								if BM.API.IsSpellInRange(sName, m.unit) == 1 and not IsRecent(m.name .. "|" .. sName) then
									lacking[#lacking + 1] = m
									perGroup[m.subgroup] = (perGroup[m.subgroup] or 0) + 1
								else
									far = far + 1
								end
							end
						end
						if #lacking > 0 then
							local target = lacking[1]
							local useDef, spell = sDef, sName
							if knowsGroup and (perGroup[target.subgroup] or 0) >= 2 then
								useDef, spell = def.group, BM:SpellName(def.group)
							end
							pending = pending + #lacking
							cands[#cands + 1] = {
								unit = target.unit, name = target.name, class = target.class, spell = spell,
								texture = BM:SpellTexture(useDef), count = #lacking, key = target.name .. "|" .. sName,
								group = (useDef == def.group),
							}
						end
					end
				end
			end
		end

		if #cands == 0 then
			if far > 0 then return nil, "Nobody in range needs a buff.", far end
			return nil, "Everyone is buffed.", 0
		end
		local c = cands[1]
		if commit and not GCDActive(c.spell) then recent[c.key] = GetTime() end
		c.pending = pending
		return c
	end

	local function NamesOf(def)
		local names = {}
		if def.single then names[#names + 1] = BM:SpellName(def.single) end
		if def.aoe then names[#names + 1] = BM:SpellName(def.aoe) end
		if def.group then names[#names + 1] = BM:SpellName(def.group) end
		return names
	end

	local function KnownSpell(def)
		if BM:Knows(def.single) then return def.single end
		if BM:Knows(def.aoe) then return def.aoe end
		if BM:Knows(def.group) then return def.group end
	end

	--- Click on one person's own button.
	function P:SelectUnit(m, mod)
		if mod then
			for _, def in ipairs(defs) do
				if def.slot == mod then return self:SelectManual(def, m.unit) end
			end
		end
		local minLeft = (BM.db.rebuffMinutes or 2) * 60
		local auras = BM:ReadAuras(m.unit)
		for _, def in ipairs(defs) do
			if self:Enabled(def) and Matches(def, m) and KnownSpell(def) and not BM:HasAny(auras, NamesOf(def), minLeft) then
				return self:SelectManual(def, m.unit)
			end
		end
		return nil, m.name .. " has everything."
	end

	--- name -> "need" | "ok" | "far" | "off" | "na"
	function P:UnitStates()
		local out = {}
		local minLeft = (BM.db.rebuffMinutes or 2) * 60
		for _, m in ipairs(BM.roster) do
			if not BM:UnitUsable(m.unit) then
				out[m.name] = "off"
			else
				local auras = BM:ReadAuras(m.unit)
				local any, need, far = false, false, false
				for _, def in ipairs(defs) do
					local sd = KnownSpell(def)
					if sd and self:Enabled(def) and Matches(def, m) then
						any = true
						if not BM:HasAny(auras, NamesOf(def), minLeft) then
							local inRange
							if def.aoe then
								inRange = m.isMe or CheckInteractDistance(m.unit, 4)
							else
								inRange = BM.API.IsSpellInRange(BM:SpellName(sd), m.unit) == 1
							end
							if inRange then need = true else far = true end
						end
					end
				end
				if not any then out[m.name] = "na"
				elseif need then out[m.name] = "need"
				elseif far then out[m.name] = "far"
				else out[m.name] = "ok" end
			end
		end
		return out
	end

	function P:ModLines()
		local out = {}
		local names = { shift = "Shift", ctrl = "Ctrl", alt = "Alt", ctrlshift = "Shift+Ctrl" }
		for _, def in ipairs(defs) do
			if def.slot then
				out[#out + 1] = { names[def.slot] .. " + click", self:Label(def) .. (def.aoe and "" or " (target / mouseover / you)") }
			end
		end
		return out
	end

	function P:PlanLines()
		local out = {}
		for _, def in ipairs(defs) do
			if self:Enabled(def) then
				local text = self:Label(def)
				if def.group then text = text .. " / " .. BM:SpellName(def.group) end
				out[#out + 1] = { "Auto", text }
			end
		end
		return out
	end

	return P
end

BM.providers = BM.providers or {}
for class, defs in pairs(DEFS) do
	BM.providers[class] = Build(class, defs)
end
