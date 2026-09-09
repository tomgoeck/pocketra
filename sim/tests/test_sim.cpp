
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "ra/sim.h"

static int failures = 0;
#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            std::printf("FEHLER %s:%d  %s\n", __FILE__, __LINE__, #cond);          \
            ++failures;                                                             \
        }                                                                           \
    } while (0)

using namespace ra;

static void test_math() {
    CHECK(isqrt(0) == 0);
    CHECK(isqrt(1) == 1);
    CHECK(isqrt(1024 * 1024) == 1024);
    CHECK(isqrt(99) == 9);

    CHECK(angle_of({0, -1000}) == 0);
    CHECK(angle_of({-1000, 0}) == 256);
    CHECK(angle_of({0, 1000}) == 512);
    CHECK(angle_of({1000, 0}) == 768);
    const WAngle nw = angle_of({-1000, -1000});
    CHECK(nw >= 126 && nw <= 130);


    CHECK(direction_of(0).x == 0 && direction_of(0).y == -1024);
    CHECK(direction_of(256).x == -1024 && direction_of(256).y == 0);
    CHECK(direction_of(512).x == 0 && direction_of(512).y == 1024);
    CHECK(direction_of(768).x == 1024 && direction_of(768).y == 0);
    CHECK(std::abs(direction_of(128).x + 724) <= 8 && std::abs(direction_of(128).y + 724) <= 8);

    CHECK(turn_towards(0, 100, 20) == 20);
    CHECK(turn_towards(10, 1000, 20) == 1014);
    CHECK(angle_diff(1000, 10) == 34);
}

static void test_flow_field() {

    std::vector<uint8_t> cost(25, 1);
    for (int y = 0; y < 4; ++y) cost[y * 5 + 2] = 0;
    Map map;
    map.reset(5, 5, cost.data());
    FlowField f;
    build_flow_field(map, {4, 0}, f);
    CHECK(f.dist[map.index({4, 0})] == 0);
    CHECK(f.dist[map.index({0, 0})] > f.dist[map.index({0, 4})]);
    CHECK(f.next[map.index({0, 0})] >= 0);
    CHECK(f.dist[map.index({2, 1})] == INT32_MAX);


    CHECK(map.can_step({1, 3}, 3));
}


static void test_diagonal_only_reachable() {

    std::vector<uint8_t> cost(9 * 9, 1);
    for (int y = 0; y < 9; ++y) cost[y * 9 + 4] = 0;
    cost[3 * 9 + 4] = 1;
    cost[3 * 9 + 5] = 0;
    cost[4 * 9 + 5] = 1;

    Map map;
    map.reset(9, 9, cost.data());
    FlowField f;
    build_flow_field(map, {8, 8}, f);
    CHECK(f.dist[map.index({0, 0})] != INT32_MAX);
    CHECK(f.dist[map.index({4, 3})] != INT32_MAX);


    World w;
    w.set_map(9, 9, cost.data());
    const int tank = w.define_type({72, 20, false});
    const int32_t id = w.spawn(tank, 0, {1, 1});
    w.order_move(&id, 1, {7, 7});
    for (uint32_t t = 0; t < 900; ++t) w.step();
    const CPos c = to_cell(w.actor(0).pos);
    std::printf("Diagonalengpass: Einheit bei (%d,%d), Ziel (7,7)\n", c.x, c.y);
    CHECK(c.x >= 5);
}

static void test_movement_and_determinism() {
    auto run = [](uint32_t ticks) {
        World w;
        std::vector<uint8_t> cost(64 * 64, 1);
        w.set_map(64, 64, cost.data());
        const int tank = w.define_type({72, 20, false});
        const int inf = w.define_type({56, 1024, true});
        std::vector<int32_t> ids;
        for (int i = 0; i < 100; ++i) ids.push_back(w.spawn(i % 3 == 0 ? inf : tank, 0, {5 + i % 10, 5 + i / 10}));
        w.order_move(ids.data(), ids.size(), {50, 50});
        for (uint32_t t = 0; t < ticks; ++t) w.step();
        return w;
    };

    World a = run(3000);
    World b = run(3000);
    CHECK(a.tick() == 3000);
    for (size_t i = 0; i < a.actor_count(); ++i) {
        CHECK(a.actor(i).pos == b.actor(i).pos);
        CHECK(a.actor(i).facing == b.actor(i).facing);
    }

    uint32_t moving = a.moving_count();
    CHECK(moving == 0);
    int near = 0;
    for (size_t i = 0; i < a.actor_count(); ++i) {
        const CPos c = to_cell(a.actor(i).pos);
        const Mobile& m = a.mobile(i);

        const bool is_near = std::abs(c.x - 50) <= 17 && std::abs(c.y - 50) <= 17;
        if (is_near) ++near;
        if (!is_near || m.moving || m.in_transit) {
            const int32_t occ = a.occupant({c.x, c.y});
            std::printf("  Actor %zu bei (%d,%d) moving=%d transit=%d to=(%d,%d) waited=%d wait=%d occ=%d\n",
                        i, c.x, c.y, m.moving, m.in_transit, m.to_cell.x, m.to_cell.y, m.has_waited, m.wait, occ);
        }
    }


    CHECK(near >= 97);
    for (size_t i = 0; i < a.actor_count(); ++i) {
        const CPos c = to_cell(a.actor(i).pos);
        CHECK(std::abs(c.x - 50) <= 20 && std::abs(c.y - 50) <= 20);
    }

    std::vector<int> seen(64 * 64, 0);
    for (size_t i = 0; i < a.actor_count(); ++i) seen[a.map().index(to_cell(a.actor(i).pos))]++;
    for (int v : seen) CHECK(v <= 1);
    CHECK(a.fields().builds() <= 9);
}


static void test_no_backwards_movement() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    Weapon cannon;
    cannon.range = 4 * CELL; cannon.reload = 50; cannon.damage = 100; cannon.spread = 128; cannon.speed = 682;
    for (int i = 0; i < NUM_ARMOR; ++i) cannon.versus[i] = 30;
    const int w_cannon = w.define_weapon(cannon);
    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 1000000; tank.armor = ARMOR_HEAVY;
    tank.weapon = w_cannon; tank.turreted = true; tank.turret_turn = 20; tank.hit_radius = 400;
    UnitType inf;
    inf.speed = 56; inf.turn_rate = 1024; inf.infantry = true; inf.hp = 1000000; inf.hit_radius = 128;
    inf.locomotor = LOCO_FOOT;
    const int t_tank = w.define_type(tank);
    const int t_inf = w.define_type(inf);
    std::vector<int32_t> mine, foe;
    for (int i = 0; i < 20; ++i) mine.push_back(w.spawn(i % 3 == 0 ? t_inf : t_tank, 0, {4 + i % 4, 4 + i / 4}));
    for (int i = 0; i < 6; ++i) foe.push_back(w.spawn(t_tank, 1, {30 + i % 3, 30 + i / 3}));
    w.set_enemy(0, 1, true);
    w.order_attack_move(mine.data(), mine.size(), {32, 32});
    w.order_move(foe.data(), foe.size(), {4, 4}, 0);

    struct Prev { CPos to; int32_t sub; int32_t dist; bool transit; };
    std::vector<Prev> prev(w.actor_count(), Prev{CPos{0, 0}, 0, 0, false});
    int backwards = 0;
    int32_t worst = 0;
    for (int t = 0; t < 400; ++t) {

        if (t % 11 == 0) w.order_move(&mine[size_t(t / 11) % mine.size()], 1, {32, 32}, 0);
        if (t % 17 == 0) w.order_stop(&mine[size_t(t / 17) % mine.size()], 1);
        w.step();
        for (size_t i = 0; i < w.actor_count(); ++i) {
            const Mobile& m = w.mobile(i);
            const int32_t d = length(subcell_center(m.to_cell, m.to_sub) - w.actor(i).pos);
            if (m.in_transit && prev[i].transit && prev[i].to == m.to_cell && prev[i].sub == m.to_sub && d > prev[i].dist) {
                const int32_t back = d - prev[i].dist;
                if (back > worst) worst = back;

                if (back > 8) {
                    ++backwards;
                    if (backwards <= 5)
                        std::printf("  Rückwärts: Tick %d Actor %zu um %d (Abstand %d → %d, to=%d,%d)\n",
                                    t, i, back, prev[i].dist, d, m.to_cell.x, m.to_cell.y);
                }
            }
            prev[i] = Prev{m.to_cell, m.to_sub, d, m.in_transit};
        }
    }
    std::printf("Rückwärtsbewegung in 400 Ticks (20 Einheiten, Gefecht + Umbefehle): %d (größter Rückfall %d)\n",
                backwards, worst);
    CHECK(backwards == 0);
}

static void test_combat() {
    auto run = [](uint32_t ticks) {
        World w;
        std::vector<uint8_t> cost(32 * 32, 1);
        w.set_map(32, 32, cost.data());

        Weapon cannon;
        cannon.range = 4 * CELL + 768; cannon.reload = 50; cannon.damage = 4000; cannon.spread = 128; cannon.speed = 682;
        const int32_t cv[NUM_ARMOR] = {30, 75, 75, 115, 50};
        for (int i = 0; i < NUM_ARMOR; ++i) cannon.versus[i] = cv[i];
        Weapon rifle;
        rifle.range = 5 * CELL; rifle.reload = 20; rifle.damage = 1000; rifle.spread = 128; rifle.speed = 0; rifle.inaccuracy = 171;
        const int32_t rv[NUM_ARMOR] = {150, 30, 40, 10, 10};
        for (int i = 0; i < NUM_ARMOR; ++i) rifle.versus[i] = rv[i];
        const int w_cannon = w.define_weapon(cannon);
        const int w_rifle = w.define_weapon(rifle);
        UnitType tank;
        tank.speed = 72; tank.turn_rate = 20; tank.hp = 46000; tank.armor = ARMOR_HEAVY; tank.weapon = w_cannon;
        tank.turreted = true; tank.turret_turn = 20; tank.hit_radius = 400;
        UnitType inf;
        inf.speed = 56; inf.turn_rate = 1024; inf.infantry = true; inf.hp = 5000; inf.armor = ARMOR_NONE; inf.weapon = w_rifle; inf.hit_radius = 128;
        const int t_tank = w.define_type(tank);
        const int t_inf = w.define_type(inf);
        std::vector<int32_t> tanks, infs;
        for (int i = 0; i < 5; ++i) tanks.push_back(w.spawn(t_tank, 0, {5, 5 + i}));
        for (int i = 0; i < 10; ++i) infs.push_back(w.spawn(t_inf, 1, {12 + i % 2, 4 + i / 2}));
        w.order_attack_move(tanks.data(), tanks.size(), {20, 8});
        for (uint32_t t = 0; t < ticks; ++t) w.step();
        return w;
    };
    World a = run(800);
    World b = run(800);
    for (size_t i = 0; i < a.actor_count(); ++i) {
        CHECK(a.actor(i).pos == b.actor(i).pos);
        CHECK(a.actor(i).hp == b.actor(i).hp);
    }


    std::printf("Kampf nach 800 Ticks: Panzer %u/5, Infanterie %u/10\n", a.alive_count(0), a.alive_count(1));
    CHECK(a.alive_count(0) == 5);
    CHECK(a.alive_count(1) == 0);
}

static void test_economy() {
    auto run = [](uint32_t ticks) {
        World w;
        std::vector<uint8_t> cost(40 * 40, 1);
        w.set_map(40, 40, cost.data());

        UnitType proc;
        proc.building = true; proc.foot_w = 3; proc.foot_h = 4;
        proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0};
        proc.sprite_h = 3; proc.refinery = true; proc.dock_dx = 1; proc.dock_dy = 2; proc.dock_angle = 256;
        proc.hp = 90000; proc.armor = ARMOR_WOOD; proc.hit_radius = 1536;

        UnitType harv;
        harv.speed = 72; harv.turn_rate = 20; harv.hp = 60000; harv.armor = ARMOR_HEAVY; harv.hit_radius = 512;
        harv.harvester = true; harv.capacity = 20; harv.bale_load_delay = 4; harv.bale_unload_delay = 1;
        harv.search_from_proc = 15; harv.search_from_harv = 8;
        const int t_proc = w.define_type(proc);
        const int t_harv = w.define_type(harv);
        w.spawn_building(t_proc, 0, {10, 10});
        const int32_t h = w.spawn(t_harv, 0, {14, 13});
        for (int y = 16; y < 21; ++y)
            for (int x = 8; x < 13; ++x) w.set_resource({x, y}, RES_ORE, 12);
        (void)h;
        for (uint32_t t = 0; t < ticks; ++t) w.step();
        return w;
    };
    World a = run(3000);
    World b = run(3000);
    CHECK(a.credits(0) == b.credits(0));
    CHECK(a.actor(1).pos == b.actor(1).pos);

    CHECK(a.occupant({11, 10}) == 0);
    CHECK(a.occupant({10, 10}) == -1);
    CHECK(a.occupant({11, 12}) != 0);

    std::printf("Wirtschaft nach 3000 Ticks: %lld Credits, Harvester-Zustand %d, Ballen %d\n",
                static_cast<long long>(a.credits(0)), int(a.harvest(1).state), a.harvest(1).bales);
    CHECK(a.credits(0) >= 1500);
    CHECK(a.credits(0) % 25 == 0);
}


static void test_buildings_block_movement() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());

    UnitType tsla;
    tsla.building = true; tsla.foot_w = 1; tsla.foot_h = 1; tsla.footprint = {1}; tsla.sprite_h = 1;
    tsla.hp = 40000; tsla.armor = ARMOR_CONCRETE;

    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 4;
    proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0};
    proc.sprite_h = 3; proc.refinery = true; proc.dock_dx = 1; proc.dock_dy = 2; proc.dock_angle = 256;
    proc.hp = 90000; proc.armor = ARMOR_WOOD; proc.hit_radius = 1536;
    UnitType harv;
    harv.speed = 72; harv.turn_rate = 20; harv.hp = 60000; harv.armor = ARMOR_HEAVY; harv.hit_radius = 512;
    harv.harvester = true; harv.capacity = 20; harv.bale_load_delay = 4; harv.bale_unload_delay = 1;
    harv.search_from_proc = 15; harv.search_from_harv = 8;
    UnitType e1;
    e1.speed = 42; e1.turn_rate = 1024; e1.hp = 5000; e1.infantry = true; e1.locomotor = LOCO_FOOT;
    const int t_tsla = w.define_type(tsla), t_proc = w.define_type(proc);
    const int t_harv = w.define_type(harv), t_e1 = w.define_type(e1);


    for (int y = 4; y < 30; ++y) w.spawn_building(t_tsla, 1, {20, y});
    w.spawn_building(t_proc, 0, {10, 10});
    const int32_t hid = w.spawn(t_harv, 0, {14, 14});
    const int32_t iid = w.spawn(t_e1, 0, {14, 16});

    w.order_move(&hid, 1, {30, 14});
    w.order_move(&iid, 1, {30, 16});
    for (int y = 16; y < 21; ++y)
        for (int x = 4; x < 9; ++x) w.set_resource({x, y}, RES_ORE, 12);

    auto in_proc = [](CPos c) {
        static const CPos cells[] = {{11, 10}, {10, 11}, {11, 11}, {12, 11}, {10, 12}};
        for (const CPos p : cells) if (p == c) return true;
        return false;
    };
    bool in_tsla = false, in_building = false;
    for (uint32_t t = 0; t < 4000; ++t) {
        w.step();
        for (size_t i = 0; i < w.actor_count(); ++i) {
            if (!w.actor(i).alive || w.actor(i).type == t_tsla || w.actor(i).type == t_proc) continue;
            const CPos c = to_cell(w.actor(i).pos);
            if (c.x == 20 && c.y >= 4 && c.y < 30) in_tsla = true;
            if (in_proc(c)) in_building = true;
        }
    }
    CHECK(!in_tsla);
    CHECK(!in_building);

    CHECK(w.occupant({20, 10}) >= 0);
    CHECK(w.occupant({11, 11}) >= 0);
    CHECK(w.occupant({11, 13}) < 0 || w.actor(size_t(w.occupant({11, 13}))).type != t_proc);
    std::printf("Gebäude sperren: Tesla-Zelle betreten %d, Raffineriezelle betreten %d\n",
                int(in_tsla), int(in_building));
}


static void test_barrels() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());

    Weapon cluster;
    cluster.damage = 5000; cluster.spread = 325; cluster.damage_type = DAMAGE_FIRE;
    cluster.delay = 5;
    cluster.trigger_prone = true; cluster.prone_damage = 50;
    cluster.falloff_steps = 7;
    const int fo[7] = {1000, 368, 135, 50, 18, 7, 0};
    for (int i = 0; i < 7; ++i) cluster.falloff[i] = fo[i];

    for (int i = 0; i < NUM_ARMOR; ++i) cluster.versus[i] = 100;
    cluster.versus[ARMOR_NONE] = 120;
    cluster.versus[ARMOR_WOOD] = 20;
    cluster.versus[ARMOR_LIGHT] = 50;
    cluster.versus[ARMOR_HEAVY] = 25;
    cluster.versus[ARMOR_CONCRETE] = 10;
    const int32_t w_cluster = w.define_weapon(cluster);

    Weapon explode;
    explode.damage = 0; explode.spread = 325; explode.delay = 5;
    explode.cluster_weapon = w_cluster;
    explode.cluster_count = 4;
    const int8_t cdx[4] = {0, -1, 1, 0}, cdy[4] = {-1, 0, 0, 1};
    for (int i = 0; i < 4; ++i) { explode.cluster_dx[i] = cdx[i]; explode.cluster_dy[i] = cdy[i]; }
    const int32_t w_explode = w.define_weapon(explode);

    Weapon rifle;
    rifle.damage = 1500; rifle.spread = 43; rifle.range = 5 * CELL; rifle.reload = 20;
    const int32_t w_rifle = w.define_weapon(rifle);

    UnitType barl;
    barl.building = true; barl.foot_w = 1; barl.foot_h = 1; barl.footprint = {1}; barl.sprite_h = 1;
    barl.hp = 1000; barl.targetable = true; barl.death_weapon = w_explode;
    UnitType e1;
    e1.speed = 42; e1.turn_rate = 1024; e1.hp = 5000; e1.infantry = true; e1.locomotor = LOCO_FOOT;
    e1.targetable = true; e1.weapon = w_rifle; e1.no_auto_target = true;
    const int t_barl = w.define_type(barl), t_e1 = w.define_type(e1);

    w.set_neutral_player(2);


    const int32_t b1 = w.spawn_building(t_barl, 2, {10, 10});
    for (int x = 11; x <= 14; ++x) w.spawn_building(t_barl, 2, {x, 10});
    const int32_t victim = w.spawn(t_e1, 1, {10, 11});
    const int32_t gunner = w.spawn(t_e1, 0, {10, 15});
    w.order_attack(&gunner, 1, b1);
    for (int t = 0; t < 400 && w.actor(size_t(w.index_of(b1))).alive; ++t) w.step();
    CHECK(!w.actor(size_t(w.index_of(b1))).alive);
    for (int t = 0; t < 100; ++t) w.step();

    CHECK(w.alive_count(2) == 0);
    CHECK(!w.actor(size_t(w.index_of(victim))).alive);
    CHECK(w.actor(size_t(w.index_of(gunner))).alive);
    std::printf("Fässer: Kettenreaktion, %u von 5 Fässern übrig, Opfer tot %d, Schütze lebt %d\n",
                w.alive_count(2), int(!w.actor(size_t(w.index_of(victim))).alive),
                int(w.actor(size_t(w.index_of(gunner))).alive));


    World v;
    std::vector<uint8_t> vcost(20 * 20, 1);
    v.set_map(20, 20, vcost.data());
    const int32_t vw_cluster = v.define_weapon(cluster);
    Weapon vexplode = explode; vexplode.cluster_weapon = vw_cluster;
    const int32_t vw_explode = v.define_weapon(vexplode);
    Weapon vrifle = rifle;
    const int32_t vw_rifle = v.define_weapon(vrifle);
    UnitType vbarl = barl; vbarl.death_weapon = vw_explode;
    UnitType ve1 = e1; ve1.weapon = vw_rifle;
    const int v_barl = v.define_type(vbarl), v_e1 = v.define_type(ve1);
    UnitType tnk_light; tnk_light.speed = 72; tnk_light.turn_rate = 1024; tnk_light.hp = 40000;
    tnk_light.armor = ARMOR_LIGHT; tnk_light.targetable = true; tnk_light.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType tnk_heavy = tnk_light; tnk_heavy.armor = ARMOR_HEAVY;
    const int v_1tnk = v.define_type(tnk_light), v_3tnk = v.define_type(tnk_heavy);

    v.set_neutral_player(2);
    const int32_t vb1 = v.spawn_building(v_barl, 2, {10, 10});
    const int32_t v_gunner = v.spawn(v_e1, 0, {10, 15});
    const int32_t light_id = v.spawn(v_1tnk, 1, {10, 8});
    const int32_t heavy_id = v.spawn(v_3tnk, 1, {8, 10});
    const int32_t light_hp0 = v.actor(size_t(v.index_of(light_id))).hp;
    const int32_t heavy_hp0 = v.actor(size_t(v.index_of(heavy_id))).hp;
    v.order_attack(&v_gunner, 1, vb1);
    for (int t = 0; t < 400; ++t) v.step();


    const int32_t dist = 1 * CELL, spread = 325;
    const int32_t step = dist / spread, rem = dist - step * spread;
    const int32_t fo7[7] = {1000, 368, 135, 50, 18, 7, 0};
    const int32_t f0 = fo7[step], f1 = fo7[step + 1];
    const int32_t falloff_pct = f0 + (f1 - f0) * rem / spread;
    const int32_t expect_light = 5000 * falloff_pct / 100 * 50 / 100;
    const int32_t expect_heavy = 5000 * falloff_pct / 100 * 25 / 100;
    const int32_t light_dmg = light_hp0 - v.actor(size_t(v.index_of(light_id))).hp;
    const int32_t heavy_dmg = heavy_hp0 - v.actor(size_t(v.index_of(heavy_id))).hp;
    std::printf("Fässer: 1tnk (Light) %d von erwarteten %d Schaden, 3tnk (Heavy) %d von erwarteten %d\n",
                light_dmg, expect_light, heavy_dmg, expect_heavy);
    CHECK(light_dmg == expect_light);
    CHECK(heavy_dmg == expect_heavy);
}

