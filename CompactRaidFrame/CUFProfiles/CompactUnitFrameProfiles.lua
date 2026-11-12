local GetInstanceInfo = C_GetInstanceInfo;

local AUTO_ACTIVATION_AWAIT;    -- roster changed in combat: re-check auto-activation afterwards
local APPLY_PROFILE_AWAIT;      -- profile changed in combat: apply it once combat ends

-- Every widget that mirrors an option. CompactUnitFrameProfiles_UpdateCurrentPanel
-- refreshes them all whenever the active profile or an option changes.
local optionControls = {};

function CompactUnitFrameProfiles_OnLoad(self)
	self:RegisterEvent("VARIABLES_LOADED");
	self:RegisterEvent("COMPACT_UNIT_FRAME_PROFILES_LOADED");
	self:RegisterEvent("GROUP_ROSTER_UPDATE");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");

	--Get this working with the InterfaceOptions panel.
	self.name = COMPACT_UNIT_FRAME_PROFILES_LABEL;
	BlizzardOptionsPanel_OnLoad(self, CompactUnitFrameProfiles_SaveChanges, CompactUnitFrameProfiles_CancelCallback, CompactUnitFrameProfiles_DefaultCallback, CompactUnitFrameProfiles_UpdateCurrentPanel);
	-- Zoning drives auto-activation. The stock BlizzardOptionsPanel_OnLoad
	-- registers this too, but don't depend on it.
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:SetScript("OnEvent", CompactUnitFrameProfiles_OnEvent);

	CompactUnitFrameProfiles_CreateOptions(self);
	InterfaceOptions_AddCategory(self);
end

-- Slider track. ClassicAPI's HorizontalSliderTemplate drew this from
-- BACKDROP_SLIDER_8_8 (nil on 3.3.5a); set it with the native SetBackdrop instead
-- so the Frame Height / Frame Width sliders show a draggable bar.
function CompactUnitFrameProfilesSlider_SetTrack(self)
	self:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	});
end

function CompactUnitFrameProfiles_OnEvent(self, event, ...)
	if ( event == "COMPACT_UNIT_FRAME_PROFILES_LOADED" ) then
		--HasLoadedCUFProfiles will now return true.
		self:UnregisterEvent(event);
		CompactUnitFrameProfiles_ValidateProfilesLoaded(self);
	elseif ( event == "VARIABLES_LOADED" ) then
		self.variablesLoaded = true;
		self:UnregisterEvent(event);
		CompactUnitFrameProfiles_ValidateProfilesLoaded(self);
	elseif ( event == "PLAYER_ENTERING_WORLD" ) then	--Check for zoning
		CompactUnitFrameProfiles_CheckAutoActivation();
	elseif ( event == "PLAYER_REGEN_ENABLED" ) then
		if ( APPLY_PROFILE_AWAIT ) then
			CompactUnitFrameProfiles_ApplyCurrentSettings();
		end
		if ( AUTO_ACTIVATION_AWAIT ) then
			AUTO_ACTIVATION_AWAIT = nil;
			CompactUnitFrameProfiles_CheckAutoActivation();
		end
	elseif ( event == "GROUP_ROSTER_UPDATE" ) then
		if ( InCombatLockdown() ) then
			AUTO_ACTIVATION_AWAIT = true;
		else
			CompactUnitFrameProfiles_CheckAutoActivation();
		end
	end
end

function CompactUnitFrameProfiles_ValidateProfilesLoaded(self)
	if ( HasLoadedCUFProfiles() and self.variablesLoaded ) then
		if ( RaidProfileExists(GetActiveRaidProfile()) ) then
			CompactUnitFrameProfiles_ActivateRaidProfile(GetActiveRaidProfile());
		elseif ( GetNumRaidProfiles() == 0 ) then	--If we don't have any profiles, we need to create a new one.
			CompactUnitFrameProfiles_ResetToDefaults();
		else
			CompactUnitFrameProfiles_ActivateRaidProfile(GetRaidProfileName(1));
		end

		-- Party frames / manager / container visibility for the saved
		-- "Use Raid-Style Party Frames" and "Always show" settings.
		if ( CompactRaidFrameManager and CompactRaidFrameManager_UpdateAll ) then
			CompactRaidFrameManager_UpdateAll(CompactRaidFrameManager);
		end
	end
end

function CompactUnitFrameProfiles_DefaultCallback(self)
	CompactUnitFrameProfiles_ResetToDefaults();
end

function CompactUnitFrameProfiles_ResetToDefaults()
	local profiles = {};
	for i=1, GetNumRaidProfiles() do
		tinsert(profiles, GetRaidProfileName(i));
	end
	for i=1, #profiles do
		DeleteRaidProfile(profiles[i]);
	end
	CreateNewRaidProfile(DEFAULT_CUF_PROFILE_NAME);
	CompactUnitFrameProfiles_ActivateRaidProfile(DEFAULT_CUF_PROFILE_NAME);
end

function CompactUnitFrameProfiles_SaveChanges(self)
	SaveRaidProfileCopy(self.selectedProfile);	--Save off the current version in case we cancel.
	CompactUnitFrameProfiles_UpdateManagementButtons();
end

function CompactUnitFrameProfiles_CancelCallback(self)
	CompactUnitFrameProfiles_CancelChanges(self);
end

function CompactUnitFrameProfiles_CancelChanges(self)
	RestoreRaidProfileFromCopy();
	CompactUnitFrameProfiles_UpdateCurrentPanel();
	CompactUnitFrameProfiles_ApplyCurrentSettings();
end

