#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <sdktools_functions>
#include <multicolors>
#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "2.0"
#define DMG_FALL   (1 << 5)


bool g_bFallDamageExempt[MAXPLAYERS+1];
bool g_bPlayerInRocket[MAXPLAYERS+1];
Handle g_hRocketExplodeTimer[MAXPLAYERS+1];
any g_ExplosionEffect;

ConVar g_bRocketMeEnabled;
ConVar g_sRocketLaunchSound;
ConVar g_sRocketExplodeSound;
ConVar g_sRocketSurviveSound;
ConVar g_fRocketExplodeTime;
ConVar g_fRocketExemptTime;
ConVar g_iRocketExplodeProbability;
ConVar g_fRocketGravity;

public Plugin myinfo =
{
    name = "[CS:GO] Evil Admin - Rocket",
    author = "<eVa>Dog, Rewrited by faketuna",
    description = "Make a rocket with a player",
    version = PLUGIN_VERSION,
    url = "http://www.theville.org"
}

public void OnPluginStart() {
    CreateConVar("sm_evilrocket_version", PLUGIN_VERSION, " Evil Rocket Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
    g_bRocketMeEnabled =                CreateConVar("sm_rocketme_enabled", "0", " Allow players to suicide as a rocket", FCVAR_NONE, true, 0.0, true, 1.0);
    g_sRocketLaunchSound =              CreateConVar("sm_rocket_launch_sound", "survival/breach_warning_beep_01.wav", "The path to sound file. DO NOT BE BLANK");
    g_sRocketExplodeSound =             CreateConVar("sm_rocket_explode_sound", "weapons/c4/c4_explode1.wav", "The path to sound file. DO NOT BE BLANK");
    g_sRocketSurviveSound =             CreateConVar("sm_rocket_survive_sound", "weapons/c4/c4_explode1.wav", "The path to sound file. DO NOT BE BLANK");
    g_fRocketExplodeTime =              CreateConVar("sm_rocket_explode_time", "3.0", "How long to detonate in seconds after launch", FCVAR_NONE, true, 0.0, true, 30.0);
    g_fRocketExemptTime =               CreateConVar("sm_rocket_exempt_time", "4.0", "How long to player exempted the fall damage after survived", FCVAR_NONE, true, 4.0, false, 0.0);
    g_iRocketExplodeProbability =       CreateConVar("sm_rocket_explode_probability", "50", "The probability of detonate chance", FCVAR_NONE, true, 0.0, true, 100.0);
    g_fRocketGravity =                  CreateConVar("sm_rocket_gravity", "0.1", "The gravity of player who lanched rocket", FCVAR_NONE, true, 0.01, true, 0.5);

    RegAdminCmd("sm_evilrocket", CommandEvilRocket, ADMFLAG_SLAY, "sm_evilrocket <#userid|name>");
    RegConsoleCmd("sm_rocketme", CommandRocketMe, " a fun way to suicide");
    RegConsoleCmd("sm_rocket", CommandRocketMe, " a fun way to suicide");
    HookEvent("round_prestart", OnRoundStart);
    LoadTranslations("mg_rocket.phrases");
    AutoExecConfig(true, "mg_rocket");
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (damagetype & DMG_FALL)
    {
        if (g_bFallDamageExempt[victim])
        {
            return Plugin_Handled;
        }
    }
    return Plugin_Continue;
}

public Action falldamageExemptTimer(Handle timer, int client)
{
    g_bFallDamageExempt[client] = false;
    return Plugin_Handled;
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast) {
    for (int i = 1; i <= MAXPLAYERS; i++) {
        g_bPlayerInRocket[i] = false;
        g_bFallDamageExempt[i] = false;
        if (g_hRocketExplodeTimer[i] != INVALID_HANDLE) {
            delete g_hRocketExplodeTimer[i];
        }
    }
}

public void OnMapStart() {
    g_ExplosionEffect = PrecacheModel("sprites/sprite_fire01.vmt");

    char buff1[256];
    char buff2[256];
    char buff3[256];
    GetConVarString(g_sRocketLaunchSound, buff1, sizeof(buff1));
    GetConVarString(g_sRocketExplodeSound, buff2, sizeof(buff2));
    GetConVarString(g_sRocketSurviveSound, buff3, sizeof(buff3));

    PrecacheSound(buff1, true);
    PrecacheSound(buff2, true);
    PrecacheSound(buff3, true);
}

public Action CommandRocketMe(int client, int args) {
    if (!GetConVarBool(g_bRocketMeEnabled)) {
        CReplyToCommand(client, "%t%t", "rocket_prefix", "rocket_disabled");
        return Plugin_Handled;
    }
    if (!IsClientInGame(client)) {
        return Plugin_Handled;
    }
    if (!IsPlayerAlive(client)) {
        CReplyToCommand(client, "%t%t", "rocket_prefix", "rocket_died");
        return Plugin_Handled;
    }
    if (g_bPlayerInRocket[client]) {
        CReplyToCommand(client, "%t%t", "rocket_prefix", "rocket_flying");
        return Plugin_Handled;
    }

    PerformEvilRocket(-1, client);
    return Plugin_Handled;
}

public Action CommandEvilRocket(int client, int args) {
    char target[65];
    char targetName[MAX_TARGET_LENGTH];
    int targetList[MAXPLAYERS];
    int targetCount;
    bool tn_is_ml;

    if (args < 1) {
        ReplyToCommand(client, "[SM] Usage: sm_evilrocket <#userid|name>");
        return Plugin_Handled;
    }

    GetCmdArg(1, target, sizeof(target));

    targetCount = ProcessTargetString(
        target,
        client,
        targetList,
        MAXPLAYERS,
        0,
        targetName,
        sizeof(targetName),
        tn_is_ml);
    if (targetCount <= 0) {
        ReplyToTargetError(client, targetCount);
        return Plugin_Handled;
    }

    for (int i = 0; i < targetCount; i++) {
        if (IsClientInGame(targetList[i]) && IsPlayerAlive(targetList[i])) {
            PerformEvilRocket(client, targetList[i]);
        }
    }
    return Plugin_Handled;
}

void PerformEvilRocket(int client, int target) {
    if (!g_bPlayerInRocket[target]) {
        if (client != -1) {
            LogAction(client, target, "\"%L\" sent \"%L\" into space", client, target);
            char name[32];
            GetClientName(target, name, sizeof(name));
            CShowActivity(client, "%t", "evil_rocket_launch", name);
        }

        AttachFlame(target);
        CreateTimer(0.0, LaunchRocket, target);
        g_hRocketExplodeTimer[target] = CreateTimer(GetConVarFloat(g_fRocketExplodeTime), DetonateRocket, target);
        g_bPlayerInRocket[target] = true;
    }
}

public Action LaunchRocket(Handle timer, int client) {
    if (!IsClientInGame(client)) {
        return Plugin_Handled;
    }

    float vVel[3];

    vVel[0] = 0.0;
    vVel[1] = 0.0;
    vVel[2] = 800.0;

    char buff[256];
    GetConVarString(g_sRocketLaunchSound, buff, sizeof(buff));
    EmitSoundToAll(buff, client, _, _, _, 1.0);

    char name[32];
    GetClientName(client, name, sizeof(name));
    CPrintToChatAll("%t%t", "rocket_prefix", "rocket_launch", name);

    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vVel);
    SetEntityGravity(client, GetConVarFloat(g_fRocketGravity));
    return Plugin_Handled;
}

