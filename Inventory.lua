-- CorpoGreed inventory: bags + bank for every character (so your bank alt's stock counts too).
local ADDON, ns = ...

local GetNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local function SlotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount end
  else
    local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
    if link then return tonumber(link:match("item:(%d+)")), count end
  end
end

local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
ns.CharKey = CharKey

local function ScanBags(list)
  local t = {}
  for _, bag in ipairs(list) do
    for slot = 1, (GetNumSlots(bag) or 0) do
      local id, n = SlotItem(bag, slot)
      if id then t[id] = (t[id] or 0) + (n or 1) end
    end
  end
  return t
end

local function Me()
  local k = CharKey()
  ns.db.inv[k] = ns.db.inv[k] or { bags = {}, bank = {} }
  return ns.db.inv[k]
end

local function UpdateBags()
  local bags = {}
  for b = 0, (NUM_BAG_SLOTS or 4) + ((NUM_REAGENTBAG_SLOTS or 0)) do bags[#bags + 1] = b end
  Me().bags = ScanBags(bags)
  Me().money = GetMoney()
  ns.Fire("InventoryUpdated")
end

local bankOpen = false
local function UpdateBank()
  if not bankOpen then return end
  -- every container that isn't a carried bag or the keyring: bank, reagent bank, bank bags / tabs
  local carried = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
  local bags = {}
  for b = -3, 40 do
    if (b < 0 or b > carried) and b ~= -2 and (GetNumSlots(b) or 0) > 0 then bags[#bags + 1] = b end
  end
  Me().bank = ScanBags(bags)
  ns.Fire("InventoryUpdated")
end

-- how many of an item: this character (bags+bank) and all characters
function ns.Owned(id)
  local mine, all = 0, 0
  local me = CharKey()
  for k, c in pairs(ns.db.inv) do
    local n = (c.bags[id] or 0) + (c.bank[id] or 0)
    all = all + n
    if k == me then mine = mine + n end
  end
  return mine, all
end

-- across all characters: how many in bags, how many in banks
function ns.OwnedSplit(id)
  local bags, bank = 0, 0
  for _, c in pairs(ns.db.inv) do bags, bank = bags + (c.bags[id] or 0), bank + (c.bank[id] or 0) end
  return bags, bank
end

function ns.OwnedBags(id)
  local c = ns.db.inv[CharKey()]
  return c and (c.bags[id] or 0) or 0
end

-- every item you own anywhere: { [id] = total }
function ns.AllOwned()
  local t = {}
  for _, c in pairs(ns.db.inv) do
    for id, n in pairs(c.bags) do t[id] = (t[id] or 0) + n end
    for id, n in pairs(c.bank) do t[id] = (t[id] or 0) + n end
  end
  return t
end

local pending = false
local function Queue()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; UpdateBags(); UpdateBank() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
pcall(ev.RegisterEvent, ev, "PLAYERBANKSLOTS_CHANGED")
ev:SetScript("OnEvent", function(_, e)
  if not ns.db then return end
  if e == "BANKFRAME_OPENED" then bankOpen = true
  elseif e == "BANKFRAME_CLOSED" then bankOpen = false; return end
  Queue()
end)
