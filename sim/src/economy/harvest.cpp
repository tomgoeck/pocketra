

#include <algorithm>
#include <climits>

#include "ra/sim.h"

namespace ra {


constexpr int32_t DOCK_WAIT = 10;

constexpr WAngle DOCK_TOLERANCE = 16;


constexpr int32_t MAX_FIELD_FAILS = 2;

constexpr int32_t EXPLORE_RECHECK = 50;


constexpr int32_t BLIND_TRIES = 3;


int32_t World::resource_value_at(CPos c) const {
    if (!map_.in_bounds(c)) return 0;
    const int i = map_.index(c);
    const int32_t t = res_type_[i] < 3 ? res_type_[i] : RES_ORE;
    return int32_t(res_density_[i]) * RESOURCE_VALUE[t];
}

void World::rebuild_res_blocks() {
    res_block_w_ = (map_.width() + RES_BLOCK - 1) / RES_BLOCK;
    res_block_h_ = (map_.height() + RES_BLOCK - 1) / RES_BLOCK;
    res_block_.assign(size_t(res_block_w_ > 0 ? res_block_w_ : 0) * size_t(res_block_h_ > 0 ? res_block_h_ : 0), 0);
    if (res_block_.empty()) return;
    for (int i = 0; i < map_.cells(); ++i) {
        const CPos c = map_.cell_at(i);
        const int32_t v = resource_value_at(c);
        if (v != 0) res_block_[size_t(c.y / RES_BLOCK) * size_t(res_block_w_) + size_t(c.x / RES_BLOCK)] += v;
    }
}

void World::add_res_value(CPos c, int32_t delta) {
    if (delta == 0 || res_block_.empty() || !map_.in_bounds(c)) return;
    res_block_[size_t(c.y / RES_BLOCK) * size_t(res_block_w_) + size_t(c.x / RES_BLOCK)] += delta;
}


int64_t World::field_value(CPos c) const {
    if (res_block_.empty() || !map_.in_bounds(c)) return 0;
    const int32_t bx = c.x / RES_BLOCK, by = c.y / RES_BLOCK;
    int64_t sum = 0;
    for (int32_t y = by - 1; y <= by + 1; ++y) {
        if (y < 0 || y >= res_block_h_) continue;
        for (int32_t x = bx - 1; x <= bx + 1; ++x) {
            if (x < 0 || x >= res_block_w_) continue;
            sum += res_block_[size_t(y) * size_t(res_block_w_) + size_t(x)];
        }
    }
    return sum;
}


bool World::resource_known(int32_t owner, CPos c) const {
    if (owner < 0 || owner >= MAX_PLAYERS) return true;
    if (((vis_players_ >> owner) & 1u) == 0) return true;
    return explored(owner, c);
}


void World::set_resource(CPos c, int32_t type, int32_t density) {
    if (!map_.in_bounds(c)) return;
    const int i = map_.index(c);
    const int32_t before = resource_value_at(c);
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
    add_res_value(c, resource_value_at(c) - before);
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
        h.park = false;
        h.dock_held = false;
        h.queue_tick = -1;
        h.has_wait = false;
        h.has_avoid = false;
        h.fails = 0;
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
        h.park = false;
        h.has_order = false;
        h.linked_proc = refinery_id;
        h.proc = refinery_id;
        h.dock_held = false;
        h.queue_tick = -1;
        h.has_wait = false;
        h.state = Harvest::TO_DOCK;
        h.timer = 0;
        any = true;
    }
    return any;
}


void World::order_harvesters_return_to_base(int32_t owner) {
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].harvester) continue;
        Harvest& h = harvests_[i];
        h.park = true;

        if (h.state == Harvest::UNLOADING || h.state == Harvest::DOCK_TURN) continue;
        release_claim(i);
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        stop(i, false);
        h.automated = true;
        h.has_order = false;
        h.dock_held = false;
        h.queue_tick = -1;
        h.has_wait = false;
        h.has_avoid = false;
        h.fails = 0;
        h.timer = 0;
        h.state = Harvest::PARKING;
    }
}

