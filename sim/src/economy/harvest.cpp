

#include <algorithm>
#include <climits>

#include "ra/sim.h"

namespace ra {


constexpr int32_t DOCK_WAIT = 10;

constexpr WAngle DOCK_TOLERANCE = 16;


void World::set_resource(CPos c, int32_t type, int32_t density) {
    if (!map_.in_bounds(c)) return;
    const int i = map_.index(c);
    const int32_t base = map_.base_terrain(c);
    const bool allowed = (base == TER_CLEAR || base == TER_ROAD);
    if (type <= RES_NONE || density <= 0) {
        res_type_[i] = RES_NONE;
        res_density_[i] = 0;
        if (allowed) map_.set_terrain_at(c, base);
    } else {
        const int32_t max = type == RES_GEMS ? GEMS_MAX_DENSITY : ORE_MAX_DENSITY;
        res_type_[i] = static_cast<uint8_t>(type);
        res_density_[i] = static_cast<uint8_t>(density > max ? max : density);
        if (allowed) map_.set_terrain_at(c, type == RES_GEMS ? TER_GEMS : TER_ORE);
    }
    ++resource_version_;
}


void World::step_cash_tricklers() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.make_ticks > 0 || a.sell_ticks >= 0) continue;
        const UnitType& t = types_[a.type];
        if (t.cash_amount <= 0) continue;
        if ((tick_ + uint32_t(a.id)) % uint32_t(std::max(1, t.cash_interval)) != 0) continue;
        give_credits(a.owner, t.cash_amount);


        cash_ticks_.push_back(CashTick{a.owner, t.cash_amount, a.pos});
    }
}

void World::step_seeds() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.seeds_resource == RES_NONE) continue;
        if ((tick_ + uint32_t(a.id)) % uint32_t(std::max(1, t.seed_interval)) != 0) continue;
        CPos c = a.origin;
        const int32_t max = t.seeds_resource == RES_GEMS ? GEMS_MAX_DENSITY : ORE_MAX_DENSITY;
        for (int step = 0; step < 100; ++step) {
            if (map_.in_bounds(c)) {
                const int idx = map_.index(c);
                const int32_t base = map_.base_terrain(c);
                const bool allowed = (base == TER_CLEAR || base == TER_ROAD) && cell_empty(c);
                if (allowed && (res_type_[idx] == RES_NONE || res_type_[idx] == t.seeds_resource) &&
                    res_density_[idx] < max) {
                    set_resource(c, t.seeds_resource, res_density_[idx] + 1);
                    break;
                }
            }
            const int d = int(rand() % NUM_DIRS);
            c = CPos{c.x + DIR_DX[d], c.y + DIR_DY[d]};
        }
    }
}

bool World::can_harvest_cell(CPos c) const {
    return map_.in_bounds(c) && res_density_[map_.index(c)] > 0 && map_.passable(c);
}


void World::order_harvest(const int32_t* ids, size_t n, CPos cell) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || !types_[actors_[i].type].harvester) continue;
        Harvest& h = harvests_[i];
        release_claim(i);
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        stop(i, false);
        h.automated = true;
        h.state = Harvest::SEARCH;
        h.order_cell = cell;
        h.has_order = map_.in_bounds(cell);
    }
}


bool World::order_deliver(const int32_t* ids, size_t n, int32_t refinery_id) {
    const int r = index_of(refinery_id);
    if (r < 0 || !actors_[r].alive || !types_[actors_[r].type].refinery) return false;
    if (actors_[r].make_ticks > 0 || actors_[r].sell_ticks >= 0) return false;
    bool any = false;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || !types_[actors_[i].type].harvester) continue;
        if (!allied(actors_[i].owner, actors_[r].owner)) continue;
        Harvest& h = harvests_[i];
        release_claim(i);
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        stop(i, false);
        h.automated = true;
        h.has_order = false;
        h.linked_proc = refinery_id;
        h.proc = refinery_id;
        h.state = Harvest::TO_DOCK;
        h.timer = 0;
        any = true;
    }
    return any;
}

