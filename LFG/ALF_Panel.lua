local ADDON, NS = ...

-------------------------------------------------------------------------------
-- The filter's options as a panel attached to the Looking For Group window,
-- built the way that window is built so it reads as a pane of it:
--   DefaultPanelTemplate   the frame itself (the window is a PortraitFrame of
--                          the same family: gold nine-slice, rock, title bar)
--   groupfinder-Stat-StoneBG  the stone strip across the top, as the window
--                          lays over its own dropdown row
--   InsetFrameTemplate + groupfinder-background  the sunken body below it,
--                          the window's list area in the same two pieces
--   groupfinder-ScrollLine the only two rules the window draws: under the
--                          strip and above the bottom buttons
--   LFGListingRoleButtonTemplate  copied for the role toggles: role icon with
--                          a tick box in its corner, from the Listing tab
--   common-sidetab         the fourth tab on the window's own tab strip
-- One tab per job: player rules, group rules, invites. The rules all live in
-- NS.filter: this file draws them and decides nothing.
-------------------------------------------------------------------------------

local SP = {}
NS.Panel = SP

local PANEL_W  = 320 -- the pane itself, right of the window's side tabs
local TAB_GAP  = 37  -- fallback channel for the side tabs, measured at build
local OVERLAP  = 6   -- how far the pane tucks under the window's own border
local PAD      = 10  -- inside the frame's border
local STRIP_H  = 86  -- the stone strip at the top, like the window's
local TABS_H   = 24  -- the row of tabs under it
local FOOT_H   = 44  -- the footer under the body
local ROW_H    = 26
local ROLE_H   = 30
local HDR_H    = 22
local GAP      = 5   -- before a section header
local LINE_H   = 24  -- a class line
local NAME_W   = 76

local STONE_BG = "groupfinder-Stat-StoneBG"
local BODY_BG  = "groupfinder-background"
local LINE_ART = "groupfinder-ScrollLine"

-- the checkbox art Blizzard's own role buttons use
local CB_UP    = "Interface\\Buttons\\UI-CheckBox-Up"
local CB_DOWN  = "Interface\\Buttons\\UI-CheckBox-Down"
local CB_HI    = "Interface\\Buttons\\UI-CheckBox-Highlight"
local CB_CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local HOVER    = "Interface\\Buttons\\UI-Common-MouseHilight"
local PASS_ART = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local TAB_ART  = "common-sidetab"
local TAB_MASK = "common-sidetab-mask"
local TAB_SEL  = "common-sidetab-selected"
local TAB_HI   = "common-sidetab-hover"
local ROW_HI   = "groupfinder-highlightbar-blue"
-- The tab has art of its own, drawn full bleed for the shape a tab shows. The
-- framed logo in Media\\ArcLFGFilter_Icon is the addon list's (toc IconTexture).
local TAB_ICON = "Interface\\AddOns\\ArcAuras_LFG\\Media\\ArcLFGFilter_Tab"

SP.strip = {}  -- the rows on the stone, above the tabs
SP.rows = {}   -- the rows inside the body, in order
SP.syncs = {}  -- one per control: re-reads the filter into the widget
SP.tab = "players"

local function Filter()
	return NS.filter
end

-- One of the window's side tabs: their size comes from the tab art at
-- runtime, so the channel they hang in is measured, never guessed.
local function SideTab()
	local parent = LFGParentFrame
	return parent and (parent.BrowsingTab or parent.ListingTab or parent.WhoListingTab) or nil
end

local function TabChannel()
	local tab = SideTab()
	local w = tab and tab.GetWidth and tab:GetWidth()
	if type(w) ~= "number" or w < 20 or w > 80 then return TAB_GAP end
	return math.floor(w)
end

-------------------------------------------------------------------------------
-- Small builders. Each returns a widget and, where it holds a value, adds its
-- own sync so a filter change from anywhere lands back in the panel.
-------------------------------------------------------------------------------

