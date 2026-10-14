-- AD_ImportArcUIRead: phase one of the Arc UI import. Reads an Arc UI v1 save the way Arc UI
-- itself loads it at the next login (its older shapes, its fallbacks, a shared profile's
-- pending pull) into one clean model the planner walks. Read-only on v1: values are copied
-- out, the save is never written.
local ADDON, NS = ...

local IA = NS.ImportArcUI or {}
NS.ImportArcUI = IA
IA.V1 = IA.V1 or {}

-- Arc UI's own default tables, generated from its source by tools\v1_source_tables.lua;
-- the import harness fails when they drift from it.
-- BEGIN GENERATED V1 TABLES
IA.V1.BAR_DEFAULTS = {
    behavior = {
        hideBuffIcon = false,
        hideOutOfCombat = false,
        hideWhenInactive = false,
        hideWhenZeroStacks = false,
        showOnSpec = 0,
        showOnSpecs = {},
    },
    colorRanges = {
        {
            color = {
                a = 1,
                b = 1,
                g = 0.5,
                r = 0,
            },
            from = 1,
            to = 4,
        },
        {
            color = {
                a = 1,
                b = 0,
                g = 1,
                r = 1,
            },
            enabled = false,
            from = 5,
            to = 8,
        },
        {
            color = {
                a = 1,
                b = 0,
                g = 1,
                r = 0,
            },
            enabled = false,
            from = 9,
            to = 12,
        },
    },
    display = {
        backgroundColor = {
            a = 0.8,
            b = 0.2,
            g = 0.2,
            r = 0.2,
        },
        barColor = {
            a = 1,
            b = 1,
            g = 0.5,
            r = 0,
        },
        barFrameLevel = 10,
        barFrameStrata = "MEDIUM",
        barIconAnchor = "LEFT",
        barIconAnchorOffsetX = 0,
        barIconAnchorOffsetY = 0,
        barIconBorderColor = {
            a = 1,
            b = 0,
            g = 0,
            r = 0,
        },
        barIconShowBorder = true,
        barIconSize = 32,
        barMovable = true,
        barOrientation = "horizontal",
        barPaddingB = 0,
        barPaddingL = 0,
        barPaddingR = 0,
        barPaddingT = 0,
        barPosition = {
            point = "CENTER",
            relPoint = "CENTER",
            x = 0,
            y = 200,
        },
        barReverseFill = false,
        barScale = 1.0,
        borderColor = {
            a = 1,
            b = 0,
            g = 0,
            r = 0,
        },
        borderStyle = "Drawn",
        displayMode = "single",
        displayType = "bar",
        drawnBorderThickness = 2,
        durationAnchor = "CENTER",
        durationAnchorOffsetX = 0,
        durationAnchorOffsetY = 0,
        durationBarFillMode = "drain",
        durationColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        durationColorCurveEnabled = false,
        durationColorCurveHighColor = {
            a = 1,
            b = 0,
            g = 1,
            r = 0,
        },
        durationColorCurveLowColor = {
            a = 1,
            b = 0,
            g = 0,
            r = 1,
        },
        durationColorCurveMidColor = {
            a = 1,
            b = 0,
            g = 1,
            r = 1,
        },
        durationColorCurveMode = "step",
        durationColorCurveThreshold = 0.3,
        durationDecimals = 1,
        durationFont = "2002 Bold",
        durationFontSize = 18,
        durationOutline = "THICKOUTLINE",
        durationShadow = false,
        durationShowWhenReady = false,
        durationThreshold2Color = {
            a = 1,
            b = 0,
            g = 0.8,
            r = 0.8,
        },
        durationThreshold2Enabled = false,
        durationThreshold2Value = 75,
        durationThreshold3Color = {
            a = 1,
            b = 0,
            g = 0.5,
            r = 1,
        },
        durationThreshold3Enabled = false,
        durationThreshold3Value = 50,
        durationThreshold4Color = {
            a = 1,
            b = 0,
            g = 0.3,
            r = 1,
        },
        durationThreshold4Enabled = false,
        durationThreshold4Value = 25,
        durationThreshold5Color = {
            a = 1,
            b = 0,
            g = 0,
            r = 1,
        },
        durationThreshold5Enabled = false,
        durationThreshold5Value = 10,
        durationThresholdAsSeconds = false,
        durationThresholdMaxDuration = 30,
        enableMaxColor = false,
        enableSmoothing = false,
        enabled = true,
        fillTextureScale = 1.0,
        foldedColor1 = {
            a = 1,
            b = 1,
            g = 0.5,
            r = 0,
        },
        foldedColor2 = {
            a = 1,
            b = 0,
            g = 1,
            r = 0,
        },
        font = "2002 Bold",
        fontSize = 24,
        fragmentedChargingColor = {
            a = 1,
            b = 0.4,
            g = 0.4,
            r = 0.4,
        },
        fragmentedColors = {},
        fragmentedShowSegmentText = false,
        fragmentedSpacing = 2,
        fragmentedTextSize = 10,
        gradientDirection = "VERTICAL",
        gradientIntensity = 0.5,
        gradientSecondColor = {
            a = 0.5,
            b = 0,
            g = 0,
            r = 0,
        },
        height = 20,
        iconBorderColor = {
            a = 1,
            b = 0,
            g = 0,
            r = 0,
        },
        iconCooldownDrawBling = true,
        iconCooldownDrawEdge = true,
        iconCooldownReverse = false,
        iconDesaturateOnCooldown = true,
        iconDesaturateWhenInactive = false,
        iconDurationColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        iconDurationFont = "2002 Bold",
        iconDurationFontSize = 14,
        iconDurationOutline = "THICKOUTLINE",
        iconDurationShadow = false,
        iconMultiDirection = "RIGHT",
        iconMultiDurationAnchor = "BOTTOM",
        iconMultiFreeMode = false,
        iconMultiLockPositions = false,
        iconMultiMode = false,
        iconMultiPositions = {},
        iconMultiShowDesatBg = true,
        iconMultiShowDurationOn = 1,
        iconMultiSpacing = 4,
        iconShowBorder = true,
        iconShowCooldownSwipe = true,
        iconShowDuration = true,
        iconShowStacks = true,
        iconShowTexture = true,
        iconSize = 48,
        iconStackAnchor = "TOPRIGHT",
        iconStackColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        iconStackFont = "2002 Bold",
        iconStackFontSize = 16,
        iconStackOutline = "THICKOUTLINE",
        iconStackShadow = false,
        iconZoom = 0,
        iconsCooldownTextSize = 12,
        iconsMode = "row",
        iconsPositions = {},
        iconsShape = "square",
        iconsShowCooldownText = true,
        iconsSize = 32,
        iconsSpacing = 4,
        maxColor = {
            a = 1,
            b = 0,
            g = 1,
            r = 0,
        },
        nameAnchor = "CENTER",
        nameAnchorOffsetX = 0,
        nameAnchorOffsetY = 0,
        nameColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        nameFont = "2002 Bold",
        nameFontSize = 14,
        nameOutline = "THICKOUTLINE",
        nameShadow = false,
        opacity = 1.0,
        rotateTexture = false,
        showBackground = true,
        showBarIcon = false,
        showBorder = true,
        showDuration = false,
        showName = false,
        showText = true,
        showTickMarks = true,
        textAnchor = "OUTERTOP",
        textAnchorOffsetX = 0,
        textAnchorOffsetY = 0,
        textColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        textLocked = true,
        textMovable = true,
        textOutline = "THICKOUTLINE",
        textPosition = {
            point = "CENTER",
            relPoint = "CENTER",
            x = 0,
            y = 230,
        },
        textShadow = false,
        texture = "Blizzard",
        thresholdMode = "simple",
        tickColor = {
            a = 1,
            b = 0,
            g = 0,
            r = 0,
        },
        tickHeightAnchor = "center",
        tickHeightPercent = 100,
        tickMode = "all",
        tickThickness = 1,
        tickThicknessAnchor = "center",
        useGradient = false,
        width = 200,
    },
    events = {},
    stackColors = {},
    thresholds = {
        {
            color = {
                a = 1,
                b = 1,
                g = 0.5,
                r = 0,
            },
            enabled = true,
            maxValue = 10,
            minValue = 0,
        },
        {
            color = {
                a = 1,
                b = 0,
                g = 1,
                r = 1,
            },
            enabled = false,
            maxValue = 10,
            minValue = 5,
        },
        {
            color = {
                a = 1,
                b = 0,
                g = 1,
                r = 0,
            },
            enabled = false,
            maxValue = 10,
            minValue = 8,
        },
    },
    tracking = {
        alternateCooldownIDs = {},
        auraInstanceID = 0,
        buffName = "",
        cooldownID = 0,
        dynamicMaxDuration = false,
        enabled = false,
        excludedCooldownIDs = {},
        iconTextureID = 0,
        maxDuration = 30,
        maxStacks = 10,
        slotNumber = 0,
        sourceType = "icon",
        spellID = 0,
        trackType = "buff",
        useBaseSpell = false,
        useDurationBar = false,
    },
}
IA.V1.BAR_TYPE_GROUPS = {
    buff = "buff",
    castbar = "castbar",
    cd_charge = "cd_charge",
    cd_cooldown = "cd_cooldown",
    cd_resource = "cd_resource",
    cooldown = "cooldown",
    resource = "resource",
    timer = "timer",
}
IA.V1.CASTBAR_CATEGORY = {
    backgroundColor = "background",
    barColor = "colors",
    borderColor = "border",
    classColor = "colors",
    colorThresholds = "colors",
    conditionalColorAsSec = "colors",
    conditionalColorEnabled = "colors",
    drawnBorderThickness = "border",
    font = "text",
    fontSize = "text",
    opacity = "fill",
    reverseFill = "fill",
    showBackground = "background",
    showBorder = "border",
    showText = "text",
    showTimer = "text",
    textColor = "text",
    textOutline = "text",
    texture = "fill",
    tickCustom = "tickMarks",
    tickHeightAnchor = "tickMarks",
    tickMarksColor = "tickMarks",
    tickMarksEnabled = "tickMarks",
    tickMarksHeightFraction = "tickMarks",
    tickMarksThickness = "tickMarks",
    tickMode = "tickMarks",
    tickPercent = "tickMarks",
    tickShowOn = "tickMarks",
    tickThicknessAnchor = "tickMarks",
}
IA.V1.CASTBAR_DEFAULTS = {
    anchorGroupName = "",
    anchorOffsetX = 0,
    anchorOffsetY = -2,
    anchorPoint = "BOTTOM",
    anchorToGroup = false,
    autoShareCategories = {},
    backgroundColor = {
        a = 0.9,
        b = 0.1,
        g = 0.1,
        r = 0.1,
    },
    barColor = {
        a = 1,
        b = 1,
        g = 0.8,
        r = 0.2,
    },
    barFrameLevel = 10,
    barFrameStrata = "MEDIUM",
    barMovable = true,
    barPosition = {
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 0,
    },
    borderColor = {
        a = 1,
        b = 0,
        g = 0,
        r = 0,
    },
    castType = "all",
    colorThresholds = {},
    conditionalColorAsSec = false,
    conditionalColorEnabled = false,
    drawnBorderThickness = 2,
    empowerDividerPerColor = false,
    empowerMaxStages = 4,
    empowerSegmentColors = {
        {
            a = 1,
            b = 1.0,
            g = 0.2,
            r = 0.6,
        },
        {
            a = 1,
            b = 0.6,
            g = 0.1,
            r = 0.9,
        },
        {
            a = 1,
            b = 0.1,
            g = 0.3,
            r = 1.0,
        },
        {
            a = 1,
            b = 0.1,
            g = 0.7,
            r = 1.0,
        },
        {
            a = 1,
            b = 0.3,
            g = 0.9,
            r = 0.1,
        },
        {
            a = 1,
            b = 1.0,
            g = 0.7,
            r = 0.1,
        },
        {
            a = 1,
            b = 0.2,
            g = 1.0,
            r = 1.0,
        },
        {
            a = 1,
            b = 0.8,
            g = 0.8,
            r = 0.8,
        },
    },
    empowerSegmentColorsEnabled = false,
    empowerStageDividers = true,
    enabled = false,
    font = "2002 Bold",
    fontSize = 14,
    height = 20,
    hideCastBar = false,
    hideChannels = false,
    hideOutOfCombat = false,
    iconMovable = false,
    iconSize = 20,
    interruptColor = {
        a = 1,
        b = 0.15,
        g = 0.15,
        r = 1,
    },
    interruptFadeDuration = 1.0,
    interruptFeedbackEnabled = false,
    latencyColor = {
        a = 0.4,
        b = 0,
        g = 0,
        r = 1,
    },
    latencyEnabled = false,
    latencyManual = false,
    latencyManualMs = 100,
    matchGroupWidth = false,
    matchSlotsOnly = false,
    matchWidthAdjust = 0,
    opacity = 1.0,
    presets = {},
    profiles = {
        channel = {
            barColor = {
                a = 1,
                b = 0.4,
                g = 1,
                r = 0.2,
            },
        },
        empower = {
            barColor = {
                a = 1,
                b = 1,
                g = 0.2,
                r = 0.6,
            },
        },
        hardcast = {
            barColor = {
                a = 1,
                b = 1,
                g = 0.8,
                r = 0.2,
            },
        },
    },
    reverseFill = false,
    showBackground = true,
    showBorder = true,
    showIcon = true,
    showText = true,
    showTimer = true,
    spellOverrides = {},
    spellShortenEnabled = false,
    spellShortenLength = 20,
    textColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    textOutline = "THICKOUTLINE",
    texture = "Blizzard",
    tickCustom = "",
    tickHeightAnchor = "center",
    tickMarksColor = {
        a = 0.6,
        b = 1,
        g = 1,
        r = 1,
    },
    tickMarksEnabled = false,
    tickMarksHeightFraction = 1.0,
    tickMarksThickness = 2,
    tickMode = "percent",
    tickPercent = 10,
    tickShowOn = "channels",
    tickThicknessAnchor = "center",
    timerFormat = "remaining",
    uninterruptibleBorderColor = {
        a = 1,
        b = 0.5,
        g = 0.3,
        r = 0.3,
    },
    uninterruptibleColor = {
        a = 1,
        b = 0.5,
        g = 0.5,
        r = 0.5,
    },
    uninterruptibleEnabled = false,
    width = 250,
}
IA.V1.CD_DISPLAY_DEFAULTS = {
    backgroundColor = {
        a = 1,
        b = 0.07,
        g = 0.07,
        r = 0.07,
    },
    backgroundTexture = "Solid",
    barBackgroundColor = {
        a = 0.9,
        b = 0.15,
        g = 0.15,
        r = 0.15,
    },
    barBorderColor = {
        a = 1,
        b = 0,
        g = 0,
        r = 0,
    },
    barBorderThickness = 1,
    barColor = {
        a = 1,
        b = 0.2,
        g = 0.6,
        r = 0.2,
    },
    barFrameLevel = 10,
    barFrameStrata = "HIGH",
    barIconAnchor = "LEFT",
    barIconBorderColor = {
        a = 1,
        b = 0,
        g = 0,
        r = 0,
    },
    barIconShowBorder = false,
    barIconSize = 29,
    barMovable = true,
    barOrientation = "horizontal",
    barPadding = 0,
    barPosition = {
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 100,
    },
    barReverseFill = false,
    barScale = 1.0,
    borderColor = {
        a = 1,
        b = 0.2,
        g = 0.6,
        r = 0.8,
    },
    chargeDisplayMode = "slots",
    chargeSlot1Color = {
        a = 1,
        b = 0.2,
        g = 0.2,
        r = 0.8,
    },
    chargeSlot2Color = {
        a = 1,
        b = 0.2,
        g = 0.8,
        r = 0.8,
    },
    chargeSlot3Color = {
        a = 1,
        b = 0.2,
        g = 0.8,
        r = 0.2,
    },
    chargeSlot4Color = {
        a = 1,
        b = 0.8,
        g = 0.6,
        r = 0.2,
    },
    chargeSlot5Color = {
        a = 1,
        b = 0.8,
        g = 0.2,
        r = 0.6,
    },
    chargeTextAnchor = "CENTER",
    chargeTextOffsetX = -22,
    chargeTextOffsetY = 25,
    drawnBorderThickness = 1,
    durationBarFillMode = "drain",
    durationColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    durationColorCurveEnabled = false,
    durationDecimals = 1,
    durationFont = "2002 Bold",
    durationFontSize = 15,
    durationOutline = "THICKOUTLINE",
    durationShadow = false,
    durationTextFrameWidth = 60,
    durationTextLevel = 35,
    durationTextLocked = false,
    durationTextStrata = "HIGH",
    durationThreshold2Color = {
        a = 1,
        b = 0,
        g = 0.8,
        r = 0.8,
    },
    durationThreshold2Enabled = false,
    durationThreshold2Value = 10,
    durationThreshold3Color = {
        a = 1,
        b = 0,
        g = 0.5,
        r = 1,
    },
    durationThreshold3Enabled = false,
    durationThreshold3Value = 5,
    durationThreshold4Color = {
        a = 1,
        b = 0,
        g = 0.3,
        r = 1,
    },
    durationThreshold4Enabled = false,
    durationThreshold4Value = 3,
    durationThreshold5Color = {
        a = 1,
        b = 0,
        g = 0,
        r = 1,
    },
    durationThreshold5Enabled = false,
    durationThreshold5Value = 1,
    durationThresholdAsSeconds = true,
    durationThresholdMaxDuration = 30,
    dynamicTextOffsetX = 0,
    dynamicTextOffsetY = 0,
    dynamicTextOnSlot = false,
    enableSmoothing = true,
    enabled = true,
    font = "2002 Bold",
    fontSize = 24,
    frameHeight = 33,
    frameWidth = 250,
    fullChargeColor = {
        a = 1,
        b = 0.3,
        g = 0.8,
        r = 0.3,
    },
    height = 26,
    iconBarSpacing = 0,
    iconOffsetX = 0,
    iconOffsetY = 0,
    nameAnchor = "TOP",
    nameColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    nameFont = "2002 Bold",
    nameFontSize = 14,
    nameOffsetX = -35,
    nameOffsetY = 4,
    nameOutline = "THICKOUTLINE",
    nameShadow = false,
    nameTextLevel = 35,
    nameTextLocked = false,
    nameTextStrata = "HIGH",
    opacity = 1.0,
    readyColor = {
        a = 1,
        b = 0.3,
        g = 1,
        r = 0.3,
    },
    readyText = "Ready",
    showBackground = true,
    showBarBackground = true,
    showBarBorder = false,
    showBarIcon = true,
    showBorder = true,
    showDuration = true,
    showDurationWhenReady = false,
    showMaxText = false,
    showName = true,
    showReadyText = false,
    showSlotBackground = true,
    showSlotBorder = false,
    showText = true,
    showTickMarks = false,
    showZeroWhenReady = false,
    slotBackgroundColor = {
        a = 1,
        b = 0.08,
        g = 0.08,
        r = 0.08,
    },
    slotBackgroundTexture = "Solid",
    slotBorderColor = {
        a = 1,
        b = 0,
        g = 0,
        r = 0,
    },
    slotBorderThickness = 1,
    slotHeight = 25,
    slotOffsetX = 0,
    slotOffsetY = 0,
    slotSpacing = 3,
    stackTextFrameWidth = 80,
    stackTextLevel = 35,
    stackTextLocked = false,
    stackTextStrata = "HIGH",
    textColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    textOutline = "THICKOUTLINE",
    textShadow = false,
    texture = "Blizzard",
    tickColor = {
        a = 0.8,
        b = 0,
        g = 0,
        r = 0,
    },
    tickMarkInterval = 1,
    tickThickness = 2,
    timerTextAnchor = "BOTTOMRIGHT",
    timerTextOffsetX = -4,
    timerTextOffsetY = 7,
    useClassColorBorder = true,
    useDifferentFullColor = false,
    useGradient = false,
    usePerSlotColors = false,
    width = 178,
}
IA.V1.CD_THRESHOLD_DEFAULT_COLORS = {
    [2] = {
        a = 1,
        b = 0,
        g = 0.8,
        r = 0.8,
    },
    [3] = {
        a = 1,
        b = 0,
        g = 0.5,
        r = 1,
    },
    [4] = {
        a = 1,
        b = 0,
        g = 0.3,
        r = 1,
    },
    [5] = {
        a = 1,
        b = 0,
        g = 0,
        r = 1,
    },
}
IA.V1.CD_THRESHOLD_DEFAULT_VALUES = {
    [2] = 10,
    [3] = 5,
    [4] = 3,
    [5] = 1,
}
IA.V1.DEFAULT_ARCAURA_SETTINGS = {
    alpha = 1.0,
    border = {
        enabled = false,
    },
    cooldownStateVisuals = {
        cooldownState = {
            alpha = 1.0,
            desaturate = true,
        },
        readyState = {
            alpha = 1.0,
            glow = false,
        },
    },
    cooldownSwipe = {
        showBling = true,
        showEdge = true,
        showSwipe = true,
    },
    scale = 1.0,
    thresholdGlow = {
        color = { 1, 0.5, 0, 1 },
        enabled = false,
        seconds = 5,
    },
    zoom = 0.08,
}
IA.V1.DEFAULT_GROUPS = {
    Buffs = {
        anchor = {
            destPoint = "BOTTOM",
            enabled = false,
            mode = "none",
            offsetX = 0,
            offsetY = 0,
            snapBack = false,
            sourcePoint = "TOP",
            targetFrame = "",
            targetGroup = "",
            useSafeAnchor = true,
        },
        autoReflow = true,
        bgColor = {
            a = 0.6,
            b = 0,
            g = 0,
            r = 0,
        },
        borderColor = {
            a = 1,
            b = 0.3,
            g = 0.8,
            r = 0.3,
        },
        containerPadding = -4,
        dynamicContainerSize = false,
        enabled = true,
        grid = {},
        hiddenAlpha = 0,
        layout = {
            direction = "HORIZONTAL",
            gridCols = 4,
            gridRows = 2,
            iconHeight = 36,
            iconSize = 36,
            iconWidth = 36,
            perRow = 4,
            spacing = 2,
        },
        lockGridSize = false,
        members = {},
        position = {
            x = 0,
            y = 200,
        },
        showBackground = false,
        showBorder = false,
        visibility = "always",
    },
    Essential = {
        anchor = {
            destPoint = "BOTTOM",
            enabled = false,
            mode = "none",
            offsetX = 0,
            offsetY = 0,
            snapBack = false,
            sourcePoint = "TOP",
            targetFrame = "",
            targetGroup = "",
            useSafeAnchor = true,
        },
        autoReflow = true,
        bgColor = {
            a = 0.6,
            b = 0,
            g = 0,
            r = 0,
        },
        borderColor = {
            a = 1,
            b = 0.2,
            g = 0.6,
            r = 0.8,
        },
        containerPadding = -4,
        dynamicContainerSize = false,
        enabled = true,
        grid = {},
        hiddenAlpha = 0,
        layout = {
            direction = "HORIZONTAL",
            gridCols = 4,
            gridRows = 2,
            iconHeight = 36,
            iconSize = 36,
            iconWidth = 36,
            perRow = 4,
            spacing = 2,
        },
        lockGridSize = false,
        members = {},
        position = {
            x = 0,
            y = 100,
        },
        showBackground = false,
        showBorder = false,
        visibility = "always",
    },
    Utility = {
        anchor = {
            destPoint = "BOTTOM",
            enabled = false,
            mode = "none",
            offsetX = 0,
            offsetY = 0,
            snapBack = false,
            sourcePoint = "TOP",
            targetFrame = "",
            targetGroup = "",
            useSafeAnchor = true,
        },
        autoReflow = true,
        bgColor = {
            a = 0.6,
            b = 0,
            g = 0,
            r = 0,
        },
        borderColor = {
            a = 1,
            b = 0.9,
            g = 0.6,
            r = 0.3,
        },
        containerPadding = -4,
        dynamicContainerSize = false,
        enabled = true,
        grid = {},
        hiddenAlpha = 0,
        layout = {
            direction = "HORIZONTAL",
            gridCols = 4,
            gridRows = 2,
            iconHeight = 36,
            iconSize = 36,
            iconWidth = 36,
            perRow = 4,
            spacing = 2,
        },
        lockGridSize = false,
        members = {},
        position = {
            x = 0,
            y = 0,
        },
        showBackground = false,
        showBorder = false,
        visibility = "always",
    },
}
IA.V1.DEFAULT_ICON_SETTINGS = {
    alertEvents = {
        onAvailable = {
            playSound = false,
            showGlow = false,
            soundID = 8959,
        },
        onChargeGained = {
            playSound = false,
            showGlow = false,
            soundID = 8959,
        },
        onPandemic = {
            glowColor = {
                b = 0,
                g = 0.5,
                r = 1,
            },
            playSound = false,
            showGlow = false,
            soundID = 43499,
        },
        onUnavailable = {
            playSound = false,
            stopGlow = true,
        },
    },
    alpha = 1.0,
    aspectRatio = 1.0,
    auraActiveState = {
        desaturateWhenInactive = false,
        glow = false,
        glowCombatOnly = false,
        glowFollowPandemic = false,
        glowIntensity = 1.0,
        glowLines = 8,
        glowParticles = 4,
        glowScale = 1.0,
        glowSpeed = 0.25,
        glowThickness = 2,
        glowType = "button",
        glowWhenMissing = false,
        ignoreAuraOverride = false,
    },
    border = {
        color = { 1, 1, 1, 1 },
        enabled = false,
        followDesaturation = false,
        inset = -3,
        thickness = 2,
        useClassColor = false,
    },
    chargeText = {
        anchor = "BOTTOMRIGHT",
        autoHide = true,
        color = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        enabled = true,
        font = "Friz Quadrata TT",
        freeX = 0,
        freeY = 0,
        hideAtZero = false,
        mode = "anchor",
        offsetX = -2,
        offsetY = 2,
        outline = "OUTLINE",
        shadow = false,
        shadowOffsetX = 1,
        shadowOffsetY = -1,
        showSingleStack = false,
        size = 16,
        thresholdBands = {
            {
                color = {
                    a = 1,
                    b = 1,
                    g = 1,
                    r = 1,
                },
                enabled = true,
                threshold = 1,
            },
            {
                color = {
                    a = 1,
                    b = 0.3,
                    g = 1,
                    r = 0.3,
                },
                enabled = true,
                threshold = 3,
            },
            {
                color = {
                    a = 1,
                    b = 0.3,
                    g = 0.3,
                    r = 1,
                },
                enabled = true,
                threshold = 6,
            },
            {
                color = {
                    a = 1,
                    b = 0,
                    g = 0.6,
                    r = 1,
                },
                enabled = false,
                threshold = 9,
            },
            {
                color = {
                    a = 1,
                    b = 1,
                    g = 0.4,
                    r = 0.6,
                },
                enabled = false,
                threshold = 12,
            },
            {
                color = {
                    a = 1,
                    b = 1,
                    g = 0.7,
                    r = 0.3,
                },
                enabled = false,
                threshold = 15,
            },
        },
        thresholdColorEnabled = false,
    },
    cooldownStateVisuals = {
        cooldownState = {
            alpha = 1.0,
            desaturate = false,
            noDesaturate = false,
        },
        readyState = {
            alpha = 1.0,
            glow = false,
            glowWhileChargesAvailable = false,
        },
    },
    cooldownSwipe = {
        edgeWaitForNoCharges = false,
        hideTextWithSwipe = false,
        noGCDSwipe = false,
        reverse = false,
        reverseWhileAura = false,
        separateInsets = false,
        showBling = true,
        showEdge = true,
        showSwipe = true,
        swipeInset = 0,
        swipeInsetX = 0,
        swipeInsetY = 0,
        swipeWaitForNoCharges = false,
    },
    cooldownText = {
        abbrevThreshold = 0,
        anchor = "CENTER",
        color = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        decimalThreshold = 0,
        decimals = 0,
        durationColor = false,
        durationColorCustom = {
            {
                color = {
                    a = 1,
                    b = 0.28,
                    g = 0.39,
                    r = 1,
                },
                enabled = true,
                threshold = 5,
            },
            {
                color = {
                    a = 1,
                    b = 0,
                    g = 1,
                    r = 1,
                },
                enabled = true,
                threshold = 60,
            },
            {
                color = {
                    a = 1,
                    b = 1,
                    g = 1,
                    r = 1,
                },
                enabled = true,
                threshold = 3600,
            },
            {
                color = {
                    a = 1,
                    b = 0,
                    g = 1,
                    r = 0,
                },
                enabled = false,
                threshold = 120,
            },
            {
                color = {
                    a = 1,
                    b = 1,
                    g = 0.5,
                    r = 0.5,
                },
                enabled = false,
                threshold = 300,
            },
        },
        durationColorCustomDefault = {
            a = 1,
            b = 0.67,
            g = 0.67,
            r = 0.67,
        },
        durationColorPreset = "custom",
        enabled = true,
        font = "Friz Quadrata TT",
        freeX = 0,
        freeY = 0,
        hideWhenHasCharges = false,
        mode = "anchor",
        offsetX = 0,
        offsetY = 0,
        outline = "OUTLINE",
        shadow = false,
        shadowOffsetX = 1,
        shadowOffsetY = -1,
        size = 14,
    },
    debuffBorder = {
        enabled = false,
    },
    forceHideIcon = false,
    keepBright = false,
    keepBrightAllowDesat = false,
    padding = 0,
    pandemicBorder = {
        enabled = false,
    },
    procGlow = {
        alpha = 1.0,
        enabled = true,
        glowType = "default",
        lines = 8,
        particles = 4,
        scale = 1.0,
        speed = 0.25,
        thickness = 2,
    },
    rangeIndicator = {
        enabled = true,
    },
    scale = 1.0,
    shadowSize = 1.0,
    spellUsability = {
        enabled = true,
        procOverride = false,
    },
    zoom = 0.08,
}
IA.V1.DURATION_THRESHOLD_DEFAULT_COLORS = {
    [2] = {
        a = 1,
        b = 0,
        g = 0.8,
        r = 0.8,
    },
    [3] = {
        a = 1,
        b = 0,
        g = 0.5,
        r = 1,
    },
    [4] = {
        a = 1,
        b = 0,
        g = 0.3,
        r = 1,
    },
    [5] = {
        a = 1,
        b = 0,
        g = 0,
        r = 1,
    },
}
IA.V1.DURATION_THRESHOLD_DEFAULT_VALUES = {
    [2] = 75,
    [3] = 50,
    [4] = 25,
    [5] = 10,
}
IA.V1.EXCLUDED_DISPLAY_KEYS = {
    anchorGroupName = true,
    anchorOffsetX = true,
    anchorOffsetY = true,
    anchorPoint = true,
    anchorToGroup = true,
    autoPowerColors = true,
    barFrameLevel = true,
    barFrameStrata = true,
    barMovable = true,
    barPosition = true,
    durationTextLevel = true,
    durationTextStrata = true,
    enabled = true,
    hideChannels = true,
    hideOutOfCombat = true,
    iconOverride = true,
    iconStackLevel = true,
    iconStackLocked = true,
    iconStackStrata = true,
    iconsPositions = true,
    matchGroupWidth = true,
    matchIconEdges = true,
    matchSlotsOnly = true,
    matchWidthAdjust = true,
    nameTextLevel = true,
    nameTextStrata = true,
    presets = true,
    readyTextLevel = true,
    readyTextLocked = true,
    readyTextStrata = true,
    stackTextLevel = true,
    stackTextStrata = true,
    textDragMode = true,
    textLevel = true,
    textLocked = true,
    textMovable = true,
    textPosition = true,
    textStrata = true,
}
IA.V1.FOCUS_CASTBAR_DEFAULTS = {
    anchorFrameName = "",
    anchorOffsetX = 0,
    anchorOffsetY = 0,
    anchorPoint = "CENTER",
    anchorRelativePoint = "CENTER",
    anchorToFrame = false,
    backgroundColor = {
        a = 0.9,
        b = 0.1,
        g = 0.1,
        r = 0.1,
    },
    barAnchorPoint = "CENTER",
    barColor = {
        a = 1,
        b = 0,
        g = 0.65,
        r = 1,
    },
    barFrameStrata = "MEDIUM",
    barPosition = {
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = -120,
    },
    borderColor = {
        a = 1,
        b = 0,
        g = 0,
        r = 0,
    },
    casterNameAnchor = "RIGHT",
    casterNameColor = {
        a = 1,
        b = 0,
        g = 0.82,
        r = 1,
    },
    casterNameOffsetX = 0,
    casterNameOffsetY = 0,
    drawnBorderThickness = 2,
    enabled = false,
    focusTargetAnchor = "RIGHT",
    focusTargetColor = {
        a = 1,
        b = 1,
        g = 0.8,
        r = 0.6,
    },
    focusTargetOffsetX = 0,
    focusTargetOffsetY = 0,
    font = "Friz Quadrata TT",
    fontSize = 11,
    glowColor = {
        a = 1,
        b = 0,
        g = 0.65,
        r = 1,
    },
    glowFrequency = 0.25,
    glowLines = 8,
    glowType = "pixel",
    glowWidth = 2,
    height = 18,
    hideNotImportant = false,
    hideNotInterruptible = false,
    holdDuration = 0.8,
    holdEnabled = false,
    holdFailColor = {
        a = 1,
        b = 0.0,
        g = 0.5,
        r = 1.0,
    },
    holdInterruptedColor = {
        a = 1,
        b = 1.0,
        g = 0.4,
        r = 0.2,
    },
    holdSuccessColor = {
        a = 1,
        b = 0.2,
        g = 1.0,
        r = 0.2,
    },
    importantGlowColor = {
        a = 1,
        b = 0.2,
        g = 0.2,
        r = 1,
    },
    importantGlowEnabled = false,
    importantGlowFrequency = 0.25,
    importantGlowLines = 8,
    importantGlowThickness = 2,
    importantGlowType = "pixel",
    kickEnabled = false,
    kickNotReadyColor = {
        a = 1,
        b = 0.55,
        g = 0.55,
        r = 0.55,
    },
    kickTickColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    raidMarkerAnchor = "LEFT",
    raidMarkerDefault = 8,
    raidMarkerOffsetX = -36,
    raidMarkerOffsetY = 0,
    raidMarkerSize = 32,
    showBackground = true,
    showBorder = true,
    showCasterName = true,
    showFocusTarget = false,
    showGlow = true,
    showRaidMarker = true,
    showSpellName = true,
    showTimer = true,
    spellNameMaxWidth = 0,
    textColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    textOutline = "THICKOUTLINE",
    texture = "Blizzard",
    uninterruptibleColor = {
        a = 1,
        b = 0.5,
        g = 0.5,
        r = 0.5,
    },
    uninterruptibleEnabled = false,
    width = 220,
}
IA.V1.KEY_CATEGORY_PREFIXES = {
    {
        category = "colors",
        prefix = "colorCurve",
    },
    {
        category = "text",
        prefix = "durationColor",
    },
    {
        category = "text",
        prefix = "durationText",
    },
    {
        category = "text",
        prefix = "textColorThreshold",
    },
    {
        category = "colors",
        prefix = "durationThreshold",
    },
    {
        category = "colors",
        prefix = "chargeSlot",
    },
    {
        category = "size",
        prefix = "iconMulti",
    },
    {
        category = "fill",
        prefix = "gradient",
    },
    {
        category = "tickMarks",
        prefix = "tick",
    },
    {
        category = "tickMarks",
        prefix = "divider",
    },
}
IA.V1.KEY_TO_CATEGORY = {
    activeCountColors = "colors",
    backgroundColor = "background",
    backgroundTexture = "background",
    barBackgroundColor = "background",
    barColor = "colors",
    barIconAnchor = "size",
    barIconShowBorder = "border",
    barIconSize = "size",
    barOrientation = "fill",
    barPadding = "size",
    barPaddingB = "size",
    barPaddingL = "size",
    barPaddingR = "size",
    barPaddingT = "size",
    barPosition = "position",
    barReverseFill = "fill",
    barScale = "size",
    borderColor = "border",
    cdTextColor = "text",
    cdTextDecimalPrecision = "text",
    cdTextFont = "text",
    cdTextOffsetX = "text",
    cdTextOffsetY = "text",
    cdTextOutline = "text",
    cdTextShow = "text",
    cdTextSize = "text",
    chargeTextAnchor = "text",
    chargeTextOffsetX = "text",
    chargeTextOffsetY = "text",
    chargedComboColor = "colors",
    customTicksAsPercent = "tickMarks",
    displayMode = "colors",
    displayType = "fill",
    drawnBorderThickness = "size",
    durationAnchor = "text",
    durationAnchorOffsetX = "text",
    durationAnchorOffsetY = "text",
    durationBarFillMode = "fill",
    durationColor = "text",
    durationDecimals = "text",
    durationFont = "text",
    durationFontSize = "text",
    durationOutline = "text",
    durationShadow = "text",
    durationShowWhenReady = "text",
    durationTextFrameWidth = "text",
    durationThreshold = "text",
    durationThresholdAsSeconds = "text",
    durationThresholdMaxDuration = "text",
    dynamicTextOffsetX = "text",
    dynamicTextOffsetY = "text",
    dynamicTextOnSlot = "text",
    enableActiveCountColors = "colors",
    enableMaxColor = "colors",
    enableSmoothing = "fill",
    foldedColor1 = "colors",
    foldedColor2 = "colors",
    font = "text",
    fontSize = "text",
    fragmentedChargingColor = "colors",
    fragmentedColors = "colors",
    fragmentedFillOrientation = "fill",
    fragmentedLayoutDirection = "fill",
    fragmentedShowSegmentText = "text",
    fragmentedSpacing = "size",
    fragmentedSpecColors = "colors",
    fragmentedTextOffsetX = "text",
    fragmentedTextOffsetY = "text",
    fragmentedTextSize = "text",
    frameHeight = "size",
    frameWidth = "size",
    fullChargeColor = "colors",
    height = "size",
    iconBarSpacing = "size",
    iconBorderColor = "border",
    iconCooldownDrawBling = "fill",
    iconCooldownDrawEdge = "fill",
    iconCooldownReverse = "fill",
    iconDesaturateOnCooldown = "colors",
    iconDesaturateWhenInactive = "colors",
    iconDurationColor = "text",
    iconDurationFont = "text",
    iconDurationFontSize = "text",
    iconDurationOutline = "text",
    iconDurationShadow = "text",
    iconOffsetX = "size",
    iconOffsetY = "size",
    iconShowBorder = "border",
    iconShowCooldownSwipe = "fill",
    iconShowDuration = "text",
    iconShowStacks = "text",
    iconShowTexture = "fill",
    iconSize = "size",
    iconStackAnchor = "text",
    iconStackColor = "text",
    iconStackFont = "text",
    iconStackFontSize = "text",
    iconStackOutline = "text",
    iconStackShadow = "text",
    iconZoom = "size",
    iconsBorderStyle = "border",
    iconsCDTextOffsetX = "text",
    iconsCDTextOffsetY = "text",
    iconsCooldownTextSize = "text",
    iconsMode = "size",
    iconsShape = "size",
    iconsShowCooldownText = "text",
    iconsSize = "size",
    iconsSpacing = "size",
    maxColor = "colors",
    nameAnchor = "text",
    nameColor = "text",
    nameFont = "text",
    nameFontSize = "text",
    nameOffsetX = "text",
    nameOffsetY = "text",
    opacity = "colors",
    predCostColor = "colors",
    predGainColor = "colors",
    predTextCostColor = "text",
    predTextFormat = "text",
    predTextGainColor = "text",
    readyColor = "text",
    readyText = "text",
    readyTextAnchor = "text",
    readyTextOffsetX = "text",
    readyTextOffsetY = "text",
    rotateTexture = "fill",
    segmentedSpacing = "size",
    showBackground = "background",
    showBarBackground = "background",
    showBarBorder = "border",
    showBarIcon = "size",
    showBorder = "border",
    showDuration = "text",
    showMaxText = "text",
    showName = "text",
    showPrediction = "text",
    showReadyText = "text",
    showSlotBackground = "background",
    showSlotBorder = "border",
    showText = "text",
    showTickMarks = "tickMarks",
    showZeroWhenReady = "text",
    slotBackgroundColor = "colors",
    slotBackgroundTexture = "background",
    slotBorderColor = "colors",
    slotBorderThickness = "border",
    slotColors = "colors",
    slotHeight = "size",
    slotOffsetX = "size",
    slotOffsetY = "size",
    slotSpacing = "size",
    slotWidth = "size",
    smartChargingColor = "colors",
    textAnchor = "text",
    textAnchorOffsetX = "text",
    textAnchorOffsetY = "text",
    textColor = "text",
    textColorByState = "text",
    textFormat = "text",
    textOutline = "text",
    textShadow = "text",
    textShowPercentSymbol = "text",
    textUnusableColor = "text",
    textUsableColor = "text",
    texture = "fill",
    thresholdAsPercent = "tickMarks",
    thresholdMode = "colors",
    tickColor = "tickMarks",
    tickHeightAnchor = "tickMarks",
    tickHeightPercent = "tickMarks",
    tickMode = "tickMarks",
    tickPercent = "tickMarks",
    tickThickness = "tickMarks",
    tickThicknessAnchor = "tickMarks",
    timerTextAnchor = "text",
    timerTextOffsetX = "text",
    timerTextOffsetY = "text",
    useClassColorBorder = "border",
    useDifferentFullColor = "colors",
    useGradient = "fill",
    usePerSlotColors = "colors",
    width = "size",
}
IA.V1.RESOURCE_BAR_DEFAULTS = {
    abilityThresholds = {},
    behavior = {
        hideBlizzardFrame = false,
        hideOutOfCombat = false,
        hideWhenEmpty = false,
        hideWhenFull = false,
        showOnSpec = 0,
        showOnSpecs = {},
    },
    display = {
        backgroundColor = {
            a = 0.9,
            b = 0.1,
            g = 0.1,
            r = 0.1,
        },
        barFrameLevel = 10,
        barFrameStrata = "MEDIUM",
        barMovable = true,
        barOrientation = "horizontal",
        barPosition = {
            point = "CENTER",
            relPoint = "CENTER",
            x = 0,
            y = -100,
        },
        barReverseFill = false,
        barScale = 1.0,
        borderColor = {
            a = 1,
            b = 0,
            g = 0,
            r = 0,
        },
        drawnBorderThickness = 2,
        enableMaxColor = false,
        enableSmoothing = false,
        enabled = true,
        fillTextureScale = 1.0,
        foldedColor1 = {
            a = 1,
            b = 1,
            g = 0.5,
            r = 0,
        },
        foldedColor2 = {
            a = 1,
            b = 0,
            g = 1,
            r = 0,
        },
        font = "Friz Quadrata TT",
        fontSize = 20,
        height = 25,
        maxColor = {
            a = 1,
            b = 0,
            g = 1,
            r = 0,
        },
        opacity = 1.0,
        rotateTexture = false,
        showBackground = true,
        showBorder = true,
        showText = true,
        showTickMarks = false,
        textAnchor = "OUTERTOP",
        textAnchorOffsetX = 0,
        textAnchorOffsetY = 0,
        textColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        textColorThresholdBaseColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        textColorThresholdEnabled = false,
        textColorThresholdFill = false,
        textColorThresholdT1Color = {
            a = 1,
            b = 0.8,
            g = 0.6,
            r = 1,
        },
        textColorThresholdT1Enabled = false,
        textColorThresholdT1Value = 15,
        textColorThresholdT2Color = {
            a = 1,
            b = 0.5,
            g = 1,
            r = 0.5,
        },
        textColorThresholdT2Enabled = false,
        textColorThresholdT2Value = 30,
        textColorThresholdT3Color = {
            a = 1,
            b = 0.3,
            g = 0.3,
            r = 1,
        },
        textColorThresholdT3Enabled = false,
        textColorThresholdT3Value = 90,
        textColorThresholdT4Color = {
            a = 1,
            b = 0.3,
            g = 1,
            r = 1,
        },
        textColorThresholdT4Enabled = false,
        textColorThresholdT4Value = 100,
        textFormat = "value",
        textLocked = true,
        textMovable = true,
        textPosition = {
            point = "CENTER",
            relPoint = "CENTER",
            x = 0,
            y = -70,
        },
        texture = "Blizzard",
        thresholdMode = "simple",
        tickColor = {
            a = 0.8,
            b = 1,
            g = 1,
            r = 1,
        },
        tickHeightAnchor = "center",
        tickHeightPercent = 100,
        tickMode = "all",
        tickThickness = 2,
        tickThicknessAnchor = "center",
        width = 250,
    },
    prediction = {
        spells = {},
    },
    thresholds = {
        {
            color = {
                a = 1,
                b = 1,
                g = 0.8,
                r = 0,
            },
            enabled = true,
            maxValue = 100,
            minValue = 0,
        },
        {
            color = {
                a = 1,
                b = 0,
                g = 1,
                r = 1,
            },
            enabled = false,
            maxValue = 100,
            minValue = 50,
        },
        {
            color = {
                a = 1,
                b = 0,
                g = 1,
                r = 0,
            },
            enabled = false,
            maxValue = 100,
            minValue = 80,
        },
    },
    tracking = {
        enabled = false,
        maxValue = 100,
        overrideMax = false,
        powerName = "",
        powerType = 0,
        resourceCategory = "primary",
        showRuneTimer = false,
    },
}
IA.V1.RESOURCE_THRESHOLD_DEFAULT_COLORS = {
    [2] = {
        a = 1,
        b = 0,
        g = 1,
        r = 1,
    },
    [3] = {
        a = 1,
        b = 0,
        g = 0.5,
        r = 1,
    },
    [4] = {
        a = 1,
        b = 0,
        g = 0,
        r = 1,
    },
    [5] = {
        a = 1,
        b = 0.5,
        g = 0,
        r = 0.5,
    },
}
IA.V1.RESOURCE_THRESHOLD_DEFAULT_VALUES = {
    [2] = 75,
    [3] = 50,
    [4] = 25,
    [5] = 10,
}
IA.V1.STALE_FRAGMENTED_KEYS = { "fragmentedSpecColors", "fragmentedColors", "fragmentedChargingColor", "fragmentedSpacing", "fragmentedFillOrientation", "fragmentedShowSegmentText", "fragmentedTextSize", "fragmentedTextOffsetX", "fragmentedTextOffsetY", "iconsMode", "iconsPositions", "iconsShowCooldownText" }
IA.V1.TARGET_CASTBAR_DEFAULTS = {
    anchorFrameName = "",
    anchorOffsetX = 0,
    anchorOffsetY = 0,
    anchorPoint = "CENTER",
    anchorRelativePoint = "CENTER",
    anchorToFrame = false,
    backgroundColor = {
        a = 0.9,
        b = 0.1,
        g = 0.1,
        r = 0.1,
    },
    barAnchorPoint = "CENTER",
    barColor = {
        a = 1,
        b = 0,
        g = 0.65,
        r = 1,
    },
    barFrameStrata = "MEDIUM",
    barPosition = {
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = -120,
    },
    borderColor = {
        a = 1,
        b = 0,
        g = 0,
        r = 0,
    },
    casterNameAnchor = "RIGHT",
    casterNameColor = {
        a = 1,
        b = 0,
        g = 0.82,
        r = 1,
    },
    casterNameOffsetX = 0,
    casterNameOffsetY = 0,
    drawnBorderThickness = 2,
    enabled = false,
    font = "Friz Quadrata TT",
    fontSize = 11,
    glowColor = {
        a = 1,
        b = 0,
        g = 0.65,
        r = 1,
    },
    glowFrequency = 0.25,
    glowLines = 8,
    glowType = "pixel",
    glowWidth = 2,
    height = 18,
    hideNotImportant = false,
    hideNotInterruptible = false,
    holdDuration = 0.8,
    holdEnabled = false,
    holdFailColor = {
        a = 1,
        b = 0.0,
        g = 0.5,
        r = 1.0,
    },
    holdInterruptedColor = {
        a = 1,
        b = 1.0,
        g = 0.4,
        r = 0.2,
    },
    holdSuccessColor = {
        a = 1,
        b = 0.2,
        g = 1.0,
        r = 0.2,
    },
    importantGlowColor = {
        a = 1,
        b = 0.2,
        g = 0.2,
        r = 1,
    },
    importantGlowEnabled = false,
    importantGlowFrequency = 0.25,
    importantGlowLines = 8,
    importantGlowThickness = 2,
    importantGlowType = "pixel",
    kickEnabled = false,
    kickNotReadyColor = {
        a = 1,
        b = 0.55,
        g = 0.55,
        r = 0.55,
    },
    kickTickColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    raidMarkerAnchor = "LEFT",
    raidMarkerDefault = 8,
    raidMarkerOffsetX = -36,
    raidMarkerOffsetY = 0,
    raidMarkerSize = 32,
    showBackground = true,
    showBorder = true,
    showCasterName = true,
    showGlow = true,
    showRaidMarker = true,
    showSpellName = true,
    showTargetTarget = false,
    showTimer = true,
    spellNameMaxWidth = 0,
    targetTargetAnchor = "RIGHT",
    targetTargetColor = {
        a = 1,
        b = 1,
        g = 0.8,
        r = 0.6,
    },
    targetTargetOffsetX = 0,
    targetTargetOffsetY = 0,
    textColor = {
        a = 1,
        b = 1,
        g = 1,
        r = 1,
    },
    textOutline = "THICKOUTLINE",
    texture = "Blizzard",
    uninterruptibleColor = {
        a = 1,
        b = 0.5,
        g = 0.5,
        r = 0.5,
    },
    uninterruptibleEnabled = false,
    width = 220,
}
IA.V1.TEXTURE_DEFAULTS = {
    behavior = {
        hideLogic = "any",
        hideWhen = {},
        hideWhenAlpha = 0,
        showOnSpec = 0,
        showOnSpecs = {},
    },
    display = {
        activeAlpha = 1,
        activeColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        activeDesaturate = false,
        activeDesaturatePct = 100,
        blendMode = "BLEND",
        cropB = 0,
        cropEnabled = false,
        cropL = 0,
        cropR = 0,
        cropT = 0,
        customTexturePath = "",
        drainInsetB = 0,
        drainInsetL = 0,
        drainInsetR = 0,
        drainInsetT = 0,
        durationAnchor = "CENTER",
        durationAnchorOffsetX = 0,
        durationAnchorOffsetY = 0,
        durationColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        durationDecimals = 1,
        durationFont = "2002 Bold",
        durationFontSize = 18,
        durationOutline = "THICKOUTLINE",
        durationShadow = false,
        durationTextLevel = 13,
        durationTextStrata = "HIGH",
        enabled = true,
        fadeOutEnabled = false,
        fadeStartPct = 50,
        frameLevel = 10,
        frameStrata = "MEDIUM",
        glowEnabled = false,
        glowType = "pixel",
        height = 64,
        inactiveAlpha = 0.5,
        inactiveColor = {
            a = 1,
            b = 1,
            g = 1,
            r = 1,
        },
        inactiveDesaturate = true,
        inactiveDesaturatePct = 100,
        lockAspect = false,
        mirrorH = false,
        mirrorV = false,
        movable = true,
        position = {
            point = "CENTER",
            relPoint = "CENTER",
            x = 0,
            y = 0,
        },
        progressDir = "TOP_TO_BOTTOM",
        progressEnabled = false,
        progressHideGhost = false,
        pulseEnabled = false,
        pulseScale = 1.15,
        pulseSpeed = 0.5,
        rotateEnabled = false,
        rotation = 0,
        showDuration = false,
        showWhenInactive = false,
        textureID = 0,
        textureSource = "library",
        width = 64,
        zoomEnabled = false,
        zoomPct = 0,
    },
    tracking = {
        alternateCooldownIDs = {},
        auraInstanceID = 0,
        buffName = "",
        cooldownID = 0,
        enabled = false,
        excludedCooldownIDs = {},
        iconTextureID = 0,
        slotNumber = 0,
        spellID = 0,
        trackType = "buff",
        useBaseSpell = false,
    },
}
IA.V1.TEXT_SUBCATEGORY = {
    cdTextColor = "textDuration",
    cdTextDecimalPrecision = "textDuration",
    cdTextFont = "textDuration",
    cdTextOffsetX = "textDuration",
    cdTextOffsetY = "textDuration",
    cdTextOutline = "textDuration",
    cdTextShow = "textDuration",
    cdTextSize = "textDuration",
    durationAnchor = "textDuration",
    durationAnchorOffsetX = "textDuration",
    durationAnchorOffsetY = "textDuration",
    durationColor = "textDuration",
    durationDecimals = "textDuration",
    durationFont = "textDuration",
    durationFontSize = "textDuration",
    durationOutline = "textDuration",
    durationShadow = "textDuration",
    durationShowWhenReady = "textDuration",
    durationTextFrameWidth = "textDuration",
    durationThreshold = "textDuration",
    durationThresholdAsSeconds = "textDuration",
    durationThresholdMaxDuration = "textDuration",
    iconDurationColor = "textDuration",
    iconDurationFont = "textDuration",
    iconDurationFontSize = "textDuration",
    iconDurationOutline = "textDuration",
    iconDurationShadow = "textDuration",
    iconShowDuration = "textDuration",
    iconsCDTextOffsetX = "textDuration",
    iconsCDTextOffsetY = "textDuration",
    iconsCooldownTextSize = "textDuration",
    iconsShowCooldownText = "textDuration",
    nameAnchor = "textName",
    nameColor = "textName",
    nameFont = "textName",
    nameFontSize = "textName",
    nameOffsetX = "textName",
    nameOffsetY = "textName",
    readyColor = "textReady",
    readyText = "textReady",
    readyTextAnchor = "textReady",
    readyTextOffsetX = "textReady",
    readyTextOffsetY = "textReady",
    showDuration = "textDuration",
    showName = "textName",
    showReadyText = "textReady",
    timerTextAnchor = "textDuration",
    timerTextOffsetX = "textDuration",
    timerTextOffsetY = "textDuration",
}
IA.V1.TOP_LEVEL_KEY_CATEGORIES = {
    abilityThresholds = "tickMarks",
    colorRanges = "colors",
    thresholds = "colors",
}
-- END GENERATED V1 TABLES

