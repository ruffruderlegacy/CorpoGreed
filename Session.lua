-- CorpoGreed session tracker: a small live popup of what you've gathered this play session.
-- "Gathered: Copper Ore x15, Tin Ore x8..." with total AH value and gold/hour. Not saved between sessions.
local ADDON, ns = ...
local L = ns.L

local function Session()
  ns.session = ns.session or { active = false, start = time(), items = {}, n = 0 }
  return ns.session
end

function ns.StartSession()
  ns.session = { active = true, start = time(), items = {}, n = 0 }
  ns.Fire("SessionUpdated")
end

function ns.StopSession()
  if ns.session then ns.session.active = false end
  ns.Fire("SessionUpdated")
end

function ns.SessionActive() return ns.session and ns.session.active or false end

local panel, rows

local function Build()
  panel = CreateFrame("Frame", "CorpoGreedSession", UIParent, "BackdropTemplate")
  ns.UI.Skin(panel, 0.85); panel:SetSize(230, 220); panel:SetFrameStrata("MEDIUM")
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    ns.db.settings.sessionPos = { p, x, y }
  end)
  panel:SetScale((ns.db.settings.scale or 1.4) * 0.85)

  local title = ns.UI.Text(panel, "GameFontNormal"); title:SetPoint("TOPLEFT", 8, -8)
  title:SetText("|cff3987e5CG|r " .. L["Session"])
  panel.time = ns.UI.Text(panel, "GameFontDisableSmall"); panel.time:SetPoint("TOPRIGHT", -8, -10)

  local close = ns.UI.Button(panel, "x", 18, 16, function() ns.db.settings.sessionShown = false; panel:Hide() end)
  close:SetPoint("TOPRIGHT", -4, -4); close:Hide()
  panel:SetScript("OnEnter", function() close:Show() end)
  panel:SetScript("OnLeave", function() if not panel:IsMouseOver() then close:Hide() end end)

  -- Start begins a fresh session; while running it becomes Stop
  panel.startBtn = ns.UI.Button(panel, L["Start session"], 110, 18, function()
    if ns.SessionActive() then ns.StopSession() else ns.StartSession() end
  end)
  panel.startBtn:SetPoint("BOTTOMLEFT", 8, 8)
  panel.total = ns.UI.Text(panel); panel.total:SetPoint("BOTTOMRIGHT", -8, 10); panel.total:SetJustifyH("RIGHT")
  panel.rate = ns.UI.Text(panel, "GameFontDisableSmall"); panel.rate:SetPoint("BOTTOMRIGHT", -8, 26); panel.rate:SetJustifyH("RIGHT")

  panel.list = CreateFrame("Frame", nil, panel)
  panel.list:SetPoint("TOPLEFT", 8, -30); panel.list:SetPoint("BOTTOMRIGHT", -8, 46)
  panel.empty = ns.UI.Text(panel, "GameFontDisable"); panel.empty:SetPoint("CENTER", panel.list, "CENTER", 0, 0)
  panel.empty:SetWidth(200)
  panel.empty:SetText(L["Press Start, then mine / herb / skin / fish. Only gathering is counted."])
  rows = {}
  panel:Hide()
end

local function Refresh()
  if not panel or not panel:IsShown() then return end
  local s = Session()
  local mins = math.max(1, (time() - s.start) / 60)
  panel.time:SetText(s.active and ("|cff6fcf8f" .. L["recording"] .. "|r " .. ("%dm"):format(math.floor(mins))) or ("%dm"):format(math.floor(mins)))
  panel.startBtn.text:SetText(s.active and L["Stop session"] or L["Start session"])

  -- sort items by quantity
  local list, total = {}, 0
  for id, qty in pairs(s.items) do
    local p = ns.Price(id) or ns.VendorPrice(id) or 0
    total = total + p * qty
    list[#list + 1] = { id = id, qty = qty, val = p * qty }
  end
  table.sort(list, function(a, b) return a.qty > b.qty end)
  panel.empty:SetShown(#list == 0)

  local rowH, max = 16, 10
  for i = 1, max do
    local d = list[i]
    local r = rows[i]
    if d then
      if not r then
        r = CreateFrame("Frame", nil, panel.list); r:SetHeight(rowH)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH); r:SetPoint("RIGHT")
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 0, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = ns.UI.Text(r, "GameFontHighlightSmall"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.name:SetPoint("RIGHT", -40, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.qty = ns.UI.Text(r, "GameFontHighlightSmall"); r.qty:SetPoint("RIGHT", 0, 0); r.qty:SetJustifyH("RIGHT")
        rows[i] = r
      end
      r.icon:SetTexture(ns.Icon(d.id))
      r.name:SetText(ns.ColoredName(d.id))
      r.qty:SetText("|cff6fcf8fx" .. d.qty .. "|r")
      r:Show()
    elseif r then r:Hide() end
  end
  if #list > max then panel.empty:SetText("") end

  panel.total:SetText(L["Value "] .. ns.Money(total))
  panel.rate:SetText(("%s/hr"):format(ns.Money(total / mins * 60, true)))
end

local function Toggle()
  if not panel then Build() end
  local show = not panel:IsShown()
  ns.db.settings.sessionShown = show
  if show then
    local pos = ns.db.settings.sessionPos
    panel:ClearAllPoints()
    if pos then panel:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else panel:SetPoint("CENTER", 200, 0) end
    panel:Show(); Refresh()
  else panel:Hide() end
end
ns.ToggleSession = Toggle
function ns.SessionIsShown() return panel and panel:IsShown() or false end
function ns.ShowSession(show) if (panel and panel:IsShown()) ~= (show and true or false) then Toggle() end end

-- live refresh while shown
local acc = 0
ns.On("Loaded", function()
  Build()
  if ns.db.settings.sessionShown then Toggle() end
  panel:SetScript("OnUpdate", function(self, el)
    acc = acc + el; if acc < 1 then return end; acc = 0
    if self:IsShown() then Refresh() end
  end)
end)
ns.On("SessionUpdated", function() Refresh() end)
