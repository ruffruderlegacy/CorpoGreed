-- CorpoGreed advisor: for anything you own, is it better to sell it, smelt it, craft it, or hold it?
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

local GREEN, YELLOW, RED, GREY = "6fcf8f", "ffd24a", "ff6f61", "9a9a9a"
ns.ADV_COLORS = { GREEN = GREEN, YELLOW = YELLOW, RED = RED, GREY = GREY }

local function VendorPrice(id)
  local v = select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(id))
  return v and v > 0 and v or nil
end
ns.VendorPrice = VendorPrice

-- recipes that use an item: { {prof, out, rec}, ... } (rebuilt when recipes change)
local usedIn = {}
local function RebuildUsedIn()
  usedIn = {}
  for prof, book in pairs(ns.db.recipes) do
   if ns.ProfEnabled(prof) then
    for out, rec in pairs(book) do
      for rid in pairs(rec.reagents) do
        usedIn[rid] = usedIn[rid] or {}
        table.insert(usedIn[rid], { prof = prof, out = out, rec = rec })
      end
    end
   end
  end
end
ns.On("Loaded", RebuildUsedIn)
ns.On("RecipesUpdated", RebuildUsedIn)

local Options
-- best net value of one unit, following crafting chains up to 3 steps (ore -> bar -> bronze -> dagger)
local function Best(id, depth, memo)
  local opts = Options(id, depth, memo)
  return opts[1] and opts[1].value or nil, opts[1]
end

-- every way to turn one unit into money, best first: { kind, label, value, out }
Options = function(id, depth, memo)
  depth, memo = depth or 0, memo or {}
  if memo[id] then return memo[id] end
  memo[id] = {} -- cycle guard
  local opts = {}
  local p = ns.Price(id)
  if p then opts[#opts + 1] = { kind = "sell", label = L["Sell on AH"], value = p * (1 - ns.AH_CUT) } end
  local v = VendorPrice(id)
  if v then opts[#opts + 1] = { kind = "vendor", label = "Vendor", value = v } end
  local de = ns.DisenchantValue and ns.DisenchantValue(id)
  if de then
    opts[#opts + 1] = { kind = "disenchant", value = de,
                        label = ns.CanDisenchant() and "Disenchant" or L["Disenchant (ask an enchanter)"] }
  end
  if depth < 3 then
    for _, u in ipairs(usedIn[id] or {}) do
     if not ns.IsIgnored(u.out) then
      local outVal, outBest = Best(u.out, depth + 1, memo)
      if outVal then
        local others, ok = 0, true
        for rid, n in pairs(u.rec.reagents) do
          if rid ~= id then
            local c = ns.BuyCost(rid)
            if c then others = others + c * n else ok = false end
          end
        end
        local need = u.rec.reagents[id]
        if ok and need and need > 0 then
          local verb = ns.IsSmelt(u.prof) and L["Smelt"] or L["Craft"]
          -- show the whole chain when the output is itself worth more crafted (bar -> bronze -> dagger)
          local path = ns.ItemInfo(u.out)
          if outBest and outBest.path then path = path .. " > " .. outBest.path end
          opts[#opts + 1] = { kind = verb:lower(), label = verb .. " > " .. path, path = path, out = u.out, color = u.rec.color,
                              value = (outVal * (u.rec.made or 1) - others) / need }
        end
      end
     end
    end
  end
  table.sort(opts, function(a, b) return a.value > b.value end)
  memo[id] = opts
  return opts
end
ns.Options = Options

-- one verdict per item: action, colour, value each, gain vs plain selling
function ns.Advise(id)
  local opts = Options(id)
  local best = opts[1]
  if not best then return nil end
  local sell
  for _, o in ipairs(opts) do if o.kind == "sell" then sell = o break end end
  local usual = ns.Usual(id)
  local p = ns.Price(id)
  local a = { opts = opts, best = best, value = best.value, gain = sell and best.value - sell.value or 0 }
  if best.kind ~= "sell" and best.kind ~= "vendor" and (not sell or best.value > sell.value * 1.1) then
    a.verdict, a.color = best.label, GREEN
  elseif best.kind == "vendor" then
    a.verdict, a.color = L["Sell to vendor"], YELLOW
  elseif p and usual and p < usual * 0.85 then
    a.verdict, a.color = L["Hold - cheap right now"], RED
  elseif p and usual and p > usual * 1.15 then
    a.verdict, a.color = L["Sell now - above usual"], GREEN
  else
    a.verdict, a.color = L["Sell"], YELLOW
  end
  return a
end

---------------------------------------------------------------- tooltip lines
local function TooltipAdd(tt, id)
  if not id or not ns.db then return end
  local bags, bank = ns.OwnedSplit(id)
  if bags + bank > 0 then
    tt:AddDoubleLine(L["|cff3987e5CG|r you own"], (bags + bank) .. (bank > 0 and (" (" .. bank .. L[" in bank)"]) or ""), 1, 1, 1, 1, 1, 1)
  end
  if ns.IsIgnored(id) then tt:AddLine(L["|cff3987e5CG|r |cff808080ignored|r"]) return end
  local a = ns.Advise(id)
  if not a or #a.opts < 2 then return end
  tt:AddLine(L["|cff3987e5CG|r best use (per item): |cff"] .. a.color .. a.verdict .. "|r")
  local top = a.opts[1].value
  for i = 1, math.min(4, #a.opts) do
    local o = a.opts[i]
    local col = i == 1 and GREEN or (o.value >= top * 0.9 and YELLOW or RED)
    tt:AddDoubleLine(L["   |cff"] .. col .. o.label .. "|r", ns.Money(o.value), 1, 1, 1, 1, 1, 1)
  end
end

ns.On("Loaded", function()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      if tt == GameTooltip or tt == ItemRefTooltip then TooltipAdd(tt, data and data.id) end
    end)
  else
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
      local _, link = tt:GetItem()
      TooltipAdd(tt, link and tonumber(link:match("item:(%d+)")))
    end)
  end
end)

---------------------------------------------------------------- Advisor tab
local tbl
local COLS = {
  { key = "name", label = L["Item (all characters)"], w = 200, align = "LEFT" },
  { key = "owned", label = L["Owned"], w = 50 },
  { key = "verdict", label = L["What to do"], w = 170, align = "LEFT" },
  { key = "value", label = L["Each"], w = 80 },
  { key = "total", label = L["Total"], w = 90 },
  { key = "gain", label = L["Extra vs selling"], w = 95 },
}

local advPage
local function Build(page)
  advPage = page
  local note = UI.Text(page, "GameFontDisableSmall"); note:SetPoint("TOPLEFT", 2, -4)
  note:SetText(L["|cff"] .. GREEN .. L["green|r = do this, it pays more   |cff"] .. YELLOW .. L["yellow|r = just sell   |cff"] .. RED ..
    L["red|r = hold, cheap right now  -  includes your banks (open each once)"])
  local ign = UI.Button(page, L["Show ignored"], 100, 18, function()
    ns.db.settings.showIgnored = not ns.db.settings.showIgnored; UI.Refresh()
  end)
  ign:SetPoint("TOPRIGHT", 0, 0)
  page.ignBtn = ign
  tbl = UI.Table(page, 24, COLS, function(r)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.item.id); GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then UI.ItemMenu(self.item.id) return end
      if IsShiftKeyDown() then UI.SearchAH(ns.ItemInfo(self.item.id)) return end
      ns.db.watch[self.item.id] = true; UI.selected = self.item.id; UI.ShowTabByName("Prices")
    end)
  end)
  tbl.sort = { key = "total", desc = true }
  tbl.onSort = function() UI.Refresh() end
