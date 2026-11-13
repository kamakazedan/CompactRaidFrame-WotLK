function CompactRaidGroup_OnLoad(self)
    self.title:Disable();

    self:RegisterEvent("GROUP_ROSTER_UPDATE");
    self:RegisterEvent("PLAYER_REGEN_ENABLED");
    self.applyFunc = CompactRaidGroup_ApplyFunctionToAllFrames;
end

function CompactRaidGroup_OnEvent(self, event, ...)
    if ( event == "PLAYER_REGEN_ENABLED" ) then
        if ( self.PLAYER_REGEN_ENABLED_AWAIT ) then
            self.PLAYER_REGEN_ENABLED_AWAIT = nil;
            CompactRaidGroup_UpdateUnits(self);
        end
    elseif ( event == "GROUP_ROSTER_UPDATE" ) then
        if ( InCombatLockdown() ) then
            self.PLAYER_REGEN_ENABLED_AWAIT = true;
            return;
        end
        CompactRaidGroup_UpdateUnits(self);
    end
end

function CompactRaidGroup_ApplyFunctionToAllFrames(frame, updateSpecifier, func, ...)
    if ( updateSpecifier == "normal" or updateSpecifier == "all" ) then
        for i=1, MEMBERS_PER_RAID_GROUP do
            local unitFrame = _G[frame:GetName().."Member"..i];
            func(unitFrame, ...);
        end
    elseif ( updateSpecifier == "group" ) then
        func(frame, ...);
    end
end

function CompactRaidGroup_GenerateForGroup(groupIndex)
    local didCreate = false;
    local frame = _G["CompactRaidGroup"..groupIndex]
    if ( not frame ) then
        frame = CreateFrame("Frame", "CompactRaidGroup"..groupIndex, UIParent, "CompactRaidGroupTemplate");
        CompactRaidGroup_InitializeForGroup(frame, groupIndex);
        --CompactRaidGroup_UpdateLayout(frame);	--Update border calls UpdateLayout.
        CompactRaidGroup_UpdateBorder(frame);
        didCreate = true;
    end
    return frame, didCreate;
end

function CompactRaidGroup_InitializeForGroup(frame, groupIndex)
    frame:SetID(groupIndex);
    for i=1, MEMBERS_PER_RAID_GROUP do
        local unitFrame = _G[frame:GetName().."Member"..i];
        CompactUnitFrame_SetUpFrame(unitFrame, DefaultCompactUnitFrameSetup);
        CompactUnitFrame_SetUpdateAllEvent(unitFrame, "GROUP_ROSTER_UPDATE");
        RegisterUnitWatch(unitFrame);
    end
    CompactRaidGroup_UpdateUnits(frame);
    frame.title:SetFormattedText(GROUP_NUMBER, groupIndex);
end

