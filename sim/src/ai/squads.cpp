

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


constexpr int32_t SIEGE_RANGE_CELLS = 9;
constexpr uint32_t NAVAL_ALARM_TICKS = 1500;

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


    if (!p.allow_air_squad || count < p.air_squad_size || !safe_at(center)) {
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
        int32_t cand = -1;
        if (b.vh_running[VH_AIR_STRIKE]) {
            const int32_t wish = bot_front_target(owner, center, 0, bot_vorhaben_scheme(VH_AIR_STRIKE));
            const int wi = wish >= 0 ? index_of(wish) : -1;
            if (wi >= 0 && safe_at(actors_[size_t(wi)].pos)) cand = wish;
        }
        if (cand < 0) cand = bot_pick_target(owner, center, 0, true);
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
    if (!p.allow_raid) return;
    if (p.raid_squad_size <= 0) return;
    if (--b.raid_ticks > 0) return;
    b.raid_ticks = std::max(1, p.raid_interval);


    if (!b.vh_running[VH_ORE_RAID]) return;
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
    ns.vorhaben = VH_ORE_RAID;
    ns.scheme = bot_vorhaben_scheme(VH_ORE_RAID);
    ns.start_size = p.raid_squad_size;
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
    BotState& b = players_[size_t(owner)].bot;
    int li = -1;
    for (int32_t id : s.units) { li = index_of(id); if (li >= 0) break; }
    if (li < 0) return;
    const int ti = index_of(s.target);
    const bool valid = ti >= 0 && actors_[size_t(ti)].alive && hostile(owner, actors_[size_t(ti)].owner);
    if (!valid) {
        s.target = bot_raid_target(owner, actors_[size_t(li)].pos);
        if (s.target < 0) {
            CPos home{-1, -1};
            if (bot_base_center(owner, home)) order_move(s.units.data(), s.units.size(), home);


            for (int32_t id : s.units) b.idle_base_units.push_back(id);
            s.units.clear();
            s.dead = true;
            return;
        }
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
    BotState& b = players_[size_t(owner)].bot;
    const int ti = index_of(s.target);
    bool valid = ti >= 0 && actors_[size_t(ti)].alive && hostile(owner, actors_[size_t(ti)].owner);


    if (b.naval_alarm_id >= 0 && tick_ - b.naval_alarm_tick <= NAVAL_ALARM_TICKS) {
        const int ai = index_of(b.naval_alarm_id);
        if (ai >= 0 && actors_[size_t(ai)].alive && hostile(owner, actors_[size_t(ai)].owner) &&
            !types_[actors_[size_t(ai)].type].building) {
            if (!valid || s.target != b.naval_alarm_id) {
                s.target = b.naval_alarm_id;
                valid = true;
            }
        } else {
            b.naval_alarm_id = -1;
        }
    }
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


bool World::bot_gather_point(int32_t owner, CPos from, CPos& out, int32_t side) const {
    constexpr int32_t GATHER_MIN_CELLS = 12;
    constexpr int32_t GATHER_MAX_CELLS = 15;
    CPos base{-1, -1};
    if (!bot_base_center(owner, base)) return false;


    CPos front{-1, -1};
    int64_t best_d = INT64_MAX;
    int32_t front_id = -1;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (!t.building || t.husk || !t.targetable) continue;
        const int64_t d = cell_dist_sq(a.origin, base);
        if (d < best_d || (d == best_d && front_id >= 0 && a.id < front_id)) {
            best_d = d;
            front = a.origin;
            front_id = a.id;
        }
    }
    if (front.x < 0) return false;
    const int64_t front_to_base = cell_dist_sq(front, base);

    std::vector<uint8_t> reach;
    bot_land_reach(from, reach);

    const int64_t min2 = int64_t(GATHER_MIN_CELLS) * GATHER_MIN_CELLS;
    const int64_t max2 = int64_t(GATHER_MAX_CELLS) * GATHER_MAX_CELLS;
    int64_t best_threat = INT64_MAX, best_base = INT64_MAX;
    int32_t best_idx = -1;
    CPos best{-1, -1};
    for (int32_t y = front.y - GATHER_MAX_CELLS; y <= front.y + GATHER_MAX_CELLS; ++y) {
        for (int32_t x = front.x - GATHER_MAX_CELLS; x <= front.x + GATHER_MAX_CELLS; ++x) {
            const CPos c{x, y};
            if (!map_.in_bounds(c) || !map_.passable(c)) continue;
            const int64_t d = cell_dist_sq(c, front);
            if (d < min2 || d > max2) continue;
            if (cell_dist_sq(c, base) >= front_to_base) continue;
            if (side != 0) {


                const int64_t ax = int64_t(front.x) - base.x, ay = int64_t(front.y) - base.y;
                const int64_t cx = int64_t(c.x) - front.x, cy = int64_t(c.y) - front.y;
                const int64_t cross = ax * cy - ay * cx;
                const int64_t dot = ax * cx + ay * cy;
                if (cross < 0 ? -cross : cross) {
                    if ((cross < 0 ? -cross : cross) < (dot < 0 ? -dot : dot)) continue;
                } else {
                    continue;
                }
            }
            const int32_t idx = map_.index(c);
            if (!reach[size_t(idx)]) continue;
            const int64_t threat = bot_threat_at(owner, c, true);
            const int64_t to_base = cell_dist_sq(c, base);
            if (threat > best_threat) continue;
            if (threat == best_threat && to_base > best_base) continue;
            if (threat == best_threat && to_base == best_base && best_idx >= 0 && idx > best_idx) continue;
            best_threat = threat;
            best_base = to_base;
            best_idx = idx;
            best = c;
        }
    }
    if (best.x < 0) return false;
    out = best;
    return true;
}


bool World::bot_squad_siege(int32_t owner, BotSquad& s) {
    constexpr int32_t SIEGE_BACK_CELLS = 3;
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (!p.allow_siege) return false;


    CPos home = s.gather;
    if (home.x < 0 && !bot_base_center(owner, home)) home = CPos{-1, -1};


    std::vector<int32_t> escorts;
    for (int32_t id : s.units) {
        const int i = index_of(id);
        if (i >= 0 && !bot_unit_is_siege(size_t(i))) escorts.push_back(id);
    }

    bool any = false;
    for (int32_t id : s.units) {
        const int idx = index_of(id);
        if (idx < 0 || !bot_unit_is_siege(size_t(idx))) continue;
        const size_t i = size_t(idx);
        any = true;


        set_stance(id, STANCE_DEFEND);
        const UnitType& t = types_[actors_[i].type];
        const Weapon& w = weapons_[size_t(t.weapon)];
        const int64_t range = w.range;
        const int64_t hold = range * std::clamp(p.siege_range_percent, 10, 100) / 100;
        const WVec pos = actors_[i].pos;


        int32_t in_range_id = -1, near_id = -1, approach_id = -1;
        int64_t in_range_d = INT64_MAX, near_d = INT64_MAX;
        int32_t approach_rank = 3;
        int64_t approach_d = INT64_MAX;
        for (size_t k = 0; k < actors_.size(); ++k) {
            const Actor& e = actors_[k];
            if (!e.alive || !hostile(owner, e.owner)) continue;
            const UnitType& et = types_[e.type];
            if (!et.targetable || et.husk) continue;
            if ((target_mask(k) & TT_AIRBORNE) != 0) continue;
            if (!weapon_hits(k, w)) continue;
            const bool worthy = et.weapon >= 0 || et.building;
            const int64_t d = length(e.pos - pos);
            if (d < near_d || (d == near_d && near_id >= 0 && e.id < near_id)) { near_d = d; near_id = e.id; }
            if (worthy && d <= range && (d < in_range_d || (d == in_range_d && in_range_id >= 0 && e.id < in_range_id))) {
                in_range_d = d;
                in_range_id = e.id;
            }

            const int32_t rank = et.building ? (et.defense ? 0 : 1) : 3;
            if (rank > 1) continue;
            if (rank > approach_rank) continue;
            if (rank == approach_rank && d > approach_d) continue;
            if (rank == approach_rank && d == approach_d && approach_id >= 0 && e.id > approach_id) continue;
            approach_rank = rank;
            approach_d = d;
            approach_id = e.id;
        }


        if (w.min_range > 0 && near_id >= 0 && near_d < w.min_range && home.x >= 0) {
            const CPos c = mobiles_[i].cell;
            const int32_t dx = home.x > c.x ? 1 : (home.x < c.x ? -1 : 0);
            const int32_t dy = home.y > c.y ? 1 : (home.y < c.y ? -1 : 0);
            CPos back{c.x + dx * SIEGE_BACK_CELLS, c.y + dy * SIEGE_BACK_CELLS};
            if (!map_.in_bounds(back)) back = home;
            order_move(&id, 1, back, 1);
            if (!escorts.empty()) order_guard(escorts.data(), escorts.size(), id);
            continue;
        }


        if (in_range_id >= 0) {
            order_attack(&id, 1, in_range_id, false);
            continue;
        }


        if (approach_id < 0) { order_stop(&id, 1); continue; }
        const int ai = index_of(approach_id);
        if (ai < 0) { order_stop(&id, 1); continue; }
        const CPos goal = types_[actors_[size_t(ai)].type].building ? actors_[size_t(ai)].origin
                                                                   : mobiles_[size_t(ai)].cell;


        const CPos c = mobiles_[i].cell;
        const CPos step{c.x + (goal.x > c.x ? 1 : (goal.x < c.x ? -1 : 0)),
                        c.y + (goal.y > c.y ? 1 : (goal.y < c.y ? -1 : 0))};
        const WVec step_pos = cell_center(step);
        bool covered = false;
        for (size_t k = 0; k < actors_.size() && !covered; ++k) {
            const Actor& e = actors_[k];
            if (!e.alive || !hostile(owner, e.owner)) continue;
            const UnitType& et = types_[e.type];
            if (!et.building || !et.defense || et.weapon < 0 || size_t(et.weapon) >= weapons_.size()) continue;
            if (length(e.pos - step_pos) <= weapons_[size_t(et.weapon)].range + CELL) covered = true;
        }
        if (covered) { order_stop(&id, 1); continue; }


        const int64_t hold_cells = std::max<int64_t>(1, hold / CELL);
        const int64_t gdx = int64_t(goal.x) - c.x, gdy = int64_t(goal.y) - c.y;
        const int64_t gd = std::max<int64_t>(1, isqrt(gdx * gdx + gdy * gdy));
        const int64_t want = gd - hold_cells;
        if (want <= 0) { order_stop(&id, 1); continue; }
        const CPos hold_cell{int32_t(c.x + gdx * want / gd), int32_t(c.y + gdy * want / gd)};
        if (!map_.in_bounds(hold_cell)) { order_stop(&id, 1); continue; }
        order_move(&id, 1, hold_cell, 1);
    }
    return any;
}

}
