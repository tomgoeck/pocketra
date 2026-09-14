

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


constexpr int32_t VAL_HARVESTER = 250;
constexpr int32_t VAL_REFINERY  = 200;
constexpr int32_t VAL_POWER     = 180;
constexpr int32_t VAL_CONYARD   = 200;
constexpr int32_t VAL_PRODUCES  = 160;


constexpr int32_t VAL_DEFENSE   = 0;
constexpr int32_t VAL_WALL      = 25;


constexpr int32_t ROLE_FAST_SPEED = 85;


constexpr uint32_t VH_MAX_TICKS = 6000;

constexpr uint32_t VH_FORM_TICKS = 900;

constexpr int32_t VH_SUCCESS_UP = 15, VH_SUCCESS_DOWN = 20, VH_SUCCESS_MIN = 50, VH_SUCCESS_MAX = 150;

constexpr int32_t VH_NOVELTY_PERCENT = 70;

constexpr uint32_t VH_SEEN_TICKS = 1500;

constexpr size_t VH_LOG_MAX = 8;


enum VhAllow { AL_ALWAYS = 0, AL_RAID, AL_SIEGE, AL_SUPPORT, AL_AIR, AL_COUNTER, AL_PINCER };


struct VorhabenRow {
    int32_t scheme;
    bool gather;
    bool heavy;
    bool needs_squad;
    int32_t cooldown;
    int32_t allow;
    int32_t orders[ROLE_COUNT];
};


constexpr VorhabenRow CATALOG[VH_COUNT] = {

    {GS_GUARD,           false, false, false, 2000, AL_ALWAYS,  {0, 0, 1, 0, 0, 0, 0, 0}},

    {GS_HARVESTER_FIRST, false, false, false, 1500, AL_RAID,    {0, 0, 4, 0, 0, 0, 0, 0}},

    {GS_DEFENSE_FIRST,   true,  true,  true,  1200, AL_ALWAYS,  {6, 0, 0, 2, 1, 0, 0, 0}},

    {GS_DEFENSE_FIRST,   true,  true,  true,  2000, AL_SIEGE,   {5, 3, 0, 0, 0, 0, 0, 0}},

    {GS_DEFENSE_FIRST,   true,  true,  true,  1500, AL_ALWAYS,  {0, 0, 0, 12, 0, 0, 0, 0}},

    {GS_POWER_FIRST,     false, false, false, 1200, AL_AIR,     {0, 0, 0, 0, 0, 0, 0, 3}},

    {GS_TECH_FIRST,      false, false, false, 3000, AL_RAID,    {2, 0, 0, 0, 0, 2, 0, 0}},

    {GS_POWER_FIRST,     false, false, false, 3000, AL_RAID,    {0, 0, 0, 0, 0, 0, 1, 0}},

    {GS_DEFENSE_FIRST,   true,  true,  true,  2000, AL_PINCER,  {6, 0, 2, 0, 0, 0, 0, 0}},

    {GS_GUARD,           false, false, true,  1200, AL_COUNTER, {0, 0, 0, 0, 0, 0, 0, 0}},

    {GS_GUARD,           false, false, true,  2500, AL_COUNTER, {2, 0, 0, 0, 0, 0, 0, 0}},

    {GS_DEFENSE_FIRST,   true,  true,  true,  4000, AL_SUPPORT, {6, 1, 0, 0, 0, 0, 0, 0}},

    {GS_DEFENSE_FIRST,   true,  true,  true,  4000, AL_SUPPORT, {6, 0, 0, 0, 0, 0, 0, 0}},

    {GS_GUARD,           false, false, false, 1000, AL_ALWAYS,  {0, 0, 0, 0, 0, 0, 0, 0}},

    {GS_GUARD,           false, false, false,    0, AL_ALWAYS,  {0, 0, 0, 0, 0, 0, 0, 0}},
};

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


