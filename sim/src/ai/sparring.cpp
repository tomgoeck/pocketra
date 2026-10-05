

#include <algorithm>
#include <climits>

#include "ra/sim.h"

namespace ra {

namespace {

constexpr int32_t SP_ORDER_INTERVAL = 25;
constexpr int32_t SP_WAVE_REORDER = 125;
constexpr int32_t SP_HOME_CELLS = 22;
constexpr int32_t SP_SURPLUS_CASH = 2500;
constexpr int32_t SP_TEMPO_INTERVAL = 25;
constexpr uint32_t SP_MINUTE_4 = 6000, SP_MINUTE_8 = 12000, SP_MINUTE_12 = 18000;

int64_t sp_cell_d2(CPos a, CPos b) {
    const int64_t dx = a.x - b.x, dy = a.y - b.y;
    return dx * dx + dy * dy;
}


enum SpRole { SP_POWER, SP_REFINERY, SP_BARRACKS, SP_FACTORY, SP_DEPOT, SP_RADAR, SP_ROLES };

int32_t sp_role_of(const UnitType& t) {
    if (!t.building || t.defense) return -1;
    if (t.refinery) return SP_REFINERY;
    if ((t.produces & (1u << QUEUE_VEHICLE)) != 0) return SP_FACTORY;
    if ((t.produces & (1u << QUEUE_INFANTRY)) != 0) return SP_BARRACKS;
    if (t.repairs_units) return SP_DEPOT;
    if (t.provides_radar) return SP_RADAR;
    if (t.power > 0) return SP_POWER;
    return -1;
}

}


void World::bot_tempo_tick(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;


    const uint32_t at = tick_ + 1;
    const bool snap = at == SP_MINUTE_4 || at == SP_MINUTE_8 || at == SP_MINUTE_12;
    if (!snap && tick_ % uint32_t(SP_TEMPO_INTERVAL) != 0) return;
    int32_t harvesters = 0, refineries = 0;
    bool barracks = false, factory = false, radar = false;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[size_t(a.type)];
        if (t.harvester) ++harvesters;
        if (!t.building) continue;
        if (t.refinery) ++refineries;
        if ((t.produces & (1u << QUEUE_INFANTRY)) != 0) barracks = true;
        if ((t.produces & (1u << QUEUE_VEHICLE)) != 0) factory = true;
        if (t.provides_radar) radar = true;
    }
    b.stat_harv_now = harvesters;
    b.stat_refineries_now = refineries;
    const int32_t now = std::max(1, int32_t(tick_));
    if (refineries >= 1 && b.stat_t_refinery == 0) b.stat_t_refinery = now;
    if (refineries >= 2 && b.stat_t_refinery2 == 0) b.stat_t_refinery2 = now;
    if (barracks && b.stat_t_barracks == 0) b.stat_t_barracks = now;
    if (factory && b.stat_t_factory == 0) b.stat_t_factory = now;
    if (radar && b.stat_t_radar == 0) b.stat_t_radar = now;
    if (tick_ % uint32_t(SP_TEMPO_INTERVAL) == 0) {
        b.stat_tempo_cash_sum += credits(owner);
        ++b.stat_tempo_cash_samples;
    }
    if (!snap) return;
    const int32_t army = bot_stat_army_value(owner);
    if (at == SP_MINUTE_4) { b.stat_army_at[0] = army; b.stat_harv_at[0] = harvesters; }
    if (at == SP_MINUTE_8) {
        b.stat_army_at[1] = army;
        b.stat_harv_at[1] = harvesters;
        b.stat_earned_at8 = int32_t(std::min<int64_t>(earned(owner), INT32_MAX));
    }
    if (at == SP_MINUTE_12) { b.stat_army_at[2] = army; b.stat_waves_at12 = b.stat_squads_sent; }
}


void World::bot_tempo_note_damage(size_t victim, int64_t dmg, int32_t attacker_owner, bool killed) {
    if (attacker_owner < 0 || attacker_owner >= MAX_PLAYERS) return;
    BotState& b = players_[size_t(attacker_owner)].bot;
    if (!b.enabled || victim >= actors_.size()) return;
    const Actor& v = actors_[victim];
    if (!types_[size_t(v.type)].building || types_[size_t(v.type)].husk) return;
    if (!hostile(attacker_owner, v.owner) || players_[size_t(std::clamp(v.owner, 0, MAX_PLAYERS - 1))].non_combatant) return;
    if (killed) ++b.stat_bldg_kills;
    else b.stat_bldg_damage += std::max<int64_t>(0, dmg);
}