function CompactUnitFrameProfiles_PlayCheckSound(checked)
	PlaySound(checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff");
end

function CompactUnitFrameProfilesNewProfileDialogBaseProfileSelector_SetUp(self)
	C_UIDropDownMenu_SetWidth(self, 190);
	C_UIDropDownMenu_Initialize(self, CompactUnitFrameProfilesNewProfileDialogBaseProfileSelector_Initialize);
end

function CompactUnitFrameProfilesNewProfileDialogBaseProfileSelector_Initialize()
	local info = C_UIDropDownMenu_CreateInfo();

	info.text = DEFAULTS;
	info.disabled  = InCombatLockdown();
	info.value = nil;
	info.func = CompactUnitFrameProfilesNewProfileDialogBaseProfileSelectorButton_OnClick;
	info.checked = CompactUnitFrameProfiles.newProfileDialog.baseProfile == info.value;
	info.isRadio = true;
	C_UIDropDownMenu_AddButton(info);

	for i=1, GetNumRaidProfiles() do
		local name = GetRaidProfileName(i);
		info.text = name;
		info.disabled  = InCombatLockdown();
		info.value = name;
		info.func = CompactUnitFrameProfilesNewProfileDialogBaseProfileSelectorButton_OnClick;
		info.checked = CompactUnitFrameProfiles.newProfileDialog.baseProfile == info.value;
		C_UIDropDownMenu_AddButton(info);
	end
end

function CompactUnitFrameProfilesNewProfileDialogBaseProfileSelectorButton_OnClick(self)
	CompactUnitFrameProfiles.newProfileDialog.baseProfile = self.value;
	C_UIDropDownMenu_SetSelectedValue(CompactUnitFrameProfilesNewProfileDialogBaseProfileSelector, self.value);
end

function CompactUnitFrameProfilesProfileSelector_SetUp(self)
	-- 170 (not Blizzard's 190) so Save/Delete fit on the same row.
	C_UIDropDownMenu_SetWidth(self, 170);
	C_UIDropDownMenu_Initialize(self, CompactUnitFrameProfilesProfileSelector_Initialize);
end

function CompactUnitFrameProfilesProfileSelector_Initialize()
	local info = C_UIDropDownMenu_CreateInfo();
	for i=1, GetNumRaidProfiles() do
		local name = GetRaidProfileName(i);
		info.text = name;
		info.disabled  = InCombatLockdown();
		info.func = CompactUnitFrameProfilesProfileSelectorButton_OnClick;
		info.value = name;
		info.checked = CompactUnitFrameProfiles.selectedProfile == name;
		info.isRadio = true;
		C_UIDropDownMenu_AddButton(info);
	end

	info.text = NEW_COMPACT_UNIT_FRAME_PROFILE;
	info.func = CompactUnitFrameProfiles_NewProfileButtonClicked;
	info.value = nil;
	info.checked = false;
	info.notCheckable = true;
	info.disabled = InCombatLockdown() or GetNumRaidProfiles() >= GetMaxNumCUFProfiles();
	info.isRadio = true;
	C_UIDropDownMenu_AddButton(info);
end

function CompactUnitFrameProfilesProfileSelectorButton_OnClick(self)
	if ( RaidProfileHasUnsavedChanges() ) then
		CompactUnitFrameProfiles_ConfirmUnsavedChanges("select", self.value);
	else
		CompactUnitFrameProfiles_ActivateRaidProfile(self.value);
	end
end

function CompactUnitFrameProfiles_NewProfileButtonClicked()
	if ( RaidProfileHasUnsavedChanges() ) then
		CompactUnitFrameProfiles_ConfirmUnsavedChanges("new");
	else
		CompactUnitFrameProfiles_ShowNewProfileDialog();
	end
end

function CompactUnitFrameProfiles_ActivateRaidProfile(profile)
	CompactUnitFrameProfiles.selectedProfile = profile;
	SaveRaidProfileCopy(profile);	--Save off the current version in case we cancel.
	SetActiveRaidProfile(profile);
	C_UIDropDownMenu_SetSelectedValue(CompactUnitFrameProfilesProfileSelector, profile);
	C_UIDropDownMenu_SetText(CompactUnitFrameProfilesProfileSelector, profile);
	C_UIDropDownMenu_SetSelectedValue(CompactRaidFrameManagerDisplayFrameProfileSelector, profile);
	C_UIDropDownMenu_SetText(CompactRaidFrameManagerDisplayFrameProfileSelector, profile);

	CompactUnitFrameProfiles_HidePopups();
	CompactUnitFrameProfiles_UpdateCurrentPanel();
	CompactUnitFrameProfiles_ApplyCurrentSettings();
end

function CompactUnitFrameProfiles_ApplyCurrentSettings()
	CompactUnitFrameProfiles_ApplyProfile(GetActiveRaidProfile());
end

function CompactUnitFrameProfiles_UpdateCurrentPanel()
	for i=1, #optionControls do
		optionControls[i]:updateFunc();
	end
	CompactUnitFrameProfiles_UpdateManagementButtons();
	CompactUnitFrameProfile_UpdateAutoActivationDisabledLabel();
end

function CompactUnitFrameProfiles_CreateProfile(profileName)
	CreateNewRaidProfile(profileName, CompactUnitFrameProfiles.newProfileDialog.baseProfile);
	CompactUnitFrameProfiles_ActivateRaidProfile(profileName);
end

function CompactUnitFrameProfiles_UpdateNewProfileCreateButton()
	local button = CompactUnitFrameProfiles.newProfileDialog.createButton;
	local text = strtrim(CompactUnitFrameProfiles.newProfileDialog.editBox:GetText());

	if ( text == "" or RaidProfileExists(text) or strlower(text) == strlower(DEFAULTS) or GetNumRaidProfiles() >= GetMaxNumCUFProfiles() ) then
		button:Disable();
	else
		button:Enable();
	end
end

function CompactUnitFrameProfiles_HideNewProfileDialog()
	CompactUnitFrameProfiles.newProfileDialog:Hide();
end

function CompactUnitFrameProfiles_ShowNewProfileDialog()
	C_UIDropDownMenu_SetSelectedValue(CompactUnitFrameProfilesNewProfileDialogBaseProfileSelector, nil);
	C_UIDropDownMenu_SetText(CompactUnitFrameProfilesNewProfileDialogBaseProfileSelector, DEFAULTS);
	CompactUnitFrameProfiles.newProfileDialog.baseProfile = nil;
	CompactUnitFrameProfiles.newProfileDialog:Show();
	CompactUnitFrameProfiles.newProfileDialog.editBox:SetText("");
	CompactUnitFrameProfiles.newProfileDialog.editBox:SetFocus();
	CompactUnitFrameProfiles_UpdateNewProfileCreateButton();
end

function CompactUnitFrameProfiles_ConfirmProfileDeletion(profile)
	CompactUnitFrameProfiles.deleteProfileDialog.profile = profile;
	CompactUnitFrameProfiles.deleteProfileDialog.label:SetFormattedText(CONFIRM_COMPACT_UNIT_FRAME_PROFILE_DELETION, profile);
	CompactUnitFrameProfiles.deleteProfileDialog:Show();
end

-- "Delete" in the confirmation dialog: switch to another profile, then remove it.
function CompactUnitFrameProfiles_DeleteProfile(profile)
	if ( not profile or GetNumRaidProfiles() <= 1 ) then
		return;
	end
	local newProfile = GetRaidProfileName(1);
	if ( newProfile == profile ) then
		newProfile = GetRaidProfileName(2);
	end
	CompactUnitFrameProfiles_ActivateRaidProfile(newProfile);
	DeleteRaidProfile(profile);
	CompactUnitFrameProfiles_UpdateManagementButtons();
end

function CompactUnitFrameProfiles_UpdateManagementButtons()
	if ( GetNumRaidProfiles() <= 1 ) then
		CompactUnitFrameProfilesDeleteButton:Disable();
	else
		CompactUnitFrameProfilesDeleteButton:Enable();
	end

	if RaidProfileHasUnsavedChanges() then
		CompactUnitFrameProfilesSaveButton:Enable();
	else
		CompactUnitFrameProfilesSaveButton:Disable();
	end
end

function CompactUnitFrameProfiles_ConfirmUnsavedChanges(action, profileArg)
	CompactUnitFrameProfiles.unsavedProfileDialog.action = action;
	CompactUnitFrameProfiles.unsavedProfileDialog.profile = profileArg;
	CompactUnitFrameProfiles.unsavedProfileDialog.label:SetFormattedText(CONFIRM_COMPACT_UNIT_FRAME_PROFILE_UNSAVED_CHANGES, CompactUnitFrameProfiles.selectedProfile);
	CompactUnitFrameProfiles.unsavedProfileDialog:Show();
end

function CompactUnitFrameProfiles_AfterConfirmUnsavedChanges()
	local action = CompactUnitFrameProfiles.unsavedProfileDialog.action;
	local profileArg = CompactUnitFrameProfiles.unsavedProfileDialog.profile;
	if ( action == "select" ) then
		CompactUnitFrameProfiles_ActivateRaidProfile(profileArg);
	elseif ( action == "new" ) then
		CompactUnitFrameProfiles_ShowNewProfileDialog();
	end
end

function CompactUnitFrameProfiles_HidePopups()
	CompactUnitFrameProfiles.newProfileDialog:Hide();
	CompactUnitFrameProfiles.deleteProfileDialog:Hide();
	CompactUnitFrameProfiles.unsavedProfileDialog:Hide();
end

local autoActivateGroupSizes = { 2, 3, 5, 10, 15, 25, 40 };
local countMap = {};	--Maps number of players to the category. (For example, so that AQ20 counts as a 25-man.)

for i, autoActivateGroupSize in ipairs(autoActivateGroupSizes) do
	local groupSizeStart = i > 1 and (autoActivateGroupSizes[i - 1] + 1) or 1;
	for groupSize = groupSizeStart, autoActivateGroupSize do
		countMap[groupSize] = autoActivateGroupSize;
	end
end

function CompactUnitFrameProfiles_GetAutoActivationState()
	local name, instanceType, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic = GetInstanceInfo();
	if ( not name ) then	--We don't have info.
		return false;
	end

	local numPlayers, profileType, enemyType;

	if ( instanceType == "party" or instanceType == "raid" ) then
		numPlayers = (maxPlayers and maxPlayers > 0) and countMap[maxPlayers] or 5;
		profileType = instanceType;
		enemyType = "PvE";
	elseif ( instanceType == "arena" ) then
		numPlayers = countMap[GetNumGroupMembers()];
		profileType = instanceType;
		enemyType = "PvP";
	elseif ( instanceType == "pvp" ) then
		numPlayers = countMap[maxPlayers];
		profileType = instanceType;
		enemyType = "PvP";
	else
		numPlayers = countMap[GetNumGroupMembers()];
		profileType = "world";
		enemyType = "PvE";
	end

	if ( not numPlayers ) then
		return false;
	end

	return true, numPlayers, profileType, enemyType;
end

local checkAutoActivationTimer;
function CompactUnitFrameProfiles_CheckAutoActivation()
	--We only want to adjust the profile when you zone. We don't want to automatically
	--change the profile when you are in the uninstanced world.
	if ( not IsInGroup() ) then
		CompactUnitFrameProfiles_SetLastActivationType(nil, nil, nil, nil);
		return;
	end

	local success, numPlayers, activationType, enemyType = CompactUnitFrameProfiles_GetAutoActivationState();

	if ( not success ) then
		--We didn't have all the relevant info yet. Update again soon.
		if ( checkAutoActivationTimer ) then
			checkAutoActivationTimer:Cancel();
		end
		checkAutoActivationTimer = C_Timer.NewTimer(3, CompactUnitFrameProfiles_CheckAutoActivation);
		return;
	else
		if ( checkAutoActivationTimer ) then
			checkAutoActivationTimer:Cancel();
			checkAutoActivationTimer = nil;
		end
	end

	local lastActivationType, lastNumPlayers, lastEnemyType = CompactUnitFrameProfiles_GetLastActivationType();
	if ( lastActivationType == activationType and lastNumPlayers == numPlayers and lastEnemyType == enemyType ) then
		--If we last auto-adjusted for this same thing, we don't change. (In case they manually changed the profile.)
		return;
	end

	if ( CompactUnitFrameProfiles_ProfileMatchesAutoActivation(GetActiveRaidProfile(), numPlayers, enemyType) ) then
		CompactUnitFrameProfiles_SetLastActivationType(activationType, numPlayers, enemyType);
	else
		-- Blizzard's loop activated EVERY matching profile in turn (a full
		-- re-layout of all frames each time) and the last match won. Pick that
		-- same profile and activate it once.
		local match;
		for i=1, GetNumRaidProfiles() do
			local profile = GetRaidProfileName(i);
			if ( CompactUnitFrameProfiles_ProfileMatchesAutoActivation(profile, numPlayers, enemyType) ) then
				match = profile;
			end
		end
		if ( match ) then
			CompactUnitFrameProfiles_ActivateRaidProfile(match);
			CompactUnitFrameProfiles_SetLastActivationType(activationType, numPlayers, enemyType);
		end
	end
end

function CompactUnitFrameProfiles_SetLastActivationType(activationType, numPlayers, enemyType)
	CompactUnitFrameProfiles.lastActivationType = activationType;
	CompactUnitFrameProfiles.lastNumPlayers = numPlayers;
	CompactUnitFrameProfiles.lastEnemyType = enemyType;
end

function CompactUnitFrameProfiles_GetLastActivationType()
	return CompactUnitFrameProfiles.lastActivationType, CompactUnitFrameProfiles.lastNumPlayers, CompactUnitFrameProfiles.lastEnemyType;
end

function CompactUnitFrameProfiles_ProfileMatchesAutoActivation(profile, numPlayers, enemyType)
	return GetRaidProfileOption(profile, "autoActivate"..numPlayers.."Players") and GetRaidProfileOption(profile, "autoActivate"..enemyType);
end

function CompactUnitFrameProfile_UpdateAutoActivationDisabledLabel()
	local label = CompactUnitFrameProfiles.optionsFrame and CompactUnitFrameProfiles.optionsFrame.autoActivateDisabledLabel;
	if ( not label ) then
		return;
	end

	local profile = GetActiveRaidProfile();
	local hasGroupSize = false;
	for i=1, #autoActivateGroupSizes do
		if ( GetRaidProfileOption(profile, "autoActivate"..autoActivateGroupSizes[i].."Players") ) then
			hasGroupSize = true;
			break;
		end
	end

	local hasEnemyType = false;
	if ( GetRaidProfileOption(profile, "autoActivatePvP") or GetRaidProfileOption(profile, "autoActivatePvE") ) then
		hasEnemyType = true;
	end

	if ( hasGroupSize == hasEnemyType ) then
		label:Hide();
	elseif ( not hasGroupSize ) then
		label:SetText(AUTO_ACTIVATE_PROFILE_NO_SIZE);
		label:Show();
	elseif ( not hasEnemyType ) then
		label:SetText(AUTO_ACTIVATE_PROFILE_NO_ENEMYTYPE);
		label:Show();
	end
end

--------------------------------------------------------------
-----------------UI Option Templates---------------------
--------------------------------------------------------------
function CompactUnitFrameProfilesOption_OnLoad(self)
	tinsert(optionControls, self);
end
-------------------------
----Dropdown--------
-------------------------
-- Required key/value pairs:
-- .optionName - String, name of option
-- .options - Array, array of possible options
-- Required strings:
-- COMPACT_UNIT_FRAME_PROFILE_<OPTION_NAME>
-- COMPACT_UNIT_FRAME_PROFILE_<OPTION_NAME>_<OPTION_VALUE>
function CompactUnitFrameProfilesDropdown_InitializeWidget(self, optionName, options, updateFunc)
	self.optionName = optionName;
	self.options = options;
	local tag = format("COMPACT_UNIT_FRAME_PROFILE_%s", strupper(optionName));
	self.label:SetText(_G[tag] or "Need string: "..tag);
	self.updateFunc = updateFunc or CompactUnitFrameProfilesDropdown_Update;
	CompactUnitFrameProfilesOption_OnLoad(self);
end

function CompactUnitFrameProfilesDropdown_OnShow(self)
	C_UIDropDownMenu_SetWidth(self, self.width or 160);
	CompactUnitFrameProfilesDropdown_Update(self);
end

function CompactUnitFrameProfilesDropdown_Update(self)
	C_UIDropDownMenu_Initialize(self, CompactUnitFrameProfilesDropdown_Initialize);
	C_UIDropDownMenu_SetSelectedValue(self, GetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, self.optionName));
