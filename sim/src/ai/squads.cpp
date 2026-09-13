

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


constexpr int32_t SIEGE_RANGE_CELLS = 9;

}


int32_t World::bot_count_aa(int32_t owner, WVec at, int32_t radius_cells) const {
    const int64_t r = int64_t(radius_cells) * CELL;
    int32_t n = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (t.aircraft || t.husk) continue;
        if (length(a.pos - at) > r) continue;
        const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
        for (int32_t wi : arms) {
            if (wi >= 0 && size_t(wi) < weapons_.size() && (weapons_[size_t(wi)].valid_targets & TT_AIRBORNE)) { ++n; break; }
        }
    }
    return n;
}


bool World::bot_unit_is_siege(size_t i) const {
    const UnitType& t = types_[actors_[i].type];
    if (t.building || t.aircraft || t.harvester || t.weapon < 0) return false;
    if (size_t(t.weapon) >= weapons_.size()) return false;
    const Weapon& w = weapons_[size_t(t.weapon)];


    if ((w.valid_targets & (TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE)) == 0) return false;
    return w.range >= SIEGE_RANGE_CELLS * CELL;
}


void World::bot_air_squads(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    BotSquad* air = nullptr;
    for (BotSquad& s : b.squads) if (s.type == BotSquad::AIR) { air = &s; break; }
    std::vector<int32_t> fresh;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];


        if (!t.aircraft || t.weapon < 0 || t.husk || t.exclude_from_squads) continue;
        if (std::find(b.active_units.begin(), b.active_units.end(), a.id) != b.active_units.end()) continue;
        fresh.push_back(a.id);
    }
    if (fresh.empty()) return;
    if (!air) {
        BotSquad ns;
        ns.type = BotSquad::AIR;
        b.squads.push_back(ns);
        air = &b.squads.back();
    }
    for (int32_t id : fresh) {
        air->units.push_back(id);
        b.active_units.push_back(id);
    }
}


void World::bot_update_air_squad(int32_t owner, BotSquad& s) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (s.units.empty()) return;

    int64_t cx = 0, cy = 0;
    int32_t n = 0;
    for (int32_t id : s.units) {
        const int i = index_of(id);
        if (i < 0) continue;
        cx += actors_[size_t(i)].pos.x;
        cy += actors_[size_t(i)].pos.y;
        ++n;
    }
    if (n == 0) return;
    const WVec center{WDist(cx / n), WDist(cy / n)};
    const int32_t count = int32_t(s.units.size());


    auto safe_at = [&](WVec at) {
        return bot_count_aa(owner, at, p.air_danger_radius) * p.aa_per_unit < count;
    };


    auto has_ammo = [&](size_t i) {
        const UnitType& t = types_[actors_[i].type];
        return t.ammo_max <= 0 || airs_[i].ammo > 0;
    };


    if (count < p.air_squad_size || !safe_at(center)) {
        s.state = BotSquad::IDLE;
        s.target = -1;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            if (!has_ammo(size_t(i)) && !airs_[size_t(i)].returning) air_return_to_base(size_t(i));
        }
        return;
    }


    const int ti = index_of(s.target);
    const bool valid = ti >= 0 && actors_[size_t(ti)].alive && hostile(owner, actors_[size_t(ti)].owner) &&
                       safe_at(actors_[size_t(ti)].pos);
    if (!valid) {


        s.target = -1;
        const int32_t cand = bot_pick_target(owner, center, 0, true);
        const int ci = cand >= 0 ? index_of(cand) : -1;
        if (ci >= 0 && safe_at(actors_[size_t(ci)].pos)) s.target = cand;
        if (s.target < 0) {
            s.state = BotSquad::IDLE;
            return;
        }
        s.state = BotSquad::ATTACK;
        s.last_updated = tick_;
    }


    std::vector<int32_t> attackers;
    for (int32_t id : s.units) {
        const int i = index_of(id);
        if (i < 0) continue;
        if (!has_ammo(size_t(i))) {
            if (!airs_[size_t(i)].returning) air_return_to_base(size_t(i));
            continue;
        }
        if (airs_[size_t(i)].returning) continue;
        attackers.push_back(id);
    }
    if (!attackers.empty()) order_attack(attackers.data(), attackers.size(), s.target, false);
}


