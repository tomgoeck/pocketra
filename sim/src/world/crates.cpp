

#include <algorithm>
#include <climits>

#include "ra/sim.h"

namespace ra {


static constexpr int CRATE_UNIT_RADIUS = 3;


static constexpr uint32_t DEFAULT_VALID_GROUND =
    (1u << TER_CLEAR) | (1u << TER_ROUGH) | (1u << TER_ROAD) | (1u << TER_ORE) | (1u << TER_BEACH);

void World::set_crate_spawner(const CrateSpawnerParams& p) {
    crate_p_ = p;
    if (crate_p_.valid_ground == 0) crate_p_.valid_ground = DEFAULT_VALID_GROUND;

    crate_ticks_ = crate_p_.initial_delay;
}

uint32_t World::crate_count() const {
    uint32_t n = 0;
    for (const Actor& a : actors_)
        if (a.alive && types_[a.type].crate) ++n;
    return n;
}


bool World::spawn_crate() {
    if (crate_p_.crate_type < 0 || crate_p_.crate_type >= int32_t(types_.size())) return false;
    if (map_.cells() <= 0) return false;
    for (int n = 0; n < 100; ++n) {
        const int idx = int(rand() % uint32_t(map_.cells()));
        const CPos c = map_.cell_at(idx);
        if (!map_.passable(c)) continue;
        if (((crate_p_.valid_ground >> map_.base_terrain(c)) & 1u) == 0) continue;
        if (!cell_empty(c)) continue;
        if (res_density_[size_t(idx)] > 0) continue;
        const int32_t id = spawn(crate_p_.crate_type, neutral_player_ >= 0 ? neutral_player_ : 0, c, 0);
        const int i = index_of(id);
        if (i >= 0) actors_[size_t(i)].life_ticks = types_[crate_p_.crate_type].crate_duration;
        return i >= 0;
    }
    return false;
}


void World::step_crates() {

    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive || !types_[a.type].crate || a.life_ticks <= 0) continue;
        if (--a.life_ticks <= 0) dispose(i);
    }
    if (!crate_p_.enabled) return;
    if (--crate_ticks_ > 0) return;
    crate_ticks_ = std::max(1, crate_p_.spawn_interval);
    const int32_t have = int32_t(crate_count());
    const int32_t to_spawn = std::max(0, crate_p_.minimum - have)
        + ((have < crate_p_.maximum && crate_p_.maximum > crate_p_.minimum) ? 1 : 0);
    for (int32_t n = 0; n < to_spawn; ++n) spawn_crate();
}


void World::step_crate_pickups() {
    if (crate_pickups_.empty()) return;
    std::vector<int32_t> pending;
    pending.swap(crate_pickups_);
    for (size_t k = 0; k + 1 < pending.size(); k += 2) {
        const int ci = index_of(pending[k]);
        const int co = index_of(pending[k + 1]);
        if (ci >= 0 && co >= 0) collect_crate(size_t(ci), size_t(co));
    }
}


void World::explore_all(int32_t owner) {
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    std::vector<uint8_t>& vis = vis_[owner];
    if (vis.size() != size_t(map_.cells())) vis.assign(map_.cells(), 0);
    for (uint8_t& v : vis) if (v == 0) v = 1;


    explored_[owner].assign(map_.cells(), 1);
    update_visibility(owner);
}


void World::reset_exploration(int32_t owner) {
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    std::vector<uint8_t>& vis = vis_[owner];
    vis.assign(map_.cells(), 0);
    explored_[owner].assign(map_.cells(), 0);
    for (uint32_t& m : seen_mask_) m &= ~(1u << owner);
    for (uint32_t& m : live_mask_) m &= ~(1u << owner);
    frozen_[owner].clear();
    update_visibility(owner);
}


static bool near_free_cell(const World& w, CPos near, int32_t type, int radius, CPos& out);


int32_t World::crate_shares(const CrateAction& ca, size_t collector) const {
    if (int32_t(tick_) < ca.time_delay) return 0;
    const Actor& col = actors_[collector];
    if (col.owner < 0 || col.owner >= MAX_PLAYERS) return 0;
    if (players_[col.owner].non_combatant) return 0;
    if (!ca.factions.empty()) {
        const std::string& f = players_[col.owner].faction;
        bool ok = false;
        for (const std::string& v : ca.factions) if (v == f) { ok = true; break; }
        if (!ok) return 0;
    }
    for (const std::string& p : ca.prerequisites)
        if (!has_prerequisite(col.owner, p)) return 0;

    switch (ca.kind) {
        case CRATE_UNIT:


            for (int32_t u : ca.units) {
                if (u < 0 || u >= int32_t(types_.size())) return 0;
                CPos c;
                if (!near_free_cell(*this, mobiles_[collector].cell, u, CRATE_UNIT_RADIUS, c)) return 0;
            }
            return ca.units.empty() ? 0 : ca.shares;
        case CRATE_BASE_BUILDER: {

            for (int32_t u : ca.units) {
                if (u < 0 || u >= int32_t(types_.size())) return 0;
                CPos c;
                if (!near_free_cell(*this, mobiles_[collector].cell, u, CRATE_UNIT_RADIUS, c)) return 0;
            }
            bool has_base = false;
            for (const Actor& a : actors_)
                if (a.alive && a.owner == col.owner && types_[a.type].base_provider) { has_base = true; break; }
            return has_base ? ca.shares : ca.no_base_shares;
        }
        case CRATE_DUPLICATE:

            if (types_[col.type].building || types_[col.type].crate) return 0;
            return ca.shares;
        case CRATE_LEVEL_UP:

            return level_of(collector) < max_level(col.type) ? ca.shares : 0;
        case CRATE_EXPLODE:
            return ca.weapon >= 0 && ca.weapon < int32_t(weapons_.size()) ? ca.shares : 0;
        case CRATE_HIDE_MAP:
        case CRATE_REVEAL_MAP:
        case CRATE_HEAL:
        case CRATE_CASH:
        default:
            return ca.shares;
    }
}