static void test_production() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());

    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 4; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0};
    fact.sprite_h = 3; fact.hp = 150000; fact.armor = ARMOR_WOOD; fact.produces = 1u << QUEUE_BUILDING;
    fact.base_provider = true; fact.provides = {"fact", "structures.allies"};
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 3; powr.footprint = {1, 1, 1, 1, 0, 0};
    powr.build_block = {1, 1, 1, 1, 1, 1};
    powr.sprite_h = 2; powr.hp = 40000; powr.armor = ARMOR_WOOD; powr.power = 100; powr.cost = 300;
    powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"}; powr.make_ticks = 20;
    UnitType tent;
    tent.building = true; tent.foot_w = 2; tent.foot_h = 3; tent.footprint = {1, 1, 1, 1, 0, 0};
    tent.build_block = {1, 1, 1, 1, 1, 1};
    tent.sprite_h = 2; tent.hp = 60000; tent.armor = ARMOR_WOOD; tent.power = -20; tent.cost = 500; tent.sellable = true;
    tent.queue_kind = QUEUE_BUILDING; tent.prerequisites = {"anypower"}; tent.provides = {"tent", "barracks"};
    tent.produces = 1u << QUEUE_INFANTRY; tent.exit_dx = 1; tent.exit_dy = 2; tent.make_ticks = 20;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.cost = 100;
    e1.queue_kind = QUEUE_INFANTRY; e1.prerequisites = {"barracks"};
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr), t_tent = w.define_type(tent), t_e1 = w.define_type(e1);
    w.spawn_building(t_fact, 0, {10, 10});
    w.give_credits(0, 1000);

    std::vector<int32_t> list;
    w.buildable(0, QUEUE_BUILDING, list);
    CHECK(list.size() == 1 && list[0] == t_powr);
    CHECK(!w.queue_build(0, t_tent));
    CHECK(w.queue_build(0, t_powr));

    for (int t = 0; t < 179; ++t) w.step();
    CHECK(!w.queue(0, QUEUE_BUILDING).front().done);
    w.step();
    CHECK(w.queue(0, QUEUE_BUILDING).front().done);
    CHECK(w.credits(0) == 700);

    CHECK(!w.can_place(0, t_powr, {30, 30}, nullptr));
    CHECK(!w.place_building(0, t_powr, {30, 30}));
    CHECK(w.can_place(0, t_powr, {14, 10}, nullptr));
    CHECK(w.place_building(0, t_powr, {14, 10}));
    CHECK(w.queue(0, QUEUE_BUILDING).empty());

    CHECK(w.has_prerequisite(0, "anypower"));
    for (int t = 0; t < 21; ++t) w.step();
    CHECK(w.has_prerequisite(0, "anypower"));
    CHECK(w.power_provided(0) == 100);


    CHECK(w.queue_build(0, t_powr));
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(!w.can_place(0, t_powr, {14, 12}, nullptr));
    CHECK(!w.can_place(0, t_powr, {14, 8}, nullptr));
    CHECK(w.can_place(0, t_powr, {14, 7}, nullptr));
    CHECK(w.can_place(0, t_powr, {14, 13}, nullptr));
    CHECK(w.cancel_build(0, QUEUE_BUILDING, t_powr));

    CHECK(w.queue_build(0, t_tent));
    for (int t = 0; t < 301; ++t) w.step();
    CHECK(w.queue(0, QUEUE_BUILDING).front().done);
    CHECK(w.place_building(0, t_tent, {10, 14}));
    for (int t = 0; t < 21; ++t) w.step();
    CHECK(w.power_drained(0) == 20);
    const size_t before = w.actor_count();
    CHECK(w.queue_build(0, t_e1));
    CHECK(w.queue_build(0, t_e1));
    for (int t = 0; t < 61; ++t) w.step();
    CHECK(w.actor_count() == before + 1);
    CHECK(w.actor(before).owner == 0 && w.actor(before).type == t_e1);
    CHECK(w.queue(0, QUEUE_INFANTRY).size() == 1);

    w.give_credits(0, -w.credits(0));
    for (int t = 0; t < 30; ++t) w.step();
    CHECK(!w.queue(0, QUEUE_INFANTRY).front().done);
    std::vector<int32_t> notes;
    w.drain_notifications(0, notes);
    CHECK(std::find(notes.begin(), notes.end(), NOTIFY_INSUFFICIENT_FUNDS) != notes.end());
    std::printf("Bauen: Credits %lld nach Kraftwerk, Kaserne und %zu Infanterist(en)\n",
                static_cast<long long>(w.credits(0)), w.actor_count() - before);


    w.give_credits(0, 5000);
    const int32_t tent_id = w.actor(before - 1).id;
    CHECK(w.actor(before - 1).type == t_tent);
    CHECK(w.actor(before - 1).rally.x == 11 && w.actor(before - 1).rally.y == 17);
    CHECK(w.set_rally(tent_id, {20, 20}));
    CHECK(!w.set_rally(w.actor(before - 2).id, {20, 20}));
    CHECK(w.set_primary(tent_id));
    CHECK(w.actor(before - 1).primary);
    for (int t = 0; t < 70; ++t) w.step();
    CHECK(w.actor_count() == before + 2);
    CHECK(w.mobile(before + 1).goal.x == 20 && w.mobile(before + 1).goal.y == 20);

    Actor& tent_a = const_cast<Actor&>(w.actor(before - 1));
    tent_a.hp = 60000 - 1400;
    const int64_t c0 = w.credits(0);
    CHECK(w.toggle_repair(tent_id));
    w.step();
    CHECK(w.actor(before - 1).hp == 60000 - 700);
    CHECK(w.credits(0) == c0 - std::max<int64_t>(1, 700LL * 20 * 500 / (60000LL * 100)));
    for (int t = 0; t < 25; ++t) w.step();
    CHECK(w.actor(before - 1).hp == 60000 && !w.actor(before - 1).repairing);

    CHECK(w.queue_build(0, t_e1));
    const int64_t c1 = w.credits(0);
    CHECK(w.sell(tent_id));
    CHECK(!w.sell(tent_id));
    for (int t = 0; t < 21; ++t) w.step();
    CHECK(!w.actor(before - 1).alive);
    CHECK(w.map().passable({10, 14}));
    CHECK(w.credits(0) >= c1 + 250 && w.queue(0, QUEUE_INFANTRY).empty());
    std::vector<int32_t> notes2;
    w.drain_notifications(0, notes2);
    CHECK(std::find(notes2.begin(), notes2.end(), NOTIFY_STRUCTURE_SOLD) != notes2.end());
    CHECK(std::find(notes2.begin(), notes2.end(), NOTIFY_REPAIRING) != notes2.end());
    std::printf("Gebäude: Sammelpunkt, Primär, Reparatur, Verkauf OK (Credits %lld)\n", static_cast<long long>(w.credits(0)));
}


static void test_bot() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    Weapon gun; gun.range = 5 * CELL; gun.reload = 50; gun.damage = 3000; gun.speed = 0;
    const int wgun = w.define_weapon(gun);
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 4; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0};
    fact.sprite_h = 3; fact.hp = 150000; fact.armor = ARMOR_WOOD; fact.produces = 1u << QUEUE_BUILDING;
    fact.base_provider = true; fact.provides = {"fact"};
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 3; powr.footprint = {1, 1, 1, 1, 0, 0};
    powr.sprite_h = 2; powr.hp = 40000; powr.armor = ARMOR_WOOD; powr.power = 100; powr.cost = 300;
    powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"}; powr.make_ticks = 20;
    powr.ai_building_fraction = 1;
    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 4; proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0};
    proc.sprite_h = 3; proc.hp = 90000; proc.armor = ARMOR_WOOD; proc.power = -30; proc.cost = 1400;
    proc.queue_kind = QUEUE_BUILDING; proc.prerequisites = {"anypower"}; proc.provides = {"proc"};
    proc.refinery = true; proc.dock_dx = 1; proc.dock_dy = 2; proc.make_ticks = 20; proc.ai_building_fraction = 1;
    UnitType tent;
    tent.building = true; tent.foot_w = 2; tent.foot_h = 3; tent.footprint = {1, 1, 1, 1, 0, 0};
    tent.sprite_h = 2; tent.hp = 60000; tent.armor = ARMOR_WOOD; tent.power = -20; tent.cost = 500;
    tent.queue_kind = QUEUE_BUILDING; tent.prerequisites = {"anypower"}; tent.provides = {"tent", "barracks"};
    tent.produces = 1u << QUEUE_INFANTRY; tent.exit_dx = 1; tent.exit_dy = 2; tent.make_ticks = 20;
    tent.ai_building_fraction = 3; tent.ai_building_limit = 7;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.cost = 100; e1.weapon = wgun;
    e1.queue_kind = QUEUE_INFANTRY; e1.prerequisites = {"barracks"}; e1.ai_unit_share = 65;
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr), t_proc = w.define_type(proc);
    const int t_tent = w.define_type(tent), t_e1 = w.define_type(e1);
    (void)t_proc;
    w.spawn_building(t_fact, 0, {5, 5});
    w.spawn_building(t_fact, 1, {50, 50});
    for (int i = 0; i < 6; ++i) w.set_resource({44 + i, 52}, RES_ORE, 12);
    w.give_credits(0, 3000);
    w.give_credits(1, 20000);
    BotParams bp;
    bp.squad_size = 6;
    bp.squad_size_random_bonus = 1;
    w.enable_bot(1, bp);
    CHECK(w.bot_enabled(1));
    int32_t bot_buildings = 0, bot_units = 0;
    for (int t = 0; t < 12000; ++t) w.step();
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        if (!a.alive || a.owner != 1) continue;
        if (w.type(a.type).building) ++bot_buildings; else ++bot_units;
    }
    CHECK(bot_buildings >= 3);
    CHECK(bot_units >= 6);
    CHECK(w.has_prerequisite(1, "barracks"));

    const bool attacked = w.actor(0).hp < 150000;
    std::printf("KI nach 12000 Ticks: %d Gebäude, %d Einheiten, Squads %zu, Spieler-Bauhof HP %d%s\n",
                bot_buildings, bot_units, w.bot_squad_count(1), w.actor(0).hp, attacked ? " (angegriffen)" : "");
    CHECK(attacked || w.bot_squad_count(1) > 0);
    (void)t_powr; (void)t_tent; (void)t_e1;
}


static void test_bot_difficulty() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.sprite_h = 3; fact.hp = 150000; fact.produces = 1u << QUEUE_BUILDING;
    fact.base_provider = true; fact.provides = {"fact"};
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.sprite_h = 2; powr.hp = 40000; powr.power = 100; powr.cost = 300;
    powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"}; powr.make_ticks = 20;
    powr.ai_building_fraction = 1;
    UnitType pbox;
    pbox.building = true; pbox.foot_w = 1; pbox.foot_h = 1; pbox.footprint = {1};
    pbox.sprite_h = 1; pbox.hp = 40000; pbox.cost = 400; pbox.power = 0;
    pbox.queue_kind = QUEUE_BUILDING; pbox.prerequisites = {"anypower"}; pbox.make_ticks = 20;
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr), t_pbox = w.define_type(pbox);
    w.spawn_building(t_fact, 1, {30, 30});
    w.give_credits(1, 20000);
    BotParams bp;
    bp.building_fraction.assign(size_t(t_pbox) + 1, -1);
    bp.building_fraction[size_t(t_powr)] = 1;
    bp.building_fraction[size_t(t_pbox)] = 13;
    bp.building_limit.assign(size_t(t_pbox) + 1, 100);
    bp.building_delay.assign(size_t(t_pbox) + 1, 0);
    w.enable_bot(1, bp);
    for (int t = 0; t < 6000; ++t) w.step();
    int32_t boxes = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        if (a.alive && a.owner == 1 && a.type == t_pbox) ++boxes;
    }
    std::printf("KI-Stärke: Turtle-Tabelle baut %d Bunker (Typwert wäre 0)\n", boxes);
    CHECK(boxes > 0);
    (void)t_fact;


    World h;
    std::vector<uint8_t> hcost(20 * 32, 1);
    h.set_map(20, 32, hcost.data());
    Weapon gun; gun.range = 5 * CELL; gun.reload = 1000; gun.damage = 10000; gun.speed = 0;
    for (int i = 0; i < NUM_ARMOR; ++i) gun.versus[i] = 100;
    const int wgun = h.define_weapon(gun);
    UnitType shooter; shooter.speed = 0; shooter.hp = 100000; shooter.weapon = wgun;
    shooter.facing_tolerance = 1024; shooter.turn_rate = 1024;
    UnitType dummy; dummy.speed = 0; dummy.hp = 100000; dummy.turn_rate = 1024;
    const int t_shoot = h.define_type(shooter), t_dummy = h.define_type(dummy);
    h.set_handicap(2, 25);
    const int32_t a0 = h.spawn(t_shoot, 0, {3, 3}), v0 = h.spawn(t_dummy, 1, {5, 3});
    const int32_t a1 = h.spawn(t_shoot, 2, {3, 10}), v1 = h.spawn(t_dummy, 1, {5, 10});
    const int32_t a2 = h.spawn(t_shoot, 0, {3, 16}), v2 = h.spawn(t_dummy, 2, {5, 16});
    (void)a0; (void)a1; (void)a2;
    for (int t = 0; t < 60; ++t) h.step();
    const int32_t d_plain = 100000 - h.actor(size_t(h.index_of(v0))).hp;
    const int32_t d_weak = 100000 - h.actor(size_t(h.index_of(v1))).hp;
    const int32_t d_soft = 100000 - h.actor(size_t(h.index_of(v2))).hp;
    std::printf("Handicap 25 %%: Schaden normal %d, Schütze behindert %d, Opfer behindert %d\n",
                d_plain, d_weak, d_soft);
    CHECK(d_plain == 10000);
    CHECK(d_weak == 7500);
    CHECK(d_soft == 13333 || d_soft == 13334);


    h.set_handicap(3, 50);
    h.set_handicap(4, 10);
    const int32_t a3 = h.spawn(t_shoot, 3, {3, 22}), v3 = h.spawn(t_dummy, 1, {5, 22});
    const int32_t a4 = h.spawn(t_shoot, 0, {3, 28}), v4 = h.spawn(t_dummy, 4, {5, 28});
    (void)a3; (void)a4;
    for (int t = 0; t < 60; ++t) h.step();
    const int32_t d_weak50 = 100000 - h.actor(size_t(h.index_of(v3))).hp;
    const int32_t d_soft10 = 100000 - h.actor(size_t(h.index_of(v4))).hp;
    std::printf("Handicap 50/10 %%: Schütze behindert %d, Opfer behindert %d\n", d_weak50, d_soft10);
    CHECK(d_weak50 == 5000);
    CHECK(d_soft10 == 11111);

    UnitType unit; unit.speed = 40; unit.hp = 1000; unit.cost = 500; unit.queue_kind = QUEUE_INFANTRY;
    unit.turn_rate = 1024;
    UnitType barr;
    barr.building = true; barr.foot_w = 2; barr.foot_h = 2; barr.footprint = {1, 1, 1, 1};
    barr.sprite_h = 2; barr.hp = 40000; barr.produces = 1u << QUEUE_INFANTRY;
    barr.exit_dx = 1; barr.exit_dy = 2;
    const int t_unit = h.define_type(unit), t_barr = h.define_type(barr);
    h.spawn_building(t_barr, 0, {14, 3});
    h.spawn_building(t_barr, 2, {14, 14});
    h.spawn_building(t_barr, 3, {14, 22});
    h.spawn_building(t_barr, 4, {14, 28});
    std::printf("Handicap 25 %%: Bauzeit %d statt %d Ticks (100 + H)\n",
                h.build_time(2, t_unit), h.build_time(0, t_unit));
    CHECK(h.build_time(0, t_unit) == 300);
    CHECK(h.build_time(2, t_unit) == 375);
    std::printf("Handicap 50/10 %%: Bauzeit %d / %d Ticks (100 + H)\n",
                h.build_time(3, t_unit), h.build_time(4, t_unit));
    CHECK(h.build_time(3, t_unit) == 450);
    CHECK(h.build_time(4, t_unit) == 330);
}


static void test_defense_depot_victory() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    Weapon gun; gun.range = 6 * CELL; gun.reload = 30; gun.damage = 6000; gun.speed = 682;
    const int wgun = w.define_weapon(gun);
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 4; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0};
    fact.sprite_h = 3; fact.hp = 150000; fact.armor = ARMOR_WOOD; fact.produces = (1u << QUEUE_BUILDING) | (1u << QUEUE_DEFENSE);
    fact.base_provider = true; fact.provides = {"fact"};
    UnitType gunt;
    gunt.building = true; gunt.defense = true; gunt.foot_w = 1; gunt.foot_h = 1; gunt.footprint = {1}; gunt.sprite_h = 1;
    gunt.hp = 40000; gunt.armor = ARMOR_HEAVY; gunt.cost = 800; gunt.queue_kind = QUEUE_DEFENSE; gunt.weapon = wgun;
    gunt.turreted = true; gunt.turret_turn = 48; gunt.power = -40;
    UnitType fix;
    fix.building = true; fix.foot_w = 3; fix.foot_h = 3; fix.footprint = {0, 0, 0, 0, 0, 0, 0, 0, 0}; fix.sprite_h = 3;
    fix.hp = 80000; fix.armor = ARMOR_WOOD; fix.cost = 1200; fix.queue_kind = QUEUE_BUILDING; fix.repairs_units = true;
    UnitType tank; tank.speed = 72; tank.turn_rate = 20; tank.hp = 46000; tank.armor = ARMOR_HEAVY; tank.cost = 850; tank.repairable = true;
    const int t_fact = w.define_type(fact), t_gun = w.define_type(gunt), t_fix = w.define_type(fix), t_tank = w.define_type(tank);
    w.spawn_building(t_fact, 0, {10, 10});
    w.spawn_building(t_fact, 1, {30, 30});
    w.give_credits(0, 10000);

    CHECK(w.queue_build(0, t_gun));
    CHECK(w.queue_build(0, t_fix));
    for (int t = 0; t < 800; ++t) w.step();
    CHECK(w.queue(0, QUEUE_DEFENSE).front().done && w.queue(0, QUEUE_BUILDING).front().done);
    CHECK(w.place_building(0, t_gun, {14, 10}));
    CHECK(!w.can_place(0, t_fix, {17, 10}, nullptr));
    CHECK(w.place_building(0, t_fix, {10, 15}));
    for (int t = 0; t < 5; ++t) w.step();

    const int32_t tank_id = w.spawn(t_tank, 0, {14, 16});
    const int ti = w.index_of(tank_id);
    const_cast<Actor&>(w.actor(ti)).hp = 46000 - 3000;
    const int32_t fix_id = w.actor(w.actor_count() - 2).id;
    CHECK(w.type(w.actor(w.actor_count() - 2).type).repairs_units);
    const int64_t c0 = w.credits(0);
    w.order_repair(&tank_id, 1, fix_id);
    for (int t = 0; t < 115; ++t) w.step();


    const int fi = w.index_of(fix_id);
    CHECK(w.actor(ti).alive);
    CHECK(w.actor(ti).being_repaired && w.actor(ti).repair_depot == fix_id);
    CHECK(w.actor(ti).pos.x == w.actor(fi).pos.x && w.actor(ti).pos.y == w.actor(fi).pos.y);
    CHECK(w.actor(ti).hp > 46000 - 3000 && w.actor(ti).hp < 46000);
    for (int t = 0; t < 300; ++t) w.step();
    CHECK(w.actor(ti).hp == 46000);
    CHECK(w.credits(0) < c0);
    std::vector<int32_t> notes;
    w.drain_notifications(0, notes);
    CHECK(std::find(notes.begin(), notes.end(), NOTIFY_UNIT_REPAIRED) != notes.end());

    CHECK(w.win_state(0) == WIN_UNDEFINED);
    w.destroy(w.actor(1).id);
    for (int t = 0; t < 30; ++t) w.step();
    CHECK(w.win_state(1) == WIN_LOST && w.win_state(0) == WIN_WON);
    notes.clear();
    w.drain_notifications(0, notes);
    CHECK(std::find(notes.begin(), notes.end(), NOTIFY_WIN) != notes.end());
    std::printf("Verteidigung/Depot/Sieg OK (Reparatur kostete %lld)\n", static_cast<long long>(c0 - w.credits(0)));
}


static void test_deploy_faction() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.sprite_h = 3; fact.hp = 150000; fact.armor = ARMOR_WOOD; fact.produces = 1u << QUEUE_BUILDING;
    fact.base_provider = true; fact.make_ticks = 10;
    fact.provides = {"fact", "structures.allies", "structures.soviet"};
    fact.provides_factions = {"", "allies,england", "soviet,russia"};
    const int t_fact = w.define_type(fact);
    UnitType mcv; mcv.speed = 60; mcv.hp = 60000; mcv.transforms_into = t_fact; mcv.transforms_dx = -1; mcv.transforms_dy = -1;
    const int t_mcv = w.define_type(mcv);
    UnitType tent; tent.building = true; tent.foot_w = 2; tent.foot_h = 2; tent.footprint = {1, 1, 1, 1}; tent.sprite_h = 2;
    tent.hp = 1000; tent.cost = 500; tent.queue_kind = QUEUE_BUILDING; tent.prerequisites = {"structures.allies"};

    tent.prerequisites_hidden = {"structures.allies"};
    const int t_tent = w.define_type(tent);
    w.set_faction(0, "soviet");
    const int32_t id = w.spawn(t_mcv, 0, {10, 10});
    CHECK(w.can_deploy(id));
    w.order_deploy(&id, 1);
    w.step();
    CHECK(!w.actor(0).alive);
    const CPos want{9, 9};
    CHECK((w.actor_count() == 2 && w.actor(1).type == t_fact && w.actor(1).origin == want));
    for (int t = 0; t < 12; ++t) w.step();
    CHECK(w.has_prerequisite(0, "structures.soviet") && !w.has_prerequisite(0, "structures.allies"));
    CHECK(!w.prerequisites_met(0, t_tent));

    CHECK(w.item_hidden(0, t_tent));
    w.set_faction(0, "allies");
    CHECK(w.prerequisites_met(0, t_tent) && !w.item_hidden(0, t_tent));
    w.set_faction(0, "soviet");


    w.set_faction(1, "allies");
    const int32_t allied = w.spawn_building(t_fact, 1, {20, 20});
    for (int t = 0; t < 12; ++t) w.step();
    CHECK(w.item_hidden(0, t_tent));
    CHECK(w.set_owner_id(allied, 0));
    CHECK(w.has_prerequisite(0, "structures.allies") && !w.item_hidden(0, t_tent));
    std::printf("Deploy/Fraktion OK (versteckte Einträge, eroberter Bauhof)\n");
}


static void test_armaments() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    Weapon cannon;
    cannon.range = 5 * CELL; cannon.reload = 90; cannon.damage = 6000; cannon.burst = 1;
    cannon.invalid_targets = TT_AIRBORNE | TT_INFANTRY;
    for (int i = 0; i < NUM_ARMOR; ++i) cannon.versus[i] = 100;
    Weapon tusk;
    tusk.range = 6 * CELL + 512; tusk.reload = 60; tusk.damage = 5000; tusk.burst = 1;
    tusk.valid_targets = TT_AIRBORNE | TT_INFANTRY;
    for (int i = 0; i < NUM_ARMOR; ++i) tusk.versus[i] = 100;
    const int w_cannon = w.define_weapon(cannon), w_tusk = w.define_weapon(tusk);

    UnitType mammoth;
    mammoth.speed = 43; mammoth.turn_rate = 1024; mammoth.hp = 90000; mammoth.armor = ARMOR_HEAVY;
    mammoth.weapon = w_cannon; mammoth.weapon_secondary = w_tusk;
    mammoth.facing_tolerance = 1024; mammoth.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    mammoth.auto_target_mask = TT_INFANTRY | TT_VEHICLE;
    const int t_mammoth = w.define_type(mammoth);
    UnitType foot; foot.speed = 1; foot.turn_rate = 1024; foot.infantry = true; foot.hp = 400000;
    foot.target_types = TT_GROUND_ACTOR | TT_INFANTRY; foot.no_auto_target = true;
    UnitType tank; tank.speed = 1; tank.turn_rate = 1024; tank.hp = 400000; tank.armor = ARMOR_HEAVY;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tank.no_auto_target = true;
    const int t_foot = w.define_type(foot), t_tank = w.define_type(tank);


    w.spawn(t_mammoth, 0, {20, 20});
    w.spawn(t_foot, 1, {23, 20});
    const int32_t foot_hp = w.actor(1).hp;
    for (int t = 0; t < 40; ++t) w.step();
    CHECK(w.actor(1).hp < foot_hp);
    CHECK(w.combat(0).reload2 > 0 && w.combat(0).reload == 0);
    const int32_t on_foot = foot_hp - w.actor(1).hp;


    World w2;
    w2.set_map(40, 40, cost.data());
    const int c2 = w2.define_weapon(cannon), k2 = w2.define_weapon(tusk);
    UnitType m2 = mammoth; m2.weapon = c2; m2.weapon_secondary = k2;
    const int t_m2 = w2.define_type(m2);
    UnitType f2 = foot, k2t = tank;
    (void)w2.define_type(f2);
    const int t_t2 = w2.define_type(k2t);
    w2.spawn(t_m2, 0, {20, 20});
    w2.spawn(t_t2, 1, {23, 20});
    const int32_t tank_hp = w2.actor(1).hp;
    for (int t = 0; t < 40; ++t) w2.step();
    CHECK(w2.actor(1).hp < tank_hp);
    CHECK(w2.combat(0).reload > 0 && w2.combat(0).reload2 == 0);
    std::printf("Mehrfachbewaffnung: Tusk gegen Infanterie %d Schaden, 120mm gegen Panzer %d Schaden\n",
                on_foot, tank_hp - w2.actor(1).hp);
}


struct DogSceneIds {
    int32_t dog_id, man_id;
};
static DogSceneIds build_dog_scene(World& w) {
    static const std::vector<uint8_t> cost(20 * 20, 1);
    w.set_map(20, 20, cost.data());
    w.set_alliance(0, 1, false);
    Weapon dogjaw;
    dogjaw.range = 3 * CELL; dogjaw.reload = 10; dogjaw.damage = 100000; dogjaw.valid_targets = TT_INFANTRY;
    const int w_jaw = w.define_weapon(dogjaw);
    UnitType dog;
    dog.speed = 100; dog.turn_rate = 1024; dog.infantry = true; dog.locomotor = LOCO_FOOT;
    dog.hp = 1800; dog.weapon = w_jaw; dog.facing_tolerance = 1024;
    dog.leap = true; dog.leap_speed = 426; dog.leap_lock_ticks = 20;
    dog.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_dog = w.define_type(dog);
    UnitType rifle;
    rifle.speed = 56; rifle.turn_rate = 1024; rifle.infantry = true; rifle.locomotor = LOCO_FOOT;
    rifle.hp = 5000; rifle.hit_radius = 128; rifle.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    rifle.no_auto_target = true;
    const int t_rifle = w.define_type(rifle);
    const int32_t dog_id = w.spawn(t_dog, 0, {5, 5});
    const int32_t man_id = w.spawn(t_rifle, 1, {7, 5});
    w.order_attack(&dog_id, 1, man_id);
    return {dog_id, man_id};
}

static void test_dog_leap() {
    World w;
    build_dog_scene(w);

    const CPos start_cell = w.mobile(0).cell;
    bool saw_leap = false, cell_unchanged = true, pos_changed = false;
    int leap_ticks_seen = 0;
    for (int t = 0; t < 200 && w.actor(1).alive; ++t) {
        const bool leaping_before = w.combat(0).leap_ticks >= 0;
        const WVec pos_before = w.actor(0).pos;
        w.step();
        if (leaping_before) {
            ++leap_ticks_seen;
            saw_leap = true;
            if (w.actor(0).pos != pos_before) pos_changed = true;


            if (w.combat(0).leap_ticks >= 0 && w.mobile(0).cell != start_cell) cell_unchanged = false;
        }
    }
    CHECK(saw_leap);
    CHECK(leap_ticks_seen >= 1);
    CHECK(pos_changed);
    CHECK(cell_unchanged);
    CHECK(!w.actor(1).alive);
    CHECK(w.combat(0).leap_ticks < 0);
    CHECK(w.combat(0).leap_lock > 0);
    CHECK(cell_dist_sq(w.mobile(0).cell, start_cell) >= 1);
    std::printf("Hundesprung: %d Ticks in der Luft, gelandet auf (%d,%d), Ziel tot\n",
                leap_ticks_seen, w.mobile(0).cell.x, w.mobile(0).cell.y);
}


