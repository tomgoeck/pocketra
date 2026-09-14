

#include <algorithm>
#include <climits>
#include <cstdlib>

#include "ra/sim.h"

namespace ra {

namespace {

constexpr int32_t MAX_RESPOND_COOLDOWN = 30;
constexpr uint32_t STALL_TICKS = 63;
constexpr uint32_t PROTECT_MAX_TICKS = 1500;

int64_t bot_cell_d2(CPos a, CPos b) {
    const int64_t dx = a.x - b.x, dy = a.y - b.y;
    return dx * dx + dy * dy;
}


inline int32_t bot_table(const std::vector<int32_t>& v, size_t t, int32_t fallback) {
    return t < v.size() ? v[t] : fallback;
}

}

void World::enable_bot(int32_t owner, const BotParams& p) {
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    BotState& b = players_[owner].bot;
    b = BotState();
    b.enabled = true;
    b.p = p;


    b.personality = p.personality;
    if (b.personality < 0 || b.personality >= BOT_P_RANDOM) {
        b.personality = int32_t(rand() % uint32_t(BOT_P_RANDOM));
        bot_apply_personality(b.p, b.personality);
    }


    b.p.first_attack_tick = std::max(b.p.first_attack_tick, b.p.min_first_attack_tick);
    b.min_excess_power = p.min_excess_power;
    b.rush_ticks = p.rush_interval - p.rush_interval / 20 + int32_t(rand() % uint32_t(std::max(1, p.rush_interval / 10)));
    b.assign_roles_ticks = int32_t(rand() % uint32_t(std::max(1, p.assign_roles_interval)));
    b.attack_force_ticks = int32_t(rand() % uint32_t(std::max(1, p.attack_force_interval)));
    b.min_attack_force_delay_ticks = p.min_attack_force_delay > 0 ? int32_t(rand() % uint32_t(p.min_attack_force_delay)) : 0;
    b.scan_idle_harvesters_ticks = int32_t(rand() % uint32_t(std::max(1, p.scan_idle_harvesters_interval)));


    b.best_resource_ticks = int32_t(rand() % uint32_t(std::max(1, p.check_best_resource_interval)));
    b.sell_refinery_ticks = int32_t(rand() % uint32_t(std::max(1, p.sell_refinery_interval)));
    b.rmap_ticks = int32_t(rand() % uint32_t(std::max(1, p.update_resource_map_interval)));
    b.mcv_scan_ticks = p.mcv_scan_interval + int32_t(rand() % uint32_t(std::max(1, p.mcv_scan_interval)));
    b.mcv_ticks = p.build_mcv_interval + int32_t(rand() % uint32_t(std::max(1, p.build_mcv_interval)));


    b.strategy_ticks = 1 + int32_t(rand() % uint32_t(std::max(1, b.p.strategy_interval)));
    b.threat_ticks = 1 + int32_t(rand() % uint32_t(std::max(1, b.p.threat_map_interval)));
    b.raid_ticks = b.p.raid_interval > 0 ? 1 + int32_t(rand() % uint32_t(std::max(1, b.p.raid_interval))) : 1;

    for (size_t i = 0; i < actors_.size(); ++i) {
        if (actors_[i].owner == owner) combats_[i].stance = STANCE_ATTACK_ANYTHING;
    }
}

void World::step_bots() {
    for (int32_t owner = 0; owner < MAX_PLAYERS; ++owner) {
        if (players_[owner].bot.enabled) bot_tick(owner);
    }
}


void World::bot_resource_map_update(int32_t owner, int32_t index) {
    BotState& b = players_[owner].bot;
    if (index < 0 || size_t(index) >= b.resource_map.size()) return;
    BotResourceIndice& in = b.resource_map[size_t(index)];
    const int32_t r = b.rmap_scan;
    const int64_t r2 = int64_t(r) * r;

    int64_t sum_x = 0, sum_y = 0;
    int32_t count = 0;
    for (int y = in.center.y - r; y <= in.center.y + r; ++y) {
        for (int x = in.center.x - r; x <= in.center.x + r; ++x) {
            const CPos c{x, y};
            if (!map_.in_bounds(c) || cell_dist_sq(c, in.center) > r2) continue;
            if (res_type_[size_t(map_.index(c))] == RES_NONE) continue;
            sum_x += c.x; sum_y += c.y; ++count;
        }
    }
    in.res_cells = count;
    in.res_center = in.center;
    if (count > 0) {

        const CPos avg{int32_t(sum_x / count), int32_t(sum_y / count)};
        int64_t best = INT64_MAX;
        for (int y = in.center.y - r; y <= in.center.y + r; ++y) {
            for (int x = in.center.x - r; x <= in.center.x + r; ++x) {
                const CPos c{x, y};
                if (!map_.in_bounds(c) || cell_dist_sq(c, in.center) > r2) continue;
                if (res_type_[size_t(map_.index(c))] == RES_NONE) continue;
                const int64_t d = cell_dist_sq(c, avg);

                if (d < best || (d == best && map_.index(c) < map_.index(in.res_center))) { best = d; in.res_center = c; }
            }
        }
    }


    in.refineries = 0; in.harvesters = 0;
    in.enemy_units = 0; in.enemy_bases = 0;
    in.friendly_units = 0; in.friendly_bases = 0;
    const int64_t wr = int64_t(r) * CELL;
    for (const Actor& a : actors_) {
        if (!a.alive || length(a.pos - cell_center(in.center)) > wr) continue;
        const UnitType& t = types_[a.type];
        const bool base_building = t.building && (t.defense || t.produces != 0 || t.power > 0 || t.refinery || t.base_provider);
        if (hostile(owner, a.owner)) {
            if (base_building) ++in.enemy_bases; else ++in.enemy_units;
        } else if (allied(owner, a.owner)) {
            if (base_building) ++in.friendly_bases; else ++in.friendly_units;
            if (a.owner == owner) {
                if (t.refinery) ++in.refineries;
                if (t.harvester) ++in.harvesters;
            }
        }
    }
}

void World::bot_resource_map(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    if (!b.rmap_built) {
        b.rmap_built = true;
        b.rmap_side = std::max(1, p.resource_map_stride_radius * 2);

        b.rmap_scan = std::max(1, p.resource_map_stride_radius * 12 / 10);
        b.rmap_cols = (map_.width() + b.rmap_side - 1) / b.rmap_side;
        b.rmap_rows = (map_.height() + b.rmap_side - 1) / b.rmap_side;
        if (b.rmap_cols <= 0 || b.rmap_rows <= 0) return;

        const int32_t xoff = -((b.rmap_cols * b.rmap_side - map_.width()) / 2);
        const int32_t yoff = -((b.rmap_rows * b.rmap_side - map_.height()) / 2);
        b.resource_map.resize(size_t(b.rmap_cols) * size_t(b.rmap_rows));
        for (int32_t i = 0; i < int32_t(b.resource_map.size()); ++i) {
            BotResourceIndice& in = b.resource_map[size_t(i)];
            in.ix = i % b.rmap_cols;
            in.iy = i / b.rmap_cols;
            in.center = CPos{xoff + in.ix * b.rmap_side + b.rmap_side / 2, yoff + in.iy * b.rmap_side + b.rmap_side / 2};
            bot_resource_map_update(owner, i);
        }
        b.rmap_ticks = p.update_resource_map_interval;
        return;
    }
    if (b.resource_map.empty()) return;
    if (--b.rmap_ticks > 0) return;
    b.rmap_ticks = std::max(1, p.update_resource_map_interval);
    const int32_t per_step = std::max(1, int32_t(b.resource_map.size()) / std::max(1, p.resource_map_sweep_intervals));
    for (int32_t k = 0; k < per_step; ++k) {
        bot_resource_map_update(owner, b.rmap_index);
        b.rmap_index = (b.rmap_index + 1) % int32_t(b.resource_map.size());
    }
}


int32_t World::bot_closest_indice(int32_t owner, CPos c) const {
    const BotState& b = players_[owner].bot;
    int32_t best = -1;
    int64_t best_d = INT64_MAX;
    for (int32_t i = 0; i < int32_t(b.resource_map.size()); ++i) {
        const int64_t d = cell_dist_sq(b.resource_map[size_t(i)].center, c);
        if (d < best_d) { best_d = d; best = i; }
    }
    return best;
}

namespace {


int64_t bot_indice_threat(const BotState& b, int32_t index, int64_t side2) {
    const BotResourceIndice& base = b.resource_map[size_t(index)];
    const int64_t base_threat = std::max(0, base.enemy_bases - base.friendly_bases);
    const int64_t unit_threat = std::max(0, base.enemy_units - base.friendly_units);
    int64_t nearby_units = 0, nearby_bases = 0, n = 0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) continue;
            const int32_t x = base.ix + dx, y = base.iy + dy;
            if (x < 0 || y < 0 || x >= b.rmap_cols || y >= b.rmap_rows) continue;
            const BotResourceIndice& o = b.resource_map[size_t(y * b.rmap_cols + x)];
            nearby_bases += o.enemy_bases - o.friendly_bases;
            nearby_units += o.enemy_units - o.friendly_units;
            ++n;
        }
    }
    nearby_units = std::max<int64_t>(nearby_units, 0);
    nearby_bases = std::max<int64_t>(nearby_bases, 0);
    if (n == 0) return ((unit_threat * side2) >> 6) + ((base_threat * side2) << 3);
    return (((unit_threat * side2) + nearby_units * side2 / n) >> 6) +
           (((base_threat * side2) + nearby_bases * side2 / n) << 3);
}

}


bool World::bot_expansion_center(int32_t owner, size_t mcv, CPos& expand, CPos& check_spot, int64_t& attraction) const {
    const BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    if (b.resource_map.empty()) return false;
    const int64_t side2 = int64_t(b.rmap_side) * b.rmap_side;
    const int64_t factor = std::max<int64_t>(1, int64_t(b.rmap_cols) * b.rmap_cols + int64_t(b.rmap_rows) * b.rmap_rows);
    const CPos from = mobiles_[mcv].cell;


    std::vector<CPos> yards, refineries;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
        if (types_[a.type].base_provider) yards.push_back(a.origin);
        if (types_[a.type].refinery) refineries.push_back(a.origin);
    }


    int64_t threshold = 0;
    for (const BotResourceIndice& in : b.resource_map)
        threshold += (side2 >> 1) - std::abs(int64_t(in.res_cells) - (side2 >> 1));
    threshold = (threshold / int64_t(b.resource_map.size())) >> 1;

    const bool check_resource = b.expansion_mode == BotState::CHECK_RESOURCE;
    const int64_t conyard_r2 = check_resource ? int64_t(p.cr_conyard_dislike_range) * p.cr_conyard_dislike_range : side2;
    const int64_t refinery_r2 = int64_t(p.cr_refinery_dislike_range) * p.cr_refinery_dislike_range;

    int64_t best = INT64_MIN;
    bool found = false;
    for (int32_t i = 0; i < int32_t(b.resource_map.size()); ++i) {
        const BotResourceIndice& in = b.resource_map[size_t(i)];
        if (in.center == b.last_failed_spot) continue;

        if (check_resource && in.res_cells == 0) continue;
        if (check_resource && b.failed_attempts > b.max_failed_attempts / 2 && in.res_cells <= threshold) continue;

        const CPos ref_cell = check_resource ? in.res_center : in.center;
        int64_t a = check_resource ? (side2 >> 2) : (side2 >> 1);
        a -= cell_dist_sq(ref_cell, from) / factor;
        if (check_resource)
            a += ((side2 >> 1) - std::abs(int64_t(in.res_cells) - (side2 >> 1))) >> 2;
        a -= bot_indice_threat(b, i, side2);
        if (check_resource)
            for (const CPos& c : refineries) if (cell_dist_sq(ref_cell, c) <= refinery_r2) a -= side2;
        for (const CPos& c : yards) if (cell_dist_sq(ref_cell, c) <= conyard_r2) a -= side2;
        for (const BotActiveMcv& other : b.active_mcvs)
            if (other.id != actors_[mcv].id && other.check_spot == in.center) a -= side2 << 1;


        if (!found || a > best) {
            best = a;
            expand = ref_cell;
            check_spot = in.center;
            found = true;
        }
    }
    attraction = best;
    return found;
}


