--========================================================================--
-- Totem and rune boxes under your own raid frame.
--
-- Blizzard shows totem timers (shamans; also a Death Knight's temporary ghoul)
-- and Death Knight runes on the player frame, so they go when "Hide Player
-- Frame" hides it (CRF_IsHidePlayerFrameEnabled). Instead, a row of small
-- boxes sits right under your own raid frame, and the frames after yours make
-- room for it (CompactRaidGroup_UpdateLayout, CompactRaidFrameContainer.lua):
--   Shamans: earth, fire, water and air, in the totem bar's order. A totem's
--     box shows its icon and the time left; right-click destroys the totem,
--     as on the player frame. An empty slot is a dim box in its element's
--     colour.
--   Death Knights: the six runes in the player frame's order (blood, frost,
--     unholy; a death rune turns purple). A used rune dims and fills back up
--     from the bottom as it returns. A seventh box shows a temporary ghoul.
-- Unit frames can't move in combat, so the room stays even with no totem down.
-- The boxes are plain frames and update in combat.
--========================================================================--

local BOX_SPACING = 2;      -- between boxes
local GHOUL_GAP = 4;        -- between the runes and the ghoul's box
local PADDING = 2;          -- above and below the boxes
local INSET = 1;            -- from your frame's left (and right) edge

-- The totem bar's order (SHAMAN_TOTEM_PRIORITIES): earth, fire, water, air.
local EARTH, FIRE, WATER, AIR = EARTH_TOTEM_SLOT or 2, FIRE_TOTEM_SLOT or 1, WATER_TOTEM_SLOT or 3, AIR_TOTEM_SLOT or 4;
local TOTEM_SLOTS = { EARTH, FIRE, WATER, AIR };
local TOTEM_COLORS = {
    [EARTH] = { 0.55, 0.75, 0.25 },
    [FIRE]  = { 1.00, 0.45, 0.15 },
    [WATER] = { 0.25, 0.60, 1.00 },
    [AIR]   = { 0.75, 0.75, 1.00 },
};
local EMPTY_ALPHA = 0.3;

-- The player frame's rune order: blood, blood, frost, frost, unholy, unholy
-- (runes 1-2 are blood, 3-4 unholy, 5-6 frost).
local RUNE_ORDER = { 1, 2, 5, 6, 3, 4 };
-- By rune type: 1 blood, 2 unholy, 3 frost, 4 death.
local RUNE_COLORS = { { 1.00, 0.15, 0.15 }, { 0.15, 0.75, 0.15 }, { 0.20, 0.85, 1.00 }, { 0.80, 0.25, 1.00 } };
local RUNE_NAMES = { "BLOOD", "UNHOLY", "FROST", "DEATH" };
local RECHARGING_ALPHA = 0.25;
local CHARGE_ALPHA = 0.75;

local GHOUL_BOX = 7;

--------------------------------------------------------------------------
-- Who gets boxes, and how much room they need
--------------------------------------------------------------------------
local function CRFClassBar_GetClassKind()
    local _, class = UnitClass("player");
    if ( class == "SHAMAN" ) then
        return "TOTEMS";
    elseif ( class == "DEATHKNIGHT" ) then
        return "RUNES";
    end
end

-- The boxes are in use while Hide Player Frame is on (the player frame and
-- the totems / runes on it are hidden whenever your raid frame is shown).
local function CRFClassBar_GetKind()
    if ( CRF_IsHidePlayerFrameEnabled and CRF_IsHidePlayerFrameEnabled() ) then
        return CRFClassBar_GetClassKind();
    end
end

-- Boxes sized like the frame's other parts, all fitting across the frame.
local function CRFClassBar_GetBoxSize(kind, width, height)
    local count, gaps = 4, 3 * BOX_SPACING;
    if ( kind == "RUNES" ) then
        count, gaps = 7, 5 * BOX_SPACING + GHOUL_GAP;
    end
    local componentScale = min(height / 36, width / 72);
    return max(4, floor(min(9 * componentScale, (width - 2 * INSET - gaps) / count)));
end

-- Room (height) the boxes need under a unit frame of this size; 0 when there
-- are none (other classes, or Hide Player Frame off).
function CRF_GetClassBarRoom(width, height)
    local kind = CRFClassBar_GetKind();
    if ( not kind or not width or not height or width <= 0 or height <= 0 ) then
        return 0;
    end
    return CRFClassBar_GetBoxSize(kind, width, height) + 2 * PADDING;
