-- CorpoGreed selling helper, tooltips and slash commands.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

---------------------------------------------------------------- sell helper bar (under the AH window)
local bar, sellItem, sellFrame

local function CurrentSellFrame()
  if not AuctionHouseFrame then return end
  for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
    local f = AuctionHouseFrame[key]
    if f and f:IsShown() then return f end
  end
end

local function SetSellPrice(copper)
  local f = CurrentSellFrame()
  if not f or not copper or copper <= 0 then return end
  local input = f.PriceInput or (f.GetPriceInput and f:GetPriceInput())
  if input and input.SetAmount then
    input:SetAmount(math.floor(copper))
    pcall(function() if f.UpdatePostState then f:UpdatePostState() end end)
    pcall(function() if f.UpdateTotalPrice then f:UpdateTotalPrice() end end)
  else
    ns.Warn(L["Couldn't find the price box - set it by hand: "] .. ns.Money(copper))
  end
end

local function UpdateBar()
  if not bar then return end
  if not sellItem then bar:Hide(); return end
  local p, q = ns.Price(sellItem)
  local avg = ns.DailyAvg(sellItem, 7)
  local st = ns.Stats(sellItem, time() - 7 * 86400)
  local parts = { ns.ColoredName(sellItem) }
  parts[#parts + 1] = L["lowest "] .. ns.Money(p) .. (q and (" (" .. q .. ")") or "")
  if avg then
    local warn = p and p < avg * 0.85 and L[" |cffff6f61(cheap now - maybe hold)|r"] or p and p > avg * 1.15 and L[" |cff6fcf8f(good time to sell)|r"] or ""
    parts[#parts + 1] = L["7d avg "] .. ns.Money(avg) .. warn
  end
  if st and st.worst then parts[#parts + 1] = L["sells best: "] .. ns.BLOCKS[st.worst][1] end
  bar.text:SetText(table.concat(parts, "  -  "))
  bar.under:SetEnabled(p ~= nil)
  bar.avg:SetEnabled(avg ~= nil)
  bar.lowest, bar.avgPrice = p, avg
  bar:Show()
end

local function BuildBar()
  bar = CreateFrame("Frame", "CorpoGreedSellBar", AuctionHouseFrame, "BackdropTemplate")
  UI.Skin(bar, 0.85)
  bar:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 0, -2)
  bar:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, -2)
  bar:SetHeight(28)
  UI.sellBar = bar
  UI.ApplyLook()
  bar.under = UI.Button(bar, L["Undercut 1c"], 90, 20, function() if bar.lowest then SetSellPrice(bar.lowest - 1) end end)
  bar.under:SetPoint("RIGHT", -4, 0)
  bar.avg = UI.Button(bar, L["7d avg"], 60, 20, function() if bar.avgPrice then SetSellPrice(bar.avgPrice) end end)
  bar.avg:SetPoint("RIGHT", bar.under, "LEFT", -4, 0)
  bar.text = UI.Text(bar); bar.text:SetPoint("LEFT", 8, 0); bar.text:SetPoint("RIGHT", bar.avg, "LEFT", -8, 0)
  bar.text:SetJustifyH("LEFT"); bar.text:SetWordWrap(false)
  bar:Hide()
end

local function OnSetItem(frame, itemLocation)
  sellFrame = frame
  sellItem = nil
  if itemLocation and itemLocation.IsValid and itemLocation:IsValid() then
    sellItem = C_Item.GetItemID(itemLocation)
  end
  if sellItem and ns.LedgerSetSellItem then ns.LedgerSetSellItem(sellItem) end
  UpdateBar()
end

local function HookAH()
  if bar or not AuctionHouseFrame then return end
  BuildBar()
  for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
    local f = AuctionHouseFrame[key]
    if type(f) == "table" and f.SetItem then hooksecurefunc(f, "SetItem", OnSetItem) end
    if type(f) == "table" then f:HookScript("OnHide", function() if sellFrame == f then sellItem = nil; UpdateBar() end end) end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, e, arg)
  if e == "AUCTION_HOUSE_SHOW" or (e == "ADDON_LOADED" and arg == "Blizzard_AuctionHouseUI") then HookAH() end
end)
ns.On("PricesUpdated", UpdateBar)

---------------------------------------------------------------- tooltips
local function Age(t)
  local age = t and (time() - t)
  if not age then return "" end
  if age < 3600 then return ("%dm"):format(math.floor(age / 60)) end
  if age < 86400 then return ("%dh"):format(math.floor(age / 3600)) end
  return ("%dd"):format(math.floor(age / 86400))
end