void World::order_harvesters_resume(int32_t owner) {
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].harvester) continue;
        Harvest& h = harvests_[i];
        h.park = false;
        switch (h.state) {
        case Harvest::PARKED:
        case Harvest::PARKING:
        case Harvest::IDLE:
        case Harvest::WAIT:
        case Harvest::EXPLORE:
            stop(i, false);
            h.automated = true;
            h.has_wait = false;
            h.timer = 0;
            h.state = Harvest::SEARCH;
            break;
        default:
            break;
        }
    }
}

void World::release_claim(size_t i) {
    Harvest& h = harvests_[i];
    if (h.claim >= 0 && claims_[h.claim] == static_cast<int32_t>(i)) claims_[h.claim] = -1;
    h.claim = -1;
}


namespace {


int64_t refinery_direction_penalty(CPos cell, CPos harv, CPos dock) {
    const int64_t b2 = cell_dist_sq(cell, dock);
    const int64_t c2 = cell_dist_sq(cell, harv);
    const int64_t a2 = cell_dist_sq(harv, dock);
    const int64_t bl = isqrt(b2), cl = isqrt(c2);
    if (bl == 0 || cl == 0) return 0;
    const int64_t cos_a = 512 * (b2 + c2 - a2) / bl / cl;
    int64_t p = REFINERY_DIRECTION_PENALTY / 2 + REFINERY_DIRECTION_PENALTY * cos_a / 2048;
    if (p < 0) p = 0;
    if (p > REFINERY_DIRECTION_PENALTY) p = REFINERY_DIRECTION_PENALTY;
    return p;
}

struct Candidate {
    int64_t cost = INT64_MAX;
    CPos cell{0, 0};
    bool ok = false;
};

}


bool World::closest_harvestable(size_t i, CPos& out, bool ignore_shroud) {
    const Mobile& m = mobiles_[i];
    Harvest& h = harvests_[i];
    const UnitType& t = types_[actors_[i].type];
    const int32_t owner = actors_[i].owner;
    const int32_t self = static_cast<int32_t>(i);

    auto claimable = [&](CPos c) {
        if (!can_harvest_cell(c)) return false;
        const int32_t cl = claims_[map_.index(c)];
        if (cl != -1 && cl != self) return false;
        return ignore_shroud || resource_known(owner, c);
    };

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


    int proc = h.proc >= 0 ? index_of(h.proc) : -1;
    if (proc >= 0 && (!actors_[proc].alive || !types_[actors_[proc].type].refinery)) proc = -1;
    if (proc < 0) proc = nearest_refinery(i);
    const bool have_dock = proc >= 0;
    const CPos dock = have_dock ? dock_cell(proc) : m.cell;

    const int64_t rich_need = int64_t(RICH_LOADS) * std::max(1, t.capacity) * RESOURCE_VALUE[RES_ORE];
    Candidate rich, any;

    auto cost_of = [&](CPos c) {
        int64_t cost = int64_t(isqrt(cell_dist_sq(c, m.cell))) * 10;
        if (have_dock) cost += refinery_direction_penalty(c, m.cell, dock);
        if (res_type_[map_.index(c)] == RES_GEMS) cost -= GEM_BONUS;
        return cost;
    };


    auto scan = [&](CPos center, int32_t radius) {
        int x0 = 0, y0 = 0, x1 = map_.width() - 1, y1 = map_.height() - 1;
        if (radius >= 0) {
            x0 = std::max(0, center.x - radius);
            y0 = std::max(0, center.y - radius);
            x1 = std::min(map_.width() - 1, center.x + radius);
            y1 = std::min(map_.height() - 1, center.y + radius);
        }
        const int64_t r2 = int64_t(radius) * radius;
        for (int y = y0; y <= y1; ++y) {
            for (int x = x0; x <= x1; ++x) {
                const CPos c{x, y};
                if (radius >= 0 && cell_dist_sq(c, center) > r2) continue;
                if (h.has_avoid && c == h.avoid_cell) continue;
                if (!claimable(c)) continue;
                const int64_t cost = cost_of(c);
                if (cost < any.cost) any = Candidate{cost, c, true};
                if (cost < rich.cost && field_value(c) >= rich_need) rich = Candidate{cost, c, true};
            }
        }
    };

    if (h.has_last) scan(h.last_cell, t.search_from_harv);
    if (!rich.ok) scan(dock, t.search_from_proc);
    if (!rich.ok) scan(m.cell, -1);

    if (rich.ok) {
        out = rich.cell;
        return true;
    }
    if (any.ok) {
        out = any.cell;
        return true;
    }
    return false;
}


