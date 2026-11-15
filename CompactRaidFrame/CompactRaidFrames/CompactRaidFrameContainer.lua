-- Only define it if the client doesn't (re-assigning a Blizzard global taints it).
if ( MAX_RAID_GROUPS == nil ) then
    MAX_RAID_GROUPS = 8;
end

local _;
local PLAYER_ZONE_TYPE;
local PLAYER_REGEN_ENABLED_AWAIT;

local GetBattlefieldInstanceRunTime = GetBattlefieldInstanceRunTime

local frameCreationSpecifiers = {
    raid = { setUpFunc = DefaultCompactUnitFrameSetup, updateList = "normal"},
    pet =  { setUpFunc = DefaultCompactMiniFrameSetup, updateList = "mini" },
    flagged = { mapping = UnitGUID, setUpFunc = DefaultCompactUnitFrameSetup, updateList = "normal" },
    target = { setUpFunc = DefaultCompactMiniFrameSetup, updateList = "mini" },
}

local function CompactRaidFrameContainer_PetLock(frame)
    return (PLAYER_ZONE_TYPE == "arena" and frame.unit and GetBattlefieldInstanceRunTime() > 60000 and strsub(frame.unit, 1, 7) == "raidpet")
end

local function CompactRaidFrameContainer_PetInUse(frameReservation, unit)
    local frame = CompactRaidFrameReservation_GetFrame(frameReservation, unit);
    return frame and frame.inUse;
end

--Widget Handlers
function CompactRaidFrameContainer_OnLoad(self)
    FlowContainer_Initialize(self);

    self:SetClampRectInsets(0, 200 - self:GetWidth(), 10, 0);

    self.raidUnits = {--[["raid1", "raid2", "raid3", ..., "raid40"]]};
    for i = 1, MAX_RAID_MEMBERS do
        tinsert(self.raidUnits, "raid"..i);
    end
    self.partyUnits = { "player" };
    for i = 1, MAX_PARTY_MEMBERS do
        tinsert(self.partyUnits, "party"..i);
    end

    CompactRaidFrameContainer_UpdateDisplayedUnits(self);

    self:RegisterEvent("PLAYER_REGEN_ENABLED");
    self:RegisterEvent("PLAYER_REGEN_DISABLED");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("GROUP_ROSTER_UPDATE");
    self:RegisterEvent("UNIT_PET");

    local unitFrameReleaseFunc = function(frame)
        if ( not CompactRaidFrameContainer_PetLock(frame) ) then
            CompactUnitFrame_SetUnit(frame, nil);
        end
    end;
    self.frameReservations = {
        raid    = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc);
        pet     = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc);
        flagged = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc); --For Main Tank/Assist units
        target  = CompactRaidFrameReservation_NewManager(unitFrameReleaseFunc); --Target of target for Main Tank/Main Assist
    }

    self.frameUpdateList = {
        normal = {},    --Groups are also in this normal list.
        mini = {},
        group = {},
    }
    self.unitFrameUnusedFunc = function(frame)
            if ( not CompactRaidFrameContainer_PetLock(frame) ) then
                frame.inUse = false;
            end
        end;

    self.displayPets = true;
    self.displayFlaggedMembers = true;
end

function CompactRaidFrameContainer_OnEvent(self, event, ...)
    if ( event == "PLAYER_REGEN_ENABLED" ) then
        if ( PLAYER_REGEN_ENABLED_AWAIT ) then
            PLAYER_REGEN_ENABLED_AWAIT = nil;
            CompactRaidFrameContainer_OnEvent(self, "GROUP_ROSTER_UPDATE");
        end
    elseif ( event == "PLAYER_REGEN_DISABLED" ) then
        -- Fires just before the combat lockdown starts, so the real frames can
        -- still be put back here.
        if ( CRF_GetRaidPreviewSize() ) then
            CRF_SetRaidPreviewSize(nil);
        end
    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        _, PLAYER_ZONE_TYPE = IsInInstance();
    else
        if ( InCombatLockdown() ) then
            PLAYER_REGEN_ENABLED_AWAIT = true;
        elseif ( event == "GROUP_ROSTER_UPDATE" ) then
            CompactRaidFrameContainer_UpdateDisplayedUnits(self);
            CompactRaidFrameContainer_TryUpdate(self);
        elseif ( event == "UNIT_PET" ) then
            if ( self.displayPets ) then
                local unit = ...;
                if ( unit == "player" or strsub(unit, 1, 4) == "raid" or strsub(unit, 1, 5) == "party" ) then
                    CompactRaidFrameContainer_TryUpdate(self);
                end
            end
        end
    end
