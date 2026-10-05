

#include <algorithm>
#include <iterator>
#include <vector>

#include "ra/sim.h"

namespace ra {

static_assert(VH_COUNT == 16, "BotCommanderMods::vh_weight hat 16 Einträge");
static_assert(BQ_COUNT == 4, "BotCommanderMods::queue hat 4 Einträge");

namespace {


template <size_t N> void normalize(const int64_t (&pts)[N], int32_t (&out)[N]) {
    int64_t sum = 0;
    for (size_t k = 0; k < N; ++k) sum += std::max<int64_t>(0, pts[k]);
    if (sum <= 0) {
        for (size_t k = 0; k < N; ++k) out[k] = k == 0 ? 1000 : 0;
        return;
    }
    int32_t given = 0;
    size_t best = 0;
    for (size_t k = 0; k < N; ++k) {
        out[k] = int32_t(std::max<int64_t>(0, pts[k]) * 1000 / sum);
        given += out[k];
        if (out[k] > out[best]) best = k;
    }
    out[best] += 1000 - given;
}

template <size_t N> size_t argmax(const int32_t (&p)[N]) {
    size_t best = 0;
    for (size_t k = 1; k < N; ++k)
        if (p[k] > p[best]) best = k;
    return best;
}


inline int32_t blend(int32_t m, int32_t strength) {
    return std::max(0, 100 + (m - 100) * strength / 100);
}


void components(int w, int h, const std::vector<uint8_t>& ok, std::vector<int32_t>& label,
                std::vector<int32_t>& sizes) {
    const int n = w * h;
    label.assign(size_t(n), -1);
    sizes.clear();
    std::vector<int32_t> stack;
    for (int start = 0; start < n; ++start) {
        if (!ok[size_t(start)] || label[size_t(start)] >= 0) continue;
        const int32_t id = int32_t(sizes.size());
        int32_t count = 0;
        stack.clear();
        stack.push_back(start);
        label[size_t(start)] = id;
        while (!stack.empty()) {
            const int32_t c = stack.back();
            stack.pop_back();
            ++count;
            const int cx = c % w, cy = c / w;
            for (int d = 0; d < NUM_DIRS; ++d) {
                const int nx = cx + DIR_DX[d], ny = cy + DIR_DY[d];
                if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                const int ni = ny * w + nx;
                if (!ok[size_t(ni)] || label[size_t(ni)] >= 0) continue;
                label[size_t(ni)] = id;
                stack.push_back(ni);
            }
        }
        sizes.push_back(count);
    }
}

int32_t domain_of(const UnitType& t) {
    if (t.aircraft) return DOM_AIR;
    if (t.locomotor == LOCO_NAVAL) return DOM_NAVAL;
    return DOM_LAND;
}

}


int32_t World::bot_level(int64_t v, const int32_t (&t)[3]) {
    if (v <= 0) return LV_NONE;
    if (v < t[0]) return LV_LOW;
    if (v < t[1]) return LV_MEDIUM;
    if (v < t[2]) return LV_HIGH;
    return LV_STRONG;
}


void World::bot_commander_tick(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (!b.p.cmd_enabled) return;
    if (--b.cmd_bucket_ticks > 0) return;
    b.cmd_bucket_ticks = CMD_BUCKET_TICKS;
    const int32_t pos = std::clamp(b.cmd_ring_pos, 0, CMD_BUCKETS - 1);
    const int64_t earned_now = earned(owner);
    b.cmd_ring_income[pos] = int32_t(std::clamp<int64_t>(earned_now - b.cmd_snap_earned, 0, INT32_MAX));
    b.cmd_snap_earned = earned_now;
    for (int d = 0; d < DOM_COUNT; ++d) {
        b.cmd_ring_lost[d][pos] = std::max(0, b.cmd_cum_lost[d] - b.cmd_snap_lost[d]);
        b.cmd_snap_lost[d] = b.cmd_cum_lost[d];
    }
    b.cmd_ring_kills[pos] = std::max(0, b.cmd_cum_kills - b.cmd_snap_kills);
    b.cmd_snap_kills = b.cmd_cum_kills;
    b.cmd_ring_damage[pos] = std::max(0, b.cmd_cum_damage - b.cmd_snap_damage);
    b.cmd_snap_damage = b.cmd_cum_damage;
    b.cmd_ring_pos = (pos + 1) % CMD_BUCKETS;
}


void World::bot_commander_note_damage(size_t victim, int64_t dmg) {
    const Actor& v = actors_[victim];
    if (v.owner < 0 || v.owner >= MAX_PLAYERS || dmg <= 0) return;
    BotState& b = players_[size_t(v.owner)].bot;
    if (!b.enabled || !types_[v.type].building) return;
    b.cmd_cum_damage = int32_t(std::min<int64_t>(int64_t(b.cmd_cum_damage) + dmg, INT32_MAX));
}


void World::bot_commander_map(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (b.initial_base_center.x < 0) return;
    b.cmd_map = commander_map_info(owner, b.initial_base_center, b.p);
}


BotMapInfo World::commander_map_info(int32_t owner, CPos start_cell, const BotParams& p) const {
    BotMapInfo m;
    m.done = 1;
    const int w = map_.width(), h = map_.height();
    const int n = w * h;
    if (n <= 0) return m;
    const bool has_terrain = !map_.raw_terrain().empty();
    std::vector<uint8_t> land(size_t(n), 0), ore(size_t(n), 0);
    int64_t n_land = 0, n_water = 0;
    for (int i = 0; i < n; ++i) {
        const CPos c = map_.cell_at(i);
        bool is_land, is_water;
        if (has_terrain) {
            const int32_t t = map_.terrain(c);
            is_land = Map::cost_for_terrain(t, MC_LAND) != 0;
            is_water = t == TER_WATER;
        } else {
            is_land = map_.passable(c, MC_LAND);
            is_water = !is_land && map_.passable(c, MC_NAVAL);
        }
        land[size_t(i)] = is_land ? 1 : 0;
        n_land += is_land ? 1 : 0;
        n_water += is_water ? 1 : 0;
        if (size_t(i) < res_type_.size() && res_type_[size_t(i)] != RES_NONE) ore[size_t(i)] = 1;
    }
    m.water_permille = int32_t(n_water * 1000 / std::max<int64_t>(1, n_land + n_water));

    std::vector<int32_t> label, sizes;
    components(w, h, land, label, sizes);
    for (int32_t s : sizes)
        if (s >= std::max(1, p.cmd_landmass_min_cells)) ++m.landmasses;


    auto label_near = [&](CPos c) -> int32_t {
        for (int r = 0; r <= 3; ++r)
            for (int dy = -r; dy <= r; ++dy)
                for (int dx = -r; dx <= r; ++dx) {
                    const CPos q{c.x + dx, c.y + dy};
                    if (!map_.in_bounds(q)) continue;
                    const int32_t l = label[size_t(map_.index(q))];
                    if (l >= 0) return l;
                }
        return -1;
    };
    const int32_t own = label_near(start_cell);
    for (int32_t q = 0; q < MAX_PLAYERS; ++q) {
        if (q == owner || players_[size_t(q)].non_combatant || !hostile(owner, q)) continue;
        CPos start{-1, -1};
        for (size_t i = 0; i < actors_.size() && start.x < 0; ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || a.owner != q) continue;
            const UnitType& t = types_[a.type];
            if (t.building && t.base_provider) start = a.origin;
        }
        for (size_t i = 0; i < actors_.size() && start.x < 0; ++i) {
            const Actor& a = actors_[i];
            if (a.alive && a.owner == q && types_[a.type].transforms_into >= 0) start = mobiles_[i].cell;
        }
        if (start.x < 0) continue;
        ++m.enemy_starts;
        if (own >= 0 && label_near(start) == own) ++m.land_connected;
    }


    if (m.enemy_starts > m.land_connected && own >= 0 && bot_lst_type(owner, false) >= 0) {
        bool yard = false;
        for (size_t t = 0; t < types_.size() && !yard; ++t) {
            const UnitType& ut = types_[t];
            if (ut.building && (ut.produces & (1u << QUEUE_SHIP)) != 0 && ut.cost > 0 &&
                ut.queue_kind >= 0 && !item_hidden(owner, int32_t(t))) yard = true;
        }
        bool coast = false;
        for (int i = 0; i < n && yard && !coast; ++i) {
            if (label[size_t(i)] != own) continue;
            const CPos c = map_.cell_at(i);
            for (int d = 0; d < NUM_DIRS && !coast; ++d) {
                const CPos q{c.x + DIR_DX[d], c.y + DIR_DY[d]};
                if (map_.in_bounds(q) && map_.passable(q, MC_NAVAL)) coast = true;
            }
        }
        m.amphib_possible = yard && coast ? 1 : 0;
    }