-- title may be a function, for a widget whose subject changes (a class icon)
function SP.Tip(owner, title, body)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(title) == "function" and title(self) or title)
		if body then GameTooltip:AddLine(type(body) == "function" and body(self) or body, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", GameTooltip_Hide)
end

-- The window's own rule, for the two places it draws one.
function SP.Rule(parent)
	local line = parent:CreateTexture(nil, "ARTWORK")
	if C_Texture.GetAtlasInfo(LINE_ART) then
		line:SetAtlas(LINE_ART, true)
	else
		line:SetColorTexture(0.5, 0.42, 0.28, 0.5)
		line:SetHeight(1)
	end
	return line
end

-- A tick box. Mouse off by default: the row or icon it sits on is the hit
-- area, the way the window's own role buttons work.
function SP.Tick(parent, size)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(size, size)
	c:EnableMouse(false)
	c:SetNormalTexture(CB_UP)
	c:SetPushedTexture(CB_DOWN)
	c:SetHighlightTexture(CB_HI, "ADD")
	c:SetCheckedTexture(CB_CHECK)
	return c
end

-- A wide row wants the window's own list bar, not the round button glow: the
-- glow stretched across a row reads as a laser beam.
function SP.Hover(frame, left, right)
	local hover = frame:CreateTexture(nil, "HIGHLIGHT")
	if C_Texture.GetAtlasInfo(ROW_HI) then
		hover:SetAtlas(ROW_HI, false)
		hover:SetAlpha(0.6)
	else
		hover:SetTexture(HOVER)
		hover:SetBlendMode("ADD")
	end
	hover:SetPoint("TOPLEFT", left or frame, left and "TOPRIGHT" or "TOPLEFT", 0, 0)
	hover:SetPoint("BOTTOMRIGHT", right or frame, "BOTTOMRIGHT", 0, 0)
	return hover
end

-- A row is a frame the layout stacks inside the body (or on the strip).
function SP.Row(height, onStrip)
	local list = onStrip and SP.strip or SP.rows
	local row = CreateFrame("Frame", nil, onStrip and SP.frame or SP.body)
	row:SetHeight(height or ROW_H)
	row._h = height or ROW_H
	row._tab = (not onStrip) and SP.building or nil
	list[#list + 1] = row
	return row
end

function SP.Gap()
	local row = SP.Row(GAP)
	row._spacer = true
	return row
end

-- A section header: gold, the size the game writes its own headers.
function SP.Header(text, onStrip)
	local row = SP.Row(HDR_H, onStrip)
	local fs = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("BOTTOMLEFT", 0, 3)
	fs:SetText(text)
	row.Text = fs
	return row
end

function SP.Label(row, text, font)
	local fs = row:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	fs:SetPoint("LEFT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(text)
	return fs
end

-- A one-line note under a control, dim and small.
function SP.Note(text)
	local row = SP.Row(16)
	local fs = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	fs:SetPoint("LEFT", 0, 0)
	fs:SetPoint("RIGHT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(text)
	row.Text = fs
	return row
end

-- The game's own checkbox with the label right of it.
function SP.Check(text, get, set, tip)
	local row = SP.Row()
	local hit = CreateFrame("Button", nil, row)
	hit:SetPoint("TOPLEFT")
	hit:SetPoint("BOTTOMRIGHT")
	local box = SP.Tick(hit, 22)
	box:SetPoint("LEFT", 0, 0)
	local fs = hit:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", box, "RIGHT", 4, 0)
	fs:SetPoint("RIGHT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(text)
	SP.Hover(hit, box)
	hit:SetScript("OnClick", function()
		PlaySound(box:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
			or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		set()
	end)
	if tip then SP.Tip(hit, text, tip) end
	row.Box, row.Text, row.Hit = box, fs, hit
	SP.syncs[#SP.syncs + 1] = function() box:SetChecked(get() and true or false) end
	return row
end

-- A role icon with a tick box in its corner: LFGListingRoleButtonTemplate,
-- the picker the window's own Listing tab uses, at panel size.
function SP.RoleToggle(parent, atlas, get, set, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(36, ROLE_H)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(26, 26)
	icon:SetPoint("TOPRIGHT")
	if atlas then icon:SetAtlas(atlas, false) end
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetTexture(HOVER)
	hover:SetBlendMode("ADD")
	hover:SetAllPoints(icon)
	local box = SP.Tick(b, 20)
	box:SetPoint("BOTTOMLEFT", 0, 0)
	b:SetScript("OnClick", function()
		PlaySound(box:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
			or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		set()
	end)
	if tip then SP.Tip(b, tip) end
	b.Icon, b.Box = icon, box
	b.Sync = function()
		local on = get() and true or false
		box:SetChecked(on)
		icon:SetDesaturated(not on)
		icon:SetAlpha(on and 1 or 0.6)
	end
	SP.syncs[#SP.syncs + 1] = b.Sync
	return b
end

-- Tank / Healer / DPS on the right of a labelled row.
function SP.RoleRow(text, get, set)
	local row = SP.Row(ROLE_H)
	if text then row.Text = SP.Label(row, text) end
	local F = Filter()
	local prev
	row.icons = {}
	for i = #F.roles, 1, -1 do
		local role = F.roles[i]
		local b = SP.RoleToggle(row, F.roleAtlas[role.key],
			function() return get(role.key) end, function() set(role.key) end, role.label)
		if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", 0, 0) end
		prev = b
		row.icons[#row.icons + 1] = b
	end
	return row
end

function SP.Button(parent, text, w, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- The class icon Blizzard draws on its own listings, when it has one.
function SP.ClassIcon(texture, classFile)
	local atlas = "groupfinder-icon-class-" .. classFile:lower()
	if C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas, false)
		texture:Show()
	else
		texture:Hide()
	end
end

-------------------------------------------------------------------------------
-- The two class lists. On the Players tab a line is: tick the class, then the
-- roles you want FROM that class, on the same line. On the Groups tab one
-- line answers three ways: any, the group must hold one, hide groups with one.
-------------------------------------------------------------------------------

function SP.ClassLine(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(10, LINE_H)
	local box = SP.Tick(b, 20)
	box:SetPoint("LEFT", 0, 0)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("LEFT", box, "RIGHT", 4, 0)
	local name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	name:SetWidth(NAME_W)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	local count = b:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	count:SetPoint("RIGHT", -2, 0)
	count:SetWidth(24)
	count:SetJustifyH("RIGHT")
	SP.Hover(b, box, count)
	b.Box, b.Icon, b.Name, b.Count = box, icon, name, count
	return b
end

-- the three role buttons that ride on a Players-tab class line
function SP.LineRoles(line)
	local F = Filter()
	local prev
	line.roles = {}
	for i = #F.roles, 1, -1 do
		local role = F.roles[i]
		local r = CreateFrame("Button", nil, line)
		r:SetSize(20, 20)
		local icon = r:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetAtlas(F.roleAtlas[role.key], false)
		local hover = r:CreateTexture(nil, "HIGHLIGHT")
		hover:SetTexture(HOVER)
		hover:SetBlendMode("ADD")
		hover:SetAllPoints()
		hover:SetAlpha(0.7)
		if prev then r:SetPoint("RIGHT", prev, "LEFT", -2, 0)
		else r:SetPoint("RIGHT", line.Count, "LEFT", -4, 0) end
		r.Icon, r.roleKey = icon, role.key
		r:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Filter().toggleClassRole(line.classFile, self.roleKey)
			SP.Refresh()
		end)
		SP.Tip(r, function() return role.label end,
			function(self) return "Only " .. role.label .. "s of this class." end)
		prev = r
		line.roles[#line.roles + 1] = r
	end
end

function SP.FillClassLine(line, classFile, count, ticked)
	local F = Filter()
	line.classFile = classFile
	line.Name:SetText(F.classLabel(classFile))
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color then line.Name:SetTextColor(color.r, color.g, color.b) else line.Name:SetTextColor(1, 1, 1) end
	line.Name:SetAlpha(ticked and 1 or 0.75)
	line.Count:SetText(count)
	SP.ClassIcon(line.Icon, classFile)
	line.Icon:SetDesaturated(not ticked)
	line.Icon:SetAlpha(ticked and 1 or 0.6)
	line.Box:SetChecked(ticked)
	for _, r in ipairs(line.roles or {}) do
		local on = F.isClassRole(classFile, r.roleKey)
		r.Icon:SetDesaturated(not on)
		r.Icon:SetAlpha(on and 1 or 0.35)
	end
	line:Show()
end

function SP.FillStateLine(line, classFile, count)
	local F = Filter()
	local state = F.classState(classFile)
	line.classFile = classFile
	line.Name:SetText(F.classLabel(classFile))
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color then line.Name:SetTextColor(color.r, color.g, color.b) else line.Name:SetTextColor(1, 1, 1) end
	line.Name:SetAlpha(state == "any" and 0.75 or 1)
	line.Count:SetText(count)
	SP.ClassIcon(line.Icon, classFile)
	line.Icon:SetDesaturated(state == "any")
	line.Icon:SetAlpha(state == "any" and 0.6 or 1)
	line.Box:SetChecked(state == "must")
	line.Cross:SetShown(state == "hide")
	line.State:SetText(state == "must" and "must have" or (state == "hide" and "hidden" or ""))
	if state == "must" then
		line.State:SetTextColor(0.37, 0.83, 0.48)
	else
		line.State:SetTextColor(0.88, 0.66, 0.61)
	end
	line:Show()
end

-------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------

function SP.Build(window)
	if SP.frame or not window then return end
	-- the pane hangs off the whole Group Finder, so it and its tab are there
	-- the moment the window opens, whichever of its own tabs is up
	window = LFGParentFrame or window
	local F = Filter()
	if not F then return end

	local gap = TabChannel()
	SP.tabGap = gap
	SP.contentX = OVERLAP + gap + PAD

	-- The frame: the game's own panel, starting under the window's right
	-- border and running behind the side tabs so the two read as one piece.
	-- A frame level below the tabs leaves them the clicks and the front.
	local p = CreateFrame("Frame", "ArcLFGFilterPanel", window, "DefaultPanelTemplate")
	p:SetPoint("TOPLEFT", window, "TOPRIGHT", -OVERLAP, 0)
	p:SetWidth(OVERLAP + gap + PANEL_W)
	p:SetHeight(window:GetHeight())
	p:EnableMouse(true)
	local tab = SideTab()
	local level = (tab and tab.GetFrameLevel and tab:GetFrameLevel()) or (window:GetFrameLevel() + 1)
	p:SetFrameLevel(math.max(0, level - 1))
	p:Hide()
	SP.frame = p

	if p.SetTitle then
		p:SetTitle("Arc Filter")
	elseif p.TitleContainer and p.TitleContainer.TitleText then
		p.TitleContainer.TitleText:SetText("Arc Filter")
	end
	if p.SetTitleOffsets then p:SetTitleOffsets(SP.contentX, -24) end

	local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() SP.Toggle(false) end)

	-- the stone the window lays over its own frame rock, across the top strip
	local stone = p:CreateTexture(nil, "BACKGROUND", nil, -5)
	if C_Texture.GetAtlasInfo(STONE_BG) then
		stone:SetAtlas(STONE_BG, false)
		stone:SetPoint("TOPLEFT", 3, -21)
		stone:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", -3, -STRIP_H)
	end

	-- the body: the window's own sunken inset with its background art inside
	local body = CreateFrame("Frame", nil, p, "InsetFrameTemplate")
	body:SetPoint("TOPLEFT", SP.contentX - PAD - 4, -(STRIP_H + TABS_H))
	body:SetPoint("BOTTOMRIGHT", -6, FOOT_H)
	SP.body = body
	local art = body:CreateTexture(nil, "BACKGROUND", nil, -4)
	if C_Texture.GetAtlasInfo(BODY_BG) then
		art:SetAtlas(BODY_BG, false)
		art:SetPoint("TOPLEFT", 3, -3)
		art:SetPoint("BOTTOMRIGHT", -3, 3)
		art:SetAlpha(0.8)
	end

	-- the only two rules the window draws: under the strip, above the buttons
	local barTop = SP.Rule(p)
	barTop:SetPoint("TOPLEFT", 4, -STRIP_H + 2)
	barTop:SetPoint("TOPRIGHT", -4, -STRIP_H + 2)
	local barFoot = SP.Rule(p)
	barFoot:SetPoint("BOTTOMLEFT", 4, FOOT_H - 4)
	barFoot:SetPoint("BOTTOMRIGHT", -4, FOOT_H - 4)

	-- The strip: Show, where the window keeps its own dropdowns.
	SP.Header("Show", true)
	local showRow = SP.Row(ROW_H, true)
	SP.showButtons = {}
	local prevShow
	for i, mode in ipairs(F.modes) do
		local b = CreateFrame("CheckButton", nil, showRow, "UIRadioButtonTemplate")
		b:SetSize(16, 16)
		local fs = showRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
		fs:SetText(mode.short)
		fs:SetWordWrap(false)
		b.Text = fs
		if prevShow then
			b:SetPoint("LEFT", prevShow.Text, "RIGHT", 14, 0)
		else
			b:SetPoint("LEFT", 0, 0)
		end
		b:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			F.setMode(mode.key)
			SP.Refresh()
		end)
		SP.Tip(b, mode.label)
		SP.showButtons[i] = b
		prevShow = b
		local key = mode.key
		SP.syncs[#SP.syncs + 1] = function() b:SetChecked(F.isMode(key)) end
	end

	-- The tabs: one per job, in the game's own folder-tab art, sitting on the
	-- body's top edge the way its top tabs do.
	SP.tabs = {}
	local hasTabArt = (not C_XMLUtil) or (not C_XMLUtil.GetTemplateInfo)
		or C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate") ~= nil
	local prevTab
	for i, info in ipairs({ { "players", "Players" }, { "groups", "Groups" }, { "invites", "Invites" } }) do
		local key, label = info[1], info[2]
		local b = CreateFrame("Button", nil, p, hasTabArt and "PanelTopTabButtonTemplate" or "UIPanelButtonTemplate")
		b:SetSize(94, TABS_H)
		if prevTab then b:SetPoint("BOTTOMLEFT", prevTab, "BOTTOMRIGHT", 2, 0)
		else b:SetPoint("BOTTOMLEFT", p, "TOPLEFT", SP.contentX - PAD, -(STRIP_H + TABS_H) + 2) end
		b:SetText(label)
		b.tabKey, b.label = key, label
		b:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SP.tab = key
			SP.Refresh()
		end)
		SP.tabs[i] = b
		prevTab = b
	end

	-- ---------------------------------------------------------------- players
	SP.building = "players"
	SP.RoleRow("Signed up as", F.isRole, function(key)
		F.toggleRole(key)
		SP.Refresh()
	end)

	local levelRow = SP.Row()
	SP.Label(levelRow, "Minimum level")
	local box = CreateFrame("EditBox", nil, levelRow, "InputBoxTemplate")
	box:SetSize(44, 22)
	box:SetPoint("RIGHT", -4, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(2)
	box:SetJustifyH("CENTER")
	box:SetScript("OnTextChanged", function(self, byUser)
		if byUser then F.setMinLevel(self:GetText()) end
	end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	SP.Tip(box, "Minimum level", "Type a level to hide anyone under it. Empty shows every level.")
	SP.levelBox = box
	SP.syncs[#SP.syncs + 1] = function()
		if not box:HasFocus() then box:SetText(F.minLevelText()) end
	end

	SP.nearRow = SP.Check("Only ones near me", F.isNearby, function()
		F.toggleNearby()
		SP.Refresh()
	end, "Keeps players standing in your zone, and groups whose leader is, plus anyone at the dungeon they listed for.")

	SP.Gap()
	local classHeader = SP.Header("Class")
	local anyClass = SP.Button(classHeader, "Any class", 76, function()
		F.clearClasses()
		SP.Refresh()
	end)
	anyClass:SetPoint("RIGHT", 0, 2)
	SP.Tip(anyClass, "Any class", "Clear every class and every role picked from one.")
	SP.syncs[#SP.syncs + 1] = function() anyClass:SetEnabled(F.anyClass()) end
	SP.classRows = {}
	SP.classBlock = SP.Row(LINE_H)

	-- ----------------------------------------------------------------- groups
	SP.building = "groups"
	SP.mineRow = SP.RoleRow("I am signed up as", F.isMine, function(key)
		F.toggleMine(key)
		SP.Refresh()
	end)
	SP.Note("Your own listing's roles, the ones the game uses")

	SP.spotRow = SP.Check("Has a spot for me", F.isSpot, function()
		F.toggleSpot()
		SP.Refresh()
	end, "Only groups with an open slot for a role you are signed up as.")
	SP.RoleRow("Open spot for", F.isNeed, function(key)
		F.toggleNeed(key)
		SP.Refresh()
	end)
	SP.RoleRow("Already has", F.isHas, function(key)
		F.toggleHas(key)
		SP.Refresh()
	end)

	SP.Gap()
	local stateHeader = SP.Header("Classes in the group")
	local anyState = SP.Button(stateHeader, "Any class", 76, function()
		F.clearClassStates()
		SP.Refresh()
	end)
	anyState:SetPoint("RIGHT", 0, 2)
	SP.Tip(anyState, "Any class", "Stop asking for or hiding any class.")
	SP.syncs[#SP.syncs + 1] = function() anyState:SetEnabled(F.anyClassState()) end
	SP.stateRows = {}
	SP.stateBlock = SP.Row(LINE_H)

	-- ---------------------------------------------------------------- invites
	SP.building = "invites"
	SP.whisperRow = SP.Check("Whisper when I invite", F.whisperOn, function()
		F.toggleWhisper()
		SP.Refresh()
	end, "Whisper the players you invite from this list.")

	SP.messageRow = SP.Row(24)
	SP.messageRow._visible = function() return F.whisperOn() end
	local msg = CreateFrame("EditBox", nil, SP.messageRow, "InputBoxTemplate")
	msg:SetPoint("LEFT", 28, 0)
	msg:SetPoint("RIGHT", -4, 0)
	msg:SetHeight(22)
	msg:SetAutoFocus(false)
	msg:SetMaxLetters(F.messageMax or 200)
	msg:SetScript("OnEnterPressed", function(self)
		F.setMessage(self:GetText())
		self:ClearFocus()
		SP.Refresh()
	end)
	msg:SetScript("OnEscapePressed", function(self)
		self:SetText(F.message())
		self:ClearFocus()
	end)
	SP.Tip(msg, "Invite message", "{dungeon}, {name} and {role}. Enter saves it.")
	SP.messageBox = msg
	SP.syncs[#SP.syncs + 1] = function()
		if not msg:HasFocus() then msg:SetText(F.message()) end
	end
	SP.msgNote = SP.Note("Sent to everyone you invite. {role}: one listed goes in, several and it asks")
	SP.msgNote._visible = function() return F.whisperOn() end

	SP.queueRow = SP.Check("Whisper queue", F.queueOn, function()
		F.toggleQueue()
		SP.Refresh()
	end, "Everyone who whispers you while your group is listed lands in a Whispers section at the top of the list.")

	SP.Gap()
	SP.Header("Quick messages")
	SP.quickRows = {}
	for i = 1, (F.quickSlots or 3) do
		local row = SP.Row()
		local pick = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
		pick:SetSize(16, 16)
		pick:SetPoint("LEFT", 2, 0)
		pick:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			F.setQuickFirst(i)
			SP.Refresh()
		end)
		SP.Tip(pick, "Send this one first", "It fills the Send Message box when it opens.")
		local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
		edit:SetPoint("LEFT", pick, "RIGHT", 10, 0)
		edit:SetPoint("RIGHT", -4, 0)
		edit:SetHeight(22)
		edit:SetAutoFocus(false)
		edit:SetMaxLetters(F.messageMax or 200)
		edit:SetScript("OnEnterPressed", function(self)
			F.setQuickText(i, self:GetText())
			self:ClearFocus()
			SP.Refresh()
		end)
		edit:SetScript("OnEscapePressed", function(self)
			self:SetText(F.quickText(i) or "")
			self:ClearFocus()
		end)
		SP.Tip(edit, "Quick message " .. i, "{level}, {class} and {role} fill themselves in.")
		row.Pick, row.Edit = pick, edit
		SP.quickRows[i] = row
		SP.syncs[#SP.syncs + 1] = function()
			pick:SetChecked(F.quickFirst() == i)
			if not edit:HasFocus() then edit:SetText(F.quickText(i) or "") end
		end
	end
	SP.Note("Edit a line, or tweak it in the box and send: the change is kept")
	SP.building = nil

	-- Footer: reset and the same status line the menu ended with, under the
	-- window's own bottom rule.
	local reset = SP.Button(p, "Reset filter", 104, function()
		F.reset()
		SP.Refresh()
	end)
	reset:SetPoint("BOTTOMLEFT", SP.contentX - PAD, 13)
	SP.Tip(reset, "Reset filter", "Clear every rule. Nothing is filtered until you turn something on.")
	SP.resetButton = reset
	local status = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	status:SetPoint("BOTTOMRIGHT", -PAD, 19)
	SP.status = status

	SP.BuildSideTab()
	SP.built = true
	F.log("panel: built, " .. #SP.rows .. " body rows, tab channel " .. gap)
end

-------------------------------------------------------------------------------
-- The fourth tab on the window's own strip. Blizzard's tab art, our icon, a
-- plain button: never their tab mixin, which drives their own tab switching.
-------------------------------------------------------------------------------

function SP.BuildSideTab()
	local parent = LFGParentFrame
	local under = parent and (parent.WhoListingTab or parent.BrowsingTab or parent.ListingTab)
	if not (parent and under) then return end
	local art = C_Texture.GetAtlasInfo(TAB_ART)
	local w = (art and art.width) or 36
	local h = (art and art.height and (art.height - 5)) or 38

	local tab = CreateFrame("Button", nil, parent)
	tab:SetSize(w, h)
	tab:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -2)
	local bg = tab:CreateTexture(nil, "BACKGROUND")
	if art then bg:SetAtlas(TAB_ART, true) end
	bg:SetAllPoints()
	-- The lit ring goes OVER the icon, not under it: the template puts
	-- SelectedTexture on OVERLAY while the icon is on ARTWORK, which is why a lit
	-- tab of the window's own shows the ring along both inner edges of its art.
	-- Under the icon it only surfaces where the icon stops short, which reads as
	-- a bare strip down one side. Its own atlas size, centred, as the template has.
	local selected = tab:CreateTexture(nil, "OVERLAY")
	if C_Texture.GetAtlasInfo(TAB_SEL) then selected:SetAtlas(TAB_SEL, true) end
	selected:SetPoint("CENTER")
	selected:Hide()
	-- The window's tabs do not draw their icon at its own size: LFGVanillaRightTab
	-- sets fillToInterior, so SidePanelTabButtonMixin.UpdateIconInterior blows the
	-- icon up to interiorExtent, 50, and lets the tab mask cut it back to the
	-- interior. That is why their art runs to the frame with no stone around it,
	-- and why an icon drawn at its own 30 sits in a ring of it. Same number here,
	-- same offset, and the mask at its own size, centred, as their template has it.
	local icon = tab:CreateTexture(nil, "ARTWORK")
	icon:SetSize(50, 50)
	icon:SetPoint("CENTER", -3, 0)
	icon:SetTexture(TAB_ICON)
	-- Their art is full bleed, so whatever survives the cut is picture and the
	-- trim is only the texture's own margin. Ours is drawn the same way now, so
	-- it takes the same trim: no crop, nothing of the file held back.
	icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
	local mask = C_Texture.GetAtlasInfo(TAB_MASK) and tab.CreateMaskTexture and tab:CreateMaskTexture()
	if mask and icon.AddMaskTexture then
		mask:SetAtlas(TAB_MASK, true)
		mask:SetPoint("CENTER")
		icon:AddMaskTexture(mask)
	end
	if C_Texture.GetAtlasInfo(TAB_HI) and tab.SetHighlightAtlas then
		tab:SetHighlightAtlas(TAB_HI)
	else
		tab:SetHighlightTexture(HOVER, "ADD")
	end
	tab:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		SP.Toggle()
	end)
	SP.Tip(tab, "Arc Filter", "Open the filter panel.")
	tab.Selected = selected
	tab.Icon = icon
	tab:Hide()
	SP.sideTab = tab
end

-- It belongs to the Browse tab, so it comes and goes with it: never a tab
-- that is there but does nothing.
function SP.UpdateSideTab()
	if not SP.sideTab then return end
	local window = SP.frame and SP.frame:GetParent()
	SP.sideTab:SetShown(window and window:IsShown() and true or false)
	SP.sideTab.Selected:SetShown(SP.IsOpen())
end

-------------------------------------------------------------------------------
-- Layout and refresh: one pass, so a row that hides takes its height with it
-- and the pane never ends up with a hole in it.
-------------------------------------------------------------------------------

function SP.LayoutClasses()
	local F = Filter()
	local list, counts = F.classChoices(false, F.tickedClasses())
	local shown = 0
	for i, classFile in ipairs(list) do
		local line = SP.classRows[i]
		if not line then
			line = SP.ClassLine(SP.classBlock)
			SP.LineRoles(line)
			line.Box:EnableMouse(true)
			line.Box:SetScript("OnClick", function()
				local filter = Filter()
				PlaySound(filter.isClass(line.classFile) and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
					or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				filter.toggleClass(line.classFile)
				if not filter.isClass(line.classFile) then filter.clearClassRoles(line.classFile) end
				SP.Refresh()
			end)
			line:SetScript("OnClick", function() line.Box:Click() end)
			SP.Tip(line, function() return Filter().classLabel(line.classFile) end,
				"Tick the class, then pick the roles you want from it on this line.")
			SP.classRows[i] = line
		end
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", SP.classBlock, "TOPLEFT", 0, -(i - 1) * LINE_H)
		line:SetPoint("TOPRIGHT", SP.classBlock, "TOPRIGHT", 0, -(i - 1) * LINE_H)
		SP.FillClassLine(line, classFile, counts[classFile] or 0, F.isClass(classFile))
		shown = i
	end
	for i = shown + 1, #SP.classRows do SP.classRows[i]:Hide() end
	SP.classBlock._h = math.max(LINE_H, shown * LINE_H)
	SP.classBlock:SetHeight(SP.classBlock._h)
end

function SP.LayoutStates()
	local F = Filter()
	local list, counts = F.classChoices(true, F.hiddenClasses())
	local shown = 0
	for i, classFile in ipairs(list) do
		local line = SP.stateRows[i]
		if not line then
			line = SP.ClassLine(SP.stateBlock)
			local cross = line:CreateTexture(nil, "OVERLAY")
			cross:SetTexture(PASS_ART)
			cross:SetSize(18, 18)
			cross:SetPoint("CENTER", line.Box, "CENTER")
			cross:Hide()
			local state = line:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			state:SetPoint("RIGHT", line.Count, "LEFT", -6, 0)
			line.Cross, line.State = cross, state
			line:SetScript("OnClick", function()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Filter().cycleClass(line.classFile)
				SP.Refresh()
			end)
			SP.Tip(line, function() return Filter().classLabel(line.classFile) end,
				"Click through: any, the group must have one, hide groups with one.")
			SP.stateRows[i] = line
		end
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", SP.stateBlock, "TOPLEFT", 0, -(i - 1) * LINE_H)
		line:SetPoint("TOPRIGHT", SP.stateBlock, "TOPRIGHT", 0, -(i - 1) * LINE_H)
		SP.FillStateLine(line, classFile, counts[classFile] or 0)
		shown = i
	end
	for i = shown + 1, #SP.stateRows do SP.stateRows[i]:Hide() end
	SP.stateBlock._h = math.max(LINE_H, shown * LINE_H)
	SP.stateBlock:SetHeight(SP.stateBlock._h)
end

function SP.Layout()
	-- the strip rows sit on the stone, above the tabs
	local y = -30
	for _, row in ipairs(SP.strip) do
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", SP.frame, "TOPLEFT", SP.contentX, y)
		row:SetPoint("TOPRIGHT", SP.frame, "TOPRIGHT", -PAD, y)
		row:SetHeight(row._h)
		row:Show()
		y = y - row._h
	end

	-- the open tab wears the game's active-tab art, the others its plain one
	for _, b in ipairs(SP.tabs) do
		local on = b.tabKey == SP.tab
		b._on = on
		if PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
			if on then PanelTemplates_SelectTab(b) else PanelTemplates_DeselectTab(b) end
		end
	end

	-- Spread, don't pile: measure the open tab's rows first, then hand
	-- whatever room is left over to the gaps between its sections.
	local window = SP.frame:GetParent()
	local room = (window and window:GetHeight() or 0) - STRIP_H - TABS_H - FOOT_H - 16
	local used, spacers = 0, 0
	for _, row in ipairs(SP.rows) do
		if SP.Visible(row) then
			used = used + row._h
			if row._spacer then spacers = spacers + 1 end
		end
	end
	local extra = 0
	if spacers > 0 and room > used then
		extra = math.min(20, math.floor((room - used) / spacers))
	end

	local by = -8
	for _, row in ipairs(SP.rows) do
		if SP.Visible(row) then
			local h = row._h + (row._spacer and extra or 0)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", SP.body, "TOPLEFT", 8, by)
			row:SetPoint("TOPRIGHT", SP.body, "TOPRIGHT", -8, by)
			row:SetHeight(h)
			row:Show()
			by = by - h
		else
			row:Hide()
		end
	end
	local needed = STRIP_H + TABS_H + (-by) + 8 + FOOT_H
	SP.frame:SetHeight(math.max(window and window:GetHeight() or 0, needed))
end

function SP.Visible(row)
	if row._tab and row._tab ~= SP.tab then return false end
	if row._visible and not row._visible() then return false end
	return true
end

function SP.Refresh()
	if not SP.built then return end
	-- nothing to draw while it is shut; Toggle and OnWindowShown refresh
	-- right after they show it, so it never comes back stale
	if not SP.frame:IsShown() then
		SP.UpdateSideTab()
		return
	end
	local F = Filter()
	if SP.tab == "players" then SP.LayoutClasses() end
	if SP.tab == "groups" then SP.LayoutStates() end
	for _, sync in ipairs(SP.syncs) do sync() end

	SP.spotRow.Text:SetText("Has a spot for me (" .. F.myRolesText() .. ")")

	SP.status:SetText(F.status())
	if F.active() and F.paused() then
		SP.status:SetTextColor(1, 0.35, 0.35)
	elseif F.active() then
		SP.status:SetTextColor(1, 0.82, 0) -- gold while a rule is on, like the window's own counts
	else
		SP.status:SetTextColor(0.7, 0.7, 0.7)
	end
	SP.Layout()
	SP.UpdateSideTab()
end

-------------------------------------------------------------------------------
-- Showing it
-------------------------------------------------------------------------------

function SP.IsOpen()
	return SP.frame and SP.frame:IsShown() and true or false
end

function SP.Toggle(show)
	if not SP.frame then return end
	if show == nil then show = not SP.IsOpen() end
	if show then
		SP.frame:Show() -- shown first: Refresh draws nothing while it is shut
		SP.Refresh()
	else
		SP.frame:Hide()
		SP.UpdateSideTab()
	end
	local F = Filter()
	if F then
		F.setPanelOpen(show)
		F.log("panel: " .. (show and "open" or "shut"))
	end
end

-- The window opening (or the Browse tab coming back) brings the panel with it
-- when it was left open, and the side tab with the window.
function SP.OnWindowShown()
	if not SP.frame then return end
	local F = Filter()
	if F and F.panelOpen() then
		SP.frame:Show()
		SP.Refresh()
	end
	SP.UpdateSideTab()
end

function SP.OnWindowHidden()
	SP.UpdateSideTab()
end
