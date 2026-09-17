

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


constexpr int32_t HARV_CELLS_PER_HARVESTER = 18;


constexpr int32_t HARV_MIN_CELLS_PER_HARVESTER = 8;


constexpr int32_t EXPAND_MIN_RES_CELLS = 40;


constexpr int32_t BOT_ATTACK_DECAY_INTERVAL = 250;
constexpr int32_t BOT_ATTACK_DECAY_NUM = 87, BOT_ATTACK_DECAY_DEN = 100;


constexpr int32_t BOT_ATTACK_LOG_COOLDOWN = 25;
constexpr int32_t BOT_ATTACK_LOG_SHIFT = 6;


constexpr int32_t SELL_LOSS_INTERVAL = 31;
constexpr int32_t SELL_LOSS_HP_PERMILLE = 300;
constexpr int32_t SELL_LOSS_THREAT_FACTOR = 3;


enum DefenseRole { DEF_ANTI_INFANTRY = 0, DEF_ANTI_ARMOR = 1, DEF_ANTI_AIR = 2, DEF_ROLE_COUNT = 3 };

constexpr int32_t DEF_MIN_RANGE_CELLS = 4;


int64_t bot_cell_d2(CPos a, CPos b) {
    const int64_t dx = a.x - b.x, dy = a.y - b.y;
    return dx * dx + dy * dy;
}


constexpr int32_t BOT_NAVAL_BOMBARD_RANGE = 12 * CELL;


constexpr int32_t BOT_NAVAL_SCAN_INTERVAL = 251;

}


static int32_t defense_role_of(const std::vector<Weapon>& weapons, const UnitType& t) {
    const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
    int64_t vs_soft = 0, vs_hard = 0;
    for (int32_t wi : arms) {
        if (wi < 0 || size_t(wi) >= weapons.size()) continue;
        const Weapon& w = weapons[size_t(wi)];
        if ((w.valid_targets & TT_AIRBORNE) != 0) return DEF_ANTI_AIR;
        vs_soft += int64_t(w.damage) * w.versus[ARMOR_NONE];
        vs_hard += int64_t(w.damage) * w.versus[ARMOR_HEAVY];
    }
    return vs_hard > vs_soft ? DEF_ANTI_ARMOR : DEF_ANTI_INFANTRY;
}


int32_t World::bot_harvester_target(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;


    std::vector<int> procs;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& a = actors_[k];
        if (a.alive && a.owner == owner && types_[a.type].refinery && a.sell_ticks < 0) procs.push_back(int(k));
    }
    const int32_t refineries = int32_t(procs.size());
    if (refineries <= 0) return 0;
    const int64_t cap = int64_t(refineries) * std::max(1, p.harvesters_per_refinery);


    const int64_t floor_want = std::min(cap, int64_t(refineries) + std::max(0, p.harvesters_extra));

    if (b.resource_map.empty()) return int32_t(floor_want);


    std::vector<uint8_t> reach;
    bot_land_reach(dock_cell(procs[0]), reach);
    std::vector<uint8_t> more;
    for (size_t k = 1; k < procs.size(); ++k) {
        const CPos d = dock_cell(procs[k]);
        if (!map_.in_bounds(d) || reach[size_t(map_.index(d))]) continue;
        bot_land_reach(d, more);
        for (size_t c = 0; c < reach.size(); ++c) if (more[c] != 0) reach[c] = 1;
    }


    int64_t cells = 0;
    for (const BotResourceIndice& in : b.resource_map) {
        if (in.res_cells <= 0) continue;
        if (!map_.in_bounds(in.res_center) || !reach[size_t(map_.index(in.res_center))]) continue;
        cells += in.res_cells;
    }


    if (cells <= 0) return 0;


    int64_t want = (cells + HARV_CELLS_PER_HARVESTER - 1) / HARV_CELLS_PER_HARVESTER;
    want = std::min<int64_t>(want, cap);
    want = std::min<int64_t>(want, cells / HARV_MIN_CELLS_PER_HARVESTER);
    return int32_t(std::max<int64_t>(floor_want, std::max<int64_t>(1, want)));
}