    components(w, h, ore, label, sizes);
    for (int32_t s : sizes)
        if (s >= std::max(1, p.cmd_ore_field_min_cells)) ++m.ore_fields;

    const bool wet = m.water_permille >= p.cmd_water_mixed_permille;
    if (m.enemy_starts > 0 && m.land_connected == 0) m.map_type = MAP_ISLANDS;
    else if (wet || m.land_connected < m.enemy_starts) m.map_type = MAP_MIXED;
    else m.map_type = MAP_LAND;
    return m;
}


BotSummary World::bot_commander_summary(int32_t owner, const BotStrategyFacts& f) const {
    const BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    BotSummary s;
    s.tick = int32_t(tick_);
    s.credits = bot_level(f.credits, p.cmd_credits_lv);
    s.refineries = bot_level(f.refineries, p.cmd_refinery_lv);
    s.power_ok = power_provided(owner) >= power_drained(owner) ? 1 : 0;

    int64_t army[DOM_COUNT] = {0, 0, 0}, enemy[DOM_COUNT] = {0, 0, 0};
    int32_t aa = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.husk) continue;
        const bool combat_unit = !t.building && !t.harvester && t.weapon >= 0;
        if (a.owner == owner) {
            if (combat_unit) army[domain_of(t)] += t.cost;
            continue;
        }
        if (!hostile(owner, a.owner) || !bot_sees(owner, i)) continue;
        if (combat_unit) enemy[domain_of(t)] += t.cost;
        const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
        for (int32_t wi : arms)
            if (wi >= 0 && size_t(wi) < weapons_.size() && (weapons_[size_t(wi)].valid_targets & TT_AIRBORNE)) { ++aa; break; }
    }
    for (int d = 0; d < DOM_COUNT; ++d) {
        s.army[d] = bot_level(army[d], p.cmd_army_lv);
        s.enemy[d] = bot_level(enemy[d], p.cmd_army_lv);
        s.raw_army[d] = int32_t(std::min<int64_t>(army[d], INT32_MAX));
        s.raw_enemy[d] = int32_t(std::min<int64_t>(enemy[d], INT32_MAX));
    }
    s.raw_credits = int32_t(std::clamp<int64_t>(f.credits, 0, INT32_MAX));
    s.raw_refineries = int32_t(std::max<int64_t>(0, f.refineries));
    s.raw_enemy_aa = aa;
    s.enemy_anti_air = bot_level(aa, p.cmd_aa_lv);
    s.enemy_attacking = b.last_attack_tick > 0 &&
                        int32_t(tick_) - b.last_attack_tick <= std::max(0, p.cmd_attack_recent_ticks) ? 1 : 0;


    int64_t income = std::max<int64_t>(0, earned(owner) - b.cmd_snap_earned);
    int64_t lost[DOM_COUNT], kills = std::max(0, b.cmd_cum_kills - b.cmd_snap_kills);
    int64_t damage = std::max(0, b.cmd_cum_damage - b.cmd_snap_damage);
    for (int d = 0; d < DOM_COUNT; ++d) lost[d] = std::max(0, b.cmd_cum_lost[d] - b.cmd_snap_lost[d]);
    int64_t old_half = 0, new_half = 0;
    const int32_t pos = std::clamp(b.cmd_ring_pos, 0, CMD_BUCKETS - 1);
    for (int k = 0; k < CMD_BUCKETS; ++k) {
        const int idx = (pos + k) % CMD_BUCKETS;
        income += b.cmd_ring_income[idx];
        (k < CMD_BUCKETS / 2 ? old_half : new_half) += b.cmd_ring_income[idx];
        for (int d = 0; d < DOM_COUNT; ++d) lost[d] += b.cmd_ring_lost[d][idx];
        kills += b.cmd_ring_kills[idx];
        damage += b.cmd_ring_damage[idx];
    }
    s.income_60s = int32_t(std::min<int64_t>(income, INT32_MAX));
    const int64_t tp = std::clamp(p.cmd_trend_percent, 0, 100);
    if (new_half * 100 > old_half * (100 + tp)) s.income = TR_RISING;
    else if (new_half * 100 < old_half * (100 - tp)) s.income = TR_FALLING;
    else s.income = TR_FLAT;
    s.air_losses_60s = bot_level(lost[DOM_AIR], p.cmd_loss_lv);
    s.land_losses_60s = bot_level(lost[DOM_LAND] + lost[DOM_NAVAL], p.cmd_loss_lv);
    s.kills_60s = bot_level(kills, p.cmd_kill_lv);
    s.base_damage_60s = bot_level(damage, p.cmd_damage_lv);
    s.raw_air_lost = int32_t(std::min<int64_t>(lost[DOM_AIR], INT32_MAX));
    s.raw_land_lost = int32_t(std::min<int64_t>(lost[DOM_LAND] + lost[DOM_NAVAL], INT32_MAX));
    s.raw_kills = int32_t(std::min<int64_t>(kills, INT32_MAX));
    s.raw_base_damage = int32_t(std::min<int64_t>(damage, INT32_MAX));


    int32_t threat = 0;
    if (f.base_threat > 0)
        threat = int32_t(std::clamp<int64_t>(int64_t(f.base_threat) * 500 / std::max(1, f.base_guard), 0, 1000));
    threat = std::max(threat, s.base_damage_60s * 200);
    if (s.enemy_attacking) threat = std::max(threat, 400);
    s.base_threat = std::min(1000, threat);

    s.opening_done = bot_opening_done(owner) ? 1 : 0;
    s.doctrine = b.cmd_directive.doctrine;
    s.doctrine_age_s = b.cmd_directive.decided
                           ? std::max(0, int32_t(tick_) - b.cmd_directive.doctrine_since) / TICKS_PER_SECOND
                           : 0;
    commander_perceive(owner, p, b.cmd_track, s);
    return s;
}


BotDecision World::bot_rule_commander(const BotSummary& s, const BotMapInfo& m, const BotParams& p) {
    BotDecision d;

    int64_t doc[DOC_COUNT] = {400, 100, 100, 150, 0};
    if (m.map_type == MAP_ISLANDS) {

        doc[DOC_LAND_PUSH] = 20;
        doc[DOC_NAVAL_DOMINANCE] += 450;
        doc[DOC_AIR_DOMINANCE] += 300;
    } else if (m.map_type == MAP_MIXED) {
        doc[DOC_NAVAL_DOMINANCE] += 150;
        doc[DOC_AIR_DOMINANCE] += 50;
    } else {
        doc[DOC_NAVAL_DOMINANCE] = 20;
    }

    if (s.army[DOM_AIR] >= LV_MEDIUM && s.enemy_anti_air <= LV_LOW) doc[DOC_AIR_DOMINANCE] += 250;

    if (s.air_losses_60s >= LV_HIGH && s.enemy_anti_air >= LV_HIGH) doc[DOC_AIR_DOMINANCE] /= 5;
    else if (s.air_losses_60s >= LV_MEDIUM && s.enemy_anti_air >= LV_MEDIUM) doc[DOC_AIR_DOMINANCE] /= 2;

    if (s.enemy[DOM_NAVAL] >= LV_MEDIUM && m.water_permille * 2 >= p.cmd_water_mixed_permille)
        doc[DOC_NAVAL_DOMINANCE] += 200;


    if (s.credits <= LV_LOW && s.income == TR_FALLING) doc[DOC_ECO_TURTLE] += 250;
    if (s.opening_done && s.refineries <= LV_LOW && s.credits <= LV_LOW) doc[DOC_ECO_TURTLE] += 150;
    if (s.base_threat >= 600) doc[DOC_ECO_TURTLE] += 150;

    if (m.map_type != MAP_ISLANDS && s.army[DOM_LAND] >= LV_HIGH && s.enemy[DOM_LAND] <= LV_LOW)
        doc[DOC_LAND_PUSH] += 300;


    const int32_t amphib_army = s.doctrine == DOC_AMPHIBIOUS ? LV_LOW : LV_MEDIUM;
    if (m.amphib_possible && p.amphib_enabled) {
        doc[DOC_AMPHIBIOUS] = 50;
        if (s.enemy[DOM_NAVAL] <= LV_LOW && s.army[DOM_LAND] >= amphib_army) {
            doc[DOC_AMPHIBIOUS] += m.map_type == MAP_ISLANDS ? 1000 : 400;
            if (s.army[DOM_LAND] >= LV_HIGH) doc[DOC_AMPHIBIOUS] += 400;
            doc[DOC_NAVAL_DOMINANCE] /= 2;
            doc[DOC_AIR_DOMINANCE] /= 2;
        }
    }
    normalize(doc, d.doctrine);


    int64_t eco[ECO_COUNT] = {100, 400, 100};


    if (s.opening_done && s.refineries <= LV_LOW && s.credits <= LV_MEDIUM && m.ore_fields > 0)
        eco[ECO_MORE_REFINERIES] += 400;
    if (s.opening_done && s.credits <= LV_LOW && s.income != TR_RISING) eco[ECO_MORE_REFINERIES] += 250;
    if (s.income == TR_FALLING && s.credits >= LV_HIGH) eco[ECO_SAVE_MONEY] += 300;
    if (s.credits >= LV_STRONG) eco[ECO_OK] += 200;
    normalize(eco, d.economy);


    int64_t st[ST_COUNT] = {200, 350, 100, 0};


    const int32_t adv = s.army[DOM_LAND] - s.enemy[DOM_LAND];
    if (adv >= 2 && s.army[DOM_LAND] >= LV_HIGH) st[ST_ATTACK] += 450;
    else if (adv >= 1 && s.army[DOM_LAND] >= LV_MEDIUM) st[ST_ATTACK] += 200;
    if (s.kills_60s > s.land_losses_60s) st[ST_ATTACK] += 100;
    if (s.enemy_attacking) st[ST_DEFEND] += 450;
    st[ST_DEFEND] += s.base_threat / 2;
    if (s.land_losses_60s >= LV_HIGH && s.kills_60s <= LV_LOW && adv <= -1) st[ST_RETREAT] += 500;
    normalize(st, d.stance);


    int32_t air = 750;
    if (s.air_losses_60s >= LV_HIGH && s.enemy_anti_air >= LV_HIGH) air = 100;
    else if (s.air_losses_60s >= LV_MEDIUM && s.enemy_anti_air >= LV_MEDIUM) air = 350;
    else if (s.enemy_anti_air <= LV_LOW) air = 900;
    d.keep_using_air = air;

    d.base_threat = std::clamp(s.base_threat, 0, 1000);
    commander_rules_v3(s, m, p, d);
    return d;
}