void World::release_claim(size_t i) {
    Harvest& h = harvests_[i];
    if (h.claim >= 0 && claims_[h.claim] == static_cast<int32_t>(i)) claims_[h.claim] = -1;
    h.claim = -1;
}


bool World::closest_harvestable(size_t i, CPos& out) {
    const Mobile& m = mobiles_[i];
    Harvest& h = harvests_[i];
    const UnitType& t = types_[actors_[i].type];
    const int32_t self = static_cast<int32_t>(i);

    auto claimable = [&](CPos c) { return can_harvest_cell(c) && (claims_[map_.index(c)] == -1 || claims_[map_.index(c)] == self); };

    if (h.has_order) {
        if (claimable(h.order_cell)) {
            out = h.order_cell;
            return true;
        }
        h.has_order = false;
    } else if (claimable(m.cell)) {
        out = m.cell;
        return true;
    }

    CPos center;
    int32_t radius;
    if (h.has_last) {
        center = h.last_cell;
        radius = t.search_from_harv;
    } else {
        radius = t.search_from_proc;
        const int proc = nearest_refinery(i);
        center = proc >= 0 ? dock_cell(proc) : m.cell;
    }
    const int64_t r2 = int64_t(radius) * radius;
    int64_t best_d = INT64_MAX;
    bool found = false;
    for (int y = center.y - radius; y <= center.y + radius; ++y) {
        for (int x = center.x - radius; x <= center.x + radius; ++x) {
            const CPos c{x, y};
            if (cell_dist_sq(c, center) > r2 || !claimable(c)) continue;
            const int64_t d = cell_dist_sq(c, m.cell);
            if (d < best_d) {
                best_d = d;
                out = c;
                found = true;
            }
        }
    }
    return found;
}

int World::nearest_refinery(size_t i) const {
    const Actor& a = actors_[i];
    int best = -1;
    int64_t best_d = INT64_MAX;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& o = actors_[k];
        if (!o.alive || o.owner != a.owner || !types_[o.type].refinery) continue;
        if (o.make_ticks > 0 || o.sell_ticks >= 0) continue;
        const int64_t d = length_sq(o.pos - a.pos);
        if (d < best_d) {
            best_d = d;
            best = static_cast<int>(k);
        }
    }
    return best;
}

CPos World::dock_cell(int proc) const {
    const UnitType& t = types_[actors_[proc].type];
    return {actors_[proc].origin.x + t.dock_dx, actors_[proc].origin.y + t.dock_dy};
}


