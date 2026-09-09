

#include <algorithm>
#include <climits>

#include "ra/sim.h"

namespace ra {


constexpr int32_t LOW_POWER_MODIFIER = 300;


void World::notify(int32_t owner, int32_t kind) {
    if (owner >= 0 && owner < MAX_PLAYERS) notifications_[owner].push_back(kind);
}

void World::drain_notifications(int32_t owner, std::vector<int32_t>& out) {
    out.clear();
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    out.swap(notifications_[owner]);
    notifications_[owner].clear();
}


bool World::has_prerequisite(int32_t owner, const std::string& token) const {
    return has_prerequisite(owner, token, 0);
}

bool World::has_prerequisite(int32_t owner, const std::string& token, int depth) const {
    if (token.empty()) return true;
    if (token.rfind("techlevel.", 0) == 0) return true;
    if (owner < 0 || owner >= MAX_PLAYERS) return false;

    for (const std::string& tok : players_[owner].infiltrated_tokens)
        if (tok == token) return true;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];

        if (!t.building || a.sell_ticks >= 0) continue;
        for (size_t k = 0; k < t.provides.size(); ++k) {
            if (t.provides[k] != token) continue;


            const int32_t fo = (a.faction_owner >= 0 && a.faction_owner < MAX_PLAYERS) ? a.faction_owner : owner;
            const std::string& f = k < t.provides_factions.size() ? t.provides_factions[k] : std::string();
            if (!f.empty() && ("," + f + ",").find("," + players_[fo].faction + ",") == std::string::npos) continue;

            const std::string& req = k < t.provides_requires.size() ? t.provides_requires[k] : std::string();
            if (!req.empty()) {
                if (depth >= 4) continue;
                bool all = true;
                size_t start = 0;
                while (all && start <= req.size()) {
                    const size_t comma = req.find(',', start);
                    const std::string one = req.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
                    if (!one.empty() && !has_prerequisite(owner, one, depth + 1)) all = false;
                    if (comma == std::string::npos) break;
                    start = comma + 1;
                }
                if (!all) continue;
            }
            return true;
        }
    }
    return false;
}

bool World::prerequisites_met(int32_t owner, int32_t type) const {
    for (const std::string& p : types_[type].prerequisites) {
        if (!has_prerequisite(owner, p)) return false;
    }

    for (const std::string& p : types_[type].prerequisites_not) {
        if (has_prerequisite(owner, p)) return false;
    }
    return true;
}


bool World::item_hidden(int32_t owner, int32_t type) const {
    if (type < 0 || type >= static_cast<int32_t>(types_.size())) return false;
    for (const std::string& p : types_[type].prerequisites_hidden) {
        const bool invert = !p.empty() && p[0] == '!';
        if (has_prerequisite(owner, invert ? p.substr(1) : p) == invert) return true;
    }
    return false;
}


int World::find_producer(int32_t owner, int32_t kind) const {
    if (owner >= 0 && owner < MAX_PLAYERS) {
        const int p = index_of(players_[owner].primary[kind]);
        if (p >= 0 && actors_[p].alive && actors_[p].make_ticks == 0 && actors_[p].sell_ticks < 0 &&
            (types_[actors_[p].type].produces & (1u << kind))) return p;
    }
    for (size_t i = 0; i < actors_.size(); ++i) {
        const Actor& a = actors_[i];
        if (!a.alive || a.owner != owner || a.make_ticks > 0 || a.sell_ticks >= 0) continue;
        if (types_[a.type].produces & (1u << kind)) return static_cast<int>(i);
    }
    return -1;
}


bool World::build_limit_reached(int32_t owner, int32_t type) const {
    if (owner < 0 || owner >= MAX_PLAYERS || type < 0 || type >= static_cast<int32_t>(types_.size())) return false;
    const int32_t limit = types_[type].build_limit;
    if (limit <= 0) return false;
    int32_t n = 0;
    for (const Actor& a : actors_) {
        if (a.alive && a.owner == owner && a.type == type) ++n;
    }
    for (int k = 0; k < NUM_QUEUES; ++k) {
        for (const BuildItem& it : players_[owner].queues[k]) {
            if (it.type == type) ++n;
        }
    }
    return n >= limit;
}


bool World::pause_build(int32_t owner, int32_t kind, bool hold) {
    if (owner < 0 || owner >= MAX_PLAYERS || kind < 0 || kind >= NUM_QUEUES) return false;
    std::vector<BuildItem>& q = players_[owner].queues[kind];
    if (q.empty()) return false;
    q.front().paused = hold;
    return true;
}

bool World::build_paused(int32_t owner, int32_t kind) const {
    if (owner < 0 || owner >= MAX_PLAYERS || kind < 0 || kind >= NUM_QUEUES) return false;
    const std::vector<BuildItem>& q = players_[owner].queues[kind];
    return !q.empty() && q.front().paused;
}


int32_t World::buildable_total(int32_t owner) const {
    int32_t n = 0;
    std::vector<int32_t> items;
    for (int32_t kind = 0; kind < NUM_QUEUES; ++kind) {
        buildable(owner, kind, items);
        n += static_cast<int32_t>(items.size());
    }
    return n;
}

void World::buildable(int32_t owner, int32_t kind, std::vector<int32_t>& out) const {
    out.clear();

    if (owner < 0 || owner >= MAX_PLAYERS || kind < 0 || kind >= NUM_QUEUES) return;
    if (find_producer(owner, kind) < 0) return;
    for (size_t t = 0; t < types_.size(); ++t) {
        const UnitType& ut = types_[t];
        if (ut.queue_kind != kind || ut.cost <= 0) continue;
        if (prerequisites_met(owner, static_cast<int32_t>(t))) out.push_back(static_cast<int32_t>(t));
    }


    std::sort(out.begin(), out.end(), [&](int32_t a, int32_t b) {
        const int32_t pa = types_[a].palette_order, pb = types_[b].palette_order;
        return pa != pb ? pa < pb : a < b;
    });
}