end

function CompactRaidFrameContainer_OnSizeChanged(self)
    FlowContainer_DoLayout(self);
    CompactRaidFrameContainer_UpdateBorder(self);
end
--Externally used functions
function CompactRaidFrameContainer_SetGroupMode(self, groupMode)
    self.groupMode = groupMode;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetFlowFilterFunction(self, flowFilterFunc)
    --Usage: flowFilterFunc is called as flowFilterFunc("unittoken") and should return whether this frame should be displayed or not.
    self.flowFilterFunc = flowFilterFunc;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetGroupFilterFunction(self, groupFilterFunc)
    --Usage: groupFilterFunc is called as groupFilterFunc(groupNum) and should return whether this group should be displayed or not.
    self.groupFilterFunc = groupFilterFunc;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetFlowSortFunction(self, flowSortFunc)
    --Usage: Takes two tokens, should work as a Lua sort function.
    --The ordering must be well-defined, even across units that will be filtered out
    self.flowSortFunc = flowSortFunc;
    CompactRaidFrameContainer_TryUpdate(self);
end

function CompactRaidFrameContainer_SetDisplayPets(self, displayPets)
    if ( self.displayPets ~= displayPets ) then
        self.displayPets = displayPets;
        CompactRaidFrameContainer_TryUpdate(self);
    end
end

function CompactRaidFrameContainer_SetDisplayMainTankAndAssist(self, displayFlaggedMembers)
    if ( self.displayFlaggedMembers ~= displayFlaggedMembers ) then
        self.displayFlaggedMembers = displayFlaggedMembers;
        CompactRaidFrameContainer_TryUpdate(self);
    end
end

function CompactRaidFrameContainer_SetBorderShown(self, showBorder)
    self.showBorder = showBorder;
    CompactRaidFrameContainer_UpdateBorder(self);
end

function CompactRaidFrameContainer_ApplyToFrames(self, updateSpecifier, func, ...)
    for specifier, list in pairs(self.frameUpdateList) do
        if ( updateSpecifier == "all" or specifier == updateSpecifier ) then
            for i=1, #list do
                list[i]:applyFunc(updateSpecifier, func, ...);
            end
        end
    end
end

--Internally used functions
function CompactRaidFrameContainer_TryUpdate(self)
    if ( CompactRaidFrameContainer_ReadyToUpdate(self) ) then
        if ( InCombatLockdown() ) then
            -- Laying out assigns units and moves/resizes secure unit buttons,
            -- which is blocked in combat. Redo it when combat ends.
            PLAYER_REGEN_ENABLED_AWAIT = true;
            return;
        end
        CompactRaidFrameContainer_LayoutFrames(self);
    end
end

function CompactRaidFrameContainer_ReadyToUpdate(self)
    if ( not self.groupMode ) then
        return false
    end
    if ( self.groupMode == "flush" and not (self.flowFilterFunc and self.flowSortFunc) ) then
        return false;
    end
    if ( self.groupMode == "discrete" and not self.groupFilterFunc ) then
        return false;
    end

    return true;
end

function CompactRaidFrameContainer_UpdateDisplayedUnits(self)
    if ( IsInRaid() ) then
        self.units = self.raidUnits;
    else
        self.units = self.partyUnits;
    end
end

