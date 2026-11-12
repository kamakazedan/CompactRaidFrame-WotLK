local MAX_CUF_PROFILES = 10;
local PROFILES, CUF_CONFIG, PROFILE_COPY;

local DEFAULT_PROFILE = {
	name = DEFAULT_CUF_PROFILE_NAME,
	isDynamic = true,

	shown = true,
	locked = true,
	sortBy = "group",
	displayAggroHighlight = true,
	displayMainTankAndAssist = true,
	displayBorder = true,
	displayNonBossDebuffs = true,
	displayHealPrediction = true,
	healthText = "none",
	frameWidth = 72,
	frameHeight = 36,
};

-- Bumped when stored profiles need a one-time update (see ADDON_LOADED below).
local OPTIONS_VERSION = 2;

local ALL_OPTIONS = {
	shown = 0,
	locked = 0,
	keepGroupsTogether = 1,
	horizontalGroups = 1,
	sortBy = 1,
	displayPowerBar = 1,
	displayOnlyHealerPowerBars = 1,
	displayHealPrediction = 1,
	displayAggroHighlight = 1,
	useClassColors = 1,
	displayPets = 1,
	displayMainTankAndAssist = 1,
	displayBorder = 1,
	displayNonBossDebuffs = 1,
	displayOnlyDispellableDebuffs = 1,
	healthText = 1,
	frameWidth = 1,
	frameHeight = 1,
	autoActivate2Players = 1,
	autoActivate3Players = 1,
	autoActivate5Players = 1,
	autoActivate10Players = 1,
	autoActivate15Players = 1,
	autoActivate25Players = 1,
	autoActivate40Players = 1,
	autoActivatePvP = 1,
	autoActivatePvE = 1,
};