int32_t World::power_provided(int32_t owner) const {


    if (owner >= 0 && owner < MAX_PLAYERS && players_[owner].power_outage > 0) return 0;
    int32_t sum = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner) continue;
        const UnitType& t = types_[a.type];
        if (t.power <= 0) continue;
        sum += t.scale_power_with_health ? int32_t(int64_t(t.power) * a.hp / std::max(1, t.hp)) : t.power;
    }
    return sum;
}


bool World::powered(size_t i) const {
    const Actor& a = actors_[i];
    if (!types_[a.type].needs_power) return true;
    return a.owner < 0 || a.owner >= MAX_PLAYERS || power_balance_[a.owner] >= 0;
}

int32_t World::power_drained(int32_t owner) const {
    int32_t sum = 0;
    for (const Actor& a : actors_) {
        if (a.alive && a.owner == owner && types_[a.type].power < 0) sum -= types_[a.type].power;
    }
    return sum;
}


static const int32_t SPEEDUP_DEFAULT[7] = {100, 86, 75, 67, 60, 55, 50};
static const int32_t SPEEDUP_VEHICLE[4] = {100, 75, 60, 50};

int32_t World::build_time(int32_t owner, int32_t type) const {
    if (type < 0 || type >= static_cast<int32_t>(types_.size())) return 1;
    const UnitType& t = types_[type];
    int32_t base = build_time(type);
    if (t.queue_kind < 0) return base;
    int32_t producers = 0;
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner != owner || a.make_ticks > 0 || a.sell_ticks >= 0) continue;
        if (types_[a.type].produces & (1u << t.queue_kind)) ++producers;
    }
    const int32_t* table = t.queue_kind == QUEUE_VEHICLE ? SPEEDUP_VEHICLE : SPEEDUP_DEFAULT;
    const int32_t n = t.queue_kind == QUEUE_VEHICLE ? 4 : 7;
    const int32_t idx = std::max(1, std::min(producers, n)) - 1;
    base = std::max(1, base * table[idx] / 100);

    const int32_t hc = handicap(owner);
    return hc != 0 ? std::max(1, base * (100 + hc) / 100) : base;
}

int32_t World::build_time(int32_t type) const {
    if (type < 0 || type >= static_cast<int32_t>(types_.size())) return 1;

    const UnitType& t = types_[type];
    const int32_t base = t.build_duration >= 0 ? t.build_duration : t.cost;
    return std::max(1, base * t.build_duration_pct / 100);
}

bool World::queue_build(int32_t owner, int32_t type) {
    if (owner < 0 || owner >= MAX_PLAYERS || type < 0 || type >= static_cast<int32_t>(types_.size())) return false;
    const UnitType& t = types_[type];
    if (t.queue_kind < 0 || find_producer(owner, t.queue_kind) < 0 || !prerequisites_met(owner, type) ||
        build_limit_reached(owner, type)) {
        notify(owner, NOTIFY_NO_BUILD);
        return false;
    }
    std::vector<BuildItem>& q = players_[owner].queues[t.queue_kind];


    if (queue_is_structure(t.queue_kind) && !q.empty() && q.front().done) {
        notify(owner, NOTIFY_BUILDING_IN_PROGRESS);
        return false;
    }
    BuildItem item;
    item.type = type;
    item.total_cost = item.remaining_cost = t.cost;
    item.total_time = item.remaining_time = build_time(owner, type);
    q.push_back(item);
    if (queue_is_structure(t.queue_kind)) notify(owner, NOTIFY_BUILDING);
    return true;
}

bool World::cancel_build(int32_t owner, int32_t kind, int32_t type) {
    if (owner < 0 || owner >= MAX_PLAYERS || kind < 0 || kind >= NUM_QUEUES) return false;
    std::vector<BuildItem>& q = players_[owner].queues[kind];

    for (size_t i = q.size(); i-- > 0;) {
        if (q[i].type != type) continue;
        credits_[owner] += q[i].total_cost - q[i].remaining_cost;
        q.erase(q.begin() + static_cast<long>(i));
        notify(owner, NOTIFY_CANCELLED);
        return true;
    }
    return false;
}

const std::vector<BuildItem>& World::queue(int32_t owner, int32_t kind) const {
    static const std::vector<BuildItem> empty;
    if (owner < 0 || owner >= MAX_PLAYERS || kind < 0 || kind >= NUM_QUEUES) return empty;
    return players_[owner].queues[kind];
}


void World::tick_item(int32_t owner, BuildItem& item) {
    if (item.done || item.paused) return;
    if (!item.started) {
        item.started = true;
        item.total_time = item.remaining_time = build_time(owner, item.type);
    }

    if (power_provided(owner) < power_drained(owner)) {
        item.slowdown -= 100;
        if (item.slowdown < 0) {
            item.slowdown = LOW_POWER_MODIFIER + item.slowdown;
        } else {
            return;
        }
    }

    const int64_t expected_remaining = item.remaining_time == 1 ? 0
        : int64_t(item.total_cost) * item.remaining_time / std::max(1, item.total_time);
    const int64_t cost_this_tick = item.remaining_cost - expected_remaining;
    if (cost_this_tick > 0) {
        if (!take_cash(owner, cost_this_tick)) {

            if (funds_notified_[owner] == NOTIFY_NEVER || tick_ - funds_notified_[owner] > 30 * TICKS_PER_SECOND) {
                funds_notified_[owner] = tick_;
                notify(owner, NOTIFY_INSUFFICIENT_FUNDS);
            }
            return;
        }
        item.remaining_cost -= static_cast<int32_t>(cost_this_tick);
    }
    if (item.remaining_time > 0) --item.remaining_time;
    if (item.remaining_time <= 0) {
        item.done = true;
        item.remaining_cost = 0;
    }
}