int32_t World::bot_free_resource_fields(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (b.resource_map.empty()) return 0;
    CPos base{-1, -1};
    if (!bot_base_center(owner, base)) return 0;
    std::vector<uint8_t> reach;
    bot_land_reach(base, reach);
    const int64_t dislike2 = int64_t(p.cr_refinery_dislike_range) * p.cr_refinery_dislike_range;


    std::vector<CPos> counted;
    int32_t free_fields = 0;
    for (int32_t i = 0; i < int32_t(b.resource_map.size()); ++i) {
        const BotResourceIndice& in = b.resource_map[size_t(i)];
        if (in.res_cells <= 0) continue;
        if (!map_.in_bounds(in.res_center) || !reach[size_t(map_.index(in.res_center))]) continue;

        int64_t cells = 0;
        for (int32_t dy = -1; dy <= 1; ++dy) {
            for (int32_t dx = -1; dx <= 1; ++dx) {
                const int32_t nx = in.ix + dx, ny = in.iy + dy;
                if (nx < 0 || ny < 0 || nx >= b.rmap_cols || ny >= b.rmap_rows) continue;
                cells += b.resource_map[size_t(ny) * size_t(b.rmap_cols) + size_t(nx)].res_cells;
            }
        }
        if (cells <= EXPAND_MIN_RES_CELLS) continue;
        bool taken = false;
        for (const Actor& a : actors_) {
            if (!a.alive || a.owner != owner || !types_[a.type].refinery) continue;
            if (cell_dist_sq(a.origin, in.res_center) <= dislike2) { taken = true; break; }
        }
        for (const CPos& c : counted) if (cell_dist_sq(c, in.res_center) <= dislike2) { taken = true; break; }
        if (taken) continue;
        counted.push_back(in.res_center);
        ++free_fields;
    }
    return free_fields;
}


int32_t World::bot_max_conyards(int32_t owner, int32_t yards) const {
    const BotParams& p = players_[size_t(owner)].bot.p;
    const int32_t want = yards + bot_free_resource_fields(owner);
    return std::clamp(want, std::max(1, p.min_construction_yards), std::max(1, p.max_conyards));
}


int32_t World::bot_pending_cost(int32_t owner) const {
    int64_t sum = 0;
    for (int32_t k = 0; k < NUM_QUEUES; ++k)
        for (const BuildItem& it : players_[size_t(owner)].queues[size_t(k)]) sum += it.remaining_cost;
    return int32_t(std::min<int64_t>(sum, INT32_MAX));
}


int32_t World::bot_spend_surplus(int32_t owner, int32_t kind, const std::vector<int32_t>& buildable_list,
                                 const std::vector<int32_t>& count) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (p.surplus_cash <= 0) return -1;
    if (credits(owner) - bot_pending_cost(owner) <= p.surplus_cash) return -1;

    auto under_limit = [&](int32_t t) {
        const int32_t limit = size_t(t) < p.building_limit.size() ? p.building_limit[size_t(t)] : types_[size_t(t)].ai_building_limit;
        return count[size_t(t)] < limit;
    };


    auto best_of = [&](bool (*match)(const UnitType&), int32_t max_count) {
        int32_t best = -1;
        for (int32_t t : buildable_list) {
            const UnitType& ut = types_[size_t(t)];
            if (ut.queue_kind != kind || !match(ut) || !under_limit(t)) continue;
            if (max_count > 0 && count[size_t(t)] >= max_count) continue;
            if (best < 0 || count[size_t(t)] < count[size_t(best)]) best = t;
        }
        return best;
    };

    if (kind == QUEUE_DEFENSE) {


        return bot_defense_request(owner, buildable_list, count);
    }


    {
        struct M { static bool f(const UnitType& t) {
            return (t.produces & ((1u << QUEUE_INFANTRY) | (1u << QUEUE_VEHICLE))) != 0;
        } };
        const int32_t t = best_of(&M::f, 3);
        if (t >= 0) return t;
    }


    {
        bool wants_air = false;
        for (size_t t = 0; t < types_.size(); ++t) {
            if (types_[t].queue_kind != QUEUE_AIRCRAFT) continue;
            const int32_t share = t < p.unit_share.size() ? p.unit_share[t] : types_[t].ai_unit_share;
            if (share >= 0) { wants_air = true; break; }
        }
        int32_t best = -1;
        for (int32_t t : buildable_list) {
            const UnitType& ut = types_[size_t(t)];
            if (ut.queue_kind != kind || !under_limit(t)) continue;
            const bool air_pad = (ut.produces & ((1u << QUEUE_AIRCRAFT))) != 0;
            const bool plain_tech = !ut.defense && !ut.refinery && !ut.base_provider && ut.produces == 0 &&
                                    ut.power <= 0 && ut.storage <= 0 && ut.support_power < 0 && !ut.provides.empty();
            const bool tech = ut.provides_radar || ut.repairs_units || plain_tech || (air_pad && wants_air);
            if (!tech) continue;
            if (count[size_t(t)] >= 2) continue;
            if (best < 0 || count[size_t(t)] < count[size_t(best)]) best = t;
        }
        if (best >= 0) return best;
    }


    {
        struct M { static bool f(const UnitType& t) { return t.support_power >= 0; } };
        const int32_t t = best_of(&M::f, 1);
        if (t >= 0) return t;
    }

    if (has_storage_ && storage_capacity(owner) > 0 && resources_stored(owner) * 5 > storage_capacity(owner) * 4) {
        struct M { static bool f(const UnitType& t) { return t.storage > 0; } };
        const int32_t t = best_of(&M::f, 0);
        if (t >= 0) return t;
    }
    return -1;
}


