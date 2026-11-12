--[[
    Locale strings. The addon's XML/Lua look its strings up as globals (the
    Blizzard retail names), so they are written to _G - but ONLY where the client
    does not already define that global. Overwriting one of Blizzard's own
    globals (even with the same text) taints it for the secure UI, and the
    client's version is already correctly localized anyway.

    enUS.lua loads first and provides the defaults; the other locale files
    (which return early unless the client matches) override the strings this
    addon created.
]]
local owned = {}

function CRF_SetLocaleString(key, value)
	if ( value ~= nil and (_G[key] == nil or owned[key]) ) then
		_G[key] = value
		owned[key] = true
	end
end

local L = CRF_SetLocaleString

-- Client Localization (reuse strings the client already translates)
L("BUFF_STACKS_OVERFLOW", CANNOT_COOPERATE_LABEL or "*")
L("DEFAULT_CUF_PROFILE_NAME", PRIMARY or "Primary")
L("CREATE_COMPACT_UNIT_FRAME_PROFILE", CREATE or "Create")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYNONBOSSDEBUFFS", SHOW_DEBUFFS or "Show Debuffs")
L("COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_NONE", NONE or "None")
L("COMPACT_UNIT_FRAME_PROFILE_SORTBY_GROUP", GROUP or "Group")
L("COMPACT_UNIT_FRAME_PROFILE_SORTBY_ROLE", ROLE or "Role")
L("SHORT", AUCTION_TIME_LEFT1 or "Short")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATEPVP", CALENDAR_TYPE_PVP or "PvP")
L("LOST_HEALTH", "-%d")
L("COMPACT_UNIT_FRAME_ERRCOMBAT", "|cffff2020"..((...) or "CompactRaidFrame")..": "..(ERR_NOT_IN_COMBAT or "You can't do that while in combat")..".")
-- Used by the raid manager's Lock/Unlock and Show/Hide buttons; normally
-- provided by the client.
L("LOCK", "Lock")
L("HIDE", "Hide")

-- Default (enUS)
L("AUTO_ACTIVATE_DISABLED_IN_PARTY", "Raid-Style Party Frames must be enabled to auto-activate with this number of players.")
L("USE_RAID_STYLE_PARTY_FRAMES", "Use Raid-Style Party Frames")
L("CREATE_NEW_COMPACT_UNIT_FRAME_PROFILE", "Create a New Profile")
L("AUTO_ACTIVATE_ON", "Auto-Activate On:")
L("AUTO_ACTIVATE_PROFILE_NO_ENEMYTYPE", "Profile will never auto-activate. Either PvP or PvE must be selected.")
L("AUTO_ACTIVATE_PROFILE_NO_SIZE", "Profile will never auto-activate. No group size is selected.")
L("RESET_POSITION", "Reset Position")
L("DONT_SAVE", "Don't Save")
L("NEW_COMPACT_UNIT_FRAME_PROFILE", "New Profile")
L("USE_EXISTING_PROFILE", "Use as a starting point:")
L("GROUP_NUMBER", "Group %d")
L("TALL", "Tall")
L("NARROW", "Narrow")
L("WIDE", "Wide")
L("UNLOCK", "Unlock")
L("SHOW", "Show")
L("ALL_ASSIST_LABEL_LONG", "Make Everyone Assistant")
L("ALL_ASSIST_DESCRIPTION", "If checked, all raid members will have the permissions of a Raid Assistant.")
L("ALL_ASSIST_NOT_LEADER_ERROR", "Only the Raid Leader may change this option.")
L("RAID_MEMBERS", "Raid Members")
L("PARTY_MEMBERS", "Party Members")
L("ROLE_POLL", "Role Check")
L("CONFIRM_COMPACT_UNIT_FRAME_PROFILE_UNSAVED_CHANGES", "|cffffffff%s|r contains unsaved changes that will be lost when performing this action. Would you like to save before proceeding?")
L("CONFIRM_COMPACT_UNIT_FRAME_PROFILE_DELETION", "Are you sure you want to permanently delete |cffffffff%s|r?")
L("OPTION_TOOLTIP_USE_RAID_STYLE_PARTY_FRAMES", "Uses Party Frames in the same style as the Raid Frames. These frames obey your Raid Frame options.")
L("COMPACT_UNIT_FRAME_PROFILES_LABEL", "Raid Profiles")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATE2PLAYERS", "2 Player Group")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATE3PLAYERS", "3 Player Group")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATE5PLAYERS", "5 Player Group")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATE10PLAYERS", "10 Player Group")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATE15PLAYERS", "15 Player Group")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATE25PLAYERS", "25 Player Group")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATE40PLAYERS", "40 Player Group")
L("COMPACT_UNIT_FRAME_PROFILE_AUTOACTIVATEPVE", "PvE")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYAGGROHIGHLIGHT", "Display Aggro Highlight")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYBORDER", "Display Border")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYMAINTANKANDASSIST", "Display Main Tank and Assist")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYONLYDISPELLABLEDEBUFFS", "Display Only Dispellable Debuffs")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYPETS", "Display Pets")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYPOWERBAR", "Display Power Bars")
L("COMPACT_UNIT_FRAME_PROFILE_FRAMEHEIGHT", "Frame Height")
L("COMPACT_UNIT_FRAME_PROFILE_FRAMEWIDTH", "Frame Width")
L("COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT", "Display Health Text")
L("COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_HEALTH", "Health Remaining")
L("COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_LOSTHEALTH", "Health Lost")
L("COMPACT_UNIT_FRAME_PROFILE_HEALTHTEXT_PERC", "Health Percentage")
L("COMPACT_UNIT_FRAME_PROFILE_HORIZONTALGROUPS", "Horizontal Groups")
L("COMPACT_UNIT_FRAME_PROFILE_KEEPGROUPSTOGETHER", "Keep Groups Together")
L("COMPACT_UNIT_FRAME_PROFILE_SORTBY", "Sort By:")
L("COMPACT_UNIT_FRAME_PROFILE_SORTBY_ALPHABETICAL", "Alphabetical")
L("COMPACT_UNIT_FRAME_PROFILE_USECLASSCOLORS", "Display Class Colors")