void World::step_production() {

    for (int32_t owner = 0; owner < MAX_PLAYERS; ++owner)
        if (players_[owner].power_outage > 0) --players_[owner].power_outage;

    int32_t provided[MAX_PLAYERS] = {0, 0, 0, 0, 0, 0, 0, 0};
    int32_t drained[MAX_PLAYERS] = {0, 0, 0, 0, 0, 0, 0, 0};
    for (const Actor& a : actors_) {
        if (!a.alive || a.owner < 0 || a.owner >= MAX_PLAYERS) continue;
        const UnitType& t = types_[a.type];
        if (t.power > 0 && players_[a.owner].power_outage == 0)
            provided[a.owner] += t.scale_power_with_health ? int32_t(int64_t(t.power) * a.hp / std::max(1, t.hp)) : t.power;
        else if (t.power < 0) drained[a.owner] -= t.power;
    }
    for (int32_t owner = 0; owner < MAX_PLAYERS; ++owner) power_balance_[owner] = provided[owner] - drained[owner];
    for (int32_t owner = 0; owner < MAX_PLAYERS; ++owner) {

        if (drained[owner] > provided[owner] && drained[owner] > 0 &&
            (power_notified_[owner] == NOTIFY_NEVER || tick_ - power_notified_[owner] > 10 * TICKS_PER_SECOND)) {
            power_notified_[owner] = tick_;
            notify(owner, NOTIFY_LOW_POWER);
        }
        for (int32_t kind = 0; kind < NUM_QUEUES; ++kind) {
            std::vector<BuildItem>& q = players_[owner].queues[kind];
            if (q.empty()) continue;


            if (find_producer(owner, kind) < 0) {
                for (const BuildItem& it : q) credits_[owner] += it.total_cost - it.remaining_cost;
                q.clear();
                continue;
            }


            for (size_t k = q.size(); k-- > 0;) {
                if (prerequisites_met(owner, q[k].type)) continue;
                credits_[owner] += q[k].total_cost - q[k].remaining_cost;
                q.erase(q.begin() + static_cast<long>(k));
            }
            if (q.empty()) continue;
            BuildItem& item = q.front();
            const bool was_done = item.done;
            tick_item(owner, item);
            if (item.done && !was_done) {
                notify(owner, queue_is_structure(kind) ? NOTIFY_CONSTRUCTION_COMPLETE : NOTIFY_UNIT_READY);
            }
            if (!item.done) continue;
            if (queue_is_structure(kind)) continue;

            const int producer = find_producer(owner, kind);
            if (producer < 0) continue;

            const Actor p = actors_[producer];
            const UnitType& pt = types_[p.type];
            const CPos exit{p.origin.x + pt.exit_dx, p.origin.y + pt.exit_dy};


            const int32_t id = spawn(item.type, owner, exit);
            const int idx = index_of(id);
            if (idx >= 0) {


                const UnitType& it = types_[item.type];
                if (!it.producible_prereqs.empty()) {
                    bool all = true;
                    for (const std::string& pr : it.producible_prereqs)
                        if (!has_prerequisite(owner, pr)) { all = false; break; }
                    if (all) give_levels(size_t(idx), it.producible_levels);
                }
                actors_[idx].facing = pt.exit_facing;


                const bool air = types_[item.type].aircraft;
                if (air) {
                    const std::vector<int32_t>& rb = types_[item.type].rearm_actors;
                    if (std::find(rb.begin(), rb.end(), p.type) != rb.end()) airs_[idx].base = p.id;
                    airs_[idx].state = Air::LANDED;


                    actors_[idx].pos = WVec{p.pos.x + pt.exit_ox, p.pos.y + pt.exit_oy};
                    prev_pos_[size_t(idx)] = actors_[idx].pos;
                }


                if ((!air || p.rally_set) && p.rally != mobiles_[idx].cell) set_move(idx, p.rally, 0);
                if (types_[item.type].harvester) harvests_[idx].automated = true;
            }

            if (pt.door_len > 0) actors_[producer].door_ticks = 2 * pt.door_len;
            q.erase(q.begin());
        }
    }
}


bool World::can_place(int32_t owner, int32_t type, CPos origin, std::vector<uint8_t>* cell_ok) const {
    const UnitType& t = types_[type];
    if (!t.building) return false;
    if (cell_ok) cell_ok->assign(size_t(t.foot_w * t.foot_h), 1);
    bool all_ok = true;
    for (int y = 0; y < t.foot_h; ++y) {
        for (int x = 0; x < t.foot_w; ++x) {
            const CPos c{origin.x + x, origin.y + y};
            bool ok = map_.in_bounds(c);

            const bool blocks = t.build_block.size() > size_t(y * t.foot_w + x) ? t.build_block[size_t(y * t.foot_w + x)] != 0 : t.footprint[size_t(y * t.foot_w + x)] != 0;


            if (ok && blocks) {
                const uint32_t mask = t.terrain_mask != 0 ? t.terrain_mask : ((1u << TER_CLEAR) | (1u << TER_ROAD));
                ok = map_.passable(c, building_move_class(t)) && cell_empty(c) && bib_owner_[map_.index(c)] == -1 &&
                     res_density_[map_.index(c)] == 0 && ((mask >> map_.base_terrain(c)) & 1u) != 0;
            }
            if (!ok) all_ok = false;
            if (cell_ok) (*cell_ok)[size_t(y * t.foot_w + x)] = ok ? 1 : 0;
        }
    }
    if (!all_ok) return false;

    bool adjacent = false, in_base = false, any_provider = false;
    for (const Actor& a : actors_) {

        if (!a.alive || a.owner != owner || !types_[a.type].building || !types_[a.type].gives_buildable_area) continue;
        const UnitType& bt = types_[a.type];

        const int dx = std::max({a.origin.x - (origin.x + t.foot_w), origin.x - (a.origin.x + bt.foot_w), 0});
        const int dy = std::max({a.origin.y - (origin.y + t.foot_h), origin.y - (a.origin.y + bt.foot_h), 0});
        if (std::max(dx, dy) < t.adjacent) adjacent = true;
        if (bt.base_provider) {
            any_provider = true;
            const WVec center{origin.x * CELL + t.foot_w * CELL / 2, origin.y * CELL + t.foot_h * CELL / 2};
            if (length(center - a.pos) <= bt.base_range) in_base = true;
        }
    }
    return adjacent && (!any_provider || in_base);
}

