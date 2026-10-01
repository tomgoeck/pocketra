

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


constexpr int32_t EMBARK_NEAR = 6;

constexpr int32_t BOAT_NEAR = 2;

constexpr int32_t LANDING_SPREAD = 4;

int32_t cheb(CPos a, CPos b) { return std::max(std::abs(a.x - b.x), std::abs(a.y - b.y)); }

}


int32_t World::bot_lst_type(int32_t owner, bool buildable_now) const {
    if (buildable_now) {
        std::vector<int32_t> list;
        buildable(owner, QUEUE_SHIP, list);
        int32_t best = -1;
        for (int32_t t : list) {
            const UnitType& ut = types_[size_t(t)];
            if (ut.building || ut.aircraft || ut.cargo_max_weight <= 0) continue;
            if (best < 0 || t < best) best = t;
        }
        return best;
    }
    for (size_t t = 0; t < types_.size(); ++t) {
        const UnitType& ut = types_[t];
        if (ut.building || ut.aircraft || ut.cargo_max_weight <= 0 || ut.queue_kind != QUEUE_SHIP) continue;
        if (ut.cost <= 0 || item_hidden(owner, int32_t(t))) continue;
        return int32_t(t);
    }
    return -1;
}


void World::bot_lcraft_reach(CPos from, std::vector<uint8_t>& out) const {
    out.assign(size_t(map_.cells()), 0);
    if (map_.cells() <= 0) return;
    const int32_t mc = int32_t(MC_LCRAFT);
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


bool World::bot_amphib_goal(int32_t owner, CPos& goal) const {
    CPos base{-1, -1};
    if (!bot_base_center(owner, base)) return false;
    std::vector<uint8_t> own;
    bot_land_reach(base, own);
    if (own.size() != size_t(map_.cells())) return false;
    auto reached = [&](CPos c) { return map_.in_bounds(c) && own[size_t(map_.index(c))] != 0; };
    int64_t best = INT64_MAX;
    int32_t best_id = -1;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !hostile(owner, a.owner)) continue;
        const UnitType& t = types_[a.type];
        if (!t.building || t.husk || !t.targetable) continue;
        if (!bot_knows(owner, i)) continue;
        if ((t.terrain_mask & (1u << TER_WATER)) != 0) continue;
        bool by_land = false;
        for (int y = -1; y <= t.foot_h && !by_land; ++y)
            for (int x = -1; x <= t.foot_w && !by_land; ++x)
                if (reached(CPos{a.origin.x + x, a.origin.y + y})) by_land = true;
        if (by_land) continue;
        const int64_t d = cell_dist_sq(a.origin, base);
        if (d < best || (d == best && best_id >= 0 && a.id < best_id)) {
            best = d;
            best_id = a.id;
            goal = CPos{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2};
        }
    }
    if (best_id >= 0) return true;
    if (!bot_fogged(owner)) return false;
    bool ok = false;
    for (const CPos& st : players_[size_t(owner)].bot.enemy_starts) {
        if (!map_.in_bounds(st) || explored(owner, st)) continue;
        bool by_land = false;
        for (int y = -4; y <= 4 && !by_land; ++y)
            for (int x = -4; x <= 4 && !by_land; ++x)
                if (reached(CPos{st.x + x, st.y + y})) by_land = true;
        if (by_land) continue;
        const int64_t d = cell_dist_sq(st, base);
        if (d < best) { best = d; goal = st; ok = true; }
    }
    return ok;
}


bool World::bot_amphib_possible(int32_t owner) const {
    const BotState& b = players_[size_t(owner)].bot;
    if (!b.p.amphib_enabled || !bot_land_isolated(owner)) return false;
    bool boats = false;
    for (const BotSquad& s : b.squads)
        if (s.type == BotSquad::AMPHIB && !s.boats.empty()) boats = true;
    if (!boats && (find_producer(owner, QUEUE_SHIP) < 0 || bot_lst_type(owner, true) < 0)) return false;
    CPos goal{-1, -1};
    return bot_amphib_goal(owner, goal);
}