function CompactRaidFrameContainer_LayoutFrames(self)
    --First, mark everything we currently use as unused. We'll hide all the ones that are still unused at the end of this function. (On release)
    for i=1, #self.flowFrames do
        if ( type(self.flowFrames[i]) == "table" and self.flowFrames[i].unusedFunc ) then
            self.flowFrames[i]:unusedFunc();
        end
    end
    FlowContainer_RemoveAllObjects(self);

    FlowContainer_PauseUpdates(self);   --We don't want to update it every time we add an item.

    if ( CRF_GetRaidPreviewSize() ) then
        CompactRaidFrameContainer_AddPreview(self, CRF_GetRaidPreviewSize());
    else
        if ( self.displayFlaggedMembers ) then
            CompactRaidFrameContainer_AddFlaggedUnits(self);
            FlowContainer_AddLineBreak(self);
        end

        local petsPlaced;
        if ( self.groupMode == "discrete" ) then
            petsPlaced = CompactRaidFrameContainer_AddGroups(self);
        elseif ( self.groupMode == "flush" ) then
            CompactRaidFrameContainer_AddPlayers(self);
        else
            error("Unknown group mode");
        end

        if ( self.displayPets and not petsPlaced ) then
            CompactRaidFrameContainer_AddPets(self);
        end
    end

    FlowContainer_ResumeUpdates(self);

    CompactRaidFrameContainer_UpdateBorder(self);

    CompactRaidFrameContainer_ReleaseAllReservedFrames(self);

    -- your totem / rune boxes go under your frame, in the room left for them
    if ( CRF_UpdateClassBar ) then
        CRF_UpdateClassBar();
    end
    -- the rested glow: frames that kept showing you as a preview started or ended
    if ( CRF_UpdateRestIndicators ) then
        CRF_UpdateRestIndicators();
    end
end

function CompactRaidFrameContainer_UpdateBorder(self)
    local usedX, usedY = FlowContainer_GetUsedBounds(self);
    if ( self.showBorder and self.groupMode ~= "discrete" and usedX > 0 and usedY > 0 ) then
        self.borderFrame:SetSize(usedX + 11, usedY + 13);
        self.borderFrame:Show();
    else
        self.borderFrame:Hide();
    end
end

-- The pets of a group's members, in the group's order: in a party the
-- player's pet, then party1's ... In a raid, raid order, with the player's pet
-- first when "Keep Me at the Top" is on.
local function CompactRaidFrameContainer_GetGroupPets(self, id, pets)
    wipe(pets);
    if ( id == "PARTY" ) then
        if ( UnitExists("pet") ) then
            tinsert(pets, "pet");
        end
        for i=1, GetNumSubgroupMembers() do
            if ( UnitExists("partypet"..i) ) then
                tinsert(pets, "partypet"..i);
            end
        end
    else
        local playerFirst = CompactRaidFrameManager_GetSetting and CompactRaidFrameManager_GetSetting("SortPlayerFirst");
        playerFirst = playerFirst and playerFirst ~= "0";
        local frameReservations = self.frameReservations["pet"];
        for i=1, MAX_RAID_MEMBERS do
            local unit = "raidpet"..i;
            local _, _, subgroup = GetRaidRosterInfo(i);
            if ( subgroup == id and (UnitExists(unit) or (PLAYER_ZONE_TYPE == "arena" and CompactRaidFrameContainer_PetInUse(frameReservations, unit))) ) then
                if ( playerFirst and UnitIsUnit("raid"..i, "player") ) then
                    tinsert(pets, 1, unit);
                else
                    tinsert(pets, unit);
                end
            end
        end
    end
    return pets;
end

-- "Separate Groups (Horizontal)": a group's pets go in one row right under
-- the group. The flow stacks objects (groups) top to bottom there, so the row
-- is a holder frame with the pet frames side by side in it; it goes into the
-- flow together with its group (an atomic add, so they wrap to the next
-- column together). Its pets are released with it when the layout is redone.
local function CompactRaidFrameContainer_PetRow_Unused(row)
    for i=1, #row.pets do
        local petFrame = row.pets[i];
        if ( petFrame.unusedFunc ) then
            petFrame:unusedFunc();
        end
    end
    wipe(row.pets);
    row:Hide();
end

local function CompactRaidFrameContainer_AddPetRow(self, index, pets)
    self.petRows = self.petRows or {};
    local row = self.petRows[index];
    if ( not row ) then
        row = CreateFrame("Frame", nil, self);
        row.pets = {};
        row.unusedFunc = CompactRaidFrameContainer_PetRow_Unused;
        self.petRows[index] = row;
    end
    wipe(row.pets);
    local width, height = 0, 0;
    for i=1, #pets do
        local petFrame = CompactRaidFrameContainer_GetUnitFrame(self, pets[i], "pet");
        CompactUnitFrame_SetUnit(petFrame, pets[i]);
        petFrame:ClearAllPoints();
        petFrame:SetPoint("TOPLEFT", row, "TOPLEFT", width, 0);
        width = width + petFrame:GetWidth();
        height = max(height, petFrame:GetHeight());
        tinsert(row.pets, petFrame);
    end
    row:SetSize(max(width, 1), max(height, 1));
    row:Show();
    FlowContainer_AddObject(self, row);
    return row;