local groupMembers = {};
function CompactRaidGroup_UpdateUnits(frame)
    local groupIndex = frame:GetID();
    local frameIndex = 1;
    local previewSize = CRF_GetRaidPreviewSize and CRF_GetRaidPreviewSize();
    if ( previewSize ) then
        -- Raid size preview: this group's share of the placeholders.
        local count = max(0, min(MEMBERS_PER_RAID_GROUP, previewSize - (groupIndex - 1) * MEMBERS_PER_RAID_GROUP));
        for i=1, MEMBERS_PER_RAID_GROUP do
            CompactUnitFrame_SetUnit(_G[frame:GetName().."Member"..i], (i <= count) and "player" or nil);
        end
        CompactRaidGroup_SetShownMembers(frame, count);
    elseif ( IsInRaid() ) then
        -- In the Sort By order (with "Keep Me at the Top": the player first).
        local sortFunc = CRF_GetMemberSortFunction and CRF_GetMemberSortFunction();
        local playerFirst = CompactRaidFrameManager_GetSetting and CompactRaidFrameManager_GetSetting("SortPlayerFirst");
        playerFirst = playerFirst and playerFirst ~= "0";
        wipe(groupMembers);
        for i=1, GetNumGroupMembers() do
            local name, rank, subgroup = GetRaidRosterInfo(i);
            if ( subgroup == groupIndex ) then
                if ( playerFirst and not sortFunc and UnitIsUnit("raid"..i, "player") ) then
                    tinsert(groupMembers, 1, "raid"..i);
                else
                    tinsert(groupMembers, "raid"..i);
                end
            end
        end
        if ( sortFunc ) then
            table.sort(groupMembers, sortFunc);
        end
        for i=1, min(#groupMembers, MEMBERS_PER_RAID_GROUP) do
            CompactUnitFrame_SetUnit(_G[frame:GetName().."Member"..frameIndex], groupMembers[i]);
            frameIndex = frameIndex + 1;
        end

        for i=frameIndex, MEMBERS_PER_RAID_GROUP do
            local unitFrame = _G[frame:GetName().."Member"..i];
            CompactUnitFrame_SetUnit(unitFrame, nil);
        end
        CompactRaidGroup_SetShownMembers(frame, frameIndex - 1);
    else
        -- Not in a raid, so the group frames are not in use: drop leftover
        -- units (placeholders from a preview, or the last raid's members).
        for i=1, MEMBERS_PER_RAID_GROUP do
            local unitFrame = _G[frame:GetName().."Member"..i];
            if ( unitFrame.unit ) then
                CompactUnitFrame_SetUnit(unitFrame, nil);
            end
        end
    end
    CompactRaidGroup_UpdateClassBarRoom(frame);
end

-- A group frame is as long as the members it shows (not always 5), so its
-- border and anything under it (pets) sit right after the last member.
function CompactRaidGroup_GetShownMembers(frame)
    return max(1, min(frame.shownMembers or MEMBERS_PER_RAID_GROUP, MEMBERS_PER_RAID_GROUP));
end

function CompactRaidGroup_SetShownMembers(frame, count)
    if ( frame.shownMembers ~= count ) then
        frame.shownMembers = count;
        CompactRaidGroup_UpdateLayout(frame);
    end
end

-- Your totem / rune boxes (CRFClassBar.lua) go under your frame: which member
-- shows you, and the room they need after it (nil, 0 for no boxes).
function CompactRaidGroup_FindClassBarMember(frame)
    if ( not CRF_GetClassBarRoom ) then
        return nil, 0;
    end
    local name = frame:GetName();
    local frame1 = _G[name.."Member1"];
    local room = CRF_GetClassBarRoom(frame1:GetWidth(), frame1:GetHeight());
    if ( room > 0 ) then
        for i=1, CompactRaidGroup_GetShownMembers(frame) do
            if ( CRF_IsClassBarUnit(_G[name.."Member"..i].unit, i == 1 and frame:GetID() == 1) ) then
                return i, room;
            end
        end
    end
    return nil, 0;
end

-- After new units: lay out again if the member with the room changed.
-- (Out of combat, as the units were.)
function CompactRaidGroup_UpdateClassBarRoom(frame)
    local member, room = CompactRaidGroup_FindClassBarMember(frame);
    if ( member ~= frame.classBarMember or room ~= (frame.classBarRoom or 0) ) then
        CompactRaidGroup_UpdateLayout(frame);
    end
end

function CompactRaidGroup_UpdateLayout(frame)
    -- No room for a hidden title (the party frame hides "Party" when solo).
    local titleHeight = frame.title:IsShown() and frame.title:GetHeight() or 0;
    local totalHeight = titleHeight;
    local totalWidth = 0;
    -- Room under your frame for your totem / rune boxes: in a column the
    -- members after you move down, in a row the row is taller.
    local barMember, barRoom = CompactRaidGroup_FindClassBarMember(frame);
    frame.classBarMember, frame.classBarRoom = barMember, barRoom;
    for i=1, MEMBERS_PER_RAID_GROUP do
        _G[frame:GetName().."Member"..i].crfClassBarRoom = (i == barMember) and barRoom or nil;
    end
    if ( CUF_HORIZONTAL_GROUPS ) then
        frame.title:ClearAllPoints();
        frame.title:SetPoint("TOPLEFT");

        local frame1 = _G[frame:GetName().."Member1"];
        frame1:ClearAllPoints();
        frame1:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -titleHeight);

        for i=2, MEMBERS_PER_RAID_GROUP do
            local unitFrame = _G[frame:GetName().."Member"..i];
            unitFrame:ClearAllPoints();
            unitFrame:SetPoint("LEFT", _G[frame:GetName().."Member"..(i-1)], "RIGHT", 0, 0);
        end
        totalHeight = totalHeight + _G[frame:GetName().."Member1"]:GetHeight() + barRoom;
        totalWidth = totalWidth + _G[frame:GetName().."Member1"]:GetWidth() * CompactRaidGroup_GetShownMembers(frame);
    else
        frame.title:ClearAllPoints();
        frame.title:SetPoint("TOP");

        local frame1 = _G[frame:GetName().."Member1"];
        frame1:ClearAllPoints();
        frame1:SetPoint("TOP", frame, "TOP", 0, -titleHeight);

        for i=2, MEMBERS_PER_RAID_GROUP do
            local unitFrame = _G[frame:GetName().."Member"..i];
            unitFrame:ClearAllPoints();
            unitFrame:SetPoint("TOP", _G[frame:GetName().."Member"..(i-1)], "BOTTOM", 0, (i - 1 == barMember) and -barRoom or 0);
        end
        totalHeight = totalHeight + _G[frame:GetName().."Member1"]:GetHeight() * CompactRaidGroup_GetShownMembers(frame) + barRoom;
        totalWidth = totalWidth + _G[frame:GetName().."Member1"]:GetWidth();
    end

    if ( frame.borderFrame:IsShown() ) then
        totalWidth = totalWidth + 12;
        totalHeight = totalHeight + 4;
    end

    frame:SetSize(totalWidth, totalHeight);
end

function CompactRaidGroup_UpdateBorder(frame)
    if ( CUF_SHOW_BORDER ) then
        frame.borderFrame:Show();
    else
        frame.borderFrame:Hide();
    end
    CompactRaidGroup_UpdateLayout(frame);
end

function CompactRaidGroup_StartMoving(frame)
    --Move the frame right onto the cursor.
    local cursorX, cursorY = GetCursorPosition();
    frame:ClearAllPoints();
    frame:SetPoint("TOP", UIParent, "BOTTOMLEFT", cursorX / UIParent:GetScale(), cursorY / UIParent:GetScale() + 10);

    frame:StartMoving();
    MOVING_COMPACT_RAID_FRAME = frame;
end

function CompactRaidGroup_StopMoving(frame)
    frame:StopMovingOrSizing();
    if ( MOVING_COMPACT_RAID_FRAME == frame ) then
        MOVING_COMPACT_RAID_FRAME = nil;
    end
end

function CompactRaidGroup_StopAllMoving()
    if ( MOVING_COMPACT_RAID_FRAME ) then
        CompactRaidGroup_StopMoving(MOVING_COMPACT_RAID_FRAME)
    end
end