bool World::place_building(int32_t owner, int32_t type, CPos origin) {
    if (owner < 0 || owner >= MAX_PLAYERS) return false;
    std::vector<BuildItem>& q = players_[owner].queues[types_[type].queue_kind == QUEUE_DEFENSE ? QUEUE_DEFENSE : QUEUE_BUILDING];
    if (q.empty() || !q.front().done || q.front().type != type) return false;
    if (!can_place(owner, type, origin, nullptr)) {
        notify(owner, NOTIFY_CANNOT_PLACE);
        return false;
    }

    const int32_t buildables_before = buildable_total(owner);
    const int32_t id = spawn_building(type, owner, origin);
    if (id < 0) return false;
    q.erase(q.begin());
    const int idx = index_of(id);
    actors_[idx].make_ticks = types_[type].make_ticks;

    if (types_[type].free_actor >= 0) {
        const CPos at{origin.x + types_[type].free_dx, origin.y + types_[type].free_dy};
        spawn(types_[type].free_actor, owner, at);
    }


    if (buildable_total(owner) > buildables_before) new_options_pending_[owner] = true;
    if (types_[type].make_ticks <= 0 && new_options_pending_[owner]) {
        new_options_pending_[owner] = false;
        notify(owner, NOTIFY_NEW_OPTIONS);
    }
    return true;
}


int64_t World::sell_value(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive) return 0;
    const UnitType& t = types_[actors_[i].type];
    const int32_t value = t.sell_value >= 0 ? t.sell_value : t.cost;
    return int64_t(value) * 50 * actors_[i].hp / (100 * std::max(1, t.hp));
}


bool World::sell(int32_t id) {
    const int i = index_of(id);
    if (i < 0) return false;
    Actor& a = actors_[i];
    const UnitType& t = types_[a.type];


    if (!a.alive || !t.building || !t.sellable || a.make_ticks > 0 || a.sell_ticks >= 0) return false;
    a.repairing = false;
    a.sell_ticks = t.make_ticks;
    play_sound(t.sell_sound, a.pos);

    return true;
}


bool World::toggle_repair(int32_t id) {
    const int i = index_of(id);
    if (i < 0) return false;
    Actor& a = actors_[i];
    const UnitType& t = types_[a.type];
    if (!a.alive || !t.building || a.make_ticks > 0 || a.sell_ticks >= 0) return false;
    if (a.repairing) {
        a.repairing = false;
        return true;
    }
    if (a.hp >= t.hp) return false;
    a.repairing = true;
    a.repair_ticks = 0;
    notify(a.owner, NOTIFY_REPAIRING);
    return true;
}


bool World::set_rally(int32_t id, CPos cell) {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive || !types_[actors_[i].type].building) return false;
    if (types_[actors_[i].type].produces == 0 || !map_.in_bounds(cell)) return false;
    actors_[i].rally = cell;
    actors_[i].rally_set = true;
    return true;
}


bool World::set_primary(int32_t id) {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive) return false;
    Actor& a = actors_[i];
    const uint32_t produces = types_[a.type].produces;
    if (produces == 0 || a.make_ticks > 0 || a.sell_ticks >= 0) return false;
    for (int32_t kind = 0; kind < NUM_QUEUES; ++kind) {
        if (!(produces & (1u << kind))) continue;
        const int old = index_of(players_[a.owner].primary[kind]);
        if (old >= 0 && old != i) {

            bool still = false;
            for (int32_t k2 = 0; k2 < NUM_QUEUES; ++k2) {
                if (k2 != kind && players_[a.owner].primary[k2] == actors_[old].id && !(produces & (1u << k2))) still = true;
            }
            if (!still) actors_[old].primary = false;
        }
        players_[a.owner].primary[kind] = a.id;
    }
    a.primary = true;
    notify(a.owner, NOTIFY_PRIMARY_SELECTED);
    return true;
}


void World::step_buildings() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];
        if (!a.alive || !types_[a.type].building) continue;
        const UnitType& t = types_[a.type];
        if (a.door_ticks > 0) --a.door_ticks;
        if (a.sell_ticks >= 0) {

            a.make_ticks = t.make_ticks - a.sell_ticks;
            if (a.sell_ticks == 0) {
                credits_[a.owner] += sell_value(a.id);
                notify(a.owner, NOTIFY_STRUCTURE_SOLD);
                dispose(i);
            } else {
                --a.sell_ticks;
            }
            continue;
        }
        if (!a.repairing) continue;
        if (a.repair_ticks > 0) { --a.repair_ticks; continue; }
        const int32_t to_repair = std::min(t.repair_step, t.hp - a.hp);

        const int32_t value = t.sell_value >= 0 ? t.sell_value : t.cost;
        const int64_t cost = std::max<int64_t>(1, int64_t(to_repair) * t.repair_percent * value / (int64_t(t.hp) * 100));
        if (!take_cash(a.owner, cost)) { a.repair_ticks = 1; continue; }
        a.hp += to_repair;
        if (a.hp >= t.hp) {
            a.hp = t.hp;
            if (t.minelayer_mine >= 0 && t.ammo_max > 0) airs_[i].ammo = t.ammo_max;
            a.repairing = false;
        }
        a.repair_ticks = t.repair_interval;
    }
}


