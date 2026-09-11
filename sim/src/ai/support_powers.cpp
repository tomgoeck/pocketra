

#include <algorithm>

#include "ra/sim.h"

namespace ra {

namespace {


constexpr int32_t SP_RETRY_HIT = 10;


constexpr int32_t SP_TARGET_RADIUS[SP_COUNT] = {3, 3, 5, 0};

}


int64_t World::bot_sp_attraction(int32_t owner, int32_t kind, CPos c) const {
    if (kind < 0 || kind >= SP_COUNT || kind == SP_GPS) return 0;
    const BotParams& p = players_[size_t(owner)].bot.p;
    const int32_t r_target = SP_TARGET_RADIUS[kind];
    const int64_t r_target2 = int64_t(r_target) * r_target;
    const int64_t r_own2 = int64_t(p.sp_check_radius) * p.sp_check_radius;
    int64_t gain = 0, malus = 0;
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner < 0) continue;
        const UnitType& t = types_[a.type];
        if (t.husk || !t.targetable) continue;
        const CPos at = t.building ? CPos{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2} : mobiles_[i].cell;
        const int64_t d2 = cell_dist_sq(at, c);
        const int64_t value = t.cost > 0 ? t.cost : 0;
        if (kind == SP_NUKE) {

            if (hostile(owner, a.owner) && t.building && d2 <= r_target2) gain += value;

            if (allied(owner, a.owner) && d2 <= r_own2) malus += value * p.sp_own_penalty;
        } else {

            if (!allied(owner, a.owner) || t.building || t.harvester || t.aircraft) continue;
            if (d2 <= r_target2) gain += value;
        }
    }
    if (kind == SP_IRON_CURTAIN) {

        const int32_t threat = bot_threat_at(owner, c, true);
        if (threat <= 0) return 0;

        gain = gain * std::clamp<int64_t>(100 + threat / 100, 100, 300) / 100;
    }
    return gain - malus;
}


bool World::bot_sp_target(int32_t owner, int32_t kind, CPos& out, CPos& out2, int64_t& attraction) const {
    const BotParams& p = players_[size_t(owner)].bot.p;
    const int32_t step = std::max(2, p.sp_coarse_step);
    const int32_t cols = (map_.width() + step - 1) / step;
    const int32_t rows = (map_.height() + step - 1) / step;
    if (cols <= 0 || rows <= 0) return false;


    std::vector<int64_t> tiles(size_t(cols) * size_t(rows), 0);
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner < 0) continue;
        const UnitType& t = types_[a.type];
        if (t.husk || !t.targetable) continue;
        int64_t w = 0;
        if (kind == SP_NUKE) {
            if (hostile(owner, a.owner) && t.building) w = t.cost;
            else if (allied(owner, a.owner)) w = -int64_t(t.cost) * p.sp_own_penalty;
        } else {
            if (allied(owner, a.owner) && !t.building && !t.harvester && !t.aircraft) w = t.cost;
        }
        if (w == 0) continue;
        const CPos at = t.building ? CPos{a.origin.x + t.foot_w / 2, a.origin.y + t.foot_h / 2} : mobiles_[i].cell;
        if (!map_.in_bounds(at)) continue;
        const size_t idx = size_t(at.y / step) * size_t(cols) + size_t(at.x / step);
        if (idx < tiles.size()) tiles[idx] += w;
    }
    int32_t best_tile = -1;
    int64_t best_tile_score = 0;
    for (size_t i = 0; i < tiles.size(); ++i) {

        if (tiles[i] > best_tile_score) { best_tile_score = tiles[i]; best_tile = int32_t(i); }
    }
    if (best_tile < 0) return false;


    const int32_t tx = (best_tile % cols) * step, ty = (best_tile / cols) * step;
    const int32_t fine = std::max(1, p.sp_fine_step);
    CPos best{-1, -1};
    int64_t best_score = 0;
    for (int32_t y = ty - 1; y <= ty + step + 1; y += fine) {
        for (int32_t x = tx - 1; x <= tx + step + 1; x += fine) {
            const CPos c{x, y};
            if (!map_.in_bounds(c)) continue;
            const int64_t s = bot_sp_attraction(owner, kind, c);
            if (s > best_score || (s == best_score && best.x >= 0 && map_.index(c) < map_.index(best))) {
                if (s <= 0) continue;
                best_score = s;
                best = c;
            }
        }
    }
    if (best.x < 0) return false;
    out = best;
    attraction = best_score;

    if (kind == SP_CHRONOSHIFT) {


        CPos dst{-1, -1}, dummy{-1, -1};
        int64_t da = 0;
        if (!bot_sp_target(owner, SP_NUKE, dst, dummy, da) || dst.x < 0) return false;
        out2 = dst;
    } else {
        out2 = best;
    }
    return true;
}


void World::bot_support_powers(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    for (int32_t kind = 0; kind < SP_COUNT; ++kind) {
        if (b.sp_wait[kind] > 0) --b.sp_wait[kind];
        if (kind == SP_GPS) continue;
        int available = 0, ready = 0, permille = 0, paused = 0;
        support_power_state(owner, kind, available, ready, permille, paused);
        if (!available || !ready || b.sp_wait[kind] > 0) continue;


        int32_t base = p.nuke_min_attractiveness;
        if (kind == SP_IRON_CURTAIN) base = p.iron_min_attractiveness;
        else if (kind == SP_CHRONOSHIFT) base = p.chrono_min_attractiveness;
        const int64_t threshold = bot_plan_sp_threshold(owner, base);

        CPos target{-1, -1}, target2{-1, -1};
        int64_t attraction = 0;
        if (!bot_sp_target(owner, kind, target, target2, attraction) || attraction < threshold) {
            b.sp_wait[kind] = std::max(1, p.sp_scan_interval);
            continue;
        }
        if (activate_support_power(owner, kind, target, target2)) {
            ++b.stat_sp_fired;
            b.sp_wait[kind] = SP_RETRY_HIT;
        } else {
            b.sp_wait[kind] = std::max(1, p.sp_scan_interval);
        }
    }
}

}
