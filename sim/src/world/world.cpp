#include <algorithm>
#include <climits>

#include "ra/sim.h"

namespace ra {


constexpr int32_t WAIT_AVERAGE = 40;

constexpr int32_t REPATH_RADIUS = 12;


constexpr WAngle DRIVE_TOLERANCE = 0;

void Map::reset(int width, int height, const uint8_t* cost) {
    w_ = width;
    h_ = height;
    cost_[MC_LAND].assign(cost, cost + width * height);

    for (int mc = 1; mc < NUM_MOVE_CLASSES; ++mc) cost_[mc].assign(size_t(width * height), 0);
    terrain_.clear();
    base_terrain_.clear();
}


int32_t terrain_speed(int32_t locomotor, int32_t terrain) {
    static const int32_t T[NUM_LOCOMOTORS][NUM_TERRAIN] = {
        {100, 89, 111, 111, 89, 89, 89, 0, 0, 0, 0, 0},
        {100, 50, 125, 125, 88, 88, 50, 0, 0, 0, 0, 0},
        {100, 88, 125, 125, 88, 88, 88, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 0, 100, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0, 70, 100, 0, 0, 0, 0},
    };
    if (locomotor < 0 || locomotor >= NUM_LOCOMOTORS || terrain < 0 || terrain >= NUM_TERRAIN) return 0;
    return T[locomotor][terrain];
}

uint8_t Map::cost_for_terrain(int32_t terrain, int32_t mc) {
    const int32_t spd = terrain_speed(move_class_locomotor(mc), terrain);
    return spd > 0 ? static_cast<uint8_t>(std::max(1, 100 * 100 / spd)) : 0;
}

void Map::set_terrain(int width, int height, const uint8_t* terrain) {
    w_ = width;
    h_ = height;
    terrain_.assign(terrain, terrain + width * height);
    base_terrain_ = terrain_;
    for (int mc = 0; mc < NUM_MOVE_CLASSES; ++mc) {
        cost_[mc].resize(size_t(width * height));
        for (size_t i = 0; i < cost_[mc].size(); ++i) cost_[mc][i] = cost_for_terrain(terrain_[i], mc);
    }
}


void Map::rebuild_water_costs() {
    if (terrain_.empty()) return;
    for (int mc = 1; mc < NUM_MOVE_CLASSES; ++mc) {
        cost_[mc].assign(cost_[MC_LAND].size(), 0);
        for (size_t i = 0; i < cost_[mc].size(); ++i) {
            const bool blocked = cost_[MC_LAND][i] == 0 && cost_for_terrain(terrain_[i], MC_LAND) != 0;
            cost_[mc][i] = blocked ? 0 : cost_for_terrain(terrain_[i], mc);
        }
    }
}

void Map::restore_cost_layer(int32_t mc, std::vector<uint8_t> cost) {
    if (mc < 0 || mc >= NUM_MOVE_CLASSES) return;
    cost_[mc] = std::move(cost);
    cost_[mc].resize(size_t(w_) * size_t(h_), 0);
}


void Map::set_terrain_at(CPos c, int32_t t) {
    if (!in_bounds(c) || terrain_.empty()) return;
    const int i = index(c);
    if (terrain_[i] == uint8_t(t)) return;
    terrain_[i] = static_cast<uint8_t>(t);
    for (int mc = 0; mc < NUM_MOVE_CLASSES; ++mc)
        if (cost_[mc][i] != 0) cost_[mc][i] = cost_for_terrain(t, mc);
}


void Map::set_base_terrain_at(CPos c, int32_t t, bool update_cost) {
    if (!in_bounds(c) || terrain_.empty()) return;
    const int i = index(c);
    terrain_[i] = static_cast<uint8_t>(t);
    if (!base_terrain_.empty()) base_terrain_[i] = static_cast<uint8_t>(t);


    if (update_cost)
        for (int mc = 0; mc < NUM_MOVE_CLASSES; ++mc) cost_[mc][i] = cost_for_terrain(t, mc);
}

void Map::restore_cost(CPos c) {
    if (!in_bounds(c)) return;
    const int i = index(c);
    for (int mc = 0; mc < NUM_MOVE_CLASSES; ++mc)
        cost_[mc][i] = terrain_.empty() ? uint8_t(mc == MC_LAND ? 1 : 0) : cost_for_terrain(terrain_[i], mc);
}


void World::update_visibility(int32_t owner) {
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    std::vector<uint8_t>& vis = vis_[owner];
    std::vector<uint8_t>& seen = explored_[owner];
    const size_t cells = size_t(map_.cells());
    if (vis.size() != cells) vis.assign(cells, 0);
    if (seen.size() != cells) {


        seen.assign(cells, 0);
        for (size_t k = 0; k < cells && k < vis.size(); ++k) seen[k] = vis[k] != 0 ? 1 : 0;
    }


    if (vis_strong_.size() != cells) vis_strong_.assign(cells, 0);
    if (vis_weak_.size() != cells) vis_weak_.assign(cells, 0);
    if (gap_count_.size() != cells) gap_count_.assign(cells, 0);
    std::fill(vis_strong_.begin(), vis_strong_.end(), uint8_t(0));
    std::fill(vis_weak_.begin(), vis_weak_.end(), uint8_t(0));
    std::fill(gap_count_.begin(), gap_count_.end(), uint16_t(0));


    auto circle = [&](CPos c, int32_t range, std::vector<uint8_t>* flag, bool gap) {
        if (range <= 0) return;
        const int r = (range + CELL - 1) / CELL;
        const int64_t r2 = int64_t(range) * range;
        for (int dy = -r; dy <= r; ++dy) {
            for (int dx = -r; dx <= r; ++dx) {
                const int64_t d2 = int64_t(dx) * dx * CELL * CELL + int64_t(dy) * dy * CELL * CELL;
                if (d2 > r2) continue;
                const CPos p{c.x + dx, c.y + dy};
                if (!map_.in_bounds(p)) continue;
                const size_t idx = size_t(map_.index(p));
                if (gap) ++gap_count_[idx]; else (*flag)[idx] = 1;
            }
        }
    };


    for (size_t k = 0; k + 2 < reveals_.size(); k += 3) {
        if (!allied(owner, reveals_[k].x)) continue;
        circle(reveals_[k + 1], reveals_[k + 2].x * CELL, &vis_strong_, false);
    }
    auto footprint_circles = [&](size_t i, int32_t range, std::vector<uint8_t>* flag, bool gap) {
        const Actor& a = actors_[i];
        const UnitType& t = types_[a.type];
        if (range <= 0) return;
        if (t.building) {
            for (int y = 0; y < t.foot_h; ++y)
                for (int x = 0; x < t.foot_w; ++x)
                    if (t.footprint[size_t(y * t.foot_w + x)])
                        circle(CPos{a.origin.x + x, a.origin.y + y}, range, flag, gap);
        } else {
            circle(mobiles_[i].cell, range, flag, gap);
        }
    };
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!in_world(i)) continue;
        const UnitType& t = types_[a.type];
        if (allied(owner, a.owner)) {
            if (t.reveal_range > 0) {

                footprint_circles(i, t.reveal_range, &vis_weak_, false);

                footprint_circles(i, std::min(t.reveal_gap_range, t.reveal_range), &vis_strong_, false);
            }
            continue;
        }


        if (t.creates_shroud_range <= 0) continue;


        if (t.needs_power && !powered(i)) continue;
        if (a.make_ticks > 0) continue;
        footprint_circles(i, t.creates_shroud_range, nullptr, true);
    }


    for (size_t k = 0; k < cells; ++k) {
        if (vis_strong_[k] || vis_weak_[k]) seen[k] = 1;
        if (!seen[k]) { vis[k] = 0; continue; }
        if (!vis_strong_[k] && gap_count_[k] > 0) { vis[k] = 0; continue; }
        vis[k] = (!fog_enabled_ || vis_strong_[k] || vis_weak_[k]) ? 2 : 1;
    }


    if (seen_mask_.size() < actors_.size()) seen_mask_.resize(actors_.size(), 0);
    if (live_mask_.size() < actors_.size()) live_mask_.resize(actors_.size(), 0);
    const uint32_t bit = 1u << owner;
    std::vector<Frozen>& frozen = frozen_[owner];
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        const UnitType& t = types_[a.type];
        if (!t.building) continue;
        bool live = false;
        for (int y = 0; y < t.foot_h && !live; ++y) {
            for (int x = 0; x < t.foot_w; ++x) {
                const CPos c{a.origin.x + x, a.origin.y + y};
                if (map_.in_bounds(c) && vis[map_.index(c)] == 2) { live = true; break; }
            }
        }
        const bool was_live = (live_mask_[i] & bit) != 0;
        if (live) {
            if (a.alive) { seen_mask_[i] |= bit; live_mask_[i] |= bit; }
            else live_mask_[i] &= ~bit;
            for (size_t k = 0; k < frozen.size(); ++k) {
                if (frozen[k].id != a.id) continue;
                frozen[k] = frozen.back();
                frozen.pop_back();
                break;
            }
            continue;
        }
        live_mask_[i] &= ~bit;
        if (!was_live || !a.alive) continue;
        Frozen f{};
        f.id = a.id;
        f.type = a.type;
        f.owner = a.owner;
        f.origin = a.origin;
        f.pos = a.pos;
        f.facing = a.facing;
        f.hp_permille = t.hp > 0 ? int32_t(int64_t(a.hp) * 1000 / t.hp) : 0;
        f.wall_mask = 0;
        if (t.wall) {
            static const int dx[4] = {0, 1, 0, -1}, dy[4] = {-1, 0, 1, 0};
            for (int d = 0; d < 4; ++d) {
                const CPos n{a.origin.x + dx[d], a.origin.y + dy[d]};
                if (!map_.in_bounds(n)) continue;
                const int32_t o = slot_at(map_.index(n), SUB_FULL);
                if (o >= 0 && size_t(o) < actors_.size() && actors_[size_t(o)].alive
                    && types_[actors_[size_t(o)].type].wall)
                    f.wall_mask |= 1 << d;
            }
        }
        bool replaced = false;
        for (Frozen& old : frozen) {
            if (old.id != f.id) continue;
            old = f;
            replaced = true;
            break;
        }
        if (!replaced) frozen.push_back(f);
    }
}