-- Arc UI's settings version: its migrations ran on the globals up to this one.
IA.V1.SETTINGS_VERSION = 8
-- CreateGroup's border colours per default group name, else grey.
IA.V1.GROUP_COLORS = {
    Buffs = { r = 0.3, g = 0.8, b = 0.3 },
    Essential = { r = 0.8, g = 0.6, b = 0.2 },
    Utility = { r = 0.3, g = 0.6, b = 0.9 },
}
-- A brand-new Arc UI install's two global layers (applied once, when both are empty).
IA.V1.FIRST_TIME_GLOBALS = {
    aura = { border = { enabled = true, color = { 0, 0, 0, 1 }, thickness = 1, inset = 0 } },
    cooldown = { border = { enabled = true, color = { 0, 0, 0, 1 }, thickness = 1, inset = 0 },
        cooldownSwipe = { noGCDSwipe = true }, rangeIndicator = { enabled = false } },
}

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function SortedKeys(t, keep)
    local keys = {}
    for k in pairs(type(t) == "table" and t or {}) do
        if not keep or keep(k) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end
IA.SortedKeys = SortedKeys

-- Arc UI's DeepMergeSettings: a source table merges into a table at the same key, field by
-- field (colours too, so {r,g,b} over a listed colour keeps both shapes, as in v1); any other
-- non-nil source value replaces.
-- out is a fresh copy no one else holds, so its tables merge in place: copying
-- each level again is what made a big save's plan slow
local function MergeInto(out, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(out[k]) == "table" then
            MergeInto(out[k], v)
        elseif v ~= nil then
            out[k] = Copy(v)
        end
    end
end

function IA.V1Merge(dest, source)
    if type(source) ~= "table" then return Copy(dest) end
    if type(dest) ~= "table" then return Copy(source) end
    local out = Copy(dest)
    MergeInto(out, source)
    return out
end

-- v1's MigrateSettingsTable (migrations 1 to 8) on a copy. v1 runs it on the globals and the
-- old account-profile icon table only; per-spec icon tables are read as they are.
function IA.V1Migrate(cfg)
    if type(cfg) ~= "table" then return cfg end
    cfg = Copy(cfg)
    local legacy = cfg.inactiveState
    if type(legacy) == "table" then
        local dim = tonumber(legacy.dimAlpha)
        if legacy.hideWhenInactive or legacy.desaturateWhenInactive or (dim and dim < 1) then
            cfg.cooldownStateVisuals = cfg.cooldownStateVisuals or {}
            cfg.cooldownStateVisuals.cooldownState = cfg.cooldownStateVisuals.cooldownState or {}
            local ns = cfg.cooldownStateVisuals.cooldownState
            if legacy.hideWhenInactive then ns.alpha = 0 elseif dim and dim < 1 then ns.alpha = dim end
            if legacy.desaturateWhenInactive then ns.desaturate = true end
        end
        cfg.inactiveState = nil
    end
    local sw = cfg.cooldownSwipe
    if type(sw) == "table" and sw.swipeMode then
        if sw.swipeMode == "noGCD" then sw.noGCDSwipe = true
        elseif sw.swipeMode == "cooldownOnly" then sw.ignoreAuraOverride = true end
        sw.swipeMode = nil
    end
    local sv = cfg.cooldownStateVisuals
    if type(sv) == "table" then
        if type(sv.readyState) == "table" and next(sv.readyState) == nil then sv.readyState = nil end
        if type(sv.cooldownState) == "table" and next(sv.cooldownState) == nil then sv.cooldownState = nil end
        if next(sv) == nil then cfg.cooldownStateVisuals = nil end
    end
    if type(cfg.chargeText) == "table" and cfg.chargeText.outline == "NONE" then cfg.chargeText.outline = "" end
    if type(cfg.cooldownText) == "table" and cfg.cooldownText.outline == "NONE" then cfg.cooldownText.outline = "" end
    local rs = cfg.cooldownStateVisuals and cfg.cooldownStateVisuals.readyState
    if type(rs) == "table" then
        for _, k in ipairs({ "glow", "glowCombatOnly", "glowWhileChargesAvailable" }) do
            if rs[k] ~= nil and rs[k] ~= true then rs[k] = nil end
        end
    end
    local cs = cfg.cooldownStateVisuals and cfg.cooldownStateVisuals.cooldownState
    if type(cs) == "table" then
        for _, k in ipairs({ "desaturate", "tint", "noDesaturate" }) do
            if cs[k] ~= nil and cs[k] ~= true then cs[k] = nil end
        end
    end
    local d = cfg.durationOverride
    if type(d) == "table" then
        if d.glow == true then
            cfg.auraActiveState = cfg.auraActiveState or {}
            local aa = cfg.auraActiveState
            if aa.glow == nil then aa.glow = true end
            for _, k in ipairs({ "Type", "Color", "Scale", "Speed", "Lines", "Thickness", "Particles",
                "XOffset", "YOffset", "FrameStrata", "FrameLevel" }) do
                if aa["glow" .. k] == nil then aa["glow" .. k] = Copy(d["glow" .. k]) end
            end
        end
        for _, k in ipairs({ "glow", "glowType", "glowColor", "glowScale", "glowSpeed", "glowLines",
            "glowThickness", "glowParticles", "glowXOffset", "glowYOffset", "glowFrameStrata",
            "glowFrameLevel", "glowPreview", "desaturate", "showSwipe", "showEdge" }) do
            d[k] = nil
        end
    end
    return cfg
end

-- A spec key "class_7_spec_2" -> 7, 2.
function IA.ParseSpecKey(key)
    local c, s = tostring(key):match("^class_(%d+)_spec_(%d+)$")
    if not c then return nil end
    return tonumber(c), tonumber(s)
end

-- The account profile's two global layers for a character, as Arc UI holds them after its
-- next login: the older per-character copy when the profile has none, the first-time
-- defaults when both are still empty and unmarked, the migrations when the profile is older.
function IA.ReadGlobals(db, v1key)
    local pname = (type(db.profileKeys) == "table" and db.profileKeys[v1key]) or "Default"
    local prof = type(db.profiles) == "table" and db.profiles[pname] or nil
    local ce = type(prof) == "table" and type(prof.cdmEnhance) == "table" and prof.cdmEnhance or nil
    local charDB = type(db.char) == "table" and db.char[v1key] or nil
    local old = type(charDB) == "table" and type(charDB.cdmEnhance) == "table" and charDB.cdmEnhance or nil
    local cd = (ce and type(ce.globalCooldownSettings) == "table" and ce.globalCooldownSettings)
        or (old and type(old.globalCooldownSettings) == "table" and old.globalCooldownSettings) or {}
    local au = (ce and type(ce.globalAuraSettings) == "table" and ce.globalAuraSettings)
        or (old and type(old.globalAuraSettings) == "table" and old.globalAuraSettings) or {}
    cd, au = Copy(cd), Copy(au)
    if not (ce and ce._firstTimeDefaultsApplied) and next(cd) == nil and next(au) == nil then
        cd = Copy(IA.V1.FIRST_TIME_GLOBALS.cooldown)
        au = Copy(IA.V1.FIRST_TIME_GLOBALS.aura)
    end
    if not ce or (tonumber(ce.settingsVersion) or 0) < IA.V1.SETTINGS_VERSION then
        cd = IA.V1Migrate(cd) or {}
        au = IA.V1Migrate(au) or {}
        if type(au.cooldownSwipe) == "table" then au.cooldownSwipe.ignoreAuraOverride = nil end
    end
    -- v1's master switches for its per-icon styling
    local styling = { aura = not (ce and ce.enableAuraCustomization == false),
        cooldown = not (ce and ce.enableCooldownCustomization == false) }
    return { cooldown = cd, aura = au, profile = pname, legacyIcons = ce and ce.iconSettings, styling = styling }
end

-- A group record the way CreateGroup reads it: the flat fields only, its defaults filled.
-- `name` picks the default border colour; a Dynamic group's unset alignment takes v1's
-- default for the grid's shape.
function IA.NormalizeGroup(name, ld)
    ld = type(ld) == "table" and ld or {}
    local col = IA.V1.GROUP_COLORS[name] or { r = 0.5, g = 0.5, b = 0.5 }
    local g = {
        gridRows = tonumber(ld.gridRows) or 2, gridCols = tonumber(ld.gridCols) or 4,
        iconSize = tonumber(ld.iconSize) or 36, iconWidth = tonumber(ld.iconWidth) or 36,
        iconHeight = tonumber(ld.iconHeight) or 36, spacing = tonumber(ld.spacing) or 2,
        spacingX = tonumber(ld.spacingX), spacingY = tonumber(ld.spacingY),
        separateSpacing = ld.separateSpacing, alignment = ld.alignment,
        horizontalGrowth = ld.horizontalGrowth, verticalGrowth = ld.verticalGrowth,
        position = type(ld.position) == "table" and { x = tonumber(ld.position.x) or 0, y = tonumber(ld.position.y) or 0 }
            or { x = 0, y = 100 },
        autoReflow = ld.autoReflow ~= false, dynamicLayout = ld.dynamicLayout == true,
        dynamicCooldowns = ld.dynamicCooldowns == true, smoothMovement = ld.smoothMovement,
        smoothMoveDuration = tonumber(ld.smoothMoveDuration), dynamicOrderMode = ld.dynamicOrderMode,
        dynamicContainerSize = ld.dynamicContainerSize, lockGridSize = ld.lockGridSize == true,
        containerPadding = tonumber(ld.containerPadding) or -4,
        showBorder = ld.showBorder == true, showBackground = ld.showBackground == true,
        visibility = ld.visibility or "always", visibilityLogic = ld.visibilityLogic,
        hiddenAlpha = tonumber(ld.hiddenAlpha),
        borderColor = type(ld.borderColor) == "table" and Copy(ld.borderColor) or { r = col.r, g = col.g, b = col.b, a = 1 },
        bgColor = type(ld.bgColor) == "table" and Copy(ld.bgColor) or { r = 0, g = 0, b = 0, a = 0.6 },
        frameStrata = ld.frameStrata or "MEDIUM", frameLevel = tonumber(ld.frameLevel) or 1,
        anchor = type(ld.anchor) == "table" and Copy(ld.anchor) or nil,
        groupType = ld.groupType, auraLayout = Copy(ld.auraLayout), id = ld.id,
    }
    if g.dynamicLayout and not g.alignment then
        g.alignment = (g.gridRows == 1 or g.gridCols == 1) and "center" or "top"
    end
    return g
end

-- The pre-profile spec-level group record (`{ layout = {...}, position, ... }`) converted
-- the way v1's profile migration converts it.
function IA.OldGroupToFlat(gd)
    if type(gd) ~= "table" or not (gd.layout or gd.position) then return nil end
    local L = type(gd.layout) == "table" and gd.layout or {}
    return {
        gridRows = L.gridRows or 2, gridCols = L.gridCols or 4,
        position = type(gd.position) == "table" and { x = gd.position.x, y = gd.position.y } or nil,
        iconSize = L.iconSize or 36, iconWidth = L.iconWidth or 36, iconHeight = L.iconHeight or 36,
        spacing = L.spacing or 2, spacingX = L.spacingX, spacingY = L.spacingY,
        separateSpacing = L.separateSpacing, alignment = L.alignment,
        horizontalGrowth = L.horizontalGrowth, verticalGrowth = L.verticalGrowth,
        showBorder = gd.showBorder, showBackground = gd.showBackground, autoReflow = gd.autoReflow ~= false,
        dynamicLayout = gd.dynamicLayout, dynamicCooldowns = gd.dynamicCooldowns,
        smoothMovement = gd.smoothMovement, smoothMoveDuration = gd.smoothMoveDuration,
        dynamicOrderMode = gd.dynamicOrderMode, dynamicContainerSize = gd.dynamicContainerSize,
        lockGridSize = gd.lockGridSize, containerPadding = gd.containerPadding,
        borderColor = Copy(gd.borderColor), bgColor = Copy(gd.bgColor),
        visibility = gd.visibility, visibilityLogic = gd.visibilityLogic, hiddenAlpha = gd.hiddenAlpha,
        anchor = Copy(gd.anchor),
    }
end

-- DEFAULT_GROUPS as v1 writes them into an empty profile.
function IA.DefaultGroupRecords()
    local out = {}
    for name, gd in pairs(IA.V1.DEFAULT_GROUPS or {}) do
        local flat = IA.OldGroupToFlat(gd)
        flat.visibility = gd.visibility or "always"
        flat.hiddenAlpha = gd.hiddenAlpha
        flat.anchor = nil
        out[name] = flat
    end
    return out
end

-- v1's one-time custom timer flip: a timer's Active look moved from the cooldown state to the
-- ready state, so a character that has not logged in since gets its timer tables swapped (and
-- their desaturation cleared) at the next login. Works on a copy.
function IA.TimerFlip(s)
    if type(s) ~= "table" or type(s.cooldownStateVisuals) ~= "table" then return s end
    s = Copy(s)
    local csv = s.cooldownStateVisuals
    csv.readyState, csv.cooldownState = csv.cooldownState, csv.readyState
    for _, st in ipairs({ csv.readyState, csv.cooldownState }) do
        if type(st) == "table" then st.noDesaturate, st.desaturate = nil, nil end
    end
    return s
end

-- A spec's profiles before any shared pull: the stored set, or the one v1 builds from the
-- pre-profile spec fields; plus the "Recovered" profile v1 adds from leftover spec fields.
local function SpecProfiles(sd, genName)
    local profiles = type(sd.layoutProfiles) == "table" and sd.layoutProfiles or nil
    local legacyGroups = type(sd.groups) == "table" and next(sd.groups) ~= nil
    local legacyPos = type(sd.savedPositions) == "table" and next(sd.savedPositions) ~= nil
    local legacyFree = type(sd.freeIcons) == "table" and next(sd.freeIcons) ~= nil
    local function FromLegacy()
        local groups = {}
        for gname, gd in pairs(type(sd.groups) == "table" and sd.groups or {}) do
            groups[gname] = IA.OldGroupToFlat(gd)
        end
        return { savedPositions = Copy(sd.savedPositions) or {}, freeIcons = Copy(sd.freeIcons) or {},
            groupLayouts = groups, iconSettings = Copy(sd.iconSettings) or {}, synthesized = true }
    end
    if not profiles or next(profiles) == nil then
        if not (legacyGroups or legacyPos or legacyFree) then return {}, nil end
        local p = FromLegacy()
        if next(p.groupLayouts) == nil then p.groupLayouts = IA.DefaultGroupRecords() end
        return { [genName] = p }, genName
    end
    local out = {}
    for pn, p in pairs(profiles) do if type(p) == "table" then out[pn] = p end end
    local active = sd.activeProfile
    local ap = out[active or ""] or out.Default
    local needs = (legacyGroups and not (ap and type(ap.groupLayouts) == "table" and next(ap.groupLayouts)))
        or (legacyPos and not (ap and type(ap.savedPositions) == "table" and next(ap.savedPositions)))
        or legacyFree
    if needs and not out.Recovered then
        local p = FromLegacy()
        if next(p.savedPositions) or next(p.freeIcons) or next(p.groupLayouts) then out.Recovered = p end
    end
    return out, nil
end

-- Which profile is live: the stored name; with none stored, v1's generated name when such a
-- profile exists, else the first; a stored name with no profile falls back to "Default".
function IA.ResolveActive(sd, profiles, genName, synthesized)
    if synthesized then return synthesized end
    local stored = sd.activeProfile
    if stored == nil then
        if genName and profiles[genName] then return genName end
        local keys = SortedKeys(profiles)
        return keys[1]
    end
    if profiles[stored] then return stored end
    if profiles.Default then return "Default" end
    return nil
end

-- A shared profile's pull, as v1's login sync runs it for this character and spec, or nil.
-- Returns the source's spec data and its character table.
function IA.PendingPull(db, v1key, sk, cdm)
    local g = type(db.global) == "table" and db.global or {}
    local ref = type(g.sharedProfiles) == "table" and g.sharedProfiles[sk] or nil
    if type(ref) ~= "table" or not ref.sourceChar or not ref.profileName then return nil end
    if ref.sourceChar == v1key then return nil end
    local on = type(cdm.sharedSync) == "table" and cdm.sharedSync[sk] == true
    if not on then
        local off = (type(cdm.sharedSyncDisabled) == "table" and cdm.sharedSyncDisabled[sk])
            or (type(g.sharedSyncDisabled) == "table" and g.sharedSyncDisabled[sk])
        if off then return nil end
    end
    local local_ts = type(cdm.sharedSyncTimestamp) == "table" and tonumber(cdm.sharedSyncTimestamp[sk]) or 0
    local sd = type(cdm.specData) == "table" and cdm.specData[sk] or nil
    local hasLocal = type(sd) == "table" and type(sd.layoutProfiles) == "table" and next(sd.layoutProfiles) ~= nil
    if hasLocal and not ((tonumber(ref.timestamp) or 0) > local_ts) then return nil end
    local src = type(db.char) == "table" and db.char[ref.sourceChar] or nil
    local sg = type(src) == "table" and type(src.cdmGroups) == "table" and src.cdmGroups or nil
    local ssd = sg and type(sg.specData) == "table" and sg.specData[sk] or nil
    if type(ssd) ~= "table" or type(ssd.layoutProfiles) ~= "table" or type(ssd.layoutProfiles[ref.profileName]) ~= "table" then
        return nil
    end
    return { ref = ref, specData = ssd, char = src }
end

-- A pull's Arc Auras stores onto a character's copy: spells and auras / timers / totems
-- wholesale (an entry the character already had keeps its own load conditions), items only
-- where the source placed them.
local LOCAL_WHO = { "showOnSpecs", "talentConditions", "talentConditionMode" }
function IA.PullArc(arc, pull)
    local sa = type(pull.char.arcAuras) == "table" and pull.char.arcAuras or nil
    if not sa then return end
    local function Replace(store, keepWho)
        if type(sa[store]) ~= "table" then return end
        local old = arc[store]
        local new = Copy(sa[store])
        if keepWho and type(old) == "table" then
            for id, def in pairs(new) do
                local prev = old[id]
                if type(def) == "table" and type(prev) == "table" then
                    for _, k in ipairs(LOCAL_WHO) do def[k] = Copy(prev[k]) end
                end
            end
        end
        arc[store] = new
    end
    Replace("trackedSpells", true)
    Replace("auraIcons", true)
    Replace("customTimers", true)
    Replace("totemSlots", false)
    if type(sa.trackedItems) == "table" then
        local placed = {}
        for _, p in pairs(pull.specData.layoutProfiles) do
            for id in pairs(type(p) == "table" and type(p.savedPositions) == "table" and p.savedPositions or {}) do
                if type(id) == "string" and id:find("^arc_item_") then placed[id] = true end
            end
        end
        arc.trackedItems = arc.trackedItems or {}
        for id, def in pairs(sa.trackedItems) do
            if placed[id] and type(def) == "table" and not def.isAutoTrackSlot then
                local prev = arc.trackedItems[id]
                local copy = Copy(def)
                if type(prev) == "table" then
                    for _, k in ipairs(LOCAL_WHO) do copy[k] = Copy(prev[k]) end
                end
                arc.trackedItems[id] = copy
            end
        end
    end
    for _, k in ipairs({ "autoTrackEquippedTrinkets", "onlyOnUseTrinkets" }) do
        if sa[k] ~= nil then arc[k] = sa[k] end
    end
    if type(sa.autoTrackSlots) == "table" then arc.autoTrackSlots = Copy(sa.autoTrackSlots) end
end

-- One placement record of a profile, cleaned. v1 places its icons from savedPositions alone
-- (its LoadProfile): a freeIcons entry is a second copy that outlives a deleted icon, so it
-- places nothing. A group target the profile's groups lack is gone in v1 (the icon goes
-- loose), so it keeps no group.
local function Placements(p, groups)
    local out = {}
    local sp = type(p.savedPositions) == "table" and p.savedPositions or {}
    for id, pos in pairs(sp) do
        if type(pos) == "table" then
            local e = Copy(pos)
            if e.type == "group" and not (e.target and groups[e.target]) then
                e = { type = "free", loose = true, viewerType = pos.viewerType }
            end
            out[tostring(id)] = { key = id, pos = e }
        end
    end
    return out
