-- Only define it if the client doesn't (re-assigning a Blizzard global taints it).
if ( NUM_RAID_ICONS == nil ) then
    NUM_RAID_ICONS = 8;
end

MINIMUM_RAID_CONTAINER_HEIGHT = 72;
local RESIZE_HORIZONTAL_OUTSETS = 4;
local RESIZE_VERTICAL_OUTSETS = 7;

local UnitGroupRolesAssigned = C_UnitGroupRolesAssigned;
local PLAYER_REGEN_ENABLED_AWAIT;   -- secure manager update postponed by combat
local BOUNDS_UPDATE_AWAIT;          -- screen size/scale change postponed by combat
local PLAYER_FRAME_UPDATE_AWAIT;    -- player frame visibility rule postponed by combat

local function  CompactRaidFrameManager_Toggle_OnLoad(self)
    local toggleButton = self.toggleButton;

    toggleButton:SetAttribute("_onclick", [=[
        local toggleButtonShown = self:GetAttribute("toggleButtonShown");
        local displayFrame = self:GetFrameRef("displayFrame");
        local X;

        if ( toggleButtonShown ) then
            displayFrame:Hide();
            X = -182;
        else
            displayFrame:Show();
            X = -7;
        end

        self:GetParent():SetPoint("TOPLEFT", UIParent, "TOPLEFT", X, -140);
        self:SetAttribute("toggleButtonShown", not toggleButtonShown);
    ]=]);

    toggleButton:SetFrameRef("displayFrame", self.displayFrame);
    toggleButton:GetNormalTexture():SetDrawLayer("OVERLAY");
end

-- "Show raid manager tab only on mouseover" (CRF_IsManagerTabFadeEnabled).
-- While the manager is collapsed, the tab left on screen (its border art and the
-- toggle button) fades out, and fades back in while the mouse is over it.
-- Only those pieces are faded: the raid frame container is parented to the
-- manager, so fading the manager itself would fade the raid frames as well.
-- SetAlpha is allowed on secure frames in combat, so this also works in combat.
local TAB_FADE_IN_TIME = 0.15;   -- seconds to fade in under the mouse
local TAB_FADE_OUT_TIME = 0.4;   -- seconds to fade out
local TAB_FADE_OUT_DELAY = 0.5;  -- seconds it stays after the mouse leaves

local function CompactRaidFrameManager_SetTabAlpha(self, alpha)
    self.tabAlpha = alpha;
    for _, region in ipairs(self.tabRegions) do
        region:SetAlpha(region.crfTabBaseAlpha * alpha);
    end
    self.toggleButton:SetAlpha(alpha);
end

-- The collapsed tab is the part of the manager still on screen, so this is
-- simply "is the cursor inside the manager's rectangle".
local function CompactRaidFrameManager_IsCursorOverTab(self)
    local left, right = self:GetLeft(), self:GetRight();
    local top, bottom = self:GetTop(), self:GetBottom();
    if ( not (left and right and top and bottom) ) then
        return false;
    end
    local x, y = GetCursorPosition();
    local scale = self:GetEffectiveScale();
    x, y = x / scale, y / scale;
    return x >= left and x <= right and y >= bottom and y <= top;
end

local function CompactRaidFrameManager_TabFade_OnUpdate(watcher, elapsed)
    local manager = watcher.manager;
    local expanded = manager.displayFrame:IsShown();
    local target = 1;
    if ( expanded or not CRF_IsManagerTabFadeEnabled() or CompactRaidFrameManager_IsCursorOverTab(manager) ) then
        watcher.awayTime = 0;
    else
        watcher.awayTime = watcher.awayTime + elapsed;
        if ( watcher.awayTime >= TAB_FADE_OUT_DELAY ) then
            target = 0;
        end
    end

    local alpha = manager.tabAlpha;
    if ( alpha == target ) then
        return;
    end
    if ( expanded ) then
        alpha = 1;  -- the open panel never fades
    elseif ( alpha < target ) then
        alpha = min(target, alpha + elapsed / TAB_FADE_IN_TIME);
    else
        alpha = max(target, alpha - elapsed / TAB_FADE_OUT_TIME);
    end
    CompactRaidFrameManager_SetTabAlpha(manager, alpha);
end

-- When the manager appears (joining a group, a loading screen, ...) start out
-- hidden instead of flashing up and then fading.
local function CompactRaidFrameManager_TabFade_OnShow(watcher)
    local manager = watcher.manager;
    if ( CRF_IsManagerTabFadeEnabled() and not manager.displayFrame:IsShown()
        and not CompactRaidFrameManager_IsCursorOverTab(manager) ) then
        watcher.awayTime = TAB_FADE_OUT_DELAY;
        CompactRaidFrameManager_SetTabAlpha(manager, 0);
    end
end

local function CompactRaidFrameManager_TabFade_OnLoad(self)
    -- The manager's own textures: its border and background (the tab art).
    self.tabRegions = { self:GetRegions() };
    for _, region in ipairs(self.tabRegions) do
        region.crfTabBaseAlpha = region:GetAlpha() or 1;
    end
    self.tabAlpha = 1;

    -- A plain (non-secure) child, so its OnUpdate only runs while the manager
    -- is on screen.
    local watcher = CreateFrame("Frame", nil, self);
    watcher.manager = self;
    watcher.awayTime = 0;
    watcher:SetScript("OnUpdate", CompactRaidFrameManager_TabFade_OnUpdate);
    watcher:SetScript("OnShow", CompactRaidFrameManager_TabFade_OnShow);
    self.tabFadeWatcher = watcher;
end

