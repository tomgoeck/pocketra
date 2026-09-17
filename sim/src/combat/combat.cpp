

#include <algorithm>
#include <climits>

#include "ra/sim.h"

namespace ra {


constexpr int32_t SCAN_MIN = 3;
constexpr int32_t SCAN_MAX = 8;

constexpr WAngle AIM_TOLERANCE = 32;

constexpr int32_t FIRE_ANIM_TICKS = 8;


constexpr uint32_t AUTO_DEFEND = TT_INFANTRY | TT_VEHICLE | TT_SHIP | TT_UNDERWATER | TT_DEFENSE | TT_MINE;


static inline WDist lerp_axis(WDist from, WDist to, int32_t t, int32_t total) {
    return from + static_cast<WDist>(int64_t(to - from) * t / total);
}

int32_t World::define_weapon(const Weapon& w) {
    weapons_.push_back(w);
    return static_cast<int32_t>(weapons_.size()) - 1;
}

int32_t World::define_effect(const EffectSeq& e) {
    effects_def_.push_back(e);
    return static_cast<int32_t>(effects_def_.size()) - 1;
}

void World::spawn_effect(WVec pos, int32_t seq, WAngle facing, WDist alt, int32_t owner) {
    if (seq < 0) return;
    effects_.push_back({pos, seq, 0, 0, facing, alt, owner});
}


uint32_t World::impact_terrain_at(WVec pos, WDist alt) const {
    constexpr WDist AIR_THRESHOLD = 128;
    if (alt > AIR_THRESHOLD) return IT_AIR;
    const CPos c = to_cell(pos);
    if (!map_.in_bounds(c)) return 0;
    const int32_t ter = map_.terrain(c);
    return (ter == TER_WATER || ter == TER_RIVER) ? IT_WATER : IT_GROUND;
}


void World::apply_effect_warhead(WVec pos, const ImpactEffect& g, int32_t attacker_id, WDist alt) {


    bool any_invalid = false;
    bool any_valid = false;
    if (g.impact_actors) {
        const size_t n_actors = actors_.size();
        for (size_t k = 0; k < n_actors && k < actors_.size(); ++k) {
            const Actor& v = actors_[k];
            if (!in_world(k)) continue;
            if (v.id == attacker_id) continue;
            if (!types_[v.type].targetable) continue;
            const int64_t r = types_[v.type].hit_radius;
            if (r <= 0) continue;
            if (length_sq(v.pos - pos) > r * r) continue;
            const uint32_t m = target_mask(k);
            const bool ok = (g.invalid_targets & m) == 0 && (g.valid_targets == 0 || (g.valid_targets & m) != 0);
            if (ok) { any_valid = true; break; }
            any_invalid = true;
        }
    }
    if (!any_valid) {
        if (any_invalid) return;
        const uint32_t ter = impact_terrain_at(pos, alt);
        if (ter == 0) return;
        if ((g.invalid_terrain & ter) != 0) return;
        if (g.valid_terrain != 0 && (g.valid_terrain & ter) == 0) return;
        if (g.valid_terrain == 0) return;
    }

    if (g.effect_count > 0) {
        const int32_t seq = g.effect_count > 1 ? g.effects[rand() % uint32_t(g.effect_count)] : g.effects[0];
        spawn_effect(pos, seq, 0, alt);
    }
    if (g.sound >= 0 && (g.sound_chance >= 100 || int32_t(rand() % 100u) < g.sound_chance))
        play_sound(g.sound, pos);
}

void World::play_sound(int32_t sound, WVec pos) {
    if (sound < 0) return;
    sounds_.push_back({sound, pos});
}

void World::drain_sounds(std::vector<SoundEvent>& out) {
    out.swap(sounds_);
    sounds_.clear();
}

void World::drain_cash_ticks(std::vector<CashTick>& out) {
    out.swap(cash_ticks_);
    cash_ticks_.clear();
}


bool World::in_range(size_t i, size_t target, WDist range) const {
    const WVec d = actors_[target].pos - actors_[i].pos;
    const int64_t reach = int64_t(range) + types_[actors_[target].type].range_radius;
    return length_sq(d) <= reach * reach;
}


uint32_t World::target_mask(size_t k) const {
    const Actor& a = actors_[k];
    const UnitType& t = types_[a.type];


    if (t.aircraft && airs_[k].alt >= 1) return t.target_types_airborne;


    if (t.target_types_underwater != 0 && cloaked(k))
        return t.target_types_underwater | (a.hp < t.hp ? t.target_types_damaged : 0u);
    return t.target_types | (a.hp < t.hp ? t.target_types_damaged : 0u);
}


bool World::weapon_hits(size_t k, const Weapon& w) const {
    if (!types_[actors_[k].type].targetable) return false;
    const uint32_t m = target_mask(k);
    if ((w.invalid_targets & m) != 0) return false;
    return w.valid_targets == 0 || (w.valid_targets & m) != 0;
}


bool World::may_attack(size_t i, size_t k, bool force) const {
    const Actor& a = actors_[i];
    const Actor& v = actors_[k];
    const int32_t wid = types_[a.type].weapon;
    if (wid >= 0 && weapons_[size_t(wid)].relation == REL_ALLY) return allied(a.owner, v.owner);
    if (force) return true;
    if (neutral_player_ >= 0 && (a.owner == neutral_player_ || v.owner == neutral_player_)) return true;
    return !allied(a.owner, v.owner);
}

bool World::force_attacking(int32_t id) const {
    const int i = index_of(id);
    return i >= 0 && combats_[size_t(i)].force_attack;
}

bool World::has_move_order(int32_t id) const {
    const int i = index_of(id);
    if (i < 0) return false;
    const Mobile& m = mobiles_[size_t(i)];
    return m.moving || m.in_transit;
}


int32_t World::armament_for(size_t i, size_t target) const {
    const UnitType& t = types_[actors_[i].type];
    for (int k = 0; k < NUM_ARMS; ++k) {
        const int32_t wid = arm_weapon(t, k);
        if (wid >= 0 && weapon_hits(target, weapons_[wid])) return wid;
    }
    return t.weapon;
}


WDist World::max_weapon_range(const UnitType& t) const {
    WDist r = 0;
    for (int k = 0; k < NUM_ARMS; ++k) {
        const int32_t wid = arm_weapon(t, k);
        if (wid >= 0 && weapons_[wid].range > r) r = weapons_[wid].range;
    }
    return r;
}


int World::nearest_enemy_in_range(size_t i, WDist range, bool auto_scan, bool require_arc) const {
    int best = -1;
    int64_t best_d = INT64_MAX;
    const Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    if (t.weapon < 0) return -1;
    const Weapon& w = weapons_[t.weapon];

    const bool ally = (w.relation == REL_ALLY);
    if (auto_scan && (t.no_auto_target || combats_[i].stance <= STANCE_RETURN_FIRE)) return -1;
    const uint32_t base_mask = t.auto_target_mask != 0 ? t.auto_target_mask : AUTO_DEFEND;


    const bool defense_building = t.building && t.weapon >= 0;
    const uint32_t stance = (combats_[i].stance >= STANCE_ATTACK_ANYTHING || defense_building)
            ? (base_mask | TT_STRUCTURE) : base_mask;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& o = actors_[k];

        if (!in_world(k) || k == i) continue;
        if (ally) {
            if (!allied(a.owner, o.owner) || o.hp >= types_[o.type].hp) continue;
        } else if (!hostile(a.owner, o.owner)) {
            continue;
        }

        if (!ally && cloaked(k) && !detected_by(a.owner, k)) continue;


        if (auto_scan && !ally && o.disguise_type >= 0 && !t.ignores_disguise &&
            !hostile(a.owner, o.disguise_owner)) continue;
        if (!in_range(i, k, range)) continue;


        bool any_arm = false;
        for (int arm = 0; arm < NUM_ARMS && !any_arm; ++arm) {
            const int32_t wid = arm_weapon(t, arm);
            if (wid < 0 || !weapon_hits(k, weapons_[wid])) continue;

            if (weapons_[wid].min_range > 0 && in_range(i, k, weapons_[wid].min_range)) continue;
            any_arm = true;
        }
        if (!any_arm) continue;


        if (require_arc && !in_firing_arc(i, k)) continue;
        if (auto_scan && !ally) {
            const uint32_t m = target_mask(k);

            if ((m & TT_NO_AUTO_TARGET) != 0 || (m != 0 && (m & stance) == 0)) continue;
        }
        const int64_t d = length_sq(o.pos - a.pos);
        if (d < best_d) {
            best_d = d;
            best = static_cast<int>(k);
        }
    }
    return best;
}


