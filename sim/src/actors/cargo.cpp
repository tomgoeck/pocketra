

#include <algorithm>

#include "ra/sim.h"

namespace ra {


static int32_t weight_of(const UnitType& t) { return std::max(1, t.passenger_weight); }

int32_t World::cargo_weight(int32_t transport_id) const {
    const int i = index_of(transport_id);
    if (i < 0) return 0;
    int32_t sum = 0;
    for (const int32_t pid : cargo_[size_t(i)]) {
        const int p = index_of(pid);
        if (p >= 0) sum += weight_of(types_[actors_[p].type]);
    }
    return sum;
}

int32_t World::transport_of(int32_t id) const {
    const int i = index_of(id);
    return i < 0 ? -1 : actors_[size_t(i)].transport;
}


bool World::can_load(int32_t transport_id, int32_t passenger_id) const {
    const int ti = index_of(transport_id);
    const int pi = index_of(passenger_id);
    if (ti < 0 || pi < 0 || ti == pi) return false;
    if (!actors_[ti].alive || !actors_[pi].alive) return false;
    if (actors_[pi].transport >= 0) return false;
    const UnitType& tt = types_[actors_[ti].type];
    const UnitType& pt = types_[actors_[pi].type];
    if (tt.cargo_max_weight <= 0 || pt.passenger_weight <= 0) return false;
    if (!allied(actors_[ti].owner, actors_[pi].owner)) return false;

    if (tt.cargo_types != 0 && (tt.cargo_types & pt.passenger_type) == 0) return false;
    return cargo_weight(transport_id) + weight_of(pt) <= tt.cargo_max_weight;
}


bool World::landable_ground(size_t i, CPos c) const {
    if (!map_.in_bounds(c)) return false;
    const UnitType& t = types_[actors_[i].type];
    if (t.landable_terrain != 0 && (t.landable_terrain & (1u << uint32_t(map_.terrain(c)))) == 0) return false;
    const int32_t occ = occupant(c);
    return occ < 0 || occ == int32_t(i);
}


bool World::landing_cell_taken(size_t i, CPos c) const {
    for (size_t j = 0; j < actors_.size(); ++j) {
        if (j == i || !types_[actors_[j].type].aircraft || !in_world(j)) continue;
        const Air& o = airs_[j];
        if (o.state == Air::FALLING) continue;
        if ((o.state == Air::LANDED || o.state == Air::LANDING) && to_cell(actors_[j].pos) == c) return true;
        if ((o.land_at_goal == LAND_TOUCHDOWN || o.land_at_goal == LAND_TURN) && to_cell(o.goal) == c) return true;
    }
    return false;
}

bool World::can_land_at(size_t i, CPos c) const {
    return landable_ground(i, c) && !landing_cell_taken(i, c);
}


CPos World::find_landing_cell(size_t i, CPos target, int32_t range) const {
    if (can_land_at(i, target)) return target;

    std::vector<CPos> taken;
    for (size_t j = 0; j < actors_.size(); ++j) {
        if (j == i || !types_[actors_[j].type].aircraft || !in_world(j)) continue;
        const Air& o = airs_[j];
        if (o.state == Air::FALLING) continue;
        if (o.state == Air::LANDED || o.state == Air::LANDING) taken.push_back(to_cell(actors_[j].pos));
        if (o.land_at_goal == LAND_TOUCHDOWN || o.land_at_goal == LAND_TURN) taken.push_back(to_cell(o.goal));
    }
    CPos best{-1, -1};
    int32_t best_d = INT32_MAX;
    for (int32_t dy = -range; dy <= range; ++dy) {
        for (int32_t dx = -range; dx <= range; ++dx) {
            const int32_t d = dx * dx + dy * dy;
            if (d == 0 || d > range * range || d >= best_d) continue;
            const CPos c{target.x + dx, target.y + dy};
            if (!landable_ground(i, c)) continue;
            if (std::find(taken.begin(), taken.end(), c) != taken.end()) continue;
            best = c;
            best_d = d;
        }
    }
    return best;
}


CPos World::pickup_cell(size_t ti) const {
    const Actor& tr = actors_[ti];
    const UnitType& tt = types_[tr.type];
    if (tt.aircraft) {
        const Air& air = airs_[ti];
        if (air.land_at_goal == LAND_TOUCHDOWN || air.land_at_goal == LAND_TURN) return to_cell(air.goal);
        return to_cell(tr.pos);
    }
    return tt.building ? tr.origin : mobiles_[ti].cell;
}


bool World::can_unload(int32_t transport_id) const {
    const int ti = index_of(transport_id);
    if (ti < 0 || !actors_[ti].alive) return false;
    if (cargo_[size_t(ti)].empty()) return false;
    const UnitType& tt = types_[actors_[ti].type];
    CPos at = tt.building ? actors_[ti].origin
        : (tt.aircraft ? to_cell(actors_[ti].pos) : mobiles_[size_t(ti)].cell);
    if (!map_.in_bounds(at)) return false;
    if (tt.aircraft) {
        if (airs_[size_t(ti)].alt > 0) {


            at = find_landing_cell(size_t(ti), at);
            if (at.x < 0) return false;
        } else if (tt.landable_terrain != 0 &&
                   (tt.landable_terrain & (1u << uint32_t(map_.terrain(at)))) == 0) {


            return false;
        }
    }
    for (const int32_t pid : cargo_[size_t(ti)]) {
        const int p = index_of(pid);
        if (p < 0 || !actors_[p].alive) continue;
        if (find_adjacent_cell(at, actors_[p].type).x >= 0) return true;
    }
    return false;
}


bool World::load_passenger(int32_t transport_id, int32_t passenger_id) {
    if (!can_load(transport_id, passenger_id)) return false;
    const int ti = index_of(transport_id);
    const int pi = index_of(passenger_id);
    Actor& p = actors_[size_t(pi)];
    Mobile& m = mobiles_[size_t(pi)];
    clear_slots(size_t(pi));
    stop(size_t(pi), true);
    m.in_transit = false;
    combats_[size_t(pi)].target = -1;
    combats_[size_t(pi)].attack_move = false;
    combats_[size_t(pi)].guard = -1;
    order_queue_[size_t(pi)].clear();
    p.transport = transport_id;
    p.enter_target = -1;
    p.pos = actors_[size_t(ti)].pos;
    cargo_[size_t(ti)].push_back(passenger_id);
    return true;
}


void World::place_passenger(size_t ti, size_t pi, CPos c, int32_t sub) {
    Actor& p = actors_[pi];
    Mobile& m = mobiles_[pi];
    p.transport = -1;
    p.pos = subcell_center(c, sub);


    prev_pos_[pi] = actors_[ti].pos;
    m.cell = c;
    m.to_cell = c;
    m.goal = c;
    m.sub = sub;
    m.to_sub = sub;
    m.in_transit = false;
    m.moving = false;
    if (map_.in_bounds(c)) slot_at(map_.index(c), sub) = int32_t(pi);
}


int32_t World::unload_passenger(int32_t transport_id, CPos at) {
    const int ti = index_of(transport_id);
    if (ti < 0 || cargo_[size_t(ti)].empty()) return -1;
    const int32_t pid = cargo_[size_t(ti)].back();
    const int pi = index_of(pid);
    if (pi < 0 || !actors_[pi].alive) {
        cargo_[size_t(ti)].pop_back();
        return -1;
    }


    const CPos c = find_exit_cell(at, actors_[pi].type);
    if (c.x < 0) return -1;
    const int32_t sub = shares_cell(actors_[pi].type)
        ? free_subcell(c, SUB_DEFAULT, -1) : (cell_free(c, -1) ? int32_t(SUB_FULL) : -1);
    if (sub < 0) return -1;
    cargo_[size_t(ti)].pop_back();
    place_passenger(size_t(ti), size_t(pi), c, sub);
    return pid;
}


int32_t World::drop_passenger(int32_t transport_id, CPos at) {
    const int ti = index_of(transport_id);
    if (ti < 0 || cargo_[size_t(ti)].empty()) return -1;
    if (!map_.in_bounds(at)) return -1;
    const int32_t pid = cargo_[size_t(ti)].back();
    const int pi = index_of(pid);
    if (pi < 0 || !actors_[pi].alive) {
        cargo_[size_t(ti)].pop_back();
        return -1;
    }


    if (!map_.passable(at, type_move_class(actors_[pi].type))) return -1;
    int32_t sub = shares_cell(actors_[pi].type) ? free_subcell(at, SUB_DEFAULT, -1) : int32_t(SUB_FULL);
    if (sub == SUB_INVALID) sub = SUB_DEFAULT;
    cargo_[size_t(ti)].pop_back();
    place_passenger(size_t(ti), size_t(pi), at, sub);
    return pid;
}


void World::order_enter_transport(const int32_t* ids, size_t n, int32_t transport_id) {
    const int ti = index_of(transport_id);
    if (ti < 0 || !actors_[ti].alive || types_[actors_[ti].type].cargo_max_weight <= 0) return;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || i == ti) continue;
        if (types_[actors_[i].type].passenger_weight <= 0) continue;
        actors_[i].enter_target = transport_id;
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        combats_[i].guard = -1;
        combats_[i].attack_cell = CPos{-1, -1};
        order_queue_[size_t(i)].clear();