end

-- "Separate Groups (Vertical)": a group and its pets as one column, the pets
-- right under the last member (centred, as the members are). The column goes
-- into the flow in the group's place; the group and pets are released with it.
local function CompactRaidFrameContainer_GroupColumn_Unused(column)
    if ( column.group and column.group.unusedFunc ) then
        column.group:unusedFunc();
    end
    column.group = nil;
    CompactRaidFrameContainer_PetRow_Unused(column);
end

local function CompactRaidFrameContainer_AddGroupColumn(self, index, id, pets)
    self.groupColumns = self.groupColumns or {};
    local column = self.groupColumns[index];
    if ( not column ) then
        column = CreateFrame("Frame", nil, self);
        column.pets = {};
        column.unusedFunc = CompactRaidFrameContainer_GroupColumn_Unused;
        self.groupColumns[index] = column;
    end
    local groupFrame = CompactRaidFrameContainer_PrepareGroup(self, id);
    column.group = groupFrame;
    groupFrame:ClearAllPoints();
    groupFrame:SetPoint("TOPLEFT", column, "TOPLEFT", 0, 0);
    wipe(column.pets);
    local height = groupFrame:GetHeight();
    local above = groupFrame;
    for i=1, #pets do
        local petFrame = CompactRaidFrameContainer_GetUnitFrame(self, pets[i], "pet");
        CompactUnitFrame_SetUnit(petFrame, pets[i]);
        petFrame:ClearAllPoints();
        petFrame:SetPoint("TOP", above, "BOTTOM", 0, 0);
        height = height + petFrame:GetHeight();
        above = petFrame;
        tinsert(column.pets, petFrame);
    end
    column:SetSize(groupFrame:GetWidth(), height);
    column:Show();
    FlowContainer_AddObject(self, column);
    return column;
end

