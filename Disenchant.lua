-- CorpoGreed disenchant value: expected AH value of the mats a green/blue weapon or armor piece breaks into.
-- Drop tables are the classic-era odds (approximate) by item level.
local ADDON, ns = ...

local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESS = { lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134, gmystic = 11135,
              lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203 }
local SHARD = { sglim = 10978, lglim = 11084, sglow = 11138, lglow = 11139, srad = 11177, lrad = 11178, sbril = 14343, lbril = 14344 }

-- { max item level, { {itemID, chance, average count}, ... } }
local GREEN = {
  { 15, { { DUST.strange, 0.8, 1.5 }, { ESS.lmagic, 0.2, 1.5 } } },
  { 20, { { DUST.strange, 0.75, 2.5 }, { ESS.gmagic, 0.2, 1.5 }, { SHARD.sglim, 0.05, 1 } } },
  { 25, { { DUST.strange, 0.75, 5 }, { ESS.lastral, 0.15, 1.5 }, { SHARD.sglim, 0.1, 1 } } },
  { 30, { { DUST.soul, 0.75, 1.5 }, { ESS.gastral, 0.2, 1.5 }, { SHARD.lglim, 0.05, 1 } } },
  { 35, { { DUST.soul, 0.75, 3.5 }, { ESS.lmystic, 0.2, 1.5 }, { SHARD.sglow, 0.05, 1 } } },
  { 40, { { DUST.vision, 0.75, 1.5 }, { ESS.gmystic, 0.2, 1.5 }, { SHARD.lglow, 0.05, 1 } } },
  { 45, { { DUST.vision, 0.75, 3.5 }, { ESS.lnether, 0.2, 1.5 }, { SHARD.srad, 0.05, 1 } } },
  { 50, { { DUST.dream, 0.75, 1.5 }, { ESS.gnether, 0.2, 1.5 }, { SHARD.lrad, 0.05, 1 } } },
  { 55, { { DUST.dream, 0.75, 3.5 }, { ESS.leternal, 0.2, 1.5 }, { SHARD.sbril, 0.05, 1 } } },
  { 65, { { DUST.illusion, 0.75, 2 }, { ESS.geternal, 0.2, 2 }, { SHARD.lbril, 0.05, 1 } } },
}
local BLUE = {
  { 25, { { SHARD.sglim, 1, 1 } } },
  { 30, { { SHARD.lglim, 1, 1 } } },
  { 35, { { SHARD.sglow, 1, 1 } } },
  { 40, { { SHARD.lglow, 1, 1 } } },
  { 45, { { SHARD.srad, 1, 1 } } },
  { 50, { { SHARD.lrad, 1, 1 } } },
  { 55, { { SHARD.sbril, 1, 1 } } },
  { 70, { { SHARD.lbril, 1, 1 } } },
}

-- returns expected value (after AH cut on the mats), or nil if it can't be disenchanted / no prices
function ns.DisenchantValue(id)
  local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not Instant then return end
  local _, _, _, _, _, classID = Instant(id)
  if classID ~= 2 and classID ~= 4 then return end -- weapons and armor only
  local _, _, quality, ilvl = (C_Item.GetItemInfo or GetItemInfo)(id)
  if not quality or not ilvl then return end
  local tbl = quality == 2 and GREEN or quality == 3 and BLUE
  if not tbl then return end
  for _, band in ipairs(tbl) do
    if ilvl <= band[1] then
      local ev, known = 0, false
      for _, m in ipairs(band[2]) do
        local p = ns.Price(m[1])
        if p then ev, known = ev + m[2] * m[3] * p, true end
      end
      return known and ev * (1 - ns.AH_CUT) or nil
    end
  end
end

function ns.CanDisenchant()
  for prof in pairs(ns.db.recipes) do if ns.IsProfession(prof, "Enchanting") then return true end end
  return false
end