function CompactRaidFrameManager_OnLoad(self)
    self.container = CompactRaidFrameContainer;
    self.container:SetParent(self);

    self:RegisterEvent("DISPLAY_SIZE_CHANGED");
    self:RegisterEvent("UI_SCALE_CHANGED");
    self:RegisterEvent("GROUP_ROSTER_UPDATE");
    self:RegisterEvent("UNIT_FLAGS");
    self:RegisterEvent("PLAYER_FLAGS_CHANGED");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("PARTY_LEADER_CHANGED");
    self:RegisterEvent("RAID_TARGET_UPDATE");
    self:RegisterEvent("PLAYER_TARGET_CHANGED");
    self:RegisterEvent("PLAYER_REGEN_ENABLED");
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED");

    -- 3.3.5a: the retail "[group]" macro conditional does not exist, and the
    -- "@unit" alias is 4.0+ (an unknown condition evaluates false, which made
    -- this driver a constant "hide"). Use the native target=unit,exists form
    -- (in a raid raid1 exists; in a party party1 exists; solo neither -> hide),
    -- so the secure driver works even in combat.
    -- CompactRaidFrameManager_UpdateShown is the event-driven backstop.
    -- (Now chosen by CompactRaidFrameManager_UpdateVisibilityDriver so the
    -- "Always show" option can override it.)
    CompactRaidFrameManager_UpdateVisibilityDriver(self);

    self.containerResizeFrame:SetMinResize(self.container:GetWidth(), MINIMUM_RAID_CONTAINER_HEIGHT + RESIZE_VERTICAL_OUTSETS * 2 + 1);
    self.dynamicContainerPosition = true;

    CompactRaidFrameContainer_SetFlowFilterFunction(self.container, CRFFlowFilterFunc);
    CompactRaidFrameContainer_SetGroupFilterFunction(self.container, CRFGroupFilterFunc);
    CompactRaidFrameManager_UpdateContainerBounds(self);
    CompactRaidFrameManager_ResizeFrame_Reanchor(self);
    CompactRaidFrameManager_AttachPartyFrames(self);

    CompactRaidFrameManager_Collapse(self);

    -- CompactRaidFrameManager_Toggle
    CompactRaidFrameManager_Toggle_OnLoad(self)
    CompactRaidFrameManager_TabFade_OnLoad(self);

    self.displayFrame.resetPosition:SetText(RESET_POSITION or "Reset Position");
    C_UIDropDownMenu_SetWidth(self.displayFrame.groupsSelector, 165);
    C_UIDropDownMenu_SetWidth(self.displayFrame.previewSelector, 165);

    --Set up the options flow container
    FlowContainer_Initialize(self.displayFrame.optionsFlowContainer);

    -- The "Always show (even when solo)" option now lives in the Raid Profiles
    -- options panel (Interface > AddOns > Raid Profiles > General).
end

function CompactRaidFrameManager_OnEvent(self, event, ...)
    if ( event == "PLAYER_REGEN_ENABLED" ) then
        if ( BOUNDS_UPDATE_AWAIT ) then
            BOUNDS_UPDATE_AWAIT = nil;
            CompactRaidFrameManager_UpdateContainerBounds(self);
        end
        if ( PLAYER_REGEN_ENABLED_AWAIT ) then
            CompactRaidFrameManager_UpdateAll(self);
        end
        if ( PLAYER_FRAME_UPDATE_AWAIT ) then
            CRF_UpdatePlayerFrameVisibility();
        end
    elseif ( event == "RAID_TARGET_UPDATE" or event == "PLAYER_TARGET_CHANGED" ) then
        CompactRaidFrameManager_UpdateRaidIcons();
    elseif ( event == "UNIT_FLAGS" or event == "PLAYER_FLAGS_CHANGED" or event == "PLAYER_ROLES_ASSIGNED" ) then
        -- Text and plain (non-secure) buttons only, so this also runs in combat:
        -- the alive/total counts no longer freeze until combat ends.
        CompactRaidFrameManager_UpdateDisplayCounts(self);
    elseif ( event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" ) then
        if ( InCombatLockdown() ) then
            BOUNDS_UPDATE_AWAIT = true;
        else
            CompactRaidFrameManager_UpdateContainerBounds(self);
        end
    elseif ( event == "GROUP_ROSTER_UPDATE" ) then -- or UPDATE_ACTIVE_BATTLEFIELD
        CompactRaidFrameManager_UpdateDisplayCounts(self);
        CompactRaidFrameManager_UpdateAll(self);
    elseif ( event == "PLAYER_ENTERING_WORLD" or event == "PARTY_LEADER_CHANGED" ) then
        CompactRaidFrameManager_UpdateAll(self);
    end
end

-- Everything that depends on group / visibility state. It shows, hides and
-- resizes the secure manager and container, so in combat it is postponed and
-- replayed (in full) on PLAYER_REGEN_ENABLED. Previously only part of the
-- GROUP_ROSTER_UPDATE work was replayed, leaving e.g. the Raid/Party Members
-- label and the container lock state stale after a roster change in combat.
function CompactRaidFrameManager_UpdateAll(self)
    self = self or CompactRaidFrameManager;
    if ( InCombatLockdown() ) then
        PLAYER_REGEN_ENABLED_AWAIT = true;
        return false;
    end
    PLAYER_REGEN_ENABLED_AWAIT = nil;

    CompactRaidFrameManager_UpdateVisibilityDriver(self);
    RaidOptionsFrame_UpdatePartyFrames();
    CompactRaidFrameManager_UpdateShown(self);
    CompactRaidFrameManager_UpdateDisplayCounts(self);
    CompactRaidFrameManager_UpdateLabel(self);
    CompactRaidFrameManager_UpdateContainerLockVisibility(self);
    CompactRaidFrameManager_UpdateRaidIcons();
    CRF_UpdatePlayerFrameVisibility();
    return true;
end

function CompactRaidFrameManagerDisplayFrameProfileSelector_SetUp(self)
    C_UIDropDownMenu_SetWidth(self, 165);
    C_UIDropDownMenu_Initialize(self, CompactRaidFrameManagerDisplayFrameProfileSelector_Initialize);
end

function CompactRaidFrameManagerDisplayFrameProfileSelector_Initialize()
    local info = C_UIDropDownMenu_CreateInfo();

    for i=1, GetNumRaidProfiles() do
        local name = GetRaidProfileName(i);
        info.text = name;
        info.value = name;
        info.func = CompactRaidFrameManagerDisplayFrameProfileSelector_OnClick;
        info.disabled  = InCombatLockdown();
        info.checked = GetActiveRaidProfile() == info.value;
        info.isRadio = true;
        C_UIDropDownMenu_AddButton(info);
    end
end

function CompactRaidFrameManagerDisplayFrameProfileSelector_OnClick(self)
    local profile = self.value;
    CompactUnitFrameProfiles_ActivateRaidProfile(profile);
end

-- Groups: the active profile's group layout. Unlike the options panel this
-- applies and saves at once (other unsaved panel edits stay unsaved).
function CompactRaidFrameManagerDisplayFrameGroupsSelector_SetUp(self)
    C_UIDropDownMenu_SetWidth(self, 165);
    C_UIDropDownMenu_Initialize(self, CompactRaidFrameManagerDisplayFrameGroupsSelector_Initialize);
    C_UIDropDownMenu_SetText(self, CRF_GetGroupLayoutText(CRF_GetGroupLayout(GetActiveRaidProfile())));
end

function CompactRaidFrameManagerDisplayFrameGroupsSelector_Initialize()
    local current = CRF_GetGroupLayout(GetActiveRaidProfile());
    for _, layout in ipairs(CRF_GROUP_LAYOUTS) do
        local info = C_UIDropDownMenu_CreateInfo();
        info.text = CRF_GetGroupLayoutText(layout);
        info.value = layout.key;
        info.arg1 = layout;
        info.func = CompactRaidFrameManagerDisplayFrameGroupsSelector_OnClick;
        info.checked = (layout == current);
        info.disabled = InCombatLockdown();
        C_UIDropDownMenu_AddButton(info);
    end
end

function CompactRaidFrameManagerDisplayFrameGroupsSelector_OnClick(button, layout)
    if ( InCombatLockdown() ) then
        DEFAULT_CHAT_FRAME:AddMessage(COMPACT_UNIT_FRAME_ERRCOMBAT);
        return;
    end
    CRF_SetGroupLayout(GetActiveRaidProfile(), layout, true);
end

-- Raid size preview (CRF_SetRaidPreviewSize, CompactRaidFrameContainer.lua).
function CompactRaidFrameManagerDisplayFramePreviewSelector_SetUp(self)
    C_UIDropDownMenu_SetWidth(self, 165);
    C_UIDropDownMenu_Initialize(self, CompactRaidFrameManagerDisplayFramePreviewSelector_Initialize);
    C_UIDropDownMenu_SetText(self, CRF_GetRaidPreviewLabel(CRF_GetRaidPreviewSize()));
end

function CompactRaidFrameManagerDisplayFramePreviewSelector_Initialize()
    CRF_AddRaidPreviewMenuButtons(CompactRaidFrameManagerDisplayFramePreviewSelector_OnClick);
end

function CompactRaidFrameManagerDisplayFramePreviewSelector_OnClick(button, size)
    CRF_SetRaidPreviewSize(size);
end

-- Keeps the side bar's Groups / preview text current (profile switches,
-- changes made in the options panel, preview on/off).
function CompactRaidFrameManager_UpdateLayoutSelectors()
    local displayFrame = CompactRaidFrameManager.displayFrame;
    C_UIDropDownMenu_SetText(displayFrame.groupsSelector, CRF_GetGroupLayoutText(CRF_GetGroupLayout(GetActiveRaidProfile())));
    C_UIDropDownMenu_SetText(displayFrame.previewSelector, CRF_GetRaidPreviewLabel(CRF_GetRaidPreviewSize()));