bool World::bot_find_deploy_cell(int32_t owner, size_t mcv, CPos target, CPos& out) {
    const BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    const bool check_resource = b.expansion_mode == BotState::CHECK_RESOURCE;
    const int32_t min_r = check_resource ? p.cr_min_deploy_radius : p.cb_min_deploy_radius;
    const int32_t max_r = check_resource ? p.cr_max_deploy_radius : p.cb_max_deploy_radius;

    const int64_t theta = check_resource ? p.cr_try_maintain_range : (p.cb_max_deploy_radius + p.cb_min_deploy_radius) / 2;
    const CPos from = mobiles_[mcv].cell;
    const UnitType& mt = types_[actors_[mcv].type];
    if (mt.transforms_into < 0) return false;
    const UnitType& into = types_[mt.transforms_into];


    auto deployable = [&](CPos cell) {
        const CPos origin{cell.x + mt.transforms_dx, cell.y + mt.transforms_dy};
        for (int y = 0; y < into.foot_h; ++y) {
            for (int x = 0; x < into.foot_w; ++x) {
                if (!into.footprint[size_t(y * into.foot_w + x)]) continue;
                const CPos c{origin.x + x, origin.y + y};
                if (!map_.in_bounds(c) || !map_.passable(c)) return false;
                const int32_t occ = occupant(c);
                if (occ != -1 && occ != int32_t(mcv)) return false;
                if (res_density_[size_t(map_.index(c))] > 0) return false;
            }
        }
        return true;
    };

    std::vector<CPos> cells;
    for (int y = target.y - max_r; y <= target.y + max_r; ++y) {
        for (int x = target.x - max_r; x <= target.x + max_r; ++x) {
            const CPos c{x, y};
            if (!map_.in_bounds(c)) continue;
            const int64_t d2 = cell_dist_sq(c, target);
            if (d2 < int64_t(min_r) * min_r || d2 > int64_t(max_r) * max_r) continue;
            cells.push_back(c);
        }
    }
    if (cells.empty()) return false;

    if (!(from == target)) {
        const int64_t deta = int64_t(isqrt(cell_dist_sq(target, from))) - theta;
        std::sort(cells.begin(), cells.end(), [&](CPos a, CPos c) {
            const int64_t da = deta * cell_dist_sq(a, target) + theta * cell_dist_sq(a, from);
            const int64_t db = deta * cell_dist_sq(c, target) + theta * cell_dist_sq(c, from);
            return da != db ? da < db : map_.index(a) < map_.index(c);
        });
    } else {
        for (size_t i = cells.size(); i > 1; --i) std::swap(cells[i - 1], cells[rand() % i]);
    }

    CPos best{-1, -1};
    for (const CPos& c : cells) if (deployable(c)) { best = c; break; }


    const bool too_far = best.x < 0 || (!(from == target) && cell_dist_sq(best, target) >= (theta + 2) * (theta + 2));
    if (too_far) {
        std::sort(cells.begin(), cells.end(), [&](CPos a, CPos c) {
            const int64_t da = cell_dist_sq(a, target), db = cell_dist_sq(c, target);
            return da != db ? da < db : map_.index(a) < map_.index(c);
        });
        for (const CPos& c : cells) {
            if (!deployable(c)) continue;
            if (best.x < 0 || cell_dist_sq(c, target) < cell_dist_sq(best, target)) best = c;
            break;
        }
    }
    if (best.x < 0) return false;
    out = best;
    return true;
}

namespace {


constexpr int32_t CR_MAX_FAILED = 3;
constexpr int32_t CB_MAX_FAILED = 2;

void bot_bad_deploy_spot(BotState& b, CPos failed) {
    b.last_failed_spot = failed;
    if (++b.failed_attempts < b.max_failed_attempts) return;
    b.failed_attempts = 0;
    if (b.expansion_mode == BotState::CHECK_RESOURCE) {
        b.expansion_mode = BotState::CHECK_BASE;
    } else {
        b.expansion_mode = BotState::CHECK_RESOURCE;
        b.max_failed_attempts = 0;
    }
}

void bot_good_deploy_spot(BotState& b) {
    b.last_failed_spot = CPos{-1, -1};
    if (--b.failed_attempts > -b.max_failed_attempts) return;
    if (b.expansion_mode == BotState::CHECK_RESOURCE) {
        b.max_failed_attempts = CR_MAX_FAILED;
        b.failed_attempts = -b.max_failed_attempts;
    } else {
        b.max_failed_attempts = CR_MAX_FAILED;
        b.failed_attempts = b.max_failed_attempts - 1;
        b.expansion_mode = BotState::CHECK_RESOURCE;
    }
    (void)CB_MAX_FAILED;
}

}


void World::bot_mcv(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    const bool scan = --b.mcv_scan_ticks <= 0;
    if (scan) b.mcv_scan_ticks = std::max(1, p.mcv_scan_interval);
    const bool rebuild = --b.mcv_ticks <= 0;
    if (rebuild) b.mcv_ticks = std::max(1, p.build_mcv_interval);

    int32_t yards = 0, mcvs = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner) continue;
        if (types_[a.type].building && types_[a.type].base_provider) {
            ++yards;
            if (b.initial_base_center.x < 0) b.initial_base_center = a.origin;
        } else if (types_[a.type].transforms_into >= 0) {
            ++mcvs;
            if (b.initial_base_center.x < 0) b.initial_base_center = mobiles_[i].cell;
        }
    }

    b.active_mcvs.erase(std::remove_if(b.active_mcvs.begin(), b.active_mcvs.end(), [&](const BotActiveMcv& m) {
        const int i = index_of(m.id);
        return i < 0 || !actors_[i].alive;
    }), b.active_mcvs.end());

    b.requested_refineries.erase(std::remove_if(b.requested_refineries.begin(), b.requested_refineries.end(),
        [&](const BotRefineryRequest& r) {
            const int i = index_of(r.mcv_id);
            return r.mcv_id >= 0 && (i < 0 || !actors_[i].alive) && !(r.conyard.x >= 0 && bot_has_yard_at(owner, r.conyard));
        }), b.requested_refineries.end());


    if (b.first_tick) {
        b.first_tick = false;
        for (size_t i = 0; i < actors_.size(); ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || a.owner != owner || types_[a.type].transforms_into < 0) continue;
            if (!can_deploy(a.id)) continue;
            const CPos at = mobiles_[i].cell;
            order_deploy(&a.id, 1);
            b.initial_base_center = at;
            b.defense_center = at;
            return;
        }
    }

    if (scan) bot_deploy_mcvs(owner, yards, mcvs);


    if (!rebuild) return;
    int32_t mcv_type = -1;
    for (size_t t = 0; t < types_.size(); ++t) {
        const UnitType& ut = types_[t];
        if (ut.transforms_into >= 0 && ut.cost > 0 && types_[ut.transforms_into].base_provider) mcv_type = int32_t(t);
    }
    if (mcv_type < 0 || !prerequisites_met(owner, mcv_type)) return;
    const int32_t kind = types_[mcv_type].queue_kind;
    if (kind < 0 || find_producer(owner, kind) < 0) return;


    const int32_t free_fields = yards > 0 ? bot_free_resource_fields(owner) : 1;
    const int32_t should_have = bot_max_conyards(owner, yards);

    if ((yards <= 0 && mcvs > 1) || (yards > 0 && mcvs > 0)) return;
    if (yards + mcvs >= should_have) return;
    if (yards > 0 && free_fields <= 0) return;

    constexpr int32_t EXPAND_CASH_RESERVE = 1000;
    if (yards > 0 && credits(owner) < types_[size_t(mcv_type)].cost + EXPAND_CASH_RESERVE) return;
    for (const BuildItem& it : players_[owner].queues[kind]) if (it.type == mcv_type) return;
    if (std::find(b.build_requests.begin(), b.build_requests.end(), mcv_type) == b.build_requests.end())
        b.build_requests.push_back(mcv_type);
}


void World::bot_deploy_mcvs(int32_t owner, int32_t yards, int32_t mcvs) {
    BotState& b = players_[owner].bot;
    (void)mcvs;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || types_[a.type].transforms_into < 0) continue;
        if (mobiles_[i].moving || mobiles_[i].in_transit) continue;

        auto deploy_here = [&]() {
            const CPos at = mobiles_[i].cell;
            const int32_t id = a.id;
            order_deploy(&id, 1);
            b.active_mcvs.erase(std::remove_if(b.active_mcvs.begin(), b.active_mcvs.end(),
                [&](const BotActiveMcv& m) { return m.id == id; }), b.active_mcvs.end());

            if (yards == 0 || (rand() % 2) > 0) {
                b.initial_base_center = at;
                b.defense_center = at;
            }
        };


        if (yards == 0) {
            if (can_deploy(a.id)) { deploy_here(); return; }
        }

        BotActiveMcv* active = nullptr;
        for (BotActiveMcv& m : b.active_mcvs) if (m.id == a.id) { active = &m; break; }
        if (active != nullptr) {

            if (can_deploy(a.id) && cell_dist_sq(mobiles_[i].cell, active->dest) <= 4) { deploy_here(); return; }
            const CPos failed = active->check_spot;
            b.active_mcvs.erase(b.active_mcvs.begin() + (active - b.active_mcvs.data()));
            bot_bad_deploy_spot(b, failed);
        }

        CPos expand{-1, -1}, check_spot{-1, -1};
        int64_t attraction = INT64_MIN;
        if (!bot_expansion_center(owner, i, expand, check_spot, attraction)) {
            bot_bad_deploy_spot(b, CPos{-1, -1});
            continue;
        }
        CPos dest{-1, -1};
        const bool ok = bot_find_deploy_cell(owner, i, expand, dest);
        if (ok && attraction > 0) bot_good_deploy_spot(b);
        else bot_bad_deploy_spot(b, ok ? CPos{-1, -1} : check_spot);
        if (!ok) continue;

        if (dest == mobiles_[i].cell) {
            if (can_deploy(a.id)) { deploy_here(); return; }
            continue;
        }
        set_move(i, dest, 0);
        BotActiveMcv m;
        m.id = a.id;
        m.dest = dest;
        m.check_spot = check_spot;
        b.active_mcvs.push_back(m);


        if (b.expansion_mode == BotState::CHECK_RESOURCE) {
            const int32_t idx = bot_closest_indice(owner, expand);
            if (idx < 0 || b.resource_map[size_t(idx)].refineries < b.p.max_refinery_per_indice) {
                BotRefineryRequest r;
                r.mcv_id = a.id;
                r.conyard = dest;
                r.resource = expand;
                bool known = false;
                for (BotRefineryRequest& e : b.requested_refineries) if (e.mcv_id == r.mcv_id) { e = r; known = true; }
                if (!known) b.requested_refineries.push_back(r);
            }
        }
        return;
    }
}


