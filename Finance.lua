-- CorpoGreed finance core: the single source of truth for money.
-- Every change in your gold (PLAYER_MONEY) is recorded and tagged by what you were doing, so nothing is missed
-- and the totals always reconcile with your real gold. db.cash = { {t, amount(+in/-out), cat, char}, ... }
local ADDON, ns = ...
local L = ns.L
local MAX = 8000

-- categories, in display order, with colours
ns.CASH_CATS = {
  { "Auction House", "7dc0ff" },
  { "Vendor",        "ffd24a" },
  { "Loot",          "6fcf8f" },
  { "Quests",        "c0a0ff" },
  { "Trade",         "9fe0e0" },
  { "Training",      "ff9f6f" },
  { "Mail",          "d0d0d0" },
  { "Travel",        "b0b0b0" },
  { "Other",         "9a9a9a" },
}

function ns.CatColor(cat)
  for _, c in ipairs(ns.CASH_CATS) do if c[1] == cat then return c[2] end end
  return "9a9a9a"
end

local lastMoney
-- each context records when it was opened (seq, ever-increasing) and until when it stays valid.
-- A short grace after a window closes catches the money event that lands just after; whichever context
-- was opened most recently wins, so a brief grace never steals a change that belongs to a newer context.
local ctx = {}
local seq = 0
local function Set(name, seconds)
  seq = seq + 1
  ctx[name] = { seq = seq, until_ = seconds == math.huge and math.huge or (GetTime() + (seconds or 0)) }
end
local function Current()
  local best, bestSeq
  local now = GetTime()
  for name, c in pairs(ctx) do
    if c.until_ == math.huge or now <= c.until_ then
      if not bestSeq or c.seq > bestSeq then best, bestSeq = name, c.seq end
    end
  end
  return best
end

local function Categorize(delta)
  local c = Current()
  if not c then return "Other" end
  if c == "Mail" then return delta >= 0 and "Auction House" or "Mail" end -- AH sale gold arrives by mail
  return c -- Vendor / Training / Trade / Loot / Quests / Travel / Auction House
end

local function Record(delta)
  if delta == 0 then return end
  local cat = Categorize(delta)
  local db = ns.db
  table.insert(db.cash, { t = time(), amount = delta, cat = cat, char = (ns.CharKey and ns.CharKey()) or "?" })
  while #db.cash > MAX do table.remove(db.cash, 1) end
  -- keep the per-character gold balance up to date
  local k = (ns.CharKey and ns.CharKey()) or "?"
  db.gold[k] = db.gold[k] or {}
  db.gold[k][ns.Today()] = GetMoney()
  ns.Fire("CashUpdated")
end

-- totals since a time: per-category net, plus income / expense / net. char = optional: only that character.
function ns.CashTotals(since, char)
  local cats, income, expense = {}, 0, 0
  for _, e in ipairs(ns.db.cash) do
    if (not since or e.t >= since) and (not char or e.char == char) then
      cats[e.cat] = (cats[e.cat] or 0) + e.amount
      if e.amount >= 0 then income = income + e.amount else expense = expense + e.amount end
    end
  end
  return cats, income, expense, income + expense
end

function ns.CashRows(since, char)
  local rows = {}
  for _, e in ipairs(ns.db.cash) do
    if (not since or e.t >= since) and (not char or e.char == char) then rows[#rows + 1] = e end
  end
  return rows
end

-- every character that has any recorded money or gold, sorted (Name-Realm keys)
function ns.CharList()
  local seen, list = {}, {}
  for _, e in ipairs(ns.db.cash or {}) do if e.char and e.char ~= "?" then seen[e.char] = true end end
  for k in pairs(ns.db.gold or {}) do if k ~= "?" then seen[k] = true end end
  for k in pairs(seen) do list[#list + 1] = k end
  table.sort(list)
  return list
end

-- one character's latest gold balance
function ns.CharGold(char)
  local days = ns.db.gold and ns.db.gold[char]
  if not days then return 0 end
  local last, lastDay = 0, -1
  for day, m in pairs(days) do if day > lastDay then last, lastDay = m, day end end
  return last
end

-- total gold across all characters (latest balance each)
function ns.TotalGold()
  local total = 0
  for _, days in pairs(ns.db.gold or {}) do
    local last, lastDay = 0, -1
    for day, m in pairs(days) do if day > lastDay then last, lastDay = m, day end end
    total = total + last
  end
  return total
end

---------------------------------------------------------------- per-item vendor purchases (detail only)
local function HookMerchant()
  if ns.merchantHooked then return end
  ns.merchantHooked = true
  if BuyMerchantItem then
    hooksecurefunc("BuyMerchantItem", function(index, qty)
      if not GetMerchantItemInfo then return end
      local link = GetMerchantItemLink and GetMerchantItemLink(index)
      local id = link and tonumber(link:match("item:(%d+)"))
      local name, _, price, stack = GetMerchantItemInfo(index)
      if id and price and price > 0 then
        qty = qty or 1
        ns.LedgerAdd({ kind = "buy", id = id, name = name, qty = qty * (stack or 1), amount = -price * qty, note = L["Vendor"] })
      end
    end)
  end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_ENTERING_WORLD",
                     "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
                     "TRAINER_SHOW", "TRAINER_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE",
                     "QUEST_TURNED_IN", "LOOT_OPENED", "LOOT_CLOSED", "TAXIMAP_OPENED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
  if not ns.db then return end
  if e == "PLAYER_MONEY" then
    local m = GetMoney()
    if lastMoney then Record(m - lastMoney) end
    lastMoney = m
  elseif e == "PLAYER_ENTERING_WORLD" then
    lastMoney = GetMoney()
    HookMerchant()
  elseif e == "MERCHANT_SHOW" then Set("Vendor", math.huge); HookMerchant()
  elseif e == "MERCHANT_CLOSED" then Set("Vendor", 2)       -- keep briefly: the money event can arrive just after
  elseif e == "MAIL_SHOW" then Set("Mail", math.huge)
  elseif e == "MAIL_CLOSED" then Set("Mail", 2)
  elseif e == "TRAINER_SHOW" then Set("Training", math.huge)
  elseif e == "TRAINER_CLOSED" then Set("Training", 2)
  elseif e == "TRADE_SHOW" or e == "TRADE_ACCEPT_UPDATE" then Set("Trade", math.huge)
  elseif e == "TRADE_CLOSED" then Set("Trade", 3)
  elseif e == "QUEST_TURNED_IN" then Set("Quests", 3)
  elseif e == "LOOT_OPENED" then Set("Loot", math.huge)
  elseif e == "LOOT_CLOSED" then Set("Loot", 3)
  elseif e == "TAXIMAP_OPENED" then Set("Travel", 8)
  elseif e == "AUCTION_HOUSE_SHOW" then Set("Auction House", math.huge)
  elseif e == "AUCTION_HOUSE_CLOSED" then Set("Auction House", 2)
  end
end)

ns.On("Loaded", function()
  ns.db.cash = ns.db.cash or {}
  ns.db.gold = ns.db.gold or {}
end)