void World::bot_commander_hysteresis(BotDirective& d, const BotDecision& dec, const BotParams& p, int32_t tick) {
    const size_t doc = argmax(dec.doctrine);
    if (!d.decided) {
        d.doctrine = int32_t(doc);
        d.doctrine_since = tick;
    } else if (int32_t(doc) != d.doctrine && dec.doctrine[doc] >= p.cmd_doctrine_min_permille &&
               dec.doctrine[doc] - (d.doctrine >= 0 && d.doctrine < DOC_COUNT ? dec.doctrine[size_t(d.doctrine)] : 0) >=
                   p.cmd_doctrine_margin_permille &&
               tick - d.doctrine_since >= p.cmd_doctrine_min_ticks) {
        d.doctrine = int32_t(doc);
        d.doctrine_since = tick;
    }
    const size_t eco = argmax(dec.economy);
    if (!d.decided || dec.economy[eco] > p.cmd_tactic_switch_p) d.economy = int32_t(eco);
    const size_t st = argmax(dec.stance);
    if (!d.decided || dec.stance[st] > p.cmd_tactic_switch_p) d.stance = int32_t(st);
    if (dec.keep_using_air > p.cmd_tactic_switch_p) d.keep_using_air = 1;
    else if (1000 - dec.keep_using_air > p.cmd_tactic_switch_p) d.keep_using_air = 0;
    d.base_threat = std::clamp(dec.base_threat, 0, 1000);


    d.counter = int32_t(argmax(dec.counter));
    d.defense_sector = int32_t(argmax(dec.defense_sector));
    const size_t ef = argmax(dec.economy_fix);
    if (!d.decided || dec.economy_fix[ef] > p.cmd_tactic_switch_p) d.economy_fix = int32_t(ef);
    const size_t so = argmax(dec.special_op);
    if (int32_t(so) != d.special_op && (!d.decided || tick - d.special_since >= p.cmd_special_min_ticks)) {
        d.special_op = int32_t(so);
        d.special_since = tick;
    }
    d.decided = 1;
}


BotCommanderMods World::bot_commander_mods(const BotDirective& d, const BotParams& p) {
    BotCommanderMods m;
    const int32_t heavy_land[4] = {VH_TANK_PUSH, VH_SIEGE, VH_INFANTRY_FLOOD, VH_PINCER};
    auto heavy = [&](int32_t pct) { for (int32_t vh : heavy_land) m.vh_weight[vh] = m.vh_weight[vh] * pct / 100; };
    switch (d.doctrine) {
    case DOC_AIR_DOMINANCE:
        m.vh_weight[VH_AIR_STRIKE] = m.vh_weight[VH_AIR_STRIKE] * 250 / 100;
        heavy(80);
        m.queue[BQ_AIRCRAFT] = 250; m.queue[BQ_VEHICLE] = 80; m.queue[BQ_INFANTRY] = 80;
        break;
    case DOC_NAVAL_DOMINANCE:
        m.vh_weight[VH_AIR_STRIKE] = m.vh_weight[VH_AIR_STRIKE] * 130 / 100;
        heavy(60);
        m.queue[BQ_NAVAL] = 250; m.queue[BQ_AIRCRAFT] = 130; m.queue[BQ_VEHICLE] = 70; m.queue[BQ_INFANTRY] = 70;
        break;
    case DOC_ECO_TURTLE:
        m.vh_weight[VH_TURTLE] = m.vh_weight[VH_TURTLE] * 200 / 100;
        heavy(60);
        m.squad = m.squad * 130 / 100;
        m.extra_refineries += 1;
        break;
    case DOC_AMPHIBIOUS:

        m.vh_weight[VH_LANDING] = m.vh_weight[VH_LANDING] * 300 / 100;
        m.queue[BQ_VEHICLE] = 200; m.queue[BQ_INFANTRY] = 200; m.queue[BQ_AIRCRAFT] = 80; m.queue[BQ_NAVAL] = 80;
        break;
    default:
        break;
    }

    switch (d.stance) {
    case ST_ATTACK:
        heavy(110);
        m.vh_weight[VH_TURTLE] = m.vh_weight[VH_TURTLE] * 70 / 100;
        m.squad = m.squad * 90 / 100;
        break;
    case ST_DEFEND:
        heavy(85);
        m.vh_weight[VH_TURTLE] = m.vh_weight[VH_TURTLE] * 130 / 100;
        m.vh_weight[VH_COUNTERATTACK] = m.vh_weight[VH_COUNTERATTACK] * 130 / 100;
        break;
    case ST_RETREAT:
        heavy(30);
        m.vh_weight[VH_TURTLE] = m.vh_weight[VH_TURTLE] * 200 / 100;
        m.squad = m.squad * 170 / 100;
        m.running_delta = -1;
        break;
    default:
        break;
    }
    if (d.economy == ECO_MORE_REFINERIES) m.extra_refineries += 1;
    else if (d.economy == ECO_SAVE_MONEY) m.surplus = 150;
    if (!d.keep_using_air) {
        m.vh_weight[VH_AIR_STRIKE] = 0;
        m.queue[BQ_AIRCRAFT] = m.queue[BQ_AIRCRAFT] * 30 / 100;
    }


    if (d.base_threat >= 500) m.defense = 100 + (d.base_threat - 300) / 10;


    const int32_t s = std::max(0, p.cmd_weight_percent);
    if (p.cmd_counter_enabled && s >= 50) {
        switch (d.counter) {
        case CT_ANTI_AIR:
            m.aa_extra = 1;
            break;
        case CT_ANTI_SIEGE_SORTIE:
            m.raid_siege = 1;
            m.vh_weight[VH_ORE_RAID] = m.vh_weight[VH_ORE_RAID] * 300 / 100;
            break;
        case CT_SPREAD_DEFENSE:
            m.defense_spread = 1;
            m.defense = std::max(m.defense, 130);
            break;
        case CT_ANTI_INFILTRATION:
            m.guard_back = 1;
            break;
        case CT_ANTI_NAVAL:
            m.queue[BQ_NAVAL] = m.queue[BQ_NAVAL] * 200 / 100;
            m.defense = std::max(m.defense, 130);
            break;
        default:
            break;
        }
        m.defense_sector = std::clamp(d.defense_sector, 0, SEC_COUNT - 1);
        if (d.economy_fix == EF_SILO) m.silo_first = 1;
        else if (d.economy_fix == EF_REFINERY) m.extra_refineries = std::max(m.extra_refineries, 1);
        else if (d.economy_fix == EF_HARVESTER) m.extra_harvesters = 1;
        switch (d.special_op) {
        case SO_COMMANDO_RAID: m.vh_weight[VH_COMMANDO] = m.vh_weight[VH_COMMANDO] * 300 / 100; break;
        case SO_ENGINEER_CAPTURE: m.vh_weight[VH_ENGINEER] = m.vh_weight[VH_ENGINEER] * 300 / 100; break;

        case SO_SPY_INFILTRATE: m.vh_weight[VH_COMMANDO] = m.vh_weight[VH_COMMANDO] * 200 / 100; break;
        case SO_SUPERWEAPON_NOW: m.sp_threshold = 50; break;
        default: break;
        }
    }


    for (int32_t& v : m.vh_weight) v = blend(v, s);
    for (int32_t& v : m.queue) v = blend(v, s);
    m.squad = std::max(10, blend(m.squad, s));
    m.surplus = blend(m.surplus, s);
    m.defense = blend(m.defense, s);
    m.sp_threshold = std::max(1, blend(m.sp_threshold, s));
    m.running_delta = m.running_delta * s / 100;
    m.extra_refineries = m.extra_refineries * s / 100;
    return m;
}