local ProfileAPI = CreateFrame("Frame");
ProfileAPI:SetScript("OnEvent", function(self, event, addon)
	if ( addon == "CompactRaidFrame" ) then
		-- Account-wide storage: profiles and settings live in
		-- CompactRaidFrameAccountDB (## SavedVariables) so they are shared by
		-- every character. Older versions stored everything per character in
		-- CompactRaidFrameDB; the FIRST login after this change seeds the
		-- account DB with a copy of that character's data so existing profiles
		-- carry over. The old per-character DB is kept on disk as a backup but
		-- is never read or written again once the account DB exists.
		local DB = _G["CompactRaidFrameAccountDB"];
		if ( not DB ) then
			local charDB = _G["CompactRaidFrameDB"];
			DB = charDB and CopyTable(charDB) or {useCompactPartyFrames = "1"};
			_G["CompactRaidFrameAccountDB"] = DB;
		end

		-- Migration: an AceDB layout (the old standalone used AceDB-3.0) or
		-- legacy per-profile spec keys.
		if ( DB.profileKeys or DB.profile or DB.profiles ) then
			wipe(DB);
			-- The wipe drops the stock default; restore it so compact party
			-- frames are on after migrating away from the AceDB layout.
			DB.useCompactPartyFrames = "1";
		else
			local P1 = DB[1];
			if ( P1 and (P1.autoActivateSpec1 or P1.autoActivateSpec2) ) then
				for i=1,#DB do
					DB[i].autoActivateSpec1 = nil;
					DB[i].autoActivateSpec2 = nil;
				end
			end
		end

		-- Guarantee the stock default exists no matter what state the saved DB
		-- was left in by older/broken builds (nil here => party frames stayed the
		-- Blizzard default and the compact container never displayed).
		if ( DB.useCompactPartyFrames == nil ) then
			DB.useCompactPartyFrames = "1";
		end

		-- Options added later. A profile stores "off" as a missing key, so a
		-- new option that should start out on has to be switched on once in
		-- the profiles saved before it existed.
		if ( (DB.crfOptionsVersion or 1) < 2 ) then
			-- 1.19: "Display Incoming Heals" (heal prediction was always shown).
			for i=1,#DB do
				DB[i].displayHealPrediction = true;
			end
		end
		DB.crfOptionsVersion = OPTIONS_VERSION;

		PROFILES = DB;
		CUF_CONFIG = DB;

		CompactUnitFrameProfiles_OnEvent(CompactUnitFrameProfiles, "COMPACT_UNIT_FRAME_PROFILES_LOADED");
		self:UnregisterEvent(event);
		self:SetScript("OnEvent", nil);
	end
end)
ProfileAPI:RegisterEvent("ADDON_LOADED");

function GetNumRaidProfiles()
	if ( not PROFILES ) then
		return 0;
	end

	return #PROFILES;
end

function GetRaidProfileName(index)
	if ( not PROFILES or not index ) then
		return;
	end

	if PROFILES[index] then
		return PROFILES[index].name;
	end
end

function RaidProfileExists(profile)
	if ( not PROFILES or not profile ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i];
		if ( profileData.name == profile ) then
			return true;
		end
	end
end

function HasLoadedCUFProfiles()
	return PROFILES and true or false;
end

function RaidProfileHasUnsavedChanges()
	if not ( PROFILES and PROFILE_COPY ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i]
		if ( profileData.name == PROFILE_COPY.name ) then
			for option, valid in pairs(ALL_OPTIONS) do
				if ( valid == 1 and profileData[option] ~= PROFILE_COPY[option] ) then
					return true;
				end
			end
		end
	end
end

function RestoreRaidProfileFromCopy()
	if ( not PROFILE_COPY or not RaidProfileHasUnsavedChanges() ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i]
		if ( profileData.name == PROFILE_COPY.name ) then
			for option, valid in pairs(ALL_OPTIONS) do
				if ( valid == 1 and profileData[option] ~= PROFILE_COPY[option] ) then
					profileData[option] = PROFILE_COPY[option];
				end
			end
			break;
		end
	end
end

function CreateNewRaidProfile(name, baseOnProfile)
	if ( not PROFILES or not name ) then
		return;
	end

	local profile
	if ( baseOnProfile and baseOnProfile ~= DEFAULTS ) then
		for i=1,#PROFILES do
			local profileData = PROFILES[i];
			if ( profileData.name == baseOnProfile ) then
				profile = CopyTable(profileData);
				break;
			end
		end
	else
		profile = CopyTable(DEFAULT_PROFILE);
	end

	profile.name = name;
	table.insert(PROFILES, profile);
end

function DeleteRaidProfile(profile)
	if ( not PROFILES or not profile ) then
		return;
	end

	if ( type(profile) == "number" ) then
		table.remove(PROFILES, profile);
	else
		for i=1,#PROFILES do
			local profileData = PROFILES[i];
			if ( profileData.name == profile ) then
				table.remove(PROFILES, i);
				break;
			end
		end
	end
end

-- Snapshot `profile` so Cancel / "Don't Save" can restore it later. This must
-- ALWAYS take a fresh copy: it is called when switching to another profile, and
-- skipping it there (as an older build did whenever the previous profile had no
-- unsaved changes) left the snapshot pointing at the OLD profile, so edits to
-- the newly selected one were never detected (Save stayed greyed out, Cancel
-- didn't revert them, and no "unsaved changes" prompt appeared).
function SaveRaidProfileCopy(profile)
	if ( not PROFILES or not profile ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i];
		if ( profileData.name == profile ) then
			PROFILE_COPY = CopyTable(profileData);
			break;
		end
	end
end

function SetRaidProfileOption(profile, optionName, value)
	if ( not PROFILES or not profile or not optionName ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i];
		if ( profileData.name == profile ) then
			PROFILES[i][optionName] = value or nil;
			break;
		end
	end
end

-- Like SetRaidProfileOption, but the change counts as saved: the snapshot that
-- Cancel restores gets the same value. Used by the raid manager's own controls,
-- which apply at once; other unsaved edits in the options panel stay unsaved.
function CRF_SetRaidProfileOptionSaved(profile, optionName, value)
	SetRaidProfileOption(profile, optionName, value);
	if ( PROFILE_COPY and PROFILE_COPY.name == profile ) then
		PROFILE_COPY[optionName] = value or nil;
	end
end

function GetRaidProfileOption(profile, optionName)
	if ( not PROFILES or not profile or not optionName ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i];
		if ( profileData.name == profile ) then
			return profileData[optionName];
		end
	end
end

function GetRaidProfileFlattenedOptions(profile)
	if ( not PROFILES or not profile ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i];
		if ( profileData.name == profile ) then
			local flattenedCache = {};
			for option, value in pairs(ALL_OPTIONS) do
				flattenedCache[option] = profileData[option] or false;
			end
			return flattenedCache;
		end
	end
end

function SetRaidProfileSavedPosition(profile, isDynamic, topPoint, topOffset, bottomPoint, bottomOffset, leftPoint, leftOffset)
	if ( not PROFILES or not profile ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i];
		if ( profileData.name == profile ) then
			profileData.isDynamic = isDynamic or nil;
			profileData.topPoint = topPoint;
			profileData.topOffset = topOffset;
			profileData.bottomPoint = bottomPoint;
			profileData.bottomOffset = bottomOffset;
			profileData.leftPoint = leftPoint;
			profileData.leftOffset = leftOffset;
			break;
		end
	end
end

function GetRaidProfileSavedPosition(profile)
	if ( not PROFILES or not profile ) then
		return;
	end

	for i=1,#PROFILES do
		local profileData = PROFILES[i];
		if ( profileData.name == profile ) then
			return profileData.isDynamic, profileData.topPoint, profileData.topOffset, profileData.bottomPoint, profileData.bottomOffset, profileData.leftPoint, profileData.leftOffset;
		end
	end
end

function GetMaxNumCUFProfiles()
	return MAX_CUF_PROFILES;
end

function SetActiveRaidProfile(profile)
	CUF_CVar:SetValue("ACTIVE_CUF_PROFILE", profile);
end

function GetActiveRaidProfile()
	return CUF_CVar:GetValue("ACTIVE_CUF_PROFILE");
end

CUF_CVar = {}
function CUF_CVar:SetValue(cvar, value)
	if ( not CUF_CONFIG ) then
		return;
	end

	-- Store "0" as "0". Turning it into nil (as an older build did) made
	-- "Use Raid-Style Party Frames" switch itself back on after every reload,
	-- because the loader treats a missing value as "never set" -> default "1".
	CUF_CONFIG[cvar] = value;
end

function CUF_CVar:GetValue(cvar, addon)
	if ( not CUF_CONFIG ) then
		return;
	end

	return CUF_CONFIG[cvar];
end

function CUF_CVar:GetCVarBool(cvar)
	return self:GetValue(cvar) == "1" and true or false;
end

-- "Always show (even when solo)". Account-wide, saved in CompactRaidFrameAccountDB
-- (it used to live in a plain global that was never saved, so it reset to "on"
-- at every login). nil = never set = off: since 1.18 the raid frames and the
-- raid manager are hidden when solo unless the option is ticked (it used to
-- default to on). A value the player saved, on or off, is kept.
function CRF_IsAlwaysEnabled()
	local value = CUF_CONFIG and CUF_CONFIG.alwaysShowSolo;
	if ( value == nil ) then
		return false;
	end
	return value and true or false;
end

function CRF_SetAlwaysEnabled(enabled)
	if ( CUF_CONFIG ) then
		CUF_CONFIG.alwaysShowSolo = enabled and true or false;
	end
	-- Manager / container / party-frame visibility (deferred until combat ends).
	if ( CompactRaidFrameManager and CompactRaidFrameManager_UpdateAll ) then
		CompactRaidFrameManager_UpdateAll(CompactRaidFrameManager);
	end
end

-- "Show raid manager tab only on mouseover": while the raid manager is
-- collapsed, its tab at the screen edge stays hidden until the mouse is over
-- it. Account-wide; nil = never set = on. The manager polls this, so changing
-- it needs no further update call (and is fine in combat: it only sets alpha).
function CRF_IsManagerTabFadeEnabled()
	local value = CUF_CONFIG and CUF_CONFIG.fadeManagerTab;
	if ( value == nil ) then
		return true;
	end
	return value and true or false;
end

function CRF_SetManagerTabFadeEnabled(enabled)
	if ( CUF_CONFIG ) then
		CUF_CONFIG.fadeManagerTab = enabled and true or false;
	end
end

-- "Hide player frame when raid frames are shown". Account-wide; nil = never
-- set = on. CRF_UpdatePlayerFrameVisibility (CompactRaidFrameManager.lua) does
-- the work and postpones it until combat ends if needed.
function CRF_IsHidePlayerFrameEnabled()
	local value = CUF_CONFIG and CUF_CONFIG.hidePlayerFrame;
	if ( value == nil ) then
		return true;
	end
	return value and true or false;
end

function CRF_SetHidePlayerFrameEnabled(enabled)
	if ( CUF_CONFIG ) then
		CUF_CONFIG.hidePlayerFrame = enabled and true or false;
	end
	if ( CRF_UpdatePlayerFrameVisibility ) then
		CRF_UpdatePlayerFrameVisibility();
	end
end