void World::order_guard(const int32_t* ids, size_t n, int32_t target_id) {
    const int ti = index_of(target_id);
    if (ti < 0 || !actors_[ti].alive) return;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || types_[actors_[i].type].building) continue;
        if (i == ti) continue;
        Combat& c = combats_[i];
        c.guard = target_id;
        c.target = -1;
        c.attack_cell = CPos{-1, -1};
        c.force_attack = false;
        c.attack_move = types_[actors_[i].type].weapon >= 0;
        c.am_goal = CPos{-1, -1};
    }
}


void World::order_attack_cell(const int32_t* ids, size_t n, CPos cell) {
    if (!map_.in_bounds(cell)) return;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || types_[actors_[i].type].weapon < 0) continue;
        Combat& c = combats_[i];
        c.attack_cell = cell;


        c.force_attack = true;
        c.target = -1;
        c.guard = -1;
        c.attack_move = false;
        cancel_unload(size_t(i));
        stop(i, false);
    }
}

void World::order_attack(const int32_t* ids, size_t n, int32_t target_id, bool force) {
    const int ti = index_of(target_id);
    if (ti < 0 || !actors_[ti].alive) return;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || types_[actors_[i].type].weapon < 0) continue;
        if (i == ti) continue;


        if (!may_attack(size_t(i), size_t(ti), force)) continue;
        Combat& c = combats_[i];
        c.force_attack = force;
        c.target = target_id;
        c.auto_target = false;
        c.attack_move = false;
        c.guard = -1;
        c.attack_cell = CPos{-1, -1};
        c.chase_cell = {-1, -1};
        c.charge_wait = types_[actors_[i].type].initial_charge_delay;
        cancel_unload(size_t(i));
        stop(i, false);
    }
}


void World::order_attack_move(const int32_t* ids, size_t n, CPos goal) {
    order_move(ids, n, goal, 8);
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0) continue;
        Combat& c = combats_[i];
        c.attack_move = types_[actors_[i].type].weapon >= 0;
        c.am_goal = mobiles_[i].goal;
        c.target = -1;
    }
}

void World::fire(size_t i, size_t target, int32_t weapon_id, int32_t arm, bool force) {
    fire_at(i, actors_[target].pos, airs_[target].alt, weapon_id >= 0 ? weapon_id : armament_for(i, target),
            actors_[target].id, arm, force);
}

void World::fire_at(size_t i, WVec aim_at, WDist target_alt, int32_t weapon_override, int32_t target_actor_id,
                    int32_t arm_index, bool force) {
    Actor& a = actors_[i];
    Combat& c = combats_[i];


    a.disguise_type = -1;
    a.disguise_owner = -1;
    const UnitType& ut = types_[a.type];
    const int32_t weapon_id = weapon_override >= 0 ? weapon_override : ut.weapon;


    int arm = arm_index;
    if (arm < 0) {
        arm = 0;
        for (int k = 0; k < NUM_ARMS; ++k) if (arm_weapon(ut, k) == weapon_id) { arm = k; break; }
    }
    const Weapon& w = weapons_[weapon_id];
    const bool missile = w.speed > 0 && w.proj_missile;


    const bool lock_on = missile && static_cast<int32_t>(rand() % 100) < w.missile_lock_on_probability;


    const WDist scatter = (missile && lock_on && w.missile_lock_on_inaccuracy >= 0)
                               ? w.missile_lock_on_inaccuracy : w.inaccuracy;
    WVec aim = aim_at;
    if (scatter > 0) {
        auto pdf = [&]() {
            const int32_t a = static_cast<int32_t>(rand() % 2048u) - 1024;
            const int32_t b = static_cast<int32_t>(rand() % 2048u) - 1024;
            return (a + b) / 2;
        };
        aim.x += static_cast<WDist>(int64_t(pdf()) * scatter / 1024);
        aim.y += static_cast<WDist>(int64_t(pdf()) * scatter / 1024);
    }

    play_sound(w.report_sound, a.pos);


    if (w.zap_duration > 0) zaps_.push_back({a.pos, aim, weapon_id, w.zap_duration});
    if (w.speed <= 0) {
        impact(aim, weapon_id, a.id, a.owner, target_alt, 0, force);
    } else {
        Projectile p;
        p.pos = a.pos;
        p.alt = airs_[i].alt;
        p.target_alt = target_alt;
        p.target = aim;
        p.weapon = weapon_id;
        p.owner = a.owner;
        p.source = a.id;
        p.facing = angle_of(aim - a.pos);
        p.force = force;
        if (missile) p.track_target = lock_on ? target_actor_id : -1;
        projectiles_.push_back(p);
    }

    if (c.burst_at(arm) <= 0) c.burst_at(arm) = w.burst;
    --c.burst_at(arm);

    c.reload_at(arm) = c.burst_at(arm) > 0 ? w.burst_delay
                                           : std::max(1, w.reload * rank_bonus(i).reload / 100);
    c.since_at(arm) = 0;
    c.fire_anim = FIRE_ANIM_TICKS;


    if (arm == 0) c.barrel_flip = !c.barrel_flip;
    uncloak(i, UNCLOAK_ATTACK);
}


