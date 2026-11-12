--[[ Buff Me - Compat
     One place that hides the differences between clients:
       * 3.3.5a (Wrath)                 - the original API
       * WoW Forever / Mainline family  - C_* namespaces, Settings API, secret values,
                                          no UnitBuff / GetSpellInfo / GetTalentTabInfo ...
     Everything else in the add-on calls BM.API.* or the helpers below, never the raw
     client functions that differ.  Every lookup is feature-detected (not version
     numbered), so a client patch that moves an API does not break the add-on as
     long as one of the known spellings still exists.
]]

local BM = BuffMe
local API = {}
BM.API = API

local pcall, type, pairs, ipairs, select = pcall, type, pairs, ipairs, select

-- Which family are we on? Detected by API presence, never by build number.
BM.modern = (C_Spell ~= nil and C_Spell.GetSpellInfo ~= nil) or (C_UnitAuras ~= nil)

local issecret = issecretvalue or function() return false end
API.issecret = issecret

-- Spells ----------------------------------------------------------------------
--- name, nil, icon  (same shape as the old GetSpellInfo)
function API.GetSpellInfo(idOrName)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, idOrName)
		if ok and type(info) == "table" then
			return info.name, nil, info.iconID or info.originalIconID
		end
		return nil
	end
	if GetSpellInfo then
		local name, rank, icon = GetSpellInfo(idOrName)
		return name, rank, icon
	end
end

--- start, duration (nil when unknown or hidden by the client)
function API.GetSpellCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
		if ok and type(info) == "table" then
			local s, d = info.startTime, info.duration
			if issecret(s) or issecret(d) then return nil end
			return s, d
		end
		return nil
	end
	if GetSpellCooldown then return GetSpellCooldown(spell) end
end

--- 1 | 0 | nil, like the old IsSpellInRange
function API.IsSpellInRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
		if not ok or issecret(r) then return nil end
		if r == true then return 1 elseif r == false then return 0 end
		return r
	end
	if IsSpellInRange then return IsSpellInRange(spell, unit) end
end

function API.GetItemCount(item)
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, item)
		return (ok and not issecret(n) and n) or 0
	end
	if GetItemCount then return GetItemCount(item) end
	return 0
end

function API.IsAddOnLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
	if IsAddOnLoaded then return IsAddOnLoaded(name) end
	return false
end

-- Spellbook -------------------------------------------------------------------
--- Fills `known` (name -> true) and `knownID` (id -> true) with everything the player can cast.
function API.ScanSpellbook(known, knownID)
	for k in pairs(known) do known[k] = nil end
	for k in pairs(knownID) do knownID[k] = nil end

	-- Modern: C_SpellBook
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
		and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
		local bank = Enum.SpellBookSpellBank.Player
		local ok = pcall(function()
			for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
				local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
				if li then
					local first = li.itemIndexOffset or 0
					for i = first + 1, first + (li.numSpellBookItems or 0) do
						local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
						if item and not issecret(item.name) then
							if item.name then known[item.name] = true end
							if item.spellID then knownID[item.spellID] = true end
							if item.actionID then knownID[item.actionID] = true end
						end
					end
				end
			end
		end)
		if ok then return end
	end

	-- 3.3.5a: GetSpellName
	if GetSpellName then
		local i = 1
		while true do
			local name = GetSpellName(i, BOOKTYPE_SPELL or "spell")
			if not name then break end
			known[name] = true
			i = i + 1
		end
	end
end

--- Direct "do I know this spell id" query when the client offers one.
function API.IsSpellKnownByID(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, r = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and not issecret(r) then return r and true or false end
	end
	if IsPlayerSpell then
		local ok, r = pcall(IsPlayerSpell, id)
		if ok and not issecret(r) then return r and true or false end
	end
	return nil -- unknown: caller falls back to the name scan
end

-- Group -----------------------------------------------------------------------
function API.NumRaid()
	if GetNumRaidMembers then return GetNumRaidMembers() end
	if IsInRaid and IsInRaid() then return GetNumGroupMembers() end
	return 0
end

function API.NumParty()
	if GetNumPartyMembers then return GetNumPartyMembers() end
	if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
		return math.max(0, GetNumGroupMembers() - 1)
	end
	return 0
end

function API.IsLeader(unit)
	if UnitIsGroupLeader then return UnitIsGroupLeader(unit) and true or false end
	if unit == "player" and IsPartyLeader then return IsPartyLeader() and true or false end
	if UnitIsPartyLeader then return UnitIsPartyLeader(unit) and true or false end
	return false
end

--- Strip "-Realm" from a sender / name.
function API.ShortName(name)
	if type(name) ~= "string" then return name end
	return (name:match("^([^%-]+)")) or name
end

-- Addon messages ----------------------------------------------------------------
function API.RegisterPrefix(prefix)
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
	elseif RegisterAddonMessagePrefix then
		pcall(RegisterAddonMessagePrefix, prefix)
	end
end

function API.SendAddon(prefix, msg, channel)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, prefix, msg, channel)
	elseif SendAddonMessage then
		SendAddonMessage(prefix, msg, channel)
	end
end

function API.Channel()
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return "INSTANCE_CHAT"
	end
	if API.NumRaid() > 0 then return "RAID" end
	if API.NumParty() > 0 then return "PARTY" end
	return nil
