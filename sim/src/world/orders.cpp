

#include "ra/sim.h"

namespace ra {

namespace {


constexpr size_t ORDER_HEAD = 6;

}

bool World::apply_order(int32_t player, const int32_t* cmd, size_t n) {
    if (cmd == nullptr || n < ORDER_HEAD) return false;
    if (player < 0 || player >= MAX_PLAYERS) return false;

    const int32_t op = cmd[0];
    const int32_t a = cmd[1], b = cmd[2], c = cmd[3], d = cmd[4];
    const int32_t declared = cmd[5];
    if (declared < 0) return false;
    const size_t have = n - ORDER_HEAD;
    const size_t count = size_t(declared) < have ? size_t(declared) : have;


    ids_scratch_.clear();
    for (size_t k = 0; k < count; ++k) {
        const int32_t id = cmd[ORDER_HEAD + k];
        const int idx = index_of(id);
        if (idx < 0) continue;
        const Actor& act = actors_[size_t(idx)];
        if (!act.alive || act.owner != player) continue;
        ids_scratch_.push_back(id);
    }
    const int32_t* ids = ids_scratch_.data();
    const size_t ni = ids_scratch_.size();


    const bool needs_ids = (op >= 0 && op <= 24) || (op >= 34 && op <= 37);
    if (needs_ids && ni == 0) return false;


    QueuedOrder q;
    switch (op) {

        case 0:
            if (c != 0) { q.kind = QueuedOrder::MOVE; q.cell = CPos{a, b}; queue_order(ids, ni, q); }
            else order_move(ids, ni, CPos{a, b});
            break;
        case 1:
            if (c != 0) { q.kind = QueuedOrder::ATTACK_MOVE; q.cell = CPos{a, b}; queue_order(ids, ni, q); }
            else order_attack_move(ids, ni, CPos{a, b});
            break;
        case 2:
            if (b != 0) { q.kind = QueuedOrder::ATTACK; q.target = a; q.force = c != 0; queue_order(ids, ni, q); }
            else order_attack(ids, ni, a, c != 0);
            break;
        case 3:  order_attack_cell(ids, ni, CPos{a, b}); break;
        case 4:  order_stop(ids, ni); break;
        case 5:  order_scatter(ids, ni); break;
        case 6:
            if (b != 0) { q.kind = QueuedOrder::GUARD; q.target = a; queue_order(ids, ni, q); }
            else order_guard(ids, ni, a);
            break;
        case 7:  order_harvest(ids, ni, CPos{a, b}); break;
        case 8:  order_deliver(ids, ni, a); break;
        case 9:  order_deploy(ids, ni); break;
        case 10: order_enter(ids, ni, a, ENTER_NONE); break;
        case 11: order_capture(ids, ni, a); break;
        case 12: order_enter(ids, ni, a, ENTER_DEMOLISH); break;
        case 13: order_enter(ids, ni, a, ENTER_INFILTRATE); break;
        case 14: order_disguise(ids[0], a); break;
        case 15: order_enter_transport(ids, ni, a); break;
        case 16: order_unload(ids, ni); break;
        case 17: order_lay_mine(ids, ni); break;
        case 18: order_detonate(ids, ni); break;
        case 19: order_chrono(ids, ni, CPos{a, b}); break;
        case 20: order_repair(ids, ni, a); break;
        case 21: order_resupply(ids, ni, a); break;
        case 22: order_land(ids, ni, CPos{a, b}); break;
        case 23: order_paradrop(ids[0], CPos{a, b}); break;
        case 24: for (size_t k = 0; k < ni; ++k) set_stance(ids[k], a); break;


        case 25: order_harvesters_return_to_base(player); break;
        case 26: order_harvesters_resume(player); break;


        case 30: queue_build(player, a); break;
        case 31: cancel_build(player, a, b); break;
        case 32: pause_build(player, a, b != 0); break;
        case 33: place_building(player, a, CPos{b, c}); break;


        case 34: sell(ids[0]); break;
        case 35: toggle_repair(ids[0]); break;
        case 36: set_rally(ids[0], CPos{a, b}); break;
        case 37: set_primary(ids[0]); break;


        case 40: {
            const CPos cell2 = d < 0 ? CPos{-1, -1} : CPos{(d >> 16) & 0xFFFF, d & 0xFFFF};
            activate_support_power(player, a, CPos{b, c}, cell2);
            break;
        }


        case 50: set_win_state(player, WIN_LOST); break;

        default: return false;
    }
    return true;
}

}