end

-- Whether the boxes go under the frame showing this unit: yours. In a raid
-- size preview every placeholder shows you; there it's the first one.
function CRF_IsClassBarUnit(unit, first)
    if ( not unit or not CRFClassBar_GetKind() or not UnitIsUnit(unit, "player") ) then
        return false;
    end
    if ( CRF_GetRaidPreviewSize and CRF_GetRaidPreviewSize() ) then
        return first and true or false;
    end
    return true;
end

--------------------------------------------------------------------------
-- The boxes
--------------------------------------------------------------------------
local bar = CreateFrame("Frame", "CompactRaidFrameClassBar", UIParent);
bar:Hide();
bar.boxes = {};

local function CRFClassBar_FormatTime(timeLeft)
    if ( timeLeft >= 60 ) then
        return format("%dm", ceil(timeLeft / 60));
    end
    return format("%d", ceil(timeLeft));
end

local function CRFClassBar_Box_OnEnter(self)
    local text = self.rune and _G["COMBAT_TEXT_RUNE_"..(RUNE_NAMES[GetRuneType(self.rune)] or "")];
    if ( not ((self.totemSlot and self.active) or text) ) then
        return;
    end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT");
    if ( text ) then
        GameTooltip:SetText(text);
    else
        GameTooltip:SetTotem(self.totemSlot);
    end
    GameTooltip:Show();
end

local function CRFClassBar_Box_OnLeave(self)
    if ( GameTooltip:IsOwned(self) ) then
        GameTooltip:Hide();
    end
end

-- Right-click a totem away, as on the player frame.
local function CRFClassBar_Box_OnClick(self, button)
    if ( button == "RightButton" and self.totemSlot and self.active ) then
        DestroyTotem(self.totemSlot);
    end
end

local function CRFClassBar_SetInset(region, box)
    region:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1);
    region:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1);
end

local function CRFClassBar_CreateBox()
    local box = CreateFrame("Button", nil, bar);
    box:RegisterForClicks("RightButtonUp");
    box:SetScript("OnClick", CRFClassBar_Box_OnClick);
    box:SetScript("OnEnter", CRFClassBar_Box_OnEnter);
    box:SetScript("OnLeave", CRFClassBar_Box_OnLeave);

    local edge = box:CreateTexture(nil, "BACKGROUND");
    edge:SetAllPoints(box);
    edge:SetTexture(0, 0, 0, 0.85);

    box.fill = box:CreateTexture(nil, "BORDER");        -- element / rune colour
    CRFClassBar_SetInset(box.fill, box);
    box.fill:SetTexture(1, 1, 1);

    box.charge = box:CreateTexture(nil, "ARTWORK");     -- a rune coming back
    box.charge:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 1, 1);
    box.charge:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1);
    box.charge:SetTexture(1, 1, 1);
    box.charge:SetAlpha(CHARGE_ALPHA);
    box.charge:Hide();

    box.icon = box:CreateTexture(nil, "ARTWORK");
    CRFClassBar_SetInset(box.icon, box);
    box.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    box.icon:Hide();

    box.cooldown = CreateFrame("Cooldown", nil, box, "CooldownFrameTemplate");
    CRFClassBar_SetInset(box.cooldown, box);
    box.cooldown:SetReverse(true);
    box.cooldown.noCooldownCount = true;    -- the box shows its own time (OmniCC & co. skip it)
    box.cooldown:Hide();

    local overlay = CreateFrame("Frame", nil, box);  -- the time, above the cooldown sweep
    overlay:SetAllPoints(box);
    overlay:SetFrameLevel(box.cooldown:GetFrameLevel() + 1);
    box.timer = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall");
    box.timer:SetPoint("CENTER", box, "CENTER", 1, 0);
    return box;
end