static void test_dog_leap_miss() {
    World w;
    DogSceneIds ids = build_dog_scene(w);
    while (w.combat(0).leap_ticks < 0) w.step();
    w.destroy(ids.man_id);
    CHECK(!w.actor(1).alive);
    for (int t = 0; t < 20 && w.combat(0).leap_ticks >= 0; ++t) w.step();
    CHECK(w.combat(0).leap_ticks < 0);
    CHECK(w.combat(0).leap_lock > 0);
    std::printf("Hundesprung ins Leere: Ziel starb während des Sprungs, Landung ohne Biss\n");
}


static void test_dog_leap_save_load() {
    World a;
    build_dog_scene(a);
    while (a.combat(0).leap_ticks < 0) a.step();
    a.step();
    CHECK(a.combat(0).leap_ticks > 0);
    const int32_t saved_ticks = a.combat(0).leap_ticks, saved_len = a.combat(0).leap_len;

    std::vector<uint8_t> blob;
    CHECK(a.save(blob));

    World b;
    build_dog_scene(b);
    CHECK(b.load(blob));
    CHECK(b.combat(0).leap_ticks == saved_ticks);
    CHECK(b.combat(0).leap_len == saved_len);
    CHECK(b.actor(0).pos.x == a.actor(0).pos.x && b.actor(0).pos.y == a.actor(0).pos.y);

    for (int t = 0; t < 50 && a.actor(1).alive; ++t) a.step();
    for (int t = 0; t < 50 && b.actor(1).alive; ++t) b.step();
    CHECK(!a.actor(1).alive);
    CHECK(!b.actor(1).alive);
    CHECK(a.mobile(0).cell.x == b.mobile(0).cell.x && a.mobile(0).cell.y == b.mobile(0).cell.y);
    std::printf("Hundesprung Save/Load: mitten im Sprung (Tick %d/%d) gespeichert, beide Welten landen gleich\n",
                saved_ticks, saved_len);
}


static void test_api_bridge() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());
    UnitType silo; silo.building = true; silo.foot_w = 1; silo.foot_h = 1; silo.footprint = {1};
    silo.hp = 30000; silo.storage = 2000;
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 1000;
    const int t_silo = w.define_type(silo), t_tank = w.define_type(tank);
    w.spawn_building(t_silo, 0, {20, 20});


    w.set_resources(0, 500);
    CHECK(w.resources_stored(0) == 500);
    w.set_resources(0, 99999);
    CHECK(w.resources_stored(0) == 2000);
    w.set_resources(0, -5);
    CHECK(w.resources_stored(0) == 0);


    const int32_t a = w.spawn(t_tank, 0, {5, 5});
    CHECK(w.occupant({5, 5}) >= 0);
    CHECK(w.teleport(a, {12, 9}));
    CHECK(w.occupant({5, 5}) == -1);
    const CPos tc = to_cell(w.actor(size_t(w.index_of(a))).pos);
    CHECK(tc.x == 12 && tc.y == 9);


    const int32_t occ = w.spawn(t_tank, 0, {18, 4});
    const int i_occ = w.index_of(occ);
    CHECK(w.occupant({18, 4}) == i_occ);
    CHECK(w.teleport(a, {18, 4}));
    CHECK(w.occupant({18, 4}) == i_occ);
    const CPos ac = w.mobile(size_t(w.index_of(a))).cell;
    CHECK(!(ac.x == 18 && ac.y == 4));
    CHECK(w.occupant(ac) == w.index_of(a));
    CHECK(w.occupant({12, 9}) == -1);


    const int32_t b = w.spawn(t_tank, 1, {14, 9});
    const int ib = w.index_of(b);
    w.damage_for_test(size_t(ib), 100, a);
    CHECK(w.actor(size_t(ib)).last_attacker == a);
    CHECK(w.actor(size_t(ib)).last_attacker_owner == 0);
    w.damage_for_test(size_t(ib), 10000, a);
    CHECK(!w.actor(size_t(ib)).alive);
    CHECK(w.actor(size_t(ib)).last_attacker == a);


    const int32_t c = w.spawn(t_tank, 0, {3, 3});
    const int ic = w.index_of(c);
    CHECK(w.remove_actor(c));
    CHECK(!w.actor(size_t(ic)).alive);
    CHECK(w.actor(size_t(ic)).vanished);
    CHECK(w.occupant({3, 3}) == -1);
    CHECK(!w.remove_actor(c));
    std::printf("Brücke: set_resources/teleport/Verursacher/remove_actor OK\n");
}


static void test_teleport_harvester_claim() {
    World w;
    std::vector<uint8_t> terrain(30 * 30, uint8_t(TER_CLEAR));
    w.set_terrain(30, 30, terrain.data());
    UnitType proc; proc.building = true; proc.foot_w = 2; proc.foot_h = 2; proc.footprint = {1, 1, 1, 1};
    proc.hp = 30000; proc.refinery = true; proc.storage = 5000;
    UnitType harv; harv.speed = 60; harv.turn_rate = 1024; harv.hp = 6000; harv.harvester = true;
    harv.capacity = 20; harv.search_from_proc = 15; harv.search_from_harv = 8;
    const int t_proc = w.define_type(proc), t_harv = w.define_type(harv);
    w.spawn_building(t_proc, 0, {4, 4});
    for (int y = 12; y < 16; ++y)
        for (int x = 12; x < 16; ++x) w.set_resource({x, y}, RES_ORE, 6);
    const int32_t h = w.spawn(t_harv, 0, {8, 8});
    const size_t ih = size_t(w.index_of(h));
    for (int t = 0; t < 300 && w.harvest(ih).claim < 0; ++t) w.step();
    CHECK(w.harvest(ih).claim >= 0);
    CHECK(w.teleport(h, {25, 25}));
    CHECK(w.harvest(ih).claim == -1);
    std::printf("Teleport: Erz-Claim des Harvesters freigegeben\n");
}


static void test_sell_cost() {
    World w;
    std::vector<uint8_t> cost(20 * 20, 1);
    w.set_map(20, 20, cost.data());
    UnitType fact; fact.building = true; fact.foot_w = 2; fact.foot_h = 2; fact.footprint = {1, 1, 1, 1};
    fact.hp = 100000; fact.cost = 2000; fact.sellable = true; fact.queue_kind = -1;
    UnitType hosp; hosp.building = true; hosp.foot_w = 2; hosp.foot_h = 2; hosp.footprint = {1, 1, 1, 1};
    hosp.hp = 40000; hosp.cost = 0; hosp.sellable = false;
    const int t_fact = w.define_type(fact), t_hosp = w.define_type(hosp);
    const int32_t f = w.spawn_building(t_fact, 0, {4, 4});
    const int32_t c = w.spawn_building(t_hosp, 0, {10, 10});
    CHECK(w.sell_value(f) == 1000);
    CHECK(w.sell(f));
    CHECK(!w.sell(c));
    std::printf("Verkauf: Bauhof (Cost 2000, ~disabled) verkäuflich, Zivilgebäude nicht\n");
}


static void test_bridge_terrain() {
    World w;
    std::vector<uint8_t> terrain(20 * 20, uint8_t(TER_CLEAR));
    w.set_terrain(20, 20, terrain.data());
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 1000;
    const int t_tank = w.define_type(tank);
    const int32_t a = w.spawn(t_tank, 0, {10, 10});
    CHECK(w.map().passable({10, 10}));
    w.set_map_terrain({10, 10}, TER_ROCK);
    CHECK(!w.map().passable({10, 10}));
    CHECK(!w.actor(size_t(w.index_of(a))).alive);
    CHECK(w.fields().size() == 0);

    w.set_map_terrain({10, 10}, TER_CLEAR);
    CHECK(w.map().passable({10, 10}));
    std::printf("Brückenterrain: Zelle gesperrt, Einheit darauf gestorben, Zelle wieder frei\n");
}

static void test_capture() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1}; powr.sprite_h = 2;
    powr.hp = 40000; powr.power = 100; powr.capturable = true; powr.provides = {"anypower"};
    UnitType eng; eng.speed = 54; eng.turn_rate = 1024; eng.infantry = true; eng.hp = 2500; eng.captures = true; eng.locomotor = LOCO_FOOT;
    const int tp = w.define_type(powr), te = w.define_type(eng);
    const int32_t bid = w.spawn_building(tp, 1, {10, 10});
    const int32_t eid = w.spawn(te, 0, {4, 10});
    w.order_capture(&eid, 1, bid);
    for (int t = 0; t < 600 && w.actor(0).owner != 0; ++t) w.step();
    CHECK(w.actor(0).owner == 0);
    CHECK(!w.actor(1).alive);
    CHECK(w.power_provided(0) == 100);
    std::printf("Erobern OK\n");
}


static void test_set_owner_health() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.sprite_h = 2; powr.hp = 40000; powr.power = 100; powr.provides = {"anypower"};
    UnitType dog; dog.speed = 71; dog.turn_rate = 1024; dog.infantry = true; dog.hp = 1800; dog.locomotor = LOCO_FOOT;
    const int tp = w.define_type(powr), td = w.define_type(dog);
    const int32_t bid = w.spawn_building(tp, 1, {10, 10});
    const int32_t did = w.spawn(td, 1, {4, 10});
    CHECK(w.power_provided(1) == 100 && w.power_provided(0) == 0);
    CHECK(w.has_prerequisite(1, "anypower") && !w.has_prerequisite(0, "anypower"));

    w.set_primary(bid);
    CHECK(w.set_owner_id(bid, 0));
    CHECK(w.actor(size_t(w.index_of(bid))).owner == 0);
    CHECK(w.power_provided(0) == 100 && w.power_provided(1) == 0);
    CHECK(w.has_prerequisite(0, "anypower") && !w.has_prerequisite(1, "anypower"));
    CHECK(!w.actor(size_t(w.index_of(bid))).primary);

    CHECK(w.set_owner_id(did, 0));
    CHECK(w.actor(size_t(w.index_of(did))).owner == 0);
    CHECK(w.alive_count(0) == 2 && w.alive_count(1) == 0);
    CHECK(!w.set_owner_id(9999, 0));

    CHECK(w.set_health(bid, 8000));
    CHECK(w.actor(size_t(w.index_of(bid))).hp == 8000);
    CHECK(w.set_health(bid, 999999));
    CHECK(w.actor(size_t(w.index_of(bid))).hp == 40000);
    CHECK(w.set_health(did, 0));
    CHECK(!w.actor(size_t(w.index_of(did))).alive);
    std::printf("Eigentümerwechsel und Health-Setter OK\n");
}


static void test_field_generation() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 1000;
    UnitType hut; hut.building = true; hut.foot_w = 2; hut.foot_h = 2; hut.footprint = {1, 1, 1, 1}; hut.hp = 1000;
    const int t_tank = w.define_type(tank), t_hut = w.define_type(hut);
    std::vector<int32_t> ids;
    for (int i = 0; i < 20; ++i) ids.push_back(w.spawn(t_tank, 0, {2 + i % 5, 2 + i / 5}));

    for (int k = 0; k < 20; ++k) {
        w.order_move(&ids[size_t(k)], 1, {30 + k % 5, 30 + k / 5}, 0);
        w.step();
    }
    CHECK(w.fields().size() > 1);
    w.spawn_building(t_hut, 0, {20, 20});
    CHECK(w.fields().size() == 0);
    for (int t = 0; t < 700; ++t) w.step();
    CHECK(w.moving_count() <= 20);
    uint32_t arrived = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        if (!w.actor(i).alive || w.type(w.actor(i).type).building) continue;
        if (w.mobile(i).cell.x >= 25) ++arrived;
    }
    std::printf("Feldgeneration: %u/20 unterwegs Richtung Ziel, %u Felder\n", arrived, uint32_t(w.fields().size()));
    CHECK(arrived >= 15);
}


static void test_crush() {
    auto build = [](int32_t inf_owner) {
        World w;

        std::vector<uint8_t> cost(20 * 20, 0);
        for (int x = 0; x < 20; ++x) cost[5 * 20 + x] = 1;
        w.set_map(20, 20, cost.data());
        UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 10000; tank.crushes = CRUSH_INFANTRY | CRUSH_WALL;
        UnitType inf; inf.speed = 54; inf.turn_rate = 1024; inf.infantry = true; inf.hp = 5000;
        inf.crush_classes = CRUSH_INFANTRY; inf.locomotor = LOCO_FOOT;
        const int t_tank = w.define_type(tank), t_inf = w.define_type(inf);
        const int32_t tid = w.spawn(t_tank, 0, {2, 5});
        w.spawn(t_inf, inf_owner, {6, 5});
        w.order_move(&tid, 1, {12, 5}, 0);
        for (int t = 0; t < 300; ++t) w.step();
        return w;
    };
    World enemy = build(1);
    CHECK(!enemy.actor(1).alive);
    CHECK(enemy.mobile(0).cell.x >= 11);

    CHECK(enemy.actor(1).last_damage_type == DAMAGE_CRUSHED);
    CHECK(enemy.actor(1).last_attacker == enemy.actor(0).id);
    CHECK(enemy.actor(1).last_attacker_owner == 0);
    World friendly = build(0);
    CHECK(friendly.actor(1).alive);
    std::printf("Überfahren: Feind tot, Verbündeter lebt\n");
}


static void test_subcells() {
    World w;
    std::vector<uint8_t> cost(32 * 32, 1);
    w.set_map(32, 32, cost.data());
    UnitType inf; inf.speed = 56; inf.turn_rate = 1024; inf.infantry = true; inf.hp = 5000;
    inf.locomotor = LOCO_FOOT; inf.crush_classes = CRUSH_INFANTRY; inf.hit_radius = 128;
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 10000;
    tank.crushes = CRUSH_INFANTRY; tank.locomotor = LOCO_TRACKED;
    const int t_inf = w.define_type(inf), t_tank = w.define_type(tank);


    std::vector<int32_t> stack;
    for (int k = 0; k < 5; ++k) stack.push_back(w.spawn(t_inf, 0, {4, 4}));
    int in_cell = 0;
    uint32_t used = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        if (w.mobile(i).cell != CPos{4, 4}) continue;
        ++in_cell;
        const int32_t sub = w.mobile(i).sub;
        CHECK(sub >= SUB_FIRST && sub <= NUM_SUBCELLS);
        CHECK((used & (1u << sub)) == 0);
        used |= 1u << sub;

        CHECK(w.actor(i).pos == subcell_center(CPos{4, 4}, sub));
    }
    CHECK(in_cell == 5);

    const int32_t sixth = w.spawn(t_inf, 0, {4, 4});
    CHECK(w.mobile(size_t(w.index_of(sixth))).cell != (CPos{4, 4}));

    w.spawn(t_tank, 0, {10, 10});
    const int32_t blocked = w.spawn(t_inf, 0, {10, 10});
    CHECK(w.mobile(size_t(w.index_of(blocked))).cell != (CPos{10, 10}));


    World m;
    m.set_map(32, 32, cost.data());
    const int m_inf = m.define_type(inf);
    std::vector<int32_t> ids;
    for (int k = 0; k < 6; ++k) ids.push_back(m.spawn(m_inf, 0, {2 + k * 3, 20}));
    for (int32_t id : ids) m.order_move(&id, 1, {16, 20}, 0);
    std::vector<int> slots(32 * 32 * CELL_SLOTS, 0);
    for (int t = 0; t < 1200; ++t) {
        m.step();

        std::fill(slots.begin(), slots.end(), 0);
        for (size_t i = 0; i < m.actor_count(); ++i) {
            if (!m.actor(i).alive) continue;
            const Mobile& mo = m.mobile(i);
            ++slots[size_t(m.map().index(mo.cell)) * CELL_SLOTS + size_t(mo.sub)];
        }
        for (int v : slots) CHECK(v <= 1);
    }
    int arrived = 0, near = 0;
    for (size_t i = 0; i < m.actor_count(); ++i) {
        const CPos c = m.mobile(i).cell;
        if (c == CPos{16, 20}) ++arrived;
        else if (std::abs(c.x - 16) <= 2 && std::abs(c.y - 20) <= 2) ++near;
    }
    std::printf("Subzellen: %d von 6 Fußtruppen in der Zielzelle, %d daneben\n", arrived, near);
    CHECK(arrived == 5);
    CHECK(near == 1);


    World c;
    std::vector<uint8_t> lane(20 * 20, 0);
    for (int x = 0; x < 20; ++x) lane[size_t(5 * 20 + x)] = 1;
    c.set_map(20, 20, lane.data());
    const int c_inf = c.define_type(inf), c_tank = c.define_type(tank);
    for (int k = 0; k < 5; ++k) c.spawn(c_inf, 1, {8, 5});
    const int32_t tid = c.spawn(c_tank, 0, {2, 5});
    c.order_move(&tid, 1, {15, 5}, 0);
    for (int t = 0; t < 400; ++t) c.step();
    int dead = 0;
    for (size_t i = 0; i < c.actor_count(); ++i)
        if (c.actor(i).type == c_inf && !c.actor(i).alive && c.actor(i).last_damage_type == DAMAGE_CRUSHED) ++dead;
    std::printf("Subzellen: Panzer überfährt %d von 5 Fußtruppen, steht bei x=%d\n",
                dead, c.mobile(size_t(c.index_of(tid))).cell.x);
    CHECK(dead == 5);
    CHECK(c.mobile(size_t(c.index_of(tid))).cell.x >= 14);
}


static void test_cash_trickler() {
    World w;
    std::vector<uint8_t> cost(20 * 20, 1);
    w.set_map(20, 20, cost.data());
    UnitType oilb;
    oilb.building = true; oilb.foot_w = 2; oilb.foot_h = 2; oilb.footprint = {1, 1, 1, 1};
    oilb.hp = 40000; oilb.cash_interval = 375; oilb.cash_amount = 100;
    const int t_oilb = w.define_type(oilb);
    w.spawn_building(t_oilb, 0, {5, 5});
    const int64_t start = w.credits(0);
    for (int t = 0; t < 375; ++t) w.step();
    CHECK(w.credits(0) == start + 100);
    for (int t = 0; t < 375; ++t) w.step();
    CHECK(w.credits(0) == start + 200);


    std::vector<CashTick> ticks;
    w.drain_cash_ticks(ticks);
    CHECK(ticks.size() == 2);
    CHECK(ticks[0].owner == 0 && ticks[0].amount == 100);
    CHECK(ticks[0].pos.x > 5 * CELL && ticks[0].pos.y > 5 * CELL);
    w.drain_cash_ticks(ticks);
    CHECK(ticks.empty());

    CHECK(w.set_owner_id(w.actor(0).id, 1));
    const int64_t foe = w.credits(1);
    for (int t = 0; t < 375; ++t) w.step();
    w.drain_cash_ticks(ticks);
    CHECK(w.credits(1) == foe + 100);
    CHECK(ticks.size() == 1 && ticks[0].owner == 1);
    std::printf("CashTrickler OK (+%lld, Ereignis %d Credits an Spieler %d)\n",
                static_cast<long long>(w.credits(0) - start), ticks[0].amount, ticks[0].owner);
}


static void test_support_powers() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());
    Weapon nuke; nuke.damage = 5000; nuke.spread = 1024; nuke.range = 0;
    for (int i = 0; i < NUM_ARMOR; ++i) nuke.versus[i] = 100;
    const int w_nuke = w.define_weapon(nuke);
    UnitType iron; iron.building = true; iron.foot_w = 2; iron.foot_h = 2; iron.footprint = {1, 1, 1, 1}; iron.hp = 40000;
    iron.support_power = SP_IRON_CURTAIN; iron.sp_charge = 20; iron.sp_duration = 50; iron.sp_dim_w = 3; iron.sp_dim_h = 3;
    iron.sp_footprint = {0, 1, 0, 1, 1, 1, 0, 1, 0}; iron.sp_notify_ready = NOTIFY_IRON_READY;
    UnitType pdox = iron; pdox.support_power = SP_CHRONOSHIFT; pdox.sp_duration = 30; pdox.sp_notify_ready = NOTIFY_CHRONO_READY;
    UnitType mslo = iron; mslo.support_power = SP_NUKE; mslo.sp_weapon = w_nuke; mslo.sp_flight = 40; mslo.sp_notify_ready = -1;
    const int t_iron = w.define_type(iron), t_pdox = w.define_type(pdox), t_mslo = w.define_type(mslo);
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 10000;
    const int t_tank = w.define_type(tank);
    w.spawn_building(t_iron, 0, {2, 2});
    w.spawn_building(t_pdox, 0, {2, 6});
    w.spawn_building(t_mslo, 0, {2, 10});
    const int32_t my_tank = w.spawn(t_tank, 0, {15, 15});
    const size_t ti = w.actor_count() - 1;
    int av, rd, pm, ps;
    w.support_power_state(0, SP_IRON_CURTAIN, av, rd, pm, ps);
    CHECK(av == 1 && rd == 0);
    CHECK(!w.activate_support_power(0, SP_IRON_CURTAIN, {15, 15}, {0, 0}));
    for (int t = 0; t < 21; ++t) w.step();
    w.support_power_state(0, SP_IRON_CURTAIN, av, rd, pm, ps);
    CHECK(rd == 1 && pm == 1000);
    std::vector<int32_t> notes; w.drain_notifications(0, notes);
    bool ready_said = false; for (int n : notes) if (n == NOTIFY_IRON_READY) ready_said = true;
    CHECK(ready_said);

    CHECK(w.activate_support_power(0, SP_IRON_CURTAIN, {15, 15}, {0, 0}));
    w.support_power_state(0, SP_IRON_CURTAIN, av, rd, pm, ps);
    CHECK(rd == 0 && pm == 0);
    w.damage_for_test(ti, 3000, -1);
    CHECK(w.actor(ti).hp == 10000);
    for (int t = 0; t < 51; ++t) w.step();
    w.damage_for_test(ti, 3000, -1);
    CHECK(w.actor(ti).hp == 7000);

    CHECK(w.activate_support_power(0, SP_CHRONOSHIFT, {15, 15}, {20, 20}));
    CHECK(w.actor(ti).pos.x / CELL == 20 && w.actor(ti).pos.y / CELL == 20);
    for (int t = 0; t < 31; ++t) w.step();
    CHECK(w.actor(ti).pos.x / CELL == 15 && w.actor(ti).pos.y / CELL == 15);

    w.set_alliance(0, 1, false);
    w.spawn(t_tank, 1, {25, 25});
    const size_t ei = w.actor_count() - 1;
    CHECK(w.activate_support_power(0, SP_NUKE, {25, 25}, {0, 0}));
    for (int t = 0; t < 39; ++t) w.step();
    CHECK(w.actor(ei).hp == 10000);
    w.step();
    CHECK(w.actor(ei).hp < 10000);
    (void)my_tank;
    std::printf("Superwaffen OK (Gegner nach Atomschlag %d HP)\n", w.actor(ei).hp);
}


static Weapon make_atomic_weapon() {
    Weapon w;
    w.range = 40 * CELL;
    w.reload = 1;
    w.damage = 15000;
    w.spread = 1 * CELL;
    const int32_t fo[7] = {1000, 368, 135, 50, 18, 7, 0};
    w.falloff_steps = 7;
    for (int i = 0; i < 7; ++i) w.falloff[i] = fo[i];
    w.valid_targets = TT_GROUND_ACTOR | TT_INFANTRY | TT_STRUCTURE;
    for (int i = 0; i < NUM_ARMOR; ++i) w.versus[i] = 100;
    w.versus[ARMOR_WOOD] = 25;
    w.versus[ARMOR_CONCRETE] = 25;

    auto ring = [&](int idx, int32_t spread_cells, int32_t delay, int32_t wood_versus) {
        ExtraWarhead& e = w.extra_warheads[idx];
        e.delay = delay;
        e.spread = spread_cells * CELL;
        e.damage = 6000;
        e.falloff_steps = 7;
        for (int i = 0; i < 7; ++i) e.falloff[i] = fo[i];
        for (int i = 0; i < NUM_ARMOR; ++i) e.versus[i] = 100;
        e.versus[ARMOR_WOOD] = wood_versus;
        e.versus[ARMOR_CONCRETE] = 25;
        e.valid_targets = TT_GROUND_ACTOR | TT_INFANTRY | TT_STRUCTURE;
    };
    ring(0, 2, 5, 25);
    ring(1, 3, 10, 50);
    ring(2, 4, 15, 100);
    ring(3, 5, 20, 100);
    w.extra_warhead_count = 4;

    w.destroy_resource_count = 5;
    const int32_t sizes[5] = {1, 2, 3, 4, 5};
    const int32_t delays[5] = {0, 5, 10, 15, 20};
    for (int i = 0; i < 5; ++i) { w.destroy_resource[i].size = sizes[i]; w.destroy_resource[i].delay = delays[i]; }
    return w;
}