void World::bot_raid_squads(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (p.raid_squad_size <= 0) return;
    if (--b.raid_ticks > 0) return;
    b.raid_ticks = std::max(1, p.raid_interval);
    if (b.plan == PLAN_ECONOMY || b.plan == PLAN_DEFEND) return;
    if (int32_t(tick_) < p.first_attack_tick) return;
    for (const BotSquad& s : b.squads) if (s.type == BotSquad::RAID && !s.units.empty()) return;
    if (int32_t(b.idle_base_units.size()) < p.raid_squad_size * 2) return;


    std::vector<std::pair<int32_t, int32_t>> pool;
    for (int32_t id : b.idle_base_units) {
        const int i = index_of(id);
        if (i < 0) continue;
        const UnitType& t = types_[actors_[size_t(i)].type];
        if (t.weapon < 0 || t.aircraft) continue;
        pool.emplace_back(t.speed, id);
    }
    if (int32_t(pool.size()) < p.raid_squad_size) return;

    std::sort(pool.begin(), pool.end(), [](const std::pair<int32_t, int32_t>& a, const std::pair<int32_t, int32_t>& c) {
        return a.first != c.first ? a.first > c.first : a.second < c.second;
    });
    BotSquad ns;
    ns.type = BotSquad::RAID;
    for (int32_t k = 0; k < p.raid_squad_size; ++k) {
        ns.units.push_back(pool[size_t(k)].second);
        b.idle_base_units.erase(std::remove(b.idle_base_units.begin(), b.idle_base_units.end(), pool[size_t(k)].second),
                                b.idle_base_units.end());
    }
    b.squads.push_back(ns);
    ++b.stat_squads_sent;
}


int32_t World::bot_raid_target(int32_t owner, WVec from) const {
    int32_t best_id = -1;
    int64_t best = INT64_MIN;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (!t.targetable || t.husk) continue;
        if (!t.harvester && !t.refinery) continue;
        const CPos at = t.building ? a.origin : mobiles_[i].cell;
        const int64_t cells = length(a.pos - from) / CELL;


        int64_t score = (t.harvester ? 2000 : 1200) * 100 / std::max<int64_t>(1, cells + 8);
        score -= int64_t(bot_threat_at(owner, at, true)) / 20;
        if (score > best || (score == best && best_id >= 0 && a.id < best_id)) { best = score; best_id = a.id; }
    }
    return best_id;
}


void World::bot_update_raid_squad(int32_t owner, BotSquad& s) {
    if (s.units.empty()) return;
    int li = -1;
    for (int32_t id : s.units) { li = index_of(id); if (li >= 0) break; }
    if (li < 0) return;
    const int ti = index_of(s.target);
    const bool valid = ti >= 0 && actors_[size_t(ti)].alive && hostile(owner, actors_[size_t(ti)].owner);
    if (!valid) {
        s.target = bot_raid_target(owner, actors_[size_t(li)].pos);
        if (s.target < 0) { s.type = BotSquad::ASSAULT; s.state = BotSquad::IDLE; return; }
    }
    const int t2 = index_of(s.target);
    if (t2 < 0) return;
    const UnitType& tt = types_[actors_[size_t(t2)].type];
    const CPos goal = tt.building ? actors_[size_t(t2)].origin : mobiles_[size_t(t2)].cell;
    order_attack_move(s.units.data(), s.units.size(), goal);
}


void World::bot_naval_reach(CPos from, std::vector<uint8_t>& out) const {
    out.assign(size_t(map_.cells()), 0);
    if (map_.cells() <= 0) return;
    const int32_t mc = move_class_of(LOCO_NAVAL);
    std::vector<int32_t> stack;
    for (int dy = -4; dy <= 4; ++dy) {
        for (int dx = -4; dx <= 4; ++dx) {
            const CPos c{from.x + dx, from.y + dy};
            if (!map_.in_bounds(c) || !map_.passable(c, mc)) continue;
            const int32_t i = map_.index(c);
            if (out[size_t(i)]) continue;
            out[size_t(i)] = 1;
            stack.push_back(i);
        }
    }
    while (!stack.empty()) {
        const CPos c = map_.cell_at(stack.back());
        stack.pop_back();
        for (int dir = 0; dir < NUM_DIRS; ++dir) {
            const CPos nb{c.x + DIR_DX[dir], c.y + DIR_DY[dir]};
            if (!map_.in_bounds(nb) || !map_.passable(nb, mc)) continue;
            const int32_t ni = map_.index(nb);
            if (out[size_t(ni)]) continue;
            out[size_t(ni)] = 1;
            stack.push_back(ni);
        }
    }
}


