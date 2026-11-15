-- usage: texlua run.lua <addonRoot> <xmlindex.lua> <scenario> [savedvars-in] [savedvars-out]
local root, xmlIndexPath, scenario, svIn, svOut = arg[1], arg[2], arg[3] or "all", arg[4], arg[5]
if svIn == "" then svIn = nil end
local here = arg[0]:match("^(.*)/") or "."
local H = dofile(here .. "/wow.lua")
assert(loadfile(here .. "/wowapi.lua"))(H)
local xmlIndex = dofile(xmlIndexPath)

local results = { pass = 0, fail = 0 }
local function check(cond, msg)
  if cond then results.pass = results.pass + 1; print("  ok   " .. msg)
  else results.fail = results.fail + 1; print("  FAIL " .. msg) end
end
local function section(t) print("\n== " .. t) end

-- serialise saved variables
local function ser(v, ind)
  ind = ind or ""
  if type(v) == "table" then
    local out = { "{\n" }
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      out[#out+1] = ind .. "  " .. ks .. " = " .. ser(v[k], ind .. "  ") .. ",\n"
    end
    out[#out+1] = ind .. "}"
    return table.concat(out)
  elseif type(v) == "string" then return string.format("%q", v)
  else return tostring(v) end
end

-- only LibStub + CallbackHandler are loaded; the other libs are optional at runtime
for _, f in ipairs({
  "Libs/LibResComm-1.0/LibResComm-1.0.xml", "Libs/LibTalentQuery-1.0/LibTalentQuery-1.0.xml",
  "Libs/LibGroupTalents-1.0/LibGroupTalents-1.0.xml", "Libs/LibHealComm-4.0/LibHealComm-4.0.xml",
  "Libs/AceEvent-3.0/AceEvent-3.0.xml", "Libs/AceSerializer-3.0/AceSerializer-3.0.xml",
  "Libs/AceTimer-3.0/AceTimer-3.0.xml", "Libs/AceComm-3.0/AceComm-3.0.xml", "Libs/AbsorbsMonitor-1.0/AbsorbsMonitor-1.0.xml",
}) do H.skipFiles[f] = true end

if os.getenv("CRF_LOCALE") then H.locale = os.getenv("CRF_LOCALE") end

------------------------------------------------------------------------
section("Load addon")
local svars = H.loadTOC(root, xmlIndex)
local writerOptionsVersion
if svIn then
  local t = dofile(svIn)
  for k, v in pairs(t) do _G[k] = v end
  writerOptionsVersion = CompactRaidFrameAccountDB and CompactRaidFrameAccountDB.crfOptionsVersion or 1
end
H.FireEvent("ADDON_LOADED", "CompactRaidFrame")
H.FireEvent("VARIABLES_LOADED")
H.FireEvent("PLAYER_LOGIN")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.RunUpdates(0.1, 3)
check(#H.errors == 0, "no Lua errors while loading (" .. #H.errors .. ")")
for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
H.errors = {}

local function geometryReport(panel, tabName)
  local pl, pr = H.hspan(panel)
  local pb, pt = H.vspan(panel)
  local overflow = {}
  local rows = {}
  local function visit(o)
    if not o.__shown then return end
    local isRegion = (o.__type == "Texture" or o.__type == "FontString")
    local skip = (o.__type == "Texture" and (o.__name or ""):match("Separator$"))
    local l, r = H.hspan(o)
    local b, t = H.vspan(o)
    if l and b and not skip and (o.__type ~= "Texture" or (r - l) > 0) then
      -- dropdown art has ~16px of transparent padding on each side
      local il, ir = l, r
      if o.__isDropDown then il, ir = l + 16, r - 16 end
      if o.__type == "Texture" and not o.__name then goto children end
      local relL, relR, relT, relB = il - pl, ir - pl, pt - t, pt - b
      local label = (o.__name or o.__type) .. ((o.__type == "FontString" and o.__text) and (' "' .. tostring(o.__text) .. '"') or "")
      if o.__type ~= "Texture" or o.__name then
        rows[#rows+1] = string.format("    %-62s x %6.1f..%6.1f  y %6.1f..%6.1f", label:sub(1, 62), relL, relR, relT, relB)
      end
      if o.__h and o.__h > 0 and math.abs((t - b) - o.__h) > 1 and not o.__isDropDown then
        overflow[#overflow+1] = string.format("%s: anchors make it %.1f tall although its height is %.1f (conflicting anchors)", label, t - b, o.__h)
      end
      if (r - l) < -0.01 or (t - b) < -0.01 then
        overflow[#overflow+1] = string.format("%s has a negative size (%.1f x %.1f) - conflicting anchors", label, r - l, t - b)
      end
      if il < pl - 0.5 or ir > pr + 0.5 or b < pb - 0.5 or t > pt + 0.5 then
        overflow[#overflow+1] = string.format("%s  (x %.1f..%.1f, y %.1f..%.1f; panel 0..%.1f x 0..%.1f)", label, relL, relR, relT, relB, pr - pl, pt - pb)
      end
    end
    ::children::
    for _, rg in ipairs(o.__regions or {}) do if rg.__shown then visit(rg) end end
    for _, c in ipairs(o.__children or {}) do
      if c.__strata ~= "DIALOG" then visit(c) end
    end
  end
  visit(panel)
  if os.getenv("CRF_VERBOSE") then for _, r in ipairs(rows) do print(r) end end
  return overflow, pr - pl, pt - pb
end

------------------------------------------------------------------------
if scenario == "all" then
  section("New profile defaults")
  local function checkDefaults(what)
    local prof = GetActiveRaidProfile()
    check(prof == DEFAULT_CUF_PROFILE_NAME and GetNumRaidProfiles() == 1, what .. ": one profile, " .. tostring(prof))
    check(GetRaidProfileOption(prof, "frameHeight") == 66 and GetRaidProfileOption(prof, "frameWidth") == 129
      and DefaultCompactUnitFrameSetupOptions.height == 66 and DefaultCompactUnitFrameSetupOptions.width == 129, what .. ": frames 66 x 129 (50% / 50%)")
    check(not GetRaidProfileOption(prof, "displayBorder") and DefaultCompactUnitFrameSetupOptions.displayBorder == false, what .. ": Display Border off")
    local on, off = true, true
    for _, k in ipairs({ "10Players", "15Players", "25Players", "40Players", "PvP", "PvE" }) do on = on and GetRaidProfileOption(prof, "autoActivate" .. k) == true end
    for _, k in ipairs({ "2Players", "3Players", "5Players" }) do off = off and not GetRaidProfileOption(prof, "autoActivate" .. k) end
    check(on and off, what .. ": auto-activates for 10/15/25/40 players, PvP and PvE (not 2/3/5)")
    check(GetRaidProfileOption(prof, "powerText") == "none" and DefaultCompactUnitFrameOptions.powerText == "none", what .. ": no power bar text")
  end
  checkDefaults("fresh install")
  check(CompactRaidFrameAccountDB.crfOptionsVersion == 4, "saved data marked as version 4")
  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  _G["CompactUnitFrameProfilesOptionsTab2"]:Click()
  check(_G["CompactUnitFrameProfilesOptionsLayoutHeightSlider"].valueLabel:GetText() == "50%"
    and _G["CompactUnitFrameProfilesOptionsLayoutWidthSlider"].valueLabel:GetText() == "50%"
    and not _G["CompactUnitFrameProfilesOptionsLayoutDisplayBorder"]:GetChecked(), "Layout tab: 50% / 50%, Display Border unticked")
  -- the panel's Defaults button
  SetRaidProfileOption(DEFAULT_CUF_PROFILE_NAME, "frameWidth", 100)
  SetRaidProfileOption(DEFAULT_CUF_PROFILE_NAME, "displayBorder", true)
  CreateNewRaidProfile("Extra", DEFAULT_CUF_PROFILE_NAME)
  CompactUnitFrameProfiles_DefaultCallback(CompactUnitFrameProfiles)
  H.RunUpdates(0.1, 2)
  checkDefaults("after Defaults")
  _G["CompactUnitFrameProfilesOptionsTab1"]:Click()
  check(#H.errors == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  H.errors = {}
end

------------------------------------------------------------------------
if scenario == "all" or scenario == "layout" then
  section("Options panel layout (3.3.5a panel container)")
  local panel = CompactUnitFrameProfiles
  InterfaceOptionsFrame_OpenToCategory(panel)
  local w, h = panel:GetWidth(), panel:GetHeight()
  check(math.abs(w - 413) < 1 and math.abs(h - 428) < 1, string.format("panel is 413x428 (got %.0fx%.0f)", w, h))
  local opts = panel.optionsFrame
  if opts and opts.pages then
    for i = 1, #opts.pages do
      _G[opts:GetName() .. "Tab" .. i]:Click()
      check(opts.pages[i]:IsVisible() and opts.selectedTab == i, "tab " .. i .. " selects its page")
      local warn = opts.autoActivateDisabledLabel
      local isAutoActivate = opts.pages[i]:GetName():match("AutoActivate$")
      if isAutoActivate then
        -- new profiles auto-activate for 10/15/25/40 players, PvP and PvE
        local aa = "CompactUnitFrameProfilesOptionsAutoActivateAutoActivate"
        local prof = GetActiveRaidProfile()
        check(_G[aa .. "10Players"]:GetChecked() and _G[aa .. "15Players"]:GetChecked() and _G[aa .. "25Players"]:GetChecked()
          and _G[aa .. "40Players"]:GetChecked() and _G[aa .. "PvP"]:GetChecked() and _G[aa .. "PvE"]:GetChecked()
          and not GetRaidProfileOption(prof, "autoActivate2Players") and not GetRaidProfileOption(prof, "autoActivate3Players")
          and not GetRaidProfileOption(prof, "autoActivate5Players") and not warn:IsVisible(),
          "default profile: auto-activates for 10/15/25/40, PvP and PvE (not 2/3/5)")
        _G[aa .. "PvP"]:Click(); _G[aa .. "PvE"]:Click()   -- sizes but no PvP/PvE
        check(warn:IsVisible() and warn:GetText() == AUTO_ACTIVATE_PROFILE_NO_ENEMYTYPE, "never-auto-activates warning shown")
      end
      local over = geometryReport(panel, "tab" .. i)
      if isAutoActivate then
        local wb, wt = H.vspan(warn)
        check((wt - wb) < 40, string.format("warning text box is %.0fpx tall (2 lines)", wt - wb))
        _G["CompactUnitFrameProfilesOptionsAutoActivateAutoActivatePvE"]:Click()
        check(not warn:IsVisible(), "warning hidden again")
        _G["CompactUnitFrameProfilesOptionsAutoActivateAutoActivatePvP"]:Click()
      end
      check(#over == 0, "tab " .. i .. ": every visible control lies inside the panel")
      for _, o in ipairs(over) do print("       outside: " .. o) end
    end
    -- the always-show checkbox is in the panel now, not on the manager
    check(_G[opts:GetName() .. "GeneralAlwaysShow"] ~= nil, "Always show checkbox is in the options panel")
  else
    local over = geometryReport(panel, "original")
    check(#over == 0, "every visible control lies inside the panel")
    for _, o in ipairs(over) do print("       outside: " .. o) end
  end
  check(_G.CompactRaidFrameManagerDisplayFrameAlwaysShowCheck == nil, "no Always show checkbox on the raid manager")
  check(#H.errors == 0, "no Lua errors opening the panel")
  for _, e in ipairs(H.errors) do print("     " .. e) end
  H.errors = {}
end

------------------------------------------------------------------------
if scenario == "all" or scenario == "behaviour" then
  section("Account settings persist")
  local DB = CompactRaidFrameAccountDB
  check(type(DB) == "table" and #DB >= 1, "account DB created with a profile")
  check(CRF_IsAlwaysEnabled() == false and DB.alwaysShowSolo == nil, "Always show defaults to off")
  check(not CompactRaidFrameManager:IsShown() and GetDisplayedAllyFrames() == nil and not CompactRaidFrameContainer:IsVisible(), "solo by default: raid frames and manager hidden")
  local always = _G["CompactUnitFrameProfilesOptionsGeneralAlwaysShow"]
  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  check(not always:GetChecked(), "checkbox starts unticked")
  always:Click()
  check(DB.alwaysShowSolo == true and CompactRaidFrameManager:IsShown() and GetDisplayedAllyFrames() == "raid", "ticking Always show saves it and shows the manager when solo")
  always:Click()
  check(DB.alwaysShowSolo == false and not CompactRaidFrameManager:IsShown(), "unticking saves false and hides it again")
  always:Click()   -- on for the rest of these tests (they were written with a solo manager on screen)

  local raidStyle = _G["CompactUnitFrameProfilesOptionsGeneralRaidStylePartyFrames"]
  raidStyle:Click()
  check(DB.useCompactPartyFrames == "0", "unticking raid-style party frames stores \"0\" (not nil)")
  local two = _G["CompactUnitFrameProfilesOptionsAutoActivateAutoActivate2Players"]
  check(CRF_IsButtonEnabled(two) == false, "2-player auto-activate disabled without raid-style party frames")
  raidStyle:Click()
  check(DB.useCompactPartyFrames == "1" and CRF_IsButtonEnabled(two), "re-enabled")

  section("Profile save / cancel tracking")
  local p = CompactUnitFrameProfiles
  -- create a second profile
  CompactUnitFrameProfiles_ShowNewProfileDialog()
  p.newProfileDialog.editBox:SetText("Healing")
  check(CRF_IsButtonEnabled(p.newProfileDialog.createButton), "Create enabled for a new name")
  p.newProfileDialog.createButton:Click()
  check(GetActiveRaidProfile() == "Healing" and GetNumRaidProfiles() == 2, "new profile created and active")
  -- switch back to Primary, then to Healing, then edit Healing
  H.pickDropDown(CompactUnitFrameProfilesProfileSelector, "Primary")
  H.pickDropDown(CompactUnitFrameProfilesProfileSelector, "Healing")
  check(GetActiveRaidProfile() == "Healing", "switched to Healing")
  local pets = _G["CompactUnitFrameProfilesOptionsGeneralDisplayPets"]
  pets:Click()
  check(RaidProfileHasUnsavedChanges() == true, "edit on the switched-to profile is detected as unsaved")
  check(CRF_IsButtonEnabled(CompactUnitFrameProfilesSaveButton), "Save button enabled")
  CompactUnitFrameProfiles_CancelChanges(p)
  check(not GetRaidProfileOption("Healing", "displayPets"), "Cancel reverts the edit")
  pets:Click()
  H.pickDropDown(CompactUnitFrameProfilesProfileSelector, "Primary")
  check(p.unsavedProfileDialog:IsShown(), "switching away with unsaved changes asks first")
  _G[p.unsavedProfileDialog:GetName() .. "SaveButton"]:Click()
  check(GetActiveRaidProfile() == "Primary" and GetRaidProfileOption("Healing", "displayPets") == true, "Save in the prompt keeps the edit and switches")

  section("Enter in the new-profile box")
  CompactUnitFrameProfiles_ShowNewProfileDialog()
  p.newProfileDialog.editBox:SetText("")
  local before = GetNumRaidProfiles()
  p.newProfileDialog.editBox:GetScript("OnEnterPressed")(p.newProfileDialog.editBox)
  check(GetNumRaidProfiles() == before, "Enter with an empty name creates nothing")
  CompactUnitFrameProfiles_HideNewProfileDialog()

  section("Sliders")
  local height = _G["CompactUnitFrameProfilesOptionsLayoutHeightSlider"]
  local before = GetRaidProfileOption("Primary", "frameHeight")
  CompactUnitFrameProfiles_UpdateCurrentPanel()
  check(GetRaidProfileOption("Primary", "frameHeight") == before and not RaidProfileHasUnsavedChanges(), "refreshing the panel does not write slider values")
  height:SetValue(50)
  check(GetRaidProfileOption("Primary", "frameHeight") == 50, "dragging the slider updates the profile")
  check(DefaultCompactUnitFrameSetupOptions.height == 50, "and applies it")
  CompactUnitFrameProfiles_CancelChanges(p)

  section("Combat")
  H.setParty({ { "Arthas", "DEATHKNIGHT" }, { "Jaina", "MAGE" } })
  CRF_RelayGroupRosterUpdate()
  check(#H.blocked == 0, "roster update out of combat: nothing blocked")
  H.blocked = {}
  H.inCombat = true
  pets = _G["CompactUnitFrameProfilesOptionsGeneralDisplayPets"]
  pets:Click()
  CRF_SetGroupLayout(GetActiveRaidProfile(), CRF_GROUP_LAYOUTS[3], false)   -- Separate Groups (Vertical)
  height:SetValue(60)
  _G["CompactUnitFrameProfilesOptionsGeneralRaidStylePartyFrames"]:Click()
  _G["CompactUnitFrameProfilesOptionsGeneralAlwaysShow"]:Click()
  H.setRaid({ { "Kami", "PALADIN", 1 }, { "Arthas", "DEATHKNIGHT", 1, "MAINTANK" }, { "Jaina", "MAGE", 2 } })
  CRF_RelayGroupRosterUpdate()
  H.FireEvent("UNIT_FLAGS", "raid2")
  check(#H.blocked == 0, "option changes + roster change in combat: no protected calls (" .. #H.blocked .. ")")
  for i = 1, math.min(3, #H.blocked) do print("       blocked: " .. H.blocked[i]:gsub("\n", "\n         ")) end
  check(CompactRaidFrameManager.displayFrame.memberCountLabel:GetText() == "3/3", "manager count updates in combat")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")
  check(CompactRaidFrameManager.displayFrame.label:GetText() == RAID_MEMBERS, "label switched to Raid Members after combat")
  check(DefaultCompactUnitFrameSetupOptions.height == 60, "profile change from combat applied after combat")
  check(CompactRaidFrameContainer.groupMode == "discrete", "keep-groups change applied after combat")
  _G["CompactUnitFrameProfilesOptionsGeneralRaidStylePartyFrames"]:Click()
  _G["CompactUnitFrameProfilesOptionsGeneralAlwaysShow"]:Click()
  CRF_SetGroupLayout(GetActiveRaidProfile(), CRF_GROUP_LAYOUTS[1], false)

  section("Sorting by role (raid)")
  local order = { "raid1", "raid2", "raid3" }
  table.sort(order, CRFSort_Role)
  check(order[1] == "raid2", "MAINTANK (raid2) sorts first (got " .. order[1] .. ")")

  section("Resize drag timer")
  local rf = CompactRaidFrameManager.containerResizeFrame
  if os.getenv("CRF_DEBUG") then
    print("rf", rf:GetLeft(), rf:GetRight(), rf:GetTop(), rf:GetBottom(), rf.__w, rf.__h)
    for p, a in pairs(rf.__points) do print(" rf point", p, a.rel and (a.rel.__name or tostring(a.rel)), a.relPoint, a.x, a.y) end
    local m = CompactRaidFrameManager
    print("m", m:GetLeft(), m:GetRight(), m:GetTop(), m:GetBottom(), m.__w, m.__h)
    for p, a in pairs(m.__points) do print(" m point", p, a.rel and (a.rel.__name or tostring(a.rel)), a.relPoint, a.x, a.y) end
  end
  CompactRaidFrameManager_ResizeFrame_OnResizeStart(CompactRaidFrameManager)
  local calls = 0
  local orig = CompactRaidFrameManager_ResizeFrame_SavePosition
  CompactRaidFrameManager_ResizeFrame_SavePosition = function(...) calls = calls + 1 return orig(...) end
  for _ = 1, 60 do rf:GetScript("OnUpdate")(rf, 0.05) end
  CompactRaidFrameManager_ResizeFrame_SavePosition = orig
  CompactRaidFrameManager_ResizeFrame_OnResizeStop(CompactRaidFrameManager)
  check(calls <= 7, "3s of resizing re-lays out ~every 0.5s (" .. calls .. " times)")

  section("Keep groups together container height")
  CompactRaidFrameManager_SetSetting("KeepGroupsTogether", true)
  rf:SetHeight(300)
  CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(CompactRaidFrameManager)
  check(math.abs(CompactRaidFrameContainer:GetHeight() - (300 - 14)) < 0.01, "discrete mode uses the full height (" .. CompactRaidFrameContainer:GetHeight() .. ")")
  CompactRaidFrameManager_SetSetting("KeepGroupsTogether", false)

  section("Right-click menu")
  local unitFrame
  for i = 1, 60 do local f = _G["CompactRaidFrame" .. i]; if f and f.unit and UnitExists(f.unit) then unitFrame = f break end end
  check(unitFrame ~= nil, "found a compact unit frame in use")
  if unitFrame then
    H.pcallr(unitFrame.menu)
    local idx
    for i, v in ipairs(UnitPopupMenus[unitFrame.dropDown.which] or {}) do if v == "SET_FOCUS" then idx = i end end
    if os.getenv("CRF_DEBUG") then print("unit", unitFrame.unit, "which", unitFrame.dropDown.which, "idx", idx, "shown", idx and UnitPopupShown[1][idx]) end
    check(idx and UnitPopupShown[1][idx] == 0, "Set Focus hidden on compact frame menus")
  end

  check(#H.errors == 0, "no Lua errors during behaviour tests (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  check(#H.blocked == 0, "no protected calls in combat overall")
  H.errors = {}
end



------------------------------------------------------------------------
if scenario == "all" or scenario == "extra" then
  section("Groups / party layouts")
  local groupsDropdown = _G["CompactUnitFrameProfilesOptionsLayoutGroupsDropdown"]
  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  _G["CompactUnitFrameProfilesOptionsTab2"]:Click()
  local raid = {}
  for i = 1, 10 do raid[i] = { "Member" .. i, (i % 2 == 0) and "PRIEST" or "WARRIOR", (i <= 5) and 1 or 2 } end
  H.setRaid(raid)
  CRF_RelayGroupRosterUpdate()
  H.pickDropDown(groupsDropdown, "separateVertical")   -- discrete mode
  check(CompactRaidGroup1 and CompactRaidGroup2 and CompactRaidGroup1:IsShown(), "Separate Groups builds group frames")
  check(_G["CompactUnitFrameProfilesOptionsLayoutSortByDropdown"]:IsShown(), "Sort By stays while groups are separate (it orders each group)")
  H.inCombat = true
  raid[11] = { "Late", "MAGE", 3 }
  H.setRaid(raid)
  CRF_RelayGroupRosterUpdate()
  check(#H.blocked == 0, "raid roster change in combat (groups mode): nothing blocked")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")
  check(CompactRaidGroup3 and CompactRaidGroup3:IsShown(), "new group laid out after combat")
  H.setParty({ { "Arthas", "DEATHKNIGHT" } })
  CRF_RelayGroupRosterUpdate()
  check(CompactPartyFrame and CompactPartyFrame:IsShown(), "party in groups mode uses the compact party frame")
  H.pickDropDown(groupsDropdown, "combineVertical")
  check(_G["CompactUnitFrameProfilesOptionsLayoutSortByDropdown"]:IsShown(), "Sort By back when groups are combined")
  H.pickDropDown(_G["CompactUnitFrameProfilesOptionsLayoutSortByDropdown"], "role")
  check(GetRaidProfileOption(GetActiveRaidProfile(), "sortBy") == "role", "Sort By dropdown writes the profile")
  check(_G["CompactUnitFrameProfilesOptionsLayoutSortByDropdownText"]:GetText() == COMPACT_UNIT_FRAME_PROFILE_SORTBY_ROLE, "and shows the choice")
  H.pickDropDown(_G["CompactUnitFrameProfilesOptionsDisplayHealthTextDropdown"], "perc")
  check(DefaultCompactUnitFrameOptions.healthText == "perc", "Health text dropdown applies")

  section("Roster event bursts")
  local layouts = 0
  local origLayout = CompactRaidFrameContainer_LayoutFrames
  CompactRaidFrameContainer_LayoutFrames = function(...) layouts = layouts + 1 return origLayout(...) end
  raid[12] = { "Later", "ROGUE", 3 }
  H.setRaid(raid)
  H.FireEvent("PARTY_MEMBERS_CHANGED"); H.FireEvent("RAID_ROSTER_UPDATE"); H.FireEvent("RAID_ROSTER_UPDATE")
  check(layouts == 0, "nothing re-laid out synchronously")
  H.RunUpdates(0.016, 1)
  check(layouts == 1, "three roster events in one frame -> one re-layout (" .. layouts .. ")")
  H.RunUpdates(0.016, 3)
  check(layouts == 1, "and nothing more afterwards")
  CompactRaidFrameContainer_LayoutFrames = origLayout

  section("Reset position / delete profile / options button")
  H.inCombat = true
  _G["CompactUnitFrameProfilesOptionsLayoutResetPositionButton"]:Click()
  H.inCombat = false
  check(#H.blocked == 0 and DEFAULT_CHAT_FRAME.messages[#DEFAULT_CHAT_FRAME.messages] == COMPACT_UNIT_FRAME_ERRCOMBAT, "Reset Position refuses in combat with a message")
  _G["CompactUnitFrameProfilesOptionsLayoutResetPositionButton"]:Click()
  check(CompactRaidFrameManager.dynamicContainerPosition == true, "Reset Position works out of combat")
  CreateNewRaidProfile("Tank")
  CompactUnitFrameProfiles_ActivateRaidProfile("Tank")
  CompactUnitFrameProfilesDeleteButton:Click()
  check(CompactUnitFrameProfiles.deleteProfileDialog:IsShown(), "Delete asks for confirmation")
  _G[CompactUnitFrameProfiles.deleteProfileDialog:GetName() .. "DeleteButton"]:Click()
  check(not RaidProfileExists("Tank") and GetActiveRaidProfile() ~= "Tank", "profile deleted and another activated")
  InterfaceOptionsFrame:Hide()
  CompactUnitFrameProfiles:Hide()
  CompactRaidFrameManagerDisplayFrameOptionsButton:Click()
  check(CompactUnitFrameProfiles:IsVisible(), "manager's options button opens the Raid Profiles panel")
  check(#H.errors == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  check(#H.blocked == 0, "nothing blocked")
  H.errors = {}
end
------------------------------------------------------------------------
if scenario == "all" or scenario == "followup" then
  local m = CompactRaidFrameManager
  local df = m.displayFrame
  local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 1) end

  section("Raid manager: Reset Position under Lock / Hide")
  H.setParty({ { "Arthas", "DEATHKNIGHT" } })
  CRF_RelayGroupRosterUpdate()
  H.RunUpdates(0.016, 2)
  CompactRaidFrameManager_Expand(m)
  local lock, hide, reset = df.lockedModeToggle, df.hiddenModeToggle, df.resetPosition
  check(GetDisplayedAllyFrames() == "raid" and reset:IsVisible(), "Reset Position shown on the raid manager")
  check(reset:GetText() == RESET_POSITION, "labelled Reset Position")
  local lockL, lockR = H.hspan(lock); local lockB = select(1, H.vspan(lock))
  local hideL, hideR = H.hspan(hide)
  local resL, resR = H.hspan(reset); local resB, resT = H.vspan(reset)
  local mB = select(1, H.vspan(m))
  check(near(resT, lockB, 0.5), string.format("directly below Lock / Hide (gap %.1f)", (lockB or 0) - (resT or 0)))
  check(near(resL, lockL) and near(resR, hideR, 2), "same width as the Lock + Hide row")
  check(resB and mB and resB - mB >= 8, string.format("inside the manager, above its bottom border (%.0fpx)", (resB or 0) - (mB or 0)))
  H.inCombat = true
  m.dynamicContainerPosition = false
  local nmsg = #DEFAULT_CHAT_FRAME.messages
  reset:Click()
  H.inCombat = false
  check(#H.blocked == 0 and m.dynamicContainerPosition == false and #DEFAULT_CHAT_FRAME.messages == nmsg + 1
    and DEFAULT_CHAT_FRAME.messages[#DEFAULT_CHAT_FRAME.messages] == COMPACT_UNIT_FRAME_ERRCOMBAT, "in combat: refuses with a message, nothing blocked")
  local saved = 0
  local origSave = CompactRaidFrameManager_ResizeFrame_SavePosition
  CompactRaidFrameManager_ResizeFrame_SavePosition = function(...) saved = saved + 1 return origSave(...) end
  reset:Click()
  CompactRaidFrameManager_ResizeFrame_SavePosition = origSave
  check(m.dynamicContainerPosition == true and saved == 1, "out of combat: resets the container position and saves it")
  _G["CompactUnitFrameProfilesOptionsGeneralRaidStylePartyFrames"]:Click()     -- Blizzard party frames
  check(GetDisplayedAllyFrames() == "party" and not reset:IsShown() and not lock:IsShown(), "hidden with Lock / Hide when the compact frames are not in use")
  _G["CompactUnitFrameProfilesOptionsGeneralRaidStylePartyFrames"]:Click()
  check(reset:IsShown(), "back with the compact frames")

  section("Raid manager tab only on mouseover")
  local border = _G["CompactRaidFrameManagerBorderRight"]
  local toggle = m.toggleButton
  local container = CompactRaidFrameContainer
  check(CRF_IsManagerTabFadeEnabled() == true, "on by default")
  CompactRaidFrameManager_Collapse(m)
  H.cursorX, H.cursorY = 900, 500
  H.RunUpdates(0.05, 30)
  check(m.tabAlpha == 0 and toggle:GetAlpha() == 0 and border:GetAlpha() == 0, "collapsed, mouse elsewhere: tab hidden")
  check(m:GetAlpha() == 1 and container:GetAlpha() == 1 and container:IsVisible(), "raid frames stay visible")
  local tl, tr = H.hspan(m); local tb, tt = H.vspan(m)
  check(tr and tr > 0 and tr < 40, string.format("collapsed tab is the strip at the screen edge (right edge x=%.0f)", tr or -1))
  H.cursorX, H.cursorY = math.max(tl, 0) + 4, (tb + tt) / 2
  H.RunUpdates(0.05, 1)
  check(m.tabAlpha > 0 and m.tabAlpha < 1, "fades in under the mouse")
  H.RunUpdates(0.05, 4)
  check(m.tabAlpha == 1 and toggle:GetAlpha() == 1 and border:GetAlpha() == 1, "fully shown while the mouse is over it")
  H.cursorX, H.cursorY = 900, 500
  H.RunUpdates(0.05, 6)
  check(m.tabAlpha == 1, "stays a moment after the mouse leaves")
  H.RunUpdates(0.05, 20)
  check(m.tabAlpha == 0, "then fades out")
  H.inCombat = true
  H.cursorX, H.cursorY = math.max(tl, 0) + 4, (tb + tt) / 2
  H.RunUpdates(0.05, 5)
  check(m.tabAlpha == 1 and #H.blocked == 0, "works in combat (alpha only, nothing blocked)")
  H.inCombat = false
  H.cursorX, H.cursorY = 900, 500
  H.RunUpdates(0.05, 30)
  CompactRaidFrameManager_Expand(m)
  H.RunUpdates(0.05, 1)
  check(m.tabAlpha == 1 and border:GetAlpha() == 1, "expanded manager is never faded")
  H.RunUpdates(0.05, 30)
  check(m.tabAlpha == 1, "even with the mouse elsewhere")
  CompactRaidFrameManager_Collapse(m)
  H.RunUpdates(0.05, 30)
  m:Hide(); m:Show()
  check(m.tabAlpha == 0, "re-shown manager starts hidden (no flash)")

  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  _G["CompactUnitFrameProfilesOptionsTab1"]:Click()
  local opt = _G["CompactUnitFrameProfilesOptionsGeneralManagerTabMouseover"]
  check(opt and opt:IsVisible() and opt:GetChecked(), "General tab has the option, ticked")
  opt:Click()
  check(CRF_IsManagerTabFadeEnabled() == false and CompactRaidFrameAccountDB.fadeManagerTab == false, "unticking saves it account-wide")
  H.RunUpdates(0.05, 5)
  check(m.tabAlpha == 1, "option off: tab always shown")
  H.RunUpdates(0.05, 30)
  check(m.tabAlpha == 1, "and stays shown")
  opt:Click()
  H.RunUpdates(0.05, 30)
  check(CRF_IsManagerTabFadeEnabled() == true and m.tabAlpha == 0, "ticking it again hides the tab")

  local divider = _G["CompactUnitFrameProfilesOptionsGeneralDivider"]
  local hpf = _G["CompactUnitFrameProfilesOptionsGeneralHidePlayerFrame"]
  local pets = _G["CompactUnitFrameProfilesOptionsGeneralDisplayPets"]
  local hpfB = select(1, H.vspan(hpf)); local divB, divT = H.vspan(divider); local petsT = select(2, H.vspan(pets))
  check(hpfB >= divT and divB >= petsT, "General tab: account options above the divider, profile options below it")

  section("Frame size percentages")
  _G["CompactUnitFrameProfilesOptionsTab2"]:Click()
  local hs = _G["CompactUnitFrameProfilesOptionsLayoutHeightSlider"]
  local ws = _G["CompactUnitFrameProfilesOptionsLayoutWidthSlider"]
  local hv, wv = hs.valueLabel, ws.valueLabel
  check(hv and hv:IsVisible() and wv and wv:IsVisible(), "both sliders show a value")
  local prof = GetActiveRaidProfile()
  check(hv:GetText() == string.format("%d%%", math.floor((GetRaidProfileOption(prof, "frameHeight") - 36) / 60 * 100 + 0.5)), "height shows the current profile's value (" .. tostring(hv:GetText()) .. ")")
  hs:SetValue(36);  check(hv:GetText() == "0%", "smallest height = 0%")
  hs:SetValue(96);  check(hv:GetText() == "100%", "largest height = 100%")
  hs:SetValue(66);  check(hv:GetText() == "50%", "height 66 = 50%")
  ws:SetValue(72);  check(wv:GetText() == "0%", "narrowest width = 0%")
  ws:SetValue(186); check(wv:GetText() == "100%", "widest width = 100%")
  ws:SetValue(130); check(wv:GetText() == "51%", "width 130 = 51%")
  ws:SetValue(129.4); check(ws:GetValue() == 129 and wv:GetText() == "50%", "width 129 = 50% (1px steps: every percentage can be picked)")
  local reachable = {}
  for v = 72, 186 do ws:SetValue(v); reachable[wv:GetText()] = true end
  local missing = {}
  for pc = 0, 100 do if not reachable[pc .. "%"] then missing[#missing+1] = pc end end
  check(#missing == 0, "width: all 101 percentages reachable" .. (#missing > 0 and (" (missing " .. table.concat(missing, ",") .. ")") or ""))
  hs:SetValue(65); check(hs:GetValue() == 65 and hv:GetText() == "48%", "height moves in 1px steps too (65 = 48%)")
  hs:SetValue(66); ws:SetValue(129)
  check(GetRaidProfileOption(prof, "frameHeight") == 66 and GetRaidProfileOption(prof, "frameWidth") == 129, "dragging still changes the profile")
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  local h0 = GetRaidProfileOption(prof, "frameHeight")
  check(hv:GetText() == string.format("%d%%", math.floor((h0 - 36) / 60 * 100 + 0.5)), "Cancel puts the number back with the slider")
  for _, s in ipairs({ hs, ws }) do
    local vl, vr = H.hspan(s.valueLabel); local ll, lr = H.hspan(s.minLabel); local rl, rr = H.hspan(s.maxLabel)
    check(vl > lr + 2 and vr < rl - 2, string.format("%s: number sits clear of '%s' and '%s'", s:GetName():match("Layout(%a+)Slider"), s.minLabel:GetText(), s.maxLabel:GetText()))
  end

  check(#H.errors == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  check(#H.blocked == 0, "nothing blocked")
  for i = 1, math.min(3, #H.blocked) do print("       blocked: " .. H.blocked[i]:gsub("\n", "\n         ")) end
  H.errors = {}
  H.blocked = {}
end
------------------------------------------------------------------------
if scenario == "all" or scenario == "features" then
  local m = CompactRaidFrameManager
  local df = m.displayFrame
  local container = CompactRaidFrameContainer
  local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 1) end
  local function unitFrames()   -- flush-mode unit frames in layout order
    local list = {}
    for _, o in ipairs(container.flowFrames) do if type(o) == "table" and o.unit then list[#list+1] = o end end
    return list
  end
  local function frameFor(unit)
    for _, f in ipairs(unitFrames()) do if f.unit == unit then return f end end
  end
  local function healthBottomInset(f)   -- distance of the health bar's bottom above the frame's bottom
    return select(1, H.vspan(f.healthBar)) - select(1, H.vspan(f))
  end
  local always = _G["CompactUnitFrameProfilesOptionsGeneralAlwaysShow"]
  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  if CRF_IsAlwaysEnabled() then always:Click() end
  H.setParty({}); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)

  ----------------------------------------------------------------------
  section("Display Incoming Heals")
  _G["CompactUnitFrameProfilesOptionsTab3"]:Click()
  local heals = _G["CompactUnitFrameProfilesOptionsDisplayDisplayHealPrediction"]
  check(heals and heals:IsVisible() and heals:GetChecked(), "Display tab: Display Incoming Heals, on by default")
  check(DefaultCompactUnitFrameOptions.displayHealPrediction == true, "applied to the frames")
  H.setParty({ { "Holy", "PRIEST", "HEALER" }, { "Prot", "WARRIOR", "TANK" } })
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local pf = frameFor("player")
  local origHeals = UnitGetIncomingHeals
  UnitGetIncomingHeals = function(unit, healer) return 3000 end
  CompactUnitFrame_UpdateHealPrediction(pf)
  check(pf.myHealPrediction:IsShown(), "incoming heal drawn while on")
  heals:Click()
  CompactUnitFrame_UpdateHealPrediction(pf)
  check(DefaultCompactUnitFrameOptions.displayHealPrediction == false and not pf.myHealPrediction:IsShown()
    and not pf.otherHealPrediction:IsShown() and not pf.totalAbsorb:IsShown(), "unticked: no incoming heals or absorbs")
  check(RaidProfileHasUnsavedChanges(), "it is a profile option (Save / Cancel)")
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  CompactUnitFrame_UpdateHealPrediction(pf)
  check(heals:GetChecked() and pf.myHealPrediction:IsShown(), "Cancel turns it back on")
  UnitGetIncomingHeals = origHeals

  ----------------------------------------------------------------------
  section("Display Only Healer Power Bars")
  local power = _G["CompactUnitFrameProfilesOptionsDisplayDisplayPowerBar"]
  local onlyHealer = _G["CompactUnitFrameProfilesOptionsDisplayDisplayOnlyHealerPowerBars"]
  check(not power:GetChecked() and onlyHealer:IsShown() and not CRF_IsButtonEnabled(onlyHealer), "sub-option greyed out while power bars are off")
  power:Click()
  check(CRF_IsButtonEnabled(onlyHealer) and not onlyHealer:GetChecked(), "usable once Display Power Bars is ticked")
  local healer, tank = frameFor("party1"), frameFor("party2")
  check(healer.powerBar:IsShown() and tank.powerBar:IsShown(), "power bars: everyone")
  onlyHealer:Click()
  healer, tank = frameFor("party1"), frameFor("party2")
  check(healer.powerBar:IsShown() and near(healthBottomInset(healer), 9), "only healers: the healer keeps the bar")
  check(not tank.powerBar:IsShown() and near(healthBottomInset(tank), 1), "the tank's health bar fills the frame instead")
  H.inCombat = true
  H.state.party[2].lfgRole = "HEALER"
  H.FireEvent("PLAYER_ROLES_ASSIGNED")
  H.RunUpdates(0.5, 6)
  check(tank.powerBar:IsShown() and near(healthBottomInset(tank), 9) and #H.blocked == 0, "role change in combat: bar appears, nothing blocked")
  H.state.party[2].lfgRole = "TANK"
  H.FireEvent("PLAYER_ROLES_ASSIGNED")
  H.RunUpdates(0.5, 6)
  check(not tank.powerBar:IsShown(), "and goes again")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")
  onlyHealer:Click(); power:Click()
  SaveRaidProfileCopy(GetActiveRaidProfile())

  ----------------------------------------------------------------------
  section("Display Power Bar Text")
  local prof = GetActiveRaidProfile()
  local ptd = _G["CompactUnitFrameProfilesOptionsDisplayPowerTextDropdown"]
  local htd = _G["CompactUnitFrameProfilesOptionsDisplayHealthTextDropdown"]
  local ptdButton = _G[ptd:GetName() .. "Button"]
  local ptdText = _G[ptd:GetName() .. "Text"]
  check(ptd:IsVisible() and ptd.label:GetText() == COMPACT_UNIT_FRAME_PROFILE_POWERTEXT, "Display tab: " .. tostring(ptd.label:GetText()))
  local hdb = select(1, H.vspan(htd)); local pdb, pdt = H.vspan(ptd); local plb, plt = H.vspan(ptd.label)
  local ob = select(1, H.vspan(CompactUnitFrameProfilesOptions))
  check(near(H.hspan(ptd), H.hspan(htd)) and pdt < hdb and plt < hdb + 4 and pdb > ob + 4,
    "under Display Health Text, its label clear of it, inside the options box")
  check(ptdText:GetText() == COMPACT_UNIT_FRAME_PROFILE_POWERTEXT_NONE and GetRaidProfileOption(prof, "powerText") == "none", "None by default")
  SetRaidProfileOption(prof, "powerText", nil); ptdText:SetText("?")
  CompactUnitFrameProfiles_UpdateCurrentPanel()
  check(ptdText:GetText() == COMPACT_UNIT_FRAME_PROFILE_POWERTEXT_NONE, "a profile without the setting shows None")
  SetRaidProfileOption(prof, "powerText", "none"); CompactUnitFrameProfiles_UpdateCurrentPanel()
  local widest, widestText = 0, ""
  for _, v in ipairs(ptd.options) do
    local t = _G["COMPACT_UNIT_FRAME_PROFILE_POWERTEXT_" .. strupper(v)]
    ptdText:SetText(t)
    if ptdText:GetStringWidth() > widest then widest, widestText = ptdText:GetStringWidth(), t end
  end
  CompactUnitFrameProfilesDropdown_Update(ptd)
  check(widest * 1.06 <= (ptd.width or 160) - 25, string.format("its entries fit the dropdown (widest %.0fpx: %s)", widest, widestText))
  check(ptd.__ddDisabled and not CRF_IsButtonEnabled(ptdButton) and ptd.label.__disabled, "greyed out while power bars are off")
  ptdButton:GetScript("OnEnter")(ptdButton)
  check(GameTooltip:IsShown() and GameTooltip.__tttext == CRF_REQUIRES_POWER_BARS, "hovering it says it needs power bars")
  ptdButton:GetScript("OnLeave")(ptdButton)
  check(not GameTooltip:IsShown(), "tooltip goes on leave")
  power:Click()
  check(not ptd.__ddDisabled and CRF_IsButtonEnabled(ptdButton) and not ptd.label.__disabled, "usable once Display Power Bars is ticked")
  ptdButton:GetScript("OnEnter")(ptdButton)
  check(not GameTooltip:IsShown(), "no tooltip while usable")
  local healer, tank, me = frameFor("party1"), frameFor("party2"), frameFor("player")
  check(healer.powerBar:IsShown() and near(healthBottomInset(healer), 9) and not healer.powerText:IsShown(), "None: the normal 8px bar, no text")
  H.pickDropDown(ptd, "power")
  healer, tank, me = frameFor("party1"), frameFor("party2"), frameFor("player")
  check(RaidProfileHasUnsavedChanges() and DefaultCompactUnitFrameOptions.powerText == "power", "a profile option (Save / Cancel)")
  check(near(healthBottomInset(healer), 17) and near(healthBottomInset(me), 17), "the power bar is twice as tall (16px)")
  check(healer.powerText:IsVisible() and tostring(healer.powerText:GetText()) == "5000", "Power Remaining: " .. tostring(healer.powerText:GetText()))
  local tb, tt = H.vspan(healer.powerText); local bb, bt = H.vspan(healer.powerBar)
  local tl, tr = H.hspan(healer.powerText); local bl, br = H.hspan(healer.powerBar)
  check(tb >= bb and tt <= bt and tl >= bl and tr <= br, string.format("the text sits inside the bar (%.0fpx text in a %.0fpx bar)", tt - tb, bt - bb))
  local sb = select(1, H.vspan(healer.statusText))
  check(sb >= bt, "the health text stays above the power bar")
  H.state.party[1].power = 4321
  H.FireEvent("UNIT_MANA", "party1")
  check(tostring(healer.powerText:GetText()) == "4321", "follows the power (4321)")
  H.pickDropDown(ptd, "perc")
  healer, tank = frameFor("party1"), frameFor("party2")
  check(healer.powerText:GetText() == "44%" and near(healthBottomInset(healer), 17), "Power Percentage: " .. tostring(healer.powerText:GetText()) .. " (4321 of 10000, rounded up like health)")
  H.state.party[1].maxPower = 8642
  H.FireEvent("UNIT_MAXMANA", "party1")
  check(healer.powerText:GetText() == "50%", "follows a new maximum (50%)")
  H.state.party[2].powerType = { 1, "RAGE" }; H.state.party[2].power = 30; H.state.party[2].maxPower = 100
  H.FireEvent("UNIT_DISPLAYPOWER", "party2")
  check(tank.powerText:GetText() == "30%", "rage: " .. tostring(tank.powerText:GetText()))
  H.state.party[2].maxPower = 120
  H.FireEvent("UNIT_MAXRAGE", "party2")
  check(tank.powerText:GetText() == "25%", "a new rage maximum (UNIT_MAXRAGE): " .. tostring(tank.powerText:GetText()))
  H.state.party[2].maxPower = 0
  H.FireEvent("UNIT_DISPLAYPOWER", "party2")
  check(not tank.powerText:IsShown(), "no power: no text")
  H.state.party[2].powerType, H.state.party[2].power, H.state.party[2].maxPower = nil, nil, nil
  H.FireEvent("UNIT_DISPLAYPOWER", "party2")
  H.state.party[1].dead = true
  H.FireEvent("UNIT_HEALTH", "party1")
  check(not healer.powerText:IsShown() and healer.statusText:GetText() == DEAD, "hidden while dead (the health text says Dead)")
  H.state.party[1].dead = nil
  H.FireEvent("UNIT_HEALTH", "party1")
  check(healer.powerText:IsShown(), "back when alive")
  H.state.party[1].offline = true
  CompactUnitFrame_UpdateAll(healer)
  check(not healer.powerText:IsShown() and healer.statusText:GetText() == PLAYER_OFFLINE, "hidden while offline")
  H.state.party[1].offline, H.state.party[1].power, H.state.party[1].maxPower = nil, nil, nil
  CompactUnitFrame_UpdateAll(healer)
  check(healer.powerText:GetText() == "50%", "back when online")

  -- short frames: the health text moves up clear of the tall bar
  SetRaidProfileOption(prof, "frameHeight", 36)
  CompactUnitFrameProfiles_ApplyCurrentSettings()
  healer = frameFor("party1")
  bb, bt = H.vspan(healer.powerBar); sb = select(1, H.vspan(healer.statusText))
  check(near(healthBottomInset(healer), 17) and sb >= bt, "36px frames: the health text stays above the 16px bar")
  check(healer.debuffFrames[1].maxHeight >= healer.debuffFrames[1].baseSize, "boss debuffs keep at least their normal size")

  -- only healers: the text goes with the bar; role changes in combat
  _G["CompactUnitFrameProfilesOptionsDisplayDisplayOnlyHealerPowerBars"]:Click()
  healer, tank = frameFor("party1"), frameFor("party2")
  check(healer.powerText:IsVisible() and not tank.powerBar:IsShown() and not tank.powerText:IsVisible(), "only healers: the tank has no bar and no text")
  H.inCombat = true
  H.state.party[2].lfgRole = "HEALER"
  H.FireEvent("PLAYER_ROLES_ASSIGNED")
  H.RunUpdates(0.5, 6)
  check(tank.powerBar:IsShown() and near(healthBottomInset(tank), 17) and tank.powerText:IsVisible() and #H.blocked == 0,
    "role change in combat: the tall bar and its text appear, nothing blocked")
  H.state.party[2].lfgRole = "TANK"
  H.FireEvent("PLAYER_ROLES_ASSIGNED")
  H.RunUpdates(0.5, 6)
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")

  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  healer = frameFor("party1")
  check(GetRaidProfileOption(prof, "powerText") == "none" and not GetRaidProfileOption(prof, "displayPowerBar")
    and ptdText:GetText() == COMPACT_UNIT_FRAME_PROFILE_POWERTEXT_NONE and ptd.__ddDisabled and not healer.powerBar:IsShown(),
    "Cancel: no power bars, None, dropdown greyed again")
  check(#H.errors == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end

  ----------------------------------------------------------------------
  do
  section("Health text centred in the box, buffs / debuffs in a strip under it")
  local prof = GetActiveRaidProfile()
  local function setSize(h, w)
    SetRaidProfileOption(prof, "frameHeight", h); SetRaidProfileOption(prof, "frameWidth", w)
  end
  setSize(66, 129)
  SetRaidProfileOption(prof, "healthText", "perc")
  SetRaidProfileOption(prof, "displayPowerBar", true)
  SetRaidProfileOption(prof, "powerText", "perc")
  CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  -- 8 buffs (own HoTs, externals) and 5 debuffs, 3 of them dispellable
  H.state.party[1].buffs = { { spellId = 61295 }, { spellId = 974 }, { spellId = 51945 }, { spellId = 2825, caster = "party2" },
    { spellId = 17, caster = "party2" }, { spellId = 871, caster = "party2" }, { spellId = 33206, caster = "party2" }, { spellId = 1022, caster = "party2" } }
  H.state.party[1].debuffs = { { spellId = 6788, type = "Magic", dispellable = true }, { spellId = 25771 },
    { spellId = 3, type = "Poison", dispellable = true }, { spellId = 4, type = "Disease", dispellable = true }, { spellId = 5 } }
  H.FireEvent("UNIT_AURA", "party1"); H.RunUpdates(0.05, 2)
  local function shownAuras(f)
    local list = {}
    for _, a in ipairs(f.buffFrames) do if a:IsShown() then list[#list + 1] = a end end
    for _, a in ipairs(f.debuffFrames) do if a:IsShown() then list[#list + 1] = a end end
    return list
  end
  local function boxReport(f, label, expectCentred)
    local hl, hr = H.hspan(f.healthBar); local hb, ht = H.vspan(f.healthBar)
    local tl, tr = H.hspan(f.statusText); local tb, tt = H.vspan(f.statusText)
    local nb = select(1, H.vspan(f.name))
    local auras = shownAuras(f)
    local inside, below, apart = true, true, true
    local size = auras[1] and select(2, H.vspan(auras[1])) - select(1, H.vspan(auras[1])) or 0
    for i, a in ipairs(auras) do
      local l, r = H.hspan(a); local b, t = H.vspan(a)
      inside = inside and l >= hl - 0.01 and r <= hr + 0.01 and b >= hb - 0.01 and t <= nb + 0.01
      below = below and t <= tb - 0.99
      for j = i + 1, #auras do
        local l2, r2 = H.hspan(auras[j]); local b2, t2 = H.vspan(auras[j])
        if l < r2 - 0.01 and l2 < r - 0.01 and b < t2 - 0.01 and b2 < t - 0.01 then apart = false end
      end
    end
    local centred = math.abs((tb + tt) / 2 - (hb + ht) / 2) < 0.5 and math.abs((tl + tr) / 2 - (hl + hr) / 2) < 0.5
    return { centred = centred, clearOfName = tt <= nb + 0.01, inside = inside, below = below, apart = apart,
      size = size, text = tt - tb, count = #auras, auraTop = auras[1] and select(2, H.vspan(auras[1])) or 0, nameBottom = nb, textBottom = tb }
  end
  local f = frameFor("party1")
  local r = boxReport(f)
  check(r.count == 6, "8 buffs and 5 debuffs on the unit: 3 of each shown (" .. r.count .. ")")
  check(r.centred and r.clearOfName, string.format("health text centred in the box (%.1fpx), clear of the name", r.text))
  check(r.inside and r.below and r.apart, string.format("6 auras of %.1fpx in a strip under the text: inside the box, not on the text, not on each other", r.size))
  local dl, dr = H.hspan(f.dispelDebuffFrames[1]); local db = select(1, H.vspan(f.dispelDebuffFrames[1]))
  check(f.dispelDebuffFrames[3]:IsShown() and db >= select(2, H.vspan(f.statusText)), "the 3 dispel markers stay in the name row, above the text")
  local ptb, ptt = H.vspan(f.powerText); local pbb, pbt = H.vspan(f.powerBar)
  check(math.abs((ptb + ptt) / 2 - (pbb + pbt) / 2) < 0.5, "power bar text centred in the power bar")
  local rc = f.ignoreParentAlpha.readyCheckIcon
  local rb, rt = H.vspan(rc)
  check(math.abs((rb + rt) / 2 - (select(1, H.vspan(f.statusText)) + select(2, H.vspan(f.statusText))) / 2) < 0.5 and rt <= r.nameBottom + 0.01,
    "ready check icon on the text, clear of the name")

  for _, case in ipairs({ { 66, 129, "perc", "none" }, { 66, 129, "health", true }, { 96, 186, "perc", "perc" }, { 50, 72, "perc", "none" } }) do
    setSize(case[1], case[2])
    SetRaidProfileOption(prof, "powerText", case[4] == true and "none" or case[4])
    SetRaidProfileOption(prof, "displayPowerBar", case[4] ~= true)
    SetRaidProfileOption(prof, "healthText", case[3])
    CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
    f = frameFor("party1"); r = boxReport(f)
    check(r.centred and r.clearOfName and r.inside and r.below and r.apart,
      string.format("%dx%d, %s: text %.1fpx centred, auras %.1fpx under it", case[2], case[1],
        case[4] == true and "no power bar" or ("power text " .. case[4]), r.text, r.size))
  end

  -- Display Health Text off: no number to avoid, so the auras keep their original size (below the name)
  setSize(66, 129); SetRaidProfileOption(prof, "displayPowerBar", true); SetRaidProfileOption(prof, "powerText", "perc")
  SetRaidProfileOption(prof, "healthText", "none")
  CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  f = frameFor("party1"); r = boxReport(f)
  check(near(r.size, 11 * min(66 / 36, 129 / 72)) and r.inside and r.apart, string.format("Health Text None: auras at their original %.1fpx, below the name", r.size))

  -- frames too short for three rows: the original arrangement (text under the name, auras over it)
  setSize(36, 72); SetRaidProfileOption(prof, "healthText", "perc"); SetRaidProfileOption(prof, "powerText", "none")
  CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  f = frameFor("party1"); r = boxReport(f)
  check(r.clearOfName and near(r.size, 11) and r.apart and r.textBottom >= select(1, H.vspan(f.healthBar)) - 0.01,
    string.format("36px frames: text %.1fpx under the name, auras at the original 11px", r.text))

  -- role change in combat (only healer power bars, with text): the box shrinks and everything re-fits
  setSize(66, 129); SetRaidProfileOption(prof, "powerText", "perc"); SetRaidProfileOption(prof, "displayOnlyHealerPowerBars", true)
  H.state.party[2].buffs = H.state.party[1].buffs; H.state.party[2].debuffs = H.state.party[1].debuffs
  CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  local tankF = frameFor("party2")
  H.FireEvent("UNIT_AURA", "party2"); H.RunUpdates(0.05, 2)
  local before = boxReport(tankF)
  H.inCombat = true
  H.state.party[2].lfgRole = "HEALER"
  H.FireEvent("PLAYER_ROLES_ASSIGNED"); H.RunUpdates(0.5, 6)
  local after = boxReport(tankF)
  check(tankF.powerBar:IsShown() and after.centred and after.below and after.apart and after.size < before.size and #H.blocked == 0,
    string.format("role change in combat: power bar appears, text re-centred, auras %.1f -> %.1fpx, nothing blocked", before.size, after.size))
  H.state.party[2].lfgRole = "TANK"
  H.FireEvent("PLAYER_ROLES_ASSIGNED"); H.RunUpdates(0.5, 6)
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED")
  H.state.party[1].buffs, H.state.party[1].debuffs, H.state.party[2].buffs, H.state.party[2].debuffs = nil, nil, nil, nil
  H.FireEvent("UNIT_AURA", "party1"); H.FireEvent("UNIT_AURA", "party2")
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  H.RunUpdates(0.05, 2)
  check(#H.errors == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  end

  ----------------------------------------------------------------------
  do
  section("Keep Me at the Top")
  local prof = GetActiveRaidProfile()
  local me = H.state.player
  local savedName = me.name
  local savedParty, savedRaid = H.state.party, H.state.raid
  me.name = "Kamakazedan"; me.lfgRole = "DAMAGER"
  SetRaidProfileOption(prof, "displayPets", false); SetRaidProfileOption(prof, "displayMainTankAndAssist", false)
  SetRaidProfileOption(prof, "keepGroupsTogether", false); SetRaidProfileOption(prof, "horizontalGroups", false)
  SetRaidProfileOption(prof, "sortBy", "role")
  CompactUnitFrameProfiles_ApplyCurrentSettings()
  _G["CompactUnitFrameProfilesOptionsTab2"]:Click()
  local pf = _G["CompactUnitFrameProfilesOptionsLayoutSortPlayerFirst"]
  local border = _G["CompactUnitFrameProfilesOptionsLayoutDisplayBorder"]
  check(pf:IsVisible() and pf:GetChecked() and GetRaidProfileOption(prof, "sortPlayerFirst") == true
    and pf.label:GetText() == COMPACT_UNIT_FRAME_PROFILE_SORTPLAYERFIRST, "Layout tab: " .. tostring(pf.label:GetText()) .. ", ticked for new profiles")
  local bb = select(1, H.vspan(border)); local pb = select(1, H.vspan(pf))
  local blr = select(2, H.hspan(border.label)); local pfl = H.hspan(pf); local plr = select(2, H.hspan(pf.label))
  local sbl = H.hspan(_G["CompactUnitFrameProfilesOptionsLayoutSortByDropdownLabel"])
  local orr = select(2, H.hspan(CompactUnitFrameProfilesOptions))
  check(near(pb, bb) and pfl > blr + 4 and math.abs((pfl + 4) - sbl) < 1 and plr <= orr - 4,
    string.format("next to Display Border, under Sort By, label inside the options box (ends at %.0f of %.0f)", plr, orr))
  pf:GetScript("OnEnter")(pf)
  check(GameTooltip:IsShown() and GameTooltip.__tttext == CRF_SORT_PLAYER_FIRST_TOOLTIP, "tooltip explains it")
  pf:GetScript("OnLeave")(pf)

  local function order()
    local t = {}
    for _, f in ipairs(unitFrames()) do t[#t + 1] = UnitName(f.unit) end
    return table.concat(t, ", ")
  end
  -- party: tank, healer, two dps, and me (dps)
  H.setParty({ { "Hatril", "PALADIN", "TANK" }, { "Aldra", "PRIEST", "HEALER" }, { "Ildary", "WARRIOR", "DAMAGER" }, { "Sokmigg", "WARLOCK" } })
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(order() == "Kamakazedan, Hatril, Aldra, Ildary, Sokmigg", "party, Sort By Role: me first, then tank, healer, dps: " .. order())
  pf:Click(); H.RunUpdates(0.05, 2)
  check(not GetRaidProfileOption(prof, "sortPlayerFirst") and order() == "Hatril, Aldra, Ildary, Kamakazedan, Sokmigg", "unticked: plain role order: " .. order())
  pf:Click(); H.RunUpdates(0.05, 2)
  SetRaidProfileOption(prof, "sortBy", "alphabetical"); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  check(order() == "Kamakazedan, Aldra, Hatril, Ildary, Sokmigg", "Sort By Alphabetical: me first: " .. order())
  SetRaidProfileOption(prof, "sortBy", "group"); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  check(order() == "Kamakazedan, Hatril, Aldra, Ildary, Sokmigg", "Sort By Group: me first (as before): " .. order())

  -- raid of 7, me in group 2 (5th in the raid)
  H.setRaid({ { "Tanky", "WARRIOR", 1 }, { "Healz", "PRIEST", 1 }, { "Rogi", "ROGUE", 1 }, { "Magi", "MAGE", 2 }, { "Bob", "WARLOCK", 2 }, { "Holy", "PALADIN", 2 } })
  H.state.raid[1].lfgRole = "TANK"; H.state.raid[2].lfgRole = "HEALER"; H.state.raid[6].lfgRole = "HEALER"
  me.subgroup = 2
  table.insert(H.state.raid, 5, me)
  SetRaidProfileOption(prof, "sortBy", "role"); CompactUnitFrameProfiles_ApplyCurrentSettings()
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(order() == "Kamakazedan, Tanky, Healz, Holy, Bob, Magi, Rogi", "raid, Combine Groups, Sort By Role: me first: " .. order())
  pf:Click(); H.RunUpdates(0.05, 2)
  check(order() == "Tanky, Healz, Holy, Bob, Kamakazedan, Magi, Rogi", "unticked: plain role order: " .. order())
  pf:Click(); H.RunUpdates(0.05, 2)
  SetRaidProfileOption(prof, "keepGroupsTogether", true); CompactUnitFrameProfiles_ApplyCurrentSettings()
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local function groupOrder(n)
    local t = {}
    for i = 1, 5 do local u = _G["CompactRaidGroup" .. n .. "Member" .. i].unit; if u then t[#t + 1] = UnitName(u) end end
    return table.concat(t, ", ")
  end
  check(groupOrder(2) == "Kamakazedan, Holy, Bob, Magi" and groupOrder(1) == "Tanky, Healz, Rogi",
    "raid, Separate Groups, Sort By Role: me first in my group, then by role (" .. groupOrder(2) .. "); group 1: " .. groupOrder(1))
  -- unticked in combat: secure frames wait for the end of combat
  H.inCombat = true; H.FireEvent("PLAYER_REGEN_DISABLED")
  pf:Click(); H.RunUpdates(0.05, 2)
  check(#H.blocked == 0 and groupOrder(2) == "Kamakazedan, Holy, Bob, Magi", "changed in combat: nothing blocked, order kept until combat ends")
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED"); H.RunUpdates(0.05, 2)
  check(groupOrder(2) == "Holy, Bob, Kamakazedan, Magi", "after combat: plain role order in my group (" .. groupOrder(2) .. ")")
  pf:Click(); H.RunUpdates(0.05, 2)
  check(groupOrder(2) == "Kamakazedan, Holy, Bob, Magi", "ticked again: me first")
  SetRaidProfileOption(prof, "sortBy", "group"); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  check(groupOrder(2) == "Kamakazedan, Magi, Bob, Holy", "Sort By Group: raid order in my group, me first (" .. groupOrder(2) .. ")")
  SetRaidProfileOption(prof, "sortBy", "role"); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  -- the party, kept separate (the "Party" frame): Sort By Role, me (a healer) first, then the tank
  H.state.party, H.state.raid = {}, {}
  me.lfgRole = "HEALER"
  H.setParty({ { "Kailani", "SHAMAN", "DAMAGER" }, { "Ellannysil", "WARRIOR", "TANK" }, { "Aherok", "SHAMAN", "DAMAGER" }, { "Mynamejeff", "HUNTER" } })
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local function partyOrder()
    local t = {}
    for i = 1, 5 do local f = _G["CompactPartyFrameMember" .. i]; if f.unit and UnitExists(f.unit) then t[#t + 1] = UnitName(f.unit) end end
    return table.concat(t, ", ")
  end
  check(partyOrder() == "Kamakazedan, Ellannysil, Aherok, Kailani, Mynamejeff", "party, Separate, Sort By Role: me, then the tank, then dps: " .. partyOrder())
  pf:Click(); H.RunUpdates(0.05, 2)
  check(partyOrder() == "Ellannysil, Kamakazedan, Aherok, Kailani, Mynamejeff", "unticked: tank, healer (me), dps: " .. partyOrder())
  pf:Click(); H.RunUpdates(0.05, 2)
  SetRaidProfileOption(prof, "sortBy", "group"); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  check(partyOrder() == "Kamakazedan, Kailani, Ellannysil, Aherok, Mynamejeff", "Sort By Group: party order: " .. partyOrder())
  SetRaidProfileOption(prof, "sortBy", "role"); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 2)
  -- someone joins in combat: they still show up (sorted when combat ends)
  H.state.party[4] = nil
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  H.inCombat = true; H.FireEvent("PLAYER_REGEN_DISABLED")
  H.state.party[4] = { name = "Zed", class = "WARRIOR", lfgRole = "TANK", guid = "0x104" }
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(#H.blocked == 0 and partyOrder():find("Zed"), "someone joins in combat: shown straight away (" .. partyOrder() .. ")")
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED"); H.RunUpdates(0.05, 2)
  check(partyOrder() == "Kamakazedan, Ellannysil, Zed, Aherok, Kailani", "after combat: sorted (" .. partyOrder() .. ")")

  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  me.name, me.lfgRole, me.subgroup = savedName, nil, nil
  H.state.party, H.state.raid = savedParty, savedRaid
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  _G["CompactUnitFrameProfilesOptionsTab3"]:Click()
  check(#H.errors == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  end

  ----------------------------------------------------------------------
  do
  section("Pets under their group (vertical groups)")
  local prof = GetActiveRaidProfile()
  local me = H.state.player
  local savedParty, savedRaid = H.state.party, H.state.raid
  local function petFrame(unit)
    local found
    CRF_ForEachCompactUnitFrame(function(f) if f.unit == unit and f:IsVisible() then found = f end end)
    return found
  end
  local function relayout()
    CompactUnitFrameProfiles_ApplyCurrentSettings()
    CRF_RelayGroupRosterUpdate(); H.FireEvent("UNIT_PET", "player"); H.RunUpdates(0.05, 2)
  end
  local function below(upper, lower)   -- lower's top meets upper's bottom, same left edge
    local ub = select(1, H.vspan(upper)); local lt = select(2, H.vspan(lower))
    return math.abs(ub - lt) < 0.5 and math.abs(H.hspan(upper) - H.hspan(lower)) < 0.5
  end
  me.pet = { name = "Kuplop", class = "WARLOCK" }
  H.setParty({ { "Hatril", "PALADIN", "TANK" }, { "Sokmigg", "WARLOCK" }, { "Hulgharun", "PRIEST", "HEALER" }, { "Rexxar", "HUNTER" } })
  H.state.party[2].pet = { name = "Imp", class = "WARLOCK" }
  H.state.party[4].pet = { name = "Misha", class = "HUNTER" }
  SetRaidProfileOption(prof, "keepGroupsTogether", true); SetRaidProfileOption(prof, "horizontalGroups", false)
  SetRaidProfileOption(prof, "displayPets", true); SetRaidProfileOption(prof, "displayBorder", false)
  relayout()
  local partyFrame = CompactPartyFrame
  local p1, p2, p3 = petFrame("pet"), petFrame("partypet2"), petFrame("partypet4")
  check(p1 and p2 and p3, "party, Separate (Vertical): 3 pets shown")
  check(p1 and below(_G["CompactPartyFrameMember5"], p1) and below(p1, p2) and below(p2, p3),
    "they stack under the party column: my pet, then party2's, then party4's")
  -- a party of two (you and one more) with a pet: the pet right under the second player, no gap
  local savedFull = H.state.party
  H.setParty({ { "Mynamejeff", "HUNTER" } })
  H.state.party[1].pet = { name = "MynameDan" }
  me.pet = nil
  relayout()
  local dan = petFrame("partypet1")
  check(dan and below(_G["CompactPartyFrameMember2"], dan), "party of 2: the pet right under the 2nd player (no room kept for 3 more)")
  local pfb, pft = H.vspan(CompactPartyFrame); local ttl = CompactPartyFrame.title:GetHeight()
  check(math.abs((pft - pfb) - (ttl + 2 * _G["CompactPartyFrameMember1"]:GetHeight())) < 0.5, "the party frame is as tall as its 2 players")
  H.setParty({ { "Mynamejeff", "HUNTER" }, { "Ildary", "WARRIOR" } }); H.state.party[1].pet = { name = "MynameDan" }
  relayout(); dan = petFrame("partypet1")
  check(dan and below(_G["CompactPartyFrameMember3"], dan), "someone joins: the pet moves down under the 3rd player")
  H.state.party = savedFull
  me.pet = { name = "Kuplop", class = "WARLOCK" }
  relayout()
  -- with a group border the group is wider: pets stay lined up with the members
  SetRaidProfileOption(prof, "displayBorder", true); relayout()
  p1 = petFrame("pet")
  check(p1 and math.abs(H.hspan(p1) - H.hspan(_G["CompactPartyFrameMember1"])) < 0.5 and select(2, H.vspan(p1)) <= select(1, H.vspan(_G["CompactPartyFrameMember5"])) + 0.5,
    "Display Border on: still under the members, lined up with them")
  SetRaidProfileOption(prof, "displayBorder", false)

  -- raid: groups 1-3, pets in groups 1 (two) and 3 (one), me in group 3
  H.setRaid({ { "Tanky", "WARRIOR", 1 }, { "Hunt", "HUNTER", 1 }, { "Lock", "WARLOCK", 1 }, { "Magi", "MAGE", 2 }, { "Priest", "PRIEST", 2 }, { "Rogi", "ROGUE", 3 } })
  H.state.raid[2].pet = { name = "Wolf" }; H.state.raid[3].pet = { name = "Felhunter" }
  me.subgroup = 3; table.insert(H.state.raid, me)   -- raid7, my pet is raidpet7
  relayout()
  local g1, g2, g3 = CompactRaidGroup1, CompactRaidGroup2, CompactRaidGroup3
  local wolf, fel, kup = petFrame("raidpet2"), petFrame("raidpet3"), petFrame("raidpet7")
  check(wolf and fel and kup and below(_G["CompactRaidGroup1Member3"], wolf) and below(wolf, fel), "raid: group 1's two pets right under its last (3rd) member")
  local g1b, g1t = H.vspan(g1); local m1b, m1t = H.vspan(_G["CompactRaidGroup1Member1"])
  check(math.abs((g1t - g1b) - (g1t - select(1, H.vspan(_G["CompactRaidGroup1Member3"])))) < 0.5, "group 1's frame ends at its last member (3 shown, not 5)")
  check(kup and math.abs(H.hspan(kup) - H.hspan(g3)) < 0.5 and math.abs(select(2, H.vspan(kup)) - select(1, H.vspan(g3))) < 0.5,
    "my pet under group 3 (group 2 has none: its column stays empty)")
  -- narrow container: 2 groups per line, each line followed by its pets
  local savedWidth = container:GetWidth()
  container:SetWidth(g1:GetWidth() * 2 + 10); relayout()
  wolf, kup = petFrame("raidpet2"), petFrame("raidpet7")
  local g3l = H.hspan(g3); local g3b, g3t = H.vspan(g3)
  check(math.abs(g3l - H.hspan(g1)) < 0.5 and g3t <= select(1, H.vspan(petFrame("raidpet3"))) + 0.5 and below(_G["CompactRaidGroup1Member3"], wolf),
    "groups on two lines: group 3 starts the second line, below group 1's pets")
  check(kup and math.abs(H.hspan(kup) - g3l) < 0.5 and math.abs(select(2, H.vspan(kup)) - g3b) < 0.5, "my pet under group 3 on its line")
  container:SetWidth(savedWidth)
  -- Keep Me at the Top: my pet first under my group
  H.state.raid[6].pet = { name = "Spider" }      -- Rogi has no pet really, but the order shows
  relayout()
  kup = petFrame("raidpet7"); local spider = petFrame("raidpet6")
  check(kup and spider and _G["CompactRaidGroup3Member1"].unit == "raid7" and below(_G["CompactRaidGroup3Member2"], kup) and below(kup, spider),
    "Keep Me at the Top: my pet first, right under my group's last (2nd) member")
  H.state.raid[6].pet = nil
  -- Separate (Horizontal): each group's pets in a row under it, before the next group
  SetRaidProfileOption(prof, "horizontalGroups", true); relayout()
  wolf, fel, kup = petFrame("raidpet2"), petFrame("raidpet3"), petFrame("raidpet7")
  local function under(upper, lower) return math.abs(select(1, H.vspan(upper)) - select(2, H.vspan(lower))) < 0.5 end
  local function leftOf(a, b) return math.abs(select(2, H.hspan(a)) - H.hspan(b)) < 0.5 and math.abs(select(2, H.vspan(a)) - select(2, H.vspan(b))) < 0.5 end
  check(wolf and fel and under(g1, wolf) and math.abs(H.hspan(wolf) - H.hspan(_G["CompactRaidGroup1Member1"])) < 0.5 and leftOf(wolf, fel),
    "Separate (Horizontal): group 1's pets in a row right under group 1")
  check(under(wolf, g2) and kup and under(g3, kup) and math.abs(H.hspan(kup) - H.hspan(g3)) < 0.5,
    "group 2 follows straight after them (no pets: no row); my pet under group 3")
  -- short container: a group and its pet row move to the next column together
  local rf = CompactRaidFrameManager.containerResizeFrame
  local savedRF = rf:GetHeight()
  local g1b, g1t = H.vspan(g1)
  local wb, wt = H.vspan(wolf)
  rf:SetHeight((g1t - g1b) * 2 + (wt - wb) + 5 + 14)    -- group 1, its pets and group 2; not group 3 with its pets
  CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(CompactRaidFrameManager)
  CompactRaidFrameContainer_TryUpdate(container); H.RunUpdates(0.05, 2)
  wolf, kup = petFrame("raidpet2"), petFrame("raidpet7")
  check(under(g1, wolf) and under(wolf, g2) and kup and under(g3, kup) and H.hspan(g3) > H.hspan(g1) + 1
    and math.abs(select(2, H.vspan(g3)) - select(2, H.vspan(g1))) < 0.5,
    string.format("short container: group 3 wraps to the top of the next column with its pets (x %.0f)", H.hspan(g3) - H.hspan(container)))
  rf:SetHeight(savedRF)
  CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(CompactRaidFrameManager)
  relayout()
  -- party, Separate (Horizontal): the party's pets in a row under it
  H.state.party, H.state.raid = {}, {}
  H.setParty({ { "Sokmigg", "WARLOCK" }, { "Rexxar", "HUNTER" } })
  H.state.party[1].pet = { name = "Imp" }; H.state.party[2].pet = { name = "Misha" }
  relayout()
  p1, p2, p3 = petFrame("pet"), petFrame("partypet1"), petFrame("partypet2")
  check(p1 and p2 and p3 and under(CompactPartyFrame, p1) and leftOf(p1, p2) and leftOf(p2, p3)
    and math.abs(H.hspan(p1) - H.hspan(_G["CompactPartyFrameMember1"])) < 0.5, "party, Separate (Horizontal): my pet, then party1's and party2's in a row under the party")
  -- back to the raid
  H.setRaid({ { "Tanky", "WARRIOR", 1 }, { "Hunt", "HUNTER", 1 }, { "Lock", "WARLOCK", 1 }, { "Magi", "MAGE", 2 }, { "Priest", "PRIEST", 2 }, { "Rogi", "ROGUE", 3 } })
  H.state.raid[2].pet = { name = "Wolf" }; H.state.raid[3].pet = { name = "Felhunter" }
  table.insert(H.state.raid, me)
  -- combined groups: pets after the players, as before
  SetRaidProfileOption(prof, "horizontalGroups", false); SetRaidProfileOption(prof, "keepGroupsTogether", false); relayout()
  local last = unitFrames()[7]
  wolf = petFrame("raidpet2")
  check(wolf and below(last, wolf), "Combine (Vertical): pets carry on under the last player")
  SetRaidProfileOption(prof, "horizontalGroups", true); relayout()
  local firstPet = petFrame("raidpet2")
  check(firstPet and select(2, H.vspan(firstPet)) <= select(1, H.vspan(unitFrames()[7])) + 0.5 or (firstPet and math.abs(select(2, H.vspan(firstPet)) - select(2, H.vspan(unitFrames()[7]))) < 0.5),
    "Combine (Horizontal): pets carry on after the last player (5 to a row)")
  SetRaidProfileOption(prof, "horizontalGroups", false)
  -- a pet dismissed: its frame goes
  SetRaidProfileOption(prof, "keepGroupsTogether", true); relayout()
  H.state.raid[2].pet = nil; relayout()
  check(not petFrame("raidpet2") and petFrame("raidpet3") and below(_G["CompactRaidGroup1Member3"], petFrame("raidpet3")), "a pet dismissed: the next one moves up")

  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  me.pet, me.subgroup = nil, nil
  H.state.party, H.state.raid = savedParty, savedRaid
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(#H.errors == 0 and #H.blocked == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  end

  ----------------------------------------------------------------------
  section("Hide player frame when raid frames are shown")
  local hpf = _G["CompactUnitFrameProfilesOptionsGeneralHidePlayerFrame"]
  _G["CompactUnitFrameProfilesOptionsTab1"]:Click()
  check(hpf and hpf:IsVisible() and hpf:GetChecked() and CRF_IsHidePlayerFrameEnabled(), "General tab option, on by default")
  check(not PlayerFrame:IsShown(), "party with raid frames: player frame hidden")
  check(TotemFrame:GetParent() == PlayerFrame and not TotemFrame:IsVisible(), "totem bar hidden with it (part of the player frame)")
  local raidStyle = _G["CompactUnitFrameProfilesOptionsGeneralRaidStylePartyFrames"]
  raidStyle:Click()
  local tp, trel, trp, tx, ty = TotemFrame:GetPoint(1)
  check(GetDisplayedAllyFrames() == "party" and PlayerFrame:IsShown() and TotemFrame:GetParent() == PlayerFrame
    and tp == "TOPLEFT" and trel == PlayerFrame and trp == "BOTTOMLEFT" and tx == 99 and ty == 38 and RuneFrame:GetParent() == PlayerFrame,
    "Blizzard party frames: player frame shown, totems and runes back where they were")
  raidStyle:Click()
  check(not PlayerFrame:IsShown(), "raid-style again: hidden")
  H.setParty({}); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(PlayerFrame:IsShown(), "solo (Always show off): shown")
  always:Click()
  check(not PlayerFrame:IsShown(), "solo with Always show: hidden")
  always:Click()
  H.inCombat = true
  H.setParty({ { "Arthas", "DEATHKNIGHT" } }); H.FireEvent("PARTY_MEMBERS_CHANGED"); H.RunUpdates(0.05, 2)
  check(not PlayerFrame:IsShown() and #H.blocked == 0, "joining a group in combat: hidden by the secure driver")
  H.setParty({}); H.FireEvent("PARTY_MEMBERS_CHANGED"); H.RunUpdates(0.05, 2)
  check(PlayerFrame:IsShown() and #H.blocked == 0, "leaving in combat: shown again")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")
  H.setRaid({ { "Kami", "PALADIN", 1 }, { "Jaina", "MAGE", 1 } }); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(not PlayerFrame:IsShown(), "raid: hidden")
  df.hiddenModeToggle:Click()
  check(not container:IsVisible() and PlayerFrame:IsShown(), "raid frames hidden with the manager's Hide: player frame back")
  df.hiddenModeToggle:Click()
  check(container:IsVisible() and not PlayerFrame:IsShown(), "Show: hidden again")
  hpf:Click()
  check(CompactRaidFrameAccountDB.hidePlayerFrame == false and PlayerFrame:IsShown() and not (PlayerFrame.__stateDrivers or {}).visibility, "option off: shown, driver removed")
  hpf:Click()
  check(not PlayerFrame:IsShown(), "on again: hidden")

  ----------------------------------------------------------------------
  section("Resting shows on your own frame")
  do
  local me = H.state.player
  local savedParty, savedRaid = H.state.party, H.state.raid
  local function near(a, b) return a and b and math.abs(a - b) < 0.05 end
  local function frameFor(match)
    local found
    CRF_ForEachCompactUnitFrame(function(f) if not found and f.unit and f:IsVisible() and match(f.unit) then found = f end end)
    return found
  end
  local function ownFrame() return frameFor(function(u) return UnitIsUnit(u, "player") and not u:find("pet") end) end
  local function overlaps(a, b)
    local al, ar = H.hspan(a); local ab, at = H.vspan(a)
    local bl, br = H.hspan(b); local bb, bt = H.vspan(b)
    return al < br - 0.01 and bl < ar - 0.01 and ab < bt - 0.01 and bb < at - 0.01
  end
  local opt = _G["CompactUnitFrameProfilesOptionsGeneralShowResting"]
  local divT = select(2, H.vspan(_G["CompactUnitFrameProfilesOptionsGeneralDivider"]))
  check(opt and opt:GetChecked() and select(1, H.vspan(opt)) >= divT and CRF_IsShowRestingEnabled(),
    "General tab: \"Show resting on your frame\", on by default, with the account options")
  H.setParty({ { "Helga", "ROGUE" } })
  H.state.party[1].debuffs = { { spellId = 7321, type = "Magic" } }
  CompactUnitFrameProfiles_ApplyCurrentSettings(); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local own, other = ownFrame(), frameFor(function(u) return u == "party1" end)
  check(own and other and not own.restGlow:IsShown() and not own.restIcon:IsShown(), "not resting: nothing")
  H.state.resting = true; H.FireEvent("PLAYER_UPDATE_RESTING"); H.RunUpdates(0.05, 1)
  check(own.restGlow:IsVisible() and own.restIcon:IsVisible() and not other.restGlow:IsShown() and not other.restIcon:IsShown(),
    "resting (an inn or a city): the glow and the zzz on my frame only")
  local v = own.restGlow.__vertex
  check(v and near(v[1], 1) and near(v[2], 0.88) and near(v[3], 0.25) and own.restGlow:GetTexture() == own.aggroHighlight:GetTexture(),
    "the glow: the aggro glow's art in the player frame's rested gold")
  local fl, fr = H.hspan(own); local fb, ft = H.vspan(own)
  local il, ir = H.hspan(own.restIcon); local ib, it = H.vspan(own.restIcon)
  check(own.restIcon:GetTexture() == "Interface\\CharacterFrame\\UI-StateIcon" and near(ir - il, 12) and near(it - ib, 12)
    and near(ir, fr - 3) and near(it, ft - 2), "the zzz: Blizzard's rest icon, as big as the role icon, in the top right corner")
  local lo, hi = 1, 0
  for _ = 1, 30 do H.RunUpdates(0.05, 1); local a = own.restGlow:GetAlpha(); lo = math.min(lo, a); hi = math.max(hi, a) end
  check(lo < 0.3 and hi > 0.95, string.format("it pulses like the player frame (%.2f to %.2f each second)", lo, hi))
  me.debuffs = { { spellId = 7321, type = "Magic" } }
  H.FireEvent("UNIT_AURA", "player"); H.RunUpdates(0.05, 1)
  local mine, theirs = own.dispelDebuffFrames[1], other.dispelDebuffFrames[1]
  check(mine:IsShown() and not overlaps(mine, own.restIcon) and select(2, H.hspan(mine)) <= il + 0.05 and near(select(2, H.hspan(theirs)), select(2, H.hspan(other)) - 3),
    "a dispel type icon on my frame moves left of the zzz (others stay in the corner)")
  H.inCombat = true
  H.state.resting = nil; H.FireEvent("PLAYER_UPDATE_RESTING"); H.RunUpdates(0.05, 1)
  check(not own.restGlow:IsShown() and not own.restIcon:IsShown() and near(select(2, H.hspan(mine)), fr - 3) and #H.blocked == 0,
    "no longer resting (in combat here): both go, the dispel icon moves back, nothing blocked")
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED")
  H.state.resting = true; H.FireEvent("PLAYER_UPDATE_RESTING"); H.RunUpdates(0.05, 1)
  -- hitting a training dummy in a city: resting and on its threat list
  H.inCombat = true; me.threat = 3; H.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "player"); H.RunUpdates(0.05, 1)
  check(own.aggroHighlight:IsShown() and not own.restGlow:IsShown() and own.restIcon:IsVisible(),
    "aggro while resting (a training dummy in a city): the aggro glow shows instead, the zzz stays")
  me.threat = nil; H.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "player"); H.RunUpdates(0.05, 1)
  check(not own.aggroHighlight:IsShown() and own.restGlow:IsVisible() and #H.blocked == 0, "aggro gone: the rest glow is back")
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED")
  opt:Click(); H.RunUpdates(0.05, 1)
  check(CRF_IsShowRestingEnabled() == false and not own.restGlow:IsShown() and not own.restIcon:IsShown(), "option off: nothing while resting")
  opt:Click(); H.RunUpdates(0.05, 1)
  check(CRF_IsShowRestingEnabled() and own.restGlow:IsVisible() and own.restIcon:IsVisible(), "on again: back")
  -- raid: my frame shows a raidN token
  H.setRaid({ { "Tanky", "WARRIOR", 1 }, { "Hunt", "HUNTER", 1 } }); me.subgroup = 1; table.insert(H.state.raid, me)
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  own = ownFrame()
  local others = 0
  CRF_ForEachCompactUnitFrame(function(f) if f ~= own and f:IsVisible() and f.restGlow and f.restGlow:IsShown() then others = others + 1 end end)
  check(own and own.unit:find("^raid") and own.restGlow:IsVisible() and own.restIcon:IsVisible() and others == 0, "in a raid: on my frame (" .. tostring(own and own.unit) .. ") only")
  -- raid size preview: every placeholder shows me, none of them glow
  CRF_SetRaidPreviewSize(10); H.RunUpdates(0.05, 2)
  local glowing = 0
  CRF_ForEachCompactUnitFrame(function(f) if f:IsVisible() and f.restGlow and f.restGlow:IsShown() then glowing = glowing + 1 end end)
  check(glowing == 0, "not on raid size preview placeholders")
  CRF_SetRaidPreviewSize(nil); H.RunUpdates(0.05, 2)
  own = ownFrame()
  check(own and own.restGlow:IsVisible(), "back on my frame after the preview")
  check(#H.errors == 0 and #H.blocked == 0, "no Lua errors, nothing blocked")
  for _, e in ipairs(H.errors) do print("     " .. e) end
  H.errors = {}; H.blocked = {}
  H.state.resting = nil; me.debuffs = nil; me.subgroup = nil
  H.state.party, H.state.raid = savedParty, savedRaid
  H.FireEvent("PLAYER_UPDATE_RESTING"); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  end

  ----------------------------------------------------------------------
  section("Dispellable debuffs follow the spells you have learned")
  do
  local prof = GetActiveRaidProfile()
  local me = H.state.player
  local savedParty, savedClass, savedBook = H.state.party, me.class, H.state.spellbook
  H.setParty({ { "Helga", "ROGUE" } })
  H.state.party[1].debuffs = { { spellId = 7321, type = "Magic" }, { spellId = 3, type = "Poison" }, { spellId = 4, type = "Disease" },
    { spellId = 5, type = "Curse" }, { spellId = 6 } }
  SetRaidProfileOption(prof, "displayOnlyDispellableDebuffs", true)
  CompactUnitFrameProfiles_ApplyCurrentSettings(); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local function helga()
    local found
    CRF_ForEachCompactUnitFrame(function(f) if f.unit == "party1" and f:IsVisible() then found = f end end)
    return found
  end
  local function shown(f)       -- debuff types shown, and the dispel type icons
    local debuffs, icons = {}, {}
    for _, d in ipairs(f.debuffFrames) do
      if d:IsShown() then debuffs[#debuffs + 1] = select(5, UnitDebuff(f.displayedUnit, d:GetID(), d.filter)) or "none" end
    end
    for _, d in ipairs(f.dispelDebuffFrames) do
      if d:IsShown() then icons[#icons + 1] = (d.icon:GetTexture() or ""):match("Debuff(%a+)$") end
    end
    return table.concat(debuffs, ","), table.concat(icons, ",")
  end
  local function learn(class, book, pet)
    me.class = class; H.state.spellbook = book; H.state.petSpellbook = pet
    H.FireEvent("SPELLS_CHANGED"); H.RunUpdates(0.05, 1)
  end
  local f = helga()
  local d, i = shown(f)
  check(d == "Magic,Poison,Disease" and i == "Magic,Poison,Disease", "a paladin with Cleanse: magic, poison and disease (3 shown), with their type icons")
  learn("PRIEST", { 6603, 2050 })
  d, i = shown(f)
  check(d == "" and i == "", "a priest who hasn't learned a dispel yet: none of them (the game's filter goes by class)")
  learn("PRIEST", { 6603, 2050, 528 })
  d, i = shown(f)
  check(d == "Disease" and i == "Disease", "learns Cure Disease: the disease")
  learn("PRIEST", { 6603, 2050, 528, 527 })
  d, i = shown(f)
  check(d == "Magic,Disease" and i == "Magic,Disease", "learns Dispel Magic: magic too (Chilled)")
  local icon = f.dispelDebuffFrames[1]
  icon:GetScript("OnEnter")(icon)
  local t = GameTooltip.__debuff
  check(t and t.filter == nil and select(5, UnitDebuff(t.unit, t.index)) == "Magic", "a type icon's tooltip shows that debuff")
  SetRaidProfileOption(prof, "displayOnlyDispellableDebuffs", false); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 1)
  d, i = shown(f)
  check(d == "Magic,Poison,Disease" and i == "Magic,Disease", "option off: debuffs whatever their type, type icons still only what you can dispel")
  SetRaidProfileOption(prof, "displayOnlyDispellableDebuffs", true); CompactUnitFrameProfiles_ApplyCurrentSettings(); H.RunUpdates(0.05, 1)
  learn("SHAMAN", { 6603, 526 })
  d, i = shown(f)
  check(d == "Poison,Disease" and i == "Poison,Disease", "a shaman with Cure Toxins: poison and disease")
  learn("SHAMAN", { 6603, 51886 })
  d, i = shown(f)
  check(d == "Poison,Disease,Curse" and i == "Poison,Disease,Curse", "with the Cleanse Spirit talent: curses too")
  learn("WARLOCK", { 6603 })
  d, i = shown(f)
  check(d == "" and i == "", "a warlock with no pet: none")
  H.state.petSpellbook = { 19505 }; H.FireEvent("UNIT_PET", "player"); H.RunUpdates(0.05, 1)
  d, i = shown(f)
  check(d == "Magic" and i == "Magic", "a Felhunter out (Devour Magic): magic")
  H.inCombat = true
  H.state.petSpellbook = nil; H.FireEvent("UNIT_PET", "player"); H.RunUpdates(0.05, 1)
  d, i = shown(f)
  check(d == "" and i == "" and #H.blocked == 0, "the Felhunter dismissed in combat: gone straight away, nothing blocked")
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED")
  check(#H.errors == 0 and #H.blocked == 0, "no Lua errors, nothing blocked")
  for _, e in ipairs(H.errors) do print("     " .. e) end
  H.errors = {}; H.blocked = {}
  learn(savedClass, savedBook, nil)
  H.state.party = savedParty
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  end

  ----------------------------------------------------------------------
  section("Totem and rune boxes under your own raid frame")
  do
  local bar = CompactRaidFrameClassBar
  local prof = GetActiveRaidProfile()
  local me = H.state.player
  local savedParty, savedRaid, savedClass, savedName = H.state.party, H.state.raid, me.class, me.name
  local function near(a, b) return a and b and math.abs(a - b) < 0.05 end
  local function shownFrames()
    local list = {}
    CRF_ForEachCompactUnitFrame(function(f) if f.unit and f:IsVisible() and UnitExists(f.unit) then list[#list + 1] = f end end)
    return list
  end
  local function ownFrame()
    for _, f in ipairs(shownFrames()) do
      if UnitIsUnit(f.unit, "player") and not f.unit:find("pet") then return f end
    end
  end
  local function overlaps(a, b)
    local al, ar = H.hspan(a); local ab, at = H.vspan(a)
    local bl, br = H.hspan(b); local bb, bt = H.vspan(b)
    return al < br - 0.01 and bl < ar - 0.01 and ab < bt - 0.01 and bb < at - 0.01
  end
  local function shownBoxes()
    local list = {}
    for i = 1, bar.count or 0 do if bar.boxes[i]:IsVisible() then list[#list + 1] = bar.boxes[i] end end
    return list
  end
  -- right under my frame (touching it, from its left edge), the boxes touching
  -- each other, inside my frame's width, over no frame
  local function barPlaced(own)
    own = own or ownFrame()
    if not (own and bar:IsVisible() and bar:GetParent() == own) then return false end
    local ol, orr = H.hspan(own); local ob = H.vspan(own)
    local bl = H.hspan(bar); local bb, bt = H.vspan(bar)
    if not (near(bl, ol) and near(bt, ob)) then return false end
    for _, f in ipairs(shownFrames()) do if overlaps(bar, f) then return false end end
    local x = ol
    for _, box in ipairs(shownBoxes()) do
      local l, r = H.hspan(box); local b, t = H.vspan(box)
      if not (near(l, x) and near(t, bt) and near(b, bb) and r <= orr + 0.05) then return false end
      x = r
    end
    return true
  end
  -- top of the nearest frame under mine (overlapping it sideways)
  local function nextBelow(own)
    own = own or ownFrame()
    local ol, orr = H.hspan(own); local ob = H.vspan(own)
    local top
    for _, f in ipairs(shownFrames()) do
      local l, r = H.hspan(f); local b, t = H.vspan(f)
      if f ~= own and l < orr - 0.01 and ol < r - 0.01 and t <= ob + 0.01 then top = math.max(top or t, t) end
    end
    return top
  end
  local function room() return bar:GetHeight() end
  local function relayout()
    CompactUnitFrameProfiles_ApplyCurrentSettings()
    CRF_RelayGroupRosterUpdate(); H.FireEvent("UNIT_PET", "player"); H.RunUpdates(0.05, 2)
  end
  local function layout(key)
    for _, l in ipairs(CRF_GROUP_LAYOUTS) do if l.key == key then CRF_SetGroupLayout(prof, l) end end
    relayout()
  end
  local function flush(upper, lower) return near(select(2, H.vspan(lower)), (H.vspan(upper))) end
  local function totem(slot, name, left, duration)
    H.state.totems = H.state.totems or {}
    duration = duration or 300
    H.state.totems[slot] = { name = name, start = H.now - (duration - left), duration = duration, icon = "Interface\\Icons\\" .. name }
    H.FireEvent("PLAYER_TOTEM_UPDATE", slot); H.RunUpdates(0.05, 1)
  end

  H.setParty({ { "Avede", "WARLOCK" }, { "Hatril", "PALADIN", "TANK" }, { "Hulgharun", "PRIEST", "HEALER" } })
  SetRaidProfileOption(prof, "displayPets", false); SetRaidProfileOption(prof, "displayBorder", false)
  SetRaidProfileOption(prof, "frameWidth", 129); SetRaidProfileOption(prof, "frameHeight", 66)
  layout("separateVertical")
  local m1, m2, m3 = CompactPartyFrameMember1, CompactPartyFrameMember2, CompactPartyFrameMember3
  check(not bar:IsVisible() and flush(m1, m2), "a paladin: no boxes, no room (frames as before)")

  me.class = "SHAMAN"; CRF_UpdateClassBarRoom(); H.RunUpdates(0.05, 2)
  check(not bar:IsVisible() and flush(m1, m2), "a shaman with no totems down: no boxes, no placeholders, no room")
  totem(2, "Spell_Nature_EarthBindTotem", 300)
  local own = ownFrame()
  local earth, fire, water, air = bar.boxes[1], bar.boxes[2], bar.boxes[3], bar.boxes[4]
  check(own == m1 and barPlaced() and #shownBoxes() == 1 and shownBoxes()[1] == earth, "a totem down: its box appears, right under my frame at its left edge")
  check(near(earth:GetWidth(), 20) and near(earth:GetHeight(), 20) and near(room(), 20), "20px boxes at the default frame size, and exactly that much room")
  check(near(select(2, H.vspan(m2)), H.vspan(m1) - room()) and flush(m2, m3), "the players below moved down by the room, touching the boxes")
  local pfb, pft = H.vspan(CompactPartyFrame)
  check(near(pft - pfb, CompactPartyFrame.title:GetHeight() + 4 * 66 + room()), "the party frame is taller by it")
  check(earth.icon:IsVisible() and earth.icon:GetTexture() == "Interface\\Icons\\Spell_Nature_EarthBindTotem" and earth.timer:GetText() == "5m"
    and earth.cooldown:IsVisible(), "the totem's icon, sweep and time left")
  check(TotemFrame:GetParent() == PlayerFrame and not TotemFrame:IsVisible(), "Blizzard's totem bar stays hidden with the player frame")
  totem(1, "Spell_Nature_GuardianWard", 10)
  check(barPlaced() and #shownBoxes() == 2 and shownBoxes()[1] == earth and shownBoxes()[2] == fire and fire.timer:GetText() == "10",
    "a second totem: side by side in the totem bar's order (earth, fire), touching")
  totem(4, "Spell_Nature_Windfury", 130)
  check(barPlaced() and #shownBoxes() == 3 and shownBoxes()[3] == air and not water:IsVisible() and air.timer:GetText() == "3m",
    "no box for an empty slot: earth, fire, air")
  H.RunUpdates(1, 5)
  check(fire.timer:GetText() == "5" and earth.timer:GetText() == "5m", "the time counts down")
  H.RunUpdates(1, 6)
  check(barPlaced() and #shownBoxes() == 2 and shownBoxes()[1] == earth and shownBoxes()[2] == air, "a totem running out: its box goes, the rest close up")
  earth:GetScript("OnEnter")(earth)
  check(GameTooltip.__totem == 2 and GameTooltip:IsOwned(earth), "hovering a totem: its tooltip")
  earth:GetScript("OnLeave")(earth)
  earth:Click("LeftButton")
  check(#H.destroyedTotems == 0, "left-click: nothing")
  earth:Click("RightButton"); H.FireEvent("PLAYER_TOTEM_UPDATE", 2)
  check(H.destroyedTotems[1] == 2 and #shownBoxes() == 1 and shownBoxes()[1] == air and barPlaced(), "right-click: destroys that totem (earth); air moves up")
  air:Click("RightButton"); H.FireEvent("PLAYER_TOTEM_UPDATE", 4); H.RunUpdates(0.05, 1)
  check(not bar:IsVisible() and flush(m1, m2), "the last totem gone (out of combat): boxes and room go, the frames close up")

  -- combat: the room is made as it starts, frames don't move during it
  H.FireEvent("PLAYER_REGEN_DISABLED"); H.inCombat = true; H.RunUpdates(0.05, 1)
  check(bar:IsVisible() and #shownBoxes() == 0 and near(select(2, H.vspan(m2)), H.vspan(m1) - room()), "combat starts: the room is made (frames can't move once it's on)")
  totem(3, "Spell_Nature_ManaRegenTotem", 5)
  H.setParty({ { "Avede", "WARLOCK" }, { "Hatril", "PALADIN", "TANK" }, { "Hulgharun", "PRIEST", "HEALER" }, { "Ildary", "WARRIOR" } })
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(barPlaced(m1) and #shownBoxes() == 1 and water.timer:GetText() == "5" and #H.blocked == 0, "a totem in combat: its box in the room (someone joins too), nothing blocked")
  H.RunUpdates(1, 6)
  check(bar:IsVisible() and #shownBoxes() == 0 and near(select(2, H.vspan(m2)), H.vspan(m1) - room()) and #H.blocked == 0,
    "it runs out in combat: the box goes, the room stays until combat ends")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED"); H.RunUpdates(0.05, 2)
  check(not bar:IsVisible() and flush(m1, m2) and flush(m3, CompactPartyFrameMember4) and CompactPartyFrameMember5:IsVisible(),
    "combat ends with nothing up: the room goes (the new member laid out too)")
  H.FireEvent("PLAYER_REGEN_DISABLED"); H.inCombat = true; totem(2, "Spell_Nature_StoneSkinTotem", 120)
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED"); H.RunUpdates(0.05, 2)
  check(barPlaced() and #shownBoxes() == 1 and near(select(2, H.vspan(m2)), H.vspan(m1) - room()), "combat ends with a totem still down: the room stays")

  -- the four layouts, with pets
  H.state.party[1].pet = { name = "Kraktast", class = "WARLOCK" }
  SetRaidProfileOption(prof, "displayPets", true)
  totem(2, "Spell_Nature_EarthBindTotem", 300)
  for _, key in ipairs({ "separateVertical", "separateHorizontal", "combineVertical", "combineHorizontal" }) do
    layout(key)
    own = ownFrame()
    local below = nextBelow(own)
    local exact = (key == "separateVertical" or key == "combineVertical")
    check(barPlaced(own) and below and (exact and near(below, H.vspan(own) - room()) or (not exact and below <= H.vspan(own) - room() + 0.05)),
      key .. ": the box under my frame, whatever is under me moved down")
  end
  layout("separateHorizontal")
  local gb, gt = H.vspan(CompactPartyFrame)
  check(near(gt - gb, CompactPartyFrame.title:GetHeight() + 66 + room()), "separateHorizontal: the row is taller by the room")
  SetRaidProfileOption(prof, "displayPets", false)

  -- raid: me in group 2
  local raid = { { "Tanky", "WARRIOR", 1 }, { "Hunt", "HUNTER", 1 }, { "Lock", "WARLOCK", 1 }, { "Magi", "MAGE", 1 }, { "Priest", "PRIEST", 1 },
    { "Aaron", "WARRIOR", 2 }, { "Bert", "ROGUE", 2 }, { "Xena", "PRIEST", 2 }, { "Yuri", "MAGE", 2 } }
  H.setRaid(raid); me.subgroup = 2; table.insert(H.state.raid, me)    -- raid10
  layout("separateVertical")
  own = ownFrame()
  check(own == CompactRaidGroup2Member1 and barPlaced() and near(select(2, H.vspan(CompactRaidGroup2Member2)), H.vspan(own) - room())
    and flush(CompactRaidGroup1Member1, CompactRaidGroup1Member2), "raid, Separate (Vertical): room under me in group 2 only")
  layout("combineHorizontal")
  own = ownFrame()
  check(barPlaced() and near(nextBelow(), H.vspan(own) - room()), "raid, Combine (Horizontal): the next row starts under the boxes")
  layout("combineVertical")
  own = ownFrame()
  check(barPlaced() and near(nextBelow(), H.vspan(own) - room()), "raid, Combine (Vertical): the next frame under the boxes")
  -- not first: alphabetical, Keep Me at the Top off -> Aaron, Bert, Kami, Xena, Yuri
  SetRaidProfileOption(prof, "sortBy", "alphabetical"); SetRaidProfileOption(prof, "sortPlayerFirst", false)
  layout("separateVertical")
  own = ownFrame()
  check(own == CompactRaidGroup2Member3 and barPlaced() and flush(CompactRaidGroup2Member1, CompactRaidGroup2Member2) and flush(CompactRaidGroup2Member2, own)
    and near(select(2, H.vspan(CompactRaidGroup2Member4)), H.vspan(own) - room()), "me 3rd in my group: the room goes after me, not at the top")
  layout("combineVertical")
  own = ownFrame()
  check(barPlaced() and near(nextBelow(), H.vspan(own) - room()), "Combine (Vertical) sorted: still right under me")
  SetRaidProfileOption(prof, "sortBy", "group"); SetRaidProfileOption(prof, "sortPlayerFirst", true)
  layout("separateVertical")

  -- frame size: the boxes follow; too small for the time at the smallest size
  SetRaidProfileOption(prof, "frameWidth", 72); SetRaidProfileOption(prof, "frameHeight", 36); relayout()
  own = ownFrame()
  check(barPlaced() and near(earth:GetWidth(), 13) and near(room(), 13) and earth.icon:IsVisible() and earth.timer:GetText() == ""
    and near(select(2, H.vspan(CompactRaidGroup2Member2)), H.vspan(own) - room()), "smallest frames: 13px boxes, the sweep but no time")
  H.RunUpdates(1, 2)
  check(earth.timer:GetText() == "", "(still no time as it counts down)")
  SetRaidProfileOption(prof, "frameWidth", 186); SetRaidProfileOption(prof, "frameHeight", 96); relayout()
  check(barPlaced() and near(earth:GetWidth(), 27) and earth.timer:GetText() == "5m", "largest frames: 27px boxes with the time")
  SetRaidProfileOption(prof, "frameWidth", 129); SetRaidProfileOption(prof, "frameHeight", 66); relayout()
  check(barPlaced() and near(earth:GetWidth(), 20) and earth.timer:GetText() == "5m", "default size again: 20px, time shown")

  -- raid size preview: every slot as a dim placeholder, under the first placeholder
  H.state.totems = nil; H.FireEvent("PLAYER_TOTEM_UPDATE", 2); H.RunUpdates(0.05, 1)
  check(not bar:IsVisible(), "no totems: no boxes")
  CRF_SetRaidPreviewSize(10); H.RunUpdates(0.05, 2)
  local marked = 0
  for _, f in ipairs(shownFrames()) do if f.crfClassBarRoom then marked = marked + 1 end end
  local wv = water.fill.__vertex
  check(bar:GetParent() == CompactRaidGroup1Member1 and barPlaced(CompactRaidGroup1Member1) and marked == 1 and #shownBoxes() == 4
    and near(water.fill:GetAlpha(), 0.3) and wv and wv[3] > 0.9 and wv[1] < 0.5 and flush(CompactRaidGroup2Member1, CompactRaidGroup2Member2),
    "preview: all four boxes as dim placeholders in their element's colour, under the first placeholder")
  layout("combineVertical")
  local first
  for _, f in ipairs(shownFrames()) do if f.crfClassBarRoom then first = f end end
  check(first and barPlaced(first) and near(nextBelow(first), H.vspan(first) - room()), "preview, combined: under the first placeholder")
  CRF_SetRaidPreviewSize(nil); H.RunUpdates(0.05, 2)
  layout("separateVertical")
  check(not bar:IsVisible() and flush(ownFrame(), CompactRaidGroup2Member2), "preview over, no totems: no boxes, no room")

  -- Death Knight
  me.class = "DEATHKNIGHT"; CRF_UpdateClassBarRoom(); H.RunUpdates(0.05, 2)
  local b = bar.boxes
  check(not bar:IsVisible() and flush(ownFrame(), CompactRaidGroup2Member2), "Death Knight, all runes ready out of combat: no boxes, no room")
  H.state.runes = { [5] = { start = H.now, duration = 10 } }
  H.FireEvent("RUNE_POWER_UPDATE", 5, false); H.RunUpdates(0.05, 1)
  own = ownFrame()
  check(barPlaced() and bar.count == 7 and #shownBoxes() == 6 and not b[7]:IsVisible() and near(b[1]:GetWidth(), 18)
    and near(select(2, H.vspan(CompactRaidGroup2Member2)), H.vspan(own) - room()), "a rune used: the six rune boxes (18px, so seven fit) and their room")
  local function hue(box)
    local v = box.fill.__vertex
    if v[1] > 0.9 and v[2] < 0.3 and v[3] < 0.3 then return "blood" end
    if v[3] > 0.9 and v[2] > 0.7 and v[1] < 0.3 then return "frost" end
    if v[2] > 0.6 and v[1] < 0.3 and v[3] < 0.3 then return "unholy" end
    if v[1] > 0.7 and v[3] > 0.9 and v[2] < 0.3 then return "death" end
  end
  check(hue(b[1]) == "blood" and hue(b[2]) == "blood" and hue(b[3]) == "frost" and hue(b[4]) == "frost" and hue(b[5]) == "unholy" and hue(b[6]) == "unholy"
    and near(b[1].fill:GetAlpha(), 1), "the player frame's order, bright when ready: blood, blood, frost, frost, unholy, unholy")
  check(near(b[3].fill:GetAlpha(), 0.25) and b[3].charge:GetHeight() < 0.5 and near(b[4].fill:GetAlpha(), 1), "the used rune (the first frost) dims")
  local runeStart = H.state.runes[5].start
  H.RunUpdates(1, 5)
  check(b[3].charge:IsVisible() and near(b[3].charge:GetHeight(), (18 - 2) * (H.now - runeStart) / 10),
    "and fills back up from the bottom (half way after 5 of 10 seconds)")
  H.RunUpdates(1, 6); H.FireEvent("RUNE_POWER_UPDATE", 5, true); H.RunUpdates(0.05, 1)
  check(not bar:IsVisible() and flush(ownFrame(), CompactRaidGroup2Member2), "all runes back (out of combat): boxes and room go")
  H.FireEvent("PLAYER_REGEN_DISABLED"); H.inCombat = true; H.RunUpdates(0.05, 1)
  check(barPlaced() and #shownBoxes() == 6 and near(b[1].fill:GetAlpha(), 1), "combat starts: the runes and their room")
  H.state.runeTypes = { [1] = 4 }; H.FireEvent("RUNE_TYPE_UPDATE", 1)
  check(hue(b[1]) == "death" and hue(b[2]) == "blood", "a death rune turns purple")
  b[1]:GetScript("OnEnter")(b[1])
  check(GameTooltip.__tttext == "Death Rune" and GameTooltip:IsOwned(b[1]), "hovering a rune: its type")
  b[1]:GetScript("OnLeave")(b[1])
  H.state.totems = { [1] = { name = "Risen Ghoul", start = H.now, duration = 60, icon = "Interface\\Icons\\Spell_Shadow_AnimateDead" } }
  H.FireEvent("PLAYER_TOTEM_UPDATE", 1)
  check(barPlaced() and b[7]:IsVisible() and #shownBoxes() == 7 and b[7].icon:GetTexture() == "Interface\\Icons\\Spell_Shadow_AnimateDead"
    and b[7].timer:GetText() == "1m" and #H.blocked == 0, "a temporary ghoul: a seventh box right after the runes, with its time left")
  H.inCombat = false; H.FireEvent("PLAYER_REGEN_ENABLED"); H.RunUpdates(1, 2)
  check(barPlaced() and b[7]:IsVisible() and b[7].timer:GetText() == "58", "combat over, ghoul still up: boxes and room stay")
  H.RunUpdates(1, 60)
  check(not bar:IsVisible() and flush(ownFrame(), CompactRaidGroup2Member2), "the ghoul gone: boxes and room go")

  -- Hide Player Frame off: the player frame has them again, no boxes or room
  me.class = "SHAMAN"; totem(2, "Spell_Nature_EarthBindTotem", 300); CRF_UpdateClassBarRoom(); H.RunUpdates(0.05, 2)
  check(barPlaced(), "(a shaman with a totem down again)")
  hpf:Click(); H.RunUpdates(0.05, 2)
  own = ownFrame()
  check(not bar:IsVisible() and flush(own, CompactRaidGroup2Member2) and PlayerFrame:IsShown() and TotemFrame:IsVisible(),
    "Hide Player Frame off: no boxes, no room, the player frame's totems are back")
  hpf:Click(); H.RunUpdates(0.05, 2)
  check(barPlaced() and not PlayerFrame:IsShown() and not TotemFrame:IsVisible(), "on again: box and room back")

  check(#H.errors == 0 and #H.blocked == 0, "no Lua errors (" .. #H.errors .. "), nothing blocked")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  for i = 1, math.min(3, #H.blocked) do print("       blocked: " .. H.blocked[i]:gsub("\n", "\n         ")) end
  H.errors = {}; H.blocked = {}

  me.class, me.name, me.subgroup = savedClass, savedName, nil
  H.state.totems, H.state.runes, H.state.runeTypes = nil, nil, nil
  H.destroyedTotems = {}
  H.state.party, H.state.raid = savedParty, savedRaid
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  CRF_UpdateClassBarRoom(); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(not bar:IsVisible() and #H.errors == 0, "a paladin again: no boxes")
  end

  ----------------------------------------------------------------------
  section("Groups in the side bar")
  local raid10 = {}
  for i = 1, 10 do raid10[i] = { "Member" .. i, (i % 2 == 0) and "PRIEST" or "WARRIOR", (i <= 5) and 1 or 2 } end
  H.setRaid(raid10); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  CompactRaidFrameManager_Expand(m)
  local gs, ps = df.groupsSelector, df.previewSelector
  check(gs:IsVisible() and ps:IsVisible(), "Groups and preview dropdowns in the side bar")
  local _, profB = H.vspan(df.profileSelector); local gsB, gsT = H.vspan(gs); local psB, psT = H.vspan(ps)
  if os.getenv("CRF_DEBUG") then print("DBG prof", H.vspan(df.profileSelector)) print("DBG gs", gsB, gsT) print("DBG ps", psB, psT) end
  check(near(gsT, select(1, H.vspan(df.profileSelector)), 1) and psT < gsB, "under the profile dropdown")
  check(_G[gs:GetName() .. "Text"]:GetText() == CRF_GROUPS_SHORT_COMBINE_VERTICAL, "shows Combine (Vertical)")
  local profile = GetActiveRaidProfile()
  _G["CompactUnitFrameProfilesOptionsTab1"]:Click()
  local petsBefore = GetRaidProfileOption(profile, "displayPets") and true or false
  _G["CompactUnitFrameProfilesOptionsGeneralDisplayPets"]:Click()          -- an unsaved panel edit
  H.pickDropDown(gs, "separateHorizontal")
  check(GetRaidProfileOption(profile, "keepGroupsTogether") == true and GetRaidProfileOption(profile, "horizontalGroups") == true
    and container.groupMode == "discrete" and CUF_HORIZONTAL_GROUPS == true, "Separate Groups (Horizontal) applied")
  local g1, g2 = CompactRaidGroup1, CompactRaidGroup2
  local m1l, m1r = H.hspan(CompactRaidGroup1Member1); local m2l = H.hspan(CompactRaidGroup1Member2)
  local g1b = select(1, H.vspan(g1)); local g2t = select(2, H.vspan(g2))
  check(near(m2l, m1r) and g2t <= g1b + 0.5, "members in a row, group 2 below group 1")
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  check((GetRaidProfileOption(profile, "displayPets") and true or false) == petsBefore and GetRaidProfileOption(profile, "keepGroupsTogether") == true,
    "the side bar saved its change; the unsaved panel edit was still cancelled")
  H.pickDropDown(gs, "separateVertical")
  m1l = H.hspan(CompactRaidGroup1Member1); local m1b = select(1, H.vspan(CompactRaidGroup1Member1)); local m2t = select(2, H.vspan(CompactRaidGroup1Member2))
  local g1r = select(2, H.hspan(g1)); local g2l = H.hspan(g2)
  check(near(m2t, m1b) and g2l >= g1r - 0.5 and near(select(2, H.vspan(g1)), select(2, H.vspan(g2))), "members in a column, group 2 beside group 1")
  check(not RaidProfileHasUnsavedChanges(), "side bar changes are saved at once")
  H.pickDropDown(gs, "combineHorizontal")
  local list = unitFrames()
  check(container.groupMode == "flush" and #list == 10, "Combine Groups: 10 frames")
  local f1l, f1r = H.hspan(list[1]); local f2l = H.hspan(list[2]); local f1b = select(1, H.vspan(list[1])); local f6t = select(2, H.vspan(list[6]))
  check(near(f2l, f1r) and near(f6t, f1b) and near(H.hspan(list[6]), f1l), "horizontal: rows of 5")
  H.pickDropDown(gs, "combineVertical")
  list = unitFrames()
  f1b = select(1, H.vspan(list[1])); local f2t = select(2, H.vspan(list[2]))
  check(near(f2t, f1b) and near(H.hspan(list[2]), H.hspan(list[1])), "vertical: one column")
  _G["CompactUnitFrameProfilesOptionsTab2"]:Click()
  H.pickDropDown(_G["CompactUnitFrameProfilesOptionsLayoutGroupsDropdown"], "separateVertical")
  check(RaidProfileHasUnsavedChanges() and _G[gs:GetName() .. "Text"]:GetText() == CRF_GROUPS_SHORT_SEPARATE_VERTICAL, "panel change is unsaved and shows in the side bar")
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  check(_G[gs:GetName() .. "Text"]:GetText() == CRF_GROUPS_SHORT_COMBINE_VERTICAL, "Cancel puts the side bar back")
  H.inCombat = true
  local nmsg = #DEFAULT_CHAT_FRAME.messages
  CompactRaidFrameManagerDisplayFrameGroupsSelector_OnClick(nil, CRF_GROUP_LAYOUTS[4])
  check(#DEFAULT_CHAT_FRAME.messages == nmsg + 1 and not GetRaidProfileOption(profile, "keepGroupsTogether") and #H.blocked == 0, "in combat: refused with a message")
  H.inCombat = false

  local function widestOf(fontString, texts)
    local widest, widestText = 0, ""
    for _, t in ipairs(texts) do
      fontString:SetText(t)
      local w = fontString:GetStringWidth()
      if w > widest then widest, widestText = w, t end
    end
    return widest, widestText
  end
  local function fits(width, dropdownWidth) return width * 1.06 <= dropdownWidth - 25 end
  local sideTexts = { CRF_GetRaidPreviewLabel(nil) }
  for _, size in ipairs(CRF_RAID_PREVIEW_SIZES) do sideTexts[#sideTexts+1] = CRF_GetRaidPreviewLabel(size) end
  local groupTexts = {}
  for _, layout in ipairs(CRF_GROUP_LAYOUTS) do sideTexts[#sideTexts+1] = CRF_GetGroupLayoutText(layout, true); groupTexts[#groupTexts+1] = CRF_GetGroupLayoutText(layout, true) end
  local w, t = widestOf(_G[gs:GetName() .. "Text"], sideTexts)
  check(fits(w, 165), string.format("side bar texts fit their 165px dropdowns (widest %.0fpx: %s)", w, t))
  local pgd = _G["CompactUnitFrameProfilesOptionsLayoutGroupsDropdown"]
  w, t = widestOf(_G[pgd:GetName() .. "Text"], groupTexts)
  check(fits(w, pgd.width), string.format("Layout tab Groups fits its %dpx dropdown (widest %.0fpx: %s)", pgd.width, w, t))
  local ppd = _G["CompactUnitFrameProfilesOptionsLayoutRaidSizePreviewDropdown"]
  local previewTexts = { CRF_GetRaidPreviewText(nil) }
  for _, size in ipairs(CRF_RAID_PREVIEW_SIZES) do previewTexts[#previewTexts+1] = CRF_GetRaidPreviewText(size) end
  w, t = widestOf(_G[ppd:GetName() .. "Text"], previewTexts)
  check(fits(w, ppd.width), string.format("Layout tab preview fits its %dpx dropdown (widest %.0fpx: %s)", ppd.width, w, t))
  CompactRaidFrameManager_UpdateLayoutSelectors()
  if CompactUnitFrameProfiles:IsVisible() then CompactUnitFrameProfiles_UpdateCurrentPanel() end

  ----------------------------------------------------------------------
  section("Raid size preview")
  H.setParty({}); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(not m:IsShown() and not container:IsVisible(), "solo, Always show off: raid frames hidden")
  H.pickDropDown(_G["CompactUnitFrameProfilesOptionsLayoutRaidSizePreviewDropdown"], 25)
  list = unitFrames()
  local allPlayer = true
  for _, f in ipairs(list) do if f.unit ~= "player" then allPlayer = false end end
  check(m:IsShown() and container:IsVisible() and #list == 25 and allPlayer, "Layout tab: 25 placeholder frames, shown while solo")
  check(_G[ps:GetName() .. "Text"]:GetText() == CRF_GetRaidPreviewLabel(25) and _G["CompactUnitFrameProfilesOptionsLayoutRaidSizePreviewDropdownText"]:GetText() == CRF_GetRaidPreviewText(25), "both dropdowns show it")
  check(not PlayerFrame:IsShown(), "player frame hidden while previewing")
  H.pickDropDown(ps, 40)
  check(#unitFrames() == 40, "side bar: 40")
  H.pickDropDown(gs, "separateVertical")
  local shownGroups, players = 0, 0
  for g = 1, 8 do
    local gf = _G["CompactRaidGroup" .. g]
    if gf and gf:IsVisible() then
      shownGroups = shownGroups + 1
      for i = 1, 5 do if _G[gf:GetName() .. "Member" .. i].unit == "player" then players = players + 1 end end
    end
  end
  check(shownGroups == 8 and players == 40, "separate groups: 8 groups of 5")
  H.pickDropDown(ps, 10)
  shownGroups = 0
  for g = 1, 8 do local gf = _G["CompactRaidGroup" .. g]; if gf and gf:IsVisible() then shownGroups = shownGroups + 1 end end
  check(shownGroups == 2, "10 players: 2 groups")
  H.setParty({ { "Arthas", "DEATHKNIGHT" } }); H.FireEvent("PARTY_MEMBERS_CHANGED"); H.RunUpdates(0.05, 2)
  check(CRF_GetRaidPreviewSize() == 10 and CompactRaidGroup1Member1.unit == "player", "survives a roster change")
  H.FireEvent("PLAYER_REGEN_DISABLED")       -- before the lockdown starts
  H.inCombat = true
  check(CRF_GetRaidPreviewSize() == nil and CompactPartyFrame and CompactPartyFrame:IsVisible() and not CompactRaidGroup1:IsVisible()
    and CompactRaidGroup1Member1.unit == nil, "combat starts: preview ends, real frames back")
  check(_G[ps:GetName() .. "Text"]:GetText() == CRF_GetRaidPreviewLabel(nil), "dropdown back to Off")
  nmsg = #DEFAULT_CHAT_FRAME.messages
  CRF_SetRaidPreviewSize(25)
  check(CRF_GetRaidPreviewSize() == nil and #DEFAULT_CHAT_FRAME.messages == nmsg + 1 and #H.blocked == 0, "can't start in combat")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")
  H.pickDropDown(gs, "combineVertical")
  H.setParty({}); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local framesBefore = #unitFrames()       -- solo: the (hidden) container still holds your own frame
  H.pickDropDown(ps, 25)
  H.pickDropDown(ps, 0)
  if os.getenv("CRF_DEBUG") then print("DBG off", m:IsShown(), container:IsVisible(), #unitFrames(), PlayerFrame:IsShown(), CRF_GetRaidPreviewSize(), GetDisplayedAllyFrames()) end
  check(not m:IsShown() and not container:IsVisible() and #unitFrames() == framesBefore and PlayerFrame:IsShown(), "Off: back to normal (solo: nothing shown, player frame back)")

  ----------------------------------------------------------------------
  section("Raid frames keep clear of the side menu")
  H.setParty({ { "Arthas", "DEATHKNIGHT" } }); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  CompactRaidFrameManager_Collapse(m)
  local rf = m.containerResizeFrame
  local prof = GetActiveRaidProfile()
  local function place(point, offset)    -- a saved position, as if moved there earlier
    SetRaidProfileSavedPosition(prof, false, "TOP", 100, "BOTTOM", 400, point, offset)
    CompactRaidFrameManager_ResizeFrame_LoadPosition(m)
  end
  local function rfLeft() return (H.hspan(rf)) end
  local function mRight() return select(2, H.hspan(m)) end
  place("LEFT", 120)
  check(near(rfLeft(), 120) and near(m.containerMenuOffset, 120 - mRight()), string.format("frames next to the closed tab follow the menu (offset %s)", tostring(m.containerMenuOffset)))
  CompactRaidFrameManager_Expand(m)
  check(rfLeft() >= mRight() and near(rfLeft() - mRight(), m.containerMenuOffset), string.format("opening the menu slides them over (left %.0f, menu edge %.0f)", rfLeft(), mRight()))
  CompactRaidFrameManager_ResizeFrame_SavePosition(m)
  local _, _, _, _, _, lp, lo = GetRaidProfileSavedPosition(prof)
  check(lp == "LEFT" and near(lo, 120), "saved where they sit with the menu closed (" .. tostring(lo) .. ")")
  CompactRaidFrameManager_Collapse(m)
  check(near(rfLeft(), 120), "closing it brings them back")
  place("LEFT", 400)
  CompactRaidFrameManager_Expand(m)
  check(m.containerMenuOffset == nil and near(rfLeft(), 400), "frames further right stay put")
  CompactRaidFrameManager_Collapse(m)
  SetRaidProfileSavedPosition(prof, false, "BOTTOM", 300, "BOTTOM", 100, "LEFT", 50)
  CompactRaidFrameManager_ResizeFrame_LoadPosition(m)
  CompactRaidFrameManager_Expand(m)
  check(m.containerMenuOffset == nil and near(rfLeft(), 50), "frames below the menu stay put")
  CompactRaidFrameManager_Collapse(m)
  place("LEFT", 400)
  local function drop(x)       -- drag the frames and let go with their left edge at x
    CompactRaidFrameManager_ResizeFrame_OnDragStart(m)
    local top = select(2, H.vspan(rf))
    rf:ClearAllPoints(); rf:SetPoint("TOPLEFT", nil, "BOTTOMLEFT", x, top)
    CompactRaidFrameManager_ResizeFrame_OnDragStop(m)
  end
  drop(60)
  _, _, _, _, _, lp, lo = GetRaidProfileSavedPosition(prof)
  check(near(m.containerMenuOffset, 60 - mRight()) and lp == "LEFT" and near(lo, 60), "dropped near the closed tab: follows the menu")
  drop(5)
  _, _, _, _, _, lp = GetRaidProfileSavedPosition(prof)
  check(m.containerMenuOffset == 0 and near(rfLeft(), mRight()) and lp == "ATTACHED", "dropped on the tab: lands beside it")
  CompactRaidFrameManager_Expand(m)
  drop(100)
  check(m.containerMenuOffset == 0 and near(rfLeft(), mRight()), "dropped on the open menu: lands beside it")
  CompactRaidFrameManager_Collapse(m)
  check(near(rfLeft(), mRight()), "and stays beside the closed tab")
  CompactRaidFrameManager_ResetContainerPosition()

  ----------------------------------------------------------------------
  section("Frame size in the side bar")
  CompactRaidFrameManager_Expand(m)
  local fs = df.frameSize
  local hS, wS = fs.height, fs.width
  check(fs:IsVisible() and hS:IsVisible() and wS:IsVisible(), "Frame Height / Width sliders in the side bar")
  local gsB = select(1, H.vspan(df.groupsSelector)); local fsB, fsT = H.vspan(fs); local psT = select(2, H.vspan(df.previewSelector))
  check(near(fsT, gsB) and near(psT, fsB), "between Groups and the preview")
  local hl, hr = H.hspan(hS); local ml, mr = H.hspan(m)
  check(hl > ml + 5 and hr < mr - 15, "inside the side bar, clear of its tab")
  check(hS.label:GetText() == COMPACT_UNIT_FRAME_PROFILE_FRAMEHEIGHT and wS.label:GetText() == COMPACT_UNIT_FRAME_PROFILE_FRAMEWIDTH, "labelled")
  local ll, lr = H.hspan(hS.label); local vl = H.hspan(hS.valueLabel)
  check(lr < vl, "name and percentage don't overlap")
  check(hS:GetValue() == GetRaidProfileOption(prof, "frameHeight") and hS.valueLabel:GetText() ~= "", "shows the profile's size")
  hS:SetValue(60)
  check(GetRaidProfileOption(prof, "frameHeight") == 60 and DefaultCompactUnitFrameSetupOptions.height == 60 and not RaidProfileHasUnsavedChanges(), "dragging resizes the frames and saves")
  check(hS.valueLabel:GetText() == "40%", "height 60 = 40%")
  wS:SetValue(129)
  check(GetRaidProfileOption(prof, "frameWidth") == 129 and wS.valueLabel:GetText() == "50%", "side bar width 129 = 50%")
  _G["CompactUnitFrameProfilesOptionsTab2"]:Click()
  check(_G["CompactUnitFrameProfilesOptionsLayoutHeightSlider"]:GetValue() == 60, "the Layout tab follows")
  _G["CompactUnitFrameProfilesOptionsLayoutWidthSlider"]:SetValue(100)
  check(wS:GetValue() == 100 and RaidProfileHasUnsavedChanges(), "a Layout tab change shows in the side bar (unsaved there)")
  CompactUnitFrameProfiles_CancelChanges(CompactUnitFrameProfiles)
  check(wS:GetValue() == GetRaidProfileOption(prof, "frameWidth") and wS:GetValue() ~= 100, "Cancel moves it back")
  H.inCombat = true
  hS:SetValue(70)
  check(GetRaidProfileOption(prof, "frameHeight") == 70 and DefaultCompactUnitFrameSetupOptions.height == 60 and #H.blocked == 0, "in combat: saved, frames wait")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")
  check(DefaultCompactUnitFrameSetupOptions.height == 70, "resized when combat ends")
  hS:SetValue(36); wS:SetValue(72)

  ----------------------------------------------------------------------
  section("No \"Party\" title when solo")
  H.pickDropDown(df.groupsSelector, "separateVertical")
  H.setParty({}); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  if not CRF_IsAlwaysEnabled() then always:Click() end
  local pf = CompactPartyFrame
  local function gap() return select(2, H.vspan(pf)) - select(2, H.vspan(CompactPartyFrameMember1)) end
  check(pf:IsVisible() and not pf.title:IsShown() and near(gap(), 0), string.format("solo: no title, your frame at the top (gap %.0f)", gap()))
  H.setParty({ { "Arthas", "DEATHKNIGHT" } }); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(pf.title:IsShown() and pf.title:GetText() == PARTY and near(gap(), 14), "in a party: \"Party\" above the frames")
  H.setParty({}); CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  check(not pf.title:IsShown() and near(gap(), 0), "leaving: gone again")
  H.inCombat = true
  H.setParty({ { "Arthas", "DEATHKNIGHT" } }); H.FireEvent("PARTY_MEMBERS_CHANGED"); H.RunUpdates(0.05, 2)
  check(not pf.title:IsShown() and #H.blocked == 0, "joining in combat: unchanged until combat ends, nothing blocked")
  H.inCombat = false
  H.FireEvent("PLAYER_REGEN_ENABLED")
  check(pf.title:IsShown() and near(gap(), 14), "after combat: \"Party\" shown")
  H.pickDropDown(df.groupsSelector, "combineVertical")
  always:Click()

  check(#H.errors == 0, "no Lua errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e:gsub("\n", "\n     ")) end
  check(#H.blocked == 0, "nothing blocked")
  for i = 1, math.min(3, #H.blocked) do print("       blocked: " .. H.blocked[i]:gsub("\n", "\n         ")) end
  H.errors = {}
  H.blocked = {}
end

------------------------------------------------------------------------
if scenario == "dump-unit" then
  -- one unit frame close up, for each power bar text setting
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_unit"
  H.setParty({ { "Kamakazedan", "SHAMAN", "HEALER" } })
  H.state.party[1].power = 7340
  if os.getenv("CRF_UNIT_AURAS") then
    H.state.party[1].buffs = { { spellId = 61295 }, { spellId = 974, count = 3 }, { spellId = 51945 } }
    H.state.party[1].debuffs = { { spellId = 6788, type = "Magic", dispellable = true }, { spellId = 25771 },
      { spellId = 3, type = "Poison", dispellable = true } }
  end
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local prof = GetActiveRaidProfile()
  SetRaidProfileOption(prof, "displayPowerBar", true)
  SetRaidProfileOption(prof, "useClassColors", true)
  SetRaidProfileOption(prof, "healthText", os.getenv("CRF_UNIT_HEALTHTEXT") or "health")
  local sizes = os.getenv("CRF_UNIT_SIZE")
  if sizes then
    local h, w = sizes:match("(%d+),(%d+)")
    SetRaidProfileOption(prof, "frameHeight", tonumber(h)); SetRaidProfileOption(prof, "frameWidth", tonumber(w))
  end
  local modes = {}
  for m in (os.getenv("CRF_UNIT_MODES") or "none,power,perc"):gmatch("[^,]+") do modes[#modes + 1] = m end
  for _, mode in ipairs(modes) do
    SetRaidProfileOption(prof, "powerText", mode)
    CompactUnitFrameProfiles_ApplyCurrentSettings()
    H.FireEvent("UNIT_AURA", "party1")
    H.RunUpdates(0.05, 2)
    local u
    CRF_ForEachCompactUnitFrame(function(f) if f.unit == "party1" and f:IsVisible() then u = f end end)
    local fl = H.hspan(u); local _, ft = H.vspan(u)
    local f = io.open(out .. "_" .. mode .. ".tsv", "w")
    local function row(kind, o, text)
      if not (o and o:IsVisible()) then return end
      local l, r = H.hspan(o); local b, t = H.vspan(o)
      f:write(table.concat({ kind, tostring(text or ""), string.format("%.1f", l - fl), string.format("%.1f", ft - t),
        string.format("%.1f", r - fl), string.format("%.1f", ft - b), string.format("%.1f", o.GetFont and select(2, o:GetFont()) or 0) }, "\t") .. "\n")
    end
    row("frame", u); row("health", u.healthBar); row("power", u.powerBar)
    row("name", u.name, u.name:GetText()); row("status", u.statusText, u.statusText:GetText()); row("powertext", u.powerText, u.powerText:GetText())
    row("role", u.roleIcon)
    for i, a in ipairs(u.buffFrames) do row("buff", a, a.count:IsShown() and a.count:GetText() or "") end
    for i, a in ipairs(u.debuffFrames) do row("debuff", a) end
    for i, a in ipairs(u.dispelDebuffFrames) do row("dispel", a) end
    f:close()
  end
  check(#H.errors == 0, "no errors while dumping a unit frame")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end
if scenario == "dump-pets" then
  -- a party with a pet, in Separate (Vertical), at the frame size given
  local container = CompactRaidFrameContainer
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_pets"
  H.state.player.name = "Kamakazedan"
  if os.getenv("CRF_PETS_PARTY") == "two" then
    H.state.player.name = "Kamikaze"
    H.setParty({ { "Mynamejeff", "HUNTER" } })
    H.state.party[1].pet = { name = "MynameDan", class = "HUNTER" }
  else
    H.setParty({ { "Sokmigg", "WARLOCK" }, { "Hatril", "PALADIN", "TANK" }, { "Hulgharun", "PRIEST", "HEALER" }, { "Ildary", "WARRIOR" } })
    H.state.party[1].pet = { name = "Kuplop", class = "WARLOCK" }
  end
  local prof = GetActiveRaidProfile()
  SetRaidProfileOption(prof, "keepGroupsTogether", true); SetRaidProfileOption(prof, "horizontalGroups", false)
  SetRaidProfileOption(prof, "displayPets", true)
  SetRaidProfileOption(prof, "frameHeight", tonumber(os.getenv("CRF_PETS_H") or 66)); SetRaidProfileOption(prof, "frameWidth", tonumber(os.getenv("CRF_PETS_W") or 129))
  CompactUnitFrameProfiles_ApplyCurrentSettings()
  CRF_RelayGroupRosterUpdate(); H.FireEvent("UNIT_PET", "party1"); H.RunUpdates(0.05, 2)
  local cl = H.hspan(container)
  local _, ct = H.vspan(container)
  local f = io.open(out .. ".tsv", "w")
  CRF_ForEachCompactUnitFrame(function(u)
    if u:IsVisible() and u.unit and UnitExists(u.unit) then
      local l, r = H.hspan(u); local b, t = H.vspan(u)
      f:write(table.concat({ u.unit:find("pet") and "pet" or "player", UnitName(u.unit) or "", string.format("%.1f", l - cl), string.format("%.1f", ct - t),
        string.format("%.1f", r - cl), string.format("%.1f", ct - b) }, "\t") .. "\n")
    end
  end)
  local gf = CompactPartyFrame
  if gf and gf:IsVisible() and gf.title:IsShown() then
    local l, r = H.hspan(gf.title); local b, t = H.vspan(gf.title)
    f:write(table.concat({ "title", gf.title:GetText() or "", string.format("%.1f", l - cl), string.format("%.1f", ct - t),
      string.format("%.1f", r - cl), string.format("%.1f", ct - b) }, "\t") .. "\n")
  end
  f:close()
  check(#H.errors == 0, "no errors while dumping the party with a pet")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end

if scenario == "dump-pets-raid" then
  -- a 10-player raid with 3 pets, in each group layout
  local container = CompactRaidFrameContainer
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_petsraid"
  local me = H.state.player
  me.name = "Kamakazedan"; me.subgroup = 1
  H.setRaid({ { "Hatril", "PALADIN", 1 }, { "Sokmigg", "WARLOCK", 1 }, { "Hulgharun", "PRIEST", 1 }, { "Ildary", "WARRIOR", 1 },
    { "Rexxar", "HUNTER", 2 }, { "Jaina", "MAGE", 2 }, { "Thrall", "SHAMAN", 2 }, { "Arthas", "DEATHKNIGHT", 2 }, { "Tyrande", "PRIEST", 2 } })
  table.insert(H.state.raid, 1, me)
  H.state.raid[3].pet = { name = "Kuplop" }; H.state.raid[6].pet = { name = "Misha" }; H.state.raid[9].pet = { name = "Ghoul" }
  local prof = GetActiveRaidProfile()
  SetRaidProfileOption(prof, "displayPets", true)
  SetRaidProfileOption(prof, "frameHeight", tonumber(os.getenv("CRF_PETS_H") or 96)); SetRaidProfileOption(prof, "frameWidth", tonumber(os.getenv("CRF_PETS_W") or 186))
  for i, layout in ipairs(CRF_GROUP_LAYOUTS) do
    CRF_SetGroupLayout(prof, layout, true)
    CompactUnitFrameProfiles_ApplyCurrentSettings()
    CRF_RelayGroupRosterUpdate(); H.FireEvent("UNIT_PET", "raid3"); H.RunUpdates(0.05, 2)
    local cl = H.hspan(container)
    local _, ct = H.vspan(container)
    local f = io.open(out .. "_" .. layout.key .. ".tsv", "w")
    CRF_ForEachCompactUnitFrame(function(u)
      if u:IsVisible() and u.unit then
        local l, r = H.hspan(u); local b, t = H.vspan(u)
        f:write(table.concat({ u.unit:find("pet") and "pet" or "player", UnitName(u.unit) or "", string.format("%.1f", l - cl), string.format("%.1f", ct - t),
          string.format("%.1f", r - cl), string.format("%.1f", ct - b) }, "\t") .. "\n")
      end
    end)
    for g = 1, 8 do
      local gf = _G["CompactRaidGroup" .. g]
      if gf and gf:IsVisible() and gf.title then
        local l, r = H.hspan(gf.title); local b, t = H.vspan(gf.title)
        f:write(table.concat({ "title", gf.title:GetText() or ("Group " .. g), string.format("%.1f", l - cl), string.format("%.1f", ct - t),
          string.format("%.1f", r - cl), string.format("%.1f", ct - b) }, "\t") .. "\n")
      end
    end
    f:close()
  end
  check(#H.errors == 0, "no errors while dumping raid layouts with pets")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end

if scenario == "dump-closeup" then
  -- your frame up close with its totem / rune boxes, and the next player under it
  -- CRF_CLOSEUP_CASE: none | one | three | small | dk
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_closeup"
  local case = os.getenv("CRF_CLOSEUP_CASE") or "three"
  local me = H.state.player
  me.name = "Kamakazedan"; me.class = (case == "dk") and "DEATHKNIGHT" or "SHAMAN"; me.lfgRole = "HEALER"; me.power = 9200
  H.setParty({ { "Avede", "WARLOCK" } })
  local prof = GetActiveRaidProfile()
  SetRaidProfileOption(prof, "keepGroupsTogether", true); SetRaidProfileOption(prof, "horizontalGroups", false)
  SetRaidProfileOption(prof, "displayPets", false); SetRaidProfileOption(prof, "displayPowerBar", true)
  SetRaidProfileOption(prof, "useClassColors", true); SetRaidProfileOption(prof, "healthText", "perc")
  SetRaidProfileOption(prof, "powerText", os.getenv("CRF_CLOSEUP_POWERTEXT") or "perc")
  if case == "small" then SetRaidProfileOption(prof, "frameHeight", 36); SetRaidProfileOption(prof, "frameWidth", 72) end
  CompactUnitFrameProfiles_ApplyCurrentSettings()
  CRF_UpdateClassBarRoom()
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  local now = H.now
  if case == "one" then
    H.state.totems = { [2] = { name = "Strength of Earth Totem", start = now - 60, duration = 300, icon = "earth" } }
  elseif case == "three" or case == "small" then
    H.state.totems = {
      [2] = { name = "Strength of Earth Totem", start = now - 60, duration = 300, icon = "earth" },
      [1] = { name = "Flametongue Totem", start = now - 255, duration = 300, icon = "fire" },
      [4] = { name = "Windfury Totem", start = now - 190, duration = 300, icon = "air" },
    }
  elseif case == "combat" then
    H.FireEvent("PLAYER_REGEN_DISABLED"); H.inCombat = true
  elseif case == "dk" then
    H.FireEvent("PLAYER_REGEN_DISABLED"); H.inCombat = true
    H.state.runes = { [1] = { start = now - 4, duration = 10 }, [3] = { start = now - 7.5, duration = 10 } }
    H.state.runeTypes = { [6] = 4 }
    H.state.totems = { [1] = { name = "Risen Ghoul", start = now - 15, duration = 60, icon = "ghoul" } }
  end
  -- CRF_CLOSEUP_REST = bright | faint: resting, the glow at either end of its pulse;
  -- CRF_CLOSEUP_DEBUFF = a debuff type on you (a resto shaman can cleanse it)
  local rest = os.getenv("CRF_CLOSEUP_REST")
  if rest then H.state.resting = true; H.FireEvent("PLAYER_UPDATE_RESTING") end
  local debuffType = os.getenv("CRF_CLOSEUP_DEBUFF")
  if debuffType then
    H.state.spellbook = { 6603, 51886 }; H.FireEvent("SPELLS_CHANGED")
    me.debuffs = { { spellId = 7321, type = debuffType } }
  end
  for slot = 1, 4 do H.FireEvent("PLAYER_TOTEM_UPDATE", slot) end
  H.FireEvent("RUNE_POWER_UPDATE", 1); H.FireEvent("UNIT_AURA", "player"); H.RunUpdates(0.05, 2)
  local own, nxt
  CRF_ForEachCompactUnitFrame(function(f)
    if f.unit and f:IsVisible() and UnitExists(f.unit) then
      if UnitIsUnit(f.unit, "player") and not own then own = f elseif f.unit == "party1" then nxt = f end
    end
  end)
  local fl = H.hspan(own); local _, ft = H.vspan(own)
  local f = io.open(out .. ".tsv", "w")
  local function row(kind, o, text, extra)
    if not (o and o:IsVisible()) then return end
    local l, r = H.hspan(o); local b, t = H.vspan(o)
    f:write(table.concat({ kind, tostring(text or ""), string.format("%.1f", l - fl), string.format("%.1f", ft - t),
      string.format("%.1f", r - fl), string.format("%.1f", ft - b), string.format("%.1f", o.GetFont and select(2, o:GetFont()) or 0), extra or "" }, "\t") .. "\n")
  end
  row("frame", own); row("health", own.healthBar); row("power", own.powerBar)
  row("name", own.name, own.name:GetText()); row("status", own.statusText, own.statusText:GetText()); row("powertext", own.powerText, own.powerText:GetText())
  row("role", own.roleIcon)
  if own.restGlow and own.restGlow:IsVisible() then
    own.restGlow:SetAlpha(rest == "faint" and 55 / 255 or 1)
    row("restglow", own.restGlow, "", string.format("%.3f", own.restGlow:GetAlpha()))
    row("resticon", own.restIcon)
  end
  for _, a in ipairs(own.buffFrames) do row("buff", a) end
  for _, a in ipairs(own.debuffFrames) do row("debuff", a) end
  for _, a in ipairs(own.dispelDebuffFrames) do row("dispel", a) end
  local ELEMENT = { [1] = "1,0.45,0.15", [2] = "0.55,0.75,0.25", [3] = "0.25,0.6,1", [4] = "0.75,0.75,1" }
  local bar = CompactRaidFrameClassBar
  for i = 1, bar.count or 0 do
    local box = bar.boxes[i]
    if box:IsVisible() then
      local v = box.fill.__vertex or { 1, 1, 1 }
      local icon, sweep, charge = "", 0, 0
      if box.icon:IsVisible() then
        local t = H.state.totems[box.totemSlot]
        icon = box.isGhoul and "0.45,0.55,0.4" or ELEMENT[box.totemSlot]; sweep = (H.now - t.start) / t.duration
      end
      if box.charge:IsVisible() then charge = box.charge:GetHeight() / (box:GetHeight() - 2) end
      row("box", box, box.timer:GetText() or "", string.format("%.2f,%.2f,%.2f,%.2f|%s|%.3f|%.3f", v[1], v[2], v[3], box.fill:GetAlpha(), icon, sweep, charge))
    end
  end
  row("nframe", nxt); row("nhealth", nxt.healthBar); row("npower", nxt.powerBar)
  row("nname", nxt.name, nxt.name:GetText()); row("nstatus", nxt.statusText, nxt.statusText:GetText()); row("npowertext", nxt.powerText, nxt.powerText:GetText())
  if case == "combat" then   -- the room has no box in it: mark it for the picture
    local l, r = H.hspan(own); local b = H.vspan(own)
    f:write(table.concat({ "room", "", "0.0", string.format("%.1f", ft - b), string.format("%.1f", r - l), string.format("%.1f", ft - b + bar:GetHeight()), "0", "" }, "\t") .. "\n")
  end
  f:close()
  check(#H.errors == 0 and #H.blocked == 0 and (case == "none" or bar:IsVisible()), "no errors while dumping the close-up")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end

if scenario == "dump-totems" then
  -- your totem / rune boxes under your raid frame (CRF_TOTEMS_CASE = shaman | empty | dk)
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_totems"
  local case = os.getenv("CRF_TOTEMS_CASE") or "shaman"
  H.state.player.name = "Kamakazedan"; H.state.player.class = (case == "dk") and "DEATHKNIGHT" or "SHAMAN"
  H.setParty({ { "Avede", "WARLOCK" }, { "Hatril", "PALADIN", "TANK" } })
  H.state.party[1].pet = { name = "Kraktast" }
  local prof = GetActiveRaidProfile()
  SetRaidProfileOption(prof, "keepGroupsTogether", true); SetRaidProfileOption(prof, "horizontalGroups", false)
  SetRaidProfileOption(prof, "displayPets", true)
  CompactUnitFrameProfiles_ApplyCurrentSettings()
  CRF_UpdateClassBarRoom()
  CRF_RelayGroupRosterUpdate(); H.FireEvent("UNIT_PET", "party1"); H.RunUpdates(0.05, 2)
  local now = H.now
  if case == "shaman" then
    H.state.totems = {
      [2] = { name = "Strength of Earth Totem", start = now - 60, duration = 300, icon = "earth" },
      [1] = { name = "Flametongue Totem", start = now - 255, duration = 300, icon = "fire" },
      [4] = { name = "Windfury Totem", start = now - 190, duration = 300, icon = "air" },
    }
  elseif case == "dk" then
    H.state.runes = { [1] = { start = now - 4, duration = 10 }, [3] = { start = now - 7.5, duration = 10 } }
    H.state.runeTypes = { [6] = 4 }
    H.state.totems = { [1] = { name = "Risen Ghoul", start = now - 15, duration = 60, icon = "ghoul" } }
  end
  for slot = 1, 4 do H.FireEvent("PLAYER_TOTEM_UPDATE", slot) end
  H.FireEvent("RUNE_POWER_UPDATE", 1); H.RunUpdates(0.05, 1)
  local bar = CompactRaidFrameClassBar
  local ol = math.huge; local ot = -math.huge
  CRF_ForEachCompactUnitFrame(function(u) if u.unit and u:IsVisible() and UnitExists(u.unit) then ol = math.min(ol, u:GetLeft()); ot = math.max(ot, u:GetTop()) end end)
  ot = ot + 14
  local f = io.open(out .. ".tsv", "w")
  local function row(kind, name, o, extra)
    local l, r = H.hspan(o); local b, t = H.vspan(o)
    f:write(table.concat({ kind, name, string.format("%.1f", l - ol), string.format("%.1f", ot - t), string.format("%.1f", r - ol), string.format("%.1f", ot - b), extra or "" }, "\t") .. "\n")
  end
  CRF_ForEachCompactUnitFrame(function(u)
    if u.unit and u:IsVisible() and UnitExists(u.unit) then row(u.unit:find("pet") and "pet" or "player", UnitName(u.unit) or "", u) end
  end)
  if CompactPartyFrame.title:IsShown() then row("title", "Party", CompactPartyFrame.title) end
  local ELEMENT = { [1] = "1,0.45,0.15", [2] = "0.55,0.75,0.25", [3] = "0.25,0.6,1", [4] = "0.75,0.75,1" }
  for i = 1, bar.count or 0 do
    local box = bar.boxes[i]
    if box:IsVisible() then
      local v = box.fill.__vertex or { 1, 1, 1 }
      local fill = string.format("%.2f,%.2f,%.2f,%.2f", v[1], v[2], v[3], box.fill:GetAlpha())
      local icon, sweep, charge = "", 0, 0
      if box.icon:IsVisible() then
        local t = H.state.totems[box.totemSlot]
        icon = box.isGhoul and "0.45,0.55,0.4" or ELEMENT[box.totemSlot]
        sweep = (H.now - t.start) / t.duration
      end
      if box.charge:IsVisible() then charge = box.charge:GetHeight() / (box:GetHeight() - 2) end
      row("box", box.timer:GetText() or "", box, table.concat({ fill, icon, string.format("%.3f", sweep), string.format("%.3f", charge) }, "|"))
    end
  end
  f:close()
  check(bar:IsVisible() and #H.errors == 0, "no errors while dumping the totem / rune boxes")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end

if scenario == "dump-raid" then
  -- the visible raid frames for each group layout, with a 25-player preview
  local container = CompactRaidFrameContainer
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_raid"
  if os.getenv("CRF_DUMP_CLASS") then
    H.state.player.class = os.getenv("CRF_DUMP_CLASS"); CRF_UpdateClassBarRoom()
    H.state.totems = { [2] = { name = "Earth", start = H.now - 60, duration = 300, icon = "e" }, [1] = { name = "Fire", start = H.now - 255, duration = 300, icon = "f" } }
  end
  CRF_SetRaidPreviewSize(tonumber(os.getenv("CRF_DUMP_SIZE") or 25))
  for i, layout in ipairs(CRF_GROUP_LAYOUTS) do
    CRF_SetGroupLayout(GetActiveRaidProfile(), layout, true)
    local cl = H.hspan(container)
    local _, ct = H.vspan(container)
    local f = io.open(out .. "_" .. layout.key .. ".tsv", "w")
    CRF_ForEachCompactUnitFrame(function(u)
      if u:IsVisible() and u.unit then
        local l, r = H.hspan(u); local b, t = H.vspan(u)
        f:write(table.concat({ u.unit:find("pet") and "pet" or "player", UnitName(u.unit) or "", string.format("%.1f", l - cl), string.format("%.1f", ct - t),
          string.format("%.1f", r - cl), string.format("%.1f", ct - b) }, "\t") .. "\n")
      end
    end)
    local bar = CompactRaidFrameClassBar
    if bar:IsVisible() then
      for slot = 1, 4 do H.FireEvent("PLAYER_TOTEM_UPDATE", slot) end
      for i = 1, bar.count do
        local box = bar.boxes[i]
        if box:IsVisible() then
          local l, r = H.hspan(box); local b, t = H.vspan(box)
          local v = box.fill.__vertex or { 1, 1, 1 }
          local icon = box.icon:IsVisible() and ({ "1,0.45,0.15", "0.55,0.75,0.25", "0.25,0.6,1", "0.75,0.75,1" })[box.totemSlot] or ""
          local t0 = box.icon:IsVisible() and H.state.totems[box.totemSlot]
          f:write(table.concat({ "box", box.timer:GetText() or "", string.format("%.1f", l - cl), string.format("%.1f", ct - t),
            string.format("%.1f", r - cl), string.format("%.1f", ct - b),
            string.format("%.2f,%.2f,%.2f,%.2f|%s|%.3f|0", v[1], v[2], v[3], box.fill:GetAlpha(), icon, t0 and (H.now - t0.start) / t0.duration or 0) }, "\t") .. "\n")
        end
      end
    end
    for g = 1, 8 do
      local gf = _G["CompactRaidGroup" .. g]
      if gf and gf:IsVisible() and gf.title then
        local l, r = H.hspan(gf.title); local b, t = H.vspan(gf.title)
        f:write(table.concat({ "title", gf.title:GetText() or ("Group " .. g), string.format("%.1f", l - cl), string.format("%.1f", ct - t),
          string.format("%.1f", r - cl), string.format("%.1f", ct - b) }, "\t") .. "\n")
      end
    end
    f:close()
  end
  CRF_SetRaidPreviewSize(nil)
  check(#H.errors == 0, "no errors while dumping raid layouts")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end

------------------------------------------------------------------------
if scenario == "dump-follow" then
  local m = CompactRaidFrameManager
  H.setParty({ { "Arthas", "DEATHKNIGHT" }, { "Jaina", "MAGE" } })
  CRF_RelayGroupRosterUpdate(); H.RunUpdates(0.05, 2)
  SetRaidProfileSavedPosition(GetActiveRaidProfile(), false, "TOP", 140, "BOTTOM", 400, "LEFT", 60)
  CompactRaidFrameManager_ResizeFrame_LoadPosition(m)
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_follow"
  for _, state in ipairs({ "closed", "open" }) do
    if state == "open" then CompactRaidFrameManager_Expand(m) else CompactRaidFrameManager_Collapse(m) end
    local f = io.open(out .. "_" .. state .. ".tsv", "w")
    local function row(kind, name, o)
      local l, r = H.hspan(o); local b, t = H.vspan(o)
      f:write(table.concat({ kind, name, string.format("%.1f", l), string.format("%.1f", 1080 - t), string.format("%.1f", r), string.format("%.1f", 1080 - b) }, "\t") .. "\n")
    end
    row("menu", "", m)
    CRF_ForEachCompactUnitFrame(function(u) if u:IsVisible() and u.unit then row("unit", UnitName(u.unit) or "", u) end end)
    f:close()
  end
  check(#H.errors == 0, "no errors while dumping")
end

------------------------------------------------------------------------
if scenario == "dump-manager" then
  -- the expanded raid manager (party, raid-style frames), relative to its top-left
  local m = CompactRaidFrameManager
  if os.getenv("CRF_GROUP") == "raidlead" then
    H.setRaid({ { "Kami", "PALADIN", 1 }, { "Arthas", "DEATHKNIGHT", 1 }, { "Jaina", "MAGE", 2 } })
  else
    H.setParty({ { "Arthas", "DEATHKNIGHT" } })
  end
  CRF_RelayGroupRosterUpdate()
  H.RunUpdates(0.016, 2)
  CompactRaidFrameManager_UpdateAll(m)
  local sizes = os.getenv("CRF_PREVIEW_SIZES")
  if sizes and CRF_SetRaidProfileOptionSaved then
    local h, w = sizes:match("(%d+),(%d+)")
    CRF_SetRaidProfileOptionSaved(GetActiveRaidProfile(), "frameHeight", tonumber(h))
    CRF_SetRaidProfileOptionSaved(GetActiveRaidProfile(), "frameWidth", tonumber(w))
    CompactUnitFrameProfiles_ApplyProfile(GetActiveRaidProfile())
  end
  CompactRaidFrameManager_Expand(m)
  local ml = H.hspan(m)
  local _, mt = H.vspan(m)
  local skip = { [CompactRaidFrameContainer] = true, [m.containerResizeFrame] = true }
  local f = io.open(os.getenv("CRF_DUMP") or "/tmp/crf_manager.tsv", "w")
  local function visit(o, depth)
    if skip[o] or not o.__shown then return end
    local l, r = H.hspan(o)
    local b, t = H.vspan(o)
    if l and b then
      local kind = o.__isDropDown and "DropDown" or o.__type
      local text = ""
      if o.__type == "FontString" then text = tostring(o.__text or "") end
      local extra = {}
      if o.__disabled then extra[#extra+1] = "disabled" end
      if o.__type == "Texture" and type(o.__texture) == "string" then extra[#extra+1] = "tex=" .. o.__texture:match("([^\\]+)$") end
      if (o.__alpha or 1) < 1 then extra[#extra+1] = "alpha=" .. o.__alpha end
      if o.__type == "Slider" then
        local lo, hi = o:GetMinMaxValues()
        extra[#extra+1] = string.format("value=%s;min=%s;max=%s", tostring(o:GetValue()), tostring(lo), tostring(hi))
      end
      f:write(table.concat({ kind, o.__name or "", (text:gsub("[\t\n]", " ")), string.format("%.1f", l - ml), string.format("%.1f", mt - t),
        string.format("%.1f", r - ml), string.format("%.1f", mt - b), table.concat(extra, ","), tostring(depth) }, "\t") .. "\n")
    end
    for _, rg in ipairs(o.__regions or {}) do if rg.__shown then visit(rg, depth + 1) end end
    for _, c in ipairs(o.__children or {}) do visit(c, depth + 1) end
  end
  visit(m, 0)
  f:close()
  check(#H.errors == 0, "no errors while dumping the manager")
end
------------------------------------------------------------------------
if scenario == "dump" then
  -- write the visible layout of the options panel (one file per tab) for rendering
  local panel = CompactUnitFrameProfiles
  InterfaceOptionsFrame_OpenToCategory(panel)
  local sizes = os.getenv("CRF_PREVIEW_SIZES")   -- e.g. "90,172": frame height,width for the picture
  if sizes then
    local h, w = sizes:match("(%d+),(%d+)")
    SetRaidProfileOption(GetActiveRaidProfile(), "frameHeight", tonumber(h))
    SetRaidProfileOption(GetActiveRaidProfile(), "frameWidth", tonumber(w))
    SaveRaidProfileCopy(GetActiveRaidProfile())
    CompactUnitFrameProfiles_UpdateCurrentPanel()
  end
  if os.getenv("CRF_DUMP_POWERTEXT") then   -- power bars on, with a power bar text setting
    SetRaidProfileOption(GetActiveRaidProfile(), "displayPowerBar", true)
    SetRaidProfileOption(GetActiveRaidProfile(), "powerText", os.getenv("CRF_DUMP_POWERTEXT"))
    SaveRaidProfileCopy(GetActiveRaidProfile())
    CompactUnitFrameProfiles_UpdateCurrentPanel()
  end
  local pl, pr = H.hspan(panel)
  local pb, pt = H.vspan(panel)
  local function dumpTo(path)
    local f = io.open(path, "w")
    local function visit(o, depth)
      if not o.__shown then return end
      if o.__strata == "DIALOG" then return end
      local l, r = H.hspan(o)
      local b, t = H.vspan(o)
      if l and b then
        local kind = o.__type
        if o.__isDropDown then kind = "DropDown" end
        local name = o.__name or ""
        local text = ""
        if o.__type == "FontString" then text = tostring(o.__text or "") end
        if o.__type == "Button" or o.__type == "CheckButton" then text = tostring(o.GetText and o:GetText() or "") end
        local extra = {}
        if o.__type == "CheckButton" then extra[#extra+1] = o:GetChecked() and "checked" or "unchecked" end
        if o.__disabled then extra[#extra+1] = "disabled" end
        if o.__activeArt then extra[#extra+1] = "activeart" end
        if o.__type == "Slider" then extra[#extra+1] = "value=" .. tostring(o.__value) .. ",min=" .. tostring(o.__min) .. ",max=" .. tostring(o.__max) end
        if o.__backdrop then extra[#extra+1] = "backdrop" end
        if o.__color then extra[#extra+1] = "red" end
        if o.__type == "Texture" and o.__texture and type(o.__texture) == "number" then extra[#extra+1] = "solid" end
        f:write(table.concat({ kind, name, (text:gsub("[\t\n]", " ")), string.format("%.1f", l - pl), string.format("%.1f", pt - t),
          string.format("%.1f", r - pl), string.format("%.1f", pt - b), table.concat(extra, ","), tostring(depth) }, "\t") .. "\n")
      end
      for _, rg in ipairs(o.__regions or {}) do if rg.__shown then visit(rg, depth + 1) end end
      for _, c in ipairs(o.__children or {}) do visit(c, depth + 1) end
    end
    visit(panel, 0)
    f:close()
  end
  local out = os.getenv("CRF_DUMP") or "/tmp/crf_layout"
  local opts = panel.optionsFrame
  if opts and opts.pages then
    for i = 1, #opts.pages do
      _G[opts:GetName() .. "Tab" .. i]:Click()
      dumpTo(out .. "_tab" .. i .. ".tsv")
    end
  else
    dumpTo(out .. "_orig.tsv")
  end
  check(#H.errors == 0, "no errors while dumping")
end
------------------------------------------------------------------------
if scenario == "persist-write" then
  section("Write saved variables")
  CompactRaidFrameAccountDB.someProfileEdit = nil
  local always = _G["CompactUnitFrameProfilesOptionsGeneralAlwaysShow"]
  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  always:Click()                                  -- on (default is off)
  _G["CompactUnitFrameProfilesOptionsGeneralRaidStylePartyFrames"]:Click()   -- off
  _G["CompactUnitFrameProfilesOptionsGeneralManagerTabMouseover"]:Click()     -- off
  _G["CompactUnitFrameProfilesOptionsGeneralHidePlayerFrame"]:Click()         -- off
  _G["CompactUnitFrameProfilesOptionsGeneralShowResting"]:Click()             -- off
  check(#H.errors == 0, "no errors")
end
if scenario == "persist-read" then
  section("After reload")
  check(CRF_IsAlwaysEnabled() == true, "Always show is still on after reload")
  check(CUF_CVar:GetCVarBool("useCompactPartyFrames") == false, "raid-style party frames still off after reload")
  check(CompactRaidFrameManager:IsShown(), "solo + Always show: manager shown after reload")
  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  check(_G["CompactUnitFrameProfilesOptionsGeneralAlwaysShow"]:GetChecked(), "checkbox shows it ticked")
  check(CRF_IsManagerTabFadeEnabled() == false and not _G["CompactUnitFrameProfilesOptionsGeneralManagerTabMouseover"]:GetChecked(), "tab-on-mouseover setting still off after reload")
  check(CRF_IsHidePlayerFrameEnabled() == false and not _G["CompactUnitFrameProfilesOptionsGeneralHidePlayerFrame"]:GetChecked()
    and PlayerFrame:IsShown(), "hide-player-frame setting still off after reload (frame shown)")
  check(CRF_IsShowRestingEnabled() == false and not _G["CompactUnitFrameProfilesOptionsGeneralShowResting"]:GetChecked(),
    "show-resting setting still off after reload")
  check(#H.errors == 0, "no errors")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end

-- upgrade path: the ORIGINAL addon writes saved data, the NEW addon reads it
if scenario == "upgrade-write" then
  section("Old version: create and activate a customised profile")
  CreateNewRaidProfile("Healer", GetActiveRaidProfile())
  SetRaidProfileOption("Healer", "useClassColors", true)
  SetRaidProfileOption("Healer", "frameHeight", 60)
  SetRaidProfileOption("Healer", "frameWidth", 100)
  SetRaidProfileOption("Healer", "healthText", "perc")
  SetRaidProfileOption("Healer", "keepGroupsTogether", true)
  SetRaidProfileOption("Healer", "autoActivate25Players", true)
  SetRaidProfileOption("Healer", "autoActivatePvE", true)
  SetRaidProfileSavedPosition("Healer", false, "TOP", 120, "BOTTOM", 300, "LEFT", 40)
  SaveRaidProfileCopy("Healer")
  CompactUnitFrameProfiles_ActivateRaidProfile("Healer")
  H.RunUpdates(0.1, 3)
  check(GetActiveRaidProfile() == "Healer", "Healer profile active in the old version")
  check(#H.errors == 0, "no errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end
if scenario == "upgrade-read" then
  section("New version loading the old version's saved data")
  check(RaidProfileExists("Healer") and RaidProfileExists(DEFAULT_CUF_PROFILE_NAME), "both profiles carried over")
  check(GetActiveRaidProfile() == "Healer", "active profile carried over")
  check(GetRaidProfileOption("Healer", "useClassColors") == true and GetRaidProfileOption("Healer", "frameHeight") == 60
    and GetRaidProfileOption("Healer", "frameWidth") == 100 and GetRaidProfileOption("Healer", "healthText") == "perc"
    and GetRaidProfileOption("Healer", "keepGroupsTogether") == true, "profile options carried over")
  local isDynamic, topPoint, topOffset, bottomPoint, bottomOffset, leftPoint, leftOffset = GetRaidProfileSavedPosition("Healer")
  print("     position:", isDynamic, topPoint, topOffset, bottomPoint, bottomOffset, leftPoint, leftOffset)
  check(not isDynamic and topPoint == "TOP" and topOffset == 120 and bottomPoint == "BOTTOM" and bottomOffset == 300
    and leftPoint == "LEFT" and leftOffset == 40, "saved frame position carried over")
  check(not RaidProfileHasUnsavedChanges(), "no phantom unsaved changes after upgrade")
  check(CRF_IsAlwaysEnabled() == false, "Always show starts unticked (the old version never saved it; new default)")
  check(CRF_IsManagerTabFadeEnabled() == true, "tab-on-mouseover starts on")
  check(CUF_CVar:GetCVarBool("useCompactPartyFrames") == true, "raid-style party frames still on")
  InterfaceOptionsFrame_OpenToCategory(CompactUnitFrameProfiles)
  check(UIDropDownMenu_GetSelectedValue(CompactUnitFrameProfilesProfileSelector) == "Healer", "panel opens on the Healer profile")
  _G["CompactUnitFrameProfilesOptionsTab2"]:Click()
  check(_G["CompactUnitFrameProfilesOptionsLayoutGroupsDropdownText"]:GetText() == CRF_GROUPS_SHORT_SEPARATE_VERTICAL, "Layout tab shows Separate (Vertical) (old Keep Groups Together)")
  check(_G["CompactUnitFrameProfilesOptionsLayoutHeightSlider"]:GetValue() == 60
    and _G["CompactUnitFrameProfilesOptionsLayoutWidthSlider"]:GetValue() == 100, "Layout tab sliders show 60 x 100")
  _G["CompactUnitFrameProfilesOptionsTab3"]:Click()
  check(_G["CompactUnitFrameProfilesOptionsDisplayUseClassColors"]:GetChecked(), "Display tab shows class colours ticked")
  check(_G["CompactUnitFrameProfilesOptionsDisplayDisplayHealPrediction"]:GetChecked() and GetRaidProfileOption("Healer", "displayHealPrediction") == true
    and GetRaidProfileOption("Primary", "displayHealPrediction") == true, "Display Incoming Heals is on for old profiles")
  check(not RaidProfileHasUnsavedChanges(), "the one-time update is not an unsaved change")
  _G["CompactUnitFrameProfilesOptionsTab4"]:Click()
  check(_G["CompactUnitFrameProfilesOptionsAutoActivateAutoActivate25Players"]:GetChecked()
    and _G["CompactUnitFrameProfilesOptionsAutoActivateAutoActivatePvE"]:GetChecked(), "Auto-Activate tab shows 25 Player + PvE ticked")
  check(not RaidProfileHasUnsavedChanges(), "browsing the tabs does not create unsaved changes")
  -- 1.22: new defaults are for new profiles only; old profiles get power bar text "None"
  local P = DEFAULT_CUF_PROFILE_NAME
  check(writerOptionsVersion >= 3 or GetRaidProfileOption(P, "frameWidth") == 72 and GetRaidProfileOption(P, "frameHeight") == 36 and GetRaidProfileOption(P, "displayBorder") == true
    and not GetRaidProfileOption(P, "autoActivate10Players") and not GetRaidProfileOption("Healer", "autoActivate10Players"),
    "old profiles keep their size, border and auto-activation (new defaults are for new profiles)")
  check(GetRaidProfileOption("Healer", "powerText") == "none" and GetRaidProfileOption(P, "powerText") == "none"
    and CompactRaidFrameAccountDB.crfOptionsVersion == 4, "old profiles: Display Power Bar Text = None")
  check(GetRaidProfileOption("Healer", "sortPlayerFirst") == true and GetRaidProfileOption(P, "sortPlayerFirst") == true,
    "old profiles: Keep Me at the Top ticked")
  _G["CompactUnitFrameProfilesOptionsTab3"]:Click()
  check(_G["CompactUnitFrameProfilesOptionsDisplayPowerTextDropdownText"]:GetText() == COMPACT_UNIT_FRAME_PROFILE_POWERTEXT_NONE
    and not RaidProfileHasUnsavedChanges(), "Display tab shows None, no unsaved changes")
  check(#H.errors == 0, "no errors (" .. #H.errors .. ")")
  for _, e in ipairs(H.errors) do print("     " .. e) end
end

if svOut then
  local f = io.open(svOut, "w")
  f:write("return {\n")
  for _, v in ipairs(svars) do f:write("  [" .. string.format("%q", v) .. "] = " .. ser(_G[v], "  ") .. ",\n") end
  f:write("}\n")
  f:close()
end

------------------------------------------------------------------------
local mm = {}
for k, n in pairs(H.missingMethods) do mm[#mm+1] = k end
table.sort(mm)
if #mm > 0 then print("\n(unmocked widget methods called: " .. table.concat(mm, ", ") .. ")") end
print(string.format("\n%d passed, %d failed", results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)