static void test_nuke_warhead_chain() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    const int w_nuke = w.define_weapon(make_atomic_weapon());

    UnitType bauhof;
    bauhof.building = true; bauhof.foot_w = 1; bauhof.foot_h = 1; bauhof.footprint = {1};
    bauhof.hp = 150000; bauhof.armor = ARMOR_WOOD; bauhof.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_bauhof = w.define_type(bauhof);
    UnitType soldier;
    soldier.speed = 54; soldier.turn_rate = 1024; soldier.infantry = true; soldier.hp = 5000;
    soldier.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_soldier = w.define_type(soldier);
    UnitType launcher;
    launcher.speed = 1; launcher.turn_rate = 1024; launcher.hp = 100000; launcher.weapon = w_nuke;
    launcher.facing_tolerance = 1024; launcher.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_launcher = w.define_type(launcher);

    const CPos ground_zero{20, 20};
    const int32_t bauhof_id = w.spawn_building(t_bauhof, 1, ground_zero);

    std::vector<int32_t> troop;
    troop.push_back(w.spawn(t_soldier, 1, {20, 17}));
    troop.push_back(w.spawn(t_soldier, 1, {23, 20}));
    troop.push_back(w.spawn(t_soldier, 1, {20, 23}));
    troop.push_back(w.spawn(t_soldier, 1, {17, 20}));


    w.set_resource(ground_zero, RES_ORE, 8);
    w.set_resource({25, 20}, RES_ORE, 8);

    const int32_t launcher_id = w.spawn(t_launcher, 0, {5, 20});
    w.order_attack_cell(&launcher_id, 1, ground_zero);

    for (int t = 0; t < 3; ++t) w.step();
    CHECK(w.resource_type(ground_zero) == RES_NONE);
    CHECK(w.resource_type({25, 20}) != RES_NONE);

    for (int t = 0; t < 40; ++t) w.step();
    CHECK(!w.actor(size_t(w.index_of(bauhof_id))).alive);
    for (const int32_t id : troop) CHECK(!w.actor(size_t(w.index_of(id))).alive);
    CHECK(w.resource_type({25, 20}) == RES_NONE);

    std::printf("Atombombe: Bauhof zerstört %d, Infanterie im 3-Zellen-Radius tot %d/%d, Erz beseitigt\n",
                int(!w.actor(size_t(w.index_of(bauhof_id))).alive), int(troop.size()), int(troop.size()));
}


static uint64_t nuke_hash(const World& w, const std::vector<int32_t>& ids, CPos ground_zero, CPos far_ore) {
    uint64_t h = 1469598103934665603ull;
    auto mix = [&h](int64_t v) { for (int b = 0; b < 8; ++b) { h ^= uint64_t((v >> (8 * b)) & 0xFF); h *= 1099511628211ull; } };
    mix(w.tick());
    for (int32_t id : ids) {
        const int i = w.index_of(id);
        mix(i < 0 ? -1 : (w.actor(size_t(i)).alive ? 1 : 0));
        mix(i < 0 ? -1 : w.actor(size_t(i)).hp);
    }
    mix(w.resource_type(ground_zero));
    mix(w.resource_type(far_ore));
    return h;
}

static void test_save_nuke_chain() {
    World a;
    std::vector<uint8_t> cost(40 * 40, 1);
    a.set_map(40, 40, cost.data());
    const int w_nuke = a.define_weapon(make_atomic_weapon());
    UnitType bauhof;
    bauhof.building = true; bauhof.foot_w = 1; bauhof.foot_h = 1; bauhof.footprint = {1};
    bauhof.hp = 150000; bauhof.armor = ARMOR_WOOD; bauhof.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_bauhof = a.define_type(bauhof);
    UnitType launcher;
    launcher.speed = 1; launcher.turn_rate = 1024; launcher.hp = 100000; launcher.weapon = w_nuke;
    launcher.facing_tolerance = 1024; launcher.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_launcher = a.define_type(launcher);

    const CPos ground_zero{20, 20};
    const CPos far_ore{25, 20};
    const int32_t bauhof_id = a.spawn_building(t_bauhof, 1, ground_zero);
    a.set_resource(ground_zero, RES_ORE, 8);
    a.set_resource(far_ore, RES_ORE, 8);
    const int32_t launcher_id = a.spawn(t_launcher, 0, {5, 20});
    a.order_attack_cell(&launcher_id, 1, ground_zero);

    std::vector<int32_t> ids = {bauhof_id};
    for (int t = 0; t < 12; ++t) a.step();

    std::vector<uint8_t> blob;
    CHECK(a.save(blob));
    const uint64_t before = nuke_hash(a, ids, ground_zero, far_ore);

    World b;
    b.set_map(40, 40, cost.data());
    b.define_weapon(make_atomic_weapon());
    b.define_type(bauhof);
    b.define_type(launcher);
    for (int t = 0; t < 7; ++t) b.step();
    CHECK(b.load(blob));
    CHECK(nuke_hash(b, ids, ground_zero, far_ore) == before);

    for (int t = 0; t < 30; ++t) { a.step(); b.step(); }
    const uint64_t ha = nuke_hash(a, ids, ground_zero, far_ore), hb = nuke_hash(b, ids, ground_zero, far_ore);
    std::printf("Spielstand mit laufender Atombomben-Kette: %zu Bytes, Hash nach 30 weiteren Ticks %016llx %s\n",
                blob.size(), static_cast<unsigned long long>(ha), ha == hb ? "identisch" : "ABWEICHUNG");
    CHECK(ha == hb);
    CHECK(!a.actor(size_t(a.index_of(bauhof_id))).alive);
}


static void test_damage_sounds() {
    World w;
    std::vector<uint8_t> cost(10 * 10, 1);
    w.set_map(10, 10, cost.data());
    UnitType b; b.building = true; b.foot_w = 1; b.foot_h = 1; b.footprint = {1}; b.hp = 1000;
    b.damaged_sound = 41; b.destroyed_sound = 42;
    const int t_b = w.define_type(b);
    w.spawn_building(t_b, 0, {3, 3});
    const size_t bi = w.actor_count() - 1;
    std::vector<SoundEvent> ev;
    w.drain_sounds(ev);
    ev.clear();
    w.damage_for_test(bi, 300, -1); w.drain_sounds(ev);
    CHECK(ev.empty());
    w.damage_for_test(bi, 300, -1); w.drain_sounds(ev);
    CHECK(ev.size() == 1 && ev[0].sound == 41);
    ev.clear();
    w.damage_for_test(bi, 100, -1); w.drain_sounds(ev);
    CHECK(ev.empty());
    w.damage_for_test(bi, 1000, -1); w.drain_sounds(ev);
    bool destroyed = false;
    for (const SoundEvent& e : ev) if (e.sound == 42) destroyed = true;
    CHECK(destroyed);
    std::printf("Schadens-Sounds OK\n");
}


static void test_mines_and_cloak() {
    World w;
    std::vector<uint8_t> cost(20 * 20, 0);
    for (int y = 0; y < 20; ++y) cost[size_t(y * 20 + 5)] = 1;
    w.set_map(20, 20, cost.data());
    w.set_alliance(0, 1, false);
    UnitType mine; mine.mine = true; mine.crush_classes = CRUSH_MINE; mine.hp = 5000; mine.targetable = false;
    mine.cloak = true; mine.cloak_initial_delay = 0; mine.cloak_types = DETECT_MINE;
    const int t_mine = w.define_type(mine);
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 46000; tank.crushes = CRUSH_MINE | CRUSH_CRATE;
    const int t_tank = w.define_type(tank);
    UnitType layer = tank; layer.mine_immune = true; layer.ammo_max = 5; layer.minelayer_mine = t_mine;
    layer.detect_range = 5 * CELL; layer.detect_types = DETECT_MINE;
    const int t_layer = w.define_type(layer);


    const int32_t ml = w.spawn(t_layer, 0, {5, 5});
    CHECK(w.can_lay_mine(ml));
    w.order_lay_mine(&ml, 1);
    w.step();
    CHECK(w.actor_count() == 1);
    w.order_move(&ml, 1, {5, 9});
    for (int t = 0; t < 60; ++t) w.step();
    CHECK(w.actor_count() == 2);
    const Actor& m = w.actor(1);
    CHECK(m.alive && m.type == t_mine && m.owner == 0);

    CHECK(!w.actor_visible_to(1, 1));
    CHECK(w.actor_visible_to(0, 1));

    w.order_move(&ml, 1, {5, 5});
    for (int t = 0; t < 80; ++t) w.step();
    CHECK(w.actor(1).alive);
    w.order_move(&ml, 1, {5, 12});
    for (int t = 0; t < 100; ++t) w.step();

    const int32_t enemy = w.spawn(t_tank, 1, {5, 1});
    w.order_move(&enemy, 1, {5, 8});
    for (int t = 0; t < 150; ++t) w.step();
    CHECK(!w.actor(1).alive);
    std::printf("Minen/Tarnung OK\n");
}

static void test_crates() {
    auto make = [](World& w, int32_t& t_crate, int32_t& t_tank, int32_t& t_inf, int cash_shares, int unit_shares) {
        UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 10000;
        tank.crushes = CRUSH_CRATE | CRUSH_INFANTRY; tank.cost = 800;
        UnitType inf; inf.speed = 56; inf.turn_rate = 1024; inf.infantry = true; inf.hp = 5000;
        inf.locomotor = LOCO_FOOT; inf.crushes = CRUSH_CRATE; inf.crush_classes = CRUSH_INFANTRY; inf.cost = 100;
        t_tank = w.define_type(tank);
        t_inf = w.define_type(inf);
        UnitType crate; crate.crate = true; crate.crate_duration = 0; crate.targetable = false;
        crate.crush_classes = CRUSH_CRATE; crate.hp = 1;
        CrateAction cash; cash.kind = CRATE_CASH; cash.shares = cash_shares; cash.amount = 1000;
        CrateAction give; give.kind = CRATE_UNIT; give.shares = unit_shares; give.units = {t_inf};
        crate.crate_actions = {cash, give};
        t_crate = w.define_type(crate);
    };


    {
        World w;
        std::vector<uint8_t> cost(20 * 20, 0);
        for (int x = 0; x < 20; ++x) cost[size_t(5 * 20 + x)] = 1;
        w.set_map(20, 20, cost.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 100, 0);
        w.spawn(tc, 1, {8, 5});
        const int32_t tid = w.spawn(tt, 0, {2, 5});
        w.order_move(&tid, 1, {15, 5}, 0);
        const int64_t before = w.credits(0);
        for (int t = 0; t < 400; ++t) w.step();
        CHECK(w.crate_count() == 0);
        CHECK(w.credits(0) == before + 1000);
    }

    {
        World w;
        std::vector<uint8_t> cost(20 * 20, 0);
        for (int x = 0; x < 20; ++x) cost[size_t(5 * 20 + x)] = 1;
        w.set_map(20, 20, cost.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 0, 100);
        w.spawn(tc, 1, {8, 5});
        const int32_t tid = w.spawn(tt, 0, {2, 5});
        w.order_move(&tid, 1, {15, 5}, 0);
        for (int t = 0; t < 400; ++t) w.step();
        int given = 0;
        for (size_t i = 0; i < w.actor_count(); ++i)
            if (w.actor(i).alive && w.actor(i).type == ti && w.actor(i).owner == 0) ++given;
        CHECK(w.crate_count() == 0);
        CHECK(given == 1);
    }

    {
        World w;
        std::vector<uint8_t> cost(20 * 20, 1);
        w.set_map(20, 20, cost.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 100, 0);
        const int32_t cid = w.spawn(tc, 1, {8, 5});
        const int ci = w.index_of(cid);
        const_cast<Actor&>(w.actor(size_t(ci))).life_ticks = 30;
        for (int t = 0; t < 29; ++t) w.step();
        CHECK(w.crate_count() == 1);
        for (int t = 0; t < 3; ++t) w.step();
        CHECK(w.crate_count() == 0);
    }

    {
        World w;
        std::vector<uint8_t> cost(20 * 20, 1);
        w.set_map(20, 20, cost.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 100, 0);
        CrateSpawnerParams p;
        p.enabled = true; p.crate_type = tc; p.minimum = 1; p.maximum = 3;
        p.spawn_interval = 20; p.initial_delay = 10;
        w.set_crate_spawner(p);
        for (int t = 0; t < 9; ++t) w.step();
        CHECK(w.crate_count() == 0);
        for (int t = 0; t < 5; ++t) w.step();

        CHECK(w.crate_count() == 2);
        for (int t = 0; t < 400; ++t) w.step();
        std::printf("Kisten: Spawner hält %u Kisten (Maximum 3)\n", w.crate_count());
        CHECK(w.crate_count() == 3);
    }

    {
        World w;
        std::vector<uint8_t> cost(20 * 20, 0);
        for (int x = 0; x < 20; ++x) cost[size_t(5 * 20 + x)] = 1;
        w.set_map(20, 20, cost.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 100, 0);
        w.spawn(tc, 1, {8, 5});
        const int32_t iid = w.spawn(ti, 0, {2, 5});
        w.order_move(&iid, 1, {15, 5}, 0);
        const int64_t before = w.credits(0);
        for (int t = 0; t < 600; ++t) w.step();
        CHECK(w.crate_count() == 0);
        CHECK(w.credits(0) == before + 1000);
        std::printf("Kisten: Fußtruppe sammelt ein (%lld Credits)\n", static_cast<long long>(w.credits(0) - before));
    }
}


static void test_veterancy() {
    auto vet_type = [](UnitType& t) {
        t.xp_levels = 4;
        t.xp_required[0] = 200; t.xp_required[1] = 400; t.xp_required[2] = 800; t.xp_required[3] = 1600;
        t.ranks[0] = {105, 95, 105, 95};
        t.ranks[1] = {110, 90, 110, 90};
        t.ranks[2] = {120, 85, 120, 85};
        t.ranks[3] = {130, 75, 140, 75};
        t.elite_heal_percent = 5; t.elite_heal_delay = 100;
        t.elite_heal_start_below = 100; t.elite_heal_cooldown = 125;
    };
    World w;
    std::vector<uint8_t> cost(32 * 32, 1);
    w.set_map(32, 32, cost.data());
    Weapon gun; gun.range = 4 * CELL; gun.reload = 40; gun.damage = 1000; gun.spread = 128; gun.speed = 0;
    const int wgun = w.define_weapon(gun);
    UnitType sold; sold.speed = 56; sold.turn_rate = 1024; sold.infantry = true; sold.hp = 20000;
    sold.cost = 100; sold.weapon = wgun; sold.hit_radius = 128; sold.locomotor = LOCO_FOOT;
    vet_type(sold);
    UnitType dummy; dummy.speed = 0; dummy.turn_rate = 1024; dummy.hp = 1; dummy.cost = 100; dummy.hit_radius = 128;
    const int t_sold = w.define_type(sold);
    const int t_dummy = w.define_type(dummy);


    const int32_t hero = w.spawn(t_sold, 0, {5, 5});
    const size_t hi = size_t(w.index_of(hero));
    CHECK(w.level_of(hi) == 0);
    for (int k = 0; k < 2; ++k) {
        const int32_t v = w.spawn(t_dummy, 1, {6 + k, 5});
        const int vi = w.index_of(v);
        w.damage_for_test(size_t(vi), 5, hero);
        CHECK(!w.actor(size_t(vi)).alive);
    }
    CHECK(w.level_of(hi) == 1);
    CHECK(w.experience_of(hi) == 2 * 100 * 100);

    w.give_levels(hi, 3);
    CHECK(w.level_of(hi) == 4);

    w.give_experience(hi, 10 * 1000 * 1000);
    CHECK(w.experience_of(hi) == 1600 * 100);


    const_cast<Actor&>(w.actor(hi)).hp = 5000;
    for (int t = 0; t < 130; ++t) w.step();
    const int32_t healed = w.actor(hi).hp;
    for (int t = 0; t < 300; ++t) w.step();
    std::printf("Ränge: Elite heilt von 5000 auf %d HP (max 20000)\n", w.actor(hi).hp);
    CHECK(w.actor(hi).hp > healed);
    CHECK(w.actor(hi).hp <= 20000);


    {
        std::vector<RenderActor> ra(w.actor_count());
        w.render(1024, ra.data());
        CHECK(ra[hi].rank == 4);
    }


    auto shot_damage = [&](int level) {
        World x;
        std::vector<uint8_t> c2(32 * 32, 1);
        x.set_map(32, 32, c2.data());
        const int xw = x.define_weapon(gun);
        UnitType s2 = sold; s2.weapon = xw;
        UnitType d2 = dummy; d2.hp = 1000000;
        const int ts = x.define_type(s2), td = x.define_type(d2);
        const int32_t a = x.spawn(ts, 0, {5, 5});
        const int32_t d = x.spawn(td, 1, {7, 5});
        if (level > 0) x.give_levels(size_t(x.index_of(a)), level);
        const int di = x.index_of(d);
        const int32_t hp0 = x.actor(size_t(di)).hp;
        for (int t = 0; t < 60; ++t) x.step();
        return hp0 - x.actor(size_t(di)).hp;
    };
    const int32_t d0 = shot_damage(0), d4 = shot_damage(4);
    std::printf("Ränge: Schaden Rekrut %d, Elite %d (Firepower 130 %%, Schadensnahme 75 %%)\n", d0, d4);
    CHECK(d0 > 0);
    CHECK(d4 > d0);


    World s;
    s.set_map(32, 32, cost.data());
    UnitType runner = sold;
    runner.weapon = -1;
    const int st = s.define_type(runner);
    const int32_t rookie = s.spawn(st, 0, {2, 2});
    const int32_t elite = s.spawn(st, 0, {2, 20});
    s.give_levels(size_t(s.index_of(elite)), 4);
    s.order_move(&rookie, 1, {28, 2}, 0);
    s.order_move(&elite, 1, {28, 20}, 0);
    for (int t = 0; t < 200; ++t) s.step();
    const int32_t rx = s.mobile(size_t(s.index_of(rookie))).cell.x;
    const int32_t ex = s.mobile(size_t(s.index_of(elite))).cell.x;
    std::printf("Ränge: Rekrut bei x=%d, Elite bei x=%d nach 200 Ticks\n", rx, ex);
    CHECK(ex > rx);
}


static void test_unconditional_healing() {
    World w;
    std::vector<uint8_t> cost(32 * 32, 1);
    w.set_map(32, 32, cost.data());


    Weapon gun;
    gun.range = 4 * CELL; gun.reload = 100000; gun.damage = 1000; gun.spread = 128; gun.speed = 0;
    const int wgun = w.define_weapon(gun);
    UnitType tank;
    tank.speed = 0; tank.turn_rate = 1024; tank.hp = 90000; tank.cost = 2000; tank.armor = ARMOR_HEAVY;
    tank.hit_radius = 400;
    tank.heal_step = 100; tank.heal_delay = 3; tank.heal_start_below = 50; tank.heal_damage_cooldown = 150;
    UnitType gunner;
    gunner.speed = 0; gunner.turn_rate = 1024; gunner.hp = 1; gunner.cost = 100; gunner.hit_radius = 128;
    gunner.weapon = wgun;
    const int t_tank = w.define_type(tank);
    const int t_gunner = w.define_type(gunner);
    const int32_t tank_id = w.spawn(t_tank, 0, {10, 10});
    const int32_t gun_id = w.spawn(t_gunner, 1, {12, 10});
    const size_t ti = size_t(w.index_of(tank_id));
    const size_t gi = size_t(w.index_of(gun_id));


    for (int t = 0; t < 30; ++t) w.step();
    CHECK(w.actor(ti).hp == 89000);
    CHECK(w.actor(ti).self_heal_cooldown > 0);
    for (int t = 0; t < 100; ++t) w.step();
    CHECK(w.actor(ti).self_heal_cooldown > 0);
    CHECK(w.actor(ti).hp == 89000);


    w.set_health(tank_id, 27000);
    const int32_t cd = w.actor(ti).self_heal_cooldown;
    CHECK(cd > 0 && cd <= 150);
    for (int t = 0; t < cd - 1; ++t) w.step();
    CHECK(w.actor(ti).hp == 27000);
    for (int t = 0; t < 800; ++t) w.step();
    std::printf("Selbstheilung (4TNK-Regeln): 27000 -> %d HP (Grenze 45000, Delay 3, Step 100)\n", w.actor(ti).hp);
    CHECK(w.actor(ti).hp == 45000);
    for (int t = 0; t < 100; ++t) w.step();
    CHECK(w.actor(ti).hp == 45000);


    Combat& gc = const_cast<Combat&>(w.combat(gi));
    gc.reload = 0; gc.burst_left = 0; gc.since_shot = 0;
    w.step();
    CHECK(w.actor(ti).hp == 44000);
    CHECK(w.actor(ti).self_heal_cooldown > 100);
    for (int t = 0; t < 50; ++t) w.step();
    CHECK(w.actor(ti).hp == 44000);


    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    World w2;
    w2.set_map(32, 32, cost.data());
    w2.define_weapon(gun);
    w2.define_type(tank);
    w2.define_type(gunner);
    CHECK(w2.load(blob));
    CHECK(w2.actor(ti).hp == w.actor(ti).hp);
    CHECK(w2.actor(ti).self_heal_cooldown == w.actor(ti).self_heal_cooldown);
    CHECK(w2.actor(ti).self_heal_ticks == w.actor(ti).self_heal_ticks);
    for (int t = 0; t < 200; ++t) { w.step(); w2.step(); }
    CHECK(w2.actor(ti).hp == w.actor(ti).hp);
}


static void test_tesla() {
    World w;
    std::vector<uint8_t> cost(20 * 20, 1);
    w.set_map(20, 20, cost.data());
    EffectSeq lit; lit.first_frame = 200; lit.length = 4; lit.ticks_per_frame = 1;
    const int fx_bright = w.define_effect(lit);
    lit.first_frame = 204;
    const int fx_dim = w.define_effect(lit);
    Weapon zap;
    zap.range = 7 * CELL; zap.reload = 3; zap.damage = 10000; zap.spread = 42; zap.speed = 0;
    for (int i = 0; i < NUM_ARMOR; ++i) zap.versus[i] = 100;
    zap.zap_duration = 2; zap.zap_bright = fx_bright; zap.zap_dim = fx_dim;
    const int w_zap = w.define_weapon(zap);
    UnitType tsla; tsla.building = true; tsla.foot_w = 1; tsla.foot_h = 1; tsla.footprint = {1};
    tsla.hp = 40000; tsla.weapon = w_zap; tsla.facing_tolerance = 1024;
    tsla.max_charges = 3; tsla.charge_reload = 120; tsla.initial_charge_delay = 22; tsla.charge_delay = 3;
    tsla.charge_sound = 77;
    UnitType target; target.speed = 1; target.turn_rate = 1024; target.hp = 1000000;
    const int t_tsla = w.define_type(tsla), t_target = w.define_type(target);
    w.spawn_building(t_tsla, 0, {5, 5});
    w.spawn(t_target, 1, {9, 5});
    const int32_t hp0 = w.actor(1).hp;
    std::vector<SoundEvent> snd;
    bool charge_played = false;
    int32_t charging_frames = 0;
    for (int t = 0; t < 20; ++t) {
        w.step();
        w.drain_sounds(snd);
        for (const SoundEvent& e : snd) if (e.sound == 77) charge_played = true;
        if (w.actor(0).active_ticks > 0) ++charging_frames;
    }
    CHECK(w.actor(1).hp == hp0);
    CHECK(charge_played);
    std::printf("Tesla: Ladeanimation läuft %d von 20 Ticks, Ladeton gespielt\n", charging_frames);
    CHECK(charging_frames >= 15);
    for (int t = 0; t < 25; ++t) w.step();
    const int32_t after_burst = (hp0 - w.actor(1).hp) / 10000;
    CHECK(after_burst == 3);
    for (int t = 0; t < 100; ++t) w.step();
    CHECK((hp0 - w.actor(1).hp) / 10000 == 3);
    for (int t = 0; t < 60; ++t) w.step();
    const int32_t total = (hp0 - w.actor(1).hp) / 10000;
    std::printf("Tesla: %d Zaps nach 205 Ticks (OpenRA: 3 je ~145 Ticks)\n", total);
    CHECK(total >= 4 && total <= 6);

    size_t seen = 0;
    for (int t = 0; t < 200 && seen == 0; ++t) {
        w.step();
        seen = w.zaps().size();
    }
    CHECK(seen > 0);
    const WVec from = w.zaps().front().from, to = w.zaps().front().to;
    CHECK(from.x != to.x || from.y != to.y);
    w.step(); w.step();
    std::printf("Tesla-Blitz: %zu Blitz(e) von (%d,%d) nach (%d,%d), nach 2 Ticks %zu\n",
                seen, from.x, from.y, to.x, to.y, w.zaps().size());
    CHECK(w.zaps().empty());
}