void World::bot_commander_decide(int32_t owner, const BotStrategyFacts& f) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (!p.cmd_enabled) { b.cmd_mods = BotCommanderMods(); return; }
    if (!b.cmd_map.done) bot_commander_map(owner);
    b.cmd_summary = bot_commander_summary(owner, f);
    b.cmd_rule_decision = bot_rule_commander(b.cmd_summary, b.cmd_map, p);
    const bool ext = b.cmd_ext_valid_until > int32_t(tick_);
    b.cmd_decision = ext ? b.cmd_ext : b.cmd_rule_decision;

    if (ext && b.cmd_ext_words < CMD_DIRECTIVE_WORDS_V3) {
        std::copy(std::begin(b.cmd_rule_decision.counter), std::end(b.cmd_rule_decision.counter), b.cmd_decision.counter);
        std::copy(std::begin(b.cmd_rule_decision.defense_sector), std::end(b.cmd_rule_decision.defense_sector),
                  b.cmd_decision.defense_sector);
        std::copy(std::begin(b.cmd_rule_decision.economy_fix), std::end(b.cmd_rule_decision.economy_fix),
                  b.cmd_decision.economy_fix);
        std::copy(std::begin(b.cmd_rule_decision.special_op), std::end(b.cmd_rule_decision.special_op),
                  b.cmd_decision.special_op);
    }


    if ((!b.cmd_map.amphib_possible || !p.amphib_enabled) && b.cmd_decision.doctrine[DOC_AMPHIBIOUS] > 0) {
        int64_t pts[DOC_COUNT];
        for (int k = 0; k < DOC_COUNT; ++k) pts[k] = b.cmd_decision.doctrine[k];
        pts[DOC_AMPHIBIOUS] = 0;
        normalize(pts, b.cmd_decision.doctrine);
    }
    bot_commander_hysteresis(b.cmd_directive, b.cmd_decision, p, int32_t(tick_));
    b.cmd_directive.source = ext ? SRC_EXTERNAL : SRC_RULE;
    b.cmd_directive.valid_until_tick = ext ? b.cmd_ext_valid_until
                                           : int32_t(tick_) + 2 * std::max(1, p.strategy_interval);
    b.cmd_mods = bot_commander_mods(b.cmd_directive, p);
}


bool World::bot_commander_external(int32_t target, const int32_t* words, size_t n, int32_t valid_ticks,
                                   int32_t latency_ms) {
    if (target < 0 || target >= MAX_PLAYERS || words == nullptr) return false;
    BotState& b = players_[size_t(target)].bot;
    if (!b.enabled || n < size_t(CMD_DIRECTIVE_WORDS_V1) || valid_ticks <= 0) return false;
    const int docs = n >= size_t(CMD_DIRECTIVE_WORDS) ? DOC_COUNT : DOC_COUNT_V1;
    auto clamp1000 = [](int32_t v) { return int64_t(std::clamp(v, 0, 1000)); };
    int64_t doc[DOC_COUNT] = {}, eco[ECO_COUNT], st[ST_COUNT];
    int64_t sd = 0, se = 0, ss = 0;
    size_t k = 0;
    for (int i = 0; i < docs; ++i) { doc[i] = clamp1000(words[k++]); sd += doc[i]; }
    for (int i = 0; i < ECO_COUNT; ++i) { eco[i] = clamp1000(words[k++]); se += eco[i]; }
    for (int i = 0; i < ST_COUNT; ++i) { st[i] = clamp1000(words[k++]); ss += st[i]; }
    if (sd <= 0 || se <= 0 || ss <= 0) return false;
    BotDecision d;
    normalize(doc, d.doctrine);
    normalize(eco, d.economy);
    normalize(st, d.stance);
    d.keep_using_air = int32_t(clamp1000(words[k++]));
    d.base_threat = int32_t(clamp1000(words[k++]));


    int32_t words_used = docs == DOC_COUNT ? CMD_DIRECTIVE_WORDS : CMD_DIRECTIVE_WORDS_V1;
    if (n >= size_t(CMD_DIRECTIVE_WORDS_V3) && docs == DOC_COUNT) {
        int64_t ct[CT_COUNT], sec[SEC_COUNT], ef[EF_COUNT], so[SO_COUNT];
        int64_t sc = 0, ss2 = 0, sf = 0, so_sum = 0;
        for (int i = 0; i < CT_COUNT; ++i) { ct[i] = clamp1000(words[k++]); sc += ct[i]; }
        for (int i = 0; i < SEC_COUNT; ++i) { sec[i] = clamp1000(words[k++]); ss2 += sec[i]; }
        for (int i = 0; i < EF_COUNT; ++i) { ef[i] = clamp1000(words[k++]); sf += ef[i]; }
        for (int i = 0; i < SO_COUNT; ++i) { so[i] = clamp1000(words[k++]); so_sum += so[i]; }
        if (sc <= 0 || ss2 <= 0 || sf <= 0 || so_sum <= 0) return false;
        normalize(ct, d.counter);
        normalize(sec, d.defense_sector);
        normalize(ef, d.economy_fix);
        normalize(so, d.special_op);
        words_used = CMD_DIRECTIVE_WORDS_V3;
    }
    b.cmd_ext_words = words_used;
    b.cmd_ext = d;
    b.cmd_ext_valid_until = int32_t(tick_) + std::min(valid_ticks, 60 * 60 * TICKS_PER_SECOND);
    b.cmd_ext_latency_ms = std::max(0, latency_ms);
    b.cmd_ext_tick = int32_t(tick_);
    return true;
}


int32_t World::bot_surplus_cash(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    if (b.p.surplus_cash <= 0) return b.p.surplus_cash;
    return int32_t(int64_t(b.p.surplus_cash) * std::max(1, b.cmd_mods.surplus) / 100);
}

int32_t World::bot_extra_refineries(int32_t owner) const {
    return std::max(0, players_[size_t(owner)].bot.cmd_mods.extra_refineries);
}


namespace {

constexpr int32_t SEC_DX[SEC_COUNT] = {0, 0, 7, 10, 7, 0, -7, -10, -7};
constexpr int32_t SEC_DY[SEC_COUNT] = {0, -10, -7, 0, 7, 10, 7, 0, -7};

constexpr int32_t SEC_ANCHOR_CELLS = 6;

constexpr int64_t SOFT_RADIUS_SQ = 7 * 7;

inline void add_sat(int32_t& v, int64_t d) { v = int32_t(std::clamp<int64_t>(int64_t(v) + d, 0, INT32_MAX)); }

template <size_t N> int64_t ring_sum(const int32_t (&r)[N]) {
    int64_t t = 0;
    for (size_t k = 0; k < N; ++k) t += r[k];
    return t;
}
}


int32_t World::cmd_sector_of(int64_t dx, int64_t dy) {
    if (dx == 0 && dy == 0) return SEC_NONE;
    const int64_t ax = dx < 0 ? -dx : dx, ay = dy < 0 ? -dy : dy;
    if (ax * 12 <= ay * 5) return dy < 0 ? SEC_N : SEC_S;
    if (ay * 12 <= ax * 5) return dx > 0 ? SEC_E : SEC_W;
    if (dy < 0) return dx > 0 ? SEC_NE : SEC_NW;
    return dx > 0 ? SEC_SE : SEC_SW;
}

void World::cmd_sector_dir(int32_t sec, int32_t& dx10, int32_t& dy10) {
    const int32_t k = sec >= 0 && sec < SEC_COUNT ? sec : 0;
    dx10 = SEC_DX[k];
    dy10 = SEC_DY[k];
}


