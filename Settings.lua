-- CorpoGreed settings tab: window look, alerts, ignore list, professions and item categories on/off.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local WHITE = "Interface\\Buttons\\WHITE8x8"

local CLASSES = { { 0, L["Consumables"] }, { 1, L["Containers"] }, { 2, L["Weapons"] }, { 3, L["Gems"] }, { 4, L["Armor"] },
                  { 5, L["Reagents"] }, { 7, L["Trade Goods"] }, { 9, L["Recipes"] }, { 12, L["Quest items"] }, { 15, L["Miscellaneous"] } }

local function ClassName(id, fallback)
  local f = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
  local n = f and f(id)
  return (n and n ~= "") and n or fallback
end

---------------------------------------------------------------- widgets
local function Header(p, text, x, y)
  local h = UI.Text(p, "GameFontNormal"); h:SetPoint("TOPLEFT", x, y); h:SetText(text)
  local line = p:CreateTexture(nil, "ARTWORK"); line:SetColorTexture(0.22, 0.53, 0.9, 0.6); line:SetHeight(1)
  line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -3); line:SetWidth(330)
  return h
end

local function Check(p, label, x, y, get, set)
  local cb = CreateFrame("CheckButton", nil, p, "BackdropTemplate")
  cb:SetSize(14, 14); cb:SetPoint("TOPLEFT", x, y); UI.Skin(cb, 0.6)
  local tick = cb:CreateTexture(nil, "ARTWORK"); tick:SetPoint("TOPLEFT", 3, -3); tick:SetPoint("BOTTOMRIGHT", -3, 3)
  tick:SetColorTexture(0.22, 0.53, 0.9, 1)
  cb:SetCheckedTexture(tick)
  cb.label = UI.Text(cb); cb.label:SetPoint("LEFT", cb, "RIGHT", 6, 0); cb.label:SetText(label)
  cb:SetHitRectInsets(0, -200, 0, 0)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  cb.Sync = function(self) self:SetChecked(get() and true or false) end
  return cb
end

local function Slider(p, label, x, y, min, max, step, get, set, fmt, liveApply)
  local s = CreateFrame("Slider", nil, p, "BackdropTemplate")
  s:SetOrientation("HORIZONTAL"); s:SetSize(220, 12); s:SetPoint("TOPLEFT", x, y - 16)
  UI.Skin(s, 0.6)
  s:SetThumbTexture(WHITE)
  local thumb = s:GetThumbTexture(); thumb:SetSize(8, 16); thumb:SetVertexColor(0.22, 0.53, 0.9, 1)
  s:SetMinMaxValues(min, max); s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)
  s.text = UI.Text(p); s.text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
  local function Label(v) s.text:SetText(label .. ": |cffffffff" .. fmt(v) .. "|r") end
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    Label(v)
    if self.syncing then return end
    if liveApply then set(v) else self.pending = v end
  end)
  -- apply things like window scale on release, so the slider doesn't jump under the mouse
  s:SetScript("OnMouseUp", function(self) if self.pending then set(self.pending); self.pending = nil end end)
  s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * step); if self.pending then set(self.pending); self.pending = nil end end)
  s.Sync = function(self) self.syncing = true; self:SetValue(get()); Label(get()); self.syncing = false end
  return s
end

---------------------------------------------------------------- page
local page, widgets, profChecks, ignText = nil, {}, {}, nil