end

function CompactUnitFrameProfilesDropdown_Initialize(dropDown)
	local info = C_UIDropDownMenu_CreateInfo();

	local currentValue = GetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, dropDown.optionName);
	for i=1, #dropDown.options do
		local id = dropDown.options[i];
		local tag = format("COMPACT_UNIT_FRAME_PROFILE_%s_%s", strupper(dropDown.optionName), strupper(id));
		info.text = _G[tag] or "Need string: "..tag;
		info.disabled  = InCombatLockdown();
		info.func = CompactUnitFrameProfilesDropdownButton_OnClick;
		info.arg1 = dropDown;
		info.value = id;
		info.checked = currentValue == id;
		info.isRadio = true;
		C_UIDropDownMenu_AddButton(info);
	end
end

function CompactUnitFrameProfilesDropdownButton_OnClick(button, dropDown)
	SetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, dropDown.optionName, button.value);
	C_UIDropDownMenu_SetSelectedValue(dropDown, button.value);
	CompactUnitFrameProfiles_ApplyCurrentSettings();
	CompactUnitFrameProfiles_UpdateCurrentPanel();
end
------------------------------
----------Slider-------------
------------------------------
function CompactUnitFrameProfilesSlider_InitializeWidget(self, optionName, minText, maxText, updateFunc)
	self.optionName = optionName;
	local tag = format("COMPACT_UNIT_FRAME_PROFILE_%s", strupper(optionName));
	self.label:SetText(_G[tag] or "Need string: "..tag);
	if ( minText ) then
		self.minLabel:SetText(minText);
	end
	if ( maxText ) then
		self.maxLabel:SetText(maxText);
	end

	self.updateFunc = updateFunc or CompactUnitFrameProfilesSlider_Update;
	CompactUnitFrameProfilesOption_OnLoad(self);
