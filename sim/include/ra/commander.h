

#pragma once

#include <cstdint>

namespace ra {


enum BotLevel { LV_NONE = 0, LV_LOW = 1, LV_MEDIUM = 2, LV_HIGH = 3, LV_STRONG = 4, LV_COUNT = 5 };
enum BotTrend { TR_FALLING = 0, TR_FLAT = 1, TR_RISING = 2 };
enum BotMapType { MAP_LAND = 0, MAP_MIXED = 1, MAP_ISLANDS = 2 };
enum BotDomain { DOM_LAND = 0, DOM_AIR = 1, DOM_NAVAL = 2, DOM_COUNT = 3 };


enum BotDoctrine { DOC_LAND_PUSH = 0, DOC_AIR_DOMINANCE = 1, DOC_NAVAL_DOMINANCE = 2, DOC_ECO_TURTLE = 3,
                   DOC_AMPHIBIOUS = 4, DOC_COUNT = 5 };

constexpr int DOC_COUNT_V1 = 4;
enum BotEconomyChoice { ECO_MORE_REFINERIES = 0, ECO_OK = 1, ECO_SAVE_MONEY = 2, ECO_COUNT = 3 };
enum BotStance { ST_ATTACK = 0, ST_HOLD = 1, ST_DEFEND = 2, ST_RETREAT = 3, ST_COUNT = 4 };
enum BotDirectiveSource { SRC_NONE = 0, SRC_RULE = 1, SRC_EXTERNAL = 2 };


constexpr int CMD_BUCKETS = 12;
constexpr int CMD_BUCKET_TICKS = 125;


constexpr int CMD_DIRECTIVE_WORDS = DOC_COUNT + ECO_COUNT + ST_COUNT + 2;
constexpr int CMD_DIRECTIVE_WORDS_V1 = DOC_COUNT_V1 + ECO_COUNT + ST_COUNT + 2;


enum CmdEnemyClass { EC_SIEGE = 0, EC_ARMOR = 1, EC_INFANTRY = 2, EC_AIR = 3, EC_NAVAL = 4, EC_SUBS = 5,
                     EC_COMMANDO = 6, EC_ENGINEER = 7, EC_SPY = 8, EC_COUNT = 9 };

enum CmdThreatClass { TC_AIR = 0, TC_LAND = 1, TC_NAVAL = 2, TC_SIEGE = 3, TC_COUNT = 4 };

enum CmdSector { SEC_NONE = 0, SEC_N = 1, SEC_NE = 2, SEC_E = 3, SEC_SE = 4, SEC_S = 5, SEC_SW = 6, SEC_W = 7,
                 SEC_NW = 8, SEC_COUNT = 9 };
constexpr int CMD_SECTORS = 8;
enum CmdSuperweapon { SW_NONE = 0, SW_CHARGING = 1, SW_READY = 2 };

enum CmdCounter { CT_NONE = 0, CT_ANTI_AIR = 1, CT_ANTI_SIEGE_SORTIE = 2, CT_SPREAD_DEFENSE = 3,
                  CT_ANTI_INFILTRATION = 4, CT_ANTI_NAVAL = 5, CT_COUNT = 6 };
enum CmdEconomyFix { EF_NONE = 0, EF_SILO = 1, EF_REFINERY = 2, EF_HARVESTER = 3, EF_COUNT = 4 };
enum CmdSpecialOp { SO_NONE = 0, SO_COMMANDO_RAID = 1, SO_ENGINEER_CAPTURE = 2, SO_SPY_INFILTRATE = 3,
                    SO_SUPERWEAPON_NOW = 4, SO_COUNT = 5 };


constexpr int CMD_DIRECTIVE_WORDS_V3 = CMD_DIRECTIVE_WORDS + CT_COUNT + SEC_COUNT + EF_COUNT + SO_COUNT;


struct CmdTrack {
    int32_t pos = 0;
    int32_t bucket_ticks = 0;
    int32_t cx = -1, cy = -1;
    int32_t dmg_class[TC_COUNT][CMD_BUCKETS] = {};
    int32_t dmg_sector[CMD_SECTORS][2][CMD_BUCKETS] = {};
    int32_t harv_lost[CMD_BUCKETS] = {};
    int32_t outranged[CMD_BUCKETS] = {};

    int32_t income[CMD_BUCKETS] = {};
    int64_t snap_earned = 0;
    int32_t lost[DOM_COUNT][CMD_BUCKETS] = {};
    int32_t kills[CMD_BUCKETS] = {};
    int32_t damage[CMD_BUCKETS] = {};
    int32_t last_hit_tick = 0;
};


struct BotMapInfo {
    int32_t done = 0;
    int32_t map_type = MAP_LAND;
    int32_t water_permille = 0;
    int32_t landmasses = 0;
    int32_t enemy_starts = 0;
    int32_t land_connected = 0;
    int32_t ore_fields = 0;