void World::bot_naval_squads(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    BotSquad* navy = nullptr;
    for (BotSquad& s : b.squads) if (s.type == BotSquad::NAVAL) { navy = &s; break; }
    std::vector<int32_t> fresh;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building || t.aircraft || t.husk || t.harvester || t.exclude_from_squads) continue;
        if (t.locomotor != LOCO_NAVAL || t.weapon < 0) continue;
        if (std::find(b.active_units.begin(), b.active_units.end(), a.id) != b.active_units.end()) continue;
        fresh.push_back(a.id);
    }
    if (fresh.empty()) return;
    if (!navy) {
        BotSquad ns;
        ns.type = BotSquad::NAVAL;
        b.squads.push_back(ns);
        navy = &b.squads.back();
    }
    for (int32_t id : fresh) {
        navy->units.push_back(id);
        b.active_units.push_back(id);
    }
}


void World::bot_update_naval_squad(int32_t owner, BotSquad& s) {
    if (s.units.empty()) return;
    int li = -1;
    for (int32_t id : s.units) { li = index_of(id); if (li >= 0) break; }
    if (li < 0) return;
    const int ti = index_of(s.target);
    const bool valid = ti >= 0 && actors_[size_t(ti)].alive && hostile(owner, actors_[size_t(ti)].owner);
    if (!valid) {
        std::vector<uint8_t> reach;
        bot_naval_reach(mobiles_[size_t(li)].cell, reach);

        int32_t range_cells = 1;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            const UnitType& ut = types_[actors_[size_t(i)].type];
            if (ut.weapon >= 0 && size_t(ut.weapon) < weapons_.size())
                range_cells = std::max(range_cells, weapons_[size_t(ut.weapon)].range / CELL);
        }
        const WVec from = actors_[size_t(li)].pos;
        int64_t best = INT64_MAX;
        int32_t best_id = -1;
        for (size_t i = 0; i < actors_.size(); ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || !hostile(owner, a.owner) || types_[a.type].husk) continue;
            if (!actor_visible_to(owner, i)) continue;
            const CPos tc = types_[a.type].building ? a.origin : mobiles_[i].cell;
            bool shootable = false;
            for (int dy = -range_cells; dy <= range_cells && !shootable; ++dy) {
                for (int dx = -range_cells; dx <= range_cells; ++dx) {
                    const CPos c{tc.x + dx, tc.y + dy};
                    if (!map_.in_bounds(c)) continue;
                    if (reach[size_t(map_.index(c))]) { shootable = true; break; }
                }
            }
            if (!shootable) continue;
            const int64_t d = length_sq(a.pos - from);
            if (d < best) { best = d; best_id = a.id; }
        }
        s.target = best_id;
        if (best_id < 0) return;
    }
    const int t2 = index_of(s.target);
    if (t2 < 0) return;
    const UnitType& tt = types_[actors_[size_t(t2)].type];
    const CPos goal = tt.building ? actors_[size_t(t2)].origin : mobiles_[size_t(t2)].cell;
    order_attack_move(s.units.data(), s.units.size(), goal);
}


bool World::bot_squad_siege(int32_t owner, BotSquad& s) {
    const int ti = index_of(s.target);
    if (ti < 0 || !actors_[size_t(ti)].alive) return false;
    const BotParams& p = players_[size_t(owner)].bot.p;
    const WVec tpos = actors_[size_t(ti)].pos;
    bool any = false;
    for (int32_t id : s.units) {
        const int i = index_of(id);
        if (i < 0 || !bot_unit_is_siege(size_t(i))) continue;
        const UnitType& t = types_[actors_[size_t(i)].type];
        const int64_t range = weapons_[size_t(t.weapon)].range;
        const int64_t hold = range * p.siege_range_percent / 100;
        if (length(actors_[size_t(i)].pos - tpos) > hold) continue;
        order_attack(&id, 1, s.target, false);
        any = true;
    }
    return any;
}

}
