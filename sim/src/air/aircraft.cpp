

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
    const UnitType& t = types_[actors_[i].type];
    air.goal = goal;
    air.has_goal = true;
    air.land_at_goal = land ? LAND_TOUCHDOWN : LAND_NONE;
    if (land && !t.can_hover) {
        const int b = air.base >= 0 ? index_of(air.base) : -1;
        if (b >= 0 && actors_[size_t(b)].alive && dock_pos(size_t(b)) == goal) {
            air.land_at_goal = LAND_APPROACH;
            air.goal = approach_point(i, goal);
        } else {


            air.land_at_goal = LAND_NONE;
        }
    }
    if (air.state == Air::LANDED) air.state = Air::TAKING_OFF;
}


bool World::pad_reserved(int32_t pad_id, int except) const {
    if (pad_id < 0) return false;
    for (size_t o = 0; o < actors_.size(); ++o) {
        if (int(o) == except || !actors_[o].alive) continue;
        if (airs_[o].base == pad_id) return true;
    }
    return false;
}


int World::find_free_pad(int32_t owner, int32_t type, int prefer) const {
    if (type < 0 || type >= int32_t(types_.size())) return -1;
    const std::vector<int32_t>& pads = pads_of(types_[size_t(type)]);
    if (pads.empty()) return -1;
    auto usable = [&](size_t k) {
        const Actor& b = actors_[k];
        if (!b.alive || b.owner != owner || b.make_ticks > 0 || b.sell_ticks >= 0) return false;
        if (std::find(pads.begin(), pads.end(), b.type) == pads.end()) return false;
        return !pad_reserved(b.id);
    };
    if (prefer >= 0 && size_t(prefer) < actors_.size() && usable(size_t(prefer))) return prefer;
    for (size_t k = 0; k < actors_.size(); ++k)
        if (usable(k)) return static_cast<int>(k);
    return -1;
}


int32_t World::free_landing_pads(int32_t owner, int32_t type) const {
    if (type < 0 || type >= int32_t(types_.size())) return 0;
    const std::vector<int32_t>& pads = pads_of(types_[size_t(type)]);
    if (pads.empty()) return 1;
    int32_t free = 0;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& b = actors_[k];
        if (!b.alive || b.owner != owner || b.make_ticks > 0 || b.sell_ticks >= 0) continue;
        if (std::find(pads.begin(), pads.end(), b.type) == pads.end()) continue;
        if (!pad_reserved(b.id)) ++free;
    }
    if (owner < 0 || owner >= MAX_PLAYERS) return free;

    for (const BuildItem& it : players_[owner].queues[QUEUE_AIRCRAFT]) {
        if (it.type < 0 || it.type >= int32_t(types_.size())) continue;
        const std::vector<int32_t>& q = pads_of(types_[size_t(it.type)]);
        bool shares = false;
        for (int32_t pt : q)
            if (std::find(pads.begin(), pads.end(), pt) != pads.end()) { shares = true; break; }
        if (shares) --free;
    }
    return free;
}


void World::release_pad(int32_t pad_id) {
    if (pad_id < 0) return;
    for (size_t o = 0; o < actors_.size(); ++o) {
        if (!actors_[o].alive || airs_[o].base != pad_id) continue;
        Air& air = airs_[o];
        air.base = -1;
        air.returning = false;
        if (air.state == Air::LANDED || air.state == Air::LANDING) {
            air.state = Air::TAKING_OFF;
            air.land_at_goal = LAND_NONE;
            air.has_goal = false;
        }


        const int b = find_free_pad(actors_[o].owner, actors_[o].type);
        if (b >= 0) {
            air.base = actors_[size_t(b)].id;
            air.returning = true;
            air_move(o, dock_pos(size_t(b)), true);
        }
    }
}


int World::find_rearm_base(size_t i) const {
    const Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    const std::vector<int32_t>& pads = pads_of(t);
    if (pads.empty()) return -1;
    if (airs_[i].base >= 0) {
        const int own = index_of(airs_[i].base);
        if (own >= 0 && actors_[size_t(own)].alive && actors_[size_t(own)].sell_ticks < 0) return own;
    }
    int best = -1;
    int64_t best_d = INT64_MAX;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& b = actors_[k];
        if (!b.alive || b.owner != a.owner || b.make_ticks > 0 || b.sell_ticks >= 0) continue;
        if (std::find(pads.begin(), pads.end(), b.type) == pads.end()) continue;

        if (pad_reserved(b.id, static_cast<int>(i))) continue;
        const int64_t d = length_sq(b.pos - a.pos);
        if (d < best_d) { best_d = d; best = static_cast<int>(k); }
    }
    return best;
}