void World::run_crate_action(const CrateAction& ca, size_t collector, WVec at) {

    const int32_t owner = actors_[collector].owner;
    const int32_t col_id = actors_[collector].id;
    const int32_t col_type = actors_[collector].type;
    const CPos cell = mobiles_[collector].cell;
    const WVec col_pos = actors_[collector].pos;
    switch (ca.kind) {
        case CRATE_CASH:


            give_credits(owner, ca.amount);
            cash_ticks_.push_back(CashTick{owner, ca.amount, at});
            break;
        case CRATE_LEVEL_UP:


            give_levels(collector, std::max(1, ca.amount));
            break;
        case CRATE_EXPLODE:


            impact(col_pos, ca.weapon, col_id, owner, 0, 0, true);
            break;
        case CRATE_HIDE_MAP:
            reset_exploration(owner);
            break;
        case CRATE_REVEAL_MAP:
            explore_all(owner);
            break;
        case CRATE_HEAL:

            for (size_t k = 0; k < actors_.size(); ++k)
                if (actors_[k].alive && actors_[k].owner == owner) actors_[k].hp = std::max(1, types_[actors_[k].type].hp);
            break;
        case CRATE_DUPLICATE: {

            int32_t n = ca.max_amount;
            const int32_t cost = types_[col_type].cost;
            if (ca.max_value > 0 && cost > 0) n = std::min(n, ca.max_value / cost);
            n = std::max(ca.min_amount, n);
            const int32_t type = col_type;
            for (int32_t k = 0; k < n; ++k) {
                CPos c;
                if (!near_free_cell(*this, cell, type, ca.max_radius, c)) break;
                spawn(type, owner, c);
            }
            break;
        }
        case CRATE_UNIT:
        case CRATE_BASE_BUILDER: {


            for (int32_t u : ca.units) {
                if (u < 0 || u >= int32_t(types_.size())) continue;
                CPos c;
                if (!near_free_cell(*this, cell, u, CRATE_UNIT_RADIUS, c)) continue;
                spawn(u, owner, c);
            }
            break;
        }
        default:
            break;
    }
    if (ca.sound >= 0) play_sound(ca.sound, at);
    if (ca.effect >= 0) spawn_effect(at, ca.effect);
}

static bool near_free_cell(const World& w, CPos near, int32_t type, int radius, CPos& out) {
    const UnitType& t = w.type(type);
    const bool shares = t.locomotor == LOCO_FOOT && !t.building;


    const int32_t mc = t.building ? ((t.terrain_mask & (1u << TER_WATER)) != 0 ? int32_t(MC_NAVAL) : int32_t(MC_LAND))
                                  : move_class_of(t.locomotor);
    for (int r = 0; r <= radius; ++r) {
        for (int dy = -r; dy <= r; ++dy) {
            for (int dx = -r; dx <= r; ++dx) {
                if (r > 0 && dx != -r && dx != r && dy != -r && dy != r) continue;
                const CPos c{near.x + dx, near.y + dy};
                if (!w.map().passable(c, mc)) continue;
                if (shares ? (w.occupant(c, SUB_FULL) < 0 && w.free_subcell(c, SUB_DEFAULT, -1) != SUB_INVALID)
                           : (w.occupant(c) < 0)) {
                    out = c;
                    return true;
                }
            }
        }
    }
    return false;
}


void World::collect_crate(size_t ci, size_t collector) {
    if (ci >= actors_.size() || collector >= actors_.size()) return;
    if (!actors_[ci].alive || !actors_[collector].alive) return;
    const UnitType& ct = types_[actors_[ci].type];
    const WVec at = actors_[ci].pos;

    const std::vector<CrateAction>& actions = ct.crate_actions;
    dispose(ci);
    if (actions.empty()) return;
    int32_t total = 0;
    for (const CrateAction& ca : actions) total += crate_shares(ca, collector);
    if (total <= 0) return;
    int32_t n = int32_t(rand() % uint32_t(total));
    for (const CrateAction& ca : actions) {
        const int32_t sh = crate_shares(ca, collector);
        if (n < sh) {
            run_crate_action(ca, collector, at);
            return;
        }
        n -= sh;
    }
}

}
