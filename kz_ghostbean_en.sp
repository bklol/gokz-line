#pragma semicolon 1
#pragma newdecls required

#define RP_MAGIC_NUMBER			0x676F6B7A
#define RP_FORMAT_VERSION		0x02
#define RP_FL_ONGROUND			(1 << 18)
#define RP_DIRECTORY_RUNS		"data/gokz-replays/_runs"
#define Load_DataTick			1000
#define BOX_SIZE				14.0

#include <sdktools>
#include <clientprefs>
#include <ripext>
#include <gokz>
#include <gokz/replays>
#include <kdtree>

public Plugin myinfo =
{
	name = "neko kz line",
	author = "neko AKA bklol" ,
	description = "give map route line and func to guess replay Nearest pos to client,notice this plugins not have api to download gokz replay you should write your own api" ,
	version = "0.1"
}

//HTTPRequest NEKO_API;
ArrayList playbackTickData;

enum struct PlayerTickData
{
	int replay_start_tick;
	int replay_end_tick;
	int replay_post_tick;
	int replay_tickcount;
	bool replay_auto_path;
	bool replay_line_enable;
}

bool g_bloadreplay = false;
int sprite;
Handle g_cookieline;
char finalpath[128];
PlayerTickData iPlayerTickData[MAXPLAYERS + 1];
static float itickrate;
public void OnPluginStart()
{
	itickrate = 1/GetTickInterval();
	g_cookieline = RegClientCookie("line_choice", "", CookieAccess_Private);

	RegConsoleCmd("sm_line", kz_line_menu);
	RegConsoleCmd("sm_lpp", kz_line_pp);
	RegConsoleCmd("sm_ldd", kz_line_dd);
	RegServerCmd("sm_redlwr", kz_redlwr);
	for( int i = 1; i <= MaxClients; i++ ) 
	{
		if( IsClientInGame(i) && !IsFakeClient(i) ) 
		{
			if( AreClientCookiesCached(i) ) 
			{
				OnClientCookiesCached(i);
			}
		}
	}
}

public Action kz_redlwr(int args)
{
	char replay_path[256];
	char mapName[128];
	GetCurrentMapDisplayName(mapName, sizeof(mapName));
	BuildPath(Path_SM, replay_path, sizeof(replay_path), "%s/%s/wr.replay", RP_DIRECTORY_RUNS, mapName);
	PrintToServer("Load replay %s", replay_path);
	if(FileExists(replay_path))
		DeleteFile(replay_path);
	SeekReplay();	
	return Plugin_Continue;
}

public int Native_GetTimeDiff(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	char buffer[32];
	float client_time = GetNativeCell(2);
	if(client_time <= 0.0078125)
	{
		SetNativeString(3, "+0:00:00", 32, false);
	}
	else
	{
		int tick = GetClosestReplayFrame(client);
		if(tick == -1)
			SetNativeString(3, "", 32, false);
		float diff_time = (tick + 1) * 0.0078125;//1 tick before
		float real_time = client_time - diff_time + RoundToZero(2 * itickrate) * 0.0078125;
		if(real_time < 0)
			Format(buffer, sizeof(buffer), "-%s", GOKZ_FormatTime(real_time * -1));
		else
			Format(buffer, sizeof(buffer), "+%s", GOKZ_FormatTime(real_time));
		SetNativeString(3, buffer, 32, false);
	}
	return 0;
}

public int Native_HasLoadReplayFile(Handle plugin, int numParams)
{
	return g_bloadreplay;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("KZ_GetTimeDiff",			Native_GetTimeDiff);
	CreateNative("KZ_HasLoadReplayFile",	Native_HasLoadReplayFile);	
}

public void OnMapStart()
{
	SeekReplay();
	
}

void SeekReplay()
{
	LoadedReplays( false );
	/*
	char wrpath[256], url[256];
	char mapName[128];
	GetCurrentMapDisplayName(mapName, sizeof(mapName));
	BuildPath(Path_SM, wrpath, sizeof(wrpath), "%s/%s/wr.replay", RP_DIRECTORY_RUNS, mapName);
	if(FileExists(wrpath))
	{
		LoadedReplays( true );
	}
	else
	{
		Format(url, sizeof(url), "map_name=%s", mapName);//you should wrote your own api
		NEKO_API = new HTTPRequest(url);
		NEKO_API.DownloadFile(wrpath, OnDownloaded);
		PrintToServer("DownloadFile replay %s", mapName);
	}
	*/
}

