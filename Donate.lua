-- CorpoGreed "About" page: a short description, a charity message, and a list of copyable links.
-- WoW addons cannot open a browser, so each link is shown in a box the viewer selects and copies (Ctrl+C).
-- Links are settings, so a streamer can point them anywhere: /cg donate <url> sets the charity link.
local ADDON, ns = ...
local L = ns.L

-- link rows: a stable key, a label, and a default URL ("" hides the row until set)
ns.LINKS = {
  { key = "donate",  label = "Charity donation", default = "https://example.org/charity" },
  { key = "stream",  label = "Streamer channel", default = "" },
  { key = "discord", label = "Discord",          default = "" },
}

function ns.LinkURL(key, default)
  local u = ns.db and ns.db.settings and ns.db.settings.links and ns.db.settings.links[key]
  if u and u ~= "" then return u end
  return default
end

function ns.SetLink(key, url)
  ns.db.settings.links = ns.db.settings.links or {}
  ns.db.settings.links[key] = url
end

function ns.DonateURL() return ns.LinkURL("donate", ns.LINKS[1].default) end

local function Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return (get and get(ADDON, "Version")) or "?"
end

---------------------------------------------------------------- About tab
local page, rows

local function Build(p)
  page = p
  local title = ns.UI.Text(p, "GameFontNormalHuge"); title:SetPoint("TOPLEFT", 4, -6)
  title:SetText("|cff3987e5Corpo|rGreed")
  local ver = ns.UI.Text(p, "GameFontDisable"); ver:SetPoint("LEFT", title, "RIGHT", 8, -1)
  ver:SetText("v" .. Version())

  local desc = ns.UI.Text(p); desc:SetPoint("TOPLEFT", 4, -38); desc:SetPoint("RIGHT", -8, 0); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
  desc:SetText(L["Your own Auction House toolkit: price history and charts, a deals finder, a sell / smelt / craft advisor, best crafts, a shopping list, and full bookkeeping."])

  local heart = p:CreateTexture(nil, "ARTWORK"); heart:SetSize(18, 18); heart:SetPoint("TOPLEFT", 4, -80)
  heart:SetTexture("Interface\\COMMON\\ReputationStar"); heart:SetTexCoord(0, 0.5, 0, 0.5); heart:SetVertexColor(1, 0.5, 0.6)
  local charity = ns.UI.Text(p); charity:SetPoint("TOPLEFT", heart, "TOPRIGHT", 6, 0); charity:SetPoint("RIGHT", -8, 0)
  charity:SetJustifyH("LEFT"); charity:SetWordWrap(true)
  charity:SetText(L["CorpoGreed is free. If it made you gold, please send a little to charity instead. Thank you!"])

  local lh = ns.UI.Text(p, "GameFontNormal"); lh:SetPoint("TOPLEFT", 4, -130); lh:SetText(L["Links"])
  local hint = ns.UI.Text(p, "GameFontDisableSmall"); hint:SetPoint("LEFT", lh, "RIGHT", 8, 0)
  hint:SetText(L["click a link, then Ctrl+C to copy it"])

  rows = {}
  for i, link in ipairs(ns.LINKS) do
    local r = CreateFrame("Frame", nil, p)
    r:SetPoint("TOPLEFT", 4, -152 - (i - 1) * 32); r:SetPoint("RIGHT", -8, 0); r:SetHeight(26)
    r.label = ns.UI.Text(r); r.label:SetPoint("LEFT", 0, 0); r.label:SetWidth(150); r.label:SetJustifyH("LEFT")
    local box = CreateFrame("EditBox", nil, r, "BackdropTemplate"); ns.UI.Skin(box, 0.5)
    box:SetPoint("LEFT", 156, 0); box:SetPoint("RIGHT", 0, 0); box:SetHeight(24)
    box:SetFontObject("GameFontHighlight"); box:SetTextInsets(8, 8, 0, 0); box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.url or ""); self:HighlightText() end end)
    r.box, r.link = box, link
    rows[i] = r
  end
end

local function Refresh()
  if not page then return end
  for _, r in ipairs(rows) do
    r.label:SetText(L[r.link.label])
    local url = ns.LinkURL(r.link.key, r.link.default)
    r.box.url = url
    r.box:SetText(url or "")
    r:SetShown(url and url ~= "")
  end
end

-- Single "Donate" tab holds the about info + charity links (the old separate gold top-bar
-- Donate button did the same thing, so it's gone -- no more duplicate).
ns.UI.AddTab("Donate", 99, Build, Refresh)

-- open the Donate tab (used by /cg donate)
function ns.ShowDonate() ns.UI.ShowTabByName("Donate") end

-- tint the Donate tab gold so it still stands out for the charity drive
ns.On("Loaded", function()
  for i, def in ipairs(ns.UI.tabDefs) do
    if def.name == "Donate" and ns.UI.tabs and ns.UI.tabs[i] then
      ns.UI.tabs[i].text:SetTextColor(1, 0.82, 0)
      ns.UI.donateTab = ns.UI.tabs[i]
    end
  end
end)
