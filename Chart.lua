-- CorpoGreed price chart: line or candles, moving average, Bollinger bands, Fibonacci levels, listed-quantity bars,
-- plus keyboard / mouse-wheel navigation through the item list.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI
local ACC = { 0.22, 0.53, 0.9 }
local RANGES = { 86400, 7 * 86400, nil } -- same order as the 24h / 7d / All buttons
local FIBS = { 0, 0.236, 0.382, 0.5, 0.618, 0.786, 1 }

local function CS()
  local s = ns.db.settings
  s.chart = s.chart or { ma = true, vol = true }
  return s.chart
end

---------------------------------------------------------------- drawing pools
local function Reset(c)
  for _, pool in pairs(c.pool) do
    for i = 1, #pool do pool[i]:Hide() end
    pool.n = 0
  end
end

local function Get(c, kind)
  local p = c.pool[kind]; p.n = p.n + 1
  local o = p[p.n]
  if not o then
    if kind == "lines" then o = c:CreateLine(nil, "ARTWORK")
    elseif kind == "bars" then o = c:CreateTexture(nil, "BORDER")
    elseif kind == "boxes" then o = c:CreateTexture(nil, "ARTWORK", nil, 2)
    elseif kind == "dots" then o = c:CreateTexture(nil, "OVERLAY")
    else o = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end
    p[p.n] = o
  end
  o:Show()
  return o
end

local function Line(c, x1, y1, x2, y2, r, g, b, a, th)
  local l = Get(c, "lines")
  l:SetThickness(th or 2); l:SetColorTexture(r, g, b, a or 1)
  l:SetStartPoint("BOTTOMLEFT", c, x1, y1); l:SetEndPoint("BOTTOMLEFT", c, x2, y2)
  return l
end

local function Box(c, kind, x, y, w, h, r, g, b, a)
  local t = Get(c, kind)
  t:SetColorTexture(r, g, b, a or 1)
  t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", x, y); t:SetSize(math.max(1, w), math.max(1, h))
  return t
end

local function Label(c, text, x, y, anchor, r, g, b)
  local fs = Get(c, "labels")
  fs:ClearAllPoints(); fs:SetPoint(anchor or "LEFT", c, "BOTTOMLEFT", x, y)
  fs:SetText(text); fs:SetTextColor(r or 0.7, g or 0.7, b or 0.7)
  return fs
end

---------------------------------------------------------------- indicators
-- moving average + standard deviation over a time window, one value per point
local function Rolling(pts, window)
  local ma, sd = {}, {}
  local j, sum, sum2 = 1, 0, 0
  for i, p in ipairs(pts) do
    sum, sum2 = sum + p[2], sum2 + p[2] * p[2]
    while pts[j][1] < p[1] - window do sum, sum2 = sum - pts[j][2], sum2 - pts[j][2] * pts[j][2]; j = j + 1 end
    local n = i - j + 1
    ma[i] = sum / n
    sd[i] = math.sqrt(math.max(0, sum2 / n - ma[i] * ma[i]))
  end
  return ma, sd
end