static void test_weapon_rules() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());

    Weapon scud;
    scud.range = 10 * CELL; scud.min_range = 4 * CELL; scud.reload = 215; scud.damage = 4500; scud.spread = 341;
    const int32_t fo[7] = {1000, 368, 135, 50, 18, 7, 0};
    scud.falloff_steps = 7;
    for (int i = 0; i < 7; ++i) scud.falloff[i] = fo[i];
    scud.valid_targets = TT_GROUND_ACTOR;
    scud.trigger_prone = true;
    scud.prone_damage = 50;
    for (int i = 0; i < NUM_ARMOR; ++i) scud.versus[i] = 100;
    const int w_scud = w.define_weapon(scud);
    UnitType soldier; soldier.speed = 54; soldier.turn_rate = 1024; soldier.infantry = true; soldier.hp = 500000;
    soldier.target_types = TT_GROUND_ACTOR | TT_INFANTRY; soldier.takes_cover = true; soldier.prone_duration = 50;
    UnitType tree; tree.hp = 50000; tree.target_types = TT_TREES; tree.armor = ARMOR_TREE;
    const int t_soldier = w.define_type(soldier), t_tree = w.define_type(tree);
    const int32_t sid = w.spawn(t_soldier, 1, {20, 20});
    const int32_t tid = w.spawn(t_tree, 2, {20, 21});
    (void)sid; (void)tid;
    const int32_t hp0 = w.actor(0).hp, tree0 = w.actor(1).hp;
    w.destroy(-1);


    UnitType launcher; launcher.speed = 1; launcher.turn_rate = 1024; launcher.hp = 100000; launcher.weapon = w_scud;
    launcher.facing_tolerance = 1024; launcher.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_launcher = w.define_type(launcher);
    w.spawn(t_launcher, 0, {14, 20});
    for (int t = 0; t < 5; ++t) w.step();
    CHECK(w.actor(0).hp < hp0);
    const int32_t hit = hp0 - w.actor(0).hp;
    std::printf("SCUD-Volltreffer: %d Schaden (OpenRA 45000 bei voller Kurve, halbiert liegend)\n", hit);
    CHECK(hit > 4500);
    CHECK(w.actor(0).prone_ticks > 0);
    CHECK(w.actor(1).hp == tree0);

    World near;
    near.set_map(40, 40, cost.data());
    const int nw = near.define_weapon(scud);
    UnitType l2 = launcher; l2.weapon = nw;
    const int t_l2 = near.define_type(l2);
    UnitType s2 = soldier;
    const int t_s2 = near.define_type(s2);
    near.spawn(t_l2, 0, {20, 20});
    near.spawn(t_s2, 1, {22, 20});
    const int32_t nhp = near.actor(1).hp;
    for (int t = 0; t < 300; ++t) near.step();
    CHECK(near.actor(1).hp == nhp);
    std::printf("MinRange: Ziel auf 2 Zellen bleibt unbeschossen\n");
}


static int32_t run_missile_intercept(bool missile) {
    World w;
    std::vector<uint8_t> cost(50 * 90, 1);
    w.set_map(50, 90, cost.data());


    Weapon wp;
    wp.range = 22 * CELL; wp.reload = 500; wp.damage = 5000; wp.spread = 400;
    wp.speed = 213; wp.proj_missile = missile; wp.missile_turn_rate = 20; wp.missile_range_limit = 30 * CELL;
    wp.valid_targets = TT_GROUND_ACTOR | TT_VEHICLE;
    for (int i = 0; i < NUM_ARMOR; ++i) wp.versus[i] = 100;
    const int w_id = w.define_weapon(wp);

    UnitType launcher;
    launcher.speed = 1; launcher.turn_rate = 1024; launcher.hp = 100000; launcher.weapon = w_id;
    launcher.facing_tolerance = 1024; launcher.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_launcher = w.define_type(launcher);
    UnitType jeep;
    jeep.speed = 113; jeep.turn_rate = 1024; jeep.hp = 30000; jeep.hit_radius = 213;
    jeep.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_jeep = w.define_type(jeep);

    const int32_t jeep_id = w.spawn(t_jeep, 1, {30, 35});
    w.order_move(&jeep_id, 1, {30, 85}, 0);
    const int32_t launcher_id = w.spawn(t_launcher, 0, {10, 40});
    w.order_attack(&launcher_id, 1, jeep_id);

    const int32_t hp0 = w.actor(size_t(w.index_of(jeep_id))).hp;
    for (int t = 0; t < 250; ++t) w.step();
    const int ji = w.index_of(jeep_id);
    return ji >= 0 ? hp0 - w.actor(size_t(ji)).hp : hp0;
}

static void test_missile_projectile() {
    const int32_t missile_dmg = run_missile_intercept(true);
    const int32_t bullet_dmg = run_missile_intercept(false);
    std::printf("Lenkrakete gegen querfahrenden Jeep: %d Schaden; geradlinige Bullet: %d Schaden\n",
                missile_dmg, bullet_dmg);
    CHECK(missile_dmg > 0);
    CHECK(bullet_dmg == 0);
}


static void test_missile_range_limit() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());

    Weapon wp;
    wp.range = 20 * CELL; wp.reload = 500; wp.damage = 5000; wp.spread = 128;
    wp.speed = 213; wp.proj_missile = true; wp.missile_turn_rate = 20;
    wp.missile_range_limit = 8 * CELL;
    wp.valid_targets = TT_GROUND_ACTOR | TT_VEHICLE;
    for (int i = 0; i < NUM_ARMOR; ++i) wp.versus[i] = 100;
    const int w_id = w.define_weapon(wp);

    UnitType launcher;
    launcher.speed = 1; launcher.turn_rate = 1024; launcher.hp = 100000; launcher.weapon = w_id;
    launcher.facing_tolerance = 1024; launcher.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_launcher = w.define_type(launcher);
    UnitType tgt;
    tgt.speed = 1; tgt.turn_rate = 1024; tgt.hp = 30000; tgt.hit_radius = 213;
    tgt.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_tgt = w.define_type(tgt);

    const CPos launcher_cell{5, 20};
    const CPos target_cell{20, 20};
    const int32_t tgt_id = w.spawn(t_tgt, 1, target_cell);
    const int32_t launcher_id = w.spawn(t_launcher, 0, launcher_cell);
    w.order_attack(&launcher_id, 1, tgt_id);

    const int32_t hp0 = w.actor(size_t(w.index_of(tgt_id))).hp;
    bool saw_projectile = false;
    WVec last_pos{};
    for (int t = 0; t < 10; ++t) {
        w.step();
        std::vector<RenderSprite> rs;
        w.render_sprites(1024, rs);
        for (const RenderSprite& s : rs) if (s.weapon == w_id) { saw_projectile = true; last_pos = {s.x, s.y}; }
    }
    CHECK(saw_projectile);
    bool still_flying = false;
    for (int t = 0; t < 60; ++t) {
        w.step();
        std::vector<RenderSprite> rs;
        w.render_sprites(1024, rs);
        still_flying = false;
        for (const RenderSprite& s : rs) if (s.weapon == w_id) { still_flying = true; last_pos = {s.x, s.y}; }
    }
    CHECK(!still_flying);

    const WVec launcher_pos = cell_center(launcher_cell);
    const WVec target_pos = cell_center(target_cell);
    const int32_t dist_to_launch = length(last_pos - launcher_pos);
    const int32_t dist_target_launch = length(target_pos - launcher_pos);
    std::printf("RangeLimit: letzte Position %d Zellen vom Schützen, Ziel wäre %d Zellen entfernt gewesen\n",
                dist_to_launch / CELL, dist_target_launch / CELL);
    CHECK(dist_to_launch < dist_target_launch);
    CHECK(w.actor(size_t(w.index_of(tgt_id))).hp == hp0);
}


static void test_economy_rules() {
    World w;
    std::vector<uint8_t> terrain(40 * 40, TER_CLEAR);
    for (int x = 0; x < 40; ++x) terrain[20 * 40 + x] = TER_BEACH;
    w.set_terrain(40, 40, terrain.data());

    UnitType fact; fact.building = true; fact.foot_w = 3; fact.foot_h = 3;
    fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1}; fact.build_block = fact.footprint;
    fact.hp = 150000; fact.cost = 2000; fact.base_provider = true;
    fact.produces = (1u << QUEUE_BUILDING) | (1u << QUEUE_DEFENSE);
    fact.provides = {"fact"};
    UnitType proc; proc.building = true; proc.foot_w = 2; proc.foot_h = 2; proc.footprint = {1, 1, 1, 1};
    proc.build_block = proc.footprint;
    proc.hp = 90000; proc.cost = 1400; proc.sell_value = 300; proc.storage = 2000; proc.queue_kind = QUEUE_BUILDING;
    proc.repair_step = 700;
    UnitType weap; weap.building = true; weap.foot_w = 2; weap.foot_h = 2; weap.footprint = {1, 1, 1, 1};
    weap.build_block = weap.footprint;
    weap.hp = 150000; weap.cost = 2000; weap.produces = 1u << QUEUE_VEHICLE; weap.queue_kind = QUEUE_BUILDING;
    UnitType tank; tank.speed = 72; tank.turn_rate = 20; tank.hp = 46000; tank.cost = 850; tank.queue_kind = QUEUE_VEHICLE;
    UnitType silo; silo.building = true; silo.foot_w = 1; silo.foot_h = 1; silo.footprint = {1}; silo.build_block = {1};
    silo.hp = 30000; silo.cost = 150; silo.storage = 3000; silo.queue_kind = QUEUE_DEFENSE; silo.build_limit = 2;
    const int t_fact = w.define_type(fact), t_proc = w.define_type(proc), t_weap = w.define_type(weap);
    const int t_tank = w.define_type(tank), t_silo = w.define_type(silo);
    w.spawn_building(t_fact, 0, {5, 5});
    const int32_t proc_id = w.spawn_building(t_proc, 0, {9, 5});
    w.give_credits(0, 20000);


    CHECK(w.sell_value(proc_id) == 150);


    CHECK(!w.can_place(0, t_proc, {6, 20}, nullptr));
    CHECK(w.can_place(0, t_proc, {6, 8}, nullptr));


    w.spawn_building(t_weap, 0, {5, 9});
    const int32_t one = w.build_time(0, t_tank);
    w.spawn_building(t_weap, 0, {8, 9});
    const int32_t two = w.build_time(0, t_tank);
    std::printf("SpeedUp: 1 Fabrik %d Ticks, 2 Fabriken %d Ticks\n", one, two);
    CHECK(one == 850 * 60 / 100);
    CHECK(two == one * 75 / 100);


    CHECK(w.queue_build(0, t_tank));
    CHECK(w.queue(0, QUEUE_VEHICLE).front().total_time == two);
    CHECK(w.queue(0, QUEUE_VEHICLE).front().total_time != w.build_time(t_tank));
    int ticks_to_done = 0;
    const int32_t announced = w.queue(0, QUEUE_VEHICLE).front().remaining_time;
    while (!w.queue(0, QUEUE_VEHICLE).empty() && !w.queue(0, QUEUE_VEHICLE).front().done && ticks_to_done < 2000) {
        w.step();
        ++ticks_to_done;
    }
    std::printf("Restzeit: angekündigt %d Ticks, gebraucht %d Ticks\n", announced, ticks_to_done);
    CHECK(ticks_to_done == announced);


    CHECK(w.queue_build(0, t_silo));
    CHECK(w.queue_build(0, t_silo));
    CHECK(!w.build_limit_reached(0, t_tank));
    CHECK(w.build_limit_reached(0, t_silo));
    CHECK(!w.queue_build(0, t_silo));


    CHECK(w.storage_room(0) == 2000);
    w.give_resources(0, 5000);
    CHECK(w.storage_room(0) == 0);
    std::printf("Wirtschaftsregeln: Erstattung %lld, Lagerplatz %lld\n",
                static_cast<long long>(w.sell_value(proc_id)), static_cast<long long>(w.storage_room(0)));
}


static void test_bot_recovery() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint;
    fact.hp = 150000; fact.armor = ARMOR_WOOD; fact.produces = (1u << QUEUE_BUILDING) | (1u << QUEUE_VEHICLE);
    fact.base_provider = true; fact.provides = {"fact"}; fact.cost = 2000; fact.repair_step = 7000;
    UnitType weap;
    weap.building = true; weap.foot_w = 3; weap.foot_h = 3; weap.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    weap.build_block = weap.footprint;
    weap.hp = 150000; weap.armor = ARMOR_WOOD; weap.produces = 1u << QUEUE_VEHICLE; weap.cost = 2000;
    weap.queue_kind = QUEUE_BUILDING; weap.provides = {"weap"}; weap.ai_building_fraction = 4; weap.exit_dx = 1; weap.exit_dy = 3;
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1}; powr.build_block = powr.footprint;
    powr.hp = 40000; powr.armor = ARMOR_WOOD; powr.power = 100; powr.cost = 300;
    powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"}; powr.ai_building_fraction = 1;
    powr.repair_step = 700;
    UnitType mcv;
    mcv.speed = 60; mcv.turn_rate = 20; mcv.hp = 60000; mcv.cost = 2000; mcv.queue_kind = QUEUE_VEHICLE;
    mcv.ai_unit_share = 10;
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr), t_weap = w.define_type(weap);
    UnitType mcv2 = mcv; mcv2.transforms_into = t_fact;
    const int t_mcv = w.define_type(mcv2);
    UnitType soldier; soldier.speed = 54; soldier.turn_rate = 1024; soldier.infantry = true; soldier.hp = 5000;
    const int t_soldier = w.define_type(soldier);
    (void)t_powr;
    const int32_t yard = w.spawn_building(t_fact, 1, {30, 30});
    w.spawn_building(t_weap, 1, {35, 30});
    const int32_t enemy = w.spawn(t_soldier, 0, {20, 20});
    w.give_credits(1, 30000);
    BotParams bp; bp.squad_size = 6;
    w.enable_bot(1, bp);
    for (int t = 0; t < 600; ++t) w.step();


    int powr_idx = -1;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        if (w.actor(i).alive && w.actor(i).owner == 1 && w.type(w.actor(i).type).power > 0) powr_idx = int(i);
    }
    if (powr_idx >= 0) {
        w.damage_for_test(size_t(powr_idx), 20000, enemy);
        for (int t = 0; t < 30; ++t) w.step();
        CHECK(w.actor(size_t(powr_idx)).repairing);
        std::printf("KI repariert: Kraftwerk auf Reparatur geschaltet\n");
    }


    w.destroy(yard);
    bool rebuilt = false;
    for (int t = 0; t < 4000 && !rebuilt; ++t) {
        w.step();
        for (size_t i = 0; i < w.actor_count(); ++i) {
            const Actor& a = w.actor(i);
            if (a.alive && a.owner == 1 && a.type == t_fact) rebuilt = true;
        }
    }
    int32_t mcvs = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        if (w.actor(i).alive && w.actor(i).owner == 1 && w.actor(i).type == t_mcv) ++mcvs;
    }
    std::printf("KI-Wiederaufbau: Bauhof %s, MCVs unterwegs %d\n", rebuilt ? "neu" : "fehlt", mcvs);
    CHECK(rebuilt || mcvs > 0);
}


static void test_field_generation_mixed() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 1000;
    UnitType hut; hut.building = true; hut.foot_w = 2; hut.foot_h = 2; hut.footprint = {1, 1, 1, 1}; hut.hp = 1000;
    const int t_tank = w.define_type(tank), t_hut = w.define_type(hut);
    std::vector<int32_t> ids;
    for (int i = 0; i < 8; ++i) ids.push_back(w.spawn(t_tank, 0, {2 + i, 2}));

    for (int k = 0; k < 8; ++k) {
        w.order_move(&ids[size_t(k)], 1, {30, 4 + 2 * k}, 0);
        w.step();
    }
    CHECK(w.fields().size() == 8);
    const uint32_t gen_before = w.fields().generation();


    w.spawn_building(t_hut, 0, {20, 20});
    CHECK(w.fields().size() == 0);
    CHECK(w.fields().generation() != gen_before);
    w.order_move(&ids[7], 1, {36, 36}, 0);
    CHECK(w.fields().size() == 1);
    for (int t = 0; t < 40; ++t) w.step();


    int checked = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        if (!w.actor(i).alive || w.type(w.actor(i).type).building) continue;
        const Mobile& m = w.mobile(i);
        if (!m.moving || m.field < 0) continue;
        CHECK(size_t(m.field) < w.fields().size());
        if (size_t(m.field) >= w.fields().size()) continue;
        CHECK(w.fields().field(m.field).goal == m.goal);
        ++checked;
    }
    std::printf("Feldgeneration gemischt: %d Einheiten am eigenen Feld, %u Felder\n",
                checked, uint32_t(w.fields().size()));
    CHECK(checked >= 7);
}


static void test_bot_harvester_redirect() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.base_provider = true; fact.cost = 2000;
    fact.produces = 1u << QUEUE_BUILDING; fact.provides = {"fact"};
    UnitType proc;
    proc.building = true; proc.foot_w = 2; proc.foot_h = 2; proc.footprint = {1, 1, 1, 1};
    proc.build_block = proc.footprint; proc.hp = 90000; proc.cost = 1400; proc.queue_kind = QUEUE_BUILDING;
    proc.refinery = true; proc.dock_dx = 1; proc.dock_dy = 2;
    UnitType harv;
    harv.speed = 72; harv.turn_rate = 20; harv.hp = 60000; harv.harvester = true; harv.capacity = 20;
    harv.bale_load_delay = 4; harv.bale_unload_delay = 1; harv.search_from_proc = 15; harv.search_from_harv = 8;
    harv.wait_duration = 25; harv.cost = 1400;
    const int t_fact = w.define_type(fact), t_proc = w.define_type(proc), t_harv = w.define_type(harv);
    w.spawn_building(t_fact, 1, {6, 6});
    w.spawn_building(t_proc, 1, {10, 6});
    std::vector<int> hs;
    for (int k = 0; k < 6; ++k) hs.push_back(w.index_of(w.spawn(t_harv, 1, {11 + k, 10})));

    for (int x = 12; x < 14; ++x) w.set_resource({x, 12}, RES_ORE, 1);
    for (int y = 30; y < 36; ++y)
        for (int x = 30; x < 36; ++x) w.set_resource({x, y}, RES_ORE, 12);
    BotParams bp;
    w.enable_bot(1, bp);
    int redirected = 0;
    CPos goal{0, 0};
    for (int t = 0; t < 3000 && redirected == 0; ++t) {
        w.step();
        for (int hi : hs) {
            if (w.mobile(size_t(hi)).goal.x >= 25) { ++redirected; goal = w.mobile(size_t(hi)).goal; }
        }
    }
    std::printf("KI-Harvester: %s zum frischen Erzfeld umgeleitet (Ziel %d,%d)\n",
                redirected > 0 ? "ja" : "NEIN", goal.x, goal.y);
    CHECK(redirected > 0);
}


static void test_order_deliver() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType harv;
    harv.speed = 72; harv.turn_rate = 1024; harv.hp = 60000; harv.harvester = true; harv.capacity = 20;
    harv.bale_load_delay = 4; harv.bale_unload_delay = 1; harv.search_from_proc = 15; harv.search_from_harv = 8;
    harv.wait_duration = 25; harv.harvest_facings = 0;
    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 3; proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0};
    proc.build_block = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    proc.hp = 90000; proc.refinery = true; proc.dock_dx = 1; proc.dock_dy = 2;
    UnitType tank;
    tank.speed = 60; tank.turn_rate = 1024; tank.hp = 40000;
    const int t_harv = w.define_type(harv), t_proc = w.define_type(proc), t_tank = w.define_type(tank);


    const int32_t proc_a = w.spawn_building(t_proc, 0, {6, 6});
    const int32_t proc_b = w.spawn_building(t_proc, 0, {28, 6});
    const int32_t foreign = w.spawn_building(t_proc, 1, {6, 28});
    (void)proc_a;
    for (int y = 12; y < 18; ++y)
        for (int x = 12; x < 18; ++x) w.set_resource({x, y}, RES_ORE, 12);
    const int32_t h = w.spawn(t_harv, 0, {14, 14});
    const int32_t tk = w.spawn(t_tank, 0, {20, 20});


    for (int t = 0; t < 400 && w.harvest(size_t(w.index_of(h))).bales < 10; ++t) w.step();
    const int32_t bales = w.harvest(size_t(w.index_of(h))).bales;
    CHECK(bales >= 1 && bales < 20);


    CHECK(!w.order_deliver(&tk, 1, proc_b));
    CHECK(!w.order_deliver(&h, 1, foreign));
    CHECK(!w.order_deliver(&h, 1, 999999));
    CHECK(!w.order_deliver(&h, 1, tk));

    const int32_t before = w.credits(0);
    CHECK(w.order_deliver(&h, 1, proc_b));
    CHECK(w.harvest(size_t(w.index_of(h))).linked_proc == proc_b);
    int docked = -1;
    for (int t = 0; t < 2000; ++t) {
        w.step();
        if (docked < 0 && w.harvest(size_t(w.index_of(h))).bales == 0) docked = t;
    }
    const int32_t after = w.credits(0);

    const CPos cell = w.mobile(size_t(w.index_of(h))).cell;
    std::printf("Deliver: %d Ballen abgeliefert bei Tick %d (Guthaben +%d), Ernteeinheit bei %d,%d\n",
                bales, docked, after - before, cell.x, cell.y);
    CHECK(docked >= 0);
    CHECK(after > before);
    CHECK(w.harvest(size_t(w.index_of(h))).state != Harvest::IDLE);
    CHECK(w.earned(0) > 0);


    const int32_t h2 = w.spawn(t_harv, 0, {20, 14});
    CHECK(w.harvest(size_t(w.index_of(h2))).bales == 0);
    CHECK(w.order_deliver(&h2, 1, proc_b));
    bool reached = false;
    for (int t = 0; t < 1500 && !reached; ++t) {
        w.step();
        const Harvest& hh = w.harvest(size_t(w.index_of(h2)));
        if (hh.state == Harvest::UNLOADING || hh.state == Harvest::DOCK_TURN) reached = true;
    }
    CHECK(reached);
    bool harvesting_again = false;
    for (int t = 0; t < 800; ++t) {
        w.step();
        const Harvest::State st = w.harvest(size_t(w.index_of(h2))).state;
        if (st == Harvest::TO_FIELD || st == Harvest::HARVESTING) harvesting_again = true;
    }
    std::printf("Deliver leer: angedockt, danach wieder am Ernten (%s), Zellabstand zur Raffinerie %d\n",
                harvesting_again ? "ja" : "NEIN",
                int(cell_dist_sq(w.mobile(size_t(w.index_of(h2))).cell, CPos{29, 8})));
    CHECK(harvesting_again);
}


static void test_bot_refinery_reachable() {
    World w;

    std::vector<uint8_t> cost(80 * 80, 1);
    for (int y = 0; y < 80; ++y) cost[size_t(y) * 80 + 40] = 0;
    w.set_map(80, 80, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.base_provider = true; fact.cost = 2000;
    fact.produces = (1u << QUEUE_BUILDING) | (1u << QUEUE_VEHICLE); fact.provides = {"fact"};
    fact.exit_dx = 1; fact.exit_dy = 3;
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1}; powr.build_block = powr.footprint;
    powr.hp = 40000; powr.power = 100; powr.cost = 300; powr.queue_kind = QUEUE_BUILDING;
    powr.provides = {"powr", "anypower"}; powr.ai_building_fraction = 1;
    UnitType harv;
    harv.speed = 72; harv.turn_rate = 20; harv.hp = 60000; harv.harvester = true; harv.capacity = 20;
    harv.bale_load_delay = 4; harv.bale_unload_delay = 1; harv.search_from_proc = 15; harv.search_from_harv = 8;
    harv.wait_duration = 25; harv.cost = 1400; harv.queue_kind = QUEUE_VEHICLE; harv.ai_unit_share = 15;
    harv.ai_unit_limit = 8;
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr), t_harv = w.define_type(harv);
    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 3; proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0};
    proc.build_block = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    proc.hp = 90000; proc.power = -30; proc.cost = 1400; proc.queue_kind = QUEUE_BUILDING;
    proc.prerequisites = {"anypower"}; proc.provides = {"proc"}; proc.refinery = true;
    proc.dock_dx = 1; proc.dock_dy = 2; proc.ai_building_fraction = 1;
    proc.free_actor = t_harv; proc.free_dx = 1; proc.free_dy = 2;
    const int t_proc = w.define_type(proc);
    (void)t_powr;


    const CPos near_field{18, 30}, far_field{46, 30};
    for (int y = near_field.y - 2; y <= near_field.y + 2; ++y)
        for (int x = near_field.x - 2; x <= near_field.x + 2; ++x) w.set_resource({x, y}, RES_ORE, 6);
    for (int y = far_field.y - 5; y <= far_field.y + 5; ++y)
        for (int x = far_field.x - 5; x <= far_field.x + 5; ++x) w.set_resource({x, y}, RES_ORE, 12);

    w.spawn_building(t_fact, 1, {30, 30});
    w.give_credits(1, 20000);
    BotParams bp;
    bp.squad_size = 1000;
    w.enable_bot(1, bp);


    std::vector<uint8_t> reach;
    w.bot_land_reach({30, 30}, reach);
    CHECK(reach[size_t(near_field.y) * 80 + size_t(near_field.x)] == 1);
    CHECK(reach[size_t(far_field.y) * 80 + size_t(far_field.x)] == 0);

    for (int t = 0; t < 6000; ++t) w.step();
    int32_t at_near = 0, at_far = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        if (!a.alive || a.owner != 1 || a.type != t_proc) continue;
        if (a.origin.x < 40) ++at_near; else ++at_far;
    }
    std::printf("KI-Raffinerie: %d diesseits der Wand, %d jenseits, Ertrag %lld\n",
                at_near, at_far, static_cast<long long>(w.earned(1)));
    CHECK(at_near > 0);
    CHECK(at_far == 0);
    CHECK(w.earned(1) > 0);
}