end

--------------------------------------------------------------------------
-- "Hide player frame when raid frames are shown" (CRF_IsHidePlayerFrameEnabled).
-- A secure visibility driver on PlayerFrame, so it follows joining and leaving
-- groups even in combat. Its condition mirrors GetDisplayedAllyFrames (which
-- frames are in use), rebuilt whenever the settings behind it change.
--------------------------------------------------------------------------
local playerFrameDriven;    -- our driver is registered on PlayerFrame

local function CompactRaidFrameManager_GetPlayerFrameCondition()
    if ( not CRF_IsHidePlayerFrameEnabled() ) then
        return nil;
    end
    if ( not CompactRaidFrameManager.container.enabled ) then
        return nil;     -- raid frames hidden with the manager's Hide button
    end
    -- In a vehicle the player frame shows the vehicle, which the raid frames don't.
    if ( CRF_GetRaidPreviewSize() ) then
        return "[vehicleui]show;hide";
    end
    local party = CUF_CVar:GetCVarBool("useCompactPartyFrames") and "hide" or "show";
    local solo = CRF_IsAlwaysEnabled() and "hide" or "show";
    return "[vehicleui]show;[target=raid1,exists]hide;[target=party1,exists]"..party..";"..solo;
end

function CRF_UpdatePlayerFrameVisibility()
    if ( not PlayerFrame ) then
        return;
    end
    if ( InCombatLockdown() ) then
        PLAYER_FRAME_UPDATE_AWAIT = true;
        return;
    end
    PLAYER_FRAME_UPDATE_AWAIT = nil;

    local condition = CompactRaidFrameManager_GetPlayerFrameCondition();
    if ( condition ) then
        RegisterStateDriver(PlayerFrame, "visibility", condition);
        playerFrameDriven = true;
    elseif ( playerFrameDriven ) then
        -- Only undo our own hiding (another addon may hide it for good).
        UnregisterStateDriver(PlayerFrame, "visibility");
        PlayerFrame:Show();
        playerFrameDriven = nil;
    end
end

-- Totem timers and Death Knight runes are children of the player frame. While
-- it is hidden for the raid frames they move to UIParent (same place on
-- screen) and go back when it shows. Neither is a secure frame, so this also
-- works when the player frame hides or shows in combat.
local CLASS_BARS = { "TotemFrame", "RuneFrame" };
local function CompactRaidFrameManager_KeepClassBars(playerFrameShown)
    for _, name in ipairs(CLASS_BARS) do
        local bar = _G[name];
        if ( bar ) then
            if ( playerFrameShown ) then
                if ( bar.crfReparented ) then
                    bar:SetParent(PlayerFrame);
                    bar.crfReparented = nil;
                end
            elseif ( bar:GetParent() == PlayerFrame ) then
                bar:SetParent(UIParent);
                bar.crfReparented = true;
            end
        end
    end
end

if ( PlayerFrame ) then
    PlayerFrame:HookScript("OnHide", function()
        if ( playerFrameDriven ) then
            CompactRaidFrameManager_KeepClassBars(false);
        end
    end);
    PlayerFrame:HookScript("OnShow", function()
        CompactRaidFrameManager_KeepClassBars(true);
    end);
end

function CompactRaidFrameManager_UpdateShown(self)
    if ( InCombatLockdown() ) then
        -- Show/Hide/SetHeight on the secure manager are blocked in combat.
        PLAYER_REGEN_ENABLED_AWAIT = true;
        return;
    end
    if ( GetDisplayedAllyFrames() ) then
        self:Show();
    else
        self:Hide();
    end
    CompactRaidFrameManager_UpdateOptionsFlowContainer(self);
    CompactRaidFrameManager_UpdateContainerVisibility();