int32_t World::cmd_enemy_class(int32_t type, const BotParams& p) const {
    if (type < 0 || size_t(type) >= types_.size()) return -1;
    const UnitType& t = types_[size_t(type)];
    if (t.building || t.husk || t.harvester) return -1;
    if (t.infiltrates != 0 && t.demolition_delay < 0) return EC_SPY;
    if (t.captures) return EC_ENGINEER;
    if (t.demolition_delay >= 0) return EC_COMMANDO;
    if (t.queue_kind == QUEUE_INFANTRY && t.build_limit == 1 && t.weapon >= 0) return EC_COMMANDO;
    if (t.aircraft) return t.weapon >= 0 ? int32_t(EC_AIR) : -1;
    if (t.weapon < 0) return -1;
    const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
    int32_t ground_range = 0;
    for (int32_t wi : arms) {
        if (wi < 0 || size_t(wi) >= weapons_.size()) continue;
        const Weapon& w = weapons_[size_t(wi)];
        if ((w.valid_targets & (TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE)) == 0) continue;
        ground_range = std::max<int32_t>(ground_range, w.range);
    }
    if (ground_range >= std::max(1, p.cmd_siege_range_cells) * CELL) return EC_SIEGE;
    if (t.locomotor == LOCO_NAVAL) return t.cloak ? int32_t(EC_SUBS) : int32_t(EC_NAVAL);
    if (ground_range <= 0) return -1;
    return t.queue_kind == QUEUE_INFANTRY ? int32_t(EC_INFANTRY) : int32_t(EC_ARMOR);
}


int32_t World::cmd_threat_class(int32_t type, const BotParams& p) const {
    if (type < 0 || size_t(type) >= types_.size()) return TC_LAND;
    const UnitType& t = types_[size_t(type)];
    if (t.aircraft) return TC_AIR;
    if (!t.building && t.locomotor == LOCO_NAVAL) return TC_NAVAL;
    if (!t.building && cmd_enemy_class(type, p) == EC_SIEGE) return TC_SIEGE;
    return TC_LAND;
}

const BotParams& World::commander_params_for(int32_t pl) const {
    static const BotParams defaults;
    if (pl >= 0 && pl < MAX_PLAYERS && players_[size_t(pl)].bot.enabled) return players_[size_t(pl)].bot.p;
    for (int32_t q = 0; q < MAX_PLAYERS; ++q)
        if (players_[size_t(q)].bot.enabled) return players_[size_t(q)].bot.p;
    return defaults;
}


CmdTrack* World::cmd_track_of(int32_t pl) {
    if (pl < 0 || pl >= MAX_PLAYERS) return nullptr;
    BotState& b = players_[size_t(pl)].bot;
    if (b.enabled) return b.p.cmd_enabled ? &b.cmd_track : nullptr;
    return cmd_human_[size_t(pl)].on ? &cmd_human_[size_t(pl)].track : nullptr;
}


void World::cmd_track_tick(int32_t pl) {
    CmdTrack* tr = cmd_track_of(pl);
    if (tr == nullptr || --tr->bucket_ticks > 0) return;
    tr->bucket_ticks = CMD_BUCKET_TICKS;
    const int32_t pos = std::clamp(tr->pos, 0, CMD_BUCKETS - 1);
    const int64_t e = earned(pl);
    tr->income[pos] = int32_t(std::clamp<int64_t>(e - tr->snap_earned, 0, INT32_MAX));
    tr->snap_earned = e;
    const int32_t nx = (pos + 1) % CMD_BUCKETS;
    tr->pos = nx;
    for (int c = 0; c < TC_COUNT; ++c) tr->dmg_class[c][nx] = 0;
    for (int k = 0; k < CMD_SECTORS; ++k) tr->dmg_sector[k][0][nx] = tr->dmg_sector[k][1][nx] = 0;
    for (int d = 0; d < DOM_COUNT; ++d) tr->lost[d][nx] = 0;
    tr->harv_lost[nx] = tr->outranged[nx] = tr->income[nx] = tr->kills[nx] = tr->damage[nx] = 0;

    int64_t sx = 0, sy = 0, n = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != pl) continue;
        const UnitType& t = types_[a.type];
        if (!t.building || t.wall || t.husk) continue;
        sx += a.origin.x + t.foot_w / 2;
        sy += a.origin.y + t.foot_h / 2;
        ++n;
    }
    if (n > 0) {
        tr->cx = int32_t(sx / n);
        tr->cy = int32_t(sy / n);
    } else if (players_[size_t(pl)].bot.initial_base_center.x >= 0) {
        tr->cx = players_[size_t(pl)].bot.initial_base_center.x;
        tr->cy = players_[size_t(pl)].bot.initial_base_center.y;
    }
}


void World::cmd_track_note_hit(size_t victim, int64_t dmg, int32_t attacker_index) {
    const Actor& v = actors_[victim];
    if (dmg <= 0 || v.owner < 0 || v.owner >= MAX_PLAYERS) return;
    CmdTrack* tr = cmd_track_of(v.owner);
    if (tr == nullptr) return;
    const int32_t pos = std::clamp(tr->pos, 0, CMD_BUCKETS - 1);
    const UnitType& vt = types_[v.type];
    add_sat(tr->damage[pos], dmg);
    tr->last_hit_tick = int32_t(tick_);
    const BotParams& p = commander_params_for(v.owner);
    const bool known = attacker_index >= 0 && size_t(attacker_index) < actors_.size();
    const int32_t cls = known ? cmd_threat_class(actors_[size_t(attacker_index)].type, p) : int32_t(TC_LAND);
    add_sat(tr->dmg_class[cls][pos], dmg);
    if (tr->cx < 0) return;
    int64_t dx = v.origin.x + vt.foot_w / 2 - tr->cx, dy = v.origin.y + vt.foot_h / 2 - tr->cy;
    if (dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1 && known) {

        const Actor& at = actors_[size_t(attacker_index)];
        const CPos ac = types_[at.type].building ? at.origin : mobiles_[size_t(attacker_index)].cell;
        dx = ac.x - tr->cx;
        dy = ac.y - tr->cy;
    }
    const int32_t sec = cmd_sector_of(dx, dy);
    if (sec != SEC_NONE) add_sat(tr->dmg_sector[sec - 1][cls == TC_AIR ? 0 : 1][pos], dmg);
}


void World::cmd_track_note_death(size_t victim, int32_t attacker_id) {
    const Actor& dead = actors_[victim];
    const UnitType& t = types_[dead.type];
    if (t.husk) return;
    const int ai = attacker_id >= 0 ? index_of(attacker_id) : -1;
    if (dead.owner >= 0 && dead.owner < MAX_PLAYERS) {
        if (CmdTrack* tr = cmd_track_of(dead.owner)) {
            const int32_t pos = std::clamp(tr->pos, 0, CMD_BUCKETS - 1);
            if (t.harvester) add_sat(tr->harv_lost[pos], 1);
            if (!t.building)
                add_sat(tr->lost[t.aircraft ? DOM_AIR : (t.locomotor == LOCO_NAVAL ? DOM_NAVAL : DOM_LAND)][pos], 1);
            if (t.building && t.defense && ai >= 0) {
                const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
                int64_t range = 0;
                for (int32_t wi : arms)
                    if (wi >= 0 && size_t(wi) < weapons_.size()) range = std::max<int64_t>(range, weapons_[size_t(wi)].range);
                if (range > 0 && length(actors_[size_t(ai)].pos - dead.pos) > range + CELL / 2)
                    add_sat(tr->outranged[pos], 1);
            }
        }
    }
    if (ai < 0) return;
    const int32_t killer = actors_[size_t(ai)].owner;
    if (killer < 0 || killer >= MAX_PLAYERS || killer == dead.owner || !hostile(killer, dead.owner)) return;
    if (CmdTrack* kt = cmd_track_of(killer)) add_sat(kt->kills[std::clamp(kt->pos, 0, CMD_BUCKETS - 1)], 1);
}


