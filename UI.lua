-- CorpoGreed UI: flat transparent window with Prices / Crafting / Sales tabs.
local ADDON, ns = ...
local L = ns.L
local UI = { tabDefs = {} }
ns.UI = UI

-- Modules register tabs before the frame is built: name, sort order, build(page), refresh().
function UI.AddTab(name, order, build, refresh)
  table.insert(UI.tabDefs, { name = name, order = order, build = build, refresh = refresh })
end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ACCENT = { 0.22, 0.53, 0.9 }
local FONT = "GameFontHighlightSmall"
local RANGES = { { "24h", 86400 }, { "7d", 7 * 86400 }, { L["All"], nil } }

---------------------------------------------------------------- style helpers
local function Skin(f, alpha)
  if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(0.04, 0.04, 0.05, alpha or 0.8)
  f:SetBackdropBorderColor(0, 0, 0, 1)
end

local function Text(parent, template, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or FONT)
  if size then local font, _, flags = fs:GetFont(); fs:SetFont(font, size, flags) end
  return fs
end

local function Button(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 70, h or 20)
  Skin(b, 0.6)
  b.text = Text(b); b.text:SetPoint("CENTER"); b.text:SetText(label)
  b:SetScript("OnEnter", function(self) if self:IsEnabled() then self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) end end)
  b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
  b:SetScript("OnClick", onClick)
  function b:SetActive(on)
    self.active = on
    self:SetBackdropColor(on and ACCENT[1] * 0.5 or 0.04, on and ACCENT[2] * 0.5 or 0.04, on and ACCENT[3] * 0.5 or 0.05, on and 0.9 or 0.6)
  end
  hooksecurefunc(b, "Disable", function(self) self.text:SetTextColor(0.5, 0.5, 0.5) end)
  hooksecurefunc(b, "Enable", function(self) self.text:SetTextColor(1, 1, 1) end)
  return b
end
UI.Button, UI.Skin, UI.Text = Button, Skin, Text

