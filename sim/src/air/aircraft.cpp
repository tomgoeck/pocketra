

#include <algorithm>

#include "ra/sim.h"

namespace ra {


constexpr WDist PARADROP_RANGE = 4 * CELL;
constexpr int32_t PARADROP_INTERVAL = 5;

int32_t World::air_altitude(int32_t id) const {
    const int i = index_of(id);
    return i < 0 ? 0 : airs_[size_t(i)].alt;
}


void World::air_move(size_t i, WVec goal, bool land) {
    Air& air = airs_[i];
    air.goal = goal;
    air.has_goal = true;
    air.land_at_goal = land ? 1 : 0;
    if (air.state == Air::LANDED) air.state = Air::TAKING_OFF;
}


int World::find_rearm_base(size_t i) const {
    const Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    if (t.rearm_actors.empty()) return -1;
    int best = -1;
    int64_t best_d = INT64_MAX;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& b = actors_[k];
        if (!b.alive || b.owner != a.owner || b.make_ticks > 0 || b.sell_ticks >= 0) continue;
        if (std::find(t.rearm_actors.begin(), t.rearm_actors.end(), b.type) == t.rearm_actors.end()) continue;

        bool taken = false;
        for (size_t o = 0; o < actors_.size() && !taken; ++o) {
            taken = o != i && actors_[o].alive && airs_[o].base == b.id;
        }
        if (taken) continue;
        const int64_t d = length_sq(b.pos - a.pos);
        if (d < best_d) { best_d = d; best = static_cast<int>(k); }
    }
    return best;
}


WVec World::dock_pos(size_t base) const {
    const UnitType& bt = types_[actors_[base].type];
    return WVec{actors_[base].pos.x + bt.exit_ox, actors_[base].pos.y + bt.exit_oy};
}


void World::snap_dock_facing(Actor& a, const Air& air) const {
    if (air.base < 0) return;
    const int b = index_of(air.base);
    if (b < 0 || !actors_[size_t(b)].alive) return;
    a.facing = types_[actors_[size_t(b)].type].exit_facing;
}

void World::air_return_to_base(size_t i) {
    Air& air = airs_[i];
    const int b = find_rearm_base(i);
    if (b < 0) {
        air.base = -1;
        air.returning = false;
        return;
    }
    air.base = actors_[size_t(b)].id;
    air.returning = true;
    air_move(i, dock_pos(size_t(b)), true);
}

void World::order_land(const int32_t* ids, size_t n, CPos cell) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || !types_[actors_[i].type].aircraft) continue;
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        air_move(size_t(i), cell_center(cell), true);
    }
}


bool World::can_resupply_at(int32_t id, int32_t target_id) const {
    const int i = index_of(id);
    const int b = index_of(target_id);
    if (i < 0 || b < 0 || !actors_[i].alive || !actors_[b].alive) return false;
    const UnitType& t = types_[actors_[i].type];
    if (!t.aircraft || actors_[i].owner != actors_[b].owner) return false;
    if (actors_[b].make_ticks > 0 || actors_[b].sell_ticks >= 0) return false;
    const int32_t bt = actors_[b].type;
    if (std::find(t.rearm_actors.begin(), t.rearm_actors.end(), bt) == t.rearm_actors.end()) return false;

    for (size_t o = 0; o < actors_.size(); ++o)
        if (o != size_t(i) && actors_[o].alive && airs_[o].base == target_id) return false;
    return true;
}

void World::order_resupply(const int32_t* ids, size_t n, int32_t target_id) {
    const int b = index_of(target_id);
    if (b < 0) return;
    for (size_t k = 0; k < n; ++k) {
        if (!can_resupply_at(ids[k], target_id)) continue;
        const int i = index_of(ids[k]);
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        combats_[i].guard = -1;
        combats_[i].attack_cell = CPos{-1, -1};
        order_queue_[size_t(i)].clear();
        airs_[size_t(i)].base = target_id;
        airs_[size_t(i)].returning = true;
        air_move(size_t(i), dock_pos(size_t(b)), true);
    }
}

void World::order_paradrop(int32_t id, CPos lz) {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive) return;
    paradrop_lz_[size_t(i)] = lz;
    paradrop_delay_[size_t(i)] = 0;
}


void World::step_air_combat(size_t i) {
    Actor& a = actors_[i];
    Combat& c = combats_[i];
    Air& air = airs_[i];
    const UnitType& t = types_[a.type];
    if (c.reload > 0) --c.reload;
    if (c.fire_anim > 0) --c.fire_anim;
    if (t.weapon < 0) return;
    const Weapon& w = weapons_[t.weapon];
    if (c.burst_left > 0 && ++c.since_shot >= w.reload) c.burst_left = 0;


    const bool no_ammo = t.ammo_max > 0 && air.ammo <= 0;
    if (no_ammo) {
        c.target = -1;
        if (!air.returning) air_return_to_base(i);
        return;
    }

    if (air.state == Air::LANDED || air.state == Air::LANDING) {
        if (c.target < 0 && !c.attack_move) return;
        air.state = Air::TAKING_OFF;
        air.returning = false;
        return;
    }

    int ti = c.target >= 0 ? index_of(c.target) : -1;
    if (ti >= 0 && !in_world(size_t(ti))) { ti = -1; c.target = -1; }

    if (ti < 0 && !air.returning) {
        if (c.scan > 0) {
            --c.scan;
        } else {
            c.scan = 3 + static_cast<int32_t>(rand() % 5);


            const int found = (c.attack_move || c.stance >= STANCE_ATTACK_ANYTHING)
                ? nearest_enemy_in_range(i, w.range * 4, true) : -1;
            if (found >= 0) { ti = found; c.target = actors_[found].id; c.auto_target = true; }
        }
    }
    if (ti < 0) return;

    const Actor& v = actors_[size_t(ti)];
    const WVec d = v.pos - a.pos;
    const WAngle want = angle_of(d);
    if (!in_range(i, size_t(ti), w.range)) {
        air_move(i, v.pos, false);
        return;
    }


    if (t.air_attack_type == 1) {
        air.has_goal = false;
        a.facing = turn_towards(a.facing, want, t.turn_rate);
    }

    if (abs_angle_diff(a.facing, want) > std::max<WAngle>(t.facing_tolerance, 8)) return;
    if (c.reload != 0) return;
    fire(i, size_t(ti));
    if (t.ammo_max > 0) --air.ammo;
}