int32_t World::bot_sparring_next_building(int32_t owner, int32_t kind) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    std::vector<int32_t> list;
    buildable(owner, kind, list);
    if (list.empty()) return -1;

    int32_t have[SP_ROLES] = {0, 0, 0, 0, 0, 0};
    int32_t towers = 0, tanks = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[size_t(a.type)];
        if (!t.building) {
            if (t.queue_kind == QUEUE_VEHICLE && t.weapon >= 0 && !t.harvester) ++tanks;
            continue;
        }
        if (t.defense) { ++towers; continue; }
        const int32_t r = sp_role_of(t);
        if (r >= 0) ++have[r];
    }
    int32_t queued_power = 0;
    for (int32_t k : {int32_t(QUEUE_BUILDING), int32_t(QUEUE_DEFENSE)}) {
        for (const BuildItem& it : players_[size_t(owner)].queues[size_t(k)]) {
            const UnitType& t = types_[size_t(it.type)];
            if (t.defense) { ++towers; continue; }
            const int32_t r = sp_role_of(t);
            if (r >= 0) ++have[r];
            queued_power += t.power;
        }
    }
    const int32_t excess = power_provided(owner) - power_drained(owner) + queued_power;


    auto pick = [&](int32_t role) {
        int32_t best = -1;
        for (int32_t t : list) {
            const UnitType& ut = types_[size_t(t)];
            if (ut.queue_kind != kind || sp_role_of(ut) != role) continue;
            if (!bot_water_building_ok(owner, t)) continue;
            if (best < 0) { best = t; continue; }
            const UnitType& bt = types_[size_t(best)];
            if (role == SP_POWER ? ut.power > bt.power : ut.cost > bt.cost) best = t;
        }
        return best;
    };

    if (kind == QUEUE_DEFENSE) {


        if (have[SP_FACTORY] < 1 || have[SP_DEPOT] < 1 || have[SP_RADAR] < 1 || towers >= p.sparring_towers) return -1;
        int32_t best = -1;
        for (int32_t t : list) {
            const UnitType& ut = types_[size_t(t)];
            if (ut.queue_kind != kind || !ut.defense || ut.weapon < 0) continue;
            if (bot_defense_role(t) == 2) continue;
            if (excess + ut.power < 0) continue;
            if (best < 0 || ut.cost > types_[size_t(best)].cost) best = t;
        }
        return best;
    }
    if (kind != QUEUE_BUILDING) return -1;


    struct Step { int32_t role, need; bool ok; };
    const bool late = tick_ >= 9000;
    const Step steps[] = {
        {SP_POWER, 1, true}, {SP_REFINERY, 1, true}, {SP_BARRACKS, 1, true}, {SP_REFINERY, 2, true},
        {SP_FACTORY, 1, true}, {SP_DEPOT, 1, true},
        {SP_REFINERY, 3, tick_ >= 6000 && tanks >= 1}, {SP_RADAR, 1, tanks >= 4 || late},
    };
    int32_t want = -1;
    for (const Step& s : steps) {
        if (!s.ok || have[s.role] >= s.need) continue;
        want = pick(s.role);
        if (want >= 0) break;
    }


    if (want < 0 && have[SP_FACTORY] == 1 && credits(owner) > SP_SURPLUS_CASH) want = pick(SP_FACTORY);
    const int32_t power = pick(SP_POWER);
    if (excess < 0 && power >= 0) return power;
    if (want >= 0 && types_[size_t(want)].power < 0 && excess + types_[size_t(want)].power < 0 && power >= 0)
        return power;
    return want;
}