void World::commander_perceive(int32_t pl, const BotParams& p, const CmdTrack& tr, BotSummary& s) const {
    const bool is_bot = players_[size_t(pl)].bot.enabled;
    auto sees = [&](size_t i) { return is_bot ? bot_sees(pl, i) : actor_visible_to(pl, i); };
    auto knows = [&](size_t i) { return is_bot ? bot_knows(pl, i) : actor_visible_to(pl, i); };
    struct Tower { CPos at; bool aa; int64_t r2; };
    std::vector<Tower> towers;
    std::vector<CPos> own_blds, foe_defs, foe_blds;
    int64_t cls[EC_COUNT] = {};
    int32_t specials[3] = {0, 0, 0}, silos = 0, ground_towers = 0, aa_towers = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.husk) continue;
        const CPos mid = t.building ? CPos{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2} : mobiles_[i].cell;
        if (a.owner == pl) {
            if (t.building) {
                if (t.defense) {
                    if (a.sell_ticks >= 0) continue;
                    const bool aa = bot_defense_role(a.type) == 2;
                    const int64_t r = bot_defense_range_cells(a.type);
                    towers.push_back({mid, aa, r * r});
                    ++(aa ? aa_towers : ground_towers);
                } else if (!t.wall) {
                    own_blds.push_back(mid);
                    if (t.storage > 0 && !t.refinery) ++silos;
                }
                continue;
            }
            const int32_t c = cmd_enemy_class(a.type, p);
            if (c == EC_COMMANDO) ++specials[0];
            else if (c == EC_ENGINEER) ++specials[1];
            else if (c == EC_SPY) ++specials[2];
            continue;
        }
        if (!hostile(pl, a.owner)) continue;
        if (t.building) {
            if (!knows(i)) continue;
            s.enemy_base_known = 1;
            if (t.defense) foe_defs.push_back(mid);
            else if (!t.wall) foe_blds.push_back(mid);
            continue;
        }
        if (!sees(i)) continue;
        const int32_t c = cmd_enemy_class(a.type, p);
        if (c < 0) continue;
        cls[c] += c >= EC_COMMANDO ? 1 : std::max(1, t.cost);
    }
    for (int c = 0; c < EC_COUNT; ++c) {
        s.raw_enemy_class[c] = int32_t(std::min<int64_t>(cls[c], INT32_MAX));
        s.enemy_class[c] = bot_level(cls[c], c >= EC_COMMANDO ? p.cmd_special_lv : p.cmd_class_lv);
    }
    for (int k = 0; k < 3; ++k) s.own_special[k] = bot_level(specials[k], p.cmd_special_lv);


    {
        const BotState& bs = players_[size_t(pl)].bot;
        s.raw_engineer_op = (bs.enabled && bs.p.eng_plan > 0) ? bs.eng_ready : s.enemy_base_known;
    }
    s.raw_own_defense[0] = ground_towers;
    s.raw_own_defense[1] = aa_towers;
    s.own_defense[0] = bot_level(ground_towers, p.cmd_tower_lv);
    s.own_defense[1] = bot_level(aa_towers, p.cmd_tower_lv);


    int64_t dc[TC_COUNT] = {}, ds[CMD_SECTORS][2] = {};
    for (int c = 0; c < TC_COUNT; ++c) dc[c] = ring_sum(tr.dmg_class[c]);
    for (int k = 0; k < CMD_SECTORS; ++k)
        for (int j = 0; j < 2; ++j) ds[k][j] = ring_sum(tr.dmg_sector[k][j]);
    int64_t best = 0;
    for (int c = 0; c < TC_COUNT; ++c) {
        s.raw_dmg_class[c] = int32_t(std::min<int64_t>(dc[c], INT32_MAX));
        s.dmg_class[c] = bot_level(dc[c], p.cmd_dmg_class_lv);
        if (dc[c] > best) { best = dc[c]; s.dmg_main_class = c; }
    }
    best = 0;
    for (int k = 0; k < CMD_SECTORS; ++k) {
        const int64_t tot = ds[k][0] + ds[k][1];
        if (tot > best) { best = tot; s.dmg_sector = k + 1; }
        if (tot >= std::max(1, p.cmd_sector_min_damage)) ++s.sectors_hit;
    }
    const int64_t outr = ring_sum(tr.outranged), harv = ring_sum(tr.harv_lost);
    s.raw_outranged = int32_t(outr);
    s.defense_outranged = bot_level(outr, p.cmd_special_lv);
    s.raw_harv_lost = int32_t(harv);
    s.harv_losses_60s = bot_level(harv, p.cmd_special_lv);


    const bool centered = tr.cx >= 0;
    auto covered = [&](int32_t sec, bool aa) {
        const CPos anchor{tr.cx + SEC_DX[sec] * SEC_ANCHOR_CELLS / 10, tr.cy + SEC_DY[sec] * SEC_ANCHOR_CELLS / 10};
        for (const Tower& tw : towers) {
            if (tw.aa != aa) continue;
            if (cmd_sector_of(tw.at.x - tr.cx, tw.at.y - tr.cy) == sec) return true;
            const int64_t dx = tw.at.x - anchor.x, dy = tw.at.y - anchor.y;
            if (dx * dx + dy * dy <= tw.r2) return true;
        }
        return false;
    };
    if (centered) {
        int64_t worst = 0;
        for (int k = 0; k < CMD_SECTORS; ++k) {
            const int32_t sec = k + 1;
            const int64_t min_dmg = std::max(1, p.cmd_sector_min_damage);

            if (ds[k][0] >= min_dmg && ds[k][0] > worst && !covered(sec, true)) {
                worst = ds[k][0]; s.uncovered_sector = sec; s.uncovered_class = TC_AIR;
            }
            if (ds[k][1] >= min_dmg && ds[k][1] > worst && !covered(sec, false)) {
                worst = ds[k][1]; s.uncovered_sector = sec; s.uncovered_class = TC_LAND;
            }
        }


        int32_t open = 0, open_best = 0;
        for (int k = 0; k < CMD_SECTORS; ++k) {
            const int32_t sec = k + 1;
            int32_t n = 0;
            int64_t far2 = 0;
            for (const CPos& c : own_blds) {
                const int64_t dx = c.x - tr.cx, dy = c.y - tr.cy;
                if (cmd_sector_of(dx, dy) != sec) continue;
                ++n;
                far2 = std::max(far2, dx * dx + dy * dy);
            }
            if (n == 0 || covered(sec, false)) continue;
            const int32_t far = isqrt(far2);
            bool edge = false;
            for (int32_t step = 2; step <= 6 && !edge; step += 2) {
                const CPos q{tr.cx + SEC_DX[sec] * (far + step) / 10, tr.cy + SEC_DY[sec] * (far + step) / 10};
                if (!map_.in_bounds(q)) edge = true;
                else if (!map_.passable(q, MC_LAND) && map_.passable(q, MC_NAVAL)) edge = true;
            }
            if (!edge) continue;
            ++open;
            if (n > open_best) { open_best = n; s.open_back_sector = sec; }
        }
        s.raw_open_back = open;
        s.open_back = bot_level(open, p.cmd_special_lv);
    }
    int32_t aa_n = 0, spread = 0, unc = 0;
    bot_defense_stats(pl, aa_n, spread, unc);
    s.raw_uncovered = unc;
    s.uncovered_buildings = bot_level(unc, p.cmd_special_lv);


    const int64_t cap = storage_capacity(pl);
    if (has_storage_ && cap > 0) {
        s.raw_storage_permille = int32_t(std::min<int64_t>(resources_stored(pl) * 1000 / cap, 1000));
        s.ore_wasting = s.raw_storage_permille >= p.cmd_storage_full_permille ? 1 : 0;
    }
    s.raw_silos = silos;
    s.silos = bot_level(silos, p.cmd_special_lv);


    const int32_t kinds[3] = {SP_NUKE, SP_IRON_CURTAIN, SP_CHRONOSHIFT};
    for (int32_t kind : kinds) {
        int av = 0, rd = 0, pm = 0, pa = 0;
        support_power_state(pl, kind, av, rd, pm, pa);
        if (av) s.own_superweapon = std::max<int32_t>(s.own_superweapon, rd ? SW_READY : SW_CHARGING);
    }
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner < 0 || a.owner >= MAX_PLAYERS || !hostile(pl, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (!t.building || t.support_power < 0) continue;
        if (t.support_power != SP_NUKE && t.support_power != SP_IRON_CURTAIN && t.support_power != SP_CHRONOSHIFT) continue;
        if (!knows(i)) continue;
        const SupportPowerState& st = players_[size_t(a.owner)].powers[t.support_power];
        s.enemy_superweapon = std::max<int32_t>(s.enemy_superweapon, st.ready ? SW_READY : SW_CHARGING);
    }


    int32_t soft = 0;
    for (const CPos& b : foe_blds) {
        bool guarded = false;
        for (const CPos& d : foe_defs) {
            const int64_t dx = d.x - b.x, dy = d.y - b.y;
            if (dx * dx + dy * dy <= SOFT_RADIUS_SQ) { guarded = true; break; }
        }
        if (!guarded) ++soft;
    }
    s.raw_enemy_soft = soft;
    s.enemy_soft = bot_level(soft, p.cmd_tower_lv);
}