    int32_t amphib_possible = 0;
};


struct BotSummary {
    int32_t tick = -1;
    int32_t credits = LV_NONE;
    int32_t income = TR_FLAT;
    int32_t income_60s = 0;
    int32_t refineries = LV_NONE;
    int32_t power_ok = 1;
    int32_t army[DOM_COUNT] = {0, 0, 0};
    int32_t enemy[DOM_COUNT] = {0, 0, 0};
    int32_t enemy_anti_air = LV_NONE;
    int32_t enemy_attacking = 0;
    int32_t air_losses_60s = LV_NONE;
    int32_t land_losses_60s = LV_NONE;
    int32_t kills_60s = LV_NONE;
    int32_t base_damage_60s = LV_NONE;
    int32_t base_threat = 0;
    int32_t doctrine = DOC_LAND_PUSH;
    int32_t doctrine_age_s = 0;
    int32_t opening_done = 1;


    int32_t raw_credits = 0;
    int32_t raw_refineries = 0;
    int32_t raw_army[DOM_COUNT] = {0, 0, 0};
    int32_t raw_enemy[DOM_COUNT] = {0, 0, 0};
    int32_t raw_enemy_aa = 0;
    int32_t raw_air_lost = 0;
    int32_t raw_land_lost = 0;
    int32_t raw_kills = 0;
    int32_t raw_base_damage = 0;


    int32_t enemy_class[EC_COUNT] = {};
    int32_t dmg_class[TC_COUNT] = {};
    int32_t dmg_main_class = -1;
    int32_t dmg_sector = SEC_NONE;
    int32_t sectors_hit = 0;
    int32_t defense_outranged = LV_NONE;
    int32_t uncovered_sector = SEC_NONE;
    int32_t uncovered_class = -1;
    int32_t own_defense[2] = {};
    int32_t ore_wasting = 0;
    int32_t silos = LV_NONE;
    int32_t harv_losses_60s = LV_NONE;
    int32_t own_superweapon = SW_NONE;
    int32_t enemy_superweapon = SW_NONE;

    int32_t open_back = LV_NONE;
    int32_t open_back_sector = SEC_NONE;
    int32_t uncovered_buildings = LV_NONE;
    int32_t own_special[3] = {};
    int32_t enemy_base_known = 0;
    int32_t enemy_soft = LV_NONE;

    int32_t raw_enemy_class[EC_COUNT] = {};
    int32_t raw_dmg_class[TC_COUNT] = {};
    int32_t raw_outranged = 0, raw_storage_permille = 0, raw_silos = 0, raw_harv_lost = 0;
    int32_t raw_open_back = 0, raw_uncovered = 0, raw_enemy_soft = 0;
    int32_t raw_own_defense[2] = {};
};


struct BotDecision {
    int32_t doctrine[DOC_COUNT] = {1000, 0, 0, 0, 0};
    int32_t economy[ECO_COUNT] = {0, 1000, 0};
    int32_t stance[ST_COUNT] = {0, 1000, 0, 0};
    int32_t keep_using_air = 1000;
    int32_t base_threat = 0;

    int32_t counter[CT_COUNT] = {1000, 0, 0, 0, 0, 0};
    int32_t defense_sector[SEC_COUNT] = {1000, 0, 0, 0, 0, 0, 0, 0, 0};
    int32_t economy_fix[EF_COUNT] = {1000, 0, 0, 0};
    int32_t special_op[SO_COUNT] = {1000, 0, 0, 0, 0};
};


struct BotDirective {
    int32_t doctrine = DOC_LAND_PUSH;
    int32_t economy = ECO_OK;
    int32_t stance = ST_HOLD;
    int32_t keep_using_air = 1;
    int32_t base_threat = 0;
    int32_t valid_until_tick = 0;
    int32_t source = SRC_NONE;
    int32_t doctrine_since = 0;
    int32_t decided = 0;


    int32_t counter = CT_NONE;
    int32_t defense_sector = SEC_NONE;
    int32_t economy_fix = EF_NONE;
    int32_t special_op = SO_NONE;
    int32_t special_since = 0;
};


struct BotCommanderMods {
    int32_t vh_weight[16] = {100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100};
    int32_t queue[4] = {100, 100, 100, 100};
    int32_t squad = 100;
    int32_t running_delta = 0;
    int32_t surplus = 100;
    int32_t extra_refineries = 0;
    int32_t defense = 100;


    int32_t aa_extra = 0;
    int32_t defense_sector = SEC_NONE;
    int32_t defense_spread = 0;
    int32_t raid_siege = 0;
    int32_t guard_back = 0;
    int32_t silo_first = 0;
    int32_t extra_harvesters = 0;
    int32_t sp_threshold = 100;
};


struct CmdHumanActs {
    int32_t aa_built = 0, aa_sector = SEC_NONE;
    int32_t towers_built = 0, tower_sector = SEC_NONE;
    uint32_t tower_sectors = 0;
    int32_t back_tower = 0;
    int32_t silo = 0, refinery = 0, harvester = 0;
    int32_t airfield = 0, shipyard = 0;
    int32_t naval_units = 0;
    int32_t attack_units = 0;
    int32_t home_units = 0;
    int32_t siege_hunt = 0;
    int32_t commando = 0, engineer = 0, spy = 0;
    int32_t superweapon = 0;
};

}
