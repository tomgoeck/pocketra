

#include <algorithm>
#include <vector>

#include "ra/sim.h"

namespace ra {

namespace {

constexpr int32_t ENG_TARGET_OPTIONS = 10;
constexpr int32_t ENG_APC_INTERVAL = 25;
constexpr uint32_t ENG_APC_LOAD_TICKS = 750;
constexpr uint32_t ENG_APC_TRIP_TICKS = 3000;
constexpr int32_t ENG_APC_UNLOAD_CELLS = 3;
constexpr int32_t ENG_NEED_MAX = 16;

constexpr int32_t ENG_QUICK_TICKS = 100;
constexpr int32_t ENG_QUICK_MIN_VALUE = 300;
constexpr int32_t ENG_GUARD_CELLS = 8;

enum EngClass { ENG_NEUTRAL = 0, ENG_WEAK = 1, ENG_QUICK = 2, ENG_KILL = 3, ENG_PACK = 4 };


int32_t cells_to_rect(CPos c, CPos origin, int32_t w, int32_t h) {
    const int32_t dx = c.x < origin.x ? origin.x - c.x : (c.x >= origin.x + w ? c.x - (origin.x + w - 1) : 0);
    const int32_t dy = c.y < origin.y ? origin.y - c.y : (c.y >= origin.y + h ? c.y - (origin.y + h - 1) : 0);
    return std::max(dx, dy);
}

}


int32_t World::bot_eng_need(int32_t eng_type, size_t target, bool& destroys) const {
    destroys = false;
    if (eng_type < 0 || size_t(eng_type) >= types_.size() || target >= actors_.size()) return 0;
    const UnitType& s = types_[size_t(eng_type)];
    const Actor& e = actors_[target];
    const int64_t max_hp = types_[e.type].hp;
    const bool neutral = e.owner >= 0 && e.owner < MAX_PLAYERS && players_[size_t(e.owner)].non_combatant;
    if (s.sabotage_threshold <= 0 || neutral || max_hp <= 0) return 1;
    int64_t dmg = max_hp * s.sabotage_hp_removal / 100;
    dmg = dmg * rank_bonus(target).damage / 100;
    const int32_t hc = handicap(e.owner);
    if (hc != 0 && hc < 100) dmg = dmg * 100 / (100 - hc);
    int64_t hp = e.hp;
    int32_t n = 0;
    while (int64_t(100) * hp > int64_t(s.sabotage_threshold) * max_hp) {
        if (dmg <= 0 || n >= ENG_NEED_MAX) return 0;
        hp -= dmg;
        ++n;
        if (hp <= 0) { destroys = true; return n; }
    }
    return n + 1;
}


bool World::bot_eng_worth(size_t target) const {
    if (target >= actors_.size()) return false;
    const UnitType& t = types_[actors_[target].type];
    if (!t.building || t.husk || t.wall) return false;
    return t.base_provider || t.refinery || (t.produces & (1u << QUEUE_VEHICLE)) != 0;
}


bool World::bot_eng_guarded(int32_t owner, size_t target) const {
    if (target >= actors_.size()) return false;
    const Actor& tg = actors_[target];
    const UnitType& tt = types_[tg.type];
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& d = actors_[k];
        if (!d.alive || k == target || d.owner == owner || allied(owner, d.owner)) continue;
        if (d.inside || d.transport >= 0) continue;
        const UnitType& dt = types_[d.type];
        if (dt.husk || dt.weapon < 0 || size_t(dt.weapon) >= weapons_.size()) continue;
        if ((weapons_[size_t(dt.weapon)].valid_targets & (TT_INFANTRY | TT_GROUND_ACTOR)) == 0) continue;
        if (dt.building ? !bot_knows(owner, k) : !bot_sees(owner, k)) continue;
        const CPos c = dt.building ? CPos{d.origin.x + dt.foot_w / 2, d.origin.y + dt.foot_h / 2} : mobiles_[k].cell;
        if (cells_to_rect(c, tg.origin, tt.foot_w, tt.foot_h) <= ENG_GUARD_CELLS) return true;
    }
    return false;
}