end

local function Refresh()
  if not tbl then return end
  local rows = {}
  local nIgn = 0
  for _ in pairs(ns.db.ignore) do nIgn = nIgn + 1 end
  -- never get stuck on an empty "ignored" view: fall back to advice when nothing is ignored
  if ns.db.settings.showIgnored and nIgn == 0 then ns.db.settings.showIgnored = false end
  local showIgn = ns.db.settings.showIgnored
  advPage.ignBtn.text:SetText(showIgn and L["Back to advice"] or (L["Show ignored ("] .. nIgn .. ")"))
  if showIgn then
    for id in pairs(ns.db.ignore) do
      local bags, bank = ns.OwnedSplit(id)
      rows[#rows + 1] = { id = id, name = ns.ItemInfo(id), owned = bags + bank, bank = bank, verdict = L["Ignored (right-click to undo)"],
                          color = GREY, value = ns.Price(id) or 0, total = (ns.Price(id) or 0) * (bags + bank) }
    end
  else
    for id, n in pairs(ns.AllOwned()) do
      local a = not ns.IsIgnored(id) and ns.ClassEnabled(id) and ns.Advise(id)
      if a and a.value > 0 then
        local _, bank = ns.OwnedSplit(id)
        rows[#rows + 1] = { id = id, name = ns.ItemInfo(id), owned = n, bank = bank, verdict = a.verdict, color = a.color,
                            value = a.value, total = a.value * n, gain = a.gain > 0 and a.gain * n or nil }
      end
    end
  end
  tbl:Set(rows, function(r, row)
    UI.Dot(r.dot, row.color)
    r.icon:SetTexture(ns.Icon(row.id))
    r.cells[1]:SetText(ns.ColoredName(row.id))
    r.cells[2]:SetText(row.owned .. (row.bank and row.bank > 0 and (" |cff808080(" .. row.bank .. "b)|r") or ""))
    r.cells[3]:SetText(L["|cff"] .. row.color .. row.verdict .. "|r")
    r.cells[4]:SetText(ns.Money(row.value))
    r.cells[5]:SetText(ns.Money(row.total))
    r.cells[6]:SetText(row.gain and (L["|cff"] .. GREEN .. "+" .. ns.Money(row.gain, true) .. "|r") or "")
  end)
end

UI.AddTab("Advisor", 30, Build, Refresh)