WVec World::dock_pos(size_t base) const {
    const UnitType& bt = types_[actors_[base].type];
    return WVec{actors_[base].pos.x + bt.exit_ox, actors_[base].pos.y + bt.exit_oy};
}


WAngle World::landing_facing(size_t i, WVec touchdown) const {
    const Air& air = airs_[i];
    if (air.base >= 0) {
        const int b = index_of(air.base);
        if (b >= 0 && actors_[size_t(b)].alive && dock_pos(size_t(b)) == touchdown)
            return types_[actors_[size_t(b)].type].exit_facing;
    }
    return AIRCRAFT_INITIAL_FACING;
}


static int64_t turn_radius(const UnitType& t) {
    return t.turn_rate > 0 ? 180 * int64_t(std::max(1, t.speed)) / t.turn_rate : 0;
}


WVec World::approach_point(size_t i, WVec touchdown) const {
    const UnitType& t = types_[actors_[i].type];
    const int64_t speed = std::max(1, t.speed);
    const int64_t drop = int64_t(t.cruise_altitude) * speed / std::max(1, t.altitude_velocity);
    const int64_t back_dist = drop + 3 * turn_radius(t);
    const WVec back = direction_of(wrap_angle(landing_facing(i, touchdown) + FULL_TURN / 2));
    return WVec{touchdown.x + static_cast<WDist>(back.x * back_dist / 1024),
                touchdown.y + static_cast<WDist>(back.y * back_dist / 1024)};
}


int World::pad_below(size_t i) const {
    const Actor& a = actors_[i];
    const std::vector<int32_t>& pads = pads_of(types_[a.type]);
    if (pads.empty()) return -1;
    const CPos c = to_cell(a.pos);
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& b = actors_[k];
        if (k == i || !b.alive || b.owner != a.owner || b.sell_ticks >= 0) continue;
        if (std::find(pads.begin(), pads.end(), b.type) == pads.end()) continue;
        const UnitType& bt = types_[b.type];
        const int dx = c.x - b.origin.x, dy = c.y - b.origin.y;
        if (dx < 0 || dy < 0 || dx >= bt.foot_w || dy >= bt.foot_h) continue;
        if (pad_reserved(b.id, static_cast<int>(i))) continue;
        return static_cast<int>(k);
    }
    return -1;
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
    const std::vector<int32_t>& pads = pads_of(t);
    if (std::find(pads.begin(), pads.end(), bt) == pads.end()) return false;

    return !pad_reserved(target_id, i);
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
    if (air.state == Air::FALLING) return;
    if (c.fire_anim > 0) --c.fire_anim;
    if (t.weapon < 0) return;


    for (int k = 0; k < NUM_ARMS; ++k) {
        const int32_t wid = arm_weapon(t, k);
        if (wid < 0) continue;
        if (c.reload_at(k) > 0) --c.reload_at(k);
        if (c.burst_at(k) > 0 && ++c.since_at(k) >= weapons_[wid].reload) c.burst_at(k) = 0;
    }


    const bool no_ammo = t.ammo_max > 0 && air.ammo <= 0;
    if (no_ammo) {
        c.target = -1;
        if (!air.returning) air_return_to_base(i);
        return;
    }


    if (air.land_at_goal == LAND_TURN) {
        if (c.target < 0 && !c.attack_move) return;
        air.land_at_goal = LAND_NONE;
        air.returning = false;
    }

    if (air.state == Air::LANDED || air.state == Air::LANDING) {
        if (c.target < 0 && !c.attack_move) return;
        air.state = Air::TAKING_OFF;
        air.land_at_goal = LAND_NONE;
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
                ? nearest_enemy_in_range(i, max_weapon_range(t) * 4, true) : -1;
            if (found >= 0) { ti = found; c.target = actors_[found].id; c.auto_target = true; }
        }
    }
    if (ti < 0) return;


    int32_t arms[NUM_ARMS];
    bool any_hits = false, can_fire = false, too_close = false;
    WDist reach = 0, keep_out = 0;
    for (int k = 0; k < NUM_ARMS; ++k) {
        arms[k] = -1;
        const int32_t wid = arm_weapon(t, k);
        if (wid < 0 || !weapon_hits(size_t(ti), weapons_[wid])) continue;
        arms[k] = wid;
        any_hits = true;
        const Weapon& wk = weapons_[wid];
        if (wk.range > reach) reach = wk.range;

        if (wk.min_range > 0 && in_range(i, size_t(ti), wk.min_range)) {
            too_close = true;
            if (wk.min_range > keep_out) keep_out = wk.min_range;
        } else if (in_range(i, size_t(ti), wk.range)) {
            can_fire = true;
        }
    }
    if (!any_hits) { c.target = -1; return; }

    const Actor& v = actors_[size_t(ti)];
    const WAngle want = angle_of(v.pos - a.pos);


    if (t.air_attack_type == 1) {


        if (!can_fire) {
            WVec goal = v.pos;
            if (too_close) {
                const WVec off = a.pos - v.pos;
                const int64_t d0 = length(off);
                const int64_t out = int64_t(keep_out) + CELL;
                goal = d0 > 0
                    ? WVec{v.pos.x + WDist(int64_t(off.x) * out / d0), v.pos.y + WDist(int64_t(off.y) * out / d0)}
                    : WVec{v.pos.x + WDist(out), v.pos.y};
            }
            air_move(i, goal, false);
            return;
        }
        air.has_goal = false;
        a.facing = turn_towards(a.facing, want, t.turn_rate);
    } else {
        if (!can_fire && !too_close) {
            air_move(i, v.pos, false);
            return;
        }


        if (!air.has_goal) {
            const WVec dir = direction_of(a.facing);
            const int64_t out = int64_t(reach) + CELL;
            air_move(i, WVec{v.pos.x + WDist(int64_t(dir.x) * out / 1024),
                             v.pos.y + WDist(int64_t(dir.y) * out / 1024)}, false);
        }
    }

    if (abs_angle_diff(a.facing, want) > std::max<WAngle>(t.facing_tolerance, 8)) return;


    for (int k = 0; k < NUM_ARMS; ++k) {
        if (arms[k] < 0 || c.reload_at(k) > 0) continue;
        const Weapon& wk = weapons_[arms[k]];
        if (!in_range(i, size_t(ti), wk.range)) continue;
        if (wk.min_range > 0 && in_range(i, size_t(ti), wk.min_range)) continue;
        fire(i, size_t(ti), arms[k], k);
        if (t.ammo_max > 0 && --air.ammo <= 0) break;
    }
}