end

function CompactUnitFrameProfilesSlider_Update(self)
	local currentValue = GetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, self.optionName);
	if ( currentValue ) then
		-- The 3.3.5a OnValueChanged has no "user input" flag, so mark our own
		-- SetValue; otherwise every panel refresh wrote the value back and
		-- re-laid out every raid frame.
		self.isUpdating = true;
		self:SetValue(currentValue);
		self.isUpdating = nil;
	end
	-- SetValue to the value it already has fires no OnValueChanged.
	CompactUnitFrameProfilesSlider_UpdateValueText(self);
end

-- Shows how far along its range the slider is: 0% = smallest, 100% = largest.
function CompactUnitFrameProfilesSlider_UpdateValueText(self, value)
	local valueLabel = self.valueLabel;
	if ( not valueLabel ) then
		return;
	end
	local minValue, maxValue = self:GetMinMaxValues();
	value = floor((value or self:GetValue() or minValue) + 0.5);
	local percent = 0;
	if ( maxValue > minValue ) then
		percent = floor((value - minValue) / (maxValue - minValue) * 100 + 0.5);
		percent = max(0, min(100, percent));
	end
	valueLabel:SetText(format("%d%%", percent));
end

function CompactUnitFrameProfilesSlider_OnValueChanged(self, value, userInput)
	-- Before the checks below, so the number follows the thumb while dragging
	-- and also updates when the panel sets the value itself.
	CompactUnitFrameProfilesSlider_UpdateValueText(self, value);
	if ( not userInput or self.isUpdating ) then
		return;
	end
	local profile = CompactUnitFrameProfiles and CompactUnitFrameProfiles.selectedProfile;
	if ( not profile ) then
		return;
	end
	value = floor(value + 0.5);
	if ( GetRaidProfileOption(profile, self.optionName) == value ) then
		return;
	end
	SetRaidProfileOption(profile, self.optionName, value);
	CompactUnitFrameProfiles_ApplyCurrentSettings();
	CompactUnitFrameProfiles_UpdateCurrentPanel();
end
-------------------------------
-------Check Button---------
-------------------------------
function CompactUnitFrameProfilesCheckButton_InitializeWidget(self, optionName, updateFunc)
	self.optionName = optionName;
	local tag = format("COMPACT_UNIT_FRAME_PROFILE_%s", strupper(optionName));
	self.label:SetText(_G[tag] or "Need string: "..tag);
	self.updateFunc = updateFunc or CompactUnitFrameProfilesCheckButton_Update;
	CompactUnitFrameProfilesOption_OnLoad(self);
end

function CompactUnitFrameProfilesCheckButton_Update(self)
	local currentValue = GetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, self.optionName);
	self:SetChecked(currentValue);
end

function CompactUnitFrameProfilesCheckButton_OnClick(self, button)
	local checked = self:GetChecked() and true or false;
	CompactUnitFrameProfiles_PlayCheckSound(checked);

	SetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, self.optionName, checked);
	CompactUnitFrameProfiles_ApplyCurrentSettings();
	CompactUnitFrameProfiles_UpdateCurrentPanel();
end

-- Enabled: .tooltipText (if any). Disabled: .disabledTooltip, the reason it is disabled.
function CompactUnitFrameProfilesCheckButton_OnEnter(self)
	local text;
	if ( CRF_IsButtonEnabled(self) ) then
		text = self.tooltipText;
	else
		text = self.disabledTooltip;
	end
	if ( text ) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(text, nil, nil, nil, nil, true);
		GameTooltip:Show();
	end
end

-- 2/3/5-player auto-activation only works with raid-style party frames.
function CompactUnitFrameProfiles_UpdatePartySizeCheckButton(self)
	CompactUnitFrameProfilesCheckButton_Update(self);
	if ( CUF_CVar:GetCVarBool("useCompactPartyFrames") ) then
		self:Enable();
	else
		self:Disable();
	end
end

-- Account-wide (not part of a profile): saved immediately, not affected by Save/Cancel.
function CompactUnitFrameProfiles_SetUseRaidStylePartyFrames(enabled)
	CUF_CVar:SetValue("useCompactPartyFrames", enabled and "1" or "0");
	-- Party frames + manager/container visibility (postponed until combat ends).
	CompactRaidFrameManager_UpdateAll(CompactRaidFrameManager);
end

