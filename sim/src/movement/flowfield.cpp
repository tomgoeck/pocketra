#include <climits>
#include <queue>
#include <utility>

#include "ra/sim.h"

namespace ra {


bool Map::can_step(CPos from, int dir, int32_t mc) const {
    return passable({from.x + DIR_DX[dir], from.y + DIR_DY[dir]}, mc);
}


constexpr int32_t LANE_BIAS_COST = 10;


void build_flow_field(const Map& map, CPos goal, FlowField& out, int32_t mc) {
    const int n = map.cells();
    out.goal = goal;
    out.move_class = mc;
    out.dist.assign(n, INT_MAX);
    out.next.assign(n, -1);
    if (!map.passable(goal, mc)) return;

    using Item = std::pair<int32_t, int>;
    std::priority_queue<Item, std::vector<Item>, std::greater<Item>> open;
    out.dist[map.index(goal)] = 0;
    open.push({0, map.index(goal)});

    while (!open.empty()) {
        const auto [d, idx] = open.top();
        open.pop();
        if (d > out.dist[idx]) continue;
        const CPos c = map.cell_at(idx);
        for (int dir = 0; dir < NUM_DIRS; ++dir) {

            const CPos nb{c.x + DIR_DX[dir], c.y + DIR_DY[dir]};
            const int back = (dir + 4) % NUM_DIRS;
            if (!map.passable(nb, mc) || !map.can_step(nb, back, mc)) continue;
            const int base = (DIR_DX[dir] != 0 && DIR_DY[dir] != 0) ? DIAGONAL_COST : STRAIGHT_COST;

            const int bx = DIR_DX[back], by = DIR_DY[back];
            const int ux = c.x & 1, uy = c.y & 1;
            int32_t bias = 0;
            if ((ux == 0 && by < 0) || (ux == 1 && by > 0)) bias += LANE_BIAS_COST;
            if ((uy == 0 && bx < 0) || (uy == 1 && bx > 0)) bias += LANE_BIAS_COST;
            const int32_t nd = d + base * map.cost(c, mc) + bias;
            const int ni = map.index(nb);
            if (nd < out.dist[ni]) {
                out.dist[ni] = nd;
                out.next[ni] = static_cast<int8_t>(back);
                open.push({nd, ni});
            }
        }
    }
}

int FlowFieldCache::get_or_build(const Map& map, CPos goal, int32_t mc) {


    const int key = map.index(goal) * NUM_MOVE_CLASSES + int(mc);
    auto it = by_goal_.find(key);
    if (it != by_goal_.end()) return it->second;
    if (fields_.size() >= MAX_FIELDS) clear();
    fields_.emplace_back();
    build_flow_field(map, goal, fields_.back(), mc);
    ++builds_;
    const int id = static_cast<int>(fields_.size()) - 1;
    by_goal_[key] = id;
    return id;
}

void FlowFieldCache::clear() {
    fields_.clear();
    by_goal_.clear();


    ++generation_;
}

}