bool World::frontier_cell(size_t i, CPos& out) const {
    const int32_t owner = actors_[i].owner;
    if (owner < 0 || owner >= MAX_PLAYERS) return false;
    if (((vis_players_ >> owner) & 1u) == 0) return false;
    const int32_t mc = actor_move_class(i);
    const CPos from = mobiles_[i].cell;
    int64_t best = INT64_MAX;
    bool ok = false;
    for (int idx = 0; idx < map_.cells(); ++idx) {
        const CPos c = map_.cell_at(idx);
        if (!map_.passable(c, mc) || !explored(owner, c)) continue;
        const int64_t d = cell_dist_sq(c, from);
        if (d >= best) continue;
        bool border = false;
        for (int k = 0; k < NUM_DIRS && !border; ++k) {
            const CPos n{c.x + DIR_DX[k], c.y + DIR_DY[k]};
            if (map_.in_bounds(n) && !explored(owner, n)) border = true;
        }
        if (!border) continue;
        best = d;
        out = c;
        ok = true;
    }
    return ok;
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


int World::choose_refinery(size_t i) const {
    const Actor& a = actors_[i];
    int best = -1;
    int64_t best_cost = INT64_MAX;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& o = actors_[k];
        if (!o.alive || o.owner != a.owner || !types_[o.type].refinery) continue;
        if (o.make_ticks > 0 || o.sell_ticks >= 0) continue;
        const int32_t res = dock_reservations(o.id, int32_t(i));
        int64_t cost = int64_t(isqrt(cell_dist_sq(dock_cell(int(k)), mobiles_[i].cell))) * 10;
        cost += int64_t(res) * DOCK_QUEUE_COST;
        if (res >= MAX_DOCK_QUEUE) cost += DOCK_FULL_COST;
        if (cost < best_cost) {
            best_cost = cost;
            best = static_cast<int>(k);
        }
    }
    return best;
}

CPos World::dock_cell(int proc) const {
    const UnitType& t = types_[actors_[proc].type];
    return {actors_[proc].origin.x + t.dock_dx, actors_[proc].origin.y + t.dock_dy};
}

namespace {

inline bool at_proc(const Harvest& h, int32_t proc_id) {
    if (h.proc != proc_id) return false;
    return h.state == Harvest::TO_DOCK || h.state == Harvest::QUEUE ||
           h.state == Harvest::DOCK_TURN || h.state == Harvest::UNLOADING;
}
}

int32_t World::dock_reservations(int32_t proc_id, int32_t self) const {
    int32_t n = 0;
    for (size_t k = 0; k < actors_.size(); ++k) {
        if (int32_t(k) == self) continue;
        if (!actors_[k].alive || !types_[actors_[k].type].harvester) continue;
        if (at_proc(harvests_[k], proc_id)) ++n;
    }
    return n;
}

int World::dock_holder(int32_t proc_id, int32_t self) const {
    for (size_t k = 0; k < actors_.size(); ++k) {
        if (int32_t(k) == self) continue;
        if (!actors_[k].alive || !types_[actors_[k].type].harvester) continue;
        const Harvest& o = harvests_[k];
        if (!o.dock_held || o.proc != proc_id) continue;
        if (o.state == Harvest::TO_DOCK || o.state == Harvest::DOCK_TURN || o.state == Harvest::UNLOADING)
            return static_cast<int>(k);
    }
    return -1;
}

int32_t World::dock_queue_rank(size_t i, int32_t proc_id) const {
    const Harvest& me = harvests_[i];
    int32_t rank = 0;
    for (size_t k = 0; k < actors_.size(); ++k) {
        if (k == i) continue;
        if (!actors_[k].alive || !types_[actors_[k].type].harvester) continue;
        const Harvest& o = harvests_[k];
        if (o.state != Harvest::QUEUE || o.proc != proc_id) continue;
        if (o.queue_tick < me.queue_tick ||
            (o.queue_tick == me.queue_tick && actors_[k].id < actors_[i].id)) ++rank;
    }
    return rank;
}


