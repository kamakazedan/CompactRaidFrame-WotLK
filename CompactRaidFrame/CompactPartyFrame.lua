function CompactPartyFrame_OnLoad(self)
    self.applyFunc = CompactRaidGroup_ApplyFunctionToAllFrames;

    local unitFrame = _G[self:GetName().."Member1"];
    CompactUnitFrame_SetUpFrame(unitFrame, DefaultCompactUnitFrameSetup);
    CompactUnitFrame_SetUnit(unitFrame, "player");
    CompactUnitFrame_SetUpdateAllEvent(unitFrame, "GROUP_ROSTER_UPDATE");
    RegisterUnitWatch(unitFrame);

    for i=1, MEMBERS_PER_RAID_GROUP do
        if ( i > 1 ) then	--Player has to be done separately.
            local unitFrame = _G[self:GetName().."Member"..i];
            CompactUnitFrame_SetUpFrame(unitFrame, DefaultCompactUnitFrameSetup);
            CompactUnitFrame_SetUnit(unitFrame, "party"..(i-1));
            CompactUnitFrame_SetUpdateAllEvent(unitFrame, "GROUP_ROSTER_UPDATE");
            RegisterUnitWatch(unitFrame);
        end
    end

    self.title:SetText(PARTY);
    self.title:Disable();
end

-- "Party" only in a party: solo (raid frames kept on screen by Always show) the
-- frame has no title and no gap for it. The frame is as long as the members it
-- shows (you and party1-4). Run from the container's layout, which never
-- happens in combat (moving the members is protected).
function CompactPartyFrame_UpdateTitle(frame)
    local inGroup = IsInGroup() and true or false;
    local members = min(MEMBERS_PER_RAID_GROUP, 1 + GetNumSubgroupMembers());
    if ( inGroup == (frame.title:IsShown() and true or false) and frame.shownMembers == members ) then
        return;
    end
    if ( inGroup ) then
        frame.title:Show();
    else
        frame.title:Hide();
    end
    frame.shownMembers = members;
    CompactRaidGroup_UpdateLayout(frame);
end

-- You and the party in the Sort By order (with "Keep Me at the Top": you
-- first). The slots after them keep the next party units, so someone joining
-- in combat still shows up (in order once combat ends). Run from the
-- container's layout, never in combat (it assigns units to secure frames).
local partyMembers = {};
function CompactPartyFrame_UpdateUnits(frame)
    local members = min(MEMBERS_PER_RAID_GROUP, 1 + GetNumSubgroupMembers());
    wipe(partyMembers);
    tinsert(partyMembers, "player");
    for i=1, members - 1 do
        tinsert(partyMembers, "party"..i);
    end
    local sortFunc = CRF_GetMemberSortFunction and CRF_GetMemberSortFunction();
    if ( sortFunc ) then
        table.sort(partyMembers, sortFunc);
    end
    for i=members + 1, MEMBERS_PER_RAID_GROUP do
        tinsert(partyMembers, "party"..(i - 1));
    end
    for i=1, MEMBERS_PER_RAID_GROUP do
        local unitFrame = _G[frame:GetName().."Member"..i];
        if ( unitFrame.unit ~= partyMembers[i] ) then
            CompactUnitFrame_SetUnit(unitFrame, partyMembers[i]);
        end
    end
end

function CompactPartyFrame_Generate()
    local frame = CompactPartyFrame;
    local didCreate = false;
    if ( not frame ) then
        frame = CreateFrame("Frame", "CompactPartyFrame", UIParent, "CompactPartyFrameTemplate");
        CompactRaidGroup_UpdateBorder(frame);
        didCreate = true;
    end

    return frame, didCreate;
end