local function TooltipAdd(tt, id)
  if not id or not ns.db then return end
  local p, q, t = ns.Price(id)
  local avg = ns.DailyAvg(id, 7)
  if not p and not avg then return end
  -- the advisor block already lists "Sell on AH", so only show the raw price when that block isn't there
  local a = ns.Advise and ns.Advise(id)
  local advisorShown = a and #a.opts >= 2
  if p and not advisorShown then
    tt:AddDoubleLine(L["|cff3987e5CG|r AH price"] .. (q and (" (" .. q .. ")") or ""), ns.Money(p), 1, 1, 1, 1, 1, 1)
  end
  if avg then
    local trend = ""
    if p and avg > 0 then
      local d = (p - avg) / avg * 100
      if d >= 3 then trend = (L["  |cff6fcf8fup %d%%|r"]):format(math.floor(d + 0.5))
      elseif d <= -3 then trend = (L["  |cffff6f61down %d%%|r"]):format(math.floor(-d + 0.5))
      else trend = L["  |cffc0c0c0steady|r"] end
    end
    local left = L["|cff3987e5CG|r 7d avg"] .. (t and time() - t > 3600 and (L[" |cff808080(price "] .. Age(t) .. L[" old)|r"]) or "")
    tt:AddDoubleLine(left, ns.Money(avg) .. trend, 1, 1, 1, 1, 1, 1)
  end
  local st = ns.Stats(id, time() - 7 * 86400)
  if st and st.best then
    tt:AddDoubleLine(L["|cff3987e5CG|r cheapest / priciest"], ns.BLOCKS[st.best][1] .. " / " .. ns.BLOCKS[st.worst][1], 1, 1, 1, 0.8, 0.8, 0.8)
  end
end

local function HookTooltips()
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
end
ns.On("Loaded", HookTooltips)

---------------------------------------------------------------- slash
SLASH_CORPOGREED1 = "/cg"
SLASH_CORPOGREED2 = "/corpogreed"
SLASH_CORPOGREED3 = "/rl"
SlashCmdList.CORPOGREED = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local id = tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)$"))
  if cmd == "add" and id then
    ns.db.watch[id] = true; UI.selected = id; ns.Print(ns.ColoredName(id) .. L[" is now tracked."]); UI.Refresh()
  elseif cmd == "remove" and id then
    ns.db.watch[id] = nil; ns.Print(ns.ColoredName(id) .. L[" untracked."]); UI.Refresh()
  elseif cmd == "scan" then
    ns.FullScan()
  elseif (cmd == "ignore" or cmd == "unignore") and id then
    if (cmd == "ignore") ~= (ns.db.ignore[id] == true) then ns.ToggleIgnore(id) end
  elseif cmd == "donate" or cmd == "link" then
    -- /cg donate <url>  or  /cg link <donate|stream|discord> <url>
    local key, url = "donate", rest
    local maybeKey, after = rest:match("^(%S+)%s+(.+)$")
    if cmd == "link" and maybeKey then key, url = maybeKey, after end
    if url and url ~= "" and (cmd == "link" or url:match("%.")) then
      ns.SetLink(key, url); ns.Say(L["link set: "] .. key .. " = " .. url)
    else ns.ShowDonate() end
  elseif cmd == "session" then
    if ns.ToggleSession then ns.ToggleSession() end
  elseif cmd == "autotrack" then
    ns.db.settings.autotrack = not (ns.db.settings.autotrack ~= false)
    ns.Say(L["auto-track searched items: "] .. (ns.db.settings.autotrack ~= false and L["on"] or L["off"]))
  elseif cmd == "refresh" then
    local s = tonumber(rest)
    if s then ns.db.settings.refreshSec = math.max(2, s) end
    ns.Say(L["tables refresh every "] .. (ns.db.settings.refreshSec or 60) .. L[" sec (full scan updates instantly)"])
  elseif cmd == "warn" then
    local s = tonumber(rest)
    if s then ns.db.settings.warnAt = math.floor(s * 100) end
    ns.Say(L["warn about drops worth at least "] .. ns.Money(ns.db.settings.warnAt or 3000) .. L[" (/cg warn <silver> to change)"])
  elseif cmd == "chat" then
    ns.db.settings.chat = not ns.db.settings.chat
    ns.Say(L["messages in chat: "] .. (ns.db.settings.chat and "on" or L["off (shown in the CorpoGreed window)"]))
  elseif cmd == "help" then
    ns.Say(L["/cg - window, /cg scan - full scan, /cg add or remove [item], /cg chat - messages in chat on/off, /cg warn <silver> - valuable drop alert, /cg ignore or unignore [item]"])
  else
    UI.Toggle()
  end
end