-- Options panel tabs and the "Always show" option (this addon's own strings)
L("CRF_OPTIONS_TAB_GENERAL", "General")
L("CRF_OPTIONS_TAB_DISPLAY", "Display")
L("CRF_OPTIONS_TAB_AUTOACTIVATE", "Auto-Activate")
L("CRF_ALWAYS_SHOW_SOLO", "Always show (even when solo)")
L("CRF_ALWAYS_SHOW_SOLO_TOOLTIP", "Show the raid frames and the raid manager even when you are not in a group.")
L("CRF_MANAGER_TAB_MOUSEOVER", "Show raid manager tab only on mouseover")
L("CRF_MANAGER_TAB_MOUSEOVER_TOOLTIP", "While the raid manager is collapsed, its tab at the left edge of the screen stays hidden until you move the mouse over it.")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYHEALPREDICTION", "Display Incoming Heals")
L("COMPACT_UNIT_FRAME_PROFILE_DISPLAYONLYHEALERPOWERBARS", "Display Only Healer Power Bars")
L("CRF_REQUIRES_POWER_BARS", "Requires \"Display Power Bars\".")
L("CRF_HIDE_PLAYER_FRAME", "Hide player frame when raid frames are shown")
L("CRF_HIDE_PLAYER_FRAME_TOOLTIP", "Hides your default player frame while the raid frames are on screen, since your own raid frame shows the same. It stays visible in vehicles, and totem timers and Death Knight runes stay on screen. Your pet frame is part of the player frame and hides with it: tick Display Pets to see your pet in the raid frames.")
L("CRF_OPTIONS_TAB_LAYOUT", "Layout")
L("CRF_GROUPS", "Groups")
L("CRF_GROUPS_COMBINE_VERTICAL", "Combine Groups (Vertical)")
L("CRF_GROUPS_COMBINE_HORIZONTAL", "Combine Groups (Horizontal)")
L("CRF_GROUPS_SEPARATE_VERTICAL", "Separate Groups (Vertical)")
L("CRF_GROUPS_SEPARATE_HORIZONTAL", "Separate Groups (Horizontal)")
L("CRF_GROUPS_SHORT_COMBINE_VERTICAL", "Combine (Vertical)")
L("CRF_GROUPS_SHORT_COMBINE_HORIZONTAL", "Combine (Horizontal)")
L("CRF_GROUPS_SHORT_SEPARATE_VERTICAL", "Separate (Vertical)")
L("CRF_GROUPS_SHORT_SEPARATE_HORIZONTAL", "Separate (Horizontal)")
L("CRF_RAID_SIZE_PREVIEW", "Raid Size Preview")
L("CRF_PREVIEW_OFF", "Off")
L("CRF_PREVIEW_PLAYERS", "%d Players")
L("CRF_PREVIEW_FORMAT", "Preview: %s")