int32_t World::bot_defense_firepower(int32_t owner, bool anti_air) const {
    int64_t sum = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].defense) continue;
        if (a.sell_ticks >= 0) continue;
        if ((defense_role_of(weapons_, types_[a.type]) == DEF_ANTI_AIR) != anti_air) continue;
        sum += bot_firepower_of(i);
    }
    return int32_t(std::min<int64_t>(sum, INT32_MAX));
}


int32_t World::bot_defense_budget(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    const int64_t r = int64_t(b.p.max_base_radius) * 2 * CELL;
    int64_t visible = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& e = actors_[i];
        if (!e.alive || !hostile(owner, e.owner)) continue;
        const UnitType& et = types_[e.type];
        if (et.building || et.husk || !et.targetable) continue;
        if (et.aircraft) continue;
        const int64_t fp = bot_firepower_of(i);
        if (fp <= 0) continue;
        bool near_base = false;
        for (const Actor& own : actors_) {
            if (!own.alive || own.owner != owner || !types_[own.type].building) continue;
            if (length(e.pos - own.pos) <= r) { near_base = true; break; }
        }
        if (!near_base) continue;
        visible += fp;
    }
    const int64_t total = (visible + b.attack_sum) * std::max(0, b.p.defense_budget_percent) / 100;
    return int32_t(std::min<int64_t>(total, INT32_MAX));
}


int32_t World::bot_defense_army_floor(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    if (b.p.defense_army_percent <= 0) return 0;
    int64_t army[MAX_PLAYERS] = {0};
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& e = actors_[i];
        if (!e.alive || !hostile(owner, e.owner)) continue;
        if (e.owner < 0 || e.owner >= MAX_PLAYERS) continue;
        const UnitType& et = types_[e.type];
        if (et.building || et.husk || !et.targetable || et.aircraft || et.harvester) continue;
        army[e.owner] += bot_firepower_of(i);
    }
    int64_t strongest = 0;
    for (int32_t pl = 0; pl < MAX_PLAYERS; ++pl) strongest = std::max(strongest, army[pl]);
    return int32_t(std::min<int64_t>(strongest * b.p.defense_army_percent / 100, INT32_MAX));
}


int32_t World::bot_defense_aa_target(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    if (b.p.defense_aa_max <= 0) return 0;
    if (!bot_enemy_has_air(owner)) return 0;
    int32_t planes = 0, pads = 0, towers = 0;
    for (const Actor& a : actors_) {
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (a.owner == owner) {
            if (t.building && t.defense && a.sell_ticks < 0) ++towers;
            continue;
        }
        if (!hostile(owner, a.owner) || t.husk) continue;
        if (t.building) {
            if ((t.produces & (1u << QUEUE_AIRCRAFT)) != 0 && a.sell_ticks < 0) ++pads;
        } else if (t.aircraft || t.queue_kind == QUEUE_AIRCRAFT) {
            ++planes;
        }
    }
    if (planes <= 0 && pads <= 0) return 0;
    int32_t want = 1 + planes / 2;
    want = std::clamp(want, 1, b.p.defense_aa_max);


    const int32_t third = std::max(1, (towers + 2) / 3);
    return std::min(want, third);
}


int32_t World::bot_defense_role(int32_t type) const {
    if (type < 0 || size_t(type) >= types_.size()) return DEF_ANTI_INFANTRY;
    return defense_role_of(weapons_, types_[size_t(type)]);
}