bool World::frozen_lit(int32_t viewer, const Frozen& f) const {
    if (viewer < 0 || viewer >= MAX_PLAYERS) return false;
    const std::vector<uint8_t>& vis = vis_[viewer];
    if (vis.size() != size_t(map_.cells())) return true;
    const UnitType& t = types_[size_t(f.type)];
    for (int y = 0; y < t.foot_h; ++y) {
        for (int x = 0; x < t.foot_w; ++x) {
            const CPos c{f.origin.x + x, f.origin.y + y};
            if (map_.in_bounds(c) && vis[size_t(map_.index(c))] != 0) return true;
        }
    }
    return false;
}

bool World::frozen_has(int32_t viewer, int32_t id) const {
    if (viewer < 0 || viewer >= MAX_PLAYERS) return false;
    for (const Frozen& f : frozen_[viewer])
        if (f.id == id) return frozen_lit(viewer, f);
    return false;
}


void World::apply_frozen(int32_t viewer, RenderActor* out, size_t n) const {
    if (viewer < 0 || viewer >= MAX_PLAYERS || out == nullptr) return;
    for (const Frozen& f : frozen_[viewer]) {
        const int i = index_of(f.id);
        if (i < 0 || size_t(i) >= n) continue;
        RenderActor& r = out[size_t(i)];
        if (!frozen_lit(viewer, f)) { r.visible = 0; continue; }
        r.type = f.type;
        r.owner = f.owner;
        r.disguise_type = -1;
        r.disguise_owner = -1;
        r.x = f.pos.x;
        r.y = f.pos.y;
        r.facing = f.facing;
        r.hp_permille = f.hp_permille;
        r.wall_mask = uint8_t(f.wall_mask);
        r.alive = 1;
        r.visible = 1;
        r.moving = 0;
        r.firing = 0;
        r.reloading = 0;
        r.fire_frame = 0;
        r.activity = ACT_NONE;
        r.make_ticks = 0;
        r.door_ticks = 0;
        r.repairing = 0;
        r.selling = 0;
        r.primary = 0;
        r.unpowered = 0;
        r.cloaked = 0;
        r.demolishing = 0;
        r.invulnerable = 0;
        r.altitude = 0;
        r.passengers = 0;
    }
}


bool World::has_active_radar(int32_t owner) const {
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].provides_radar) continue;
        if (a.make_ticks > 0 || !powered(i)) continue;
        if (!actor_jammed(a.id)) return true;
    }
    return false;
}

bool World::gps_granted(int32_t viewer) const {
    if (viewer < 0 || viewer >= MAX_PLAYERS) return false;
    for (int32_t p = 0; p < MAX_PLAYERS; ++p) {
        if (p != viewer && !allied(viewer, p)) continue;
        if (((gps_launched_ >> p) & 1u) == 0) continue;


        bool has_power = false;
        for (size_t i = 0; i < actors_.size(); ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || a.owner != p || a.make_ticks > 0) continue;
            const UnitType& t = types_[a.type];
            if (t.support_power != SP_GPS) continue;
            if (t.needs_power && !powered(i)) continue;
            has_power = true;
            break;
        }
        if (has_power && has_active_radar(p)) return true;
    }
    return false;
}

void World::gps_dots(int32_t viewer, std::vector<GpsDotInfo>& out) const {
    out.clear();
    if (!gps_granted(viewer)) return;
    const std::vector<uint8_t>& vis = vis_[viewer];
    if (vis.size() != size_t(map_.cells())) return;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || !in_world(i)) continue;
        const UnitType& t = types_[a.type];


        if (!t.gps_dot) continue;


        const int32_t eff = a.disguise_owner >= 0 ? a.disguise_owner : a.owner;
        if (eff == viewer || allied(viewer, eff)) continue;
        const CPos c = t.building ? to_cell(a.pos) : mobiles_[i].cell;
        if (!map_.in_bounds(c)) continue;

        if (vis[size_t(map_.index(c))] != 1) continue;


        if (cloaked(i) && !detected_by(viewer, i)) continue;

        if (t.building && frozen_has(viewer, a.id)) continue;
        out.push_back(GpsDotInfo{a.pos, eff, t.building ? 1 : 0});
    }
}

bool World::explored(int32_t owner, CPos c) const {
    if (owner < 0 || owner >= MAX_PLAYERS || !map_.in_bounds(c)) return false;
    const std::vector<uint8_t>& seen = explored_[owner];
    if (seen.size() != size_t(map_.cells())) return vis_[owner].empty() ? true : vis_[owner][size_t(map_.index(c))] != 0;
    return seen[size_t(map_.index(c))] != 0;
}


bool World::shroud_generated(int32_t owner, CPos c) const {
    if (owner < 0 || owner >= MAX_PLAYERS || !map_.in_bounds(c)) return false;
    return explored(owner, c) && !vis_[owner].empty() && vis_[owner][size_t(map_.index(c))] == 0;
}


bool World::actor_jammed(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[size_t(i)].alive) return false;
    const Actor& target = actors_[size_t(i)];
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& j = actors_[k];
        if (!j.alive || k == size_t(i)) continue;
        const UnitType& jt = types_[j.type];
        if (jt.jammer_range <= 0) continue;
        if (j.inside || j.transport >= 0) continue;
        if (j.owner == target.owner || allied(j.owner, target.owner)) continue;
        const WVec d = j.pos - target.pos;
        if (int64_t(d.x) * d.x + int64_t(d.y) * d.y <= int64_t(jt.jammer_range) * jt.jammer_range)
            return true;
    }
    return false;
}

bool World::radar_jammed(int32_t owner) const {
    bool any = false;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || !types_[a.type].provides_radar) continue;
        if (a.make_ticks > 0 || !powered(i)) continue;
        any = true;
        if (!actor_jammed(a.id)) return false;
    }
    return any;
}


void World::reveal(int32_t owner, CPos c, int32_t radius) {
    reveal_source(owner, c, radius);
}


int32_t World::reveal_source(int32_t owner, CPos c, int32_t radius) {
    const int32_t id = next_id_++;
    reveals_.push_back(CPos{owner, 0});
    reveals_.push_back(c);
    reveals_.push_back(CPos{radius, 0});
    reveal_ids_.push_back(id);
    for (int32_t p = 0; p < MAX_PLAYERS; ++p) if (allied(p, owner)) update_visibility(p);
    return id;
}

void World::remove_reveal_source(int32_t id) {
    for (size_t k = 0; k < reveal_ids_.size(); ++k) {
        if (reveal_ids_[k] != id) continue;
        const int32_t owner = reveals_[k * 3].x;
        reveals_.erase(reveals_.begin() + long(k) * 3, reveals_.begin() + long(k) * 3 + 3);
        reveal_ids_.erase(reveal_ids_.begin() + long(k));
        for (int32_t p = 0; p < MAX_PLAYERS; ++p) if (allied(p, owner)) update_visibility(p);
        return;
    }
}


void World::set_stance(int32_t id, int32_t stance) {
    const int i = index_of(id);
    if (i < 0) return;
    combats_[i].stance = std::max(0, std::min(int(STANCE_ATTACK_ANYTHING), stance));
    if (combats_[i].stance == STANCE_HOLD_FIRE) combats_[i].target = -1;
}

int32_t World::stance(int32_t id) const {
    const int i = index_of(id);
    return i < 0 ? STANCE_DEFEND : combats_[i].stance;
}


void World::queue_order(const int32_t* ids, size_t n, const QueuedOrder& o) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || types_[actors_[i].type].building) continue;
        order_queue_[size_t(i)].push_back(o);
    }
}


void World::step_order_queue() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (order_queue_[i].empty()) continue;
        const Actor& a = actors_[i];
        if (!a.alive) { order_queue_[i].clear(); continue; }
        const Mobile& m = mobiles_[i];
        const Combat& c = combats_[i];
        if (m.moving || m.in_transit || c.target >= 0 || c.attack_move || c.guard >= 0) continue;
        const QueuedOrder o = order_queue_[i].front();


        std::vector<QueuedOrder> rest(order_queue_[i].begin() + 1, order_queue_[i].end());
        const int32_t id = a.id;
        switch (o.kind) {
        case QueuedOrder::ATTACK_MOVE: order_attack_move(&id, 1, o.cell); break;
        case QueuedOrder::ATTACK: order_attack(&id, 1, o.target, o.force); break;
        case QueuedOrder::GUARD: order_guard(&id, 1, o.target); break;
        case QueuedOrder::HARVEST: order_harvest(&id, 1, o.cell); break;
        default: order_move(&id, 1, o.cell, o.near_enough); break;
        }
        order_queue_[i] = rest;
    }
}

bool World::actor_visible_to(int32_t viewer, size_t i) const {
    const Actor& a = actors_[i];


    if (a.inside || a.transport >= 0) return false;
    if (a.owner == viewer || viewer < 0 || viewer >= MAX_PLAYERS) return true;

    if (cloaked(i) && !allied(viewer, a.owner) && !detected_by(viewer, i)) return false;
    const std::vector<uint8_t>& vis = vis_[viewer];
    if (vis.empty()) return true;
    const UnitType& t = types_[a.type];
    if (t.building) {


        if (!fog_enabled_) {
            for (int y = 0; y < t.foot_h; ++y)
                for (int x = 0; x < t.foot_w; ++x) {
                    const CPos c{a.origin.x + x, a.origin.y + y};
                    if (map_.in_bounds(c) && vis[size_t(map_.index(c))] > 0) return true;
                }
            return false;
        }


        return size_t(i) < seen_mask_.size() && ((seen_mask_[i] >> viewer) & 1u) != 0;
    }
    const CPos c = mobiles_[i].cell;
    return map_.in_bounds(c) && vis[map_.index(c)] == 2;
}


