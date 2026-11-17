-- CorpoGreed translations.
-- Every piece of text in the addon goes through L["English text"]. Missing translations fall back to English,
-- so a language can be filled in bit by bit. The language follows the game client, or a manual choice in Settings
-- (needed for languages with no WoW client, like Ukrainian).
-- Translation files live in Locales\<locale>.lua (loaded right after this file) and call:
--   CorpoGreed_AddLocale("deDE", { ["English text"] = "Deutscher Text", ... })
local ADDON, ns = ...

ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.clientLocale = GetLocale and GetLocale() or "enUS"
ns.locales = {}          -- locale -> strings table, kept so the language can be switched without a reload
ns.localeNames = {}      -- locale -> display name shown in Settings

local ALIASES = { esMX = "esES", enGB = "enUS" }

-- which locale is active: a manual override from Settings, else the game client's
function ns.ActiveLocale()
  local pick = CorpoGreedDB and CorpoGreedDB.settings and CorpoGreedDB.settings.language
  if pick and pick ~= "auto" then return pick end
  return ns.clientLocale
end

-- (re)build ns.L from English + the active locale's table (+ its alias fallback)
function ns.ApplyLocale()
  for k in pairs(ns.L) do rawset(ns.L, k, nil) end
  local active = ns.ActiveLocale()
  local t = ns.locales[active] or ns.locales[ALIASES[active] or ""]
  if t then for k, v in pairs(t) do rawset(ns.L, k, v) end end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function CorpoGreed_AddLocale(locale, strings)
  ns.locales[locale] = strings
  if strings["_name"] then ns.localeNames[locale] = strings["_name"] end
  ns.ApplyLocale()
end

-- the game reports spell / profession names in the client's language, so resolve them by spell ID
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id))
end
ns.SpellName = SpellName
function ns.IsProfession(profName, key)
  local ids = { Mining = 2575, Enchanting = 7411, Herbalism = 2366, Skinning = 8613, Smelting = 2656 }
  return profName == key or (ids[key] and profName == SpellName(ids[key]))
end
-- smelting (ore -> bar) counts as mining for the "Smelt" wording and grouping
function ns.IsSmelt(profName) return ns.IsProfession(profName, "Mining") or ns.IsProfession(profName, "Smelting") end