--------------------------------------------------------------
-- Group layout ("Groups", as in Edit Mode). Stored in the profile as Keep
-- Groups Together + Horizontal Groups. Used by the Layout tab and the raid
-- manager side bar.
--------------------------------------------------------------
CRF_GROUP_LAYOUTS = {
	{ key = "combineVertical",    keepGroupsTogether = false, horizontalGroups = false, text = "CRF_GROUPS_COMBINE_VERTICAL",    fallback = "Combine Groups (Vertical)" },
	{ key = "combineHorizontal",  keepGroupsTogether = false, horizontalGroups = true,  text = "CRF_GROUPS_COMBINE_HORIZONTAL",  fallback = "Combine Groups (Horizontal)" },
	{ key = "separateVertical",   keepGroupsTogether = true,  horizontalGroups = false, text = "CRF_GROUPS_SEPARATE_VERTICAL",   fallback = "Separate Groups (Vertical)" },
	{ key = "separateHorizontal", keepGroupsTogether = true,  horizontalGroups = true,  text = "CRF_GROUPS_SEPARATE_HORIZONTAL", fallback = "Separate Groups (Horizontal)" },
};

function CRF_GetGroupLayout(profile)
	if ( not profile ) then
		return nil;
	end
	local keep = GetRaidProfileOption(profile, "keepGroupsTogether") and true or false;
	local horizontal = GetRaidProfileOption(profile, "horizontalGroups") and true or false;
	for _, layout in ipairs(CRF_GROUP_LAYOUTS) do
		if ( layout.keepGroupsTogether == keep and layout.horizontalGroups == horizontal ) then
			return layout;
		end
	end
end

function CRF_GetGroupLayoutText(layout)
	if ( not layout ) then
		return "";
	end
	return _G[layout.text] or layout.fallback;
end

-- saved: the raid manager applies and saves at once; the options panel leaves
-- it as an unsaved edit, like its other controls.
function CRF_SetGroupLayout(profile, layout, saved)
	if ( not (profile and layout) ) then
		return;
	end
	local setOption = saved and CRF_SetRaidProfileOptionSaved or SetRaidProfileOption;
	setOption(profile, "keepGroupsTogether", layout.keepGroupsTogether);
	setOption(profile, "horizontalGroups", layout.horizontalGroups);
	if ( profile == GetActiveRaidProfile() ) then
		CompactUnitFrameProfiles_ApplyProfile(profile);
	end
	if ( CompactUnitFrameProfiles:IsVisible() ) then
		CompactUnitFrameProfiles_UpdateCurrentPanel();
	end
	CompactRaidFrameManager_UpdateLayoutSelectors();
end

function CompactUnitFrameProfilesGroupsDropdown_OnClick(button, layout)
	if ( InCombatLockdown() ) then
		DEFAULT_CHAT_FRAME:AddMessage(COMPACT_UNIT_FRAME_ERRCOMBAT);
		return;
	end
	CRF_SetGroupLayout(CompactUnitFrameProfiles.selectedProfile, layout, false);
end

-- Raid size preview texts and menu (CRF_SetRaidPreviewSize lives in
-- CompactRaidFrameContainer.lua).
CRF_RAID_PREVIEW_SIZES = { 10, 25, 40 };

function CRF_GetRaidPreviewText(size)
	if ( not size ) then
		return CRF_PREVIEW_OFF or "Off";
	end
	return format(CRF_PREVIEW_PLAYERS or "%d Players", size);
end

-- "Preview: 25 Players" (the raid manager's dropdown has no label of its own).
function CRF_GetRaidPreviewLabel(size)
	return format(CRF_PREVIEW_FORMAT or "Preview: %s", CRF_GetRaidPreviewText(size));
end

function CRF_AddRaidPreviewMenuButtons(onClick)
	local current = CRF_GetRaidPreviewSize();
	local inCombat = InCombatLockdown();
	for i = 0, #CRF_RAID_PREVIEW_SIZES do
		local size = CRF_RAID_PREVIEW_SIZES[i];		-- i = 0: off
		local info = C_UIDropDownMenu_CreateInfo();
		info.text = CRF_GetRaidPreviewText(size);
		info.value = size or 0;
		info.arg1 = size;
		info.func = onClick;
		info.checked = (current == size);
		info.disabled = inCombat and size ~= nil;
		C_UIDropDownMenu_AddButton(info);
	end
end

function CompactUnitFrameProfilesPreviewDropdown_OnClick(button, size)
	CRF_SetRaidPreviewSize(size);
end

-- Preview switched on or off (from either dropdown, or by combat starting).
function CRF_OnRaidPreviewChanged()
	CompactRaidFrameManager_UpdateLayoutSelectors();
	local options = CompactUnitFrameProfiles.optionsFrame;
	if ( options and options.previewDropdown ) then
		options.previewDropdown:updateFunc();
	end
end

--------------------------------------------------------------
-----------------Options panel layout-------------------------
--------------------------------------------------------------
-- The 3.3.5a Interface Options panel is about 413 x 428. Blizzard's retail
-- layout assumed a far bigger one, so the Auto-Activate column, the health text
-- dropdown and the size sliders hung outside the window. Now:
--   title / separator / [profile v] [Save] [Delete]                (XML)
--   [General] [Layout] [Display] [Auto-Activate] tabs over a box   (built here)
local OPTIONS_BOX_TOP = -114;   -- top edge of the tabbed box, relative to the panel
local OPTIONS_BOX_INSET = 12;   -- left / right / bottom margin of the box
local PAGE_INSET = 8;           -- padding inside the box
local SUB_INDENT = 15;          -- indent for options that depend on the one above
-- A dropdown's art begins ~16px right of its frame edge; this lines its label
-- and box up with the checkboxes.
local DROPDOWN_OFFSET_X = -12;

local function CreateCheckButton(page, suffix)
	return CreateFrame("CheckButton", page:GetName()..suffix, page, "CompactUnitFrameProfilesCheckButtonTemplate");
end

-- A checkbox bound to an option of the selected profile.
local function CreateProfileCheckButton(page, suffix, optionName, updateFunc)
	local check = CreateCheckButton(page, suffix);
	CompactUnitFrameProfilesCheckButton_InitializeWidget(check, optionName, updateFunc);
	return check;
end

-- A checkbox bound to an account-wide setting.
local function CreateAccountCheckButton(page, suffix, text, tooltip, getFunc, setFunc)
	local check = CreateCheckButton(page, suffix);
	check.label:SetText(text);
	check.tooltipText = tooltip;
	check.updateFunc = function(self)
		self:SetChecked(getFunc());
	end
	check:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false;
		CompactUnitFrameProfiles_PlayCheckSound(checked);
		setFunc(checked);
		CompactUnitFrameProfiles_UpdateCurrentPanel();
	end);
	CompactUnitFrameProfilesOption_OnLoad(check);
	return check;
end

local function CreateProfileDropdown(page, suffix, optionName, options, width)
	local dropdown = CreateFrame("Frame", page:GetName()..suffix, page, "CompactUnitFrameProfilesDropdownTemplate");
	dropdown.width = width;
	CompactUnitFrameProfilesDropdown_InitializeWidget(dropdown, optionName, options);
	return dropdown;
end

local function CreateProfileSlider(page, suffix, optionName, minValue, maxValue, step, minText, maxText)
	local slider = CreateFrame("Slider", page:GetName()..suffix, page, "CompactUnitFrameProfilesSliderTemplate");
	slider.isUpdating = true;	-- setting the range clamps the value; that is not user input
	slider:SetMinMaxValues(minValue, maxValue);
	slider:SetValueStep(step);
	slider.isUpdating = nil;
	CompactUnitFrameProfilesSlider_SetTrack(slider);
	CompactUnitFrameProfilesSlider_InitializeWidget(slider, optionName, minText, maxText);
	CompactUnitFrameProfilesSlider_UpdateValueText(slider);
	return slider;