CPos World::side_cell(CPos anchor, CPos exclude, int32_t slot) const {
    int32_t count = 0;
    for (int r = 1; r <= 8; ++r) {
        for (int dy = -r; dy <= r; ++dy) {
            for (int dx = -r; dx <= r; ++dx) {
                if (dx > -r && dx < r && dy > -r && dy < r) continue;
                const CPos c{anchor.x + dx, anchor.y + dy};
                if (c == exclude || !map_.in_bounds(c) || !map_.passable(c)) continue;
                if (count++ == slot) return c;
            }
        }
    }
    return anchor;
}

CPos World::dock_queue_cell(int proc, int32_t slot) const {
    const Actor& a = actors_[proc];
    const UnitType& t = types_[a.type];
    const CPos dock = dock_cell(proc);
    const CPos centre{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2};

    int ax = dock.x > centre.x ? 1 : (dock.x < centre.x ? -1 : 0);
    int ay = dock.y > centre.y ? 1 : (dock.y < centre.y ? -1 : 0);
    if (ax == 0 && ay == 0) ay = 1;
    const CPos anchor{dock.x + ax * 3, dock.y + ay * 3};
    return side_cell(anchor, dock, slot);
}


int World::nearest_base(size_t i) const {
    const Actor& a = actors_[i];
    for (int pass = 0; pass < 2; ++pass) {
        int best = -1;
        int64_t best_d = INT64_MAX;
        for (size_t k = 0; k < actors_.size(); ++k) {
            const Actor& o = actors_[k];
            if (!o.alive || o.owner != a.owner || !types_[o.type].building) continue;
            if (o.sell_ticks >= 0) continue;
            const bool fit = pass == 0 ? types_[o.type].base_provider : types_[o.type].refinery;
            if (!fit) continue;
            const int64_t d = length_sq(o.pos - a.pos);
            if (d < best_d) {
                best_d = d;
                best = static_cast<int>(k);
            }
        }
        if (best >= 0) return best;
    }
    return -1;
}