do
    local usedGroups = {}; --Enclosure to make sure usedGroups isn't used anywhere else.
    local groupIDs, groupPets = {}, {};
    -- With Display Pets, each group's pets go under that group (and the
    -- function returns true: the pets are placed).
    function CompactRaidFrameContainer_AddGroups(self)
        wipe(groupIDs);
        if ( IsInRaid() ) then
            RaidUtil_GetUsedGroups(usedGroups);

            for groupNum, isUsed in ipairs(usedGroups) do
                if ( isUsed and self.groupFilterFunc(groupNum) ) then
                    tinsert(groupIDs, groupNum);
                end
            end
        else
            tinsert(groupIDs, "PARTY");
        end

        if ( not self.displayPets ) then
            for i=1, #groupIDs do
                CompactRaidFrameContainer_AddGroup(self, groupIDs[i]);
            end
        elseif ( CUF_HORIZONTAL_GROUPS ) then
            -- Rows of groups, top to bottom: each group's pets in a row under it.
            for i=1, #groupIDs do
                groupPets[i] = groupPets[i] or {};
                local pets = CompactRaidFrameContainer_GetGroupPets(self, groupIDs[i], groupPets[i]);
                if ( #pets > 0 ) then
                    FlowContainer_BeginAtomicAdd(self);
                    CompactRaidFrameContainer_AddGroup(self, groupIDs[i]);
                    CompactRaidFrameContainer_AddPetRow(self, i, pets);
                    FlowContainer_EndAtomicAdd(self);
                else
                    CompactRaidFrameContainer_AddGroup(self, groupIDs[i]);
                end
            end
        else
            -- Columns of groups, side by side: each group's pets in a column
            -- right under its last member (a column frame holds both).
            for i=1, #groupIDs do
                groupPets[i] = groupPets[i] or {};
                local pets = CompactRaidFrameContainer_GetGroupPets(self, groupIDs[i], groupPets[i]);
                if ( #pets > 0 ) then
                    CompactRaidFrameContainer_AddGroupColumn(self, i, groupIDs[i], pets);
                else
                    CompactRaidFrameContainer_AddGroup(self, groupIDs[i]);
                end
            end
        end
        CompactRaidFrameContainer_SetGroupsArrangement(self);
        return self.displayPets;
    end
end

-- "Separate Groups": vertical groups (columns of 5) are placed side by side;
-- horizontal groups (rows of 5) are stacked top to bottom.
function CompactRaidFrameContainer_SetGroupsArrangement(self)
    FlowContainer_SetMaxPerLine(self, nil);
    FlowContainer_SetOrientation(self, CUF_HORIZONTAL_GROUPS and "vertical" or "horizontal");
end

-- "Combine Groups": one list, filling columns top to bottom (vertical) or rows
-- of 5 left to right (horizontal).
function CompactRaidFrameContainer_SetPlayersArrangement(self)
    if ( CUF_HORIZONTAL_GROUPS ) then
        FlowContainer_SetMaxPerLine(self, MEMBERS_PER_RAID_GROUP);
        FlowContainer_SetOrientation(self, "horizontal");
    else
        FlowContainer_SetMaxPerLine(self, nil);
        FlowContainer_SetOrientation(self, "vertical");
    end
end

function CompactRaidFrameContainer_AddGroup(self, id)
    local groupFrame = CompactRaidFrameContainer_PrepareGroup(self, id);
    FlowContainer_AddObject(self, groupFrame);
    return groupFrame;
end

-- The group's frame, set up and shown, but not yet placed.
function CompactRaidFrameContainer_PrepareGroup(self, id)
    local groupFrame, didCreation;

    if ( type(id) == "number" ) then
        groupFrame, didCreation = CompactRaidGroup_GenerateForGroup(id);
        if ( not didCreation ) then
            -- Current members (and so the group's length) before it is placed,
            -- whichever of the group and the container sees a roster change first.
            CompactRaidGroup_UpdateUnits(groupFrame);
        end
    elseif ( id == "PARTY" ) then
        groupFrame, didCreation = CompactPartyFrame_Generate();
        CompactPartyFrame_UpdateTitle(groupFrame);
        CompactPartyFrame_UpdateUnits(groupFrame);
    else
        error("Unknown id");
    end

    groupFrame:SetParent(self);
    groupFrame:SetFrameStrata("LOW");
    groupFrame.unusedFunc = groupFrame.Hide;
    if ( didCreation ) then
        tinsert(self.frameUpdateList.normal, groupFrame);
        tinsert(self.frameUpdateList.group, groupFrame);
    end

    groupFrame:Show();
    return groupFrame;
end

-- "Combine Groups": your frame with room under it for your totem / rune boxes
-- (CRFClassBar.lua) goes into the flow as one object, a holder with your frame
-- at its top. So the frames after yours move down (in rows of 5, the row is
-- taller), and frame and room wrap to the next column together. Your frame is
-- released with the holder when the layout is redone.
local function CompactRaidFrameContainer_ClassBarHolder_Unused(holder)
    local unitFrame = holder.unitFrame;
    if ( unitFrame ) then
        unitFrame.crfClassBarRoom = nil;
        if ( unitFrame.unusedFunc ) then
            unitFrame:unusedFunc();
        end
    end
    holder.unitFrame = nil;
    holder:Hide();
end

-- A member's frame into the flow (first: the first placeholder of a preview).
local function CompactRaidFrameContainer_AddMemberFrame(self, mapping, unit, first)
    local frame = CompactRaidFrameContainer_GetUnitFrame(self, mapping, "raid");
    CompactUnitFrame_SetUnit(frame, unit);
    local room = 0;
    if ( CRF_IsClassBarUnit and CRF_IsClassBarUnit(unit, first) ) then
        room = CRF_GetClassBarRoom(frame:GetWidth(), frame:GetHeight());
    end
    if ( room <= 0 ) then
        FlowContainer_AddObject(self, frame);
        return frame;
    end
    local holder = self.classBarHolder;
    if ( not holder ) then
        holder = CreateFrame("Frame", nil, self);
        holder.unusedFunc = CompactRaidFrameContainer_ClassBarHolder_Unused;
        self.classBarHolder = holder;
    end
    frame:ClearAllPoints();
    frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0);
    frame.crfClassBarRoom = room;
    holder.unitFrame = frame;
    holder:SetSize(frame:GetWidth(), frame:GetHeight() + room);
    holder:Show();
    FlowContainer_AddObject(self, holder);
    return frame;
end

function CompactRaidFrameContainer_AddPlayers(self)
    --First, sort the players we're going to use
    assert(self.flowSortFunc);  --No sort function defined! Call CompactRaidFrameContainer_SetFlowSortFunction.
    assert(self.flowFilterFunc);    --No filter function defined! Call CompactRaidFrameContainer_SetFlowFilterFunction.

    table.sort(self.units, self.flowSortFunc);

    for i=1, #self.units do
        local unit = self.units[i];
        if ( self.flowFilterFunc(unit) ) then
            CompactRaidFrameContainer_AddMemberFrame(self, unit, unit);
        end
    end

    CompactRaidFrameContainer_SetPlayersArrangement(self);
end

-- Placeholder frames for the raid size preview, in the current group layout.
-- They all show the player (a unit that always exists), like Edit Mode does.
function CompactRaidFrameContainer_AddPreview(self, size)
    if ( self.groupMode == "discrete" ) then
        for groupNum = 1, min(MAX_RAID_GROUPS, ceil(size / MEMBERS_PER_RAID_GROUP)) do
            local groupFrame = CompactRaidFrameContainer_AddGroup(self, groupNum);
            CompactRaidGroup_UpdateUnits(groupFrame);   -- sees the preview
        end
        CompactRaidFrameContainer_SetGroupsArrangement(self);
    else
        for i = 1, size do
            -- one reservation per placeholder ("preview1", ...) so each gets
            -- its own frame although they all show the same unit
            CompactRaidFrameContainer_AddMemberFrame(self, "preview"..i, "player", i == 1);
        end
        CompactRaidFrameContainer_SetPlayersArrangement(self);
    end
end

function CompactRaidFrameContainer_AddPets(self)
    if ( IsInRaid() ) then
        local frameReservations = self.frameReservations["pet"]
        for i=1, MAX_RAID_MEMBERS do
            local unit = "raidpet"..i;
            if ( UnitExists(unit) or (PLAYER_ZONE_TYPE == "arena" and CompactRaidFrameContainer_PetInUse(frameReservations, unit)) ) then
                CompactRaidFrameContainer_AddUnitFrame(self, unit, "pet");
            end
        end
    else
        --Add the player's pet.
        if ( UnitExists("pet") ) then
            CompactRaidFrameContainer_AddUnitFrame(self, "pet", "pet");
        end
        for i=1, GetNumSubgroupMembers() do
            local unit = "partypet"..i;
            if ( UnitExists(unit) ) then
                CompactRaidFrameContainer_AddUnitFrame(self, unit, "pet");
            end
        end
    end
end

local flaggedRoles = { "MAINTANK", "MAINASSIST" };
function CompactRaidFrameContainer_AddFlaggedUnits(self)
    if ( not IsInRaid() ) then
        return;
    end
    for roleIndex = 1, #flaggedRoles do
        local desiredRole = flaggedRoles[roleIndex]
        for i=1, MAX_RAID_MEMBERS do
            local unit = "raid"..i;
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);
            if ( role == desiredRole ) then
                FlowContainer_BeginAtomicAdd(self); --We want each unit to be right next to its target and target of target.

                CompactRaidFrameContainer_AddUnitFrame(self, unit, "flagged");

                --If we want to display the tank/assist target...
                local targetFrame = CompactRaidFrameContainer_AddUnitFrame(self, unit.."target", "target");
                CompactUnitFrame_SetUpdateAllOnUpdate(targetFrame, true);

                --Target of target?
                local targetOfTargetFrame = CompactRaidFrameContainer_AddUnitFrame(self, unit.."targettarget", "target");
                CompactUnitFrame_SetUpdateAllOnUpdate(targetOfTargetFrame, true);

                --Add some space before the next one.
                --FlowContainer_AddSpacer(self, 36);

                FlowContainer_EndAtomicAdd(self);
            end
        end
    end
end

--Utility Functions
function CompactRaidFrameContainer_AddUnitFrame(self, unit, frameType)
    local frame = CompactRaidFrameContainer_GetUnitFrame(self, unit, frameType);

    CompactUnitFrame_SetUnit(frame, unit);
    FlowContainer_AddObject(self, frame);

    return frame;
end

local function applyFunc(unitFrame, updateSpecifier, func, ...)
    func(unitFrame, ...);
end

local unitFramesCreated = 0;
function CompactRaidFrameContainer_GetUnitFrame(self, unit, frameType)
    local info = frameCreationSpecifiers[frameType];
    assert(info);
    assert(info.setUpFunc);

    --Get the mapping for re-using frames
    local mapping;
    if ( info.mapping ) then
        mapping = info.mapping(unit);
    else
        mapping = unit;
    end

    local frame = CompactRaidFrameReservation_GetFrame(self.frameReservations[frameType], mapping);
    if ( not frame ) then
        unitFramesCreated = unitFramesCreated + 1;
        frame = CreateFrame("Button", "CompactRaidFrame"..unitFramesCreated, self, "CompactUnitFrameTemplate");
        frame.applyFunc = applyFunc;
        CompactUnitFrame_SetUpFrame(frame, info.setUpFunc);
        CompactUnitFrame_SetUpdateAllEvent(frame, "GROUP_ROSTER_UPDATE");
        frame.unusedFunc = self.unitFrameUnusedFunc;
        tinsert(self.frameUpdateList[info.updateList], frame);
        CompactRaidFrameReservation_RegisterReservation(self.frameReservations[frameType], frame, mapping);

        RegisterUnitWatch(frame);
    end

    frame.inUse = true;
    return frame;
end

function CompactRaidFrameContainer_ReleaseAllReservedFrames(self)
    for key, reservations in pairs(self.frameReservations) do
        CompactRaidFrameReservation_ReleaseUnusedReservations(reservations);
    end
end

function RaidUtil_GetUsedGroups(tab)    --Fills out the table with which groups have people.
    for i=1, MAX_RAID_GROUPS do
        tab[i] = false;
    end
    if ( IsInRaid() ) then
        for i=1, GetNumRaidMembers() do
            local name, rank, subgroup = GetRaidRosterInfo(i);
            tab[subgroup] = true;
        end
    end
    return tab;
end

--========================================================================--
-- Raid size preview ("Raid Size" in the raid manager and the options' Layout
-- tab). Out of combat, the container is filled with placeholder frames for a
-- 10-, 25- or 40-player raid in the current group layout, so frame size and
-- position can be set up while solo. The raid frames and the manager are shown
-- while it is on. Not saved; it ends when combat starts.
--========================================================================--
local raidPreviewSize;

function CRF_GetRaidPreviewSize()
    return raidPreviewSize;
end

function CRF_SetRaidPreviewSize(size)
    size = tonumber(size);
    if ( size and size <= 0 ) then
        size = nil;
    end
    if ( size == raidPreviewSize ) then
        return true;
    end
    if ( size and InCombatLockdown() ) then
        DEFAULT_CHAT_FRAME:AddMessage(COMPACT_UNIT_FRAME_ERRCOMBAT);
        return false;
    end
    raidPreviewSize = size;

    -- Placeholder units on group frames are dropped (or real ones restored).
    -- In combat (only when switching off) these and the layout below wait for
    -- the end of combat by themselves.
    if ( not size and not InCombatLockdown() ) then
        for groupNum = 1, MAX_RAID_GROUPS do
            local groupFrame = _G["CompactRaidGroup"..groupNum];
            if ( groupFrame ) then
                CompactRaidGroup_UpdateUnits(groupFrame);
            end
        end
    end
    -- Manager / container visibility (shown while previewing) and side bar.
    if ( CompactRaidFrameManager_UpdateAll ) then
        CompactRaidFrameManager_UpdateAll(CompactRaidFrameManager);
    end
    CompactRaidFrameContainer_TryUpdate(CompactRaidFrameContainer);
    if ( CRF_OnRaidPreviewChanged ) then
        CRF_OnRaidPreviewChanged();
    end
    return true;
end