end

-- A dropdown that is not a single profile option (the group layout) or not
-- saved at all (the preview): its own menu and refresh, same look and label.
local function CreateCustomDropdown(page, suffix, labelText, width, initFunc, updateFunc)
	local dropdown = CreateFrame("Frame", page:GetName()..suffix, page, "CompactUnitFrameProfilesDropdownTemplate");
	dropdown.label:SetText(labelText);
	dropdown.width = width;
	dropdown.initFunc = initFunc;
	dropdown.updateFunc = updateFunc;	-- also run by CompactUnitFrameProfiles_UpdateCurrentPanel
	dropdown:SetScript("OnShow", function(self)
		C_UIDropDownMenu_SetWidth(self, self.width);
		C_UIDropDownMenu_Initialize(self, self.initFunc);
		self:updateFunc();
	end);
	CompactUnitFrameProfilesOption_OnLoad(dropdown);
	return dropdown;
end

local function CreateResetPositionButton(page)
	local resetPosition = CreateFrame("Button", page:GetName().."ResetPositionButton", page, "UIPanelButtonTemplate2");
	resetPosition:SetWidth(160);
	resetPosition:SetHeight(22);
	resetPosition:SetText(RESET_POSITION);
	resetPosition:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOn");
		if ( InCombatLockdown() ) then
			DEFAULT_CHAT_FRAME:AddMessage(COMPACT_UNIT_FRAME_ERRCOMBAT);
			return;
		end
		CompactRaidFrameManager_ResetContainerPosition();
	end);
	return resetPosition;
end

-- General: account-wide settings, then which extra frames to show.
local function CreateGeneralPage(options, page)
	local raidStyle = CreateAccountCheckButton(page, "RaidStylePartyFrames",
		USE_RAID_STYLE_PARTY_FRAMES, OPTION_TOOLTIP_USE_RAID_STYLE_PARTY_FRAMES,
		function() return CUF_CVar:GetCVarBool("useCompactPartyFrames"); end,
		CompactUnitFrameProfiles_SetUseRaidStylePartyFrames);
	raidStyle:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0);

	local alwaysShow = CreateAccountCheckButton(page, "AlwaysShow",
		CRF_ALWAYS_SHOW_SOLO or "Always show (even when solo)",
		CRF_ALWAYS_SHOW_SOLO_TOOLTIP,
		CRF_IsAlwaysEnabled, CRF_SetAlwaysEnabled);
	alwaysShow:SetPoint("TOPLEFT", raidStyle, "BOTTOMLEFT", 0, 0);

	local tabMouseover = CreateAccountCheckButton(page, "ManagerTabMouseover",
		CRF_MANAGER_TAB_MOUSEOVER or "Show raid manager tab only on mouseover",
		CRF_MANAGER_TAB_MOUSEOVER_TOOLTIP,
		CRF_IsManagerTabFadeEnabled, CRF_SetManagerTabFadeEnabled);
	tabMouseover:SetPoint("TOPLEFT", alwaysShow, "BOTTOMLEFT", 0, 0);

	local hidePlayerFrame = CreateAccountCheckButton(page, "HidePlayerFrame",
		CRF_HIDE_PLAYER_FRAME or "Hide player frame when raid frames are shown",
		CRF_HIDE_PLAYER_FRAME_TOOLTIP,
		CRF_IsHidePlayerFrameEnabled, CRF_SetHidePlayerFrameEnabled);
	hidePlayerFrame:SetPoint("TOPLEFT", tabMouseover, "BOTTOMLEFT", 0, 0);

	-- Both anchors on the page's top edge: mixing TOPLEFT with a plain RIGHT
	-- anchor would also pin the line's vertical centre and stretch it.
	local ACCOUNT_ROWS = 4;
	local divider = page:CreateTexture(page:GetName().."Divider", "ARTWORK");
	divider:SetTexture(0.25, 0.25, 0.25);
	divider:SetHeight(1);
	divider:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -(ACCOUNT_ROWS * 26 + 6));
	divider:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, -(ACCOUNT_ROWS * 26 + 6));

	local displayPets = CreateProfileCheckButton(page, "DisplayPets", "displayPets");
	displayPets:SetPoint("TOPLEFT", hidePlayerFrame, "BOTTOMLEFT", 0, -14);

	local displayMainTankAndAssist = CreateProfileCheckButton(page, "DisplayMainTankAndAssist", "displayMainTankAndAssist");
	displayMainTankAndAssist:SetPoint("TOPLEFT", displayPets, "BOTTOMLEFT", 0, 0);
end

-- Layout: how the frames are arranged and sized (like Edit Mode's Raid Frames).
local function CreateLayoutPage(options, page)
	-- Groups: Combine / Separate, Vertical / Horizontal (Keep Groups Together +
	-- Horizontal Groups in the profile).
	local groups = CreateCustomDropdown(page, "GroupsDropdown", CRF_GROUPS or "Groups", 170,
		function(self)
			local current = CRF_GetGroupLayout(CompactUnitFrameProfiles.selectedProfile);
			for _, layout in ipairs(CRF_GROUP_LAYOUTS) do
				local info = C_UIDropDownMenu_CreateInfo();
				info.text = CRF_GetGroupLayoutText(layout);
				info.value = layout.key;
				info.arg1 = layout;
				info.func = CompactUnitFrameProfilesGroupsDropdown_OnClick;
				info.checked = (layout == current);
				info.disabled = InCombatLockdown();
				C_UIDropDownMenu_AddButton(info);
			end
		end,
		function(self)
			local layout = CRF_GetGroupLayout(CompactUnitFrameProfiles.selectedProfile);
			C_UIDropDownMenu_SetText(self, CRF_GetGroupLayoutText(layout));
			-- Sort By only applies when groups are combined.
			if ( layout and not layout.keepGroupsTogether ) then
				self.sortBy:Show();
			else
				self.sortBy:Hide();
			end
		end);
	groups:SetPoint("TOPLEFT", page, "TOPLEFT", DROPDOWN_OFFSET_X, -16);

	local sortBy = CreateProfileDropdown(page, "SortByDropdown", "sortBy", { "role", "group", "alphabetical" }, 110);
	sortBy:SetPoint("TOPLEFT", groups, "TOPRIGHT", -16, 0);
	groups.sortBy = sortBy;

	local border = CreateProfileCheckButton(page, "DisplayBorder", "displayBorder");
	border:SetPoint("TOPLEFT", groups, "BOTTOMLEFT", -DROPDOWN_OFFSET_X, -4);

	local heightSlider = CreateProfileSlider(page, "HeightSlider", "frameHeight", 36, 96, 2, SHORT, TALL);
	heightSlider:SetPoint("TOPLEFT", border, "BOTTOMLEFT", 14, -24);

	local widthSlider = CreateProfileSlider(page, "WidthSlider", "frameWidth", 72, 186, 2, NARROW, WIDE);
	widthSlider:SetPoint("LEFT", heightSlider, "RIGHT", 44, 0);

	-- Raid size preview (not part of the profile; ends when combat starts).
	local preview = CreateCustomDropdown(page, "RaidSizePreviewDropdown", CRF_RAID_SIZE_PREVIEW or "Raid Size Preview", 110,
		function(self)
			CRF_AddRaidPreviewMenuButtons(CompactUnitFrameProfilesPreviewDropdown_OnClick);
		end,
		function(self)
			C_UIDropDownMenu_SetText(self, CRF_GetRaidPreviewText(CRF_GetRaidPreviewSize()));
		end);
	preview:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", -14 + DROPDOWN_OFFSET_X, -36);
	options.previewDropdown = preview;

	local resetPosition = CreateResetPositionButton(page);
	resetPosition:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0);