int32_t World::bot_front_target(int32_t owner, WVec from, int64_t radius, int32_t scheme,
                                bool buildings_only) const {

    auto rank_of = [&](const UnitType& t) -> int32_t {
        switch (scheme) {
        case GS_HARVESTER_FIRST:
            if (t.harvester) return 0;
            if (t.refinery) return 1;
            if (t.building) return t.defense ? 3 : 2;
            return 4;
        case GS_TECH_FIRST:
            if (t.building && (t.produces != 0 || t.support_power >= 0)) return 0;
            if (t.building && t.power > 0) return 1;
            if (t.building) return t.defense ? 3 : 2;
            return 4;
        case GS_POWER_FIRST:
            if (t.building && t.power > 0) return 0;
            if (t.building && t.produces != 0) return 1;
            if (t.building) return t.defense ? 3 : 2;
            return 4;
        case GS_GUARD:
            return 0;
        case GS_DEFENSE_FIRST:
        default:
            if (t.building) return t.defense ? 0 : 1;
            return 2;
        }
    };
    int32_t best_id = -1;
    int32_t best_rank = 9;
    int64_t best_d = INT64_MAX;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (!t.targetable || t.husk) continue;
        if (buildings_only && !t.building) continue;

        if ((target_mask(i) & TT_AIRBORNE) != 0) continue;
        const int64_t d = length(a.pos - from);
        if (radius > 0 && d > radius) continue;
        const int32_t rank = rank_of(t);
        if (rank > best_rank) continue;
        if (rank == best_rank && d > best_d) continue;

        if (rank == best_rank && d == best_d && best_id >= 0 && a.id > best_id) continue;
        best_rank = rank;
        best_d = d;
        best_id = a.id;
    }
    return best_id;
}


int32_t World::bot_focus_target(int32_t owner, const BotSquad& s, WVec center) const {
    constexpr int32_t FOCUS_MIN_UNITS = 3;
    constexpr int32_t FOCUS_RADIUS_CELLS = 6;
    const bool siege_apart = players_[size_t(owner)].bot.p.allow_siege != 0;
    const int64_t r = int64_t(FOCUS_RADIUS_CELLS) * CELL;
    int32_t best_id = -1, best_count = 0;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& e = actors_[k];
        if (!e.alive || !hostile(owner, e.owner)) continue;
        const UnitType& et = types_[e.type];
        if (!et.targetable || et.husk) continue;
        if ((target_mask(k) & TT_AIRBORNE) != 0) continue;
        if (length(e.pos - center) > r) continue;
        int32_t count = 0;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            if (siege_apart && bot_unit_is_siege(size_t(i))) continue;
            const UnitType& ut = types_[actors_[size_t(i)].type];
            if (ut.weapon < 0 || size_t(ut.weapon) >= weapons_.size()) continue;
            if (!weapon_hits(k, weapons_[size_t(ut.weapon)])) continue;
            if (length(actors_[size_t(i)].pos - e.pos) <= weapons_[size_t(ut.weapon)].range) ++count;
        }
        if (count < FOCUS_MIN_UNITS) continue;

        if (count > best_count || (count == best_count && best_id >= 0 && e.id < best_id)) {
            best_count = count;
            best_id = e.id;
        }
    }
    return best_id;
}


int32_t World::bot_role_of_type(size_t t) const {
    const UnitType& ut = types_[t];
    if (ut.building || ut.husk || ut.harvester) return -1;
    if (ut.captures) return ROLE_ENGINEER;
    if (ut.demolition_delay >= 0 || ut.infiltrates != 0) return ROLE_COMMANDO;
    if (ut.aircraft) return ut.weapon >= 0 ? int32_t(ROLE_AIR) : -1;
    if (ut.weapon < 0 || size_t(ut.weapon) >= weapons_.size()) return -1;
    const Weapon& w = weapons_[size_t(ut.weapon)];
    const bool hits_ground = (w.valid_targets & (TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE | TT_VEHICLE | TT_INFANTRY)) != 0;

    if (hits_ground && w.range >= 9 * CELL) return ROLE_SIEGE;
    if ((w.valid_targets & TT_AIRBORNE) != 0 && !hits_ground) return ROLE_AA;
    if (!hits_ground) return -1;
    if (ut.speed >= ROLE_FAST_SPEED) return ROLE_FAST;
    if (ut.queue_kind == QUEUE_INFANTRY) return ROLE_INFANTRY;
    return ROLE_TANK;
}