int32_t World::speed_at(size_t i) const {
    const UnitType& t = types_[actors_[i].type];
    const Mobile& m = mobiles_[i];
    const int32_t pct = terrain_speed(t.locomotor, map_.terrain(m.in_transit ? m.to_cell : m.cell));
    int32_t speed = t.speed * (pct > 0 ? pct : 100) / 100;

    if (t.harvester && t.capacity > 0) {
        const int32_t fullness = std::min(100, harvests_[i].bales * 100 / t.capacity);
        speed = speed * (100 - (100 - t.fully_loaded_speed) * fullness / 100) / 100;
    }

    if (actors_[i].prone_ticks > 0) speed = speed * t.prone_speed / 100;

    speed = speed * rank_bonus(i).speed / 100;
    return std::max(1, speed);
}


void World::set_rng_seed(uint32_t seed) { rng_ = seed != 0 ? seed : 0x2545F491u; }


void World::set_visibility_players(uint32_t mask) {
    vis_players_ = mask;
    for (int32_t p = 0; p < MAX_PLAYERS; ++p)
        if ((mask >> p) & 1u) update_visibility(p);
}


void World::set_fog_enabled(bool on) {
    if (fog_enabled_ == on) return;
    fog_enabled_ = on;
    for (int32_t p = 0; p < MAX_PLAYERS; ++p)
        if ((vis_players_ >> p) & 1u) update_visibility(p);
}

uint32_t World::rand() {

    rng_ ^= rng_ << 13;
    rng_ ^= rng_ >> 17;
    rng_ ^= rng_ << 5;
    return rng_;
}

void World::set_terrain(int width, int height, const uint8_t* terrain) {
    map_.set_terrain(width, height, terrain);
    init_layers();
}

void World::set_map(int width, int height, const uint8_t* cost) {
    map_.reset(width, height, cost);
    init_layers();
}


void World::init_layers() {
    for (auto& v : vis_) v.assign(map_.cells(), 0);
    for (auto& v : explored_) v.assign(map_.cells(), 0);
    for (auto& f : frozen_) f.clear();
    live_mask_.clear();
    gps_launched_ = 0;
    cell_slots_.assign(size_t(map_.cells()) * CELL_SLOTS, -1);
    bib_owner_.assign(map_.cells(), -1);
    visit_stamp_.assign(map_.cells(), 0);
    parent_.assign(map_.cells(), -1);
    queue_.reserve(map_.cells());
    res_type_.assign(map_.cells(), RES_NONE);
    res_density_.assign(map_.cells(), 0);
    claims_.assign(map_.cells(), -1);
    rebuild_res_blocks();
    smudge_kind_.assign(map_.cells(), uint8_t(SMUDGE_NONE));
    smudge_variant_.assign(map_.cells(), 0);
    smudge_depth_.assign(map_.cells(), 0);
    ++smudge_version_;
    stamp_ = 0;
    fields_.clear();
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (actors_[i].alive && map_.in_bounds(mobiles_[i].cell))
            slot_at(map_.index(mobiles_[i].cell), mobiles_[i].sub) = static_cast<int32_t>(i);
    }
}


void World::set_smudge_sprites(int32_t kind, int32_t variants, int32_t depth) {
    if (kind <= SMUDGE_NONE || kind >= NUM_SMUDGE_KINDS) return;
    smudge_variants_[kind] = variants > 0 ? variants : 1;
    smudge_depths_[kind] = depth > 0 ? depth : 1;
}


void World::add_smudge(CPos c, int32_t kind) {
    if (!map_.in_bounds(c) || kind <= SMUDGE_NONE || kind >= NUM_SMUDGE_KINDS) return;
    if (smudge_kind_.size() != size_t(map_.cells())) return;
    const int idx = map_.index(c);
    if (smudge_kind_[idx] == SMUDGE_NONE) {

        smudge_kind_[idx] = uint8_t(kind);
        smudge_variant_[idx] = uint8_t(rand() % uint32_t(std::max(1, smudge_variants_[kind])));
        smudge_depth_[idx] = 0;
    } else {


        const int32_t old_kind = smudge_kind_[idx];
        const int32_t maxd = std::max(1, smudge_depths_[old_kind]);
        if (smudge_depth_[idx] + 1 >= maxd) return;
        smudge_depth_[idx] = uint8_t(smudge_depth_[idx] + 1);
    }
    ++smudge_version_;
}

void World::smudges(std::vector<SmudgeInfo>& out) const {
    out.clear();
    if (smudge_kind_.size() != size_t(map_.cells())) return;
    for (int i = 0; i < map_.cells(); ++i) {
        if (smudge_kind_[size_t(i)] == SMUDGE_NONE) continue;
        out.push_back({map_.cell_at(i), int32_t(smudge_kind_[size_t(i)]),
                       int32_t(smudge_variant_[size_t(i)]), int32_t(smudge_depth_[size_t(i)])});
    }
}

uint32_t World::smudge_count() const {
    uint32_t n = 0;
    for (uint8_t k : smudge_kind_) if (k != SMUDGE_NONE) ++n;
    return n;
}

int32_t World::define_type(const UnitType& t) {
    if (t.storage > 0) has_storage_ = true;
    types_.push_back(t);
    return static_cast<int32_t>(types_.size()) - 1;
}

int World::index_of(int32_t id) const {
    auto it = index_by_id_.find(id);
    return it == index_by_id_.end() ? -1 : it->second;
}

int32_t World::occupant(CPos c) const {
    if (!map_.in_bounds(c)) return -1;
    const int idx = map_.index(c);
    for (int s = 0; s < CELL_SLOTS; ++s)
        if (slot_at(idx, s) >= 0) return slot_at(idx, s);
    return -1;
}

int32_t World::occupant(CPos c, int sub) const {
    if (!map_.in_bounds(c) || sub < 0 || sub >= CELL_SLOTS) return -1;
    return slot_at(map_.index(c), sub);
}

bool World::cell_empty(CPos c) const { return occupant(c) == -1; }


int32_t World::free_subcell(CPos c, int preferred, int32_t self) const {
    if (!map_.in_bounds(c)) return SUB_INVALID;
    const int idx = map_.index(c);
    auto is_free = [&](int s) {
        const int32_t o = slot_at(idx, s);
        return o < 0 || o == self;
    };
    if (preferred >= SUB_FIRST && preferred <= NUM_SUBCELLS && is_free(preferred)) return preferred;
    for (int s = SUB_FIRST; s <= NUM_SUBCELLS; ++s)
        if (s != preferred && is_free(s)) return s;
    return SUB_INVALID;
}


int32_t World::blocker_at(CPos c, size_t mover) const {
    if (!map_.in_bounds(c)) return -1;
    const int idx = map_.index(c);
    const int32_t self = static_cast<int32_t>(mover);
    const int32_t full = slot_at(idx, SUB_FULL);
    if (full >= 0 && full != self && !crushable_by(full, mover)) return full;
    if (shares_cell(actors_[mover].type)) {
        int32_t first = -1;
        for (int s = SUB_FIRST; s <= NUM_SUBCELLS; ++s) {
            const int32_t o = slot_at(idx, s);
            if (o < 0 || o == self || crushable_by(o, mover)) return -1;
            if (first < 0) first = o;
        }
        return first;
    }
    for (int s = SUB_FIRST; s <= NUM_SUBCELLS; ++s) {
        const int32_t o = slot_at(idx, s);
        if (o >= 0 && o != self && !crushable_by(o, mover)) return o;
    }
    return -1;
}

bool World::cell_free(CPos c, int32_t self) const {

    const int32_t mc = (self >= 0 && size_t(self) < actors_.size()) ? actor_move_class(size_t(self)) : int32_t(MC_LAND);
    if (!map_.passable(c, mc)) return false;
    if (self < 0 || size_t(self) >= actors_.size()) return occupant(c) == -1;
    return blocker_at(c, size_t(self)) < 0;
}


CPos World::find_free_cell(CPos near, int32_t type) {
    const bool shares = type >= 0 && type < int32_t(types_.size()) && shares_cell(type);
    const int32_t mc = type_move_class(type);
    auto ok = [&](CPos c) {
        if (!map_.passable(c, mc)) return false;
        if (!shares) return occupant(c) == -1;
        return slot_at(map_.index(c), SUB_FULL) < 0 && free_subcell(c, SUB_DEFAULT, -1) != SUB_INVALID;
    };
    if (ok(near)) return near;
    for (int r = 1; r < 32; ++r) {
        for (int dy = -r; dy <= r; ++dy) {
            for (int dx = -r; dx <= r; ++dx) {
                if (dx != -r && dx != r && dy != -r && dy != r) continue;
                const CPos c{near.x + dx, near.y + dy};
                if (map_.in_bounds(c) && ok(c)) return c;
            }
        }
    }
    return near;
}


CPos World::find_adjacent_cell(CPos c, int32_t type) const {
    const bool shares = type >= 0 && type < int32_t(types_.size()) && shares_cell(type);
    const int32_t mc = type_move_class(type);
    static const int dxs[8] = {-1, 1, -1, 1, -1, 0, 1, 0};
    static const int dys[8] = {-1, -1, 1, 1, 0, -1, 0, 1};
    for (int k = 0; k < 8; ++k) {
        const CPos n{c.x + dxs[k], c.y + dys[k]};
        if (!map_.in_bounds(n) || !map_.passable(n, mc)) continue;
        if (shares) {
            if (slot_at(map_.index(n), SUB_FULL) < 0 && free_subcell(n, SUB_DEFAULT, -1) != SUB_INVALID) return n;
        } else if (occupant(n) == -1) {
            return n;
        }
    }
    return CPos{-1, -1};
}