CPos World::repair_cell(size_t depot, size_t unit) const {
    const Actor& d = actors_[depot];
    const UnitType& dt = types_[d.type];
    const CPos center{d.origin.x + dt.foot_w / 2, d.origin.y + dt.foot_h / 2};
    const int32_t mc = actor_move_class(unit);
    if (mc == MC_LAND) return center;
    const int32_t self = static_cast<int32_t>(unit);
    CPos best = mobiles_[unit].cell;
    int64_t best_d = INT64_MAX;
    bool found = false;
    for (int y = -1; y <= dt.foot_h; ++y) {
        for (int x = -1; x <= dt.foot_w; ++x) {
            if (x >= 0 && x < dt.foot_w && y >= 0 && y < dt.foot_h) continue;
            const CPos c{d.origin.x + x, d.origin.y + y};
            if (!map_.in_bounds(c) || !map_.passable(c, mc)) continue;
            if (!cell_free(c, self)) continue;
            const int64_t dist = cell_dist_sq(c, mobiles_[unit].cell);
            if (dist < best_d) { best_d = dist; best = c; found = true; }
        }
    }
    return found ? best : mobiles_[unit].cell;
}


bool World::at_repair_place(size_t depot, size_t unit) const {
    const Actor& d = actors_[depot];
    const UnitType& dt = types_[d.type];
    const Mobile& m = mobiles_[unit];
    if (m.in_transit) return false;
    if (actor_move_class(unit) == MC_LAND)
        return m.cell == CPos{d.origin.x + dt.foot_w / 2, d.origin.y + dt.foot_h / 2};
    return m.cell.x >= d.origin.x - 1 && m.cell.x <= d.origin.x + dt.foot_w &&
           m.cell.y >= d.origin.y - 1 && m.cell.y <= d.origin.y + dt.foot_h;
}

void World::order_repair(const int32_t* ids, size_t n, int32_t depot_id) {
    const int d = index_of(depot_id);
    if (d < 0 || !actors_[d].alive || !types_[actors_[d].type].repairs_units || actors_[d].make_ticks > 0) return;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || actors_[i].owner != actors_[d].owner) continue;
        const UnitType& t = types_[actors_[i].type];
        if (!t.repairable || t.building) continue;
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        if (t.harvester) harvests_[i].automated = false;
        actors_[i].repair_depot = depot_id;
        actors_[i].being_repaired = false;
        set_move(i, repair_cell(size_t(d), size_t(i)), 0);
    }
}


void World::step_repairs() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        Actor& a = actors_[i];


        if (a.active_ticks > 0) {
            --a.active_ticks;
            ++a.active_anim;
        } else {
            a.active_anim = 0;
        }
        if (!a.alive || a.repair_depot < 0) continue;
        const int d = index_of(a.repair_depot);
        if (d < 0 || !actors_[d].alive) { a.repair_depot = -1; a.being_repaired = false; continue; }
        const UnitType& dt = types_[actors_[d].type];
        const UnitType& t = types_[a.type];
        const Mobile& m = mobiles_[i];
        if (!at_repair_place(size_t(d), i)) {

            if (!m.moving && !m.in_transit && !a.being_repaired) set_move(i, repair_cell(size_t(d), i), 0);
            continue;
        }
        if (!a.being_repaired) {
            a.being_repaired = true;
            a.repair_wait = 0;
            if (a.hp < t.hp) notify(a.owner, NOTIFY_REPAIRING);
        }
        if (a.repair_wait > 0) { --a.repair_wait; continue; }
        if (a.hp >= t.hp) {
            a.hp = t.hp;
            a.repair_depot = -1;
            a.being_repaired = false;
            notify(a.owner, NOTIFY_UNIT_REPAIRED);
            set_move(i, actors_[d].rally, 0);
            continue;
        }
        const int32_t step = std::min(dt.repair_hp_step, t.hp - a.hp);
        const int64_t cost = std::max<int64_t>(1, int64_t(step) * dt.repair_value_percent * t.cost / (int64_t(t.hp) * 100));
        if (!take_cash(a.owner, cost)) { a.repair_wait = 1; continue; }
        a.hp += step;
        a.repair_wait = dt.repair_units_interval;
        actors_[d].active_ticks = dt.repair_units_interval + 2;
    }
}


void World::step_victory() {
    if (!conquest_victory_) return;
    bool required[MAX_PLAYERS] = {};
    for (const Actor& a : actors_) {
        if (a.owner < 0 || a.owner >= MAX_PLAYERS) continue;
        players_[a.owner].participant = true;
        const UnitType& t = types_[a.type];
        const bool req = t.required_short_game >= 0 ? t.required_short_game == 1 : (t.building && !t.defense);
        if (a.alive && req) {
            required[a.owner] = true;
            players_[a.owner].had_required = true;
        }
    }
    for (int32_t p = 0; p < MAX_PLAYERS; ++p) {
        PlayerState& ps = players_[p];
        if (!ps.participant || ps.non_combatant || ps.win_state != WIN_UNDEFINED) continue;
        if (!ps.had_required) continue;
        if (!required[p]) {
            ps.win_state = WIN_LOST;
            notify(p, NOTIFY_LOSE);


            for (size_t i = 0; i < actors_.size(); ++i) {
                Actor& a = actors_[i];
                if (!a.alive || a.owner != p) continue;
                const UnitType& t = types_[a.type];


                if (t.building && t.capturable && !t.sellable && t.cost <= 0 && neutral_player_ >= 0) set_owner(i, neutral_player_);
                else kill(i, DAMAGE_EXPLOSION);
            }
        }
    }
    for (int32_t p = 0; p < MAX_PLAYERS; ++p) {
        PlayerState& ps = players_[p];
        if (!ps.participant || ps.non_combatant || ps.win_state != WIN_UNDEFINED) continue;
        bool others = false, all_lost = true;
        for (int32_t o = 0; o < MAX_PLAYERS; ++o) {
            if (o == p || !players_[o].participant || players_[o].non_combatant || allied(p, o)) continue;
            others = true;
            if (players_[o].win_state != WIN_LOST) all_lost = false;
        }
        if (others && all_lost) {
            ps.win_state = WIN_WON;
            notify(p, NOTIFY_WIN);
        }
    }
}