        if (can_load(transport_id, actors_[i].id) &&
            cell_dist_sq(mobiles_[i].cell, transport_cell(size_t(ti))) > 2)
            approach_transport(size_t(i), size_t(ti), false);
    }
}


CPos World::transport_cell(size_t ti) const {
    const Actor& tr = actors_[ti];
    const UnitType& tt = types_[tr.type];
    return tt.aircraft ? to_cell(tr.pos) : (tt.building ? tr.origin : mobiles_[ti].cell);
}


bool World::board_approach_cell(size_t i, size_t ti, CPos& out) const {
    const UnitType& tt = types_[actors_[ti].type];
    const CPos wc = pickup_cell(ti);
    const CPos avoid = (tt.aircraft || tt.building) ? CPos{-1, -1} : wc;
    return approach_cell(i, wc, 1, 1, false, avoid, actors_[ti].id, out);
}


bool World::transport_in_motion(size_t ti) const {
    const UnitType& tt = types_[actors_[ti].type];
    if (tt.building) return false;
    if (tt.aircraft) {
        const Air& air = airs_[ti];
        if (air.state == Air::TAKING_OFF) return true;
        return air.has_goal && air.land_at_goal != LAND_TOUCHDOWN && air.land_at_goal != LAND_TURN;
    }
    return mobiles_[ti].moving || mobiles_[ti].in_transit;
}