CPos World::find_exit_cell(CPos c, int32_t type) {
    static const int dxs[8] = {-1, 1, -1, 1, -1, 0, 1, 0};
    static const int dys[8] = {-1, -1, 1, 1, 0, -1, 0, 1};
    int order[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    for (int k = 7; k > 0; --k) {
        const int j = static_cast<int>(rand() % uint32_t(k + 1));
        std::swap(order[k], order[j]);
    }
    const bool shares = type >= 0 && type < int32_t(types_.size()) && shares_cell(type);
    const int32_t mc = type_move_class(type);
    for (int k = 0; k < 8; ++k) {
        const CPos n{c.x + dxs[order[k]], c.y + dys[order[k]]};
        if (!map_.in_bounds(n) || !map_.passable(n, mc)) continue;
        if (shares) {
            if (slot_at(map_.index(n), SUB_FULL) < 0 && free_subcell(n, SUB_DEFAULT, -1) != SUB_INVALID) return n;
        } else if (occupant(n) == -1) {
            return n;
        }
    }
    return CPos{-1, -1};
}


void World::clear_slots(size_t i) {
    const int32_t self = static_cast<int32_t>(i);
    const Mobile& m = mobiles_[i];
    for (const CPos c : {m.cell, m.to_cell}) {
        if (!map_.in_bounds(c)) continue;
        const int idx = map_.index(c);
        for (int s = 0; s < CELL_SLOTS; ++s)
            if (slot_at(idx, s) == self) slot_at(idx, s) = -1;
    }
}

int World::push_actor(const Actor& a, const Mobile& m) {
    Combat cb;
    cb.turret = a.facing;
    cb.turret2 = a.facing;
    cb.scan = static_cast<int32_t>(rand() % 8);
    cb.charges = types_[a.type].max_charges;
    cb.charge_wait = types_[a.type].initial_charge_delay;

    const bool bot_owner = a.owner >= 0 && a.owner < MAX_PLAYERS && players_[a.owner].bot.enabled;
    if (bot_owner) cb.stance = STANCE_ATTACK_ANYTHING;

    const int32_t want = bot_owner ? types_[a.type].initial_stance_ai : types_[a.type].initial_stance;
    if (want >= 0) cb.stance = want;
    if (types_[a.type].no_auto_target) cb.stance = STANCE_HOLD_FIRE;
    const int idx = static_cast<int>(actors_.size());
    actors_.push_back(a);
    actors_.back().cloak_timer = types_[a.type].cloak ? types_[a.type].cloak_initial_delay : 0;
    mobiles_.push_back(m);
    combats_.push_back(cb);
    detected_.push_back(0);
    harvests_.emplace_back();
    Air air;

    air.ammo = types_[a.type].ammo_max;
    airs_.push_back(air);
    cargo_.emplace_back();
    paradrop_lz_.push_back(CPos{-1, -1});
    paradrop_delay_.push_back(0);
    prev_pos_.push_back(a.pos);
    prev_facing_.push_back(a.facing);
    prev_turret_.push_back(cb.turret);
    prev_turret2_.push_back(cb.turret2);
    order_queue_.emplace_back();
    index_by_id_[a.id] = idx;
    return idx;
}

int32_t World::spawn(int32_t type, int32_t owner, CPos cell, WAngle facing, int32_t health_percent, bool airborne) {
    if (type < 0 || type >= static_cast<int32_t>(types_.size())) return -1;


    const bool air = types_[type].aircraft;
    const CPos c = air ? cell : find_free_cell(cell, type);


    if (!air && !types_[type].building && !map_.passable(c, type_move_class(type))) return -1;
    const int32_t sub = (!air && shares_cell(type))
        ? std::max(int32_t(SUB_FIRST), free_subcell(c, SUB_DEFAULT, -1)) : int32_t(SUB_FULL);
    Actor a;
    a.id = next_id_++;
    a.type = type;
    a.owner = owner;
    a.faction_owner = owner;


    a.pos = subcell_center(c, sub);


    a.facing = facing >= 0 ? wrap_angle(facing)
             : (types_[type].aircraft ? AIRCRAFT_INITIAL_FACING
                                      : static_cast<WAngle>(rand() % FULL_TURN));
    a.hp = std::max(1, types_[type].hp * std::min(100, std::max(1, health_percent)) / 100);
    a.origin = c;
    Mobile m;
    m.cell = c;
    m.to_cell = c;
    m.goal = c;
    m.sub = sub;
    m.to_sub = sub;
    const int idx = push_actor(a, m);
    if (air) {
        Air& ai = airs_[size_t(idx)];
        ai.alt = airborne ? types_[type].cruise_altitude : 0;
        ai.state = airborne ? Air::CRUISING : Air::TAKING_OFF;


        if (!airborne) {
            const int b = pad_below(size_t(idx));
            if (b >= 0) {
                ai.base = actors_[size_t(b)].id;
                ai.state = Air::LANDED;
                actors_[idx].pos = dock_pos(size_t(b));
                actors_[idx].facing = types_[actors_[size_t(b)].type].exit_facing;
                prev_pos_[size_t(idx)] = actors_[idx].pos;
                prev_facing_[size_t(idx)] = actors_[idx].facing;
            }
        }
    } else if (map_.in_bounds(c)) {
        slot_at(map_.index(c), sub) = idx;
    }
    return a.id;
}


bool World::teleport(int32_t id, CPos cell) {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive) return false;
    if (types_[actors_[i].type].building) return false;
    if (!map_.in_bounds(cell)) return false;
    const int32_t self = static_cast<int32_t>(i);
    Mobile& m = mobiles_[size_t(i)];


    clear_slots(size_t(i));
    const CPos c = cell_free(cell, self) ? cell : find_free_cell(cell, actors_[i].type);
    const int32_t sub = shares_cell(actors_[i].type)
        ? std::max(int32_t(SUB_FIRST), free_subcell(c, m.sub, self)) : int32_t(SUB_FULL);


    if (types_[actors_[i].type].harvester) release_claim(size_t(i));
    stop(size_t(i), true);
    m.in_transit = false;
    m.cell = c;
    m.to_cell = c;
    m.goal = c;
    m.sub = sub;
    m.to_sub = sub;
    actors_[i].pos = subcell_center(c, sub);
    if (map_.in_bounds(c)) slot_at(map_.index(c), sub) = self;
    return true;
}

void World::set_map_terrain(CPos c, int32_t terrain) {
    if (!map_.in_bounds(c)) return;
    const int idx = map_.index(c);
    const int32_t on_cell = slot_at(idx, SUB_FULL);
    const bool building_here = on_cell >= 0 && actors_[size_t(on_cell)].alive
        && types_[actors_[size_t(on_cell)].type].building;
    map_.set_base_terrain_at(c, terrain, !building_here);


    for (int sl = 0; sl < CELL_SLOTS; ++sl) {
        const int32_t o = slot_at(idx, sl);
        if (o < 0 || !actors_[size_t(o)].alive || types_[actors_[size_t(o)].type].building) continue;
        if (!map_.passable(c, actor_move_class(size_t(o)))) kill(size_t(o), DAMAGE_EXPLOSION);
    }
    fields_.clear();
}


int32_t World::spawn_building(int32_t type, int32_t owner, CPos origin, int32_t health_percent) {
    if (type < 0 || type >= static_cast<int32_t>(types_.size())) return -1;
    const UnitType& t = types_[type];
    if (!t.building) return -1;
    Actor a;
    a.id = next_id_++;
    a.type = type;
    a.owner = owner;
    a.faction_owner = owner;
    a.origin = origin;
    const int32_t sprite_h = t.sprite_h > 0 ? t.sprite_h : t.foot_h;
    a.pos = {origin.x * CELL + t.foot_w * CELL / 2, origin.y * CELL + sprite_h * CELL / 2};
    a.facing = 0;
    a.hp = std::max(1, t.hp * std::min(100, std::max(1, health_percent)) / 100);
    a.rally = CPos{origin.x + t.rally_dx, origin.y + t.rally_dy};
    Mobile m;
    m.cell = origin;
    m.to_cell = origin;
    m.goal = origin;
    const int idx = push_actor(a, m);
    for (int y = 0; y < t.foot_h; ++y) {
        for (int x = 0; x < t.foot_w; ++x) {
            const CPos c{origin.x + x, origin.y + y};
            if (!map_.in_bounds(c)) continue;
            if (!t.footprint[y * t.foot_w + x]) {
                if (t.build_block.size() > size_t(y * t.foot_w + x) && t.build_block[y * t.foot_w + x]) bib_owner_[map_.index(c)] = idx;
                continue;
            }
            slot_at(map_.index(c), SUB_FULL) = idx;
            map_.set_cost(c, 0);
        }
    }
    fields_.clear();
    return a.id;
}


static void reset_progress(Mobile& m) {
    if (!m.in_transit) m.progress = 0;
}


void World::set_move(size_t i, CPos goal, int32_t near_enough) {

    if (types_[actors_[i].type].aircraft) {
        mobiles_[i].goal = goal;
        mobiles_[i].moving = true;
        mobiles_[i].arrived = false;
        air_move(i, cell_center(goal), false);
        return;
    }
    if (!map_.in_bounds(goal)) return;
    const int32_t mc = actor_move_class(i);
    if (!map_.passable(goal, mc)) goal = find_free_cell(goal, actors_[i].type);
    Mobile& m = mobiles_[i];
    m.moving = true;
    m.arrived = false;
    m.goal = goal;
    m.field = fields_.get_or_build(map_, goal, mc);
    m.field_gen = fields_.generation();
    m.near_enough = near_enough;
    m.has_waited = false;
    m.wait = 0;
    m.is_blocking = false;
    m.near_cycles = 0;
    m.detour.clear();
    reset_progress(m);
}

