

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


inline int32_t bot_table(const std::vector<int32_t>& v, size_t t, int32_t fallback) {
    return t < v.size() ? v[t] : fallback;
}

}


bool World::bot_land_isolated(int32_t owner) const {
    if (owner < 0 || owner >= MAX_PLAYERS) return false;
    if (bot_iso_tick_[owner] == tick_ + 1) return bot_iso_val_[owner] != 0;

    CPos from{-1, -1};
    if (!bot_base_center(owner, from)) {
        for (size_t i = 0; i < actors_.size(); ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || a.owner != owner) continue;
            const UnitType& t = types_[a.type];
            if (t.building || t.aircraft || t.husk || t.locomotor == LOCO_NAVAL) continue;
            from = mobiles_[i].cell;
            break;
        }
    }
    bool isolated = false;
    if (from.x >= 0 && map_.cells() > 0) {
        std::vector<uint8_t> reach;
        bot_land_reach(from, reach);
        auto reached = [&](CPos c) { return map_.in_bounds(c) && reach[size_t(map_.index(c))] != 0; };
        bool any_enemy = false, reachable = false;
        for (size_t i = 0; i < actors_.size() && !reachable; ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || !hostile(owner, a.owner)) continue;


            if (!bot_knows(owner, i)) continue;
            const UnitType& t = types_[a.type];
            if (t.husk || !t.targetable || t.aircraft) continue;
            if (t.building) {
                any_enemy = true;
                for (int y = -1; y <= t.foot_h && !reachable; ++y)
                    for (int x = -1; x <= t.foot_w && !reachable; ++x)
                        if (reached(CPos{a.origin.x + x, a.origin.y + y})) reachable = true;
                continue;
            }
            if (t.locomotor == LOCO_NAVAL) continue;
            const CPos c = mobiles_[i].cell;
            if (!map_.passable(c, MC_LAND)) continue;
            any_enemy = true;
            if (reached(c)) reachable = true;
        }


        if (bot_fogged(owner)) {
            for (const CPos& c : players_[size_t(owner)].bot.enemy_starts) {
                if (reachable) break;
                any_enemy = true;
                for (int y = -4; y <= 4 && !reachable; ++y)
                    for (int x = -4; x <= 4 && !reachable; ++x)
                        if (reached(CPos{c.x + x, c.y + y})) reachable = true;
            }
        }

        isolated = any_enemy && !reachable;
    }
    bot_iso_tick_[owner] = tick_ + 1;
    bot_iso_val_[owner] = isolated ? 1 : 0;
    return isolated;
}


int32_t World::bot_prereq_building(int32_t owner, int32_t type, const std::vector<int32_t>& buildable_list,
                                   const std::vector<int32_t>& count, int32_t depth) const {
    if (type < 0 || size_t(type) >= types_.size()) return -1;
    const BotParams& p = players_[size_t(owner)].bot.p;
    auto limit_of = [&](size_t bt) { return bot_table(p.building_limit, bt, types_[bt].ai_building_limit); };
    for (const std::string& tok : types_[size_t(type)].prerequisites) {
        if (has_prerequisite(owner, tok)) continue;
        int32_t best = -1;
        for (int32_t bt : buildable_list) {
            const UnitType& ut = types_[size_t(bt)];
            if (!ut.building) continue;
            if (std::find(ut.provides.begin(), ut.provides.end(), tok) == ut.provides.end()) continue;
            if (size_t(bt) < count.size() && count[size_t(bt)] > 0) return -1;
            if (size_t(bt) < count.size() && count[size_t(bt)] >= limit_of(size_t(bt))) continue;
            if (!bot_water_building_ok(owner, bt)) continue;
            if (best < 0 || bt < best) best = bt;
        }
        if (best >= 0 || depth <= 0) return best;

        for (size_t bt = 0; bt < types_.size(); ++bt) {
            const UnitType& ut = types_[bt];
            if (!ut.building || ut.cost <= 0 || ut.queue_kind < 0) continue;
            if (std::find(ut.provides.begin(), ut.provides.end(), tok) == ut.provides.end()) continue;
            if (std::find(buildable_list.begin(), buildable_list.end(), int32_t(bt)) != buildable_list.end()) continue;
            if (item_hidden(owner, int32_t(bt))) continue;
            if (bt < count.size() && (count[bt] > 0 || count[bt] >= limit_of(bt))) continue;
            const int32_t deeper = bot_prereq_building(owner, int32_t(bt), buildable_list, count, depth - 1);
            if (deeper >= 0) return deeper;
        }
        return -1;
    }
    return -1;
}


