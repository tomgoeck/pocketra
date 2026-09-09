

#include <algorithm>

#include "ra/sim.h"

namespace ra {


int32_t World::level_threshold(int32_t type, int32_t level) const {
    const UnitType& t = types_[type];
    if (level < 1 || level > t.xp_levels) return 0;
    const int32_t value = t.cost > 0 ? t.cost : 1;
    return t.xp_required[level - 1] * value;
}

const RankBonus& World::rank_bonus(size_t i) const {
    static const RankBonus none;
    if (i >= actors_.size()) return none;
    const Actor& a = actors_[i];
    if (a.level <= 0) return none;
    const UnitType& t = types_[a.type];
    const int32_t lvl = std::min(a.level, t.xp_levels);
    return t.ranks[std::min(lvl, MAX_RANKS) - 1];
}


void World::give_experience(size_t i, int32_t amount) {
    if (i >= actors_.size() || amount <= 0) return;
    Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    if (t.xp_levels <= 0) return;
    const int32_t cap = level_threshold(a.type, t.xp_levels);
    a.experience = std::min(cap, a.experience + amount);
    while (a.level < t.xp_levels && a.experience >= level_threshold(a.type, a.level + 1)) {
        ++a.level;

        play_sound(t.levelup_sound, a.pos);
        if (t.levelup_effect >= 0) spawn_effect(a.pos, t.levelup_effect);
    }
}


void World::give_levels(size_t i, int32_t levels) {
    if (i >= actors_.size() || levels <= 0) return;
    const Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    if (t.xp_levels <= 0 || a.level >= t.xp_levels) return;
    const int32_t target = std::min(a.level + levels, t.xp_levels);
    give_experience(i, level_threshold(a.type, target) - a.experience);
}


void World::on_kill_experience(size_t victim, int32_t attacker_id) {
    if (attacker_id < 0) return;
    const int ai = index_of(attacker_id);
    if (ai < 0 || !actors_[size_t(ai)].alive) return;
    if (size_t(ai) == victim) return;
    const UnitType& vt = types_[actors_[victim].type];
    const int32_t exp = vt.gives_experience >= 0 ? vt.gives_experience : vt.cost;
    if (exp <= 0) return;
    if (allied(actors_[size_t(ai)].owner, actors_[victim].owner)) return;
    give_experience(size_t(ai), exp * ACTOR_EXPERIENCE_FACTOR);
}


void World::step_self_healing() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.elite_heal_delay <= 0 || t.xp_levels <= 0) continue;
        if (a.heal_cooldown > 0) --a.heal_cooldown;
        if (a.level < t.xp_levels) continue;
        const int32_t max_hp = std::max(1, t.hp);
        if (int64_t(a.hp) * 100 >= int64_t(max_hp) * t.elite_heal_start_below) continue;
        if (a.heal_cooldown > 0) continue;
        if (--a.heal_ticks > 0) continue;
        a.heal_ticks = t.elite_heal_delay;
        const int32_t step = t.elite_heal_step + max_hp * t.elite_heal_percent / 100;
        if (step <= 0) continue;
        a.hp = std::min(max_hp, a.hp + step);
    }
    step_unconditional_healing();
}


void World::step_unconditional_healing() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive) continue;
        const UnitType& t = types_[a.type];
        if (t.heal_delay <= 0) continue;
        const int32_t max_hp = std::max(1, t.hp);
        if (int64_t(a.hp) * 100 >= int64_t(max_hp) * t.heal_start_below) continue;
        if (a.self_heal_cooldown > 0) { --a.self_heal_cooldown; continue; }
        if (--a.self_heal_ticks > 0) continue;
        a.self_heal_ticks = t.heal_delay;
        const int32_t step = t.heal_step + max_hp * t.heal_percent / 100;
        if (step <= 0) continue;
        a.hp = std::min(max_hp, a.hp + step);
    }
}

}