int32_t World::park_rank(size_t i) const {
    int32_t rank = 0;
    for (size_t k = 0; k < actors_.size(); ++k) {
        if (k == i) continue;
        if (!actors_[k].alive || actors_[k].owner != actors_[i].owner) continue;
        if (!types_[actors_[k].type].harvester) continue;
        const Harvest& o = harvests_[k];
        if (o.state != Harvest::PARKING && o.state != Harvest::PARKED) continue;
        if (actors_[k].id < actors_[i].id) ++rank;
    }
    return rank;
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
        h.state = h.park ? Harvest::PARKING : Harvest::SEARCH;
        [[fallthrough]];

    case Harvest::SEARCH: {
        if (h.park) {
            h.state = Harvest::PARKING;
            break;
        }
        if (h.bales >= t.capacity) {
            h.state = Harvest::TO_DOCK;
            break;
        }
        CPos target;
        bool found = closest_harvestable(i, target);


        if (!found && h.has_avoid) {
            h.has_avoid = false;
            found = closest_harvestable(i, target);
        }
        if (!found) {
            if (h.bales > 0) {
                h.state = Harvest::TO_DOCK;
                break;
            }

            CPos front;
            if (frontier_cell(i, front)) {
                h.blind = 0;
                set_move(i, front, 2);
                h.timer = EXPLORE_RECHECK;
                h.state = Harvest::EXPLORE;
                break;
            }


            if (++h.blind >= BLIND_TRIES && closest_harvestable(i, target, true)) {
                h.blind = 0;
                found = true;
            } else {
                if (h.blind > BLIND_TRIES) h.blind = BLIND_TRIES;
                h.timer = t.wait_duration;
                h.state = Harvest::WAIT;
                break;
            }
        }
        h.blind = 0;
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
            h.fails = 0;
            h.has_avoid = false;
            h.state = Harvest::HARVESTING;
            h.timer = 0;
        } else {


            if (++h.fails >= MAX_FIELD_FAILS) {
                h.avoid_cell = h.target;
                h.has_avoid = true;
                h.fails = 0;
            }
            release_claim(i);
            h.state = Harvest::SEARCH;
        }
        break;

    case Harvest::HARVESTING: {
        if (h.park) {
            release_claim(i);
            h.state = Harvest::PARKING;
            break;
        }
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
        const int32_t rt = res_type_[ci] < 3 ? res_type_[ci] : RES_ORE;
        h.bale_value += RESOURCE_VALUE[rt];
        add_res_value(m.cell, -RESOURCE_VALUE[rt]);
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
        if (proc < 0 && h.dock_held && h.proc >= 0) {

            const int li = index_of(h.proc);
            if (li >= 0 && actors_[li].alive && actors_[li].sell_ticks < 0 && actors_[li].make_ticks == 0) proc = li;
        }
        if (proc < 0) proc = choose_refinery(i);
        if (proc < 0) {
            h.dock_held = false;
            h.timer = t.wait_duration;
            h.state = h.park ? Harvest::PARKING : Harvest::WAIT;
            break;
        }
        h.proc = actors_[proc].id;


        if (!h.dock_held) {
            if (dock_holder(h.proc, int32_t(i)) >= 0) {
                if (h.queue_tick < 0) h.queue_tick = int32_t(tick_);
                h.state = Harvest::QUEUE;
                h.has_wait = false;
                h.timer = 0;
                break;
            }
            h.dock_held = true;
            h.queue_tick = -1;
        }

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

    case Harvest::QUEUE: {
        const int proc = index_of(h.proc);
        if (proc < 0 || !actors_[proc].alive || actors_[proc].sell_ticks >= 0 || actors_[proc].make_ticks > 0) {
            h.proc = -1;
            h.queue_tick = -1;
            h.has_wait = false;
            h.state = h.park ? Harvest::PARKING : Harvest::TO_DOCK;
            break;
        }


        if (dock_holder(h.proc, int32_t(i)) < 0 && dock_queue_rank(i, h.proc) == 0) {
            h.queue_tick = -1;
            h.has_wait = false;
            h.timer = 0;
            h.state = Harvest::TO_DOCK;
            break;
        }
        const CPos want = dock_queue_cell(proc, dock_queue_rank(i, h.proc));
        if (!h.has_wait || h.wait_cell != want) {
            h.wait_cell = want;
            h.has_wait = true;
            if (m.cell != want) set_move(i, want, 1);
        } else if (!m.moving && !m.in_transit && m.cell != want) {

            if (h.timer > 0) --h.timer;
            else {
                set_move(i, want, 1);
                h.timer = t.wait_duration;
            }
        }
        break;
    }

    case Harvest::DOCK_TURN: {
        const int proc = index_of(h.proc);
        if (proc < 0 || !actors_[proc].alive) {
            h.dock_held = false;
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
            h.dock_held = false;
            h.state = Harvest::TO_DOCK;
            break;
        }
        if (h.bales == 0) {


            h.dock_held = false;
            h.timer = 0;
            h.state = h.park ? Harvest::PARKING : Harvest::SEARCH;
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

    case Harvest::EXPLORE: {


        if (h.park) {
            stop(i, false);
            h.state = Harvest::PARKING;
            break;
        }
        if (h.timer > 0) --h.timer;
        if (h.timer <= 0 || (!m.moving && !m.in_transit)) {
            h.state = Harvest::SEARCH;
            h.timer = 0;
        }
        break;
    }

    case Harvest::PARKING: {
        const int base = nearest_base(i);
        if (base < 0) {
            stop(i, false);
            h.state = Harvest::PARKED;
            break;
        }
        const Actor& b = actors_[base];
        const UnitType& bt = types_[b.type];
        const CPos centre{b.origin.x + bt.foot_w / 2, b.origin.y + bt.foot_h / 2};
        const CPos want = side_cell(centre, CPos{-1, -1}, park_rank(i));
        if (!h.has_wait || h.wait_cell != want) {
            h.wait_cell = want;
            h.has_wait = true;
            h.timer = 0;
            if (m.cell != want) set_move(i, want, 1);
        }
        if (m.moving || m.in_transit) break;
        if (cell_dist_sq(m.cell, want) <= 2) {
            h.state = Harvest::PARKED;
            break;
        }
        if (h.timer > 0) --h.timer;
        else {
            set_move(i, want, 1);
            h.timer = t.wait_duration;
        }
        break;
    }

    case Harvest::PARKED:

        if (!h.park) h.state = Harvest::SEARCH;
        break;

    case Harvest::WAIT:
        if (h.park) {
            h.state = Harvest::PARKING;
            break;
        }
        if (--h.timer <= 0) h.state = Harvest::SEARCH;
        break;
    }
}

}