end

-- Chooses the secure visibility driver for the manager. With "Always show" the
-- manager (and the container it parents) is shown even when solo; otherwise only
-- when a raid/party member exists. Out of combat only (secure frame).
function CompactRaidFrameManager_UpdateVisibilityDriver(self)
    if ( InCombatLockdown() ) then
        return false;
    end
    if ( CRF_IsAlwaysEnabled() or CRF_GetRaidPreviewSize() ) then
        RegisterStateDriver(self, "visibility", "show");
    else
        RegisterStateDriver(self, "visibility", "[target=raid1,exists][target=party1,exists]show;hide");
    end
    return true;
end

-- CRF_SetAlwaysEnabled() (the "Always show" option) is defined in
-- CUFProfiles\CUFProfilesAPI.lua; it saves the setting and calls
-- CompactRaidFrameManager_UpdateAll().

function CompactRaidFrameManager_UpdateLabel(self)
    if ( IsInRaid() ) then
        self.displayFrame.label:SetText(RAID_MEMBERS);
    else
        self.displayFrame.label:SetText(PARTY_MEMBERS);
    end
end

function CompactRaidFrameManager_Toggle(self)
    if ( self.collapsed ) then
        CompactRaidFrameManager_Expand(self);
    else
        CompactRaidFrameManager_Collapse(self);
    end
end

function CompactRaidFrameManager_Expand(self)
    self.collapsed = false;
    self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -7, -140);
    self.displayFrame:Show();
    self.toggleButton:GetNormalTexture():SetTexCoord(0.5, 1, 0, 1);
end

function CompactRaidFrameManager_Collapse(self)
    self.collapsed = true;
    self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -182, -140);
    self.displayFrame:Hide();
    self.toggleButton:GetNormalTexture():SetTexCoord(0, 0.5, 0, 1);
end

