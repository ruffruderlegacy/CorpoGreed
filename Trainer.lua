-- CorpoGreed trainer scanner: at a profession trainer, show which recipes are worth learning.
-- Reads trainable (unlearned) recipes, prices their reagents and result, and ranks them by profit.
local ADDON, ns = ...
local L = ns.L
local GREEN, RED, GREY = "6fcf8f", "ff6f61", "9a9a9a"

local panel, rows

-- read the item the recipe makes (best-effort: trainer gives a link on most profession recipes)
local function ServiceOutput(i)
  local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
  local id = link and tonumber(link:match("item:(%d+)"))
  return id
end

local function Scan()
  local out = {}
  local n = GetNumTrainerServices and GetNumTrainerServices() or 0
  for i = 1, n do
    local name, rank, category = GetTrainerServiceInfo(i)
    -- only recipes you don't have yet and can eventually use
    if name and category == "available" then
      local cost = 0
      local nr = GetTrainerServiceNumReagents and GetTrainerServiceNumReagents(i) or 0
      local reagents, missing = {}, false
      for r = 1, nr do
        local rname, _, count = GetTrainerServiceReagentInfo(i, r)
        local rlink = GetTrainerServiceReagentItemLink and GetTrainerServiceReagentItemLink(i, r)
        local rid = rlink and tonumber(rlink:match("item:(%d+)"))
        if rid then
          local c = ns.BuyCost(rid)
          if c then cost = cost + c * (count or 1) else missing = true end
        elseif rname then
          missing = true -- a reagent with no link we can price
        end
      end
      local outID = ServiceOutput(i)
      local value = outID and ns.Price(outID)
      local trainCost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
      local skill = GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i)
      out[#out + 1] = {
        name = name, id = outID, skill = skill, train = trainCost,
        cost = (not missing) and cost or nil,
        value = value,
        profit = (value and not missing) and (value * (1 - ns.AH_CUT) - cost) or nil,
      }
    end
  end
  return out
end

---------------------------------------------------------------- panel
local function TrainerFrame()
  for _, name in ipairs({ "ClassTrainerFrame", "TrainerFrame", "ProfessionsTrainerFrame" }) do
    local f = _G[name]
    if f and f:IsShown() then return f end
  end
end

local function MakeRow(i, y)
  local r = CreateFrame("Button", nil, panel)
  r:SetHeight(18); r:SetPoint("TOPLEFT", 6, y); r:SetPoint("RIGHT", -6, 0)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
  r.dot = r:CreateTexture(nil, "ARTWORK"); r.dot:SetSize(7, 7); r.dot:SetPoint("LEFT", 0, 0)
  r.name = ns.UI.Text(r); r.name:SetPoint("LEFT", 12, 0); r.name:SetPoint("RIGHT", -64, 0)
  r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.val = ns.UI.Text(r); r.val:SetPoint("RIGHT", 0, 0); r.val:SetJustifyH("RIGHT")
  r:SetScript("OnEnter", function(self)
    local row = self.row; if not row then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.name, 1, 1, 1)
    if row.id then GameTooltip:AddDoubleLine(L["AH value"], row.value and ns.Money(row.value) or L["no data"], 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:AddDoubleLine(L["Cost"], row.cost and ns.Money(row.cost) or "?", 0.8, 0.8, 0.8, 1, 1, 1)
    if row.train and row.train > 0 then GameTooltip:AddDoubleLine(L["Train cost"], ns.Money(row.train), 0.8, 0.8, 0.8, 1, 1, 1) end
    if row.skill then GameTooltip:AddDoubleLine(L["Skill needed"], row.skill, 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  return r
end

local function Build()
  panel = CreateFrame("Frame", "CorpoGreedTrainer", UIParent, "BackdropTemplate")
  ns.UI.Skin(panel, 0.9); panel:SetSize(280, 340); panel:SetFrameStrata("HIGH")
  local title = ns.UI.Text(panel, "GameFontNormal"); title:SetPoint("TOPLEFT", 8, -8)
  title:SetText("|cff3987e5CG|r " .. L["Worth learning"])
  panel.sub = ns.UI.Text(panel, "GameFontDisableSmall"); panel.sub:SetPoint("TOPLEFT", 8, -26)
  panel.sub:SetText(L["Ranked by profit per craft (after AH cut). Scan the AH first for prices."])
  rows = {}
  for i = 1, 14 do rows[i] = MakeRow(i, -42 - (i - 1) * 18) end
  panel.empty = ns.UI.Text(panel, "GameFontDisable"); panel.empty:SetPoint("CENTER"); panel.empty:SetWidth(250)
  panel:Hide()
end

local function Refresh()
  local tf = TrainerFrame()
  if not tf then if panel then panel:Hide() end return end
  if not panel then Build() end
  panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", tf, "TOPRIGHT", 4, 0)
  panel:SetScale(ns.db.settings.scale or 1.4)

  local list = Scan()
  table.sort(list, function(a, b)
    if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
    if a.profit and b.profit then return a.profit > b.profit end
    return (a.name or "") < (b.name or "")
  end)
  local shown = 0
  for i, r in ipairs(rows) do
    local d = list[i]
    if d then
      r.row = d
      local col = (d.profit and d.profit > 0) and GREEN or (d.profit and RED) or GREY
      ns.UI.Dot(r.dot, col)
      r.name:SetText(d.name)
      if d.profit then
        r.val:SetText((d.profit >= 0 and "|cff" .. GREEN .. "+" or "|cff" .. RED .. "-") .. ns.Money(math.abs(d.profit), true) .. "|r")
      elseif d.cost then
        r.val:SetText("|cff808080" .. ns.Money(d.cost, true) .. "?|r")
      else
        r.val:SetText("|cff808080-|r")
      end
      r:Show(); shown = shown + 1
    else
      r.row = nil; r:Hide()
    end
  end
  panel.empty:SetText(#list == 0 and L["Nothing new to learn here."] or "")
  panel:Show()
end

local pending = false
local function Queue()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; Refresh() end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e)
  if not ns.db then return end
  if e == "TRAINER_CLOSED" then if panel then panel:Hide() end return end
  Queue()
end)
ns.On("PricesUpdated", function() if panel and panel:IsShown() then Queue() end end)