int32_t World::bot_sparring_next_unit(int32_t owner, int32_t kind) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    std::vector<int32_t> list;
    buildable(owner, kind, list);
    if (list.empty()) return -1;
    int32_t harvesters = 0, refineries = 0, infantry = 0, depots = 0, factories = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[size_t(a.type)];
        if (t.harvester) ++harvesters;
        if (t.building && t.refinery) ++refineries;
        if (t.building && t.repairs_units) ++depots;
        if (t.building && (t.produces & (1u << QUEUE_VEHICLE)) != 0) ++factories;
        if (!t.building && t.queue_kind == QUEUE_INFANTRY && t.weapon >= 0) ++infantry;
    }
    for (const BuildItem& it : players_[size_t(owner)].queues[size_t(QUEUE_VEHICLE)])
        if (types_[size_t(it.type)].harvester) ++harvesters;

    if (kind == QUEUE_VEHICLE) {

        const int32_t cap = std::max(1, p.sparring_harvesters) + std::max(0, refineries - 2);
        const int32_t want = std::min(2 * refineries, cap);
        if (harvesters < want) {
            for (int32_t t : list) if (types_[size_t(t)].harvester) return t;
        }


        int32_t best = -1, best_rank = -1;
        for (int32_t t : list) {
            const UnitType& ut = types_[size_t(t)];
            if (ut.harvester || ut.transforms_into >= 0 || ut.weapon < 0) continue;
            const int32_t role = bot_role_of_type(size_t(t));
            int32_t rank = -1;
            if (role == ROLE_TANK) rank = 2;
            else if (role == ROLE_FAST && ut.cost >= 600) rank = 1;
            if (rank < 0) continue;
            if (depots < 1 && rank < 2 && ut.cost < 700) continue;
            if (best < 0 || rank > best_rank || (rank == best_rank && ut.cost > types_[size_t(best)].cost)) {
                best = t;
                best_rank = rank;
            }
        }
        return best;
    }
    if (kind == QUEUE_INFANTRY) {


        const bool surplus = factories > 0 && depots > 0 && credits(owner) > SP_SURPLUS_CASH &&
                             infantry < 3 * std::max(1, p.sparring_infantry);
        if (infantry >= p.sparring_infantry && !surplus) return -1;

        int32_t best = -1;
        for (int32_t t : list) {
            const UnitType& ut = types_[size_t(t)];
            if (ut.weapon < 0 || bot_role_of_type(size_t(t)) != ROLE_INFANTRY) continue;
            if (best < 0 || ut.cost < types_[size_t(best)].cost) best = t;
        }
        return best;
    }
    return -1;
}