void World::bot_counter_scan(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (b.p.counter_interval <= 0) return;
    if (--b.counter_ticks > 0) return;
    b.counter_ticks = std::max(1, b.p.counter_interval);


    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (t.building || t.husk || t.harvester || t.weapon < 0) continue;
        const CPos c = mobiles_[i].cell;
        if (bot_threat_at(owner, c, false) <= 0) continue;

        bool found = false;
        for (size_t k = 0; k < b.seen_ids.size(); ++k) {
            if (b.seen_ids[k] == a.id) { b.seen_ticks[k] = tick_; found = true; break; }
        }
        if (!found) { b.seen_ids.push_back(a.id); b.seen_ticks.push_back(tick_); }
    }

    size_t out = 0;
    for (size_t k = 0; k < b.seen_ids.size(); ++k) {
        const int i = index_of(b.seen_ids[k]);
        const bool fresh = tick_ <= b.seen_ticks[k] + VH_SEEN_TICKS;
        if (!fresh || i < 0 || !actors_[size_t(i)].alive) continue;
        b.seen_ids[out] = b.seen_ids[k];
        b.seen_ticks[out] = b.seen_ticks[k];
        ++out;
    }
    b.seen_ids.resize(out);
    b.seen_ticks.resize(out);

    b.counter_class[0] = b.counter_class[1] = b.counter_class[2] = 0;
    for (int32_t id : b.seen_ids) {
        const int i = index_of(id);
        if (i < 0) continue;
        const UnitType& t = types_[actors_[size_t(i)].type];
        const int32_t cost = std::max(1, t.cost);
        if (t.aircraft) b.counter_class[2] += cost;
        else if (t.queue_kind == QUEUE_INFANTRY) b.counter_class[0] += cost;
        else b.counter_class[1] += cost;
    }
}


int32_t World::bot_counter_share(int32_t owner, size_t t) const {
    const BotState& b = players_[size_t(owner)].bot;
    if (b.p.counter_interval <= 0) return 100;
    const int64_t total = int64_t(b.counter_class[0]) + b.counter_class[1] + b.counter_class[2];
    if (total <= 0) return 100;
    const UnitType& ut = types_[t];
    if (ut.weapon < 0 || size_t(ut.weapon) >= weapons_.size()) return 100;
    const Weapon& w = weapons_[size_t(ut.weapon)];
    const int32_t inf_pct = int32_t(int64_t(b.counter_class[0]) * 100 / total);
    const int32_t veh_pct = int32_t(int64_t(b.counter_class[1]) * 100 / total);
    const int32_t air_pct = int32_t(int64_t(b.counter_class[2]) * 100 / total);
    int32_t mult = 100;
    if ((w.valid_targets & TT_AIRBORNE) != 0) mult += air_pct;
    const bool hits_ground = (w.valid_targets & (TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE | TT_VEHICLE | TT_INFANTRY)) != 0;
    if (hits_ground) {
        if (w.versus[ARMOR_HEAVY] > w.versus[ARMOR_NONE]) mult += veh_pct;
        else if (w.versus[ARMOR_NONE] > w.versus[ARMOR_HEAVY]) mult += inf_pct;
    }
    return std::clamp(mult, 50, 250);
}


bool World::bot_vorhaben_heavy(int32_t vh) const {
    return vh >= 0 && vh < VH_COUNT && CATALOG[vh].heavy;
}

int32_t World::bot_vorhaben_scheme(int32_t vh) const {
    return vh >= 0 && vh < VH_COUNT ? CATALOG[vh].scheme : int32_t(GS_DEFENSE_FIRST);
}