void World::order_move(const int32_t* ids, size_t n, CPos goal, int32_t near_enough) {
    if (!map_.in_bounds(goal)) return;


    const CPos air_goal = goal;


    const CPos raw_goal = goal;
    if (!map_.passable(goal)) goal = find_free_cell(goal);


    int64_t cx = 0, cy = 0;
    size_t count = 0;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || types_[actors_[i].type].building) continue;
        cx += actors_[i].pos.x;
        cy += actors_[i].pos.y;
        ++count;
    }
    if (count == 0) return;
    cx /= static_cast<int64_t>(count);
    cy /= static_cast<int64_t>(count);
    const int32_t spacing = count > 1 ? (isqrt(static_cast<int64_t>(count)) * 3 + 2) / 4 : 0;

    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || types_[actors_[i].type].building) continue;
        const int32_t mc = actor_move_class(size_t(i));
        CPos sub = types_[actors_[i].type].aircraft ? air_goal : (mc == MC_LAND ? goal : raw_goal);
        if (spacing > 0 && !types_[actors_[i].type].aircraft) {
            const int64_t dx = actors_[i].pos.x - cx, dy = actors_[i].pos.y - cy;
            const int64_t band = int64_t(spacing) * CELL / 2;
            const int qx = dx > band ? 1 : (dx < -band ? -1 : 0);
            const int qy = dy > band ? 1 : (dy < -band ? -1 : 0);
            const CPos base_goal = mc == MC_LAND ? goal : raw_goal;
            sub = {base_goal.x + qx * spacing, base_goal.y + qy * spacing};
            if (!map_.in_bounds(sub) || !map_.passable(sub, mc)) sub = base_goal;
        }

        combats_[i].target = -1;
        combats_[i].attack_move = false;
        combats_[i].guard = -1;
        combats_[i].attack_cell = CPos{-1, -1};
        combats_[i].force_attack = false;
        order_queue_[size_t(i)].clear();
        cancel_unload(size_t(i));
        if (types_[actors_[i].type].harvester) {
            release_claim(i);
            harvests_[i].automated = false;
            harvests_[i].park = false;
            harvests_[i].dock_held = false;
            harvests_[i].queue_tick = -1;
            harvests_[i].has_wait = false;
            actors_[i].repair_depot = -1;
            actors_[i].being_repaired = false;
            harvests_[i].state = Harvest::IDLE;
        }
        set_move(i, sub, near_enough);
    }
}

void World::order_stop(const int32_t* ids, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0) continue;
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        combats_[i].guard = -1;
        combats_[i].attack_cell = CPos{-1, -1};
        combats_[i].force_attack = false;
        order_queue_[size_t(i)].clear();
        cancel_unload(size_t(i));
        if (types_[actors_[i].type].harvester) {
            release_claim(i);
            harvests_[i].automated = false;
            harvests_[i].park = false;
            harvests_[i].dock_held = false;
            harvests_[i].queue_tick = -1;
            harvests_[i].has_wait = false;
            actors_[i].repair_depot = -1;
            actors_[i].being_repaired = false;
            harvests_[i].state = Harvest::IDLE;
        }
        stop(i, false);
    }
}


void World::order_scatter(const int32_t* ids, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || types_[actors_[i].type].building) continue;
        Mobile& m = mobiles_[i];
        if (m.in_transit) continue;
        CPos out;
        if (!adjacent_free_cell(size_t(i), m.cell, out)) continue;
        m.moving = true;
        m.arrived = false;
        m.goal = out;
        m.field = -1;
        m.near_enough = 0;
        m.has_waited = false;
        m.wait = 0;
        m.is_blocking = false;
        m.near_cycles = 0;
        reset_progress(m);
        m.detour.clear();
    }
}

void World::stop(size_t i, bool arrived) {
    if (types_[actors_[i].type].aircraft) {
        airs_[i].has_goal = false;
        airs_[i].land_at_goal = 0;
        airs_[i].returning = false;
    }
    Mobile& m = mobiles_[i];
    m.moving = false;
    m.arrived = arrived;
    m.field = -1;
    reset_progress(m);
    m.has_waited = false;
    m.wait = 0;
    m.is_blocking = false;
    m.detour.clear();
}


bool World::crushable_by(int32_t blocker, size_t crusher) const {
    if (blocker < 0 || blocker == static_cast<int32_t>(crusher)) return false;


    if (types_[actors_[size_t(blocker)].type].mine) {
        const UnitType& ct = types_[actors_[crusher].type];
        return (types_[actors_[size_t(blocker)].type].crush_classes & ct.crushes) != 0 && !ct.mine_immune;
    }
    const Actor& b = actors_[blocker];
    if (!b.alive) return false;
    const UnitType& bt = types_[b.type];


    if (bt.building) return false;
    const UnitType& ct = types_[actors_[crusher].type];
    if ((bt.crush_classes & ct.crushes) == 0) return false;


    if (bt.crate) return true;
    return !allied(actors_[crusher].owner, b.owner);
}

void World::begin_transit(size_t i, CPos next) {
    Mobile& m = mobiles_[i];
    const int32_t self = static_cast<int32_t>(i);
    const int idx = map_.index(next);


    m.crush_count = 0;
    for (int sl = 0; sl < CELL_SLOTS; ++sl) {
        const int32_t o = slot_at(idx, sl);
        if (o >= 0 && o != self && crushable_by(o, i) && m.crush_count < CELL_SLOTS)
            m.crush_victims[m.crush_count++] = actors_[o].id;
    }
    if (shares_cell(actors_[i].type)) {


        const int32_t sub = free_subcell(next, m.sub, self);
        m.to_sub = sub == SUB_INVALID ? int32_t(SUB_DEFAULT) : sub;
    } else {
        m.to_sub = SUB_FULL;
    }
    slot_at(idx, m.to_sub) = self;
    m.to_cell = next;
    m.in_transit = true;
    m.has_waited = false;
    m.wait = 0;
    m.is_blocking = false;
    m.transit_from = actors_[i].pos;
    m.transit_dist = std::max(1, length(subcell_center(next, m.to_sub) - actors_[i].pos));
}


bool World::adjacent_free_cell(size_t i, CPos avoid, CPos& out) {
    const Mobile& m = mobiles_[i];
    const int start = static_cast<int>(rand() % NUM_DIRS);
    const int32_t mc = actor_move_class(i);
    for (int k = 0; k < NUM_DIRS; ++k) {
        const int d = (start + k) % NUM_DIRS;
        if (!map_.can_step(m.cell, d, mc)) continue;
        const CPos c{m.cell.x + DIR_DX[d], m.cell.y + DIR_DY[d]};
        if (c == avoid || !cell_free(c, static_cast<int32_t>(i))) continue;
        out = c;
        return true;
    }
    return false;
}


bool World::is_nudgeable(size_t k) const {
    const Actor& a = actors_[k];
    if (!a.alive || types_[a.type].building) return false;


    if (types_[a.type].husk) return false;
    const Mobile& m = mobiles_[k];
    if (m.moving || m.in_transit) return false;
    if (combats_[k].target >= 0) return false;
    const Harvest& h = harvests_[k];


    if (types_[a.type].harvester && h.automated) {
        switch (h.state) {
        case Harvest::IDLE:
        case Harvest::WAIT:
        case Harvest::QUEUE:
        case Harvest::PARKED:
            break;
        default:
            return false;
        }
    }
    return true;
}


bool World::nudge(size_t k, CPos avoid, int depth) {
    Mobile& b = mobiles_[k];
    const int32_t mc = actor_move_class(k);
    CPos c;
    bool found = false;
    int64_t best_d = INT64_MAX;
    for (int d = 0; d < NUM_DIRS; ++d) {
        if (!map_.can_step(b.cell, d, mc)) continue;
        const CPos n{b.cell.x + DIR_DX[d], b.cell.y + DIR_DY[d]};
        if (n == avoid || !cell_free(n, static_cast<int32_t>(k))) continue;
        const int64_t dist = cell_dist_sq(n, b.goal);
        if (dist < best_d) {
            best_d = dist;
            c = n;
            found = true;
        }
    }
    if (found) {
        b.moving = true;
        b.arrived = false;
        b.goal = c;
        b.field = -1;
        b.near_enough = 0;
        b.has_waited = false;
        b.wait = 0;
        b.detour.clear();
        return true;
    }
    if (depth <= 0) return false;

    const int start = static_cast<int>(rand() % NUM_DIRS);
    for (int j = 0; j < NUM_DIRS; ++j) {
        const int d = (start + j) % NUM_DIRS;
        if (!map_.can_step(b.cell, d, mc)) continue;
        const CPos n{b.cell.x + DIR_DX[d], b.cell.y + DIR_DY[d]};
        if (n == avoid) continue;
        const int32_t o = occupant(n);
        if (o < 0 || o == static_cast<int32_t>(k)) continue;
        if (actors_[o].owner != actors_[k].owner || !is_nudgeable(o)) continue;
        if (nudge(o, b.cell, depth - 1)) return true;
    }
    return false;
}


void World::notify_blocker(size_t i, int32_t blocker) {
    if (!allied(actors_[blocker].owner, actors_[i].owner)) return;
    if (types_[actors_[blocker].type].building) return;
    Mobile& b = mobiles_[blocker];
    if (!b.moving && !b.in_transit) {
        if (is_nudgeable(blocker)) nudge(blocker, mobiles_[i].cell, 4);
        return;
    }
    b.is_blocking = true;
}