void World::bot_sparring_army(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    CPos base{-1, -1};
    if (!bot_base_center(owner, base)) return;


    std::vector<size_t> army;
    int32_t vehicles = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || a.inside || a.transport >= 0) continue;
        const UnitType& t = types_[size_t(a.type)];
        if (t.building || t.husk || t.harvester || t.aircraft || t.weapon < 0 || t.transforms_into >= 0) continue;
        if (t.locomotor == LOCO_NAVAL || t.locomotor == LOCO_LCRAFT) continue;
        army.push_back(i);
        if (t.queue_kind == QUEUE_VEHICLE) ++vehicles;
    }
    b.sp_wave_units.erase(std::remove_if(b.sp_wave_units.begin(), b.sp_wave_units.end(), [&](int32_t id) {
        const int i = index_of(id);
        return i < 0 || !actors_[size_t(i)].alive || actors_[size_t(i)].owner != owner;
    }), b.sp_wave_units.end());


    if (b.protect_from >= 0) {
        const int ai = index_of(b.protect_from);
        b.protect_from = -1;
        if (ai >= 0 && actors_[size_t(ai)].alive) {
            const Actor& att = actors_[size_t(ai)];
            const CPos at = types_[size_t(att.type)].building ? att.origin : mobiles_[size_t(ai)].cell;
            b.sp_alarm = at;
            b.sp_alarm_tick = tick_;
            std::vector<int32_t> ids;
            const int64_t home2 = int64_t(SP_HOME_CELLS) * SP_HOME_CELLS;
            for (size_t i : army) {
                if (sp_cell_d2(mobiles_[i].cell, base) > home2) continue;
                if (combats_[i].target >= 0) continue;
                ids.push_back(actors_[i].id);
            }
            if (!ids.empty() && sp_cell_d2(at, base) <= home2 * 4) order_attack_move(ids.data(), ids.size(), at);
        }
    }


    bool launch = false;
    if (b.sp_wave_next == 0) {
        launch = (int32_t(tick_) >= p.sparring_first_wave_tick && vehicles >= p.sparring_first_wave_units) ||
                 (int32_t(tick_) >= p.sparring_first_wave_late && army.size() >= 3);
    } else {
        launch = tick_ >= b.sp_wave_next && army.size() >= 3;
    }
    if (launch) {
        b.sp_wave_units.clear();
        for (size_t i : army) b.sp_wave_units.push_back(actors_[i].id);
        b.sp_wave_next = tick_ + uint32_t(std::max(250, p.sparring_wave_interval));
        ++b.stat_squads_sent;
        if (b.stat_first_attack == 0) b.stat_first_attack = tick_;
    }
    if (b.sp_wave_units.empty()) return;
    if (!launch && tick_ % uint32_t(SP_WAVE_REORDER) != 0) return;


    int64_t sx = 0, sy = 0;
    int32_t n = 0;
    for (int32_t id : b.sp_wave_units) {
        const int i = index_of(id);
        if (i < 0) continue;
        sx += mobiles_[size_t(i)].cell.x;
        sy += mobiles_[size_t(i)].cell.y;
        ++n;
    }
    if (n <= 0) return;
    const CPos mid{int32_t(sx / n), int32_t(sy / n)};


    CPos goal{-1, -1};
    int32_t goal_id = -1;
    int64_t best = INT64_MAX;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner) || !types_[size_t(a.type)].building || types_[size_t(a.type)].husk) continue;
        if (!types_[size_t(a.type)].targetable || players_[size_t(std::clamp(a.owner, 0, MAX_PLAYERS - 1))].non_combatant) continue;
        if (!bot_knows(owner, i)) continue;
        const UnitType& t = types_[size_t(a.type)];
        const CPos c{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2};
        const int64_t d = sp_cell_d2(c, mid);
        if (d < best) { best = d; goal = c; goal_id = a.id; }
    }
    if (goal.x < 0) {
        for (const CPos& c : b.enemy_starts) {
            if (!map_.in_bounds(c) || explored(owner, c)) continue;
            const int64_t d = sp_cell_d2(c, base);
            if (d < best) { best = d; goal = c; }
        }
    }
    if (goal.x < 0) {
        for (size_t i = 0; i < actors_.size(); ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || !hostile(owner, a.owner) || types_[size_t(a.type)].building) continue;
            const UnitType& t = types_[size_t(a.type)];
            if (!t.targetable || t.husk || t.aircraft || a.inside || a.transport >= 0) continue;
            if (players_[size_t(std::clamp(a.owner, 0, MAX_PLAYERS - 1))].non_combatant || !bot_knows(owner, i)) continue;
            const int64_t d = sp_cell_d2(mobiles_[i].cell, mid);
            if (d < best) { best = d; goal = mobiles_[i].cell; }
        }
    }
    if (goal.x < 0 && !b.enemy_starts.empty()) goal = b.enemy_starts[size_t(tick_ / 3000) % b.enemy_starts.size()];
    if (goal.x < 0) return;


    std::vector<int32_t> march, strike;
    const int64_t near2 = int64_t(8) * 8;
    for (int32_t id : b.sp_wave_units) {
        const int i = index_of(id);
        if (i < 0) continue;
        if (!launch && (mobiles_[size_t(i)].moving || mobiles_[size_t(i)].in_transit || combats_[size_t(i)].target >= 0)) continue;
        if (goal_id >= 0 && sp_cell_d2(mobiles_[size_t(i)].cell, goal) <= near2) strike.push_back(id);
        else march.push_back(id);
    }
    if (!march.empty()) order_attack_move(march.data(), march.size(), goal);
    if (!strike.empty()) order_attack(strike.data(), strike.size(), goal_id);
}


