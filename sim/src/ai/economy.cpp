

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

    std::vector<CPos> procs;
    for (const Actor& a : actors_) {
        if (a.alive && a.owner == owner && types_[a.type].refinery && a.sell_ticks < 0) procs.push_back(a.origin);
    }
    const int32_t refineries = int32_t(procs.size());
    if (refineries <= 0) return 0;

    if (b.resource_map.empty()) return refineries;


    std::vector<uint8_t> reach;
    bot_land_reach(procs[0], reach);


    const int32_t range = b.rmap_scan + 15;
    const int64_t range2 = int64_t(range) * range;
    int64_t cells = 0;
    for (const BotResourceIndice& in : b.resource_map) {
        if (in.res_cells <= 0) continue;
        if (!map_.in_bounds(in.res_center) || !reach[size_t(map_.index(in.res_center))]) continue;
        bool near_proc = false;
        for (const CPos& c : procs) if (cell_dist_sq(in.res_center, c) <= range2) { near_proc = true; break; }
        if (!near_proc) continue;
        cells += in.res_cells;
    }
    if (cells <= 0) return 0;


    int64_t want = (cells + HARV_CELLS_PER_HARVESTER - 1) / HARV_CELLS_PER_HARVESTER;
    want = std::min<int64_t>(want, int64_t(refineries) * std::max(1, p.harvesters_per_refinery));
    want = std::min<int64_t>(want, cells / HARV_MIN_CELLS_PER_HARVESTER);
    return int32_t(std::max<int64_t>(1, want));
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


int32_t World::bot_defense_firepower(int32_t owner) const {
    int64_t sum = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].defense) continue;
        if (a.sell_ticks >= 0) continue;
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
        bool near_base = false;
        for (const Actor& own : actors_) {
            if (!own.alive || own.owner != owner || !types_[own.type].building) continue;
            if (length(e.pos - own.pos) <= r) { near_base = true; break; }
        }
        if (!near_base) continue;
        visible += bot_firepower_of(i);
    }
    const int64_t total = (visible + b.attack_sum) * std::max(0, b.p.defense_budget_percent) / 100;
    return int32_t(std::min<int64_t>(total, INT32_MAX));
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
    const bool below_base = towers * 4 < buildings;
    const bool below_budget = bot_defense_firepower(owner) < bot_defense_budget(owner);
    if (!below_base && !below_budget) return -1;

    const bool air = bot_enemy_has_air(owner);


    int32_t want_role = have[DEF_ANTI_ARMOR] < have[DEF_ANTI_INFANTRY] ? DEF_ANTI_ARMOR : DEF_ANTI_INFANTRY;


    const int64_t seen_total = int64_t(b.counter_class[0]) + b.counter_class[1] + b.counter_class[2];
    const bool air_heavy = seen_total > 0 && int64_t(b.counter_class[2]) * 100 >= seen_total * 30;
    const int32_t aa_div = air_heavy ? 2 : 3;
    if (air && have[DEF_ANTI_AIR] * aa_div < towers + 1) want_role = DEF_ANTI_AIR;

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
            if (role == DEF_ANTI_AIR && !air) continue;
            if (pass == 0 && role != want_role) continue;


            if (best < 0 || count[size_t(t)] < count[size_t(best)]) best = t;
        }
        if (best >= 0) return best;
    }
    return -1;
}


void World::bot_log_attack(int32_t owner, size_t victim, size_t attacker) {
    BotState& b = players_[size_t(owner)].bot;
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

}