const BotRefineryRequest* World::bot_refinery_request(int32_t owner) const {
    const BotState& b = players_[owner].bot;
    for (const BotRefineryRequest& r : b.requested_refineries)
        if (bot_has_yard_at(owner, r.conyard)) return &r;
    return nullptr;
}


bool World::bot_has_yard_at(int32_t owner, CPos cell) const {
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].base_provider) continue;
        if (cell_dist_sq(a.origin, cell) <= 4) return true;
    }
    return false;
}


void World::bot_sell_refineries(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    if (--b.sell_refinery_ticks > 0) return;
    b.sell_refinery_ticks = std::max(1, p.sell_refinery_interval);

    std::vector<int> procs;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (a.alive && a.owner == owner && types_[a.type].refinery && a.make_ticks == 0 && a.sell_ticks < 0)
            procs.push_back(int(i));
    }
    if (int32_t(procs.size()) <= p.initial_min_refineries + p.additional_min_refineries) return;

    const int64_t close2 = int64_t(p.sell_refinery_too_close) * p.sell_refinery_too_close;
    const int32_t no_res = p.sell_refinery_no_resource;
    const int64_t no_res2 = int64_t(no_res) * no_res;
    for (size_t k = 0; k < procs.size(); ++k) {
        const CPos origin = actors_[size_t(procs[k])].origin;
        for (size_t j = k + 1; j < procs.size(); ++j) {
            if (cell_dist_sq(origin, actors_[size_t(procs[j])].origin) <= close2) {
                sell(actors_[size_t(procs[k])].id);
                return;
            }
        }
        bool ore = false;
        for (int y = origin.y - no_res; y <= origin.y + no_res && !ore; ++y) {
            for (int x = origin.x - no_res; x <= origin.x + no_res; ++x) {
                const CPos c{x, y};
                if (!map_.in_bounds(c) || cell_dist_sq(c, origin) > no_res2) continue;
                if (res_type_[size_t(map_.index(c))] != RES_NONE) { ore = true; break; }
            }
        }
        if (!ore) {
            sell(actors_[size_t(procs[k])].id);
            return;
        }
    }
}


void World::bot_best_resource_conyard(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    if (--b.best_resource_ticks > 0) return;
    b.best_resource_ticks = std::max(1, p.check_best_resource_interval);


    b.requested_refineries.erase(std::remove_if(b.requested_refineries.begin(), b.requested_refineries.end(),
        [&](const BotRefineryRequest& r) {
            const int32_t idx = bot_closest_indice(owner, r.resource);
            return idx >= 0 && b.resource_map[size_t(idx)].refineries >= p.max_refinery_per_indice;
        }), b.requested_refineries.end());

    const int64_t r2 = int64_t(p.max_base_radius) * p.max_base_radius;
    const int64_t wr = int64_t(p.max_base_radius) * CELL;
    int64_t best = INT64_MIN;
    CPos best_yard{-1, -1};
    for (const Actor& yard : actors_) {
        if (!yard.alive || yard.owner != owner || !types_[yard.type].building || !types_[yard.type].base_provider) continue;
        bool has_ore = false;
        for (int y = yard.origin.y - p.max_base_radius; y <= yard.origin.y + p.max_base_radius && !has_ore; ++y) {
            for (int x = yard.origin.x - p.max_base_radius; x <= yard.origin.x + p.max_base_radius; ++x) {
                const CPos c{x, y};
                if (!map_.in_bounds(c)) continue;
                const int64_t d2 = cell_dist_sq(c, yard.origin);
                if (d2 < int64_t(p.min_base_radius) * p.min_base_radius || d2 > r2) continue;
                if (res_type_[size_t(map_.index(c))] != RES_NONE) { has_ore = true; break; }
            }
        }
        if (!has_ore) continue;
        int64_t suitable = 0;
        for (const Actor& o : actors_) {
            if (!o.alive || length(o.pos - yard.pos) > wr) continue;
            if (o.owner == owner && types_[o.type].refinery) --suitable;
            else if (hostile(owner, o.owner)) --suitable;
        }
        if (suitable > best) { best = suitable; best_yard = yard.origin; }
    }
    b.resource_conyard_center = best_yard;
}


void World::bot_repair(int32_t owner) {
    BotState& b = players_[owner].bot;
    if (b.repair_all_tick != 0 && tick_ - b.repair_all_tick < 107) return;
    b.repair_all_tick = tick_;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
        if (a.repairing || a.sell_ticks >= 0 || a.make_ticks > 0 || a.hp >= types_[a.type].hp) continue;
        toggle_repair(a.id);
    }
}


void World::bot_rally_points(int32_t owner) {
    BotState& b = players_[owner].bot;
    if (--b.rally_ticks > 0) return;
    b.rally_ticks = 100;
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || types_[a.type].produces == 0) continue;
        const UnitType& t = types_[a.type];
        const CPos center{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2};
        for (int tries = 0; tries < 12; ++tries) {
            const CPos c{center.x + int32_t(rand() % 17) - 8, center.y + int32_t(rand() % 17) - 8};
            if (!map_.in_bounds(c) || !map_.passable(c) || !cell_empty(c)) continue;
            if (c.x >= a.origin.x - 1 && c.x <= a.origin.x + t.foot_w && c.y >= a.origin.y - 1 && c.y <= a.origin.y + t.foot_h) continue;
            a.rally = c;
            a.rally_set = true;
            break;
        }
    }
}

void World::bot_tick(int32_t owner) {
    bot_reaction_tick(owner);
    bot_resource_map(owner);
    bot_mcv(owner);
    bot_best_resource_conyard(owner);
    bot_sell_refineries(owner);
    bot_rally_points(owner);


    bot_repair(owner);
    bot_repair_units(owner);
    bot_saboteurs(owner);
    bot_base_builder(owner);
    bot_unit_builder(owner);
    bot_harvesters(owner);
    bot_low_effect_harvesters(owner);


    bot_attack_decay(owner);
    bot_sell_on_loss(owner);


    bot_threat_map(owner);
    bot_counter_scan(owner);
    bot_vorhaben_wahl(owner);
    bot_support_powers(owner);
    bot_squads(owner);
    bot_raid_squads(owner);
}


static int find_base_center(const std::vector<Actor>& actors, const std::vector<UnitType>& types, int32_t owner,
                            uint32_t pick, CPos& out) {
    std::vector<int> yards;
    for (size_t i = 0; i < actors.size(); ++i) {
        const Actor& a = actors[i];
        if (a.alive && a.owner == owner && types[a.type].building && types[a.type].base_provider) yards.push_back(int(i));
    }
    if (yards.empty()) return -1;
    const int idx = yards[pick % yards.size()];
    out = actors[idx].origin;
    return idx;
}


bool World::bot_base_center(int32_t owner, CPos& out) const {
    if (find_base_center(actors_, types_, owner, rand_peek(), out) >= 0) return true;
    const CPos& init = players_[owner].bot.initial_base_center;
    if (init.x < 0) return false;
    out = init;
    return true;
}


void World::bot_on_attack(size_t victim, int32_t attacker_id) {
    const Actor& v = actors_[victim];
    if (!bot_enabled(v.owner)) return;
    BotState& b = players_[v.owner].bot;
    const int ai = index_of(attacker_id);
    if (ai < 0 || !actors_[ai].alive || !hostile(actors_[ai].owner, v.owner)) return;
    const UnitType& vt = types_[v.type];
    if (vt.building) {
        b.defense_center = v.origin;
        bot_repair(v.owner);


        bot_log_attack(v.owner, victim, size_t(ai));
        CPos hot{-1, -1};
        if (bot_attack_center(v.owner, hot)) b.defense_center = hot;
    }


    if (vt.transforms_into >= 0 && b.mcv_respond_cooldown <= 0 && can_deploy(v.id)) {
        b.mcv_respond_cooldown = 20;
        const int32_t vid = v.id;
        const CPos at = mobiles_[victim].cell;
        bool has_yard = false;
        for (const Actor& a : actors_)
            if (a.alive && a.owner == v.owner && types_[a.type].building && types_[a.type].base_provider) { has_yard = true; break; }
        order_deploy(&vid, 1);
        b.active_mcvs.erase(std::remove_if(b.active_mcvs.begin(), b.active_mcvs.end(),
            [&](const BotActiveMcv& m) { return m.id == vid; }), b.active_mcvs.end());
        if (!has_yard) { b.initial_base_center = at; b.defense_center = at; }
        return;
    }

    if (vt.harvester && b.harv_respond_cooldown <= 0) {
        Harvest& h = harvests_[victim];
        if (h.state != Harvest::UNLOADING && h.state != Harvest::DOCK_TURN && h.bales > 0) {
            b.harv_respond_cooldown = MAX_RESPOND_COOLDOWN;
            release_claim(victim);
            h.automated = true;
            h.state = Harvest::TO_DOCK;
            h.timer = 0;
        }
    }


    const UnitType& at = types_[actors_[ai].type];
    const bool naval_attacker = !at.building && !at.aircraft &&
        (at.locomotor == LOCO_NAVAL || at.locomotor == LOCO_LCRAFT ||
         (!map_.passable(mobiles_[ai].cell, MC_LAND) && map_.passable(mobiles_[ai].cell, MC_NAVAL)));
    if (naval_attacker) {
        b.naval_alarm_id = attacker_id;
        b.naval_alarm_cell = mobiles_[ai].cell;
        b.naval_alarm_tick = tick_;
    }

    if (b.respond_cooldown > 0 || !(vt.building || vt.harvester)) return;


    if (at.aircraft) return;
    if (naval_attacker) {


        std::vector<uint8_t> reach;
        bot_land_reach(vt.building ? v.origin : mobiles_[victim].cell, reach);
        bool any = false;
        for (int32_t id : b.idle_base_units) {
            const int i = index_of(id);
            CPos fc;
            if (i >= 0 && bot_shore_firing_cell(size_t(i), size_t(ai), reach, fc)) { any = true; break; }
        }
        if (!any) return;
    }
    b.respond_cooldown = MAX_RESPOND_COOLDOWN;
    b.protect_from = attacker_id;
}


void World::bot_base_builder(int32_t owner) {
    BotState& b = players_[owner].bot;
    for (int k = 0; k < 2; ++k) --b.wait_ticks_q[k];


    if (b.p.surplus_cash > 0 && credits(owner) - bot_pending_cost(owner) > b.p.surplus_cash) {
        for (int k = 0; k < 2; ++k) {
            const int32_t kind = k == 0 ? QUEUE_BUILDING : QUEUE_DEFENSE;
            if (find_producer(owner, kind) >= 0) bot_base_builder_queue(owner, kind);
        }
        return;
    }
    b.builder_index = (b.builder_index + 1) % 2;
    const int32_t kind = b.builder_index == 0 ? QUEUE_BUILDING : QUEUE_DEFENSE;
    if (find_producer(owner, kind) < 0) return;
    bot_base_builder_queue(owner, kind);
}