local function ScrollList(parent, rowHeight, makeRow)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  sf:SetScrollChild(child)
  sf:HookScript("OnSizeChanged", function(self, w) child:SetWidth(w) end)
  local list = { sf = sf, child = child, rows = {} }
  function list:Set(items, fill)
    for i, item in ipairs(items) do
      local r = self.rows[i]
      if not r then
        r = CreateFrame("Button", nil, child)
        r:SetHeight(rowHeight)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight); r:SetPoint("RIGHT", child, "RIGHT")
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1); r.sel:SetAllPoints(); r.sel:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.3); r.sel:Hide()
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        makeRow(r)
        self.rows[i] = r
      end
      r.item = item
      fill(r, item)
      r:Show()
    end
    for i = #items + 1, #self.rows do self.rows[i]:Hide() end
    child:SetHeight(math.max(1, #items * rowHeight))
  end
  return list
end
UI.ScrollList = ScrollList

-- A table page: header buttons that sort, rows of cells. cols = { {key, label, w, align}, ... }
function UI.Table(page, top, cols, onRow)
  local t = { cols = cols, sort = { key = cols[1].key, desc = false } }
  local header = CreateFrame("Frame", nil, page)
  header:SetPoint("TOPLEFT", 0, -top); header:SetPoint("TOPRIGHT", 0, -top); header:SetHeight(18)
  local x = 24
  for _, col in ipairs(cols) do
    local b = CreateFrame("Button", nil, header)
    b:SetPoint("LEFT", x, 0); b:SetSize(col.w, 18)
    b.text = Text(b, "GameFontNormalSmall"); b.text:SetAllPoints(); b.text:SetJustifyH(col.align or "RIGHT")
    b:SetScript("OnClick", function()
      if t.sort.key == col.key then t.sort.desc = not t.sort.desc else t.sort.key, t.sort.desc = col.key, col.align ~= "LEFT" end
      if t.onSort then t.onSort() end
    end)
    col.btn = b
    x = x + col.w + 6
  end
  local box = CreateFrame("Frame", nil, page, "BackdropTemplate"); Skin(box, 0.35)
  box:SetPoint("TOPLEFT", 0, -(top + 20)); box:SetPoint("BOTTOMRIGHT")
  t.list = ScrollList(box, 20, function(r)
    r.dot = r:CreateTexture(nil, "ARTWORK"); r.dot:SetSize(8, 8); r.dot:SetPoint("LEFT", 6, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 22, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.cells = {}
    local cx = 24
    for i, col in ipairs(cols) do
      local fs = Text(r)
      if i == 1 then fs:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); fs:SetWidth(col.w - 20)
      else fs:SetPoint("LEFT", cx, 0); fs:SetWidth(col.w) end
      fs:SetJustifyH(col.align or "RIGHT"); fs:SetWordWrap(false)
      r.cells[i] = fs
      cx = cx + col.w + 6
    end
    if onRow then onRow(r) end
  end)
  t.list.sf:SetPoint("TOPLEFT", 3, -3); t.list.sf:SetPoint("BOTTOMRIGHT", -24, 3)
  function t:Set(rows, fill)
    local s = self.sort
    -- stable sort: equal values tie-break by a fixed identity so rows never swap between redraws
    local function tie(r) return tostring(r.name or r.id or r.cat or "") end
    table.sort(rows, function(a, b)
      local va, vb = a[s.key], b[s.key]
      if va == vb then return tie(a) < tie(b) end
      if va == nil then return false elseif vb == nil then return true end
      if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
      if va == vb then return tie(a) < tie(b) end
      if s.desc then return va > vb else return va < vb end
    end)
    -- skip the redraw entirely when the sorted data is identical to last time (stops flicker)
    local sig = {}
    for i, r in ipairs(rows) do sig[i] = tie(r) .. "=" .. tostring(r[s.key]) end
    local key = table.concat(sig, "|") .. "#" .. tostring(s.key) .. (s.desc and "d" or "a")
    if key == self._sig then return end
    self._sig = key
    for _, col in ipairs(self.cols) do col.btn.text:SetText(col.label .. (s.key == col.key and (s.desc and " v" or " ^") or "")) end
    self.list:Set(rows, fill)
  end
  return t
end

-- tiny right-click menu: entries = { {text, func}, ... }
local menu
function UI.Menu(entries)
  if not menu then
    menu = CreateFrame("Frame", "CorpoGreedMenu", UIParent, "BackdropTemplate")
    Skin(menu, 0.95); menu:SetFrameStrata("TOOLTIP"); menu:EnableMouse(true); menu.btns = {}
    menu:SetScript("OnUpdate", function(self)
      if not self:IsMouseOver(12, -12, -12, 12) and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then self:Hide() end
    end)
  end
  for i, e in ipairs(entries) do
    local b = menu.btns[i]
    if not b then
      b = CreateFrame("Button", nil, menu); b:SetHeight(18)
      b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18); b:SetPoint("RIGHT", -4, 0)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
      b.text = Text(b); b.text:SetPoint("LEFT", 4, 0)
      menu.btns[i] = b
    end
    b.text:SetText(e[1]); b:SetScript("OnClick", function() menu:Hide(); e[2]() end); b:Show()
  end
  for i = #entries + 1, #menu.btns do menu.btns[i]:Hide() end
  menu:SetSize(190, 8 + #entries * 18)
  local x, y = GetCursorPosition(); local s = UIParent:GetEffectiveScale()
  menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 4, y / s + 4)
  menu:Show()
end

function UI.ItemMenu(id, extra)
  local entries = extra or {}
  -- favourite toggle (favouriting also tracks, so the chart stays fed)
  table.insert(entries, { ns.db.favs[id] and L["Remove from favourites"] or L["Add to favourites"], function()
    ns.db.favs[id] = not ns.db.favs[id] or nil
    if ns.db.favs[id] then ns.db.watch[id] = true end
    UI.Refresh()
  end })
  -- toggle membership of each custom list
  local names = {}
  for n in pairs(ns.db.lists) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do
    local inlist = ns.db.lists[n][id]
    table.insert(entries, { (inlist and "|cff6fcf8f* |r" or "|cff808080+ |r") .. n, function()
      if inlist then ns.db.lists[n][id] = nil
      else ns.db.lists[n][id] = true; ns.db.watch[id] = true end
      UI.Refresh()
    end })
  end
  table.insert(entries, { L["New list..."], function() UI.NewListPopup(id) end })
  table.insert(entries, { ns.IsIgnored(id) and L["Stop ignoring"] or L["Ignore this item"], function() ns.ToggleIgnore(id) end })
  table.insert(entries, { ns.db.watch[id] and L["Stop tracking price"] or L["Track price"], function() ns.db.watch[id] = not ns.db.watch[id] or nil; UI.Refresh() end })
  table.insert(entries, { L["Search on AH"], function() UI.SearchAH(ns.ItemInfo(id)) end })
  UI.Menu(entries)
end

-- popup to create a new custom list; addId (optional) is dropped into the new list
function UI.NewListPopup(addId)
  StaticPopupDialogs["CORPOGREED_NEWLIST"] = StaticPopupDialogs["CORPOGREED_NEWLIST"] or {
    text = L["Name your new list:"],
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 24,
    OnAccept = function(self)
      local name = (self.editBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if name == "" or name == "all" or name == "fav" then return end
      ns.db.lists[name] = ns.db.lists[name] or {}
      if self.data then ns.db.lists[name][self.data] = true; ns.db.watch[self.data] = true end
      ns.db.settings.list = "list:" .. name
      UI.RefreshPrices()
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent(); if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
  local dlg = StaticPopup_Show("CORPOGREED_NEWLIST")
  if dlg then dlg.data = addId end
end

-- popup to rename a list
function UI.RenameListPopup(old)
  StaticPopupDialogs["CORPOGREED_RENAMELIST"] = {
    text = L["Rename list to:"],
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 24,
    OnShow = function(self) self.editBox:SetText(self.data or "") end,
    OnAccept = function(self)
      local name = (self.editBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if name == "" or name == self.data or not ns.db.lists[self.data] then return end
      ns.db.lists[name] = ns.db.lists[self.data]; ns.db.lists[self.data] = nil
      if ns.db.settings.list == "list:" .. self.data then ns.db.settings.list = "list:" .. name end
      UI.RefreshPrices()
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent(); if p.button1 then p.button1:Click() end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
  local dlg = StaticPopup_Show("CORPOGREED_RENAMELIST")
  if dlg then dlg.data = old end
end

-- right-click menu on a list chip: rename / delete
function UI.ListChipMenu(name)
  UI.Menu({
    { L["Rename list"], function() UI.RenameListPopup(name) end },
    { L["Delete list"], function()
      StaticPopupDialogs["CORPOGREED_DELLIST"] = {
        text = L["Delete the list \"%s\"? (items stay tracked)"],
        button1 = YES, button2 = NO,
        OnAccept = function(self)
          ns.db.lists[self.data] = nil
          if ns.db.settings.list == "list:" .. self.data then ns.db.settings.list = nil end
          UI.RefreshPrices()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
      local dlg = StaticPopup_Show("CORPOGREED_DELLIST", name)
      if dlg then dlg.data = name end
    end },
  })
end

function UI.Dot(tex, hex)
  tex:SetColorTexture(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1)
end

---------------------------------------------------------------- main frame
local function BuildFrame()
  local f = CreateFrame("Frame", "CorpoGreedFrame", UIParent, "BackdropTemplate")
  local st = ns.db.settings
  -- one-time bump: the Settings page needs ~600 tall so its right column doesn't spill past the bottom border
  if not st.heightBumped then st.height = math.max(st.height or 0, 600); st.heightBumped = true end
  f:SetSize(math.max(st.width or 900, 880), st.height or 600); f:SetFrameStrata("HIGH"); f:SetToplevel(true)
  if st.point then f:SetPoint(st.point, UIParent, st.point, st.x or 0, st.y or 0) else f:SetPoint("CENTER") end
  Skin(f, st.opacity or 0.82)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(880, 560, 1600, 1100) elseif f.SetMinResize then f:SetMinResize(880, 560) end
  local function SavePos()
    local p, _, _, x, y = f:GetPoint()
    st.point, st.x, st.y = p, x, y
    st.width, st.height = math.floor(f:GetWidth()), math.floor(f:GetHeight())
  end
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePos() end)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); SavePos(); UI.Refresh() end)
  tinsert(UISpecialFrames, "CorpoGreedFrame")
  UI.frame = f

  local top = CreateFrame("Frame", nil, f); top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(28)
  local tbg = top:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints(); tbg:SetColorTexture(0, 0, 0, 0.45)
  local title = Text(top, "GameFontNormal"); title:SetPoint("LEFT", 10, 0)
  title:SetText(L["|cff3987e5Corpo|rGreed"])

  local close = Button(top, "x", 22, 20, function() f:Hide() end); close:SetPoint("RIGHT", -4, 0)
  UI.closeBtn = close

  UI.tabs, UI.pages = {}, {}
  table.sort(UI.tabDefs, function(a, b) return a.order < b.order end)
  for i, def in ipairs(UI.tabDefs) do
    local b = Button(top, L[def.name], 70, 20, function() UI.ShowTab(i) end)
    b:SetPoint("LEFT", title, "RIGHT", 12 + (i - 1) * 73, 0)
    UI.tabs[i] = b
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", 8, -36); page:SetPoint("BOTTOMRIGHT", -8, 28)
    page:Hide()
    UI.pages[i] = page
  end

  UI.scanBtn = Button(top, L["Full Scan"], 90, 20, function() ns.FullScan() end)
  UI.scanBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)

  local status = Text(f, "GameFontDisableSmall"); status:SetPoint("BOTTOMLEFT", 10, 9)
  UI.status = status
  local hint = Text(f, "GameFontDisableSmall"); hint:SetPoint("BOTTOMRIGHT", -24, 9)
  hint:SetText(L["/cg, drag items onto the chart to track them"])
  UI.hint = hint

  f:SetScript("OnUpdate", function(self, el)
    self.tick = (self.tick or 0) + el
    if self.tick < 1 then return end
    self.tick = 0
    UI.UpdateStatus()
  end)
  f:SetScript("OnShow", function() UI.Refresh() end)
  f:Hide()
  UI.ApplyLook()
end

-- window scale + background opacity from Settings
function UI.ApplyLook()
  local f, st = UI.frame, ns.db.settings
  if not f then return end
  f:SetScale(st.scale or 1.4)
  if UI.ahButton then UI.ahButton:SetScale(st.scale or 1.4) end
  if UI.sellBar then UI.sellBar:SetScale(st.scale or 1.4) end
  f:SetBackdropColor(0.04, 0.04, 0.05, st.opacity or 0.82)
end

function UI.UpdateStatus()
  local left = ns.ScanCooldownLeft()
  local ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()
  if ns.IsScanning() then
    UI.scanBtn.text:SetText(UI.scanPct and (L["Scanning "] .. math.floor(UI.scanPct * 100) .. "%") or L["Scanning..."])
    UI.scanBtn:Disable()
  elseif left > 0 then
    UI.scanBtn.text:SetText((L["Scan in %d:%02d"]):format(math.floor(left / 60), left % 60)); UI.scanBtn:Disable()
  else
    UI.scanBtn.text:SetText(L["Full Scan"])
    if ahOpen then
      UI.scanBtn:Enable()
      -- auto-scan: the moment the cooldown is up and the AH is open, scan again (as often as the server allows)
      if ns.db.settings.autoScan and not ns.IsScanning() then ns.FullScan() end
    else
      UI.scanBtn:Disable()
    end
  end
  local last = ns.db.lastFullScan
  local n = 0
  for _ in pairs(ns.db.prices) do n = n + 1 end
  if ns.lastMsg and time() - ns.lastMsgT < 15 then UI.status:SetText("|cffffd24a" .. ns.lastMsg .. "|r") return end
  UI.status:SetText(("%d items priced, last full scan %s"):format(n,
    last and (SecondsToTime and SecondsToTime(time() - last, true) .. L[" ago"] or date("%H:%M", last)) or "never"))
end

ns.scanFrame = { SetProgress = function(_, pct) UI.scanPct = pct; if UI.frame and UI.frame:IsShown() then UI.UpdateStatus() end end }

function UI.ShowTab(i)
  ns.db.settings.tab = i
  for j, b in ipairs(UI.tabs) do b:SetActive(j == i); UI.pages[j]:SetShown(j == i) end
  UI.Refresh()
end

function UI.Refresh()
  if not (UI.frame and UI.frame:IsShown()) then return end
  local tab = ns.db.settings.tab or 1
  for j, b in ipairs(UI.tabs) do b:SetActive(j == tab); UI.pages[j]:SetShown(j == tab) end
  UI.UpdateStatus()
  local def = UI.tabDefs[tab]
  -- the bottom status line + hint overlap the Settings page content, so hide them there
  local onSettings = def and def.name == "Settings"
  if UI.status then UI.status:SetShown(not onSettings) end
  if UI.hint then UI.hint:SetShown(not onSettings) end
  if def and def.refresh then def.refresh() end
end

-- coalesced refresh. The chart tabs stay snappy; the heavy tables (Deals / Ledger / Advisor) only
-- redraw on a slow interval so their rows stop flickering while the AH streams price updates.
local refreshQueued = false
function UI.RefreshSoon()
  if refreshQueued or not (UI.frame and UI.frame:IsShown()) then return end
  refreshQueued = true
  local fast = UI.TabIs("Prices") or UI.TabIs("Crafting")
  local delay = fast and 0.5 or (ns.db.settings.refreshSec or 60)
  C_Timer.After(delay, function() refreshQueued = false; UI.Refresh() end)
end

function UI.TabIs(name)
  local def = UI.tabDefs[ns.db.settings.tab or 1]
  return UI.frame and UI.frame:IsShown() and def and def.name == name
end

function UI.ShowTabByName(name)
  for i, def in ipairs(UI.tabDefs) do if def.name == name then
    UI.frame:Show(); UI.ShowTab(i)
    return end end
end


---------------------------------------------------------------- Prices tab
local function PricesPage(page)
  local search = CreateFrame("EditBox", nil, page, "BackdropTemplate")
  Skin(search, 0.6); search:SetSize(220, 20); search:SetPoint("TOPLEFT", 0, 0)
  search:SetFontObject(FONT); search:SetTextInsets(6, 6, 0, 0); search:SetAutoFocus(false)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  search:SetScript("OnTextChanged", function() UI.RefreshPrices() end)
  search.ph = Text(search, "GameFontDisableSmall"); search.ph:SetPoint("LEFT", 6, 0); search.ph:SetText(L["Search tracked items..."])
  UI.search = search

  -- list-filter chips: All / Favs / custom lists / +  (wraps to a second row if needed)
  local chipBar = CreateFrame("Frame", nil, page)
  chipBar:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4); chipBar:SetSize(220, 20)
  UI.chipBar, UI.chips = chipBar, {}

  local box = CreateFrame("Frame", nil, page, "BackdropTemplate"); Skin(box, 0.35)
  box:SetPoint("TOPLEFT", chipBar, "BOTTOMLEFT", 0, -4); box:SetPoint("BOTTOMLEFT", 0, 0); box:SetWidth(220)
  UI.priceList = ScrollList(box, 22, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 3, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = Text(r); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetWidth(100); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.price = Text(r); r.price:SetPoint("RIGHT", -4, 0); r.price:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then
        UI.ItemMenu(self.item)
        return
      end
      UI.selected = self.item
      UI.RefreshPrices()
    end)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.item)
      GameTooltip:AddLine(L["Right-click: favourite, lists, menu"], 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
  end)
  UI.priceList.sf:SetPoint("TOPLEFT", 3, -3); UI.priceList.sf:SetPoint("BOTTOMRIGHT", -24, 3)

  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", box, "TOPRIGHT", 12, 24); right:SetPoint("BOTTOMRIGHT")
  UI.header = Text(right, "GameFontNormalLarge"); UI.header:SetPoint("TOPLEFT", 0, 0); UI.header:SetJustifyH("LEFT")
  UI.sub = Text(right); UI.sub:SetPoint("TOPLEFT", UI.header, "BOTTOMLEFT", 0, -4); UI.sub:SetJustifyH("LEFT")

  UI.rangeBtns = {}
  for i = #RANGES, 1, -1 do
    local b = Button(right, RANGES[i][1], 40, 18, function() ns.db.settings.range = i; UI.RefreshPrices() end)
    if i == #RANGES then b:SetPoint("TOPRIGHT", 0, 0) else b:SetPoint("RIGHT", UI.rangeBtns[i + 1], "LEFT", -3, 0) end
    UI.rangeBtns[i] = b
  end

  local c = CreateFrame("Frame", nil, right, "BackdropTemplate"); Skin(c, 0.35)
  -- price axis now lives on the RIGHT (TradingView-style): small left gutter, wider right gutter for labels/tags
  c:SetPoint("TOPLEFT", 8, -48); c:SetPoint("BOTTOMRIGHT", -52, 84)
  c.lines, c.dots, c.grid = {}, {}, {}
  for k, frac in ipairs({ 0.25, 0.5, 0.75 }) do
    local g = c:CreateTexture(nil, "BORDER"); g:SetColorTexture(1, 1, 1, 0.06); g:SetHeight(1)
    c.grid[k] = { g, frac }
  end
  c:SetScript("OnSizeChanged", function(self, w, h)
    for _, gg in ipairs(self.grid) do
      gg[1]:ClearAllPoints(); gg[1]:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, h * gg[2]); gg[1]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, h * gg[2])
    end
    UI.RefreshPrices()
  end)
  c.hiTxt = Text(c); c.hiTxt:SetPoint("TOPRIGHT", c, "TOPLEFT", -4, 0)
  c.loTxt = Text(c); c.loTxt:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", -4, 0)
  c.t0 = Text(c, "GameFontDisableSmall"); c.t0:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -3)
  c.t1 = Text(c, "GameFontDisableSmall"); c.t1:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", 0, -3)
  c.empty = Text(c, "GameFontDisable"); c.empty:SetPoint("CENTER")
  c.cross = c:CreateTexture(nil, "OVERLAY"); c.cross:SetColorTexture(1, 1, 1, 0.35); c.cross:SetWidth(1); c.cross:Hide()
  -- horizontal crosshair + a price tag on the right axis that follow the cursor
  c.crossH = c:CreateTexture(nil, "OVERLAY"); c.crossH:SetColorTexture(1, 1, 1, 0.22); c.crossH:SetHeight(1); c.crossH:Hide()
  local function AxisTag(accent)
    local t = CreateFrame("Frame", nil, c, "BackdropTemplate"); Skin(t, 0.95)
    t:SetSize(48, 14); t:Hide(); t:SetFrameStrata("HIGH")
    t.text = Text(t, "GameFontHighlightSmall"); t.text:SetPoint("CENTER", 0, 0)
    return t
  end
  c.axisTag = AxisTag()   -- hovered price
  c.lastTag = AxisTag()   -- latest price (always on while data is shown)
  c:EnableMouse(true)
  c:SetScript("OnUpdate", function(self) if self.pts and self:IsMouseOver() then UI.ChartHover(self) end end)
  c:SetScript("OnLeave", function(self)
    self.hoverIdx = nil; self.cross:Hide()
    if self.crossH then self.crossH:Hide() end
    if self.axisTag then self.axisTag:Hide() end
    GameTooltip:Hide()
  end)
  local function Drop()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
      ClearCursor(); ns.db.watch[id] = true; UI.selected = id
      ns.Print(ns.ColoredName(id) .. L[" is now tracked."]); UI.RefreshPrices()
    end
  end
  c:SetScript("OnReceiveDrag", Drop); c:SetScript("OnMouseUp", Drop)
  UI.chart = c
  if ns.BuildChartControls then ns.BuildChartControls(right) end

  UI.blocks = {}
  for i = 1, 4 do
    local b = CreateFrame("Frame", nil, right, "BackdropTemplate"); Skin(b, 0.35)
    UI.blocks[i] = b
    b.text = Text(b); b.text:SetPoint("CENTER")
  end
  local function LayoutBlocks()
    local w = (c:GetWidth() - 18) / 4
    for i, b in ipairs(UI.blocks) do
      b:ClearAllPoints(); b:SetSize(math.max(w, 60), 40)
      if i == 1 then b:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -20) else b:SetPoint("LEFT", UI.blocks[i - 1], "RIGHT", 6, 0) end
    end
  end
  c:HookScript("OnSizeChanged", LayoutBlocks)
  LayoutBlocks()
  local cap = Text(right, "GameFontDisableSmall"); cap:SetPoint("TOPLEFT", UI.blocks[1], "BOTTOMLEFT", 0, -3)
  cap:SetText(L["Average price by time of day - buy in the cheapest block, sell in the priciest"])