-- One box per totem slot, or per rune plus the ghoul's.
local function CRFClassBar_SetKind(kind)
    if ( bar.kind == kind ) then
        return;
    end
    bar.kind = kind;
    local count = (kind == "RUNES") and GHOUL_BOX or #TOTEM_SLOTS;
    for i=1, max(count, #bar.boxes) do
        local box = bar.boxes[i];
        if ( i <= count ) then
            if ( not box ) then
                box = CRFClassBar_CreateBox();
                bar.boxes[i] = box;
            end
            box.rune = (kind == "RUNES") and RUNE_ORDER[i] or nil;
            box.totemSlot = (kind == "TOTEMS") and TOTEM_SLOTS[i] or nil;
            box.isGhoul = (kind == "RUNES" and i == GHOUL_BOX) or nil;
            box.active, box.expires, box.recharging = nil, nil, nil;
            box.icon:Hide();
            box.cooldown:Hide();
            box.charge:Hide();
            box.timer:SetText("");
            box:Show();
        elseif ( box ) then
            box:Hide();
        end
    end
    bar.count = count;
end

local function CRFClassBar_SetBoxSize(size)
    local x = 0;
    for i=1, bar.count do
        local box = bar.boxes[i];
        if ( i > 1 ) then
            x = x + (box.isGhoul and GHOUL_GAP or BOX_SPACING);
        end
        box:ClearAllPoints();
        box:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0);
        box:SetSize(size, size);
        local fontFile = box.timer:GetFont();
        box.timer:SetFont(fontFile, max(6, floor(size * 0.55 + 0.5)), "OUTLINE");
        x = x + size;
    end
    bar:SetSize(x, size);
    bar.boxSize = size;
end

-- A totem's icon, sweep and time left; an empty slot dims to its colour.
local function CRFClassBar_UpdateTotemBox(box, slot, now)
    local haveTotem, _, startTime, duration, icon = GetTotemInfo(slot);
    local expires = (haveTotem and duration and duration > 0) and (startTime + duration) or 0;
    if ( expires > now ) then
        box.active, box.expires = true, expires;
        box.icon:SetTexture(icon);
        box.icon:Show();
        box.cooldown:SetCooldown(startTime, duration);
        box.cooldown:Show();
        box.timer:SetText(CRFClassBar_FormatTime(expires - now));
        return true;
    end
    box.active, box.expires = nil, nil;
    box.icon:Hide();
    box.cooldown:Hide();
    box.timer:SetText("");
    local color = TOTEM_COLORS[slot] or TOTEM_COLORS[EARTH];
    box.fill:SetVertexColor(color[1], color[2], color[3]);
    box.fill:SetAlpha(EMPTY_ALPHA);
    return false;
end

local function CRFClassBar_UpdateCharge(box, now)
    local progress = (now - box.start) / box.duration;
    local inner = box:GetHeight() - 2;
    if ( progress <= 0 or inner <= 0 ) then
        box.charge:Hide();
    else
        box.charge:SetHeight(inner * min(progress, 1));
        box.charge:Show();
    end
end

-- A rune: bright when ready, dim and filling up while it comes back.
local function CRFClassBar_UpdateRuneBox(box, now)
    local start, duration, ready = GetRuneCooldown(box.rune);
    local color = RUNE_COLORS[GetRuneType(box.rune) or 0] or RUNE_COLORS[1];
    box.fill:SetVertexColor(color[1], color[2], color[3]);
    box.charge:SetVertexColor(color[1], color[2], color[3]);
    if ( ready or not (start and duration and duration > 0) ) then
        box.recharging = nil;
        box.fill:SetAlpha(1);
        box.charge:Hide();
        return false;
    end
    box.recharging, box.start, box.duration = true, start, duration;
    box.fill:SetAlpha(RECHARGING_ALPHA);
    CRFClassBar_UpdateCharge(box, now);
    return true;
end

-- A Death Knight's temporary ghoul (or whatever else is in a totem slot).
local function CRFClassBar_UpdateGhoulBox(box, now)
    for slot=1, MAX_TOTEMS or 4 do
        local haveTotem, _, startTime, duration = GetTotemInfo(slot);
        if ( haveTotem and duration and duration > 0 and startTime + duration > now ) then
            box.totemSlot = slot;
            box:Show();
            return CRFClassBar_UpdateTotemBox(box, slot, now);
        end
    end
    box.totemSlot, box.active, box.expires = nil, nil, nil;
    box:Hide();
    return false;
end

local CRFClassBar_OnUpdate;