void World::bot_base_builder_queue(int32_t owner, int32_t kind) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    const int qi = kind == QUEUE_DEFENSE ? 1 : 0;
    int32_t& wait_ticks = b.wait_ticks_q[qi];
    int32_t& fail_count = b.fail_count_q[qi];
    int32_t& fail_retry_ticks = b.fail_retry_q[qi];


    int32_t buildings = 0, bases = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
        ++buildings;
        if (types_[a.type].base_provider) ++bases;
    }


    if (fail_count >= p.max_failed_placements) {
        if (--fail_retry_ticks <= 0) {
            if (buildings < b.cached_buildings || bases > b.cached_bases) fail_count = 0;
            else fail_retry_ticks = p.structure_resume_delay;
        }
        if (fail_count >= p.max_failed_placements) return;
    }
    if (wait_ticks > 0) return;

    const int32_t bonus = p.excess_power_increment * (buildings / std::max(1, p.excess_power_threshold));
    b.min_excess_power = std::clamp(p.min_excess_power + bonus, p.min_excess_power, p.max_excess_power);


    bool active = true;
    std::vector<BuildItem>& q = players_[owner].queues[kind];
    if (q.empty()) {
        if (credits(owner) < p.production_min_cash) {
            active = false;
        } else if (!bot_reaction_ready(owner, kind)) {


        } else {
            const int32_t item = bot_choose_building(owner, kind);
            if (item >= 0) { queue_build(owner, item); bot_reaction_reset(owner, kind); }
            else active = false;
        }
    } else if (q.front().done) {


        if (bot_reaction_ready(owner, kind)) {
            const int32_t type = q.front().type;
            CPos loc;
            if (!bot_find_location(owner, type, loc)) {
                if (++fail_count >= p.max_failed_placements) {
                    cancel_build(owner, kind, type);
                    b.cached_buildings = buildings;
                    b.cached_bases = bases;
                }
            } else {
                fail_count = 0;
                place_building(owner, type, loc);
                bot_reaction_reset(owner, kind);
            }
        }
    }
    const int32_t random_factor = int32_t(rand() % uint32_t(std::max(1, p.structure_random_delay)));
    wait_ticks = (active ? p.structure_active_delay : p.structure_inactive_delay) + random_factor;
}


bool World::bot_water_building_ok(int32_t owner, int32_t type) const {
    const UnitType& t = types_[size_t(type)];
    if (!t.building || t.terrain_mask == 0) return true;

    if ((t.terrain_mask & (1u << TER_WATER)) == 0) return true;
    CPos center{-1, -1};
    if (find_base_center(actors_, types_, owner, 0, center) < 0 || center.x < 0) return true;
    const int32_t r = std::max(8, players_[size_t(owner)].bot.p.max_base_radius);
    for (int dy = -r; dy <= r; ++dy) {
        for (int dx = -r; dx <= r; ++dx) {
            const CPos cc{center.x + dx, center.y + dy};
            if (!map_.in_bounds(cc)) continue;
            if (((t.terrain_mask >> map_.base_terrain(cc)) & 1u) != 0) return true;
        }
    }
    return false;
}


constexpr int32_t UNIT_REPAIR_HP_PERMILLE = 500;
constexpr int32_t UNIT_REPAIR_INTERVAL = 97;
constexpr int32_t UNIT_REPAIR_NO_FIGHT_CELLS = 10;

void World::bot_repair_units(int32_t owner) {
    BotState& b = players_[owner].bot;
    if (--b.unit_repair_ticks > 0) return;
    b.unit_repair_ticks = UNIT_REPAIR_INTERVAL;

    for (const Actor& a : actors_)
        if (a.alive && a.owner == owner && a.repair_depot >= 0 && !types_[a.type].building) return;

    std::vector<size_t> depots;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& d = actors_[i];
        if (d.alive && d.owner == owner && types_[d.type].repairs_units && d.make_ticks <= 0 && d.sell_ticks < 0)
            depots.push_back(i);
    }
    if (depots.empty()) return;

    CPos base{-1, -1};
    if (find_base_center(actors_, types_, owner, 0, base) < 0 || base.x < 0) return;
    const int64_t home_r2 = int64_t(b.p.max_base_radius) * b.p.max_base_radius;

    std::vector<int32_t> busy;
    for (const BotSquad& sq : b.squads) {
        if (sq.state == BotSquad::IDLE) continue;
        busy.insert(busy.end(), sq.units.begin(), sq.units.end());
    }
    size_t worst = actors_.size();
    int32_t worst_permille = UNIT_REPAIR_HP_PERMILLE;
    size_t worst_depot = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building || !t.repairable || a.transport >= 0 || a.repair_depot >= 0) continue;
        if (combats_[i].target >= 0 || combats_[i].attack_move) continue;
        if (std::find(busy.begin(), busy.end(), a.id) != busy.end()) continue;
        if (bot_cell_d2(mobiles_[i].cell, base) > home_r2) continue;
        const int32_t permille = t.hp > 0 ? int32_t(int64_t(a.hp) * 1000 / t.hp) : 1000;
        if (permille >= worst_permille) continue;

        bool enemy_near = false;
        for (size_t k = 0; k < actors_.size() && !enemy_near; ++k) {
            const Actor& e = actors_[k];
            if (!e.alive || !hostile(owner, e.owner) || types_[e.type].husk) continue;
            if (length(e.pos - a.pos) <= int64_t(UNIT_REPAIR_NO_FIGHT_CELLS) * CELL) enemy_near = true;
        }
        if (enemy_near) continue;

        int64_t best_d = INT64_MAX;
        size_t best_depot = 0;
        bool found = false;
        for (size_t d : depots) {
            if (!t.may_repair_at(actors_[d].type)) continue;
            const int64_t dist = length_sq(actors_[d].pos - a.pos);
            if (dist < best_d) { best_d = dist; best_depot = d; found = true; }
        }
        if (!found) continue;
        worst = i;
        worst_permille = permille;
        worst_depot = best_depot;
    }
    if (worst >= actors_.size()) return;
    const int32_t id = actors_[worst].id;
    order_repair(&id, 1, actors_[worst_depot].id);
}


constexpr int32_t SABOTEUR_INTERVAL = 375;
constexpr int32_t SABOTEUR_TARGET_OPTIONS = 10;

void World::bot_saboteurs(int32_t owner) {
    BotState& b = players_[owner].bot;
    if (--b.saboteur_ticks > 0) return;
    b.saboteur_ticks = SABOTEUR_INTERVAL;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building || t.aircraft || t.husk || t.harvester) continue;

        if (!t.captures && t.demolition_delay < 0 && t.infiltrates == 0) continue;
        if (a.transport >= 0 || a.enter_target >= 0 || a.enter_kind != ENTER_NONE) continue;

        std::vector<uint8_t> reach;
        bot_land_reach(mobiles_[i].cell, reach);

        struct Cand { int32_t id; int64_t value; int64_t dist; };
        std::vector<Cand> cands;
        for (size_t k = 0; k < actors_.size(); ++k) {
            const Actor& e = actors_[k];
            if (!e.alive || e.owner == owner) continue;
            const UnitType& et = types_[e.type];
            if (!et.building || et.husk) continue;
            if (!actor_visible_to(owner, k)) continue;
            const int32_t kind = enter_kind_for(i, k);
            if (kind == ENTER_NONE || kind == ENTER_REPAIR || kind == ENTER_REPAIR_BRIDGE) continue;

            bool can_walk = false;
            for (int y = -1; y <= et.foot_h && !can_walk; ++y) {
                for (int x = -1; x <= et.foot_w; ++x) {
                    const CPos c{e.origin.x + x, e.origin.y + y};
                    if (!map_.in_bounds(c)) continue;
                    if (reach[size_t(map_.index(c))]) { can_walk = true; break; }
                }
            }
            if (!can_walk) continue;
            const int64_t value = et.sell_value >= 0 ? et.sell_value : et.cost;
            cands.push_back({e.id, value, length_sq(e.pos - a.pos)});
        }
        if (cands.empty()) continue;


        std::sort(cands.begin(), cands.end(), [](const Cand& x, const Cand& y) {
            if (x.value != y.value) return x.value > y.value;
            return x.id < y.id;
        });
        if (cands.size() > size_t(SABOTEUR_TARGET_OPTIONS)) cands.resize(size_t(SABOTEUR_TARGET_OPTIONS));
        const Cand* best = &cands[0];
        for (const Cand& c : cands) if (c.dist < best->dist) best = &c;
        const int32_t id = a.id;
        order_enter(&id, 1, best->id);


        for (BotSquad& sq : b.squads)
            sq.units.erase(std::remove(sq.units.begin(), sq.units.end(), id), sq.units.end());
        b.idle_base_units.erase(std::remove(b.idle_base_units.begin(), b.idle_base_units.end(), id),
                                b.idle_base_units.end());
        if (std::find(b.active_units.begin(), b.active_units.end(), id) == b.active_units.end())
            b.active_units.push_back(id);
    }
}


int32_t World::bot_choose_building(int32_t owner, int32_t kind) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    std::vector<int32_t> buildable_list;
    buildable(owner, kind, buildable_list);
    if (buildable_list.empty()) return -1;


    std::vector<int32_t> count(types_.size(), 0);
    int32_t buildings = 0, refineries = 0, powers = 0, productions = 0, yards = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
        const UnitType& t = types_[a.type];
        ++count[a.type];
        ++buildings;
        if (t.refinery) ++refineries;
        if (t.power > 0) ++powers;
        if (t.produces & ((1u << QUEUE_INFANTRY) | (1u << QUEUE_VEHICLE))) ++productions;
        if (t.base_provider) ++yards;
    }
    for (const BuildItem& it : players_[owner].queues[QUEUE_BUILDING]) ++count[it.type];
    for (const BuildItem& it : players_[owner].queues[QUEUE_DEFENSE]) ++count[it.type];

    auto under_limit = [&](int32_t t) { return count[t] < bot_table(p.building_limit, size_t(t), types_[t].ai_building_limit); };
    const int32_t excess = power_provided(owner) - power_drained(owner);
    auto sufficient_power = [&](int32_t t) { return types_[t].power + excess >= p.min_excess_power; };


    int32_t power = -1;
    for (int32_t t : buildable_list) {
        if (types_[t].power > 0 && under_limit(t) && (power < 0 || types_[t].power > types_[power].power)) power = t;
    }
    if (excess < b.min_excess_power && power >= 0) return power;


    const int32_t optimal_refineries = productions > 0 ? p.initial_min_refineries + p.additional_min_refineries : p.initial_min_refineries;
    const bool adequate = refineries >= optimal_refineries || powers == 0 || yards == 0;


    if (!adequate || bot_refinery_request(owner) != nullptr) {
        int32_t refinery = -1;
        std::vector<int32_t> cands;
        for (int32_t t : buildable_list) if (types_[t].refinery && under_limit(t)) cands.push_back(t);
        if (!cands.empty()) refinery = cands[rand() % cands.size()];
        if (refinery >= 0 && sufficient_power(refinery)) return refinery;
        if (power >= 0 && refinery >= 0 && !sufficient_power(refinery)) return power;
    }


    if (kind == QUEUE_DEFENSE) {
        const int32_t tower = bot_defense_request(owner, buildable_list, count);
        if (tower >= 0) {
            if (sufficient_power(tower)) return tower;
            if (power >= 0) return power;
        }
    }


    {
        const int32_t surplus = bot_spend_surplus(owner, kind, buildable_list, count);
        if (surplus >= 0) {
            if (sufficient_power(surplus)) return surplus;
            if (power >= 0) return power;
        }
    }


    if (has_storage_ && storage_capacity(owner) > 0 && resources_stored(owner) * 5 > storage_capacity(owner) * 4) {
        for (int32_t t : buildable_list) {
            if (types_[t].storage > 0 && under_limit(t)) return t;
        }
    }


    std::vector<int32_t> fractions;
    for (size_t t = 0; t < types_.size(); ++t) {
        if (bot_table(p.building_fraction, t, types_[t].ai_building_fraction) >= 0 && types_[t].queue_kind == kind) {
            fractions.push_back(int32_t(t));
        }
    }
    for (size_t i = fractions.size(); i > 1; --i) std::swap(fractions[i - 1], fractions[rand() % i]);
    for (int32_t t : fractions) {
        const UnitType& ut = types_[t];
        if (bot_table(p.building_delay, size_t(t), ut.ai_building_delay) > int32_t(tick_)) continue;
        if (std::find(buildable_list.begin(), buildable_list.end(), t) == buildable_list.end()) continue;


        if (!bot_water_building_ok(owner, t)) continue;
        if (count[t] * 100 > bot_table(p.building_fraction, size_t(t), ut.ai_building_fraction) * buildings) continue;
        if (!under_limit(t)) continue;
        if (excess < b.min_excess_power || !sufficient_power(t)) {
            if (power >= 0) return power;
        }
        return t;
    }
    return -1;
}