function CompactRaidFrameManager_UpdateOptionsFlowContainer(self)
    local container = self.displayFrame.optionsFlowContainer;

    FlowContainer_RemoveAllObjects(container);
    FlowContainer_PauseUpdates(container);

    if ( GetDisplayedAllyFrames() == "raid" ) then
        -- One per row. (A dropdown is only 40px wide until its OnShow sets the
        -- width, which can be after this layout, so they would share a row.)
        FlowContainer_AddObject(container, self.displayFrame.profileSelector);
        FlowContainer_AddLineBreak(container);
        FlowContainer_AddObject(container, self.displayFrame.groupsSelector);
        FlowContainer_AddLineBreak(container);
        FlowContainer_AddObject(container, self.displayFrame.previewSelector);
        FlowContainer_AddLineBreak(container);
        self.displayFrame.profileSelector:Show();
        self.displayFrame.groupsSelector:Show();
        self.displayFrame.previewSelector:Show();
        CompactRaidFrameManager_UpdateLayoutSelectors();
    else
        self.displayFrame.profileSelector:Hide();
        self.displayFrame.groupsSelector:Hide();
        self.displayFrame.previewSelector:Hide();
    end

    if ( IsInRaid() ) then
        FlowContainer_AddObject(container, self.displayFrame.filterOptions);
        self.displayFrame.filterOptions:Show();
    else
        self.displayFrame.filterOptions:Hide();
    end

    if ( not IsInRaid() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") ) then
        FlowContainer_AddObject(container, self.displayFrame.raidMarkers);
        self.displayFrame.raidMarkers:Show();
    else
        self.displayFrame.raidMarkers:Hide();
    end

    if ( not IsInRaid() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") ) then
        FlowContainer_AddObject(container, self.displayFrame.leaderOptions);
        self.displayFrame.leaderOptions:Show();
    else
        self.displayFrame.leaderOptions:Hide();
    end

    if ( not IsInRaid() and UnitIsGroupLeader("player") and not HasLFGRestrictions() ) then
        FlowContainer_AddLineBreak(container);
        FlowContainer_AddSpacer(container, 20);
        FlowContainer_AddObject(container, self.displayFrame.convertToRaid);
        self.displayFrame.convertToRaid:Show();
    else
        self.displayFrame.convertToRaid:Hide();
    end

    if ( GetDisplayedAllyFrames() == "raid" ) then
        FlowContainer_AddLineBreak(container);
        FlowContainer_AddSpacer(container, 20);
        FlowContainer_AddObject(container, self.displayFrame.lockedModeToggle);
        FlowContainer_AddObject(container, self.displayFrame.hiddenModeToggle);
        -- Reset Position on its own row under Lock / Hide.
        FlowContainer_AddLineBreak(container);
        FlowContainer_AddSpacer(container, 20);
        FlowContainer_AddObject(container, self.displayFrame.resetPosition);
        self.displayFrame.lockedModeToggle:Show();
        self.displayFrame.hiddenModeToggle:Show();
        self.displayFrame.resetPosition:Show();
    else
        self.displayFrame.lockedModeToggle:Hide();
        self.displayFrame.hiddenModeToggle:Hide();
        self.displayFrame.resetPosition:Hide();
    end
    if ( IsInRaid() and UnitIsGroupLeader("player") ) then
        FlowContainer_AddLineBreak(container);
        FlowContainer_AddSpacer(container, 20);
        FlowContainer_AddObject(container, self.displayFrame.everyoneIsAssistButton);
        self.displayFrame.everyoneIsAssistButton:Show();
    else
        self.displayFrame.everyoneIsAssistButton:Hide();
    end

    FlowContainer_ResumeUpdates(container);

    local usedX, usedY = FlowContainer_GetUsedBounds(container);
    self:SetHeight(usedY + 40);

    --Then, we update which specific buttons are enabled.

    --Any sort of leader may initiate a ready check.
    if ( IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) ) then
        self.displayFrame.leaderOptions.readyCheckButton:Enable();
        self.displayFrame.leaderOptions.readyCheckButton:SetAlpha(1);
    else
        self.displayFrame.leaderOptions.readyCheckButton:Disable();
        self.displayFrame.leaderOptions.readyCheckButton:SetAlpha(0.5);
    end
end

function CompactRaidFrameManager_UpdateDisplayCounts(self)
    CRF_CountStuff();
    CompactRaidFrameManager_UpdateHeaderInfo(self);
    CompactRaidFrameManager_UpdateFilterInfo(self)
end

function CompactRaidFrameManager_UpdateHeaderInfo(self)
    self.displayFrame.memberCountLabel:SetFormattedText("%d/%d", RaidInfoCounts.totalAlive, RaidInfoCounts.totalCount);
end

local usedGroups = {};
function CompactRaidFrameManager_UpdateFilterInfo(self)
    CompactRaidFrameManager_UpdateRoleFilterButton(self.displayFrame.filterOptions.filterRoleTank);
    CompactRaidFrameManager_UpdateRoleFilterButton(self.displayFrame.filterOptions.filterRoleHealer);
    CompactRaidFrameManager_UpdateRoleFilterButton(self.displayFrame.filterOptions.filterRoleDamager);

    RaidUtil_GetUsedGroups(usedGroups);
    for i=1, MAX_RAID_GROUPS do
        CompactRaidFrameManager_UpdateGroupFilterButton(self.displayFrame.filterOptions["filterGroup"..i], usedGroups);
    end
end

function CompactRaidFrameManager_UpdateRoleFilterButton(button)
    local totalAlive, totalCount = RaidInfoCounts["aliveRole"..button.role], RaidInfoCounts["totalRole"..button.role]
    button:SetFormattedText("%s %d/%d", button.roleTexture, totalAlive, totalCount);
    local keepGroupsTogether = CompactRaidFrameManager_GetSetting("KeepGroupsTogether");
    keepGroupsTogether = keepGroupsTogether and keepGroupsTogether ~= "0";
    if ( totalCount == 0 or keepGroupsTogether ) then
        button.selectedHighlight:Hide();
        button:Disable();
        button:SetAlpha(0.5);
    else
        button:Enable();
        button:SetAlpha(1);
        local isFiltered = CRF_GetFilterRole(button.role)
        if ( isFiltered ) then
            button.selectedHighlight:Show();
        else
            button.selectedHighlight:Hide();
        end
    end
end

function CompactRaidFrameManager_ToggleRoleFilter(role)
    CRF_SetFilterRole(role, not CRF_GetFilterRole(role));
    CompactRaidFrameManager_UpdateFilterInfo(CompactRaidFrameManager);
    CompactRaidFrameContainer_TryUpdate(CompactRaidFrameContainer);
end

function CompactRaidFrameManager_UpdateGroupFilterButton(button, usedGroups)
    local group = button:GetID();
    if ( usedGroups[group] ) then
        button:Enable();
        button:SetAlpha(1);
        local isFiltered = CRF_GetFilterGroup(group);
        if ( isFiltered ) then
            button.selectedHighlight:Show();
        else
            button.selectedHighlight:Hide();
        end
    else
        button.selectedHighlight:Hide();
        button:Disable();
        button:SetAlpha(0.5);
    end
end

function CompactRaidFrameManager_ToggleGroupFilter(group)
    CRF_SetFilterGroup(group, not CRF_GetFilterGroup(group));
    CompactRaidFrameManager_UpdateFilterInfo(CompactRaidFrameManager);
    CompactRaidFrameContainer_TryUpdate(CompactRaidFrameContainer);
end

function CompactRaidFrameManager_UpdateRaidIcons()
    local unit = "target";
    local disableAll = not CanBeRaidTarget(unit);
    for i=1, NUM_RAID_ICONS do
        local button = _G["CompactRaidFrameManagerDisplayFrameRaidMarkersRaidMarker"..i];   --.... /cry
        if ( disableAll or button:GetID() == GetRaidTargetIndex(unit) ) then
            button:GetNormalTexture():SetDesaturated(true);
            button:SetAlpha(0.7);
            button:Disable();
        else
            button:GetNormalTexture():SetDesaturated(false);
            button:SetAlpha(1);
            button:Enable();
        end
    end

    local removeButton = CompactRaidFrameManagerDisplayFrameRaidMarkersRaidMarkerRemove;
    if ( not GetRaidTargetIndex(unit) ) then
        removeButton:GetNormalTexture():SetDesaturated(true);
        removeButton:Disable();
    else
        removeButton:GetNormalTexture():SetDesaturated(false);
        removeButton:Enable();
    end
end

--Settings stuff
local cachedSettings = {};
local isSettingCached = {};
function CompactRaidFrameManager_GetSetting(settingName)
    if ( not isSettingCached[settingName] ) then
        cachedSettings[settingName] = CompactRaidFrameManager_GetSettingBeforeLoad(settingName);
        isSettingCached[settingName] = true;
    end
    return cachedSettings[settingName];
end

function CompactRaidFrameManager_GetSettingBeforeLoad(settingName)
    if ( settingName == "Managed" ) then
        return true;
    elseif ( settingName == "Locked" ) then
        return true;
    elseif ( settingName == "SortMode" ) then
        return "role";
    elseif ( settingName == "KeepGroupsTogether" ) then
        return false;
    elseif ( settingName == "DisplayPets" ) then
        return false;
    elseif ( settingName == "DisplayMainTankAndAssist" ) then
        return true;
    elseif ( settingName == "IsShown" ) then
        return true;
    elseif ( settingName == "ShowBorders" ) then
        return true;
    elseif ( settingName == "HorizontalGroups" ) then
        return false;
    else
        GMError("Unknown setting "..tostring(settingName));
    end
end

do  --Enclosure to make sure people go through SetSetting
    local function CompactRaidFrameManager_SetManaged(value)
        local container = CompactRaidFrameManager.container;
    end

    local function CompactRaidFrameManager_SetLocked(value)
        local manager = CompactRaidFrameManager;
        if ( value and value ~= "0" ) then
            CompactRaidFrameManagerDisplayFrameLockedModeToggle:SetText(UNLOCK);
            CompactRaidFrameManagerDisplayFrameLockedModeToggle.lockMode = false;
            CompactRaidFrameManager_UpdateContainerLockVisibility(manager);
        else
            CompactRaidFrameManagerDisplayFrameLockedModeToggle:SetText(LOCK);
            CompactRaidFrameManagerDisplayFrameLockedModeToggle.lockMode = true;
            CompactRaidFrameManager_UpdateContainerLockVisibility(manager);
        end
    end

    local function CompactRaidFrameManager_SetSortMode(value)
        local manager = CompactRaidFrameManager;
        if ( value == "group" ) then
            CompactRaidFrameContainer_SetFlowSortFunction(manager.container, CRFSort_Group);
        elseif ( value == "role" ) then
            CompactRaidFrameContainer_SetFlowSortFunction(manager.container, CRFSort_Role);
        elseif ( value == "alphabetical" ) then
            CompactRaidFrameContainer_SetFlowSortFunction(manager.container, CRFSort_Alphabetical);
        else
            CompactRaidFrameManager_SetSetting("SortMode", "role");
            GMError("Unknown sort mode: "..tostring(value));
        end
    end

    local function CompactRaidFrameManager_SetKeepGroupsTogether(value)
        local manager = CompactRaidFrameManager;
        local groupMode;
        if ( not value or value == "0" ) then
            groupMode = "flush";
        else
            groupMode = "discrete";
        end

        CompactRaidFrameContainer_SetGroupMode(manager.container, groupMode);
        CompactRaidFrameManager_UpdateFilterInfo(manager);
    end

    local function CompactRaidFrameManager_SetDisplayPets(value)
        local container = CompactRaidFrameManager.container;
        local displayPets;
        if ( value and value ~= "0" ) then
            displayPets = true;
        end

        CompactRaidFrameContainer_SetDisplayPets(container, displayPets);
    end

    local function CompactRaidFrameManager_SetDisplayMainTankAndAssist(value)
        local container = CompactRaidFrameManager.container;
        local displayFlaggedMembers;
        if ( value and value ~= "0" ) then
            displayFlaggedMembers = true;
        end

        CompactRaidFrameContainer_SetDisplayMainTankAndAssist(container, displayFlaggedMembers);
    end

    local function CompactRaidFrameManager_SetIsShown(value)
        local manager = CompactRaidFrameManager;
        if ( value and value ~= "0" ) then
            manager.container.enabled = true;
            CompactRaidFrameManagerDisplayFrameHiddenModeToggle:SetText(HIDE);
            CompactRaidFrameManagerDisplayFrameHiddenModeToggle.shownMode = false;
        else
            manager.container.enabled = false;
            CompactRaidFrameManagerDisplayFrameHiddenModeToggle:SetText(SHOW);
            CompactRaidFrameManagerDisplayFrameHiddenModeToggle.shownMode = true;
        end
        CompactRaidFrameManager_UpdateContainerVisibility();
        CRF_UpdatePlayerFrameVisibility();
    end

    local function CompactRaidFrameManager_SetBorderShown(value)
        local manager = CompactRaidFrameManager;
        local showBorder;
        if ( value and value ~= "0" ) then
            showBorder = true;
        end
        CUF_SHOW_BORDER = showBorder;
        CompactRaidFrameContainer_SetBorderShown(manager.container, showBorder);
    end

    local function CompactRaidFrameManager_SetHorizontalGroups(value)
        local horizontalGroups;
        if ( value and value ~= "0" ) then
            horizontalGroups = true;
        end
        CUF_HORIZONTAL_GROUPS = horizontalGroups;
    end

    function CompactRaidFrameManager_SetSetting(settingName, value)
        cachedSettings[settingName] = value;
        isSettingCached[settingName] = true;
        --Perform the actual functions
        if ( settingName == "Managed" ) then
            CompactRaidFrameManager_SetManaged(value);
        elseif ( settingName == "Locked" ) then
            CompactRaidFrameManager_SetLocked(value);
        elseif ( settingName == "SortMode" ) then
            CompactRaidFrameManager_SetSortMode(value);
        elseif ( settingName == "KeepGroupsTogether" ) then
            CompactRaidFrameManager_SetKeepGroupsTogether(value);
        elseif ( settingName == "DisplayPets" ) then
            CompactRaidFrameManager_SetDisplayPets(value);
        elseif ( settingName == "DisplayMainTankAndAssist" ) then
            CompactRaidFrameManager_SetDisplayMainTankAndAssist(value);
        elseif ( settingName == "IsShown" ) then
            CompactRaidFrameManager_SetIsShown(value);
        elseif ( settingName == "ShowBorders" ) then
            CompactRaidFrameManager_SetBorderShown(value);
        elseif ( settingName == "HorizontalGroups" ) then
            CompactRaidFrameManager_SetHorizontalGroups(value);
        else
            error("Unknown setting "..tostring(settingName));
        end
    end
end

function CompactRaidFrameManager_UpdateContainerVisibility()
    local manager = CompactRaidFrameManager;
    if ( GetDisplayedAllyFrames() == "raid" and manager.container.enabled ) then
        manager.container:Show();
    else
        manager.container:Hide();
    end
end

function CompactRaidFrameManager_AttachPartyFrames(manager)
    PartyMemberFrame1:ClearAllPoints();
    PartyMemberFrame1:SetPoint("TOPLEFT", manager, "TOPRIGHT", 0, -20);
end

function CompactRaidFrameManager_ResetContainerPosition()
    local manager = CompactRaidFrameManager;
    manager.dynamicContainerPosition = true;
    CompactRaidFrameManager_UpdateContainerBounds(manager);
    CompactRaidFrameManager_ResizeFrame_SavePosition(manager);
end

function CompactRaidFrameManager_UpdateContainerBounds(self) --Hah, "Bounds" instead of "SizeAndPosition". WHO NEEDS A THESAURUS NOW?!
    self.containerResizeFrame:SetMaxResize(self.containerResizeFrame:GetWidth(), GetScreenHeight() - 90);

    if ( self.dynamicContainerPosition ) then
        --Should be below the TargetFrameSpellBar at its lowest height..
        local top = GetScreenHeight() - 135;
        --Should be just above the FriendsFrameMicroButton.
        local bottom = 330;

        local managerTop = self:GetTop();

        self.containerResizeFrame:ClearAllPoints();
        self.containerResizeFrame:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, top - managerTop);
        self.containerResizeFrame:SetHeight(top - bottom);

        CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(self);
    end