void World::bot_sparring_harvesters(int32_t owner) {
    constexpr int32_t SP_HARV_STALL = 250;
    std::vector<int32_t> taken;
    std::vector<uint8_t> reach;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[size_t(a.type)].harvester) continue;
        const Harvest& h = harvests_[i];
        if (h.stall_ticks < SP_HARV_STALL || mobiles_[i].moving || mobiles_[i].in_transit) continue;
        if (h.state != Harvest::SEARCH && h.state != Harvest::TO_FIELD && h.state != Harvest::WAIT &&
            h.state != Harvest::IDLE) continue;
        const int proc = nearest_refinery(i);
        if (proc < 0) continue;
        bot_land_reach(dock_cell(proc), reach);
        const CPos from = mobiles_[i].cell;
        CPos best{-1, -1};
        int64_t best_d = INT64_MAX;
        for (int idx = 0; idx < map_.cells(); ++idx) {
            if (res_density_[size_t(idx)] <= 0 || !reach[size_t(idx)] || claim_taken(idx, int32_t(i))) continue;
            if (std::find(taken.begin(), taken.end(), idx) != taken.end()) continue;
            const int64_t d = sp_cell_d2(map_.cell_at(idx), from);
            if (d < best_d) { best_d = d; best = map_.cell_at(idx); }
        }
        if (best.x < 0) continue;
        taken.push_back(map_.index(best));
        const int32_t id = a.id;
        order_harvest(&id, 1, best);
    }
}


void World::bot_sparring_tick(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;


    bot_fog_tick(owner);
    bot_reaction_tick(owner);
    bot_resource_map(owner);
    bot_mcv(owner);
    bot_best_resource_conyard(owner);
    bot_rally_points(owner);
    bot_repair(owner);
    bot_harvesters(owner);
    bot_low_effect_harvesters(owner);
    bot_attack_decay(owner);
    b.build_requests.clear();
    if (b.harv_respond_cooldown > 0) --b.harv_respond_cooldown;
    if (b.mcv_respond_cooldown > 0) --b.mcv_respond_cooldown;
    if (b.respond_cooldown > 0) --b.respond_cooldown;


    for (int32_t kind : {int32_t(QUEUE_BUILDING), int32_t(QUEUE_DEFENSE)}) {
        if (find_producer(owner, kind) < 0) continue;
        const int qi = kind == QUEUE_DEFENSE ? 1 : 0;
        std::vector<BuildItem>& q = players_[size_t(owner)].queues[size_t(kind)];
        if (q.empty()) {
            if (!bot_reaction_ready(owner, kind)) continue;
            const int32_t item = bot_sparring_next_building(owner, kind);
            if (item >= 0 && queue_build(owner, item)) bot_reaction_reset(owner, kind);
        } else if (q.front().done) {
            if (!bot_reaction_ready(owner, kind)) continue;
            if (b.wait_ticks_q[qi] > 0) { --b.wait_ticks_q[qi]; continue; }
            const int32_t type = q.front().type;
            CPos loc;
            if (bot_find_location(owner, type, loc) && place_building(owner, type, loc)) {
                b.fail_count_q[qi] = 0;
                bot_reaction_reset(owner, kind);
            } else if (++b.fail_count_q[qi] >= std::max(1, p.max_failed_placements)) {
                cancel_build(owner, kind, type);
                b.fail_count_q[qi] = 0;
            } else {
                b.wait_ticks_q[qi] = 25;
            }
        }
    }

    for (int32_t kind : {int32_t(QUEUE_VEHICLE), int32_t(QUEUE_INFANTRY)}) {
        if (find_producer(owner, kind) < 0) continue;
        if (!players_[size_t(owner)].queues[size_t(kind)].empty()) continue;
        if (!bot_reaction_ready(owner, kind)) continue;
        const int32_t unit = bot_sparring_next_unit(owner, kind);
        if (unit >= 0 && queue_build(owner, unit)) {
            ++b.stat_units_built;
            ++b.stat_built_q[kind == QUEUE_VEHICLE ? BQ_VEHICLE : BQ_INFANTRY];
            bot_reaction_reset(owner, kind);
        }
    }
    if (--b.sp_ticks <= 0) {
        b.sp_ticks = SP_ORDER_INTERVAL;
        bot_sparring_army(owner);
        if (tick_ % uint32_t(SP_WAVE_REORDER) < uint32_t(SP_ORDER_INTERVAL)) bot_sparring_harvesters(owner);
    }
}

}
