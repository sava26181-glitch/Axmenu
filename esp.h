#pragma once
#include <vector>
#include <string>

struct Vec3 { float x, y, z; };

struct Config {
    bool  esp         = false;
    bool  esp_box     = true;
    bool  esp_health  = false;
    bool  aimbot      = false;
    float aim_fov     = 45.0f;
    float aim_smooth  = 8.0f;
};
extern Config g_cfg;

struct ESPPlayer {
    Vec3  world_head;
    Vec3  world_feet;
    float health = 100.0f;
    bool  valid  = false;
};
extern std::vector<ESPPlayer> g_esp_players;

#ifdef __cplusplus
extern "C" {
#endif

void  AX_InstallRuntimeHooks(void);
void  AX_StartOverlay(void);
void  AX_DrawESP(void);
void  AX_Tick(void* self);
void  AX_CollectESP(void);
bool  AX_WorldToScreen(Vec3 world, Vec3* screen);

// дамп методов — для реверса
void  AX_DumpAllClasses(void);
void  AX_DumpClassMethods(const char* klassName);
void* AX_FindMethodPtr(const char* ns, const char* klass, const char* method, int argc);

#ifdef __cplusplus
}
#endif