void World::bot_land_reach(CPos from, std::vector<uint8_t>& out) const {
    out.assign(size_t(map_.cells()), 0);
    if (map_.cells() <= 0) return;
    std::vector<int32_t> stack;
    for (int dy = -4; dy <= 4; ++dy) {
        for (int dx = -4; dx <= 4; ++dx) {
            const CPos c{from.x + dx, from.y + dy};
            if (!map_.in_bounds(c) || !map_.passable(c)) continue;
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
            if (!map_.in_bounds(nb) || !map_.passable(nb)) continue;
            const int32_t ni = map_.index(nb);
            if (out[size_t(ni)]) continue;
            out[size_t(ni)] = 1;
            stack.push_back(ni);
        }
    }
}


bool World::bot_find_location(int32_t owner, int32_t type, CPos& out) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    CPos base_center;
    if (!bot_base_center(owner, base_center)) return false;
    CPos center = base_center;


    const BotRefineryRequest* request = nullptr;
    if (types_[type].refinery) {
        request = bot_refinery_request(owner);
        if (b.fail_count_q[0] > 0) center = base_center;
        else if (request != nullptr) center = request->conyard;
        else if (b.resource_conyard_center.x >= 0) center = b.resource_conyard_center;
    }

    if (types_[type].defense && b.defense_center.x >= 0) {
        CPos best = center;
        int64_t bd = INT64_MAX;
        for (const Actor& a : actors_) {
            if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].base_provider) continue;
            const int64_t d = bot_cell_d2(a.origin, b.defense_center);
            if (d < bd) { bd = d; best = a.origin; }
        }
        center = best;
    }

    std::vector<CPos> cells;
    for (int y = center.y - p.max_base_radius; y <= center.y + p.max_base_radius; ++y) {
        for (int x = center.x - p.max_base_radius; x <= center.x + p.max_base_radius; ++x) {
            const CPos c{x, y};
            if (!map_.in_bounds(c)) continue;
            const int64_t d2 = bot_cell_d2(c, center);
            if (d2 < int64_t(p.min_base_radius) * p.min_base_radius || d2 > int64_t(p.max_base_radius) * p.max_base_radius) continue;
            cells.push_back(c);
        }
    }
    if (cells.empty()) return false;

    const UnitType& t = types_[type];
    if (t.defense) {


        CPos target = center;
        bool have_target = bot_attack_center(owner, target);
        int64_t best = INT64_MAX;
        for (size_t i = 0; i < actors_.size() && !have_target; ++i) {
            if (!actors_[i].alive || !hostile(owner, actors_[i].owner)) continue;
            const int64_t d = bot_cell_d2(mobiles_[i].cell, center);
            if (d < best) { best = d; target = mobiles_[i].cell; }
        }
        const int64_t theta = 5;
        const int64_t deta = int64_t(isqrt(bot_cell_d2(target, center))) - 5;


        std::sort(cells.begin(), cells.end(), [&](CPos a, CPos c2) {
            const int64_t da = deta * bot_cell_d2(a, target) + theta * bot_cell_d2(a, center);
            const int64_t db = deta * bot_cell_d2(c2, target) + theta * bot_cell_d2(c2, center);
            return da != db ? da < db : map_.index(a) < map_.index(c2);
        });
        for (const CPos& c : cells) {
            if (can_place(owner, type, c, nullptr)) { out = c; return true; }
        }
        return false;
    }
    auto try_cells = [&](std::vector<CPos>& list) -> bool {
        for (const CPos& c : list) {

            if (can_place(owner, type, c, nullptr)) { out = c; return true; }
        }
        return false;
    };

    if (t.refinery) {


        std::vector<uint8_t> reach;
        bot_land_reach(center, reach);
        cells.erase(std::remove_if(cells.begin(), cells.end(),
                                   [&](CPos c) { return !reach[size_t(map_.index(c))]; }),
                    cells.end());
        if (cells.empty()) return false;
        std::vector<CPos> ore;
        for (const CPos& c : cells) if (res_type_[map_.index(c)] != RES_NONE) ore.push_back(c);


        CPos closest_refinery{-1, -1};
        if (b.fail_count_q[0] <= 0) {
            int64_t best = INT64_MAX;
            for (const Actor& a : actors_) {
                if (!a.alive || a.owner != owner || !types_[a.type].refinery) continue;
                const int64_t d = bot_cell_d2(a.origin, center);
                if (d < best || (d == best && map_.index(a.origin) < map_.index(closest_refinery))) {
                    best = d;
                    closest_refinery = a.origin;
                }
            }
        }
        if (closest_refinery.x < 0) {

            for (size_t i = ore.size(); i > 1; --i) std::swap(ore[i - 1], ore[rand() % i]);
        } else if (request != nullptr) {

            const CPos want = request->resource;
            std::sort(ore.begin(), ore.end(), [&](CPos a, CPos c2) {
                const int64_t da = bot_cell_d2(a, want), db = bot_cell_d2(c2, want);
                return da != db ? da < db : map_.index(a) < map_.index(c2);
            });
        } else {


            std::sort(ore.begin(), ore.end(), [&](CPos a, CPos c2) {
                const int64_t da = bot_cell_d2(a, closest_refinery), db = bot_cell_d2(c2, closest_refinery);
                return da != db ? da > db : map_.index(a) < map_.index(c2);
            });
        }
        if (ore.size() > size_t(p.max_resource_cells_to_check)) ore.resize(size_t(p.max_resource_cells_to_check));
        for (const CPos& target : ore) {
            std::vector<CPos> sorted = cells;
            std::sort(sorted.begin(), sorted.end(), [&](CPos a, CPos c2) {
                const int64_t da = bot_cell_d2(a, target), db = bot_cell_d2(c2, target);
                return da != db ? da < db : map_.index(a) < map_.index(c2);
            });
            if (try_cells(sorted)) {
                if (request != nullptr) b.requested_refineries.erase(b.requested_refineries.begin() + (request - b.requested_refineries.data()));
                return true;
            }
        }
        if (request != nullptr) b.requested_refineries.erase(b.requested_refineries.begin() + (request - b.requested_refineries.data()));

        if (!(center == base_center)) {
            cells.clear();
            for (int y = base_center.y - p.max_base_radius; y <= base_center.y + p.max_base_radius; ++y) {
                for (int x = base_center.x - p.max_base_radius; x <= base_center.x + p.max_base_radius; ++x) {
                    const CPos c{x, y};
                    if (!map_.in_bounds(c)) continue;
                    const int64_t d2 = bot_cell_d2(c, base_center);
                    if (d2 < int64_t(p.min_base_radius) * p.min_base_radius || d2 > int64_t(p.max_base_radius) * p.max_base_radius) continue;
                    if (!reach[size_t(map_.index(c))]) continue;
                    cells.push_back(c);
                }
            }
        }
    }
    for (size_t i = cells.size(); i > 1; --i) std::swap(cells[i - 1], cells[rand() % i]);
    return try_cells(cells);
}


bool World::bot_shore_firing_cell(size_t unit, size_t target, const std::vector<uint8_t>& reach, CPos& out) const {
    const UnitType& t = types_[actors_[unit].type];
    if (t.weapon < 0 || size_t(t.weapon) >= weapons_.size()) return false;
    const Weapon& w = weapons_[size_t(t.weapon)];
    if ((w.valid_targets & target_mask(target)) == 0) return false;
    const int64_t range = std::max<int64_t>(CELL, w.range - CELL / 4);
    const int32_t rc = int32_t(range / CELL) + 1;
    const CPos tc = mobiles_[target].cell;
    const CPos from = mobiles_[unit].cell;
    int64_t best = INT64_MAX;
    bool found = false;
    for (int dy = -rc; dy <= rc; ++dy) {
        for (int dx = -rc; dx <= rc; ++dx) {
            const CPos c{tc.x + dx, tc.y + dy};
            if (!map_.in_bounds(c)) continue;
            if (int64_t(dx) * dx * CELL * CELL + int64_t(dy) * dy * CELL * CELL > range * range) continue;
            const int32_t idx = map_.index(c);
            if (!map_.passable(c, MC_LAND) || idx < 0 || size_t(idx) >= reach.size() || !reach[size_t(idx)]) continue;
            const int64_t d = cell_dist_sq(c, from);

            if (d < best || (d == best && found && idx < map_.index(out))) { best = d; out = c; found = true; }
        }
    }
    return found;
}


bool World::bot_reaction_ready(int32_t owner, int32_t kind) {
    if (kind < 0 || kind >= NUM_QUEUES) return true;
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    if (p.reaction_max_ticks <= 0) return true;
    int32_t& r = b.react_q[kind];
    if (r < 0) {
        const int32_t lo = std::max(0, std::min(p.reaction_min_ticks, p.reaction_max_ticks));
        const int32_t span = std::max(0, p.reaction_max_ticks - lo);
        r = lo + (span > 0 ? int32_t(rand() % uint32_t(span + 1)) : 0);
    }
    return r <= 0;
}

void World::bot_reaction_reset(int32_t owner, int32_t kind) {
    if (kind < 0 || kind >= NUM_QUEUES) return;
    players_[owner].bot.react_q[kind] = -1;
}

void World::bot_reaction_tick(int32_t owner) {
    BotState& b = players_[owner].bot;
    for (int k = 0; k < NUM_QUEUES; ++k) if (b.react_q[k] > 0) --b.react_q[k];
}


void World::bot_unit_builder(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;

    int32_t refineries = 0, harvesters = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        if (types_[a.type].refinery) ++refineries;
        if (types_[a.type].harvester) ++harvesters;
    }
    if (credits(owner) < p.unit_min_cash || refineries < p.initial_min_refineries) return;
    if (++b.unit_ticks % std::max(1, p.unit_feedback_time) != 0) return;


    static const int32_t UNIT_QUEUES[] = {QUEUE_VEHICLE, QUEUE_INFANTRY, QUEUE_AIRCRAFT, QUEUE_SHIP};
    constexpr int NUM_UNIT_QUEUES = 4;


    if (!b.build_requests.empty()) {
        const int32_t type = b.build_requests.front();
        const bool surplus = types_[type].harvester && harvesters >= std::max(1, refineries);
        if (!surplus || credits(owner) >= std::max(types_[type].cost, p.surplus_cash)) {
            b.build_requests.erase(b.build_requests.begin());
            const int32_t kind = types_[type].queue_kind;
            if (kind >= 0 && players_[owner].queues[kind].empty()) {


                if (!bot_reaction_ready(owner, kind)) {
                    b.build_requests.insert(b.build_requests.begin(), type);
                } else {
                    queue_build(owner, type);
                    bot_reaction_reset(owner, kind);
                }
            }
        }
    }


    for (int i = 0; i < NUM_UNIT_QUEUES; ++i) {
        b.queue_index = (b.queue_index + 1) % NUM_UNIT_QUEUES;
        const int32_t kind = UNIT_QUEUES[b.queue_index];
        if (find_producer(owner, kind) < 0) continue;
        if (!players_[owner].queues[kind].empty()) continue;


        if (!bot_reaction_ready(owner, kind)) continue;
        const int32_t unit = bot_choose_unit(owner, kind);
        if (unit >= 0 && queue_build(owner, unit)) { ++b.stat_units_built; bot_reaction_reset(owner, kind); }
        break;
    }
}