/*
void OnDownloaded(HTTPStatus status, any value)
{
	if (status == HTTPStatus_OK)
	{
		PrintToServer("File replay Download success");
		LoadedReplays( true );
	}
	else
	{
		LoadedReplays( false );
		PrintToServer("File replay Download failed");
	}
}
*/

public void OnClientCookiesCached(int client)
{
	if(!IsValidClient(client))
		return;
	char value[16];
	
	GetClientCookie(client, g_cookieline, value, sizeof(value));
	if(StringToInt(value) != 1)
	{
		iPlayerTickData[client].replay_line_enable = true;
	}
	else
		iPlayerTickData[client].replay_line_enable = false;
	
	iPlayerTickData[client].replay_start_tick = 1; // we start from 1 tick
	iPlayerTickData[client].replay_end_tick = Load_DataTick + 1;
	iPlayerTickData[client].replay_post_tick = 1;
	iPlayerTickData[client].replay_auto_path = true;
}

public Action kz_line_pp(int client, int args)
{
	if(playbackTickData.Length - 1 < Load_DataTick)
	{
		PrintToChat(client, "[KZ line] The current replay length does not need to advance or retreat");
		return Plugin_Continue;
	}
	if((iPlayerTickData[client].replay_end_tick + Load_DataTick >= playbackTickData.Length - 1))
	{
		if(iPlayerTickData[client].replay_start_tick + Load_DataTick < playbackTickData.Length - 1)
		{
			iPlayerTickData[client].replay_start_tick += Load_DataTick;
			iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
			iPlayerTickData[client].replay_end_tick = playbackTickData.Length - 1;
		}
	}
	else
	{
		iPlayerTickData[client].replay_start_tick += Load_DataTick;
		iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
		iPlayerTickData[client].replay_end_tick += Load_DataTick;
	}
	return Plugin_Continue;
}

public Action kz_line_dd(int client, int args)
{
	if(playbackTickData.Length - 1 < Load_DataTick)
	{
		PrintToChat(client, "[KZ line] The current replay length does not need to advance or retreat");
		return Plugin_Continue;
	}
	if(iPlayerTickData[client].replay_start_tick - Load_DataTick <= 1)
	{
		iPlayerTickData[client].replay_start_tick = 1;
		iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
		iPlayerTickData[client].replay_end_tick = iPlayerTickData[client].replay_start_tick + Load_DataTick;
	}
	else
	{
		iPlayerTickData[client].replay_start_tick -= Load_DataTick;
		iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
		iPlayerTickData[client].replay_end_tick -= Load_DataTick;
	}
	return Plugin_Continue;
}