public Action DetonateRocket(Handle timer, int client) {
    if (!IsClientInGame(client)) {
        return Plugin_Handled;
    }

    float vPlayer[3];
    GetClientAbsOrigin(client, vPlayer);

    if (!canDetonate()) {
        char buff[256];
        GetConVarString(g_sRocketSurviveSound, buff, sizeof(buff));
        EmitSoundToAll(buff, client, _, _, _, 1.0);

        char name[32];
        GetClientName(client, name, sizeof(name));
        CPrintToChatAll("%t%t", "rocket_prefix", "rocket_survived", name);

        SetEntityGravity(client, 1.0);
        g_bPlayerInRocket[client]   = false;
        g_bFallDamageExempt[client] = true;
        CreateTimer(GetConVarFloat(g_fRocketExemptTime), falldamageExemptTimer, client);
        return Plugin_Handled;
    }

    TE_SetupExplosion(vPlayer, g_ExplosionEffect, 10.0, 1, 0, 600, 5000);
    TE_SendToAll();
    g_bPlayerInRocket[client] = false;
    
    // TODO Rewrite this to damage suicide kill not a suicide
    ForcePlayerSuicide(client);
    char buff[256];
    GetConVarString(g_sRocketExplodeSound, buff, sizeof(buff));
    EmitSoundToAll(buff, client, _, _, _, 1.0);

    char name[32];
    GetClientName(client, name, sizeof(name));
    CPrintToChatAll("%t%t", "rocket_prefix", "rocket_explode", name);

    SetEntityGravity(client, 1.0);
    return Plugin_Handled;
}

void AttachFlame(any entity) {
    char flameName[128];
    Format(flameName, sizeof(flameName), "RocketFlame%i", entity);

    char targetName[128];

    any flame = CreateEntityByName("env_steam");
    if (!IsValidEdict(flame)) {
        return;
    }

    float pos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
    pos[2] += 30;

    float angles[3];
    angles[0] = 90.0;
    angles[1] = 0.0;
    angles[2] = 0.0;


    Format(targetName, sizeof(targetName), "target%i", entity);
    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(flame,"targetname", flameName);
    DispatchKeyValue(flame, "parentname", targetName);
    DispatchKeyValue(flame,"SpawnFlags", "1");
    DispatchKeyValue(flame,"Type", "0");
    DispatchKeyValue(flame,"InitialState", "1");
    DispatchKeyValue(flame,"Spreadspeed", "10");
    DispatchKeyValue(flame,"Speed", "800");
    DispatchKeyValue(flame,"Startsize", "10");
    DispatchKeyValue(flame,"EndSize", "250");
    DispatchKeyValue(flame,"Rate", "15");
    DispatchKeyValue(flame,"JetLength", "400");
    DispatchKeyValue(flame,"RenderColor", "180 71 8");
    DispatchKeyValue(flame,"RenderAmt", "180");
    DispatchSpawn(flame);
    TeleportEntity(flame, pos, angles, NULL_VECTOR);
    SetVariantString(targetName);
    AcceptEntityInput(flame, "SetParent", flame, flame, 0);

    CreateTimer(GetConVarFloat(g_fRocketExplodeTime), DeleteFlame, flame);
}

public Action DeleteFlame(Handle timer, any entity) {
    if (!IsValidEntity(entity)) {
        return Plugin_Handled;
    }

    char className[256];
    GetEdictClassname(entity, className, sizeof(className));
    if (StrEqual(className, "env_steam", false)) {
        RemoveEdict(entity);
    }
    return Plugin_Handled;
}

bool canDetonate() {
    if (GetConVarInt(g_iRocketExplodeProbability) >= GetRandomInt(0, 100)) {
        return true;
    }
    return false;
}