bool World::is_idle(size_t i) const {
    const Actor& a = actors_[i];
    if (!a.alive) return false;
    const Combat& c = combats_[i];
    const Mobile& m = mobiles_[i];
    if (m.moving || m.in_transit) return false;
    if (!order_queue_[i].empty()) return false;
    if (c.target >= 0 || c.attack_move || c.guard >= 0 || map_.in_bounds(c.attack_cell)) return false;
    if (c.leap_ticks >= 0) return false;
    if (a.enter_target >= 0 || a.unloading) return false;
    if (types_[a.type].harvester && harvests_[i].state != Harvest::IDLE) return false;
    if (types_[a.type].aircraft && (airs_[i].has_goal || airs_[i].returning)) return false;
    return true;
}


bool World::in_firing_arc(size_t i, size_t target) const {
    const UnitType& t = types_[actors_[i].type];
    if (t.turreted || t.building) return true;
    const WVec d = actors_[target].pos - actors_[i].pos;
    if (d.x == 0 && d.y == 0) return true;
    return abs_angle_diff(actors_[i].facing, angle_of(d)) <= t.facing_tolerance;
}


bool World::opportunity_armed(size_t i, size_t target) const {
    const UnitType& t = types_[actors_[i].type];
    for (int k = 0; k < NUM_ARMS; ++k) {
        const int32_t wid = arm_weapon(t, k);
        if (wid < 0 || !weapon_hits(target, weapons_[wid])) continue;
        const Weapon& w = weapons_[wid];
        if (!in_range(i, target, w.range)) continue;
        if (w.min_range > 0 && in_range(i, target, w.min_range)) continue;
        return true;
    }
    return false;
}


bool World::step_opportunity_fire(size_t i) {
    Actor& a = actors_[i];
    Combat& c = combats_[i];
    const UnitType& t = types_[a.type];

    if (t.weapon < 0 || t.no_auto_target || c.stance < STANCE_DEFEND) { c.opp_target = -1; return false; }

    if (t.max_charges > 0 || t.leap) { c.opp_target = -1; return false; }
    if (t.needs_power && !powered(i)) { c.opp_target = -1; return false; }


    int ti = c.opp_target >= 0 ? index_of(c.opp_target) : -1;
    if (ti >= 0 && (!in_world(size_t(ti)) || !actors_[ti].alive || !may_attack(i, size_t(ti), false) ||
                    !in_firing_arc(i, size_t(ti)) || !opportunity_armed(i, size_t(ti)))) {
        ti = -1;
        c.opp_target = -1;
    }
    if (ti < 0) {

        if (c.scan > 0) { --c.scan; return false; }
        c.scan = SCAN_MIN + static_cast<int32_t>(rand() % (SCAN_MAX - SCAN_MIN));
        const int found = nearest_enemy_in_range(i, max_weapon_range(t), true, true);
        if (found < 0 || !opportunity_armed(i, size_t(found))) return false;
        ti = found;
        c.opp_target = actors_[found].id;
    }

    const Actor& v = actors_[ti];
    const WAngle want = angle_of(v.pos - a.pos);


    bool turret_ready[MAX_TURRETS] = {false, false};
    if (t.turreted) {
        for (int k = 0; k < t.turret_count; ++k) {
            c.turret_at(k) = turn_towards(c.turret_at(k), want, t.turret_turn);
            turret_ready[k] = abs_angle_diff(c.turret_at(k), want) <= AIM_TOLERANCE;
        }
        c.realign = 0;
    } else {
        const bool ok = abs_angle_diff(a.facing, want) <= t.facing_tolerance;
        turret_ready[0] = turret_ready[1] = ok;
    }

    for (int k = 0; k < NUM_ARMS; ++k) {
        const int32_t wid = arm_weapon(t, k);
        if (wid < 0 || c.reload_at(k) > 0) continue;
        if (!weapon_hits(size_t(ti), weapons_[wid])) continue;
        if (!turret_ready[t.arm_turret[k] < t.turret_count ? t.arm_turret[k] : 0]) continue;
        const Weapon& wk = weapons_[wid];
        if (!in_range(i, size_t(ti), wk.range)) continue;
        if (wk.min_range > 0 && in_range(i, size_t(ti), wk.min_range)) continue;
        fire(i, size_t(ti), wid, k, false);
    }
    return true;
}