public Action kz_line_menu(int client, int args)
{
	Menu menu = new Menu(m_kzlines);
	menu.SetTitle(" - KZ | Path guidance - \n ");
	char buffer[64];
	Format(buffer, sizeof(buffer), "Path guidance %s", iPlayerTickData[client].replay_line_enable ? "ON":"OFF");
	menu.AddItem("1", buffer, g_bloadreplay ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(buffer, sizeof(buffer), "Auto update %s", iPlayerTickData[client].replay_auto_path ? "ON":"OFF");
	menu.AddItem("1", buffer, (g_bloadreplay && iPlayerTickData[client].replay_line_enable) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("4", "forward >> \ncan bind sm_lpp", (g_bloadreplay && !iPlayerTickData[client].replay_auto_path) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("5", "Backtrack << \ncan bind sm_ldd", (g_bloadreplay && !iPlayerTickData[client].replay_auto_path) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("1", "from begging << \n ", (g_bloadreplay && !iPlayerTickData[client].replay_auto_path) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);	
	if(g_bloadreplay)
		Format(buffer, sizeof(buffer), "progress bar %i - %i / %i ", iPlayerTickData[client].replay_start_tick, iPlayerTickData[client].replay_end_tick, playbackTickData.Length);
	else
		Format(buffer, sizeof(buffer), "The current map does not have playback data");
	menu.AddItem("4", buffer, ITEMDRAW_DISABLED);
	menu.AddItem("1", "Watch this route with BOT", g_bloadreplay ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Continue;
}

public int m_kzlines(Menu menu, MenuAction action, int client, int option)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			if(option == 0)
			{
				iPlayerTickData[client].replay_line_enable = !iPlayerTickData[client].replay_line_enable;
				PrintToChat(client, "[KZ line] %s", iPlayerTickData[client].replay_line_enable ? "ON":"OFF");
				if(iPlayerTickData[client].replay_line_enable)
					SetClientCookie(client, g_cookieline, "1");
				else
					SetClientCookie(client, g_cookieline, "0");
				kz_line_menu(client, 0);	
			}
			if(option == 1)
			{
				iPlayerTickData[client].replay_auto_path = !iPlayerTickData[client].replay_auto_path;
				PrintToChat(client, "[KZ line] Auto update%s", iPlayerTickData[client].replay_auto_path ? "ON":"OFF");
				kz_line_menu(client, 0);	
			}
			if(option == 2)
			{
				if(playbackTickData.Length - 1 < Load_DataTick)
				{
					PrintToChat(client, "[KZ line] The current replay length does not need to advance or retreat");
					return 0;
				}
				if((iPlayerTickData[client].replay_end_tick + Load_DataTick >= playbackTickData.Length - 1))
				{
					if(iPlayerTickData[client].replay_start_tick + Load_DataTick < playbackTickData.Length - 1)
					{
						iPlayerTickData[client].replay_start_tick += Load_DataTick;
						iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
						iPlayerTickData[client].replay_end_tick = playbackTickData.Length - 1;
					}
				}
				else
				{
					iPlayerTickData[client].replay_start_tick += Load_DataTick;
					iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
					iPlayerTickData[client].replay_end_tick += Load_DataTick;
				}
				kz_line_menu(client, 0);	
				return 0;
			}
			if(option == 3)
			{
				if(playbackTickData.Length - 1 < Load_DataTick)
				{
					PrintToChat(client, "[KZ line] The current replay length does not need to advance or retreat");
					return 0;
				}
				if(iPlayerTickData[client].replay_start_tick - Load_DataTick <= 1)
				{
					iPlayerTickData[client].replay_start_tick = 1;
					iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
					iPlayerTickData[client].replay_end_tick = iPlayerTickData[client].replay_start_tick + Load_DataTick;
				}
				else
				{
					iPlayerTickData[client].replay_start_tick -= Load_DataTick;
					iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
					iPlayerTickData[client].replay_end_tick -= Load_DataTick;
				}
				kz_line_menu(client, 0);
				return 0;
			}
			if(option == 4)
			{
				PrintToChat(client, "[KZ line] start from begging replay line");
				iPlayerTickData[client].replay_start_tick = 1;
				iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
				iPlayerTickData[client].replay_end_tick = iPlayerTickData[client].replay_start_tick + Load_DataTick;
				kz_line_menu(client, 0);
				return 0;
			}
			if(option == 6)
			{
				GOKZ_RP_LoadJumpReplay(client, finalpath);
				return 0;
			}
		}
	}
	return 0;
}

#define TE_TIME 1.2
#define TE_MIN 1.0
#define TE_MAX 1.0

public void OnConfigsExecuted() 
{
	sprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
}

public Action OnPlayerRunCmd(int client)
{
	if(IsValidClient(client) && g_bloadreplay && iPlayerTickData[client].replay_line_enable)
	{
		if((iPlayerTickData[client].replay_post_tick >= iPlayerTickData[client].replay_end_tick - 1) || iPlayerTickData[client].replay_post_tick <= 0)
			iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick;
			
		if( (iPlayerTickData[client].replay_tickcount % 128) == 0 && iPlayerTickData[client].replay_auto_path) // update every 1 s
		{
			iPlayerTickData[client].replay_tickcount = 0;
			int GuessTick = GetClosestReplayFrame(client);
			if(GuessTick == -1 || GuessTick >= playbackTickData.Length - 1)
				return Plugin_Continue;
			else
			{
				if(GuessTick + (Load_DataTick - 300) >= playbackTickData.Length - 1)
				{
					iPlayerTickData[client].replay_start_tick = playbackTickData.Length - Load_DataTick;
					iPlayerTickData[client].replay_end_tick = playbackTickData.Length - 1;
					
				}
				else if(GuessTick <= 300 )
				{
					iPlayerTickData[client].replay_start_tick = 2;
					iPlayerTickData[client].replay_end_tick = iPlayerTickData[client].replay_start_tick + Load_DataTick;
				}
				else
				{
					iPlayerTickData[client].replay_start_tick = GuessTick - 300;
					iPlayerTickData[client].replay_end_tick = GuessTick + Load_DataTick - 300;	
				}
				if(iPlayerTickData[client].replay_post_tick < iPlayerTickData[client].replay_start_tick || iPlayerTickData[client].replay_post_tick > iPlayerTickData[client].replay_end_tick)
				{
					iPlayerTickData[client].replay_post_tick = iPlayerTickData[client].replay_start_tick + 1;
				}
			}
			
		}
		
		ReplayTickData PostTickData;
		ReplayTickData NextTickData;
		ReplayTickData PreTickData;
		if(iPlayerTickData[client].replay_post_tick <= 0)
			return Plugin_Continue;
		playbackTickData.GetArray(iPlayerTickData[client].replay_post_tick, PostTickData);
		playbackTickData.GetArray(iPlayerTickData[client].replay_post_tick + 1, NextTickData);
		playbackTickData.GetArray(iPlayerTickData[client].replay_post_tick - 1, PreTickData);
		if(GetVectorHorizontalLength(PostTickData.velocity) > 251.0 &&((PostTickData.flags & RP_FL_ONGROUND) && (NextTickData.flags & RP_FL_ONGROUND)))
			DrawBeams(client, PostTickData.origin, NextTickData.origin, TE_TIME, TE_MIN, TE_MAX, { 255, 0, 0, 255}, 0.0, 0);
		else
			DrawBeams(client, PostTickData.origin, NextTickData.origin, TE_TIME, TE_MIN, TE_MAX, { 0, 255, 0, 255}, 0.0, 0);
		float square[4][3];
		if(PostTickData.flags & RP_FL_ONGROUND && !(NextTickData.flags & RP_FL_ONGROUND))
		{
			square[0][0] = PostTickData.origin[0] + BOX_SIZE;
			square[0][1] = PostTickData.origin[1] + BOX_SIZE;
			square[0][2] = PostTickData.origin[2];
			
			square[1][0] = PostTickData.origin[0] + BOX_SIZE;
			square[1][1] = PostTickData.origin[1] - BOX_SIZE;
			square[1][2] = PostTickData.origin[2];
			
			square[2][0] = PostTickData.origin[0] - BOX_SIZE;
			square[2][1] = PostTickData.origin[1] - BOX_SIZE;
			square[2][2] = PostTickData.origin[2];
			
			square[3][0] = PostTickData.origin[0] - BOX_SIZE;
			square[3][1] = PostTickData.origin[1] + BOX_SIZE;
			square[3][2] = PostTickData.origin[2];
			
			DrawBeams(client, square[0], square[1], 1.0, 1.0, 1.0, { 255, 192, 203, 255}, 0.0, 0);
			DrawBeams(client, square[1], square[2], 1.0, 1.0, 1.0, { 255, 192, 203, 255}, 0.0, 0);
			DrawBeams(client, square[2], square[3], 1.0, 1.0, 1.0, { 255, 192, 203, 255}, 0.0, 0);
			DrawBeams(client, square[3], square[0], 1.0, 1.0, 1.0, { 255, 192, 203, 255}, 0.0, 0);	
		}
		else if(!(PreTickData.flags & RP_FL_ONGROUND ) && PostTickData.flags & RP_FL_ONGROUND)
		{
			square[0][0] = PostTickData.origin[0] + BOX_SIZE;
			square[0][1] = PostTickData.origin[1] + BOX_SIZE;
			square[0][2] = PostTickData.origin[2];
			
			square[1][0] = PostTickData.origin[0] + BOX_SIZE;
			square[1][1] = PostTickData.origin[1] - BOX_SIZE;
			square[1][2] = PostTickData.origin[2];
			
			square[2][0] = PostTickData.origin[0] - BOX_SIZE;
			square[2][1] = PostTickData.origin[1] - BOX_SIZE;
			square[2][2] = PostTickData.origin[2];
			
			square[3][0] = PostTickData.origin[0] - BOX_SIZE;
			square[3][1] = PostTickData.origin[1] + BOX_SIZE;
			square[3][2] = PostTickData.origin[2];
			
			DrawBeams(client, square[0], square[1], 1.0, 1.0, 1.0, { 25, 25, 255, 255}, 0.0, 0);
			DrawBeams(client, square[1], square[2], 1.0, 1.0, 1.0, { 25, 25, 255, 255}, 0.0, 0);
			DrawBeams(client, square[2], square[3], 1.0, 1.0, 1.0, { 25, 25, 255, 255}, 0.0, 0);
			DrawBeams(client, square[3], square[0], 1.0, 1.0, 1.0, { 25, 25, 255, 255}, 0.0, 0);		
		}
		iPlayerTickData[client].replay_post_tick++;
		iPlayerTickData[client].replay_tickcount++;
	}
	return Plugin_Continue;
}

void DrawBeams(int client, float startvec[3], float endvec[3], float life, float width, float endwidth, int color[4], float amplitude, int speed) 
{
	TE_SetupBeamPoints(startvec, endvec, sprite, 0, 0, 66, life, width, endwidth, 0, amplitude, color, speed);
	TE_SendToClient(client);
}

void LoadedReplays(bool use_wr) 
{
	g_bloadreplay = false;
	Init_KDtree();
	if(playbackTickData != null)
		playbackTickData.Clear();
	char replay_path[256];
	char mapName[128];
	
	GetCurrentMapDisplayName(mapName, sizeof(mapName));
	if(use_wr)
	{
		BuildPath(Path_SM, replay_path, sizeof(replay_path), "%s/%s/wr.replay", RP_DIRECTORY_RUNS, mapName);
		PrintToServer("Load replay %s", replay_path);
	}
	else
	{
		BuildPath(Path_SM, replay_path, sizeof(replay_path),
			"%s/%s/0_KZT_NRM_NUB.replay", RP_DIRECTORY_RUNS, mapName); // read nub runs bcz is good mode :)
		if(!FileExists(replay_path))
		{
			PrintToServer("%s not Exists", replay_path);
			BuildPath(Path_SM, replay_path, sizeof(replay_path),
				"%s/%s/0_KZT_NRM_PRO.replay", RP_DIRECTORY_RUNS, mapName); // now we read pro runs :)
			if(!FileExists(replay_path))
			{
				PrintToServer("%s not Exists", replay_path);
				return;
			}
		}
	}
	File file = OpenFile(replay_path, "rb");
	int magicNumber;
	file.ReadInt32(magicNumber);
	if (magicNumber != RP_MAGIC_NUMBER)
	{
		LogError("Failed to load invalid replay file: \"%s\".", replay_path);
		if(use_wr)
		{
			DeleteFile(replay_path);
			delete file;
			LoadedReplays( false );
		}
		delete file;
		return;
	}

	int formatVersion;
	file.ReadInt8(formatVersion);
	switch(formatVersion)
	{
		case 1:
		{
			PrintToServer("read %s as formatVersion 1", replay_path);
			LoadFormatVersion1Replay(file);
		}
		case 2:
		{
			PrintToServer("read %s as formatVersion 2", replay_path);
			LoadFormatVersion2Replay(file);
		}

		default:
		{
			LogError("Failed to load replay file with unsupported format version: \"%s\".", replay_path);
			delete file;
		}
	}
	
	strcopy(finalpath, sizeof(finalpath), replay_path);
}

#define RP_V1_TICK_DATA_BLOCKSIZE 7

void LoadFormatVersion1Replay(File file)
{	
	int length;

	// GOKZ version
	file.ReadInt8(length);
	char[] gokzVersion = new char[length + 1];
	file.ReadString(gokzVersion, length, length);
	gokzVersion[length] = '\0';
	
	// Map name 
	file.ReadInt8(length);
	char[] mapName = new char[length + 1];
	file.ReadString(mapName, length, length);
	mapName[length] = '\0';
	
	int botCourse;
	int botMode;
	int botStyle;
	// Some integers...
	file.ReadInt32(botCourse);
	file.ReadInt32(botMode);
	file.ReadInt32(botStyle);
	
	
	// Time
	int timeAsInt;
	file.ReadInt32(timeAsInt);
	
	// Some integers...
	int botTeleportsUsed;
	int botSteamAccountID;
	file.ReadInt32(botTeleportsUsed);
	file.ReadInt32(botSteamAccountID);
	
	// SteamID2 
	file.ReadInt8(length);
	char[] steamID2 = new char[length + 1];
	file.ReadString(steamID2, length, length);

	
	// IP
	file.ReadInt8(length);
	char[] IP = new char[length + 1];
	file.ReadString(IP, length, length);

	
	// Alias
	char botAlias[MAX_NAME_LENGTH];
	file.ReadInt8(length);
	file.ReadString(botAlias, MAX_NAME_LENGTH, length);

	// Read tick data
	file.ReadInt32(length);
	
	// Setup playback tick data array list

	playbackTickData = new ArrayList(IntMax(RP_V1_TICK_DATA_BLOCKSIZE, sizeof(ReplayTickData)), length);

	// The replay has no replay data, this shouldn't happen normally,
	// but this would cause issues in other code, so we don't even try to load this.
	if (length == 0)
	{
		LogError("Failed to load replay file length == 0");
		delete file;
		return;
	}
	
	any tickData[RP_V1_TICK_DATA_BLOCKSIZE];
	for (int i = 0; i < length; i++)
	{
		file.Read(tickData, RP_V1_TICK_DATA_BLOCKSIZE, 4);
		playbackTickData.Set(i, view_as<float>(tickData[0]), 0); // origin[0]
		playbackTickData.Set(i, view_as<float>(tickData[1]), 1); // origin[1]
		playbackTickData.Set(i, view_as<float>(tickData[2]), 2); // origin[2]
		playbackTickData.Set(i, view_as<float>(tickData[3]), 3); // angles[0]
		playbackTickData.Set(i, view_as<float>(tickData[4]), 4); // angles[1]
		playbackTickData.Set(i, view_as<int>(tickData[5]), 5); // buttons
		playbackTickData.Set(i, view_as<int>(tickData[6]), 6); // flags
	}

	delete file;
	g_bloadreplay = true;
}

void LoadFormatVersion2Replay(File file)
{
	int length;
	
	int replayType;
	file.ReadInt8(replayType);
	
	file.ReadInt8(length);
	char[] gokzVersion = new char[length + 1];
	file.ReadString(gokzVersion, length, length);
	gokzVersion[length] = '\0';
	
	file.ReadInt8(length);
	char[] mapName = new char[length + 1];
	file.ReadString(mapName, length, length);
	mapName[length] = '\0';
	
	int mapFileSize;
	file.ReadInt32(mapFileSize);

	int serverIP;
	file.ReadInt32(serverIP);

	int timestamp;
	file.ReadInt32(timestamp);
	
	char botAlias[MAX_NAME_LENGTH];
	file.ReadInt8(length);
	file.ReadString(botAlias, MAX_NAME_LENGTH, length);

	// Player Steam ID
	int steamID;
	file.ReadInt32(steamID);

	// Mode
	int botMode;
	file.ReadInt8(botMode);

	// Style
	int botStyle;
	file.ReadInt8(botStyle);

	// Player Sensitivity
	int intPlayerSensitivity;
	file.ReadInt32(intPlayerSensitivity);
	float playerSensitivity = view_as<float>(intPlayerSensitivity);

	// Player MYAW
	int intPlayerMYaw;
	file.ReadInt32(intPlayerMYaw);
	float playerMYaw = view_as<float>(intPlayerMYaw);

	// Tickrate
	int tickrateAsInt;
	file.ReadInt32(tickrateAsInt);
	float tickrate = view_as<float>(tickrateAsInt);

	// Tick Count
	int tickCount;
	file.ReadInt32(tickCount);

	if (tickCount == 0)
	{
		LogError("Failed to load replay file length == 0");
		delete file;
		return;
	}
	
	int botWeapon;
	// Equipped Weapon
	file.ReadInt32(botWeapon);
	int botKnife;
	// Equipped Knife
	file.ReadInt32(botKnife);

	// Big spit to console
	PrintToServer("Replay Type: %d\nGOKZ Version: %s\nMap Name: %s\nMap Filesize: %d\nServer IP: %d\nTimestamp: %d\nPlayer Alias: %s\nPlayer Steam ID: %d\nMode: %d\nStyle: %d\nPlayer Sensitivity: %f\nPlayer m_yaw: %f\nTickrate: %f\nTick Count: %d\nWeapon: %d\nKnife: %d", replayType, gokzVersion, mapName, mapFileSize, serverIP, timestamp, botAlias, steamID, botMode, botStyle, playerSensitivity, playerMYaw, tickrate, tickCount, botWeapon, botKnife);

	int timeAsInt;
	file.ReadInt32(timeAsInt);
	float botTime = view_as<float>(timeAsInt);
	int botCourse;
	int botTeleportsUsed;
	file.ReadInt8(botCourse);
	file.ReadInt32(botTeleportsUsed);

	PrintToServer("Time: %f\nCourse: %d\nTeleports Used: %d", botTime, botCourse, botTeleportsUsed);
	playbackTickData = new ArrayList(IntMax(RP_V1_TICK_DATA_BLOCKSIZE, sizeof(ReplayTickData)));
	any tickDataArray[RP_V2_TICK_DATA_BLOCKSIZE];
	for (int i = 0; i < tickCount; i++)
	{
		file.ReadInt32(tickDataArray[RPDELTA_DELTAFLAGS]);
		
		for (int index = 1; index < sizeof(tickDataArray); index++)
		{
			int currentFlag = (1 << index);
			if (tickDataArray[RPDELTA_DELTAFLAGS] & currentFlag)
			{
				file.ReadInt32(tickDataArray[index]);
			}
		}
		
		ReplayTickData tickData;
		TickDataFromArray(tickDataArray, tickData);
		if (tickData.origin[0] == 0 && tickData.origin[1] == 0 && tickData.origin[2] == 0 && tickData.angles[0] == 0 && tickData.angles[1] == 0)
		{
			break;
		}
		KDTree_InsertNode(tickData.origin, i);
		playbackTickData.PushArray(tickData);
	}
	delete file;
	g_bloadreplay = true;
	PrintToServer("KDTree_InsertNode Done! Length %i",KDtreeData.Length - 1);
}

void TickDataFromArray(any array[RP_V2_TICK_DATA_BLOCKSIZE], ReplayTickData result)
{
	result.deltaFlags          = array[0];
	result.deltaFlags2         = array[1];
	result.vel[0]              = array[2];
	result.vel[1]              = array[3];
	result.vel[2]              = array[4];
	result.mouse[0]            = array[5];
	result.mouse[1]            = array[6];
	result.origin[0]           = array[7];
	result.origin[1]           = array[8];
	result.origin[2]           = array[9];
	result.angles[0]           = array[10];
	result.angles[1]           = array[11];
	result.angles[2]           = array[12];
	result.velocity[0]         = array[13];
	result.velocity[1]         = array[14];
	result.velocity[2]         = array[15];
	result.flags               = array[16];
	result.packetsPerSecond    = array[17];
	result.laggedMovementValue = array[18];
	result.buttonsForced       = array[19];
}

stock char[] I_FormatTime(float time)
{
	char formattedTime[12];

	int roundedTime = RoundFloat(time * 100); // Time rounded to number of centiseconds

	int centiseconds = roundedTime % 100;
	roundedTime = (roundedTime - centiseconds) / 100;
	int seconds = roundedTime % 60;
	roundedTime = (roundedTime - seconds) / 60;
	int minutes = roundedTime % 60;
	roundedTime = (roundedTime - minutes) / 60;
	int hours = roundedTime;

	if (hours == 0 && minutes == 0)
	{
		FormatEx(formattedTime, sizeof(formattedTime), "%02d.%02d",seconds, centiseconds);
	}
	if(hours == 0 && minutes > 0)
		FormatEx(formattedTime, sizeof(formattedTime), "%01d:%01d.%02d",minutes, seconds, centiseconds);
	else if(hours > 0)
	{
		FormatEx(formattedTime, sizeof(formattedTime), "%01d:%01d", hours, minutes);
	}
	return formattedTime;
}