int32_t World::bot_defense_range_cells(int32_t type) const {
    if (type < 0 || size_t(type) >= types_.size()) return DEF_MIN_RANGE_CELLS;
    const UnitType& t = types_[size_t(type)];
    const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
    int32_t best = 0;
    for (int32_t wi : arms) {
        if (wi < 0 || size_t(wi) >= weapons_.size()) continue;
        best = std::max(best, weapons_[size_t(wi)].range / CELL);
    }
    return std::max(best, DEF_MIN_RANGE_CELLS);
}


void World::bot_defense_stats(int32_t owner, int32_t& aa, int32_t& spread, int32_t& uncovered) const {
    aa = 0;
    spread = 0;
    uncovered = 0;
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    struct Tower { CPos at; int32_t role; int32_t rng; };
    std::vector<Tower> towers;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].defense) continue;
        if (a.sell_ticks >= 0) continue;
        const int32_t role = defense_role_of(weapons_, types_[a.type]);
        towers.push_back({a.origin, role, bot_defense_range_cells(a.type)});
        if (role == DEF_ANTI_AIR) ++aa;
    }


    int64_t sum = 0, pairs = 0;
    for (size_t i = 0; i < towers.size(); ++i) {
        for (size_t k = i + 1; k < towers.size(); ++k) {
            if (towers[i].role != towers[k].role) continue;
            sum += isqrt(bot_cell_d2(towers[i].at, towers[k].at));
            ++pairs;
        }
    }
    if (pairs > 0) spread = int32_t(sum / pairs);


    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
        const UnitType& t = types_[a.type];
        if (t.defense) continue;
        const bool valuable = t.base_provider || t.refinery || t.power > 0 ||
                              (t.produces & ((1u << QUEUE_INFANTRY) | (1u << QUEUE_VEHICLE))) != 0;
        if (!valuable) continue;
        bool covered = false;
        for (const Tower& tw : towers) {
            if (tw.role == DEF_ANTI_AIR) continue;
            if (bot_cell_d2(tw.at, a.origin) <= int64_t(tw.rng) * tw.rng) { covered = true; break; }
        }
        if (!covered) ++uncovered;
    }
}


CPos World::bot_defense_weak_spot(int32_t owner, int32_t type) const {
    const int32_t role = bot_defense_role(type);
    std::vector<std::pair<CPos, int64_t>> towers;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].defense) continue;
        if (a.sell_ticks >= 0) continue;
        if (defense_role_of(weapons_, types_[a.type]) != role) continue;
        const int64_t r = bot_defense_range_cells(a.type);
        towers.emplace_back(a.origin, r * r);
    }
    CPos out{-1, -1};
    int32_t best = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building || a.sell_ticks >= 0) continue;
        const UnitType& t = types_[a.type];
        if (t.defense) continue;
        int32_t weight = 0;
        if (t.base_provider || t.refinery) weight = 3;
        else if ((t.produces & ((1u << QUEUE_INFANTRY) | (1u << QUEUE_VEHICLE))) != 0 || t.power > 0) weight = 2;
        else continue;
        bool covered = false;
        for (const auto& tw : towers) {
            if (bot_cell_d2(tw.first, a.origin) <= tw.second) { covered = true; break; }
        }
        if (covered) continue;

        if (weight > best || (weight == best && out.x >= 0 && map_.index(a.origin) < map_.index(out))) {
            best = weight;
            out = a.origin;
        }
    }
    return out;
}


bool World::bot_enemy_has_air(int32_t owner) const {
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (t.building) {
            if ((t.produces & (1u << QUEUE_AIRCRAFT)) != 0) return true;
        } else if (t.queue_kind == QUEUE_AIRCRAFT || (target_mask(i) & TT_AIRBORNE) != 0) {
            return true;
        }
    }
    return false;
}


