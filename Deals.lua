-- CorpoGreed deals: auctions listed well below the usual price (dumps), and AH items cheaper than a vendor pays.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local STALE = 2 * 3600
local ALERT_MIN_PROFIT = 2000 -- 20s

local function DealRows()
  local rows, now = {}, time()
  for id, d in pairs(ns.db.deals) do
    if now - d.t < STALE and not ns.IsIgnored(id) and ns.ClassEnabled(id) then
      local avgBuy = d.cost / d.n
      local resell = d.usual * (1 - ns.AH_CUT)
      local p = ns.db.prices[id]
      -- profit uses the realistic resale quantity (what the market can absorb), not the whole cheap pile
      local qty = d.resale or d.n
      rows[#rows + 1] = { id = id, name = ns.ItemInfo(id), n = d.n, buy = avgBuy, usual = d.usual,
                          disc = 1 - avgBuy / d.usual, profit = (resell - avgBuy) * qty, listed = p and p.q,
                          kind = "dump", days = p and p.q }
    end
  end
  -- vendor flips: AH lowest below what a vendor pays
  for id, p in pairs(ns.db.prices) do
    if now - p.t < STALE and not ns.IsIgnored(id) and ns.ClassEnabled(id) then
      local v = ns.VendorPrice(id)
      if v and p.p < v * 0.95 then
        rows[#rows + 1] = { id = id, name = ns.ItemInfo(id), n = nil, buy = p.p, usual = v, disc = 1 - p.p / v,
                            profit = v - p.p, listed = p.q, kind = "vendor" }
      end
    end
  end
  return rows
end
ns.DealRows = DealRows

---------------------------------------------------------------- alerts after a scan
ns.On("ScanDone", function()
  -- no chat spam: one sound + a badge on the Deals tab when something worth >= 20s turns up
  local good, best = 0, nil
  for _, r in ipairs(DealRows()) do
    if r.profit >= ALERT_MIN_PROFIT then
      good = good + 1
      if not best or r.profit > best.profit then best = r end
    end
  end
  ns.dealCount = good
  if good > 0 then
    if ns.db.settings.dealSound ~= false then PlaySound(SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN or 5274) end
    ns.Print(("%d deal%s found - best: %s (~%s profit)"):format(good, good == 1 and "" or "s", best.name, ns.Money(best.profit)))
  end
end)

---------------------------------------------------------------- Deals tab
local tbl
local COLS = {
  { key = "name", label = L["Item"], w = 190, align = "LEFT" },
  { key = "n", label = L["Cheap qty"], w = 65 },
  { key = "buy", label = L["Buy at"], w = 80 },
  { key = "usual", label = L["Usual / vendor"], w = 95 },
  { key = "disc", label = L["Discount"], w = 60 },
  { key = "profit", label = L["Profit if resold"], w = 100 },
  { key = "listed", label = L["Listed"], w = 55 },
}

local function Build(page)
  local note = UI.Text(page, "GameFontDisableSmall"); note:SetPoint("TOPLEFT", 2, -4)
  note:SetText(L["Listings at <=75% of the usual price, from your last full scan or searches (2h). Click to search the AH, then buy in the Blizzard window."])
  tbl = UI.Table(page, 24, COLS, function(r)
    r:SetScript("OnEnter", function(self)
      local row = self.item
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(row.id)
      GameTooltip:AddLine(" ")
      if row.kind == "vendor" then
        GameTooltip:AddLine(L["Buy and sell straight to a vendor."], 0.44, 0.81, 0.56)
      else
        GameTooltip:AddLine((L["Usual price is from %s."]):format(row.days and row.days > 0 and (row.days .. " day(s) of scans") or L["today only - less reliable"]), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Check how fast it sells (Listed) before buying a lot."], 0.8, 0.8, 0.8)
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then UI.ItemMenu(self.item.id) return end
      UI.SearchAH(ns.ItemInfo(self.item.id))
    end)
  end)
  tbl.sort = { key = "profit", desc = true }
  tbl.onSort = function() UI.Refresh() end
end

local function Refresh()
  if not tbl then return end
  tbl:Set(DealRows(), function(r, row)
    UI.Dot(r.dot, row.kind == "vendor" and ns.ADV_COLORS.YELLOW or ns.ADV_COLORS.GREEN)
    r.icon:SetTexture(ns.Icon(row.id))
    r.cells[1]:SetText(ns.ColoredName(row.id))
    r.cells[2]:SetText(row.n or L["|cff808080vendor|r"])
    r.cells[3]:SetText(ns.Money(row.buy))
    r.cells[4]:SetText(ns.Money(row.usual))
    r.cells[5]:SetText(("%d%%"):format(math.floor(row.disc * 100)))
    r.cells[6]:SetText("|cff6fcf8f" .. ns.Money(row.profit, true) .. "|r" .. (row.kind == "vendor" and L[" /ea"] or ""))
    r.cells[7]:SetText(row.listed or "")
  end)
end

-- Deals tab removed (scrapped by request); the post-scan deal sound/alert above stays.
-- Build/Refresh/DealRows kept for the alert and any future use, but no tab is registered.
local _ = Build and Refresh  -- silence "unused" without registering a tab