bool World::start_fall_to_earth(size_t i) {
    Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    if (!t.aircraft || t.husk_actor < 0 || t.husk_actor >= int32_t(types_.size())) return false;
    if (airs_[i].alt <= 0 || airs_[i].state == Air::FALLING) return false;
    const UnitType& ht = types_[size_t(t.husk_actor)];
    if (!ht.falls_to_earth) return false;


    Air& air = airs_[i];
    air.base = -1;
    air.returning = false;
    air.has_goal = false;
    air.land_at_goal = LAND_NONE;
    air.state = Air::FALLING;
    air.ammo = 0;


    air.spin = ht.fall_max_spin == 0 ? 0 : (int32_t(rand() % 2u) * 2 - 1);
    combats_[i].target = -1;
    combats_[i].attack_move = false;
    combats_[i].guard = -1;
    combats_[i].attack_cell = CPos{-1, -1};
    order_queue_[i].clear();
    a.type = t.husk_actor;
    a.hp = std::max(1, ht.hp);
    return true;
}


void World::step_falling(size_t i) {
    Actor& a = actors_[i];
    Air& air = airs_[i];
    const UnitType& t = types_[a.type];
    if (air.alt <= 0) {


        const WVec pos = a.pos;
        const int32_t id = a.id, owner = a.owner, weapon = t.fall_weapon, snd = t.death_sound;
        if (weapon >= 0) impact(pos, weapon, id, owner, 0);
        play_sound(snd, pos);
        dispose(i);
        actors_[i].vanished = false;
        return;
    }
    if (air.spin != 0) {

        const int32_t dir = air.spin < 0 ? -1 : 1;
        int32_t mag = air.spin < 0 ? -air.spin : air.spin;
        if (t.fall_max_spin < 0 || mag < t.fall_max_spin) mag += 4;
        air.spin = dir * mag;
        a.facing = wrap_angle(a.facing + air.spin);
    }

    if (t.fall_moves) {
        const WVec dir = direction_of(a.facing);
        const int32_t speed = std::max(1, t.speed);
        a.pos.x += static_cast<WDist>(int64_t(dir.x) * speed / 1024);
        a.pos.y += static_cast<WDist>(int64_t(dir.y) * speed / 1024);
    }
    air.alt = std::max(0, air.alt - std::max(1, t.fall_velocity));
    mobiles_[i].moving = false;
    mobiles_[i].cell = to_cell(a.pos);
    mobiles_[i].to_cell = mobiles_[i].cell;
}

