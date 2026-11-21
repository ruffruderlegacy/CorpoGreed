-- CorpoGreed flip / conversion calculator.
-- Model a "buy these -> get these -> sell them" hustle (ore->steel smelting,
-- Darkmoon plume->tickets->bag, buy-low-sell-high flips) and see the profit after the AH cut.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

----------------------------------------------------------------- data helpers
local function Flips() return ns.db.flips end

local function Current()
  local f = Flips()
  local i = ns.db.settings.flipSel or 1
  if i > #f then i = #f end
  if i < 1 then i = nil end
  ns.db.settings.flipSel = i
  return i and f[i] or nil, i
end

-- totals for a flip: input cost, gross sell value, value after the 5% AH cut,
-- net profit and ROI. `ok` is false when any line is missing a price.
function ns.FlipTotals(flip)
  local cost, gross, ok = 0, 0, true
  for _, r in ipairs(flip.inputs or {}) do
    local each = ns.BuyCost(r.id)
    if each then cost = cost + each * (r.qty or 1) else ok = false end
  end
  for _, r in ipairs(flip.outputs or {}) do
    local each = ns.Price(r.id)
    if each then gross = gross + each * (r.qty or 1) else ok = false end
  end
  local net = gross * (1 - ns.AH_CUT)
  local profit = net - cost
  local roi = cost > 0 and (profit / cost) or nil
  return { cost = cost, gross = gross, net = net, profit = profit, roi = roi, ok = ok }
end

