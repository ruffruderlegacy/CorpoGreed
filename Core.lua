-- CorpoGreed core: saved data, price store, helpers.
local ADDON, ns = ...
local L = ns.L
_G.CorpoGreed = ns

ns.MAX_POINTS = 2000
ns.AH_CUT = 0.05
ns.BLOCKS = { { L["Night"], 0, 6 }, { L["Morning"], 6, 12 }, { L["Afternoon"], 12, 18 }, { L["Evening"], 18, 24 } }
ns.DEFAULT_WATCH = {
  2770, 2840, 2771, 3576, 2841, 2775, 2842, 2772, 3575, 2776, 3577, 2836, 2838,
  1210, 1206, 1705, 5498, 5500, 3466, 2319, 5540, 3491, 2870, 3836,
}

local callbacks = {}
function ns.On(name, fn) callbacks[name] = callbacks[name] or {}; table.insert(callbacks[name], fn) end
function ns.Fire(name, ...) for _, fn in ipairs(callbacks[name] or {}) do fn(...) end end

-- Quiet by default: info goes to the window's status line, not chat (/cg chat to show it in chat).
function ns.Print(msg)
  ns.lastMsg, ns.lastMsgT = msg, time()
  ns.Fire("Message", msg)
  if ns.db and ns.db.settings.chat then print(L["|cff3987e5CG|r "] .. msg) end
end
-- Warnings flash on screen (like "not enough mana") instead of chat.
function ns.Warn(msg)
  if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.82, 0) end
  ns.Print(msg)
end
-- Answers to slash commands always go to chat.
function ns.Say(msg) print(L["|cff3987e5CorpoGreed|r: "] .. msg) end

