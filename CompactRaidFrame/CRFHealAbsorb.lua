--[[----------------------------------------------------------------------------
    CRFHealAbsorb.lua  -  heal prediction (LibHealComm-4.0) + damage absorbs
    (AbsorbsMonitor-1.0) for the stock-3.3.5a backport.

    The source repo dropped these libs and relied on ClassicAPI no-ops. We bundle
    the proven WotLK libs and wire them into the CompactUnitFrame heal-prediction
    code path. Everything here is GUARDED: if a library is missing the unit-frame
    system is completely unaffected and the bars simply stay hidden (the no-op
    fallbacks in WotLKCompat.lua remain in force).

    Loads AFTER CompactUnitFrame.xml (needs CompactUnitFrame_OnLoad /
    DefaultCompactUnitFrameOptions) and AFTER Libs\Load.xml (needs the libs).
------------------------------------------------------------------------------]]

local HealComm  = LibStub and LibStub:GetLibrary("LibHealComm-4.0", true)
local LibAbsorb = LibStub and LibStub:GetLibrary("AbsorbsMonitor-1.0", true)

local UnitGUID, GetTime, select, pairs, wipe = UnitGUID, GetTime, select, pairs, wipe

--========================================================================--
-- Incoming heals.  CompactUnitFrame_UpdateHealPrediction calls:
--   UnitGetIncomingHeals(unit, "player")  -> heals on `unit` cast by me
--   UnitGetIncomingHeals(unit)            -> all incoming heals on `unit`
-- LibHealComm's GetHealAmount(guid, bitFlag, time, casterGUID) gives both.
--========================================================================--
if HealComm then
    -- ALL_HEALS = direct + channelled + HoTs. HoT ticks are predicted by LibHealComm
    -- the instant the HoT is applied, so the bar can sit ~1 tick ahead of the actual
    -- tick (an inherent LibHealComm-4.0 limitation on 3.3.5a), but the user prefers
    -- having HoT prediction over not having it.
    local HEAL_FLAGS = HealComm.ALL_HEALS
    function UnitGetIncomingHeals(unit, healer)
        if not unit then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        local amount
        if healer then
            local hguid = UnitGUID(healer)
            if not hguid then return end
            amount = HealComm:GetHealAmount(guid, HEAL_FLAGS, GetTime() + 5, hguid)
        else
            amount = HealComm:GetHealAmount(guid, HEAL_FLAGS, GetTime() + 5)
        end
        if amount then
            -- LibHealComm reports raw amounts and tracks the target's healing
            -- modifier separately (Mortal Strike, Wound Poison, Aimed Shot,
            -- Divine Hymn, ...); without this the bar over-predicted on
            -- anyone with a healing debuff.
            amount = amount * (HealComm:GetHealModifier(guid) or 1)
        end
        return amount
    end
end

--========================================================================--
-- Damage absorbs (Power Word: Shield, Divine Aegis, Sacred Shield, Ice Barrier,
-- Mana Shield, etc. — AbsorbsMonitor-1.0 tracks them via UNIT_AURA + combat log
-- and exposes a per-GUID total).
--========================================================================--
if LibAbsorb then
    function UnitGetTotalAbsorbs(unit)
        if not unit then return end
        local guid = UnitGUID(unit)
        local total = guid and LibAbsorb.Unit_Total(guid)
        if not total or total < 0 then return 0 end  -- guard the AbsorbMonitor TexCoord bug
        return total
    end
end

--========================================================================--
-- Callback wiring.  The libs broadcast every heal/absorb change in range, with
-- the affected GUIDs as arguments. One listener marks only the unit frames
-- showing those GUIDs as dirty; CompactUnitFrame's dirty-flag batching
-- (SetHealPredictionDirty -> OnUpdate) then re-queries the amounts once per
-- frame. (An older build registered every unit frame as its own listener and
-- dirtied ALL of them on every single heal anywhere in the raid.)
--========================================================================--
local unitFrames = {}   -- every compact unit frame created (they are never destroyed)
local dirtyGUIDs = {}

