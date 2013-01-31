/* [TF2] Critplay manager 
 * Copyright (C) 2013, Eric G. Wolfe
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#pragma semicolon 1
#include <sourcemod>
#include <smlib>

#define PLUGIN_AUTHOR "atomic-penguin"
#define PLUGIN_VERSION "0.1.0"
#define PLUGIN_NAME "Critplay Manager"
#define PLUGIN_DESCRIPTION "Manages critical hits, and weapon/damage spread based on player count."
#define PLUGIN_URL "https://github.com/atomic-penguin/sm-critplay"

// Configurable cvars
new Handle:cvar_Enabled;
new Handle:cvar_QuickplayThreshold;
new Handle:cvar_NocritsThreshold;
new Handle:cvar_CountBots;
new Handle:cvar_LogActivity;

// Internal global vars
new bool:bEnabled;
new bool:bQuickplayMap = true;
new bool:bCountBots;
new bool:bLogActivity;
new iQuickplayThreshold;
new iNocritsThreshold;

static const String:quickplay_maps[][] = {
    "cp_dustbowl",
    "cp_egypt_final",
    "cp_gorge",
    "cp_gravelpit",
    "cp_junction_final",
    "cp_mountainlab",
    "cp_steel",
    "cp_gullywash_final1",
    "cp_5gorge",
    "cp_badlands",
    "cp_coldfront",
    "cp_fastlane",
    "cp_freight_final1",
    "cp_granary",
    "cp_well",
    "cp_yukon_final",
    "cp_foundry",
    "ctf_2fort",
    "ctf_doublecross",
    "ctf_sawmill",
    "ctf_turbine",
    "ctf_well",
    "sd_doomsday",
    "koth_badlands",
    "koth_harvest_final",
    "koth_lakeside_final",
    "koth_nucleus",
    "koth_sawmill",
    "koth_viaduct",
    "koth_king",
    "plr_hightower",
    "plr_pipeline",
    "plr_nightfall_final",
    "pl_badwater",
    "pl_frontier_final",
    "pl_goldrush",
    "pl_hoodoo_final",
    "pl_thundermountain",
    "pl_upward",
    "pl_barnblitz"
};

public Plugin:myinfo = {
    name = PLUGIN_NAME, 
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
}

public OnPluginStart() {
	
    // Initialize plugin cvars
    cvar_Enabled = CreateConVar("cp_enabled", "1", "Disable/enable critplay plugin. Default 0/Disabled.", _, true, 0.0, true, 1.0);
    cvar_QuickplayThreshold = CreateConVar("cp_quickplay_threshold", "8", "Lower player threshold to turn on crits/random spread. Default 8.", _, true, 0.0, true, 12.0);
    cvar_NocritsThreshold = CreateConVar("cp_nocrits_threshold", "18", "High player threshold to turn on crits/random spread. Default 18.", _, true, 12.0, true, 24.0);
    cvar_CountBots = CreateConVar("cp_count_bots", "0", "Whether or not to count bots in threshold count. Default 0/false.", _, true, 0.0, true, 1.0);
    cvar_LogActivity = CreateConVar("cp_log_activity", "1", "Whether or not to log activity in the server chat area. Default 1/True.", _, true, 0.0, true, 1.0);
	
    // Auto-create the config file
    //AutoExecConfig(true, "plugin.critplay");

    // Initialize global vars
    bEnabled = GetConVarBool(cvar_Enabled);
    bCountBots = GetConVarBool(cvar_CountBots);
    bLogActivity = GetConVarBool(cvar_LogActivity);
    iQuickplayThreshold = GetConVarInt(cvar_QuickplayThreshold);
    iNocritsThreshold = GetConVarInt(cvar_NocritsThreshold);

    if (bEnabled && bLogActivity) {
        // Remove NOTIFY flags
        Convar_RemoveFlags(FindConVar("tf_damage_disablespread"), FCVAR_NOTIFY);
        Convar_RemoveFlags(FindConVar("tf_weapon_criticals"), FCVAR_NOTIFY);
        Convar_RemoveFlags(FindConVar("tf_use_fixed_weaponspreads"), FCVAR_NOTIFY);
        Convar_RemoveFlags(FindConVar("tf_ctf_bonus_time"), FCVAR_NOTIFY);
    }
}

public OnConfigsExecuted() {
    // Initialize global vars
    bEnabled = GetConVarBool(cvar_Enabled);
    bCountBots = GetConVarBool(cvar_CountBots);
    bLogActivity = GetConVarBool(cvar_LogActivity);
    iQuickplayThreshold = GetConVarInt(cvar_QuickplayThreshold);
    iNocritsThreshold = GetConVarInt(cvar_NocritsThreshold);
}

public OnMapStart() {
    // Check if map is quickplay
    bQuickplayMap=IsQuickplayMap();
    SetCritPlay(bQuickplayMap);
    if (bLogActivity) {
        PrintToChatAll("\x04[%s]\x01 turned \x03on\x01 random/bonus crits and weapon/damage spread due to quickplay map.", PLUGIN_NAME);
    } else {
        PrintToChatAll("\x04[%s]\x01 turned \x03off\x01 random/bonus crits and weapon/damage spread due to non-quickplay map.", PLUGIN_NAME);
    }
}

public OnMapEnd() {
    bQuickplayMap = true;
}

public OnPluginEnd() {
    if (bEnabled && bLogActivity) {
        // Restore NOTIFY flags
        Convar_AddFlags(FindConVar("tf_damage_disablespread"), FCVAR_NOTIFY);
        Convar_AddFlags(FindConVar("tf_weapon_criticals"), FCVAR_NOTIFY);
        Convar_AddFlags(FindConVar("tf_use_fixed_weaponspreads"), FCVAR_NOTIFY);
        Convar_AddFlags(FindConVar("tf_ctf_bonus_time"), FCVAR_NOTIFY);
    }
}

public OnClientConnected(client) {
    CheckPlayerThreshold();
}

public OnClientDisconnect(client) {
    CheckPlayerThreshold();
}


/**
 * Set the Critical hits, damage spread, weapon spread, and CTF crits on/off
 *
 * @param1    True: turns on vanilla settings
 *            False: turns off random crits, uses fixed spread
 */
