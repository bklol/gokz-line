#if defined _kztime_included
 #endinput
#endif
#define _kztime_included

native bool KZ_HasLoadReplayFile()//查询是否已载入数据

/**
 * 与载入replay时间差 Time difference from replay
 * @param client 目标玩家 player index
 * @param time 玩家在该位置的时间 The player's time at the location
 * @param timediff 与replay时间差 Time difference with replay
 */
native void KZ_GetTimeDiff(int client, float time, char[] timediff)

