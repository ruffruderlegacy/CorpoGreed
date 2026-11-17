-- CorpoGreed crafting: remembers your recipes when a profession window is open, then ranks them by profit.
local ADDON, ns = ...

local COLORS = { optimal = "ff8040", medium = "ffff00", easy = "40bf40", trivial = "808080" }
local RETAIL_DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
ns.SKILL_COLORS = COLORS

local function IdFromLink(link) return link and tonumber(link:match("item:(%d+)")) end

local function ReadClassic()
  local prof = GetTradeSkillLine and GetTradeSkillLine()
  if prof then prof = prof:gsub("^%s+", ""):gsub("%s+$", "") end
  if not prof or prof == "" or prof == "UNKNOWN" then return end
  local book = ns.db.recipes[prof] or {}
  ns.db.recipes[prof] = book
  local n = 0
  for i = 1, GetNumTradeSkills() do
    local name, skillType = GetTradeSkillInfo(i)
    if name and skillType ~= "header" and skillType ~= "subheader" then
      local out = IdFromLink(GetTradeSkillItemLink(i))
      if out then
        local minMade, maxMade = GetTradeSkillNumMade(i)
        local reagents, ok = {}, true
        for r = 1, GetTradeSkillNumReagents(i) do
          local _, _, count = GetTradeSkillReagentInfo(i, r)
          local rid = IdFromLink(GetTradeSkillReagentItemLink(i, r))
          if rid and count then reagents[rid] = count else ok = false end
        end
        if ok then
          book[out] = { name = name, color = skillType, made = ((minMade or 1) + (maxMade or minMade or 1)) / 2,
                        reagents = reagents, seen = time() }
          n = n + 1
        end
      end
    end
  end
  return n
end

local function ReadRetail()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return end
  local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  local prof = info and info.professionName
  if prof then prof = prof:gsub("^%s+", ""):gsub("%s+$", "") end
  if not prof or prof == "" then return end
  local book = ns.db.recipes[prof] or {}
  ns.db.recipes[prof] = book
  local n = 0
  for _, rid in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
    local ri = C_TradeSkillUI.GetRecipeInfo(rid)
    if ri and ri.learned then
      local s = C_TradeSkillUI.GetRecipeSchematic(rid, false)
      if s and s.outputItemID then
        local reagents = {}
        for _, slot in ipairs(s.reagentSlotSchematics or {}) do
          local r = slot.reagents and slot.reagents[1]
          if r and r.itemID and (slot.reagentType == nil or slot.reagentType == 1) then
            reagents[r.itemID] = slot.quantityRequired
          end
        end
        book[s.outputItemID] = { name = ri.name, color = RETAIL_DIFF[ri.relativeDifficulty] or "trivial",
                                 made = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2,
                                 reagents = reagents, seen = time() }
        n = n + 1
      end
    end
  end
  return n
end

function ns.RebuildCraftItems()
  ns.craftItems = {}
  for _, book in pairs(ns.db.recipes) do
    for out, r in pairs(book) do
      ns.craftItems[out] = true
      for rid in pairs(r.reagents) do ns.craftItems[rid] = true end
    end
  end
end

local pending = false
local function Read()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    local n = (GetNumTradeSkills and ReadClassic()) or ReadRetail()
    if n and n > 0 then ns.RebuildCraftItems(); ns.Fire("RecipesUpdated") end
  end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() if ns.db then Read() end end)
ns.On("Loaded", function()
  -- clean out any blank/whitespace profession names stored by older versions
  for prof in pairs(ns.db.recipes) do
    if type(prof) ~= "string" or prof:gsub("%s", "") == "" then ns.db.recipes[prof] = nil end
  end
  ns.RebuildCraftItems()
end)

-- One row per recipe: cost to make, AH value, profit after the 5% cut.
function ns.CraftRows(profFilter)
  local rows = {}
  for prof, book in pairs(ns.db.recipes) do
    if (not profFilter or profFilter == prof) and ns.ProfEnabled(prof) then
      for out, r in pairs(book) do
       if not ns.IsIgnored(out) then
        local cost, missing = 0, false
        for rid, n in pairs(r.reagents) do
          local c = ns.BuyCost(rid)
          if c then cost = cost + c * n else missing = true end
        end
        local sell, qty, seenAt = ns.Price(out)
        local value = sell and sell * (r.made or 1)
        local profit = value and not missing and (value * (1 - ns.AH_CUT) - cost)
        -- "thin": only a few listed, or listed far above its usual price -> the profit may not be real
        local usual = ns.Usual(out)
        local thin = (qty and qty <= 3) or (sell and usual and sell > usual * 1.5) or false
        rows[#rows + 1] = { id = out, prof = prof, name = r.name, color = r.color, cost = not missing and cost or nil, thin = thin,
                            sell = value, qty = qty, profit = profit, pct = profit and cost > 0 and profit / cost or nil,
                            avg7 = ns.DailyAvg(out, 7), vendor = select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(out)) }
       end
      end
    end
  end
  return rows
end

function ns.Professions()
  local list = {}
  for prof in pairs(ns.db.recipes) do if ns.ProfEnabled(prof) then list[#list + 1] = prof end end
  table.sort(list)
  return list
end