void World::step_harvester(size_t i) {
    Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    if (!t.harvester) return;
    Harvest& h = harvests_[i];
    Mobile& m = mobiles_[i];


    if (!h.automated) return;

    switch (h.state) {
    case Harvest::IDLE:
        h.state = Harvest::SEARCH;
        [[fallthrough]];

    case Harvest::SEARCH: {
        if (h.bales >= t.capacity) {
            h.state = Harvest::TO_DOCK;
            break;
        }
        CPos target;
        bool found = closest_harvestable(i, target);
        if (!found && h.has_last) {
            h.has_last = false;
            found = closest_harvestable(i, target);
        }
        if (!found) {
            if (h.bales > 0) {
                h.state = Harvest::TO_DOCK;
            } else {
                h.timer = t.wait_duration;
                h.state = Harvest::WAIT;
            }
            break;
        }
        release_claim(i);
        h.claim = map_.index(target);
        claims_[h.claim] = static_cast<int32_t>(i);
        h.target = target;
        if (m.cell != target) set_move(i, target, 0);
        h.state = Harvest::TO_FIELD;
        break;
    }

    case Harvest::TO_FIELD:
        if (m.moving || m.in_transit) break;
        if (m.cell == h.target) {
            h.state = Harvest::HARVESTING;
            h.timer = 0;
        } else {
            h.state = Harvest::SEARCH;
        }
        break;

    case Harvest::HARVESTING: {
        if (h.bales >= t.capacity) {
            release_claim(i);
            h.state = Harvest::TO_DOCK;
            break;
        }
        const int ci = map_.index(m.cell);
        if (res_density_[ci] == 0) {
            release_claim(i);
            h.last_cell = m.cell;
            h.has_last = true;
            h.state = Harvest::SEARCH;
            break;
        }

        if (t.harvest_facings > 0) {
            const WAngle step = FULL_TURN / t.harvest_facings;
            const WAngle desired = wrap_angle(((a.facing + step / 2) / step) * step);
            if (a.facing != desired) {
                a.facing = turn_towards(a.facing, desired, t.turn_rate);
                break;
            }
        }
        ++h.anim;
        if (h.timer > 0) {
            --h.timer;
            break;
        }
        h.bale_value += RESOURCE_VALUE[res_type_[ci] < 3 ? res_type_[ci] : RES_ORE];
        --res_density_[ci];
        if (res_density_[ci] == 0) res_type_[ci] = RES_NONE;
        ++resource_version_;
        ++h.bales;
        h.timer = t.bale_load_delay;
        break;
    }

    case Harvest::TO_DOCK: {


        int proc = -1;
        if (h.linked_proc >= 0) {
            const int li = index_of(h.linked_proc);
            if (li >= 0 && actors_[li].alive && actors_[li].sell_ticks < 0 && actors_[li].make_ticks == 0) proc = li;
            else h.linked_proc = -1;
        }
        if (proc < 0) proc = nearest_refinery(i);
        if (proc < 0) {
            h.timer = t.wait_duration;
            h.state = Harvest::WAIT;
            break;
        }
        h.proc = actors_[proc].id;
        const CPos dock = dock_cell(proc);
        if (m.cell == dock && !m.in_transit) {
            h.state = Harvest::DOCK_TURN;
            h.timer = DOCK_WAIT;
        } else if (!m.moving && !m.in_transit) {
            if (h.timer > 0) {
                --h.timer;
                break;
            }
            set_move(i, dock, 0);
            h.timer = t.wait_duration;
        }
        break;
    }

    case Harvest::DOCK_TURN: {
        const int proc = index_of(h.proc);
        if (proc < 0 || !actors_[proc].alive) {
            h.state = Harvest::TO_DOCK;
            break;
        }
        if (h.timer > 0) {
            --h.timer;
            break;
        }
        const WAngle angle = types_[actors_[proc].type].dock_angle;
        a.facing = turn_towards(a.facing, angle, t.turn_rate);
        if (abs_angle_diff(a.facing, angle) <= DOCK_TOLERANCE) {
            h.state = Harvest::UNLOADING;
            h.timer = 0;
            h.anim = 0;
        }
        break;
    }

    case Harvest::UNLOADING: {
        ++h.anim;

        const int proc = index_of(h.proc);
        if (proc < 0 || !actors_[proc].alive || actors_[proc].sell_ticks >= 0) {
            h.proc = -1;
            h.state = Harvest::TO_DOCK;
            break;
        }
        if (h.bales == 0) {

            h.timer = 0;
            h.state = Harvest::WAIT;
            break;
        }
        if (h.timer > 0) {
            --h.timer;
            break;
        }
        const int32_t per = h.bales > 0 ? h.bale_value / h.bales : 0;


        if (storage_room(a.owner) < per) {
            h.timer = t.bale_unload_delay;
            break;
        }
        --h.bales;
        give_resources(a.owner, per);
        h.bale_value -= per;
        h.timer = t.bale_unload_delay;
        break;
    }

    case Harvest::WAIT:
        if (--h.timer <= 0) h.state = Harvest::SEARCH;
        break;
    }
}

}