bool World::bot_vorhaben_allowed(int32_t owner, int32_t vh) const {
    if (vh < 0 || vh >= VH_COUNT) return false;
    const BotParams& p = players_[size_t(owner)].bot.p;
    switch (CATALOG[vh].allow) {
    case AL_RAID:    return p.allow_raid != 0;
    case AL_SIEGE:   return p.allow_siege != 0;
    case AL_SUPPORT: return p.allow_support_powers != 0;
    case AL_AIR:     return p.allow_air_squad != 0;
    case AL_COUNTER: return p.allow_counterattack != 0;
    case AL_PINCER:  return p.allow_pincer != 0;
    default:         return true;
    }
}

namespace {


int32_t ref_count_for(const std::vector<Actor>& actors, const std::vector<UnitType>& types,
                      const World& w, int32_t owner, int32_t scheme) {
    int32_t n = 0;
    for (size_t i = 0; i < actors.size(); ++i) {
        const Actor& a = actors[i];
        if (!a.alive || !w.hostile(owner, a.owner)) continue;
        const UnitType& t = types[a.type];
        if (t.husk || !t.targetable) continue;
        switch (scheme) {
        case GS_HARVESTER_FIRST: if (t.harvester || t.refinery) ++n; break;
        case GS_TECH_FIRST:      if (t.building && (t.produces != 0 || t.support_power >= 0)) ++n; break;
        case GS_POWER_FIRST:     if (t.building && t.power > 0) ++n; break;
        case GS_GUARD:           if (!t.building && t.weapon >= 0) ++n; break;
        case GS_DEFENSE_FIRST:
        default:                 if (t.building && t.defense) ++n; break;
        }
    }
    return n;
}

}


BotStrategyFacts World::bot_strategy_facts(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    BotStrategyFacts f;
    f.credits = credits(owner);
    f.reserve = int32_t(b.idle_base_units.size());
    CPos base{-1, -1};
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.husk) continue;
        if (a.owner == owner) {
            if (t.refinery) ++f.refineries;
            if (t.harvester) ++f.harvesters;
            if (t.building && t.base_provider) { ++f.conyards; if (base.x < 0) base = a.origin; }
            if (t.aircraft) ++f.own_aircraft;
            if (!t.building && !t.harvester && t.weapon >= 0) f.own_army += t.cost;
            if (bot_unit_is_siege(i)) ++f.siege_units;
            const int32_t role = bot_role_of_type(size_t(a.type));
            if (role == ROLE_FAST) ++f.own_fast;
            else if (role == ROLE_INFANTRY) ++f.own_infantry;
            else if (role == ROLE_ENGINEER) ++f.own_engineers;
            else if (role == ROLE_COMMANDO) ++f.own_commandos;
        } else if (hostile(owner, a.owner)) {
            if (t.building) ++f.enemy_buildings;
            if (t.defense) ++f.enemy_defenses;
            if (t.harvester) ++f.enemy_harvesters;
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
    return f;
}