void World::bot_eng_note(int32_t owner, int32_t eng_id, int32_t target_id) {
    BotState& b = players_[size_t(owner)].bot;
    for (size_t k = 0; k + 1 < b.eng_ops.size(); k += 2)
        if (b.eng_ops[k] == eng_id) { b.eng_ops[k + 1] = target_id; return; }
    b.eng_ops.push_back(eng_id);
    b.eng_ops.push_back(target_id);
}


void World::bot_eng_track(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    if (!b.eng_ops.empty()) {
        std::vector<int32_t> counted;
        size_t out = 0;
        for (size_t k = 0; k + 1 < b.eng_ops.size(); k += 2) {
            const int32_t eid = b.eng_ops[k], tid = b.eng_ops[k + 1];
            const int ei = index_of(eid), ti = index_of(tid);
            const bool eng_ok = ei >= 0 && actors_[size_t(ei)].alive && actors_[size_t(ei)].owner == owner;
            const bool tgt_ok = ti >= 0 && actors_[size_t(ti)].alive;
            const bool tgt_ours = tgt_ok && (actors_[size_t(ti)].owner == owner || allied(owner, actors_[size_t(ti)].owner));
            if (!eng_ok) {
                ++b.stat_eng_spent;
                if (tgt_ok && actors_[size_t(ti)].owner == owner &&
                    std::find(counted.begin(), counted.end(), tid) == counted.end()) {
                    ++b.stat_eng_captured;
                    counted.push_back(tid);
                }
                continue;
            }
            if (!tgt_ok || tgt_ours) continue;
            const Actor& a = actors_[size_t(ei)];
            const bool in_apc_pack = b.eng_apc >= 0 && tid == b.eng_apc_target;

            if (!in_apc_pack && a.enter_kind == ENTER_NONE && a.transport < 0 && a.enter_target < 0) continue;
            b.eng_ops[out++] = eid;
            b.eng_ops[out++] = tid;
        }
        b.eng_ops.resize(out);
    }
    if (b.eng_apc >= 0 && tick_ % uint32_t(ENG_APC_INTERVAL) == 0) bot_eng_apc(owner);
}


void World::bot_eng_apc(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const int ai = index_of(b.eng_apc);
    const int ti = index_of(b.eng_apc_target);
    auto release = [&]() {

        b.active_units.erase(std::remove(b.active_units.begin(), b.active_units.end(), b.eng_apc), b.active_units.end());
        b.eng_apc = -1;
        b.eng_apc_target = -1;
        b.eng_apc_phase = 0;
    };
    if (ai < 0 || !actors_[size_t(ai)].alive || actors_[size_t(ai)].owner != owner) { release(); return; }
    const int32_t apc_id = b.eng_apc;
    const bool tgt_ok = ti >= 0 && actors_[size_t(ti)].alive && actors_[size_t(ti)].owner != owner &&
                        !allied(owner, actors_[size_t(ti)].owner);

    std::vector<int32_t> inside, outside;
    for (size_t k = 0; k + 1 < b.eng_ops.size(); k += 2) {
        if (b.eng_ops[k + 1] != b.eng_apc_target) continue;
        const int ei = index_of(b.eng_ops[k]);
        if (ei < 0 || !actors_[size_t(ei)].alive) continue;
        (actors_[size_t(ei)].transport == apc_id ? inside : outside).push_back(b.eng_ops[k]);
    }
    if (!tgt_ok) {

        if (cargo_of(size_t(ai)).empty()) { release(); return; }
        order_unload(&apc_id, 1);
        return;
    }
    const Actor& tgt = actors_[size_t(ti)];
    const UnitType& tt = types_[tgt.type];
    const uint32_t age = tick_ - b.eng_apc_since;
    if (b.eng_apc_phase == 0) {
        const bool full = outside.empty() && !inside.empty();
        if (full || (age > ENG_APC_LOAD_TICKS && !inside.empty())) {
            b.eng_apc_phase = 1;
            const CPos goal{tgt.origin.x + tt.foot_w / 2, tgt.origin.y + tt.foot_h / 2};
            order_move(&apc_id, 1, goal, ENG_APC_UNLOAD_CELLS);
            return;
        }
        if (age > ENG_APC_LOAD_TICKS || (inside.empty() && outside.empty())) {

            if (!outside.empty()) order_enter(outside.data(), outside.size(), b.eng_apc_target);
            release();
            return;
        }
        for (int32_t id : outside) {
            const int ei = index_of(id);
            if (actors_[size_t(ei)].enter_target != apc_id) order_enter_transport(&id, 1, apc_id);
        }
        return;
    }
    if (b.eng_apc_phase == 1) {
        const int32_t d = cells_to_rect(mobiles_[size_t(ai)].cell, tgt.origin, tt.foot_w, tt.foot_h);
        if (d <= ENG_APC_UNLOAD_CELLS || age > ENG_APC_TRIP_TICKS ||
            (!mobiles_[size_t(ai)].moving && d <= 2 * ENG_APC_UNLOAD_CELLS)) {
            b.eng_apc_phase = 2;
        } else if (!mobiles_[size_t(ai)].moving) {
            const CPos goal{tgt.origin.x + tt.foot_w / 2, tgt.origin.y + tt.foot_h / 2};
            order_move(&apc_id, 1, goal, ENG_APC_UNLOAD_CELLS);
            return;
        } else {
            return;
        }
    }

    if (!cargo_of(size_t(ai)).empty() && !actors_[size_t(ai)].unloading) order_unload(&apc_id, 1);
    for (int32_t id : outside) {
        const int ei = index_of(id);
        const Actor& a = actors_[size_t(ei)];
        if (a.enter_kind == ENTER_NONE && a.enter_target < 0) order_enter(&id, 1, b.eng_apc_target);
    }
    if (cargo_of(size_t(ai)).empty()) {
        bool all_sent = true;
        for (int32_t id : outside) if (actors_[size_t(index_of(id))].enter_kind == ENTER_NONE) all_sent = false;
        if (all_sent || age > ENG_APC_TRIP_TICKS + ENG_APC_LOAD_TICKS) release();
    }
}


