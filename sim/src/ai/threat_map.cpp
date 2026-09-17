

#include <algorithm>

#include "ra/sim.h"

namespace ra {


int32_t World::bot_firepower_of(size_t i) const {
    const UnitType& t = types_[actors_[i].type];
    int64_t sum = 0;
    const int32_t arms[3] = {t.weapon, t.weapon_secondary, t.weapon_tertiary};
    for (int32_t wi : arms) {
        if (wi < 0 || size_t(wi) >= weapons_.size()) continue;
        const Weapon& w = weapons_[size_t(wi)];
        const int32_t burst = std::max(1, w.burst);
        const int32_t reload = std::max(1, w.reload + std::clamp(w.burst_delay * (burst - 1), 1, 200));
        sum += int64_t(w.damage) * burst / reload * 100;
    }


    const int32_t max_hp = std::max(1, t.hp);
    return int32_t(std::clamp<int64_t>(sum * actors_[i].hp / max_hp, 0, INT32_MAX));
}


void World::bot_threat_map(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    if (--b.threat_ticks > 0) return;
    b.threat_ticks = std::max(1, p.threat_map_interval);

    const int32_t side = std::max(2, p.threat_map_side);
    const int32_t cols = (map_.width() + side - 1) / side;
    const int32_t rows = (map_.height() + side - 1) / side;
    if (cols <= 0 || rows <= 0) return;
    if (b.tm_cols != cols || b.tm_rows != rows || b.tm_side != side) {
        b.tm_cols = cols;
        b.tm_rows = rows;
        b.tm_side = side;
        b.threat_enemy.assign(size_t(cols) * size_t(rows), 0);
        b.threat_friendly.assign(size_t(cols) * size_t(rows), 0);
    } else {
        std::fill(b.threat_enemy.begin(), b.threat_enemy.end(), 0);
        std::fill(b.threat_friendly.begin(), b.threat_friendly.end(), 0);
    }

    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner < 0) continue;
        const UnitType& t = types_[a.type];
        if (t.husk || !t.targetable) continue;
        const int32_t fp = bot_firepower_of(i);
        if (fp <= 0) continue;
        const bool foe = hostile(owner, a.owner);
        const bool friendly = allied(owner, a.owner);
        if (!foe && !friendly) continue;
        const CPos c = t.building ? CPos{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2} : mobiles_[i].cell;
        if (!map_.in_bounds(c)) continue;
        const int32_t gx = c.x / side, gy = c.y / side;
        std::vector<int32_t>& grid = foe ? b.threat_enemy : b.threat_friendly;


        for (int32_t dy = -1; dy <= 1; ++dy) {
            for (int32_t dx = -1; dx <= 1; ++dx) {
                const int32_t nx = gx + dx, ny = gy + dy;
                if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
                const int32_t add = (dx == 0 && dy == 0) ? fp : fp / 2;
                int32_t& cell = grid[size_t(ny) * size_t(cols) + size_t(nx)];
                cell = int32_t(std::min<int64_t>(int64_t(cell) + add, INT32_MAX));
            }
        }
    }
}


int32_t World::bot_threat_at(int32_t owner, CPos c, bool enemy) const {
    if (owner < 0 || owner >= MAX_PLAYERS) return 0;
    const BotState& b = players_[size_t(owner)].bot;
    if (b.tm_side <= 0 || b.tm_cols <= 0) return 0;
    const int32_t gx = c.x / b.tm_side, gy = c.y / b.tm_side;
    if (gx < 0 || gy < 0 || gx >= b.tm_cols || gy >= b.tm_rows) return 0;
    const std::vector<int32_t>& grid = enemy ? b.threat_enemy : b.threat_friendly;
    const size_t idx = size_t(gy) * size_t(b.tm_cols) + size_t(gx);
    return idx < grid.size() ? grid[idx] : 0;
}

}