int32_t World::bot_defense_request(int32_t owner, const std::vector<int32_t>& buildable_list,
                                   const std::vector<int32_t>& count) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;

    int32_t buildings = 0, towers = 0;
    int32_t have[DEF_ROLE_COUNT] = {0, 0, 0};
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
        ++buildings;
        if (!types_[a.type].defense) continue;
        ++towers;
        ++have[defense_role_of(weapons_, types_[a.type])];
    }


    int32_t per_buildings = 4;
    if (p.defense_growth_tick > 0) {
        if (tick_ >= uint32_t(p.defense_growth_tick) * 2) per_buildings = 2;
        else if (tick_ >= uint32_t(p.defense_growth_tick)) per_buildings = 3;
    }


    if (bot_opening_hold_defense(owner)) return -1;
    const bool below_base = towers * per_buildings < buildings;

    const int32_t want_aa = bot_defense_aa_target(owner);
    const int32_t ground_want = std::max(bot_defense_budget(owner), bot_defense_army_floor(owner));
    const bool below_budget = bot_defense_firepower(owner, false) < ground_want;
    const bool below_aa = have[DEF_ANTI_AIR] < want_aa;
    if (!below_base && !below_budget && !below_aa) return -1;


    if (towers >= buildings / 2 + 2) return -1;


    int32_t want_role = have[DEF_ANTI_ARMOR] < have[DEF_ANTI_INFANTRY] ? DEF_ANTI_ARMOR : DEF_ANTI_INFANTRY;
    if (below_aa) want_role = DEF_ANTI_AIR;

    auto under_limit = [&](int32_t t) {
        const int32_t limit = size_t(t) < p.building_limit.size() ? p.building_limit[size_t(t)] : types_[size_t(t)].ai_building_limit;
        return count[size_t(t)] < limit;
    };


    for (int pass = 0; pass < 2; ++pass) {
        int32_t best = -1;
        for (int32_t t : buildable_list) {
            const UnitType& ut = types_[size_t(t)];
            if (!ut.defense || ut.queue_kind != QUEUE_DEFENSE || !under_limit(t)) continue;
            const int32_t role = defense_role_of(weapons_, ut);
            if (role == DEF_ANTI_AIR && have[DEF_ANTI_AIR] >= want_aa) continue;
            if (pass == 0 && role != want_role) continue;


            if (best < 0 || count[size_t(t)] < count[size_t(best)]) best = t;
        }
        if (best >= 0) return best;
    }
    return -1;
}


void World::bot_log_attack(int32_t owner, size_t victim, size_t attacker) {
    BotState& b = players_[size_t(owner)].bot;


    b.last_attack_tick = int32_t(tick_);
    if (b.attack_log_cooldown > 0) return;
    b.attack_log_cooldown = BOT_ATTACK_LOG_COOLDOWN;
    const int32_t add = bot_firepower_of(attacker) >> BOT_ATTACK_LOG_SHIFT;
    if (add <= 0) return;
    b.attack_sum = int32_t(std::min<int64_t>(int64_t(b.attack_sum) + add, INT32_MAX));
    if (b.tm_cols <= 0 || b.tm_side <= 0) return;
    if (b.attack_heat.size() != size_t(b.tm_cols) * size_t(b.tm_rows))
        b.attack_heat.assign(size_t(b.tm_cols) * size_t(b.tm_rows), 0);
    const UnitType& vt = types_[actors_[victim].type];
    const CPos at = vt.building ? actors_[victim].origin : mobiles_[victim].cell;
    const int32_t gx = at.x / b.tm_side, gy = at.y / b.tm_side;
    if (gx < 0 || gy < 0 || gx >= b.tm_cols || gy >= b.tm_rows) return;
    int32_t& cell = b.attack_heat[size_t(gy) * size_t(b.tm_cols) + size_t(gx)];
    cell = int32_t(std::min<int64_t>(int64_t(cell) + add, INT32_MAX));
}


void World::bot_attack_decay(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (b.attack_log_cooldown > 0) --b.attack_log_cooldown;
    if (--b.attack_decay_ticks > 0) return;
    b.attack_decay_ticks = BOT_ATTACK_DECAY_INTERVAL;
    b.attack_sum = int32_t(int64_t(b.attack_sum) * BOT_ATTACK_DECAY_NUM / BOT_ATTACK_DECAY_DEN);
    for (int32_t& v : b.attack_heat) v = int32_t(int64_t(v) * BOT_ATTACK_DECAY_NUM / BOT_ATTACK_DECAY_DEN);
}


bool World::bot_attack_center(int32_t owner, CPos& out) const {
    const BotState& b = players_[size_t(owner)].bot;
    if (b.tm_cols <= 0 || b.tm_side <= 0) return false;
    if (b.attack_heat.size() != size_t(b.tm_cols) * size_t(b.tm_rows)) return false;
    int32_t best = 0;
    size_t best_i = b.attack_heat.size();
    for (size_t i = 0; i < b.attack_heat.size(); ++i) {

        if (b.attack_heat[i] > best) { best = b.attack_heat[i]; best_i = i; }
    }
    if (best_i >= b.attack_heat.size()) return false;
    const int32_t gx = int32_t(best_i % size_t(b.tm_cols)), gy = int32_t(best_i / size_t(b.tm_cols));
    out = CPos{gx * b.tm_side + b.tm_side / 2, gy * b.tm_side + b.tm_side / 2};
    return true;
}


