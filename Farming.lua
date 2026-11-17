-- CorpoGreed farming: what you mine / gather / loot (and its AH value), gold looted, and warnings for valuable drops.
-- db.loot[day][source][itemID] = qty      db.lootGold[day][source] = copper
local ADDON, ns = ...
local L = ns.L

local GATHER = { ["Mining"] = "Mining", ["Herb Gathering"] = "Herbalism", ["Skinning"] = "Skinning",
                 ["Disenchant"] = "Disenchant", ["Opening"] = "Chests", ["Pick Lock"] = "Chests" }
-- the game reports spell names in the client's language: add the localized names too
for id, src in pairs({ [2575] = "Mining", [2366] = "Herbalism", [8613] = "Skinning", [13262] = "Disenchant", [3365] = "Chests", [1804] = "Chests" }) do
  local n = ns.SpellName(id)
  if n then GATHER[n] = src end
end
local lastGather, lastGatherT = nil, 0
local lootSource, lootOpen, lootClosedT = nil, false, 0

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id))
end

local function Pattern(fmt)
  if not fmt then return nil end
  fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  fmt = fmt:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. fmt .. "$"
end

local PATTERNS
local function Patterns()
  if PATTERNS then return PATTERNS end
  PATTERNS = {}
  for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }) do
    local p = Pattern(_G[g])
    if p then PATTERNS[#PATTERNS + 1] = p end
  end
  return PATTERNS
end

local function InLoot() return lootOpen or (GetTime() - lootClosedT) < 3 end

---------------------------------------------------------------- valuable drop warnings
local function BindType(id)
  local info = { (C_Item and C_Item.GetItemInfo or GetItemInfo)(id) }
  return info[14], info[3]
end

local function Warn(text)
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
    RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
  elseif UIErrorsFrame then
    UIErrorsFrame:AddMessage(text, 1, 0.82, 0)
  end
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  ns.Print(text)
end

-- worth warning about: bind-on-equip (or no binding) and the AH pays at least the threshold
function ns.ValuableBoE(id)
  if ns.IsIgnored(id) or ns.db.settings.warnAt == 0 then return end
  local value = ns.Price(id) or ns.Usual(id)
  if not value then return end
  local bind = BindType(id)
  if bind == 1 or bind == 4 then return end -- bind on pickup / quest item: can't sell anyway
  if value >= (ns.db.settings.warnAt or 3000) then return value, bind == 2 end
end

local function CheckDrop(id, link)
  local value, boe = ns.ValuableBoE(id)
  if value then
    Warn((L["|cff3987e5CG|r %s sells for %s on the AH%s"]):format(link or ns.ColoredName(id), ns.Money(value),
      boe and L[" - don't equip it, sell it!"] or ""))
  end
end

---------------------------------------------------------------- recording
local function Record(id, qty, source)
  local db, day = ns.db, ns.Today()
  db.loot[day] = db.loot[day] or {}
  db.loot[day][source] = db.loot[day][source] or {}
  local t = db.loot[day][source]
  t[id] = (t[id] or 0) + qty
  -- live session counts: only gathering professions, and only while a session is running (Start pressed)
  local GATHER_SOURCES = { Mining = true, Herbalism = true, Skinning = true, Fishing = true }
  if ns.session and ns.session.active and GATHER_SOURCES[source] then
    ns.session.items[id] = (ns.session.items[id] or 0) + qty
    ns.session.n = ns.session.n + qty
    ns.Fire("SessionUpdated", id, qty, source)
  end
  ns.Fire("LootUpdated")
end

-- read everything in the loot window directly - reliable for mining/herbs/skinning, unlike chat messages
local function ReadLootWindow()
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  for i = 1, n do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local _, _, quantity = GetLootSlotInfo(i)
      Record(id, quantity or 1, lootSource or "Mobs")
      CheckDrop(id, link)
    end
  end
end

local lootRead = false
local ev = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "LOOT_OPENED", "LOOT_CLOSED",
                     "START_LOOT_ROLL", "EQUIP_BIND_CONFIRM" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, ...)
  if not ns.db then return end
  if e == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" then
      local g = GATHER[SpellName(spellID) or ""]
      if g then lastGather, lastGatherT = g, GetTime() end
    end
  elseif e == "LOOT_OPENED" then
    lootOpen = true
    if IsFishingLoot and IsFishingLoot() then lootSource = "Fishing"
    elseif lastGather and GetTime() - lastGatherT < 6 then lootSource = lastGather
    else lootSource = "Mobs" end
    if not lootRead then lootRead = true; ReadLootWindow() end
  elseif e == "LOOT_CLOSED" then
    lootOpen, lootClosedT, lootRead = false, GetTime(), false
  elseif e == "START_LOOT_ROLL" then
    local rollID = ...
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    local id = link and tonumber(link:match("item:(%d+)"))
    local value = id and ns.ValuableBoE(id)
    if value then Warn((L["|cff3987e5CG|r %s is worth %s on the AH - roll for it!"]):format(link, ns.Money(value))) end
  elseif e == "EQUIP_BIND_CONFIRM" then
    -- "equipping this will bind it to you" - last chance
    local kind, id = GetCursorInfo()
    local value = kind == "item" and id and ns.ValuableBoE(id)
    if value then Warn((L["|cffff6f61STOP|r - this sells for %s on the AH. Equipping binds it!"]):format(ns.Money(value))) end
  end
end)

ns.On("Loaded", function()
  ns.db.loot = ns.db.loot or {}
  ns.db.lootGold = ns.db.lootGold or {}
  ns.db.settings.warnAt = ns.db.settings.warnAt or 3000 -- 30s
end)

---------------------------------------------------------------- totals for the ledger
-- looted gold (cash) and farmed items valued at today's AH price, since a day index
function ns.FarmTotals(sinceDay)
  local gold, value = 0, 0
  for day, srcs in pairs(ns.db.lootGold) do
    if not sinceDay or day >= sinceDay then for _, c in pairs(srcs) do gold = gold + c end end
  end
  for day, srcs in pairs(ns.db.loot) do
    if not sinceDay or day >= sinceDay then
      for _, items in pairs(srcs) do
        for id, n in pairs(items) do
          local p = ns.Price(id) or ns.VendorPrice(id)
          if p then value = value + p * n end
        end
      end
    end
  end
  return gold, value
end

-- rows for the Farming view: one per day + source + item
function ns.FarmRows()
  local rows = {}
  for day, srcs in pairs(ns.db.loot) do
    for src, items in pairs(srcs) do
      for id, n in pairs(items) do
        local p = ns.Price(id) or ns.VendorPrice(id)
        rows[#rows + 1] = { t = day * 86400 + 43200, day = day, kind = src, id = id, name = ns.ItemInfo(id), qty = n,
                            amount = p and p * n or nil }
      end
    end
  end
  for day, srcs in pairs(ns.db.lootGold) do
    for src, c in pairs(srcs) do
      rows[#rows + 1] = { t = day * 86400 + 43200, day = day, kind = src, name = L["Gold looted"], amount = c }
    end
  end
  return rows
end