int32_t World::bot_mcv_prereq(int32_t owner, const std::vector<int32_t>& buildable_list,
                              const std::vector<int32_t>& count) const {
    const BotParams& p = players_[size_t(owner)].bot.p;
    int32_t yards = 0, mcvs = 0, mcv_type = -1;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building && t.base_provider) ++yards;
        else if (!t.building && t.transforms_into >= 0) ++mcvs;
    }
    if (yards <= 0 || yards >= std::max(1, p.min_construction_yards) || mcvs > 0) return -1;
    for (size_t t = 0; t < types_.size(); ++t) {
        const UnitType& ut = types_[t];
        if (ut.transforms_into >= 0 && ut.cost > 0 && types_[size_t(ut.transforms_into)].base_provider) mcv_type = int32_t(t);
    }
    if (mcv_type < 0 || prerequisites_met(owner, mcv_type)) return -1;
    return bot_prereq_building(owner, mcv_type, buildable_list, count);
}


int32_t World::bot_island_building(int32_t owner, const std::vector<int32_t>& buildable_list,
                                   const std::vector<int32_t>& count) const {
    const BotParams& p = players_[size_t(owner)].bot.p;
    auto under_limit = [&](int32_t t) {
        return size_t(t) >= count.size() ||
               count[size_t(t)] < bot_table(p.building_limit, size_t(t), types_[size_t(t)].ai_building_limit);
    };

    int32_t shipyards = 0, pads = 0;
    for (size_t t = 0; t < types_.size() && t < count.size(); ++t) {
        if (count[t] <= 0 || !types_[t].building) continue;
        if (types_[t].produces & (1u << QUEUE_SHIP)) shipyards += count[t];
        if (types_[t].produces & (1u << QUEUE_AIRCRAFT)) pads += count[t];
    }


    int32_t yard_type = -1, pad_type = -1;
    for (int32_t t : buildable_list) {
        const UnitType& ut = types_[size_t(t)];
        if (!ut.building || !under_limit(t)) continue;
        if ((ut.produces & (1u << QUEUE_SHIP)) && yard_type < 0 && bot_water_building_ok(owner, t)) yard_type = t;
        if (ut.produces & (1u << QUEUE_AIRCRAFT)) {
            if (pad_type < 0 || count[size_t(t)] < count[size_t(pad_type)] ||
                (count[size_t(t)] == count[size_t(pad_type)] && t < pad_type)) pad_type = t;
        }
    }
    if (shipyards == 0 && yard_type >= 0) return yard_type;
    if (pads == 0 && pad_type >= 0) return pad_type;


    const bool air_first = p.air_first_radar > 0;
    if (!air_first) {
        const int32_t mcv_pre = bot_mcv_prereq(owner, buildable_list, count);
        if (mcv_pre >= 0) return mcv_pre;
    }


    bool armed_buildable = false;
    int32_t prereq = -1;
    for (size_t t = 0; t < types_.size(); ++t) {
        const UnitType& ut = types_[t];
        if (ut.building || !ut.aircraft || ut.weapon < 0 || ut.queue_kind != QUEUE_AIRCRAFT) continue;
        if (bot_table(p.unit_share, t, ut.ai_unit_share) < 0) continue;
        if (prerequisites_met(owner, int32_t(t))) { armed_buildable = true; break; }
        if (prereq < 0) prereq = bot_prereq_building(owner, int32_t(t), buildable_list, count);
    }
    if (!armed_buildable && prereq >= 0) return prereq;
    if (air_first) {
        const int32_t mcv_pre = bot_mcv_prereq(owner, buildable_list, count);
        if (mcv_pre >= 0) return mcv_pre;
    }


    if (shipyards > 0) {
        bool bombard_buildable = false;
        int32_t ship_prereq = -1;
        for (size_t t = 0; t < types_.size(); ++t) {
            const UnitType& ut = types_[t];
            if (ut.building || ut.queue_kind != QUEUE_SHIP || !bot_naval_is_bombard(t)) continue;
            if (bot_table(p.unit_share, t, ut.ai_unit_share) < 0) continue;
            if (prerequisites_met(owner, int32_t(t))) { bombard_buildable = true; break; }
            if (ship_prereq < 0) ship_prereq = bot_prereq_building(owner, int32_t(t), buildable_list, count);
        }
        if (!bombard_buildable && ship_prereq >= 0) return ship_prereq;
    }
    if (!armed_buildable) return -1;


    int32_t aircraft = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.aircraft && !t.husk && t.weapon >= 0) ++aircraft;
    }
    for (const BuildItem& it : players_[size_t(owner)].queues[QUEUE_AIRCRAFT])
        if (types_[size_t(it.type)].weapon >= 0) ++aircraft;
    if (pad_type >= 0 && pads <= aircraft) return pad_type;
    return -1;
}