static void test_bot_expansion() {
    World w;
    std::vector<uint8_t> cost(96 * 96, 1);
    w.set_map(96, 96, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.base_provider = true; fact.cost = 2000;
    fact.produces = (1u << QUEUE_BUILDING) | (1u << QUEUE_VEHICLE); fact.provides = {"fact"};
    fact.exit_dx = 1; fact.exit_dy = 3;
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1}; powr.build_block = powr.footprint;
    powr.hp = 40000; powr.power = 100; powr.cost = 300; powr.queue_kind = QUEUE_BUILDING;
    powr.provides = {"powr", "anypower"}; powr.ai_building_fraction = 1;
    UnitType harv;
    harv.speed = 72; harv.turn_rate = 20; harv.hp = 60000; harv.harvester = true; harv.capacity = 20;
    harv.bale_load_delay = 4; harv.bale_unload_delay = 1; harv.search_from_proc = 15; harv.search_from_harv = 8;
    harv.wait_duration = 25; harv.cost = 1400; harv.queue_kind = QUEUE_VEHICLE; harv.ai_unit_share = 15;
    harv.ai_unit_limit = 8;
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr), t_harv = w.define_type(harv);
    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 3; proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0};
    proc.build_block = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    proc.hp = 90000; proc.power = -30; proc.cost = 1400; proc.queue_kind = QUEUE_BUILDING;
    proc.prerequisites = {"anypower"}; proc.provides = {"proc"}; proc.refinery = true;
    proc.dock_dx = 1; proc.dock_dy = 2; proc.ai_building_fraction = 1;
    proc.free_actor = t_harv; proc.free_dx = 1; proc.free_dy = 2;
    const int t_proc = w.define_type(proc);
    UnitType mcv;
    mcv.speed = 60; mcv.turn_rate = 20; mcv.hp = 60000; mcv.cost = 2000; mcv.queue_kind = QUEUE_VEHICLE;
    mcv.transforms_into = t_fact;
    const int t_mcv = w.define_type(mcv);


    const CPos field_b{65, 65};
    for (int y = 8; y < 16; ++y)
        for (int x = 16; x < 24; ++x) w.set_resource({x, y}, RES_ORE, 4);
    for (int y = field_b.y - 5; y <= field_b.y + 5; ++y)
        for (int x = field_b.x - 5; x <= field_b.x + 5; ++x) w.set_resource({x, y}, RES_ORE, 12);

    w.spawn_building(t_fact, 1, {10, 10});
    w.give_credits(1, 30000);
    BotParams bp;
    bp.squad_size = 1000;
    w.enable_bot(1, bp);

    int64_t earned_13000 = 0;
    int32_t first_mcv_tick = -1, second_yard_tick = -1;
    for (int t = 1; t <= 15000; ++t) {
        w.step();
        if (first_mcv_tick < 0) {
            for (size_t i = 0; i < w.actor_count(); ++i)
                if (w.actor(i).alive && w.actor(i).owner == 1 && w.actor(i).type == t_mcv) { first_mcv_tick = t; break; }
        }
        if (second_yard_tick < 0) {
            int32_t n = 0;
            for (size_t i = 0; i < w.actor_count(); ++i)
                if (w.actor(i).alive && w.actor(i).owner == 1 && w.actor(i).type == t_fact) ++n;
            if (n >= 2) second_yard_tick = t;
        }
        if (t == 13000) earned_13000 = w.earned(1);
    }

    int32_t yards = 0, refineries = 0, refineries_at_b = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        if (!a.alive || a.owner != 1 || !w.type(a.type).building) continue;
        if (a.type == t_fact) ++yards;
        if (w.type(a.type).refinery) {
            ++refineries;
            if (cell_dist_sq(a.origin, field_b) <= 25 * 25) ++refineries_at_b;
        }
    }
    const int64_t late_income = w.earned(1) - earned_13000;
    std::printf("KI-Erweiterung: MCV T%d, zweiter Bauhof T%d, Bauhöfe %d, Raffinerien %d (davon am zweiten Feld %d), "
                "Ertrag gesamt %lld, T13000–15000 %lld\n",
                first_mcv_tick, second_yard_tick, yards, refineries, refineries_at_b,
                static_cast<long long>(w.earned(1)), static_cast<long long>(late_income));
    CHECK(first_mcv_tick > 0);
    CHECK(yards >= 2);
    CHECK(refineries_at_b >= 1);
    CHECK(late_income > 0);
    (void)t_powr; (void)t_proc;
}


static void test_bot_intervals() {
    World w;
    std::vector<uint8_t> cost(32 * 32, 1);
    w.set_map(32, 32, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.base_provider = true; fact.cost = 2000;
    fact.produces = (1u << QUEUE_BUILDING) | (1u << QUEUE_VEHICLE); fact.provides = {"fact"};
    const int t_fact = w.define_type(fact);
    w.spawn_building(t_fact, 1, {5, 5});
    w.enable_bot(1, BotParams());


    auto measure = [&](int32_t BotState::*counter, int32_t reload, const char* name) {
        int last = -1, delta = -1;
        for (int t = 0; t < 400; ++t) {
            w.step();
            if (w.bot_state(1).*counter == reload) {
                if (last >= 0 && delta < 0) delta = t - last;
                last = t;
            }
        }
        std::printf("KI-Intervall %s: %d Ticks (OpenRA %d)\n", name, delta, reload);
        CHECK(delta == reload);
    };
    measure(&BotState::mcv_scan_ticks, 20, "MCV-Suche");
    measure(&BotState::mcv_ticks, 101, "MCV-Nachbau");
    measure(&BotState::rally_ticks, 100, "Sammelpunkte");
}


static void test_bot_squad_advance() {
    World w;
    std::vector<uint8_t> cost(96 * 96, 1);
    w.set_map(96, 96, cost.data());
    Weapon gun; gun.range = 4 * CELL; gun.reload = 20; gun.damage = 2000; gun.speed = 0;
    const int wgun = w.define_weapon(gun);
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.armor = ARMOR_WOOD;
    fact.base_provider = true; fact.provides = {"fact"};
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.weapon = wgun;
    UnitType hut;
    hut.building = true; hut.foot_w = 2; hut.foot_h = 2; hut.footprint = {1, 1, 1, 1};
    hut.build_block = hut.footprint; hut.hp = 200000; hut.armor = ARMOR_WOOD;
    const int t_fact = w.define_type(fact), t_e1 = w.define_type(e1), t_hut = w.define_type(hut);

    w.spawn_building(t_fact, 1, {6, 6});
    const int32_t target = w.spawn_building(t_hut, 0, {84, 84});
    for (int i = 0; i < 12; ++i) w.spawn(t_e1, 1, {10 + i % 4, 10 + i / 4});
    BotParams bp;
    bp.squad_size = 8;
    bp.squad_size_random_bonus = 1;
    w.enable_bot(1, bp);


    uint32_t hit_tick = 0;
    for (int t = 0; t < 12000 && hit_tick == 0; ++t) {
        w.step();
        const int i = w.index_of(target);
        if (i >= 0 && w.actor(size_t(i)).hp < 200000) hit_tick = w.tick();
    }
    const int li = w.index_of(target);
    std::printf("KI-Trupp erreicht das Ziel bei Tick %u (Ziel-HP %d, Schranke 6400)\n", hit_tick,
                li >= 0 ? w.actor(size_t(li)).hp : 0);
    CHECK(hit_tick > 0 && hit_tick < 6400);
}


static void test_bot_vehicle_timing() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    Weapon cannon; cannon.range = 5 * CELL; cannon.reload = 50; cannon.damage = 4000; cannon.speed = 0;
    const int wcannon = w.define_weapon(cannon);
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.armor = ARMOR_WOOD;
    fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true; fact.provides = {"fact"};
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.build_block = powr.footprint; powr.hp = 40000; powr.armor = ARMOR_WOOD; powr.power = 100;
    powr.cost = 300; powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"};
    powr.ai_building_fraction = 1;
    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 3; proc.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    proc.build_block = proc.footprint; proc.hp = 90000; proc.armor = ARMOR_WOOD; proc.power = -30;
    proc.cost = 1400; proc.queue_kind = QUEUE_BUILDING; proc.prerequisites = {"anypower"};
    proc.provides = {"proc"}; proc.refinery = true; proc.dock_dx = 1; proc.dock_dy = 2;
    proc.ai_building_fraction = 1;
    UnitType weap;
    weap.building = true; weap.foot_w = 3; weap.foot_h = 3; weap.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    weap.build_block = weap.footprint; weap.hp = 150000; weap.armor = ARMOR_WOOD; weap.power = -30;
    weap.cost = 2000; weap.queue_kind = QUEUE_BUILDING; weap.prerequisites = {"proc"};
    weap.provides = {"weap"}; weap.produces = 1u << QUEUE_VEHICLE; weap.exit_dx = 1; weap.exit_dy = 3;
    weap.ai_building_fraction = 4;
    UnitType harv;
    harv.speed = 72; harv.turn_rate = 20; harv.hp = 60000; harv.cost = 1100;
    harv.queue_kind = QUEUE_VEHICLE; harv.prerequisites = {"proc"}; harv.harvester = true;
    harv.capacity = 20; harv.ai_unit_share = 15; harv.ai_unit_limit = 8;
    UnitType tank;
    tank.speed = 85; tank.turn_rate = 20; tank.hp = 40000; tank.cost = 1150; tank.weapon = wcannon;
    tank.queue_kind = QUEUE_VEHICLE; tank.prerequisites = {"weap"}; tank.ai_unit_share = 50;

    const int t_harv = w.define_type(harv);
    proc.free_actor = t_harv;
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr);
    const int t_proc = w.define_type(proc), t_weap = w.define_type(weap);
    const int t_tank = w.define_type(tank);
    (void)t_powr; (void)t_proc;

    w.spawn_building(t_fact, 1, {8, 8});
    w.spawn_building(t_weap, 1, {14, 8});

    for (int y = 20; y < 34; ++y)
        for (int x = 4; x < 18; ++x) w.set_resource({x, y}, RES_ORE, 12);
    w.give_credits(1, 20000);
    w.enable_bot(1, BotParams());

    uint32_t tank_tick = 0;
    for (int t = 0; t < 6000 && tank_tick == 0; ++t) {
        w.step();
        for (size_t i = 0; i < w.actor_count(); ++i) {
            const Actor& a = w.actor(i);
            if (a.alive && a.owner == 1 && a.type == t_tank) { tank_tick = w.tick(); break; }
        }
    }
    std::printf("KI baut ihr erstes Kampffahrzeug bei Tick %u (Ziel < 6000)\n", tank_tick);
    CHECK(tank_tick > 0 && tank_tick < 6000);
}


static uint64_t state_hash(const World& w) {
    uint64_t h = 1469598103934665603ull;
    auto mix = [&h](int64_t v) {
        for (int b = 0; b < 8; ++b) {
            h ^= uint64_t((v >> (8 * b)) & 0xFF);
            h *= 1099511628211ull;
        }
    };
    mix(w.tick());
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        mix(a.id); mix(a.type); mix(a.owner); mix(a.alive ? 1 : 0); mix(a.hp);
        mix(a.pos.x); mix(a.pos.y); mix(a.facing);
        const Mobile& m = w.mobile(i);
        mix(m.cell.x); mix(m.cell.y); mix(m.goal.x); mix(m.goal.y); mix(m.moving ? 1 : 0);
    }
    for (int32_t p = 0; p < MAX_PLAYERS; ++p) mix(w.credits(p));
    return h;
}


static void test_cargo() {
    World w;
    std::vector<uint8_t> cost(32 * 32, 1);
    w.set_map(32, 32, cost.data());
    UnitType apc;
    apc.speed = 128; apc.turn_rate = 20; apc.hp = 35000; apc.hit_radius = 426;
    apc.cargo_max_weight = 5; apc.cargo_types = TT_INFANTRY; apc.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.hit_radius = 128;
    e1.passenger_weight = 1; e1.passenger_type = TT_INFANTRY; e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_apc = w.define_type(apc);
    const int t_e1 = w.define_type(e1);
    const int32_t apc_id = w.spawn(t_apc, 0, {10, 10});
    std::vector<int32_t> troop;
    for (int i = 0; i < 5; ++i) troop.push_back(w.spawn(t_e1, 0, {14 + i, 14}));
    w.order_enter_transport(troop.data(), troop.size(), apc_id);
    for (int t = 0; t < 400; ++t) w.step();
    CHECK(w.cargo_weight(apc_id) == 5);
    for (const int32_t id : troop) CHECK(w.transport_of(id) == apc_id);

    const int32_t extra = w.spawn(t_e1, 0, {12, 12});
    CHECK(!w.can_load(apc_id, extra));
    std::printf("Transport: %d Gewicht geladen, sechster Passagier abgewiesen\n", w.cargo_weight(apc_id));


    w.order_move(&apc_id, 1, {24, 24});
    for (int t = 0; t < 400; ++t) w.step();
    w.order_unload(&apc_id, 1);
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.cargo_weight(apc_id) == 0);
    int out = 0;
    for (const int32_t id : troop) {
        const int i = w.index_of(id);
        if (i >= 0 && w.actor(size_t(i)).alive && w.actor(size_t(i)).transport < 0) ++out;
        if (i >= 0) CHECK(cell_dist_sq(w.mobile(size_t(i)).cell, w.mobile(size_t(w.index_of(apc_id))).cell) < 40);
    }
    CHECK(out == 5);
    std::printf("Transport: %d Passagiere wieder ausgestiegen\n", out);


    w.order_enter_transport(troop.data(), troop.size(), apc_id);
    for (int t = 0; t < 400; ++t) w.step();
    CHECK(w.cargo_weight(apc_id) == 5);
    w.destroy(apc_id);
    int dead = 0;
    for (const int32_t id : troop) {
        const int i = w.index_of(id);
        if (i >= 0 && !w.actor(size_t(i)).alive) ++dead;
    }
    CHECK(dead == 5);
    std::printf("Transport: %d Passagiere mit dem Wrack gestorben\n", dead);
}


static void test_aircraft() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    Weapon hellfire;
    hellfire.range = 4 * CELL; hellfire.reload = 30; hellfire.damage = 3000; hellfire.spread = 128;
    hellfire.speed = 0; hellfire.valid_targets = TT_GROUND_ACTOR;
    Weapon flak;
    flak.range = 6 * CELL; flak.reload = 20; flak.damage = 2000; flak.spread = 128;
    flak.speed = 0; flak.valid_targets = TT_AIRBORNE;
    const int w_hell = w.define_weapon(hellfire);
    const int w_flak = w.define_weapon(flak);

    UnitType hpad;
    hpad.building = true; hpad.foot_w = 2; hpad.foot_h = 2; hpad.footprint = {1, 1, 1, 1};
    hpad.build_block = hpad.footprint; hpad.hp = 80000; hpad.produces = 1u << QUEUE_AIRCRAFT;
    hpad.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_hpad = w.define_type(hpad);

    UnitType heli;
    heli.aircraft = true; heli.can_hover = true; heli.vtol = true; heli.speed = 149; heli.turn_rate = 16;
    heli.cruise_altitude = 1280; heli.altitude_velocity = 43; heli.hp = 12000; heli.weapon = w_hell;
    heli.ammo_max = 8; heli.ammo_reload = 20; heli.air_attack_type = 1; heli.facing_tolerance = 80;
    heli.hit_radius = 426; heli.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    heli.target_types_airborne = TT_AIRBORNE; heli.rearm_actors = {t_hpad};
    heli.auto_target_mask = TT_GROUND_ACTOR | TT_VEHICLE | TT_STRUCTURE;
    const int t_heli = w.define_type(heli);

    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 40000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_tank = w.define_type(tank);

    UnitType agun;
    agun.building = true; agun.foot_w = 1; agun.foot_h = 1; agun.footprint = {1};
    agun.build_block = agun.footprint; agun.hp = 40000; agun.weapon = w_flak; agun.turreted = true;
    agun.turret_turn = 40; agun.target_types = TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE;
    agun.auto_target_mask = TT_AIRBORNE;
    const int t_agun = w.define_type(agun);

    const int32_t pad = w.spawn_building(t_hpad, 0, {4, 4});
    const int32_t h = w.spawn(t_heli, 0, {6, 6});
    const int32_t victim = w.spawn(t_tank, 1, {36, 36});
    CHECK(pad > 0 && h > 0);

    CHECK(w.occupant({6, 6}) == -1);

    w.order_attack(&h, 1, victim);
    int hi = w.index_of(h);
    for (int t = 0; t < 200 && w.air(size_t(hi)).alt < 1280; ++t) w.step();
    CHECK(w.air(size_t(w.index_of(h))).alt == 1280);
    for (int t = 0; t < 900; ++t) {
        w.step();
        if (w.index_of(victim) < 0 || !w.actor(size_t(w.index_of(victim))).alive) break;
    }
    hi = w.index_of(h);
    const int vi = w.index_of(victim);
    std::printf("Helikopter: Ziel-HP %d, Munition %d/8, Höhe %d\n",
                vi >= 0 ? w.actor(size_t(vi)).hp : 0, w.air(size_t(hi)).ammo, w.air(size_t(hi)).alt);
    CHECK(vi >= 0 && w.actor(size_t(vi)).hp < 40000);

    for (int t = 0; t < 2500; ++t) {
        w.step();
        hi = w.index_of(h);
        if (w.air(size_t(hi)).ammo >= 8 && w.air(size_t(hi)).state == Air::LANDED) break;
    }
    hi = w.index_of(h);
    std::printf("Helikopter: nach Rückflug Zustand %d, Höhe %d, Munition %d\n",
                w.air(size_t(hi)).state, w.air(size_t(hi)).alt, w.air(size_t(hi)).ammo);
    CHECK(w.air(size_t(hi)).state == Air::LANDED);
    CHECK(w.air(size_t(hi)).alt == 0);
    CHECK(w.air(size_t(hi)).ammo == 8);


    w.spawn_building(t_agun, 1, {10, 10});
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.index_of(h) >= 0 && w.actor(size_t(w.index_of(h))).alive);
    const int32_t to = w.spawn(t_tank, 1, {12, 12});
    w.order_attack(&h, 1, to);
    int hits = 0;
    for (int t = 0; t < 1200; ++t) {
        w.step();
        if (w.index_of(h) < 0 || !w.actor(size_t(w.index_of(h))).alive) { hits = 1; break; }
    }
    std::printf("Flugabwehr: Helikopter %s\n", hits ? "abgeschossen" : "überlebt");
    CHECK(hits == 1);
}


static void test_air_production() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    Weapon hellfire;
    hellfire.range = 5 * CELL; hellfire.reload = 40; hellfire.damage = 3000; hellfire.spread = 128;
    hellfire.speed = 0; hellfire.valid_targets = TT_GROUND_ACTOR;
    const int w_hell = w.define_weapon(hellfire);

    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.hp = 150000; fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true;
    fact.provides = {"fact"};
    UnitType hpad;
    hpad.building = true; hpad.foot_w = 2; hpad.foot_h = 2; hpad.footprint = {1, 1, 1, 1};
    hpad.build_block = hpad.footprint; hpad.hp = 80000; hpad.produces = 1u << QUEUE_AIRCRAFT;
    hpad.target_types = TT_GROUND_ACTOR | TT_STRUCTURE; hpad.provides = {"hpad"};
    hpad.exit_dx = 0; hpad.exit_dy = 0; hpad.rally_dx = 0; hpad.rally_dy = 1;


    hpad.exit_ox = 0; hpad.exit_oy = -256; hpad.exit_facing = 896;
    UnitType heli;
    heli.aircraft = true; heli.can_hover = true; heli.vtol = true; heli.speed = 149; heli.turn_rate = 16;
    heli.cruise_altitude = 1280; heli.altitude_velocity = 43; heli.hp = 12000; heli.weapon = w_hell;
    heli.ammo_max = 8; heli.ammo_reload = 20; heli.air_attack_type = 1; heli.facing_tolerance = 80;
    heli.hit_radius = 426; heli.cost = 200; heli.queue_kind = QUEUE_AIRCRAFT;
    heli.prerequisites = {"hpad"};
    heli.target_types = TT_GROUND_ACTOR | TT_VEHICLE; heli.target_types_airborne = TT_AIRBORNE;
    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 40000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_fact = w.define_type(fact), t_hpad = w.define_type(hpad);
    heli.rearm_actors = {t_hpad};
    const int t_heli = w.define_type(heli), t_tank = w.define_type(tank);

    w.spawn_building(t_fact, 0, {10, 10});
    const int32_t pad = w.spawn_building(t_hpad, 0, {16, 10});
    w.give_credits(0, 5000);
    const size_t before = w.actor_count();
    CHECK(w.queue_build(0, t_heli));
    for (int t = 0; t < 400 && w.actor_count() == before; ++t) w.step();
    CHECK(w.actor_count() == before + 1);
    const int32_t h = w.actor(before).id;
    int hi = w.index_of(h);

    for (int t = 0; t < 60; ++t) w.step();
    hi = w.index_of(h);
    CHECK(w.air(size_t(hi)).state == Air::LANDED);
    CHECK(w.air(size_t(hi)).alt == 0);
    CHECK(w.air(size_t(hi)).ammo == 8);
    CHECK(w.air(size_t(hi)).base == pad);


    const int pi = w.index_of(pad);
    CHECK(w.actor(size_t(hi)).pos.x == w.actor(size_t(pi)).pos.x + hpad.exit_ox);
    CHECK(w.actor(size_t(hi)).pos.y == w.actor(size_t(pi)).pos.y + hpad.exit_oy);
    CHECK(w.actor(size_t(hi)).facing == hpad.exit_facing);
    std::printf("Flugzeugbau: Zustand %d, Höhe %d, Munition %d, Platz reserviert %d, Andockversatz %d,%d\n",
                w.air(size_t(hi)).state, w.air(size_t(hi)).alt, w.air(size_t(hi)).ammo,
                int(w.air(size_t(hi)).base == pad),
                w.actor(size_t(hi)).pos.x - w.actor(size_t(pi)).pos.x,
                w.actor(size_t(hi)).pos.y - w.actor(size_t(pi)).pos.y);


    const int32_t victim = w.spawn(t_tank, 1, {30, 30});
    w.order_attack(&h, 1, victim);
    for (int t = 0; t < 900; ++t) {
        w.step();
        const int vi = w.index_of(victim);
        if (vi < 0 || w.actor(size_t(vi)).hp < 40000) break;
    }
    hi = w.index_of(h);
    const int vi = w.index_of(victim);
    CHECK(vi >= 0 && w.actor(size_t(vi)).hp < 40000);
    CHECK(w.air(size_t(hi)).ammo < 8);
    std::printf("Flugzeugbau: nach dem Angriffsbefehl Ziel-HP %d, Munition %d\n",
                w.actor(size_t(vi)).hp, w.air(size_t(hi)).ammo);


    CHECK(w.can_resupply_at(h, pad));
    w.order_resupply(&h, 1, pad);
    for (int t = 0; t < 1500; ++t) {
        w.step();
        hi = w.index_of(h);
        if (w.air(size_t(hi)).state == Air::LANDED) break;
    }
    hi = w.index_of(h);
    CHECK(w.air(size_t(hi)).state == Air::LANDED);
    CHECK(w.air(size_t(hi)).alt == 0);


    CHECK(w.actor(size_t(hi)).pos.x == w.actor(size_t(pi)).pos.x + hpad.exit_ox);
    CHECK(w.actor(size_t(hi)).pos.y == w.actor(size_t(pi)).pos.y + hpad.exit_oy);
    CHECK(w.actor(size_t(hi)).facing == hpad.exit_facing);
    std::printf("Flugzeugbau: nach dem Landebefehl Zustand %d, Höhe %d\n",
                w.air(size_t(hi)).state, w.air(size_t(hi)).alt);


    CHECK(w.set_rally(pad, {20, 16}));
    const size_t before2 = w.actor_count();
    CHECK(w.queue_build(0, t_heli));
    for (int t = 0; t < 400 && w.actor_count() == before2; ++t) w.step();
    CHECK(w.actor_count() == before2 + 1);
    for (int t = 0; t < 120; ++t) w.step();
    const int h2 = w.index_of(w.actor(before2).id);
    CHECK(w.air(size_t(h2)).alt > 0);
    std::printf("Flugzeugbau: mit Sammelpunkt Höhe %d\n", w.air(size_t(h2)).alt);
}


static void test_new_options() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.hp = 150000; fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true;
    fact.provides = {"fact"};
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.build_block = powr.footprint; powr.hp = 40000; powr.power = 100; powr.cost = 100;
    powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr"}; powr.make_ticks = 20;
    UnitType tent;
    tent.building = true; tent.foot_w = 2; tent.foot_h = 2; tent.footprint = {1, 1, 1, 1};
    tent.build_block = tent.footprint; tent.hp = 60000; tent.cost = 100;
    tent.queue_kind = QUEUE_BUILDING; tent.prerequisites = {"powr"}; tent.provides = {"tent"};
    tent.produces = 1u << QUEUE_INFANTRY; tent.make_ticks = 20;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.cost = 100;
    e1.queue_kind = QUEUE_INFANTRY; e1.prerequisites = {"tent"};
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr);
    const int t_tent = w.define_type(tent), t_e1 = w.define_type(e1);
    (void)t_e1;
    w.spawn_building(t_fact, 0, {10, 10});
    w.give_credits(0, 5000);

    auto build_and_place = [&](int32_t type, CPos at) {
        CHECK(w.queue_build(0, type));
        for (int t = 0; t < 400 && !w.queue(0, QUEUE_BUILDING).front().done; ++t) w.step();
        CHECK(w.place_building(0, type, at));
        std::vector<int32_t> notes;
        w.drain_notifications(0, notes);
        for (int t = 0; t < 40; ++t) w.step();
        w.drain_notifications(0, notes);
        return std::find(notes.begin(), notes.end(), int32_t(NOTIFY_NEW_OPTIONS)) != notes.end();
    };

    CHECK(build_and_place(t_powr, {14, 10}));

    CHECK(!build_and_place(t_powr, {14, 13}));

    CHECK(build_and_place(t_tent, {14, 16}));

    CHECK(!build_and_place(t_tent, {17, 16}));
    std::printf("Neue Bauoptionen: nur beim ersten Kraftwerk und der ersten Kaserne\n");
}


