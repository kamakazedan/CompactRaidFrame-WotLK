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
-- frame has no title and no gap for it. Run from the container's layout, which
-- never happens in combat (moving the members is protected).
function CompactPartyFrame_UpdateTitle(frame)
    local inGroup = IsInGroup() and true or false;
    if ( inGroup == (frame.title:IsShown() and true or false) ) then
        return;
    end
    if ( inGroup ) then
        frame.title:Show();
    else
        frame.title:Hide();
    end
    CompactRaidGroup_UpdateLayout(frame);
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