end

-- Display: what each unit frame shows.
local function CreateDisplayPage(options, page)
	local healPrediction = CreateProfileCheckButton(page, "DisplayHealPrediction", "displayHealPrediction");
	healPrediction:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0);

	-- "Only healer" is greyed out (not hidden: no empty row) without power bars.
	local onlyHealer;
	local powerBar = CreateProfileCheckButton(page, "DisplayPowerBar", "displayPowerBar", function(self)
		local currentValue = GetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, self.optionName);
		self:SetChecked(currentValue);
		if ( currentValue ) then
			onlyHealer:Enable();
		else
			onlyHealer:Disable();
		end
	end);
	powerBar:SetPoint("TOPLEFT", healPrediction, "BOTTOMLEFT", 0, 0);

	onlyHealer = CreateProfileCheckButton(page, "DisplayOnlyHealerPowerBars", "displayOnlyHealerPowerBars");
	onlyHealer:SetPoint("TOPLEFT", powerBar, "BOTTOMLEFT", SUB_INDENT, 0);
	onlyHealer.disabledTooltip = CRF_REQUIRES_POWER_BARS;

	local aggroHighlight = CreateProfileCheckButton(page, "DisplayAggroHighlight", "displayAggroHighlight");
	aggroHighlight:SetPoint("TOPLEFT", powerBar, "BOTTOMLEFT", 0, -26);

	local classColors = CreateProfileCheckButton(page, "UseClassColors", "useClassColors");
	classColors:SetPoint("TOPLEFT", aggroHighlight, "BOTTOMLEFT", 0, 0);

	local showDebuffs = CreateProfileCheckButton(page, "ShowDebuffs", "displayNonBossDebuffs", function(self)
		local currentValue = GetRaidProfileOption(CompactUnitFrameProfiles.selectedProfile, self.optionName);
		if ( currentValue ) then
			self.onlyDispellable:Show();
		else
			self.onlyDispellable:Hide();
		end
		self:SetChecked(currentValue);
	end);
	showDebuffs:SetPoint("TOPLEFT", classColors, "BOTTOMLEFT", 0, 0);

	local onlyDispellable = CreateProfileCheckButton(page, "DisplayOnlyDispellableDebuffs", "displayOnlyDispellableDebuffs");
	onlyDispellable:SetPoint("TOPLEFT", showDebuffs, "BOTTOMLEFT", SUB_INDENT, 0);
	showDebuffs.onlyDispellable = onlyDispellable;

	local healthText = CreateProfileDropdown(page, "HealthTextDropdown", "healthText", { "none", "health", "losthealth", "perc" });
	healthText:SetPoint("TOPLEFT", showDebuffs, "BOTTOMLEFT", DROPDOWN_OFFSET_X, -46);
end

-- Auto-Activate: which group sizes / content switch to this profile.
local function CreateAutoActivatePage(options, page)
	local label = page:CreateFontString(page:GetName().."Label", "ARTWORK", "GameFontNormal");
	label:SetText(AUTO_ACTIVATE_ON);
	label:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4);
	options.autoActivateLabel = label;

	local previous;
	for i, size in ipairs(autoActivateGroupSizes) do
		local optionName = "autoActivate"..size.."Players";
		local check;
		if ( size <= 5 ) then
			check = CreateProfileCheckButton(page, "AutoActivate"..size.."Players", optionName, CompactUnitFrameProfiles_UpdatePartySizeCheckButton);
			check.disabledTooltip = AUTO_ACTIVATE_DISABLED_IN_PARTY;
		else
			check = CreateProfileCheckButton(page, "AutoActivate"..size.."Players", optionName);
		end
		if ( previous ) then
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 0);
		else
			check:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -4, -6);
		end
		options[optionName] = check;	-- options.autoActivate2Players, ...
		previous = check;
	end

	-- PvP / PvE in a second column, level with the first two group sizes.
	local pvp = CreateProfileCheckButton(page, "AutoActivatePvP", "autoActivatePvP");
	pvp:SetPoint("TOPLEFT", options.autoActivate2Players, "TOPLEFT", 190, 0);
	options.AutoActivatePvP = pvp;

	local pve = CreateProfileCheckButton(page, "AutoActivatePvE", "autoActivatePvE");
	pve:SetPoint("TOPLEFT", pvp, "BOTTOMLEFT", 0, 0);
	options.AutoActivatePvE = pve;

	-- "Profile will never auto-activate ..." (shown by CompactUnitFrameProfile_UpdateAutoActivationDisabledLabel)
	-- (fixed width so it word-wraps; the height follows the text)
	local disabledLabel = page:CreateFontString(page:GetName().."DisabledLabel", "ARTWORK", "GameFontNormal");
	disabledLabel:SetTextColor(1, 0.1, 0.1);
	disabledLabel:SetJustifyH("LEFT");
	disabledLabel:SetWidth(350);
	disabledLabel:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 4, -10);
	disabledLabel:Hide();
	options.autoActivateDisabledLabel = disabledLabel;
end

local OPTION_TABS = {
	{ suffix = "General",      text = CRF_OPTIONS_TAB_GENERAL or "General",            build = CreateGeneralPage },
	{ suffix = "Layout",       text = CRF_OPTIONS_TAB_LAYOUT or "Layout",              build = CreateLayoutPage },
	{ suffix = "Display",      text = CRF_OPTIONS_TAB_DISPLAY or "Display",            build = CreateDisplayPage },
	{ suffix = "AutoActivate", text = CRF_OPTIONS_TAB_AUTOACTIVATE or "Auto-Activate", build = CreateAutoActivatePage },
};

function CompactUnitFrameProfiles_SelectOptionsTab(options, id)
	PanelTemplates_SetTab(options, id);
	for i, page in ipairs(options.pages) do
		if ( i == id ) then
			page:Show();
		else
			page:Hide();
		end
	end
end

function CompactUnitFrameProfilesOptionsTab_OnClick(self)
	PlaySound("igCharacterInfoTab");
	CompactUnitFrameProfiles_SelectOptionsTab(self:GetParent(), self:GetID());
end