end

function CompactRaidFrameManager_UpdateContainerLockVisibility(self)
    if ( GetDisplayedAllyFrames() ~= "raid" or not CompactRaidFrameManagerDisplayFrameLockedModeToggle.lockMode ) then
        CompactRaidFrameManager_LockContainer(self);
    else
        CompactRaidFrameManager_UnlockContainer(self);
    end
end

function CompactRaidFrameManager_LockContainer(self)
    self.containerResizeFrame:Hide();
end

function CompactRaidFrameManager_UnlockContainer(self)
    self.containerResizeFrame:Show();
end

--ResizeFrame related functions
function CompactRaidFrameManager_ResizeFrame_Reanchor(manager)
    manager.container:SetPoint("TOPLEFT", manager.containerResizeFrame, "TOPLEFT", RESIZE_HORIZONTAL_OUTSETS, -RESIZE_VERTICAL_OUTSETS);
end

function CompactRaidFrameManager_ResizeFrame_OnDragStart(manager)
    manager.dynamicContainerPosition = false;

    manager.containerResizeFrame:StartMoving();
end

function CompactRaidFrameManager_ResizeFrame_OnDragStop(manager)
    manager.containerResizeFrame:StopMovingOrSizing();
    CompactRaidFrameManager_ResizeFrame_CheckMagnetism(manager);
    CompactRaidFrameManager_ResizeFrame_SavePosition(manager);