void World::step_combat(size_t i) {
    Actor& a = actors_[i];
    Combat& c = combats_[i];
    Mobile& m = mobiles_[i];
    const UnitType& t = types_[a.type];

    if (t.aircraft) { step_air_combat(i); return; }


    if (c.leap_ticks >= 0) { step_leap(i); return; }

    if (airs_[i].alt > 0) return;
    if (t.weapon < 0) return;

    if (t.needs_power && !powered(i)) {
        c.target = -1;
        return;
    }
    const Weapon& w = weapons_[t.weapon];

    if (c.fire_anim > 0) --c.fire_anim;
    for (int k = 0; k < NUM_ARMS; ++k) {
        const int32_t wid = arm_weapon(t, k);
        if (wid < 0) continue;
        if (c.reload_at(k) > 0) --c.reload_at(k);

        if (c.burst_at(k) > 0 && ++c.since_at(k) >= weapons_[wid].reload) c.burst_at(k) = 0;
    }

    if (t.max_charges > 0) {
        if (c.recharge > 0) --c.recharge;
        if (c.recharge <= 0) c.charges = t.max_charges;
    }


    int ti = c.target >= 0 ? index_of(c.target) : -1;
    if (ti >= 0 && !actors_[ti].alive) {
        ti = -1;
        c.target = -1;
        c.force_attack = false;
    }


    if (ti >= 0 && !may_attack(i, size_t(ti), c.force_attack)) {
        ti = -1;
        c.target = -1;
        c.force_attack = false;
    }


    if (ti < 0) {
        const bool may_scan = (!m.moving && !m.in_transit) || c.attack_move;
        if (may_scan) {
            if (c.scan > 0) {
                --c.scan;
            } else {
                c.scan = SCAN_MIN + static_cast<int32_t>(rand() % (SCAN_MAX - SCAN_MIN));
                const int found = nearest_enemy_in_range(i, max_weapon_range(t), true);
                if (found >= 0) {
                    ti = found;
                    c.target = actors_[found].id;
                    c.auto_target = true;
                    c.force_attack = false;
                    c.charge_wait = t.initial_charge_delay;
                }
            }
        }
    }

    if (ti < 0 && map_.in_bounds(c.attack_cell)) {

        const WVec aim = cell_center(c.attack_cell);
        const int64_t d = length(aim - a.pos);
        if (d > w.range) {


            if (t.building) { c.attack_cell = CPos{-1, -1}; c.force_attack = false; return; }
            if (!m.moving) set_move(i, c.attack_cell, w.range / CELL);
            return;
        }
        if (w.min_range > 0 && d < w.min_range) return;
        if (m.moving) stop(i, false);
        const WAngle want_cell = angle_of(aim - a.pos);
        bool ok;
        bool turret_ok[MAX_TURRETS] = {false, false};
        if (t.turreted) {
            ok = false;
            for (int k = 0; k < t.turret_count; ++k) {
                c.turret_at(k) = turn_towards(c.turret_at(k), want_cell, t.turret_turn);
                turret_ok[k] = abs_angle_diff(c.turret_at(k), want_cell) <= AIM_TOLERANCE;
                if (turret_ok[k]) ok = true;
            }
            c.realign = 0;
        } else if (t.building) {
            ok = true;
        } else {
            if (!m.in_transit) a.facing = t.infantry ? want_cell : turn_towards(a.facing, want_cell, t.turn_rate);
            ok = abs_angle_diff(a.facing, want_cell) <= t.facing_tolerance;
        }
        if (!t.turreted) { turret_ok[0] = ok; turret_ok[1] = ok; }


        if (!ok) return;
        for (int k = 0; k < NUM_ARMS; ++k) {
            const int32_t wid = arm_weapon(t, k);
            if (wid < 0 || c.reload_at(k) > 0) continue;
            if (!turret_ok[t.arm_turret[k] < t.turret_count ? t.arm_turret[k] : 0]) continue;
            const Weapon& wk = weapons_[wid];


            if ((wk.valid_targets & (TT_GROUND_ACTOR | TT_WATER_ACTOR)) == 0) continue;
            if (d > wk.range || (wk.min_range > 0 && d < wk.min_range)) continue;
            fire_at(i, aim, 0, wid, -1, k, true);
        }
        return;
    }

    if (ti < 0 && c.guard >= 0) {

        const int gi = index_of(c.guard);
        if (gi < 0 || !actors_[gi].alive) {
            c.guard = -1;
        } else {
            const CPos gc = types_[actors_[gi].type].building ? actors_[gi].origin : mobiles_[gi].cell;
            if (cell_dist_sq(m.cell, gc) > 4 && (!m.moving || gc != c.am_goal)) {
                set_move(i, gc, 2);
                c.am_goal = gc;
            }
            if (t.turreted && !m.moving) {
                if (c.realign < t.realign_delay) ++c.realign;
                else for (int k = 0; k < t.turret_count; ++k)
                    c.turret_at(k) = turn_towards(c.turret_at(k), a.facing, t.turret_turn);
            }
            return;
        }
    }

    if (ti < 0) {

        if (c.attack_move && map_.in_bounds(c.am_goal) && !m.moving && !m.in_transit && m.cell != c.am_goal) set_move(i, c.am_goal, 8);


        if (m.moving || m.in_transit) {
            if (step_opportunity_fire(i)) return;
        } else {
            c.opp_target = -1;
        }

        if (t.turreted) {
            if (c.realign < t.realign_delay) ++c.realign;
            else for (int k = 0; k < t.turret_count; ++k)
                c.turret_at(k) = turn_towards(c.turret_at(k), a.facing, t.turret_turn);
        }
        if (t.max_charges > 0) c.charge_wait = t.initial_charge_delay;
        return;
    }

    const Actor& v = actors_[ti];


    int32_t arms[NUM_ARMS];
    bool any_in_range = false, any_too_close = false, any_hits = false;
    for (int k = 0; k < NUM_ARMS; ++k) {
        arms[k] = -1;
        const int32_t wid = arm_weapon(t, k);
        if (wid < 0 || !weapon_hits(ti, weapons_[wid])) continue;
        arms[k] = wid;
        any_hits = true;
        const Weapon& wk = weapons_[wid];
        if (wk.min_range > 0 && in_range(i, ti, wk.min_range)) any_too_close = true;
        else if (in_range(i, ti, wk.range)) any_in_range = true;
    }
    if (!any_hits) {
        c.target = -1;
        c.force_attack = false;
        return;
    }
    const bool too_close = !any_in_range && any_too_close;
    if (!any_in_range) {
        if (c.auto_target) {


            if (c.stance < STANCE_ATTACK_ANYTHING || too_close) {
                c.target = -1;
                c.force_attack = false;
                return;
            }
        }
        if (too_close) return;


        if (t.building) {
            c.target = -1;
            c.force_attack = false;
            return;
        }


        const CPos tc = to_cell(v.pos);
        const CPos block{tc.x >> 1, tc.y >> 1};
        if (!m.moving || block != c.chase_cell) {
            set_move(i, tc, 0);
            c.chase_cell = block;
        }
        return;
    }


    if (m.moving) stop(i, false);
    const WAngle want = angle_of(v.pos - a.pos);
    bool ready;

    bool turret_ready[MAX_TURRETS] = {false, false};
    if (t.turreted) {


        for (int k = 0; k < t.turret_count; ++k) {
            c.turret_at(k) = turn_towards(c.turret_at(k), want, t.turret_turn);
            turret_ready[k] = abs_angle_diff(c.turret_at(k), want) <= AIM_TOLERANCE;
        }
        c.realign = 0;
        ready = turret_ready[0] || (t.turret_count > 1 && turret_ready[1]);
    } else if (t.building) {
        ready = true;
    } else {
        if (!m.in_transit) a.facing = t.infantry ? want : turn_towards(a.facing, want, t.turn_rate);
        ready = abs_angle_diff(a.facing, want) <= t.facing_tolerance;
    }
    if (!t.turreted) { turret_ready[0] = ready; turret_ready[1] = ready; }


    if (t.max_charges > 0) {
        if (c.charges <= 0) {
            c.charge_wait = t.initial_charge_delay;
            return;
        }
        if (c.charge_wait > 0) {


            if (c.charge_wait == t.initial_charge_delay) {
                play_sound(t.charge_sound, a.pos);
                a.active_ticks = t.initial_charge_delay;
                a.active_anim = 0;
            }
            --c.charge_wait;
            return;
        }
    }
    if (!ready) return;


    if (t.leap) {
        if (arms[0] < 0 || c.reload_at(0) > 0) return;
        if (!in_range(i, ti, weapons_[arms[0]].range)) return;
        start_leap(i, static_cast<size_t>(ti));
        return;
    }

    for (int k = 0; k < NUM_ARMS; ++k) {
        if (arms[k] < 0 || c.reload_at(k) > 0) continue;

        if (!turret_ready[t.arm_turret[k] < t.turret_count ? t.arm_turret[k] : 0]) continue;
        const Weapon& wk = weapons_[arms[k]];
        if (!in_range(i, ti, wk.range)) continue;
        if (wk.min_range > 0 && in_range(i, ti, wk.min_range)) continue;
        fire(i, ti, arms[k], k, c.force_attack);
        if (t.max_charges > 0) {
            --c.charges;
            c.recharge = t.charge_reload;
            c.charge_wait = t.charge_delay;
        }
    }
}