bool World::can_deploy(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive) return false;
    const UnitType& t = types_[actors_[i].type];
    if (t.transforms_into < 0 || mobiles_[i].in_transit) return false;
    const UnitType& into = types_[t.transforms_into];
    const CPos origin{mobiles_[i].cell.x + t.transforms_dx, mobiles_[i].cell.y + t.transforms_dy};
    for (int y = 0; y < into.foot_h; ++y) {
        for (int x = 0; x < into.foot_w; ++x) {
            if (!into.footprint[size_t(y * into.foot_w + x)]) continue;
            const CPos c{origin.x + x, origin.y + y};
            if (!map_.in_bounds(c) || !map_.passable(c)) return false;
            const int occ = occupant(c);
            if (occ != -1 && occ != i) return false;
            if (res_density_[map_.index(c)] > 0) return false;
        }
    }
    return true;
}

void World::order_deploy(const int32_t* ids, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        const int32_t id = ids[k];
        if (!can_deploy(id)) continue;
        const int i = index_of(id);
        const Actor a = actors_[i];
        const UnitType& t = types_[a.type];
        const CPos origin{mobiles_[i].cell.x + t.transforms_dx, mobiles_[i].cell.y + t.transforms_dy};
        const int32_t buildables_before = buildable_total(a.owner);
        dispose(size_t(i));
        const int32_t bid = spawn_building(t.transforms_into, a.owner, origin);
        const int bi = index_of(bid);
        if (bi >= 0) actors_[bi].make_ticks = types_[t.transforms_into].make_ticks;

        if (buildable_total(a.owner) > buildables_before) new_options_pending_[a.owner] = true;
        if (types_[t.transforms_into].make_ticks <= 0 && new_options_pending_[a.owner]) {
            new_options_pending_[a.owner] = false;
            notify(a.owner, NOTIFY_NEW_OPTIONS);
        }
    }
}


static uint32_t cap_mask(uint32_t m) { return m != 0 ? m : uint32_t(CAP_BUILDING); }


int32_t World::enter_kind_for(size_t i, size_t t) const {
    if (i >= actors_.size() || t >= actors_.size() || i == t) return ENTER_NONE;
    if (!actors_[i].alive || !actors_[t].alive || actors_[t].make_ticks > 0) return ENTER_NONE;
    const UnitType& s = types_[actors_[i].type];
    const UnitType& b = types_[actors_[t].type];
    if (s.building) return ENTER_NONE;
    const bool ally = allied(actors_[i].owner, actors_[t].owner);

    if (s.instantly_repairs && b.instantly_repairable && ally && actors_[t].hp < b.hp) return ENTER_REPAIR;
    if (ally) return ENTER_NONE;

    if (s.infiltrates != 0 && (s.infiltrates & target_mask(t)) != 0) return ENTER_INFILTRATE;

    if (s.demolition_delay >= 0 && b.demolishable) return ENTER_DEMOLISH;

    if (s.captures && b.capturable && (cap_mask(s.capture_types) & cap_mask(b.capturable_types)) != 0)
        return ENTER_CAPTURE;
    return ENTER_NONE;
}


void World::order_enter(const int32_t* ids, size_t n, int32_t target_id, int32_t kind) {
    const int t = index_of(target_id);
    if (t < 0 || !actors_[t].alive) return;
    for (size_t k = 0; k < n; ++k) {
        const int i = index_of(ids[k]);
        if (i < 0 || !actors_[i].alive || actors_[i].inside) continue;
        const int32_t want = enter_kind_for(size_t(i), size_t(t));
        if (want == ENTER_NONE || (kind != ENTER_NONE && kind != want)) continue;
        Actor& a = actors_[i];
        a.capture_target = target_id;
        a.enter_kind = want;
        a.enter_state = ENTER_APPROACH;

        a.capture_ticks = want == ENTER_CAPTURE ? std::max(1, types_[a.type].capture_delay) : 1;
        a.capture_total = a.capture_ticks;
        combats_[i].target = -1;
        combats_[i].attack_move = false;
        combats_[i].guard = -1;
        if (types_[a.type].harvester) harvests_[i].automated = false;

        const Actor& b = actors_[t];
        const UnitType& bt = types_[b.type];
        CPos best = mobiles_[i].cell;
        int64_t best_d = INT64_MAX;
        const int32_t emc = actor_move_class(size_t(i));
        for (int y = -1; y <= bt.foot_h; ++y) {
            for (int x = -1; x <= bt.foot_w; ++x) {
                if (x >= 0 && x < bt.foot_w && y >= 0 && y < bt.foot_h) continue;
                const CPos c{b.origin.x + x, b.origin.y + y};
                if (!map_.in_bounds(c) || !map_.passable(c, emc)) continue;
                const int64_t d = length_sq(WVec{WDist(c.x * CELL + CELL / 2), WDist(c.y * CELL + CELL / 2)} - actors_[i].pos);
                if (d < best_d) { best_d = d; best = c; }
            }
        }
        set_move(size_t(i), best, 0);
    }
}


void World::order_capture(const int32_t* ids, size_t n, int32_t target_id) {
    order_enter(ids, n, target_id, ENTER_NONE);
}

int32_t World::enter_progress(int32_t id) const {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive || actors_[i].capture_target < 0) return -1;
    const Actor& a = actors_[i];
    if (a.capture_total <= 1 || a.enter_kind != ENTER_CAPTURE) return -1;
    if (a.enter_state != ENTER_APPROACH) return 1000;
    return int32_t(int64_t(a.capture_total - a.capture_ticks) * 1000 / a.capture_total);
}