void World::step_aircraft(size_t i) {
    Actor& a = actors_[i];
    Air& air = airs_[i];
    Mobile& m = mobiles_[i];
    const UnitType& t = types_[a.type];
    if (a.prone_ticks > 0) --a.prone_ticks;


    if (air.state == Air::LANDED) {
        m.moving = false;
        const int b = air.base >= 0 ? index_of(air.base) : -1;
        if (b >= 0 && actors_[size_t(b)].alive && t.ammo_max > 0 && air.ammo < t.ammo_max) {
            if (air.reload > 0) { --air.reload; }
            else {
                air.reload = t.ammo_reload;
                ++air.ammo;
                play_sound(t.rearm_sound, a.pos);
            }
        } else if (t.ammo_max <= 0 || air.ammo >= t.ammo_max) {
            air.returning = false;
        }
        if (!air.has_goal) return;
        air.state = Air::TAKING_OFF;
    }


    const WDist want_alt = (air.state == Air::LANDING) ? 0 : t.cruise_altitude;
    if (air.alt < want_alt) air.alt = std::min(want_alt, air.alt + t.altitude_velocity);
    else if (air.alt > want_alt) air.alt = std::max(want_alt, air.alt - t.altitude_velocity);
    if (air.state == Air::TAKING_OFF && air.alt >= t.cruise_altitude) air.state = Air::CRUISING;
    if (air.state == Air::LANDING && air.alt <= 0) {
        air.state = Air::LANDED;
        air.has_goal = false;
        m.moving = false;
        m.cell = to_cell(a.pos);
        m.to_cell = m.cell;
        return;
    }

    const int32_t speed = std::max(1, t.speed);
    WAngle want_face = a.facing;
    int64_t dist = 0;
    if (air.has_goal) {
        const WVec d = air.goal - a.pos;
        dist = length(d);
        if (dist > 0) want_face = angle_of(d);
    }

    if (t.can_hover) {

        a.facing = turn_towards(a.facing, want_face, t.turn_rate);
        if (air.has_goal) {
            if (dist <= speed) {
                a.pos = air.goal;
                air.has_goal = false;
                if (air.land_at_goal) {
                    air.state = Air::LANDING;
                    snap_dock_facing(a, air);
                }
            } else {
                const WVec d = air.goal - a.pos;
                a.pos.x += static_cast<WDist>(int64_t(d.x) * speed / dist);
                a.pos.y += static_cast<WDist>(int64_t(d.y) * speed / dist);
            }
        }
    } else {

        a.facing = turn_towards(a.facing, want_face, t.turn_rate);
        const WVec dir = direction_of(a.facing);
        a.pos.x += static_cast<WDist>(int64_t(dir.x) * speed / 1024);
        a.pos.y += static_cast<WDist>(int64_t(dir.y) * speed / 1024);
        if (air.has_goal && dist <= speed * 2) {
            air.has_goal = false;
            if (air.land_at_goal) {
                a.pos = air.goal;
                air.state = Air::LANDING;
                snap_dock_facing(a, air);
            }
        }
        if (!air.has_goal) {


            a.facing = turn_towards(a.facing, wrap_angle(a.facing + FULL_TURN / 4), t.turn_rate);
            const CPos c = to_cell(a.pos);
            if (!map_.in_bounds(c) || c.x < 1 || c.y < 1 || c.x >= map_.width() - 1 || c.y >= map_.height() - 1) {
                air.goal = cell_center(CPos{map_.width() / 2, map_.height() / 2});
                air.has_goal = true;
            }
        }
    }

    m.moving = air.has_goal;
    m.cell = to_cell(a.pos);
    m.to_cell = m.cell;


    const CPos lz = paradrop_lz_[i];
    if (lz.x >= 0) {
        if (paradrop_delay_[i] > 0) {
            --paradrop_delay_[i];
        } else if (cargo_[i].empty()) {
            paradrop_lz_[i] = CPos{-1, -1};
        } else if (length(cell_center(lz) - a.pos) <= PARADROP_RANGE) {
            const int32_t pid = unload_passenger(a.id, to_cell(a.pos));
            if (pid >= 0) {
                const int p = index_of(pid);
                if (p >= 0) airs_[size_t(p)].alt = air.alt;
                paradrop_delay_[i] = PARADROP_INTERVAL;
            }
        }
    }
}

}