local function CRFClassBar_Update()
    if ( not bar.kind ) then
        return;
    end
    local now = GetTime();
    local ticking = false;
    for i=1, bar.count do
        local box = bar.boxes[i];
        local boxTicking;
        if ( box.rune ) then
            boxTicking = CRFClassBar_UpdateRuneBox(box, now);
        elseif ( box.isGhoul ) then
            boxTicking = CRFClassBar_UpdateGhoulBox(box, now);
        else
            boxTicking = CRFClassBar_UpdateTotemBox(box, box.totemSlot, now);
        end
        ticking = ticking or boxTicking;
    end
    bar.elapsed = 0;
    bar:SetScript("OnUpdate", ticking and CRFClassBar_OnUpdate or nil);
end

-- Time left and rune fill, a few times a second while anything is running.
function CRFClassBar_OnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed;
    if ( self.elapsed < 0.05 ) then
        return;
    end
    self.elapsed = 0;
    local now = GetTime();
    local ticking = false;
    for i=1, self.count do
        local box = self.boxes[i];
        if ( box.expires ) then
            if ( box.expires <= now ) then
                CRFClassBar_Update();   -- ran out (the totem update event follows)
                return;
            end
            box.timer:SetText(CRFClassBar_FormatTime(box.expires - now));
            ticking = true;
        elseif ( box.recharging ) then
            CRFClassBar_UpdateCharge(box, now);
            ticking = true;
        end
    end
    if ( not ticking ) then
        self:SetScript("OnUpdate", nil);
    end
end

bar:SetScript("OnShow", CRFClassBar_Update);
bar:SetScript("OnEvent", function(self)
    if ( self:IsVisible() ) then
        CRFClassBar_Update();
    end
end);
bar:RegisterEvent("PLAYER_ENTERING_WORLD");
bar:RegisterEvent("PLAYER_TOTEM_UPDATE");
bar:RegisterEvent("RUNE_POWER_UPDATE");
bar:RegisterEvent("RUNE_TYPE_UPDATE");

--------------------------------------------------------------------------
-- Placing them: after each layout of the raid frames
--------------------------------------------------------------------------
-- The frame in use that the layout left room under (crfClassBarRoom): one in
-- the container's flow, or a member of a group frame in use.
local function CRFClassBar_FindOwner()
    local container = CompactRaidFrameContainer;
    local owner;
    CRF_ForEachCompactUnitFrame(function(frame)
        if ( owner or not frame.crfClassBarRoom or not frame.unit ) then
            return;
        end
        local parent = frame:GetParent();
        if ( parent == container ) then
            if ( frame.inUse ) then
                owner = frame;
            end
        elseif ( parent and parent:IsShown() and parent:GetParent() == container ) then
            owner = frame;
        end
    end);
    return owner;
end

function CRF_UpdateClassBar()
    local kind = CRFClassBar_GetKind();
    local owner = kind and CRFClassBar_FindOwner();
    if ( not owner ) then
        bar:Hide();
        return;
    end
    CRFClassBar_SetKind(kind);
    bar:SetParent(owner);
    bar:SetFrameStrata(owner:GetFrameStrata());
    bar:ClearAllPoints();
    bar:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", INSET, -PADDING);
    CRFClassBar_SetBoxSize(owner.crfClassBarRoom - 2 * PADDING);
    bar:Show();
    CRFClassBar_Update();
end

-- Hide Player Frame switched on or off (out of combat): the frames make room
-- for the boxes, or close the gap again. (The first call always lays out, so
-- the saved setting wins over anything laid out before it was loaded.)
local roomKind;
function CRF_UpdateClassBarRoom()
    local kind = CRFClassBar_GetKind() or false;
    if ( kind == roomKind or InCombatLockdown() ) then
        return;
    end
    roomKind = kind;
    for groupNum=1, MAX_RAID_GROUPS do
        local groupFrame = _G["CompactRaidGroup"..groupNum];
        if ( groupFrame ) then
            CompactRaidGroup_UpdateLayout(groupFrame);
        end
    end
    if ( CompactPartyFrame ) then
        CompactRaidGroup_UpdateLayout(CompactPartyFrame);
    end
    if ( CompactRaidFrameContainer ) then
        CompactRaidFrameContainer_TryUpdate(CompactRaidFrameContainer);
    end
end