void World::approach_transport(size_t i, size_t ti, bool may_end) {
    Mobile& m = mobiles_[i];
    CPos c{-1, -1};
    if (board_approach_cell(i, ti, c)) {
        if (m.moving || m.in_transit || c != m.cell) set_move(i, c, 0);
        else m.arrived = false;
        return;
    }
    if (may_end && !transport_in_motion(ti)) actors_[i].enter_target = -1;
    stop(i, false);
}


void World::cancel_unload(size_t i) {
    if (!actors_[i].unloading) return;
    actors_[i].unloading = false;
    actors_[i].unload_ticks = -1;
    actors_[i].unload_takeoff = false;
}


void World::lock_for_pickup(size_t ti) {
    Actor& t = actors_[ti];
    if (t.load_lock) return;
    const UnitType& tt = types_[t.type];
    if (tt.aircraft && airs_[ti].alt > 0) {
        const Air& air = airs_[ti];
        const bool landing = air.state == Air::LANDING || air.land_at_goal != LAND_NONE;
        if (!landing) {
            const CPos here = to_cell(t.pos);
            const CPos lc = find_landing_cell(ti, here);
            if (lc.x < 0) return;
            stop(ti, false);
            order_queue_[ti].clear();
            air_move(ti, lc == here ? t.pos : cell_center(lc), true);
        }
        t.load_takeoff = !lands_when_idle(tt);
    } else {
        stop(ti, false);
        order_queue_[ti].clear();
    }
    t.load_lock = true;
    t.after_load_ticks = -1;
}


void World::air_take_off(size_t i) {
    Air& air = airs_[i];
    if (air.state == Air::LANDED || air.state == Air::LANDING) air.state = Air::TAKING_OFF;
    air.land_at_goal = LAND_NONE;
    air.returning = false;
}


void World::order_unload(const int32_t* ids, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || cargo_[size_t(i)].empty()) continue;


        if (!can_unload(actors_[i].id)) continue;
        actors_[i].unloading = true;
        actors_[i].unload_ticks = types_[actors_[i].type].before_unload_delay;
        stop(size_t(i), false);


        if (types_[actors_[i].type].aircraft && airs_[size_t(i)].alt > 0) {


            actors_[i].unload_takeoff = !lands_when_idle(types_[actors_[i].type]);
            const CPos here = to_cell(actors_[i].pos);
            const CPos lc = find_landing_cell(size_t(i), here);
            air_move(size_t(i), (lc.x < 0 || lc == here) ? actors_[i].pos : cell_center(lc), true);
        }
    }
}