bool World::local_repath(size_t i, const FlowField& f) {
    Mobile& m = mobiles_[i];
    const int32_t self = static_cast<int32_t>(i);
    const int32_t mc = actor_move_class(i);
    const int start = map_.index(m.cell);
    if (++stamp_ == 0) {
        std::fill(visit_stamp_.begin(), visit_stamp_.end(), 0);
        stamp_ = 1;
    }
    queue_.clear();
    queue_.push_back(start);
    visit_stamp_[start] = stamp_;
    parent_[start] = -1;

    int best = -1;
    int32_t best_d = f.dist[start];
    for (size_t head = 0; head < queue_.size(); ++head) {
        const int ci = queue_[head];
        const CPos c = map_.cell_at(ci);
        for (int d = 0; d < NUM_DIRS; ++d) {
            if (!map_.can_step(c, d, mc)) continue;
            const CPos n{c.x + DIR_DX[d], c.y + DIR_DY[d]};
            if (n.x < m.cell.x - REPATH_RADIUS || n.x > m.cell.x + REPATH_RADIUS ||
                n.y < m.cell.y - REPATH_RADIUS || n.y > m.cell.y + REPATH_RADIUS) continue;
            const int ni = map_.index(n);
            if (visit_stamp_[ni] == stamp_ || !cell_free(n, self)) continue;
            visit_stamp_[ni] = stamp_;
            parent_[ni] = ci;
            queue_.push_back(ni);
            if (f.dist[ni] < best_d) {
                best_d = f.dist[ni];
                best = ni;
            }
        }
    }
    if (best < 0) return false;
    m.detour.clear();
    for (int step = best; step != start; step = parent_[step]) m.detour.push_back(map_.cell_at(step));
    return true;
}


void World::step_idle(size_t i) {
    Mobile& m = mobiles_[i];
    const UnitType& t = types_[actors_[i].type];
    if (t.idle_anim_len[0] <= 0 || combats_[i].target >= 0 || actors_[i].prone_ticks > 0) {
        m.idle_seq = -1;
        return;
    }
    if (m.idle_seq >= 0) {
        ++m.idle_anim;
        if (int32_t(m.idle_anim) >= t.idle_anim_len[m.idle_seq] * t.idle_anim_ticks) {
            m.idle_seq = -1;
            m.idle_delay = 30 + static_cast<int32_t>(rand() % 81);
        }
        return;
    }
    if (--m.idle_delay > 0) return;
    const int32_t pick = static_cast<int32_t>(rand() % 2);
    m.idle_seq = t.idle_anim_len[pick] > 0 ? pick : 0;
    m.idle_anim = 0;
}


bool World::step_mobile_part(size_t i, bool carry_only) {
    Actor& a = actors_[i];
    Mobile& m = mobiles_[i];
    const UnitType& t = types_[a.type];
    const int32_t self = static_cast<int32_t>(i);

    if (!m.in_transit) {
        if (!m.moving) {
            step_idle(i);
            return false;
        }
        m.idle_seq = -1;
        if (m.cell == m.goal) {
            stop(i, true);
            return false;
        }


        if (m.field >= 0 && !fields_.valid(m.field, m.field_gen)) {
            m.field = fields_.get_or_build(map_, m.goal, move_class_of(t.locomotor));
            m.field_gen = fields_.generation();
        }

        CPos next;
        if (m.field < 0) {

            int dir = -1;
            for (int d = 0; d < NUM_DIRS; ++d) {
                if (m.cell.x + DIR_DX[d] == m.goal.x && m.cell.y + DIR_DY[d] == m.goal.y) dir = d;
            }
            if (dir < 0 || !map_.can_step(m.cell, dir, move_class_of(t.locomotor)) || !cell_free(m.goal, self)) {
                stop(i, false);
                return false;
            }
            next = m.goal;
        } else {
            const FlowField& f = fields_.field(m.field);
            const int here = map_.index(m.cell);


            bool from_detour = false;
            if (!m.detour.empty()) {
                const CPos step = m.detour.back();
                const int64_t adj = cell_dist_sq(step, m.cell);
                if (adj >= 1 && adj <= 2 && cell_free(step, self)) {
                    m.detour.pop_back();
                    next = step;
                    from_detour = true;
                } else {
                    m.detour.clear();
                }
            }

            if (!from_detour) {
                const int8_t nd = f.next[here];
                if (nd < 0) {
                    stop(i, false);
                    return false;
                }
                next = {m.cell.x + DIR_DX[nd], m.cell.y + DIR_DY[nd]};
            }


            const int32_t blocker = blocker_at(next, i);

            if (blocker != -1 && blocker != self) {


                const int64_t range = m.near_enough;
                const bool in_range = cell_dist_sq(m.cell, m.goal) <= range * range;
                if (in_range) {

                    if (next == m.goal) {
                        stop(i, true);
                        return false;
                    }


                    const int64_t blocker_d = cell_dist_sq(next, m.goal);
                    bool nudge_or_repath = false;
                    for (int d = 0; d < NUM_DIRS && !nudge_or_repath; ++d) {
                        const CPos c{next.x + DIR_DX[d], next.y + DIR_DY[d]};
                        if (c == m.cell || !map_.in_bounds(c)) continue;
                        nudge_or_repath = cell_dist_sq(c, m.goal) <= blocker_d && cell_free(c, self);
                    }
                    if (!nudge_or_repath) {
                        stop(i, true);
                        return false;
                    }
                }


                {
                    int best = -1;
                    int32_t best_d = f.dist[here];
                    for (int d = 0; d < NUM_DIRS; ++d) {
                        if (!map_.can_step(m.cell, d, move_class_of(t.locomotor))) continue;
                        const CPos c{m.cell.x + DIR_DX[d], m.cell.y + DIR_DY[d]};
                        const int ci = map_.index(c);
                        if (!cell_free(c, self) || f.dist[ci] >= best_d) continue;
                        best_d = f.dist[ci];
                        best = d;
                    }
                    if (best >= 0) {
                        begin_transit(i, {m.cell.x + DIR_DX[best], m.cell.y + DIR_DY[best]});
                        goto transit;
                    }
                }


                notify_blocker(i, blocker);


                if (!m.has_waited) {
                    m.wait = WAIT_AVERAGE;
                    m.has_waited = true;
                    return false;
                }
                if (--m.wait >= 0) return false;
                m.has_waited = false;


                if (in_range && ++m.near_cycles > 3) {
                    stop(i, true);
                    return false;
                }


                const Mobile& b = mobiles_[blocker];
                if (b.in_transit && b.cell == next && b.to_cell != next) return false;


                CPos step;
                if (local_repath(i, f)) {
                    next = m.detour.back();
                    m.detour.pop_back();
                } else if (m.is_blocking && adjacent_free_cell(i, next, step)) {

                    next = step;
                } else if (actors_[blocker].owner == a.owner && (b.moving || b.in_transit)) {


                    return false;
                } else {
                    stop(i, false);
                    return false;
                }
            }
        }
        begin_transit(i, next);
    }

transit:

    const WVec target = subcell_center(m.to_cell, m.to_sub);
    const WVec d = target - a.pos;
    const WAngle want = angle_of(d);
    const WAngle facing_before = a.facing;


    if (t.infantry) {
        a.facing = want;
    } else if (!carry_only) {
        a.facing = turn_towards(a.facing, want, t.turn_rate);
    }


    if (t.turreted && a.facing != facing_before) {
        const WAngle delta = angle_diff(facing_before, a.facing);
        for (int k = 0; k < t.turret_count; ++k)
            combats_[i].turret_at(k) = wrap_angle(combats_[i].turret_at(k) + delta);
    }
    if (!t.infantry) {
        const WAngle diff = angle_diff(a.facing, want);
        if (diff > DRIVE_TOLERANCE || diff < -DRIVE_TOLERANCE) return false;
    }


    if (!carry_only) m.progress += speed_at(i);
    const WVec from = m.transit_from;
    const int32_t dist = m.transit_dist;
    if (m.progress >= dist) {
        a.pos = target;
        m.in_transit = false;
        m.progress -= dist;
    } else {
        a.pos.x = from.x + static_cast<WDist>(int64_t(target.x - from.x) * m.progress / dist);
        a.pos.y = from.y + static_cast<WDist>(int64_t(target.y - from.y) * m.progress / dist);
    }


    if (m.cell != m.to_cell && length(target - a.pos) <= CELL / 2) {
        const int old = map_.index(m.cell);
        if (slot_at(old, m.sub) == self) slot_at(old, m.sub) = -1;
        const int32_t crusher_id = a.id;
        m.cell = m.to_cell;
        m.sub = m.to_sub;

        for (int32_t k = 0; k < m.crush_count; ++k) {
            const int vi = index_of(m.crush_victims[k]);
            if (vi >= 0 && actors_[vi].alive) {


                if (types_[actors_[vi].type].crate) {
                    crate_pickups_.push_back(actors_[vi].id);
                    crate_pickups_.push_back(a.id);
                    continue;
                }
                play_sound(types_[actors_[vi].type].crush_sound, actors_[vi].pos);


                kill(size_t(vi), DAMAGE_CRUSHED, crusher_id);
            }
        }
        m.crush_count = 0;
    }
    if (!carry_only) ++m.anim;


    return !m.in_transit && m.moving && m.progress > 0;
}

void World::step_mobile(size_t i) {
    Actor& a = actors_[i];

    if (a.prone_ticks > 0) --a.prone_ticks;
    if (types_[a.type].building) return;


    if (combats_[i].leap_lock > 0) { --combats_[i].leap_lock; return; }


    if (a.mad_ticks >= 0) return;


    if (airs_[i].alt > 0) {
        airs_[i].alt = std::max(0, airs_[i].alt - types_[a.type].fall_rate);
        return;
    }


    bool carry_only = false;
    for (int part = 0; part < 4; ++part) {
        if (!step_mobile_part(i, carry_only)) return;
        carry_only = true;
    }
}