void World::set_owner(size_t i, int32_t owner) {
    Actor& a = actors_[i];
    if (a.owner == owner) return;
    a.owner = owner;
    a.primary = false;
    a.repairing = false;
    a.capture_target = -1;
    a.capture_ticks = 0;
    a.enter_kind = ENTER_NONE;
    combats_[i].target = -1;
    combats_[i].attack_move = false;
    if (types_[a.type].harvester) harvests_[i].automated = true;
    if (owner >= 0 && owner < MAX_PLAYERS) players_[owner].participant = true;

    fields_.clear();
}


bool World::set_owner_id(int32_t id, int32_t owner) {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive || owner < 0 || owner >= MAX_PLAYERS) return false;
    set_owner(size_t(i), owner);
    return true;
}


bool World::order_disguise(int32_t id, int32_t target_id) {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive || !types_[actors_[i].type].disguise) return false;
    if (target_id < 0) { actors_[i].disguise_type = -1; actors_[i].disguise_owner = -1; return true; }
    const int t = index_of(target_id);
    if (t < 0 || !actors_[t].alive || t == i) return false;
    int32_t as_type = actors_[t].disguise_type >= 0 ? actors_[t].disguise_type : actors_[t].type;
    int32_t as_owner = actors_[t].disguise_type >= 0 ? actors_[t].disguise_owner : actors_[t].owner;

    if (as_type == actors_[i].type && as_owner == actors_[i].owner) { as_type = -1; as_owner = -1; }
    actors_[i].disguise_type = as_type;
    actors_[i].disguise_owner = as_owner;
    return true;
}


bool World::set_disguise(int32_t id, int32_t type, int32_t owner) {
    const int i = index_of(id);
    if (i < 0 || !actors_[i].alive || !types_[actors_[i].type].disguise) return false;
    if (type < 0 || size_t(type) >= types_.size()) { actors_[i].disguise_type = -1; actors_[i].disguise_owner = -1; return true; }
    actors_[i].disguise_type = type;
    actors_[i].disguise_owner = owner;
    return true;
}


void World::enter_effect(size_t i, size_t t) {
    Actor& a = actors_[i];
    switch (a.enter_kind) {
    case ENTER_CAPTURE:

        set_owner(t, a.owner);
        dispose(i);
        break;
    case ENTER_REPAIR:

        actors_[t].hp = types_[actors_[t].type].hp;
        dispose(i);
        break;
    case ENTER_DEMOLISH:


        actors_[t].demolish_ticks = types_[a.type].demolition_delay;
        actors_[t].demolish_by = a.id;
        a.enter_state = ENTER_EXIT;
        break;
    case ENTER_INFILTRATE:
        infiltrate(i, t);
        dispose(i);
        break;
    default:
        a.capture_target = -1;
        break;
    }
}


void World::infiltrate(size_t i, size_t t) {
    ++actors_[t].infiltrated_count;
    actors_[t].infiltrated_by = actors_[i].id;
    const int32_t spy_owner = actors_[i].owner;
    const int32_t victim = actors_[t].owner;
    const UnitType& st = types_[actors_[i].type];
    const UnitType& bt = types_[actors_[t].type];
    const uint32_t types = st.infiltrates;


    if ((bt.infil_cash & types) != 0) {
        const int64_t take = credits(victim) * bt.infil_cash_percent / 100;
        const int64_t give = std::max<int64_t>(take, bt.infil_cash_min >= 0 ? bt.infil_cash_min : st.cost);
        take_cash(victim, take);
        give_credits(spy_owner, give);
        notify(victim, NOTIFY_CREDITS_STOLEN);
    }


    if ((bt.infil_explore & types) != 0) {
        if (spy_owner >= 0 && spy_owner < MAX_PLAYERS && vis_[spy_owner].size() == size_t(map_.cells()))
            for (uint8_t& v : vis_[spy_owner]) if (v == 0) v = 1;
        if (victim >= 0 && victim < MAX_PLAYERS) {
            for (uint8_t& v : vis_[victim]) v = 0;
            for (uint32_t& m : seen_mask_) m &= ~(1u << victim);
        }
    }

    if ((bt.infil_power & types) != 0 && victim >= 0 && victim < MAX_PLAYERS)
        players_[victim].power_outage = bt.infil_power_duration;


    if ((bt.infil_support & types) != 0 && !bt.infil_proxy.empty() && spy_owner >= 0 && spy_owner < MAX_PLAYERS) {
        std::vector<std::string>& tok = players_[spy_owner].infiltrated_tokens;
        if (std::find(tok.begin(), tok.end(), bt.infil_proxy) == tok.end()) {
            const int32_t before = buildable_total(spy_owner);
            tok.push_back(bt.infil_proxy);
            if (buildable_total(spy_owner) > before) notify(spy_owner, NOTIFY_NEW_OPTIONS);
        }
    }


    notify(spy_owner, NOTIFY_BUILDING_INFILTRATED);
}


bool World::leave_building(size_t i, size_t t) {
    Actor& a = actors_[i];
    const Actor& b = actors_[t];
    const UnitType& bt = types_[b.type];
    const int32_t self = static_cast<int32_t>(i);
    CPos best{0, 0};
    int64_t best_d = INT64_MAX;
    bool found = false;
    const int32_t lmc = actor_move_class(i);
    for (int y = -1; y <= bt.foot_h; ++y) {
        for (int x = -1; x <= bt.foot_w; ++x) {
            if (x >= 0 && x < bt.foot_w && y >= 0 && y < bt.foot_h) continue;
            const CPos c{b.origin.x + x, b.origin.y + y};
            if (!map_.in_bounds(c) || !map_.passable(c, lmc)) continue;

            if (shares_cell(a.type)) {
                if (occupant(c, SUB_FULL) >= 0 || free_subcell(c, mobiles_[i].sub, self) == SUB_INVALID) continue;
            } else if (!cell_free(c, self)) {
                continue;
            }
            const int64_t d = cell_dist_sq(c, a.enter_return);
            if (d < best_d) { best_d = d; best = c; found = true; }
        }
    }
    if (!found) return false;
    Mobile& m = mobiles_[i];

    const int32_t sub = shares_cell(a.type)
        ? std::max(int32_t(SUB_FIRST), free_subcell(best, m.sub, self)) : int32_t(SUB_FULL);
    m.cell = best;
    m.to_cell = best;
    m.sub = sub;
    m.to_sub = sub;
    m.goal = best;
    m.in_transit = false;
    m.moving = false;
    m.detour.clear();
    m.field = -1;
    a.pos = subcell_center(best, sub);
    slot_at(map_.index(best), sub) = self;
    a.inside = false;
    return true;
}


