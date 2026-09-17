

#include "ra/sim.h"

namespace ra {


bool World::can_detonate(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[size_t(i)].alive || !in_world(size_t(i))) return false;
    const UnitType& t = types_[actors_[size_t(i)].type];
    if (t.detonate_on_deploy) return true;
    return t.mad_charge_delay >= 0 && actors_[size_t(i)].mad_ticks < 0;
}

bool World::detonating(int32_t id) const {
    const int i = index_of(id);
    return i >= 0 && actors_[size_t(i)].alive && actors_[size_t(i)].mad_ticks >= 0;
}

void World::set_mad_driver(int32_t type, int32_t driver_type) {
    if (type >= 0 && type < int32_t(types_.size())) types_[size_t(type)].mad_driver = driver_type;
}

void World::order_detonate(const int32_t* ids, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        const int32_t id = ids[k];
        if (!can_detonate(id)) continue;
        const int i = index_of(id);
        const UnitType& t = types_[actors_[size_t(i)].type];
        if (t.detonate_on_deploy) {


            kill(size_t(i), DAMAGE_EXPLOSION, id);
            continue;
        }


        stop(size_t(i), false);
        combats_[size_t(i)].target = -1;
        combats_[size_t(i)].attack_move = false;
        combats_[size_t(i)].guard = -1;
        order_queue_[size_t(i)].clear();
        actors_[size_t(i)].mad_ticks = 0;


        if (t.mad_driver >= 0) {
            const CPos c = find_adjacent_cell(mobiles_[size_t(i)].cell, t.mad_driver);
            if (map_.in_bounds(c)) spawn(t.mad_driver, actors_[size_t(i)].owner, c);
        }
    }
}


int32_t World::chrono_charge_left(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[size_t(i)].alive) return 0;
    return actors_[size_t(i)].chrono_charge;
}

int32_t World::chrono_max_cells(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[size_t(i)].alive) return 0;
    return types_[actors_[size_t(i)].type].chrono_max_distance;
}


bool World::can_chrono(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[size_t(i)].alive || !in_world(size_t(i))) return false;
    const UnitType& t = types_[actors_[size_t(i)].type];
    return t.chrono_charge_delay > 0 && actors_[size_t(i)].chrono_charge <= 0;
}


bool World::order_chrono(const int32_t* ids, size_t n, CPos cell) {
    bool any = false;
    for (size_t k = 0; k < n; ++k) {
        const int32_t id = ids[k];
        if (!can_chrono(id)) continue;
        const int i = index_of(id);
        const UnitType& t = types_[actors_[size_t(i)].type];
        const CPos from = mobiles_[size_t(i)].cell;
        CPos to = cell;


        const int32_t max_cells = t.chrono_max_distance;
        if (max_cells > 0) {
            const int32_t dx = to.x - from.x, dy = to.y - from.y;
            const int64_t dist_sq = int64_t(dx) * dx + int64_t(dy) * dy;
            if (dist_sq > int64_t(max_cells) * max_cells) {
                const int32_t d = isqrt(dist_sq);
                if (d <= 0) continue;
                to = CPos{from.x + int32_t(int64_t(dx) * max_cells / d), from.y + int32_t(int64_t(dy) * max_cells / d)};
            }
        }
        if (!map_.in_bounds(to)) continue;


        const int32_t mc = actor_move_class(size_t(i));
        if (!map_.passable(to, mc) && !map_.passable(find_free_cell(to, actors_[size_t(i)].type), mc)) continue;

        play_sound(t.chrono_sound, actors_[size_t(i)].pos);
        if (!teleport(id, to)) continue;
        play_sound(t.chrono_sound, actors_[size_t(i)].pos);

        actors_[size_t(i)].chrono_charge = t.chrono_charge_delay;
        any = true;
    }
    return any;
}


void World::step_deploy() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive) continue;
        if (a.chrono_charge > 0) --a.chrono_charge;
        if (a.mad_ticks < 0) continue;
        const UnitType& t = types_[a.type];
        if (t.mad_charge_delay < 0) { a.mad_ticks = -1; continue; }
        ++a.mad_ticks;

        if (t.mad_thump_weapon >= 0 && a.mad_ticks % t.mad_thump_interval == 0) {
            impact(a.pos, t.mad_thump_weapon, a.id, a.owner);
        }

        if (a.mad_ticks == t.mad_charge_delay) play_sound(t.mad_charge_sound, a.pos);

        if (a.mad_ticks >= t.mad_charge_delay + t.mad_detonation_delay) {
            play_sound(t.mad_detonation_sound, a.pos);
            if (t.mad_detonation_weapon >= 0) impact(a.pos, t.mad_detonation_weapon, a.id, a.owner);
            a.mad_ticks = -1;
            kill(i, DAMAGE_EXPLOSION, a.id);
        }
    }
}

}