int32_t World::bot_choose_unit(int32_t owner, int32_t kind) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    std::vector<int32_t> list;
    buildable(owner, kind, list);
    if (list.empty()) return -1;
    for (size_t i = list.size(); i > 1; --i) std::swap(list[i - 1], list[rand() % i]);
    std::vector<int32_t> count(types_.size(), 0);
    int32_t all = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || bot_table(p.unit_share, size_t(a.type), types_[a.type].ai_unit_share) < 0) continue;
        ++count[a.type];
        ++all;
    }


    for (int32_t role = 0; role < ROLE_COUNT; ++role) {
        if (b.vh_orders[role] <= 0) continue;
        int32_t best = -1;
        for (int32_t t : list) {
            const UnitType& ut = types_[t];
            if (bot_role_of_type(size_t(t)) != role) continue;
            if (bot_table(p.unit_share, size_t(t), ut.ai_unit_share) < 0) continue;
            if (count[t] >= bot_table(p.unit_limit, size_t(t), ut.ai_unit_limit)) continue;
            if (best < 0 || t < best) best = t;
        }
        if (best < 0) continue;
        --b.vh_orders[role];
        return best;
    }

    int32_t desired = -1, desired_error = INT32_MAX;
    for (int32_t t : list) {
        const UnitType& ut = types_[t];
        int32_t share = bot_table(p.unit_share, size_t(t), ut.ai_unit_share);
        if (share < 0) continue;
        share = share * bot_counter_share(owner, size_t(t)) / 100;
        if (count[t] >= bot_table(p.unit_limit, size_t(t), ut.ai_unit_limit)) continue;
        const int32_t error = all > 0 ? count[t] * 100 / all - share : -1;
        if (error < 0) return t;
        if (error < desired_error) { desired_error = error; desired = t; }
    }
    return desired;
}


void World::bot_harvesters(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    if (--b.scan_idle_harvesters_ticks > 0) return;
    b.scan_idle_harvesters_ticks = p.scan_idle_harvesters_interval;
    int32_t harvesters = 0, refineries = 0, harvester_type = -1;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner) continue;
        if (types_[a.type].refinery) ++refineries;
        if (!types_[a.type].harvester) continue;
        ++harvesters;

        Harvest& h = harvests_[i];
        if (!h.automated && !mobiles_[i].moving && !mobiles_[i].in_transit) {
            h.automated = true;
            h.state = Harvest::SEARCH;
        }
    }
    for (size_t t = 0; t < types_.size(); ++t) {
        if (types_[t].harvester && types_[t].cost > 0 &&
            bot_table(p.unit_share, t, types_[t].ai_unit_share) >= 0) harvester_type = int32_t(t);
    }
    if (harvester_type < 0) return;


    const int32_t want = std::max(bot_harvester_target(owner), refineries > 0 ? 0 : std::min(p.initial_harvesters, 1));
    const bool too_low = harvesters < want;
    if (too_low && std::find(b.build_requests.begin(), b.build_requests.end(), harvester_type) == b.build_requests.end()) {
        b.build_requests.push_back(harvester_type);
    }
}


void World::bot_low_effect_harvesters(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    if (--b.low_effect_ticks > 0) return;
    b.low_effect_ticks = std::max(1, p.scan_low_effect_interval);
    bot_idle_harvesters(owner);
    if (b.resource_map.empty()) return;

    const int64_t side2 = int64_t(b.rmap_side) * b.rmap_side;
    const int32_t per_harv = std::max(1, p.resource_cells_per_harvester);
    struct Lack { int64_t attraction; int32_t lack; CPos res_center; };
    std::vector<Lack> lacking;
    CPos worst{-1, -1};
    int32_t worst_lack = INT32_MAX;

    for (int32_t i = 0; i < int32_t(b.resource_map.size()); ++i) {
        const BotResourceIndice& in = b.resource_map[size_t(i)];
        int64_t attraction = side2 >> 5;
        attraction += in.res_cells - int64_t(in.harvesters) * per_harv;
        int32_t lack = attraction > 0 ? int32_t(attraction / per_harv) : ((attraction == 0 && in.res_cells > 0) ? 1 : -1);
        attraction >>= 1;
        if (in.refineries <= 0 && lack > 0) lack = 1;
        if (in.enemy_bases > 0 || in.enemy_units > 0) {
            attraction -= side2 << 4;
        } else if (bot_indice_threat(b, i, side2) > 0) {
            attraction -= side2 >> 5;
        }
        if (in.refineries > 0) attraction += side2;
        if (in.res_cells > 0 && attraction > 0 && lack > 0) lacking.push_back({attraction, lack, in.res_center});
        if (lack < worst_lack && lack < 0) { worst_lack = lack; worst = in.center; }
    }
    if (worst.x < 0 || lacking.empty()) return;


    const int64_t search_r = int64_t(b.rmap_scan) * CELL;
    std::vector<int> harvs;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].harvester) continue;
        if (length(a.pos - cell_center(worst)) > search_r) continue;
        const Harvest& h = harvests_[i];
        if (h.state == Harvest::UNLOADING || h.state == Harvest::DOCK_TURN) continue;
        harvs.push_back(int(i));
    }
    int32_t can_assign = std::min(-worst_lack, int32_t(harvs.size()) - 1);
    if (can_assign <= 0) return;

    const CPos from = mobiles_[size_t(harvs[0])].cell;


    std::vector<uint8_t> reach;
    bot_land_reach(from, reach);
    const int64_t factor = std::max<int64_t>(1, int64_t(b.rmap_cols) * b.rmap_cols + int64_t(b.rmap_rows) * b.rmap_rows);
    std::sort(lacking.begin(), lacking.end(), [&](const Lack& a, const Lack& c) {
        const int64_t va = a.attraction - cell_dist_sq(from, a.res_center) / factor;
        const int64_t vc = c.attraction - cell_dist_sq(from, c.res_center) / factor;

        return va != vc ? va > vc : map_.index(a.res_center) < map_.index(c.res_center);
    });

    for (const Lack& l : lacking) {
        if (can_assign <= 0) break;
        int32_t need = l.lack;

        std::vector<CPos> targets;
        const int64_t own_d = cell_dist_sq(from, l.res_center);
        for (int y = l.res_center.y - b.rmap_scan; y <= l.res_center.y + b.rmap_scan; ++y) {
            for (int x = l.res_center.x - b.rmap_scan; x <= l.res_center.x + b.rmap_scan; ++x) {
                const CPos c{x, y};
                if (!map_.in_bounds(c) || cell_dist_sq(c, l.res_center) > int64_t(b.rmap_scan) * b.rmap_scan) continue;
                if (res_type_[size_t(map_.index(c))] == RES_NONE) continue;
                if (cell_dist_sq(c, from) > own_d) continue;
                if (!reach[size_t(map_.index(c))]) continue;
                targets.push_back(c);
            }
        }
        if (targets.empty() || need <= 0) continue;
        std::vector<int> rest;
        for (int hi : harvs) {
            if (need <= 0 || can_assign <= 0) { rest.push_back(hi); continue; }
            const int32_t id = actors_[size_t(hi)].id;
            order_harvest(&id, 1, targets[rand() % targets.size()]);
            --need;
            --can_assign;
        }
        harvs = rest;
    }
}


void World::bot_idle_harvesters(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    const int64_t avoid = int64_t(p.harvester_enemy_avoidance) * CELL;
    std::vector<int32_t> taken;
    std::vector<uint8_t> reach;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].harvester) continue;
        const Harvest& h = harvests_[i];
        if (!h.automated || h.bales > 0 || h.state != Harvest::WAIT) continue;
        const int proc = nearest_refinery(i);
        if (proc < 0) continue;
        const CPos dock = dock_cell(proc);
        const int32_t radius = std::max(1, types_[a.type].search_from_proc);
        const int64_t r2 = int64_t(radius) * radius;
        const CPos from = mobiles_[i].cell;


        bot_land_reach(dock, reach);
        CPos best{-1, -1};
        int64_t best_d = INT64_MAX;
        for (int idx = 0; idx < map_.cells(); ++idx) {
            if (res_density_[size_t(idx)] <= 0 || claims_[size_t(idx)] >= 0) continue;
            if (std::find(taken.begin(), taken.end(), idx) != taken.end()) continue;
            const CPos c = map_.cell_at(idx);
            if (cell_dist_sq(c, dock) <= r2 || !map_.passable(c)) continue;
            if (!reach[size_t(idx)]) continue;
            const int64_t d = cell_dist_sq(c, from);
            if (d >= best_d) continue;
            bool threatened = false;
            for (const Actor& e : actors_) {
                if (!e.alive || !hostile(owner, e.owner)) continue;
                if (length(e.pos - cell_center(c)) <= avoid) { threatened = true; break; }
            }
            if (threatened) continue;
            best_d = d;
            best = c;
        }
        if (best.x < 0) continue;
        taken.push_back(map_.index(best));
        const int32_t id = a.id;
        order_harvest(&id, 1, best);
    }
    (void)b;
}


bool World::bot_can_attack(const std::vector<int32_t>& own, const std::vector<int32_t>& enemies, bool rush) const {
    auto health = [&](const std::vector<int32_t>& ids) -> int32_t {
        int64_t hp = 0, max = 0;
        for (int32_t id : ids) {
            const int i = index_of(id);
            if (i < 0) continue;
            hp += actors_[i].hp;
            max += types_[actors_[i].type].hp;
        }
        return max > 0 ? int32_t(hp * 100 / max) : 0;
    };

    auto power = [&](const std::vector<int32_t>& ids) -> int64_t {
        int64_t sum = 0;
        for (int32_t id : ids) {
            const int i = index_of(id);
            if (i < 0) continue;
            const UnitType& t = types_[actors_[i].type];
            if (t.weapon < 0) continue;
            const Weapon& w = weapons_[t.weapon];
            const int32_t burst = std::max(1, w.burst);
            const int32_t reload = std::max(1, w.reload + std::clamp(w.burst_delay * (burst - 1), 1, 200));
            sum += int64_t(w.damage) * burst / reload * 100;
        }
        return sum;
    };
    auto speed = [&](const std::vector<int32_t>& ids) -> int64_t {
        int64_t sum = 0, n = 0;
        for (int32_t id : ids) {
            const int i = index_of(id);
            if (i < 0 || types_[actors_[i].type].building) continue;
            sum += types_[actors_[i].type].speed;
            ++n;
        }
        return n > 0 ? sum / n : 0;
    };
    auto relative = [&](int64_t mine, int64_t theirs) -> int32_t {
        if (enemies.empty()) return 999;
        if (own.empty()) return 0;
        if (theirs <= 0) return 999;
        return int32_t(std::clamp<int64_t>(mine * 100 / theirs, 0, 999));
    };
    enum { NEAR_DEAD, INJURED, NORMAL };
    enum { WEAK, EQUAL, STRONG };
    auto h_term = [](int32_t h) { return h < 35 ? NEAR_DEAD : (h < 62 ? INJURED : NORMAL); };
    auto r_term = [](int32_t r) { return r < 87 ? WEAK : (r <= 113 ? EQUAL : STRONG); };
    const int oh = h_term(health(own));
    const int eh = h_term(health(enemies));
    const int rp = r_term(relative(power(own), power(enemies)));
    const int rs = r_term(relative(speed(own), speed(enemies)));


    if (rush && oh == NORMAL) return rp == STRONG;
    if (oh == NORMAL) return true;
    if (oh == INJURED) {
        if (eh == NEAR_DEAD) return true;
        if (rp == EQUAL || rp == STRONG) return true;
        if (rp == WEAK && rs == WEAK) return true;
        return false;
    }

    if ((eh == NEAR_DEAD || eh == INJURED) && (rp == EQUAL || rp == STRONG) && (rs == WEAK || rs == EQUAL)) return true;
    return false;
}