end

function CompactRaidFrameManager_ResizeFrame_OnResizeStart(manager)
    manager.dynamicContainerPosition = false;

    manager.containerResizeFrame:StartSizing("BOTTOM")
    manager.containerResizeFrame.timeSinceUpdate = 0;
    manager.containerResizeFrame:SetScript("OnUpdate", CompactRaidFrameManager_ResizeFrame_OnUpdate);
end

function CompactRaidFrameManager_ResizeFrame_OnResizeStop(manager)
    manager.containerResizeFrame:StopMovingOrSizing();
    manager.containerResizeFrame:SetScript("OnUpdate", nil);
    CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(manager);
    CompactRaidFrameManager_ResizeFrame_CheckMagnetism(manager);
    CompactRaidFrameManager_ResizeFrame_SavePosition(manager);
end

local RESIZE_UPDATE_INTERVAL = 0.5;
function CompactRaidFrameManager_ResizeFrame_OnUpdate(self, elapsed)
    self.timeSinceUpdate = (self.timeSinceUpdate or 0) + elapsed;
    if ( self.timeSinceUpdate >= RESIZE_UPDATE_INTERVAL ) then
        -- Reset, or after the first half second this re-laid-out the
        -- container on every single frame for the rest of the drag.
        self.timeSinceUpdate = 0;
        local manager = self:GetParent();
        CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(manager);
        CompactRaidFrameManager_ResizeFrame_CheckMagnetism(manager);
        CompactRaidFrameManager_ResizeFrame_SavePosition(manager);
    end
end

function CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(manager)
    --If we're flow style, we want to make sure we exactly fit N frames.
    --(The setting is a boolean from the profile; the old `~= "1"` test was
    -- always true, so the height was snapped even with Keep Groups Together.)
    local keepGroupsTogether = CompactRaidFrameManager_GetSetting("KeepGroupsTogether");
    if ( not keepGroupsTogether or keepGroupsTogether == "0" ) then
        local unitFrameHeight = DefaultCompactUnitFrameSetupOptions.height;
        local resizerHeight = manager.containerResizeFrame:GetHeight() - RESIZE_VERTICAL_OUTSETS * 2;
        local newHeight = unitFrameHeight * floor(resizerHeight / unitFrameHeight);
        manager.container:SetHeight(newHeight);
    else
        manager.container:SetHeight(manager.containerResizeFrame:GetHeight() - RESIZE_VERTICAL_OUTSETS * 2);
    end
end

local MAGNETIC_FIELD_RANGE = 10;
function CompactRaidFrameManager_ResizeFrame_CheckMagnetism(manager)
    if ( abs(manager.containerResizeFrame:GetLeft() - manager:GetRight()) < MAGNETIC_FIELD_RANGE and
        manager.containerResizeFrame:GetTop() > manager:GetBottom() and manager.containerResizeFrame:GetBottom() < manager:GetTop() ) then
        manager.containerResizeFrame:ClearAllPoints();
        manager.containerResizeFrame:SetPoint("TOPLEFT", manager, "TOPRIGHT", 0, manager.containerResizeFrame:GetTop() - manager:GetTop());
    end
end

function CompactRaidFrameManager_ResizeFrame_SavePosition(manager)
    if ( manager.dynamicContainerPosition ) then
        SetRaidProfileSavedPosition(GetActiveRaidProfile(), true);
        return;
    end

    --The stuff we're actually saving
    local topPoint, topOffset;
    local bottomPoint, bottomOffset;
    local leftPoint, leftOffset;

    local screenHeight = GetScreenHeight();
    local top = manager.containerResizeFrame:GetTop();
    if ( top > screenHeight / 2 ) then
        topPoint = "TOP";
        topOffset = screenHeight - top;
    else
        topPoint = "BOTTOM";
        topOffset = top;
    end

    local bottom = manager.containerResizeFrame:GetBottom();
    if ( bottom > screenHeight / 2 ) then
        bottomPoint = "TOP";
        bottomOffset = screenHeight - bottom;
    else
        bottomPoint = "BOTTOM";
        bottomOffset = bottom;
    end

    local isAttached = (select(2, manager.containerResizeFrame:GetPoint(1)) == manager);
    if ( isAttached ) then
        leftPoint = "ATTACHED";
        leftOffset = 0;
    else
        local screenWidth = GetScreenWidth();
        local left = manager.containerResizeFrame:GetLeft();
        if ( left > screenWidth / 2 ) then
            leftPoint = "RIGHT";
            leftOffset = screenWidth - left;
        else
            leftPoint = "LEFT";
            leftOffset = left;
        end
    end

    SetRaidProfileSavedPosition(GetActiveRaidProfile(), false, topPoint, topOffset, bottomPoint, bottomOffset, leftPoint, leftOffset);
end

function CompactRaidFrameManager_ResizeFrame_LoadPosition(manager)
    local dynamic, topPoint, topOffset, bottomPoint, bottomOffset, leftPoint, leftOffset = GetRaidProfileSavedPosition(GetActiveRaidProfile());
    if ( dynamic ) then --We are automatically placed.
        manager.dynamicContainerPosition = true;
        CompactRaidFrameManager_UpdateContainerBounds(manager);
        return;
    else
        manager.dynamicContainerPosition = false;
    end

    --First, let's clear the container's current anchors.
    manager.containerResizeFrame:ClearAllPoints();

    local top;
    if ( topPoint == "TOP" ) then
        top = GetScreenHeight() - topOffset;
    else
        top = topOffset;
    end

    local bottom;
    if ( bottomPoint == "TOP" ) then
        bottom = GetScreenHeight() - bottomOffset;
    else
        bottom = bottomOffset
    end

    local height = top - bottom;
    height = max(height, MINIMUM_RAID_CONTAINER_HEIGHT);
    top = max(top, height);

    manager.containerResizeFrame:SetHeight(height);

    if ( leftPoint == "ATTACHED" ) then
        manager.containerResizeFrame:SetPoint("TOPLEFT", manager, "TOPRIGHT", 0, top - manager:GetTop());
    else
        local left;
        if ( leftPoint == "RIGHT" ) then
            left = GetScreenWidth() - leftOffset;
        else
            left = leftOffset;
        end

        manager.containerResizeFrame:SetPoint("TOPLEFT", nil, "BOTTOMLEFT", left, top);
    end

    CompactRaidFrameManager_ResizeFrame_UpdateContainerSize(manager);