static void test_paradrop() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    UnitType badr;
    badr.aircraft = true; badr.speed = 180; badr.turn_rate = 20; badr.cruise_altitude = 2560;
    badr.altitude_velocity = 43; badr.hp = 40000; badr.cargo_max_weight = 10; badr.cargo_types = TT_INFANTRY;
    badr.target_types = TT_GROUND_ACTOR; badr.target_types_airborne = TT_AIRBORNE;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.hit_radius = 128;
    e1.passenger_weight = 1; e1.passenger_type = TT_INFANTRY; e1.fall_rate = 26;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_badr = w.define_type(badr);
    const int t_e1 = w.define_type(e1);

    const int32_t plane = w.spawn(t_badr, 0, {2, 32}, 768, 100, true);
    CHECK(w.air(size_t(w.index_of(plane))).alt == 2560);
    std::vector<int32_t> troop;
    for (int i = 0; i < 5; ++i) {
        const int32_t id = w.spawn(t_e1, 0, {2, 32});
        troop.push_back(id);
        CHECK(w.load_passenger(plane, id));
    }
    CHECK(w.cargo_weight(plane) == 5);
    w.order_move(&plane, 1, {60, 32});
    w.order_paradrop(plane, {32, 32});
    WDist max_x = 0;
    for (int t = 0; t < 600; ++t) {
        w.step();
        const int k = w.index_of(plane);
        if (k >= 0) max_x = std::max(max_x, w.actor(size_t(k)).pos.x);
    }
    CHECK(w.cargo_weight(plane) == 0);
    CHECK(max_x > 40 * CELL);
    int landed = 0, near_lz = 0;
    for (const int32_t id : troop) {
        const int i = w.index_of(id);
        if (i < 0 || !w.actor(size_t(i)).alive) continue;
        if (w.air(size_t(i)).alt == 0) ++landed;
        if (cell_dist_sq(w.mobile(size_t(i)).cell, CPos{32, 32}) <= 36) ++near_lz;
    }
    std::printf("Fallschirme: %d von 5 gelandet, %d in der Landezone\n", landed, near_lz);
    CHECK(landed == 5);
    CHECK(near_lz == 5);
}


static void test_dual_armament() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    Weapon ag;
    ag.range = 5 * CELL; ag.reload = 20; ag.damage = 1500; ag.spread = 128; ag.speed = 0;
    ag.valid_targets = TT_GROUND_ACTOR;
    Weapon aa;
    aa.range = 7 * CELL; aa.reload = 20; aa.damage = 3000; aa.spread = 128; aa.speed = 0;
    aa.valid_targets = TT_AIRBORNE;
    const int w_ag = w.define_weapon(ag);
    const int w_aa = w.define_weapon(aa);
    UnitType ftrk;
    ftrk.speed = 128; ftrk.turn_rate = 20; ftrk.hp = 20000; ftrk.hit_radius = 426;
    ftrk.weapon = w_ag; ftrk.weapon_secondary = w_aa; ftrk.turreted = true; ftrk.turret_turn = 40;
    ftrk.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    ftrk.auto_target_mask = TT_GROUND_ACTOR | TT_VEHICLE | TT_AIRBORNE;
    UnitType heli;
    heli.aircraft = true; heli.can_hover = true; heli.speed = 100; heli.turn_rate = 16;
    heli.cruise_altitude = 1280; heli.hp = 6000; heli.hit_radius = 426;
    heli.target_types = TT_GROUND_ACTOR | TT_VEHICLE; heli.target_types_airborne = TT_AIRBORNE;
    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 20000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_ftrk = w.define_type(ftrk);
    const int t_heli = w.define_type(heli);
    const int t_tank = w.define_type(tank);

    w.spawn(t_ftrk, 0, {10, 10});
    const int32_t h = w.spawn(t_heli, 1, {16, 10}, 0, 100, true);
    const int32_t g = w.spawn(t_tank, 1, {13, 10});
    for (int t = 0; t < 600; ++t) w.step();
    const int hi = w.index_of(h), gi = w.index_of(g);
    const bool heli_dead = hi < 0 || !w.actor(size_t(hi)).alive;
    const bool tank_hit = gi >= 0 && w.actor(size_t(gi)).hp < 20000;
    std::printf("Zwei Bewaffnungen: Flugziel %s, Bodenziel %s\n",
                heli_dead ? "abgeschossen" : "unversehrt", tank_hit ? "getroffen" : "unversehrt");
    CHECK(heli_dead);
    CHECK(tank_hit);
}


static std::vector<int32_t> build_battle(World& w) {
    std::vector<uint8_t> cost(64 * 64, 1);
    for (int i = 0; i < 64 * 64; i += 53) cost[size_t(i)] = 0;
    w.set_map(64, 64, cost.data());
    Weapon gun; gun.range = 5 * CELL; gun.reload = 40; gun.damage = 2500; gun.spread = 128; gun.speed = 0;
    const int wgun = w.define_weapon(gun);
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.armor = ARMOR_WOOD; fact.cost = 2000;
    fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true; fact.provides = {"fact"};
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.build_block = powr.footprint; powr.hp = 40000; powr.armor = ARMOR_WOOD; powr.power = 100;
    powr.cost = 300; powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"};
    powr.make_ticks = 20; powr.ai_building_fraction = 1;
    UnitType tent;
    tent.building = true; tent.foot_w = 2; tent.foot_h = 2; tent.footprint = {1, 1, 1, 1};
    tent.build_block = tent.footprint; tent.hp = 60000; tent.armor = ARMOR_WOOD; tent.power = -20;
    tent.cost = 500; tent.queue_kind = QUEUE_BUILDING; tent.prerequisites = {"anypower"};
    tent.provides = {"tent", "barracks"}; tent.produces = 1u << QUEUE_INFANTRY;
    tent.exit_dx = 1; tent.exit_dy = 2; tent.make_ticks = 20; tent.ai_building_fraction = 3;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.cost = 100; e1.weapon = wgun;
    e1.hit_radius = 128; e1.queue_kind = QUEUE_INFANTRY; e1.prerequisites = {"barracks"}; e1.ai_unit_share = 100;
    const int t_fact = w.define_type(fact);
    w.define_type(powr); w.define_type(tent);
    const int t_e1 = w.define_type(e1);
    w.spawn_building(t_fact, 0, {6, 6});
    w.spawn_building(t_fact, 1, {50, 50});
    w.give_credits(0, 20000);
    w.give_credits(1, 20000);
    BotParams bp; bp.squad_size = 4; bp.squad_size_random_bonus = 2;
    w.enable_bot(0, bp);
    w.enable_bot(1, bp);

    std::vector<int32_t> troop;
    for (int i = 0; i < 12; ++i) troop.push_back(w.spawn(t_e1, 0, {10 + i, 20}));
    return troop;
}


static void run_battle(World& w, std::vector<int32_t>& troop, uint32_t from, uint32_t count) {
    for (uint32_t t = from; t < from + count; ++t) {
        if (t % 37 == 0) {
            const size_t k = (t / 37) % troop.size();
            w.order_attack_move(&troop[k], 1, {int32_t(5 + (t * 7) % 55), int32_t(5 + (t * 11) % 55)});
        }
        w.step();
    }
}


static void test_determinism_hash() {
    auto run = [](uint32_t ticks) {
        World w;
        std::vector<int32_t> troop = build_battle(w);
        run_battle(w, troop, 0, ticks);
        return state_hash(w);
    };
    const uint64_t h1 = run(2000), h2 = run(2000);
    std::printf("Determinismus (2000 Ticks, Kampf + 2 Bots): Hash %016llx %s\n",
                static_cast<unsigned long long>(h1), h1 == h2 ? "identisch" : "ABWEICHUNG");
    CHECK(h1 == h2);
}


static void test_save_load() {
    World a;
    std::vector<int32_t> troop = build_battle(a);
    run_battle(a, troop, 0, 2000);

    std::vector<uint8_t> blob;
    CHECK(a.save(blob));
    CHECK(blob.size() > 1000);
    const uint64_t before = state_hash(a);


    World b;
    std::vector<int32_t> troop_b = build_battle(b);
    run_battle(b, troop_b, 0, 137);
    CHECK(b.load(blob));
    CHECK(state_hash(b) == before);
    CHECK(b.tick() == a.tick());

    run_battle(a, troop, 2000, 1000);
    run_battle(b, troop_b, 2000, 1000);
    const uint64_t ha = state_hash(a), hb = state_hash(b);
    std::printf("Spielstand: %zu Bytes für %zu Actors / 64x64; Hash nach 1000 Ticks %016llx %s\n",
                blob.size(), a.actor_count(), static_cast<unsigned long long>(ha),
                ha == hb ? "identisch" : "ABWEICHUNG");
    CHECK(ha == hb);


    World c;
    CHECK(!c.load(blob));
    std::vector<uint8_t> junk = {1, 2, 3, 4, 5, 6, 7, 8};
    World d;
    build_battle(d);
    CHECK(!d.load(junk));
    std::vector<uint8_t> cut(blob.begin(), blob.begin() + int(blob.size()) / 2);
    World e;
    build_battle(e);
    CHECK(!e.load(cut));
    CHECK(World::state_version() >= 1);
}


struct ExtrasIds {
    int32_t heli = -1, apc = -1, layer = -1, tank = -1, enemy = -1;
    int t_e1 = -1;
};

static ExtrasIds build_extras(World& w) {
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    w.set_alliance(0, 1, false);
    Weapon hellfire;
    hellfire.range = 4 * CELL; hellfire.reload = 30; hellfire.damage = 800; hellfire.spread = 128;
    hellfire.speed = 0; hellfire.valid_targets = TT_GROUND_ACTOR;
    const int w_hell = w.define_weapon(hellfire);
    Weapon nuke; nuke.damage = 5000; nuke.spread = 1024; nuke.range = 0;
    const int w_nuke = w.define_weapon(nuke);

    UnitType hpad;
    hpad.building = true; hpad.foot_w = 2; hpad.foot_h = 2; hpad.footprint = {1, 1, 1, 1};
    hpad.build_block = hpad.footprint; hpad.hp = 80000; hpad.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_hpad = w.define_type(hpad);
    UnitType heli;
    heli.aircraft = true; heli.can_hover = true; heli.vtol = true; heli.speed = 149; heli.turn_rate = 16;
    heli.cruise_altitude = 1280; heli.altitude_velocity = 43; heli.hp = 12000; heli.weapon = w_hell;
    heli.ammo_max = 8; heli.ammo_reload = 20; heli.air_attack_type = 1; heli.facing_tolerance = 80;
    heli.hit_radius = 426; heli.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    heli.target_types_airborne = TT_AIRBORNE; heli.rearm_actors = {t_hpad};
    const int t_heli = w.define_type(heli);
    UnitType apc;
    apc.speed = 128; apc.turn_rate = 20; apc.hp = 35000; apc.hit_radius = 426;
    apc.cargo_max_weight = 5; apc.cargo_types = TT_INFANTRY; apc.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_apc = w.define_type(apc);
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.locomotor = LOCO_FOOT; e1.hp = 5000;
    e1.hit_radius = 128; e1.passenger_weight = 1; e1.passenger_type = TT_INFANTRY;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_e1 = w.define_type(e1);
    UnitType mine;
    mine.mine = true; mine.crush_classes = CRUSH_MINE; mine.hp = 5000; mine.targetable = false;
    mine.cloak = true; mine.cloak_initial_delay = 0; mine.cloak_types = DETECT_MINE;
    const int t_mine = w.define_type(mine);
    UnitType tank;
    tank.speed = 72; tank.turn_rate = 1024; tank.hp = 46000; tank.hit_radius = 426;
    tank.crushes = CRUSH_MINE | CRUSH_CRATE; tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_tank = w.define_type(tank);
    UnitType layer = tank;
    layer.mine_immune = true; layer.ammo_max = 5; layer.minelayer_mine = t_mine;
    layer.detect_range = 5 * CELL; layer.detect_types = DETECT_MINE;
    const int t_layer = w.define_type(layer);
    UnitType iron;
    iron.building = true; iron.foot_w = 2; iron.foot_h = 2; iron.footprint = {1, 1, 1, 1};
    iron.build_block = iron.footprint; iron.hp = 40000; iron.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    iron.support_power = SP_IRON_CURTAIN; iron.sp_charge = 25; iron.sp_duration = 600;
    iron.sp_dim_w = 3; iron.sp_dim_h = 3; iron.sp_footprint = {0, 1, 0, 1, 1, 1, 0, 1, 0};
    UnitType pdox = iron; pdox.support_power = SP_CHRONOSHIFT; pdox.sp_duration = 600;
    UnitType mslo = iron; mslo.support_power = SP_NUKE; mslo.sp_weapon = w_nuke; mslo.sp_flight = 600;
    const int t_iron = w.define_type(iron), t_pdox = w.define_type(pdox), t_mslo = w.define_type(mslo);

    ExtrasIds ids;
    ids.t_e1 = t_e1;
    w.spawn_building(t_hpad, 0, {4, 4});
    w.spawn_building(t_iron, 0, {2, 10});
    w.spawn_building(t_pdox, 0, {2, 14});
    w.spawn_building(t_mslo, 0, {2, 18});
    ids.heli = w.spawn(t_heli, 0, {6, 6});
    ids.apc = w.spawn(t_apc, 0, {12, 12});
    ids.layer = w.spawn(t_layer, 0, {20, 20});
    ids.tank = w.spawn(t_tank, 0, {24, 8});
    ids.enemy = w.spawn(t_tank, 1, {34, 34});
    return ids;
}


static uint64_t extras_hash(const World& w) {
    uint64_t h = 1469598103934665603ull;
    auto mix = [&h](int64_t v) {
        for (int b = 0; b < 8; ++b) { h ^= uint64_t((v >> (8 * b)) & 0xFF); h *= 1099511628211ull; }
    };
    mix(w.tick());
    mix(w.rand_peek());
    mix(int64_t(w.actor_count()));
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        mix(a.id); mix(a.type); mix(a.owner); mix(a.alive ? 1 : 0); mix(a.hp);
        mix(a.pos.x); mix(a.pos.y); mix(a.facing);
        mix(a.cloak_timer); mix(a.invulnerable_ticks); mix(a.chrono_return);
        mix(a.chrono_origin.x); mix(a.chrono_origin.y);
        mix(a.transport); mix(a.enter_target); mix(a.unload_ticks); mix(a.unloading ? 1 : 0);
        const Air& air = w.air(i);
        mix(air.state); mix(air.alt); mix(air.ammo); mix(air.reload); mix(air.base);
        mix(air.returning ? 1 : 0); mix(air.goal.x); mix(air.goal.y); mix(air.has_goal ? 1 : 0);
        mix(air.land_at_goal); mix(air.spin);
        mix(int64_t(w.cargo_of(i).size()));
        for (const int32_t id : w.cargo_of(i)) mix(id);
    }
    for (int32_t p = 0; p < MAX_PLAYERS; ++p) {
        mix(w.credits(p));
        for (int32_t k = 0; k < SP_COUNT; ++k) {
            int av = 0, rd = 0, pm = 0, ps = 0;
            w.support_power_state(p, k, av, rd, pm, ps);
            mix(av); mix(rd); mix(pm); mix(ps);
        }
    }
    return h;
}

static void test_save_load_extras() {
    World a;
    ExtrasIds ids = build_extras(a);


    a.order_attack(&ids.heli, 1, ids.enemy);
    std::vector<int32_t> troop;
    for (int i = 0; i < 3; ++i) troop.push_back(a.spawn(ids.t_e1, 0, {14 + i, 14}));
    a.order_enter_transport(troop.data(), troop.size(), ids.apc);
    a.order_lay_mine(&ids.layer, 1);
    for (int t = 0; t < 120; ++t) a.step();
    a.order_move(&ids.layer, 1, {20, 26});
    for (int t = 0; t < 200; ++t) a.step();

    for (int t = 0; t < 30; ++t) a.step();
    CHECK(a.activate_support_power(0, SP_IRON_CURTAIN, {24, 8}, {0, 0}));
    CHECK(a.activate_support_power(0, SP_CHRONOSHIFT, {24, 8}, {28, 8}));
    CHECK(a.activate_support_power(0, SP_NUKE, {34, 34}, {0, 0}));
    for (int t = 0; t < 20; ++t) a.step();

    const size_t hi = size_t(a.index_of(ids.heli));
    CHECK(a.air(hi).alt > 0);
    CHECK(a.cargo_weight(ids.apc) > 0);
    const size_t ti = size_t(a.index_of(ids.tank));
    CHECK(a.actor(ti).invulnerable_ticks > 0);
    CHECK(a.actor(ti).chrono_return > 0);

    std::vector<uint8_t> blob;
    CHECK(a.save(blob));
    const uint64_t before = extras_hash(a);

    World b;
    build_extras(b);
    for (int t = 0; t < 77; ++t) b.step();
    CHECK(b.load(blob));
    CHECK(extras_hash(b) == before);

    for (int t = 0; t < 700; ++t) { a.step(); b.step(); }
    const uint64_t ha = extras_hash(a), hb = extras_hash(b);
    std::printf("Spielstand mit Luft/Ladung/Minen/Superwaffen: %zu Bytes, Hash nach 700 Ticks %016llx %s\n",
                blob.size(), static_cast<unsigned long long>(ha), ha == hb ? "identisch" : "ABWEICHUNG");
    CHECK(ha == hb);
}


static uint64_t shots_hash(const World& w) {
    uint64_t h = 1469598103934665603ull;
    auto mix = [&h](int64_t v) {
        for (int b = 0; b < 8; ++b) { h ^= uint64_t((v >> (8 * b)) & 0xFF); h *= 1099511628211ull; }
    };
    mix(w.tick());
    std::vector<RenderSprite> rs;
    w.render_sprites(1024, rs);
    mix(int64_t(rs.size()));
    for (const RenderSprite& s : rs) { mix(s.x); mix(s.y); mix(s.alt); mix(s.weapon); mix(s.facing); }
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        mix(a.id); mix(a.hp); mix(a.pos.x); mix(a.pos.y);
    }
    return h;
}

static void test_save_missile() {
    World a;
    std::vector<uint8_t> cost(50 * 90, 1);
    a.set_map(50, 90, cost.data());
    Weapon wp;
    wp.range = 22 * CELL; wp.reload = 500; wp.damage = 5000; wp.spread = 400;
    wp.speed = 213; wp.proj_missile = true; wp.missile_turn_rate = 20; wp.missile_range_limit = 30 * CELL;
    wp.valid_targets = TT_GROUND_ACTOR | TT_VEHICLE;
    for (int i = 0; i < NUM_ARMOR; ++i) wp.versus[i] = 100;
    const int w_id = a.define_weapon(wp);
    UnitType launcher;
    launcher.speed = 1; launcher.turn_rate = 1024; launcher.hp = 100000; launcher.weapon = w_id;
    launcher.facing_tolerance = 1024; launcher.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_launcher = a.define_type(launcher);
    UnitType jeep;
    jeep.speed = 113; jeep.turn_rate = 1024; jeep.hp = 30000; jeep.hit_radius = 213;
    jeep.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_jeep = a.define_type(jeep);

    const int32_t jeep_id = a.spawn(t_jeep, 1, {30, 35});
    a.order_move(&jeep_id, 1, {30, 85}, 0);
    const int32_t launcher_id = a.spawn(t_launcher, 0, {10, 40});
    a.order_attack(&launcher_id, 1, jeep_id);


    for (int t = 0; t < 15; ++t) a.step();
    std::vector<RenderSprite> mid;
    a.render_sprites(1024, mid);
    bool in_flight = false;
    for (const RenderSprite& s : mid) if (s.weapon == w_id) in_flight = true;
    CHECK(in_flight);

    std::vector<uint8_t> blob;
    CHECK(a.save(blob));
    const uint64_t before = shots_hash(a);


    World b;
    b.set_map(50, 90, cost.data());
    b.define_weapon(wp);
    b.define_type(launcher);
    b.define_type(jeep);
    for (int t = 0; t < 9; ++t) b.step();
    CHECK(b.load(blob));
    CHECK(shots_hash(b) == before);

    for (int t = 0; t < 235; ++t) { a.step(); b.step(); }
    const uint64_t ha = shots_hash(a), hb = shots_hash(b);
    std::printf("Spielstand mit Lenkrakete im Flug: %zu Bytes, Hash nach 235 weiteren Ticks %016llx %s\n",
                blob.size(), static_cast<unsigned long long>(ha), ha == hb ? "identisch" : "ABWEICHUNG");
    CHECK(ha == hb);
    CHECK(a.actor(size_t(a.index_of(jeep_id))).hp < 30000);
}


static void test_save_size() {
    World w;
    std::vector<uint8_t> terrain(128 * 128, TER_CLEAR);
    for (int i = 0; i < 128 * 128; i += 17) terrain[size_t(i)] = TER_ROUGH;
    for (int i = 0; i < 128 * 128; i += 53) terrain[size_t(i)] = TER_WATER;
    w.set_terrain(128, 128, terrain.data());
    for (int y = 20; y < 40; ++y)
        for (int x = 20; x < 40; ++x) w.set_resource({x, y}, RES_ORE, 1 + (x * 7 + y * 3) % 12);
    UnitType tank;
    tank.speed = 72; tank.hp = 40000; tank.hit_radius = 426; tank.cost = 800;
    const int t_tank = w.define_type(tank);
    std::vector<int32_t> ids;
    for (int i = 0; i < 500; ++i) ids.push_back(w.spawn(t_tank, i % 4, {2 + i % 60, 2 + i / 60}));
    w.order_move(ids.data(), ids.size(), {100, 100});
    for (int t = 0; t < 200; ++t) w.step();
    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    std::printf("Spielstand 128x128 mit %zu Actors: %zu Bytes (%.2f MB, Ziel < 2 MB)\n",
                w.actor_count(), blob.size(), double(blob.size()) / (1024.0 * 1024.0));
    CHECK(blob.size() < 2u * 1024u * 1024u);
    World v2;
    v2.define_type(tank);
    CHECK(v2.load(blob));
    CHECK(v2.actor_count() == w.actor_count());
    CHECK(v2.tick() == w.tick());
}

static void bench() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    for (int i = 0; i < 64 * 64; i += 37) cost[i] = 0;
    w.set_map(64, 64, cost.data());
    const int tank = w.define_type({72, 20, false});
    std::vector<int32_t> ids;
    for (int i = 0; i < 500; ++i) ids.push_back(w.spawn(tank, 0, {2 + i % 25, 2 + i / 25}));
    w.order_move(ids.data(), ids.size(), {58, 58});
    const auto t0 = std::chrono::steady_clock::now();
    const int ticks = 1000;
    for (int t = 0; t < ticks; ++t) {
        if (t % 250 == 0) w.order_move(ids.data(), ids.size(), {(t / 250) % 2 ? 5 : 58, 58});
        w.step();
    }
    const auto us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();
    std::printf("Benchmark: 500 Einheiten, %d Ticks: %.1f µs/Tick (Budget bei 25 Hz: 40000 µs)\n",
                ticks, double(us) / ticks);
}


static void test_enter_activity() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.sprite_h = 2; powr.hp = 40000; powr.capturable = true; powr.instantly_repairable = true;
    powr.demolishable = true; powr.target_types = TT_STRUCTURE;
    UnitType eng; eng.speed = 54; eng.turn_rate = 1024; eng.infantry = true; eng.hp = 2500;
    eng.captures = true; eng.instantly_repairs = true; eng.locomotor = LOCO_FOOT;
    UnitType tanya; tanya.speed = 68; tanya.turn_rate = 1024; tanya.infantry = true; tanya.hp = 10000;
    tanya.demolition_delay = 45; tanya.locomotor = LOCO_FOOT;
    const int tp = w.define_type(powr), te = w.define_type(eng), tt = w.define_type(tanya);


    const int32_t own = w.spawn_building(tp, 0, {10, 10});
    w.set_health(own, 10000);
    const int32_t eng1 = w.spawn(te, 0, {4, 10});
    w.order_capture(&eng1, 1, own);
    for (int t = 0; t < 400 && w.actor(size_t(w.index_of(own))).hp < 40000; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(own))).hp == 40000);
    CHECK(w.index_of(eng1) < 0 || !w.actor(size_t(w.index_of(eng1))).alive);


    const int32_t foe = w.spawn_building(tp, 1, {24, 10});
    const int32_t t1 = w.spawn(tt, 0, {18, 10});
    w.order_capture(&t1, 1, foe);
    int ticks = 0;
    for (; ticks < 900 && w.index_of(foe) >= 0 && w.actor(size_t(w.index_of(foe))).alive; ++ticks) w.step();
    CHECK(!w.actor(size_t(w.index_of(foe))).alive);
    const int ti = w.index_of(t1);
    CHECK(ti >= 0 && w.actor(size_t(ti)).alive);
    CHECK(!w.actor(size_t(ti)).inside);
    std::printf("Enter: Pionier repariert voll, Tanya sprengt (%d Ticks) und überlebt\n", ticks);
}