void World::step_cargo() {

    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive || a.transport >= 0 || a.enter_target < 0) continue;
        const int ti = index_of(a.enter_target);
        if (ti < 0 || !actors_[ti].alive || !can_load(a.enter_target, a.id)) {
            a.enter_target = -1;
            continue;
        }
        const Actor& tr = actors_[size_t(ti)];
        const CPos tc = transport_cell(size_t(ti));


        const CPos wc = pickup_cell(size_t(ti));

        if (cell_dist_sq(mobiles_[i].cell, tc) <= 2) {


            lock_for_pickup(size_t(ti));

            if (!types_[tr.type].aircraft || airs_[size_t(ti)].alt == 0) {
                const int32_t tid = a.enter_target;
                load_passenger(tid, a.id);
            }
            continue;
        }


        const Mobile& m = mobiles_[i];
        if (m.moving) {
            if (cell_dist_sq(m.goal, wc) > 2) approach_transport(i, size_t(ti), true);
        } else if (!m.in_transit) {

            if (wc != tc && cell_dist_sq(m.cell, wc) <= 2) continue;
            if (m.arrived || (tick_ + uint32_t(a.id)) % ENTER_RETRY_TICKS == 0)
                approach_transport(i, size_t(ti), true);
        }
    }


    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive) continue;
        if (a.load_lock) {
            bool still_reserved = false;
            for (size_t p = 0; p < actors_.size() && !still_reserved; ++p) {
                if (!actors_[p].alive || actors_[p].transport >= 0 || actors_[p].enter_target != a.id) continue;
                const CPos tc = types_[a.type].aircraft ? to_cell(a.pos)
                    : (types_[a.type].building ? a.origin : mobiles_[i].cell);
                still_reserved = cell_dist_sq(mobiles_[p].cell, tc) <= 2;
            }
            if (still_reserved) continue;
            a.load_lock = false;
            a.after_load_ticks = types_[a.type].after_load_delay;
        }
        if (a.after_load_ticks >= 0 && --a.after_load_ticks < 0 && a.load_takeoff) {
            a.load_takeoff = false;
            air_take_off(i);
        }
    }


    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive || !a.unloading) continue;
        if (types_[a.type].aircraft && airs_[i].alt > 0) continue;
        if (a.unload_ticks > 0) { --a.unload_ticks; continue; }
        if (cargo_[i].empty()) {

            a.unloading = false;
            a.unload_ticks = -1;
            if (a.unload_takeoff) {
                a.unload_takeoff = false;
                air_take_off(i);
            }
            continue;
        }
        const CPos at = types_[a.type].building ? a.origin
            : (types_[a.type].aircraft ? to_cell(a.pos) : mobiles_[i].cell);
        if (unload_passenger(a.id, at) < 0) {
            a.unload_ticks = 10;
            continue;
        }
        a.unload_ticks = cargo_[i].empty() ? types_[a.type].after_unload_delay
                                           : types_[a.type].between_unload_delay;
    }
}


bool World::ramp_should_open(size_t i) const {
    const UnitType& t = types_[actors_[i].type];
    if (t.ramp_terrain == 0) return false;


    const Mobile& m = mobiles_[i];
    if (m.moving || m.in_transit) return false;


    if (t.aircraft && airs_[i].alt > 0) return false;
    const CPos at = t.building ? actors_[i].origin : m.cell;
    if (!map_.in_bounds(at)) return false;

    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) continue;
            const CPos c{at.x + dx, at.y + dy};
            if (!map_.in_bounds(c)) continue;
            if ((t.ramp_terrain & (1u << uint32_t(map_.terrain(c)))) != 0) return true;
        }
    }
    return false;
}


void World::step_landing_craft() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive || types_[a.type].ramp_terrain == 0) continue;
        const int32_t len = std::max(1, types_[a.type].ramp_ticks);
        const bool want = ramp_should_open(i);
        switch (a.ramp) {
            case RAMP_CLOSED:
                if (want) { a.ramp = RAMP_OPENING; a.ramp_frame = 0; }
                break;
            case RAMP_OPENING:


                if (!want) { a.ramp = RAMP_CLOSING; a.ramp_frame = 0; }
                else if (++a.ramp_frame >= len) {

                    a.ramp = RAMP_OPEN;
                    a.ramp_frame = 0;
                }
                break;
            case RAMP_OPEN:
                if (!want) { a.ramp = RAMP_CLOSING; a.ramp_frame = 0; }
                break;
            case RAMP_CLOSING:
                if (want) { a.ramp = RAMP_OPENING; a.ramp_frame = 0; }
                else if (++a.ramp_frame >= len) { a.ramp = RAMP_CLOSED; a.ramp_frame = 0; }
                break;
            default:
                a.ramp = RAMP_CLOSED;
                a.ramp_frame = 0;
                break;
        }
    }
}

int32_t World::ramp_state(int32_t id) const {
    const int i = index_of(id);
    return i < 0 ? int32_t(RAMP_CLOSED) : actors_[size_t(i)].ramp;
}

}
