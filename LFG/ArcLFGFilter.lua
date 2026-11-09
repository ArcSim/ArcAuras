local ADDON, NS = ...

-- Arc LFG Filter - an "Advanced Filter" button beside the refresh button of WoW
-- Forever's Looking For Group window (Blizzard_GroupFinder_VanillaStyle,
-- browse tab). Its menu holds three independent filters:
--   Show        - players and groups / players only / groups only
--   Players     - Tank / Healer / DPS: solo players who signed up for a
--                 ticked role (the role icons Blizzard shows), plus a Class
--                 submenu (every class the game has, with counts) and a typed
--                 Minimum level; role, class and level combine, so DPS + Mage
--                 = DPS mages
--   Groups      - "has a spot for me": groups with an open slot for a role
--                 YOU are queued as (C_LFGListRoles.GetRoles, the same source
--                 Blizzard uses to rank groups) via the *_REMAINING counts;
--                 "Open spot for": the same test against roles you pick, ANY
--                 ticked role is enough; "Already has": the group must hold
--                 EVERY ticked role; plus "Hide groups with": drop any group
--                 that has a member of a ticked class (every member is read)
-- Nothing set = nothing changes (default OFF). Your own listing always stays.
--
-- HOW (v6, 2026-09-21): BLIZZARD'S LIST IS NEVER TOUCHED. While a filter is
-- on, the addon draws its OWN list over Blizzard's (same background art, row
-- layout, fonts and role display) holding only the matching listings, in
-- Blizzard's order, with its own selection, tooltip, right-click menu and
-- Send Message / Group Invite buttons laid over Blizzard's. Filter off,
-- searching, no results, or data it cannot read: its list hides and
-- Blizzard's is simply there.
-- WHY: v2-v5 filtered by editing Blizzard's results table (a post-hook on
-- LFGBrowseUtil_SortSearchResults) and redrew with
-- LFGBrowseFrame:UpdateResultList(). Any addon write or call there leaves
-- Blizzard's list - its ScrollBox, data provider and rows - stored as
-- addon-touched for the rest of the session. In a dungeon or in combat
-- Forever makes listing data secret to touched code, so every background
-- search then errored inside Blizzard's own row code ("attempt to compare
-- field 'numMembers' (a secret number value, while execution tainted by
-- 'ArcLFGFilter')", Blizzard_LFGVanilla_Browse.lua:366). Everything this
-- addon does to Blizzard's LFG frames now: two read-only hooksecurefunc
-- post-hooks (UpdateResults, C_PartyInfo.InviteUnit), reading fields, and
-- anchoring its own frames to theirs.
--
-- INVITE WHISPER (default OFF): inviting a listed player from this window
-- also whispers them your message, "Inviting you to run {dungeon}" unless you
-- write your own. A hooksecurefunc post-hook on C_PartyInfo.InviteUnit, which
-- both of Blizzard's invite paths and this addon's own Group Invite call, so
-- the invite itself always runs first and untouched. It only answers an
-- invite while the browse window is open and the name is a solo player in the
-- results, never repeats a player within a minute, and stands aside in chat
-- lockdown. The menu holds the switch; the message lives in a small settings
-- window (/arclfg) built from the Arc theme (ALF_Theme.lua, a verbatim copy
-- of ArcDisplay's AD_Theme.lua).
--
-- DEBUG: /arclfg debug opens a copyable log panel (probe-GUI rule) and
-- /arclfg snap adds a snapshot of every listing. It records setup, every
-- Blizzard list rebuild, every rebuild of the addon's own list, and every
-- invite whisper. Every logged value goes through S(), so secret values print
-- as <secret> instead of throwing.
--
-- SAVED: only the invite whisper settings (ArcLFGFilterDB, account-wide).
-- The filter itself still resets every session on purpose. Forever's
-- SavedVariables loading bug can hand the addon an empty table for a whole
-- session; the whisper is then off with the default message until the saved
-- file loads again, and a session like that saves the defaults over it. The
-- debug log lives only in the panel, never in a saved file.

local issecret = issecretvalue or function() return false end

local ROLES = {
	{ key = "TANK",    solo = "tank",   label = "Tank",   letter = "T" },
	{ key = "HEALER",  solo = "healer", label = "Healer", letter = "H" },
	{ key = "DAMAGER", solo = "dps",    label = "DPS",    letter = "D" },
}

-- short = the panel's button, which has room for one word; label is the
-- wording the menu used and the button's tooltip still carries
local SHOW_MODES = {
	{ key = "both",    label = "Players and groups", short = "All" },
	{ key = "players", label = "Players only",       short = "Players" },
	{ key = "groups",  label = "Groups only",        short = "Groups" },
}

local FILTER_ATLAS   = "ui-questtrackerbutton-filter"
local FALLBACK_ATLAS = "groupfinder-icon-role-large-tank"
local STATUS_WIDEST  = "Paused: roles hidden" -- sizes the menu's status line
local MAX_LOG_LINES  = 800

local DEFAULT_MESSAGE  = "Inviting you to run {dungeon} as {role}"
local FALLBACK_DUNGEON = "a dungeon" -- {dungeon} when the listing names none
local SAMPLE_DUNGEON   = "Deadmines" -- settings preview when nothing is picked
local SAMPLE_NAME      = "Rowan"     -- settings preview for {name}
local MAX_TEMPLATE     = 200         -- leaves room for the tokens in a whisper
local MAX_WHISPER      = 255         -- chat's limit, in bytes
local WHISPER_REPEAT   = 60          -- seconds before the same player is whispered again

-- The addon's own list mirrors Blizzard's row template (Mainline
-- Blizzard_LFGVanilla_Browse.xml): 48px rows, 36px category headers, names
-- capped at 228px, and Blizzard's role display template on the right.
local ROW_H, HEADER_H, NAME_MAX = 48, 36, 228
local NO_MATCH_NOTE = "No listings match your filter."
local DISPLAY_TEMPLATE = "LFGVanillaListGroupDataDisplayTemplate"
local DELISTED_COLOR   = { r = 0.3, g = 0.3, b = 0.3 }

local active = {}                   -- [role key] = true while that role is ticked
local classActive = {}              -- [classFile] = true while that class is ticked
local groupExclude = {}             -- [classFile] = true: hide groups with that class in them
local groupNeeds = {}               -- [role key] = true: group must have an open spot for it
local groupHas = {}                 -- [role key] = true: group must already have that role
-- Per-class roles, saving the filter and suggesting an invite live on one
-- table: the file is at Lua's 200-local ceiling.
local F = { classRoles = {} }       -- classRoles[classFile] = { [role key] = true }
local minLevel                      -- nil, or the lowest level a solo player may be
local showMode = "both"             -- "both", "players" or "groups"
local openSpotOnly = false          -- groups: only those with a slot for my role
local shownCount, totalCount = 0, 0 -- result of the last rebuild of our list
local pausedReason                  -- nil, "lockdown" or "hidden"
local lockSeen = "no"               -- last lockdown reading: "no", "yes" or "secret"
local db                            -- ArcLFGFilterDB once this addon has loaded
local lastWhisper = {}              -- [name] = GetTime() of the last invite whisper
local panel            -- the debug log window
local frames = {}      -- button, settings, page, whisper: one table, the file is at Lua's 200-local cap
local view                          -- the addon's own list over Blizzard's
local viewRows, viewHeaders = {}, {} -- pooled row and header buttons
local selectedID                    -- the listing selected in our list
local collapsed = {}                -- [category] = true while its header is shut
local rebuildQueued = false
local logLines, logBatching = {}, false

-- Extension points for a companion addon, which reads this addon's table via
-- C_AddOns.GetAddOnLocalTable (the toc opts in with AllowAddOnTableAccess):
-- functions(root) run while the menu is built, and functions(tooltip) that
-- add lines to the button tooltip. Empty for everyone else. The read-only
-- API they use is set at the bottom of this file.
NS.menuExtras = NS.menuExtras or {}
NS.tooltipExtras = NS.tooltipExtras or {}

-------------------------------------------------------------------------------
-- Debug log
-------------------------------------------------------------------------------

-- Every logged value goes through here: a secret must never reach tostring.
local function S(v)
	if issecret(v) then return "<secret>" end
	return tostring(v)
end

-- A value, or nil when it is secret.
local function Plain(v)
	if issecret(v) then return nil end
	return v
end

local function RefreshPanel()
	if not (panel and panel:IsShown()) then return end
	panel.Edit:SetText(table.concat(logLines, "\n"))
	C_Timer.After(0, function()
		panel.Scroll:SetVerticalScroll(panel.Scroll:GetVerticalScrollRange())
	end)
end

local function Log(text)
	logLines[#logLines + 1] = date("%H:%M:%S") .. "  " .. text
	if #logLines > MAX_LOG_LINES then table.remove(logLines, 1) end
	if not logBatching then RefreshPanel() end
end

-------------------------------------------------------------------------------
-- Filter state helpers
-------------------------------------------------------------------------------

local function AnyRoleTicked()
	return active.TANK or active.HEALER or active.DAMAGER
end

local function AnyClassTicked()
	return next(classActive) ~= nil
end

local function AnyGroupExclusion()
	return next(groupExclude) ~= nil
end

-- Roles picked for one class ("for Paladin I only want healers and tanks").
-- A class with none set takes the roles ticked at the top of the menu.
function F.ClassRoles(classFile)
	local set = F.classRoles[classFile]
	return (set and next(set)) and set or nil
end

function F.IsClassRole(data)
	local classFile, key = data:match("^(%u+):(%u+)$")
	local set = classFile and F.classRoles[classFile]
	return (set and set[key]) == true
end

function F.ToggleClassRole(data)
	local classFile, key = data:match("^(%u+):(%u+)$")
	if not classFile then return end
	local set = F.classRoles[classFile] or {}
	set[key] = not set[key] or nil
	F.classRoles[classFile] = next(set) and set or nil
	-- picking a role for a class is also picking the class
	if F.classRoles[classFile] then classActive[classFile] = true end
	Log("menu: " .. classFile .. " roles -> " .. (F.RoleList(classFile) or "any"))
	if F.Changed then F.Changed() end
end

function F.ClearClassRoles(classFile)
	F.classRoles[classFile] = nil
	Log("menu: " .. classFile .. " roles -> any")
	if F.Changed then F.Changed() end
end

-- "Tank, Healer" for a class, or nil when it takes any role.
function F.RoleList(classFile)
	local set = F.ClassRoles(classFile)
	if not set then return nil end
	local names = {}
	for _, role in ipairs(ROLES) do
		if set[role.key] then names[#names + 1] = role.label end
	end
	return table.concat(names, ", ")
end

local function AnyGroupNeeds()
	return next(groupNeeds) ~= nil
end

local function AnyGroupHas()
	return next(groupHas) ~= nil
end

local function FilterActive()
	return showMode ~= "both" or openSpotOnly or AnyRoleTicked() or AnyClassTicked() or AnyGroupExclusion()
		or minLevel ~= nil or AnyGroupNeeds() or AnyGroupHas() or F.nearby
		or next(F.mustClass) ~= nil
end

function F.IsNearbyOn()
	return F.nearby and true or false
end

-- A class in a group answers three ways, on one row: any, the group must
-- hold one, or hide every group that does.
F.mustClass = {}

function F.ClassState(classFile)
	if F.mustClass[classFile] then return "must" end
	if groupExclude[classFile] then return "hide" end
	return "any"
end

function F.CycleClass(classFile)
	local state = F.ClassState(classFile)
	F.mustClass[classFile] = (state == "any") and true or nil
	groupExclude[classFile] = (state == "must") and true or nil
	Log("menu: groups " .. classFile .. " -> " .. F.ClassState(classFile))
	if F.Changed then F.Changed() end
end

function F.AnyClassState()
	return (next(F.mustClass) ~= nil or AnyGroupExclusion()) and true or false
end

function F.ClearClassStates()
	wipe(F.mustClass)
	wipe(groupExclude)
	Log("menu: groups any class")
	if F.Changed then F.Changed() end
end

-- A rule about which PLAYERS match (role, class or level), as opposed to the
-- show mode or group rules.
local function HasPlayerRules()
	return (AnyRoleTicked() or AnyClassTicked() or minLevel ~= nil) and true or false
end

-- The roles in a set (active, groupNeeds, groupHas), in Tank/Healer/DPS order.
local function RoleNames(set)
	local names = {}
	for _, role in ipairs(ROLES) do
		if set[role.key] then names[#names + 1] = role.label end
	end
	return table.concat(names, ", ")
end

local function ActiveNames()
	return RoleNames(active)
end

-- Blizzard's class order (CLASS_SORT_ORDER) where it has the class, else by name.
local function SortClasses(list)
	local rank = {}
	if CLASS_SORT_ORDER then
		for i, classFile in ipairs(CLASS_SORT_ORDER) do rank[classFile] = i end
	end
	table.sort(list, function(a, b)
		local ra, rb = rank[a] or 99, rank[b] or 99
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	return list
end

local function ClassLabel(classFile)
	local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
	return name or (classFile:sub(1, 1) .. classFile:sub(2):lower())
end

-- The classes in a set (classActive or groupExclude), in class order, joined.
-- withRoles names the roles a class is limited to: "Warlock (Healer, DPS)".
local function ClassNames(set, withRoles)
	local list = {}
	for classFile in pairs(set) do list[#list + 1] = classFile end
	SortClasses(list)
	for i, classFile in ipairs(list) do
		local name = ClassLabel(classFile)
		local roles = withRoles and F.RoleList(classFile)
		list[i] = roles and (name .. " (" .. roles .. ")") or name
	end
	return table.concat(list, ", ")
end

-- The roles you are queued / listed as: { tank, healer, dps }, or nil when
-- unavailable or secret.
local function MyRoles()
	local roles = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
	if roles == nil or issecret(roles) then return nil end
	return roles
end

local function MyRolesText()
	local roles = MyRoles()
	if not roles then return "unknown" end
	local names = {}
	for _, role in ipairs(ROLES) do
		local on = roles[role.solo]
		if not issecret(on) and on then names[#names + 1] = role.label end
	end
	if #names == 0 then return "no role set" end
	return table.concat(names, "/")
end

-- The roles you are signed up as are the game's own, not ours: the same call
-- the window's Listing tab makes, so your listing follows what you tick here.
function F.IsMine(key)
	local roles = MyRoles()
	if not roles then return false end
	for _, role in ipairs(ROLES) do
		if role.key == key then
			local on = roles[role.solo]
			return (not issecret(on)) and on == true
		end
	end
	return false
end

function F.ToggleMine(key)
	local roles = MyRoles()
	if not roles or not (C_LFGListRoles and C_LFGListRoles.SetRoles) then return end
	local wanted = {}
	for _, role in ipairs(ROLES) do
		local on = roles[role.solo]
		wanted[role.solo] = (not issecret(on)) and on == true or false
		if role.key == key then wanted[role.solo] = not wanted[role.solo] end
	end
	local ok = C_LFGListRoles.SetRoles(wanted, false)
	Log("menu: my roles -> " .. (MyRolesText() or "?") .. " (" .. S(ok) .. ")")
	if F.Changed then F.Changed() end
end

local function FilterSummary()
	local parts = {}
	if showMode == "players" then
		parts[#parts + 1] = "players only"
	elseif showMode == "groups" then
		parts[#parts + 1] = "groups only"
	end
	if showMode ~= "groups" then
		if AnyRoleTicked() then parts[#parts + 1] = "players: " .. ActiveNames() end
		if AnyClassTicked() then parts[#parts + 1] = "class: " .. ClassNames(classActive, true) end
		if minLevel then parts[#parts + 1] = "level " .. minLevel .. "+" end
	end
	if F.nearby then parts[#parts + 1] = "near me (" .. (F.MyZone() or "?") .. ")" end
	if showMode ~= "players" then
		if openSpotOnly then parts[#parts + 1] = "groups: spot for " .. MyRolesText() end
		if AnyGroupNeeds() then parts[#parts + 1] = "groups needing: " .. RoleNames(groupNeeds) end
		if AnyGroupHas() then parts[#parts + 1] = "groups with: " .. RoleNames(groupHas) end
		if AnyGroupExclusion() then parts[#parts + 1] = "groups without: " .. ClassNames(groupExclude) end
		if next(F.mustClass) then parts[#parts + 1] = "groups with: " .. ClassNames(F.mustClass) end
	end
	if #parts == 0 then return "none" end
	return table.concat(parts, "; ")
end

-- Never boolean-test a secret: an unreadable answer is reported as "secret".
local function LockState()
	if not (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) then return "no" end
	local isRestricted = C_ChatInfo.InChatMessagingLockdown()
	if issecret(isRestricted) then return "secret" end
	return isRestricted and "yes" or "no"
end

-- true = keep, false = drop, nil = unreadable (our list then steps aside).
local function Verdict(resultID)
	local info = C_LFGList.GetSearchResultInfo(resultID)
	if not info then return true end
	if issecret(info) then return nil end
	local hasSelf, numMembers = info.hasSelf, info.numMembers
	if issecret(hasSelf) or issecret(numMembers) then return nil end
	if hasSelf then return true end

	if numMembers == 1 then
		if showMode == "groups" then return false end
		local wantRoles, wantClasses = AnyRoleTicked(), AnyClassTicked()
		if not (wantRoles or wantClasses or minLevel or F.nearby) then return true end
		local member = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
		if not member then return false end
		if issecret(member) then return nil end
		if F.nearby and not F.IsNear(Plain(member.areaName), info.activityIDs) then return false end
		if minLevel then
			local level = member.level
			if issecret(level) then return nil end
			if not level or level < minLevel then return false end
		end
		local classFile
		if wantClasses then
			classFile = member.classFilename
			if issecret(classFile) then return nil end
			if not (classFile and classActive[classFile]) then return false end
		end
		-- the roles this player must have: the ones picked for their class
		-- when it has its own list, else the roles ticked at the top
		local roleSet = (classFile and F.ClassRoles(classFile)) or (wantRoles and active or nil)
		if not roleSet then return true end
		local roles = member.lfgRoles
		if not roles then return false end
		if issecret(roles) then return nil end
		for _, role in ipairs(ROLES) do
			if roleSet[role.key] then
				local can = roles[role.solo]
				if issecret(can) then return nil end
				if can then return true end
			end
		end
		return false
	end

	if showMode == "players" then return false end
	-- The classes rule: a hidden class drops the group, a must-have class the
	-- group does not hold drops it too. A member the game gives no info for
	-- simply cannot count against it.
	if AnyGroupExclusion() or next(F.mustClass) then
		local present = {}
		for m = 1, numMembers do
			local member = C_LFGList.GetSearchResultPlayerInfo(resultID, m)
			if member then
				if issecret(member) then return nil end
				local classFile = member.classFilename
				if issecret(classFile) then return nil end
				if classFile then
					if groupExclude[classFile] then return false end
					present[classFile] = true
				end
			end
		end
		for classFile in pairs(F.mustClass) do
			if not present[classFile] then return false end
		end
	end
	-- a group is where its leader is
	if F.nearby then
		local leader = C_LFGList.GetSearchResultLeaderInfo(resultID)
		local area = (leader and not issecret(leader)) and Plain(leader.areaName) or nil
		if not F.IsNear(area, info.activityIDs) then return false end
	end
	if not (openSpotOnly or AnyGroupNeeds() or AnyGroupHas()) then return true end
	-- The role counts Blizzard ranks groups with: TANK/HEALER/DAMAGER = who is
	-- in the group, <ROLE>_REMAINING = the open slots left. A missing count
	-- cannot judge, so it keeps the group.
	local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
	if not counts then return true end
	if issecret(counts) then return nil end

	-- "Already has": EVERY ticked role must be in the group already
	if AnyGroupHas() then
		for _, role in ipairs(ROLES) do
			if groupHas[role.key] then
				local have = counts[role.key]
				if issecret(have) then return nil end
				if have ~= nil and have <= 0 then return false end
			end
		end
	end

	-- "Open spot for": an open slot for ANY ticked role is enough
	if AnyGroupNeeds() then
		local found = false
		for _, role in ipairs(ROLES) do
			if groupNeeds[role.key] then
				local open = counts[role.key .. "_REMAINING"]
				if issecret(open) then return nil end
				if open == nil or open > 0 then found = true end
			end
		end
		if not found then return false end
	end

	-- "Has a spot for me": the same test against the roles YOU are queued as
	if openSpotOnly then
		local mine = MyRoles()
		if not mine then return nil end
		local found = false
		for _, role in ipairs(ROLES) do
			local wanted = mine[role.solo]
			if issecret(wanted) then return nil end
			if wanted then
				local open = counts[role.key .. "_REMAINING"]
				if issecret(open) then return nil end
				if open == nil or open > 0 then found = true end
			end
		end
		if not found then return false end
	end
	return true
end

-------------------------------------------------------------------------------
-- Invite whisper (the only saved setting)
-------------------------------------------------------------------------------

local function WhisperOn()
	return db ~= nil and db.inviteWhisper == true
end

local function SetWhisperOn(on)
	if not db then return end
	db.inviteWhisper = on and true or nil
	Log("settings: invite whisper -> " .. (on and "ON" or "off"))
end

-- The message exactly as saved; "" = not set, so the settings field shows
-- the default as a hint instead of pre-filling it.
local function TypedMessage()
	local text = db and db.inviteMessage
	if type(text) == "string" then return text end
	return ""
end

local function SetTypedMessage(text)
	if not db then return end
	text = (text or ""):match("^%s*(.-)%s*$")
	if text == DEFAULT_MESSAGE then text = "" end
	db.inviteMessage = (text ~= "") and text or nil
end

local function MessageTemplate()
	local text = TypedMessage()
	if text == "" then return DEFAULT_MESSAGE end
	return text
end

-- Quick messages: ready-made lines for the Send Message box (Arc, 2026-09-28:
-- "premade messages that I can edit, default should say like Level X Class
-- Here"). One table, not a pile of file locals - this file sits near Lua's
-- 200-local ceiling. Slot 1 falls back to the default; the others are empty
-- until you write one.
local QM = {
	SLOTS = 3,
	DEFAULT = "Level {level} {class} here, can I join?",
}
QM.DEFAULTS = {
	QM.DEFAULT,
	"Level {level} {class} {role} here, can I join?",
	"Invite me when you have room",
}

function QM.Text(i)
	local saved = db and db.quickMessages and db.quickMessages[i]
	if type(saved) == "string" and saved ~= "" then return saved end
	return QM.DEFAULTS[i]
end

-- Which one fills the Send Message box when it opens.
function QM.First()
	local i = db and db.quickFirst
	if type(i) == "number" and i >= 1 and i <= QM.SLOTS then return i end
	return 1
end

function QM.SetFirst(i)
	if not db then return end
	db.quickFirst = (i ~= 1) and i or nil
	Log("settings: quick message " .. i .. " goes in the box")
end

-- Your own roles, for {role} in a quick message.
function QM.MyRoles()
	return MyRolesText()
end

function QM.Set(i, text)
	if not db then return end
	text = (text or ""):match("^%s*(.-)%s*$")
	if text == QM.DEFAULTS[i] then text = "" end
	db.quickMessages = db.quickMessages or {}
	db.quickMessages[i] = (text ~= "") and text or nil
	if not next(db.quickMessages) then db.quickMessages = nil end
end

-- Runs once this addon's saved file has had its chance to load.
-- The filter is remembered across reloads and logins (Arc, 2026-10-11: "I
-- want the filter to remember what filter I had before"). Saved account-wide
-- beside the invite settings; anything unreadable in the file is ignored.
local function CopySet(from, into)
	wipe(into)
	if type(from) ~= "table" then return into end
	for key, value in pairs(from) do
		if type(key) == "string" and value == true then into[key] = true end
	end
	return into
end

function F.Save()
	if not db then return end
	local roles = {}
	for classFile, set in pairs(F.classRoles) do
		if next(set) then roles[classFile] = CopySet(set, {}) end
	end
	db.filter = {
		roles = CopySet(active, {}),
		classes = CopySet(classActive, {}),
		hide = CopySet(groupExclude, {}),
		must = CopySet(F.mustClass, {}),
		needs = CopySet(groupNeeds, {}),
		has = CopySet(groupHas, {}),
		classRoles = next(roles) and roles or nil,
		level = minLevel,
		show = (showMode ~= "both") and showMode or nil,
		spot = openSpotOnly or nil,
		near = F.nearby or nil,
	}
end

function F.Restore()
	local saved = db and db.filter
	if type(saved) ~= "table" then return end
	CopySet(saved.roles, active)
	CopySet(saved.classes, classActive)
	CopySet(saved.hide, groupExclude)
	CopySet(saved.must, F.mustClass)
	CopySet(saved.needs, groupNeeds)
	CopySet(saved.has, groupHas)
	wipe(F.classRoles)
	if type(saved.classRoles) == "table" then
		for classFile, set in pairs(saved.classRoles) do
			if type(classFile) == "string" then
				local copy = CopySet(set, {})
				if next(copy) then F.classRoles[classFile] = copy end
			end
		end
	end
	local level = tonumber(saved.level)
	minLevel = (level and level > 1) and math.floor(level) or nil
	showMode = (saved.show == "players" or saved.show == "groups") and saved.show or "both"
	openSpotOnly = saved.spot == true
	F.nearby = saved.near == true
end

local function LoadSettings()
	local found = type(ArcLFGFilterDB) == "table"
	if not found then ArcLFGFilterDB = {} end
	db = ArcLFGFilterDB
	Log(string.format("settings: %s - invite whisper %s, message %s",
		found and "loaded from the saved file" or "nothing saved yet, defaults",
		WhisperOn() and "ON" or "off", (TypedMessage() ~= "") and "custom" or "default"))
	F.Restore()
end

-- On Forever other players' names come in two parts ("First Last"); {name}
-- is the first.
local function FirstName(name)
	return name:match("^[^%s%-]+") or name
end

-- Chat refuses "|" (it starts an escape code) and line breaks, and takes at
-- most 255 bytes: cut there without splitting a letter.
local function ChatSafe(text)
	text = text:gsub("|", ""):gsub("[\r\n]", " ")
	if #text > MAX_WHISPER then
		local cut = MAX_WHISPER
		local nextByte = text:byte(cut + 1)
		while cut > 0 and nextByte and nextByte >= 0x80 and nextByte < 0xC0 do
			cut = cut - 1
			nextByte = text:byte(cut + 1)
		end
		text = text:sub(1, cut)
	end
	return text
end

-- Fills {dungeon} and {name} (any case; anything else in braces stays as
-- typed), then makes the result chat-safe.
-- Your own level and class, the two tokens the ready-made lines add.
function QM.MyLevel()
	local level = UnitLevel and UnitLevel("player")
	if issecret(level) or type(level) ~= "number" or level <= 0 then return nil end
	return level
end

function QM.MyClass()
	local name = UnitClass and UnitClass("player")
	if issecret(name) or type(name) ~= "string" or name == "" then return nil end
	return name
end

-- {role} is the role in hand: yours in a quick message, the one you are
-- inviting someone AS in an invite whisper. Unknown, it drops out quietly.
local function BuildMessage(template, dungeon, name, role)
	if not role or role == "" then
		local head, tail = template:match("^(.-)%s*{[rR][oO][lL][eE]}(.*)$")
		if head then
			head = head:gsub("%s+%a%a?%a?$", ""):gsub("%s+%a%a?%a?$", "")
			template = head .. tail
		end
	end
	local text = template:gsub("{(%a+)}", function(key)
		key = key:lower()
		if key == "dungeon" then return dungeon end
		if key == "name" then return name end
		if key == "level" then local l = QM.MyLevel() return l and tostring(l) or nil end
		if key == "class" then return QM.MyClass() end
		if key == "role" then return role or "" end
	end)
	text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+([,.!?])", "%1")
	return ChatSafe(text)
end

-- Blizzard's own naming rule (LFGUtil_GetActivityInfoName): the short name
-- when there is one, else the full name.
local function ActivityName(activityID)
	if issecret(activityID) or activityID == nil then return nil end
	local info = C_LFGList.GetActivityInfoTable(activityID)
	if not info or issecret(info) then return nil end
	local short, full = info.shortName, info.fullName
	if issecret(short) or issecret(full) then return nil end
	if short and short ~= "" then return short end
	if full and full ~= "" then return full end
	return nil
end

-- A readable list of activity IDs, or nil.
local function IDList(list)
	if issecret(list) or type(list) ~= "table" then return nil end
	return list
end

local function ListHas(list, value)
	for _, v in ipairs(list) do
		if not issecret(v) and v == value then return true end
	end
	return false
end

local function FirstActivityName(list)
	list = IDList(list)
	if not list then return nil end
	for _, id in ipairs(list) do
		local name = ActivityName(id)
		if name then return name end
	end
	return nil
end

local function MyActivityIDs()
	local mine = C_LFGList.GetActiveEntryInfo()
	if not mine or issecret(mine) then return nil end
	return IDList(mine.activityIDs)
end

local function PickedActivityIDs()
	local dropdown = LFGBrowseFrame and LFGBrowseFrame.ActivityDropdown
	if not dropdown then return nil end
	return IDList(dropdown.selectedValues)
end

-- First of the listing's activities that is also in `prefer`, named.
local function SharedName(activityIDs, prefer)
	if not prefer then return nil end
	for _, id in ipairs(activityIDs) do
		if not issecret(id) and ListHas(prefer, id) then
			local name = ActivityName(id)
			if name then return name end
		end
	end
	return nil
end

-- The dungeon an invite is for: one the listing shares with your own
-- listing, else one picked in the browse window's activity filter, else the
-- listing's first - how Blizzard names the row, plus the filter.
local function DungeonFor(activityIDs)
	activityIDs = IDList(activityIDs)
	if not activityIDs then return nil end
	return SharedName(activityIDs, MyActivityIDs())
		or SharedName(activityIDs, PickedActivityIDs())
		or FirstActivityName(activityIDs)
end

-------------------------------------------------------------------------------
-- Near me: who can actually be there soon. Their zone rides along with the
-- listing; the zone a dungeon sits in comes from the client's OWN map tree,
-- so there is no table of ours to keep up to date and it reads in whatever
-- language the player runs.
-------------------------------------------------------------------------------

function F.MyZone()
	local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
	if issecret(zone) or type(zone) ~= "string" or zone == "" then return nil end
	return zone
end

-- Every dungeon map under the world, with the zone it hangs off. Built once.
function F.ZoneIndex()
	if F.zoneIndex then return F.zoneIndex end
	local index = {}
	F.zoneIndex = index
	if not (C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapInfo and C_Map.GetBestMapForUnit) then
		return index
	end
	local map = Plain(C_Map.GetBestMapForUnit("player"))
	for _ = 1, 12 do -- climb to the top of the tree
		local info = map and Plain(C_Map.GetMapInfo(map))
		local parent = info and Plain(info.parentMapID)
		if not parent or parent == 0 then break end
		map = parent
	end
	if not map then return index end
	local kind = (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon) or 4
	local dungeons = Plain(C_Map.GetMapChildrenInfo(map, kind, true))
	if type(dungeons) ~= "table" then return index end
	local placed = 0
	for _, entry in ipairs(dungeons) do
		local name = Plain(entry.name)
		local above = Plain(entry.parentMapID)
		local zone = above and Plain(C_Map.GetMapInfo(above))
		zone = zone and Plain(zone.name)
		if type(name) == "string" and name ~= "" and type(zone) == "string" and zone ~= "" then
			index[name:lower()] = zone
			placed = placed + 1
		end
	end
	-- an empty answer is not an answer: let the next call try again, in case
	-- the map was not ready yet
	if placed == 0 then F.zoneIndex = nil end
	Log("near me: " .. placed .. " dungeons placed from the map tree")
	return index
end

-- The zone a dungeon sits in, plus the dungeon's own map name.
function F.DungeonZone(dungeon)
	if type(dungeon) ~= "string" or dungeon == "" then return nil end
	local index = F.ZoneIndex()
	local key = dungeon:lower()
	if index[key] then return index[key], key end
	for name, zone in pairs(index) do
		if name:find(key, 1, true) or key:find(name, 1, true) then return zone, name end
	end
	-- a wing carries only part of its dungeon's name ("Scarlet Graveyard"):
	-- one long word in common places it
	for word in key:gmatch("[^%s%-]+") do
		if #word >= 5 then
			for name, zone in pairs(index) do
				if name:find(word, 1, true) then return zone, name end
			end
		end
	end
	return nil
end

-- Their zone is yours, the dungeon's, or the dungeon itself. A zone the game
-- will not read out keeps the listing: there is nothing to judge it on.
function F.IsNear(area, activityIDs)
	if type(area) ~= "string" or area == "" then return true end
	local mine = F.MyZone()
	if mine and area == mine then return true end
	local dungeon = DungeonFor(activityIDs)
	if not dungeon then return false end
	local key = area:lower()
	if key == dungeon:lower() then return true end
	local zone, mapName = F.DungeonZone(dungeon)
	if zone and area == zone then return true end
	if mapName and key == mapName then return true end
	return false
end

-- The settings preview names what you are set up for right now.
local function PreviewDungeon()
	return FirstActivityName(MyActivityIDs()) or FirstActivityName(PickedActivityIDs()) or SAMPLE_DUNGEON
end

-- The solo listing (search result info) of the invited name, or nil. A fresh
-- GetFilteredSearchResults call is the unfiltered list.
local function SoloListingOf(name)
	local _, results = C_LFGList.GetFilteredSearchResults()
	if not results or issecret(results) then return nil end
	for i = 1, #results do
		local id = results[i]
		if not issecret(id) then
			local info = C_LFGList.GetSearchResultInfo(id)
			if info and not issecret(info) then
				local leader, members = info.leaderName, info.numMembers
				if not (issecret(leader) or issecret(members)) and members == 1 and leader == name then
					return info
				end
			end
		end
	end
	return nil
end

-- A whisper by default; the suggest button passes PARTY or RAID instead.
local function SendWhisper(text, target, channel)
	channel = channel or "WHISPER"
	if C_ChatInfo and C_ChatInfo.SendChatMessage then
		C_ChatInfo.SendChatMessage(text, channel, nil, target)
	else
		SendChatMessage(text, channel, nil, target)
	end
end

-- Whispers the invite message to a listed solo player just invited. From a
-- click (the InviteUnit hook) it needs the whisper switch on and the browse
-- window open; `auto` (an invite made through a companion addon) skips both -
-- such an invite must always explain itself - but every other gate
-- (lockdown, listed solo player, the one-minute repeat guard) still applies,
-- so the hook and the companion firing for the same invite whisper once.
local function WhisperInvitee(name, auto)
	if not auto then
		if not WhisperOn() then return end
		local frame = LFGBrowseFrame
		if not (frame and frame:IsVisible()) then return end
	end
	if issecret(name) or type(name) ~= "string" then
		Log("invite: name unreadable - no whisper")
		return
	end
	lockSeen = LockState()
	if lockSeen ~= "no" then
		Log("invite: " .. name .. " - lockdown=" .. lockSeen .. ", no whisper")
		return
	end
	local listing = SoloListingOf(name)
	if not listing then
		Log("invite: " .. name .. " - not a listed player, no whisper")
		return
	end
	local now = GetTime()
	local last = lastWhisper[name]
	if last and now - last < WHISPER_REPEAT then
		Log(string.format("invite: %s - whispered %ds ago, not again", name, math.floor(now - last)))
		return
	end
	-- the role you picked on the way in, else the only one they signed up as
	local role = F.pendingRole and F.pendingRole[name]
	if F.pendingRole then F.pendingRole[name] = nil end
	if not role then role = F.OnlyRole(listing) end
	local text = BuildMessage(MessageTemplate(), DungeonFor(listing.activityIDs) or FALLBACK_DUNGEON,
		FirstName(name), role)
	if not text:match("%S") then
		Log("invite: " .. name .. " - message is empty, no whisper")
		return
	end
	lastWhisper[name] = now
	SendWhisper(text, name)
	Log("invite: whispered " .. name .. ": " .. text)
end

-- Which roles a listing signed up as, and the one role when there is only
-- one: that needs no asking.
F.pendingRole = {}

function F.ListingRoles(listing)
	local id = listing and Plain(listing.searchResultID)
	local member = id and C_LFGList.GetSearchResultPlayerInfo(id, 1)
	if not member or issecret(member) then return nil end
	local roles = member.lfgRoles
	if not roles or issecret(roles) then return nil end
	local out = {}
	for _, role in ipairs(ROLES) do
		local on = roles[role.solo]
		if not issecret(on) and on then out[#out + 1] = role end
	end
	return out
end

function F.OnlyRole(listing)
	local roles = F.ListingRoles(listing)
	return (roles and #roles == 1) and roles[1].label or nil
end

-- True when the invite whisper would say a role but the listing offers more
-- than one, so the player has to say which.
function F.NeedsRolePick(listing)
	if not WhisperOn() then return nil end
	local template = MessageTemplate()
	if not (template and template:lower():find("{role}", 1, true)) then return nil end
	local roles = F.ListingRoles(listing)
	if not roles or #roles < 2 then return nil end
	return roles
end

-- Post-hook on C_PartyInfo.InviteUnit: the invite has already run (and
-- Blizzard's stays secure); this runs right after it, inside the same click.
local function OnInviteUnit(name)
	WhisperInvitee(name, false)
end

-------------------------------------------------------------------------------
-- Snapshot: what the addon can read for every listing, filter or not
-------------------------------------------------------------------------------

local function VerdictText(resultID)
	if not FilterActive() then return "n/a (no filter)" end
	local verdict = Verdict(resultID)
	if verdict == nil then return "UNREADABLE" end
	return verdict and "keep" or "drop"
end

local function DescribeResult(index, resultID)
	if issecret(resultID) then
		Log(string.format("  #%d id=<secret>", index))
		return
	end
	local parts = { string.format("  #%d id=%s", index, S(resultID)) }

	local info = C_LFGList.GetSearchResultInfo(resultID)
	if info == nil then
		parts[#parts + 1] = "info=nil"
	elseif issecret(info) then
		parts[#parts + 1] = "info=<secret table>"
	else
		parts[#parts + 1] = "name=" .. S(info.leaderName)
		parts[#parts + 1] = "members=" .. S(info.numMembers)
		parts[#parts + 1] = "self=" .. S(info.hasSelf)
		parts[#parts + 1] = "delisted=" .. S(info.isDelisted)
	end

	local member = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
	if member == nil then
		parts[#parts + 1] = "player=nil"
	elseif issecret(member) then
		parts[#parts + 1] = "player=<secret table>"
	else
		local roles = member.lfgRoles
		if roles == nil then
			parts[#parts + 1] = "lfgRoles=nil"
		elseif issecret(roles) then
			parts[#parts + 1] = "lfgRoles=<secret table>"
		else
			parts[#parts + 1] = string.format("roles T=%s H=%s D=%s", S(roles.tank), S(roles.healer), S(roles.dps))
		end
		parts[#parts + 1] = "class=" .. S(member.classFilename) .. " lvl=" .. S(member.level)
	end

	local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
	if counts == nil then
		parts[#parts + 1] = "counts=nil"
	elseif issecret(counts) then
		parts[#parts + 1] = "counts=<secret table>"
	else
		parts[#parts + 1] = string.format("counts T=%s H=%s D=%s open T=%s H=%s D=%s",
			S(counts.TANK), S(counts.HEALER), S(counts.DAMAGER),
			S(counts.TANK_REMAINING), S(counts.HEALER_REMAINING), S(counts.DAMAGER_REMAINING))
	end

	-- every member's class of a group (what "Hide groups with" reads)
	local members = info and not issecret(info) and Plain(info.numMembers)
	if members and members > 1 then
		local classes = {}
		for m = 1, members do
			local p = C_LFGList.GetSearchResultPlayerInfo(resultID, m)
			classes[m] = (p == nil and "nil") or (issecret(p) and "<secret>") or S(p.classFilename)
		end
		parts[#parts + 1] = "member classes=" .. table.concat(classes, ",")
	end

	parts[#parts + 1] = "verdict=" .. VerdictText(resultID)
	Log(table.concat(parts, "  "))
end

local function Snapshot(label)
	logBatching = true
	local frame = LFGBrowseFrame
	Log("---- SNAPSHOT (" .. label .. ") ----")
	Log(string.format("LFG window: loaded=%s shown=%s searching=%s  filter button=%s",
		S(frame ~= nil), S(frame and frame:IsShown()), S(frame and frame.searching), S(frames.button ~= nil)))
	local lockRaw = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
	local inInstance, instanceType = IsInInstance()
	Log(string.format("InChatMessagingLockdown=%s  issecretvalue exists=%s  inInstance=%s (%s)  inCombat=%s",
		S(lockRaw), S(issecretvalue ~= nil), S(inInstance), S(instanceType), S(InCombatLockdown())))
	Log(string.format("filter: %s  my roles: %s  our list: shown=%s, %s of %s listings, selected=%s, pause=%s",
		FilterSummary(), MyRolesText(), S(view ~= nil and view:IsShown()), S(shownCount), S(totalCount),
		S(selectedID), S(pausedReason)))
	Log(string.format("invite whisper: %s  message: %s  settings table: %s",
		WhisperOn() and "ON" or "off", MessageTemplate(), S(db ~= nil)))
	local total, results = C_LFGList.GetFilteredSearchResults()
	if issecret(results) then
		Log("GetFilteredSearchResults: total=" .. S(total) .. "  results=<secret table>")
	elseif results then
		Log(string.format("GetFilteredSearchResults: total=%s listed=%d", S(total), #results))
		for i = 1, #results do DescribeResult(i, results[i]) end
	else
		Log("GetFilteredSearchResults: total=" .. S(total) .. "  results=nil")
	end
	if frame and frame.results and not issecret(frame.results) then
		Log(string.format("Blizzard list table right now: %d rows", #frame.results))
	end
	Log("---- end snapshot ----")
	logBatching = false
	RefreshPanel()
end

-------------------------------------------------------------------------------
-- Debug panel (movable, copyable, never prints to chat)
-------------------------------------------------------------------------------

local function MakePanelButton(parent, text, x, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(100, 22)
	button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 12)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function BuildPanel()
	local frame = CreateFrame("Frame", "ArcLFGFilterDebug", UIParent, "BackdropTemplate")
	frame:SetSize(620, 440)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	frame:SetBackdropColor(0.05, 0.07, 0.11, 0.96)
	frame:SetBackdropBorderColor(0.2, 0.75, 0.9, 1)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -10)
	title:SetText("Arc LFG Filter - Debug log")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 44)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(620 - 12 - 32)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	scroll:SetScrollChild(edit)

	frame.Scroll, frame.Edit = scroll, edit

	MakePanelButton(frame, "Select All", 12, function()
		edit:SetFocus()
		edit:HighlightText()
	end)
	MakePanelButton(frame, "Snapshot", 118, function() Snapshot("button") end)
	MakePanelButton(frame, "Refresh", 224, RefreshPanel)
	MakePanelButton(frame, "Clear", 330, function()
		wipe(logLines)
		RefreshPanel()
	end)

	frame:SetScript("OnShow", RefreshPanel)
	panel = frame
end

local function ShowPanel()
	if not panel then BuildPanel() end
	panel:Show()
	RefreshPanel()
end

-- The whisper queue lives in one table, not twenty file locals: this file
-- sits near Lua's 200-local ceiling. `items` is the queue (newest first),
-- `mode` is true while the Whispers tab is the one showing. Its functions are
-- filled in two blocks below: the collector after the whisper box, the tab UI
-- next to the list it shares a panel with.
local WQ = {
	items = {},
	rows = {},
	MAX = 25,
	ROW_H = 46,
}

-------------------------------------------------------------------------------
-- Settings window (Arc theme: ALF_Theme.lua)
-------------------------------------------------------------------------------

local function RefreshSettings()
	if frames.settings and frames.settings:IsShown() then NS.AT.LayoutPage(frames.page) end
end

local function ToggleWhisper()
	SetWhisperOn(not WhisperOn())
	RefreshSettings()
end

local function BuildSettings()
	local AT = NS.AT
	local COL, LAY = AT.COL, AT.LAY
	local win = AT.CreateWindow("ArcLFGFilterSettings", {
		title = "|cff3fc9f2Arc|r|cffd5e2f2 LFG Filter|r",
		version = C_AddOns.GetAddOnMetadata(ADDON, "Version"),
		w = 470, h = 500, minW = 420, minH = 440,
	})
	local pg = AT.NewPage(win)
	pg:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -40)
	pg:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 40)
	pg:Show()

	AT.Section(pg, "Invite whisper")
	AT.RowToggle(pg, "Whisper players when I invite them", WhisperOn, SetWhisperOn, nil,
		"When you invite a player from the Looking For Group list, they also get your message as a whisper. Off until you turn it on.")

	AT.Section(pg, "Message")
	local input = AT.RowInput(pg, "Message", TypedMessage, function(text)
		SetTypedMessage(text)
		RefreshSettings()
	end, nil, "Leave it empty to send the default message.", DEFAULT_MESSAGE, true)
	-- a whole sentence, not a short value: the field runs from the control
	-- column to the row's end (the engine's _colFill) instead of 160px
	input._colFill = true
	input._colCtrl:SetMaxLetters(MAX_TEMPLATE)

	-- live preview, re-read on every layout; grows like RowDesc when it wraps
	local preview = AT.AddRow(pg, LAY.descH)
	local fs = preview:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, 11, "")
	fs:SetPoint("TOPLEFT", 10, -2)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
	preview._sync = function()
		fs:SetText("Preview:  |cfff2f7ff" .. BuildMessage(MessageTemplate(), PreviewDungeon(), SAMPLE_NAME) .. "|r")
		local width = pg:GetWidth() or 0
		if width < 60 then return end
		fs:SetWidth(width - 36)
		local want = math.max(LAY.descH, math.floor((fs:GetStringHeight() or 12) + 8))
		if preview._h ~= want then
			preview._h = want
			preview:SetHeight(want)
		end
	end

	AT.RowDesc(pg, "{dungeon} becomes the dungeon and {name} the player's first name.")

	AT.Section(pg, "Whisper queue")
	AT.RowToggle(pg, "Collect whispers while my group is listed", WQ.On, function(on)
		if on ~= WQ.On() then WQ.Toggle() end
	end, nil, "Adds a Whispers tab to the Looking For Group window: everyone who whispers you while your group is listed, with their class and an Invite button. Off until you turn it on.")

	AT.Section(pg, "Quick messages")
	for i = 1, QM.SLOTS do
		local row = AT.RowInput(pg, "Message " .. i, function() return QM.Text(i) or "" end,
			function(text)
				QM.Set(i, text)
				RefreshSettings()
			end, nil, nil, i == 1 and QM.DEFAULT or "Empty", true)
		row._colFill = true
		row._colCtrl:SetMaxLetters(MAX_TEMPLATE)
	end
	AT.RowDesc(pg, "These sit as buttons in the Send Message box. {level} and {class} become yours, {name} the player's first name and {dungeon} the dungeon.", 32)

	AT.AddDiscordFooter(win, "ArcLFGFilterDiscordCopy")
	-- CreateWindow owns OnShow via SetScript: hook it, never replace it
	win:HookScript("OnShow", function() AT.LayoutPage(pg) end)
	frames.settings, frames.page = win, pg
end

local function ShowSettings()
	if not frames.settings then BuildSettings() end
	frames.settings:Show()
	NS.AT.LayoutPage(frames.page)
	-- the first pass runs before the anchors resolve; measure again next frame
	C_Timer.After(0, RefreshSettings)
end

-------------------------------------------------------------------------------
-- Whisper box: Send Message for the addon's own list. Opening Blizzard's chat
-- box from addon code would leave the chat frames addon-touched (the same
-- trap as the list), so the message is typed here and sent as a whisper.
-------------------------------------------------------------------------------

-- A button's label: the message it will write, cut on a letter boundary.
local function Shorten(text, max)
	if #text <= max then return text end
	local cut = max
	while cut > 0 and (text:byte(cut + 1) or 0) >= 128 and (text:byte(cut + 1) or 0) < 192 do cut = cut - 1 end
	return text:sub(1, cut) .. "..."
end

-- The dungeon a quick message means for the player the box is open on: their
-- own listing first, then the usual preview fallback.
local function QuickDungeon(name)
	local info = SoloListingOf(name)
	local dungeon = info and DungeonFor(info.activityIDs)
	return dungeon or PreviewDungeon()
end

local function OpenWhisperBox(name)
	if not name then return end
	local AT = NS.AT
	local COL = AT.COL
	if not frames.whisper then
		local win = AT.CreateWindow("ArcLFGFilterWhisper", {
			title = "|cff3fc9f2Arc|r|cffd5e2f2 Send Message|r",
			w = 380, h = 152, minW = 380, minH = 152, resizable = false,
		})
		local label = win:CreateFontString(nil, "OVERLAY")
		label:SetFont(STANDARD_TEXT_FONT, 12, "")
		label:SetPoint("TOPLEFT", 14, -42)
		label:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])

		local box = CreateFrame("EditBox", nil, win, "BackdropTemplate")
		box:SetPoint("TOPLEFT", 12, -62)
		box:SetPoint("TOPRIGHT", -104, -62)
		box:SetHeight(22)
		AT.Skin(box, COL.well)
		box:SetFont(STANDARD_TEXT_FONT, 12, "")
		box:SetTextInsets(6, 6, 0, 0)
		box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
		box:SetAutoFocus(false)
		box:SetMaxLetters(MAX_WHISPER)

		local hint = win:CreateFontString(nil, "OVERLAY")
		hint:SetFont(STANDARD_TEXT_FONT, 10, "")
		hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
		hint:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
		hint:SetText("Enter sends, Esc closes.")

		local send = AT.MakeSmallButton(win, "Send", 84)
		send:SetPoint("LEFT", box, "RIGHT", 8, 0)

		local function Send()
			local text = ChatSafe(((box:GetText() or ""):match("^%s*(.-)%s*$")))
			if text == "" then return end
			lockSeen = LockState()
			if lockSeen ~= "no" then
				hint:SetText("The game is blocking addon messages right now.")
				Log("whisper box: lockdown=" .. lockSeen .. " - not sent")
				return
			end
			SendWhisper(text, win.target)
			Log("whisper box: sent to " .. win.target)
			-- a message you tweaked before sending is kept for next time
			if win.slot and win.filled and text ~= win.filled then
				QM.Set(win.slot, box:GetText())
				Log("whisper box: quick message " .. win.slot .. " kept as sent")
			end
			box:SetText("")
			win:Hide()
		end
		-- clear the box and your quick message is safe: only an edit OF the
		-- message that is in there is kept when you send it
		box:SetScript("OnTextChanged", function(self, byUser)
			if byUser and (self:GetText() or "") == "" then win.slot = nil end
		end)
		box:SetScript("OnEnterPressed", Send)
		box:SetScript("OnEscapePressed", function() win:Hide() end)
		send:SetScript("OnClick", Send)
		win:HookScript("OnHide", function() box:ClearFocus() end)

		-- ready-made messages, written in the settings window
		local quick = {}
		for i = 1, QM.SLOTS do
			local b = AT.MakeSmallButton(win, "", 112)
			if i == 1 then
				b:SetPoint("BOTTOMLEFT", 12, 12)
			else
				b:SetPoint("LEFT", quick[i - 1], "RIGHT", 6, 0)
			end
			b:SetScript("OnClick", function()
				local template = QM.Text(i)
				if not template then return end
				win.slot = i
				win.filled = BuildMessage(template, QuickDungeon(win.target), FirstName(win.target), QM.MyRoles())
				box:SetText(win.filled)
				box:SetFocus()
				box:SetCursorPosition(#(box:GetText() or ""))
			end)
			quick[i] = b
		end
		win.Label, win.Box, win.Hint, win.Quick = label, box, hint, quick
		frames.whisper = win
	end
	frames.whisper.target = name
	frames.whisper.Label:SetText("To " .. name)
	frames.whisper.Hint:SetText("Enter sends, Esc closes.")
	for i, button in ipairs(frames.whisper.Quick) do
		local template = QM.Text(i)
		button:SetShown(template ~= nil)
		if template then
			button.fs:SetText(Shorten(BuildMessage(template, QuickDungeon(name), FirstName(name), QM.MyRoles()), 15))
		end
	end
	-- the one you marked fills the box, ready to send or to tweak
	local first = QM.First()
	local opener = QM.Text(first)
	if opener then
		frames.whisper.slot = first
		frames.whisper.filled = BuildMessage(opener, QuickDungeon(name), FirstName(name), QM.MyRoles())
		frames.whisper.Box:SetText(frames.whisper.filled)
	else
		frames.whisper.slot = nil
		frames.whisper.Box:SetText("")
	end
	frames.whisper:Show()
	frames.whisper.Box:SetFocus()
end

-------------------------------------------------------------------------------
-- Whisper queue: who whispered you while your group is listed
-------------------------------------------------------------------------------
-- Arc, 2026-09-28: "when you queue your group you get bombarded with whispers
-- ... a whispered queue where it shows the class of the person that whispered
-- and the message, and an easy button to invite".
--
-- CHAT_MSG_WHISPER carries the text, the sender's name and their GUID, and
-- GetPlayerInfoByGUID turns that GUID into their class - listed or not. Level
-- and roles come from their own listing when they have one. The event is
-- `SecretInChatMessagingLockdown`, so in lockdown nothing is collected at all:
-- a secret would be unusable (no invite, no class) and must never be stored.
-- Default OFF; the queue lives in a tab over Blizzard's list, built below.

function WQ.On()
	return (db and db.whisperQueue == true) and true or false
end

function WQ.SetOn(on)
	if not db then return end
	db.whisperQueue = on and true or nil
	Log("whisper queue -> " .. (on and "ON" or "off"))
end

-- Only while you are actually recruiting.
function WQ.ListingActive()
	local mine = C_LFGList.GetActiveEntryInfo()
	return (mine ~= nil and not issecret(mine)) and true or false
end

function WQ.ClassFromGUID(guid)
	if not (guid and GetPlayerInfoByGUID) or issecret(guid) then return nil end
	local localized, classFile = GetPlayerInfoByGUID(guid)
	if issecret(classFile) then classFile = nil end
	if issecret(localized) then localized = nil end
	return classFile, localized
end

function WQ.Find(name)
	for i, entry in ipairs(WQ.items) do
		if entry.name == name then return entry, i end
	end
end

function WQ.Add(name, text, guid)
	if not WQ.On() then return end
	if issecret(name) or issecret(text) or type(name) ~= "string" or type(text) ~= "string" then return end
	if LockState() ~= "no" then return end   -- never store a secret
	if not WQ.ListingActive() then return end
	local classFile, className = WQ.ClassFromGUID(guid)
	local level, roles
	-- their own listing, when they have one, adds level and the roles they
	-- signed up as
	local info = SoloListingOf(name)
	local id = info and Plain(info.searchResultID)
	local member = id and C_LFGList.GetSearchResultPlayerInfo(id, 1)
	local area
	if member and not issecret(member) then
		level = Plain(member.level)
		area = Plain(member.areaName)
		classFile = classFile or Plain(member.classFilename)
		local signed = member.lfgRoles
		if signed and not issecret(signed) then
			roles = {}
			for _, role in ipairs(ROLES) do
				local on = signed[role.solo]
				roles[role.solo] = (not issecret(on) and on) and true or false
			end
		end
	end
	-- not listed but on your friends list: that carries their zone too.
	-- (/who is not an option: C_FriendList.SendWho is HasRestrictions, so an
	-- addon cannot ask the server where a stranger is.)
	if not area and C_FriendList and C_FriendList.GetFriendInfo then
		local friend = C_FriendList.GetFriendInfo(name)
		if friend and not issecret(friend) then area = Plain(friend.area) end
	end
	-- the same player whispering again moves back to the top and keeps the
	-- rest of what we know about them
	local entry, at = WQ.Find(name)
	if entry then
		table.remove(WQ.items, at)
	else
		entry = { name = name }
	end
	entry.text, entry.at = text, GetTime()
	entry.classFile, entry.className = classFile or entry.classFile, className or entry.className
	entry.level, entry.roles = level or entry.level, roles or entry.roles
	entry.area = area or entry.area
	table.insert(WQ.items, 1, entry)
	while #WQ.items > WQ.MAX do table.remove(WQ.items) end
	Log("whisper queue: " .. name .. (entry.classFile and (" (" .. entry.classFile .. ")") or ""))
	if WQ.Refresh then WQ.Refresh() end
end

-- Recruiting is over, so the queue is stale (Arc, 2026-09-28: "once the group
-- is full and it is not in the LFG, clear the whisper queue").
function WQ.PartyFull()
	if not IsInGroup() or (IsInRaid and IsInRaid()) then return false end
	local size = GetNumGroupMembers and GetNumGroupMembers()
	if issecret(size) or type(size) ~= "number" then return false end
	return size >= 5
end

function WQ.Clear(why)
	if #WQ.items == 0 then return end
	wipe(WQ.items)
	Log("whisper queue: cleared - " .. why)
	if WQ.Refresh then WQ.Refresh() end
end

function WQ.Drop(entry)
	local _, at = WQ.Find(entry and entry.name or "")
	if not at then return end
	table.remove(WQ.items, at)
	Log("whisper queue: dismissed " .. entry.name)
	if WQ.Refresh then WQ.Refresh() end
end

WQ.chat = CreateFrame("Frame")
for _, event in ipairs({ "CHAT_MSG_WHISPER", "LFG_LIST_ACTIVE_ENTRY_UPDATE", "GROUP_ROSTER_UPDATE" }) do
	if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
		WQ.chat:RegisterEvent(event)
	end
end
WQ.chat:SetScript("OnEvent", function(_, event, text, playerName, languageName, channelName, playerName2,
	specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid)
	if event == "CHAT_MSG_WHISPER" then
		WQ.Add(playerName, text, guid)
	elseif not WQ.ListingActive() then
		WQ.Clear("your group is no longer listed")
	elseif WQ.PartyFull() then
		WQ.Clear("your group is full")
	end
end)

-------------------------------------------------------------------------------
-- Popup menus: this addon's own, drawn with Forever's menu art
-------------------------------------------------------------------------------
-- Blizzard's menu system (MenuUtil) is shared by every menu in the game.
-- Opening one from addon code left it running on this addon's taint, and
-- Blizzard's own LFG Category dropdown then could not search:
-- "[ADDON_ACTION_BLOCKED] AddOn 'ArcLFGFilter' tried to call the protected
-- function 'Search()'" from Menu.lua Pick (2026-09-21). So the funnel and row
-- menus are drawn here, on this addon's frames, and never go near it. The
-- look copies Blizzard's MenuStyle1 (Mainline MenuTemplates / MenuVariants):
-- common-dropdown-bg at .925 alpha overhanging 10/3, insets 8/8/8/15, 20px
-- rows, 13px tooltip dividers, square and radial ticks with the yellow marks,
-- the chat expand arrow for submenus and the quest title highlight.
--
-- The builder mirrors the subset of Blizzard's menu description API this
-- addon (and its companion) uses - CreateTitle / CreateButton / CreateCheckbox
-- / CreateRadio / CreateDivider, SetResponse / SetEnabled / AddInitializer -
-- so the generators read the same. Defaults as Blizzard: checkboxes stay
-- open and refresh, radios and buttons close unless SetResponse(REFRESH).
-- One kind of our own, CreateInput: a label with a small typed box (the
-- Minimum level, Arc 2026-09-21: "I want this to be a user input").

local REFRESH = (MenuResponse and MenuResponse.Refresh) or "refresh"
local POPUP_ROW_H, POPUP_DIVIDER_H = 20, 13
local POPUP_INSET_L, POPUP_INSET_T, POPUP_INSET_R, POPUP_INSET_B, POPUP_PAD_W = 8, 8, 8, 15, 20
local POPUP_INPUT_H, POPUP_INPUT_W, POPUP_INPUT_GAP = 24, 36, 12

local PopupNode = {}
PopupNode.__index = PopupNode

local function NewPopupNode(kind, text)
	return setmetatable({ kind = kind, text = text, children = {}, enabled = true, inits = {} }, PopupNode)
end

function PopupNode:Add(kind, text)
	local node = NewPopupNode(kind, text)
	self.children[#self.children + 1] = node
	return node
end

function PopupNode:CreateTitle(text)
	return self:Add("title", text)
end

function PopupNode:CreateDivider()
	return self:Add("divider")
end

function PopupNode:CreateButton(text, callback, data)
	local node = self:Add("button", text)
	node.callback, node.data = callback, data
	return node
end

function PopupNode:CreateCheckbox(text, isSelected, setSelected, data)
	local node = self:Add("checkbox", text)
	node.isSelected, node.setSelected, node.data = isSelected, setSelected, data
	node.response = REFRESH
	return node
end

function PopupNode:CreateRadio(text, isSelected, setSelected, data)
	local node = self:Add("radio", text)
	node.isSelected, node.setSelected, node.data = isSelected, setSelected, data
	return node
end

-- A label with a typed box on the right. get() gives the text to show and
-- set(text) runs on every keystroke; the menu stays open and refreshes, and
-- the box keeps what is being typed until it loses focus. opts: numeric,
-- maxLetters, width, placeholder (shown while the box is empty).
function PopupNode:CreateInput(text, get, set, opts)
	local node = self:Add("input", text)
	node.get, node.set, node.opts = get, set, opts or {}
	return node
end

function PopupNode:SetResponse(response)
	self.response = response
end

function PopupNode:SetEnabled(on)
	self.enabled = on and true or false
end

function PopupNode:AddInitializer(fn)
	self.inits[#self.inits + 1] = fn
end

local popup = { panels = {}, openPath = {} } -- panels[level], 1 = the root
local hookedOwners = setmetatable({}, { __mode = "k" })
local RefreshPopup, ClosePopup -- defined below; rows call them

local function TextWidth(fs)
	return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

local function MouseOverPopup()
	for _, panel in pairs(popup.panels) do
		if panel:IsShown() and panel:IsMouseOver() then return true end
	end
	return false
end

-- Hides the panels from `level` down.
local function ClosePopupFrom(level)
	for l, panel in pairs(popup.panels) do
		if l >= level then panel:Hide() end
	end
end

local function PopupPanel(level)
	local panel = popup.panels[level]
	if panel then return panel end
	panel = CreateFrame("Frame", level == 1 and "ArcLFGFilterPopup" or nil, UIParent)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel.level = level
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAtlas("common-dropdown-bg")
	bg:SetPoint("TOPLEFT", -10, 3)
	bg:SetPoint("BOTTOMRIGHT", 10, -3)
	bg:SetAlpha(0.925)
	panel.rows = {}
	panel:Hide()
	if level == 1 then
		tinsert(UISpecialFrames, "ArcLFGFilterPopup") -- Escape closes it
		-- a click anywhere else closes it, like Blizzard's menus
		panel:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
		panel:SetScript("OnHide", function(self)
			self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
			ClosePopupFrom(2)
			popup.generator, popup.owner = nil, nil
		end)
		panel:SetScript("OnEvent", function()
			if MouseOverPopup() then return end
			if popup.owner and popup.owner:IsMouseOver() then return end -- its click toggles
			ClosePopup()
		end)
	end
	popup.panels[level] = panel
	return panel
end

local PopupRowEnter, PopupRowLeave, PopupRowClick -- defined below

local function PopupRow(panel, i)
	local row = panel.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, panel)
	row.panel = panel
	row:SetHeight(POPUP_ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.highlight:SetBlendMode("ADD")
	row.highlight:SetAllPoints()
	row.highlight:Hide()
	row.tick = row:CreateTexture(nil, "ARTWORK")
	row.mark = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.fontString = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.fontString:SetJustifyH("LEFT")
	row.fontString:SetWordWrap(false)
	row.arrow = row:CreateTexture(nil, "ARTWORK")
	row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	row.arrow:SetSize(16, 16)
	row.arrow:SetPoint("RIGHT")
	row.divider = row:CreateTexture(nil, "ARTWORK")
	row.divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
	row.divider:SetPoint("LEFT")
	row.divider:SetPoint("RIGHT")
	row.divider:SetHeight(POPUP_DIVIDER_H)
	row:SetScript("OnEnter", PopupRowEnter)
	row:SetScript("OnLeave", PopupRowLeave)
	row:SetScript("OnClick", PopupRowClick)
	panel.rows[i] = row
	return row
end

-- The box of an input entry, made on first use and kept with its row. It is
-- a plain EditBox wearing the game's input border (the atlases of Blizzard's
-- InputBoxVisualTemplate), so no Blizzard template or script runs on it.
local function PopupInput(row)
	local box = row.input
	if box then return box end
	box = CreateFrame("EditBox", nil, row)
	box.row = row
	box:SetSize(POPUP_INPUT_W, 20)
	box:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	box:SetAutoFocus(false)
	box:SetFontObject("GameFontHighlight")
	box:SetJustifyH("CENTER")
	box:SetTextInsets(2, 2, 0, 0)
	local left = box:CreateTexture(nil, "BACKGROUND")
	left:SetAtlas("common-search-border-left")
	left:SetSize(8, 20)
	left:SetPoint("LEFT")
	local right = box:CreateTexture(nil, "BACKGROUND")
	right:SetAtlas("common-search-border-right")
	right:SetSize(8, 20)
	right:SetPoint("RIGHT")
	local middle = box:CreateTexture(nil, "BACKGROUND")
	middle:SetAtlas("common-search-border-middle")
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
	box.placeholder = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	box.placeholder:SetPoint("CENTER")
	-- the mouse can reach the box without crossing its label: resting on it
	-- still closes a submenu opened from another entry
	box:SetScript("OnEnter", function(self) PopupRowEnter(self.row) end)
	box:SetScript("OnLeave", function(self) PopupRowLeave(self.row) end)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		-- show what is in effect ("07" becomes 7, a cleared box the placeholder)
		local node = self.row.node
		if node and node.kind == "input" and node.get then self:SetText(node.get() or "") end
		self.placeholder:SetShown(self:GetText() == "")
	end)
	box:SetScript("OnTextChanged", function(self, userInput)
		self.placeholder:SetShown(self:GetText() == "")
		if not userInput then return end
		local node = self.row.node
		if not (node and node.kind == "input" and node.enabled and node.set) then return end
		node.set(self:GetText())
		RefreshPopup()
	end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		ClosePopup()
	end)
	-- the keyboard is never kept once the menu is gone
	box:SetScript("OnHide", function(self) self:ClearFocus() end)
	row.input = box
	return box
end

-- Draws one entry; returns the width its content needs.
local function FillPopupRow(row, node)
	row.node = node
	local kind = node.kind
	row.tick:Hide()
	row.mark:Hide()
	row.arrow:Hide()
	row.divider:Hide()
	row.highlight:Hide()
	if row.input and kind ~= "input" then row.input:Hide() end
	if kind == "divider" then
		row:SetHeight(POPUP_DIVIDER_H)
		row.fontString:Hide()
		row.divider:Show()
		row:EnableMouse(false)
		return 0
	end
	row:SetHeight(POPUP_ROW_H)
	row:EnableMouse(kind ~= "title")
	local font = "GameFontHighlight"
	if kind == "title" then font = "GameFontNormal" elseif not node.enabled then font = "GameFontDisable" end
	row.fontString:SetFontObject(font)
	row.fontString:SetText(node.text or "")
	row.fontString:ClearAllPoints()
	row.fontString:Show()
	local width = TextWidth(row.fontString)
	if kind == "checkbox" or kind == "radio" then
		local on = node.isSelected and node.isSelected(node.data)
		row.tick:ClearAllPoints()
		row.mark:ClearAllPoints()
		if kind == "checkbox" then
			row.tick:SetAtlas("common-dropdown-ticksquare", true)
			row.tick:SetPoint("LEFT")
			row.mark:SetAtlas("common-dropdown-icon-checkmark-yellow", true)
			row.mark:SetPoint("CENTER", row.tick, "CENTER", 2, 1)
			row.fontString:SetPoint("LEFT", row.tick, "RIGHT", 7, 1)
			width = width + (row.tick:GetWidth() or 0) + 7
		else
			row.tick:SetAtlas("common-dropdown-tickradial", true)
			row.tick:SetPoint("LEFT", -3, 0)
			row.mark:SetAtlas("common-dropdown-icon-radialtick-yellow", true)
			row.mark:SetPoint("TOPLEFT", row.tick, "TOPLEFT")
			row.fontString:SetPoint("LEFT", row.tick, "RIGHT", 1, 0)
			width = width + (row.tick:GetWidth() or 0) - 2
		end
		row.tick:Show()
		row.mark:SetShown(on and true or false)
	elseif kind == "input" then
		local opts, box = node.opts, PopupInput(row)
		row:SetHeight(POPUP_INPUT_H)
		row.fontString:SetPoint("LEFT")
		box:SetWidth(opts.width or POPUP_INPUT_W)
		box:SetNumeric(opts.numeric and true or false)
		box:SetMaxLetters(opts.maxLetters or 0)
		box:SetEnabled(node.enabled)
		box.placeholder:SetText(opts.placeholder or "")
		-- a refresh while typing must not overwrite the typing
		if not box:HasFocus() then box:SetText(node.get and node.get() or "") end
		box.placeholder:SetShown(box:GetText() == "")
		box:Show()
		width = width + POPUP_INPUT_GAP + (opts.width or POPUP_INPUT_W)
	else
		row.fontString:SetPoint("LEFT")
	end
	if #node.children > 0 then
		row.arrow:Show()
		width = width + 16
	end
	for _, init in ipairs(node.inits) do init(row, node) end
	return width
end

-- Lays out one panel: the root at the click, a submenu beside its row.
local function RenderPopupPanel(level, node, anchorRow)
	local panel = PopupPanel(level)
	panel.node = node
	local y, widest, count = -POPUP_INSET_T, 50, 0
	for i, child in ipairs(node.children) do
		local row = PopupRow(panel, i)
		local width = FillPopupRow(row, child)
		row.index = i
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", POPUP_INSET_L, y)
		row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -POPUP_INSET_R, y)
		row:Show()
		y = y - row:GetHeight()
		if width > widest then widest = width end
		count = i
	end
	for i = count + 1, #panel.rows do
		panel.rows[i]:Hide()
		panel.rows[i].node = nil
	end
	-- A MENU NEVER SHRINKS WHILE IT IS OPEN. Ticking a filter rewrites the
	-- labels ("Class: any" becomes "Class: Paladin"), and a panel that
	-- resizes under the cursor reads as the menu jumping about.
	local key = (level == 1) and "root" or table.concat(popup.openPath, ".", 1, level - 1)
	if panel.widthKey ~= key then panel.widthKey, panel.minWidth = key, 0 end
	local width = widest + POPUP_PAD_W + POPUP_INSET_L + POPUP_INSET_R
	if width < (panel.minWidth or 0) then
		width = panel.minWidth
	else
		panel.minWidth = width
	end
	panel:SetSize(width, -y + POPUP_INSET_B)
	panel:ClearAllPoints()
	if anchorRow then
		panel:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", POPUP_INSET_R + 10, POPUP_INSET_T)
	else
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", popup.x or 0, popup.y or 0)
	end
	panel:Show()
	panel:Raise()
	return panel
end

local function OpenPopupSubmenu(row)
	local panel = row.panel
	local level = panel.level
	ClosePopupFrom(level + 2)
	for l = level, #popup.openPath do popup.openPath[l] = nil end
	popup.openPath[level] = row.index
	RenderPopupPanel(level + 1, row.node, row)
end

function PopupRowEnter(row)
	local node = row.node
	if not node or node.kind == "title" or node.kind == "divider" then return end
	if node.enabled and node.kind ~= "input" then row.highlight:Show() end
	if #node.children > 0 then
		OpenPopupSubmenu(row)
	else
		-- resting on a plain entry closes a submenu opened from this panel
		local level = row.panel.level
		ClosePopupFrom(level + 1)
		for l = level, #popup.openPath do popup.openPath[l] = nil end
	end
end

function PopupRowLeave(row)
	row.highlight:Hide()
end

function PopupRowClick(row)
	local node = row.node
	if not node or not node.enabled or node.kind == "title" or node.kind == "divider" then return end
	-- a checkbox that carries a submenu still TICKS on click; its submenu is
	-- on hover (the class rows, which hold their own role list)
	if #node.children > 0 and node.kind ~= "checkbox" then
		OpenPopupSubmenu(row)
		return
	end
	local kind = node.kind
	if kind == "input" then
		-- a click on the label types into the box
		if row.input then row.input:SetFocus() end
		return
	end
	if kind == "checkbox" and node.isSelected and node.isSelected(node.data) then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
	if kind == "checkbox" or kind == "radio" then
		if node.setSelected then node.setSelected(node.data) end
	elseif node.callback then
		node.callback(node.data)
	end
	if node.response == REFRESH then RefreshPopup() else ClosePopup() end
end

-- Rebuilds every open panel from the generator, keeping open submenus open.
function RefreshPopup()
	if not popup.generator then return end
	local root = NewPopupNode("root")
	popup.generator(popup.owner, root)
	local node, panel = root, RenderPopupPanel(1, root, nil)
	for level = 1, #popup.openPath do
		local child = node.children[popup.openPath[level]]
		if not (child and #child.children > 0) then
			ClosePopupFrom(level + 1)
			for l = level, #popup.openPath do popup.openPath[l] = nil end
			break
		end
		panel = RenderPopupPanel(level + 1, child, panel.rows[popup.openPath[level]])
		node = child
	end
end

function ClosePopup()
	for _, panel in pairs(popup.panels) do panel.widthKey, panel.minWidth = nil, 0 end
	ClosePopupFrom(1)
	popup.generator, popup.owner = nil, nil
	wipe(popup.openPath)
end

local function PopupOpenFor(owner)
	return popup.owner == owner and popup.panels[1] ~= nil and popup.panels[1]:IsShown()
end

-- Opens a menu at the cursor. `generator(owner, root)` fills it.
local function OpenPopup(owner, generator)
	ClosePopup()
	popup.owner, popup.generator = owner, generator
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale() or 1
	popup.x, popup.y = x / scale, y / scale
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	RefreshPopup()
	-- a menu never outlives what it belongs to (the window closing, a row
	-- being recycled)
	if owner and owner.HookScript and not hookedOwners[owner] then
		hookedOwners[owner] = true
		owner:HookScript("OnHide", function(self)
			if popup.owner == self then ClosePopup() end
		end)
	end
end
NS.OpenPopup = OpenPopup

-------------------------------------------------------------------------------
-- Button badge and menu status
-------------------------------------------------------------------------------

local function StatusText()
	if not FilterActive() then return "Showing everyone" end
	if pausedReason then return STATUS_WIDEST end
	return string.format("Showing %d of %d", shownCount, totalCount)
end

local function UpdateButton()
	if not frames.button then return end
	local badge = frames.button.Badge
	if FilterActive() then
		frames.button:LockHighlight()
		if pausedReason then
			badge:SetText("!")
			badge:SetTextColor(1, 0.3, 0.3)
		else
			badge:SetText(tostring(shownCount))
			badge:SetTextColor(1, 1, 1)
		end
		badge:Show()
	else
		frames.button:UnlockHighlight()
		badge:Hide()
	end
	-- the panel carries the same count and status line
	if NS.Panel and NS.Panel.Refresh then NS.Panel.Refresh() end
end

-------------------------------------------------------------------------------
-- The addon's own list, over Blizzard's while a filter is on
-------------------------------------------------------------------------------

local RebuildView -- defined below; the category headers call it

-- Suggest Invite is the SAME call as an invite: in someone else's group
-- C_PartyInfo.InviteUnit asks the leader on your behalf and the game only
-- changes the label (GetDisplayedInviteType -> SUGGEST_INVITE). It is refused
-- only when the group is already full and you do not lead it.
function F.MustSuggest()
	return (IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")))
		and true or false
end

function F.Blocked()
	return F.MustSuggest() and C_PartyInfo.IsPartyFull and C_PartyInfo.IsPartyFull() and true or false
end

function F.InviteLabel(short)
	if F.MustSuggest() then return "Suggest" end
	return short and (INVITE or "Invite") or (GROUP_INVITE or "Group Invite")
end

local function CanInvite(entry)
	if not (entry and entry.name and entry.solo) or entry.delisted or entry.self then return false end
	return not F.Blocked()
end

local function InviteEntry(entry, owner)
	if not CanInvite(entry) then return end
	-- when the whisper names a role and they signed up as several, ask which
	-- before the invite goes out; the answer rides along to the whisper
	local choices = entry.solo and F.NeedsRolePick(SoloListingOf(entry.name))
	if choices and owner then
		NS.OpenPopup(owner, function(_, root)
			root:CreateTitle("Inviting " .. FirstName(entry.name) .. " as")
			for _, role in ipairs(choices) do
				root:CreateButton(role.label, function()
					F.pendingRole[entry.name] = role.label
					Log("our list: invite " .. entry.name .. " as " .. role.label)
					C_PartyInfo.InviteUnit(entry.name)
				end)
			end
		end)
		return
	end
	Log("our list: " .. (F.MustSuggest() and "suggest " or "invite ") .. entry.name)
	C_PartyInfo.InviteUnit(entry.name)
end

local function SelectedEntry()
	if not selectedID then return nil end
	for _, row in ipairs(viewRows) do
		if row:IsShown() and row.entry and row.entry.id == selectedID then return row.entry end
	end
	return nil
end

local function PaintSelection()
	for _, row in ipairs(viewRows) do
		row.Selected:SetShown(row:IsShown() and row.entry ~= nil and row.entry.id == selectedID)
	end
end

local function UpdateViewButtons()
	if not view then return end
	local entry = SelectedEntry()
	view.SendButton:SetEnabled(entry ~= nil and entry.name ~= nil)
	view.InviteButton:SetText(F.InviteLabel())
	view.InviteButton:SetEnabled(CanInvite(entry))
end

local function ShowRowMenu(row)
	local entry = row.entry
	NS.OpenPopup(row, function(owner, root)
		root:CreateTitle(entry.name)
		root:CreateButton(SEND_MESSAGE or "Send Message", function() OpenWhisperBox(entry.name) end)
		local invite = root:CreateButton(F.InviteLabel(), function() InviteEntry(entry, owner) end)
		invite:SetEnabled(CanInvite(entry))
	end)
end

local function RowOnClick(row, button)
	local entry = row.entry
	if not entry or entry.delisted or entry.self then return end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if button == "RightButton" then
		ShowRowMenu(row)
		return
	end
	if selectedID == entry.id then selectedID = nil else selectedID = entry.id end
	PaintSelection()
	UpdateViewButtons()
end

local function TableReadable(t)
	for _, v in pairs(t) do
		if issecret(v) then return false end
	end
	return true
end

-- The hover card. Blizzard's LFGBrowseSearchEntryTooltip is theirs: filling
-- it from here would leave it addon-touched, so this is GameTooltip with the
-- same content in the same order - delisted / new-player notes, the members
-- (role icon, class-coloured name, spec when the game gives one, level; the
-- leader marked with the crown), the comment, the member count, the
-- activities (yours in blue) and the bosses already defeated. Every field
-- is secret-guarded.
local ROLE_ATLAS = {
	TANK    = "groupfinder-icon-role-large-tank",
	HEALER  = "groupfinder-icon-role-large-heal",
	DAMAGER = "groupfinder-icon-role-large-dps",
}
local LEADER_ICON     = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14|t"
local MEMBER_LIST_MAX = 10 -- Blizzard lists the members only up to this size

local function Icon(atlas)
	return string.format("|A:%s:14:14|a", atlas)
end

local function ClassColored(name, classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
	return name
end

-- One member: role icon + name (+ crown) on the left, spec + level right.
local function AddMemberLine(member, isLeader)
	if not member or issecret(member) then return end
	local name = Plain(member.name)
	if not name then return end
	local classFile, level = Plain(member.classFilename), Plain(member.level)
	local role, spec = Plain(member.assignedRole), Plain(member.specName)
	local left = ClassColored(name, classFile)
	if role and ROLE_ATLAS[role] then left = Icon(ROLE_ATLAS[role]) .. " " .. left end
	if isLeader then left = left .. " " .. LEADER_ICON end
	local right = level and ((LEVEL_ABBR or "Lvl") .. " " .. level) or ""
	if spec and spec ~= "" then right = spec .. "   " .. right end
	GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 0.65, 0.65, 0.65)
end

local function RowOnEnter(row)
	local entry = row.entry
	if not entry then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local info = LockState() == "no" and C_LFGList.GetSearchResultInfo(entry.id)
	if not info or issecret(info) then
		GameTooltip:SetText(entry.name or "?", 1, 1, 1)
		GameTooltip:AddLine("Details are hidden right now.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
		return
	end
	local color = NORMAL_FONT_COLOR
	local leader = C_LFGList.GetSearchResultLeaderInfo(entry.id)
	local leaderClass = leader and not issecret(leader) and Plain(leader.classFilename)
	if leaderClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[leaderClass] then color = RAID_CLASS_COLORS[leaderClass] end
	GameTooltip:SetText(entry.name or "?", color.r, color.g, color.b)
	if entry.delisted then GameTooltip:AddLine(LFG_LIST_ENTRY_DELISTED or "Delisted", 1, 0.2, 0.2) end
	if Plain(info.newPlayerFriendly) then
		GameTooltip:AddLine(Icon("newplayerchat-chaticon-newcomer") .. " "
			.. (LFG_LIST_NEW_PLAYER_FRIENDLY_HEADER or "New Player Friendly"), 0.1, 1, 0.1)
	end

	local members = Plain(info.numMembers)
	if members == 1 then
		local member = C_LFGList.GetSearchResultPlayerInfo(entry.id, 1)
		if member and not issecret(member) then
			local level, classFile = Plain(member.level), Plain(member.classFilename)
			local spec = Plain(member.specName)
			if level and classFile then
				local line = string.format("%s %s %s", LEVEL or "Level", level, ClassLabel(classFile))
				if spec and spec ~= "" then line = line .. " (" .. spec .. ")" end
				GameTooltip:AddLine(line, 1, 1, 1)
			end
			local roles = member.lfgRoles
			if roles and not issecret(roles) then
				local parts = {}
				for _, role in ipairs(ROLES) do
					local on = roles[role.solo]
					if not issecret(on) and on then parts[#parts + 1] = Icon(ROLE_ATLAS[role.key]) .. " " .. role.label end
				end
				if #parts > 0 then GameTooltip:AddLine("Roles:  " .. table.concat(parts, "  "), 0.9, 0.9, 0.9) end
			end
		end
	elseif members and members <= MEMBER_LIST_MAX then
		-- the leader first, then everyone else in the game's order
		local list = {}
		for m = 1, members do
			local member = C_LFGList.GetSearchResultPlayerInfo(entry.id, m)
			if member and not issecret(member) and Plain(member.isLeader) then
				table.insert(list, 1, member)
			elseif member then
				list[#list + 1] = member
			end
		end
		for i, member in ipairs(list) do
			AddMemberLine(member, i == 1 and not issecret(member) and Plain(member.isLeader))
		end
	end

	local comment = Plain(info.comment)
	if comment and comment ~= "" then
		GameTooltip:AddLine(LFG_LIST_COMMENT_FORMAT and string.format(LFG_LIST_COMMENT_FORMAT, comment) or comment, 0.8, 0.8, 0.8, true)
	end

	if members and members > 1 then
		local counts = C_LFGList.GetSearchResultMemberCounts(entry.id)
		local readable = counts and not issecret(counts)
		local tank = readable and Plain(counts.TANK)
		local healer = readable and Plain(counts.HEALER)
		local dps = readable and Plain(counts.DAMAGER)
		if tank and healer and dps then
			GameTooltip:AddLine(string.format("%d players: %d tank, %d healer, %d DPS", members, tank, healer, dps), 1, 1, 1)
		else
			GameTooltip:AddLine(string.format("%d players", members), 1, 1, 1)
		end
	end

	local ids = IDList(info.activityIDs)
	if ids then
		local mine = MyActivityIDs()
		for _, id in ipairs(ids) do
			local name = ActivityName(id)
			if name then
				local c = (mine and ListHas(mine, id)) and BRIGHTBLUE_FONT_COLOR or GRAY_FONT_COLOR
				GameTooltip:AddLine(name, c.r, c.g, c.b)
			end
		end
		-- bosses this group already killed (Blizzard shows them for a single dungeon)
		if #ids == 1 and C_LFGList.GetSearchResultEncounterInfo then
			local killed = C_LFGList.GetSearchResultEncounterInfo(entry.id)
			if killed and not issecret(killed) and #killed > 0 then
				GameTooltip:AddLine(LFG_LIST_BOSSES_DEFEATED or "Bosses Defeated:", 1, 0.82, 0)
				for _, boss in ipairs(killed) do
					if not issecret(boss) then GameTooltip:AddLine(boss, 1, 0.1, 0.1) end
				end
			end
		end
	end
	GameTooltip:Show()
end

local function RowOnLeave()
	GameTooltip:Hide()
end

local function NewRow()
	local row = CreateFrame("Button", nil, view.Content)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(1, 1, 1, 0.04)
	bg:SetPoint("TOPLEFT", 3, -2)
	bg:SetPoint("BOTTOMRIGHT", -3, 0)

	row.PartyIcon = row:CreateTexture(nil, "ARTWORK")
	row.PartyIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	row.PartyIcon:SetSize(24, 24)
	row.PartyIcon:SetPoint("TOPLEFT", 8, -4)

	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	row.Name:SetJustifyH("LEFT")
	row.Name:SetMaxLines(1)
	row.Name:SetHeight(14)

	row.Level = row:CreateFontString(nil, "ARTWORK", "GameFontDisableLeft")
	row.Level:SetMaxLines(1)
	row.Level:SetHeight(14)
	row.Level:SetPoint("BOTTOMLEFT", row.Name, "BOTTOMRIGHT", 4, 0)

	row.ClassIcon = row:CreateTexture(nil, "ARTWORK")
	row.ClassIcon:SetSize(24, 24)
	row.ClassIcon:SetPoint("BOTTOMLEFT", row.Level, "BOTTOMRIGHT", 3, -5)

	row.NewPlayer = row:CreateTexture(nil, "ARTWORK")
	row.NewPlayer:SetAtlas("newplayerchat-chaticon-newcomer")
	row.NewPlayer:SetSize(20, 20)
	row.NewPlayer:Hide()

	row.Activity = row:CreateFontString(nil, "ARTWORK", "GameFontDisableLeft")
	row.Activity:SetHeight(15)
	row.Activity:SetPoint("BOTTOMLEFT", 10, 5)

	row.Selected = row:CreateTexture(nil, "OVERLAY")
	row.Selected:SetAtlas("groupfinder-highlightbar-yellow")
	row.Selected:SetBlendMode("ADD")
	row.Selected:SetPoint("TOPLEFT", 3, -3)
	row.Selected:SetPoint("BOTTOMRIGHT", -3, -1)
	row.Selected:Hide()

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAtlas("groupfinder-highlightbar-blue")
	highlight:SetBlendMode("ADD")
	highlight:SetPoint("TOPLEFT", 3, -3)
	highlight:SetPoint("BOTTOMRIGHT", -3, -1)

	-- Blizzard's role display, used purely as art: its delist button would
	-- run Blizzard's listing code from an addon-made frame, so it stays off
	if view.hasDisplay then
		local display = CreateFrame("Frame", nil, row, DISPLAY_TEMPLATE)
		display:SetPoint("RIGHT", row, "RIGHT", -2, -1)
		display.showDelistButton = false
		if display.DelistButton then
			display.DelistButton:Hide()
			display.DelistButton:EnableMouse(false)
		end
		row.Display = display
	end

	row:SetScript("OnClick", RowOnClick)
	row:SetScript("OnEnter", RowOnEnter)
	row:SetScript("OnLeave", RowOnLeave)
	return row
end

local function NewHeader()
	local header = CreateFrame("Button", nil, view.Content)
	header:SetHeight(HEADER_H)

	local bg = header:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0.3, 0.3, 0.3, 0.2)
	bg:SetPoint("TOPLEFT", 3, -8)
	bg:SetPoint("BOTTOMRIGHT", -3, 0)

	header.Label = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header.Label:SetJustifyH("LEFT")
	header.Label:SetSize(200, 18)
	header.Label:SetPoint("LEFT", 8, -4)

	header.Expand = header:CreateTexture(nil, "ARTWORK")
	header.Expand:SetAtlas("QuestLog-icon-Expand")
	header.Collapse = header:CreateTexture(nil, "ARTWORK")
	header.Collapse:SetAtlas("QuestLog-icon-shrink")
	for _, icon in ipairs({ header.Expand, header.Collapse }) do
		icon:SetSize(18, 18)
		icon:SetPoint("RIGHT", -8, -4)
		icon:SetVertexColor(0.8, 0.8, 0.8, 1)
	end

	local highlight = header:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAtlas("groupfinder-highlightbar-blue")
	highlight:SetBlendMode("ADD")
	highlight:SetPoint("TOPLEFT", 3, -7)
	highlight:SetPoint("BOTTOMRIGHT", -3, -1)

	header:SetScript("OnClick", function(self)
		collapsed[self.category] = not collapsed[self.category] or nil
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		RebuildView()
	end)
	return header
end

-- One row, built the way Blizzard's LFGBrowseSearchEntry_Update builds
-- theirs, minus their tooltip. Called only after a fully readable verdict
-- pass, and every field is still secret-guarded.
local function FillRow(row, id, info)
	local isSolo = Plain(info.numMembers) == 1
	local hasSelf = Plain(info.hasSelf) and true or false
	local delisted = Plain(info.isDelisted) and true or false
	local name = Plain(info.leaderName)
	row.entry = { id = id, name = name, solo = isSolo, self = hasSelf, delisted = delisted }

	local soloRoles, area
	if isSolo then
		row.PartyIcon:Hide()
		local member = C_LFGList.GetSearchResultPlayerInfo(id, 1)
		local readable = member and not issecret(member)
		local classFile = readable and Plain(member.classFilename)
		local level = readable and Plain(member.level)
		area = readable and Plain(member.areaName)
		local atlas = classFile and ("groupfinder-icon-class-" .. classFile:lower())
		if classFile and level and C_Texture.GetAtlasInfo(atlas) then
			row.Level:SetText((LEVEL_ABBR or "Lvl") .. " " .. level)
			row.Level:Show()
			row.ClassIcon:SetAtlas(atlas, false)
			row.ClassIcon:Show()
		else
			row.Level:Hide()
			row.ClassIcon:Hide()
		end
		row.Name:SetPoint("TOPLEFT", row.PartyIcon, "TOPLEFT", 1, -5)
		row.NewPlayer:SetPoint("LEFT", row.ClassIcon, "RIGHT", 2, 0)
		local roles = readable and member.lfgRoles
		if roles and not issecret(roles)
			and not (issecret(roles.tank) or issecret(roles.healer) or issecret(roles.dps)) then
			soloRoles = roles
		end
	else
		row.PartyIcon:Show()
		row.Level:Hide()
		row.ClassIcon:Hide()
		row.Name:SetPoint("TOPLEFT", row.PartyIcon, "TOPRIGHT", 0, -5)
		row.NewPlayer:SetPoint("LEFT", row.Name, "RIGHT", 2, 0)
	end

	-- activity line: yours first (blue), a count when several, and grey
	-- when the listing is not in the activity filter
	local ids = {}
	for _, aid in ipairs(IDList(info.activityIDs) or {}) do
		if not issecret(aid) then ids[#ids + 1] = aid end
	end
	local matching = {}
	for _, aid in ipairs(MyActivityIDs() or {}) do
		if not issecret(aid) and ListHas(ids, aid) then matching[#matching + 1] = aid end
	end
	local shown = (#matching > 0) and matching or ids
	local activityText
	if hasSelf then
		activityText = LFG_SELF_LISTING or "Your listing"
	elseif #shown == 1 then
		activityText = ActivityName(shown[1]) or ""
	else
		local fmt = (#matching > 0) and LFGBROWSE_ACTIVITY_MATCHING_COUNT or LFGBROWSE_ACTIVITY_COUNT
		activityText = string.format(fmt or "%d activities", #shown)
	end
	local picked = PickedActivityIDs()
	local matchesFilter = true
	if picked and #picked > 0 then
		matchesFilter = false
		for _, aid in ipairs(ids) do
			if ListHas(picked, aid) then matchesFilter = true break end
		end
	end

	local nameColor = NORMAL_FONT_COLOR
	local leader = C_LFGList.GetSearchResultLeaderInfo(id)
	-- a group shows where its leader is standing
	if not area and leader and not issecret(leader) then area = Plain(leader.areaName) end
	local leaderClass = leader and not issecret(leader) and Plain(leader.classFilename)
	if leaderClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[leaderClass] then nameColor = RAID_CLASS_COLORS[leaderClass] end
	local levelColor, activityColor = GRAY_FONT_COLOR, GRAY_FONT_COLOR
	if delisted or not matchesFilter then
		nameColor, levelColor, activityColor = DELISTED_COLOR, DELISTED_COLOR, DELISTED_COLOR
	elseif hasSelf then
		activityColor = LIGHTGREEN_FONT_COLOR
	elseif #matching > 0 then
		activityColor = BRIGHTBLUE_FONT_COLOR
	end

	row.Name:SetWidth(0)
	row.Name:SetText(name or "")
	row.Name:SetTextColor(nameColor.r, nameColor.g, nameColor.b)
	if row.Name:GetWidth() > NAME_MAX then row.Name:SetWidth(NAME_MAX) end
	row.Level:SetTextColor(levelColor.r, levelColor.g, levelColor.b)
	row.ClassIcon:SetDesaturated(delisted)
	-- where they are, after the activity (Arc, 2026-10-11: "the current
	-- location of the person in here"); green when it is your own zone
	if type(area) == "string" and area ~= "" then
		if delisted then
			activityText = activityText .. "   " .. area
		else
			local mine = WQ.MyZone and WQ.MyZone()
			activityText = activityText .. "   |cff" .. ((area == mine) and "40dd5a" or "9d9d9d")
				.. area .. "|r"
		end
	end
	row.Activity:SetText(activityText)
	row.Activity:SetTextColor(activityColor.r, activityColor.g, activityColor.b)
	row.NewPlayer:SetShown(Plain(info.newPlayerFriendly) and true or false)
	row.NewPlayer:SetDesaturated(delisted)

	if row.Display then
		local counts = C_LFGList.GetSearchResultMemberCounts(id)
		if not counts or issecret(counts) or not TableReadable(counts) then counts = nil end
		local displayType, maxPlayers = LFGBrowseUtil_GetBestDisplayTypeForActivityIDs(ids)
		-- Blizzard's updater returns early without a display type, which
		-- would leave a pooled row showing its previous listing's roles
		row.Display:SetShown(displayType ~= nil)
		if displayType then
			LFGBrowseGroupDataDisplay_Update(row.Display, displayType, maxPlayers, counts, delisted,
				isSolo, soloRoles, Plain(info.comment) or "", hasSelf)
		end
	end
end

local function FillHeader(header, category)
	header.category = category
	if category == "whispers" then
		header.Label:SetText("Whispers (" .. #WQ.items .. ")")
	elseif category == "players" then
		header.Label:SetText(LFG_LIST_CATEGORY_SOLO_PLAYERS or "Players")
	else
		header.Label:SetText(LFG_LIST_CATEGORY_GROUPS or "Groups")
	end
	local shut = collapsed[category] and true or false
	header.Expand:SetShown(shut)
	header.Collapse:SetShown(not shut)
end

-- Blizzard's list keeps the scrollbar out of the way until it is needed.
-- Blizzard's Send Message / Group Invite overlap the bottom of the list area,
-- so the list stops above them: a row must never sit behind a button.
local function PlaceScroll(needBar)
	local scroll = view.Scroll
	local buttons = LFGBrowseFrame and LFGBrowseFrame.SendMessageButton
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", view, "TOPLEFT", 3, -3)
	scroll:SetPoint("RIGHT", view, "RIGHT", needBar and -18 or -2, 0)
	if buttons then
		scroll:SetPoint("BOTTOM", buttons, "TOP", 0, 6)
	else
		scroll:SetPoint("BOTTOM", view, "BOTTOM", 0, 3)
	end
	view.Bar:SetShown(needBar)
	if not needBar then scroll:SetVerticalScroll(0) end
end

-- What the list can show without scrolling.
local function ListHeight()
	local height = view and view.Scroll and view.Scroll:GetHeight()
	if height and height > 40 then return height end
	return math.max(40, (view and view:GetHeight() or 0) - 48)
end

-- Lays out the kept listings in Blizzard's order, with Blizzard's
-- Players / Groups headers (collapsible here too).
local function LayoutView(kept)
	local content = view.Content
	local showHeaders = LFGVANILLA_SETTING_BROWSE_SHOW_COLLAPSIBLE_CATEGORIES
	local y, rowCount, headerCount, lastCategory = 0, 0, 0, nil
	local selectedHere = false
	local function Place(frame, height)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
		frame:Show()
		y = y + height
	end

	-- The whisper queue rides above the listings as a third section, in the
	-- same collapsible shape as Players and Groups (Arc, 2026-09-28: "like
	-- the same drop down for groups and players, but the Whisper queue").
	local queued = WQ.On() and #WQ.items > 0
	local shownWhispers = 0
	if queued then
		headerCount = headerCount + 1
		local header = viewHeaders[headerCount] or NewHeader()
		viewHeaders[headerCount] = header
		FillHeader(header, "whispers")
		Place(header, HEADER_H)
		if not collapsed.whispers then
			for i, entry in ipairs(WQ.items) do
				local row = WQ.rows[i] or WQ.NewRow()
				WQ.rows[i] = row
				WQ.FillRow(row, entry)
				Place(row, WQ.ROW_H)
				shownWhispers = i
			end
		end
	end
	for i = shownWhispers + 1, #WQ.rows do
		WQ.rows[i]:Hide()
		WQ.rows[i].entry = nil
	end

	for _, id in ipairs(kept) do
		-- Verdict keeps a listing it has no info for (it cannot judge one);
		-- there is nothing to draw for it either
		local info = C_LFGList.GetSearchResultInfo(id)
		if info and not issecret(info) then
			local category
			if not info.hasSelf then category = (info.numMembers <= 1) and "players" or "groups" end
			if showHeaders and category and category ~= lastCategory then
				lastCategory = category
				headerCount = headerCount + 1
				local header = viewHeaders[headerCount] or NewHeader()
				viewHeaders[headerCount] = header
				FillHeader(header, category)
				Place(header, HEADER_H)
			end
			if not (category and collapsed[category]) then
				rowCount = rowCount + 1
				local row = viewRows[rowCount] or NewRow()
				viewRows[rowCount] = row
				FillRow(row, id, info)
				Place(row, ROW_H)
				if row.entry.id == selectedID then selectedHere = true end
			end
		end
	end
	for i = rowCount + 1, #viewRows do
		viewRows[i]:Hide()
		viewRows[i].entry = nil
	end
	for i = headerCount + 1, #viewHeaders do viewHeaders[i]:Hide() end
	if not selectedHere then selectedID = nil end

	-- the scroll area is 21px narrower than the list with a scrollbar, 5px
	-- without (Blizzard's own ScrollBox insets)
	local needBar = y > ListHeight()
	PlaceScroll(needBar)
	content:SetHeight(math.max(1, y))
	content:SetWidth(math.max(1, (view:GetWidth() or 0) - (needBar and 21 or 5)))
	view.Note:SetShown(#kept == 0 and not queued)
	PaintSelection()
	UpdateViewButtons()
end

local function HideView()
	if view and view:IsShown() then view:Hide() end
	UpdateButton()
end

-- Rebuilds the addon's list from Blizzard's CURRENT results (read, never
-- written): judge every listing first and step aside if any is unreadable.
function RebuildView()
	rebuildQueued = false
	local frame = LFGBrowseFrame
	if not (view and frame) then return end
	-- our list is the list while the window is open, filter or no filter
	-- (Arc, 2026-10-11: "I want the custom panel enabled as soon as I am
	-- looking for a dungeon, even if the filter is not turned on yet")
	if not frame:IsVisible() or frame.searching or frame.searchFailed then
		HideView()
		return
	end
	local results = frame.results
	if issecret(results) or type(results) ~= "table" then
		pausedReason = "hidden"
		HideView()
		Log("our list: Blizzard's results are unreadable - Blizzard's list shows")
		return
	end
	local n = #results
	totalCount = n
	if n == 0 and not (WQ.On() and #WQ.items > 0) then
		pausedReason, shownCount = nil, 0
		HideView()
		return
	end
	lockSeen = LockState()
	if lockSeen ~= "no" then
		pausedReason = "lockdown"
		HideView()
		Log(string.format("our list: %d listings - PAUSED, lockdown=%s, Blizzard's list shows", n, lockSeen))
		return
	end
	local kept = {}
	for i = 1, n do
		local id = results[i]
		local verdict
		if not issecret(id) then verdict = Verdict(id) end
		if verdict == nil then
			pausedReason = "hidden"
			HideView()
			Log(string.format("our list: %d listings - PAUSED, listing #%d unreadable, Blizzard's list shows", n, i))
			return
		end
		if verdict then kept[#kept + 1] = id end
	end
	pausedReason = nil
	shownCount = #kept
	view:Show()
	LayoutView(kept)
	UpdateButton()
	Log(string.format("our list: %d listings, filter %s - showing %d", n, FilterSummary(), shownCount))
end

-- Coalesced: many events in one frame cost one rebuild, from our own timer.
-- A rebuild that runs first (Blizzard's redraw) clears the flag and cancels it.
local function RequestRebuild()
	if rebuildQueued then return end
	rebuildQueued = true
	C_Timer.After(0, function()
		if rebuildQueued then RebuildView() end
	end)
end

local function BuildView(frame)
	local v = CreateFrame("Frame", nil, frame)
	v:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 0, 0)
	v:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", 0, 0)
	-- well above Blizzard's rows, which sit a few levels inside their ScrollBox
	local under = (frame.ScrollBox and frame.ScrollBox:GetFrameLevel()) or frame:GetFrameLevel()
	v:SetFrameLevel(under + 20)
	-- nothing reaches Blizzard's rows underneath: clicks, hover or the wheel
	v:EnableMouse(true)
	v:EnableMouseWheel(true)
	v:SetScript("OnMouseWheel", function() end)
	v:Hide()
	view = v

	-- the same art as Blizzard's Inset, over a solid base so none of the
	-- list underneath shows through
	local base = v:CreateTexture(nil, "BACKGROUND", nil, -8)
	base:SetColorTexture(0, 0, 0, 1)
	base:SetPoint("TOPLEFT", 3, -3)
	base:SetPoint("BOTTOMRIGHT", -3, 3)
	local art = v:CreateTexture(nil, "BACKGROUND", nil, -7)
	art:SetAtlas("groupfinder-background")
	art:SetPoint("TOPLEFT", 3, -3)
	art:SetPoint("BOTTOMRIGHT", -3, 3)

	local scroll = CreateFrame("ScrollFrame", nil, v)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	local bar = CreateFrame("EventFrame", nil, v, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, -4)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 0, 2)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
	scroll:SetPanExtent(ROW_H)
	scroll:EnableMouseWheel(true)
	v.Scroll, v.Content, v.Bar = scroll, content, bar
	PlaceScroll(false)

	local note = v:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	note:SetPoint("TOP", 0, -40)
	note:SetText(NO_MATCH_NOTE)
	v.Note = note

	-- our Send Message / Group Invite, exactly over Blizzard's (which only
	-- ever act on Blizzard's own selection). Blizzard's pair overlaps the
	-- bottom of the Inset by a few pixels (buttons at y 16..44, the inset
	-- floor at 37), and our rows live two levels above this frame (scroll ->
	-- content -> row), so without a level of their own the buttons end up
	-- UNDER the list (Arc, 2026-09-28: "the send message and group invite
	-- button is behind our panels").
	local buttonLevel = v:GetFrameLevel() + 10
	local send = CreateFrame("Button", nil, v, "UIPanelButtonTemplate")
	send:SetFrameLevel(buttonLevel)
	send:SetAllPoints(frame.SendMessageButton)
	send:SetText(SEND_MESSAGE or "Send Message")
	send:SetScript("OnClick", function()
		local entry = SelectedEntry()
		if entry then OpenWhisperBox(entry.name) end
	end)
	local invite = CreateFrame("Button", nil, v, "UIPanelButtonTemplate")
	invite:SetFrameLevel(buttonLevel)
	invite:SetAllPoints(frame.GroupInviteButton)
	invite:SetText(GROUP_INVITE or "Group Invite")
	invite:SetScript("OnClick", function() InviteEntry(SelectedEntry(), invite) end)
	v.SendButton, v.InviteButton = send, invite

	v.hasDisplay = not (C_XMLUtil and C_XMLUtil.GetTemplateInfo)
		or C_XMLUtil.GetTemplateInfo(DISPLAY_TEMPLATE) ~= nil
	UpdateViewButtons()
end

-------------------------------------------------------------------------------
-- The Whispers section: the queue's rows, drawn by LayoutView above the
-- Players and Groups sections and collapsed by the same header
-------------------------------------------------------------------------------

function WQ.TimeAgo(at)
	local secs = GetTime() - (at or 0)
	if secs < 60 then return "just now" end
	if secs < 3600 then return math.floor(secs / 60) .. "m ago" end
	return math.floor(secs / 3600) .. "h ago"
end

-- Where they were when they whispered, and whether that is where you are
-- (Arc, 2026-09-28: "the current location of the people that whisper me, and
-- see if we can say close by or not"). Their zone comes from their own
-- listing, or from your friends list when they are on it.
function WQ.MyZone()
	return F.MyZone()
end

function WQ.AreaText(area)
	if type(area) ~= "string" or area == "" then return nil end
	if area == WQ.MyZone() then return "|cff40dd5a" .. area .. " (here)|r" end
	return area
end

function WQ.RoleIcons(roles)
	if type(roles) ~= "table" then return nil end
	local out = {}
	for _, role in ipairs(ROLES) do
		if roles[role.solo] then out[#out + 1] = Icon(ROLE_ATLAS[role.key]) end
	end
	if #out == 0 then return nil end
	return table.concat(out, " ")
end

-- name + what we know about them on the first line, their message on the
-- second, Reply / Invite and a dismiss x on the right
function WQ.NewRow()
	local row = CreateFrame("Frame", nil, view.Content)
	row:SetHeight(WQ.ROW_H)
	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Name:SetPoint("TOPLEFT", 10, -7)
	row.Meta = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Meta:SetPoint("LEFT", row.Name, "RIGHT", 8, 0)
	row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Text:SetPoint("BOTTOMLEFT", 10, 9)
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)

	local invite = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	invite:SetSize(64, 20)
	invite:SetPoint("BOTTOMRIGHT", -8, 6)
	invite:SetText(INVITE or "Invite")
	invite:SetScript("OnClick", function()
		local entry = row.entry
		if not entry then return end
		if F.Blocked() then return end
		local choices = F.NeedsRolePick(SoloListingOf(entry.name))
		if choices then
			NS.OpenPopup(invite, function(_, root)
				root:CreateTitle("Inviting " .. FirstName(entry.name) .. " as")
				for _, role in ipairs(choices) do
					root:CreateButton(role.label, function()
						F.pendingRole[entry.name] = role.label
						entry.invited = true
						Log("whisper queue: invited " .. entry.name .. " as " .. role.label)
						C_PartyInfo.InviteUnit(entry.name)
						WQ.Refresh()
					end)
				end
			end)
			return
		end
		entry.invited = true
		Log("whisper queue: " .. (F.MustSuggest() and "suggested " or "invited ") .. entry.name)
		C_PartyInfo.InviteUnit(entry.name)
		WQ.Refresh()
	end)
	local reply = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	reply:SetSize(58, 20)
	reply:SetPoint("RIGHT", invite, "LEFT", -4, 0)
	reply:SetText("Reply")
	reply:SetScript("OnClick", function()
		if row.entry then OpenWhisperBox(row.entry.name) end
	end)
	row.Text:SetPoint("RIGHT", reply, "LEFT", -8, 0)

	local dismiss = CreateFrame("Button", nil, row)
	dismiss:SetSize(16, 16)
	dismiss:SetPoint("TOPRIGHT", -8, -5)
	local x = dismiss:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	x:SetPoint("CENTER")
	x:SetText("x")
	dismiss:SetScript("OnEnter", function() x:SetTextColor(1, 0.82, 0) end)
	dismiss:SetScript("OnLeave", function() x:SetTextColor(0.5, 0.5, 0.5) end)
	dismiss:SetScript("OnClick", function() WQ.Drop(row.entry) end)

	local line = row:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.06)
	line:SetPoint("BOTTOMLEFT", 6, 0)
	line:SetPoint("BOTTOMRIGHT", -6, 0)
	line:SetHeight(1)

	row.InviteButton, row.ReplyButton, row.DismissButton = invite, reply, dismiss
	return row
end

function WQ.FillRow(row, entry)
	row.entry = entry
	local color = entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile]
	row.Name:SetText(entry.name)
	if color then
		row.Name:SetTextColor(color.r, color.g, color.b)
	else
		row.Name:SetTextColor(1, 1, 1)
	end
	local bits = {}
	if entry.level then bits[#bits + 1] = (LEVEL_ABBR or "Lvl") .. " " .. entry.level end
	if entry.className then bits[#bits + 1] = entry.className end
	local icons = WQ.RoleIcons(entry.roles)
	if icons then bits[#bits + 1] = icons end
	local where = WQ.AreaText(entry.area)
	if where then bits[#bits + 1] = where end
	bits[#bits + 1] = WQ.TimeAgo(entry.at)
	if entry.invited then bits[#bits + 1] = "invited" end
	row.Meta:SetText(table.concat(bits, "   "))
	row.Text:SetText(entry.text)
	row.InviteButton:SetText(F.InviteLabel(true))
	row.InviteButton:SetEnabled(not entry.invited and not F.Blocked())
	row:Show()
end



-- A whisper arriving or being answered redraws the list, coalesced.
function WQ.Refresh()
	RequestRebuild()
end

function WQ.Toggle()
	WQ.SetOn(not WQ.On())
	RebuildView()
	RefreshSettings()
end

-------------------------------------------------------------------------------
-- Menu
-------------------------------------------------------------------------------

-- A filter change starts the list from the top, and is remembered.
local function Changed()
	F.Save()
	if view then view.Scroll:SetVerticalScroll(0) end
	RebuildView()
end
F.Changed = Changed -- the per-class role toggles live above this point

local function IsRoleOn(key)
	return active[key] == true
end

local function ToggleRole(key)
	active[key] = not active[key] or nil
	Log("menu: " .. key .. " -> " .. (active[key] and "ON" or "off"))
	Changed()
end

local function IsShowMode(key)
	return showMode == key
end

local function SetShowMode(key)
	showMode = key
	Log("menu: show " .. key)
	Changed()
end

-- Keeps only listings standing in your zone, at their dungeon, or in the
-- zone that dungeon sits in. Groups are judged by their leader.
function F.ToggleNearby()
	F.nearby = not F.nearby
	Log("menu: only ones near me -> " .. (F.nearby and "ON" or "off"))
	if F.Changed then F.Changed() end
end

local function IsOpenSpotOn()
	return openSpotOnly
end

local function ToggleOpenSpot()
	openSpotOnly = not openSpotOnly
	Log("menu: groups with a spot for my role -> " .. (openSpotOnly and "ON" or "off"))
	Changed()
end

local function IsClassOn(classFile)
	return classActive[classFile] == true
end

local function ToggleClass(classFile)
	classActive[classFile] = not classActive[classFile] or nil
	Log("menu: class " .. classFile .. " -> " .. (classActive[classFile] and "ON" or "off"))
	Changed()
end

-- Any class clears the per-class roles with it: a role left on a class nobody
-- ticked keeps filtering while nothing on screen says so.
local function ClearClasses()
	wipe(classActive)
	wipe(F.classRoles)
	Log("menu: any class")
	Changed()
end

-- The lowest level a solo player may be (Arc, 2026-09-21: "I only want to see
-- people level 18+ or 50+"), typed into the menu's Minimum level box ("I want
-- this to be a user input"). Empty, 0 or 1 = any level.
local function MinLevelText()
	return minLevel and tostring(minLevel) or ""
end

local function SetMinLevel(text)
	local level = tonumber(text)
	level = (level and level > 1) and math.floor(level) or nil
	if level == minLevel then return end -- "0" after empty, "07" after "7"
	minLevel = level
	Log("menu: player level " .. (minLevel and (minLevel .. "+") or "any"))
	Changed()
end

-- Which roles a group must still have room for, and which it must already
-- have. Both read Blizzard's own member counts, the same source as "has a
-- spot for me" (Arc, 2026-09-23).
local function IsGroupNeed(key)
	return groupNeeds[key] == true
end

local function ToggleGroupNeed(key)
	groupNeeds[key] = not groupNeeds[key] or nil
	Log("menu: groups with an open spot for " .. key .. " -> " .. (groupNeeds[key] and "ON" or "off"))
	Changed()
end

local function ClearGroupNeeds()
	wipe(groupNeeds)
	Log("menu: groups with an open spot for any role")
	Changed()
end

local function IsGroupHas(key)
	return groupHas[key] == true
end

local function ToggleGroupHas(key)
	groupHas[key] = not groupHas[key] or nil
	Log("menu: groups that already have " .. key .. " -> " .. (groupHas[key] and "ON" or "off"))
	Changed()
end

local function ClearGroupHas()
	wipe(groupHas)
	Log("menu: groups with anyone in them")
	Changed()
end

-- Tank / Healer / DPS checkboxes wearing Blizzard's role icons.
local function AddRoleBoxes(menu, isOn, toggle)
	for _, role in ipairs(ROLES) do
		menu:CreateCheckbox(Icon(ROLE_ATLAS[role.key]) .. " " .. role.label, isOn, toggle, role.key)
	end
end

local function IsGroupClassHidden(classFile)
	return groupExclude[classFile] == true
end

local function ToggleGroupClass(classFile)
	groupExclude[classFile] = not groupExclude[classFile] or nil
	Log("menu: hide groups with " .. classFile .. " -> " .. (groupExclude[classFile] and "ON" or "off"))
	Changed()
end

local function ClearGroupClasses()
	wipe(groupExclude)
	Log("menu: groups with any class")
	Changed()
end

-- Every class this game has: the class lists always offer all of them, at 0
-- when nobody of a class is listed right now (Arc, 2026-09-21: "always show
-- all classes"). The list is Blizzard's own CLASS_SORT_ORDER, which the game
-- loads per game type (Forever's holds the nine classic classes). Counting
-- GetClassInfo up to GetNumClasses() left Druid out: Forever answers 9, but
-- class IDs have gaps and Druid is 11 (Arc: "when there is no druid available
-- I still want the option"). The ID walk is only a fallback.
local function GameClasses()
	local list, seen = {}, {}
	local function Add(classFile)
		if type(classFile) == "string" and not seen[classFile] then
			seen[classFile] = true
			list[#list + 1] = classFile
		end
	end
	if type(CLASS_SORT_ORDER) == "table" then
		for _, classFile in ipairs(CLASS_SORT_ORDER) do
			if not issecret(classFile) then Add(classFile) end
		end
	end
	if #list == 0 and GetClassInfo then
		for classID = 1, 30 do -- no count to stop at: the IDs have gaps
			local _, classFile = GetClassInfo(classID)
			if not issecret(classFile) then Add(classFile) end
		end
	end
	return list
end

local function MemberClass(resultID, index)
	local member = C_LFGList.GetSearchResultPlayerInfo(resultID, index)
	if not member or issecret(member) then return nil end
	local classFile = member.classFilename
	if issecret(classFile) then return nil end
	return classFile
end

-- A class list for a menu: every class the game has, plus any seen in the
-- results or already ticked (in case the game's list misses one), with
-- counts from the current (unfiltered) results - solo players for the
-- player list, groups with at least one member of the class for the group
-- list. Your own listing is not counted. Read-only.
local function ClassChoices(forGroups, ticked)
	local counts, order = {}, {}
	for _, classFile in ipairs(GameClasses()) do counts[classFile] = 0 end
	local _, results = C_LFGList.GetFilteredSearchResults()
	if results and not issecret(results) then
		for i = 1, #results do
			local id = results[i]
			local info = not issecret(id) and C_LFGList.GetSearchResultInfo(id)
			local members = info and not issecret(info) and Plain(info.numMembers)
			local hasSelf = info and not issecret(info) and Plain(info.hasSelf)
			if members and not hasSelf then
				if not forGroups and members == 1 then
					local classFile = MemberClass(id, 1)
					if classFile then counts[classFile] = (counts[classFile] or 0) + 1 end
				elseif forGroups and members > 1 then
					local seen = {}
					for m = 1, members do
						local classFile = MemberClass(id, m)
						if classFile and not seen[classFile] then
							seen[classFile] = true
							counts[classFile] = (counts[classFile] or 0) + 1
						end
					end
				end
			end
		end
	end
	for classFile in pairs(ticked) do counts[classFile] = counts[classFile] or 0 end
	for classFile in pairs(counts) do order[#order + 1] = classFile end
	return SortClasses(order), counts
end

-- Class-coloured checkboxes "Mage (2)" for one of the two class lists.
local function AddClassBoxes(menu, forGroups, ticked, isOn, toggle)
	local choices, counts = ClassChoices(forGroups, ticked)
	if #choices == 0 then
		menu:CreateTitle("No classes found")
	end
	for _, classFile in ipairs(choices) do
		local label = ClassLabel(classFile)
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
		if color and color.colorStr then label = "|c" .. color.colorStr .. label .. "|r" end
		-- the class icon Blizzard draws on its own listings, when it has one
		local atlas = "groupfinder-icon-class-" .. classFile:lower()
		if C_Texture.GetAtlasInfo(atlas) then label = Icon(atlas) .. " " .. label end
		local text = string.format("%s (%d)", label, counts[classFile])
		-- the roles picked for this class ride on its own line
		local picked = not forGroups and F.ClassRoles(classFile)
		if picked then
			local icons = {}
			for _, role in ipairs(ROLES) do
				if picked[role.key] then icons[#icons + 1] = Icon(ROLE_ATLAS[role.key]) end
			end
			text = text .. "  " .. table.concat(icons, " ")
		end
		local box = menu:CreateCheckbox(text, isOn, toggle, classFile)
		-- Hovering a class opens its own role list (Arc, 2026-10-11: "for this
		-- class I only want to see healer and tank"). Clicking still ticks the
		-- class itself; the group list has no roles to pick.
		if not forGroups then
			local any = box:CreateButton("Any role", F.ClearClassRoles, classFile)
			any:SetResponse(REFRESH)
			for _, role in ipairs(ROLES) do
				box:CreateCheckbox(Icon(ROLE_ATLAS[role.key]) .. " " .. role.label,
					F.IsClassRole, F.ToggleClassRole, classFile .. ":" .. role.key)
			end
		end
	end
end

local function ClearAll()
	wipe(active)
	wipe(classActive)
	wipe(groupExclude)
	wipe(F.mustClass)
	wipe(groupNeeds)
	wipe(groupHas)
	wipe(F.classRoles)
	showMode = "both"
	openSpotOnly = false
	minLevel = nil
	F.nearby = false
	Log("menu: reset filter")
	Changed()
end

-------------------------------------------------------------------------------
-- What the panel is allowed to touch (ALF_Panel.lua). The rules stay in this
-- file; the panel only reads and flips them through this one table, so it
-- never reaches into these locals and a rule has exactly one owner.
-------------------------------------------------------------------------------

NS.filter = {
	modes = SHOW_MODES, roles = ROLES, roleAtlas = ROLE_ATLAS,
	isMode = IsShowMode, setMode = SetShowMode,
	isRole = IsRoleOn, toggleRole = ToggleRole,
	classChoices = ClassChoices, classLabel = ClassLabel,
	isClass = IsClassOn, toggleClass = ToggleClass, clearClasses = ClearClasses,
	anyClass = AnyClassTicked,
	tickedClasses = function() return classActive end,
	hiddenClasses = function() return groupExclude end,
	isClassRole = function(classFile, key) return F.IsClassRole(classFile .. ":" .. key) end,
	toggleClassRole = function(classFile, key) F.ToggleClassRole(classFile .. ":" .. key) end,
	clearClassRoles = function(classFile) F.ClearClassRoles(classFile) end,
	-- "T H" for a class the roles are narrowed on, nil when it takes any role
	classRoleLetters = function(classFile)
		local set = classFile and F.ClassRoles(classFile)
		if not set then return nil end
		local out = {}
		for _, role in ipairs(ROLES) do
			if set[role.key] then out[#out + 1] = role.letter end
		end
		return table.concat(out, " ")
	end,
	minLevelText = MinLevelText, setMinLevel = SetMinLevel,
	isNearby = F.IsNearbyOn, toggleNearby = F.ToggleNearby, myZone = F.MyZone,
	isSpot = IsOpenSpotOn, toggleSpot = ToggleOpenSpot, myRolesText = MyRolesText,
	isNeed = IsGroupNeed, toggleNeed = ToggleGroupNeed,
	isHas = IsGroupHas, toggleHas = ToggleGroupHas,
	isHidden = IsGroupClassHidden, toggleHidden = ToggleGroupClass,
	classState = F.ClassState, cycleClass = F.CycleClass,
	anyClassState = F.AnyClassState, clearClassStates = F.ClearClassStates,
	isMine = F.IsMine, toggleMine = F.ToggleMine,
	whisperOn = WhisperOn, toggleWhisper = ToggleWhisper,
	queueOn = WQ.On, toggleQueue = WQ.Toggle,
	message = MessageTemplate, setMessage = SetTypedMessage, messageMax = MAX_TEMPLATE,
	quickSlots = QM.SLOTS, quickText = QM.Text, setQuickText = QM.Set,
	quickFirst = QM.First, setQuickFirst = QM.SetFirst,
	openSettings = ShowSettings,
	reset = ClearAll, status = StatusText, active = FilterActive,
	paused = function() return pausedReason ~= nil end,
	-- whether the panel was left open, so the window brings it back
	panelOpen = function() return (db and db.panel == true) and true or false end,
	setPanelOpen = function(on) if db then db.panel = on and true or nil end end,
	log = Log,
}

local function BuildMenu(owner, root)
	root:CreateTitle("Show")
	for _, mode in ipairs(SHOW_MODES) do
		local radio = root:CreateRadio(mode.label, IsShowMode, SetShowMode, mode.key)
		radio:SetResponse(REFRESH) -- stay open, like the checkboxes
	end
	root:CreateDivider()
	root:CreateTitle("Players signed up as")
	AddRoleBoxes(root, IsRoleOn, ToggleRole)
	-- Class submenu: combines with the role ticks (DPS + Mage = DPS mages).
	local classMenu = root:CreateButton(AnyClassTicked() and ("Class: " .. ClassNames(classActive)) or "Class: any")
	local anyClass = classMenu:CreateButton("Any class", ClearClasses)
	anyClass:SetResponse(REFRESH)
	AddClassBoxes(classMenu, false, classActive, IsClassOn, ToggleClass)
	-- Typed minimum level; combines with the rest. Empty = any level.
	root:CreateInput("Minimum level", MinLevelText, SetMinLevel,
		{ numeric = true, maxLetters = 2, placeholder = "any" })
	root:CreateCheckbox("Only ones near me", F.IsNearbyOn, F.ToggleNearby)
	root:CreateDivider()
	root:CreateTitle("Groups")
	root:CreateCheckbox("Has a spot for me (" .. MyRolesText() .. ")", IsOpenSpotOn, ToggleOpenSpot)
	-- Which roles a group still has room for: an open slot for ANY ticked role
	-- keeps it (Arc, 2026-09-23: "add a couple more options for groups").
	local needsMenu = root:CreateButton(AnyGroupNeeds()
		and ("Open spot for: " .. RoleNames(groupNeeds)) or "Open spot for: any")
	local anyNeed = needsMenu:CreateButton("Any role", ClearGroupNeeds)
	anyNeed:SetResponse(REFRESH)
	AddRoleBoxes(needsMenu, IsGroupNeed, ToggleGroupNeed)
	-- Which roles a group must already have: EVERY ticked role must be there
	local hasMenu = root:CreateButton(AnyGroupHas()
		and ("Already has: " .. RoleNames(groupHas)) or "Already has: anyone")
	local anyHas = hasMenu:CreateButton("Anyone", ClearGroupHas)
	anyHas:SetResponse(REFRESH)
	AddRoleBoxes(hasMenu, IsGroupHas, ToggleGroupHas)
	-- Hide groups that have anyone of a ticked class (Arc, 2026-09-21: "if I
	-- don't want a group that has a hunter, a rogue or a warrior").
	local groupMenu = root:CreateButton(AnyGroupExclusion()
		and ("Hide groups with: " .. ClassNames(groupExclude)) or "Hide groups with: none")
	local allGroups = groupMenu:CreateButton("Allow all classes", ClearGroupClasses)
	allGroups:SetResponse(REFRESH)
	AddClassBoxes(groupMenu, true, groupExclude, IsGroupClassHidden, ToggleGroupClass)
	root:CreateDivider()
	root:CreateTitle("Invites")
	root:CreateCheckbox("Whisper when I invite", WhisperOn, ToggleWhisper)
	root:CreateCheckbox("Whisper queue", WQ.On, WQ.Toggle)
	root:CreateButton("Edit invite message", ShowSettings)
	for _, extend in ipairs(NS.menuExtras) do extend(root) end
	root:CreateDivider()
	root:CreateButton("Reset filter", ClearAll)
	-- Built at the widest text so it never truncates; the initializer re-runs
	-- on every refresh, which keeps the line live.
	local status = root:CreateTitle(STATUS_WIDEST)
	status:AddInitializer(function(frame)
		frame.fontString:SetText(StatusText())
		if FilterActive() and pausedReason then
			frame.fontString:SetTextColor(1, 0.35, 0.35)
		else
			frame.fontString:SetTextColor(0.7, 0.7, 0.7)
		end
	end)
end

-- The active filter as one plain line per rule, for the button tooltip (the
-- debug log keeps the compact FilterSummary).
local function SummaryLines()
	local lines = {}
	if showMode == "players" then
		lines[#lines + 1] = "Show: players only"
	elseif showMode == "groups" then
		lines[#lines + 1] = "Show: groups only"
	end
	if showMode ~= "groups" then
		if AnyRoleTicked() then lines[#lines + 1] = "Players signed up as: " .. ActiveNames() end
		if AnyClassTicked() then lines[#lines + 1] = "Player classes: " .. ClassNames(classActive, true) end
		if minLevel then lines[#lines + 1] = "Player level: " .. minLevel .. "+" end
	end
	if showMode ~= "players" then
		if openSpotOnly then lines[#lines + 1] = "Groups with a spot for: " .. MyRolesText() end
		if AnyGroupNeeds() then lines[#lines + 1] = "Groups with an open spot for: " .. RoleNames(groupNeeds) end
		if AnyGroupHas() then lines[#lines + 1] = "Groups that already have: " .. RoleNames(groupHas) end
		if AnyGroupExclusion() then lines[#lines + 1] = "Hiding groups with: " .. ClassNames(groupExclude) end
		if next(F.mustClass) then lines[#lines + 1] = "Groups that must have: " .. ClassNames(F.mustClass) end
	end
	if F.nearby then
		lines[#lines + 1] = "Near me: " .. (F.MyZone() or "your zone") .. ", or at the dungeon"
	end
	return lines
end

-- Titled "Advanced Filter" (Arc, 2026-09-21): it filters groups as well as
-- players now, so "Player filter" undersold it.
local function ShowTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText("Advanced Filter", 1, 1, 1)
	if not FilterActive() then
		GameTooltip:AddLine("Filter players by role, class and level, show only players or only groups, find groups with a spot for your role, or hide groups that have a class you don't want.", nil, nil, nil, true)
	else
		for _, line in ipairs(SummaryLines()) do
			GameTooltip:AddLine(line, 1, 0.82, 0, true)
		end
		if pausedReason then
			GameTooltip:AddLine("Paused: Blizzard is not letting addons read the list right now, so the normal list is shown.", 1, 0.35, 0.35, true)
		else
			GameTooltip:AddLine(string.format("Showing %d of %d listings.", shownCount, totalCount), 1, 1, 1)
		end
	end
	if WhisperOn() then
		GameTooltip:AddLine("Invite whisper is on.", 0.25, 0.79, 0.95)
	end
	for _, add in ipairs(NS.tooltipExtras) do add(GameTooltip) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click to open the filter panel.", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

-- Read-only post-hook on Blizzard's UpdateResults: their results table is
-- final by now. Our list is rebuilt right here, in the same frame Blizzard
-- drew theirs, so their full list never shows for a frame before ours covers
-- it (a one-frame timer gave Arc "everyone, then poof" on every refresh).
-- Safe: hooksecurefunc hands the caller back its secure state after the
-- hook, and the rebuild only reads Blizzard's fields and writes our frames.
local function OnBlizzardRedraw()
	local frame = LFGBrowseFrame
	local results = frame.results
	if results and not issecret(results) then
		Log(string.format("blizzard: list rebuilt, %d listings (searching=%s)", #results, S(frame.searching)))
	end
	RebuildView()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "GROUP_ROSTER_UPDATE" then
		UpdateViewButtons()
	elseif FilterActive() then
		RequestRebuild()
	end
end)

local function Setup()
	local frame = LFGBrowseFrame
	if frames.button then return end
	if not (frame and frame.RefreshButton and frame.Inset and frame.SendMessageButton and frame.GroupInviteButton) then
		Log("setup: the Looking For Group browse frame is not what this addon expects - nothing installed")
		return
	end

	hooksecurefunc(frame, "UpdateResults", OnBlizzardRedraw)
	BuildView(frame)
	for _, event in ipairs({ "LFG_LIST_SEARCH_RESULT_UPDATED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
		if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
			events:RegisterEvent(event)
		end
	end

	-- Same square art, size and press nudge as Blizzard's refresh button.
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(32, 32)
	button:SetPoint("LEFT", frame.RefreshButton, "RIGHT", -2, 0)
	button:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	local icon = button:CreateTexture(nil, "ARTWORK", nil, 5)
	icon:SetSize(16, 16)
	icon:SetPoint("CENTER", button, "CENTER", -1, 0)
	local hasFunnel = C_Texture.GetAtlasInfo(FILTER_ATLAS) ~= nil
	icon:SetAtlas(hasFunnel and FILTER_ATLAS or FALLBACK_ATLAS, false)
	button.Icon = icon

	local badge = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 5)
	badge:Hide()
	button.Badge = badge

	button:SetScript("OnMouseDown", function(self) self.Icon:SetPoint("CENTER", self, "CENTER", -2, -1) end)
	button:SetScript("OnMouseUp", function(self) self.Icon:SetPoint("CENTER", self, "CENTER", -1, 0) end)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(self, mouseButton)
		GameTooltip_Hide()
		-- right-click still opens the old menu: a fallback while the panel is
		-- new, and our own menu, never Blizzard's (see "Popup menus")
		if mouseButton == "RightButton" then
			if PopupOpenFor(self) then
				ClosePopup()
			else
				NS.OpenPopup(self, BuildMenu)
			end
			return
		end
		ClosePopup()
		if NS.Panel then NS.Panel.Toggle() end
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	frames.button = button

	-- The options panel, docked to the window. It is our own frame: the
	-- window is never resized, re-anchored or written to.
	if NS.Panel then
		NS.Panel.Build(frame)
		frame:HookScript("OnShow", NS.Panel.OnWindowShown)
		frame:HookScript("OnHide", NS.Panel.OnWindowHidden)
		if LFGParentFrame then
			LFGParentFrame:HookScript("OnShow", NS.Panel.OnWindowShown)
			LFGParentFrame:HookScript("OnHide", NS.Panel.OnWindowHidden)
		end
		if frame:IsShown() then NS.Panel.OnWindowShown() end
	end

	Log(string.format("setup: own list built (role display=%s), read-only hook on UpdateResults; funnel icon=%s",
		S(view.hasDisplay), S(hasFunnel)))
	Log("setup: classes the game lists: " .. table.concat(GameClasses(), ", "))
end

-- Our own ADDON_LOADED brings the saved settings; the Looking For Group UI is
-- load-on-demand and gets its button whenever it arrives.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
	if name == ADDON then
		LoadSettings()
	elseif name == "Blizzard_GroupFinder_VanillaStyle" then
		Setup()
	end
	if db and frames.button then self:UnregisterEvent("ADDON_LOADED") end
end)
if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder_VanillaStyle") then
	Setup()
end

-- Invites: a post-hook, so the invite itself always runs first, untouched.
if C_PartyInfo and C_PartyInfo.InviteUnit then
	hooksecurefunc(C_PartyInfo, "InviteUnit", OnInviteUnit)
end

-- The read-only API a companion addon uses (see NS.menuExtras at the top):
-- judge a listing with the current filter, ask whether any player rule is
-- set, whisper someone it just invited, and write to the debug log.
NS.Verdict = Verdict
NS.HasPlayerRules = HasPlayerRules
NS.FilterSummary = FilterSummary
NS.WhisperInvite = function(name) WhisperInvitee(name, true) end
NS.ActivityName = ActivityName
NS.Log = Log

-- /arclfg          open the settings window (invite whisper)
-- /arclfg debug    open the debug log
-- /arclfg snap     open the debug log and take a snapshot of every listing
SLASH_ARCLFG1 = "/arclfg"
SlashCmdList.ARCLFG = function(msg)
	msg = (msg or ""):lower()
	if msg:match("snap") then
		ShowPanel()
		Snapshot("/arclfg snap")
	elseif msg:match("debug") or msg:match("log") then
		ShowPanel()
	else
		ShowSettings()
	end
end
