-- Heal prediction / absorb wiring with stand-in LibHealComm / AbsorbsMonitor.
-- usage: texlua healtest.lua <root> <xmlindex>
local root, xmlIndexPath = arg[1], arg[2]
local here = arg[0]:match("^(.*)/") or "."
local H = dofile(here .. "/wow.lua")
assert(loadfile(here .. "/wowapi.lua"))(H)
for _, f in ipairs({"Libs/LibResComm-1.0/LibResComm-1.0.xml","Libs/LibTalentQuery-1.0/LibTalentQuery-1.0.xml","Libs/LibGroupTalents-1.0/LibGroupTalents-1.0.xml","Libs/LibHealComm-4.0/LibHealComm-4.0.xml","Libs/AceEvent-3.0/AceEvent-3.0.xml","Libs/AceSerializer-3.0/AceSerializer-3.0.xml","Libs/AceTimer-3.0/AceTimer-3.0.xml","Libs/AceComm-3.0/AceComm-3.0.xml","Libs/AbsorbsMonitor-1.0/AbsorbsMonitor-1.0.xml"}) do H.skipFiles[f] = true end

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 print("  ok   " .. m) else fail = fail + 1 print("  FAIL " .. m) end end

-- load LibStub + CallbackHandler first, then register the stand-in libs, then the rest
H.loadLua(root, "Libs/LibStub/LibStub.lua")
H.loadLua(root, "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
local CBH = LibStub:GetLibrary("CallbackHandler-1.0")
local HC = LibStub:NewLibrary("LibHealComm-4.0", 999)
HC.callbacks = CBH:New(HC)
HC.ALL_HEALS = 0x17
HC.amounts = {}      -- guid -> amount
HC.mods = {}         -- guid -> modifier
function HC:GetHealAmount(guid, flags, time, caster) return HC.amounts[guid] end
function HC:GetHealModifier(guid) return HC.mods[guid] or 1 end
local AM = LibStub:NewLibrary("AbsorbsMonitor-1.0", 999)
AM.Core = { Callbacks = CBH:New(AM) }
AM.totals = {}
function AM.Unit_Total(guid) return AM.totals[guid] end
H.skipFiles["Libs/LibStub/LibStub.lua"] = true
H.skipFiles["Libs/CallbackHandler-1.0/CallbackHandler-1.0.xml"] = true

H.loadTOC(root, dofile(xmlIndexPath))
H.FireEvent("ADDON_LOADED", "CompactRaidFrame"); H.FireEvent("VARIABLES_LOADED"); H.FireEvent("PLAYER_LOGIN"); H.FireEvent("PLAYER_ENTERING_WORLD")
H.setParty({ { "Arthas", "DEATHKNIGHT" }, { "Jaina", "MAGE" } })
CRF_RelayGroupRosterUpdate()
H.RunUpdates(0.05, 2)
check(#H.errors == 0, "loads with heal/absorb libs present (" .. #H.errors .. " errors)")
for _, e in ipairs(H.errors) do print("    " .. e:sub(1, 300)) end

-- find the frames showing party1 / party2 / player
local byUnit = {}
for i = 1, 20 do local f = _G["CompactRaidFrame" .. i]; if f and f.unit then byUnit[f.unit] = f end end
check(byUnit.player and byUnit.party1 and byUnit.party2, "frames exist for player, party1, party2")

local function clearDirty() for _, f in pairs(byUnit) do f.healPredictionDirty = nil end end
local function dirtyUnits()
  local t = {}
  for u, f in pairs(byUnit) do if f.healPredictionDirty then t[#t+1] = u end end
  table.sort(t); return table.concat(t, ",")
end

clearDirty()
HC.callbacks:Fire("HealComm_HealStarted", "0x01", 48782, 1, H.now + 2, "0x101")   -- Holy Light on party1
check(dirtyUnits() == "party1", "a heal on party1 only refreshes party1's frame (got " .. dirtyUnits() .. ")")
clearDirty()
HC.callbacks:Fire("HealComm_HealStarted", "0x01", 48072, 1, H.now + 2, "0x101", "0x102", "0x01")   -- Prayer of Healing
check(dirtyUnits() == "party1,party2,player", "a group heal refreshes each target (got " .. dirtyUnits() .. ")")
clearDirty()
HC.callbacks:Fire("HealComm_HealStopped", "0x01", 48782, 1, false, "0x102")
check(dirtyUnits() == "party2", "heal stopped refreshes its target")
clearDirty()
HC.callbacks:Fire("HealComm_ModifierChanged", "0x102", 0.5)
check(dirtyUnits() == "party2", "healing modifier change refreshes that unit")
clearDirty()
AM.Core.Callbacks:Fire("EffectApplied", "0x01", "Kami", "0x101", "Arthas", 48066, 2000, 1)
check(dirtyUnits() == "party1", "absorb applied refreshes the shielded unit")
clearDirty()
AM.Core.Callbacks:Fire("UnitUpdated", "0x102", 100, 1)
check(dirtyUnits() == "party2", "absorb update refreshes that unit")
clearDirty()
HC.callbacks:Fire("HealComm_HealStarted", "0x09", 1, 1, H.now + 2, "0xDEAD")
check(dirtyUnits() == "", "heals on someone not shown refresh nothing")

HC.amounts["0x102"] = 4000
HC.mods["0x102"] = 0.5
check(UnitGetIncomingHeals("party2") == 2000, "incoming heals scaled by the target's healing modifier (" .. tostring(UnitGetIncomingHeals("party2")) .. ")")
AM.totals["0x101"] = 1500
check(UnitGetTotalAbsorbs("party1") == 1500, "absorb total read from AbsorbsMonitor")
H.RunUpdates(0.05, 2)
check(#H.errors == 0, "no errors drawing predictions (" .. #H.errors .. ")")
for _, e in ipairs(H.errors) do print("    " .. e:sub(1, 300)) end
print(string.format("\n%d passed, %d failed", pass, fail))
