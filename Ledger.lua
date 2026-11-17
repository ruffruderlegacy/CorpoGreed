-- CorpoGreed bookkeeping: every sale, purchase, listing deposit, expired/cancelled auction, vendor visit and gold balance.
-- db.ledger = { { t, kind, name, id, qty, amount (copper, + in / - out), char, note }, ... }
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local MAX_ENTRIES = 5000

local KINDS = {
  sale = { label = L["Sold"], color = "6fcf8f" },
  buy = { label = L["Bought"], color = "ff6f61" },
  post = { label = L["Posted"], color = "c0c0c0" },
  expired = { label = L["Expired"], color = "ffd24a" },
  cancel = { label = L["Cancelled"], color = "ffd24a" },
  refund = { label = L["Deposit back"], color = "c0c0c0" },
  vendor_in = { label = L["Vendor sold"], color = "6fcf8f" },
  vendor_out = { label = L["Vendor spent"], color = "ff6f61" },
}
ns.LEDGER_KINDS = KINDS

local function Add(e)
  e.t = e.t or time()
  e.char = e.char or (ns.CharKey and ns.CharKey()) or "?"
  table.insert(ns.db.ledger, e)
  while #ns.db.ledger > MAX_ENTRIES do table.remove(ns.db.ledger, 1) end
  ns.Fire("LedgerUpdated")
end
ns.LedgerAdd = Add

---------------------------------------------------------------- AH mail (sold / won / expired / cancelled)
local function Pattern(fmt)
  if not fmt then return nil end
  fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
  return "^" .. fmt .. "$"
end