void World::step_enter() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (!actors_[i].alive || actors_[i].capture_target < 0) continue;
        const int t = index_of(actors_[i].capture_target);

        if (t < 0 || !actors_[t].alive) {
            if (actors_[i].inside) {
                actors_[i].inside = false;
                Mobile& m = mobiles_[i];
                const int32_t self = static_cast<int32_t>(i);
                const CPos c = find_free_cell(actors_[i].enter_return, actors_[i].type);
                const int32_t sub = shares_cell(actors_[i].type)
                    ? std::max(int32_t(SUB_FIRST), free_subcell(c, m.sub, self)) : int32_t(SUB_FULL);
                m.cell = c; m.to_cell = c; m.sub = sub; m.to_sub = sub; m.goal = c;
                m.in_transit = false;
                actors_[i].pos = subcell_center(c, sub);
                if (map_.in_bounds(c)) slot_at(map_.index(c), sub) = self;
            }
            actors_[i].capture_target = -1;
            actors_[i].enter_kind = ENTER_NONE;
            continue;
        }

        if (actors_[i].enter_state == ENTER_APPROACH &&
            enter_kind_for(i, size_t(t)) != actors_[i].enter_kind) {
            actors_[i].capture_target = -1;
            actors_[i].enter_kind = ENTER_NONE;
            continue;
        }
        switch (actors_[i].enter_state) {
        case ENTER_APPROACH: {
            const Actor& b = actors_[t];
            const UnitType& bt = types_[b.type];
            const CPos c = mobiles_[i].cell;
            const bool adjacent = c.x >= b.origin.x - 1 && c.x <= b.origin.x + bt.foot_w &&
                                  c.y >= b.origin.y - 1 && c.y <= b.origin.y + bt.foot_h;
            if (!adjacent || mobiles_[i].in_transit) {


                actors_[i].capture_ticks = actors_[i].capture_total;
                if (!mobiles_[i].moving && !mobiles_[i].in_transit) {
                    const int32_t id = actors_[i].id;
                    order_enter(&id, 1, actors_[i].capture_target, actors_[i].enter_kind);
                }
                continue;
            }
            if (--actors_[i].capture_ticks > 0) continue;

            actors_[i].enter_return = c;
            actors_[i].inside = true;
            clear_slots(i);
            mobiles_[i].moving = false;
            mobiles_[i].in_transit = false;
            mobiles_[i].detour.clear();
            actors_[i].pos = cell_center(CPos{b.origin.x + bt.foot_w / 2, b.origin.y + bt.foot_h / 2});
            actors_[i].enter_state = ENTER_INSIDE;
            break;
        }
        case ENTER_INSIDE:
            enter_effect(i, size_t(t));
            break;
        case ENTER_EXIT:
            if (leave_building(i, size_t(t))) {
                actors_[i].capture_target = -1;
                actors_[i].enter_kind = ENTER_NONE;
                actors_[i].enter_state = ENTER_APPROACH;
            }
            break;
        default:
            break;
        }
    }
}


void World::step_demolitions() {
    for (size_t i = 0; i < actors_.size(); ++i) {
        if (!actors_[i].alive || actors_[i].demolish_ticks < 0) continue;
        if (actors_[i].demolish_ticks-- > 0) continue;
        const int32_t by = actors_[i].demolish_by;
        actors_[i].demolish_ticks = -1;
        actors_[i].demolish_by = -1;
        kill(i, DAMAGE_EXPLOSION, by);
    }
}


void World::clamp_storage(int32_t owner) {
    if (owner < 0 || owner >= MAX_PLAYERS || !has_storage_) return;
    resources_[owner] = std::min(resources_[owner], storage_capacity(owner));
}

int64_t World::storage_capacity(int32_t owner) const {
    int64_t cap = 0;
    for (const Actor& a : actors_) {
        if (a.alive && a.owner == owner && a.make_ticks == 0 && a.sell_ticks < 0) cap += types_[a.type].storage;
    }
    return cap;
}


bool World::take_cash(int32_t owner, int64_t amount) {
    if (owner < 0 || owner >= MAX_PLAYERS || credits(owner) < amount) return false;
    resources_[owner] -= amount;
    if (resources_[owner] < 0) {
        credits_[owner] += resources_[owner];
        resources_[owner] = 0;
    }
    return true;
}


void World::give_resources(int32_t owner, int64_t amount) {
    if (owner < 0 || owner >= MAX_PLAYERS) return;
    if (!has_storage_) { resources_[owner] += amount; earned_[owner] += amount; return; }
    const int64_t cap = storage_capacity(owner);
    const int64_t before = resources_[owner];
    resources_[owner] = std::min(cap, resources_[owner] + amount);
    earned_[owner] += resources_[owner] - before;
    if (cap > 0 && resources_[owner] * 100 >= cap * 80 &&
        (silos_notified_[owner] == NOTIFY_NEVER || tick_ - silos_notified_[owner] > 20 * TICKS_PER_SECOND)) {
        silos_notified_[owner] = tick_;
        notify(owner, NOTIFY_SILOS_NEEDED);
    }
}


int64_t World::storage_room(int32_t owner) const {
    if (owner < 0 || owner >= MAX_PLAYERS || !has_storage_) return INT64_MAX;
    return std::max<int64_t>(0, storage_capacity(owner) - resources_[owner]);
}

}
