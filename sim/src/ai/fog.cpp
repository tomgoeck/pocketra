

#include <algorithm>

#include "ra/sim.h"

namespace ra {

bool World::bot_fogged(int32_t owner) const {
    if (owner < 0 || owner >= MAX_PLAYERS) return false;
    const BotState& b = players_[size_t(owner)].bot;
    return b.enabled && b.p.fog_obey != 0;
}


bool World::bot_knows(int32_t owner, size_t i) const {
    if (!bot_fogged(owner)) return true;
    if (i >= actors_.size()) return false;


    if (vis_[size_t(owner)].size() != size_t(map_.cells())) return allied(owner, actors_[i].owner);
    return actor_visible_to(owner, i);
}


bool World::bot_sees(int32_t owner, size_t i) const {
    if (bot_fogged(owner)) return bot_knows(owner, i);
    if (i >= actors_.size()) return false;
    const Actor& a = actors_[i];
    if (a.inside || a.transport >= 0) return false;
    if (a.owner == owner || allied(owner, a.owner)) return true;
    return !(cloaked(i) && !detected_by(owner, i));
}


void World::bot_fog_tick(int32_t owner) {
    if (!bot_fogged(owner)) return;
    BotState& b = players_[size_t(owner)].bot;

    const bool fresh = b.fog_starts_read == 0 || vis_[size_t(owner)].size() != size_t(map_.cells());


    if (b.fog_starts_read == 0) {
        b.fog_starts_read = 1;
        b.enemy_starts.clear();
        for (int32_t q = 0; q < MAX_PLAYERS; ++q) {
            if (q == owner || !hostile(owner, q)) continue;
            CPos at{-1, -1};
            for (size_t i = 0; i < actors_.size() && at.x < 0; ++i) {
                const Actor& a = actors_[i];
                if (!a.alive || a.owner != q) continue;
                const UnitType& t = types_[a.type];
                if (t.building && t.base_provider) at = CPos{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2};
                else if (!t.building && t.transforms_into >= 0) at = mobiles_[i].cell;
            }
            if (at.x >= 0) b.enemy_starts.push_back(at);
        }
    }

    if (((vis_players_ >> owner) & 1u) != 0 && !fresh) return;
    const uint32_t every = uint32_t(std::max(1, b.p.fog_vis_interval));
    if (!fresh && (tick_ + uint32_t(owner)) % every != 0) return;
    update_visibility(owner);

    if (b.stat_t_enemy_found == 0) {
        for (size_t i = 0; i < actors_.size(); ++i) {
            const Actor& a = actors_[i];
            if (!a.alive || !hostile(owner, a.owner) || !types_[a.type].building || types_[a.type].husk) continue;
            if (!bot_knows(owner, i)) continue;
            b.stat_t_enemy_found = int32_t(std::max<uint32_t>(1, tick_));
            break;
        }
    }
}


int32_t World::bot_presumed_bases(int32_t owner) const {
    if (!bot_fogged(owner)) return 0;
    const BotState& b = players_[size_t(owner)].bot;
    int32_t n = 0;
    for (const CPos& c : b.enemy_starts)
        if (map_.in_bounds(c) && !explored(owner, c)) ++n;
    return n;
}


bool World::bot_scout_cell(int32_t owner, CPos from, CPos& out) const {
    constexpr int32_t SCOUT_STEP = 4;
    constexpr int32_t SCOUT_NEAR = 4;
    if (!bot_fogged(owner) || !map_.in_bounds(from)) return false;
    const BotState& b = players_[size_t(owner)].bot;
    std::vector<uint8_t> reach;
    bot_land_reach(from, reach);
    if (reach.size() != size_t(map_.cells())) return false;
    auto reach_near = [&](CPos c, CPos& land) -> bool {
        int64_t best = INT64_MAX;
        for (int32_t dy = -SCOUT_NEAR; dy <= SCOUT_NEAR; ++dy) {
            for (int32_t dx = -SCOUT_NEAR; dx <= SCOUT_NEAR; ++dx) {
                const CPos n{c.x + dx, c.y + dy};
                if (!map_.in_bounds(n) || !reach[size_t(map_.index(n))]) continue;
                const int64_t d = int64_t(dx) * dx + int64_t(dy) * dy;
                if (d < best) { best = d; land = n; }
            }
        }
        return best != INT64_MAX;
    };
    int64_t best = INT64_MAX;
    bool ok = false;
    for (const CPos& c : b.enemy_starts) {
        if (!map_.in_bounds(c) || explored(owner, c)) continue;
        CPos land{-1, -1};
        if (!reach_near(c, land)) continue;
        const int64_t d = cell_dist_sq(land, from);
        if (d < best) { best = d; out = land; ok = true; }
    }
    if (ok) return true;
    for (int32_t y = SCOUT_STEP / 2; y < map_.height(); y += SCOUT_STEP) {
        for (int32_t x = SCOUT_STEP / 2; x < map_.width(); x += SCOUT_STEP) {
            const CPos c{x, y};
            const int32_t idx = map_.index(c);
            if (!reach[size_t(idx)] || explored(owner, c)) continue;
            const int64_t d = cell_dist_sq(c, from);
            if (d < best) { best = d; out = c; ok = true; }
        }
    }
    return ok;
}


bool World::bot_sea_scout_cell(int32_t owner, const std::vector<uint8_t>& naval_reach, CPos from, CPos& out) const {
    constexpr int32_t SEA_NEAR = 24;
    if (!bot_fogged(owner) || naval_reach.size() != size_t(map_.cells())) return false;
    const BotState& b = players_[size_t(owner)].bot;
    int64_t best = INT64_MAX;
    bool ok = false;
    for (const CPos& st : b.enemy_starts) {
        if (!map_.in_bounds(st) || explored(owner, st)) continue;
        int64_t near = INT64_MAX;
        CPos w{-1, -1};
        for (int32_t dy = -SEA_NEAR; dy <= SEA_NEAR; ++dy) {
            for (int32_t dx = -SEA_NEAR; dx <= SEA_NEAR; ++dx) {
                const CPos c{st.x + dx, st.y + dy};
                if (!map_.in_bounds(c) || !naval_reach[size_t(map_.index(c))]) continue;
                const int64_t d = int64_t(dx) * dx + int64_t(dy) * dy;
                if (d < near) { near = d; w = c; }
            }
        }
        if (w.x < 0 || explored(owner, w)) continue;
        const int64_t d = cell_dist_sq(w, from);
        if (d < best) { best = d; out = w; ok = true; }
    }
    return ok;
}


bool World::bot_air_scout_cell(int32_t owner, CPos from, CPos& out) const {
    if (!bot_fogged(owner)) return false;
    const BotState& b = players_[size_t(owner)].bot;
    int64_t best = INT64_MAX;
    bool ok = false;
    for (const CPos& st : b.enemy_starts) {
        if (!map_.in_bounds(st) || explored(owner, st)) continue;
        const int64_t d = cell_dist_sq(st, from);
        if (d < best) { best = d; out = st; ok = true; }
    }
    return ok;
}

}