local function AddItem(side, id)
  local flip = Current()
  if not flip or not id then return end
  for _, r in ipairs(flip[side]) do
    if r.id == id then r.qty = (r.qty or 1) + 1; UI.Refresh(); return end
  end
  flip[side][#flip[side] + 1] = { id = id, qty = 1 }
  UI.Refresh()
end

----------------------------------------------------------------- popups
StaticPopupDialogs["CORPOGREED_FLIPNAME"] = {
  text = L["Name this flip:"],
  button1 = ACCEPT, button2 = CANCEL,
  hasEditBox = true, maxLetters = 28, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnShow = function(self) local eb = self.editBox or self.EditBox; eb:SetText(self.data and self.data.name or ""); eb:HighlightText(); eb:SetFocus() end,
  OnAccept = function(self)
    local eb = self.editBox or self.EditBox
    local name = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local d = self.data
    if d and d.rename then
      local flip = Current(); if flip then flip.name = name end
    else
      local f = Flips()
      f[#f + 1] = { name = name, inputs = {}, outputs = {} }
      ns.db.settings.flipSel = #f
    end
    UI.Refresh()
  end,
  EditBoxOnEnterPressed = function(self) local p = self:GetParent(); if p.button1 then p.button1:Click() end end,
}

StaticPopupDialogs["CORPOGREED_FLIPQTY"] = {
  text = L["Quantity of %s:"],
  button1 = ACCEPT, button2 = CANCEL,
  hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnShow = function(self) local eb = self.editBox or self.EditBox; eb:SetNumeric(true); eb:SetText(tostring(self.data and self.data.qty or 1)); eb:HighlightText(); eb:SetFocus() end,
  OnAccept = function(self)
    local eb = self.editBox or self.EditBox
    local n = tonumber(eb:GetText())
    local d = self.data
    if d and n and n > 0 then d.row.qty = math.floor(n); UI.Refresh() end
  end,
  EditBoxOnEnterPressed = function(self) local p = self:GetParent(); if p.button1 then p.button1:Click() end end,
}

----------------------------------------------------------------- UI
local page, nameText, inBox, outBox, resultText, hint
local inList, outList

local function SideList(box, side)
  box:EnableMouse(true)
  local function drop()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then ClearCursor(); AddItem(side, id) end
  end
  box:SetScript("OnReceiveDrag", drop)
  box:SetScript("OnMouseUp", drop)
  local list = UI.ScrollList(box, 20, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 3, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.sub = UI.Text(r); r.sub:SetPoint("RIGHT", -4, 0); r.sub:SetWidth(78); r.sub:SetJustifyH("RIGHT")
    r.each = UI.Text(r); r.each:SetPoint("RIGHT", r.sub, "LEFT", -6, 0); r.each:SetWidth(62); r.each:SetJustifyH("RIGHT")
    r.qty = UI.Text(r); r.qty:SetPoint("RIGHT", r.each, "LEFT", -6, 0); r.qty:SetWidth(42); r.qty:SetJustifyH("RIGHT")
    r.name = UI.Text(r); r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.name:SetPoint("RIGHT", r.qty, "LEFT", -6, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.item.id)
      GameTooltip:AddLine(L["Click: set quantity, Right-click: remove"], 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self, btn)
      local flip, row = Current(), self.item
      if not flip then return end
      if btn == "RightButton" then
        for i, rr in ipairs(flip[side]) do if rr == row then table.remove(flip[side], i); break end end
        UI.Refresh(); return
      end
      StaticPopup_Show("CORPOGREED_FLIPQTY", ns.ItemInfo(row.id), nil, { row = row, qty = row.qty })
    end)
  end)
  list.sf:SetPoint("TOPLEFT", 3, -3); list.sf:SetPoint("BOTTOMRIGHT", -24, 3)
  return list
end

local function Build(p)
  page = p

  -- top bar: pick / new / rename / delete
  local pick = UI.Button(p, L["Flips \226\150\190"], 150, 20, function()
    local entries = {}
    for i, f in ipairs(Flips()) do
      entries[#entries + 1] = { f.name, function() ns.db.settings.flipSel = i; UI.Refresh() end }
    end
    entries[#entries + 1] = { L["|cff6fcf8f+ New flip...|r"], function() StaticPopup_Show("CORPOGREED_FLIPNAME") end }
    UI.Menu(entries)
  end)
  pick:SetPoint("TOPLEFT", 0, 0)
  nameText = UI.Text(p, "GameFontNormalLarge"); nameText:SetPoint("LEFT", pick, "RIGHT", 10, 0); nameText:SetJustifyH("LEFT")

  local del = UI.Button(p, L["Delete"], 70, 20, function()
    local flip, i = Current()
    if not flip then return end
    table.remove(Flips(), i)
    ns.db.settings.flipSel = math.min(i, #Flips())
    UI.Refresh()
  end)
  del:SetPoint("TOPRIGHT", 0, 0)
  local ren = UI.Button(p, L["Rename"], 70, 20, function()
    local flip = Current(); if flip then StaticPopup_Show("CORPOGREED_FLIPNAME", nil, nil, { rename = true, name = flip.name }) end
  end)
  ren:SetPoint("TOPRIGHT", del, "TOPLEFT", -6, 0)
  local newb = UI.Button(p, L["+ New"], 70, 20, function() StaticPopup_Show("CORPOGREED_FLIPNAME") end)
  newb:SetPoint("TOPRIGHT", ren, "TOPLEFT", -6, 0)

  -- column headers
  local inHdr = UI.Text(p, "GameFontNormal"); inHdr:SetPoint("TOPLEFT", 0, -30); inHdr:SetText(L["|cffff6f61Buy|r  (drag items here)"])
  local outHdr = UI.Text(p, "GameFontNormal"); outHdr:SetPoint("TOPLEFT", p, "TOP", 8, -30); outHdr:SetText(L["|cff6fcf8fSell|r  (drag items here)"])

  -- two boxes around the centre line
  inBox = CreateFrame("Frame", nil, p, "BackdropTemplate"); UI.Skin(inBox, 0.35)
  inBox:SetPoint("TOPLEFT", 0, -48); inBox:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -6, 54)
  outBox = CreateFrame("Frame", nil, p, "BackdropTemplate"); UI.Skin(outBox, 0.35)
  outBox:SetPoint("TOPLEFT", p, "TOP", 6, -48); outBox:SetPoint("BOTTOMRIGHT", 0, 54)

  inList = SideList(inBox, "inputs")
  outList = SideList(outBox, "outputs")

  -- big empty-state hint (shown when there are no flips at all)
  hint = UI.Text(p, "GameFontDisable"); hint:SetPoint("CENTER", 0, 20); hint:SetWidth(500)
  hint:SetText(L["No flips yet.  Click |cffffffffFlips \226\150\190|r -> |cff6fcf8f+ New flip|r, give it a name (e.g. \"Ore -> Steel\"),\nthen drag the items you BUY into the left box and the items you SELL into the right box.\nCorpoGreed fills in your tracked prices and shows the profit after the 5% AH cut."])

  -- result bar along the bottom
  local resBox = CreateFrame("Frame", nil, p, "BackdropTemplate"); UI.Skin(resBox, 0.5)
  resBox:SetPoint("BOTTOMLEFT", 0, 0); resBox:SetPoint("BOTTOMRIGHT", 0, 0); resBox:SetHeight(44)
  resultText = UI.Text(resBox, "GameFontNormal"); resultText:SetPoint("LEFT", 10, 0); resultText:SetPoint("RIGHT", -10, 0); resultText:SetJustifyH("LEFT")
end

local function FillRow(r, row, isInput)
  r.icon:SetTexture(ns.Icon(row.id))
  r.name:SetText(ns.ColoredName(row.id))
  r.qty:SetText("x" .. (row.qty or 1))
  local each
  if isInput then each = ns.BuyCost(row.id) else each = ns.Price(row.id) end
  r.each:SetText(each and ns.Money(each) or "|cff808080?|r")
  r.sub:SetText(each and ns.Money(each * (row.qty or 1)) or "|cff808080-|r")
end

local function Refresh()
  if not page then return end
  local flip = Current()
  local has = flip ~= nil
  if hint then hint:SetShown(not has) end
  if inBox then inBox:SetShown(has) end
  if outBox then outBox:SetShown(has) end

  nameText:SetText(has and flip.name or L["|cff808080(no flip selected)|r"])

  if not has then
    inList:Set({}, function() end); outList:Set({}, function() end)
    resultText:SetText("")
    return
  end

  inList:Set(flip.inputs, function(r, row) FillRow(r, row, true) end)
  outList:Set(flip.outputs, function(r, row) FillRow(r, row, false) end)

  local t = ns.FlipTotals(flip)
  local col = t.profit >= 0 and "|cff6fcf8f" or "|cffff6f61"
  local sign = t.profit >= 0 and "+" or "-"
  local roi = t.roi and ((" (%s%d%%)"):format(sign, math.floor(math.abs(t.roi) * 100 + 0.5))) or ""
  resultText:SetText(
    (L["Buy: %s"]):format(ns.Money(t.cost)) ..
    "   |cff808080->|r   " ..
    (L["Sell: %s  (after 5%% cut: %s)"]):format(ns.Money(t.gross), ns.Money(t.net)) ..
    "        " ..
    (L["Profit: %s%s%s|r%s"]):format(col, sign, ns.Money(math.abs(t.profit), true), roi) ..
    (t.ok and "" or L["   |cff808080(some prices missing - do a Full Scan)|r"])
  )
end

UI.AddTab("Flip", 40, Build, Refresh)