local SUBJECTS
local function Subjects()
  if SUBJECTS then return SUBJECTS end
  SUBJECTS = {
    { Pattern(AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s"), "sale" },
    { Pattern(AUCTION_WON_MAIL_SUBJECT or "Auction won: %s"), "buy" },
    { Pattern(AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"), "expired" },
    { Pattern(AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s"), "cancel" },
  }
  return SUBJECTS
end

local function SplitQty(name)
  local base, n = name:match("^(.-) %((%d+)%)$")
  if base then return base, tonumber(n) end
  return name, 1
end

local requested = {}
function ns.ReadMail()
  local db = ns.db
  db.mailSeen = db.mailSeen or {}
  local added = 0
  for i = 1, GetInboxNumItems() do
    local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    if subject and daysLeft then
      local kind, itemText
      for _, s in ipairs(Subjects()) do
        local m = s[1] and subject:match(s[1])
        if m then kind, itemText = s[2], m break end
      end
      if kind then
        local sent = time() - math.floor((30 - daysLeft) * 86400)
        local base, bucket = subject .. ":" .. (money or 0) .. ":", math.floor(sent / 600)
        if not (db.mailSeen[base .. bucket] or db.mailSeen[base .. (bucket - 1)] or db.mailSeen[base .. (bucket + 1)]) then
          -- invoice details (price, AH cut, deposit) only load once a mail has been looked at
          local invoiceType, invName, buyer, bid, _, deposit, consignment, _, _, count = GetInboxInvoiceInfo(i)
          if (kind == "sale" or kind == "buy") and not invoiceType and not requested[base] then
            requested[base] = true
            GetInboxText(i) -- loads the invoice; a later MAIL_INBOX_UPDATE picks it up
          else
            local name, qty = SplitQty(itemText)
            qty = count or qty
            if kind == "sale" then
              local net = bid and (bid - (consignment or 0)) or ((money or 0) - (deposit or 0))
              Add({ t = sent, kind = "sale", name = invName or name, qty = qty, amount = net, note = buyer })
              if deposit and deposit > 0 then Add({ t = sent, kind = "refund", name = invName or name, qty = qty, amount = deposit }) end
            elseif kind == "buy" then
              Add({ t = sent, kind = "buy", name = invName or name, qty = qty, amount = -(bid or 0), note = buyer })
            else
              Add({ t = sent, kind = kind, name = name, qty = qty, amount = 0 })
            end
            db.mailSeen[base .. bucket] = true
            added = added + 1
          end
        end
      end
    end
  end
  return added
end

---------------------------------------------------------------- posting (deposit paid)
local lastSellItem
function ns.LedgerSetSellItem(id) lastSellItem = id end

local function OnPost(itemLocation, duration, quantity, unitPriceOrBid, buyout)
  local id
  if itemLocation and itemLocation.IsValid and itemLocation:IsValid() then id = C_Item.GetItemID(itemLocation) end
  id = id or lastSellItem
  if not id then return end
  local deposit = 0
  local ok, d = pcall(function()
    if buyout ~= nil then return C_AuctionHouse.CalculateItemDeposit(itemLocation, duration, quantity) end
    return C_AuctionHouse.CalculateCommodityDeposit(id, duration, quantity)
  end)
  if ok and d then deposit = d end
  local unit = buyout ~= nil and (buyout / math.max(1, quantity)) or unitPriceOrBid
  Add({ kind = "post", id = id, name = ns.ItemInfo(id), qty = quantity, amount = -deposit,
        note = unit and (L["at "] .. ns.Money(unit, true) .. L[" each"]) or nil })
end

---------------------------------------------------------------- events (item detail only; Finance.lua owns the money)
local ev = CreateFrame("Frame")
ev:RegisterEvent("MAIL_INBOX_UPDATE")
ev:SetScript("OnEvent", function(_, e)
  if ns.db and e == "MAIL_INBOX_UPDATE" then ns.ReadMail() end
end)

ns.On("Loaded", function()
  local db = ns.db
  db.ledger = db.ledger or {}
  db.gold = db.gold or {}
  -- carry over v0.2-0.5 sales
  if db.sales and #db.sales > 0 then
    for _, s in ipairs(db.sales) do
      table.insert(db.ledger, { t = s.t, kind = "sale", name = s.name, qty = 1, amount = s.net, note = s.buyer, char = "?" })
    end
  end
  db.sales, db.salesSeen = nil, nil
  if C_AuctionHouse then
    if C_AuctionHouse.PostCommodity then hooksecurefunc(C_AuctionHouse, "PostCommodity", OnPost) end
    if C_AuctionHouse.PostItem then
      hooksecurefunc(C_AuctionHouse, "PostItem", function(loc, dur, qty, bid, buyout) OnPost(loc, dur, qty, bid, buyout or bid or 0) end)
    end
  end
end)

---------------------------------------------------------------- totals
function ns.LedgerTotals(since)
  local t = { sales = 0, buys = 0, deposits = 0, vendor = 0, net = 0, soldQty = 0 }
  for _, e in ipairs(ns.db.ledger) do
    if not since or e.t >= since then
      local a = e.amount or 0
      if e.kind == "sale" then t.sales = t.sales + a; t.soldQty = t.soldQty + (e.qty or 1)
      elseif e.kind == "buy" then t.buys = t.buys + a
      elseif e.kind == "post" or e.kind == "refund" then t.deposits = t.deposits + a
      elseif e.kind == "vendor_in" or e.kind == "vendor_out" then t.vendor = t.vendor + a end
      t.net = t.net + a
    end
  end
  return t
end

local function StartOfDay(now)
  return now - (tonumber(date("%H", now)) * 3600 + tonumber(date("%M", now)) * 60 + tonumber(date("%S", now)))
end

---------------------------------------------------------------- CSV export
local exportFrame
local function Export()
  if not exportFrame then
    local f = CreateFrame("Frame", "CorpoGreedExport", UIParent, "BackdropTemplate")
    UI.Skin(f, 0.95); f:SetSize(620, 400); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local t = UI.Text(f, "GameFontNormal"); t:SetPoint("TOPLEFT", 10, -10)
    t:SetText(L["Ledger CSV - press Ctrl+A then Ctrl+C, paste into Excel / Google Sheets"])
    local close = UI.Button(f, L["Close"], 70, 20, function() f:Hide() end); close:SetPoint("TOPRIGHT", -8, -6)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -34); sf:SetPoint("BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject("ChatFontSmall"); eb:SetWidth(570); eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.eb = eb
    tinsert(UISpecialFrames, "CorpoGreedExport")
    exportFrame = f
  end
  local lines = { "date,character,type,item,quantity,amount_gold,note" }
  for _, e in ipairs(ns.db.ledger) do
    local k = KINDS[e.kind]
    lines[#lines + 1] = ("%s,%s,%s,\"%s\",%d,%.4f,\"%s\""):format(date("%Y-%m-%d %H:%M", e.t), e.char or "", k and k.label or e.kind,
      (e.name or ""):gsub('"', "'"), e.qty or 1, (e.amount or 0) / 10000, (e.note or ""):gsub('"', "'"))
  end
  exportFrame.eb:SetText(table.concat(lines, "\n"))
  exportFrame:Show(); exportFrame.eb:SetFocus(); exportFrame.eb:HighlightText()
end

---------------------------------------------------------------- Ledger tab
local page, grid, list, filterBtns
local FILTERS = { { L["All"] }, { L["Sold"], sale = true }, { L["Bought"], buy = true }, { L["Posted"], post = true, refund = true },
                  { L["Expired"], expired = true, cancel = true }, { L["Cash flow"], cash = true }, { L["Farming"] }, { L["By item"] } }

local COLS = {
  { key = "t", label = L["When"], w = 110, align = "LEFT" },
  { key = "kind", label = L["Type"], w = 85, align = "LEFT" },
  { key = "name", label = L["Item"], w = 210, align = "LEFT" },
  { key = "qty", label = L["Qty"], w = 45 },
  { key = "amount", label = L["Amount"], w = 95 },
  { key = "note", label = L["Buyer / note"], w = 150, align = "LEFT" },
}
local ITEM_COLS = {
  { key = "name", label = L["Item"], w = 210, align = "LEFT" },
  { key = "sold", label = L["Sold"], w = 55 },
  { key = "revenue", label = L["Revenue"], w = 95 },
  { key = "avg", label = L["Avg each"], w = 85 },
  { key = "bought", label = L["Bought"], w = 55 },
  { key = "spent", label = L["Spent"], w = 90 },
  { key = "net", label = L["Net"], w = 95 },
}

local function Build(p)
  page = p
  -- summary grid: rows = Sales / Purchases / Deposits / Vendor / Net, cols = Today / 7d / 30d / All
  grid = {}
  local colNames = { L["Today"], L["7 days"], L["30 days"], L["All time"] }
  local rowNames = { L["Auction House"], L["Vendor"], L["Loot"], L["Quests"], L["Other"], L["Net profit"], L["Farmed items (value)"] }
  for c, name in ipairs(colNames) do
    local h = UI.Text(p, "GameFontNormalSmall"); h:SetPoint("TOPLEFT", 110 + (c - 1) * 105, -2); h:SetWidth(100); h:SetJustifyH("RIGHT"); h:SetText(name)
  end
  for r, name in ipairs(rowNames) do
    local l = UI.Text(p, r == 6 and "GameFontNormal" or nil); l:SetPoint("TOPLEFT", 4, -4 - r * 14); l:SetText(name)
    grid[r] = {}
    for c = 1, 4 do
      local v = UI.Text(p, r == 6 and "GameFontNormal" or nil); v:SetPoint("TOPLEFT", 110 + (c - 1) * 105, -4 - r * 14); v:SetWidth(100); v:SetJustifyH("RIGHT")
      grid[r][c] = v
    end
  end
  p.gold = UI.Text(p, "GameFontNormal"); p.gold:SetPoint("TOPRIGHT", -4, -2); p.gold:SetJustifyH("RIGHT")
  p.hint = UI.Text(p, "GameFontDisableSmall"); p.hint:SetPoint("TOPRIGHT", -4, -20); p.hint:SetJustifyH("RIGHT")
  p.hint:SetText(L["Open your mailbox to record AH sales and purchases.\nPosts, vendor visits and loot are recorded automatically.\nFarmed items are valued at today's AH price (not in net)."])
  local export = UI.Button(p, L["Export CSV"], 90, 20, Export); export:SetPoint("TOPRIGHT", -4, -78)

  -- character scope: cycles All -> each character that has records -> All
  p.scope = UI.Button(p, L["Char: All"], 120, 20, function()
    local list = (ns.CharList and ns.CharList()) or {}
    local cur, idx = ns.db.settings.ledgerChar, 0
    if cur then for i, c in ipairs(list) do if c == cur then idx = i break end end end
    local nxt = idx + 1
    ns.db.settings.ledgerChar = (nxt <= #list) and list[nxt] or nil
    UI.Refresh()
  end)
  p.scope:SetPoint("TOPRIGHT", -98, -78)

  filterBtns = {}
  for i, f in ipairs(FILTERS) do
    local b = UI.Button(p, f[1], 78, 20, function() ns.db.settings.ledgerFilter = i; UI.Refresh() end)
    b:SetPoint("TOPLEFT", (i - 1) * 82, -110)
    filterBtns[i] = b
  end

  local holder = CreateFrame("Frame", nil, p); holder:SetPoint("TOPLEFT", 0, -112); holder:SetPoint("BOTTOMRIGHT")
  list = UI.Table(holder, 24, COLS, function(r)
    r:SetScript("OnEnter", function(self)
      local e = self.item
      if e.id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(e.id); GameTooltip:Show() end
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
  end)
  list.sort = { key = "t", desc = true }
  list.onSort = function() UI.Refresh() end
  local holder2 = CreateFrame("Frame", nil, p); holder2:SetPoint("TOPLEFT", 0, -112); holder2:SetPoint("BOTTOMRIGHT")
  p.itemList = UI.Table(holder2, 24, ITEM_COLS)
  p.itemList.sort = { key = "net", desc = true }
  p.itemList.onSort = function() UI.Refresh() end
  p.holder, p.holder2 = holder, holder2
end

local function Money(c)
  if not c or c == 0 then return "|cff808080-|r" end
  return (c > 0 and "|cff6fcf8f" or "|cffff6f61-") .. ns.Money(math.abs(c), true) .. "|r"
end

local function Refresh()
  if not page then return end
  local char = ns.db.settings.ledgerChar  -- nil = all characters
  local now = time()
  local periods = { StartOfDay(now), now - 7 * 86400, now - 30 * 86400, nil }
  for c, since in ipairs(periods) do
    local cats, _, _, net = ns.CashTotals(since, char)
    local ah, vendor, loot, quests = cats["Auction House"] or 0, cats["Vendor"] or 0, cats["Loot"] or 0, cats["Quests"] or 0
    local other = net - ah - vendor - loot - quests  -- Trade + Training + Mail + Travel + Other
    local _, farmed = ns.FarmTotals and ns.FarmTotals(since and math.floor(since / 86400) or nil) or 0, 0
    local vals = { ah, vendor, loot, quests, other, net, farmed }
    for r = 1, 7 do grid[r][c]:SetText(Money(vals[r])) end
  end
  if char then
    local short = char:match("^[^-]+") or char
    page.gold:SetText(short .. L["'s gold: "] .. ns.Money(ns.CharGold(char)))
    page.scope.text:SetText(L["Char: "] .. short)
  else
    page.gold:SetText(L["Gold, all characters: "] .. ns.Money(ns.TotalGold()))
    page.scope.text:SetText(L["Char: All"])
  end

  local fi = ns.db.settings.ledgerFilter or 1
  for i, b in ipairs(filterBtns) do b:SetActive(i == fi) end
  local byItem = FILTERS[fi][1] == L["By item"]
  page.holder:SetShown(not byItem); page.holder2:SetShown(byItem)

  if byItem then
    local agg = {}
    for _, e in ipairs(ns.db.ledger) do
      if (e.kind == "sale" or e.kind == "buy") and e.name and (not char or e.char == char) then
        local a = agg[e.name] or { name = e.name, sold = 0, revenue = 0, bought = 0, spent = 0 }
        agg[e.name] = a
        if e.kind == "sale" then a.sold = a.sold + (e.qty or 1); a.revenue = a.revenue + (e.amount or 0)
        else a.bought = a.bought + (e.qty or 1); a.spent = a.spent + (e.amount or 0) end
      end
    end
    local rows = {}
    for _, a in pairs(agg) do
      a.avg = a.sold > 0 and a.revenue / a.sold or nil
      a.net = a.revenue + a.spent
      rows[#rows + 1] = a
    end
    page.itemList:Set(rows, function(r, a)
      r.dot:Hide(); r.icon:Hide()
      r.cells[1]:SetText(a.name)
      r.cells[2]:SetText(a.sold > 0 and a.sold or "")
      r.cells[3]:SetText(a.revenue ~= 0 and ns.Money(a.revenue) or "")
      r.cells[4]:SetText(a.avg and ns.Money(a.avg) or "")
      r.cells[5]:SetText(a.bought > 0 and a.bought or "")
      r.cells[6]:SetText(a.spent ~= 0 and ns.Money(-a.spent) or "")
      r.cells[7]:SetText(Money(a.net))
    end)
    return
  end

  local f = FILTERS[fi]
  local rows = {}
  if f[1] == L["Farming"] then
    rows = ns.FarmRows and ns.FarmRows() or {}
  elseif f.cash then
    -- the complete money log: every gold change, tagged by what you were doing
    for _, e in ipairs(ns.CashRows and ns.CashRows(nil, char) or {}) do
      rows[#rows + 1] = { t = e.t, kind = "cash", cat = e.cat, amount = e.amount, name = L[e.cat] }
    end
  else
    for _, e in ipairs(ns.db.ledger) do
      if (fi == 1 or f[e.kind]) and (not char or e.char == char) then rows[#rows + 1] = e end
    end
  end
  list:Set(rows, function(r, e)
    local col = e.cat and (ns.CatColor and ns.CatColor(e.cat)) or nil
    local k = KINDS[e.kind] or { label = L[e.name or e.kind or ""], color = col or "8fb8ff" }
    UI.Dot(r.dot, e.cat and (col or "8fb8ff") or k.color)
    r.icon:SetTexture(e.id and ns.Icon(e.id) or nil)
    r.cells[1]:SetText(e.day and date("%a %d %b", e.t) or date("%a %d %b %H:%M", e.t))
    r.cells[2]:SetText(L["|cff"] .. (e.cat and (col or "8fb8ff") or k.color) .. (e.cat and L[e.cat] or k.label) .. "|r")
    r.cells[3]:SetText(e.id and ns.ColoredName(e.id) or L[e.name or ""])
    r.cells[4]:SetText(e.qty or "")
    r.cells[5]:SetText(Money(e.amount))
    r.cells[6]:SetText(e.note or "")
  end)
end

UI.AddTab("Ledger", 90, Build, Refresh)
ns.On("LedgerUpdated", function() if UI.TabIs("Ledger") then UI.RefreshSoon() end end)
ns.On("LootUpdated", function() if UI.TabIs("Ledger") then UI.RefreshSoon() end end)
ns.On("CashUpdated", function() if UI.TabIs("Ledger") then UI.RefreshSoon() end end)