static void test_infiltration() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    w.init_layers();
    UnitType silo; silo.building = true; silo.foot_w = 1; silo.foot_h = 1; silo.footprint = {1};
    silo.sprite_h = 1; silo.hp = 30000; silo.storage = 3000;
    silo.target_types = TT_STRUCTURE | TT_THIEF_INFILTRATE;
    silo.infil_cash = TT_THIEF_INFILTRATE; silo.infil_cash_percent = 50;
    UnitType pwr; pwr.building = true; pwr.foot_w = 2; pwr.foot_h = 2; pwr.footprint = {1, 1, 1, 1};
    pwr.sprite_h = 2; pwr.hp = 40000; pwr.power = 100;
    pwr.target_types = TT_STRUCTURE | TT_SPY_INFILTRATE;
    pwr.infil_power = TT_SPY_INFILTRATE; pwr.infil_power_duration = 500;
    UnitType barr; barr.building = true; barr.foot_w = 2; barr.foot_h = 2; barr.footprint = {1, 1, 1, 1};
    barr.sprite_h = 2; barr.hp = 60000; barr.target_types = TT_STRUCTURE | TT_SPY_INFILTRATE;
    barr.infil_support = TT_SPY_INFILTRATE; barr.infil_proxy = "barracks.upgraded";
    UnitType thf; thf.speed = 72; thf.turn_rate = 1024; thf.infantry = true; thf.hp = 8000;
    thf.locomotor = LOCO_FOOT; thf.cost = 500; thf.infiltrates = TT_THIEF_INFILTRATE;
    UnitType spy; spy.speed = 71; spy.turn_rate = 1024; spy.infantry = true; spy.hp = 2500;
    spy.locomotor = LOCO_FOOT; spy.cost = 500; spy.infiltrates = TT_SPY_INFILTRATE; spy.disguise = true;
    const int ts = w.define_type(silo), tp = w.define_type(pwr), tb = w.define_type(barr);
    const int tt = w.define_type(thf), tsp = w.define_type(spy);

    w.spawn_building(ts, 1, {12, 10});
    w.give_credits(1, 4000);
    const int32_t thief = w.spawn(tt, 0, {6, 10});
    const int64_t before = w.credits(0);
    w.order_capture(&thief, 1, w.actor(0).id);
    for (int t = 0; t < 600 && w.credits(0) == before; ++t) w.step();
    CHECK(w.credits(0) - before == 2000);
    CHECK(w.credits(1) == 2000);


    const int32_t pid = w.spawn_building(tp, 1, {24, 10});
    CHECK(w.power_provided(1) == 100);
    const int32_t spy1 = w.spawn(tsp, 0, {18, 10});
    w.order_capture(&spy1, 1, pid);
    for (int t = 0; t < 600 && w.power_provided(1) > 0; ++t) w.step();
    CHECK(w.power_provided(1) == 0);
    CHECK(w.power_outage(1) > 0);
    for (int t = 0; t < 520; ++t) w.step();
    CHECK(w.power_provided(1) == 100);


    const int32_t bid = w.spawn_building(tb, 1, {24, 24});
    CHECK(!w.has_prerequisite(0, "barracks.upgraded"));
    const int32_t spy2 = w.spawn(tsp, 0, {18, 24});
    w.order_capture(&spy2, 1, bid);
    for (int t = 0; t < 600 && !w.has_prerequisite(0, "barracks.upgraded"); ++t) w.step();
    CHECK(w.has_prerequisite(0, "barracks.upgraded"));


    UnitType rifle; rifle.speed = 56; rifle.turn_rate = 1024; rifle.infantry = true; rifle.hp = 5000;
    rifle.locomotor = LOCO_FOOT; rifle.cost = 100; rifle.queue_kind = QUEUE_INFANTRY;
    rifle.xp_levels = 3; rifle.xp_required[0] = 2; rifle.xp_required[1] = 4; rifle.xp_required[2] = 8;
    rifle.producible_prereqs = {"barracks.upgraded"}; rifle.producible_levels = 1;
    UnitType tent; tent.building = true; tent.foot_w = 2; tent.foot_h = 2; tent.footprint = {1, 1, 1, 1};
    tent.sprite_h = 2; tent.hp = 60000; tent.produces = 1u << QUEUE_INFANTRY;
    const int tr = w.define_type(rifle);
    w.spawn_building(w.define_type(tent), 0, {30, 10});
    w.give_credits(0, 5000);
    CHECK(w.queue_build(0, tr));
    int32_t rank = -1;
    for (int t = 0; t < 900 && rank < 0; ++t) {
        w.step();
        for (size_t k = 0; k < w.actor_count(); ++k)
            if (w.actor(k).alive && w.actor(k).type == tr) rank = w.level_of(k);
    }
    CHECK(rank == 1);


    UnitType dome; dome.building = true; dome.foot_w = 2; dome.foot_h = 2; dome.footprint = {1, 1, 1, 1};
    dome.sprite_h = 2; dome.hp = 100000; dome.target_types = TT_STRUCTURE | TT_SPY_INFILTRATE;
    dome.infil_explore = TT_SPY_INFILTRATE;
    const int32_t did = w.spawn_building(w.define_type(dome), 1, {6, 24});
    size_t unexplored = 0;
    for (uint8_t v : w.visibility(0)) unexplored += (v == 0) ? 1 : 0;
    CHECK(unexplored > 0);
    const int32_t spy3 = w.spawn(tsp, 0, {2, 24});
    w.order_capture(&spy3, 1, did);
    for (int t = 0; t < 600 && unexplored > 0; ++t) {
        w.step();
        unexplored = 0;
        for (uint8_t v : w.visibility(0)) unexplored += (v == 0) ? 1 : 0;
    }
    CHECK(unexplored == 0);
    std::printf("Infiltration: Dieb 2000 Credits, Stromausfall 500 Ticks, Veteranen-Rang %d bei der nächsten Einheit, Karte aufgedeckt\n", rank);
}


static void test_disguise() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    Weapon rifle; rifle.range = 5 * CELL; rifle.reload = 20; rifle.damage = 500;
    rifle.spread = 128; rifle.valid_targets = TT_INFANTRY;
    const int wr = w.define_weapon(rifle);
    UnitType e1; e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000;
    e1.locomotor = LOCO_FOOT; e1.weapon = wr; e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    e1.auto_target_mask = TT_INFANTRY;
    UnitType dog = e1; dog.ignores_disguise = true;
    UnitType spy = e1; spy.disguise = true; spy.weapon = -1; spy.no_auto_target = true;
    const int te1 = w.define_type(e1), tdog = w.define_type(dog), tspy = w.define_type(spy);


    const int32_t guard = w.spawn(te1, 1, {20, 20});
    const int32_t mask = w.spawn(te1, 1, {21, 20});
    const int32_t s = w.spawn(tspy, 0, {22, 20});
    w.set_stance(guard, STANCE_ATTACK_ANYTHING);
    CHECK(w.order_disguise(s, mask));
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(s))).alive);
    CHECK(w.actor(size_t(w.index_of(s))).hp == 2500 || w.actor(size_t(w.index_of(s))).hp == 5000);


    const int32_t d = w.spawn(tdog, 1, {24, 20});
    w.set_stance(d, STANCE_ATTACK_ANYTHING);
    int t = 0;
    for (; t < 600 && w.actor(size_t(w.index_of(s))).alive; ++t) w.step();
    CHECK(!w.actor(size_t(w.index_of(s))).alive);
    std::printf("Verkleidung: Schütze ignoriert den Spion, Hund tötet ihn nach %d Ticks\n", t);
}


static constexpr int SEA_W = 40, SEA_H = 30, BEACH_X = 14;

struct NavalIds {
    int t_tank = -1, t_pt = -1, t_ss = -1, t_dd = -1, t_lst = -1, t_e1 = -1;
    int t_yard = -1, t_fact = -1;
    int w_torp = -1, w_depth = -1, w_gun = -1;
};

static NavalIds build_naval(World& w) {
    NavalIds id;
    std::vector<uint8_t> terrain(size_t(SEA_W * SEA_H), TER_CLEAR);
    for (int y = 0; y < SEA_H; ++y)
        for (int x = 0; x < SEA_W; ++x)
            terrain[size_t(y * SEA_W + x)] = uint8_t(x < BEACH_X ? TER_CLEAR : (x == BEACH_X ? TER_BEACH : TER_WATER));
    w.set_terrain(SEA_W, SEA_H, terrain.data());


    Weapon torp; torp.range = 9 * CELL; torp.reload = 100; torp.damage = 18000; torp.spread = 426;
    for (int i = 0; i < NUM_ARMOR; ++i) torp.versus[i] = 100;
    torp.valid_targets = TT_WATER_ACTOR | TT_UNDERWATER;
    id.w_torp = w.define_weapon(torp);

    Weapon depth; depth.range = 5 * CELL; depth.reload = 60; depth.damage = 6000; depth.spread = 128;
    for (int i = 0; i < NUM_ARMOR; ++i) depth.versus[i] = 100;
    depth.valid_targets = TT_UNDERWATER;
    id.w_depth = w.define_weapon(depth);

    Weapon gun; gun.range = 7 * CELL; gun.reload = 60; gun.damage = 2500; gun.spread = 256;
    for (int i = 0; i < NUM_ARMOR; ++i) gun.versus[i] = 100;
    gun.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_SHIP;
    gun.invalid_targets = TT_UNDERWATER;
    id.w_gun = w.define_weapon(gun);

    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 10000; tank.locomotor = LOCO_TRACKED;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tank.weapon = id.w_gun;
    id.t_tank = w.define_type(tank);
    UnitType e1; e1.speed = 42; e1.turn_rate = 1024; e1.hp = 5000; e1.infantry = true; e1.locomotor = LOCO_FOOT;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY; e1.passenger_weight = 1; e1.passenger_type = TT_INFANTRY;
    id.t_e1 = w.define_type(e1);


    UnitType pt; pt.speed = 142; pt.turn_rate = 28; pt.hp = 20000; pt.armor = ARMOR_HEAVY;
    pt.locomotor = LOCO_NAVAL; pt.weapon = id.w_gun; pt.weapon_secondary = id.w_depth;
    pt.target_types = TT_WATER_ACTOR | TT_SHIP; pt.turreted = true;
    pt.detect_range = 4 * CELL; pt.detect_types = DETECT_UNDERWATER;
    pt.auto_target_mask = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_SHIP | TT_UNDERWATER;
    id.t_pt = w.define_type(pt);

    UnitType dd = pt; dd.speed = 92; dd.hp = 40000; dd.detect_range = 4 * CELL;
    id.t_dd = w.define_type(dd);

    UnitType ss; ss.speed = 78; ss.turn_rate = 20; ss.hp = 25000; ss.armor = ARMOR_LIGHT;
    ss.locomotor = LOCO_NAVAL; ss.weapon = id.w_torp;
    ss.target_types = TT_WATER_ACTOR | TT_SHIP | TT_SUBMARINE;
    ss.target_types_underwater = TT_UNDERWATER | TT_SUBMARINE;
    ss.cloak = true; ss.cloak_initial_delay = 0; ss.cloak_delay = 50;
    ss.cloak_types = DETECT_UNDERWATER; ss.uncloak_on = UNCLOAK_ATTACK;
    ss.auto_target_mask = TT_WATER_ACTOR | TT_UNDERWATER;
    id.t_ss = w.define_type(ss);

    UnitType lst; lst.speed = 115; lst.turn_rate = 28; lst.hp = 40000; lst.armor = ARMOR_HEAVY;
    lst.locomotor = LOCO_LCRAFT; lst.cargo_max_weight = 5; lst.target_types = TT_WATER_ACTOR | TT_SHIP;
    id.t_lst = w.define_type(lst);


    UnitType yard; yard.building = true; yard.foot_w = 3; yard.foot_h = 3;
    yard.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1}; yard.build_block = yard.footprint;
    yard.hp = 100000; yard.terrain_mask = 1u << TER_WATER; yard.adjacent = 8;
    yard.produces = 1u << QUEUE_SHIP; yard.exit_dx = 0; yard.exit_dy = 3; yard.rally_dx = 0; yard.rally_dy = 4;
    yard.gives_buildable_area = false; yard.repairs_units = true; yard.cost = 1000;
    yard.queue_kind = QUEUE_BUILDING; yard.sellable = true;
    yard.target_types = TT_WATER_ACTOR | TT_STRUCTURE;
    id.t_yard = w.define_type(yard);

    UnitType fact; fact.building = true; fact.foot_w = 3; fact.foot_h = 3;
    fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1}; fact.build_block = fact.footprint;
    fact.hp = 100000; fact.base_provider = true; fact.base_range = 20 * CELL;
    fact.produces = 1u << QUEUE_BUILDING;
    id.t_fact = w.define_type(fact);
    return id;
}

static void test_naval() {
    World w;
    const NavalIds id = build_naval(w);
    w.set_alliance(0, 1, false);


    CHECK(w.map().passable({5, 5}, MC_LAND) && !w.map().passable({5, 5}, MC_NAVAL));
    CHECK(!w.map().passable({25, 5}, MC_LAND) && w.map().passable({25, 5}, MC_NAVAL));
    CHECK(w.map().passable({BEACH_X, 5}, MC_LAND) && !w.map().passable({BEACH_X, 5}, MC_NAVAL));
    CHECK(w.map().passable({BEACH_X, 5}, MC_LCRAFT));


    const int32_t boat = w.spawn(id.t_pt, 0, {30, 5});
    const size_t bi = size_t(w.index_of(boat));
    w.order_move(&boat, 1, {5, 5});
    for (int t = 0; t < 600; ++t) w.step();
    CHECK(w.map().terrain(w.mobile(bi).cell) == TER_WATER);
    CHECK(w.mobile(bi).cell.x > BEACH_X);


    const int32_t tank = w.spawn(id.t_tank, 0, {5, 20});
    const size_t tk = size_t(w.index_of(tank));
    w.order_move(&tank, 1, {30, 20});
    for (int t = 0; t < 600; ++t) w.step();
    CHECK(w.map().terrain(w.mobile(tk).cell) != TER_WATER);
    CHECK(w.mobile(tk).cell.x <= BEACH_X);


    w.spawn_building(id.t_fact, 0, {10, 10});
    CHECK(!w.can_place(0, id.t_yard, {8, 10}, nullptr));
    CHECK(w.can_place(0, id.t_yard, {16, 10}, nullptr));
    const int32_t yard = w.spawn_building(id.t_yard, 0, {16, 10});
    CHECK(yard > 0);

    CHECK(!w.map().passable({17, 11}, MC_NAVAL));


    w.give_credits(0, 10000);
    CHECK(w.queue_build(0, id.t_pt) == false);
    const int32_t boat2 = w.spawn(id.t_pt, 0, {16, 13});
    CHECK(w.map().terrain(w.mobile(size_t(w.index_of(boat2))).cell) == TER_WATER);

    std::printf("Marine: Schiff auf Wasser (%d,%d), Panzer an Land (%d,%d), Werft auf Wasser\n",
                w.mobile(bi).cell.x, w.mobile(bi).cell.y, w.mobile(tk).cell.x, w.mobile(tk).cell.y);
}


static void test_submarine() {
    World w;
    const NavalIds id = build_naval(w);
    w.set_alliance(0, 1, false);
    const int32_t sub = w.spawn(id.t_ss, 1, {30, 15});
    const size_t si = size_t(w.index_of(sub));
    const int32_t boat = w.spawn(id.t_pt, 0, {20, 15});
    const size_t bi = size_t(w.index_of(boat));
    for (int t = 0; t < 5; ++t) w.step();
    CHECK(w.cloaked(si));
    CHECK(!w.detected_by(0, si));

    for (int t = 0; t < 100; ++t) w.step();
    CHECK(w.actor(si).hp == 25000);


    const int32_t dd = w.spawn(id.t_dd, 0, {26, 15});
    const size_t di = size_t(w.index_of(dd));
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.detected_by(0, si));
    CHECK(w.actor(si).hp < 25000);

    CHECK(w.actor(di).hp < 40000 || w.actor(bi).hp < 20000);
    std::printf("U-Boot: getarnt bis der Zerstörer heran ist, danach %d HP (Zerstörer %d HP)\n",
                w.actor(si).hp, w.actor(di).hp);
}


static void test_landing_craft() {
    World w;
    const NavalIds id = build_naval(w);
    const int32_t lst = w.spawn(id.t_lst, 0, {25, 10});
    std::vector<int32_t> troop;
    for (int i = 0; i < 3; ++i) troop.push_back(w.spawn(id.t_e1, 0, {5, 10 + i}));
    for (int32_t p : troop) CHECK(w.load_passenger(lst, p));
    CHECK(w.cargo_weight(lst) == 3);
    w.order_move(&lst, 1, {BEACH_X, 10});
    for (int t = 0; t < 600; ++t) w.step();
    const size_t li = size_t(w.index_of(lst));
    CHECK(w.mobile(li).cell.x <= BEACH_X + 1);
    w.order_unload(&lst, 1);
    for (int t = 0; t < 300; ++t) w.step();
    CHECK(w.cargo_weight(lst) == 0);
    int on_land = 0;
    for (int32_t p : troop) {
        const int pi = w.index_of(p);
        if (pi >= 0 && w.actor(size_t(pi)).alive && w.map().terrain(w.mobile(size_t(pi)).cell) != TER_WATER) ++on_land;
    }
    CHECK(on_land == 3);
    std::printf("Landungsboot: bei (%d,%d) gelandet, %d von 3 Passagieren an Land\n",
                w.mobile(li).cell.x, w.mobile(li).cell.y, on_land);
}


static void test_lst_full_cycle() {
    World w;
    const NavalIds id = build_naval(w);


    const int32_t lst = w.spawn(id.t_lst, 0, {30, 10});
    const size_t li = size_t(w.index_of(lst));
    std::vector<int32_t> troop;
    for (int i = 0; i < 3; ++i) troop.push_back(w.spawn(id.t_e1, 0, {2, 10 + i}));
    w.order_enter_transport(troop.data(), troop.size(), lst);
    w.order_move(&lst, 1, {BEACH_X, 10});
    for (int t = 0; t < 900; ++t) w.step();
    CHECK(w.cargo_weight(lst) == 3);
    for (const int32_t p : troop) CHECK(w.transport_of(p) == lst);
    std::printf("Landungsboot: %d/3 Passagiere über order_enter_transport eingestiegen, Boot bei (%d,%d)\n",
                w.cargo_weight(lst), w.mobile(li).cell.x, w.mobile(li).cell.y);


    w.order_move(&lst, 1, {30, 10});
    for (int t = 0; t < 400; ++t) w.step();
    CHECK(w.map().terrain(w.mobile(li).cell) == TER_WATER && w.mobile(li).cell.x > BEACH_X + 1);
    w.order_unload(&lst, 1);
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.cargo_weight(lst) == 3);
    std::printf("Landungsboot: Entladebefehl auf offener See abgewiesen, weiter %d/3 an Bord\n", w.cargo_weight(lst));


    w.order_move(&lst, 1, {BEACH_X, 10});
    for (int t = 0; t < 600; ++t) w.step();
    w.order_unload(&lst, 1);
    for (int t = 0; t < 300; ++t) w.step();
    CHECK(w.cargo_weight(lst) == 0);
    int on_land = 0;
    for (const int32_t p : troop) {
        const int pi = w.index_of(p);
        if (pi >= 0 && w.actor(size_t(pi)).alive && w.actor(size_t(pi)).transport < 0
            && w.map().terrain(w.mobile(size_t(pi)).cell) != TER_WATER) ++on_land;
    }
    CHECK(on_land == 3);
    std::printf("Landungsboot: %d/3 Passagiere an Land entladen und steuerbar\n", on_land);


    w.order_enter_transport(troop.data(), troop.size(), lst);
    for (int t = 0; t < 900; ++t) w.step();
    CHECK(w.cargo_weight(lst) == 3);


    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    const uint64_t before = state_hash(w);
    World reloaded;
    build_naval(reloaded);
    CHECK(reloaded.load(blob));
    CHECK(state_hash(reloaded) == before);
    CHECK(reloaded.cargo_weight(lst) == 3);
    for (const int32_t p : troop) CHECK(reloaded.transport_of(p) == lst);
    std::printf("Landungsboot: Spielstand mit 3 Passagieren an Bord identisch nach dem Laden\n");


    w.destroy(lst);
    int dead = 0;
    for (const int32_t p : troop) {
        const int pi = w.index_of(p);
        if (pi >= 0 && !w.actor(size_t(pi)).alive) ++dead;
    }
    CHECK(dead == 3);
    std::printf("Landungsboot: mit Ladung zerstört, %d/3 Passagiere gestorben\n", dead);
}


static void test_save_naval() {
    World a;
    const NavalIds id = build_naval(a);
    a.set_alliance(0, 1, false);
    a.spawn_building(a.type_count() > 0 ? id.t_fact : 0, 0, {10, 10});
    a.spawn_building(id.t_yard, 0, {16, 10});
    const int32_t boat = a.spawn(id.t_pt, 0, {30, 5});
    a.spawn(id.t_ss, 1, {32, 20});
    a.spawn(id.t_lst, 0, {25, 25});
    a.order_move(&boat, 1, {35, 25});
    for (int t = 0; t < 120; ++t) a.step();

    std::vector<uint8_t> blob;
    CHECK(a.save(blob));
    const uint64_t before = state_hash(a);
    World b;
    build_naval(b);
    for (int t = 0; t < 37; ++t) b.step();
    CHECK(b.load(blob));
    CHECK(state_hash(b) == before);

    CHECK(b.map().passable({30, 5}, MC_NAVAL));
    CHECK(!b.map().passable({17, 11}, MC_NAVAL));
    for (int t = 0; t < 400; ++t) { a.step(); b.step(); }
    const uint64_t ha = state_hash(a), hb = state_hash(b);
    std::printf("Spielstand mit Schiffen: %zu Bytes, Hash nach 400 Ticks %016llx %s\n",
                blob.size(), static_cast<unsigned long long>(ha), ha == hb ? "identisch" : "ABWEICHUNG");
    CHECK(ha == hb);
}


static void test_gps() {
    World w;
    std::vector<uint8_t> terrain(30 * 30, TER_CLEAR);
    w.set_terrain(30, 30, terrain.data());
    w.set_alliance(0, 2, true);
    UnitType atek; atek.building = true; atek.foot_w = 2; atek.foot_h = 2;
    atek.footprint = {1, 1, 1, 1}; atek.hp = 60000;
    atek.support_power = SP_GPS; atek.sp_charge = 20; atek.sp_reveal_delay = 15; atek.sp_one_shot = true;
    atek.sp_notify_launch = NOTIFY_SATELLITE_LAUNCHED;
    const int t_atek = w.define_type(atek);
    const int32_t bld = w.spawn_building(t_atek, 0, {4, 4});
    const size_t bi = size_t(w.index_of(bld));
    w.update_visibility(0);
    CHECK(w.visibility(0)[size_t(28 * 30 + 28)] == 0);

    int av = 0, rd = 0, pm = 0, ps = 0;
    w.support_power_state(0, SP_GPS, av, rd, pm, ps);
    CHECK(av == 1 && rd == 0);
    for (int t = 0; t < 21; ++t) w.step();

    std::vector<int32_t> notes; w.drain_notifications(0, notes);
    CHECK(std::find(notes.begin(), notes.end(), NOTIFY_SATELLITE_LAUNCHED) != notes.end());
    CHECK(w.actor(bi).active_ticks > 0);
    CHECK(w.visibility(0)[size_t(28 * 30 + 28)] == 0);
    for (int t = 0; t < 20; ++t) w.step();
    CHECK(w.visibility(0)[size_t(28 * 30 + 28)] != 0);
    CHECK(w.visibility(2)[size_t(28 * 30 + 28)] != 0);
    CHECK(w.visibility(1)[size_t(28 * 30 + 28)] == 0);

    w.support_power_state(0, SP_GPS, av, rd, pm, ps);
    CHECK(av == 0);
    for (int t = 0; t < 60; ++t) w.step();
    w.support_power_state(0, SP_GPS, av, rd, pm, ps);
    CHECK(av == 0);
    std::printf("GPS: Satellit gestartet, Karte für Besitzer und Verbündete erkundet, OneShot\n");
}

int main() {
    test_math();
    test_flow_field();
    test_diagonal_only_reachable();
    test_movement_and_determinism();
    test_combat();
    test_economy();
    test_production();
    test_buildings_block_movement();
    test_barrels();
    test_bot();
    test_bot_difficulty();
    test_defense_depot_victory();
    test_deploy_faction();
    test_capture();
    test_enter_activity();
    test_infiltration();
    test_disguise();
    test_set_owner_health();
    test_api_bridge();
    test_bridge_terrain();
    test_teleport_harvester_claim();
    test_sell_cost();
    test_field_generation();
    test_field_generation_mixed();
    test_crush();
    test_subcells();
    test_crates();
    test_veterancy();
    test_unconditional_healing();
    test_tesla();
    test_weapon_rules();
    test_missile_projectile();
    test_missile_range_limit();
    test_armaments();
    test_dog_leap();
    test_dog_leap_miss();
    test_dog_leap_save_load();
    test_economy_rules();
    test_bot_recovery();
    test_bot_intervals();
    test_bot_harvester_redirect();
    test_bot_expansion();
    test_bot_refinery_reachable();
    test_order_deliver();
    test_bot_squad_advance();
    test_bot_vehicle_timing();
    test_no_backwards_movement();
    test_cargo();
    test_aircraft();
    test_air_production();
    test_new_options();
    test_paradrop();
    test_dual_armament();
    test_cash_trickler();
    test_mines_and_cloak();
    test_damage_sounds();
    test_support_powers();
    test_nuke_warhead_chain();
    test_determinism_hash();
    test_save_load();
    test_save_load_extras();
    test_save_missile();
    test_save_nuke_chain();
    test_save_size();
    test_naval();
    test_submarine();
    test_landing_craft();
    test_lst_full_cycle();
    test_save_naval();
    test_gps();
    bench();
    if (failures == 0) std::printf("OK — alle Tests bestanden (sim v%s)\n", version());
    return failures == 0 ? 0 : 1;
}