void World::commander_rules_v3(const BotSummary& s, const BotMapInfo& m, const BotParams& p, BotDecision& d) {
    const bool water = m.water_permille * 2 >= p.cmd_water_mixed_permille;
    const int32_t infil = std::max({s.enemy_class[EC_COMMANDO], s.enemy_class[EC_ENGINEER], s.enemy_class[EC_SPY]});

    int64_t ct[CT_COUNT] = {400, 0, 0, 0, 0, 0};
    if (s.dmg_class[TC_AIR] >= LV_LOW) {
        ct[CT_ANTI_AIR] += 450;
        if (s.uncovered_class == TC_AIR) ct[CT_ANTI_AIR] += 600;
    }
    if (s.enemy_class[EC_AIR] >= LV_MEDIUM && s.own_defense[1] == LV_NONE) ct[CT_ANTI_AIR] += 300;

    if (s.enemy_class[EC_SIEGE] >= LV_MEDIUM && s.defense_outranged >= LV_LOW && s.dmg_main_class != TC_NAVAL)
        ct[CT_ANTI_SIEGE_SORTIE] += 900;
    if (s.dmg_class[TC_SIEGE] >= LV_LOW) ct[CT_ANTI_SIEGE_SORTIE] += 500;
    if (s.enemy_class[EC_SIEGE] >= LV_HIGH) ct[CT_ANTI_SIEGE_SORTIE] += 200;

    if (s.sectors_hit >= 3) ct[CT_SPREAD_DEFENSE] += 500;
    if (s.sectors_hit >= 2 && s.uncovered_class == TC_LAND) ct[CT_SPREAD_DEFENSE] += 200;

    if (infil >= LV_LOW) ct[CT_ANTI_INFILTRATION] += 600;
    if (s.open_back >= LV_LOW) ct[CT_ANTI_INFILTRATION] += infil >= LV_LOW ? 300 : 150;

    if (s.dmg_class[TC_NAVAL] >= LV_LOW) ct[CT_ANTI_NAVAL] += 700;
    if (water && (s.enemy_class[EC_NAVAL] >= LV_MEDIUM || s.enemy_class[EC_SUBS] >= LV_LOW)) ct[CT_ANTI_NAVAL] += 250;
    if (s.defense_outranged >= LV_LOW && s.dmg_main_class == TC_NAVAL) ct[CT_ANTI_NAVAL] += 300;
    normalize(ct, d.counter);


    int64_t sec[SEC_COUNT] = {300, 0, 0, 0, 0, 0, 0, 0, 0};
    if (s.uncovered_sector > SEC_NONE && s.uncovered_sector < SEC_COUNT) sec[s.uncovered_sector] += 900;
    else if (s.dmg_sector > SEC_NONE && s.dmg_sector < SEC_COUNT && s.sectors_hit >= 1) sec[s.dmg_sector] += 500;
    if (s.open_back_sector > SEC_NONE && s.open_back_sector < SEC_COUNT && infil >= LV_LOW) sec[s.open_back_sector] += 600;
    normalize(sec, d.defense_sector);


    int64_t ef[EF_COUNT] = {400, 0, 0, 0};
    if (s.ore_wasting) ef[EF_SILO] += 900;
    if (s.opening_done && s.refineries <= LV_LOW && s.credits <= LV_MEDIUM && m.ore_fields > 0 && !s.ore_wasting)
        ef[EF_REFINERY] += 500;
    if (s.harv_losses_60s >= LV_LOW) ef[EF_HARVESTER] += 500;
    normalize(ef, d.economy_fix);


    int64_t so[SO_COUNT] = {500, 0, 0, 0, 0};
    if (s.own_superweapon == SW_READY && s.enemy_base_known) so[SO_SUPERWEAPON_NOW] += 900;
    if (s.own_special[0] >= LV_LOW && s.enemy_soft >= LV_LOW) so[SO_COMMANDO_RAID] += 700;


    if (s.own_special[1] >= LV_LOW && s.raw_engineer_op > 0) so[SO_ENGINEER_CAPTURE] += 600;
    if (s.own_special[2] >= LV_LOW && s.enemy_base_known) so[SO_SPY_INFILTRATE] += 600;
    normalize(so, d.special_op);
}


void World::commander_human_track(int32_t pl, bool on) {
    if (pl < 0 || pl >= MAX_PLAYERS) return;
    CmdHuman& h = cmd_human_[size_t(pl)];
    if (on && !h.on) {
        h = CmdHuman();
        h.track.snap_earned = earned(pl);
    }
    h.on = on ? 1 : 0;
}

bool World::commander_human_tracked(int32_t pl) const {
    return pl >= 0 && pl < MAX_PLAYERS && cmd_human_[size_t(pl)].on != 0;
}

const CmdHumanActs& World::commander_human_acts(int32_t pl) const {
    static const CmdHumanActs none;
    return pl >= 0 && pl < MAX_PLAYERS ? cmd_human_[size_t(pl)].acts : none;
}


BotSummary World::commander_summary_for_player(int32_t pl) {
    BotSummary s;
    if (pl < 0 || pl >= MAX_PLAYERS) return s;
    CmdHuman& h = cmd_human_[size_t(pl)];
    const BotParams& p = commander_params_for(pl);
    const CmdTrack& tr = h.track;
    if (!h.map.done && tr.cx >= 0) h.map = commander_map_info(pl, CPos{tr.cx, tr.cy}, p);
    s.tick = int32_t(tick_);
    int64_t army[DOM_COUNT] = {0, 0, 0}, enemy[DOM_COUNT] = {0, 0, 0};
    int32_t aa = 0, refineries = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.husk) continue;
        const bool combat_unit = !t.building && !t.harvester && t.weapon >= 0;
        if (a.owner == pl) {
            if (combat_unit) army[domain_of(t)] += t.cost;
            if (t.refinery) ++refineries;
            continue;
        }
        if (!hostile(pl, a.owner) || !actor_visible_to(pl, i)) continue;
        if (combat_unit) enemy[domain_of(t)] += t.cost;
        const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
        for (int32_t wi : arms)
            if (wi >= 0 && size_t(wi) < weapons_.size() && (weapons_[size_t(wi)].valid_targets & TT_AIRBORNE)) { ++aa; break; }
    }
    const int64_t cr = credits(pl);
    s.credits = bot_level(cr, p.cmd_credits_lv);
    s.raw_credits = int32_t(std::clamp<int64_t>(cr, 0, INT32_MAX));
    s.refineries = bot_level(refineries, p.cmd_refinery_lv);
    s.raw_refineries = refineries;
    s.power_ok = power_provided(pl) >= power_drained(pl) ? 1 : 0;
    for (int d = 0; d < DOM_COUNT; ++d) {
        s.army[d] = bot_level(army[d], p.cmd_army_lv);
        s.enemy[d] = bot_level(enemy[d], p.cmd_army_lv);
        s.raw_army[d] = int32_t(std::min<int64_t>(army[d], INT32_MAX));
        s.raw_enemy[d] = int32_t(std::min<int64_t>(enemy[d], INT32_MAX));
    }
    s.raw_enemy_aa = aa;
    s.enemy_anti_air = bot_level(aa, p.cmd_aa_lv);
    s.enemy_attacking = tr.last_hit_tick > 0 &&
                        int32_t(tick_) - tr.last_hit_tick <= std::max(0, p.cmd_attack_recent_ticks) ? 1 : 0;

    const int32_t pos = std::clamp(tr.pos, 0, CMD_BUCKETS - 1);
    int64_t income = std::max<int64_t>(0, earned(pl) - tr.snap_earned), old_half = 0, new_half = income;
    for (int k = 1; k < CMD_BUCKETS; ++k) {
        const int idx = (pos + k) % CMD_BUCKETS;
        income += tr.income[idx];
        (k <= CMD_BUCKETS / 2 ? old_half : new_half) += tr.income[idx];
    }
    s.income_60s = int32_t(std::min<int64_t>(income, INT32_MAX));
    const int64_t tp = std::clamp(p.cmd_trend_percent, 0, 100);
    if (new_half * 100 > old_half * (100 + tp)) s.income = TR_RISING;
    else if (new_half * 100 < old_half * (100 - tp)) s.income = TR_FALLING;
    else s.income = TR_FLAT;
    const int64_t lost_air = ring_sum(tr.lost[DOM_AIR]);
    const int64_t lost_land = ring_sum(tr.lost[DOM_LAND]) + ring_sum(tr.lost[DOM_NAVAL]);
    const int64_t kills = ring_sum(tr.kills), damage = ring_sum(tr.damage);
    s.air_losses_60s = bot_level(lost_air, p.cmd_loss_lv);
    s.land_losses_60s = bot_level(lost_land, p.cmd_loss_lv);
    s.kills_60s = bot_level(kills, p.cmd_kill_lv);
    s.base_damage_60s = bot_level(damage, p.cmd_damage_lv);
    s.raw_air_lost = int32_t(lost_air);
    s.raw_land_lost = int32_t(lost_land);
    s.raw_kills = int32_t(kills);
    s.raw_base_damage = int32_t(std::min<int64_t>(damage, INT32_MAX));
    int32_t threat = s.base_damage_60s * 200;
    if (s.enemy_attacking) threat = std::max(threat, 400);
    s.base_threat = std::min(1000, threat);
    s.opening_done = bot_opening_done(pl) ? 1 : 0;
    s.doctrine = h.doctrine_hint;
    s.doctrine_age_s = std::max(0, int32_t(tick_) - h.doctrine_since) / TICKS_PER_SECOND;
    commander_perceive(pl, p, tr, s);
    return s;
}