bool World::bot_amphib_embark(int32_t owner, const std::vector<uint8_t>& boat_reach, CPos& land, CPos& water) const {
    CPos base{-1, -1};
    if (!bot_base_center(owner, base) || boat_reach.size() != size_t(map_.cells())) return false;
    std::vector<uint8_t> own;
    bot_land_reach(base, own);
    int64_t best = INT64_MAX;
    bool ok = false;
    for (int32_t idx = 0; idx < map_.cells(); ++idx) {
        if (!boat_reach[size_t(idx)]) continue;
        const CPos c = map_.cell_at(idx);

        CPos n{-1, -1};
        for (int dir = 0; dir < NUM_DIRS && n.x < 0; ++dir) {
            const CPos q{c.x + DIR_DX[dir], c.y + DIR_DY[dir]};
            if (!map_.in_bounds(q) || !own[size_t(map_.index(q))] || !map_.passable(q)) continue;
            n = q;
        }
        if (n.x < 0) continue;
        const int64_t threat = bot_threat_at(owner, c, true) > 0 ? 1 : 0;
        const int64_t key = threat * (int64_t(1) << 40) + cell_dist_sq(c, base);
        if (key < best) { best = key; land = n; water = c; ok = true; }
    }
    return ok;
}


bool World::bot_amphib_landing(int32_t owner, const std::vector<uint8_t>& boat_reach, CPos goal, CPos& out) const {
    if (!map_.in_bounds(goal) || boat_reach.size() != size_t(map_.cells())) return false;
    std::vector<uint8_t> target_land, own;
    bot_land_reach(goal, target_land);
    CPos base{-1, -1};
    if (bot_base_center(owner, base)) bot_land_reach(base, own);
    else own.assign(size_t(map_.cells()), 0);
    int64_t best = INT64_MAX;
    bool ok = false;
    for (int32_t idx = 0; idx < map_.cells(); ++idx) {
        if (!boat_reach[size_t(idx)]) continue;
        const CPos c = map_.cell_at(idx);
        bool shore = false;
        for (int dir = 0; dir < NUM_DIRS && !shore; ++dir) {
            const CPos q{c.x + DIR_DX[dir], c.y + DIR_DY[dir]};
            if (!map_.in_bounds(q) || !map_.passable(q)) continue;
            const size_t qi = size_t(map_.index(q));
            if (target_land[qi] && !own[qi]) shore = true;
        }
        if (!shore) continue;
        const int64_t threat = bot_threat_at(owner, c, true) > 0 ? 1 : 0;
        const int64_t key = threat * (int64_t(1) << 40) + cell_dist_sq(c, goal);
        if (key < best) { best = key; out = c; ok = true; }
    }
    return ok;
}


BotSquad* World::bot_amphib_squad(int32_t owner, bool create) {
    BotState& b = players_[size_t(owner)].bot;
    for (BotSquad& s : b.squads)
        if (s.type == BotSquad::AMPHIB && !s.dead) return &s;
    if (!create) return nullptr;
    BotSquad ns;
    ns.type = BotSquad::AMPHIB;
    ns.state = BotSquad::IDLE;
    b.squads.push_back(ns);
    return &b.squads.back();
}


void World::bot_amphib_squads(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (!b.p.amphib_enabled) return;
    std::vector<int32_t> fresh;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building || t.aircraft || t.husk || t.cargo_max_weight <= 0) continue;
        if (t.locomotor != LOCO_LCRAFT && t.locomotor != LOCO_NAVAL) continue;
        if (std::find(b.active_units.begin(), b.active_units.end(), a.id) != b.active_units.end()) continue;
        fresh.push_back(a.id);
    }
    if (fresh.empty()) return;
    BotSquad* s = bot_amphib_squad(owner, true);
    for (int32_t id : fresh) {
        s->boats.push_back(id);
        b.active_units.push_back(id);
    }
}


