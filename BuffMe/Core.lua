--[[ Buff Me - Core
     Event dispatch, saved variables, timers, slash commands.
     Runs on 3.3.5a and on the WoW Forever / Mainline-family client (see Compat.lua).
]]

BuffMe = BuffMe or {}
local BM = BuffMe

BM.name = "BuffMe"
BM.version = "1.3.2"
BM.PREFIX = "BuffMe"

local pairs, ipairs, type, tinsert = pairs, ipairs, type, table.insert

-- Key binding labels ---------------------------------------------------------
BINDING_HEADER_BUFFME = "Buff Me"
BINDING_NAME_BUFFME_TOGGLELOCK = "Lock / unlock the Buff Me button"
BINDING_NAME_BUFFME_TOGGLEGRID = "Show / hide the assignment window"
_G["BINDING_NAME_CLICK BuffMeButton:LeftButton"] = "Cast next buff (Shift/Ctrl/Alt = specific buff)"

-- Defaults ------------------------------------------------------------------
BM.defaults = {
	locked = false,
	scale = 1,
	iconSize = 44,
	alpha = 1,
	theme = "auto",                 -- auto | dark | retail | classic | light | class | elvui
	accent = { 0.20, 0.70, 0.95 },
	minimap = { hide = false, angle = 215 },
	showButton = "always",          -- always | group | needed
	showCount = true,
	placement = "below",           -- player grid relative to the main button: below | above | right | left
	align = "start",               -- start | center | finish (along that edge)
	showPlayers = true,             -- a button for every group member under the main button
	playerSize = 26,
	showTargetName = true,
	tooltips = true,
	wheelCast = true,
	castMode = "spell",             -- spell | macro  (macro is a fallback, see /bm cast)
	myRole = "auto",                -- auto | tank | healer | melee | ranged | caster
	greaterMode = "auto",           -- auto | greater | normal
	greaterMinGroup = 4,            -- groups this size or bigger use Greater Blessings
	rebuffMinutes = 2,              -- re-buff when less than this is left (own casts)
	singlePaladinKings = true,      -- lone paladin: Kings on everyone
	mods = { shift = "kings", ctrl = "might", alt = "wisdom", ctrlshift = "sanctuary" },
	buffs = {},                     -- per-buff enable overrides for non-paladin classes
}

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-- Output --------------------------------------------------------------------
function BM:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33b8f2[Buff Me]|r " .. tostring(msg))
end

function BM:Notice(msg)
	if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 0.4, 0.8, 1.0, 1.0) end
end

-- Events --------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "BuffMeEventFrame")
local handlers = {}

function BM:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- newer clients throw on events that no longer exist; just skip those
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	tinsert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do list[i](event, ...) end
	end
end)

-- Timers (debounced by key) -------------------------------------------------
local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function()
	if not next(timers) then return end
	local now = GetTime()
	local due
	for key, t in pairs(timers) do
		if now >= t.at then
			due = due or {}
			due[#due + 1] = key
		end
	end
	if due then
		for i = 1, #due do
			local t = timers[due[i]]
			timers[due[i]] = nil
			if t then t.fn() end
		end
	end
end)

--- Run fn after delay seconds. Calling again with the same key restarts the timer.
function BM:Schedule(key, delay, fn)
	timers[key] = { at = GetTime() + delay, fn = fn }
end

--- Like Schedule, but does nothing when a timer with this key is already waiting.
function BM:ScheduleOnce(key, delay, fn)
	if not timers[key] then
		timers[key] = { at = GetTime() + delay, fn = fn }
	end
end

function BM:Cancel(key)
	timers[key] = nil
end

-- Combat queue --------------------------------------------------------------
local combatQueue = {}
function BM:AfterCombat(key, fn)
	if InCombatLockdown() then
		combatQueue[key] = fn
	else
		fn()
	end
end

BM:On("PLAYER_REGEN_ENABLED", function()
	local q = combatQueue
	combatQueue = {}
	for _, fn in pairs(q) do fn() end
end)

-- Module init list (run on PLAYER_LOGIN, in registration order) -------------
local inits = {}
function BM:OnInit(fn) tinsert(inits, fn) end

BM:On("ADDON_LOADED", function(_, addon)
	if addon ~= BM.name then return end
	BuffMeDB = BuffMeDB or {}
	CopyDefaults(BM.defaults, BuffMeDB)
	BM.db = BuffMeDB
end)

BM:On("PLAYER_LOGIN", function()
	BM.db = BuffMeDB or BM.db
	BM.playerName = UnitName("player")
	BM.playerClass = select(2, UnitClass("player"))
	for i = 1, #inits do
		local ok, err = pcall(inits[i])
		if not ok then BM:Print("|cffff4444init error:|r " .. tostring(err)) end
	end
end)

-- Slash commands ------------------------------------------------------------
SLASH_BUFFME1 = "/buffme"
SLASH_BUFFME2 = "/bm"
SlashCmdList["BUFFME"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "lock" then
		BM:SetLocked(true)
	elseif msg == "unlock" then
		BM:SetLocked(false)
	elseif msg == "grid" or msg == "assign" then
		BM:ToggleGrid()
	elseif msg == "reset" then
		BM:ResetPosition()
	elseif msg:find("^sim") then
		local n = tonumber(msg:match("^sim%s+(%d+)"))
		if n then BM:SetSimulation(true, n) else BM:SetSimulation(not BM.sim.on) end
		BM:Print(BM.sim.on and ("Group simulation on (" .. BM.sim.size .. " players).") or "Group simulation off.")
	elseif msg == "plan" then
		BM:DumpPlan()
	elseif msg == "debug" or msg == "debug on" or msg == "debug off" then
		if msg == "debug on" then BM.debugOn = true elseif msg == "debug off" then BM.debugOn = false end
		BM:DebugReport()
	elseif msg == "spells" then
		BM:DumpSpells()
	elseif msg:find("^role") then
		local r = msg:match("^role%s+(%a+)")
		local ok = { auto = 1, tank = 1, healer = 1, melee = 1, ranged = 1, caster = 1 }
		if r and ok[r] then
			BM.db.myRole = r
			BM:DetectSelfSpec(); BM:SendHello(); BM:RequestRefresh(0.05)
			BM:Print("Your role is now: " .. r .. (r == "auto" and " (detected automatically)" or " (set by hand)") .. ".")
		else
			BM:Print("Role: " .. tostring(BM.myRole) .. " (setting: " .. tostring(BM.db.myRole) .. "). Use /bm role auto | tank | healer | melee | ranged | caster")
		end
	elseif msg:find("^cast") then
		local m = msg:match("^cast%s+(%a+)")
		if m == "spell" or m == "macro" then
			BM.db.castMode = m
			BM:Print("Cast method: " .. m .. ".")
		else
			BM:Print("Cast method: " .. tostring(BM.db.castMode) .. ". Use /bm cast spell | macro")
		end
	elseif msg == "help" then
		BM:Print("/bm  - open settings   |  /bm lock | unlock  |  /bm grid  - assignments  |  /bm sim [size]  - group simulation  |  /bm reset")
		BM:Print("/bm spells  - spells and ranks found   |  /bm role [x]  |  /bm cast spell | macro  |  /bm debug [on | off]  - report for bug reports")
	else
		BM:OpenOptions()
	end
end