void World::start_leap(size_t i, size_t target) {
    Actor& a = actors_[i];
    Combat& c = combats_[i];
    Mobile& m = mobiles_[i];
    const UnitType& t = types_[a.type];
    const Actor& v = actors_[target];
    c.leap_origin = a.pos;
    c.leap_last_target = v.pos;
    c.leap_dest_cell = mobiles_[target].cell;
    const int32_t dist = length(v.pos - a.pos);
    const WDist speed = t.leap_speed > 0 ? t.leap_speed : 1;
    c.leap_len = std::max(1, dist / speed);
    c.leap_ticks = 0;
    a.facing = angle_of(v.pos - a.pos);
    m.in_transit = false;
    stop(i, false);
    clear_slots(i);
}


void World::step_leap(size_t i) {
    Actor& a = actors_[i];
    Combat& c = combats_[i];
    const int ti = c.target >= 0 ? index_of(c.target) : -1;
    if (ti >= 0 && actors_[size_t(ti)].alive && in_world(size_t(ti))) c.leap_last_target = actors_[size_t(ti)].pos;
    const int32_t len = c.leap_len;
    a.pos = len > 1 ? WVec{lerp_axis(c.leap_origin.x, c.leap_last_target.x, c.leap_ticks, len - 1),
                           lerp_axis(c.leap_origin.y, c.leap_last_target.y, c.leap_ticks, len - 1)}
                     : c.leap_last_target;
    if (++c.leap_ticks >= len) land_leap(i, ti);
}


void World::land_leap(size_t i, int target) {
    Actor& a = actors_[i];
    Combat& c = combats_[i];
    Mobile& m = mobiles_[i];
    const int32_t self = static_cast<int32_t>(i);
    const CPos want = c.leap_dest_cell;
    const CPos land = (map_.in_bounds(want) && cell_free(want, self)) ? want : find_free_cell(want, a.type);
    const int32_t sub = shares_cell(a.type) ? std::max(int32_t(SUB_FIRST), free_subcell(land, SUB_DEFAULT, self))
                                             : int32_t(SUB_FULL);
    m.cell = land;
    m.to_cell = land;
    m.goal = land;
    m.sub = sub;
    m.to_sub = sub;
    a.pos = subcell_center(land, sub);
    if (map_.in_bounds(land)) slot_at(map_.index(land), sub) = self;
    c.leap_ticks = -1;
    c.leap_lock = types_[a.type].leap_lock_ticks;
    if (target >= 0 && actors_[size_t(target)].alive && in_world(size_t(target))) fire(i, size_t(target));
}

void World::step_projectiles() {
    for (Projectile& p : projectiles_) {
        const Weapon& w = weapons_[p.weapon];
        if (w.proj_missile) { step_missile(p); continue; }
        const WVec d = p.target - p.pos;
        const int32_t len = length(d);
        if (len <= w.speed) {
            p.pos = p.target;
            p.alt = p.target_alt;
            impact(p.pos, p.weapon, p.source, p.owner, p.alt, 0, p.force);
            p.alive = false;
        } else {
            p.pos.x += static_cast<WDist>(int64_t(d.x) * w.speed / len);
            p.pos.y += static_cast<WDist>(int64_t(d.y) * w.speed / len);

            p.alt += static_cast<WDist>(int64_t(p.target_alt - p.alt) * w.speed / len);
        }
    }
    size_t k = 0;
    for (size_t i = 0; i < projectiles_.size(); ++i) {
        if (projectiles_[i].alive) projectiles_[k++] = projectiles_[i];
    }
    projectiles_.resize(k);
}


void World::step_missile(Projectile& p) {
    const Weapon& w = weapons_[p.weapon];
    if (p.track_target >= 0) {
        const int ti = index_of(p.track_target);
        if (ti >= 0 && actors_[ti].alive) {
            p.target = actors_[ti].pos;
            p.target_alt = airs_[ti].alt;
        }
    }
    ++p.ticks_alive;
    const WVec to_target = p.target - p.pos;
    const int32_t dist = length(to_target);
    const WAngle want = angle_of(to_target);
    p.facing = turn_towards(p.facing, want, w.missile_turn_rate);
    const WVec dir = direction_of(p.facing);
    p.pos.x += static_cast<WDist>(int64_t(dir.x) * w.speed / 1024);
    p.pos.y += static_cast<WDist>(int64_t(dir.y) * w.speed / 1024);
    if (dist > 0) p.alt += static_cast<WDist>(int64_t(p.target_alt - p.alt) * w.speed / dist);
    else p.alt = p.target_alt;
    p.distance_covered += w.speed;

    if (w.missile_trail_effect >= 0) {
        if (p.trail_wait > 0) {
            --p.trail_wait;
        } else {
            spawn_effect(p.pos, w.missile_trail_effect, p.facing, p.alt);
            p.trail_wait = w.missile_trail_interval;
        }
    }
    const int32_t limit = w.missile_range_limit > 0 ? w.missile_range_limit : w.range;
    const bool close_enough = dist <= w.missile_close_enough;
    const bool out_of_fuel = p.distance_covered > limit;
    if (close_enough || out_of_fuel) {
        if (p.ticks_alive > w.missile_arm) impact(p.pos, p.weapon, p.source, p.owner, p.alt, 0, p.force);
        p.alive = false;
    }
}


void World::step_zaps() {
    size_t k = 0;
    for (size_t i = 0; i < zaps_.size(); ++i) {
        if (--zaps_[i].ticks > 0) zaps_[k++] = zaps_[i];
    }
    zaps_.resize(k);
}

void World::step_effects() {
    size_t k = 0;
    for (size_t i = 0; i < effects_.size(); ++i) {
        Effect e = effects_[i];
        const EffectSeq& s = effects_def_[e.seq];
        if (++e.ticks >= s.ticks_per_frame) {
            e.ticks = 0;
            ++e.frame;
        }
        if (e.frame < s.length) effects_[k++] = e;
    }
    effects_.resize(k);
}


bool World::vt_targetable(size_t k) const { return types_[actors_[k].type].targetable; }


