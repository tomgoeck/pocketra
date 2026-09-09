

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


int32_t World::unload_passenger(int32_t transport_id, CPos at) {
    const int ti = index_of(transport_id);
    if (ti < 0 || cargo_[size_t(ti)].empty()) return -1;
    const int32_t pid = cargo_[size_t(ti)].back();
    const int pi = index_of(pid);
    if (pi < 0 || !actors_[pi].alive) {
        cargo_[size_t(ti)].pop_back();
        return -1;
    }


    const CPos c = find_adjacent_cell(at, actors_[pi].type);
    if (c.x < 0) return -1;
    const int32_t sub = shares_cell(actors_[pi].type)
        ? free_subcell(c, SUB_DEFAULT, -1) : (cell_free(c, -1) ? int32_t(SUB_FULL) : -1);
    if (sub < 0) return -1;
    cargo_[size_t(ti)].pop_back();
    Actor& p = actors_[size_t(pi)];
    Mobile& m = mobiles_[size_t(pi)];
    p.transport = -1;
    p.pos = subcell_center(c, sub);
    prev_pos_[size_t(pi)] = p.pos;
    m.cell = c;
    m.to_cell = c;
    m.goal = c;
    m.sub = sub;
    m.to_sub = sub;
    m.in_transit = false;
    m.moving = false;
    if (map_.in_bounds(c)) slot_at(map_.index(c), sub) = pi;
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
    }
}


void World::order_unload(const int32_t* ids, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || cargo_[size_t(i)].empty()) continue;
        actors_[i].unloading = true;
        actors_[i].unload_ticks = types_[actors_[i].type].before_unload_delay;
        stop(size_t(i), false);

        if (types_[actors_[i].type].aircraft) air_move(size_t(i), actors_[i].pos, true);
    }
}

void World::step_cargo() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive) continue;


        if (a.transport < 0 && a.enter_target >= 0) {
            const int ti = index_of(a.enter_target);
            if (ti < 0 || !actors_[ti].alive || !can_load(a.enter_target, a.id)) {
                a.enter_target = -1;
            } else {
                const Actor& tr = actors_[size_t(ti)];
                const CPos tc = types_[tr.type].aircraft ? to_cell(tr.pos)
                    : (types_[tr.type].building ? tr.origin : mobiles_[size_t(ti)].cell);

                const bool ready = !types_[tr.type].aircraft || airs_[size_t(ti)].alt == 0;
                if (ready && cell_dist_sq(mobiles_[i].cell, tc) <= 2) {
                    const int32_t tid = a.enter_target;
                    load_passenger(tid, a.id);
                    continue;
                }


                if (!mobiles_[i].moving && !mobiles_[i].in_transit) {
                    const CPos adj = find_adjacent_cell(tc, actors_[i].type);
                    if (adj.x >= 0 && mobiles_[i].goal != adj) set_move(i, adj, 0);
                }
            }
        }


        if (!a.unloading) continue;
        if (types_[a.type].aircraft && airs_[i].alt > 0) continue;
        if (a.unload_ticks > 0) { --a.unload_ticks; continue; }
        if (cargo_[i].empty()) {
            a.unloading = false;
            a.unload_ticks = -1;
            continue;
        }
        const CPos at = types_[a.type].building ? a.origin
            : (types_[a.type].aircraft ? to_cell(a.pos) : mobiles_[i].cell);
        if (unload_passenger(a.id, at) < 0) {
            a.unload_ticks = 5;
            continue;
        }
        a.unload_ticks = types_[a.type].between_unload_delay;
        if (cargo_[i].empty()) {
            a.unloading = false;
            a.unload_ticks = -1;
        }
    }
}

}