int32_t World::bot_vorhaben_lage(int32_t owner, int32_t vh, const BotStrategyFacts& f) const {
    if (vh < 0 || vh >= VH_COUNT) return 0;
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    const bool schedule_ok = int32_t(tick_) >= p.first_attack_tick;

    switch (vh) {
    case VH_SCOUT:

        if (tick_ < 500 || f.own_fast <= 0) return 0;
        return 200;
    case VH_ORE_RAID:

        if (f.enemy_harvesters <= 0 || p.raid_squad_size <= 0) return 0;
        if (f.own_fast < p.raid_squad_size) return 0;
        return std::min(900, 150 + f.enemy_harvesters * 150);
    case VH_TANK_PUSH: {


        if (!schedule_ok || f.own_army <= 0 || f.enemy_buildings <= 0) return 0;
        return int32_t(std::clamp<int64_t>(int64_t(f.own_army) * 400 / std::max(1, f.enemy_army), 1, 800));
    }
    case VH_SIEGE:

        if (f.siege_units <= 0 || f.enemy_defenses < 2 || !schedule_ok) return 0;
        return std::min(800, f.enemy_defenses * 60 + f.siege_units * 50);
    case VH_INFANTRY_FLOOD:

        if (f.own_infantry < 6 || !schedule_ok) return 0;
        return std::min(800, f.own_infantry * 50 + std::max(0, 6 - f.enemy_defenses) * 40);
    case VH_AIR_STRIKE: {

        if (f.own_aircraft < p.air_squad_size) return 0;
        const int32_t aa_penalty = std::min(600, f.enemy_aa * 80);
        return std::max(0, 200 + f.own_aircraft * 90 - aa_penalty);
    }
    case VH_ENGINEER:

        if (f.own_engineers <= 0 || f.enemy_buildings <= 0) return 0;
        return std::min(700, 300 + f.own_engineers * 100);
    case VH_COMMANDO:
        if (f.own_commandos <= 0 || f.enemy_buildings <= 0) return 0;
        return std::min(700, 350 + f.own_commandos * 150);
    case VH_PINCER: {

        bool heavy_running = false;
        for (int32_t k = 0; k < VH_COUNT; ++k)
            if (b.vh_running[k] && CATALOG[k].heavy) { heavy_running = true; break; }
        if (!heavy_running || !schedule_ok) return 0;
        if (int64_t(f.own_army) * 100 < int64_t(f.enemy_army) * 130) return 0;
        return 500;
    }
    case VH_COUNTERATTACK:


        if (b.attack_peak <= 0 || b.attack_sum * 2 >= b.attack_peak) return 0;
        if (f.reserve <= 0) return 0;
        if (int64_t(f.base_guard) * 100 < int64_t(f.base_threat) * 60) return 0;
        return 450;
    case VH_EXPANSION_GUARD:

        if (f.conyards < 2 || f.reserve < 2) return 0;
        if (bot_defense_firepower(owner) >= bot_defense_budget(owner)) return 300;
        return 400;
    case VH_NUKE_PUSH: {

        int available = 0, ready = 0, permille = 0, paused = 0;
        support_power_state(owner, SP_NUKE, available, ready, permille, paused);
        if (!available || !ready || f.enemy_buildings <= 0) return 0;
        return 600;
    }
    case VH_CURTAIN_PUSH: {
        int available = 0, ready = 0, permille = 0, paused = 0;
        support_power_state(owner, SP_IRON_CURTAIN, available, ready, permille, paused);
        if (!available || !ready) {
            support_power_state(owner, SP_CHRONOSHIFT, available, ready, permille, paused);
            if (!available || !ready) return 0;
        }
        if (f.own_army <= 0) return 0;
        return 550;
    }
    case VH_TURTLE:

        if (f.base_threat <= 0) return 0;
        return int32_t(std::clamp<int64_t>(int64_t(f.base_threat) * 400 / std::max(1, f.base_guard), 1, 900));
    case VH_ECONOMY: {

        int32_t s = std::max(0, (p.additional_min_refineries - f.refineries)) * 180;
        if (f.harvesters < p.initial_harvesters) s += (p.initial_harvesters - f.harvesters) * 140;
        if (f.credits < p.production_min_cash) s += 200;
        return std::min(900, s + 120);
    }
    default:
        return 0;
    }
}