void World::step() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        prev_pos_[i] = actors_[i].pos;
        prev_facing_[i] = actors_[i].facing;
        prev_turret_[i] = combats_[i].turret;
        prev_turret2_[i] = combats_[i].turret2;
    }
    step_pending_impacts();
    step_projectiles();
    step_bots();
    step_production();
    step_pending_places();
    step_buildings();
    step_repairs();
    step_enter();
    step_demolitions();
    step_seeds();
    step_cash_tricklers();
    step_cloak();
    step_pending_mines();
    step_deploy();
    step_support_powers();
    step_crates();
    step_self_healing();
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (actors_[i].alive && actors_[i].make_ticks > 0 && actors_[i].sell_ticks < 0) {


            const int32_t owner = actors_[i].owner;
            const int32_t before = actors_[i].make_ticks == 1 ? buildable_total(owner) : 0;
            if (--actors_[i].make_ticks == 0) {
                if (buildable_total(owner) > before) new_options_pending_[owner] = true;
                if (new_options_pending_[owner]) {
                    new_options_pending_[owner] = false;
                    notify(owner, NOTIFY_NEW_OPTIONS);
                }
            }
        }
    }


    step_cargo();
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (in_world(i) && actors_[i].make_ticks == 0) step_combat(i);
    }
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (in_world(i)) step_harvester(i);
    }
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (!in_world(i)) continue;


        if (types_[actors_[i].type].aircraft) step_aircraft(i);
        else if (!actors_[i].load_lock && actors_[i].after_load_ticks < 0) step_mobile(i);
    }


    step_landing_craft();
    step_crate_pickups();
    step_pending_husks();
    step_order_queue();
    step_effects();
    step_zaps();


    if (tick_ % 5 == 0)
        for (int32_t p = 0; p < MAX_PLAYERS; ++p)
            if ((vis_players_ >> p) & 1u) update_visibility(p);
    if (tick_ % 25 == 0) step_victory();
    ++tick_;
}

uint32_t World::moving_count() const {
    uint32_t n = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Mobile& m = mobiles_[i];
        n += (actors_[i].alive && (m.moving || m.in_transit)) ? 1 : 0;
    }
    return n;
}

void World::render(int32_t alpha, RenderActor* out, int32_t viewer) const {
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        const Mobile& m = mobiles_[i];
        const Combat& c = combats_[i];
        const Harvest& h = harvests_[i];
        RenderActor& r = out[i];
        r.id = a.id;
        r.type = a.type;
        r.owner = a.owner;


        r.disguise_type = a.disguise_type;
        r.disguise_owner = a.disguise_owner;
        r.x = prev_pos_[i].x + static_cast<WDist>(int64_t(a.pos.x - prev_pos_[i].x) * alpha / 1024);
        r.y = prev_pos_[i].y + static_cast<WDist>(int64_t(a.pos.y - prev_pos_[i].y) * alpha / 1024);
        r.facing = wrap_angle(prev_facing_[i] + angle_diff(prev_facing_[i], a.facing) * alpha / 1024);

        r.turret = wrap_angle(prev_turret_[i] + angle_diff(prev_turret_[i], c.turret) * alpha / 1024);
        r.turret2 = wrap_angle(prev_turret2_[i] + angle_diff(prev_turret2_[i], c.turret2) * alpha / 1024);


        r.moving = (prev_pos_[i] != a.pos) ? 1 : 0;
        r.alive = a.alive ? 1 : 0;
        r.firing = (c.fire_anim > 0) ? 1 : 0;
        r.reloading = (c.reload > 0) ? 1 : 0;
        r.fire_frame = c.fire_anim > 0 ? (8 - c.fire_anim) : 0;
        r.barrel_flip = c.barrel_flip ? 1 : 0;

        r.leaping = (c.leap_ticks >= 0) ? 1 : 0;
        r.deploying = (a.mad_ticks >= 0) ? 1 : 0;
        r.deploy_frame = a.mad_ticks;

        r.ramp = uint8_t(a.ramp);
        r.ramp_frame = a.ramp_frame;
        r.leap_frame = c.leap_ticks > 0 ? c.leap_ticks - 1 : 0;
        r.activity = ACT_NONE;
        if (types_[a.type].building && a.active_ticks > 0) r.activity = ACT_ACTIVE;
        if (types_[a.type].harvester && h.automated) {
            if (h.state == Harvest::HARVESTING) r.activity = ACT_HARVESTING;
            else if (h.state == Harvest::UNLOADING) r.activity = ACT_DOCKING;
        }
        const int32_t max_hp = types_[a.type].hp;
        r.hp_permille = max_hp > 0 ? static_cast<int32_t>(int64_t(a.hp) * 1000 / max_hp) : 0;
        const int32_t cap = types_[a.type].capacity;
        r.cargo_permille = (types_[a.type].harvester && cap > 0) ? h.bales * 1000 / cap : 0;
        r.make_ticks = a.make_ticks;
        r.door_ticks = a.door_ticks;
        r.visible = actor_visible_to(viewer, i) ? 1 : 0;

        r.altitude = airs_[i].alt;
        r.passengers = 0;
        for (const int32_t pid : cargo_[i]) {
            const int p = index_of(pid);
            if (p >= 0) r.passengers += std::max(1, types_[actors_[p].type].passenger_weight);
        }
        r.cargo_max = types_[a.type].cargo_max_weight;
        r.ammo = airs_[i].ammo;
        r.ammo_max = types_[a.type].ammo_max;
        r.wall_mask = 0;
        if (types_[a.type].wall) {
            static const int dx[4] = {0, 1, 0, -1}, dy[4] = {-1, 0, 1, 0};
            for (int d = 0; d < 4; ++d) {
                const CPos n{a.origin.x + dx[d], a.origin.y + dy[d]};
                if (!map_.in_bounds(n)) continue;
                const int o = slot_at(map_.index(n), SUB_FULL);
                if (o >= 0 && actors_[o].alive && actors_[o].type == a.type) r.wall_mask |= uint8_t(1 << d);
            }
        }
        r.idle_seq = m.idle_seq;
        r.idle_anim = m.idle_anim;
        r.prone = a.prone_ticks > 0 ? 1 : 0;
        r.rank = uint8_t(a.level);
        r.repairing = a.repairing ? 1 : 0;
        r.selling = (a.sell_ticks >= 0 || (!a.alive && a.vanished)) ? 1 : 0;
        r.primary = a.primary ? 1 : 0;

        r.unpowered = (types_[a.type].building && !powered(i)) ? 1 : 0;


        r.cloaked = cloaked(i) ? 1 : 0;
        r.demolishing = a.demolish_ticks >= 0 ? 1 : 0;

        r.demolish_left = uint8_t(std::clamp<int32_t>(a.demolish_ticks + 1, 0, 127));
        r.invulnerable = a.invulnerable_ticks > 0 ? 1 : 0;
        r.rally = a.rally;


        r.anim = (types_[a.type].building && r.activity == ACT_ACTIVE)
                     ? uint32_t(a.active_anim)
                     : (r.activity != ACT_NONE
                            ? h.anim
                            : ((types_[a.type].building || types_[a.type].aircraft) ? tick_ : m.anim));
    }
}

}

namespace ra {


void World::step_cloak() {
    if (detected_.size() != actors_.size()) detected_.assign(actors_.size(), 0);
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        const UnitType& t = types_[a.type];
        if (!a.alive || !t.cloak) continue;


        const bool was_cloaked = a.cloak_timer <= 0 && !cloak_paused(i);
        if (!cloak_paused(i)) {
            if ((t.uncloak_on & UNCLOAK_MOVE) && (mobiles_[i].moving || mobiles_[i].in_transit)) a.cloak_timer = t.cloak_delay;
            else if (a.cloak_timer > 0) --a.cloak_timer;
        }

        const bool now_cloaked = a.cloak_timer <= 0 && !cloak_paused(i);
        if (now_cloaked != was_cloaked && t.cloak_sound >= 0) play_sound(t.cloak_sound, a.pos);
        uint8_t mask = 0;
        for (size_t k = 0; k < actors_.size(); ++k) {
            const Actor& d = actors_[k];
            const UnitType& dt = types_[d.type];
            if (!d.alive || dt.detect_range <= 0 || (dt.detect_types & t.cloak_types) == 0) continue;
            if (d.owner < 0 || d.owner >= MAX_PLAYERS) continue;
            if (length(d.pos - a.pos) > dt.detect_range + (dt.building ? dt.range_radius : 0)) continue;
            for (int32_t p = 0; p < MAX_PLAYERS; ++p) {
                if (allied(p, d.owner)) mask |= uint8_t(1u << p);
            }
        }
        detected_[i] = mask;
    }
}

bool World::detected_by(int32_t viewer, size_t i) const {
    if (viewer < 0 || viewer >= MAX_PLAYERS || i >= detected_.size()) return false;
    return (detected_[i] & (1u << viewer)) != 0;
}


void World::uncloak(size_t i, uint32_t reason) {
    const UnitType& t = types_[actors_[i].type];
    if (t.cloak && (t.uncloak_on & reason)) actors_[i].cloak_timer = std::max(actors_[i].cloak_timer, t.cloak_delay);
}


bool World::can_lay_mine(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[size_t(i)].alive) return false;
    const UnitType& t = types_[actors_[size_t(i)].type];
    return t.minelayer_mine >= 0 && (t.ammo_max <= 0 || airs_[size_t(i)].ammo > 0);
}