end
-------------Utility functions-------------
--Functions used for sorting and such
function CRFSort_Group(token1, token2)
    if ( IsInRaid() ) then
        local id1 = tonumber(string.sub(token1, 5));
        local id2 = tonumber(string.sub(token2, 5));

        if ( not id1 or not id2 ) then
            return id1;
        end
        local _, _, subgroup1 = GetRaidRosterInfo(id1);
        local _, _, subgroup2 = GetRaidRosterInfo(id2);

        if ( subgroup1 and subgroup2 and subgroup1 ~= subgroup2 ) then
            return subgroup1 < subgroup2;
        end

        --Fallthrough: Sort by order in Raid window.
        return id1 < id2;
    else
        if ( token1 == "player" ) then
            return true;
        elseif ( token2 == "player" ) then
            return false;
        else
            return token1 < token2; --String compare is OK since we don't go above 1 digit for party.
        end
    end
end

local roleValues = { MAINTANK = 1, MAINASSIST = 2, TANK = 3, HEALER = 4, DAMAGER = 5, NONE = 6 };
function CRFSort_Role(token1, token2)
    -- UnitInRaid is 0-based on 3.3.5a (raid1 -> 0), GetRaidRosterInfo 1-based.
    local id1, id2 = UnitInRaid(token1), UnitInRaid(token2);
    local role1, role2;
    if ( id1 ) then
        role1 = select(10, GetRaidRosterInfo(id1 + 1));
    end
    if ( id2 ) then
        role2 = select(10, GetRaidRosterInfo(id2 + 1));
    end

    role1 = role1 or UnitGroupRolesAssigned(token1);
    role2 = role2 or UnitGroupRolesAssigned(token2);

    local value1, value2 = roleValues[role1], roleValues[role2];
    if ( value1 ~= value2 ) then
        return value1 < value2;
    end

    --Fallthrough: Sort alphabetically.
    return CRFSort_Alphabetical(token1, token2);
end

function CRFSort_Alphabetical(token1, token2)
    local name1, name2 = UnitName(token1), UnitName(token2);
    if ( name1 and name2 ) then
        return name1 < name2;
    elseif ( name1 or name2 ) then
        return name1;
    end

    --Fallthrough: Alphabetic order of tokens (just here to make comparisons well-ordered)
    return token1 < token2;
end
--Functions used for filtering
local filterOptions = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true,
    [7] = true,
    [8] = true,
    displayRoleNONE = true;
    displayRoleTANK = true;
    displayRoleHEALER = true;
    displayRoleDAMAGER = true;
}

function CRF_SetFilterRole(role, show)
    filterOptions["displayRole"..role] = show;
end

function CRF_GetFilterRole(role)
    return filterOptions["displayRole"..role];
end

function CRF_SetFilterGroup(group, show)
    assert(type(group) == "number");
    filterOptions[group] = show;
end

function CRF_GetFilterGroup(group)
    assert(type(group) == "number");
    return filterOptions[group];
end

function CRFFlowFilterFunc(token)
    if ( token ~= "player" and not UnitExists(token) ) then
        return false;
    end

    if ( not IsInRaid() ) then  --We don't filter unless we're in a raid.
        return true;
    end

    local role = UnitGroupRolesAssigned(token);
    if ( not filterOptions["displayRole"..role] ) then
        return false;
    end

    local raidID = UnitInRaid(token);

    if ( raidID ) then
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, raidRole, isML = GetRaidRosterInfo(raidID + 1);
        if ( not filterOptions[subgroup] ) then
            return false;
        end

        local showingMTandMA = CompactRaidFrameManager_GetSetting("DisplayMainTankAndAssist");
        if ( raidRole and (showingMTandMA and showingMTandMA ~= "0") ) then --If this character is already displayed as a Main Tank/Main Assist, we don't want to show them a second time
            return false;
        end
    end

    return true;
end

function CRFGroupFilterFunc(groupNum)
    return filterOptions[groupNum];
end
--Counting functions
RaidInfoCounts = {
    aliveRoleTANK       = 0,
    totalRoleTANK       = 0,
    aliveRoleHEALER     = 0,
    totalRoleHEALER     = 0,
    aliveRoleDAMAGER    = 0,
    totalRoleDAMAGER    = 0,
    aliveRoleNONE       = 0,
    totalRoleNONE       = 0,
    totalCount          = 0,
    totalAlive          = 0,
}

local function CRF_ResetCountedStuff()
    for key, val in pairs(RaidInfoCounts) do
        RaidInfoCounts[key] = 0;
    end
end

function CRF_CountStuff()
    CRF_ResetCountedStuff();
    if ( IsInRaid() ) then
        for i=1, GetNumGroupMembers() do
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);  --Weird that we have 2 role return values, but... oh well
            local assignedRole = UnitGroupRolesAssigned("raid"..i)
            if ( rank ) then
                CRF_AddToCount(isDead, assignedRole);
            end
        end
    else
        CRF_AddToCount(UnitIsDeadOrGhost("player"), UnitGroupRolesAssigned("player"));
        for i=1, GetNumSubgroupMembers() do
            local unit = "party"..i;
            CRF_AddToCount(UnitIsDeadOrGhost(unit), UnitGroupRolesAssigned(unit));
        end
    end
end

function CRF_AddToCount(isDead, assignedRole)
    RaidInfoCounts.totalCount = RaidInfoCounts.totalCount + 1;
    RaidInfoCounts["totalRole"..assignedRole] = RaidInfoCounts["totalRole"..assignedRole] + 1;
    if ( not isDead ) then
        RaidInfoCounts.totalAlive = RaidInfoCounts.totalAlive + 1;
        RaidInfoCounts["aliveRole"..assignedRole] = RaidInfoCounts["aliveRole"..assignedRole] + 1;
    end
end