void World::bot_vorhaben_start(int32_t owner, int32_t vh) {
    if (vh < 0 || vh >= VH_COUNT) return;
    BotState& b = players_[size_t(owner)].bot;
    const VorhabenRow& row = CATALOG[vh];
    b.vh_running[vh] = 1;
    b.vh_start[vh] = tick_;
    b.vh_ref[vh] = ref_count_for(actors_, types_, *this, owner, row.scheme);

    b.vh_last[1] = b.vh_last[0];
    b.vh_last[0] = vh;


    for (int32_t r = 0; r < ROLE_COUNT; ++r)
        b.vh_orders[r] = std::min(30, b.vh_orders[r] + row.orders[r]);

    BotVorhabenLog entry;
    entry.vorhaben = vh;
    entry.start = tick_;
    b.vorhaben_log.push_back(entry);
    if (b.vorhaben_log.size() > VH_LOG_MAX) b.vorhaben_log.erase(b.vorhaben_log.begin());

    if (!row.needs_squad) return;


    if (vh == VH_COUNTERATTACK || vh == VH_EXPANSION_GUARD) {
        const size_t want = vh == VH_EXPANSION_GUARD ? size_t(2) : b.idle_base_units.size();
        std::vector<int32_t> take, rest;
        for (int32_t id : b.idle_base_units) {
            const int i = index_of(id);
            if (take.size() < want && i >= 0 && types_[actors_[size_t(i)].type].weapon >= 0) take.push_back(id);
            else rest.push_back(id);
        }
        if (take.empty()) return;
        b.idle_base_units = rest;
        BotSquad ns;
        ns.type = BotSquad::ASSAULT;
        ns.units = take;
        ns.vorhaben = vh;
        ns.scheme = row.scheme;
        ns.start_size = int32_t(take.size());
        ns.state = BotSquad::IDLE;
        if (vh == VH_COUNTERATTACK) {

            ns.gather = CPos{map_.width() / 2, map_.height() / 2};
            ns.state = BotSquad::ATTACK_MOVE;
            ns.storm = true;
        } else {

            for (const Actor& a : actors_) {
                if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].base_provider) continue;
                ns.gather = a.origin;
            }
        }
        b.squads.push_back(ns);
        ++b.stat_squads_sent;
        return;
    }

    b.vh_pending = vh;
}


void World::bot_vorhaben_end(int32_t owner, int32_t vh, bool success) {
    if (vh < 0 || vh >= VH_COUNT) return;
    BotState& b = players_[size_t(owner)].bot;
    if (!b.vh_running[vh]) return;
    const VorhabenRow& row = CATALOG[vh];
    b.vh_running[vh] = 0;
    b.vh_cooldown[vh] = row.cooldown;
    b.vh_success[vh] = std::clamp(b.vh_success[vh] + (success ? VH_SUCCESS_UP : -VH_SUCCESS_DOWN),
                                  VH_SUCCESS_MIN, VH_SUCCESS_MAX);
    for (int32_t r = 0; r < ROLE_COUNT; ++r) b.vh_orders[r] = std::max(0, b.vh_orders[r] - row.orders[r]);
    if (b.vh_pending == vh) b.vh_pending = -1;

    for (BotSquad& s : b.squads)
        if (s.vorhaben == vh) { s.vorhaben = -1; s.scheme = GS_DEFENSE_FIRST; s.storm_at = 0; }

    for (size_t k = b.vorhaben_log.size(); k > 0; --k) {
        BotVorhabenLog& e = b.vorhaben_log[k - 1];
        if (e.vorhaben != vh || e.result != 0) continue;
        e.end = tick_;
        e.result = success ? 1 : -1;
        break;
    }
}


void World::bot_vorhaben_review(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    for (int32_t vh = 0; vh < VH_COUNT; ++vh) {
        if (!b.vh_running[vh]) continue;
        if (vh == VH_ECONOMY) continue;
        const VorhabenRow& row = CATALOG[vh];

        const int32_t now = ref_count_for(actors_, types_, *this, owner, row.scheme);
        if (row.scheme != GS_GUARD && now < b.vh_ref[vh]) { bot_vorhaben_end(owner, vh, true); continue; }
        if (row.needs_squad) {
            int32_t alive = -1, start = 0;
            for (const BotSquad& s : b.squads) {
                if (s.vorhaben != vh) continue;
                alive = int32_t(s.units.size());
                start = s.start_size;
                break;
            }
            if (alive < 0) {


                if (tick_ > b.vh_start[vh] + VH_FORM_TICKS) { bot_vorhaben_end(owner, vh, false); continue; }
            } else if (start > 0 && alive * 2 < start) {
                bot_vorhaben_end(owner, vh, false);
                continue;
            }
        }
        if (tick_ > b.vh_start[vh] + VH_MAX_TICKS) bot_vorhaben_end(owner, vh, false);
    }
}


