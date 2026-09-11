

#include "ra/sim.h"

namespace ra {

namespace {


struct PersonalityRow {
    int32_t plan_weight[PLAN_COUNT];
    int32_t first_attack_tick;
    int32_t target_value_weight;
    int32_t target_threat_weight;
    int32_t nuke_min;
    int32_t iron_min;
    int32_t chrono_min;
    int32_t air_squad_size;
    int32_t raid_squad_size;
    int32_t raid_interval;
    int32_t siege_range_percent;
};


constexpr PersonalityRow ROWS[BOT_P_COUNT - 1] = {

    {{100, 100, 100, 100, 100}, 4500, 100, 30, 3000, 2000, 2500, 3, 4, 1500, 85},


    {{ 70, 170,  80,  80,  70}, 1500,  80, 15, 4000, 2600, 3200, 3, 3,  900, 85},


    {{130,  60,  90, 120, 170}, 12000, 110, 50, 1800, 1300, 1600, 4, 0, 3000, 90},


    {{100,  90, 200,  80,  90}, 6000, 100, 60, 3000, 2000, 2500, 2, 3, 1200, 85},


    {{110, 100,  90, 110, 100}, 5000, 100, 30, 3000, 2000, 2500, 3, 4, 1500, 85},
};

}


void World::bot_apply_personality(BotParams& p, int32_t personality) {
    const int32_t idx = (personality >= 0 && personality < BOT_P_COUNT - 1) ? personality : int32_t(BOT_P_NORMAL);
    const PersonalityRow& r = ROWS[idx];
    p.personality = personality;
    for (int i = 0; i < PLAN_COUNT; ++i) p.plan_weight[i] = r.plan_weight[i];
    p.first_attack_tick = r.first_attack_tick;
    p.target_value_weight = r.target_value_weight;
    p.target_threat_weight = r.target_threat_weight;
    p.nuke_min_attractiveness = r.nuke_min;
    p.iron_min_attractiveness = r.iron_min;
    p.chrono_min_attractiveness = r.chrono_min;
    p.air_squad_size = r.air_squad_size;
    p.raid_squad_size = r.raid_squad_size;
    p.raid_interval = r.raid_interval;
    p.siege_range_percent = r.siege_range_percent;
}

}