void World::apply_damage_warhead(WVec pos, int32_t attacker_id, int32_t attacker_owner, WDist spread,
                                  int32_t damage, const int32_t* falloff, int32_t falloff_steps,
                                  const int32_t* versus, uint32_t valid_targets, uint32_t invalid_targets,
                                  int32_t relation, bool hits_allies, int32_t damage_type, bool trigger_prone,
                                  int32_t prone_damage, bool damage_percent) {

    const int64_t max_range = int64_t(spread) * (falloff_steps - 1);
    const bool ally_weapon = (relation == REL_ALLY);
    const int attacker_index = index_of(attacker_id);


    const size_t n_actors = actors_.size();
    for (size_t k = 0; k < n_actors && k < actors_.size(); ++k) {
        Actor& v = actors_[k];
        if (!in_world(k)) continue;


        const bool neutral_hit = neutral_player_ >= 0
            && (attacker_owner == neutral_player_ || v.owner == neutral_player_);
        const bool hits_all = hits_allies || neutral_hit;
        if (ally_weapon ? !allied(attacker_owner, v.owner) : (allied(attacker_owner, v.owner) && !hits_all)) continue;
        const UnitType& vt = types_[v.type];


        if (!vt.targetable) continue;
        const uint32_t m = target_mask(k);
        if ((invalid_targets & m) != 0) continue;
        if (!(valid_targets == 0 || (valid_targets & m) != 0)) continue;
        int64_t dist = length(v.pos - pos) - vt.hit_radius;
        if (dist < 0) dist = 0;
        if (dist > max_range) continue;

        const int64_t step = dist / spread;
        const int64_t f0 = falloff[step];
        const int64_t rem = dist - step * spread;
        const int64_t f1 = falloff[step + 1 < falloff_steps ? step + 1 : step];
        const int64_t fo = f0 + (f1 - f0) * rem / spread;


        const int64_t base = damage_percent ? int64_t(vt.hp) * damage / 100 : int64_t(damage);
        int64_t dmg = base * fo / 100 * versus[vt.armor] / 100;

        if (attacker_index >= 0) dmg = dmg * rank_bonus(size_t(attacker_index)).firepower / 100;
        dmg = dmg * rank_bonus(k).damage / 100;


        const int32_t hc_att = handicap(attacker_owner), hc_vic = handicap(v.owner);
        if (hc_att != 0) dmg = dmg * (100 - hc_att) / 100;
        if (hc_vic != 0) dmg = dmg * 100 / (100 - hc_vic);

        if (v.prone_ticks > 0 && prone_damage != 100) dmg = dmg * prone_damage / 100;
        if (dmg == 0) continue;
        if (v.invulnerable_ticks > 0 && dmg > 0) continue;
        if (dmg < 0) {
            v.hp = static_cast<int32_t>(std::min<int64_t>(vt.hp, v.hp - dmg));
            continue;
        }
        const int32_t hp_before = v.hp;
        v.hp -= static_cast<int32_t>(dmg);
        note_damage_transition(k, hp_before);


        v.last_attacker = attacker_id;
        v.last_attacker_owner = attacker_owner;
        v.last_damage_type = damage_type;
        v.heal_cooldown = vt.elite_heal_cooldown;
        v.self_heal_cooldown = vt.heal_damage_cooldown;

        if (trigger_prone && vt.takes_cover) v.prone_ticks = vt.prone_duration;
        bot_on_attack(k, attacker_id);


        Combat& vc = combats_[k];
        if (is_idle(k) && vc.stance > STANCE_HOLD_FIRE && vt.weapon >= 0 && weapons_[vt.weapon].relation == REL_ENEMY) {
            const int ai = index_of(attacker_id);
            if (ai >= 0 && actors_[ai].alive && in_range(k, ai, weapons_[vt.weapon].range)) {
                vc.target = attacker_id;
                vc.auto_target = true;
            }
        }
        if (v.hp <= 0) kill(k, damage_type, attacker_id);
    }
}


void World::apply_destroy_resource(WVec pos, int32_t size_cells) {
    if (size_cells <= 0) return;
    const CPos center = to_cell(pos);
    for (int32_t dy = -size_cells; dy <= size_cells; ++dy) {
        for (int32_t dx = -size_cells; dx <= size_cells; ++dx) {
            if (dx * dx + dy * dy > size_cells * size_cells) continue;
            const CPos c{center.x + dx, center.y + dy};
            if (!map_.in_bounds(c) || resource_type(c) == RES_NONE) continue;
            set_resource(c, RES_NONE, 0);
        }
    }
}


void World::apply_smudge_warhead(WVec pos, const Weapon& w, int32_t attacker_id) {
    (void)attacker_id;
    if (w.smudge_type == SMUDGE_NONE) return;
    if (w.smudge_chance < 100 && int32_t(rand() % 100u) >= w.smudge_chance) return;
    const CPos center = to_cell(pos);
    const int32_t outer = w.smudge_size > 0 ? w.smudge_size : 0;
    const int32_t inner = w.smudge_size_inner > 0 ? w.smudge_size_inner : 0;


    const int64_t out2 = int64_t(outer) * outer;
    const int64_t in2 = inner > 0 ? int64_t(inner - 1) * (inner - 1) : -1;
    for (int32_t dy = -outer; dy <= outer; ++dy) {
        for (int32_t dx = -outer; dx <= outer; ++dx) {
            const int64_t d2 = int64_t(dx) * dx + int64_t(dy) * dy;
            if (d2 > out2 || d2 <= in2) continue;
            const CPos c{center.x + dx, center.y + dy};
            if (!map_.in_bounds(c)) continue;


            if (!terrain_accepts_smudge(map_.terrain(c))) continue;


            bool blocked = false;
            for (int sub = 0; sub < CELL_SLOTS && !blocked; ++sub) {
                const int32_t k = occupant(c, sub);
                if (k < 0 || size_t(k) >= actors_.size() || !actors_[size_t(k)].alive) continue;
                const uint32_t m = target_mask(size_t(k));
                if ((w.smudge_invalid_targets & m) != 0) blocked = true;
                else if (w.smudge_valid_targets != 0 && (w.smudge_valid_targets & m) == 0) blocked = true;
            }
            if (blocked) continue;
            add_smudge(c, w.smudge_type);
        }
    }
}

void World::impact(WVec pos, int32_t weapon_id, int32_t attacker_id, int32_t attacker_owner, WDist alt,
                   int32_t depth, bool force) {
    const Weapon& w = weapons_[weapon_id];


    if (w.cluster_weapon >= 0 && depth == 0) {
        const CPos c = to_cell(pos);
        for (int32_t k = 0; k < w.cluster_count; ++k) {
            const CPos t{c.x + w.cluster_dx[k], c.y + w.cluster_dy[k]};
            if (map_.in_bounds(t)) impact(cell_center(t), w.cluster_weapon, attacker_id, attacker_owner, alt, depth + 1, force);
        }
    }


    for (int32_t i = 0; i < w.impact_effect_count; ++i) {
        const ImpactEffect& g = w.impact_effects[i];
        if (g.delay <= 0) apply_effect_warhead(pos, g, attacker_id, alt);
        else pending_impacts_.push_back({pos, weapon_id, PendingImpact::EFFECT, i, attacker_id,
                                          attacker_owner, alt, g.delay, force});
    }
    if (w.delay <= 0) {


        apply_damage_warhead(pos, attacker_id, attacker_owner, w.spread, w.damage, w.falloff, w.falloff_steps,
                              w.versus, w.valid_targets, w.invalid_targets, w.relation, w.hits_allies || force,
                              w.damage_type, w.trigger_prone, w.prone_damage, w.damage_percent);
    } else {

        pending_impacts_.push_back({pos, weapon_id, PendingImpact::DAMAGE, -1, attacker_id, attacker_owner,
                                     alt, w.delay, force});
    }


    for (int32_t i = 0; i < w.extra_warhead_count; ++i) {
        const ExtraWarhead& e = w.extra_warheads[i];
        if (e.delay <= 0) {
            apply_damage_warhead(pos, attacker_id, attacker_owner, e.spread, e.damage, e.falloff,
                                  e.falloff_steps, e.versus, e.valid_targets, e.invalid_targets,
                                  w.relation, w.hits_allies || force, w.damage_type, e.trigger_prone, e.prone_damage);
        } else {
            pending_impacts_.push_back({pos, weapon_id, PendingImpact::DAMAGE, i, attacker_id, attacker_owner,
                                         alt, e.delay, force});
        }
    }


    if (w.smudge_type != SMUDGE_NONE && alt <= 0) apply_smudge_warhead(pos, w, attacker_id);
    for (int32_t i = 0; i < w.destroy_resource_count; ++i) {
        const DestroyResourceWarhead& d = w.destroy_resource[i];
        if (d.delay <= 0) apply_destroy_resource(pos, d.size);
        else pending_impacts_.push_back({pos, weapon_id, PendingImpact::DESTROY_RESOURCE, i, attacker_id,
                                          attacker_owner, alt, d.delay});
    }
}


