-- Reproduce the reported bugs on a given build (original or fixed) using only
-- functions that exist in both. usage: texlua origbugs.lua <root> <xmlindex>
local root, xmlIndexPath = arg[1], arg[2]
local here = arg[0]:match("^(.*)/") or "."
local H = dofile(here .. "/wow.lua")
assert(loadfile(here .. "/wowapi.lua"))(H)
for _, f in ipairs({"Libs/LibResComm-1.0/LibResComm-1.0.xml","Libs/LibTalentQuery-1.0/LibTalentQuery-1.0.xml","Libs/LibGroupTalents-1.0/LibGroupTalents-1.0.xml","Libs/LibHealComm-4.0/LibHealComm-4.0.xml","Libs/AceEvent-3.0/AceEvent-3.0.xml","Libs/AceSerializer-3.0/AceSerializer-3.0.xml","Libs/AceTimer-3.0/AceTimer-3.0.xml","Libs/AceComm-3.0/AceComm-3.0.xml","Libs/AbsorbsMonitor-1.0/AbsorbsMonitor-1.0.xml"}) do H.skipFiles[f] = true end
H.loadTOC(root, dofile(xmlIndexPath))
H.FireEvent("ADDON_LOADED", "CompactRaidFrame"); H.FireEvent("VARIABLES_LOADED"); H.FireEvent("PLAYER_LOGIN"); H.FireEvent("PLAYER_ENTERING_WORLD")
H.errors = {}
local function row(name, buggy) print(string.format("  %-58s %s", name, buggy and "BUG PRESENT" or "fixed")) end

-- 1. unsaved-change tracking after switching profiles
CreateNewRaidProfile("Healing")
CompactUnitFrameProfiles_ActivateRaidProfile("Healing")
CompactUnitFrameProfiles_ActivateRaidProfile(DEFAULT_CUF_PROFILE_NAME)
CompactUnitFrameProfiles_ActivateRaidProfile("Healing")
SetRaidProfileOption("Healing", "displayPets", true)
row("edit after switching profile not seen as unsaved", not RaidProfileHasUnsavedChanges())
CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
row("Cancel doesn't revert that edit", GetRaidProfileOption("Healing", "displayPets") == true)

-- 2. raid-style party frames "off" survives reload?
CUF_CVar:SetValue("useCompactPartyFrames", "0")
row("'Use Raid-Style Party Frames' off is saved as nil (reset on reload)", CompactRaidFrameAccountDB.useCompactPartyFrames == nil)
CUF_CVar:SetValue("useCompactPartyFrames", "1")

-- 3. always show saved?
local svars = {}
for line in io.lines(root .. "/CompactRaidFrame.toc") do
  local v = line:match("^## SavedVariables[^:]*:%s*(.*)$")
  if v then for n in v:gmatch("[^,%s]+") do svars[n] = true end end
end
local savedSomewhere = svars.CRF_AlwaysShow or (CompactRaidFrameAccountDB.alwaysShowSolo ~= nil) or CompactRaidFrameAccountDB.alwaysShowSolo == nil and type(CRF_SetAlwaysEnabled) == "function" and (function()
  CRF_SetAlwaysEnabled(false); local saved = CompactRaidFrameAccountDB.alwaysShowSolo == false; CRF_SetAlwaysEnabled(true); return saved end)()
row("'Always show' setting not saved between sessions", not savedSomewhere)

-- 4. role sort uses wrong raid member
H.setRaid({ { "Kami", "PALADIN", 1 }, { "Arthas", "DEATHKNIGHT", 1, "MAINTANK" }, { "Jaina", "MAGE", 2 } })
local order = { "raid1", "raid2", "raid3" }
table.sort(order, CRFSort_Role)
row("Sort By Role puts the wrong member first as Main Tank", order[1] ~= "raid2")

-- 5. resize timer
local m = CompactRaidFrameManager
local rf = m.containerResizeFrame
CompactRaidFrameManager_ResizeFrame_OnResizeStart(m)
local calls = 0
local orig = CompactRaidFrameManager_ResizeFrame_SavePosition
CompactRaidFrameManager_ResizeFrame_SavePosition = function(...) calls = calls + 1 return orig(...) end
for _ = 1, 60 do rf:GetScript("OnUpdate")(rf, 0.05) end
CompactRaidFrameManager_ResizeFrame_SavePosition = orig
CompactRaidFrameManager_ResizeFrame_OnResizeStop(m)
row("resizing re-lays out every frame after 0.5s (" .. calls .. " in 3s)", calls > 10)

-- 6. keep groups together height
CompactRaidFrameManager_SetSetting("KeepGroupsTogether", true)
rf:SetHeight(300)
CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(m)
row("Keep Groups Together height snapped to frame rows", math.abs(CompactRaidFrameContainer:GetHeight() - 286) > 0.01)
CompactRaidFrameManager_SetSetting("KeepGroupsTogether", false)

-- 7. option change in combat
H.setParty({ { "Arthas", "DEATHKNIGHT" } })
CRF_RelayGroupRosterUpdate()
H.blocked = {}
H.inCombat = true
SetRaidProfileOption(GetActiveRaidProfile(), "frameHeight", 60)
CompactUnitFrameProfiles_ApplyCurrentSettings()
SetRaidProfileOption(GetActiveRaidProfile(), "displayPets", true)
CompactUnitFrameProfiles_ApplyCurrentSettings()
local n1 = #H.blocked
H.blocked = {}
H.setRaid({ { "Kami", "PALADIN", 1 }, { "Arthas", "DEATHKNIGHT", 1 }, { "Jaina", "MAGE", 2 } })
CRF_RelayGroupRosterUpdate()
H.FireEvent("UNIT_FLAGS", "raid2")
local countText = m.displayFrame.memberCountLabel:GetText()
H.inCombat = false
H.FireEvent("PLAYER_REGEN_ENABLED")
row("changing options in combat hits protected frames (" .. n1 .. " blocked calls)", n1 > 0)
row("raid member counts frozen during combat (shows " .. tostring(countText) .. ")", countText ~= "3/3")
row("'Raid Members' label stale after a roster change in combat", m.displayFrame.label:GetText() ~= RAID_MEMBERS)
print("  (lua errors during run: " .. #H.errors .. ")")
for _, e in ipairs(H.errors) do print("    " .. e:sub(1, 200)) end