int32_t World::bot_island_shipyard(int32_t owner, const std::vector<int32_t>& buildable_list,
                                   const std::vector<int32_t>& count) const {
    const BotParams& p = players_[size_t(owner)].bot.p;
    for (size_t t = 0; t < types_.size() && t < count.size(); ++t)
        if (count[t] > 0 && types_[t].building && (types_[t].produces & (1u << QUEUE_SHIP))) return -1;
    for (int32_t t : buildable_list) {
        const UnitType& ut = types_[size_t(t)];
        if (!ut.building || !(ut.produces & (1u << QUEUE_SHIP))) continue;
        if (size_t(t) < count.size() &&
            count[size_t(t)] >= bot_table(p.building_limit, size_t(t), ut.ai_building_limit)) continue;
        if (bot_water_building_ok(owner, t)) return t;
    }
    return -1;
}


bool World::bot_air_first(int32_t owner) const {
    if (owner < 0 || owner >= MAX_PLAYERS) return false;
    const BotState& b = players_[size_t(owner)].bot;
    if (b.p.air_first_radar <= 0) return false;
    if (b.p.cmd_enabled && b.cmd_directive.decided &&
        (b.cmd_directive.doctrine == DOC_AIR_DOMINANCE || b.cmd_directive.doctrine == DOC_NAVAL_DOMINANCE))
        return true;
    return bot_land_isolated(owner);
}


bool World::bot_air_first_hold_towers(int32_t owner) const {
    if (!bot_air_first(owner)) return false;
    const BotState& b = players_[size_t(owner)].bot;
    if (b.last_attack_tick > 0 && int32_t(tick_) - b.last_attack_tick <= std::max(0, b.p.opening_attack_ticks))
        return false;
    bool radar = false, pad = false;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[size_t(a.type)];
        if (!t.building) continue;
        if (t.provides_radar) radar = true;
        if (t.produces & (1u << QUEUE_AIRCRAFT)) pad = true;
    }
    for (const BuildItem& it : players_[size_t(owner)].queues[QUEUE_BUILDING]) {
        const UnitType& t = types_[size_t(it.type)];
        if (t.provides_radar) radar = true;
        if (t.produces & (1u << QUEUE_AIRCRAFT)) pad = true;
    }
    if (!(radar && pad)) return true;
    return b.stat_built_q[BQ_AIRCRAFT] < b.p.air_first_aircraft;
}


int32_t World::bot_air_first_building(int32_t owner, const std::vector<int32_t>& buildable_list,
                                      const std::vector<int32_t>& count, int32_t stage) const {
    const BotParams& p = players_[size_t(owner)].bot.p;
    int32_t radars = 0, pads = 0;
    for (size_t t = 0; t < types_.size() && t < count.size(); ++t) {
        if (count[t] <= 0 || !types_[t].building) continue;
        if (types_[t].provides_radar) radars += count[t];
        if (types_[t].produces & (1u << QUEUE_AIRCRAFT)) pads += count[t];
    }
    int32_t radar_type = -1, pad_type = -1;
    for (int32_t t : buildable_list) {
        const UnitType& ut = types_[size_t(t)];
        if (!ut.building || ut.queue_kind != QUEUE_BUILDING) continue;
        if (size_t(t) < count.size() &&
            count[size_t(t)] >= bot_table(p.building_limit, size_t(t), ut.ai_building_limit)) continue;
        if (ut.provides_radar && radar_type < 0) radar_type = t;
        if ((ut.produces & (1u << QUEUE_AIRCRAFT)) && pad_type < 0) pad_type = t;
    }
    if (radars == 0) return radar_type;
    if (pads == 0) return pad_type;
    if (stage <= 0) return -1;


    {
        bool armed_buildable = false;
        int32_t prereq = -1;
        for (size_t t = 0; t < types_.size(); ++t) {
            const UnitType& ut = types_[t];
            if (ut.building || !ut.aircraft || ut.weapon < 0 || ut.queue_kind != QUEUE_AIRCRAFT) continue;
            if (bot_table(p.unit_share, t, ut.ai_unit_share) < 0) continue;
            if (prerequisites_met(owner, int32_t(t))) { armed_buildable = true; break; }
            if (prereq < 0) prereq = bot_prereq_building(owner, int32_t(t), buildable_list, count);
        }
        if (!armed_buildable && prereq >= 0) return prereq;
    }
    if (stage <= 1 || pads >= 2) return -1;
    int32_t aircraft = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[size_t(a.type)];
        if (t.aircraft && !t.husk && t.weapon >= 0) ++aircraft;
    }
    for (const BuildItem& it : players_[size_t(owner)].queues[QUEUE_AIRCRAFT])
        if (types_[size_t(it.type)].weapon >= 0) ++aircraft;
    return aircraft >= pads ? pad_type : -1;
}

}