local function Build(p)
  -- scrollable page so the content never spills past the window at any size
  local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 0, 0); sf:SetPoint("BOTTOMRIGHT", -24, 0)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 540)  -- tall enough to hold both columns; scroll reveals the rest
  sf:SetScrollChild(child)
  sf:HookScript("OnSizeChanged", function(self, w) child:SetWidth(w) end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, d)
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - d * 30)))
  end)
  p = child; page = child  -- everything below anchors to the scroll child
  local st = function() return ns.db.settings end
  local LX, RX = 4, 400

  -- window
  Header(p, L["Window"], LX, -2)
  -- language: cycles auto -> each loaded translation. "auto" follows the game client.
  local langBtn = UI.Button(p, "", 150, 18, function()
    local order = { "auto" }
    for loc in pairs(ns.locales or {}) do order[#order + 1] = loc end
    table.sort(order, function(a, b) return a == "auto" or (b ~= "auto" and a < b) end)
    local cur = st().language or "auto"
    local idx = 1
    for i, loc in ipairs(order) do if loc == cur then idx = i break end end
    st().language = order[(idx % #order) + 1]
    ns.ApplyLocale()
    page.SyncLang()
    -- static labels (tabs, headers) are drawn once, so reload to retranslate everything
    if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end
  end)
  langBtn:SetPoint("TOPLEFT", 150, -2)
  page.SyncLang = function()
    local cur = st().language or "auto"
    local name = cur == "auto" and (L["Language"] .. ": auto") or (L["Language"] .. ": " .. (ns.localeNames[cur] or cur))
    langBtn.text:SetText(name)
  end
  page.SyncLang()
  widgets[#widgets + 1] = Slider(p, L["Size (scale)"], LX, -28, 0.8, 2.0, 0.05,
    function() return st().scale or 1.4 end, function(v) st().scale = v; UI.ApplyLook() end,
    function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)
  widgets[#widgets + 1] = Slider(p, L["Background"], LX, -70, 0.3, 1.0, 0.05,
    function() return st().opacity or 0.82 end, function(v) st().opacity = v; UI.ApplyLook() end,
    function(v) return ("%d%% solid"):format(math.floor(v * 100 + 0.5)) end, true)
  widgets[#widgets + 1] = Check(p, L["Open together with the Auction House"], LX, -108,
    function() return st().openWithAH end, function(v) st().openWithAH = v end)
  widgets[#widgets + 1] = Check(p, L["Show messages in chat (otherwise only in this window)"], LX, -128,
    function() return st().chat end, function(v) st().chat = v end)
  widgets[#widgets + 1] = Slider(p, L["Tables refresh every"], LX, -150, 5, 300, 5,
    function() return st().refreshSec or 60 end, function(v) st().refreshSec = v end,
    function(v) return v .. "s" end, true)

  -- alerts
  Header(p, L["Alerts"], LX, -196)
  widgets[#widgets + 1] = Slider(p, L["Warn about drops worth at least"], LX, -222, 0, 500, 5,
    function() return (st().warnAt or 3000) / 100 end, function(v) st().warnAt = v * 100 end,
    function(v) return v == 0 and "off" or (v .. "s") end, true)
  widgets[#widgets + 1] = Slider(p, L["Deal = listed at or below"], LX, -264, 50, 95, 5,
    function() return math.floor((st().dealRatio or 0.75) * 100 + 0.5) end,
    function(v) st().dealRatio = v / 100; ns.DEAL_RATIO = v / 100 end,
    function(v) return v .. L["% of usual price"] end, true)
  widgets[#widgets + 1] = Check(p, L["Play a sound when a scan finds deals"], LX, -302,
    function() return st().dealSound ~= false end, function(v) st().dealSound = v end)

  -- ignore list
  Header(p, L["Ignore list"], LX, -332)
  ignText = UI.Text(p); ignText:SetPoint("TOPLEFT", LX, -354)
  -- shift-click an item (from bags or the AH) into this box to ignore it
  local addBox = CreateFrame("EditBox", nil, p, "BackdropTemplate"); UI.Skin(addBox, 0.5)
  addBox:SetPoint("TOPLEFT", LX, -372); addBox:SetSize(220, 20)
  addBox:SetFontObject("GameFontHighlightSmall"); addBox:SetTextInsets(6, 6, 0, 0); addBox:SetAutoFocus(false)
  addBox.ph = UI.Text(addBox, "GameFontDisableSmall"); addBox.ph:SetPoint("LEFT", 6, 0)
  addBox.ph:SetText(L["Shift-click an item here to ignore it"])
  addBox:SetScript("OnEditFocusGained", function(self) self.ph:Hide() end)
  addBox:SetScript("OnEditFocusLost", function(self) self.ph:SetShown(self:GetText() == "") end)
  addBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  addBox:SetScript("OnTextChanged", function(self)
    local id = tonumber((self:GetText() or ""):match("item:(%d+)"))
    if id then
      if not ns.IsIgnored(id) then ns.ToggleIgnore(id) end
      self:SetText(""); self:ClearFocus()
    end
  end)
  local show = UI.Button(p, L["Show ignored"], 100, 20, function()
    ns.db.settings.showIgnored = next(ns.db.ignore) ~= nil -- only if something is actually ignored
    UI.ShowTabByName("Advisor")
  end)
  show:SetPoint("TOPLEFT", LX, -398)
  local clear = UI.Button(p, L["Clear all"], 80, 20, function() wipe(ns.db.ignore); ns.Fire("PricesUpdated", "ignore") end)
  clear:SetPoint("LEFT", show, "RIGHT", 6, 0)
  local hint = UI.Text(p, "GameFontDisableSmall"); hint:SetPoint("TOPLEFT", LX, -424)
  hint:SetText(L["Or right-click any item in Advisor, Deals or Crafting."])

  -- professions
  Header(p, L["Professions (Crafting, Advisor, profession window)"], RX, -2)
  p.profAnchorY = -26

  -- item categories
  Header(p, L["Item types shown in the Advisor"], RX, -190)
  for i, c in ipairs(CLASSES) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    widgets[#widgets + 1] = Check(p, L[c[2]], RX + col * 170, -214 - row * 20,
      function() return not (st().classOff and st().classOff[c[1]]) end,
      function(v) st().classOff = st().classOff or {}; st().classOff[c[1]] = (not v) or nil; ns.Fire("PricesUpdated", "settings") end)
  end

  -- tracking & tools
  Header(p, L["Tracking"], RX, -330)
  widgets[#widgets + 1] = Check(p, L["Auto-track items you search on the Auction House"], RX, -354,
    function() return st().autotrack ~= false end, function(v) st().autotrack = v end)
  widgets[#widgets + 1] = Check(p, L["Show the session tracker (mining / herbs / skinning / fishing)"], RX, -374,
    function() return ns.SessionIsShown and ns.SessionIsShown() end, function(v) if ns.ShowSession then ns.ShowSession(v) end end)
  widgets[#widgets + 1] = Check(p, L["Show the 'Worth Making' panel at profession windows"], RX, -394,
    function() return not ns.db.bestPanelOff end, function(v) if ns.ShowBestPanel then ns.ShowBestPanel(v) end end)
  widgets[#widgets + 1] = Check(p, L["Auto-scan whenever the cooldown is up (Auction House open)"], RX, -414,
    function() return st().autoScan == true end, function(v) st().autoScan = v end)
  local scan = UI.Button(p, L["Full Scan"], 100, 20, function() ns.FullScan() end)
  scan:SetPoint("TOPLEFT", RX, -440)
  -- no API can pick a layer; relogging is the only thing an addon can do to try for a new one
  local relog = UI.Button(p, L["Relog (try new layer)"], 150, 20, function() StaticPopup_Show("CORPOGREED_RELOG") end)
  relog:SetPoint("TOPLEFT", RX, -464)
  local rhint = UI.Text(p, "GameFontDisableSmall"); rhint:SetPoint("TOPLEFT", RX, -488); rhint:SetWidth(330); rhint:SetJustifyH("LEFT")
  rhint:SetText(L["Logs you to character select; log back in to maybe land on a different layer. Not guaranteed."])
end

StaticPopupDialogs["CORPOGREED_RELOG"] = {
  text = L["Log out to character select to try for a new layer?"],
  button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function() if not InCombatLockdown() then Logout() end end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Refresh()
  if not page then return end
  for _, w in ipairs(widgets) do w:Sync() end
  local n = 0
  for _ in pairs(ns.db.ignore) do n = n + 1 end
  ignText:SetText(n .. L[" item"] .. (n == 1 and "" or "s") .. L[" ignored"])
  -- one checkbox per profession we've seen
  local profs = {}
  for prof in pairs(ns.db.recipes) do
    if type(prof) == "string" and prof:gsub("%s", "") ~= "" then profs[#profs + 1] = prof end
  end
  table.sort(profs)
  for i, prof in ipairs(profs) do
    local cb = profChecks[i]
    if not cb then
      cb = Check(page, prof, 400, page.profAnchorY - (i - 1) * 20, function() return false end, function() end)
      profChecks[i] = cb
    end
    cb.label:SetText(prof)
    cb:SetScript("OnClick", function(self)
      local s = ns.db.settings
      s.profOff = s.profOff or {}
      s.profOff[prof] = (not self:GetChecked()) or nil
      ns.Fire("RecipesUpdated")
    end)
    cb:SetChecked(ns.ProfEnabled(prof))
    cb:Show()
  end
  for i = #profs + 1, #profChecks do profChecks[i]:Hide() end
end

UI.AddTab("Settings", 95, Build, Refresh)

ns.On("Loaded", function()
  local s = ns.db.settings
  -- everything was laid out right but too small: bump to 140% once (the slider still goes 80-180%)
  if not s.scaleBumped then s.scale = math.max(s.scale or 0, 1.4); s.scaleBumped = true end
  ns.DEAL_RATIO = s.dealRatio or 0.75
end)