void World::step_pending_impacts() {
    size_t k = 0;
    for (size_t i = 0; i < pending_impacts_.size(); ++i) {
        PendingImpact& p = pending_impacts_[i];
        if (--p.ticks > 0) { pending_impacts_[k++] = p; continue; }
        const Weapon& w = weapons_[p.weapon];
        if (p.kind == PendingImpact::EFFECT && p.index < w.impact_effect_count) {

            apply_effect_warhead(p.pos, w.impact_effects[p.index], p.attacker_id, p.alt);
        } else if (p.kind == PendingImpact::DAMAGE && p.index < 0) {

            apply_damage_warhead(p.pos, p.attacker_id, p.attacker_owner, w.spread, w.damage, w.falloff,
                                  w.falloff_steps, w.versus, w.valid_targets, w.invalid_targets,
                                  w.relation, w.hits_allies || p.force, w.damage_type, w.trigger_prone,
                                  w.prone_damage, w.damage_percent);
        } else if (p.kind == PendingImpact::DAMAGE && p.index < w.extra_warhead_count) {
            const ExtraWarhead& e = w.extra_warheads[p.index];
            apply_damage_warhead(p.pos, p.attacker_id, p.attacker_owner, e.spread, e.damage, e.falloff,
                                  e.falloff_steps, e.versus, e.valid_targets, e.invalid_targets,
                                  w.relation, w.hits_allies || p.force, w.damage_type, e.trigger_prone,
                                  e.prone_damage);
        } else if (p.kind == PendingImpact::DESTROY_RESOURCE && p.index < w.destroy_resource_count) {
            apply_destroy_resource(p.pos, w.destroy_resource[p.index].size);
        }
    }
    pending_impacts_.resize(k);
}


void World::note_damage_transition(size_t i, int32_t hp_before) {
    const Actor& v = actors_[i];
    const UnitType& vt = types_[v.type];
    if (vt.damaged_sound >= 0 && v.hp > 0 && hp_before * 2 >= vt.hp && v.hp * 2 < vt.hp) play_sound(vt.damaged_sound, v.pos);
}

void World::kill(size_t i, int32_t damage_type, int32_t attacker_id) {
    if (!actors_[i].alive) return;


    actors_[i].last_damage_type = damage_type;
    actors_[i].last_attacker = attacker_id;
    const int atk = attacker_id >= 0 ? index_of(attacker_id) : -1;
    actors_[i].last_attacker_owner = atk >= 0 ? actors_[atk].owner : -1;


    bot_stat_note_death(i);
    bot_stat_note_kill(i, attacker_id);

    on_kill_experience(i, attacker_id);


    std::vector<int32_t> doomed;
    if (!types_[actors_[i].type].cargo_eject_on_death) doomed.swap(cargo_[i]);
    const WDist death_alt = airs_[i].alt;


    if (start_fall_to_earth(i)) {
        for (const int32_t pid : doomed) {
            const int p = index_of(pid);
            if (p < 0 || !actors_[p].alive) continue;
            actors_[p].transport = -1;
            kill(size_t(p), damage_type, attacker_id);
        }
        return;
    }
    dispose(i);
    actors_[i].vanished = false;
    for (const int32_t pid : doomed) {
        const int p = index_of(pid);
        if (p < 0 || !actors_[p].alive) continue;
        actors_[p].transport = -1;
        kill(size_t(p), damage_type, attacker_id);
    }
    const Actor a = actors_[i];
    const UnitType& t = types_[a.type];
    const int32_t fx = (damage_type >= 0 && damage_type < NUM_DAMAGE_TYPES && t.death_effect[damage_type] >= 0)
        ? t.death_effect[damage_type] : t.death_effect[DAMAGE_DEFAULT];


    spawn_effect(a.pos, fx, a.facing, death_alt, a.owner);
    play_sound(t.death_sound, a.pos);
    if (t.destroyed_sound >= 0) play_sound(t.destroyed_sound, a.pos);

    if (t.death_weapon >= 0) impact(a.pos, t.death_weapon, a.id, a.owner, death_alt);


    queue_husk(a);
}


void World::queue_husk(const Actor& dead) {
    const UnitType& t = types_[dead.type];
    if (t.husk_actor < 0 || t.husk_actor >= int32_t(types_.size())) return;


    if (dead.inside || dead.transport >= 0) return;


    if (t.aircraft) return;
    if (t.husk_probability < 100 && int32_t(rand() % 100u) >= t.husk_probability) return;
    const CPos c = to_cell(dead.pos);
    if (!map_.in_bounds(c)) return;

    const UnitType& ht = types_[size_t(t.husk_actor)];
    if (ht.husk_terrain != 0 && (ht.husk_terrain & (1u << uint32_t(map_.terrain(c)))) == 0) return;
    pending_husks_.push_back({t.husk_actor, dead.owner, c, dead.facing});
}


void World::step_pending_husks() {
    if (pending_husks_.empty()) return;
    std::vector<PendingHusk> list;
    list.swap(pending_husks_);
    for (const PendingHusk& h : list) {
        const UnitType& ht = types_[size_t(h.type)];
        if (!map_.passable(h.cell, move_class_of(ht.locomotor))) continue;


        bool blocked = false;
        for (int sub = 0; sub < CELL_SLOTS && !blocked; ++sub) {
            const int32_t k = occupant(h.cell, sub);
            if (k < 0 || size_t(k) >= actors_.size() || !actors_[size_t(k)].alive) continue;
            if ((types_[actors_[size_t(k)].type].crush_classes & ht.crushes) == 0) blocked = true;
        }
        if (blocked) continue;
        for (int sub = 0; sub < CELL_SLOTS; ++sub) {
            const int32_t k = occupant(h.cell, sub);
            if (k < 0 || size_t(k) >= actors_.size() || !actors_[size_t(k)].alive) continue;
            kill(size_t(k), DAMAGE_EXPLOSION, -1);
        }
        if (!cell_free(h.cell, -1)) continue;
        spawn(h.type, h.owner, h.cell, h.facing);
    }
}


