-- CorpoGreed scanning: full scan (ReplicateItems), passive capture from normal AH searches, sales from mail.
local ADDON, ns = ...
local L = ns.L
local SCAN_COOLDOWN = 15 * 60
local CHUNK = 2500
ns.DEAL_RATIO = 0.75 -- listings at or below 75% of the usual price count as deals

local processing, lastProcessed, waitingSince = false, 0, nil

function ns.ScanCooldownLeft()
  local last = ns.db.lastFullScan or 0
  return math.max(0, SCAN_COOLDOWN - (time() - last))
end

ns.MIN_DEPTH = 5 -- an item needs at least this many listed before we trust a "deal"
-- ladder = { {unit, count}, ... } for one item. Returns min, total qty, market(typical), deal info.
-- The "typical" price is the quantity-weighted median of the CURRENT listings - robust against a few
-- troll listings - so deals are judged against what the item really goes for now, not a stale average.
local function Analyze(id, ladder)
  table.sort(ladder, function(a, b) return a[1] < b[1] end)
  local total = 0
  for _, a in ipairs(ladder) do total = total + a[2] end
  if total == 0 then return ladder[1] and ladder[1][1] or 0, 0, nil, nil end
  local cum, median = 0, ladder[#ladder][1]
  for _, a in ipairs(ladder) do cum = cum + a[2]; if cum * 2 >= total then median = a[1]; break end end
  local minP = ladder[1][1]
  local deal
  -- a deal = listings well below the typical price, in a market with real depth, where the cheap
  -- pile is a MINORITY (if most listings are cheap, cheap IS the price - not a bargain).
  if total >= ns.MIN_DEPTH and median > 0 then
    local n, cost = 0, 0
    for _, a in ipairs(ladder) do
      if a[1] > median * ns.DEAL_RATIO then break end
      n, cost = n + a[2], cost + a[1] * a[2]
    end
    if n > 0 and n < total * 0.5 then
      deal = { n = n, cost = cost, usual = median, t = time(), resale = math.min(n, total - n) }
    end
  end
  return minP, total, median, deal
end
ns.AnalyzeLadder = Analyze

local function ProcessReplicate()
  local n = C_AuctionHouse.GetNumReplicateItems()
  if not n or n == 0 then processing = false; return end
  local ladders = {}
  local i = 0
  local function step()
    local stop = math.min(i + CHUNK, n)
    for idx = i, stop - 1 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
      if itemID and buyout and buyout > 0 and count and count > 0 then
        local l = ladders[itemID]
        if not l then l = {}; ladders[itemID] = l end
        l[#l + 1] = { buyout / count, count }
      end
    end
    i = stop
    if ns.scanFrame then ns.scanFrame:SetProgress(i / n) end
    if i < n then C_Timer.After(0, step) return end
    local now, items, deals = time(), 0, 0
    ns.db.deals = {}
    for id, ladder in pairs(ladders) do
      local minP, qty, market, deal = Analyze(id, ladder)
      ns.db.deals[id] = deal
      if deal then deals = deals + 1 end
      ns.RecordPrice(id, math.floor(minP + 0.5), qty, now, true, math.floor(market + 0.5))
      items = items + 1
    end
    ns.db.lastFullScan = now
    processing, lastProcessed, waitingSince = false, now, nil
    ns.Print((L["full scan done: %d auctions, %d items priced, |cff6fcf8f%d deals|r found."]):format(n, items, deals))
    ns.Fire("PricesUpdated", "scan")
    ns.Fire("ScanDone")
  end
  step()
end

function ns.FullScan()
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then ns.Warn(L["Open the Auction House first."]); return end
  local left = ns.ScanCooldownLeft()
  if left > 0 then ns.Warn((L["Full scan is on cooldown for %d:%02d (Blizzard limit)."]):format(math.floor(left / 60), left % 60)); return end
  waitingSince = time()
  C_AuctionHouse.ReplicateItems()
  ns.Print(L["full scan started - this can take a minute, keep the AH open."])
  ns.Fire("ScanStarted")
  C_Timer.After(90, function()
    if waitingSince and not processing and time() - waitingSince >= 89 then
      waitingSince = nil
      ns.Warn(L["No scan data came back. Blizzard allows one full scan per 15 min (also counts scans by other addons)."])
      ns.db.lastFullScan = time() - SCAN_COOLDOWN + 60
      ns.Fire("PricesUpdated", "failed")
    end
  end)
end

function ns.IsScanning() return processing or waitingSince ~= nil end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
ev:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ev:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
ev:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
ev:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")

-- auto-track items you look up on the AH, so they show in the Prices tab without dragging
function ns.AutoTrack(id)
  if id and ns.db.settings.autotrack ~= false and not ns.db.watch[id] and not ns.IsIgnored(id) then
    ns.db.watch[id] = true
  end
end

local function RecordBrowse(list)
  if not list then return end
  -- a specific search returns few results; only auto-track those (not a broad 100-item browse)
  local track = #list <= 25
  for _, r in ipairs(list) do
    if r.itemKey and r.minPrice and r.minPrice > 0 then
      ns.RecordPrice(r.itemKey.itemID, r.minPrice, r.totalQuantity)
      if track then ns.AutoTrack(r.itemKey.itemID) end
    end
  end
end

local passivePending = false
local function PassiveChanged()
  if passivePending then return end
  passivePending = true
  C_Timer.After(1, function() passivePending = false; ns.Fire("PricesUpdated", "search") end)
end

ev:SetScript("OnEvent", function(_, e, arg)
  if not ns.db then return end
  if e == "REPLICATE_ITEM_LIST_UPDATE" then
    -- also fires when another addon runs the full scan; use it either way
    if not processing and time() - lastProcessed > 60 then
      processing = true
      C_Timer.After(2, ProcessReplicate)
    end
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    RecordBrowse(C_AuctionHouse.GetBrowseResults()); PassiveChanged()
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    RecordBrowse(arg); PassiveChanged()
  elseif e == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local id = arg
    local ladder = {}
    for i = 1, (C_AuctionHouse.GetNumCommoditySearchResults(id) or 0) do
      local info = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
      if info and info.unitPrice and info.quantity then ladder[#ladder + 1] = { info.unitPrice, info.quantity } end
    end
    if #ladder > 0 then
      local minP, qty, market, deal = Analyze(id, ladder)
      ns.db.deals[id] = deal
      ns.RecordPrice(id, minP, C_AuctionHouse.GetCommoditySearchResultsQuantity(id) or qty, nil, false, math.floor(market + 0.5))
      ns.AutoTrack(id)
      PassiveChanged()
    end
  elseif e == "ITEM_SEARCH_RESULTS_UPDATED" then
    local key = arg
    local ladder = {}
    for i = 1, (C_AuctionHouse.GetNumItemSearchResults(key) or 0) do
      local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
      if info and info.buyoutAmount and info.buyoutAmount > 0 then
        local q = math.max(1, info.quantity or 1)
        ladder[#ladder + 1] = { info.buyoutAmount / q, q }
      end
    end
    if #ladder > 0 and key and key.itemID then
      local minP, qty, market, deal = Analyze(key.itemID, ladder)
      ns.db.deals[key.itemID] = deal
      ns.RecordPrice(key.itemID, math.floor(minP + 0.5), #ladder, nil, false, math.floor(market + 0.5))
      ns.AutoTrack(key.itemID)
      PassiveChanged()
    end
  end
end)
