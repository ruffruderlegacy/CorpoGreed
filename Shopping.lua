-- CorpoGreed shopping list: "I want to craft 5 of X" -> what you still need to buy and what it costs.
local ADDON, ns = ...
local L = ns.L
local UI = ns.UI

function ns.AddToShopping(prof, out, crafts)
  local rec = ns.db.recipes[prof] and ns.db.recipes[prof][out]
  if not rec or not crafts or crafts <= 0 then return end
  for rid, n in pairs(rec.reagents) do ns.db.shop[rid] = (ns.db.shop[rid] or 0) + n * crafts end
  ns.Print((L["added reagents for %dx %s to your shopping list."]):format(math.floor(crafts), ns.ColoredName(out)))
  ns.Fire("InventoryUpdated")
end

StaticPopupDialogs["RUFFLEDGER_SHOP"] = {
  text = L["How many %s do you want to craft?"],
  button1 = ADD or L["Add"], button2 = CANCEL or L["Cancel"],
  hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnShow = function(self) local eb = self.editBox or self.EditBox; eb:SetNumeric(true); eb:SetText("1"); eb:HighlightText(); eb:SetFocus() end,
  OnAccept = function(self, data)
    local eb = self.editBox or self.EditBox
    ns.AddToShopping(data.prof, data.out, tonumber(eb:GetText()))
  end,
  EditBoxOnEnterPressed = function(self)
    local parent = self:GetParent()
    ns.AddToShopping(parent.data.prof, parent.data.out, tonumber(self:GetText()))
    parent:Hide()
  end,
}

function ns.AskShopping(prof, out)
  StaticPopup_Show("RUFFLEDGER_SHOP", ns.ItemInfo(out), nil, { prof = prof, out = out })
end

local function Rows()
  local rows = {}
  for id, need in pairs(ns.db.shop) do
    local have = ns.Owned(id) -- this character, bags + bank
    local buy = math.max(0, need - have)
    local each, src = ns.BuyCost(id)
    rows[#rows + 1] = { id = id, name = ns.ItemInfo(id), need = need, have = have, buy = buy, each = each, src = src,
                        cost = each and each * buy or nil }
  end
  return rows
end

local tbl, totalText
local COLS = {
  { key = "name", label = L["Reagent"], w = 200, align = "LEFT" },
  { key = "need", label = L["Need"], w = 55 },
  { key = "have", label = L["Have"], w = 55 },
  { key = "buy", label = L["To buy"], w = 55 },
  { key = "each", label = L["Each"], w = 90 },
  { key = "cost", label = L["Cost"], w = 100 },
}

local function Build(page)
  totalText = UI.Text(page, "GameFontNormal"); totalText:SetPoint("TOPLEFT", 2, -4)
  local nextBtn = UI.Button(page, L["Search next"], 90, 20, function()
    for _, r in ipairs(Rows()) do
      if r.buy > 0 and r.src ~= "vendor" then UI.SearchAH(r.name) return end
    end
    ns.Warn(L["Nothing left to buy on the AH."])
  end)
  nextBtn:SetPoint("TOPRIGHT", -96, 0)
  local clear = UI.Button(page, L["Clear list"], 90, 20, function() wipe(ns.db.shop); UI.Refresh() end)
  clear:SetPoint("TOPRIGHT", 0, 0)
  tbl = UI.Table(page, 26, COLS, function(r)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.item.id)
      GameTooltip:AddLine(L["Click: search AH, Right-click: remove"], 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then ns.db.shop[self.item.id] = nil; UI.Refresh() return end
      UI.SearchAH(self.item.name)
    end)
  end)
  tbl.sort = { key = "cost", desc = true }
  tbl.onSort = function() UI.Refresh() end
end

local function Refresh()
  if not tbl then return end
  local rows, total, missing = Rows(), 0, false
  for _, r in ipairs(rows) do
    if r.cost then total = total + r.cost elseif r.buy > 0 then missing = true end
  end
  totalText:SetText(#rows == 0 and L["Empty - right-click a recipe in the Crafting tab to add it."]
    or (L["Still to buy: %s%s"]):format(ns.Money(total), missing and L[" |cff808080(+ items with no price)|r"] or ""))
  tbl:Set(rows, function(r, row)
    UI.Dot(r.dot, row.buy == 0 and ns.ADV_COLORS.GREEN or ns.ADV_COLORS.YELLOW)
    r.icon:SetTexture(ns.Icon(row.id))
    r.cells[1]:SetText(ns.ColoredName(row.id))
    r.cells[2]:SetText(row.need)
    r.cells[3]:SetText(row.have)
    r.cells[4]:SetText(row.buy == 0 and L["|cff6fcf8fdone|r"] or row.buy)
    r.cells[5]:SetText(row.each and (ns.Money(row.each) .. (row.src == "vendor" and " |cff808080V|r" or "")) or "|cff808080?|r")
    r.cells[6]:SetText(row.cost and ns.Money(row.cost) or "")
  end)
end

-- Cart tab removed (scrapped by request). Shopping helpers kept but no tab is registered.
local _ = Build and Refresh
