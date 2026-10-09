-- AD_OptionsLoader: the options window's first build, run a slice per frame
-- behind a small loading bar, so opening the panel never stalls the game; then
-- the editors' panes, built in the background in small slices (Options.Prebuild).
-- AD_Options hands its build to Loader.Start and pauses through Options.BuildYield
-- and Options.BuildStep; Loader.Then queues what waits for the window.
local ADDON, NS = ...
local Options = NS.Options
local AT = NS.AT
local COL = AT.COL

local Loader = {}
Options.Loader = Loader

-- Build time per frame; the rest of the frame stays the game's. A build the
-- player waits on takes SLICE_MS, a background one BG_MS, which the frame
-- rate does not feel.
local SLICE_MS = 12
local BG_MS = 3
local VIEW_W, VIEW_H = 300, 84

local step, co              -- the build while it runs: the resumer and its thread
local stepping = false      -- still set on the next frame = the last slice raised
local sliceStart = 0
local after = {}            -- work that waits for the window
local driver, view
local bg, hurried = false, false   -- a background build, and a pick waiting on it

-- force: end the slice now (a background build yields after each pane, so a
-- pick waiting on that pane opens on the next frame)
function Options.BuildYield(force)
    if not (co and coroutine.running() == co) then return end
    local limit = (bg and not hurried) and BG_MS or SLICE_MS
    if force or debugprofilestop() - sliceStart >= limit then
        coroutine.yield()
    end
end

function Options.BuildStep(i, n)
    if not (co and coroutine.running() == co) then return end
    Loader.Paint(i, n)
    Options.BuildYield()
end

local function EnsureView()
    if view then return view end
    view = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    view:SetSize(VIEW_W, VIEW_H)
    view:SetPoint("CENTER", 0, 40)
    -- above the options window (DIALOG, raised on every click), never behind it
    view:SetFrameStrata("FULLSCREEN_DIALOG")
    AT.Skin(view, COL.bg, COL.line2)
    local title = view:CreateFontString(nil, "OVERLAY")
    title:SetFont(AT.FONT, 14, "")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(AT.Brand("Arc", " Auras"))
    local status = view:CreateFontString(nil, "OVERLAY")
    status:SetFont(AT.FONT, 11, "")
    status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    status:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    status:SetText("Loading options")
    local track = CreateFrame("Frame", nil, view, "BackdropTemplate")
    track:SetPoint("BOTTOMLEFT", 12, 12)
    track:SetPoint("BOTTOMRIGHT", -12, 12)
    track:SetHeight(8)
    AT.Skin(track, COL.well, COL.line)
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(COL.fill[1], COL.fill[2], COL.fill[3], 1)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetWidth(1)
    view.fill = fill
    view.fillW = VIEW_W - 24 - 2
    view:Hide()
    return view
end

function Loader.Paint(i, n)
    if not view then return end
    local pct = (n and n > 0) and math.min(1, math.max(0, i / n)) or 0
    view.fill:SetWidth(math.max(1, view.fillW * pct))
end

function Loader.Stop()
    if driver then driver:SetScript("OnUpdate", nil) end
    if view then view:Hide() end
    step, co = nil, nil
    bg, hurried = false, false
end

local function Tick()
    if stepping then
        -- the last slice raised (the error handler has it): stop, do not retry
        stepping = false
        after = {}
        Loader.Stop()
        return
    end
    -- a background build waits out combat (the window is shut in combat)
    if bg and InCombatLockdown() then return end
    stepping = true
    sliceStart = debugprofilestop()
    local finished = step()
    stepping = false
    if finished then
        Loader.Stop()
        local run = after
        after = {}
        for _, fn in ipairs(run) do fn() end
    end
    -- outside the build: the picks whose pane now exists open
    if Loader.OnSlice then Loader.OnSlice() end
end

-- Starts `build` as a coroutine resumed once per frame. coroutine.wrap lets an
-- error in the build reach the normal error handler, nothing catches it.
-- quiet: a pane built after the first open, so no bar. background: small
-- slices until Hurry (a pick waits on it).
function Loader.Start(build, quiet, background)
    if step then return end
    step = coroutine.wrap(function()
        co = coroutine.running()
        build()
        return true
    end)
    bg, hurried = background == true, false
    Loader.quiet = quiet == true
    -- the bar is the first open's only; a quiet build leaves it as it was
    if not Loader.quiet then
        Options.ApplySavedScale()
        EnsureView()
        view:SetScale(AT.FitScale(VIEW_W, VIEW_H))
        Loader.Paint(0, 1)
        view:Show()
    elseif view then
        view:Hide()
    end
    driver = driver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", Tick)
end

function Loader.Busy() return step ~= nil end
function Loader.InBuild() return co ~= nil and coroutine.running() == co end
function Loader.Background() return step ~= nil and bg end
-- a pick waits on the background build: full slices until it opens
function Loader.Hurry() if bg then hurried = true end end
function Loader.Calm() hurried = false end

function Loader.Then(fn)
    after[#after + 1] = fn
    -- a new open after a cancel shows the bar again
    if step and view and not Loader.quiet then view:Show() end
end

-- The player closed it while it loaded: drop the queued work, keep building
-- so the next open is instant.
function Loader.Cancel()
    after = {}
    if view then view:Hide() end
    if Loader.OnCancel then Loader.OnCancel() end
end