local function MarkDirty()
    for frame in pairs(unitFrames) do
        local unit = frame.unit
        if unit then
            local guid = UnitGUID(frame.displayedUnit or unit)
            if guid and dirtyGUIDs[guid] then
                CompactUnitFrame_SetHealPredictionDirty(frame)
            end
        end
    end
    wipe(dirtyGUIDs)
end

local function MarkGUID(guid)
    if guid then
        dirtyGUIDs[guid] = true
        MarkDirty()
    end
end

local function MarkGUIDs(...)
    local any
    for i = 1, select("#", ...) do
        local guid = select(i, ...)
        if guid then
            dirtyGUIDs[guid] = true
            any = true
        end
    end
    if any then
        MarkDirty()
    end
end

-- HealComm_HealStarted / Updated / Delayed (casterGUID, spellID, bitType, endTime, ...targets)
-- HealComm_HealStopped (casterGUID, spellID, bitType, interrupted, ...targets)
local function OnHealEvent(event, casterGUID, spellID, bitType, endTimeOrInterrupted, ...)
    MarkGUIDs(...)
end

-- HealComm_ModifierChanged (guid, modifier) / HealComm_GUIDDisappeared (guid)
-- AbsorbsMonitor EffectUpdated / EffectRemoved / UnitUpdated / UnitCleared (guid, ...)
local function OnGUIDEvent(event, guid)
    MarkGUID(guid)
end

-- AbsorbsMonitor EffectApplied (sourceGUID, sourceName, destGUID, ...)
local function OnAbsorbApplied(event, sourceGUID, sourceName, destGUID)
    MarkGUID(destGUID)
end

local listener = {}
if HealComm then
    HealComm.RegisterCallback(listener, "HealComm_HealStarted",     OnHealEvent)
    HealComm.RegisterCallback(listener, "HealComm_HealUpdated",     OnHealEvent)
    HealComm.RegisterCallback(listener, "HealComm_HealDelayed",     OnHealEvent)
    HealComm.RegisterCallback(listener, "HealComm_HealStopped",     OnHealEvent)
    HealComm.RegisterCallback(listener, "HealComm_ModifierChanged", OnGUIDEvent)
    HealComm.RegisterCallback(listener, "HealComm_GUIDDisappeared", OnGUIDEvent)
end
if LibAbsorb then
    LibAbsorb.RegisterCallback(listener, "EffectApplied", OnAbsorbApplied)
    LibAbsorb.RegisterCallback(listener, "EffectUpdated", OnGUIDEvent)
    LibAbsorb.RegisterCallback(listener, "EffectRemoved", OnGUIDEvent)
    LibAbsorb.RegisterCallback(listener, "UnitUpdated",   OnGUIDEvent)
    LibAbsorb.RegisterCallback(listener, "UnitCleared",   OnGUIDEvent)
end

-- Registers a unit frame for heal/absorb refreshes (kept under its old name).
function CompactUnitFrame_RegisterCallback(self)
    unitFrames[self] = true
end

-- The source's CompactUnitFrame_OnLoad does not register lib callbacks (the
-- standalone's did). Hook it so every unit frame is tracked on creation.
if (HealComm or LibAbsorb) and type(CompactUnitFrame_OnLoad) == "function" then
    hooksecurefunc("CompactUnitFrame_OnLoad", function(self)
        CompactUnitFrame_RegisterCallback(self)
    end)
end

--========================================================================--
-- Turn heal prediction ON by default (the source's option tables left it unset,
-- so the bars never drew even when a heal lib was present). The setup code
-- (DefaultCompactUnitFrameSetup) already creates the prediction/absorb textures.
--========================================================================--
if (HealComm or LibAbsorb) then
    if DefaultCompactUnitFrameOptions then
        DefaultCompactUnitFrameOptions.displayHealPrediction = true
    end
    if DefaultCompactMiniFrameOptions then
        DefaultCompactMiniFrameOptions.displayHealPrediction = true
    end
end