-- OHLC candles: one per bucket (2h on the 24h view, otherwise a day)
local function Candles(pts, size)
  local out, cur = {}, nil
  for _, p in ipairs(pts) do
    local k = math.floor(p[1] / size)
    if not cur or cur.k ~= k then
      cur = { k = k, t = k * size + size / 2, o = p[2], h = p[2], l = p[2], c = p[2] }
      out[#out + 1] = cur
    end
    cur.h, cur.l, cur.c = math.max(cur.h, p[2]), math.min(cur.l, p[2]), p[2]
  end
  return out
end

---------------------------------------------------------------- main draw
function ns.DrawChart()
  local c = UI.chart
  if not c then return end
  if type(c.pool) ~= "table" then c.pool = { lines = {}, bars = {}, boxes = {}, dots = {}, labels = {} } end
  Reset(c)
  for _, g in ipairs(c.grid or {}) do g[1]:Hide() end
  c.pts = nil
  local cs = CS()
  local id = UI.selected
  local rangeIdx = ns.db.settings.range or 3
  local range = RANGES[rangeIdx]
  local st = id and ns.Stats(id, range and time() - range)
  if id then UI.header:SetText(ns.ColoredName(id) .. "   " .. ns.Money((ns.Price(id)))) else UI.header:SetText("") end
  if not st then
    c.empty:SetText(id and L["No history in this range yet."] or L["Pick an item on the left."]); c.empty:Show()
    c.hiTxt:SetText(""); c.loTxt:SetText(""); c.t0:SetText(""); c.t1:SetText(""); UI.sub:SetText("")
    for _, b in ipairs(UI.blocks) do b.text:SetText("") end
    return
  end
  c.empty:Hide()
  local pts = st.pts
  local W, H = c:GetWidth() - 8, c:GetHeight() - 8
  if W <= 0 or H <= 0 then return end

  local hasQty = false
  for _, p in ipairs(pts) do if p[3] then hasQty = true break end end
  local volH = (cs.vol and hasQty) and math.floor(H * 0.18) or 0
  local base = 4 + volH + (volH > 0 and 6 or 0)
  local PH = H - (base - 4)

  local window = range == 86400 and 4 * 3600 or 24 * 3600
  local ma, sd = Rolling(pts, window)
  local lo, hi = st.lo, st.hi
  if cs.bands then
    for i = 1, #pts do lo, hi = math.min(lo, ma[i] - 2 * sd[i]), math.max(hi, ma[i] + 2 * sd[i]) end
  end
  local pad = (hi - lo) * 0.12; if pad == 0 then pad = math.max(hi * 0.05, 1) end
  lo, hi = math.max(0, lo - pad), hi + pad
  local t0, t1 = pts[1][1], pts[#pts][1]
  if cs.candles and t1 > t0 then
    local size = range == 86400 and 7200 or 86400
    t0, t1 = math.floor(t0 / size) * size, (math.floor(t1 / size) + 1) * size
  end
  local function X(t) if t1 == t0 then return 4 + W / 2 end return 4 + (t - t0) / (t1 - t0) * W end
  local function Y(v) return base + (v - lo) / (hi - lo) * PH end
  c.X, c.pts, c.ma = X, pts, ma

  -- grid + price axis
  for k, g in ipairs(c.grid or {}) do
    local v = lo + (hi - lo) * g[2]
    g[1]:ClearAllPoints(); g[1]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, Y(v)); g[1]:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", W + 8, Y(v)); g[1]:Show()
    Label(c, ns.Money(v), -4, Y(v), "RIGHT")
  end
  c.hiTxt:SetText(""); c.loTxt:SetText("") -- the grid labels show the price axis now

  -- listed quantity bars
  if volH > 0 then
    local maxQ = 1
    for _, p in ipairs(pts) do if p[3] and p[3] > maxQ then maxQ = p[3] end end
    local bw = math.max(2, math.min(10, W / #pts * 0.6))
    for _, p in ipairs(pts) do
      if p[3] then Box(c, "bars", X(p[1]) - bw / 2, 4, bw, p[3] / maxQ * volH, 0.55, 0.6, 0.7, 0.35) end
    end
    Label(c, L["listed (max "] .. maxQ .. ")", 6, 4 + volH - 6, "LEFT")
  end

  -- Fibonacci retracement between the range high and low
  if cs.fib and st.hi > st.lo then
    for _, f in ipairs(FIBS) do
      local v = st.hi - (st.hi - st.lo) * f
      Line(c, 4, Y(v), W + 4, Y(v), 1, 0.82, 0, f == 0.618 and 0.55 or 0.28, 1)
      Label(c, ("%.1f%%  %s"):format(f * 100, ns.Money(v, true)), W, Y(v) + 6, "RIGHT", 1, 0.82, 0)
    end
  end

  -- Bollinger bands
  if cs.bands and #pts > 2 then
    for i = 2, #pts do
      local xa, xb = X(pts[i - 1][1]), X(pts[i][1])
      Line(c, xa, Y(ma[i - 1] + 2 * sd[i - 1]), xb, Y(ma[i] + 2 * sd[i]), 0.75, 0.5, 1, 0.45, 1)
      Line(c, xa, Y(ma[i - 1] - 2 * sd[i - 1]), xb, Y(ma[i] - 2 * sd[i]), 0.75, 0.5, 1, 0.45, 1)
    end
  end

  -- price: candles or line
  if cs.candles then
    local size = range == 86400 and 7200 or 86400
    local cand = Candles(pts, size)
    local cw = math.max(3, math.min(16, W / math.max(1, (t1 - t0) / size) * 0.6))
    for _, k in ipairs(cand) do
      local up = k.c >= k.o
      local r, g, b = up and 0.44 or 1, up and 0.81 or 0.44, up and 0.56 or 0.38
      local x = X(k.t)
      Line(c, x, Y(k.l), x, Y(k.h), r, g, b, 0.9, 1)
      local y1, y2 = Y(math.min(k.o, k.c)), Y(math.max(k.o, k.c))
      Box(c, "boxes", x - cw / 2, y1, cw, math.max(1, y2 - y1), r, g, b, 1)
    end
    c.candles, c.candleSize = cand, size
  else
    c.candles = nil
    for i = 2, #pts do
      Line(c, X(pts[i - 1][1]), Y(pts[i - 1][2]), X(pts[i][1]), Y(pts[i][2]), ACC[1], ACC[2], ACC[3], 1, 2)
    end
    if #pts <= 80 then
      for _, p in ipairs(pts) do
        local d = Get(c, "dots"); d:SetColorTexture(ACC[1], ACC[2], ACC[3], 1); d:SetSize(5, 5)
        d:ClearAllPoints(); d:SetPoint("CENTER", c, "BOTTOMLEFT", X(p[1]), Y(p[2]))
      end
    end
  end

  -- moving average
  if cs.ma and #pts > 2 then
    for i = 2, #pts do
      Line(c, X(pts[i - 1][1]), Y(ma[i - 1]), X(pts[i][1]), Y(ma[i]), 1, 0.6, 0.2, 0.9, 1.5)
    end
  end

  c.t0:SetText(date("%a %d %H:%M", pts[1][1])); c.t1:SetText(#pts > 1 and date("%a %d %H:%M", pts[#pts][1]) or "")
  local chg = ""
  if #pts > 1 and st.first > 0 then
    local d = (st.now - st.first) / st.first * 100
    chg = (d > 0 and "|cff6fcf8f+%d%%|r" or d < 0 and "|cffff6f61%d%%|r" or "%d%%"):format(math.floor(d + 0.5)) .. L[" in range   "]
  end
  local _, q = ns.Price(id)
  UI.sub:SetText(chg .. (L["low %s   avg %s   high %s%s"]):format(ns.Money(st.lo), ns.Money(st.avg), ns.Money(st.hi),
    q and ("  -  " .. q .. L[" listed"]) or ""))
  for i, b in ipairs(UI.blocks) do
    local a = st.blocks[i]
    local tag = st.best == i and L[" |cff6fcf8fcheapest|r"] or st.worst == i and L[" |cffff6f61priciest|r"] or ""
    b.text:SetText(ns.BLOCKS[i][1] .. tag .. "\n" .. (a and ns.Money(a) or "-"))
  end
end

function ns.ChartHover(c)
  local x = select(1, GetCursorPosition()) / c:GetEffectiveScale() - c:GetLeft()
  local best, bi = math.huge, 1
  for i, p in ipairs(c.pts) do
    local d = math.abs(c.X(p[1]) - x); if d < best then best, bi = d, i end
  end
  if c.hoverIdx == bi then return end
  c.hoverIdx = bi
  local p = c.pts[bi]
  c.cross:ClearAllPoints(); c.cross:SetPoint("BOTTOM", c, "BOTTOMLEFT", c.X(p[1]), 0); c.cross:SetHeight(c:GetHeight()); c.cross:Show()
  GameTooltip:SetOwner(c, "ANCHOR_CURSOR")
  GameTooltip:AddLine(ns.Money(p[2]), 1, 1, 1)
  GameTooltip:AddLine(date("%a %d %b  %H:%M", p[1]), 0.7, 0.7, 0.7)
  if p[3] then GameTooltip:AddLine(p[3] .. L[" listed"], 0.7, 0.7, 0.7) end
  if CS().ma and c.ma and c.ma[bi] then GameTooltip:AddDoubleLine(L["Moving avg"], ns.Money(c.ma[bi]), 1, 0.6, 0.2, 1, 1, 1) end
  if c.candles then
    local k = math.floor(p[1] / c.candleSize)
    for _, cd in ipairs(c.candles) do
      if cd.k == k then
        GameTooltip:AddDoubleLine(L["Open / Close"], ns.Money(cd.o, true) .. " / " .. ns.Money(cd.c, true), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["High / Low"], ns.Money(cd.h, true) .. " / " .. ns.Money(cd.l, true), 0.8, 0.8, 0.8, 1, 1, 1)
      end
    end
  end
  GameTooltip:Show()
end

---------------------------------------------------------------- navigation
function UI.SelectRelative(d)
  local ids = UI.priceIds
  if not ids or #ids == 0 then return end
  local idx = 1
  for i, id in ipairs(ids) do if id == UI.selected then idx = i break end end
  idx = math.max(1, math.min(#ids, idx + d))
  UI.selected = ids[idx]
  UI.RefreshPrices()
  local sf, rowH = UI.priceList.sf, 22
  local top, h, y = sf:GetVerticalScroll(), sf:GetHeight(), (idx - 1) * rowH
  if y < top then sf:SetVerticalScroll(y) elseif y + rowH > top + h then sf:SetVerticalScroll(y + rowH - h) end
end

-- chart toggles + prev/next buttons, called while the Prices page is built
function ns.BuildChartControls(right)
  local toggles = { { "candles", L["Candles"] }, { "ma", "MA" }, { "bands", L["Bands"] }, { "fib", L["Fib"] }, { "vol", L["Vol"] } }
  UI.chartToggles = {}
  local prev
  for i = #toggles, 1, -1 do
    local key, label = toggles[i][1], toggles[i][2]
    local b = UI.Button(right, label, key == "candles" and 60 or 44, 18, function() CS()[key] = not CS()[key]; UI.RefreshPrices() end)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -3, 0) else b:SetPoint("TOPRIGHT", 0, -22) end
    b.key = key
    UI.chartToggles[#UI.chartToggles + 1] = b
    prev = b
  end
  local nextB = UI.Button(right, ">", 22, 18, function() UI.SelectRelative(1) end)
  nextB:SetPoint("RIGHT", UI.rangeBtns[1], "LEFT", -8, 0)
  local prevB = UI.Button(right, "<", 22, 18, function() UI.SelectRelative(-1) end)
  prevB:SetPoint("RIGHT", nextB, "LEFT", -3, 0)

  UI.chart:EnableMouseWheel(true)
  UI.chart:SetScript("OnMouseWheel", function(_, d) UI.SelectRelative(-d) end)

  UI.search:SetScript("OnArrowPressed", function(_, key)
    if key == "UP" then UI.SelectRelative(-1) elseif key == "DOWN" then UI.SelectRelative(1) end
  end)
  UI.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
end

function ns.SyncChartToggles()
  for _, b in ipairs(UI.chartToggles or {}) do b:SetActive(CS()[b.key] and true or false) end
end

-- Up / Down arrows switch items while the mouse is over the window (arrows still move you otherwise)
ns.On("Loaded", function()
  local f = UI.frame
  f:HookScript("OnUpdate", function(self)
    local over = self:IsMouseOver() and not InCombatLockdown()
    if over ~= self.kb then self.kb = over; self:EnableKeyboard(over and true or false) end
  end)
  f:SetScript("OnKeyDown", function(self, key)
    if (key == "UP" or key == "DOWN") and UI.TabIs("Prices") then
      pcall(self.SetPropagateKeyboardInput, self, false)
      UI.SelectRelative(key == "UP" and -1 or 1)
    else
      pcall(self.SetPropagateKeyboardInput, self, true)
    end
  end)
  f:HookScript("OnHide", function(self) self.kb = false; self:EnableKeyboard(false) end)
end)