void World::bot_sell_on_loss(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (b.p.sell_on_loss == 0) return;
    if (--b.sell_loss_ticks > 0) return;
    b.sell_loss_ticks = SELL_LOSS_INTERVAL;
    if (b.attack_sum <= 0) return;

    int32_t powers = 0;
    for (const Actor& a : actors_)
        if (a.alive && a.owner == owner && types_[a.type].building && types_[a.type].power > 0) ++powers;

    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (!t.building || t.base_provider) continue;
        if (a.sell_ticks >= 0 || a.make_ticks > 0) continue;
        if (t.power > 0 && powers <= 1) continue;
        if (t.hp <= 0 || int64_t(a.hp) * 1000 / t.hp >= SELL_LOSS_HP_PERMILLE) continue;
        const int32_t foe = bot_threat_at(owner, a.origin, true);
        const int32_t own = bot_threat_at(owner, a.origin, false);
        if (foe <= 0 || int64_t(foe) < int64_t(own) * SELL_LOSS_THREAT_FACTOR) continue;
        sell(a.id);
        return;
    }
}


int32_t World::bot_queue_kind_of(int32_t bq) {
    switch (bq) {
    case BQ_VEHICLE:  return QUEUE_VEHICLE;
    case BQ_INFANTRY: return QUEUE_INFANTRY;
    case BQ_AIRCRAFT: return QUEUE_AIRCRAFT;
    case BQ_NAVAL:    return QUEUE_SHIP;
    default:          return -1;
    }
}

int32_t World::bot_unit_queue_of(int32_t queue_kind) {
    switch (queue_kind) {
    case QUEUE_VEHICLE:  return BQ_VEHICLE;
    case QUEUE_INFANTRY: return BQ_INFANTRY;
    case QUEUE_AIRCRAFT: return BQ_AIRCRAFT;
    case QUEUE_SHIP:     return BQ_NAVAL;
    default:             return -1;
    }
}


void World::bot_queue_values(int32_t owner, int32_t (&out)[BQ_COUNT]) const {
    for (int i = 0; i < BQ_COUNT; ++i) out[i] = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building || t.husk || t.harvester || t.transforms_into >= 0) continue;
        const int32_t bq = bot_unit_queue_of(t.queue_kind);
        if (bq < 0) continue;
        out[bq] += std::max(0, t.cost);
    }
}


int32_t World::bot_queue_target(int32_t owner, int32_t bq) const {
    const BotState& b = players_[size_t(owner)].bot;
    if (bq < 0 || bq >= BQ_COUNT) return 0;
    const int32_t base = b.p.queue_budget[bq];
    if (bq != BQ_NAVAL) return std::max(0, base);
    if (b.naval_demand < 0) return std::max(0, base);
    return std::max(0, b.naval_demand);
}


bool World::bot_queue_has_order(int32_t owner, int32_t bq) const {
    const BotState& b = players_[size_t(owner)].bot;
    const int32_t kind = bot_queue_kind_of(bq);
    if (kind < 0) return false;
    for (size_t t = 0; t < types_.size(); ++t) {
        if (types_[t].queue_kind != kind) continue;
        const int32_t role = bot_role_of_type(t);
        if (role < 0 || role >= ROLE_COUNT || b.vh_orders[role] <= 0) continue;
        const int32_t share = t < b.p.unit_share.size() ? b.p.unit_share[t] : types_[t].ai_unit_share;
        if (share >= 0) return true;
    }
    return false;
}


int32_t World::bot_reserve_value(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    int64_t sum = 0;
    for (int32_t id : b.idle_base_units) {
        const int i = index_of(id);
        if (i < 0 || !actors_[size_t(i)].alive) continue;
        sum += std::max(0, types_[actors_[size_t(i)].type].cost);
    }
    return int32_t(std::min<int64_t>(sum, INT32_MAX));
}