void World::bot_squads(int32_t owner) {
    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    auto cannot_be_ordered = [&](int32_t id) {
        const int i = index_of(id);
        return i < 0 || !actors_[i].alive || actors_[i].owner != owner;
    };
    auto erase_dead = [&](std::vector<int32_t>& v) {
        v.erase(std::remove_if(v.begin(), v.end(), cannot_be_ordered), v.end());
    };

    for (BotSquad& s : b.squads) erase_dead(s.units);
    b.squads.erase(std::remove_if(b.squads.begin(), b.squads.end(), [](const BotSquad& s) { return s.dead || s.units.empty(); }), b.squads.end());
    erase_dead(b.active_units);
    erase_dead(b.idle_base_units);

    auto is_enemy = [&](int i) { return actors_[i].alive && hostile(owner, actors_[i].owner) && types_[actors_[i].type].targetable; };


    if (--b.rush_ticks <= 0) {
        b.rush_ticks = p.rush_interval;
        const size_t ground = b.idle_base_units.size();
        if (ground >= size_t(bot_vorhaben_squad_size(owner)) && !b.idle_base_units.empty()) {
            std::vector<int32_t> attackers;
            for (int32_t id : b.idle_base_units) {
                const int i = index_of(id);
                if (i >= 0 && types_[actors_[i].type].weapon >= 0) attackers.push_back(id);
            }
            if (!attackers.empty()) {

                for (size_t yi = 0; yi < actors_.size(); ++yi) {
                    const Actor& yard = actors_[yi];
                    if (!is_enemy(int(yi)) || !types_[yard.type].base_provider) continue;
                    std::vector<int32_t> enemies;
                    const int64_t r = int64_t(p.rush_scan_radius) * CELL;
                    for (size_t ei = 0; ei < actors_.size(); ++ei) {
                        if (!is_enemy(int(ei)) || types_[actors_[ei].type].weapon < 0) continue;
                        if (length(actors_[ei].pos - yard.pos) <= r) enemies.push_back(actors_[ei].id);
                    }
                    if (bot_can_attack(b.idle_base_units, enemies, true)) {
                        const int32_t target = enemies.empty() ? yard.id : enemies[rand() % enemies.size()];
                        for (BotSquad& s : b.squads) s.target = target;
                        BotSquad* rush = nullptr;
                        for (BotSquad& s : b.squads) if (s.type == BotSquad::RUSH) { rush = &s; break; }
                        if (!rush) {
                            BotSquad ns;
                            ns.type = BotSquad::RUSH;
                            ns.target = target;
                            b.squads.push_back(ns);
                            rush = &b.squads.back();
                        }
                        rush->units.insert(rush->units.end(), b.idle_base_units.begin(), b.idle_base_units.end());
                        b.idle_base_units.clear();
                        break;
                    }
                }
            }
        }
    }


    if (--b.attack_force_ticks <= 0) {
        const size_t n = b.squads.size();
        if (n == 0) {
            b.attack_force_ticks = std::max(1, p.attack_force_interval);
        } else {
            b.attack_force_ticks = std::max<int32_t>(1, p.attack_force_interval / int32_t(n));
            if (b.squad_cursor < 0 || size_t(b.squad_cursor) >= n) b.squad_cursor = 0;
            BotSquad& s = b.squads[size_t(b.squad_cursor)];
            if (!s.units.empty()) {

                if (s.type == BotSquad::AIR) bot_update_air_squad(owner, s);
                else if (s.type == BotSquad::NAVAL) bot_update_naval_squad(owner, s);
                else if (s.type == BotSquad::RAID) bot_update_raid_squad(owner, s);
                else bot_update_squad(owner, s);
            }
            b.squad_cursor = int32_t((size_t(b.squad_cursor) + 1) % n);
            b.squads.erase(std::remove_if(b.squads.begin(), b.squads.end(), [](const BotSquad& q) { return q.dead || q.units.empty(); }), b.squads.end());
        }
    }


    if (--b.assign_roles_ticks <= 0) {
        b.assign_roles_ticks = p.assign_roles_interval;


        bot_air_squads(owner);

        bot_naval_squads(owner);
        for (const Actor& a : actors_) {
            if (!a.alive || a.owner != owner) continue;
            const UnitType& t = types_[a.type];


            if (t.building || t.harvester || t.transforms_into >= 0 || t.exclude_from_squads || t.husk) continue;
            if (t.aircraft) continue;
            if (std::find(b.active_units.begin(), b.active_units.end(), a.id) != b.active_units.end()) continue;
            b.idle_base_units.push_back(a.id);
            b.active_units.push_back(a.id);
        }
    }


    if (--b.min_attack_force_delay_ticks <= 0) {
        b.min_attack_force_delay_ticks = p.min_attack_force_delay;
        const size_t randomized = size_t(bot_vorhaben_squad_size(owner)) +
            (p.squad_size_random_bonus > 0 ? rand() % uint32_t(p.squad_size_random_bonus) : 0);


        int32_t assaults = 0;
        for (const BotSquad& s : b.squads) if (s.type == BotSquad::ASSAULT && !s.units.empty()) ++assaults;
        const bool may_form = p.allow_pincer ? assaults < 2 : assaults < 1;
        if (may_form && b.idle_base_units.size() >= randomized && int32_t(tick_) >= p.first_attack_tick) {
            BotSquad ns;
            ns.type = BotSquad::ASSAULT;
            ns.units = b.idle_base_units;


            ns.state = BotSquad::GATHER;
            ns.gather_start = tick_;
            ns.start_size = int32_t(ns.units.size());


            if (b.vh_pending >= 0) {
                ns.vorhaben = b.vh_pending;
                ns.scheme = bot_vorhaben_scheme(b.vh_pending);
                if (b.vh_pending == VH_PINCER) ns.gather_side = 1;
                if (b.vh_pending == VH_NUKE_PUSH || b.vh_pending == VH_CURTAIN_PUSH) ns.storm_at = UINT32_MAX;
                b.vh_pending = -1;
            }
            b.idle_base_units.clear();
            b.squads.push_back(ns);
            ++b.stat_squads_sent;
            if (b.stat_first_attack == 0) b.stat_first_attack = tick_;
        }
    }


    if (b.harv_respond_cooldown > 0) --b.harv_respond_cooldown;
    if (b.mcv_respond_cooldown > 0) --b.mcv_respond_cooldown;
    if (b.respond_cooldown-- == MAX_RESPOND_COOLDOWN) {
        const int ai = index_of(b.protect_from);
        if (ai >= 0 && is_enemy(ai)) {
            const int64_t r2 = int64_t(p.protect_unit_scan_radius) * p.protect_unit_scan_radius;
            for (BotSquad& s : b.squads) {
                if (s.units.empty()) continue;
                const int li = index_of(s.units.front());
                if (li >= 0 && bot_cell_d2(mobiles_[li].cell, mobiles_[ai].cell) <= r2) s.target = b.protect_from;
            }
            BotSquad* prot = nullptr;
            for (BotSquad& s : b.squads) if (s.type == BotSquad::PROTECTION) { prot = &s; break; }
            if (!prot) {
                BotSquad ns;
                ns.type = BotSquad::PROTECTION;
                ns.target = b.protect_from;
                b.squads.push_back(ns);
                prot = &b.squads.back();
            }
            std::vector<int32_t> unused;
            for (int32_t id : b.idle_base_units) {
                const int i = index_of(id);
                if (i >= 0 && types_[actors_[i].type].weapon >= 0) prot->units.push_back(id);
                else unused.push_back(id);
            }
            b.idle_base_units = unused;
            const int ti = index_of(prot->target);
            if (!prot->units.empty() && (ti < 0 || !is_enemy(ti))) prot->target = b.protect_from;
        }
    }
}