void World::cmd_human_note_order(int32_t pl, int32_t op, int32_t a, int32_t b, int32_t c, const int32_t* ids, size_t ni) {
    if (pl < 0 || pl >= MAX_PLAYERS) return;
    CmdHuman& h = cmd_human_[size_t(pl)];
    if (!h.on || players_[size_t(pl)].bot.enabled) return;
    CmdHumanActs& x = h.acts;
    const BotParams& p = commander_params_for(pl);
    const CmdTrack& tr = h.track;
    auto sector_at = [&](CPos cell) { return tr.cx < 0 ? int32_t(SEC_NONE) : cmd_sector_of(cell.x - tr.cx, cell.y - tr.cy); };
    if (op == 30 && a >= 0 && size_t(a) < types_.size()) {
        const UnitType& t = types_[size_t(a)];
        if (t.harvester) ++x.harvester;
        if (!t.building && t.locomotor == LOCO_NAVAL && t.weapon >= 0) ++x.naval_units;
        return;
    }
    if (op == 33 && a >= 0 && size_t(a) < types_.size()) {
        const UnitType& t = types_[size_t(a)];
        const int32_t sec = sector_at(CPos{b + t.foot_w / 2, c + t.foot_h / 2});
        if (t.defense) {
            if (bot_defense_role(a) == 2) {
                if (x.aa_built++ == 0) x.aa_sector = sec;
            } else {
                if (x.towers_built++ == 0) x.tower_sector = sec;
                if (sec != SEC_NONE) x.tower_sectors |= 1u << sec;
                if (sec != SEC_NONE && h.has_last && sec == h.last.open_back_sector) ++x.back_tower;
            }
        }
        if (t.storage > 0 && !t.refinery) ++x.silo;
        if (t.refinery) ++x.refinery;
        if ((t.produces & (1u << QUEUE_AIRCRAFT)) != 0) ++x.airfield;
        if ((t.produces & (1u << QUEUE_SHIP)) != 0) ++x.shipyard;
        return;
    }
    if (op == 40) {
        if (a == SP_NUKE || a == SP_IRON_CURTAIN || a == SP_CHRONOSHIFT) ++x.superweapon;
        return;
    }
    const bool move_like = op >= 0 && op <= 3;
    const bool enter_like = op >= 10 && op <= 13;
    if ((!move_like && !enter_like) || ni == 0) return;

    CPos goal{-1, -1};
    bool hostile_target = false;
    if (op == 0 || op == 1 || op == 3) goal = CPos{a, b};
    else {
        const int ti = index_of(a);
        if (ti < 0) return;
        const Actor& ta = actors_[size_t(ti)];
        const UnitType& tt = types_[ta.type];
        goal = tt.building ? ta.origin : mobiles_[size_t(ti)].cell;
        hostile_target = hostile(pl, ta.owner);
        if (op == 2 && hostile_target && !tt.building && cmd_enemy_class(ta.type, p) == EC_SIEGE) ++x.siege_hunt;
    }


    bool at_enemy = hostile_target && enter_like;
    for (size_t i = 0; i < actors_.size() && !at_enemy; ++i) {
        const Actor& e = actors_[i];
        if (!e.alive || !types_[e.type].building || !hostile(pl, e.owner) || !actor_visible_to(pl, i)) continue;
        const int64_t dx = e.origin.x - goal.x, dy = e.origin.y - goal.y;
        if (dx * dx + dy * dy <= 15 * 15) at_enemy = true;
    }
    const bool at_home = !at_enemy && tr.cx >= 0 &&
                         int64_t(goal.x - tr.cx) * (goal.x - tr.cx) + int64_t(goal.y - tr.cy) * (goal.y - tr.cy) <= 10 * 10;
    for (size_t k = 0; k < ni; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0) continue;
        const UnitType& t = types_[actors_[size_t(i)].type];
        const int32_t cls = cmd_enemy_class(actors_[size_t(i)].type, p);
        if (at_enemy) {
            if (cls == EC_COMMANDO) ++x.commando;
            else if (cls == EC_ENGINEER) ++x.engineer;
            else if (cls == EC_SPY) ++x.spy;
            else if (move_like && !t.building && !t.harvester && t.weapon >= 0) ++x.attack_units;
        } else if (at_home && move_like && !t.building && !t.harvester && t.weapon >= 0) {
            ++x.home_units;
        }
    }
}


BotDecision World::commander_human_answers(int32_t pl, const BotSummary& prev, int32_t (&asked)[9]) const {
    BotDecision d;
    for (int32_t& v : asked) v = 0;
    if (pl < 0 || pl >= MAX_PLAYERS) return d;
    const CmdHumanActs& x = cmd_human_[size_t(pl)].acts;
    auto one_hot = [](int32_t* out, int n, int k) { for (int i = 0; i < n; ++i) out[i] = i == k ? 1000 : 0; };
    int ct = CT_NONE;
    int tower_sectors = 0;
    for (int k = 1; k < SEC_COUNT; ++k) tower_sectors += (x.tower_sectors >> k) & 1u;
    const bool naval_threat = prev.dmg_class[TC_NAVAL] >= LV_LOW || prev.enemy_class[EC_NAVAL] >= LV_LOW ||
                              prev.enemy_class[EC_SUBS] >= LV_LOW;
    if (x.aa_built > 0) ct = CT_ANTI_AIR;
    else if (x.siege_hunt > 0) ct = CT_ANTI_SIEGE_SORTIE;
    else if (tower_sectors >= 2) ct = CT_SPREAD_DEFENSE;
    else if (x.back_tower > 0) ct = CT_ANTI_INFILTRATION;
    else if (x.naval_units > 0 && naval_threat) ct = CT_ANTI_NAVAL;
    one_hot(d.counter, CT_COUNT, ct);
    asked[5] = 1;
    one_hot(d.defense_sector, SEC_COUNT, x.aa_built > 0 ? x.aa_sector : (x.towers_built > 0 ? x.tower_sector : SEC_NONE));
    asked[6] = 1;
    one_hot(d.economy_fix, EF_COUNT, x.silo > 0 ? EF_SILO : x.refinery > 0 ? EF_REFINERY : x.harvester > 0 ? EF_HARVESTER : EF_NONE);
    asked[7] = 1;
    int so = SO_NONE;
    if (x.superweapon > 0) so = SO_SUPERWEAPON_NOW;
    else if (x.commando > 0) so = SO_COMMANDO_RAID;
    else if (x.engineer > 0) so = SO_ENGINEER_CAPTURE;
    else if (x.spy > 0) so = SO_SPY_INFILTRATE;
    one_hot(d.special_op, SO_COUNT, so);
    asked[8] = 1;
    int st = ST_HOLD;
    if (x.attack_units >= 3) st = ST_ATTACK;
    else if (x.home_units >= 3 && prev.enemy_attacking) st = ST_DEFEND;
    one_hot(d.stance, ST_COUNT, st);
    asked[2] = 1;
    if (x.airfield > 0 || x.shipyard > 0) {
        one_hot(d.doctrine, DOC_COUNT, x.airfield >= x.shipyard ? DOC_AIR_DOMINANCE : DOC_NAVAL_DOMINANCE);
        asked[0] = 1;
    }
    return d;
}

bool World::commander_human_step(int32_t pl, BotSummary& prev, BotMapInfo& map, BotDecision& answers,
                                 int32_t (&asked)[9], BotDecision& rule) {
    if (pl < 0 || pl >= MAX_PLAYERS || !cmd_human_[size_t(pl)].on) return false;
    CmdHuman& h = cmd_human_[size_t(pl)];
    const bool had = h.has_last != 0;
    if (had) {
        prev = h.last;
        answers = commander_human_answers(pl, h.last, asked);
        map = h.map;
        rule = bot_rule_commander(h.last, h.map, commander_params_for(pl));
        if (asked[0]) {
            const int32_t doc = int32_t(argmax(answers.doctrine));
            if (doc != h.doctrine_hint) { h.doctrine_hint = doc; h.doctrine_since = int32_t(tick_); }
        }
    }
    h.acts = CmdHumanActs();
    h.last = commander_summary_for_player(pl);
    h.has_last = 1;
    return had;
}

}
