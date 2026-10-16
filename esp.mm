#import <Foundation/Foundation.h>
#import "esp.h"
#include <cmath>

std::vector<ESPPlayer> g_esp_players;

bool AX_WorldToScreen(Vec3 world, Vec3* screen) {
    // TODO: хук Camera.WorldToScreenPoint (имя получим из дампа)
    (void)world; (void)screen;
    return false;
}

void AX_CollectESP(void) {
    g_esp_players.clear();
    // TODO: обойти врагов, заполнить world_head/world_feet/health
    // имена методов получим из дампа
}

void AX_Tick(void* self) {
    if (!g_cfg.esp && !g_cfg.aimbot) return;
    AX_CollectESP();
    if (g_cfg.esp) AX_DrawESP();
}