function CompactUnitFrameProfiles_CreateOptions(panel)
	local options = CreateFrame("Frame", panel:GetName().."Options", panel);
	options:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_BOX_INSET, OPTIONS_BOX_TOP);
	options:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -OPTIONS_BOX_INSET, OPTIONS_BOX_INSET);
	options:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	});
	options:SetBackdropColor(0.1, 0.1, 0.1, 0.5);
	options:SetBackdropBorderColor(0.6, 0.6, 0.6, 1);
	options.pages = {};
	panel.optionsFrame = options;

	local previousTab;
	for i, info in ipairs(OPTION_TABS) do
		local page = CreateFrame("Frame", options:GetName()..info.suffix, options);
		page:SetPoint("TOPLEFT", options, "TOPLEFT", PAGE_INSET, -PAGE_INSET);
		page:SetPoint("BOTTOMRIGHT", options, "BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET);
		page:Hide();
		info.build(options, page);
		options.pages[i] = page;

		-- Same tab art and spacing as the Interface window's own Game/AddOns tabs.
		-- (PanelTemplates finds them by name: <options>Tab1, Tab2, ...)
		local tab = CreateFrame("Button", options:GetName().."Tab"..i, options, "OptionsFrameTabButtonTemplate");
		tab:SetID(i);
		tab:SetText(info.text);
		if ( previousTab ) then
			tab:SetPoint("TOPLEFT", previousTab, "TOPRIGHT", -16, 0);
		else
			tab:SetPoint("BOTTOMLEFT", options, "TOPLEFT", 6, -3);
		end
		tab:SetScript("OnClick", CompactUnitFrameProfilesOptionsTab_OnClick);
		previousTab = tab;
	end
	PanelTemplates_SetNumTabs(options, #OPTION_TABS);
	CompactUnitFrameProfiles_SelectOptionsTab(options, 1);
end

-------------------------------------------------------------
-----------------Applying of Options----------------------
-------------------------------------------------------------
function CompactUnitFrameProfiles_ApplyProfile(profile)
	if ( InCombatLockdown() ) then
		-- Resizing / re-anchoring the secure unit frames is blocked in combat
		-- (it used to trigger "Interface action failed" errors); the
		-- PLAYER_REGEN_ENABLED handler applies the active profile afterwards.
		APPLY_PROFILE_AWAIT = true;
		return;
	end

	local settings = GetRaidProfileFlattenedOptions(profile);
	if ( not settings ) then
		return;
	end
	APPLY_PROFILE_AWAIT = nil;

	for settingName, value in pairs(settings) do
		local func = CUFProfileActionTable[settingName];
		if ( func ) then
			func(value);
		end
	end

	--Refresh all frames to make sure the changes stick.
	CompactRaidFrameContainer_ApplyToFrames(CompactRaidFrameContainer, "normal", DefaultCompactUnitFrameSetup);
	CompactRaidFrameContainer_ApplyToFrames(CompactRaidFrameContainer, "normal", CompactUnitFrame_UpdateAll);
	CompactRaidFrameContainer_ApplyToFrames(CompactRaidFrameContainer, "mini", DefaultCompactMiniFrameSetup);
	CompactRaidFrameContainer_ApplyToFrames(CompactRaidFrameContainer, "mini", CompactUnitFrame_UpdateAll);
	--CompactRaidFrameContainer_ApplyToFrames(CompactRaidFrameContainer, "group", CompactRaidGroup_UpdateLayout);	--UpdateBorder calls UpdateLayout.

	--Update the borders on the group frames.
	CompactRaidFrameContainer_ApplyToFrames(CompactRaidFrameContainer, "group", CompactRaidGroup_UpdateBorder);

	--Update the position of the container.
	CompactRaidFrameManager_ResizeFrame_LoadPosition(CompactRaidFrameManager);

	--Update the container in case sizes and such changed.
	CompactRaidFrameContainer_TryUpdate(CompactRaidFrameContainer);

	--The raid manager's Groups dropdown shows this profile's layout.
	if ( CompactRaidFrameManager_UpdateLayoutSelectors ) then
		CompactRaidFrameManager_UpdateLayoutSelectors();
	end
end

local function CompactUnitFrameProfiles_GenerateRaidManagerSetting(optionName)
	return function(value)
		CompactRaidFrameManager_SetSetting(optionName, value);
	end
end

local function CompactUnitFrameProfiles_GenerateOptionSetter(optionName, optionTarget)
	return function(value)
		if ( optionTarget == "normal" or optionTarget == "all" ) then
			DefaultCompactUnitFrameOptions[optionName] = value;
		end
		if ( optionTarget == "mini" or optionTarget == "all" ) then
			DefaultCompactMiniFrameOptions[optionName] = value;
		end
	end
end

local function CompactUnitFrameProfiles_GenerateSetUpOptionSetter(optionName, optionTarget)
	return function(value)
		if ( optionTarget == "normal" or optionTarget == "all" ) then
			DefaultCompactUnitFrameSetupOptions[optionName] = value;
		end
		if ( optionTarget == "mini" or optionTarget == "all" ) then
			DefaultCompactMiniFrameSetUpOptions[optionName] = value;
		end
	end
end

CUFProfileActionTable = {
	--Settings
	keepGroupsTogether = CompactUnitFrameProfiles_GenerateRaidManagerSetting("KeepGroupsTogether"),
	sortBy = CompactUnitFrameProfiles_GenerateRaidManagerSetting("SortMode"),
	displayPets = CompactUnitFrameProfiles_GenerateRaidManagerSetting("DisplayPets"),
	displayMainTankAndAssist = CompactUnitFrameProfiles_GenerateRaidManagerSetting("DisplayMainTankAndAssist"),
	displayPowerBar = CompactUnitFrameProfiles_GenerateSetUpOptionSetter("displayPowerBar", "normal"),
	displayOnlyHealerPowerBars = CompactUnitFrameProfiles_GenerateSetUpOptionSetter("displayOnlyHealerPowerBars", "normal"),
	displayHealPrediction = CompactUnitFrameProfiles_GenerateOptionSetter("displayHealPrediction", "all"),
	displayAggroHighlight = CompactUnitFrameProfiles_GenerateOptionSetter("displayAggroHighlight", "all"),
	displayNonBossDebuffs = CompactUnitFrameProfiles_GenerateOptionSetter("displayNonBossDebuffs", "normal"),
	displayOnlyDispellableDebuffs = CompactUnitFrameProfiles_GenerateOptionSetter("displayOnlyDispellableDebuffs", "normal"),
	useClassColors = CompactUnitFrameProfiles_GenerateOptionSetter("useClassColors", "normal"),
	horizontalGroups = CompactUnitFrameProfiles_GenerateRaidManagerSetting("HorizontalGroups");
	healthText = CompactUnitFrameProfiles_GenerateOptionSetter("healthText", "normal"),
	frameWidth = CompactUnitFrameProfiles_GenerateSetUpOptionSetter("width", "all");
	frameHeight = 	function(value)
								DefaultCompactUnitFrameSetupOptions.height = value;
								DefaultCompactMiniFrameSetUpOptions.height = value / 2;
							end,
	displayBorder = function(value)
								RAID_BORDERS_SHOWN = value;
								DefaultCompactUnitFrameSetupOptions.displayBorder = value;
								DefaultCompactMiniFrameSetUpOptions.displayBorder = value;
								CompactRaidFrameManager_SetSetting("ShowBorders", value);
							end,

	--State
	locked = CompactUnitFrameProfiles_GenerateRaidManagerSetting("Locked"),
	shown = CompactUnitFrameProfiles_GenerateRaidManagerSetting("IsShown"),
}
