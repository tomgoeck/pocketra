

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace ra {

using WDist = int32_t;
using WAngle = int32_t;
constexpr WDist CELL = 1024;
constexpr WAngle FULL_TURN = 1024;
constexpr int TICKS_PER_SECOND = 25;


constexpr int MAX_PLAYERS = 10;

const char* version();


struct WVec {
    WDist x = 0, y = 0;
    WVec operator+(WVec o) const { return {x + o.x, y + o.y}; }
    WVec operator-(WVec o) const { return {x - o.x, y - o.y}; }
    bool operator==(WVec o) const { return x == o.x && y == o.y; }
    bool operator!=(WVec o) const { return !(*this == o); }
};

struct CPos {
    int32_t x = 0, y = 0;
    bool operator==(CPos o) const { return x == o.x && y == o.y; }
    bool operator!=(CPos o) const { return !(*this == o); }
};

inline CPos to_cell(WVec p) { return {p.x >> 10, p.y >> 10}; }
inline WVec cell_center(CPos c) { return {c.x * CELL + CELL / 2, c.y * CELL + CELL / 2}; }


constexpr int NUM_SUBCELLS = 5;
constexpr int SUB_FULL = 0;
constexpr int SUB_FIRST = 1;
constexpr int SUB_INVALID = -1;
constexpr int SUB_DEFAULT = 3;
constexpr int CELL_SLOTS = NUM_SUBCELLS + 1;


inline WVec subcell_offset(int sub) {
    constexpr WDist OX[CELL_SLOTS] = {0, -299, 256, 0, -299, 256};
    constexpr WDist OY[CELL_SLOTS] = {0, -256, -256, 0, 256, 256};
    return (sub > SUB_FULL && sub <= NUM_SUBCELLS) ? WVec{OX[sub], OY[sub]} : WVec{0, 0};
}

inline WVec subcell_center(CPos c, int sub) { return cell_center(c) + subcell_offset(sub); }

inline int64_t cell_dist_sq(CPos a, CPos b) {
    const int64_t dx = a.x - b.x, dy = a.y - b.y;
    return dx * dx + dy * dy;
}

int32_t isqrt(int64_t v);
inline int64_t length_sq(WVec v) { return int64_t(v.x) * v.x + int64_t(v.y) * v.y; }
inline int32_t length(WVec v) { return isqrt(length_sq(v)); }


WAngle iatan2(int64_t y, int64_t x);

inline WAngle angle_of(WVec d) { return iatan2(-int64_t(d.x), -int64_t(d.y)); }
inline WAngle wrap_angle(WAngle a) { return ((a % FULL_TURN) + FULL_TURN) % FULL_TURN; }

inline WAngle angle_diff(WAngle from, WAngle to) { return wrap_angle(to - from + FULL_TURN / 2) - FULL_TURN / 2; }
inline WAngle abs_angle_diff(WAngle a, WAngle b) { const WAngle d = angle_diff(a, b); return d < 0 ? -d : d; }
WAngle turn_towards(WAngle from, WAngle to, WAngle max_step);

WVec direction_of(WAngle a);


constexpr int NUM_DIRS = 8;
constexpr int DIR_DX[NUM_DIRS] = {0, 1, 1, 1, 0, -1, -1, -1};
constexpr int DIR_DY[NUM_DIRS] = {-1, -1, 0, 1, 1, 1, 0, -1};
constexpr int STRAIGHT_COST = 10;
constexpr int DIAGONAL_COST = 14;


enum Terrain { TER_CLEAR = 0, TER_ROUGH, TER_ROAD, TER_BRIDGE, TER_ORE, TER_GEMS, TER_BEACH, TER_WATER, TER_RIVER,
               TER_ROCK, TER_TREE, TER_WALL, NUM_TERRAIN };
enum Locomotor { LOCO_FOOT = 0, LOCO_WHEELED, LOCO_TRACKED, LOCO_NAVAL, LOCO_LCRAFT, NUM_LOCOMOTORS };


enum SmudgeKind { SMUDGE_NONE = 0, SMUDGE_SCORCH = 1, SMUDGE_CRATER = 2, NUM_SMUDGE_KINDS = 3 };


inline bool terrain_accepts_smudge(int32_t terrain) {
    return terrain == TER_CLEAR || terrain == TER_ROUGH || terrain == TER_ROAD || terrain == TER_BRIDGE ||
           terrain == TER_ORE || terrain == TER_GEMS || terrain == TER_WALL;
}


int32_t terrain_speed(int32_t locomotor, int32_t terrain);


enum MoveClass { MC_LAND = 0, MC_NAVAL, MC_LCRAFT, NUM_MOVE_CLASSES };
inline int32_t move_class_of(int32_t locomotor) {
    if (locomotor == LOCO_NAVAL) return MC_NAVAL;
    if (locomotor == LOCO_LCRAFT) return MC_LCRAFT;
    return MC_LAND;
}

inline int32_t move_class_locomotor(int32_t mc) {
    if (mc == MC_NAVAL) return LOCO_NAVAL;
    if (mc == MC_LCRAFT) return LOCO_LCRAFT;
    return LOCO_TRACKED;
}

class Map {
public:
    void reset(int width, int height, const uint8_t* cost);

    void set_terrain(int width, int height, const uint8_t* terrain);
    int32_t terrain(CPos c) const { return in_bounds(c) && !terrain_.empty() ? terrain_[index(c)] : TER_CLEAR; }


    int32_t base_terrain(CPos c) const { return in_bounds(c) && !base_terrain_.empty() ? base_terrain_[index(c)] : TER_CLEAR; }
    void set_terrain_at(CPos c, int32_t t);


    void set_base_terrain_at(CPos c, int32_t t, bool update_cost = true);

    void set_cost(CPos c, uint8_t cost) {
        if (!in_bounds(c)) return;
        for (int mc = 0; mc < NUM_MOVE_CLASSES; ++mc) cost_[mc][index(c)] = cost;
    }
    void restore_cost(CPos c);
    static uint8_t cost_for_terrain(int32_t terrain, int32_t mc = MC_LAND);
    int width() const { return w_; }
    int height() const { return h_; }
    int cells() const { return w_ * h_; }
    bool in_bounds(CPos c) const { return c.x >= 0 && c.y >= 0 && c.x < w_ && c.y < h_; }
    int index(CPos c) const { return c.y * w_ + c.x; }
    CPos cell_at(int index) const { return {index % w_, index / w_}; }
    uint8_t cost(CPos c, int32_t mc = MC_LAND) const {
        return in_bounds(c) && mc >= 0 && mc < NUM_MOVE_CLASSES ? cost_[mc][index(c)] : 0;
    }
    bool passable(CPos c, int32_t mc = MC_LAND) const { return cost(c, mc) != 0; }


    bool can_step(CPos from, int dir, int32_t mc = MC_LAND) const;


    const std::vector<uint8_t>& raw_cost(int32_t mc = MC_LAND) const { return cost_[mc]; }
    const std::vector<uint8_t>& raw_terrain() const { return terrain_; }
    const std::vector<uint8_t>& raw_base_terrain() const { return base_terrain_; }
    void restore(int width, int height, std::vector<uint8_t> cost, std::vector<uint8_t> terrain,
                 std::vector<uint8_t> base_terrain);
    void restore_cost_layer(int32_t mc, std::vector<uint8_t> cost);


    void rebuild_water_costs();

private:
    int w_ = 0, h_ = 0;
    std::vector<uint8_t> cost_[NUM_MOVE_CLASSES];
    std::vector<uint8_t> terrain_;
    std::vector<uint8_t> base_terrain_;
};


struct FlowField {
    CPos goal;
    int32_t move_class = MC_LAND;
    std::vector<int32_t> dist;
    std::vector<int8_t> next;
};

class FlowFieldCache {
public:
    static constexpr size_t MAX_FIELDS = 256;


    int get_or_build(const Map& map, CPos goal, int32_t mc = MC_LAND);
    const FlowField& field(int id) const { return fields_[id]; }
    void clear();
    size_t size() const { return fields_.size(); }
    uint32_t builds() const { return builds_; }


    uint32_t generation() const { return generation_; }
    bool valid(int id, uint32_t gen) const { return id >= 0 && size_t(id) < fields_.size() && gen == generation_; }

private:
    std::vector<FlowField> fields_;
    std::unordered_map<int, int> by_goal_;
    uint32_t builds_ = 0;
    uint32_t generation_ = 1;
};

void build_flow_field(const Map& map, CPos goal, FlowField& out, int32_t mc = MC_LAND);


enum Resource { RES_NONE = 0, RES_ORE = 1, RES_GEMS = 2 };
constexpr int32_t RESOURCE_VALUE[3] = {0, 25, 50};
constexpr uint8_t ORE_MAX_DENSITY = 12;
constexpr uint8_t GEMS_MAX_DENSITY = 3;


constexpr int32_t RES_BLOCK = 4;

constexpr int32_t RICH_LOADS = 2;


constexpr int32_t GEM_BONUS = 150;

constexpr int32_t REFINERY_DIRECTION_PENALTY = 200;

constexpr int32_t MAX_DOCK_QUEUE = 3;


constexpr int32_t DOCK_QUEUE_COST = 60;

constexpr int32_t DOCK_FULL_COST = 600;


enum Armor { ARMOR_NONE = 0, ARMOR_WOOD, ARMOR_LIGHT, ARMOR_HEAVY, ARMOR_CONCRETE, ARMOR_TREE, NUM_ARMOR };


enum TargetType {
    TT_GROUND_ACTOR = 1u << 0, TT_WATER_ACTOR = 1u << 1, TT_AIRBORNE = 1u << 2, TT_INFANTRY = 1u << 3,
    TT_VEHICLE = 1u << 4, TT_STRUCTURE = 1u << 5, TT_DEFENSE = 1u << 6, TT_WALL = 1u << 7,
    TT_MINE = 1u << 8, TT_TREES = 1u << 9, TT_NO_AUTO_TARGET = 1u << 10, TT_HEAL = 1u << 11,
    TT_REPAIR = 1u << 12, TT_SHIP = 1u << 13, TT_SUBMARINE = 1u << 14, TT_UNDERWATER = 1u << 15,
    TT_C4 = 1u << 16, TT_BARREL = 1u << 17, TT_CRATE = 1u << 18, TT_DISGUISE = 1u << 19,
    TT_ANT = 1u << 20, TT_BRIDGE = 1u << 21, TT_HUSK = 1u << 22, TT_DETONATE = 1u << 23,


    TT_SPY_INFILTRATE = 1u << 24, TT_THIEF_INFILTRATE = 1u << 25,


    TT_MISSION_OBJECTIVES = 1u << 26,
};


enum EnterKind {
    ENTER_NONE = 0,
    ENTER_CAPTURE,
    ENTER_REPAIR,
    ENTER_DEMOLISH,
    ENTER_INFILTRATE,


    ENTER_REPAIR_BRIDGE,
};

enum EnterState { ENTER_APPROACH = 0, ENTER_INSIDE, ENTER_EXIT };


enum CaptureType { CAP_BUILDING = 1u << 0, CAP_VEHICLE = 1u << 1, CAP_AIRCRAFT = 1u << 2, CAP_HUSK = 1u << 3 };


enum CrushClass { CRUSH_INFANTRY = 1u << 0, CRUSH_WALL = 1u << 1, CRUSH_HEAVYWALL = 1u << 2,
                  CRUSH_MINE = 1u << 3, CRUSH_CRATE = 1u << 4 };

enum DetectionType { DETECT_CLOAK = 1u << 0, DETECT_MINE = 1u << 1, DETECT_UNDERWATER = 1u << 2 };


enum SupportPowerKind { SP_IRON_CURTAIN = 0, SP_CHRONOSHIFT = 1, SP_NUKE = 2, SP_GPS = 3, SP_COUNT = 4 };
struct SupportPowerState {
    bool available = false;
    bool ready = false;
    int32_t charge = 0;

    bool used = false;
};
enum UncloakOn { UNCLOAK_ATTACK = 1u << 0, UNCLOAK_MOVE = 1u << 1, UNCLOAK_UNLOAD = 1u << 2, UNCLOAK_INFILTRATE = 1u << 3,
                 UNCLOAK_DEMOLISH = 1u << 4, UNCLOAK_LOAD = 1u << 5, UNCLOAK_HEAL = 1u << 6, UNCLOAK_DOCK = 1u << 7 };


enum TargetRelation { REL_ENEMY = 0, REL_ALLY = 1 };


enum RampState { RAMP_CLOSED = 0, RAMP_OPENING = 1, RAMP_OPEN = 2, RAMP_CLOSING = 3 };


enum Stance { STANCE_HOLD_FIRE = 0, STANCE_RETURN_FIRE, STANCE_DEFEND, STANCE_ATTACK_ANYTHING };


struct QueuedOrder {
    enum Kind { MOVE = 0, ATTACK_MOVE, ATTACK, GUARD, HARVEST };
    int32_t kind = MOVE;
    CPos cell;
    int32_t target = -1;
    int32_t near_enough = 8;
    bool force = false;
};


enum DamageType { DAMAGE_DEFAULT = 0, DAMAGE_BULLET, DAMAGE_SMALL_EXPLOSION, DAMAGE_EXPLOSION, DAMAGE_FIRE,
                  DAMAGE_ELECTRICITY, DAMAGE_CRUSHED, NUM_DAMAGE_TYPES };


struct ExtraWarhead {
    int32_t delay = 0;
    WDist spread = 43;
    int32_t damage = 0;
    int32_t falloff[8] = {100, 37, 14, 5, 0, 0, 0, 0};
    int32_t falloff_steps = 5;
    int32_t versus[NUM_ARMOR] = {100, 100, 100, 100, 100, 100};
    uint32_t valid_targets = 0;
    uint32_t invalid_targets = 0;
    bool trigger_prone = false;
    int32_t prone_damage = 100;
};


struct DestroyResourceWarhead {
    int32_t delay = 0;
    int32_t size = 0;
};


constexpr int MAX_IMPACT_EFFECTS = 12;
constexpr int MAX_IMPACT_EXPLOSIONS = 6;


enum ImpactTerrain : uint32_t { IT_GROUND = 1u << 0, IT_WATER = 1u << 1, IT_AIR = 1u << 2 };
struct ImpactEffect {
    int32_t effects[MAX_IMPACT_EXPLOSIONS] = {-1, -1, -1, -1, -1, -1};
    int32_t effect_count = 0;
    int32_t sound = -1;
    int32_t sound_chance = 100;
    int32_t delay = 0;
    bool impact_actors = true;
    uint32_t valid_targets = 0;
    uint32_t invalid_targets = 0;
    uint32_t valid_terrain = 0;
    uint32_t invalid_terrain = 0;
};

struct Weapon {
    WDist range = 0;
    int32_t reload = 1;
    int32_t burst = 1;
    int32_t burst_delay = 5;
    int32_t damage = 0;


    bool damage_percent = false;
    WDist spread = 43;
    int32_t versus[NUM_ARMOR] = {100, 100, 100, 100, 100, 100};
    int32_t damage_type = DAMAGE_BULLET;
    int32_t speed = 0;
    WDist inaccuracy = 0;


    int32_t delay = 0;


    ImpactEffect impact_effects[MAX_IMPACT_EFFECTS];
    int32_t impact_effect_count = 0;
    int32_t report_sound = -1;
    WDist min_range = 0;


    int32_t falloff[8] = {100, 37, 14, 5, 0, 0, 0, 0};
    int32_t falloff_steps = 5;

    uint32_t valid_targets = 0;
    uint32_t invalid_targets = 0;

    int32_t relation = REL_ENEMY;


    bool hits_allies = false;

    bool trigger_prone = false;
    int32_t prone_damage = 100;


    int32_t zap_duration = 0;
    int32_t zap_bright = -1, zap_dim = -1;


    int32_t cluster_weapon = -1;
    int32_t cluster_count = 0;
    int8_t cluster_dx[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    int8_t cluster_dy[8] = {0, 0, 0, 0, 0, 0, 0, 0};


    bool proj_missile = false;
    WAngle missile_turn_rate = 20;
    WDist missile_range_limit = 0;
    int32_t missile_arm = 0;
    int32_t missile_lock_on_probability = 100;
    WDist missile_lock_on_inaccuracy = -1;
    WDist missile_close_enough = 298;
    int32_t missile_trail_effect = -1;
    int32_t missile_trail_interval = 2;


    int32_t smudge_type = SMUDGE_NONE;
    int32_t smudge_size = 0;
    int32_t smudge_size_inner = 0;
    int32_t smudge_chance = 100;
    uint32_t smudge_valid_targets = 0;
    uint32_t smudge_invalid_targets = 0;


    ExtraWarhead extra_warheads[4];
    int32_t extra_warhead_count = 0;
    DestroyResourceWarhead destroy_resource[6];
    int32_t destroy_resource_count = 0;
};


struct Zap {
    WVec from, to;
    int32_t weapon = -1;
    int32_t ticks = 0;
};


struct EffectSeq {
    int32_t first_frame = 0;
    int32_t length = 1;
    int32_t ticks_per_frame = 1;
};


enum QueueKind { QUEUE_BUILDING = 0, QUEUE_INFANTRY = 1, QUEUE_VEHICLE = 2, QUEUE_DEFENSE = 3,
                 QUEUE_AIRCRAFT = 4, QUEUE_SHIP = 5, NUM_QUEUES };
inline bool queue_is_structure(int32_t kind) { return kind == QUEUE_BUILDING || kind == QUEUE_DEFENSE; }


enum Notification {
    NOTIFY_BUILDING = 0,
    NOTIFY_BUILDING_IN_PROGRESS,
    NOTIFY_CONSTRUCTION_COMPLETE,
    NOTIFY_UNIT_READY,
    NOTIFY_INSUFFICIENT_FUNDS,
    NOTIFY_NO_BUILD,
    NOTIFY_CANCELLED,
    NOTIFY_NEW_OPTIONS,
    NOTIFY_LOW_POWER,
    NOTIFY_STRUCTURE_SOLD,
    NOTIFY_REPAIRING,
    NOTIFY_PRIMARY_SELECTED,
    NOTIFY_UNIT_REPAIRED,
    NOTIFY_WIN,
    NOTIFY_LOSE,
    NOTIFY_SILOS_NEEDED,
    NOTIFY_CANNOT_PLACE,
    NOTIFY_BUILDING_INFILTRATED,
    NOTIFY_CREDITS_STOLEN,

    NOTIFY_SELECT_TARGET,
    NOTIFY_INSUFFICIENT_POWER,
    NOTIFY_IRON_CHARGING,
    NOTIFY_IRON_READY,
    NOTIFY_CHRONO_CHARGING,
    NOTIFY_CHRONO_READY,
    NOTIFY_ABOMB_PREPPING,
    NOTIFY_ABOMB_READY,
    NOTIFY_ABOMB_LAUNCH_DETECTED,
    NOTIFY_SATELLITE_LAUNCHED,


    NOTIFY_BUILDING_CAPTURED,
    NOTIFY_UNIT_STOLEN,
    NOTIFY_UNIT_LOST,


    NOTIFY_PLACE_PENDING,
};


constexpr uint32_t NOTIFY_NEVER = 0xFFFFFFFFu;

enum WinState { WIN_UNDEFINED = 0, WIN_WON = 1, WIN_LOST = 2 };


struct PendingPlace {
    int32_t type = -1;
    CPos origin{0, 0};
    int32_t ticks = 0;
};

struct BuildItem {
    int32_t type = 0;
    int32_t total_cost = 0, remaining_cost = 0;
    int32_t total_time = 1, remaining_time = 1;
    int32_t slowdown = 0;
    bool started = false;
    bool paused = false;
    bool done = false;
};


constexpr int MAX_RANKS = 4;


struct RankBonus {
    int32_t firepower = 100;
    int32_t damage = 100;
    int32_t speed = 100;
    int32_t reload = 100;
};


constexpr int32_t ACTOR_EXPERIENCE_FACTOR = 100;


enum CrateActionKind {
    CRATE_CASH = 0,
    CRATE_LEVEL_UP,
    CRATE_EXPLODE,
    CRATE_HIDE_MAP,
    CRATE_HEAL,
    CRATE_REVEAL_MAP,
    CRATE_DUPLICATE,
    CRATE_UNIT,
    CRATE_BASE_BUILDER,
    NUM_CRATE_ACTIONS
};

struct CrateAction {
    int32_t kind = CRATE_CASH;
    int32_t shares = 10;
    int32_t no_base_shares = 1000;
    int32_t amount = 0;
    int32_t min_amount = 1;
    int32_t max_amount = 2;
    int32_t max_value = -1;
    int32_t max_radius = 4;
    int32_t weapon = -1;
    int32_t time_delay = 0;
    int32_t sound = -1;
    int32_t effect = -1;
    std::vector<int32_t> units;
    std::vector<std::string> factions;
    std::vector<std::string> prerequisites;
};


struct CrateSpawnerParams {
    bool enabled = false;
    int32_t crate_type = -1;
    int32_t minimum = 1, maximum = 3;
    int32_t spawn_interval = 3000, initial_delay = 1500;
    uint32_t valid_ground = 0;
};


enum BotPersonality {
    BOT_P_NORMAL = 0, BOT_P_RUSH = 1, BOT_P_TURTLE = 2, BOT_P_AIR = 3, BOT_P_NAVAL = 4,
    BOT_P_RANDOM = 5, BOT_P_COUNT = 6
};


enum BotPlan { PLAN_ECONOMY = 0, PLAN_PRESSURE = 1, PLAN_AIR_STRIKE = 2, PLAN_SIEGE = 3, PLAN_DEFEND = 4, PLAN_COUNT = 5 };

struct BotParams {

    int32_t min_excess_power = 0, max_excess_power = 200, excess_power_increment = 40, excess_power_threshold = 4;


    int32_t initial_min_refineries = 0, additional_min_refineries = 3;
    int32_t structure_inactive_delay = 125, structure_active_delay = 25, structure_random_delay = 10;
    int32_t structure_resume_delay = 1500, max_failed_placements = 3;
    int32_t min_base_radius = 2, max_base_radius = 20, max_resource_cells_to_check = 3;
    int32_t new_production_cash_threshold = 8000, new_production_chance = 50, production_min_cash = 500;

    int32_t check_best_resource_interval = 151, max_refinery_per_indice = 2;

    int32_t sell_refinery_interval = 5000, sell_refinery_too_close = 6, sell_refinery_no_resource = 12;


    int32_t resource_map_stride_radius = 8, update_resource_map_interval = 67;


    int32_t resource_map_sweep_intervals = 16;

    int32_t min_construction_yards = 2, additional_construction_yards = 0;
    int32_t build_additional_mcv_cash = 5000;
    int32_t mcv_scan_interval = 20, build_mcv_interval = 101;
    int32_t cr_min_deploy_radius = 2, cr_max_deploy_radius = 20, cr_try_maintain_range = 8;
    int32_t cr_conyard_dislike_range = 14, cr_refinery_dislike_range = 14;
    int32_t cb_min_deploy_radius = 2, cb_max_deploy_radius = 20;

    int32_t unit_feedback_time = 30, unit_min_cash = 500;


    int32_t initial_harvesters = 3, scan_idle_harvesters_interval = 50;
    int32_t scan_low_effect_interval = 433, resource_cells_per_harvester = 4;
    int32_t harvester_enemy_avoidance = 10;

    int32_t squad_size = 40, squad_size_random_bonus = 30, assign_roles_interval = 50, rush_interval = 600;
    int32_t attack_force_interval = 75, min_attack_force_delay = 0, rush_scan_radius = 15;
    int32_t protect_unit_scan_radius = 15, idle_scan_radius = 10, danger_scan_radius = 10, attack_scan_radius = 12;
    int32_t protection_scan_radius = 12;


    std::vector<int32_t> building_fraction, building_limit, building_delay, unit_share, unit_limit;


    int32_t personality = BOT_P_NORMAL;
    int32_t strategy_interval = 200;
    int32_t plan_weight[PLAN_COUNT] = {100, 100, 100, 100, 100};

    int32_t threat_map_interval = 97, threat_map_side = 6;

    int32_t target_value_weight = 100, target_distance_bias = 8, target_threat_weight = 30;

    int32_t sp_scan_interval = 100;
    int32_t sp_coarse_step = 5, sp_fine_step = 2, sp_check_radius = 7;
    int32_t sp_own_penalty = 10;
    int32_t nuke_min_attractiveness = 3000;
    int32_t iron_min_attractiveness = 2000;
    int32_t chrono_min_attractiveness = 2500;

    int32_t air_squad_size = 3;
    int32_t air_danger_radius = 10;
    int32_t aa_per_unit = 3;

    int32_t raid_squad_size = 4, raid_interval = 1500;
    int32_t siege_range_percent = 85;
    int32_t first_attack_tick = 0;
};

struct BotSquad {


    enum Type { ASSAULT, RUSH, PROTECTION, AIR, RAID };
    enum State { IDLE, ATTACK_MOVE, ATTACK, FLEE };
    Type type = ASSAULT;
    State state = IDLE;
    std::vector<int32_t> units;
    int32_t target = -1;
    int32_t leader = -1;
    uint32_t last_updated = 0;
    CPos last_leader_cell{-1, -1};
    int32_t last_target = -1;
    int32_t backoff = 4;
    bool dead = false;
};


struct BotResourceIndice {
    int32_t ix = 0, iy = 0;
    CPos center{0, 0};
    CPos res_center{0, 0};
    int32_t res_cells = 0;
    int32_t refineries = 0;
    int32_t harvesters = 0;
    int32_t enemy_units = 0, enemy_bases = 0;
    int32_t friendly_units = 0, friendly_bases = 0;
};


struct BotActiveMcv {
    int32_t id = -1;
    CPos dest{-1, -1};
    CPos check_spot{-1, -1};
    int32_t scans = 0;
};


struct BotRefineryRequest {
    int32_t mcv_id = -1;
    CPos conyard{-1, -1};
    CPos resource{-1, -1};
};

struct BotState {
    bool enabled = false;
    BotParams p;

    int32_t wait_ticks_q[2] = {0, 0}, fail_count_q[2] = {0, 0}, fail_retry_q[2] = {0, 0};
    int32_t builder_index = 0, cached_buildings = 0, cached_bases = 0;
    int32_t min_excess_power = 0;

    int32_t unit_ticks = 0, queue_index = 0;
    std::vector<int32_t> build_requests;

    int32_t scan_idle_harvesters_ticks = 0;
    int32_t low_effect_ticks = 0;

    std::vector<BotSquad> squads;
    std::vector<int32_t> active_units;
    std::vector<int32_t> idle_base_units;
    int32_t rush_ticks = 0, assign_roles_ticks = 0, attack_force_ticks = 0, min_attack_force_delay_ticks = 0;
    int32_t respond_cooldown = 30;
    int32_t protect_from = -1;
    bool first_tick = true;

    CPos initial_base_center{-1, -1};
    int32_t mcv_ticks = 0;

    int32_t mcv_scan_ticks = 0;

    enum ExpansionMode { CHECK_RESOURCE, CHECK_BASE };
    int32_t expansion_mode = CHECK_RESOURCE;
    int32_t failed_attempts = 0, max_failed_attempts = 3;
    CPos last_failed_spot{-1, -1};
    std::vector<BotActiveMcv> active_mcvs;

    std::vector<BotResourceIndice> resource_map;
    int32_t rmap_cols = 0, rmap_rows = 0, rmap_side = 0, rmap_scan = 0;
    int32_t rmap_index = 0, rmap_ticks = 0;
    bool rmap_built = false;

    CPos resource_conyard_center{-1, -1};
    int32_t best_resource_ticks = 0, sell_refinery_ticks = 0;
    std::vector<BotRefineryRequest> requested_refineries;

    uint32_t repair_all_tick = 0;

    CPos defense_center{-1, -1};

    int32_t harv_respond_cooldown = 0;

    int32_t mcv_respond_cooldown = 0;

    int32_t rally_ticks = 0;

    int32_t personality = BOT_P_NORMAL;
    int32_t plan = PLAN_ECONOMY;
    int32_t plan_score = 0;
    int32_t strategy_ticks = 0, raid_ticks = 0, threat_ticks = 0;


    int32_t sp_wait[SP_COUNT] = {0, 0, 0, 0};


    std::vector<int32_t> threat_enemy, threat_friendly;
    int32_t tm_cols = 0, tm_rows = 0, tm_side = 0;

    int32_t stat_units_built = 0, stat_sp_fired = 0, stat_squads_sent = 0;
    uint32_t stat_first_attack = 0;
};

struct PlayerState {
    std::vector<BuildItem> queues[NUM_QUEUES];
    BotState bot;
    int32_t primary[NUM_QUEUES] = {-1, -1, -1, -1, -1, -1};
    int32_t win_state = WIN_UNDEFINED;
    bool non_combatant = false;
    std::string faction = "allies";
    uint32_t allies = 0;
    uint32_t enemies = 0;
    bool explicit_enemies = false;
    bool participant = false;
    bool had_required = false;


    int32_t power_outage = 0;


    std::vector<std::string> infiltrated_tokens;


    int32_t handicap = 0;
    SupportPowerState powers[SP_COUNT];


    PendingPlace pending[2];
};


struct UnitType {
    int32_t speed = 64;
    int32_t locomotor = LOCO_TRACKED;
    bool targetable = true;
    int32_t required_short_game = -1;
    int32_t reveal_cells = 0;
    WDist reveal_range = 0;


    WDist reveal_gap_range = 0;


    WDist creates_shroud_range = 0;


    WDist jammer_range = 0;
    bool wall = false;
    bool captures = false;
    int32_t capture_delay = 200;
    uint32_t capture_types = 0;
    bool capturable = false;
    uint32_t capturable_types = 0;


    bool instantly_repairs = false;
    bool instantly_repairable = false;


    bool repairs_bridges = false;


    int32_t demolition_delay = -1;
    bool demolishable = false;

    uint32_t infiltrates = 0;


    uint32_t infiltrates_ally = 0;


    bool disguise = false;
    bool ignores_disguise = false;

    uint32_t infil_cash = 0;
    int32_t infil_cash_percent = 50;
    int32_t infil_cash_min = -1;
    int32_t infil_cash_max = INT32_MAX;
    uint32_t infil_explore = 0;


    uint32_t infil_transform = 0;
    uint32_t infil_power = 0;
    int32_t infil_power_duration = 500;
    uint32_t infil_support = 0;
    std::string infil_proxy;


    uint32_t infil_reset = 0;
    int32_t storage = 0;
    int32_t turn_rate = 20;
    bool infantry = false;
    int32_t hp = 1;
    int32_t armor = ARMOR_NONE;
    int32_t weapon = -1;


    int32_t weapon_secondary = -1;


    int32_t weapon_tertiary = -1;
    bool turreted = false;
    int32_t turret_turn = 512;
    int32_t realign_delay = 40;


    int32_t turret_count = 1;
    int32_t turret_ox[2] = {0, 0}, turret_oy[2] = {0, 0}, turret_oz[2] = {0, 0};

    int32_t arm_turret[3] = {0, 0, 0};
    WAngle facing_tolerance = 512;


    bool leap = false;
    WDist leap_speed = 426;


    int32_t leap_lock_ticks = 0;
    WDist hit_radius = 0;


    WDist range_radius = 0;
    uint32_t target_types = 0;
    uint32_t target_types_damaged = 0;


    uint32_t target_types_underwater = 0;
    uint32_t crushes = 0;
    uint32_t crush_classes = 0;
    int32_t death_weapon = -1;
    int32_t crush_sound = -1;

    int32_t max_charges = 0;
    int32_t charge_reload = 120, initial_charge_delay = 22, charge_delay = 3;
    int32_t charge_sound = -1;

    bool takes_cover = false;
    int32_t prone_duration = 50, prone_speed = 50;

    bool no_auto_target = false;


    int32_t initial_stance = -1;
    int32_t initial_stance_ai = -1;


    uint32_t auto_target_mask = 0;
    int32_t fully_loaded_speed = 85;

    int32_t idle_anim_len[2] = {0, 0};
    int32_t idle_anim_ticks = 3;
    int32_t death_effect[NUM_DAMAGE_TYPES] = {-1, -1, -1, -1, -1, -1, -1};
    int32_t transforms_into = -1;
    int32_t transforms_dx = 0, transforms_dy = 0;
    int32_t death_sound = -1;


    int32_t damaged_sound = -1;
    int32_t destroyed_sound = -1;


    int32_t cost = 0;
    int32_t queue_kind = -1;
    int32_t palette_order = 0;
    std::vector<std::string> prerequisites;
    std::vector<std::string> prerequisites_not;


    std::vector<std::string> prerequisites_hidden;
    std::vector<std::string> provides;
    std::vector<std::string> provides_factions;


    std::vector<std::string> provides_requires;
    int32_t power = 0;


    bool building = false;
    int32_t foot_w = 0, foot_h = 0;
    std::vector<uint8_t> footprint;
    std::vector<uint8_t> build_block;
    int32_t sprite_h = 0;
    uint32_t produces = 0;
    int32_t exit_dx = 1, exit_dy = 2;
    WAngle exit_facing = 0;


    int32_t exit_ox = 0, exit_oy = 0;
    int32_t rally_dx = 1, rally_dy = 3;
    int32_t free_dx = 0, free_dy = 0;
    bool base_provider = false;
    WDist base_range = 16 * CELL;
    int32_t make_ticks = 0;
    int32_t door_len = 0;
    int32_t free_actor = -1;
    bool refinery = false;

    int32_t seeds_resource = RES_NONE;
    int32_t seed_interval = 75;
    int32_t seed_max_range = 100;

    int32_t cash_interval = 50;
    int32_t cash_amount = 0;


    bool mine = false;
    bool mine_immune = false;
    int32_t minelayer_mine = -1;


    int32_t mad_charge_delay = -1;
    int32_t mad_detonation_delay = 42;
    int32_t mad_thump_interval = 8;
    int32_t mad_thump_weapon = -1;
    int32_t mad_detonation_weapon = -1;
    int32_t mad_charge_sound = -1;
    int32_t mad_detonation_sound = -1;
    int32_t mad_driver = -1;


    bool detonate_on_deploy = false;


    int32_t chrono_charge_delay = 0;


    int32_t chrono_max_distance = 12;
    int32_t chrono_sound = -1;


    bool cloak = false;
    int32_t cloak_initial_delay = 10;
    int32_t cloak_delay = 30;
    uint32_t cloak_types = DETECT_CLOAK;
    uint32_t uncloak_on = UNCLOAK_ATTACK;
    WDist detect_range = 0;
    uint32_t detect_types = 0;


    bool cloak_pause_critical = false;
    int32_t cloak_sound = -1;


    int32_t support_power = -1;
    int32_t sp_charge = 3000;
    int32_t sp_duration = 400;
    int32_t sp_dim_w = 1, sp_dim_h = 1;
    std::vector<uint8_t> sp_footprint;
    int32_t sp_weapon = -1;
    int32_t sp_flight = 405;
    int32_t sp_sound = -1;
    int32_t sp_launch_effect = -1;
    int32_t sp_impact_effect = -1;


    WDist sp_camera_range = 0;
    int32_t sp_notify_charging = -1;
    int32_t sp_notify_ready = -1;
    int32_t sp_notify_launch = -1;


    int32_t sp_reveal_delay = 0;
    bool sp_one_shot = false;
    int32_t dock_dx = 0, dock_dy = 0;
    WAngle dock_angle = 0;
    int32_t sell_sound = -1;

    bool defense = false;


    bool gives_buildable_area = true;
    bool repairs_units = false;
    int32_t repair_hp_step = 1000, repair_units_interval = 7, repair_value_percent = 20;
    bool repairable = false;


    std::vector<int32_t> repair_actors;
    bool may_repair_at(int32_t depot_type) const {
        if (repair_actors.empty()) return true;
        for (int32_t d : repair_actors) if (d == depot_type) return true;
        return false;
    }
    int32_t ai_building_fraction = -1;
    int32_t ai_building_limit = INT32_MAX;
    int32_t ai_building_delay = 0;
    int32_t ai_unit_share = -1;
    int32_t ai_unit_limit = INT32_MAX;
    bool exclude_from_squads = false;
    int32_t build_limit = 0;
    int32_t build_duration = -1;
    int32_t build_duration_pct = 60;
    int32_t sell_value = -1;
    bool sellable = false;
    int32_t adjacent = 2;


    bool requires_base_provider = false;
    uint32_t terrain_mask = 0;
    bool scale_power_with_health = false;
    bool needs_power = false;


    bool provides_radar = false;


    bool gps_dot = false;

    int32_t repair_step = 700;
    int32_t repair_interval = 24;
    int32_t repair_percent = 20;


    int32_t xp_levels = 0;
    int32_t xp_required[MAX_RANKS] = {0, 0, 0, 0};
    RankBonus ranks[MAX_RANKS];
    int32_t gives_experience = -1;


    std::vector<std::string> producible_prereqs;
    int32_t producible_levels = 1;
    int32_t levelup_sound = -1;
    int32_t levelup_effect = -1;


    int32_t elite_heal_step = 0, elite_heal_percent = 0, elite_heal_delay = 0;
    int32_t elite_heal_start_below = 100, elite_heal_cooldown = 0;


    int32_t heal_step = 0, heal_percent = 0, heal_delay = 0;
    int32_t heal_start_below = 50, heal_damage_cooldown = 0;


    bool crate = false;
    int32_t crate_duration = 0;
    std::vector<CrateAction> crate_actions;


    bool harvester = false;
    int32_t capacity = 20;
    int32_t bale_load_delay = 4;
    int32_t bale_unload_delay = 4;
    int32_t search_from_proc = 24;
    int32_t search_from_harv = 12;
    int32_t wait_duration = 25;
    int32_t harvest_facings = 8;


    int32_t cargo_max_weight = 0;
    uint32_t cargo_types = 0;
    int32_t before_unload_delay = 8;
    int32_t between_unload_delay = 0;
    int32_t after_unload_delay = 25;
    int32_t after_load_delay = 8;
    bool cargo_eject_on_death = false;
    int32_t passenger_weight = 0;
    uint32_t passenger_type = 0;


    uint32_t ramp_terrain = 0;


    int32_t ramp_ticks = 15;


    bool aircraft = false;
    WDist cruise_altitude = 1280;
    WDist altitude_velocity = 43;
    bool can_hover = false;
    bool vtol = false;
    int32_t idle_behavior = 0;
    uint32_t landable_terrain = 0;

    int32_t ammo_max = 0;
    int32_t ammo_reload = 50;
    int32_t rearm_sound = -1;

    int32_t air_attack_type = 0;

    std::vector<int32_t> rearm_actors;


    std::vector<int32_t> land_actors;

    bool reservable = false;

    int32_t fall_rate = 43;


    bool falls_to_earth = false;
    bool fall_moves = false;
    WDist fall_velocity = 43;
    int32_t fall_max_spin = -1;
    int32_t fall_weapon = -1;
    uint32_t target_types_airborne = 0;


    bool husk = false;

    int32_t husk_actor = -1;
    int32_t husk_probability = 100;

    uint32_t husk_terrain = 0;


    int32_t capture_into = -1;

    int32_t capture_health_percent = 0;
};

struct Actor {
    int32_t id = 0;
    int32_t type = 0;
    int32_t owner = 0;
    WVec pos;
    WAngle facing = 0;
    int32_t hp = 1;
    bool alive = true;
    CPos origin;
    int32_t make_ticks = 0;
    CPos rally;
    bool repairing = false;
    int32_t repair_ticks = 0;
    int32_t sell_ticks = -1;
    bool primary = false;
    int32_t repair_depot = -1;
    int32_t repair_wait = 0;
    bool being_repaired = false;
    int32_t active_ticks = 0;
    int32_t active_anim = 0;
    bool vanished = false;


    int32_t capture_target = -1;
    int32_t capture_ticks = 0;
    int32_t capture_total = 0;
    int32_t enter_kind = ENTER_NONE;
    int32_t enter_state = ENTER_APPROACH;
    CPos enter_return;
    bool inside = false;

    int32_t demolish_ticks = -1;
    int32_t demolish_by = -1;

    int32_t disguise_type = -1;
    int32_t disguise_owner = -1;


    int32_t infiltrated_count = 0;
    int32_t infiltrated_by = -1;
    int32_t cloak_timer = 0;
    int32_t invulnerable_ticks = 0;
    int32_t chrono_return = 0;
    CPos chrono_origin{-1, -1};
    int32_t prone_ticks = 0;


    int32_t mad_ticks = -1;
    int32_t chrono_charge = 0;
    int32_t life_ticks = 0;

    int32_t experience = 0;
    int32_t level = 0;
    int32_t heal_ticks = 0;
    int32_t heal_cooldown = 0;


    int32_t self_heal_ticks = 0;
    int32_t self_heal_cooldown = 0;
    int32_t door_ticks = 0;


    int32_t last_attacker = -1;
    int32_t last_attacker_owner = -1;
    int32_t last_damage_type = DAMAGE_DEFAULT;


    int32_t transport = -1;
    int32_t enter_target = -1;
    int32_t unload_ticks = -1;
    bool unloading = false;


    bool load_lock = false;
    bool load_takeoff = false;
    int32_t after_load_ticks = -1;
    bool unload_takeoff = false;


    int32_t ramp = 0;
    int32_t ramp_frame = 0;


    int32_t faction_owner = 0;


    bool rally_set = false;
};


struct Mobile {
    CPos cell;
    CPos to_cell;


    int32_t sub = SUB_FULL;
    int32_t to_sub = SUB_FULL;
    bool in_transit = false;
    bool moving = false;
    bool arrived = false;
    int32_t field = -1;
    CPos goal;
    int32_t near_enough = 0;
    bool has_waited = false;
    int32_t wait = 0;
    bool is_blocking = false;
    int32_t near_cycles = 0;
    std::vector<CPos> detour;
    uint32_t anim = 0;
    uint32_t field_gen = 0;


    int32_t progress = 0;
    WVec transit_from;
    int32_t transit_dist = 0;


    int32_t crush_victims[CELL_SLOTS] = {-1, -1, -1, -1, -1, -1};
    int32_t crush_count = 0;

    int32_t idle_seq = -1;
    int32_t idle_delay = 0;
    uint32_t idle_anim = 0;
};


struct Combat {
    int32_t target = -1;
    bool auto_target = false;
    int32_t reload = 0;
    int32_t burst_left = 0;
    int32_t scan = 0;
    WAngle turret = 0;
    bool attack_move = false;
    CPos am_goal;
    CPos chase_cell;
    int32_t fire_anim = 0;

    int32_t charges = 0;
    int32_t recharge = 0;
    int32_t charge_wait = 0;
    int32_t guard = -1;
    CPos attack_cell{-1, -1};


    bool force_attack = false;
    int32_t since_shot = 0;


    bool barrel_flip = true;
    int32_t realign = 0;
    int32_t stance = STANCE_DEFEND;


    int32_t reload2 = 0;
    int32_t burst2 = 0;
    int32_t since_shot2 = 0;

    int32_t reload3 = 0;
    int32_t burst3 = 0;
    int32_t since_shot3 = 0;

    WAngle turret2 = 0;


    int32_t leap_ticks = -1;
    int32_t leap_len = 1;
    WVec leap_origin{0, 0};
    WVec leap_last_target{0, 0};
    CPos leap_dest_cell{-1, -1};
    int32_t leap_lock = 0;


    int32_t opp_target = -1;


    int32_t& reload_at(int k) { return k == 0 ? reload : (k == 1 ? reload2 : reload3); }
    int32_t reload_at(int k) const { return k == 0 ? reload : (k == 1 ? reload2 : reload3); }
    int32_t& burst_at(int k) { return k == 0 ? burst_left : (k == 1 ? burst2 : burst3); }
    int32_t& since_at(int k) { return k == 0 ? since_shot : (k == 1 ? since_shot2 : since_shot3); }

    WAngle& turret_at(int k) { return k == 0 ? turret : turret2; }
    WAngle turret_at(int k) const { return k == 0 ? turret : turret2; }
};


constexpr int NUM_ARMS = 3;
constexpr int MAX_TURRETS = 2;
inline int32_t arm_weapon(const UnitType& t, int k) {
    return k == 0 ? t.weapon : (k == 1 ? t.weapon_secondary : t.weapon_tertiary);
}


struct Harvest {


    enum State { IDLE, SEARCH, TO_FIELD, HARVESTING, TO_DOCK, DOCK_TURN, UNLOADING, WAIT,
                 QUEUE, EXPLORE, PARKING, PARKED };
    State state = IDLE;
    bool automated = true;
    int32_t bales = 0;
    int32_t bale_value = 0;
    CPos target;
    int32_t claim = -1;
    bool has_last = false;
    CPos last_cell;
    bool has_order = false;
    CPos order_cell;
    int32_t proc = -1;


    int32_t linked_proc = -1;
    int32_t timer = 0;
    uint32_t anim = 0;


    bool dock_held = false;


    bool park = false;
    int32_t queue_tick = -1;
    CPos wait_cell;
    bool has_wait = false;


    CPos avoid_cell;
    bool has_avoid = false;
    int32_t fails = 0;


    int32_t blind = 0;
};


constexpr WAngle AIRCRAFT_INITIAL_FACING = 0;


enum LandPhase : int32_t {
    LAND_NONE = 0,
    LAND_TOUCHDOWN = 1,
    LAND_APPROACH = 2,
    LAND_TURN = 3,
};


struct Air {
    enum State { CRUISING = 0, LANDING, LANDED, TAKING_OFF, FALLING };
    int32_t state = CRUISING;
    WDist alt = 0;
    int32_t ammo = 0;
    int32_t reload = 0;
    int32_t base = -1;
    bool returning = false;
    WVec goal;
    bool has_goal = false;
    int32_t land_at_goal = 0;
    int32_t spin = 0;
};

struct Projectile {
    WVec pos, target;
    int32_t weapon;
    int32_t owner;
    int32_t source;
    WAngle facing;
    bool alive = true;
    WDist alt = 0;
    WDist target_alt = 0;


    int32_t track_target = -1;
    int32_t distance_covered = 0;
    int32_t ticks_alive = 0;
    int32_t trail_wait = 0;


    bool force = false;
};

struct Effect {
    WVec pos;
    int32_t seq;
    int32_t frame;
    int32_t ticks;
    WAngle facing;
    WDist alt = 0;


    int32_t owner = -1;
};

struct SoundEvent {
    int32_t sound;
    WVec pos;
};


struct CashTick {
    int32_t owner;
    int32_t amount;
    WVec pos;
};


struct NukeInfo {
    int32_t owner;
    WVec target;
    int32_t ticks_left;
};


struct SmudgeInfo {
    CPos cell;
    int32_t kind;
    int32_t variant;
    int32_t depth;
};

enum Activity { ACT_NONE = 0, ACT_HARVESTING = 1, ACT_DOCKING = 2, ACT_ACTIVE = 3 };

struct RenderActor {
    int32_t id, type, owner;


    int32_t disguise_type = -1, disguise_owner = -1;
    WDist x, y;
    WAngle facing;
    WAngle turret;
    WAngle turret2;
    uint8_t moving;
    uint8_t alive;
    uint8_t firing;


    uint8_t reloading;
    uint8_t activity;
    uint8_t visible;
    uint8_t wall_mask;
    int32_t fire_frame;
    uint8_t barrel_flip;

    uint8_t leaping;
    int32_t leap_frame;


    uint8_t deploying;
    int32_t deploy_frame;


    uint8_t ramp;
    int32_t ramp_frame;
    int32_t hp_permille;
    int32_t cargo_permille;
    int32_t make_ticks;
    int32_t door_ticks;
    uint32_t anim;
    int32_t idle_seq;
    uint32_t idle_anim;
    uint8_t prone;
    uint8_t rank;
    uint8_t repairing, selling, primary;


    uint8_t unpowered;


    uint8_t cloaked;

    uint8_t demolishing;


    uint8_t demolish_left;


    uint8_t invulnerable;
    CPos rally;
    WDist altitude;
    int32_t passengers;
    int32_t cargo_max;
    int32_t ammo;
    int32_t ammo_max;
};

struct RenderSprite {
    WDist x, y;
    WDist alt;
    int32_t weapon;
    int32_t seq;
    int32_t frame;
    WAngle facing;
    int32_t owner = -1;
};


class World {
public:
    void set_map(int width, int height, const uint8_t* cost);
    void set_terrain(int width, int height, const uint8_t* terrain);
    void init_layers();

    void update_visibility(int32_t owner);
    const std::vector<uint8_t>& visibility(int32_t owner) const { return vis_[owner < 0 || owner >= MAX_PLAYERS ? 0 : owner]; }
    bool actor_visible_to(int32_t viewer, size_t i) const;
    void reveal(int32_t owner, CPos c, int32_t radius);

    bool explored(int32_t owner, CPos c) const;

    bool shroud_generated(int32_t owner, CPos c) const;


    struct Frozen {
        int32_t id;
        int32_t type;
        int32_t owner;
        CPos origin;
        WVec pos;
        WAngle facing;
        int32_t hp_permille;
        int32_t wall_mask;
    };
    const std::vector<Frozen>& frozen(int32_t viewer) const {
        return frozen_[viewer < 0 || viewer >= MAX_PLAYERS ? 0 : viewer];
    }


    bool frozen_lit(int32_t viewer, const Frozen& f) const;
    bool frozen_has(int32_t viewer, int32_t id) const;

    void apply_frozen(int32_t viewer, RenderActor* out, size_t n) const;


    bool gps_granted(int32_t viewer) const;
    bool gps_launched(int32_t owner) const {
        return owner >= 0 && owner < MAX_PLAYERS && ((gps_launched_ >> owner) & 1u) != 0;
    }
    struct GpsDotInfo { WVec pos; int32_t owner; int32_t building; };

    void gps_dots(int32_t viewer, std::vector<GpsDotInfo>& out) const;


    bool actor_jammed(int32_t id) const;

    bool radar_jammed(int32_t owner) const;

    bool has_active_radar(int32_t owner) const;
    std::vector<CPos> reveals_;
    std::vector<int32_t> reveal_ids_;
    void set_faction(int32_t owner, const std::string& f) { if (owner >= 0 && owner < MAX_PLAYERS) players_[owner].faction = f; }
    const std::string& faction(int32_t owner) const { return players_[owner < 0 || owner >= MAX_PLAYERS ? 0 : owner].faction; }

    void set_handicap(int32_t owner, int32_t percent) {
        if (owner >= 0 && owner < MAX_PLAYERS) players_[owner].handicap = percent < 0 ? 0 : (percent > 95 ? 95 : percent);
    }
    int32_t handicap(int32_t owner) const { return players_[owner < 0 || owner >= MAX_PLAYERS ? 0 : owner].handicap; }
    void order_deploy(const int32_t* ids, size_t n);
    void order_lay_mine(const int32_t* ids, size_t n);

    bool can_detonate(int32_t id) const;
    void order_detonate(const int32_t* ids, size_t n);
    bool detonating(int32_t id) const;
    bool can_chrono(int32_t id) const;
    int32_t chrono_charge_left(int32_t id) const;
    int32_t chrono_max_cells(int32_t id) const;
    bool order_chrono(const int32_t* ids, size_t n, CPos cell);
    void set_mad_driver(int32_t type, int32_t driver_type);
    void step_deploy();
    bool can_lay_mine(int32_t id) const;
    void set_minelayer(int32_t type, int32_t mine_type) {
        if (type >= 0 && type < int32_t(types_.size())) types_[size_t(type)].minelayer_mine = mine_type;
    }


    void set_capture_actor(int32_t type, int32_t into_type, int32_t health_percent) {
        if (type < 0 || type >= int32_t(types_.size())) return;
        types_[size_t(type)].capture_into = into_type;
        types_[size_t(type)].capture_health_percent = health_percent;
    }


    void set_land_actors(int32_t type, const int32_t* pads, size_t n) {
        if (type < 0 || type >= int32_t(types_.size())) return;
        types_[size_t(type)].land_actors.assign(pads, pads + n);
    }

    void set_husk_actor(int32_t type, int32_t husk_type) {
        if (type >= 0 && type < int32_t(types_.size())) types_[size_t(type)].husk_actor = husk_type;
    }

    void set_repair_actors(int32_t type, const int32_t* depots, size_t n) {
        if (type < 0 || type >= int32_t(types_.size())) return;
        types_[size_t(type)].repair_actors.assign(depots, depots + n);
    }

    bool cloaked(size_t i) const {
        const UnitType& t = types_[actors_[i].type];
        return actors_[i].alive && t.cloak && actors_[i].cloak_timer <= 0 && !cloak_paused(i);
    }

    bool cloak_paused(size_t i) const {
        const UnitType& t = types_[actors_[i].type];
        return t.cloak_pause_critical && int64_t(actors_[i].hp) * 100 < int64_t(t.hp) * 25;
    }
    bool detected_by(int32_t viewer, size_t i) const;
    void uncloak(size_t i, uint32_t reason);

    void support_power_state(int32_t owner, int32_t kind, int& available, int& ready, int& permille, int& paused) const;
    bool activate_support_power(int32_t owner, int32_t kind, CPos cell, CPos cell2);
    void order_capture(const int32_t* ids, size_t n, int32_t target_id);


    void order_enter(const int32_t* ids, size_t n, int32_t target_id, int32_t kind = ENTER_NONE);
    int32_t enter_kind_for(size_t i, size_t t) const;


    CPos enter_origin(size_t t) const;
    void step_enter();


    bool order_disguise(int32_t id, int32_t target_id);

    bool set_disguise(int32_t id, int32_t type, int32_t owner);
    void step_demolitions();

    int32_t enter_progress(int32_t id) const;
    int32_t power_outage(int32_t owner) const { return owner >= 0 && owner < MAX_PLAYERS ? players_[owner].power_outage : 0; }
    int32_t infiltrated_count(int32_t id) const { const int i = index_of(id); return i < 0 ? 0 : actors_[i].infiltrated_count; }
    int32_t infiltrated_by(int32_t id) const { const int i = index_of(id); return i < 0 ? -1 : actors_[i].infiltrated_by; }
    void step_seeds();
    void step_cash_tricklers();
    void step_cloak();
    void step_pending_mines();
    void step_pending_husks();
    void step_support_powers();


    bool type_can_gain_level(int32_t type) const { return type >= 0 && type < int32_t(types_.size()) && types_[type].xp_levels > 0; }
    int32_t max_level(int32_t type) const { return type_can_gain_level(type) ? types_[type].xp_levels : 0; }
    int32_t level_of(size_t i) const { return i < actors_.size() ? actors_[i].level : 0; }
    int32_t experience_of(size_t i) const { return i < actors_.size() ? actors_[i].experience : 0; }
    void give_experience(size_t i, int32_t amount);
    void give_levels(size_t i, int32_t levels);
    void step_self_healing();
    void step_unconditional_healing();
    const RankBonus& rank_bonus(size_t i) const;


    void set_crate_spawner(const CrateSpawnerParams& p);
    bool crates_enabled() const { return crate_p_.enabled; }
    void step_crates();
    void step_crate_pickups();
    void collect_crate(size_t ci, size_t collector);
    uint32_t crate_count() const;

    void explore_all(int32_t owner);
    void reset_exploration(int32_t owner);
    void set_owner(size_t i, int32_t owner);


    bool set_owner_id(int32_t id, int32_t owner);
    bool can_deploy(int32_t id) const;
    void set_non_combatant(int32_t owner, bool value) { if (owner >= 0 && owner < MAX_PLAYERS) players_[owner].non_combatant = value; }


    bool hostile(int32_t a, int32_t b) const {
        if (a == b || a < 0 || b < 0 || a >= MAX_PLAYERS || b >= MAX_PLAYERS) return false;
        if (players_[a].allies & (1u << b)) return false;
        if (players_[a].explicit_enemies || players_[b].explicit_enemies)
            return ((players_[a].enemies >> b) & 1u) != 0 || ((players_[b].enemies >> a) & 1u) != 0;
        if (players_[a].non_combatant || players_[b].non_combatant) return false;
        return true;
    }
    void set_enemy(int32_t a, int32_t b, bool value) {
        if (a < 0 || b < 0 || a >= MAX_PLAYERS || b >= MAX_PLAYERS) return;
        players_[a].explicit_enemies = true;
        if (value) players_[a].enemies |= 1u << b;
        else players_[a].enemies &= ~(1u << b);
    }


    bool may_attack(size_t i, size_t k, bool force) const;

    bool force_attacking(int32_t id) const;


    bool has_move_order(int32_t id) const;
    bool allied(int32_t a, int32_t b) const { return a == b || (a >= 0 && b >= 0 && a < MAX_PLAYERS && b < MAX_PLAYERS && (players_[a].allies & (1u << b))); }
    void set_alliance(int32_t a, int32_t b, bool value) {
        if (a < 0 || b < 0 || a >= MAX_PLAYERS || b >= MAX_PLAYERS) return;
        if (value) { players_[a].allies |= 1u << b; players_[b].allies |= 1u << a; }
        else { players_[a].allies &= ~(1u << b); players_[b].allies &= ~(1u << a); }
    }

    void set_conquest_victory(bool on) { conquest_victory_ = on; }

    void set_neutral_player(int32_t owner) { if (owner >= -1 && owner < MAX_PLAYERS) neutral_player_ = owner; }
    void set_win_state(int32_t owner, int32_t state) {
        if (owner < 0 || owner >= MAX_PLAYERS || players_[owner].win_state != WIN_UNDEFINED) return;
        players_[owner].win_state = state;
        notify(owner, state == WIN_WON ? NOTIFY_WIN : NOTIFY_LOSE);
    }
    int32_t speed_at(size_t i) const;
    const Map& map() const { return map_; }

    int32_t define_type(const UnitType& t);
    int32_t define_weapon(const Weapon& w);
    int32_t define_effect(const EffectSeq& e);
    const UnitType& type(int32_t id) const { return types_[id]; }
    size_t type_count() const { return types_.size(); }
    const Weapon& weapon(int32_t id) const { return weapons_[id]; }
    const EffectSeq& effect_seq(int32_t id) const { return effects_def_[id]; }


    int32_t spawn(int32_t type, int32_t owner, CPos cell, WAngle facing = -1, int32_t health_percent = 100,
                  bool airborne = false);
    int32_t spawn_building(int32_t type, int32_t owner, CPos origin, int32_t health_percent = 100);

    void order_move(const int32_t* ids, size_t n, CPos goal, int32_t near_enough = 8);
    void order_attack_move(const int32_t* ids, size_t n, CPos goal);


    void order_attack(const int32_t* ids, size_t n, int32_t target_id, bool force = false);
    void order_harvest(const int32_t* ids, size_t n, CPos cell);


    bool order_deliver(const int32_t* ids, size_t n, int32_t refinery_id);


    void order_harvesters_return_to_base(int32_t owner);

    void order_harvesters_resume(int32_t owner);
    void order_stop(const int32_t* ids, size_t n);
    void order_scatter(const int32_t* ids, size_t n);

    void queue_order(const int32_t* ids, size_t n, const QueuedOrder& o);
    void step_order_queue();
    void set_stance(int32_t id, int32_t stance);
    int32_t stance(int32_t id) const;

    int32_t reveal_source(int32_t owner, CPos c, int32_t radius);
    void remove_reveal_source(int32_t id);
    void order_guard(const int32_t* ids, size_t n, int32_t target_id);
    void order_attack_cell(const int32_t* ids, size_t n, CPos cell);


    void order_enter_transport(const int32_t* ids, size_t n, int32_t transport_id);

    void order_unload(const int32_t* ids, size_t n);
    void step_cargo();


    void step_landing_craft();


    bool ramp_should_open(size_t i) const;

    int32_t ramp_state(int32_t id) const;
    bool can_load(int32_t transport_id, int32_t passenger_id) const;

    bool load_passenger(int32_t transport_id, int32_t passenger_id);

    int32_t unload_passenger(int32_t transport_id, CPos at);


    int32_t drop_passenger(int32_t transport_id, CPos at);


    bool can_unload(int32_t transport_id) const;

    bool can_land_at(size_t i, CPos c) const;

    void cancel_unload(size_t i);

    void lock_for_pickup(size_t ti);

    void place_passenger(size_t ti, size_t pi, CPos c, int32_t sub);
    int32_t cargo_weight(int32_t transport_id) const;
    const std::vector<int32_t>& cargo_of(size_t i) const { return cargo_[i]; }
    int32_t transport_of(int32_t id) const;


    void step_aircraft(size_t i);
    void step_air_combat(size_t i);

    void air_move(size_t i, WVec goal, bool land);

    int find_rearm_base(size_t i) const;
    void air_return_to_base(size_t i);


    const std::vector<int32_t>& pads_of(const UnitType& t) const {
        return t.land_actors.empty() ? t.rearm_actors : t.land_actors;
    }

    bool pad_reserved(int32_t pad_id, int except = -1) const;


    int find_free_pad(int32_t owner, int32_t type, int prefer = -1) const;

    int32_t free_landing_pads(int32_t owner, int32_t type) const;

    void release_pad(int32_t pad_id);

    bool start_fall_to_earth(size_t i);
    void step_falling(size_t i);

    WVec dock_pos(size_t base) const;


    WAngle landing_facing(size_t i, WVec touchdown) const;


    WVec approach_point(size_t i, WVec touchdown) const;

    int pad_below(size_t i) const;

    void order_land(const int32_t* ids, size_t n, CPos cell);

    void air_take_off(size_t i);


    bool can_resupply_at(int32_t id, int32_t target_id) const;
    void order_resupply(const int32_t* ids, size_t n, int32_t target_id);
    const Air& air(size_t i) const { return airs_[i]; }
    int32_t air_altitude(int32_t id) const;

    void order_paradrop(int32_t id, CPos lz);
    void order_repair(const int32_t* ids, size_t n, int32_t depot_id);


    CPos repair_cell(size_t depot, size_t unit) const;
    bool at_repair_place(size_t depot, size_t unit) const;

    void note_damage_transition(size_t i, int32_t hp_before);
    void damage_for_test(size_t i, int32_t amount, int32_t attacker_id) {
        if (i >= actors_.size() || !actors_[i].alive) return;
        if (actors_[i].invulnerable_ticks > 0) return;
        const int32_t hp_before = actors_[i].hp;
        actors_[i].hp -= amount;
        note_damage_transition(i, hp_before);
        actors_[i].last_attacker = attacker_id;
        const int ai = index_of(attacker_id);
        actors_[i].last_attacker_owner = ai >= 0 ? actors_[ai].owner : -1;
        bot_on_attack(i, attacker_id);
        if (actors_[i].hp <= 0) kill(i, DAMAGE_EXPLOSION, attacker_id);
    }


    void destroy(int32_t id, int32_t damage_type = DAMAGE_EXPLOSION) {
        const int i = index_of(id);
        if (i >= 0) kill(size_t(i), damage_type);
    }


    void test_impact(WVec pos, int32_t weapon_id, WDist alt) {
        if (weapon_id >= 0 && size_t(weapon_id) < weapons_.size()) impact(pos, weapon_id, -1, -1, alt);
    }

    void impact_for_test(WVec pos, int32_t weapon, int32_t attacker_id = -1, int32_t attacker_owner = -1) {
        if (weapon >= 0 && weapon < int32_t(weapons_.size())) impact(pos, weapon, attacker_id, attacker_owner);
    }


    bool set_health(int32_t id, int32_t hp) {
        const int i = index_of(id);
        if (i < 0 || !actors_[i].alive) return false;
        const int32_t max_hp = std::max(1, types_[actors_[i].type].hp);
        const int32_t v = std::min(hp, max_hp);
        if (v <= 0) { kill(size_t(i), DAMAGE_EXPLOSION, actors_[i].id); return true; }
        actors_[i].hp = v;
        return true;
    }


    bool remove_actor(int32_t id) {
        const int i = index_of(id);
        if (i < 0 || !actors_[i].alive) return false;
        dispose(size_t(i));
        return true;
    }

    bool teleport(int32_t id, CPos cell);


    void set_map_terrain(CPos c, int32_t terrain);
    int32_t win_state(int32_t owner) const { return owner >= 0 && owner < MAX_PLAYERS ? players_[owner].win_state : WIN_UNDEFINED; }


    void add_smudge(CPos c, int32_t kind);
    int32_t smudge_kind(CPos c) const {
        return map_.in_bounds(c) && !smudge_kind_.empty() ? smudge_kind_[map_.index(c)] : int32_t(SMUDGE_NONE);
    }
    int32_t smudge_variant(CPos c) const {
        return map_.in_bounds(c) && !smudge_variant_.empty() ? smudge_variant_[map_.index(c)] : 0;
    }
    int32_t smudge_depth(CPos c) const {
        return map_.in_bounds(c) && !smudge_depth_.empty() ? smudge_depth_[map_.index(c)] : 0;
    }


    void set_smudge_sprites(int32_t kind, int32_t variants, int32_t depth);
    uint32_t smudge_version() const { return smudge_version_; }
    void smudges(std::vector<SmudgeInfo>& out) const;
    uint32_t smudge_count() const;


    void set_resource(CPos c, int32_t type, int32_t density);
    int32_t resource_type(CPos c) const { return map_.in_bounds(c) ? res_type_[map_.index(c)] : RES_NONE; }
    int32_t resource_density(CPos c) const { return map_.in_bounds(c) ? res_density_[map_.index(c)] : 0; }
    const std::vector<uint8_t>& resource_types() const { return res_type_; }
    const std::vector<uint8_t>& resource_densities() const { return res_density_; }
    uint32_t resource_version() const { return resource_version_; }
    bool can_harvest_cell(CPos c) const;

    int64_t credits(int32_t owner) const { return owner >= 0 && owner < MAX_PLAYERS ? credits_[owner] + resources_[owner] : 0; }
    void give_credits(int32_t owner, int64_t amount) { if (owner >= 0 && owner < MAX_PLAYERS) credits_[owner] += amount; }
    bool take_cash(int32_t owner, int64_t amount);
    void give_resources(int32_t owner, int64_t amount);
    int64_t storage_capacity(int32_t owner) const;
    int64_t storage_room(int32_t owner) const;
    void clamp_storage(int32_t owner);
    int64_t resources_stored(int32_t owner) const { return owner >= 0 && owner < MAX_PLAYERS ? resources_[owner] : 0; }

    void set_resources(int32_t owner, int64_t amount) {
        if (owner < 0 || owner >= MAX_PLAYERS) return;
        const int64_t cap = storage_capacity(owner);
        resources_[owner] = amount < 0 ? 0 : (amount > cap ? cap : amount);
    }
    int64_t cash(int32_t owner) const { return owner >= 0 && owner < MAX_PLAYERS ? credits_[owner] : 0; }


    int64_t earned(int32_t owner) const { return owner >= 0 && owner < MAX_PLAYERS ? earned_[owner] : 0; }


    bool queue_build(int32_t owner, int32_t type);
    bool cancel_build(int32_t owner, int32_t kind, int32_t type);

    bool pause_build(int32_t owner, int32_t kind, bool hold);
    bool build_paused(int32_t owner, int32_t kind) const;

    bool build_limit_reached(int32_t owner, int32_t type) const;
    const std::vector<BuildItem>& queue(int32_t owner, int32_t kind) const;
    void buildable(int32_t owner, int32_t kind, std::vector<int32_t>& out) const;


    int32_t buildable_total(int32_t owner) const;
    bool prerequisites_met(int32_t owner, int32_t type) const;

    bool item_hidden(int32_t owner, int32_t type) const;
    bool has_prerequisite(int32_t owner, const std::string& token) const;
    bool has_prerequisite(int32_t owner, const std::string& token, int depth) const;
    bool can_place(int32_t owner, int32_t type, CPos origin, std::vector<uint8_t>* cell_ok) const;


    bool footprint_clear(int32_t type, CPos origin) const;

    bool cell_clearable(CPos c, int32_t owner) const;

    bool cell_reserved(CPos c, int32_t owner, int32_t self_type, CPos self_origin) const;

    int32_t pending_place_type(int32_t owner, int32_t kind) const;
    CPos pending_place_origin(int32_t owner, int32_t kind) const;
    void cancel_pending_place(int32_t owner, int32_t kind);


    void buildable_area(int32_t owner, int32_t adjacent, std::vector<uint8_t>& out) const;
    bool place_building(int32_t owner, int32_t type, CPos origin);
    int32_t power_provided(int32_t owner) const;
    int32_t power_drained(int32_t owner) const;
    int32_t build_time(int32_t type) const;
    int32_t build_time(int32_t owner, int32_t type) const;
    bool powered(size_t i) const;
    void drain_notifications(int32_t owner, std::vector<int32_t>& out);

    int64_t sell_value(int32_t id) const;
    bool sell(int32_t id);
    bool toggle_repair(int32_t id);
    bool set_rally(int32_t id, CPos cell);
    bool set_primary(int32_t id);


    void enable_bot(int32_t owner, const BotParams& p);
    bool bot_enabled(int32_t owner) const { return owner >= 0 && owner < MAX_PLAYERS && players_[owner].bot.enabled; }
    size_t bot_squad_count(int32_t owner) const { return bot_enabled(owner) ? players_[owner].bot.squads.size() : 0; }


    int32_t bot_pick_personality() { return int32_t(rand() % uint32_t(BOT_P_RANDOM)); }

    int32_t bot_personality(int32_t owner) const { return bot_enabled(owner) ? players_[owner].bot.personality : -1; }
    int32_t bot_plan(int32_t owner) const { return bot_enabled(owner) ? players_[owner].bot.plan : -1; }
    int32_t bot_stat(int32_t owner, int32_t which) const {
        if (!bot_enabled(owner)) return 0;
        const BotState& b = players_[owner].bot;
        switch (which) {
        case 0: return b.stat_units_built;
        case 1: return b.stat_sp_fired;
        case 2: return b.stat_squads_sent;
        case 3: return int32_t(b.stat_first_attack);
        default: return 0;
        }
    }

    const BotState& bot_state(int32_t owner) const { return players_[owner < 0 || owner >= MAX_PLAYERS ? 0 : owner].bot; }
    void step_bots();
    void bot_tick(int32_t owner);
    void bot_mcv(int32_t owner);
    void bot_resource_map(int32_t owner);
    void bot_resource_map_update(int32_t owner, int32_t index);
    int32_t bot_closest_indice(int32_t owner, CPos c) const;
    void bot_best_resource_conyard(int32_t owner);
    void bot_sell_refineries(int32_t owner);

    bool bot_expansion_center(int32_t owner, size_t mcv, CPos& expand, CPos& check_spot, int64_t& attraction) const;
    bool bot_find_deploy_cell(int32_t owner, size_t mcv, CPos target, CPos& out);
    void bot_deploy_mcvs(int32_t owner, int32_t yards, int32_t mcvs);
    bool bot_has_yard_at(int32_t owner, CPos cell) const;
    const BotRefineryRequest* bot_refinery_request(int32_t owner) const;
    void bot_base_builder(int32_t owner);
    void bot_base_builder_queue(int32_t owner, int32_t kind);
    void bot_unit_builder(int32_t owner);
    void bot_harvesters(int32_t owner);
    void bot_low_effect_harvesters(int32_t owner);
    void bot_idle_harvesters(int32_t owner);
    void bot_repair(int32_t owner);
    bool bot_base_center(int32_t owner, CPos& out) const;
    uint32_t rand_peek() const { return rng_; }
    void bot_rally_points(int32_t owner);
    void bot_squads(int32_t owner);
    void bot_update_squad(int32_t owner, BotSquad& s);
    void bot_on_attack(size_t victim, int32_t attacker_id);
    int32_t bot_choose_building(int32_t owner, int32_t kind);
    bool bot_find_location(int32_t owner, int32_t type, CPos& out);


    void bot_land_reach(CPos from, std::vector<uint8_t>& out) const;
    int32_t bot_choose_unit(int32_t owner, int32_t kind);
    bool bot_can_attack(const std::vector<int32_t>& own, const std::vector<int32_t>& enemies, bool rush) const;


    static void bot_apply_personality(BotParams& p, int32_t personality);

    void bot_threat_map(int32_t owner);
    int32_t bot_threat_at(int32_t owner, CPos c, bool enemy) const;
    int32_t bot_firepower_of(size_t i) const;

    void bot_strategy(int32_t owner);
    int32_t bot_plan_score(int32_t owner, int32_t plan) const;
    int64_t bot_target_value(size_t i) const;
    int32_t bot_pick_target(int32_t owner, WVec from, int64_t radius, bool ignore_airborne) const;

    void bot_support_powers(int32_t owner);
    bool bot_sp_target(int32_t owner, int32_t kind, CPos& out, CPos& out2, int64_t& attraction) const;
    int64_t bot_sp_attraction(int32_t owner, int32_t kind, CPos c) const;

    void bot_air_squads(int32_t owner);
    void bot_update_air_squad(int32_t owner, BotSquad& s);
    void bot_raid_squads(int32_t owner);
    void bot_update_raid_squad(int32_t owner, BotSquad& s);
    int32_t bot_raid_target(int32_t owner, WVec from) const;
    bool bot_squad_siege(int32_t owner, BotSquad& s);
    int32_t bot_plan_squad_size(int32_t owner) const;
    int32_t bot_plan_sp_threshold(int32_t owner, int32_t base) const;
    int32_t bot_count_aa(int32_t owner, WVec at, int32_t radius_cells) const;
    bool bot_unit_is_siege(size_t i) const;

    void step();
    uint32_t tick() const { return tick_; }


    uint64_t state_hash() const;


    uint64_t state_hash_full();


    void set_visibility_players(uint32_t mask);
    uint32_t visibility_players() const { return vis_players_; }


    void set_fog_enabled(bool on);
    bool fog_enabled() const { return fog_enabled_; }


    void set_rng_seed(uint32_t seed);


    bool apply_order(int32_t player, const int32_t* cmd, size_t n);


    bool save(std::vector<uint8_t>& out);
    bool load(const std::vector<uint8_t>& in);
    static uint32_t state_version();


    uint64_t rules_hash() const;

    size_t actor_count() const { return actors_.size(); }
    const Actor& actor(size_t i) const { return actors_[i]; }
    const Mobile& mobile(size_t i) const { return mobiles_[i]; }
    const Combat& combat(size_t i) const { return combats_[i]; }
    const Harvest& harvest(size_t i) const { return harvests_[i]; }
    int index_of(int32_t id) const;


    bool in_world(size_t i) const { return actors_[i].alive && !actors_[i].inside && actors_[i].transport < 0; }


    void render(int32_t alpha_1024, RenderActor* out, int32_t viewer = 0) const;
    void render_sprites(int32_t alpha_1024, std::vector<RenderSprite>& out) const;

    void drain_sounds(std::vector<SoundEvent>& out);

    void drain_cash_ticks(std::vector<CashTick>& out);


    void pending_nukes(std::vector<NukeInfo>& out) const;

    const FlowFieldCache& fields() const { return fields_; }

    int32_t occupant(CPos c) const;

    int32_t occupant(CPos c, int sub) const;

    int32_t free_subcell(CPos c, int preferred, int32_t self) const;

    bool cell_empty(CPos c) const;
    uint32_t moving_count() const;
    uint32_t alive_count(int32_t owner = -1) const;
    size_t projectile_count() const { return projectiles_.size(); }

    const std::vector<Zap>& zaps() const { return zaps_; }

private:
    Map map_;
    std::vector<UnitType> types_;
    std::vector<Weapon> weapons_;
    std::vector<EffectSeq> effects_def_;
    std::vector<Actor> actors_;
    std::vector<Mobile> mobiles_;
    std::vector<Combat> combats_;
    std::vector<Harvest> harvests_;
    std::vector<Air> airs_;
    std::vector<std::vector<int32_t>> cargo_;
    std::vector<CPos> paradrop_lz_;
    std::vector<int32_t> paradrop_delay_;
    std::vector<std::vector<QueuedOrder>> order_queue_;
    std::vector<WVec> prev_pos_;
    std::vector<WAngle> prev_facing_;
    std::vector<WAngle> prev_turret_;
    std::vector<WAngle> prev_turret2_;


    std::vector<int32_t> cell_slots_;
    std::vector<int32_t> bib_owner_;
    std::unordered_map<int32_t, int> index_by_id_;
    FlowFieldCache fields_;
    std::vector<Projectile> projectiles_;
    std::vector<Effect> effects_;
    std::vector<Zap> zaps_;
    std::vector<SoundEvent> sounds_;
    std::vector<CashTick> cash_ticks_;
    std::vector<uint8_t> res_type_;
    std::vector<uint8_t> res_density_;


    std::vector<uint8_t> smudge_kind_;
    std::vector<uint8_t> smudge_variant_;
    std::vector<uint8_t> smudge_depth_;
    int32_t smudge_variants_[NUM_SMUDGE_KINDS] = {0, 1, 1};
    int32_t smudge_depths_[NUM_SMUDGE_KINDS] = {1, 1, 1};
    uint32_t smudge_version_ = 0;
    std::vector<int32_t> claims_;


    std::vector<int32_t> res_block_;
    int32_t res_block_w_ = 0, res_block_h_ = 0;
    uint32_t resource_version_ = 0;
    int64_t credits_[MAX_PLAYERS] = {};
    int64_t resources_[MAX_PLAYERS] = {};
    int64_t earned_[MAX_PLAYERS] = {};


    uint32_t silos_notified_[MAX_PLAYERS] = {NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER,
            NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER};
    uint32_t funds_notified_[MAX_PLAYERS] = {NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER,
            NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER};
    uint32_t power_notified_[MAX_PLAYERS] = {NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER,
            NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER, NOTIFY_NEVER};


    bool new_options_pending_[MAX_PLAYERS] = {};
    bool has_storage_ = false;

    int32_t power_balance_[MAX_PLAYERS] = {};
    PlayerState players_[MAX_PLAYERS];
    std::vector<int32_t> notifications_[MAX_PLAYERS];
    uint32_t tick_ = 0;
    int32_t next_id_ = 1;
    uint32_t rng_ = 0x2545F491u;


    uint32_t vis_players_ = 1;

    bool fog_enabled_ = true;
    bool conquest_victory_ = true;
    CrateSpawnerParams crate_p_;
    int32_t crate_ticks_ = 0;


    std::vector<int32_t> crate_pickups_;
    std::vector<uint16_t> detected_;

    struct PendingMine { int32_t owner; int32_t type; CPos cell; };
    std::vector<PendingMine> pending_mines_;

    struct PendingHusk { int32_t type; int32_t owner; CPos cell; WAngle facing; };
    std::vector<PendingHusk> pending_husks_;


    struct PendingNuke { int32_t owner; int32_t type; WVec target; int32_t ticks; WVec launch_pos = {}; int32_t total = 1; int32_t reveal_id = -1; };
    std::vector<PendingNuke> pending_nukes_;

    struct PendingGps { int32_t owner; int32_t ticks; };
    std::vector<PendingGps> pending_gps_;


    struct PendingImpact {
        enum Kind { DAMAGE = 0, DESTROY_RESOURCE = 1, EFFECT = 2 };
        WVec pos;
        int32_t weapon = -1;
        int32_t kind = DAMAGE;
        int32_t index = 0;
        int32_t attacker_id = -1;
        int32_t attacker_owner = -1;
        WDist alt = 0;
        int32_t ticks = 1;
        bool force = false;
    };
    std::vector<PendingImpact> pending_impacts_;
    int32_t neutral_player_ = -1;
    std::vector<uint8_t> vis_[MAX_PLAYERS];


    std::vector<uint8_t> explored_[MAX_PLAYERS];


    std::vector<uint8_t> vis_strong_;
    std::vector<uint8_t> vis_weak_;
    std::vector<uint16_t> gap_count_;


    std::vector<uint32_t> seen_mask_;


    std::vector<uint32_t> live_mask_;
    std::vector<Frozen> frozen_[MAX_PLAYERS];
    uint32_t gps_launched_ = 0;


    std::vector<int32_t> ids_scratch_;


    std::vector<uint32_t> visit_stamp_;
    std::vector<int32_t> parent_;
    std::vector<int32_t> queue_;
    uint32_t stamp_ = 0;

    uint32_t rand();
    int32_t& slot_at(int idx, int sub) { return cell_slots_[size_t(idx) * CELL_SLOTS + size_t(sub)]; }
    int32_t slot_at(int idx, int sub) const { return cell_slots_[size_t(idx) * CELL_SLOTS + size_t(sub)]; }

    bool shares_cell(int32_t type) const { return types_[type].locomotor == LOCO_FOOT && !types_[type].building; }

    int32_t type_move_class(int32_t type) const {
        return type >= 0 && type < int32_t(types_.size()) ? move_class_of(types_[size_t(type)].locomotor) : int32_t(MC_LAND);
    }
    int32_t actor_move_class(size_t i) const { return type_move_class(actors_[i].type); }


    int32_t building_move_class(const UnitType& t) const {
        return (t.terrain_mask & (1u << TER_WATER)) != 0 ? int32_t(MC_NAVAL) : int32_t(MC_LAND);
    }
    void clear_slots(size_t i);


    int32_t blocker_at(CPos c, size_t mover) const;
    CPos find_free_cell(CPos near, int32_t type = -1);


    CPos find_adjacent_cell(CPos c, int32_t type) const;


    CPos find_exit_cell(CPos c, int32_t type);
    bool cell_free(CPos c, int32_t self) const;
    bool crushable_by(int32_t blocker, size_t crusher) const;
    void step_idle(size_t i);
    bool local_repath(size_t i, const FlowField& f);
    bool adjacent_free_cell(size_t i, CPos avoid, CPos& out);
    void notify_blocker(size_t i, int32_t blocker);
    bool is_nudgeable(size_t k) const;
    bool nudge(size_t k, CPos avoid, int depth);


    void nudge_footprint(int32_t owner, int32_t type, CPos origin);

    void step_pending_places();
    bool place_building_now(int32_t owner, int32_t type, CPos origin);
    void set_move(size_t i, CPos goal, int32_t near_enough);
    void step_mobile(size_t i);
    bool step_mobile_part(size_t i, bool carry_only);
    void begin_transit(size_t i, CPos next);
    void stop(size_t i, bool arrived);
    int push_actor(const Actor& a, const Mobile& m);


    void step_combat(size_t i);
    void step_projectiles();
    void step_missile(Projectile& p);
    void step_effects();
    void step_zaps();


    int nearest_enemy_in_range(size_t i, WDist range, bool auto_scan, bool require_arc = false) const;

    bool is_idle(size_t i) const;


    bool in_firing_arc(size_t i, size_t target) const;


    bool step_opportunity_fire(size_t i);


    bool opportunity_armed(size_t i, size_t target) const;
    bool in_range(size_t i, size_t target, WDist range) const;


    void fire(size_t i, size_t target, int32_t weapon_id = -1, int32_t arm = -1, bool force = false);
    void fire_at(size_t i, WVec aim, WDist target_alt = 0, int32_t weapon_id = -1, int32_t target_actor_id = -1,
                 int32_t arm = -1, bool force = false);


    void start_leap(size_t i, size_t target);
    void step_leap(size_t i);
    void land_leap(size_t i, int target);

    int32_t armament_for(size_t i, size_t target) const;

    WDist max_weapon_range(const UnitType& t) const;


    void impact(WVec pos, int32_t weapon, int32_t attacker_id, int32_t attacker_owner, WDist alt = 0,
                int32_t depth = 0, bool force = false);


    void apply_damage_warhead(WVec pos, int32_t attacker_id, int32_t attacker_owner, WDist spread,
                               int32_t damage, const int32_t* falloff, int32_t falloff_steps,
                               const int32_t* versus, uint32_t valid_targets, uint32_t invalid_targets,
                               int32_t relation, bool hits_allies, int32_t damage_type, bool trigger_prone,
                               int32_t prone_damage, bool damage_percent = false);

    void apply_destroy_resource(WVec pos, int32_t size_cells);

    void apply_smudge_warhead(WVec pos, const Weapon& w, int32_t attacker_id);


    void queue_husk(const Actor& dead);
    void step_pending_impacts();
    void kill(size_t i, int32_t damage_type, int32_t attacker_id = -1);
    bool vt_targetable(size_t k) const;
    uint32_t target_mask(size_t k) const;
    bool weapon_hits(size_t k, const Weapon& w) const;
    void spawn_effect(WVec pos, int32_t seq, WAngle facing = 0, WDist alt = 0, int32_t owner = -1);

    void apply_effect_warhead(WVec pos, const ImpactEffect& g, int32_t attacker_id, WDist alt);

    uint32_t impact_terrain_at(WVec pos, WDist alt) const;
    void play_sound(int32_t sound, WVec pos);


    void step_harvester(size_t i);
    bool closest_harvestable(size_t i, CPos& out, bool ignore_shroud = false);
    int nearest_refinery(size_t i) const;


    int choose_refinery(size_t i) const;
    CPos dock_cell(int proc) const;

    int32_t dock_reservations(int32_t proc_id, int32_t self) const;

    int dock_holder(int32_t proc_id, int32_t self) const;

    int32_t dock_queue_rank(size_t i, int32_t proc_id) const;


    CPos side_cell(CPos anchor, CPos exclude, int32_t slot) const;
    CPos dock_queue_cell(int proc, int32_t slot) const;
    int nearest_base(size_t i) const;
    int32_t park_rank(size_t i) const;
    void release_claim(size_t i);


    bool allow_resource_at(int32_t type, CPos c) const;
    bool can_add_resource(int32_t type, CPos c) const;

    int32_t resource_value_at(CPos c) const;
    int64_t field_value(CPos c) const;
    void add_res_value(CPos c, int32_t delta);
    void rebuild_res_blocks();


    bool resource_known(int32_t owner, CPos c) const;

    bool frontier_cell(size_t i, CPos& out) const;


    int32_t level_threshold(int32_t type, int32_t level) const;
    void on_kill_experience(size_t victim, int32_t attacker_id);


    int32_t crate_shares(const CrateAction& ca, size_t collector) const;
    void run_crate_action(const CrateAction& ca, size_t collector, WVec at);
    bool spawn_crate();


    void step_production();
    void step_buildings();
    void step_repairs();
    void step_victory();
    void dispose(size_t i);
    void enter_effect(size_t i, size_t t);
    void infiltrate(size_t i, size_t t);

    void transform_captured(size_t t, int32_t owner);
    bool leave_building(size_t i, size_t t);
    void tick_item(int32_t owner, BuildItem& item);
    int find_producer(int32_t owner, int32_t kind) const;
    void notify(int32_t owner, int32_t kind);
};

}