end

-- One icon's look as Arc UI merges it (GetEffectiveIconSettings): its defaults, then the
-- global layer of its family, then the icon's own table. A Cooldown Manager aura (category
-- 2, 3, 4, 6 or 8) takes the aura layer; every other id, each arc_* one included, the
-- cooldown layer. Masque's flattening (aspect 1, zoom 0, padding 0) is left out: Arc Auras
-- draws no Masque skin, and the values under it are the nearer match to the skin's crop.
-- The defaults under a global layer are the same for every icon of a character:
-- made once per layer table (the read's own copy). Icons share it, and an icon's
-- own table copies only the parts it changes: a big save's plan made so much
-- garbage that collecting it stalled a frame. Nothing writes a merged look;
-- t_adv1import checks every base stays as made (IA.V1Bases).
local baseOf = setmetatable({}, { __mode = "k" })
IA.V1Bases = baseOf

local function Overlay(base, own)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(own) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = Overlay(out[k], v)
        elseif v ~= nil then
            out[k] = Copy(v)
        end
    end
    return out
end

function IA.V1Effective(C, P, key, auraFamily)
    -- v1 merges nothing for a key that is neither a cooldown id nor an arc_* id
    local skey = tostring(key)
    if not (tonumber(skey) or skey:match("^arc_")) then return IA.V1Merge(IA.V1.DEFAULT_ICON_SETTINGS, nil) end
    local layer = auraFamily and C.globals.aura or C.globals.cooldown
    if type(layer) ~= "table" then layer = IA.V1.DEFAULT_ICON_SETTINGS end
    local base = baseOf[layer]
    if not base then
        base = IA.V1Merge(IA.V1.DEFAULT_ICON_SETTINGS, layer)
        baseOf[layer] = base
    end
    local own = P and P.iconSettings[tostring(key)]
    if type(own) == "table" and next(own) ~= nil then return Overlay(base, own) end
    return base
end

-- Arc UI's own icons: their painters read ArcAuras.GetEffectiveSettings, which lays the Arc
-- defaults under the look above (only thresholdGlow survives it) and the character's Arc-wide
-- settings over it (no option writes them; an old import can). Marks the look when that
-- Arc-wide layer took part.
function IA.V1ArcEffective(C, eff)
    local out = IA.V1Merge(IA.V1.DEFAULT_ARCAURA_SETTINGS, eff)
    local gs = C and type(C.arc) == "table" and C.arc.globalSettings
    if type(gs) == "table" and next(gs) ~= nil then
        out = IA.V1Merge(out, gs)
        out._arcWide = true
    end
    return out
end

-- The whole save -> the model: characters (sorted), each with its globals, its Arc Auras
-- stores and its specs; each spec with its profiles, the live one marked, and each profile
-- with its groups (normalized, the account-wide set it links to named), its placements and
-- its per-icon tables. `opts.specID(classID, index)` answers a spec's id and name in play.
function IA.ReadV1(db, opts)
    opts = opts or {}
    local model = { chars = {}, notes = {} }
    if type(db) ~= "table" or type(db.char) ~= "table" then return model end
    local function Note(what) model.notes[what] = (model.notes[what] or 0) + 1 end
    local global = type(db.global) == "table" and db.global or {}
    for _, v1key in ipairs(SortedKeys(db.char)) do
        if IA.Yield then IA.Yield() end
        local charDB = db.char[v1key]
        if type(charDB) == "table" then
            local name, realm = tostring(v1key):match("^(.-) %- (.+)$")
            local C = { v1key = v1key, charKey = name and (name .. "-" .. realm) or tostring(v1key),
                name = name or tostring(v1key), globals = IA.ReadGlobals(db, v1key), specs = {} }
            local cdm = type(charDB.cdmGroups) == "table" and charDB.cdmGroups or {}
            C.masque = type(cdm.masqueSettings) == "table" and cdm.masqueSettings.enabled == true
            C.groupsOff = cdm.enabled == false
            -- icon tooltips are character-wide in v1. Its click-through hides them only as a side
            -- effect; Arc Auras' click-through keeps them, so only Disable tooltips turns them off
            C.noTips = cdm.disableTooltips == true
            C.arc = Copy(type(charDB.arcAuras) == "table" and charDB.arcAuras or {})
            local specData = type(cdm.specData) == "table" and cdm.specData or {}
            local legacyIconsDone = cdm.migratedProfileIconSettings == true
            local flipTimers = type(charDB.cdmGroups) == "table" and not cdm._timerStateFlipMigrated
            -- the account profile's old layout store, which v1 copies into a spec with no profiles
            local prof = type(db.profiles) == "table" and db.profiles[C.globals.profile] or nil
            local oldStore = not cdm.cleanedProfileStorageV2 and type(prof) == "table" and type(prof.cdmGroups) == "table"
                and type(prof.cdmGroups.specData) == "table" and prof.cdmGroups.specData or nil
            for _, sk in ipairs(SortedKeys(specData)) do
                local sd = specData[sk]
                local classID, idx = IA.ParseSpecKey(sk)
                if classID and type(sd) == "table" then
                    local specID, specName = IA.SpecID(classID, idx, opts)
                    if not specID then
                        Note("a spec key the class does not have")
                    else
                        C.classID = C.classID or classID
                        local pull = IA.PendingPull(db, v1key, sk, cdm)
                        local S = { key = sk, classID = classID, index = idx, specID = specID,
                            specName = specName or ("Spec " .. idx), profiles = {} }
                        local src = sd
                        local old = oldStore and (oldStore[sk] or oldStore[idx]) or nil
                        if type(old) == "table" and type(old.layoutProfiles) == "table" and next(old.layoutProfiles)
                            and not (type(sd.layoutProfiles) == "table" and next(sd.layoutProfiles)) then
                            src = { layoutProfiles = old.layoutProfiles, activeProfile = old.activeProfile or "Default",
                                groups = sd.groups, savedPositions = sd.savedPositions, freeIcons = sd.freeIcons,
                                iconSettings = sd.iconSettings }
                            Note("a spec rescued from the account profile's old store")
                        end
                        if pull then
                            S.pulledFrom = pull.ref.sourceChar
                            src = { layoutProfiles = pull.specData.layoutProfiles,
                                activeProfile = (sd.activeProfile and pull.specData.layoutProfiles[sd.activeProfile]) and sd.activeProfile
                                    or pull.ref.profileName,
                                groupSettings = pull.specData.groupSettings or sd.groupSettings,
                                keepCDMStyle = pull.specData.keepCDMStyle }
                            IA.PullArc(C.arc, pull)
                            -- the pull brings the source's tooltip switches too
                            local sg = type(pull.char.cdmGroups) == "table" and pull.char.cdmGroups or nil
                            if sg then C.noTips = sg.disableTooltips == true end
                            Note("a shared profile's pending pull")
                        end
                        -- the spec's own switches: the Cooldown Manager's icon style, the keybinds
                        S.keepCDMStyle = src.keepCDMStyle == true
                        local gs = type(src.groupSettings) == "table" and src.groupSettings or sd.groupSettings
                        S.keybinds = type(gs) == "table" and type(gs.keybinds) == "table" and gs.keybinds or {}
                        S.raw = src.layoutProfiles
                        local shared = type(cdm.sharedSync) == "table" and cdm.sharedSync[sk] == true
                        local genName = specName and (shared and specName or (specName .. " (" .. C.name .. ")")) or nil
                        local profiles, synthesized = SpecProfiles(src, genName or "Default")
                        if synthesized then Note("a spec from before profiles") end
                        local active = IA.ResolveActive(src, profiles, genName, synthesized)
                        if src.activeProfile == nil and not synthesized then Note("a spec with no active profile stored") end
                        for _, pn in ipairs(SortedKeys(profiles)) do
                            local p = profiles[pn]
                            local P = { name = pn, active = pn == active, iconSettings = {}, groups = {},
                                talentsIgnored = type(p.talentConditions) == "table" and #p.talentConditions > 0 or nil,
                                arcSnapshot = type(p.arcAuras) == "table" and p.arcAuras or nil, synthesized = p.synthesized }
                            -- the group set: the linked account-wide one, else the profile's own,
                            -- else the three defaults
                            local link = type(p.groupLayoutName) == "string" and p.groupLayoutName ~= "" and p.groupLayoutName or nil
                            local set = link and type(global.groupLayouts) == "table" and global.groupLayouts[link] or nil
                            if type(set) ~= "table" then
                                if link then Note("a profile linked to a missing account-wide set") end
                                link, set = nil, p.groupLayouts
                            end
                            P.link = link
                            if type(set) ~= "table" or next(set) == nil then
                                set = IA.DefaultGroupRecords()
                                P.defaultGroups = true
                            end
                            for gname, ld in pairs(set) do
                                if type(gname) == "string" and type(ld) == "table" then
                                    P.groups[gname] = IA.NormalizeGroup(gname, ld)
                                end
                            end
                            P.placements = Placements(p, P.groups)
                            for id, s in pairs(type(p.iconSettings) == "table" and p.iconSettings or {}) do
                                if type(s) == "table" then P.iconSettings[tostring(id)] = s end
                            end
                            -- v1 copies its old account-profile icon table into the profile in
                            -- play at the next login, once, when that profile has none
                            if P.active and not legacyIconsDone and next(P.iconSettings) == nil
                                and type(C.globals.legacyIcons) == "table" and next(C.globals.legacyIcons)
                                and (cdm.lastActiveSpec == nil or cdm.lastActiveSpec == sk) then
                                for id, s in pairs(C.globals.legacyIcons) do
                                    if type(s) == "table" then P.iconSettings[tostring(id)] = IA.V1Migrate(s) end
                                end
                                legacyIconsDone = true
                                Note("the old account-profile icon table")
                            end
                            -- a pull lands after the flip, so pulled tables stay as the source has them
                            if flipTimers and not pull then
                                for id, s in pairs(P.iconSettings) do
                                    if id:find("^arc_timer_") then P.iconSettings[id] = IA.TimerFlip(s) end
                                end
                            end
                            S.profiles[#S.profiles + 1] = P
                            if P.active then S.active = P end
                            -- a live profile's Arc Auras snapshot fills what the character lacks
                            if P.active and P.arcSnapshot then
                                for _, store in ipairs({ "trackedItems", "trackedSpells" }) do
                                    local snap = P.arcSnapshot[store]
                                    if type(snap) == "table" then
                                        C.arc[store] = C.arc[store] or {}
                                        for id, def in pairs(snap) do
                                            if C.arc[store][id] == nil then C.arc[store][id] = Copy(def) end
                                        end
                                    end
                                end
                            end
                        end
                        if #S.profiles > 0 then C.specs[#C.specs + 1] = S end
                    end
                end
            end
            model.chars[#model.chars + 1] = C
        end
    end
    return model
end