void World::bot_update_amphib_squad(int32_t owner, BotSquad& s) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    const bool active = p.amphib_enabled && b.vh_running[VH_LANDING] != 0;
    const int32_t lst = bot_lst_type(owner, true);

    auto cell_of = [&](int32_t id) -> CPos {
        const int i = index_of(id);
        return i < 0 ? CPos{-1, -1} : mobiles_[size_t(i)].cell;
    };
    auto aboard = [&](int32_t id) {
        const int i = index_of(id);
        return i >= 0 && actors_[size_t(i)].transport >= 0;
    };
    auto change = [&](BotSquad::State st) {
        s.state = st;
        s.phase_start = tick_;
    };

    auto release = [&]() {
        std::vector<int32_t> keep;
        for (int32_t id : s.units) {
            if (aboard(id)) { keep.push_back(id); continue; }
            const int i = index_of(id);
            if (i >= 0) actors_[size_t(i)].enter_target = -1;
            b.idle_base_units.push_back(id);
        }
        s.units = keep;
    };

    const UnitType* lst_t = lst >= 0 ? &types_[size_t(lst)] : nullptr;
    if (!lst_t) {
        for (int32_t id : s.boats) {
            const int i = index_of(id);
            if (i >= 0) { lst_t = &types_[actors_[size_t(i)].type]; break; }
        }
    }
    auto eligible = [&](int32_t id) {
        const int i = index_of(id);
        if (i < 0 || !actors_[size_t(i)].alive || actors_[size_t(i)].transport >= 0) return false;
        const UnitType& t = types_[actors_[size_t(i)].type];
        if (t.building || t.aircraft || t.harvester || t.husk || t.transforms_into >= 0) return false;
        if (t.weapon < 0 || t.passenger_weight <= 0) return false;
        if (t.locomotor == LOCO_NAVAL || t.locomotor == LOCO_LCRAFT) return false;
        if (!lst_t) return false;
        if (lst_t->cargo_types != 0 && (lst_t->cargo_types & t.passenger_type) == 0) return false;
        return std::max(1, t.passenger_weight) <= lst_t->cargo_max_weight;
    };

    auto top_up = [&]() {
        const int32_t want = std::max(1, p.amphib_wave_units);
        std::vector<int32_t> rest;
        for (int32_t id : b.idle_base_units) {
            if (int32_t(s.units.size()) < want && eligible(id)) s.units.push_back(id);
            else rest.push_back(id);
        }
        b.idle_base_units = rest;
    };


    auto request_boats = [&]() {
        if (lst < 0 || find_producer(owner, QUEUE_SHIP) < 0) return;


        int32_t have = 0;
        for (const Actor& a : actors_)
            if (a.alive && a.owner == owner && a.type == lst) ++have;
        for (const BuildItem& it : players_[size_t(owner)].queues[QUEUE_SHIP])
            if (it.type == lst) ++have;
        for (int32_t t : b.build_requests)
            if (t == lst) ++have;


        if (have < std::max(1, p.amphib_boats)) b.build_requests.insert(b.build_requests.begin(), lst);
    };


    CPos sea_from{-1, -1};
    for (int32_t id : s.boats) {
        const CPos c = cell_of(id);
        if (c.x >= 0) { sea_from = c; break; }
    }
    if (sea_from.x < 0) {
        for (const Actor& a : actors_)
            if (a.alive && a.owner == owner && types_[a.type].building && (types_[a.type].produces & (1u << QUEUE_SHIP))) {
                sea_from = a.origin;
                break;
            }
    }
    std::vector<uint8_t> reach;
    if (sea_from.x >= 0) bot_lcraft_reach(sea_from, reach);
    if (!reach.empty() && (s.embark.x < 0 || s.state == BotSquad::IDLE)) {
        CPos land{-1, -1}, water{-1, -1};
        if (bot_amphib_embark(owner, reach, land, water)) { s.embark = land; s.embark_water = water; }
    }
    auto boat_at = [&](int32_t id, CPos where, int32_t near) {
        const int i = index_of(id);
        if (i < 0 || where.x < 0) return false;
        const Mobile& m = mobiles_[size_t(i)];
        return cheb(m.cell, where) <= near && !m.moving && !m.in_transit;
    };
    auto send_boat = [&](int32_t id, CPos where) {
        const int i = index_of(id);
        if (i < 0 || where.x < 0 || actors_[size_t(i)].unloading) return;
        const Mobile& m = mobiles_[size_t(i)];
        if (cheb(m.cell, where) <= 0) return;
        if (m.moving && m.goal == where) return;
        order_move(&id, 1, where, 0);
    };
    auto park_boats = [&]() {
        for (int32_t id : s.boats) {
            const int i = index_of(id);
            if (i < 0 || !cargo_[size_t(i)].empty()) continue;
            if (!boat_at(id, s.embark_water, BOAT_NEAR)) send_boat(id, s.embark_water);
        }
    };


    auto beachhead = [&]() -> CPos {
        constexpr int32_t BEACHHEAD_CELLS = 4;
        CPos out{-1, -1};
        if (!map_.in_bounds(s.landing) || !map_.in_bounds(s.land_goal)) return out;
        std::vector<uint8_t> target_land;
        bot_land_reach(s.land_goal, target_land);
        int64_t best = INT64_MAX;
        for (int dy = -2 * BEACHHEAD_CELLS; dy <= 2 * BEACHHEAD_CELLS; ++dy)
            for (int dx = -2 * BEACHHEAD_CELLS; dx <= 2 * BEACHHEAD_CELLS; ++dx) {
                const CPos c{s.landing.x + dx, s.landing.y + dy};
                if (!map_.in_bounds(c) || !map_.passable(c) || !target_land[size_t(map_.index(c))]) continue;
                const int64_t ring = std::abs(cheb(c, s.landing) - BEACHHEAD_CELLS);
                const int64_t key = ring * (int64_t(1) << 32) + cell_dist_sq(c, s.land_goal);
                if (key < best) { best = key; out = c; }
            }
        return out;
    };

    std::vector<BotSquad> new_squads;

    switch (s.state) {
    case BotSquad::IDLE:
    default: {
        if (!s.units.empty()) release();
        park_boats();
        if (!active) break;
        CPos goal{-1, -1};
        if (!bot_amphib_goal(owner, goal)) break;
        s.land_goal = goal;
        request_boats();
        if (s.embark.x < 0) break;

        int32_t ready = 0;
        for (int32_t id : b.idle_base_units)
            if (eligible(id)) ++ready;
        if (ready < std::max(1, p.amphib_min_units)) break;
        top_up();
        s.returning = 0;
        change(BotSquad::GATHER);
        break;
    }
    case BotSquad::GATHER: {
        if (!active) { release(); change(BotSquad::IDLE); park_boats(); break; }
        top_up();
        request_boats();
        if (s.embark.x < 0) break;
        std::vector<int32_t> movers;
        int32_t near = 0, alive = 0;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0 || aboard(id)) continue;
            ++alive;
            const Mobile& m = mobiles_[size_t(i)];
            if (cheb(m.cell, s.embark) <= EMBARK_NEAR) { ++near; continue; }
            if (!m.moving || m.goal != s.embark) movers.push_back(id);
        }
        if (!movers.empty()) order_move(movers.data(), movers.size(), s.embark, 2);
        park_boats();
        if (alive <= 0) { change(BotSquad::IDLE); break; }
        bool boat_ready = false;
        for (int32_t id : s.boats)
            if (boat_at(id, s.embark_water, BOAT_NEAR)) boat_ready = true;
        const int32_t ready_percent = p.gather_ready_percent > 0 ? p.gather_ready_percent : 80;
        const bool enough = near * 100 >= alive * ready_percent;
        const bool timeout = tick_ > s.phase_start + uint32_t(std::max(1, p.gather_max_ticks));
        if (boat_ready && near > 0 && (enough || timeout)) change(BotSquad::LOAD);
        break;
    }
    case BotSquad::LOAD: {
        park_boats();

        std::vector<int32_t> waiting;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0 || aboard(id)) continue;
            if (actors_[size_t(i)].enter_target >= 0) continue;
            if (cheb(mobiles_[size_t(i)].cell, s.embark) > EMBARK_NEAR) continue;
            waiting.push_back(id);
        }

        bool room_left = false;
        size_t next = 0;
        for (int32_t bid : s.boats) {
            const int bi = index_of(bid);
            if (bi < 0 || !boat_at(bid, s.embark_water, BOAT_NEAR)) continue;
            int32_t used = cargo_weight(bid);
            for (int32_t id : s.units) {
                const int i = index_of(id);
                if (i >= 0 && actors_[size_t(i)].enter_target == bid && actors_[size_t(i)].transport < 0)
                    used += std::max(1, types_[actors_[size_t(i)].type].passenger_weight);
            }
            const int32_t cap = types_[actors_[size_t(bi)].type].cargo_max_weight;
            while (next < waiting.size()) {
                const int wi = index_of(waiting[next]);
                const int32_t wgt = std::max(1, types_[actors_[size_t(wi)].type].passenger_weight);
                if (used + wgt > cap) break;
                order_enter_transport(&waiting[next], 1, bid);
                used += wgt;
                ++next;
            }
            if (used < cap) room_left = true;
        }
        int32_t loaded = 0, pending = 0;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            if (aboard(id)) ++loaded;
            else if (actors_[size_t(i)].enter_target >= 0) ++pending;
        }
        const bool timeout = tick_ > s.phase_start + uint32_t(std::max(1, p.amphib_load_ticks));
        const bool done = pending == 0 && (next >= waiting.size() || !room_left);
        if (!(done || timeout)) break;
        if (loaded <= 0) {

            change(BotSquad::GATHER);
            break;
        }

        std::vector<int32_t> left;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0 || aboard(id) || actors_[size_t(i)].enter_target < 0) continue;
            actors_[size_t(i)].enter_target = -1;
            left.push_back(id);
        }
        if (!left.empty()) order_move(left.data(), left.size(), s.embark, 2);

        CPos goal = s.land_goal;
        if (bot_amphib_goal(owner, goal)) s.land_goal = goal;
        CPos landing{-1, -1};
        if (reach.empty() || !map_.in_bounds(s.land_goal) || !bot_amphib_landing(owner, reach, s.land_goal, landing)) {

            landing = s.embark_water;
            s.returning = 1;
        } else {
            s.returning = 0;
        }
        s.landing = landing;
        for (int32_t bid : s.boats) {
            const int bi = index_of(bid);
            if (bi >= 0 && !cargo_[size_t(bi)].empty()) send_boat(bid, s.landing);
        }
        change(BotSquad::SAIL);
        break;
    }
    case BotSquad::SAIL: {

        if (!s.returning) {
            const CPos head = beachhead();
            std::vector<int32_t> clear;
            for (int32_t id : s.units) {
                const int i = index_of(id);
                if (i < 0 || aboard(id) || head.x < 0) continue;
                const Mobile& m = mobiles_[size_t(i)];
                if (cheb(m.cell, s.landing) > LANDING_SPREAD + 1) continue;
                if (m.moving && m.goal == head) continue;
                if (cheb(m.cell, head) <= 1) continue;
                clear.push_back(id);
            }
            if (!clear.empty()) order_move(clear.data(), clear.size(), head, 2);
        }
        bool any_loaded = false;
        for (int32_t bid : s.boats) {
            const int bi = index_of(bid);
            if (bi < 0 || cargo_[size_t(bi)].empty()) continue;
            any_loaded = true;
            if (actors_[size_t(bi)].unloading) continue;
            const Mobile& m = mobiles_[size_t(bi)];
            const bool stopped = !m.moving && !m.in_transit;

            if (stopped && cheb(m.cell, s.landing) <= LANDING_SPREAD && can_unload(bid)) {
                order_unload(&bid, 1);
                continue;
            }
            if (stopped && cheb(m.cell, s.landing) <= LANDING_SPREAD) {


                int64_t best = INT64_MAX;
                CPos alt{-1, -1};
                for (int dy = -LANDING_SPREAD; dy <= LANDING_SPREAD; ++dy)
                    for (int dx = -LANDING_SPREAD; dx <= LANDING_SPREAD; ++dx) {
                        const CPos c{s.landing.x + dx, s.landing.y + dy};
                        if (!map_.in_bounds(c) || c == m.cell) continue;
                        if (reach.empty() || !reach[size_t(map_.index(c))]) continue;
                        const int32_t occ = occupant(c);
                        if (occ >= 0 && occ != bi) continue;
                        bool shore = false;
                        for (int dir = 0; dir < NUM_DIRS && !shore; ++dir) {
                            const CPos q{c.x + DIR_DX[dir], c.y + DIR_DY[dir]};
                            if (map_.in_bounds(q) && map_.passable(q) && occupant(q) < 0) shore = true;
                        }
                        if (!shore) continue;
                        const int64_t d = cell_dist_sq(c, m.cell);
                        if (d < best) { best = d; alt = c; }
                    }
                if (alt.x >= 0) order_move(&bid, 1, alt, 0);
                continue;
            }
            send_boat(bid, s.landing);
        }
        park_boats();
        if (!any_loaded) { change(s.returning ? BotSquad::GATHER : BotSquad::LAND); break; }
        if (tick_ > s.phase_start + uint32_t(std::max(1, p.amphib_sail_ticks)) && !s.returning) {

            s.landing = s.embark_water;
            s.returning = 1;
            s.phase_start = tick_;
            for (int32_t bid : s.boats) {
                const int bi = index_of(bid);
                if (bi >= 0 && !cargo_[size_t(bi)].empty()) send_boat(bid, s.landing);
            }
            break;
        }
        break;
    }
    case BotSquad::LAND: {

        std::vector<uint8_t> own;
        CPos base{-1, -1};
        if (bot_base_center(owner, base)) bot_land_reach(base, own);
        std::vector<int32_t> landed, stay;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            const CPos c = mobiles_[size_t(i)].cell;
            const bool home = !own.empty() && map_.in_bounds(c) && own[size_t(map_.index(c))] != 0;
            if (!aboard(id) && !home) landed.push_back(id);
            else stay.push_back(id);
        }
        s.units = stay;
        if (!landed.empty()) {
            BotSquad ns;
            ns.type = BotSquad::ASSAULT;
            ns.units = landed;
            ns.state = BotSquad::GATHER;
            const CPos head = beachhead();
            ns.gather = head.x >= 0 ? head : cell_of(landed.front());
            ns.gather_start = tick_;
            ns.gather_picks = 1;
            ns.start_size = int32_t(landed.size());
            ns.from_landing = 1;
            if (active) {
                ns.vorhaben = VH_LANDING;
                ns.scheme = bot_vorhaben_scheme(VH_LANDING);
            }
            new_squads.push_back(ns);
            ++s.waves;
            ++b.stat_landings;
            b.stat_landed_units += int32_t(landed.size());
            if (b.stat_t_landing == 0) b.stat_t_landing = int32_t(std::max<uint32_t>(1, tick_));
            ++b.stat_squads_sent;
            if (b.stat_first_attack == 0) b.stat_first_attack = tick_;
        }

        park_boats();
        if (!s.units.empty() || active) {
            change(s.units.empty() ? BotSquad::IDLE : BotSquad::GATHER);
        } else {
            change(BotSquad::IDLE);
        }
        break;
    }
    }

    for (BotSquad& ns : new_squads) b.squads.push_back(ns);
}

}
