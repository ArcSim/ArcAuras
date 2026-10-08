-- AD_ItemSets: ready-made item lists for item icons (Healthstone, Healing Potion, ...) and their picks in the Add window.
-- AD_Options builds the Add window and calls Options.ItemSetAddRows; the icon runtime is the cooldown driver's.
-- The lists are WoW Forever's own item IDs, best first; elsewhere none are offered.
local ADDON, NS = ...

local IS = {}
NS.ItemSets = IS

-- Each list: its words, the item whose art stands for it, and its items in the
-- order the icon prefers them (it shows the first one you carry and can use).
IS.FOREVER = {
    { key = "healthstone", name = "Healthstone", art = 9421,
      ids = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 } },
    { key = "healing", name = "Healing Potion", art = 13446,
      ids = { 13446, 23579, 223913, 241650, 17348, 3928, 18839, 247242, 17349, 1710, 223914, 247241,
          929, 247240, 268883, 858, 247239, 268882, 118, 4596, 268881, 282011 } },
    { key = "mana", name = "Mana Potion", art = 13444,
      ids = { 13444, 23578, 17351, 13443, 18841, 17352, 6149, 3827, 3385, 2455, 3087, 282013 } },
    { key = "rejuvenation", name = "Rejuvenation Potion", art = 18253,
      ids = { 18253, 274935, 9144, 2456 } },
    { key = "rage", name = "Rage Potion", art = 13442,
      ids = { 13442, 5633, 5631 } },
    { key = "bandage", name = "Bandage", art = 14530,
      ids = { 232433, 23684, 14530, 14529, 8545, 8544, 6451, 6450, 3531, 3530, 2581, 1251 } },
    -- every item sharing the food cooldown, best first (Well Fed buff foods have
    -- their own and are not here)
    { key = "food", name = "Food", art = 4540,
      ids = { 22895, 238637, 238638, 238639, 238641, 238642, 262433, 8076, 8932, 8948, 8950, 8952, 8953,
          8959, 11415, 11444, 11950, 12763, 13810, 13888, 13889, 13893, 16171, 18255, 19225, 21031, 21033,
          22324, 23160, 232436, 260627, 260628, 278122, 23175, 16971, 3927, 4599, 4601, 4602, 4603, 4608,
          8075, 9681, 13754, 13755, 13756, 13758, 13759, 13760, 16168, 17408, 18635, 19306, 21030, 21552,
          232438, 260624, 260625, 6807, 1487, 1707, 3771, 4539, 4544, 4607, 6362, 8365, 8543, 13546, 16169,
          17407, 18632, 19224, 260623, 278118, 278120, 422, 1114, 3664, 3770, 4538, 4542, 4606, 5845, 6308,
          7228, 16170, 19305, 248613, 249793, 278121, 1119, 1326, 3448, 414, 1113, 2287, 2684, 4537, 4541,
          4605, 5066, 5479, 6289, 6317, 6361, 6458, 12213, 16167, 17119, 17406, 18633, 19304, 252030,
          278117, 6522, 251524, 5474, 6657, 6888, 17197, 17198, 251525, 206177, 4656, 5057, 117, 4604, 961,
          2070, 4536, 4540, 11584, 5349, 6291, 6299, 6303, 7097, 7806, 7807, 7808, 11109, 16166, 17344,
          19223, 251917, 252022, 252023, 252028, 267474, 278119, 278265, 278569 } },
    -- every item sharing the drink cooldown, best first
    { key = "drink", name = "Drink", art = 159,
      ids = { 8079, 18300, 231778, 227813, 19318, 8078, 8766, 13813, 23161, 285359, 19997, 21241, 1645,
          8077, 19300, 1708, 3772, 4600, 4791, 17405, 1205, 2136, 9451, 19299, 5342, 4953, 4952, 1179, 2288,
          17404, 1262, 159, 5350, 252031, 5265 } },
    { key = "managem", name = "Mana Gem", art = 8008,
      ids = { 8008, 8007, 5513, 5514 } },
    { key = "conjuredfood", name = "Conjured Food", art = 8076,
      ids = { 22895, 8076, 8075, 1487, 1114, 1113, 5349 } },
    { key = "conjuredwater", name = "Conjured Water", art = 8079,
      ids = { 8079, 8078, 8077, 3772, 2136, 2288, 5350 } },
}

-- the lists this client gets
function IS.List()
    return NS.IsForever == true and IS.FOREVER or {}
end

function IS.Get(key)
    for _, s in ipairs(IS.List()) do
        if s.key == key then return s end
    end
    return nil
end

IS.CELL, IS.PITCH = 32, 36

-- One square per list, on the label margin: a click fills the Item IDs field
-- and names the new icon after the list; the pick stays cyan.
function IS.AddRows(pg, owner, addState, vis, onPick)
    local AT, COL = NS.AT, NS.AT.COL
    local list = IS.List()
    if #list == 0 then return end
    local row = AT.AddRow(pg, IS.PITCH + 8, vis)
    local cells = {}
    for i, s in ipairs(list) do
        local b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(IS.CELL, IS.CELL)
        b:SetPoint("LEFT", row, "LEFT", 10 + (i - 1) * IS.PITCH, 0)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.tex:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(s.art) or 134400)
        function b.Edge(hot)
            local c = (addState.itemSet == s.key and COL.arc) or (hot and COL.focus) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(s.name, COL.ink[1], COL.ink[2], COL.ink[3])
            GameTooltip:AddLine(("Any of %d items: the icon shows the best one you carry and can use."):format(#s.ids),
                COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            local t = {}
            for k, id in ipairs(s.ids) do t[k] = tostring(id) end
            addState.itemID, addState.itemName, addState.itemSet = table.concat(t, ", "), s.name, s.key
            AT.LayoutPage(pg)
            if onPick then onPick() end
        end)
        b._adSet = s.key
        cells[i] = b
    end
    row._cells = cells
    row._sync = function()
        for _, b in ipairs(cells) do b.Edge(false) end
    end
    return row
end

-- AD_Options loads first and calls this while building the Add window
if NS.Options then NS.Options.ItemSetAddRows = IS.AddRows end