end

-- chart drawing lives in Chart.lua
function UI.ChartHover(c) if ns.ChartHover then ns.ChartHover(c) end end
local function DrawChart() if ns.DrawChart then ns.DrawChart() end end

-- (re)build the filter chips under the search box from favourites + custom lists
function UI.RefreshListChips()
  local bar = UI.chipBar
  if not bar then return end
  local cur = ns.db.settings.list or "all"
  local defs = {
    { key = "all", label = L["All"] },
    { key = "fav", label = L["Favs"] },
  }
  local names = {}
  for name in pairs(ns.db.lists) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do defs[#defs + 1] = { key = "list:" .. name, label = name, list = name } end
  defs[#defs + 1] = { key = "new", label = "+" }

  local x, y, rowH, maxW = 0, 0, 20, 220
  for i, d in ipairs(defs) do
    local chip = UI.chips[i]
    if not chip then
      chip = UI.Button(bar, "", 20, 17)
      chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      UI.chips[i] = chip
    end
    chip.text:SetText(d.label)
    local w = math.max(math.floor(chip.text:GetStringWidth() + 0.5) + 14, 20)
    if x > 0 and x + w > maxW then x = 0; y = y - rowH end
    chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", x, y); chip:SetWidth(w)
    x = x + w + 3
    chip:SetActive(cur == d.key)
    chip:SetScript("OnClick", function(_, btn)
      if d.key == "new" then
        UI.NewListPopup()
      elseif btn == "RightButton" and d.list then
        UI.ListChipMenu(d.list)
      else
        ns.db.settings.list = (d.key == "all") and nil or d.key
        UI.RefreshPrices()
      end
    end)
    chip:Show()
  end
  for i = #defs + 1, #UI.chips do UI.chips[i]:Hide() end
  bar:SetHeight(rowH - y)
end

function UI.RefreshPrices()
  if not (UI.priceList and UI.blocks and #UI.blocks == 4) then return end
  local q = (UI.search:GetText() or ""):lower()
  UI.search.ph:SetShown(q == "" and not UI.search:HasFocus())
  -- pick the item source from the active filter chip
  local sel = ns.db.settings.list
  if sel and sel:match("^list:") and not ns.db.lists[sel:sub(6)] then ns.db.settings.list, sel = nil, nil end
  local source = ns.db.watch
  if sel == "fav" then source = ns.db.favs
  elseif sel and sel:match("^list:") then source = ns.db.lists[sel:sub(6)] or ns.db.watch end
  UI.RefreshListChips()
  local ids = {}
  for id in pairs(source) do
    if q == "" or ns.ItemInfo(id):lower():find(q, 1, true) then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b) return ns.ItemInfo(a) < ns.ItemInfo(b) end)
  -- keep the charted item valid for the current filter
  if UI.selected and not source[UI.selected] then UI.selected = nil end
  if not UI.selected then UI.selected = ids[1] end
  UI.priceIds = ids
  if ns.SyncChartToggles then ns.SyncChartToggles() end
  UI.priceList:Set(ids, function(r, id)
    r.icon:SetTexture(ns.Icon(id))
    r.name:SetText((ns.db.favs[id] and "|cffffd100*|r" or "") .. ns.ColoredName(id))
    local p = ns.Price(id)
    r.price:SetText(p and ns.Money(p) or "|cff808080-|r")
    r.sel:SetShown(UI.selected == id)
  end)
  for i, b in ipairs(UI.rangeBtns) do b:SetActive((ns.db.settings.range or 3) == i) end
  DrawChart()
end

---------------------------------------------------------------- Crafting tab
local COLS = {
  { key = "name", label = L["Recipe"], w = 230 },
  { key = "cost", label = L["Cost"], w = 90 },
  { key = "sell", label = L["AH value"], w = 90 },
  { key = "profit", label = L["Profit"], w = 90 },
  { key = "pct", label = "ROI", w = 55 },
  { key = "qty", label = L["Listed"], w = 55 },
  { key = "avg7", label = L["7d avg"], w = 90 },
}

local function CraftingPage(page)
  UI.profBtns = {}
  UI.craftSort = { key = "profit", desc = true }

  local header = CreateFrame("Frame", nil, page); header:SetPoint("TOPLEFT", 0, -26); header:SetPoint("TOPRIGHT", 0, -26); header:SetHeight(18)
  local x = 24
  for _, col in ipairs(COLS) do
    local b = CreateFrame("Button", nil, header)
    b:SetPoint("LEFT", x, 0); b:SetSize(col.w, 18)
    b.text = Text(b, "GameFontNormalSmall"); b.text:SetAllPoints()
    b.text:SetJustifyH(col.key == "name" and "LEFT" or "RIGHT")
    b:SetScript("OnClick", function()
      if UI.craftSort.key == col.key then UI.craftSort.desc = not UI.craftSort.desc
      else UI.craftSort.key, UI.craftSort.desc = col.key, col.key ~= "name" end
      UI.RefreshCrafting()
    end)
    col.btn = b
    x = x + col.w + 6
  end

  local box = CreateFrame("Frame", nil, page, "BackdropTemplate"); Skin(box, 0.35)
  box:SetPoint("TOPLEFT", 0, -46); box:SetPoint("BOTTOMRIGHT")
  UI.craftList = ScrollList(box, 20, function(r)
    r.dot = r:CreateTexture(nil, "ARTWORK"); r.dot:SetSize(8, 8); r.dot:SetPoint("LEFT", 8, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 22, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.cells = {}
    local cx = 24
    for i, col in ipairs(COLS) do
      local fs = Text(r)
      if i == 1 then fs:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); fs:SetWidth(col.w - 20)
      else fs:SetPoint("LEFT", cx, 0); fs:SetWidth(col.w) end
      fs:SetJustifyH(i == 1 and "LEFT" or "RIGHT"); fs:SetWordWrap(false)
      r.cells[i] = fs
      cx = cx + col.w + 6
    end
    r:SetScript("OnEnter", function(self)
      local row = self.item
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(row.id)
      local rec = ns.db.recipes[row.prof] and ns.db.recipes[row.prof][row.id]
      if rec then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Reagents"], 1, 0.82, 0)
        for rid, n in pairs(rec.reagents) do
          local c, src = ns.BuyCost(rid)
          GameTooltip:AddDoubleLine(n .. "x " .. ns.ColoredName(rid), (c and ns.Money(c * n) or L["no price"]) .. (src == "vendor" and L[" |cff808080(vendor)|r"] or ""), 1, 1, 1, 1, 1, 1)
        end
      end
      if row.vendor and row.vendor > 0 then GameTooltip:AddDoubleLine(L["Vendor sells for"], ns.Money(row.vendor), 0.7, 0.7, 0.7, 1, 1, 1) end
      GameTooltip:AddLine(L["Click: price chart, Shift-click: search AH, Right-click: menu"], 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self, btn)
      local row = self.item
      if btn == "RightButton" then
        UI.ItemMenu(row.id)
        return
      end
      if IsShiftKeyDown() then UI.SearchAH(ns.ItemInfo(row.id)) return end
      ns.db.watch[row.id] = true; UI.selected = row.id; UI.ShowTab(1)
    end)
  end)
  UI.craftList.sf:SetPoint("TOPLEFT", 3, -3); UI.craftList.sf:SetPoint("BOTTOMRIGHT", -24, 3)
  -- shown only when the selected profession has no priced recipes (no overlap with the header)
  UI.craftEmpty = Text(box, "GameFontDisable"); UI.craftEmpty:SetPoint("CENTER"); UI.craftEmpty:SetWidth(360); UI.craftEmpty:Hide()
end

function UI.SearchAH(name)
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then ns.Warn(L["Open the Auction House first."]); return end
  local bar = AuctionHouseFrame.SearchBar
  if bar and bar.SearchBox then
    bar.SearchBox:SetText(name)
    if bar.StartSearch then bar:StartSearch() end
  end
end

function UI.RefreshCrafting()
  if not UI.craftList then return end
  local profs = ns.Professions()
  local cur = ns.db.settings.prof
  if not cur or not ns.db.recipes[cur] then cur = profs[1]; ns.db.settings.prof = cur end
  for i, prof in ipairs(profs) do
    local b = UI.profBtns[i]
    if not b then
      b = Button(UI.pages[2], prof, 100, 20)
      b:SetPoint("TOPLEFT", (i - 1) * 104, 0)
      UI.profBtns[i] = b
    end
    b.text:SetText(prof); b:SetScript("OnClick", function() ns.db.settings.prof = prof; UI.RefreshCrafting() end)
    b:SetActive(prof == cur); b:Show()
  end
  for i = #profs + 1, #UI.profBtns do UI.profBtns[i]:Hide() end

  local rows = cur and ns.CraftRows(cur) or {}
  if UI.craftEmpty then
    UI.craftEmpty:SetShown(#rows == 0)
    UI.craftEmpty:SetText(#profs == 0 and L["Open a profession window once so its recipes are learned (open the Smelting window for ore to bars)."]
      or L["No priced recipes here yet - do a Full Scan at the Auction House."])
  end
  local s = UI.craftSort
  table.sort(rows, function(a, b)
    local va, vb = a[s.key], b[s.key]
    if va == nil and vb == nil then return (a.name or "") < (b.name or "") end
    if va == nil then return false elseif vb == nil then return true end
    if s.desc then return va > vb else return va < vb end
  end)
  for _, col in ipairs(COLS) do
    col.btn.text:SetText(col.label .. (s.key == col.key and (s.desc and " v" or " ^") or ""))
  end
  UI.craftList:Set(rows, function(r, row)
    local hex = ns.SKILL_COLORS[row.color] or "808080"
    r.dot:SetColorTexture(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1)
    r.icon:SetTexture(ns.Icon(row.id))
    r.cells[1]:SetText(ns.ColoredName(row.id))
    r.cells[2]:SetText(row.cost and ns.Money(row.cost) or "|cff808080?|r")
    r.cells[3]:SetText(row.sell and ns.Money(row.sell) or L["|cff808080no data|r"])
    local p = row.profit
    r.cells[4]:SetText(p and ((p >= 0 and "|cff6fcf8f" or "|cffff6f61-") .. ns.Money(math.abs(p), true) .. "|r" .. (row.thin and " |cff808080?|r" or "")) or "|cff808080-|r")
    r.cells[5]:SetText(row.pct and ("%d%%"):format(math.floor(row.pct * 100)) or "")
    r.cells[6]:SetText(row.qty or "")
    r.cells[7]:SetText(row.avg7 and ns.Money(row.avg7) or "")
  end)
end

---------------------------------------------------------------- button on the Auction House window
function UI.Toggle()
  UI.frame:SetShown(not UI.frame:IsShown())
end

local ahButton
local function BuildAHButton()
  if ahButton or not AuctionHouseFrame then return end
  ahButton = Button(AuctionHouseFrame, L["|cff3987e5Corpo|rGreed"], 100, 22, function() UI.Toggle() end)
  ahButton:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", 0, 2)
  ahButton:SetFrameStrata(AuctionHouseFrame:GetFrameStrata())
  UI.ahButton = ahButton
  UI.ApplyLook()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:SetScript("OnEvent", function(_, e)
  if e == "AUCTION_HOUSE_SHOW" then
    BuildAHButton()
    if ns.db.settings.openWithAH then UI.frame:Show(); UI.autoShown = true end
    UI.UpdateStatus()
  elseif e == "AUCTION_HOUSE_CLOSED" then
    if UI.autoShown then UI.frame:Hide(); UI.autoShown = nil end
  end
end)

UI.AddTab("Prices", 10, PricesPage, function() UI.RefreshPrices() end)
UI.AddTab("Crafting", 20, CraftingPage, function() UI.RefreshCrafting() end)

ns.On("Loaded", function()
  BuildFrame()
  for i, def in ipairs(UI.tabDefs) do def.build(UI.pages[i]) end
  if (ns.db.settings.tab or 1) > #UI.tabDefs then ns.db.settings.tab = 1 end
end)
ns.On("PricesUpdated", function() UI.RefreshSoon() end)
ns.On("Message", function() if UI.frame and UI.frame:IsShown() then UI.UpdateStatus() end end)
-- a finished full scan refreshes the visible tab right away (no waiting for the slow interval)
ns.On("ScanDone", function() if UI.frame and UI.frame:IsShown() then UI.Refresh() end end)
ns.On("RecipesUpdated", function() if UI.TabIs("Crafting") then UI.Refresh() end end)
ns.On("InventoryUpdated", function() if UI.TabIs("Advisor") then UI.RefreshSoon() end end)

-- item names stream in as GET_ITEM_INFO_RECEIVED over many seconds. Redrawing on each one makes the
-- lists flicker while names resolve, so wait until the stream goes quiet, then redraw once.
local infoGen = 0
local iev = CreateFrame("Frame"); iev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
iev:SetScript("OnEvent", function()
  if not (UI.frame and UI.frame:IsShown()) then return end
  infoGen = infoGen + 1
  local g = infoGen
  C_Timer.After(1.0, function() if g == infoGen then UI.Refresh() end end)
end)