void World::bot_vorhaben_wahl(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (--b.strategy_ticks > 0) return;
    const int32_t step = std::max(1, p.strategy_interval);
    b.strategy_ticks = step;


    for (int32_t vh = 0; vh < VH_COUNT; ++vh) b.vh_cooldown[vh] = std::max(0, b.vh_cooldown[vh] - step);
    bot_vorhaben_review(owner);


    if (!b.vh_running[VH_ECONOMY]) bot_vorhaben_start(owner, VH_ECONOMY);

    int32_t running = 0, heavy_running = 0;
    for (int32_t vh = 0; vh < VH_COUNT; ++vh) {
        if (!b.vh_running[vh] || vh == VH_ECONOMY) continue;
        ++running;
        if (CATALOG[vh].heavy) ++heavy_running;
    }


    const bool guard_ok = bot_defense_firepower(owner) * 2 >= bot_defense_budget(owner);

    const BotStrategyFacts facts = bot_strategy_facts(owner);
    int32_t best_vh = -1;
    int64_t best_score = 0;
    int32_t lead_vh = VH_ECONOMY, lead_score = -1;
    const int32_t spread = std::clamp(p.vorhaben_random_percent, 0, 90);
    for (int32_t vh = 0; vh < VH_COUNT; ++vh) {
        const int32_t lage = bot_vorhaben_lage(owner, vh, facts);

        if (b.vh_running[vh]) {
            const int32_t s = int32_t(std::min<int64_t>(int64_t(lage) * p.vorhaben_weight[vh] / 100, INT32_MAX));
            if (s > lead_score || (s == lead_score && vh < lead_vh)) { lead_score = s; lead_vh = vh; }
            continue;
        }
        if (vh == VH_ECONOMY) continue;
        if (running >= std::max(1, p.max_running_vorhaben)) continue;
        if (lage <= 0 || b.vh_cooldown[vh] > 0 || !bot_vorhaben_allowed(owner, vh)) continue;
        if (CATALOG[vh].heavy && (heavy_running > 0 || !guard_ok)) continue;

        int64_t s = int64_t(lage) * p.vorhaben_weight[vh] / 100;
        s = s * b.vh_success[vh] / 100;
        if (vh == b.vh_last[0] || vh == b.vh_last[1]) s = s * VH_NOVELTY_PERCENT / 100;
        if (spread > 0) {


            const int32_t pct = 100 - spread + int32_t(rand() % uint32_t(2 * spread + 1));
            s = s * pct / 100;
        }

        if (s > best_score) { best_score = s; best_vh = vh; }
    }
    if (best_vh >= 0) {
        bot_vorhaben_start(owner, best_vh);
        const int32_t s = int32_t(std::min<int64_t>(best_score, INT32_MAX));
        if (s > lead_score) { lead_score = s; lead_vh = best_vh; }
    }
    b.vorhaben_lead = lead_vh;
    b.vorhaben_score = std::max(0, lead_score);
}


int32_t World::bot_vorhaben_squad_size(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    int32_t pct = 100;
    switch (b.vorhaben_lead) {
    case VH_TANK_PUSH:      pct = 70; break;
    case VH_PINCER:         pct = 70; break;
    case VH_INFANTRY_FLOOD: pct = 80; break;
    case VH_SIEGE:          pct = 110; break;
    case VH_NUKE_PUSH:
    case VH_CURTAIN_PUSH:   pct = 110; break;
    case VH_AIR_STRIKE:     pct = 100; break;
    case VH_ECONOMY:        pct = 130; break;
    case VH_TURTLE:         pct = 150; break;
    default: break;
    }
    return std::max(1, b.p.squad_size * pct / 100);
}


int32_t World::bot_vorhaben_sp_threshold(int32_t owner, int32_t base) const {
    const BotState& b = players_[size_t(owner)].bot;
    int32_t pct = 100;
    switch (b.vorhaben_lead) {
    case VH_NUKE_PUSH:
    case VH_CURTAIN_PUSH: pct = 60; break;
    case VH_TURTLE:       pct = 70; break;
    case VH_SIEGE:        pct = 75; break;
    case VH_TANK_PUSH:    pct = 90; break;
    case VH_ECONOMY:      pct = 130; break;
    default: break;
    }
    return std::max(1, base * pct / 100);
}

}