bool World::bot_naval_is_escort(size_t t) const {
    const UnitType& ut = types_[t];
    if (ut.locomotor != LOCO_NAVAL || ut.building) return false;
    const int32_t arms[3] = {ut.weapon, ut.weapon_secondary, ut.weapon_tertiary};
    bool hits_water = false, deep = false, short_range = false;
    for (int32_t wi : arms) {
        if (wi < 0 || size_t(wi) >= weapons_.size()) continue;
        const Weapon& w = weapons_[size_t(wi)];
        if ((w.valid_targets & (TT_WATER_ACTOR | TT_SHIP | TT_SUBMARINE | TT_UNDERWATER)) == 0) continue;
        hits_water = true;
        if ((w.valid_targets & (TT_SUBMARINE | TT_UNDERWATER)) != 0) deep = true;
        if (w.range < BOT_NAVAL_BOMBARD_RANGE) short_range = true;
    }
    return hits_water && (deep || short_range);
}


bool World::bot_naval_is_bombard(size_t t) const {
    const UnitType& ut = types_[t];
    if (ut.locomotor != LOCO_NAVAL || ut.building) return false;
    if (bot_naval_is_escort(t)) return false;
    const int32_t arms[3] = {ut.weapon, ut.weapon_secondary, ut.weapon_tertiary};
    for (int32_t wi : arms) {
        if (wi < 0 || size_t(wi) >= weapons_.size()) continue;
        const Weapon& w = weapons_[size_t(wi)];
        const bool hits_ground = (w.valid_targets & (TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE | TT_VEHICLE | TT_INFANTRY)) != 0;
        if (hits_ground && w.range >= BOT_NAVAL_BOMBARD_RANGE) return true;
    }
    return false;
}


void World::bot_naval_scan(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;


    if (b.naval_scan_ticks > 0 && int32_t(tick_) < b.naval_scan_ticks) return;
    b.naval_scan_ticks = int32_t(tick_) + BOT_NAVAL_SCAN_INTERVAL;


    CPos from{-1, -1};
    int32_t range_cells = 1;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (!t.building && t.locomotor == LOCO_NAVAL && t.weapon >= 0 && from.x < 0) from = mobiles_[i].cell;
    }
    if (from.x < 0) {

        for (const Actor& a : actors_) {
            if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
            if ((types_[a.type].produces & (1u << QUEUE_SHIP)) == 0) continue;
            from = a.origin;
            break;
        }
    }
    b.naval_enemy_value = 0;
    b.naval_shore_targets = 0;
    if (from.x < 0) { b.naval_demand = 0; return; }


    for (size_t t = 0; t < types_.size(); ++t) {
        const UnitType& ut = types_[t];
        if (ut.building || ut.locomotor != LOCO_NAVAL || ut.weapon < 0) continue;
        const int32_t share = t < p.unit_share.size() ? p.unit_share[t] : ut.ai_unit_share;
        if (share < 0) continue;
        if (size_t(ut.weapon) < weapons_.size())
            range_cells = std::max(range_cells, weapons_[size_t(ut.weapon)].range / CELL);
    }

    std::vector<uint8_t> reach;
    bot_naval_reach(from, reach);
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (t.husk || !t.targetable) continue;
        const bool enemy_ship = !t.building && t.locomotor == LOCO_NAVAL;
        const CPos tc = t.building ? a.origin : mobiles_[i].cell;
        bool shootable = false;
        for (int32_t dy = -range_cells; dy <= range_cells && !shootable; ++dy) {
            for (int32_t dx = -range_cells; dx <= range_cells; ++dx) {
                const CPos c{tc.x + dx, tc.y + dy};
                if (!map_.in_bounds(c)) continue;
                if (reach[size_t(map_.index(c))]) { shootable = true; break; }
            }
        }
        if (!shootable) continue;
        if (enemy_ship) b.naval_enemy_value += std::max(0, t.cost);
        else if (t.building) ++b.naval_shore_targets;
    }


    const int32_t base = std::max(0, p.queue_budget[BQ_NAVAL]);
    if (b.naval_enemy_value <= 0 && b.naval_shore_targets <= 0) { b.naval_demand = 0; return; }
    int32_t want = base;
    if (b.naval_enemy_value > 0) {
        int32_t own[BQ_COUNT];
        bot_queue_values(owner, own);


        if (own[BQ_NAVAL] < b.naval_enemy_value) want = base * 2;
    }
    if (b.naval_shore_targets <= 0) want = std::min(want, base);
    b.naval_demand = std::clamp(want, 0, 100);
}

}