void World::step_aircraft(size_t i) {
    Actor& a = actors_[i];
    Air& air = airs_[i];
    Mobile& m = mobiles_[i];
    const UnitType& t = types_[a.type];
    if (a.prone_ticks > 0) --a.prone_ticks;

    if (air.state == Air::FALLING) { step_falling(i); return; }


    if (air.state == Air::LANDED) {
        m.moving = false;
        const int b = air.base >= 0 ? index_of(air.base) : -1;

        const bool rearms = b >= 0 && actors_[size_t(b)].alive &&
            std::find(t.rearm_actors.begin(), t.rearm_actors.end(), actors_[size_t(b)].type) != t.rearm_actors.end();
        if (rearms && t.ammo_max > 0 && air.ammo < t.ammo_max) {
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

    const int32_t speed = std::max(1, t.speed);


    if (air.land_at_goal == LAND_TURN) {
        const WAngle want = landing_facing(i, air.goal);
        a.facing = turn_towards(a.facing, want, t.turn_rate);
        if (a.facing == want) {
            air.land_at_goal = LAND_NONE;
            air.state = Air::LANDING;
        }
        m.moving = false;
        m.cell = to_cell(a.pos);
        m.to_cell = m.cell;
        return;
    }


    WDist want_alt = t.cruise_altitude;
    if (air.state == Air::LANDING) {
        want_alt = 0;
        if (!t.can_hover && air.has_goal) {
            const int64_t rest = length(air.goal - a.pos);
            want_alt = static_cast<WDist>(std::min<int64_t>(t.cruise_altitude,
                                                            rest * t.altitude_velocity / speed));
        }
    }
    if (air.alt < want_alt) air.alt = std::min(want_alt, air.alt + t.altitude_velocity);
    else if (air.alt > want_alt) air.alt = std::max(want_alt, air.alt - t.altitude_velocity);
    if (air.state == Air::TAKING_OFF && air.alt >= t.cruise_altitude) air.state = Air::CRUISING;


    if (air.state == Air::LANDING && air.alt <= 0 && (t.can_hover || !air.has_goal)) {
        air.state = Air::LANDED;
        air.has_goal = false;
        m.moving = false;
        m.cell = to_cell(a.pos);
        m.to_cell = m.cell;
        return;
    }

    WAngle want_face = a.facing;
    int64_t dist = 0;
    if (air.has_goal) {
        const WVec d = air.goal - a.pos;
        dist = length(d);
        if (dist > 0) want_face = angle_of(d);
    }


    const bool taking_off = air.state == Air::TAKING_OFF;
    if (taking_off) want_face = a.facing;

    if (t.can_hover) {

        a.facing = turn_towards(a.facing, want_face, t.turn_rate);
        if (air.has_goal && !taking_off) {
            if (dist <= speed) {
                a.pos = air.goal;
                air.has_goal = false;

                if (air.land_at_goal != LAND_NONE) air.land_at_goal = LAND_TURN;
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


        const int64_t reached = air.land_at_goal == LAND_APPROACH
            ? std::max<int64_t>(speed * 2, 3 * turn_radius(t)) : speed * 2;
        if (air.has_goal && dist <= reached) {
            if (air.land_at_goal == LAND_APPROACH) {


                const int b = air.base >= 0 ? index_of(air.base) : -1;
                if (b < 0 || !actors_[size_t(b)].alive) {
                    air.land_at_goal = LAND_NONE;
                    air.has_goal = false;
                } else {
                    air.goal = dock_pos(size_t(b));
                    air.land_at_goal = LAND_TOUCHDOWN;
                    air.state = Air::LANDING;
                }
            } else if (air.land_at_goal == LAND_TOUCHDOWN) {

                a.pos = air.goal;
                a.facing = landing_facing(i, air.goal);
                air.alt = 0;
                air.has_goal = false;
                air.land_at_goal = LAND_NONE;
                air.state = Air::LANDED;
                m.moving = false;
                m.cell = to_cell(a.pos);
                m.to_cell = m.cell;
                return;
            } else {
                air.has_goal = false;
            }
        }
        if (!air.has_goal && !taking_off && air.state != Air::LANDING) {


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


            const int32_t pid = drop_passenger(a.id, to_cell(a.pos));
            if (pid >= 0) {
                const int p = index_of(pid);
                if (p >= 0) airs_[size_t(p)].alt = air.alt;
                paradrop_delay_[i] = PARADROP_INTERVAL;
            }
        }
    }
}

}