function ns.Money(c, plain)
  if not c then return "-" end
  c = math.floor(c + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  if plain then
    if g > 0 then return ("%dg %ds"):format(g, s) end
    if s > 0 then return ("%ds %dc"):format(s, cp) end
    return ("%dc"):format(cp)
  end
  local G, S, C = "|cffffd100g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
  if g > 0 then return ("%d%s %02d%s"):format(g, G, s, S) end
  if s > 0 then return ("%d%s %02d%s"):format(s, S, cp, C) end
  return ("%d%s"):format(cp, C)
end

-- cache resolved names/quality so a cell never flips back to "item:ID" if GetItemInfo momentarily returns nil
local nameCache = {}
function ns.ItemInfo(id)
  id = tonumber(id) or id
  local c = nameCache[id]
  if c then return c[1], c[2], c[3] end
  local name, link, quality
  if C_Item and C_Item.GetItemInfo then name, link, quality = C_Item.GetItemInfo(id)
  else name, link, quality = GetItemInfo(id) end
  if not name then
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return "item:" .. id, 1
  end
  nameCache[id] = { name, quality or 1, link }
  return name, quality or 1, link
end

function ns.ColoredName(id)
  local name, q = ns.ItemInfo(id)
  local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return (col and col.hex or "|cffffffff") .. name .. "|r"
end

function ns.Icon(id)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  return GetItemIcon and GetItemIcon(id)
end

function ns.Today() return math.floor(time() / 86400) end

-- profession / item category switches (Settings tab)
function ns.ProfEnabled(prof) return not (ns.db.settings.profOff and ns.db.settings.profOff[prof]) end
function ns.ClassEnabled(id)
  local off = ns.db.settings.classOff
  if not off or not next(off) then return true end
  local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local classID = Instant and select(6, Instant(id))
  return not (classID and off[classID])
end

-- ignore list: items hidden from the advisor, deals, crafting and drop warnings
function ns.IsIgnored(id) return id and ns.db and ns.db.ignore[id] or false end
function ns.ToggleIgnore(id)
  if not id then return end
  ns.db.ignore[id] = not ns.db.ignore[id] or nil
  ns.Print(ns.ColoredName(id) .. (ns.db.ignore[id] and L[" is now ignored."] or L[" is no longer ignored."]))
  ns.Fire("PricesUpdated", "ignore")
end

function ns.Block(t)
  local h = tonumber(date("%H", t))
  for i, b in ipairs(ns.BLOCKS) do if h >= b[2] and h < b[3] then return i end end
end

---------------------------------------------------------------- price store
-- db.prices[id] = { t = time, p = min unit buyout, q = quantity listed }
-- db.daily[id][day] = lowest seen that day
-- db.hist[id] = { {t, p, q}, ... }  (tracked + crafting-related items only)

function ns.IsHistoried(id)
  return ns.db.watch[id] or ns.craftItems[id]
end

-- market = "typical" price (cheapest 20% of supply averaged), robust against one dumped stack
function ns.RecordPrice(id, price, qty, t, forcePoint, market)
  if not id or not price or price <= 0 then return end
  local db = ns.db
  t = t or time()
  local prev = db.prices[id]
  db.prices[id] = { t = t, p = price, q = qty or (prev and prev.q), m = market or (prev and t - prev.t < 3600 and prev.m) or nil }
  local day = math.floor(t / 86400)
  db.daily[id] = db.daily[id] or {}
  local d = db.daily[id]
  if type(d[day]) ~= "table" then d[day] = { lo = price, mk = market or price } end
  local e = d[day]
  if price < e.lo then e.lo = price end
  if market then e.mk = market elseif not e.hasMk then e.mk = price end
  if market then e.hasMk = true end
  if ns.IsHistoried(id) then
    db.hist[id] = db.hist[id] or {}
    local h = db.hist[id]
    local last = h[#h]
    if not last or last[2] ~= price or forcePoint and t - last[1] >= 1800 then
      h[#h + 1] = { t, price, qty }
      while #h > ns.MAX_POINTS do table.remove(h, 1) end
    elseif last and t - last[1] < 1800 then
      last[3] = qty or last[3]
    end
  end
end

function ns.PruneDaily()
  local cutoff = ns.Today() - 60
  for _, d in pairs(ns.db.daily) do
    for day, e in pairs(d) do
      if day < cutoff or type(e) ~= "table" then d[day] = nil end -- also drops v0.2 number format
    end
  end
end

-- Current price: own data first, Auctionator as fallback if it is still installed.
function ns.Price(id)
  local p = ns.db.prices[id]
  if p then return p.p, p.q, p.t end
  if Auctionator and Auctionator.API and Auctionator.API.v1 then
    local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "CorpoGreed", id)
    if ok and v then return v end
  end
end

-- Cheapest way to get a reagent: vendor (if we've seen it on a merchant) or AH.
function ns.BuyCost(id)
  local ah = ns.Price(id)
  local v = ns.db.vendor[id]
  if v and (not ah or v < ah) then return v, "vendor" end
  return ah, ah and "ah"
end

function ns.Stats(id, since)
  local h = ns.db.hist[id]
  local pts = {}
  if h then for _, p in ipairs(h) do if not since or p[1] >= since then pts[#pts + 1] = p end end end
  if #pts == 0 then return nil end
  local lo, hi, sum = math.huge, 0, 0
  local bs = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
  for _, p in ipairs(pts) do
    lo, hi, sum = math.min(lo, p[2]), math.max(hi, p[2]), sum + p[2]
    local b = bs[ns.Block(p[1])]; b[1] = b[1] + p[2]; b[2] = b[2] + 1
  end
  local avgs, filled, best, worst = {}, 0, nil, nil
  for i, b in ipairs(bs) do
    if b[2] > 0 then
      avgs[i] = b[1] / b[2]; filled = filled + 1
      if not best or avgs[i] < avgs[best] then best = i end
      if not worst or avgs[i] > avgs[worst] then worst = i end
    end
  end
  return { pts = pts, lo = lo, hi = hi, avg = sum / #pts, now = pts[#pts][2], first = pts[1][2],
           blocks = avgs, filled = filled, best = filled >= 2 and best or nil, worst = filled >= 2 and worst or nil }
end

-- Average daily market price over the last N days (works for every item, not just historied ones).
-- excludeToday = the "usual" price to compare today's listings against.
function ns.DailyAvg(id, days, excludeToday)
  local d = ns.db.daily[id]; if not d then return end
  local today, sum, n = ns.Today(), 0, 0
  for day, e in pairs(d) do
    if day > today - (days or 7) and not (excludeToday and day == today) then
      sum, n = sum + (type(e) == "table" and e.mk or e), n + 1
    end
  end
  if n > 0 then return sum / n, n end
end

-- "Usual" price: past days' market average; falls back to today's market if that's all we have.
function ns.Usual(id)
  local avg, n = ns.DailyAvg(id, 7, true)
  if avg then return avg, n end
  local p = ns.db.prices[id]
  return p and p.m, 0
end

---------------------------------------------------------------- init
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("MERCHANT_SHOW")
ev:SetScript("OnEvent", function(_, e, arg)
  if e == "ADDON_LOADED" and arg == ADDON then
    CorpoGreedDB = CorpoGreedDB or {}
    local db = CorpoGreedDB
    ns.db = db
    db.hist = db.hist or {}
    db.prices = db.prices or {}
    db.daily = db.daily or {}
    db.vendor = db.vendor or {}
    db.recipes = db.recipes or {}
    db.sales = db.sales or {}
    db.settings = db.settings or { range = 3, dock = true }
    db.inv = db.inv or {}
    db.ignore = db.ignore or {}
    db.shop = db.shop or {}
    db.deals = db.deals or {}
    if db.range then db.settings.range = db.range; db.range = nil end
    if not db.watch then
      db.watch = {}
      for _, id in ipairs(ns.DEFAULT_WATCH) do db.watch[id] = true end
    end
    -- old v0.1 history had no current-price table: seed it from the last point
    for id, h in pairs(db.hist) do
      if not db.prices[id] and h[#h] then db.prices[id] = { t = h[#h][1], p = h[#h][2] } end
    end
    -- one-time import of the Auctionator baseline shipped in Seed.lua
    if CorpoGreedSeed and not db.seeded then
      for day, items in pairs(CorpoGreedSeed) do
        for id, v in pairs(items) do
          db.daily[id] = db.daily[id] or {}
          if type(db.daily[id][day]) ~= "table" then db.daily[id][day] = { lo = v[1], mk = v[2] } end
          local p = db.prices[id]
          if not p or p.t < day * 86400 then db.prices[id] = { t = day * 86400 + 43200, p = v[2] } end
        end
      end
      db.seeded = true
    end
    CorpoGreedSeed = nil
    ns.craftItems = {}
    if ns.ApplyLocale then ns.ApplyLocale() end -- now that settings.language is loaded
    ns.Fire("Loaded")
  elseif e == "PLAYER_LOGIN" then
    ns.PruneDaily()
    ns.Fire("Login")
  elseif e == "MERCHANT_SHOW" then
    -- remember vendor buy prices (flux, thread, vials...) so crafting costs are right
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
      local link = GetMerchantItemLink(i)
      local id = link and tonumber(link:match("item:(%d+)"))
      local price, stack, numAvail, extCost
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then price, stack, numAvail, extCost = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
      else
        local _
        _, _, price, stack, numAvail, _, _, extCost = GetMerchantItemInfo(i)
      end
      if id and price and price > 0 and numAvail == -1 and not extCost then
        ns.db.vendor[id] = price / (stack or 1)
      end
    end
  end
end)