void World::bot_engineers(int32_t owner) {
    BotState& b = players_[size_t(owner)].bot;
    const BotParams& p = b.p;
    b.eng_want = 0;
    b.eng_ready = b.eng_ops.empty() ? 0 : 1;

    auto on_mission = [&](int32_t id) {
        for (size_t k = 0; k + 1 < b.eng_ops.size(); k += 2) if (b.eng_ops[k] == id) return true;
        return false;
    };


    auto detach = [&](int32_t id) {
        for (BotSquad& sq : b.squads)
            sq.units.erase(std::remove(sq.units.begin(), sq.units.end(), id), sq.units.end());
        b.idle_base_units.erase(std::remove(b.idle_base_units.begin(), b.idle_base_units.end(), id),
                                b.idle_base_units.end());
        if (std::find(b.active_units.begin(), b.active_units.end(), id) == b.active_units.end())
            b.active_units.push_back(id);
    };


    int32_t eng_type = -1, have = 0;
    std::vector<size_t> free;
    CPos ref{-1, -1};
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.building) {
            if (ref.x < 0 && !t.husk && !t.wall) ref = a.origin;
            continue;
        }
        if (!t.captures || t.aircraft || t.husk || t.harvester) continue;
        ++have;
        if (eng_type < 0) eng_type = a.type;
        detach(a.id);
        if (a.transport >= 0 || a.inside || a.enter_target >= 0 || a.enter_kind != ENTER_NONE || on_mission(a.id)) continue;
        free.push_back(i);
    }
    if (eng_type < 0) {
        std::vector<int32_t> list;
        buildable(owner, QUEUE_INFANTRY, list);
        for (int32_t t : list)
            if (types_[size_t(t)].captures && (eng_type < 0 || t < eng_type)) eng_type = t;
    }
    if (eng_type < 0) return;
    const UnitType& et = types_[size_t(eng_type)];
    if (!free.empty()) ref = mobiles_[free[0]].cell;
    if (ref.x < 0) return;


    std::vector<uint8_t> reach;
    bot_land_reach(ref, reach);
    auto in_reach = [&](CPos c) { return map_.in_bounds(c) && reach[size_t(map_.index(c))] != 0; };


    struct Tgt { size_t idx; int32_t id; int32_t cls; int32_t need; int64_t value; int64_t score; };
    std::vector<Tgt> singles, packs;
    for (size_t k = 0; k < actors_.size(); ++k) {
        const Actor& e = actors_[k];
        if (!e.alive || e.owner == owner || e.make_ticks > 0) continue;
        const UnitType& bt = types_[e.type];
        if (!bt.building || bt.husk) continue;
        if (allied(owner, e.owner)) continue;

        if (!bt.capturable) continue;
        const uint32_t cm = et.capture_types != 0 ? et.capture_types : uint32_t(CAP_BUILDING);
        const uint32_t bm = bt.capturable_types != 0 ? bt.capturable_types : uint32_t(CAP_BUILDING);
        if ((cm & bm) == 0) continue;
        if (!bot_sees(owner, k)) continue;
        bool can_walk = false;
        for (int y = -1; y <= bt.foot_h && !can_walk; ++y)
            for (int x = -1; x <= bt.foot_w; ++x)
                if (in_reach(CPos{e.origin.x + x, e.origin.y + y})) { can_walk = true; break; }
        if (!can_walk) continue;
        bool destroys = false;
        const int32_t need = bot_eng_need(eng_type, k, destroys);
        if (need <= 0) continue;
        const bool neutral = e.owner >= 0 && e.owner < MAX_PLAYERS && players_[size_t(e.owner)].non_combatant;
        const int64_t value = bt.sell_value >= 0 ? bt.sell_value : bt.cost;
        const bool worth = bot_eng_worth(k) || value >= p.eng_pack_min_value;
        int32_t cls;
        int64_t score = value;
        if (et.sabotage_threshold <= 0) {


            const int32_t dur = std::max(1, capture_duration_type(eng_type, k));
            score = value * 100 / dur;
            const bool damaged = int64_t(e.hp) * 2 <= int64_t(bt.hp);
            const bool gun = bt.weapon >= 0;
            const bool guarded = !neutral && !gun && bot_eng_guarded(owner, k);
            if (neutral) cls = ENG_NEUTRAL;
            else if (damaged && !gun && !guarded) cls = ENG_WEAK;
            else if (!gun && !guarded && dur <= ENG_QUICK_TICKS && value >= ENG_QUICK_MIN_VALUE) cls = ENG_QUICK;
            else cls = ENG_PACK;
        } else if (need == 1 && !destroys) cls = neutral ? ENG_NEUTRAL : ENG_WEAK;
        else if (need == 1) cls = ENG_KILL;
        else if (!destroys) cls = ENG_PACK;
        else continue;
        if (cls == ENG_WEAK && p.eng_plan < 2) continue;
        if (cls == ENG_QUICK && p.eng_plan < 3) continue;
        if ((cls == ENG_KILL || cls == ENG_PACK) && (p.eng_plan < 3 || !worth)) continue;

        int32_t pending = 0;
        for (size_t o = 0; o + 1 < b.eng_ops.size(); o += 2) if (b.eng_ops[o + 1] == e.id) ++pending;
        if (pending >= need) continue;
        (cls == ENG_PACK ? packs : singles).push_back({k, e.id, cls, need - pending, value, score});
    }


    auto by_value = [](const Tgt& x, const Tgt& y) {
        if (x.cls != y.cls) return x.cls < y.cls;
        if (x.score != y.score) return x.score > y.score;
        if (x.value != y.value) return x.value > y.value;
        return x.id < y.id;
    };
    std::sort(singles.begin(), singles.end(), by_value);
    std::sort(packs.begin(), packs.end(), by_value);
    if (singles.size() > size_t(ENG_TARGET_OPTIONS)) singles.resize(size_t(ENG_TARGET_OPTIONS));


    auto take_nearest = [&](const Actor& tgt) -> int32_t {
        size_t best = free.size();
        int64_t best_d = 0;
        for (size_t f = 0; f < free.size(); ++f) {
            if (!in_reach(mobiles_[free[f]].cell)) continue;
            const int64_t d = length_sq(tgt.pos - actors_[free[f]].pos);
            if (best == free.size() || d < best_d) { best = f; best_d = d; }
        }
        if (best == free.size()) return -1;
        const int32_t id = actors_[free[best]].id;
        free.erase(free.begin() + std::ptrdiff_t(best));
        return id;
    };


    const bool eng_eco_ok = !bot_eco_hold(owner) && bot_tank_value(owner) >= p.army_min_value &&
                            int64_t(credits(owner)) >= int64_t(std::max(0, et.cost)) + p.eng_pack_cash;
    int32_t open_singles = 0;
    for (const Tgt& t : singles) {
        b.eng_ready = std::max(b.eng_ready, 1);
        const int32_t id = take_nearest(actors_[t.idx]);
        if (id < 0) {
            if (t.cls != ENG_QUICK) ++open_singles;
            else if (eng_eco_ok && open_singles == 0) open_singles = 1;
            continue;
        }
        order_enter(&id, 1, t.id, ENTER_CAPTURE);
        bot_eng_note(owner, id, t.id);
    }
    int32_t deficit = std::min(open_singles, std::max(0, p.eng_single_max));


    if (!packs.empty() && p.eng_pack_max > 0 && b.eng_apc < 0) {
        const Tgt* pk = nullptr;
        for (const Tgt& t : packs) if (t.need <= p.eng_pack_max) { pk = &t; break; }
        if (pk != nullptr) {
            int32_t ready_n = 0;
            for (size_t f : free) if (in_reach(mobiles_[f].cell)) ++ready_n;

            bool escort = false;
            for (const BotSquad& s : b.squads) {
                if (s.dead || s.units.empty()) continue;
                if (s.type != BotSquad::ASSAULT && s.type != BotSquad::RUSH) continue;
                if (s.state == BotSquad::ATTACK_MOVE || s.state == BotSquad::ATTACK) { escort = true; break; }
            }

            int32_t apc = -1;
            if (p.eng_pack_apc != 0 && ready_n >= pk->need) {
                int64_t best_d = 0;
                const int32_t probe = actors_[free[0]].id;
                for (size_t i = 0; i < actors_.size(); ++i) {
                    const Actor& a = actors_[i];
                    if (!a.alive || a.owner != owner) continue;
                    const UnitType& t = types_[a.type];
                    if (t.building || t.aircraft || t.husk || t.harvester || t.locomotor == LOCO_NAVAL) continue;
                    if (t.cargo_max_weight < pk->need * std::max(1, et.passenger_weight)) continue;
                    if (!cargo_of(i).empty() || a.unloading || !can_load(a.id, probe)) continue;
                    if (!in_reach(mobiles_[i].cell)) continue;
                    const int64_t d = length_sq(a.pos - actors_[free[0]].pos);
                    if (apc < 0 || d < best_d) { apc = a.id; best_d = d; }
                }
            }
            if (ready_n >= pk->need && (apc >= 0 || escort)) {
                std::vector<int32_t> ids;
                for (int32_t n = 0; n < pk->need; ++n) {
                    const int32_t id = take_nearest(actors_[pk->idx]);
                    if (id < 0) break;
                    ids.push_back(id);
                    bot_eng_note(owner, id, pk->id);
                }
                if (apc >= 0) {
                    detach(apc);
                    b.eng_apc = apc;
                    b.eng_apc_target = pk->id;
                    b.eng_apc_phase = 0;
                    b.eng_apc_since = tick_;
                    const int ai = index_of(apc);
                    stop(size_t(ai), false);
                    order_enter_transport(ids.data(), ids.size(), apc);
                } else {
                    order_enter(ids.data(), ids.size(), pk->id, ENTER_CAPTURE);
                }
                b.eng_ready = 2;
            } else {


                const int32_t missing = std::max(0, pk->need - ready_n);
                const bool eco_ok = !bot_eco_hold(owner) && bot_tank_value(owner) >= p.army_min_value;
                const int64_t price = int64_t(missing) * std::max(0, et.cost) + p.eng_pack_cash;
                if (missing == 0) {
                    b.eng_ready = 2;
                } else if (eco_ok && int64_t(credits(owner)) >= price) {
                    deficit = std::max(deficit, missing);
                    b.eng_ready = 2;
                }
            }
        }
    }

    b.eng_want = deficit > 0 ? have + deficit : 0;
}

}
