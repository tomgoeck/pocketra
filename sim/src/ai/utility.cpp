

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


constexpr int32_t VAL_HARVESTER = 250;
constexpr int32_t VAL_REFINERY  = 200;
constexpr int32_t VAL_POWER     = 180;
constexpr int32_t VAL_CONYARD   = 200;
constexpr int32_t VAL_PRODUCES  = 160;
constexpr int32_t VAL_DEFENSE   = 60;
constexpr int32_t VAL_WALL      = 25;

}


int64_t World::bot_target_value(size_t i) const {
    const UnitType& t = types_[actors_[i].type];
    int64_t v = t.cost > 0 ? t.cost : 100;
    if (t.harvester) v = v * VAL_HARVESTER / 100;
    if (t.refinery) v = v * VAL_REFINERY / 100;
    if (t.power > 0) v = v * VAL_POWER / 100;
    if (t.base_provider) v = v * VAL_CONYARD / 100;
    if (t.produces != 0) v = v * VAL_PRODUCES / 100;
    if (t.defense) v = v * VAL_DEFENSE / 100;
    if (t.wall) v = v * VAL_WALL / 100;
    return v;
}


int32_t World::bot_pick_target(int32_t owner, WVec from, int64_t radius, bool ignore_airborne) const {
    const BotParams& p = players_[size_t(owner)].bot.p;
    int32_t best_id = -1;
    int64_t best_score = INT64_MIN;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (!t.targetable || t.husk) continue;
        if (ignore_airborne && (target_mask(i) & TT_AIRBORNE) != 0) continue;
        const int64_t d = length(a.pos - from);
        if (radius > 0 && d > radius) continue;
        const int64_t cells = d / CELL;
        const int64_t value = bot_target_value(i);
        const CPos at = t.building ? a.origin : mobiles_[i].cell;
        const int64_t threat = bot_threat_at(owner, at, true);
        int64_t score = value * p.target_value_weight / std::max<int64_t>(1, cells + p.target_distance_bias);
        score -= threat * p.target_threat_weight / 1000;


        if (score > best_score || (score == best_score && best_id >= 0 && a.id < best_id)) {
            best_score = score;
            best_id = a.id;
        }
    }
    return best_id;
}


namespace {


struct StrategyFacts {
    int64_t credits = 0;
    int32_t refineries = 0, harvesters = 0;
    int32_t own_army = 0, enemy_army = 0;
    int32_t own_aircraft = 0, enemy_aa = 0;
    int32_t siege_units = 0;
    int32_t enemy_defenses = 0;
    int32_t base_threat = 0, base_guard = 0;
};

}


int32_t World::bot_plan_score(int32_t owner, int32_t plan) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    StrategyFacts f;
    f.credits = credits(owner);
    CPos base{-1, -1};
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.husk) continue;
        if (a.owner == owner) {
            if (t.refinery) ++f.refineries;
            if (t.harvester) ++f.harvesters;
            if (t.building && t.base_provider && base.x < 0) base = a.origin;
            if (t.aircraft) ++f.own_aircraft;
            if (!t.building && !t.harvester && t.weapon >= 0) f.own_army += t.cost;
            if (bot_unit_is_siege(i)) ++f.siege_units;
        } else if (hostile(owner, a.owner)) {
            if (t.defense) ++f.enemy_defenses;
            if (!t.building && !t.harvester && t.weapon >= 0) f.enemy_army += t.cost;

            const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
            for (int32_t wi : arms)
                if (wi >= 0 && size_t(wi) < weapons_.size() && (weapons_[size_t(wi)].valid_targets & TT_AIRBORNE)) { ++f.enemy_aa; break; }
        }
    }
    if (base.x >= 0) {
        f.base_threat = bot_threat_at(owner, base, true);
        f.base_guard = bot_threat_at(owner, base, false);
    }

    switch (plan) {
    case PLAN_ECONOMY: {

        int32_t s = std::max(0, (p.additional_min_refineries - f.refineries)) * 180;
        if (f.harvesters < p.initial_harvesters) s += (p.initial_harvesters - f.harvesters) * 140;
        if (f.credits < p.production_min_cash) s += 200;
        return std::min(900, s + 120);
    }
    case PLAN_PRESSURE: {


        if (int32_t(tick_) < p.first_attack_tick) return 0;
        const int32_t ratio = int32_t(std::clamp<int64_t>(int64_t(f.own_army) * 400 / std::max(1, f.enemy_army), 0, 800));
        return f.own_army > 0 ? ratio : 0;
    }
    case PLAN_AIR_STRIKE: {

        if (f.own_aircraft < p.air_squad_size) return 0;
        const int32_t aa_penalty = std::min(600, f.enemy_aa * 80);
        return std::max(0, 200 + f.own_aircraft * 90 - aa_penalty);
    }
    case PLAN_SIEGE: {

        if (f.siege_units <= 0) return 0;
        if (int32_t(tick_) < p.first_attack_tick) return 0;
        return std::min(800, f.enemy_defenses * 60 + f.siege_units * 50);
    }
    case PLAN_DEFEND: {

        if (f.base_threat <= 0) return 0;
        return int32_t(std::clamp<int64_t>(int64_t(f.base_threat) * 400 / std::max(1, f.base_guard), 0, 900));
    }
    default:
        return 0;
    }
}


void World::bot_strategy(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (--b.strategy_ticks > 0) return;
    b.strategy_ticks = std::max(1, b.p.strategy_interval);
    int32_t best_plan = PLAN_ECONOMY, best = INT32_MIN;
    for (int32_t plan = 0; plan < PLAN_COUNT; ++plan) {
        const int64_t raw = bot_plan_score(owner, plan);
        const int32_t s = int32_t(std::clamp<int64_t>(raw * b.p.plan_weight[plan] / 100, INT32_MIN, INT32_MAX));

        if (s > best) { best = s; best_plan = plan; }
    }
    b.plan = best_plan;
    b.plan_score = best;
}


int32_t World::bot_plan_squad_size(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    int32_t pct = 100;
    switch (b.plan) {
    case PLAN_PRESSURE:   pct = 70; break;
    case PLAN_SIEGE:      pct = 110; break;
    case PLAN_AIR_STRIKE: pct = 100; break;
    case PLAN_ECONOMY:    pct = 130; break;
    case PLAN_DEFEND:     pct = 150; break;
    default: break;
    }
    return std::max(1, b.p.squad_size * pct / 100);
}


int32_t World::bot_plan_sp_threshold(int32_t owner, int32_t base) const {
    const BotState& b = players_[size_t(owner)].bot;
    int32_t pct = 100;
    switch (b.plan) {
    case PLAN_DEFEND:   pct = 70; break;
    case PLAN_SIEGE:    pct = 75; break;
    case PLAN_PRESSURE: pct = 90; break;
    case PLAN_ECONOMY:  pct = 130; break;
    default: break;
    }
    return std::max(1, base * pct / 100);
}

}