public SetCritPlay(bool:bCritPlayState) {
    if (!bEnabled) return;
    if (bCritPlayState) {
        SetConVarInt(FindConVar("tf_damage_disablespread"), 0);
        SetConVarInt(FindConVar("tf_weapon_criticals"), 1);
        SetConVarInt(FindConVar("tf_use_fixed_weaponspreads"), 0);
        SetConVarInt(FindConVar("tf_ctf_bonus_time"), 10);
    } else {
        SetConVarInt(FindConVar("tf_damage_disablespread"), 1);
        SetConVarInt(FindConVar("tf_weapon_criticals"), 0);
        SetConVarInt(FindConVar("tf_use_fixed_weaponspreads"), 1);
        SetConVarInt(FindConVar("tf_ctf_bonus_time"), 0);
    }
}

stock CheckPlayerThreshold() {
    if (!bEnabled) return;
    new iClientCount=Client_GetCount(false, bCountBots);
    if ((iClientCount <= iQuickplayThreshold) && bQuickplayMap) {
        SetCritPlay(true);
        if (bLogActivity) PrintToChatAll("\x04[%s]\x01 turned \x03on\x01 random/bonus crits, and weapon/damage spread due to player threshold.", PLUGIN_NAME);
    } else if (iClientCount >= iNocritsThreshold) {
        SetCritPlay(false);
        if (bLogActivity) PrintToChatAll("\x04[%s]\x01 turned \x03off\x01 random/bonus crits, and weapon/damage spread due to player threshold.", PLUGIN_NAME);
    }
}

stock bool:IsQuickplayMap() {
    decl String:curMap[64];
    GetCurrentMap(curMap, sizeof(curMap));
    if (Array_FindString(quickplay_maps, sizeof(quickplay_maps), curMap)==-1) {
        return false;
    } else {
        return true;
    }
}