end

-- Auras -------------------------------------------------------------------------
--- Reads a unit's buffs into { [name] = remainingSeconds | true }.
--  `restricted = true` is set when the client hides aura data (secret values /
--  combat restrictions); callers must then NOT guess who needs a buff.
function API.ReadAuras(unit)
	local t = {}
	local now = GetTime()

	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		if C_Secrets and C_Secrets.ShouldAurasBeSecret then
			local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
			if ok and secret then t.restricted = true; return t end
		end
		local ok = pcall(function()
			for i = 1, 255 do
				local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
				if not a then break end
				local name, expires = a.name, a.expirationTime
				if issecret(name) or issecret(expires) then t.restricted = true; return end
				if name then
					if expires and expires > 0 then t[name] = expires - now else t[name] = true end
				end
			end
		end)
		if not ok then t.restricted = true end
		return t
	end

	if UnitBuff then
		local i = 1
		while true do
			local name, _, _, _, _, _, expires = UnitBuff(unit, i)
			if not name then break end
			if expires and expires > 0 then t[name] = expires - now else t[name] = true end
			i = i + 1
		end
	end
	return t
end

-- Specs ---------------------------------------------------------------------------
--- Returns specIndex (1..n) or 0, plus a role string ("tank"/"healer"/"melee"...) or nil.
--  Uses the old talent-tree reader on 3.3.5a and the specialization API elsewhere.
function API.SelfSpec()
	if GetTalentTabInfo and not (GetSpecialization) then
		local group = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
		local best, bestPts = 0, 0
		for i = 1, 3 do
			local _, _, pts = GetTalentTabInfo(i, false, false, group)
			if pts and pts > bestPts then best, bestPts = i, pts end
		end
		return best, nil
	end

	local getSpec = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
	if getSpec then
		local ok, idx = pcall(getSpec)
		if ok and type(idx) == "number" and not issecret(idx) then
			local role
			local getRole = GetSpecializationRole or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole)
			if getRole then
				local ok2, r = pcall(getRole, idx)
				if ok2 and type(r) == "string" and not issecret(r) then
					role = (r == "TANK" and "tank") or (r == "HEALER" and "healer") or nil
				end
			end
			return idx, role
		end
	end
	return 0, nil
end

--- Can we read other players' talents? (3.3.5a only; elsewhere roles come from the group.)
function API.CanInspectTalents()
	return GetTalentTabInfo ~= nil and GetSpecialization == nil
end

-- Frames --------------------------------------------------------------------------
--- Make a frame accept SetBackdrop on clients where that needs a mixin.
function API.EnableBackdrop(frame)
	if frame.SetBackdrop then return end
	if BackdropTemplateMixin and Mixin then
		Mixin(frame, BackdropTemplateMixin)
		if frame.OnBackdropLoaded then frame:OnBackdropLoaded() end
		if frame.HookScript then
			frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
		end
	end
end

--- Flat-colour texture on both old and new clients.
function API.Solid(tex, r, g, b, a)
	if tex.SetColorTexture then
		tex:SetColorTexture(r, g, b, a or 1)
	else
		tex:SetTexture(r, g, b, a or 1)
	end
end

--- CreateFrame that falls back when a template no longer exists.
function API.CreateWithTemplate(frameType, name, parent, templates)
	for _, tmpl in ipairs(templates) do
		local ok, f = pcall(CreateFrame, frameType, name, parent, tmpl)
		if ok and f then return f, tmpl end
	end
	return CreateFrame(frameType, name, parent)
end

-- Colour picker -------------------------------------------------------------------
function API.PickColor(r, g, b, onChange, onCancel)
	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				onChange(nr, ng, nb)
			end,
			cancelFunc = function() onCancel(r, g, b) end,
		})
		return
	end
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.previousValues = { r, g, b }
	ColorPickerFrame.func = function()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		onChange(nr, ng, nb)
	end
	ColorPickerFrame.cancelFunc = function(prev)
		if prev then onCancel(prev[1], prev[2], prev[3]) end
	end
	ColorPickerFrame:SetColorRGB(r, g, b)
	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()
end

-- Options window ------------------------------------------------------------------
--- Registers a canvas panel. Parent is the parent panel (a frame) or nil.
function API.AddOptionsPanel(p, parentPanel)
	if InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(p)
		return
	end
	if Settings and Settings.RegisterCanvasLayoutCategory then
		if parentPanel and parentPanel.category and Settings.RegisterCanvasLayoutSubcategory then
			p.category = Settings.RegisterCanvasLayoutSubcategory(parentPanel.category, p, p.name)
		else
			p.category = Settings.RegisterCanvasLayoutCategory(p, p.name)
			Settings.RegisterAddOnCategory(p.category)
		end
	end
end

function API.OpenOptions(p)
	if InterfaceOptionsFrame_OpenToCategory then
		-- called twice on purpose: the 3.3.5 client opens the wrong tab on the first call
		InterfaceOptionsFrame_OpenToCategory(p)
		InterfaceOptionsFrame_OpenToCategory(p)
		return true
	end
	if Settings and Settings.OpenToCategory and p and p.category then
		local id = p.category.GetID and p.category:GetID() or p.category.ID or p.category
		local ok = pcall(Settings.OpenToCategory, id)
		return ok
	end
	return false
end