void World::order_lay_mine(const int32_t* ids, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !can_lay_mine(ids[k])) continue;
        const UnitType& t = types_[actors_[size_t(i)].type];
        const CPos c = mobiles_[size_t(i)].cell;
        if (!map_.in_bounds(c)) continue;
        bool dup = false;
        for (const PendingMine& pm : pending_mines_) if (pm.cell == c) dup = true;
        for (size_t j = 0; j < actors_.size() && !dup; ++j) {
            if (actors_[j].alive && types_[actors_[j].type].mine && mobiles_[j].cell == c) dup = true;
        }
        if (dup) continue;
        if (t.ammo_max > 0) --airs_[size_t(i)].ammo;
        pending_mines_.push_back(PendingMine{actors_[size_t(i)].owner, t.minelayer_mine, c});
    }
}

void World::step_pending_mines() {
    for (size_t k = 0; k < pending_mines_.size();) {
        const PendingMine pm = pending_mines_[k];
        bool free = map_.in_bounds(pm.cell);
        if (free) {
            const int idx = map_.index(pm.cell);
            for (int s = 0; s < CELL_SLOTS; ++s) if (slot_at(idx, s) != -1) { free = false; break; }
        }
        if (!free) { ++k; continue; }
        spawn(pm.type, pm.owner, pm.cell);
        pending_mines_[k] = pending_mines_.back();
        pending_mines_.pop_back();
    }
}


constexpr int32_t GPS_DOOR_TICKS = 2 * TICKS_PER_SECOND;


static int sp_building(const std::vector<Actor>& actors, const std::vector<UnitType>& types, int32_t owner, int32_t kind) {
    for (size_t i = 0; i < actors.size(); ++i) {
        const Actor& a = actors[i];
        if (!a.alive || a.owner != owner || a.make_ticks > 0 || a.sell_ticks >= 0) continue;
        if (types[a.type].support_power == kind) return int(i);
    }
    return -1;
}

void World::support_power_state(int32_t owner, int32_t kind, int& available, int& ready, int& permille, int& paused) const {
    available = ready = permille = paused = 0;
    if (owner < 0 || owner >= MAX_PLAYERS || kind < 0 || kind >= SP_COUNT) return;
    const SupportPowerState& st = players_[owner].powers[kind];
    const int b = sp_building(actors_, types_, owner, kind);
    if (b < 0) return;

    if (st.used) return;
    available = 1;
    ready = st.ready ? 1 : 0;
    permille = st.ready ? 1000 : int(int64_t(st.charge) * 1000 / std::max(1, types_[actors_[size_t(b)].type].sp_charge));
    paused = (!st.ready && power_balance_[owner] < 0) ? 1 : 0;
}


constexpr int32_t NUKE_EFFECT_REPEAT = 20;


void World::step_support_powers() {
    for (int32_t owner = 0; owner < MAX_PLAYERS; ++owner) {
        for (int32_t kind = 0; kind < SP_COUNT; ++kind) {
            SupportPowerState& st = players_[owner].powers[kind];
            const int b = sp_building(actors_, types_, owner, kind);
            if (b < 0) { st.available = false; st.ready = false; st.charge = 0; continue; }
            const UnitType& t = types_[actors_[size_t(b)].type];
            if (st.used) continue;
            if (!st.available) {
                st.available = true;
                if (!st.ready && t.sp_notify_charging >= 0) notify(owner, t.sp_notify_charging);
            }
            if (st.ready || power_balance_[owner] < 0) continue;
            if (++st.charge >= t.sp_charge) {
                st.ready = true;
                if (t.sp_notify_ready >= 0) notify(owner, t.sp_notify_ready);


                if (kind == SP_GPS) activate_support_power(owner, kind, CPos{0, 0}, CPos{0, 0});
            }
        }
    }

    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive) continue;
        if (a.invulnerable_ticks > 0) --a.invulnerable_ticks;
        if (a.chrono_return > 0 && --a.chrono_return == 0) {
            if (a.chrono_origin.x >= 0) teleport(a.id, find_free_cell(a.chrono_origin, a.type));
            a.chrono_origin = CPos{-1, -1};
        }
    }


    for (size_t k = 0; k < pending_gps_.size();) {
        if (--pending_gps_[k].ticks > 0) { ++k; continue; }
        const int32_t owner = pending_gps_[k].owner;
        gps_launched_ |= 1u << uint32_t(owner);
        for (int32_t p = 0; p < MAX_PLAYERS; ++p)
            if (p == owner || allied(owner, p)) explore_all(p);
        pending_gps_[k] = pending_gps_.back();
        pending_gps_.pop_back();
    }


    for (size_t k = 0; k < pending_nukes_.size();) {
        PendingNuke& n = pending_nukes_[k];
        const UnitType& t = types_[n.type];
        const int32_t elapsed = n.total - n.ticks;
        const int32_t turn = std::max(1, n.total / 2);
        if (elapsed % NUKE_EFFECT_REPEAT == 0) {
            if (elapsed < turn) { if (t.sp_launch_effect >= 0) spawn_effect(n.launch_pos, t.sp_launch_effect, 0, 0); }
            else if (t.sp_impact_effect >= 0) spawn_effect(n.target, t.sp_impact_effect, 0, 0);
        }
        if (elapsed >= turn && n.reveal_id < 0 && t.sp_camera_range > 0)
            n.reveal_id = reveal_source(n.owner, to_cell(n.target), std::max(1, t.sp_camera_range / CELL));
        if (--n.ticks > 0) { ++k; continue; }
        if (n.reveal_id >= 0) remove_reveal_source(n.reveal_id);
        impact(n.target, t.sp_weapon, -1, n.owner, 0);
        pending_nukes_[k] = pending_nukes_.back();
        pending_nukes_.pop_back();
    }
}


bool World::activate_support_power(int32_t owner, int32_t kind, CPos cell, CPos cell2) {
    if (owner < 0 || owner >= MAX_PLAYERS || kind < 0 || kind >= SP_COUNT) return false;
    SupportPowerState& st = players_[owner].powers[kind];
    const int b = sp_building(actors_, types_, owner, kind);
    if (b < 0 || !st.ready || st.used) return false;
    const Actor& bld = actors_[size_t(b)];
    const UnitType& t = types_[bld.type];

    auto cells_at = [&](CPos center, std::vector<CPos>& out) {
        for (int y = 0; y < t.sp_dim_h; ++y)
            for (int x = 0; x < t.sp_dim_w; ++x)
                if (t.sp_footprint.empty() || t.sp_footprint[size_t(y * t.sp_dim_w + x)])
                    out.push_back(CPos{center.x - t.sp_dim_w / 2 + x, center.y - t.sp_dim_h / 2 + y});
    };
    auto in_cells = [&](const std::vector<CPos>& cells, CPos c) {
        for (const CPos& k : cells) if (k == c) return true;
        return false;
    };
    if (kind == SP_IRON_CURTAIN) {

        std::vector<CPos> cells; cells_at(cell, cells);
        for (size_t i = 0; i < actors_.size(); ++i) {
            Actor& a = actors_[i];
            if (!a.alive || !allied(owner, a.owner)) continue;
            const UnitType& at = types_[a.type];
            bool hit = false;
            if (at.building) {
                for (int y = 0; y < at.foot_h && !hit; ++y)
                    for (int x = 0; x < at.foot_w && !hit; ++x)
                        if (at.footprint[size_t(y * at.foot_w + x)] && in_cells(cells, CPos{a.origin.x + x, a.origin.y + y})) hit = true;
            } else {
                hit = in_cells(cells, mobiles_[i].cell);
            }
            if (hit) a.invulnerable_ticks = t.sp_duration;
        }
        if (t.sp_sound >= 0) play_sound(t.sp_sound, cell_center(cell));
    } else if (kind == SP_CHRONOSHIFT) {


        std::vector<CPos> src; cells_at(cell, src);
        bool any = false;
        for (size_t i = 0; i < actors_.size(); ++i) {
            Actor& a = actors_[i];
            const UnitType& at = types_[a.type];
            if (!a.alive || at.building || at.aircraft || !in_world(i)) continue;
            const CPos from = mobiles_[i].cell;
            if (!in_cells(src, from)) continue;
            const CPos to{from.x + cell2.x - cell.x, from.y + cell2.y - cell.y};
            if (!map_.in_bounds(to)) continue;
            const CPos origin = from;
            if (teleport(a.id, find_free_cell(to, a.type))) {
                actors_[i].chrono_return = t.sp_duration;
                actors_[i].chrono_origin = origin;
                any = true;
            }
        }
        if (!any) return false;
        if (t.sp_sound >= 0) play_sound(t.sp_sound, cell_center(cell2));
    } else if (kind == SP_GPS) {


        if (t.sp_sound >= 0) play_sound(t.sp_sound, bld.pos);
        actors_[size_t(b)].active_ticks = GPS_DOOR_TICKS;
        actors_[size_t(b)].active_anim = 0;
        if (t.sp_notify_launch >= 0) notify(owner, t.sp_notify_launch);
        pending_gps_.push_back(PendingGps{owner, std::max(1, t.sp_reveal_delay)});
    } else {


        if (t.sp_weapon < 0) return false;
        const int32_t flight = std::max(1, t.sp_flight);
        pending_nukes_.push_back(PendingNuke{owner, bld.type, cell_center(cell), flight, bld.pos, flight, -1});
        for (int32_t p = 0; p < MAX_PLAYERS; ++p) if (players_[p].participant) notify(p, NOTIFY_ABOMB_LAUNCH_DETECTED);
    }
    st.ready = false;
    st.charge = 0;
    st.used = t.sp_one_shot;
    if (!st.used && t.sp_notify_charging >= 0) notify(owner, t.sp_notify_charging);
    return true;
}


void World::pending_nukes(std::vector<NukeInfo>& out) const {
    out.clear();
    for (const PendingNuke& n : pending_nukes_) out.push_back(NukeInfo{n.owner, n.target, n.ticks});
}
}