void World::bot_update_squad(int32_t owner, BotSquad& s) {


    constexpr uint32_t SIEGE_STALL_TICKS = 1500;

    constexpr int64_t GATHER_NEAR_D2 = 16;

    constexpr int32_t GATHER_READY_PERCENT = 80;

    BotState& b = players_[owner].bot;
    const BotParams& p = b.p;
    auto is_enemy = [&](int i) { return i >= 0 && actors_[i].alive && hostile(owner, actors_[i].owner) && types_[actors_[i].type].targetable; };


    auto centroid = [&]() -> WVec {
        int64_t cx = 0, cy = 0;
        int n = 0;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            cx += actors_[i].pos.x; cy += actors_[i].pos.y; ++n;
        }
        if (n == 0) return WVec{0, 0};
        return WVec{WDist(cx / n), WDist(cy / n)};
    };
    auto elect_leader = [&]() {
        const WVec c = centroid();
        int64_t best = INT64_MAX;
        s.leader = -1;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            const int64_t d = length(actors_[i].pos - c);
            if (d < best) { best = d; s.leader = id; }
        }
    };
    if (index_of(s.leader) < 0 || std::find(s.units.begin(), s.units.end(), s.leader) == s.units.end()) elect_leader();
    const int li = index_of(s.leader);
    if (li < 0) return;


    auto is_siege_id = [&](int32_t id) {
        if (!p.allow_siege) return false;
        const int i = index_of(id);
        return i >= 0 && bot_unit_is_siege(size_t(i));
    };

    auto line_units = [&]() {
        std::vector<int32_t> v;
        for (int32_t id : s.units) if (!is_siege_id(id)) v.push_back(id);
        return v;
    };


    auto squad_target = [&](WVec from) -> int32_t {
        const int32_t id = bot_front_target(owner, from, 0, s.scheme);
        if (id < 0) return -1;
        const int i = index_of(id);
        if (i < 0) return -1;
        if (types_[actors_[i].type].building) return id;
        if (length(actors_[i].pos - from) <= int64_t(p.attack_scan_radius) * CELL) return id;


        const int32_t bld = bot_front_target(owner, from, 0, s.scheme, true);
        return bld >= 0 ? bld : id;
    };

    auto closest_enemy = [&](WVec from, int64_t radius) -> int32_t {
        return bot_pick_target(owner, from, radius, true);
    };
    auto enemies_near = [&](WVec at, int32_t radius_cells, bool armed_only) {
        std::vector<int32_t> out;
        const int64_t r = int64_t(radius_cells) * CELL;
        for (size_t i = 0; i < actors_.size(); ++i) {
            if (!is_enemy(int(i))) continue;
            if (armed_only && types_[actors_[i].type].weapon < 0) continue;
            if (length(actors_[i].pos - at) <= r) out.push_back(actors_[i].id);
        }
        return out;
    };
    auto target_valid = [&]() { return is_enemy(index_of(s.target)); };
    auto attack_move_all = [&](CPos goal) {
        std::vector<int32_t> v = line_units();
        if (!v.empty()) order_attack_move(v.data(), v.size(), goal);
    };


    auto target_cell = [&]() -> CPos {
        if (s.storm && s.goal_target >= 0) {
            const int gi = index_of(s.goal_target);
            if (gi >= 0 && actors_[gi].alive) return types_[actors_[gi].type].building ? actors_[gi].origin : mobiles_[gi].cell;
        }
        const int ti = index_of(s.target);
        if (ti < 0) return mobiles_[li].cell;
        return types_[actors_[ti].type].building ? actors_[ti].origin : mobiles_[ti].cell;
    };


    auto change_state = [&](BotSquad::State next) {
        s.state = next;
        s.leader = -1;
        s.last_updated = tick_;
        s.last_leader_cell = CPos{-1, -1};
        s.last_target = -1;
    };


    auto flee = [&]() {
        CPos home = s.gather;
        if (home.x < 0) {

            const WVec c = centroid();
            int64_t best = INT64_MAX;
            int32_t best_id = -1;
            for (const Actor& a : actors_) {
                if (!a.alive || a.owner != owner || !types_[a.type].building) continue;
                const int64_t d = length(a.pos - c);
                if (d < best || (d == best && best_id >= 0 && a.id < best_id)) { best = d; best_id = a.id; home = a.origin; }
            }
        }
        if (home.x >= 0 && !s.units.empty()) order_move(s.units.data(), s.units.size(), home);
        if (s.type == BotSquad::PROTECTION) {
            change_state(BotSquad::IDLE);
            for (int32_t id : s.units) {
                b.active_units.erase(std::remove(b.active_units.begin(), b.active_units.end(), id), b.active_units.end());
            }
            s.units.clear();
            s.dead = true;
            return;
        }
        s.gather = home;
        s.target = -1;
        s.storm = false;
        change_state(BotSquad::GATHER);
        s.gather_start = tick_;
        s.regen_until = tick_ + uint32_t(std::max(0, p.regen_ticks));
    };

    auto should_flee = [&]() -> bool {
        const WVec c = centroid();
        if (s.units.empty()) return false;
        const int64_t r = int64_t(p.danger_scan_radius) * CELL;
        for (const Actor& a : actors_) {
            if (a.alive && a.owner == owner && types_[a.type].building && length(a.pos - c) <= r) return false;
        }
        const std::vector<int32_t> enemies = enemies_near(c, p.danger_scan_radius, true);
        if (enemies.empty()) return false;
        return !bot_can_attack(s.units, enemies, false);
    };
    auto note_progress = [&]() {
        if (!(mobiles_[li].cell == s.last_leader_cell)) { s.last_leader_cell = mobiles_[li].cell; s.last_updated = tick_; }
        if (s.target != s.last_target) { s.last_target = s.target; s.last_updated = tick_; }
    };


    auto focus_fire = [&](WVec c) -> bool {
        const int32_t focus = bot_focus_target(owner, s, c);
        if (focus < 0) return false;
        std::vector<int32_t> v = line_units();
        if (v.empty()) return false;
        order_attack(v.data(), v.size(), focus, false);
        return true;
    };


    if (s.vorhaben == VH_EXPANSION_GUARD) {
        int32_t yard = -1;
        int64_t best = INT64_MAX;
        for (const Actor& a : actors_) {
            if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].base_provider) continue;
            const int64_t d = s.gather.x >= 0 ? bot_cell_d2(a.origin, s.gather) : 0;
            if (d < best || (d == best && yard >= 0 && a.id < yard)) { best = d; yard = a.id; }
        }
        if (yard < 0) { bot_vorhaben_end(owner, VH_EXPANSION_GUARD, false); return; }
        order_guard(s.units.data(), s.units.size(), yard);
        return;
    }

    if (s.type == BotSquad::PROTECTION) {


        const int32_t backoff_max = p.allow_counterattack ? 4 : 1;


        if (s.protect_since == 0) s.protect_since = tick_;
        if (tick_ > s.protect_since + PROTECT_MAX_TICKS) { flee(); return; }
        if (!target_valid()) {
            s.target = closest_enemy(actors_[li].pos, int64_t(p.protection_scan_radius) * CELL);
            if (s.target < 0) { flee(); return; }
            s.backoff = backoff_max;
        }
        const int ti = index_of(s.target);


        if (ti >= 0) {
            const UnitType& tt = types_[actors_[ti].type];
            if (tt.aircraft) { flee(); return; }
            const bool on_water = !tt.building && (tt.locomotor == LOCO_NAVAL || tt.locomotor == LOCO_LCRAFT ||
                                                   !map_.passable(mobiles_[ti].cell, MC_LAND));
            if (on_water) {
                std::vector<uint8_t> reach;
                bot_land_reach(mobiles_[li].cell, reach);
                std::vector<int32_t> keep;
                for (int32_t id : s.units) {
                    const int i = index_of(id);
                    if (i < 0) continue;
                    CPos fc;
                    if (bot_shore_firing_cell(size_t(i), size_t(ti), reach, fc)) {
                        keep.push_back(id);
                        order_attack_move(&id, 1, fc);
                    } else {

                        b.active_units.erase(std::remove(b.active_units.begin(), b.active_units.end(), id), b.active_units.end());
                    }
                }
                s.units = keep;
                if (s.units.empty()) { flee(); return; }
                bot_squad_siege(owner, s);
                return;
            }
        }
        bool near_base = false;
        if (ti >= 0) {
            const int64_t r = int64_t(p.protection_scan_radius) * CELL;
            for (const Actor& a : actors_) {
                if (a.alive && a.owner == owner && types_[a.type].building && length(a.pos - actors_[ti].pos) <= r) {
                    near_base = true;
                    break;
                }
            }
        }
        if (near_base) {
            s.backoff = backoff_max;
        } else if (--s.backoff <= 0) {
            flee();
            return;
        }
        attack_move_all(target_cell());
        bot_squad_siege(owner, s);
        return;
    }

    switch (s.state) {
    case BotSquad::GATHER: {

        if (s.gather.x < 0 || !map_.in_bounds(s.gather)) {
            CPos g{-1, -1};

            if (bot_gather_point(owner, mobiles_[li].cell, g, s.gather_side)) s.gather = g;
            else if (!bot_base_center(owner, s.gather)) {

                s.target = squad_target(centroid());
                if (s.target < 0) return;
                change_state(BotSquad::ATTACK_MOVE);
                s.siege_start = tick_;
                return;
            }
            s.gather_start = tick_;
        }


        std::vector<int32_t> movers;
        int32_t ready = 0, alive = 0;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0) continue;
            ++alive;
            if (bot_cell_d2(mobiles_[i].cell, s.gather) <= GATHER_NEAR_D2) { ++ready; continue; }
            if (!mobiles_[i].moving || mobiles_[i].goal != s.gather) movers.push_back(id);
        }
        if (!movers.empty()) order_move(movers.data(), movers.size(), s.gather);
        if (alive <= 0) return;
        if (tick_ < s.regen_until) return;


        if (tick_ < s.storm_at) return;
        const bool enough = ready * 100 >= alive * GATHER_READY_PERCENT;
        const bool timeout = tick_ > s.gather_start + uint32_t(std::max(1, p.gather_max_ticks));
        if (!enough && !timeout) return;
        s.target = squad_target(centroid());


        if (s.target < 0 && timeout) s.target = bot_pick_target(owner, centroid(), 0, true);
        if (s.target < 0) {
            if (timeout) { s.gather = CPos{-1, -1}; s.gather_start = tick_; }
            return;
        }
        change_state(BotSquad::ATTACK_MOVE);
        s.siege_start = tick_;
        s.storm = false;
        break;
    }
    case BotSquad::IDLE: {
        if (!target_valid()) {
            elect_leader();
            const int lj = index_of(s.leader);
            if (lj < 0) return;
            s.target = squad_target(actors_[lj].pos);
            if (s.target < 0) return;
        }
        const int ti = index_of(s.target);
        const std::vector<int32_t> enemies = enemies_near(actors_[ti].pos, p.idle_scan_radius, false);
        if (enemies.empty()) return;
        if (bot_can_attack(s.units, enemies, false)) {
            attack_move_all(target_cell());
            change_state(BotSquad::ATTACK_MOVE);
            s.siege_start = tick_;
        } else {
            flee();
        }
        break;
    }
    case BotSquad::ATTACK_MOVE: {


        if (s.vorhaben == VH_COUNTERATTACK && s.gather.x >= 0 &&
            bot_cell_d2(mobiles_[li].cell, s.gather) <= 36) {
            bot_vorhaben_end(owner, VH_COUNTERATTACK, true);
            s.gather = CPos{-1, -1};
            change_state(BotSquad::GATHER);
            s.gather_start = tick_;
            return;
        }
        if (!target_valid()) {
            elect_leader();
            const int lj = index_of(s.leader);
            if (lj < 0) return;
            s.target = squad_target(actors_[lj].pos);
            if (s.target < 0) { flee(); return; }
        }
        note_progress();
        if (tick_ > s.last_updated + STALL_TICKS) { change_state(BotSquad::IDLE); return; }
        const WVec c = centroid();


        if (!s.storm) {
            const int32_t front = bot_front_target(owner, c, int64_t(p.attack_scan_radius) * CELL);
            const int fi = front >= 0 ? index_of(front) : -1;
            const bool defense_left = fi >= 0 && types_[actors_[fi].type].building && types_[actors_[fi].type].defense;
            if (!defense_left || tick_ > s.siege_start + SIEGE_STALL_TICKS) s.storm = true;
        }

        const int64_t r = int64_t(s.units.size()) * CELL / 3;
        std::vector<int32_t> stragglers;
        for (int32_t id : s.units) {
            const int i = index_of(id);
            if (i < 0 || is_siege_id(id)) continue;
            if (length(actors_[i].pos - actors_[li].pos) > r) stragglers.push_back(id);
        }
        if (!stragglers.empty() && !is_siege_id(s.leader)) {
            order_stop(&s.leader, 1);
            order_attack_move(stragglers.data(), stragglers.size(), mobiles_[li].cell);
        } else if (!focus_fire(c)) {
            const int32_t near = squad_target(actors_[li].pos);
            const int ni = near >= 0 ? index_of(near) : -1;
            if (ni >= 0 && length(actors_[ni].pos - actors_[li].pos) <= int64_t(p.attack_scan_radius) * CELL) {
                s.target = near;
                change_state(BotSquad::ATTACK);
            } else {
                attack_move_all(target_cell());
            }
        }


        bot_squad_siege(owner, s);
        if (should_flee()) flee();
        break;
    }
    case BotSquad::ATTACK: {
        if (!target_valid()) {
            elect_leader();
            const int lj = index_of(s.leader);
            if (lj < 0) return;
            s.target = squad_target(actors_[lj].pos);
            if (s.target < 0) { flee(); return; }
            change_state(BotSquad::ATTACK_MOVE);
            return;
        }
        note_progress();
        if (tick_ > s.last_updated + STALL_TICKS) { change_state(BotSquad::IDLE); return; }
        const WVec c = centroid();
        if (!focus_fire(c)) {


            std::vector<int32_t> free_units;
            for (int32_t id : line_units()) {
                const int i = index_of(id);
                if (i >= 0 && combats_[i].target < 0) free_units.push_back(id);
            }
            if (!free_units.empty()) order_attack_move(free_units.data(), free_units.size(), target_cell());
        }
        bot_squad_siege(owner, s);
        if (should_flee()) flee();
        break;
    }
    case BotSquad::FLEE:
        flee();
        break;
    }
}

}
