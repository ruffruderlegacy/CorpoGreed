-- CorpoGreed "Worth Making" panel: a separate list docked beside the profession window,
-- ranking the recipes you know for the open profession by profit. No injection into Blizzard
-- rows (that caused overlap) and works whether the window is classic TradeSkillFrame or modern.
local ADDON, ns = ...
local L = ns.L
local GREEN, RED = "6fcf8f", "ff6f61"
local COLORS = ns.SKILL_COLORS or { optimal = "ff8040", medium = "ffff00", easy = "40bf40", trivial = "808080" }
local MAX = 14

local function Short(c)
  if not c then return "|cff808080--|r" end
  local a = math.abs(c)
  local s = a >= 10000 and ("%.1fg"):format(a / 10000)
    or a >= 100 and ("%ds"):format(math.floor(a / 100))
    or ("%dc"):format(math.floor(a))
  return "|cff" .. (c >= 0 and GREEN .. "+" or RED .. "-") .. s .. "|r"
end

local function CurrentProf()
  if GetTradeSkillLine then
    local p = GetTradeSkillLine()
    if p and p ~= "UNKNOWN" then return p end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
    local ok, i = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if ok and i then return i.professionName end
  end
end

local function Host()
  if TradeSkillFrame and TradeSkillFrame.IsShown and TradeSkillFrame:IsShown() then return TradeSkillFrame end
  if ProfessionsFrame and ProfessionsFrame.IsShown and ProfessionsFrame:IsShown() then return ProfessionsFrame end
end

local panel
local function Build()
  panel = CreateFrame("Frame", "CorpoGreedBestCrafts", UIParent, "BackdropTemplate")
  panel:SetSize(210, 60)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- normalize to a UIParent anchor and remember it so the spot sticks across sessions
    local x, y = self:GetLeft(), self:GetTop()
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    ns.db.bestPanel = { x = x, y = y }
  end)
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0, 0, 0, 0.82)
    panel:SetBackdropBorderColor(0.22, 0.53, 0.9, 1)
  end
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", 8, -6)
  title:SetText("|cff3987e5CorpoGreed|r \226\128\162 Worth Making")
  panel.title = title
  local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sub:SetPoint("TOPLEFT", 8, -20)
  panel.sub = sub

  panel.rows = {}
  for i = 1, MAX do
    local nameFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("TOPLEFT", 8, -32 - (i - 1) * 14)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWidth(140)
    nameFS:SetWordWrap(false)
    local profFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profFS:SetPoint("TOPRIGHT", -8, -32 - (i - 1) * 14)
    profFS:SetJustifyH("RIGHT")
    panel.rows[i] = { name = nameFS, profit = profFS }
  end
end

local function Reposition()
  panel:ClearAllPoints()
  -- 1) if you've dragged it somewhere, keep that spot (now remembered across sessions)
  local saved = ns.db.bestPanel
  if saved and saved.point then saved = nil; ns.db.bestPanel = nil end  -- drop old-format saves
  if saved and saved.x then
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
    return
  end
  -- 2) otherwise dock beside the profession window, on whichever side actually has room
  local h = Host()
  if h then
    local hl, hr = h:GetLeft(), h:GetRight()
    local sw = UIParent:GetWidth() or 1024
    local need = 210 + 8
    if hl and hr and (sw - hr) < need and hl >= need then
      panel:SetPoint("TOPRIGHT", h, "TOPLEFT", -4, 0)   -- no room on the right -> dock left
    else
      panel:SetPoint("TOPLEFT", h, "TOPRIGHT", 4, 0)     -- default: dock right
    end
    return
  end
  -- 3) no window open: park it center-right
  panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
end

local function Refresh()
  if not (panel and panel:IsShown()) then return end
  local prof = CurrentProf()
  local rows = prof and ns.CraftRows(prof) or {}
  table.sort(rows, function(a, b)
    local pa, pb = a.profit or -math.huge, b.profit or -math.huge
    if pa ~= pb then return pa > pb end
    return (a.name or "") < (b.name or "")
  end)
  panel.title:SetText("|cff3987e5CorpoGreed|r \226\128\162 Worth Making")
  if not prof then
    panel.sub:SetText("Open a profession window.")
  elseif #rows == 0 then
    panel.sub:SetText(prof .. ": no priced recipes yet. Scan the AH (/cg scan).")
  else
    panel.sub:SetText(prof .. "  \226\128\148  top by profit")
  end
  local shown = 0
  for i = 1, MAX do
    local r, row = rows[i], panel.rows[i]
    if r then
      shown = shown + 1
      local col = COLORS[r.color] or "ffffff"
      row.name:SetText("|cff" .. col .. (r.name or "?") .. "|r" .. (r.thin and " |cff808080?|r" or ""))
      row.profit:SetText(Short(r.profit))
      row.name:Show(); row.profit:Show()
    else
      row.name:Hide(); row.profit:Hide()
    end
  end
  panel:SetHeight(36 + math.max(shown, 1) * 14 + 6)
  panel:SetWidth(210)
end

local function Show()
  if not panel then Build() end
  Reposition()
  panel:Show()
  Refresh()
end
local function Hide() if panel then panel:Hide() end end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
  if e == "ADDON_LOADED" then return end
  if not ns.db then return end
  if ns.db.bestPanelOff then return end  -- user turned the panel off in Settings
  if e == "TRADE_SKILL_CLOSE" then Hide() else Show() end
end)

ns.On("PricesUpdated", Refresh)
ns.On("RecipesUpdated", Refresh)

-- let Settings / slash toggle it
ns.ShowBestPanel = function(on)
  ns.db.bestPanelOff = not on
  if not on then Hide() elseif Host() then Show() end
end