void World::dispose(size_t i) {
    Actor& a = actors_[i];
    if (!a.alive) return;
    a.alive = false;
    a.hp = 0;
    a.vanished = true;
    a.repairing = false;
    a.sell_ticks = -1;
    a.primary = false;
    Mobile& m = mobiles_[i];
    const int32_t self = static_cast<int32_t>(i);
    const UnitType& t = types_[a.type];
    if (t.building) {

        for (int y = 0; y < t.foot_h; ++y) {
            for (int x = 0; x < t.foot_w; ++x) {
                const CPos c{a.origin.x + x, a.origin.y + y};
                if (!map_.in_bounds(c)) continue;
                if (bib_owner_[map_.index(c)] == self) bib_owner_[map_.index(c)] = -1;
                if (!t.footprint[y * t.foot_w + x]) continue;
                if (slot_at(map_.index(c), SUB_FULL) == self) slot_at(map_.index(c), SUB_FULL) = -1;
                map_.restore_cost(c);
            }
        }
        fields_.clear();


        if (t.reservable) release_pad(a.id);
    } else {
        clear_slots(i);
    }
    m.moving = false;
    m.in_transit = false;
    combats_[i].target = -1;


    while (!cargo_[i].empty()) {
        const CPos at = t.building ? a.origin : m.cell;
        if (unload_passenger(a.id, at) < 0) {

            for (const int32_t pid : cargo_[i]) {
                const int p = index_of(pid);
                if (p >= 0) { actors_[p].transport = -1; dispose(size_t(p)); }
            }
            cargo_[i].clear();
        }
    }
    a.unloading = false;
    a.unload_ticks = -1;
    if (t.harvester) release_claim(i);
    if (t.storage > 0) clamp_storage(a.owner);
}


constexpr int32_t NUKE_FLIGHT_VELOCITY = 512;

void World::render_sprites(int32_t alpha, std::vector<RenderSprite>& out) const {
    (void)alpha;
    for (const Projectile& p : projectiles_) out.push_back({p.pos.x, p.pos.y, p.alt, p.weapon, -1, 0, p.facing});
    for (const Effect& e : effects_) out.push_back({e.pos.x, e.pos.y, e.alt, -1, e.seq, e.frame, e.facing, e.owner});


    for (const PendingNuke& n : pending_nukes_) {
        if (n.type < 0 || size_t(n.type) >= types_.size()) continue;
        const UnitType& t = types_[size_t(n.type)];
        const int32_t total = std::max(1, n.total);
        const int32_t turn = std::max(1, total / 2);
        const int32_t elapsed = std::max(0, total - n.ticks);
        const bool ascending = elapsed < turn;
        const int32_t seq = ascending ? t.sp_launch_effect : t.sp_impact_effect;
        if (seq < 0 || size_t(seq) >= effects_def_.size()) continue;
        const int32_t peak = NUKE_FLIGHT_VELOCITY * (total - turn);
        WVec pos = ascending ? n.launch_pos : n.target;
        WDist alt = ascending
            ? WDist(int64_t(peak) * elapsed / turn)
            : WDist(peak - int64_t(peak) * (elapsed - turn) / std::max(1, total - turn));
        const EffectSeq& es = effects_def_[size_t(seq)];
        const int32_t len = std::max(1, es.length);
        const int32_t frame = (elapsed / std::max(1, es.ticks_per_frame)) % len;
        out.push_back({pos.x, pos.y, alt, -1, seq, frame, 0, -1});
    }
}

uint32_t World::alive_count(int32_t owner) const {
    uint32_t n = 0;
    for (const Actor& a : actors_) n += (a.alive && (owner < 0 || a.owner == owner)) ? 1 : 0;
    return n;
}


int32_t World::bot_stat_army_value(int32_t owner) const {
    int64_t sum = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building || t.husk || t.harvester || t.weapon < 0) continue;
        sum += t.cost;
    }
    return int32_t(std::min<int64_t>(sum, INT32_MAX));
}


int32_t World::bot_stat_towers(int32_t owner) const {
    int32_t n = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (!t.building || !t.defense || a.sell_ticks >= 0) continue;
        ++n;
    }
    return n;
}


void World::bot_stat_sample(int32_t owner) {
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    BotState& b = players_[size_t(owner)].bot;
    if (!b.enabled) return;
    b.stat_army_value = bot_stat_army_value(owner);
    b.stat_towers = bot_stat_towers(owner);
    b.stat_cash_sum += credits(owner);
    ++b.stat_cash_samples;
}


void World::bot_stat_note_death(size_t i) {
    const Actor& dead = actors_[i];
    if (dead.owner < 0 || dead.owner >= MAX_PLAYERS) return;
    BotState& b = players_[size_t(dead.owner)].bot;
    if (!b.enabled) return;
    for (const BotSquad& s : b.squads) {
        if (std::find(s.units.begin(), s.units.end(), dead.id) == s.units.end()) continue;
        ++b.stat_squad_units_lost;
        break;
    }
    if (!bot_unit_is_siege(i)) return;
    ++b.stat_siege_lost;
    const WVec at = dead.pos;
    const int32_t owner = dead.owner;
    for (const Actor& c : actors_) {
        if (!c.alive || !hostile(owner, c.owner)) continue;
        const UnitType& t = types_[c.type];
        if (!t.building || !t.defense) continue;
        const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
        int64_t range = 0;
        for (int32_t wi : arms)
            if (wi >= 0 && size_t(wi) < weapons_.size()) range = std::max<int64_t>(range, weapons_[size_t(wi)].range);
        if (range <= 0) continue;
        if (length(c.pos - at) <= range) { ++b.stat_siege_lost_in_range; break; }
    }
}


void World::bot_stat_note_kill(size_t victim, int32_t attacker_id) {
    const Actor& dead = actors_[victim];
    const UnitType& t = types_[dead.type];
    const bool is_air = t.aircraft && !t.husk;
    const bool is_ship = !t.building && !t.aircraft && !t.husk && t.locomotor == LOCO_NAVAL;
    if (!is_air && !is_ship) return;
    if (dead.owner >= 0 && dead.owner < MAX_PLAYERS) {
        BotState& b = players_[size_t(dead.owner)].bot;
        if (b.enabled) {
            if (is_air) ++b.stat_air_lost;
            if (is_ship) ++b.stat_ships_lost;
        }
    }
    if (!is_ship || attacker_id < 0) return;
    const int ai = index_of(attacker_id);
    if (ai < 0) return;
    const int32_t killer = actors_[size_t(ai)].owner;
    if (killer < 0 || killer >= MAX_PLAYERS || killer == dead.owner) return;
    BotState& kb = players_[size_t(killer)].bot;
    if (kb.enabled) ++kb.stat_ships_killed;
}

}
