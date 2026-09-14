
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
            std::fflush(stdout);                                                    \
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


static void test_barrels_owned_by_player() {
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
    cluster.versus[ARMOR_NONE] = 120; cluster.versus[ARMOR_WOOD] = 20;
    cluster.versus[ARMOR_LIGHT] = 50; cluster.versus[ARMOR_HEAVY] = 25;
    cluster.versus[ARMOR_CONCRETE] = 10;
    cluster.hits_allies = true;
    const int32_t w_cluster = w.define_weapon(cluster);

    Weapon explode;
    explode.damage = 0; explode.spread = 325; explode.delay = 5;
    explode.cluster_weapon = w_cluster; explode.cluster_count = 4;
    const int8_t cdx[4] = {0, -1, 1, 0}, cdy[4] = {-1, 0, 0, 1};
    for (int i = 0; i < 4; ++i) { explode.cluster_dx[i] = cdx[i]; explode.cluster_dy[i] = cdy[i]; }
    explode.hits_allies = true;
    const int32_t w_explode = w.define_weapon(explode);

    Weapon rifle;
    rifle.damage = 1500; rifle.spread = 43; rifle.range = 5 * CELL; rifle.reload = 20;
    const int32_t w_rifle = w.define_weapon(rifle);

    UnitType barl;
    barl.building = true; barl.foot_w = 1; barl.foot_h = 1; barl.footprint = {1}; barl.sprite_h = 1;
    barl.hp = 1000; barl.targetable = true; barl.death_weapon = w_explode;
    barl.target_types = TT_GROUND_ACTOR;
    UnitType e1;
    e1.speed = 42; e1.turn_rate = 1024; e1.hp = 5000; e1.infantry = true; e1.locomotor = LOCO_FOOT;
    e1.targetable = true; e1.weapon = w_rifle; e1.no_auto_target = true;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    UnitType hut;
    hut.building = true; hut.foot_w = 1; hut.foot_h = 1; hut.footprint = {1}; hut.sprite_h = 1;
    hut.hp = 40000; hut.armor = ARMOR_WOOD; hut.targetable = true; hut.target_types = TT_GROUND_ACTOR;
    const int t_barl = w.define_type(barl), t_e1 = w.define_type(e1), t_hut = w.define_type(hut);

    w.set_neutral_player(2);

    const int32_t b1 = w.spawn_building(t_barl, 1, {10, 10});
    const int32_t b2 = w.spawn_building(t_barl, 1, {11, 10});
    const int32_t guard = w.spawn(t_e1, 1, {10, 11});
    const int32_t hut_id = w.spawn_building(t_hut, 1, {10, 9});
    const int32_t tanya = w.spawn(t_e1, 0, {10, 15});
    const int32_t hut_hp0 = w.actor(size_t(w.index_of(hut_id))).hp;
    w.order_attack(&tanya, 1, b1);
    for (int t = 0; t < 400 && w.actor(size_t(w.index_of(b1))).alive; ++t) w.step();
    CHECK(!w.actor(size_t(w.index_of(b1))).alive);
    for (int t = 0; t < 100; ++t) w.step();
    const bool neighbour_gone = !w.actor(size_t(w.index_of(b2))).alive;
    const bool guard_dead = !w.actor(size_t(w.index_of(guard))).alive;
    const int32_t hut_dmg = hut_hp0 - w.actor(size_t(w.index_of(hut_id))).hp;
    std::printf("Fässer (Partei statt Neutral): Nachbarfass weg %d, Wachposten tot %d, Hüttenschaden %d, Schütze lebt %d\n",
                int(neighbour_gone), int(guard_dead), hut_dmg,
                int(w.actor(size_t(w.index_of(tanya))).alive));
    CHECK(neighbour_gone);
    CHECK(guard_dead);
    CHECK(hut_dmg > 0);
    CHECK(w.actor(size_t(w.index_of(tanya))).alive);


    World v;
    std::vector<uint8_t> vcost(30 * 30, 1);
    v.set_map(30, 30, vcost.data());
    Weapon v_cluster = cluster; v_cluster.hits_allies = false;
    const int32_t vw_cluster = v.define_weapon(v_cluster);
    Weapon v_explode = explode; v_explode.hits_allies = false; v_explode.cluster_weapon = vw_cluster;
    const int32_t vw_explode = v.define_weapon(v_explode);
    const int32_t vw_rifle = v.define_weapon(rifle);
    UnitType v_barl = barl; v_barl.death_weapon = vw_explode;
    UnitType v_e1t = e1; v_e1t.weapon = vw_rifle;
    const int v_t_barl = v.define_type(v_barl), v_t_e1 = v.define_type(v_e1t);
    v.set_neutral_player(2);
    const int32_t vb1 = v.spawn_building(v_t_barl, 1, {10, 10});
    const int32_t vb2 = v.spawn_building(v_t_barl, 1, {11, 10});
    const int32_t v_guard = v.spawn(v_t_e1, 1, {10, 11});
    const int32_t v_tanya = v.spawn(v_t_e1, 0, {10, 15});
    v.order_attack(&v_tanya, 1, vb1);
    for (int t = 0; t < 400 && v.actor(size_t(v.index_of(vb1))).alive; ++t) v.step();
    for (int t = 0; t < 100; ++t) v.step();
    CHECK(v.actor(size_t(v.index_of(vb2))).alive);
    CHECK(v.actor(size_t(v.index_of(v_guard))).alive);
    std::printf("Fässer: ohne hits_allies bleibt die eigene Partei verschont (Nachbarfass %d, Wachposten %d)\n",
                int(v.actor(size_t(v.index_of(vb2))).alive), int(v.actor(size_t(v.index_of(v_guard))).alive));
}


static void test_auto_target_tanya() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());

    Weapon colt45;
    colt45.damage = 10000; colt45.spread = 42; colt45.range = 7 * CELL; colt45.reload = 7;
    colt45.valid_targets = TT_INFANTRY | TT_BARREL;
    const int32_t w_colt = w.define_weapon(colt45);

    UnitType e7;
    e7.speed = 68; e7.turn_rate = 1024; e7.hp = 10000; e7.infantry = true; e7.locomotor = LOCO_FOOT;
    e7.targetable = true; e7.weapon = w_colt;
    e7.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    e7.auto_target_mask = TT_INFANTRY | TT_VEHICLE | TT_SHIP | TT_UNDERWATER | TT_DEFENSE | TT_MINE;
    UnitType e7_noauto = e7;
    e7_noauto.no_auto_target = true;
    UnitType e1 = e7; e1.auto_target_mask = 0; e1.no_auto_target = true;
    e1.hp = 5000; e1.weapon = -1;
    UnitType tnk;
    tnk.speed = 72; tnk.turn_rate = 1024; tnk.hp = 40000; tnk.armor = ARMOR_HEAVY;
    tnk.targetable = true; tnk.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tnk.weapon = -1;
    const int t_e7 = w.define_type(e7), t_noauto = w.define_type(e7_noauto);
    const int t_e1 = w.define_type(e1), t_tnk = w.define_type(tnk);


    const int32_t tanya = w.spawn(t_e7, 0, {10, 10});
    const int32_t foe = w.spawn(t_e1, 1, {14, 10});
    const int32_t foe_hp0 = w.actor(size_t(w.index_of(foe))).hp;
    int fired_at = -1;
    for (int t = 0; t < 40; ++t) {
        w.step();
        if (fired_at < 0 && w.actor(size_t(w.index_of(foe))).hp < foe_hp0) fired_at = t;
    }
    CHECK(fired_at >= 0);
    CHECK(fired_at <= 20);
    CHECK(w.stance(tanya) == STANCE_DEFEND);


    World v;
    std::vector<uint8_t> vcost(30 * 30, 1);
    v.set_map(30, 30, vcost.data());
    const int32_t vw_colt = v.define_weapon(colt45);
    UnitType v_e7 = e7; v_e7.weapon = vw_colt;
    const int v_t_e7 = v.define_type(v_e7), v_t_tnk = v.define_type(tnk);
    v.spawn(v_t_e7, 0, {10, 10});
    const int32_t vfoe = v.spawn(v_t_tnk, 1, {14, 10});
    const int32_t vfoe_hp0 = v.actor(size_t(v.index_of(vfoe))).hp;
    for (int t = 0; t < 60; ++t) v.step();
    CHECK(v.actor(size_t(v.index_of(vfoe))).hp == vfoe_hp0);


    World c;
    std::vector<uint8_t> ccost(30 * 30, 1);
    c.set_map(30, 30, ccost.data());
    const int32_t cw_colt = c.define_weapon(colt45);
    UnitType c_e7 = e7_noauto; c_e7.weapon = cw_colt;
    UnitType c_e1 = e1;
    const int c_t_e7 = c.define_type(c_e7), c_t_e1 = c.define_type(c_e1);
    const int32_t ctanya = c.spawn(c_t_e7, 0, {10, 10});
    const int32_t cfoe = c.spawn(c_t_e1, 1, {14, 10});
    const int32_t cfoe_hp0 = c.actor(size_t(c.index_of(cfoe))).hp;
    for (int t = 0; t < 60; ++t) c.step();
    const bool idle_ok = c.actor(size_t(c.index_of(cfoe))).hp == cfoe_hp0;
    CHECK(idle_ok);
    CHECK(c.stance(ctanya) == STANCE_HOLD_FIRE);
    c.order_attack(&ctanya, 1, cfoe);
    for (int t = 0; t < 60 && c.actor(size_t(c.index_of(cfoe))).alive; ++t) c.step();
    CHECK(!c.actor(size_t(c.index_of(cfoe))).alive);
    std::printf("Tanya: Autofeuer auf Infanterie nach %d Ticks, kein Autofeuer auf Fahrzeuge, "
                "E7.noautotarget wartet auf Befehl (%d) und trifft dann\n", fired_at, int(idle_ok));
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


static void test_bot_naval_alarm() {


    auto run = [](int ship_x, bool& protection_vs_ship, int32_t& reserve, int32_t& naval_target,
                  int32_t& alarm_id, bool& moved_to_shore, int32_t& enemy_out) {
        World w;
        const int size = 64;
        std::vector<uint8_t> cost(size_t(size) * size_t(size), 1);
        std::vector<uint8_t> terrain(size_t(size) * size_t(size), uint8_t(TER_CLEAR));
        for (int y = 0; y < size; ++y) {
            for (int x = 24; x < 48; ++x) {
                cost[size_t(y * size + x)] = 0;
                terrain[size_t(y * size + x)] = uint8_t(TER_WATER);
            }
        }
        w.set_map(size, size, cost.data());
        w.set_terrain(size, size, terrain.data());
        w.init_layers();
        Weapon gun; gun.range = 6 * CELL; gun.reload = 40; gun.damage = 500; gun.speed = 0;
        gun.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_INFANTRY | TT_WATER_ACTOR;
        const int w_gun = w.define_weapon(gun);
        UnitType fact;
        fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
        fact.build_block = fact.footprint; fact.sprite_h = 3; fact.hp = 150000; fact.cost = 2500;
        fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true; fact.provides = {"fact"};
        fact.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
        const int t_fact = w.define_type(fact);
        UnitType powr;
        powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
        powr.build_block = powr.footprint; powr.sprite_h = 2; powr.hp = 400000; powr.power = 300;
        powr.cost = 300; powr.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
        const int t_powr = w.define_type(powr);
        UnitType tank;
        tank.speed = 85; tank.turn_rate = 20; tank.hp = 40000; tank.cost = 1000; tank.weapon = w_gun;
        tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tank.auto_target_mask = TT_GROUND_ACTOR | TT_VEHICLE | TT_INFANTRY | TT_WATER_ACTOR;
        const int t_tank = w.define_type(tank);
        UnitType dd;
        dd.speed = 56; dd.turn_rate = 20; dd.hp = 60000; dd.cost = 1000; dd.weapon = w_gun;
        dd.locomotor = LOCO_NAVAL; dd.hit_radius = 426;
        dd.auto_target_mask = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_WATER_ACTOR;
        dd.target_types = TT_WATER_ACTOR | TT_VEHICLE;
        const int t_dd = w.define_type(dd);
        Weapon big = gun; big.range = 16 * CELL;
        const int w_big = w.define_weapon(big);
        UnitType dd_far = dd; dd_far.weapon = w_big;
        const int t_dd_far = w.define_type(dd_far);

        w.spawn_building(t_fact, 0, {8, 30});
        const int32_t powr_id = w.spawn_building(t_powr, 0, {20, 30});
        std::vector<int32_t> tanks;
        for (int k = 0; k < 3; ++k) tanks.push_back(w.spawn(t_tank, 0, {10 + k, 36}));
        w.spawn(t_dd, 0, {30, 50});
        const int32_t enemy_ship = w.spawn(ship_x > 30 ? t_dd_far : t_dd, 1, {ship_x, 31});
        enemy_out = enemy_ship;
        w.set_enemy(0, 1, true);
        w.set_enemy(1, 0, true);
        w.give_credits(0, 5000);
        BotParams p;
        p.first_attack_tick = 100000;
        w.enable_bot(0, p);
        w.order_attack(&enemy_ship, 1, powr_id, false);

        protection_vs_ship = false; naval_target = -1; reserve = 0; moved_to_shore = false;
        for (int t = 0; t < 600; ++t) {
            w.step();
            const BotState& b = w.bot_state(0);
            for (const BotSquad& s : b.squads) {
                if (s.type == BotSquad::PROTECTION && !s.units.empty() && s.target == enemy_ship) protection_vs_ship = true;
                if (s.type == BotSquad::NAVAL && !s.units.empty()) naval_target = s.target;
            }
            reserve = int32_t(b.idle_base_units.size());
            for (int32_t id : tanks) {
                const int i = w.index_of(id);
                if (i >= 0 && w.mobile(size_t(i)).cell.x >= 18) moved_to_shore = true;
            }
        }
        alarm_id = w.bot_state(0).naval_alarm_id;
    };
    bool prot = false, shore = false;
    int32_t reserve = 0, naval = -1, alarm = -1, enemy = -1;

    run(26, prot, reserve, naval, alarm, shore, enemy);
    std::printf("Marine-Alarm (a) Schiff am Ufer: Schutztrupp=%s, ans Ufer gefahren=%s, Marine-Ziel=%d (Angreifer %d), Alarm=%d\n",
                prot ? "ja" : "nein", shore ? "ja" : "nein", naval, enemy, alarm);
    CHECK(prot);
    CHECK(shore);
    CHECK(alarm == enemy);
    CHECK(naval == enemy);


    run(36, prot, reserve, naval, alarm, shore, enemy);
    std::printf("Marine-Alarm (b) Schiff fern: Schutztrupp=%s, Reserve=%d, ans Ufer gefahren=%s, Marine-Ziel=%d (Angreifer %d)\n",
                prot ? "ja" : "nein", reserve, shore ? "ja" : "nein", naval, enemy);
    CHECK(!prot);
    CHECK(reserve == 3);
    CHECK(!shore);
    CHECK(naval == enemy);
}

static void test_bot_naval() {
    World w;
    const int size = 64;
    std::vector<uint8_t> cost(size_t(size) * size_t(size), 1);
    std::vector<uint8_t> terrain(size_t(size) * size_t(size), uint8_t(TER_CLEAR));
    for (int y = 0; y < size; ++y) {
        for (int x = 24; x < 36; ++x) {
            cost[size_t(y * size + x)] = 0;
            terrain[size_t(y * size + x)] = uint8_t(TER_WATER);
        }
    }
    w.set_map(size, size, cost.data());
    w.set_terrain(size, size, terrain.data());
    w.init_layers();

    Weapon gun; gun.range = 5 * CELL; gun.reload = 40; gun.damage = 3000; gun.speed = 0;
    gun.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_INFANTRY;
    const int w_gun = w.define_weapon(gun);

    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.sprite_h = 3; fact.hp = 150000; fact.cost = 2500;
    fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true; fact.provides = {"fact"};
    fact.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_fact = w.define_type(fact);

    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.build_block = powr.footprint; powr.sprite_h = 2; powr.hp = 40000; powr.power = 300;
    powr.cost = 300; powr.make_ticks = 10; powr.queue_kind = QUEUE_BUILDING;
    powr.provides = {"powr", "anypower"}; powr.ai_building_fraction = 2;
    powr.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_powr = w.define_type(powr);


    UnitType syrd;
    syrd.building = true; syrd.foot_w = 3; syrd.foot_h = 3; syrd.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    syrd.build_block = syrd.footprint; syrd.sprite_h = 3; syrd.hp = 100000; syrd.cost = 1000;
    syrd.make_ticks = 10; syrd.queue_kind = QUEUE_BUILDING; syrd.power = -30;
    syrd.terrain_mask = 1u << TER_WATER; syrd.produces = 1u << QUEUE_SHIP;
    syrd.prerequisites = {"anypower"}; syrd.ai_building_fraction = 20; syrd.provides = {"syrd"};
    syrd.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_syrd = w.define_type(syrd);

    UnitType dd;
    dd.speed = 56; dd.turn_rate = 20; dd.hp = 60000; dd.cost = 1000; dd.weapon = w_gun;
    dd.locomotor = LOCO_NAVAL; dd.queue_kind = QUEUE_SHIP; dd.prerequisites = {"syrd"};
    dd.ai_unit_share = 30; dd.hit_radius = 426; dd.auto_target_mask = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE;
    dd.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_dd = w.define_type(dd);


    UnitType hut;
    hut.building = true; hut.foot_w = 2; hut.foot_h = 2; hut.footprint = {1, 1, 1, 1};
    hut.build_block = hut.footprint; hut.sprite_h = 2; hut.hp = 40000;
    hut.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_hut = w.define_type(hut);

    w.spawn_building(t_fact, 0, {20, 30});
    w.spawn_building(t_powr, 0, {24, 34});
    const int32_t coast = w.spawn_building(t_hut, 1, {37, 30});
    w.set_enemy(0, 1, true);
    w.set_enemy(1, 0, true);
    w.give_credits(0, 60000);
    w.reveal(0, CPos{32, 32}, 64);
    BotParams p;
    w.bot_apply_personality(p, BOT_P_NAVAL);
    p.max_base_radius = 20;
    w.enable_bot(0, p);

    bool yard = false, ship = false;
    for (int t = 0; t < 20000 && !ship; ++t) {
        w.step();
        for (size_t i = 0; i < w.actor_count(); ++i) {
            const Actor& a = w.actor(i);
            if (!a.alive || a.owner != 0) continue;
            if (a.type == t_syrd && a.make_ticks <= 0) yard = true;
            if (a.type == t_dd) ship = true;
        }
    }
    std::printf("Marine-KI: Werft gebaut=%s, Schiff gebaut=%s\n", yard ? "ja" : "nein", ship ? "ja" : "nein");
    CHECK(yard);
    CHECK(ship);


    bool hurt = false;
    for (int t = 0; t < 20000 && !hurt; ++t) {
        w.step();
        const int ci = w.index_of(coast);
        if (ci < 0 || !w.actor(size_t(ci)).alive || w.actor(size_t(ci)).hp < 40000) hurt = true;
    }
    std::printf("Marine-KI: Küstenziel unter Beschuss=%s\n", hurt ? "ja" : "nein");
    CHECK(hurt);


    {
        World dry;
        std::vector<uint8_t> dcost(size_t(size) * size_t(size), 1);
        dry.set_map(size, size, dcost.data());
        std::vector<uint8_t> dterrain(size_t(size) * size_t(size), uint8_t(TER_CLEAR));
        dry.set_terrain(size, size, dterrain.data());
        dry.init_layers();
        dry.define_weapon(gun);
        const int d_fact = dry.define_type(fact);
        dry.define_type(powr);
        const int d_syrd = dry.define_type(syrd);
        dry.spawn_building(d_fact, 0, {20, 30});
        dry.give_credits(0, 60000);
        BotParams dp;
        dry.bot_apply_personality(dp, BOT_P_NAVAL);
        dry.enable_bot(0, dp);
        bool dry_yard = false;
        for (int t = 0; t < 6000 && !dry_yard; ++t) {
            dry.step();
            for (size_t i = 0; i < dry.actor_count(); ++i)
                if (dry.actor(i).alive && dry.actor(i).owner == 0 && dry.actor(i).type == d_syrd) dry_yard = true;
        }
        CHECK(!dry_yard);
        std::printf("Marine-KI: auf trockener Karte keine Werft gewählt\n");
    }
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


struct UtilityWorld {
    int32_t fact = -1, powr = -1, mslo = -1, hpad = -1, heli = -1, tank = -1, agun = -1, proc = -1;
};

static UtilityWorld build_utility_world(World& w, int size = 64) {
    UtilityWorld t;
    std::vector<uint8_t> cost(size_t(size) * size_t(size), 1);
    w.set_map(size, size, cost.data());
    Weapon gun; gun.range = 5 * CELL; gun.reload = 40; gun.damage = 3000; gun.speed = 0;
    gun.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_INFANTRY;
    const int w_gun = w.define_weapon(gun);
    Weapon hell; hell.range = 4 * CELL; hell.reload = 30; hell.damage = 3000; hell.speed = 0;
    hell.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE;
    const int w_hell = w.define_weapon(hell);
    Weapon flak; flak.range = 6 * CELL; flak.reload = 20; flak.damage = 2000; flak.speed = 0;
    flak.valid_targets = TT_AIRBORNE;
    const int w_flak = w.define_weapon(flak);
    Weapon nuke; nuke.damage = 20000; nuke.spread = 2 * CELL; nuke.range = 0;
    for (int i = 0; i < NUM_ARMOR; ++i) nuke.versus[i] = 100;
    nuke.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_INFANTRY;
    const int w_nuke = w.define_weapon(nuke);

    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.sprite_h = 3; fact.hp = 150000; fact.produces = 1u << QUEUE_BUILDING;
    fact.base_provider = true; fact.provides = {"fact"}; fact.cost = 2500;
    fact.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    t.fact = w.define_type(fact);

    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.sprite_h = 2; powr.hp = 40000; powr.power = 200; powr.cost = 300; powr.make_ticks = 20;
    powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"}; powr.ai_building_fraction = 2;
    powr.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    t.powr = w.define_type(powr);

    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 3; proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0};
    proc.sprite_h = 3; proc.hp = 90000; proc.power = -30; proc.cost = 1400; proc.make_ticks = 20;
    proc.queue_kind = QUEUE_BUILDING; proc.prerequisites = {"anypower"}; proc.provides = {"proc"};
    proc.refinery = true; proc.dock_dx = 1; proc.dock_dy = 2; proc.ai_building_fraction = 1;
    proc.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    t.proc = w.define_type(proc);

    UnitType mslo;
    mslo.building = true; mslo.foot_w = 2; mslo.foot_h = 2; mslo.footprint = {1, 1, 1, 1};
    mslo.sprite_h = 2; mslo.hp = 40000; mslo.power = -150; mslo.cost = 2500; mslo.make_ticks = 20;
    mslo.queue_kind = QUEUE_BUILDING; mslo.prerequisites = {"anypower"}; mslo.ai_building_fraction = 1;
    mslo.support_power = SP_NUKE; mslo.sp_charge = 200; mslo.sp_weapon = w_nuke; mslo.sp_flight = 10;
    mslo.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    t.mslo = w.define_type(mslo);

    UnitType hpad;
    hpad.building = true; hpad.foot_w = 2; hpad.foot_h = 2; hpad.footprint = {1, 1, 1, 1};
    hpad.sprite_h = 2; hpad.hp = 80000; hpad.power = -10; hpad.cost = 500; hpad.make_ticks = 20;
    hpad.queue_kind = QUEUE_BUILDING; hpad.prerequisites = {"anypower"}; hpad.provides = {"hpad"};
    hpad.produces = 1u << QUEUE_AIRCRAFT; hpad.ai_building_fraction = 4;
    hpad.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    t.hpad = w.define_type(hpad);

    UnitType heli;
    heli.aircraft = true; heli.can_hover = true; heli.vtol = true; heli.speed = 149; heli.turn_rate = 16;
    heli.cruise_altitude = 1280; heli.altitude_velocity = 43; heli.hp = 12000; heli.weapon = w_hell;
    heli.ammo_max = 8; heli.ammo_reload = 20; heli.air_attack_type = 1; heli.facing_tolerance = 80;
    heli.hit_radius = 426; heli.cost = 1200; heli.queue_kind = QUEUE_AIRCRAFT;
    heli.prerequisites = {"hpad"}; heli.make_ticks = 10; heli.ai_unit_share = 90;
    heli.target_types = TT_GROUND_ACTOR | TT_VEHICLE; heli.target_types_airborne = TT_AIRBORNE;
    heli.rearm_actors = {t.hpad}; heli.auto_target_mask = TT_GROUND_ACTOR | TT_VEHICLE | TT_STRUCTURE;
    t.heli = w.define_type(heli);

    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 40000; tank.hit_radius = 426; tank.cost = 800;
    tank.weapon = w_gun; tank.queue_kind = QUEUE_VEHICLE; tank.ai_unit_share = 60;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    t.tank = w.define_type(tank);

    UnitType agun;
    agun.building = true; agun.foot_w = 1; agun.foot_h = 1; agun.footprint = {1};
    agun.hp = 40000; agun.weapon = w_flak; agun.turreted = true; agun.turret_turn = 40;
    agun.cost = 600; agun.defense = true; agun.auto_target_mask = TT_AIRBORNE;
    agun.target_types = TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE;
    t.agun = w.define_type(agun);
    return t;
}


static void test_bot_saboteurs() {
    World w;
    UtilityWorld t = build_utility_world(w, 64);

    UnitType tanya;
    tanya.speed = 56; tanya.turn_rate = 1024; tanya.infantry = true; tanya.locomotor = LOCO_FOOT;
    tanya.hp = 10000; tanya.demolition_delay = 45; tanya.cost = 1800;
    tanya.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_tanya = w.define_type(tanya);

    UnitType eng;
    eng.speed = 56; eng.turn_rate = 1024; eng.infantry = true; eng.locomotor = LOCO_FOOT;
    eng.hp = 5000; eng.captures = true; eng.capture_delay = 20; eng.cost = 500;
    eng.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_eng = w.define_type(eng);


    UnitType cheap;
    cheap.building = true; cheap.foot_w = 2; cheap.foot_h = 2; cheap.footprint = {1, 1, 1, 1};
    cheap.build_block = cheap.footprint; cheap.hp = 40000; cheap.cost = 300; cheap.sell_value = 300;
    cheap.demolishable = true; cheap.capturable = true;
    cheap.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_cheap = w.define_type(cheap);
    UnitType rich = cheap;
    rich.cost = 2500; rich.sell_value = 2500;
    const int t_rich = w.define_type(rich);


    UnitType cap = cheap;
    cap.demolishable = false; cap.capturable = true; cap.cost = 800; cap.sell_value = 800;
    const int t_cap = w.define_type(cap);

    w.spawn_building(t.fact, 0, {10, 10});
    const int32_t cheap_id = w.spawn_building(t_cheap, 1, {30, 10});
    const int32_t rich_id = w.spawn_building(t_rich, 1, {34, 10});
    w.set_enemy(0, 1, true);
    w.set_enemy(1, 0, true);
    w.reveal(0, CPos{32, 32}, 64);
    const int32_t saboteur = w.spawn(t_tanya, 0, {14, 10});
    BotParams p;
    w.bot_apply_personality(p, BOT_P_NORMAL);
    w.enable_bot(0, p);

    bool blown = false;
    for (int i = 0; i < 6000 && !blown; ++i) {
        w.step();
        const int ri = w.index_of(rich_id);
        if (ri < 0 || !w.actor(size_t(ri)).alive) blown = true;
    }
    const int ci = w.index_of(cheap_id);
    std::printf("KI-Spezialisten: teures Gebäude zuerst gesprengt=%s (billiges danach: %s)\n",
                blown ? "ja" : "nein", (ci >= 0 && w.actor(size_t(ci)).alive) ? "steht noch" : "auch weg");
    CHECK(blown);
    CHECK(w.index_of(saboteur) >= 0);


    const int32_t cap_id = w.spawn_building(t_cap, 1, {30, 16});
    w.spawn(t_eng, 0, {14, 12});
    bool captured = false;
    for (int i = 0; i < 6000 && !captured; ++i) {
        w.step();
        const int k = w.index_of(cap_id);
        if (k >= 0 && w.actor(size_t(k)).alive && w.actor(size_t(k)).owner == 0) captured = true;
    }
    std::printf("KI-Spezialisten: Pionier hat das Gebäude erobert=%s\n", captured ? "ja" : "nein");
    CHECK(captured);
}


static void test_bot_repair() {
    World w;
    UtilityWorld t = build_utility_world(w, 64);
    UnitType fix;

    fix.building = true; fix.foot_w = 3; fix.foot_h = 3;
    fix.footprint = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    fix.build_block = {0, 1, 0, 1, 1, 1, 0, 1, 0};
    fix.sprite_h = 3; fix.hp = 60000; fix.cost = 1200; fix.repairs_units = true;
    fix.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_fix = w.define_type(fix);


    UnitType veh;
    veh.speed = 72; veh.turn_rate = 20; veh.hp = 40000; veh.hit_radius = 426;
    veh.repairable = true; veh.repair_actors = {t_fix};
    veh.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_veh = w.define_type(veh);

    const int32_t hq = w.spawn_building(t.fact, 0, {20, 20});
    w.spawn_building(t.powr, 0, {26, 20});
    const int32_t depot = w.spawn_building(t_fix, 0, {24, 26});
    const int32_t hurt = w.spawn(t_veh, 0, {30, 30});
    const int32_t foe = w.spawn(t.tank, 1, {40, 40});
    w.set_enemy(0, 1, true);
    w.set_enemy(1, 0, true);
    w.give_credits(0, 20000);
    BotParams p;
    w.bot_apply_personality(p, BOT_P_NORMAL);
    w.enable_bot(0, p);


    const size_t hi = size_t(w.index_of(hq));
    w.damage_for_test(hi, 60000, foe);
    CHECK(w.actor(hi).hp < 150000);
    const int32_t after_hit = w.actor(hi).hp;
    CHECK(w.actor(hi).repairing);
    for (int i = 0; i < 600; ++i) w.step();
    const int32_t healed = w.actor(size_t(w.index_of(hq))).hp;
    CHECK(healed > after_hit);
    std::printf("KI-Reparatur: Gebäude %d → %d Trefferpunkte (geschaltet=%s)\n",
                after_hit, healed, w.actor(size_t(w.index_of(hq))).repairing ? "ja" : "fertig");


    size_t vi = size_t(w.index_of(hurt));
    w.damage_for_test(vi, 30000, foe);
    const int32_t veh_after_hit = w.actor(vi).hp;
    bool sent = false;
    for (int i = 0; i < 300 && !sent; ++i) {
        w.step();
        vi = size_t(w.index_of(hurt));
        if (w.actor(vi).repair_depot == depot) sent = true;
    }
    CHECK(sent);
    bool fixed = false;
    for (int i = 0; i < 4000 && !fixed; ++i) {
        w.step();
        vi = size_t(w.index_of(hurt));
        if (w.actor(vi).hp >= 40000) fixed = true;
    }
    CHECK(fixed);
    std::printf("KI-Reparatur: Fahrzeug %d → %d Trefferpunkte im Depot\n",
                veh_after_hit, w.actor(size_t(w.index_of(hurt))).hp);


    const int32_t far_away = w.spawn(t_veh, 0, {58, 58});
    w.damage_for_test(size_t(w.index_of(far_away)), 30000, foe);

    const int32_t home1 = w.spawn(t_veh, 0, {21, 24});
    const int32_t home2 = w.spawn(t_veh, 0, {22, 24});
    w.damage_for_test(size_t(w.index_of(home1)), 30000, foe);
    w.damage_for_test(size_t(w.index_of(home2)), 30000, foe);
    int max_underway = 0;
    for (int i = 0; i < 600; ++i) {
        w.step();
        int underway = 0;
        for (const int32_t id : {home1, home2, far_away}) {
            const int k = w.index_of(id);
            if (k >= 0 && w.actor(size_t(k)).repair_depot >= 0) ++underway;
        }
        max_underway = std::max(max_underway, underway);
        const int fi = w.index_of(far_away);
        CHECK(fi < 0 || w.actor(size_t(fi)).repair_depot < 0);
    }
    CHECK(max_underway <= 1);
    std::printf("KI-Reparatur: gleichzeitig unterwegs höchstens %d (Sollwert 1), das Fahrzeug beim Gegner blieb stehen\n",
                max_underway);
}

static void test_bot_personality() {
    BotParams rush, turtle, air;
    World::bot_apply_personality(rush, BOT_P_RUSH);
    World::bot_apply_personality(turtle, BOT_P_TURTLE);
    World::bot_apply_personality(air, BOT_P_AIR);

    CHECK(rush.first_attack_tick < turtle.first_attack_tick);

    CHECK(turtle.nuke_min_attractiveness < rush.nuke_min_attractiveness);

    CHECK(turtle.raid_squad_size == 0 && rush.raid_squad_size > 0);

    CHECK(air.vorhaben_weight[VH_AIR_STRIKE] > rush.vorhaben_weight[VH_AIR_STRIKE]);

    CHECK(rush.vorhaben_weight[VH_TANK_PUSH] > turtle.vorhaben_weight[VH_TANK_PUSH]);
    CHECK(turtle.vorhaben_weight[VH_TURTLE] > rush.vorhaben_weight[VH_TURTLE]);
    CHECK(turtle.vorhaben_weight[VH_NUKE_PUSH] > rush.vorhaben_weight[VH_NUKE_PUSH]);
    CHECK(air.target_threat_weight > rush.target_threat_weight);


    auto roll = [](uint32_t seed) {
        World w;
        std::vector<uint8_t> cost(16 * 16, 1);
        w.set_map(16, 16, cost.data());
        w.set_rng_seed(seed);
        BotParams p;
        World::bot_apply_personality(p, BOT_P_RANDOM);
        w.enable_bot(1, p);
        return w.bot_personality(1);
    };
    const int32_t a = roll(4242), b = roll(4242), c = roll(99);
    CHECK(a == b);
    CHECK(a >= 0 && a < BOT_P_RANDOM);
    std::printf("KI-Persoenlichkeiten: Rush T%d < Turtle T%d, Zufall(4242)=%d zweimal gleich, Zufall(99)=%d\n",
                rush.first_attack_tick, turtle.first_attack_tick, a, c);
    (void)c;
}


static void test_bot_target_value() {
    World w;
    const UtilityWorld t = build_utility_world(w);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {5, 5});
    w.spawn(t.tank, 0, {20, 20});
    w.spawn_building(t.proc, 0, {30, 30});
    BotParams bp;
    World::bot_apply_personality(bp, BOT_P_NORMAL);
    w.enable_bot(1, bp);
    const int32_t pick = w.bot_pick_target(1, WVec{5 * CELL, 5 * CELL}, 0, true);
    int proc_id = -1;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).owner == 0 && w.type(w.actor(i).type).refinery) proc_id = w.actor(i).id;
    CHECK(pick == proc_id);
    std::printf("KI-Zielwahl: Raffinerie (Wert 2800, 35 Zellen) schlaegt Panzer (Wert 800, 21 Zellen)\n");
}


static void test_bot_support_power() {
    World w;
    const UtilityWorld t = build_utility_world(w);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {4, 4});
    w.spawn_building(t.mslo, 1, {4, 9});
    w.spawn_building(t.powr, 1, {8, 4});

    w.spawn_building(t.fact, 0, {40, 40});
    w.spawn_building(t.proc, 0, {44, 40});
    w.spawn_building(t.proc, 0, {40, 44});

    w.spawn(t.tank, 0, {20, 55});
    BotParams bp;
    World::bot_apply_personality(bp, BOT_P_NORMAL);
    bp.sp_scan_interval = 20;
    w.enable_bot(1, bp);

    CPos target{-1, -1}, target2{-1, -1};
    int64_t attraction = 0;
    CHECK(w.bot_sp_target(1, SP_NUKE, target, target2, attraction));
    CHECK(attraction >= bp.nuke_min_attractiveness);
    CHECK(target.x >= 38 && target.x <= 47 && target.y >= 38 && target.y <= 47);


    int hp_before = 0;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).owner == 0 && w.actor(i).type == t.fact) hp_before = w.actor(i).hp;
    for (int k = 0; k < 400; ++k) w.step();
    int hp_after = hp_before;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).owner == 0 && w.actor(i).type == t.fact) hp_after = w.actor(i).hp;
    CHECK(w.bot_stat(1, 1) >= 1);
    CHECK(hp_after < hp_before);
    std::printf("KI-Superwaffe: Ziel (%d,%d) Anziehung %lld, %d Abschuss/Abschuesse, Bauhof %d -> %d HP\n",
                target.x, target.y, static_cast<long long>(attraction), w.bot_stat(1, 1), hp_before, hp_after);
}


static void test_bot_air_squad() {
    World w;
    const UtilityWorld t = build_utility_world(w);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {4, 4});
    w.spawn_building(t.hpad, 1, {8, 4});
    w.spawn_building(t.powr, 1, {4, 9});
    w.spawn_building(t.fact, 0, {50, 50});
    const int32_t victim = w.spawn_building(t.proc, 0, {46, 50});
    BotParams bp;
    World::bot_apply_personality(bp, BOT_P_AIR);
    bp.air_squad_size = 2;
    bp.first_attack_tick = 0;
    w.enable_bot(1, bp);

    for (int k = 0; k < 3; ++k) w.spawn(t.heli, 1, {10 + k, 8});
    for (int k = 0; k < 60; ++k) w.step();

    const BotState& b = w.bot_state(1);
    int air_squads = 0, air_units = 0, ground_with_air = 0;
    for (const BotSquad& s : b.squads) {
        if (s.type == BotSquad::AIR) { ++air_squads; air_units += int(s.units.size()); continue; }
        for (int32_t id : s.units) {
            const int i = w.index_of(id);
            if (i >= 0 && w.type(w.actor(size_t(i)).type).aircraft) ++ground_with_air;
        }
    }
    CHECK(air_squads == 1);
    CHECK(air_units == 3);
    CHECK(ground_with_air == 0);


    auto enemy_hp = [&]() {
        int64_t sum = 0;
        for (size_t i = 0; i < w.actor_count(); ++i)
            if (w.actor(i).alive && w.actor(i).owner == 0) sum += w.actor(i).hp;
        return sum;
    };
    const int64_t hp0 = enemy_hp();
    for (int k = 0; k < 1500; ++k) w.step();
    const int64_t hp1 = enemy_hp();
    CHECK(hp1 < hp0);
    (void)victim;
    std::printf("KI-Luft-Trupp: 1 Trupp, 3 Flieger, kein Flieger im Bodentrupp; Gegner %lld -> %lld HP\n",
                static_cast<long long>(hp0), static_cast<long long>(hp1));


    World v;
    const UtilityWorld t2 = build_utility_world(v);
    v.set_alliance(0, 1, false);
    v.spawn_building(t2.fact, 1, {4, 4});
    v.spawn_building(t2.hpad, 1, {8, 4});
    v.spawn_building(t2.fact, 0, {50, 50});
    for (int k = 0; k < 4; ++k) v.spawn_building(t2.agun, 0, {46 + k, 50});
    BotParams bp2 = bp;
    v.enable_bot(1, bp2);
    for (int k = 0; k < 2; ++k) v.spawn(t2.heli, 1, {10 + k, 8});
    for (int k = 0; k < 400; ++k) v.step();
    bool any_target = false;
    for (const BotSquad& s : v.bot_state(1).squads)
        if (s.type == BotSquad::AIR && s.target >= 0) any_target = true;
    CHECK(!any_target);
    std::printf("KI-Luft-Trupp: 2 Flieger gegen 4 Flakstellungen -> kein Ziel (AirStates: Flak x 3 >= Truppgroesse)\n");
}


struct SiegeWorld {
    int32_t fact = -1, arty = -1, tank = -1, tower = -1, hut = -1;
};

static SiegeWorld build_siege_world(World& w) {
    SiegeWorld t;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    Weapon shell;
    shell.range = 11 * CELL; shell.min_range = 4 * CELL; shell.reload = 60; shell.damage = 2000; shell.speed = 0;
    shell.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE | TT_VEHICLE | TT_INFANTRY;
    const int w_shell = w.define_weapon(shell);
    Weapon gun;
    gun.range = 5 * CELL; gun.reload = 15; gun.damage = 4000; gun.speed = 0;
    gun.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE | TT_VEHICLE | TT_INFANTRY;
    const int w_gun = w.define_weapon(gun);

    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.cost = 2500;
    fact.base_provider = true; fact.provides = {"fact"};
    fact.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    t.fact = w.define_type(fact);

    UnitType arty;
    arty.speed = 45; arty.turn_rate = 20; arty.hp = 15000; arty.hit_radius = 426; arty.cost = 600;
    arty.weapon = w_shell; arty.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    t.arty = w.define_type(arty);

    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 40000; tank.hit_radius = 426; tank.cost = 800;
    tank.weapon = w_gun; tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    t.tank = w.define_type(tank);

    UnitType tower;
    tower.building = true; tower.foot_w = 1; tower.foot_h = 1; tower.footprint = {1};
    tower.build_block = tower.footprint; tower.hp = 400000; tower.cost = 600;
    tower.weapon = w_gun; tower.defense = true;
    tower.target_types = TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE;
    t.tower = w.define_type(tower);

    UnitType hut;
    hut.building = true; hut.foot_w = 2; hut.foot_h = 2; hut.footprint = {1, 1, 1, 1};
    hut.build_block = hut.footprint; hut.hp = 200000; hut.cost = 1000;
    hut.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    t.hut = w.define_type(hut);
    return t;
}


static BotParams siege_bot_params() {
    BotParams bp;
    World::bot_apply_personality(bp, BOT_P_NORMAL);
    bp.squad_size = 2;
    bp.squad_size_random_bonus = 1;
    bp.first_attack_tick = 0;
    bp.rush_interval = 100000;
    bp.raid_squad_size = 0;
    bp.gather_max_ticks = 600;
    return bp;
}


static void test_bot_siege_holds_range() {
    World w;
    const SiegeWorld t = build_siege_world(w);
    w.set_rng_seed(4242);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {18, 49});
    const int32_t tower = w.spawn_building(t.tower, 0, {44, 50});
    w.spawn_building(t.hut, 0, {50, 50});
    for (int k = 0; k < 4; ++k) w.spawn(t.arty, 1, {22 + k, 48 + (k % 2)});
    w.enable_bot(1, siege_bot_params());

    const int tw = w.index_of(tower);
    const int hp0 = w.actor(size_t(tw)).hp;
    int64_t closest = INT64_MAX;
    int dead_in_range = 0;
    int hp1 = hp0;
    for (int k = 0; k < 4000; ++k) {
        w.step();
        const int ti = w.index_of(tower);


        if (ti < 0 || !w.actor(size_t(ti)).alive) break;
        hp1 = w.actor(size_t(ti)).hp;
        const CPos tc = w.actor(size_t(ti)).origin;
        for (size_t i = 0; i < w.actor_count(); ++i) {
            if (w.actor(i).owner != 1 || w.type(w.actor(i).type).building) continue;
            const int64_t dx = w.mobile(i).cell.x - tc.x, dy = w.mobile(i).cell.y - tc.y;
            const int64_t d2 = dx * dx + dy * dy;
            if (!w.actor(i).alive) { if (d2 <= 36) ++dead_in_range; continue; }
            closest = std::min(closest, d2);
        }
    }
    int alive = 0;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).alive && w.actor(i).owner == 1 && !w.type(w.actor(i).type).building) ++alive;
    std::printf("KI-Belagerung: dichteste Annaeherung %.1f Zellen (Turmreichweite 5), Turm %d -> %d HP, %d/4 Belagerer leben\n",
                std::sqrt(double(closest)), hp0, hp1, alive);
    CHECK(closest > 36);
    CHECK(dead_in_range == 0);
    CHECK(hp1 < hp0);
    CHECK(alive == 4);
}


static void test_bot_gather() {
    World w;
    const SiegeWorld t = build_siege_world(w);
    w.set_rng_seed(99);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {6, 30});
    w.spawn_building(t.tower, 0, {44, 30});
    w.spawn_building(t.hut, 0, {50, 30});
    for (int k = 0; k < 6; ++k) w.spawn(t.tank, 1, {10 + k % 3, 28 + k / 3});
    BotParams bp = siege_bot_params();
    bp.squad_size = 4;
    w.enable_bot(1, bp);

    CPos gather{-1, -1};
    bool saw_gather = false, left_gather = false;
    int near_at_start = 0, total_at_start = 0;
    uint32_t gather_tick = 0, start_tick = 0;
    for (int k = 0; k < 4000; ++k) {
        w.step();
        const BotState& b = w.bot_state(1);
        for (const BotSquad& s : b.squads) {
            if (s.type != BotSquad::ASSAULT) continue;
            if (s.state == BotSquad::GATHER && s.gather.x >= 0 && !saw_gather) {
                saw_gather = true;
                gather = s.gather;
                gather_tick = w.tick();
            } else if (saw_gather && !left_gather && s.state != BotSquad::GATHER) {
                left_gather = true;
                start_tick = w.tick();
                total_at_start = int(s.units.size());
                for (int32_t id : s.units) {
                    const int i = w.index_of(id);
                    if (i < 0) continue;
                    const int64_t dx = w.mobile(size_t(i)).cell.x - gather.x, dy = w.mobile(size_t(i)).cell.y - gather.y;
                    if (dx * dx + dy * dy <= 16) ++near_at_start;
                }
            }
        }
        if (left_gather) break;
    }

    const int64_t dx = gather.x - 44, dy = gather.y - 30;
    const double dist = std::sqrt(double(dx * dx + dy * dy));
    std::printf("KI-Sammeln: Sammelpunkt (%d,%d), %.1f Zellen vor dem Turm, ab Tick %u, Aufbruch Tick %u mit %d/%d Einheiten am Punkt\n",
                gather.x, gather.y, dist, gather_tick, start_tick, near_at_start, total_at_start);
    CHECK(saw_gather);
    CHECK(dist >= 12.0 && dist <= 15.0);
    CHECK(gather.x < 44);
    CHECK(w.bot_threat_at(1, gather, true) == 0);
    CHECK(left_gather);

    CHECK(near_at_start * 100 >= total_at_start * 80 || start_tick > gather_tick + 600);
}


static void test_bot_gather_leaves_without_building() {
    World w;
    const SiegeWorld t = build_siege_world(w);
    w.set_rng_seed(7);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {6, 30});
    const int32_t far_enemy = w.spawn(t.tank, 0, {55, 30});
    for (int k = 0; k < 6; ++k) w.spawn(t.tank, 1, {10 + k % 3, 28 + k / 3});
    BotParams bp = siege_bot_params();
    bp.squad_size = 4;
    bp.gather_max_ticks = 400;
    w.enable_bot(1, bp);

    bool saw_gather = false, left_gather = false;
    uint32_t gather_tick = 0, start_tick = 0;
    int32_t start_target = -1;
    for (int k = 0; k < 4000; ++k) {
        w.step();
        for (const BotSquad& s : w.bot_state(1).squads) {
            if (s.type != BotSquad::ASSAULT) continue;
            if (s.state == BotSquad::GATHER && !saw_gather) { saw_gather = true; gather_tick = w.tick(); }
            else if (saw_gather && !left_gather && s.state != BotSquad::GATHER) {
                left_gather = true;
                start_tick = w.tick();
                start_target = s.target;
            }
        }
        if (left_gather) break;
    }
    std::printf("KI-Sammeln ohne Gegnergebaeude: Sammeln ab Tick %u, Aufbruch Tick %u, Ziel %d (Gegner %d)\n",
                gather_tick, start_tick, start_target, far_enemy);
    CHECK(saw_gather);
    CHECK(left_gather);
    CHECK(start_target == far_enemy);

    CHECK(start_tick <= gather_tick + 400 + 200);
}


static void test_bot_vorhaben_form_timeout() {
    World w;
    const SiegeWorld t = build_siege_world(w);
    w.set_rng_seed(11);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {6, 30});
    w.spawn_building(t.hut, 0, {50, 30});
    for (int k = 0; k < 3; ++k) w.spawn(t.tank, 1, {10 + k, 28});
    BotParams bp = siege_bot_params();
    bp.squad_size = 5000;
    bp.squad_size_random_bonus = 0;
    w.enable_bot(1, bp);

    int32_t pending = -1;
    uint32_t pending_since = 0, longest = 0;
    int32_t ever_pending = -1;
    for (int k = 0; k < 6000; ++k) {
        w.step();
        const int32_t now = w.bot_state(1).vh_pending;
        if (now != pending) {
            if (pending >= 0) longest = std::max(longest, w.tick() - pending_since);
            pending = now;
            pending_since = w.tick();
            if (now >= 0) ever_pending = now;
        }
    }
    if (pending >= 0) longest = std::max(longest, w.tick() - pending_since);
    const BotState& b = w.bot_state(1);
    int32_t open_orders = 0;
    for (int r = 0; r < ROLE_COUNT; ++r) open_orders += b.vh_orders[r];
    std::printf("KI-Vorhaben ohne Trupp: laengste Wartezeit %u Ticks, zuletzt %d, offene Bestellungen %d\n",
                longest, ever_pending, open_orders);
    CHECK(ever_pending >= 0);
    CHECK(longest <= 900 + 400);
    CHECK(open_orders <= 30);
}


static void test_bot_difficulty_params() {

    {
        World w;
        build_siege_world(w);
        BotParams bp;
        World::bot_apply_personality(bp, BOT_P_RUSH);
        bp.min_first_attack_tick = 8000;
        w.enable_bot(1, bp);
        CHECK(w.bot_state(1).p.first_attack_tick == 8000);
    }


    int64_t closest_off = INT64_MAX;
    {
        World w;
        const SiegeWorld t = build_siege_world(w);
        w.set_rng_seed(4242);
        w.set_alliance(0, 1, false);
        w.spawn_building(t.fact, 1, {18, 49});
        const int32_t tower = w.spawn_building(t.tower, 0, {44, 50});
        w.spawn_building(t.hut, 0, {50, 50});
        for (int k = 0; k < 4; ++k) w.spawn(t.arty, 1, {22 + k, 48 + (k % 2)});
        BotParams bp = siege_bot_params();
        bp.allow_siege = 0;
        w.enable_bot(1, bp);
        for (int k = 0; k < 4000; ++k) {
            w.step();
            const int ti = w.index_of(tower);
            if (ti < 0 || !w.actor(size_t(ti)).alive) break;
            const CPos tc = w.actor(size_t(ti)).origin;
            for (size_t i = 0; i < w.actor_count(); ++i) {
                if (!w.actor(i).alive || w.actor(i).owner != 1 || w.type(w.actor(i).type).building) continue;
                const int64_t dx = w.mobile(i).cell.x - tc.x, dy = w.mobile(i).cell.y - tc.y;
                closest_off = std::min(closest_off, dx * dx + dy * dy);
            }
        }
        CHECK(closest_off <= 36);
    }


    {
        World w;
        const UtilityWorld t = build_utility_world(w);
        w.set_alliance(0, 1, false);
        w.spawn_building(t.fact, 1, {4, 4});
        w.spawn_building(t.mslo, 1, {4, 9});
        w.spawn_building(t.powr, 1, {8, 4});
        w.spawn_building(t.fact, 0, {40, 40});
        w.spawn_building(t.proc, 0, {44, 40});
        w.spawn_building(t.proc, 0, {40, 44});
        BotParams bp;
        World::bot_apply_personality(bp, BOT_P_NORMAL);
        bp.sp_scan_interval = 20;
        bp.allow_support_powers = 0;
        w.enable_bot(1, bp);
        for (int k = 0; k < 400; ++k) w.step();
        CHECK(w.bot_stat(1, 1) == 0);
    }

    int max_assaults = 0;
    {
        World w;
        const SiegeWorld t = build_siege_world(w);
        w.set_rng_seed(7);
        w.set_alliance(0, 1, false);
        w.spawn_building(t.fact, 1, {6, 30});
        w.spawn_building(t.tower, 0, {44, 30});
        w.spawn_building(t.hut, 0, {50, 30});
        for (int k = 0; k < 24; ++k) w.spawn(t.tank, 1, {10 + k % 6, 26 + k / 6});
        BotParams bp = siege_bot_params();
        bp.squad_size = 4;
        bp.allow_pincer = 0;
        w.enable_bot(1, bp);
        for (int k = 0; k < 3000; ++k) {
            w.step();
            int n = 0;
            for (const BotSquad& s : w.bot_state(1).squads)
                if (s.type == BotSquad::ASSAULT && !s.units.empty()) ++n;
            max_assaults = std::max(max_assaults, n);
        }
        CHECK(max_assaults <= 1);
    }

    bool air_target = false;
    {
        World w;
        const UtilityWorld t = build_utility_world(w);
        w.set_alliance(0, 1, false);
        w.spawn_building(t.fact, 1, {4, 4});
        w.spawn_building(t.hpad, 1, {8, 4});
        w.spawn_building(t.fact, 0, {50, 50});
        BotParams bp;
        World::bot_apply_personality(bp, BOT_P_AIR);
        bp.air_squad_size = 2;
        bp.first_attack_tick = 0;
        bp.allow_air_squad = 0;
        w.enable_bot(1, bp);
        for (int k = 0; k < 3; ++k) w.spawn(t.heli, 1, {10 + k, 8});
        for (int k = 0; k < 600; ++k) w.step();
        for (const BotSquad& s : w.bot_state(1).squads)
            if (s.type == BotSquad::AIR && s.target >= 0) air_target = true;
        CHECK(!air_target);
    }
    std::printf("KI-Stufen: first_attack_tick auf 8000 angehoben; ohne allow_siege %.1f Zellen an den Turm heran; "
                "ohne allow_support_powers kein Abschuss; ohne allow_pincer hoechstens %d Stosstrupp; ohne allow_air_squad kein Luftziel\n",
                std::sqrt(double(closest_off)), max_assaults);
}


static void setup_vorhaben_world(World& w, const SiegeWorld& t) {
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {6, 30});
    for (int k = 0; k < 3; ++k) w.spawn(t.arty, 1, {10 + k, 30});
    w.spawn_building(t.fact, 0, {56, 30});
    for (int k = 0; k < 3; ++k) w.spawn_building(t.tower, 0, {52, 26 + k * 3});
    for (int k = 0; k < 10; ++k) w.spawn(t.tank, 0, {56 + k % 5, 38 + k / 5});
}

static BotParams vorhaben_bot_params() {
    BotParams bp = siege_bot_params();
    bp.strategy_interval = 100;
    bp.max_running_vorhaben = 1;
    bp.vorhaben_random_percent = 0;
    bp.counter_interval = 0;
    return bp;
}


static void test_bot_vorhaben_wahl() {


    int32_t lage_siege = 0, lage_push = 0, chosen = -1;
    {
        World w;
        const SiegeWorld t = build_siege_world(w);
        w.set_rng_seed(4242);
        setup_vorhaben_world(w, t);
        w.enable_bot(1, vorhaben_bot_params());
        for (int k = 0; k < 200; ++k) w.step();
        lage_siege = w.bot_vorhaben_lage(1, VH_SIEGE);
        lage_push = w.bot_vorhaben_lage(1, VH_TANK_PUSH);
        for (int32_t vh = 0; vh < VH_COUNT; ++vh)
            if (vh != VH_ECONOMY && w.bot_state(1).vh_running[vh]) chosen = vh;
        CHECK(lage_siege > lage_push);
        CHECK(chosen == VH_SIEGE);

        CHECK(w.bot_state(1).vh_running[VH_ECONOMY] == 1);

        bool squad_has_order = false;
        for (const BotSquad& s : w.bot_state(1).squads)
            if (s.vorhaben == VH_SIEGE && s.scheme == GS_DEFENSE_FIRST) squad_has_order = true;
        CHECK(squad_has_order || w.bot_state(1).vh_pending == VH_SIEGE);
    }


    int32_t easy_choice = -1;
    {
        World w;
        const SiegeWorld t = build_siege_world(w);
        w.set_rng_seed(4242);
        setup_vorhaben_world(w, t);
        BotParams bp = vorhaben_bot_params();
        bp.allow_siege = 0;
        bp.allow_raid = 0;
        bp.allow_support_powers = 0;
        bp.allow_air_squad = 0;
        bp.allow_counterattack = 0;
        bp.allow_pincer = 0;
        w.enable_bot(1, bp);
        CHECK(!w.bot_vorhaben_allowed(1, VH_SIEGE));
        CHECK(!w.bot_vorhaben_allowed(1, VH_ORE_RAID));
        CHECK(w.bot_vorhaben_allowed(1, VH_TANK_PUSH));
        CHECK(w.bot_vorhaben_allowed(1, VH_INFANTRY_FLOOD));
        CHECK(w.bot_vorhaben_allowed(1, VH_TURTLE));
        for (int k = 0; k < 200; ++k) w.step();
        CHECK(w.bot_state(1).vh_running[VH_SIEGE] == 0);
        for (int32_t vh = 0; vh < VH_COUNT; ++vh)
            if (vh != VH_ECONOMY && w.bot_state(1).vh_running[vh]) easy_choice = vh;
        CHECK(easy_choice == VH_TANK_PUSH);
    }

    int32_t after_fail = 0, after_win = 0;
    {
        World w;
        const SiegeWorld t = build_siege_world(w);
        setup_vorhaben_world(w, t);
        w.enable_bot(1, vorhaben_bot_params());
        w.bot_vorhaben_start(1, VH_COMMANDO);
        w.bot_vorhaben_end(1, VH_COMMANDO, false);
        after_fail = w.bot_state(1).vh_success[VH_COMMANDO];
        w.bot_vorhaben_start(1, VH_COMMANDO);
        w.bot_vorhaben_end(1, VH_COMMANDO, true);
        after_win = w.bot_state(1).vh_success[VH_COMMANDO];
        CHECK(after_fail == 80);
        CHECK(after_win == 95);

        CHECK(w.bot_state(1).vh_cooldown[VH_COMMANDO] > 0);
        CHECK(w.bot_vorhaben_log(1).size() >= 2);
        CHECK(w.bot_vorhaben_log(1).back().result == 1);
    }


    auto run = [](uint32_t seed) {
        World w;
        const SiegeWorld t = build_siege_world(w);
        w.set_rng_seed(seed);
        setup_vorhaben_world(w, t);
        BotParams bp = vorhaben_bot_params();
        bp.vorhaben_random_percent = 20;
        bp.max_running_vorhaben = 3;
        w.enable_bot(1, bp);
        for (int k = 0; k < 2500; ++k) w.step();
        uint64_t h = 0;
        for (int32_t vh = 0; vh < VH_COUNT; ++vh)
            h = h * 131 + uint64_t(w.bot_state(1).vh_running[vh] * 1000 + w.bot_state(1).vh_success[vh]);
        return h;
    };
    const uint64_t h1 = run(99), h2 = run(99);
    CHECK(h1 == h2);
    std::printf("KI-Vorhaben: Belagerung %d > Panzerstoss %d, gewaehlt %d; leicht waehlt %d; "
                "Erfolgsfaktor 100 -> %d -> %d; Determinismus %016llx zweimal\n",
                lage_siege, lage_push, chosen, easy_choice, after_fail, after_win,
                static_cast<unsigned long long>(h1));
}


static void test_bot_stats() {
    World w;
    const SiegeWorld t = build_siege_world(w);
    w.set_rng_seed(7);
    w.set_alliance(0, 1, false);
    w.spawn_building(t.fact, 1, {10, 10});
    w.spawn_building(t.tower, 0, {40, 40});
    w.spawn_building(t.tower, 1, {12, 12});

    const int32_t nah = w.spawn(t.arty, 1, {43, 40});
    const int32_t fern = w.spawn(t.arty, 1, {20, 40});
    const int32_t panzer = w.spawn(t.tank, 1, {11, 14});
    BotParams bp = siege_bot_params();
    bp.squad_size = 99;
    w.enable_bot(1, bp);
    w.step();

    const BotState& b = w.bot_state(1);
    w.bot_stat_sample(1);
    const int32_t armee = b.stat_army_value;
    const int32_t tuerme = b.stat_towers;
    CHECK(armee == 600 + 600 + 800);
    CHECK(tuerme == 1);

    w.destroy(nah);
    CHECK(b.stat_siege_lost == 1);
    CHECK(b.stat_siege_lost_in_range == 1);
    w.destroy(fern);
    CHECK(b.stat_siege_lost == 2);
    CHECK(b.stat_siege_lost_in_range == 1);
    w.destroy(panzer);
    CHECK(b.stat_siege_lost == 2);


    const BotState& b2 = w.bot_state(1);
    const int64_t vorher = b2.stat_cash_sum;
    const int32_t n_vorher = b2.stat_cash_samples;
    w.give_credits(1, 1000);
    w.bot_stat_sample(1);
    w.give_credits(1, 2000);
    w.bot_stat_sample(1);
    const int64_t mittel = (b2.stat_cash_sum - vorher) / std::max(1, b2.stat_cash_samples - n_vorher);
    std::printf("KI-Messung: Armeewert %d, Tuerme %d, Belagerer verloren %d (davon %d in Turmreichweite), Bargeld-Mittel %lld\n",
                armee, tuerme, b2.stat_siege_lost, b2.stat_siege_lost_in_range, (long long)mittel);
    CHECK(b2.stat_cash_samples - n_vorher == 2);
    CHECK(mittel == 2000);

    w.bot_stat_sample(1);
    CHECK(b2.stat_army_value == 0);
}


static uint64_t state_hash(const World& w);

static void test_bot_determinism() {
    auto run = [](uint32_t seed, uint32_t ticks) {
        World w;
        const UtilityWorld t = build_utility_world(w);
        w.set_rng_seed(seed);
        w.set_alliance(0, 1, false);
        w.spawn_building(t.fact, 0, {6, 6});
        w.spawn_building(t.fact, 1, {50, 50});
        w.give_credits(0, 20000);
        w.give_credits(1, 20000);
        BotParams a, b;
        World::bot_apply_personality(a, BOT_P_RUSH);
        World::bot_apply_personality(b, BOT_P_TURTLE);
        a.squad_size = 5; a.squad_size_random_bonus = 3; a.first_attack_tick = 200;
        b.squad_size = 6; b.squad_size_random_bonus = 3; b.first_attack_tick = 400;
        w.enable_bot(0, a);
        w.enable_bot(1, b);
        for (uint32_t k = 0; k < ticks; ++k) w.step();
        return std::pair<uint64_t, uint64_t>(state_hash(w), w.state_hash_full());
    };
    const auto r1 = run(777, 4000), r2 = run(777, 4000), r3 = run(778, 4000);
    CHECK(r1.first == r2.first);
    CHECK(r1.second == r2.second);
    CHECK(r1.first != r3.first);
    std::printf("KI-Determinismus: Rush gegen Turtle, 4000 Ticks, Hash %016llx zweimal identisch (Seed 778: %016llx)\n",
                static_cast<unsigned long long>(r1.first), static_cast<unsigned long long>(r3.first));
}

static void test_build_area() {
    World w;
    std::vector<uint8_t> cost(60 * 60, 1);
    w.set_map(60, 60, cost.data());


    UnitType fact; fact.building = true; fact.foot_w = 3; fact.foot_h = 3;
    fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1}; fact.build_block = fact.footprint;
    fact.hp = 100000; fact.base_provider = true; fact.base_range = 16 * CELL;
    fact.requires_base_provider = true;


    UnitType silo; silo.building = true; silo.foot_w = 1; silo.foot_h = 1; silo.footprint = {1};
    silo.build_block = {1}; silo.hp = 30000; silo.gives_buildable_area = true;
    silo.requires_base_provider = true;

    UnitType tsla = silo; tsla.defense = true;

    UnitType sbag = silo; sbag.wall = true; sbag.adjacent = 7;
    sbag.requires_base_provider = false; sbag.gives_buildable_area = false;
    const int t_fact = w.define_type(fact), t_silo = w.define_type(silo);
    const int t_tsla = w.define_type(tsla), t_sbag = w.define_type(sbag);
    w.spawn_building(t_fact, 0, {20, 20});


    CHECK(w.can_place(0, t_silo, {24, 21}, nullptr));
    CHECK(!w.can_place(0, t_silo, {25, 21}, nullptr));


    CHECK(w.can_place(0, t_sbag, {29, 21}, nullptr));
    CHECK(!w.can_place(0, t_sbag, {30, 21}, nullptr));

    CHECK(w.spawn_building(t_silo, 0, {24, 21}) > 0);
    CHECK(w.can_place(0, t_silo, {26, 21}, nullptr));


    CHECK(w.can_place(0, t_tsla, {20, 24}, nullptr));
    CHECK(w.spawn_building(t_tsla, 0, {20, 24}) > 0);
    CHECK(w.can_place(0, t_tsla, {20, 26}, nullptr));


    CHECK(w.spawn_building(t_silo, 0, {20, 30}) > 0);
    CHECK(w.can_place(0, t_sbag, {27, 30}, nullptr));
    CHECK(!w.can_place(0, t_sbag, {28, 30}, nullptr));
    CHECK(w.spawn_building(t_sbag, 0, {27, 30}) > 0);
    CHECK(!w.can_place(0, t_silo, {29, 30}, nullptr));
    CHECK(!w.can_place(0, t_sbag, {34, 30}, nullptr));


    CPos c{26, 21};
    for (int i = 0; i < 14; ++i) {
        CHECK(w.can_place(0, t_silo, c, nullptr));
        CHECK(w.spawn_building(t_silo, 0, c) > 0);
        c.x += 2;
    }
    CHECK(w.can_place(0, t_silo, {c.x, 21}, nullptr));
    const int weit = c.x - 22;
    CHECK(weit > 16);

    CHECK(!w.can_place(0, t_silo, {c.x + 4, 21}, nullptr));
    std::printf("Baubereich: Adjacent 2/7, jedes Gebaeude ausser Mauern gibt Flaeche, Kette %d Zellen weit\n", weit);
}


static void test_place_over_unit() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType fact; fact.building = true; fact.foot_w = 3; fact.foot_h = 3;
    fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1}; fact.build_block = fact.footprint;
    fact.hp = 150000; fact.base_provider = true; fact.produces = 1u << QUEUE_BUILDING;
    fact.provides = {"fact"};
    UnitType powr; powr.building = true; powr.foot_w = 1; powr.foot_h = 1; powr.footprint = {1};
    powr.build_block = {1}; powr.hp = 40000; powr.cost = 300; powr.queue_kind = QUEUE_BUILDING;
    UnitType tank; tank.speed = 85; tank.turn_rate = 1024; tank.hp = 40000;
    UnitType silo = powr;
    const int t_fact = w.define_type(fact), t_powr = w.define_type(powr), t_tank = w.define_type(tank);
    const int t_silo = w.define_type(silo);
    w.spawn_building(t_fact, 0, {10, 10});
    w.give_credits(0, 5000);


    const int32_t own = w.spawn(t_tank, 0, {14, 11});
    CHECK(own > 0);
    CHECK(w.can_place(0, t_powr, {14, 11}, nullptr));

    const int32_t foe = w.spawn(t_tank, 1, {14, 10});
    CHECK(foe > 0);
    CHECK(!w.can_place(0, t_powr, {14, 10}, nullptr));


    CHECK(w.queue_build(0, t_powr));
    for (int t = 0; t < 400 && !w.queue(0, QUEUE_BUILDING).front().done; ++t) w.step();
    CHECK(w.queue(0, QUEUE_BUILDING).front().done);
    CHECK(w.place_building(0, t_powr, {14, 11}));
    CHECK(w.pending_place_type(0, 0) == t_powr);
    CHECK(!w.queue(0, QUEUE_BUILDING).empty());

    CHECK(!w.can_place(0, t_silo, {14, 11}, nullptr));
    CHECK(w.can_place(0, t_powr, {14, 11}, nullptr));
    int built = -1;
    for (int t = 0; t < 200; ++t) {
        w.step();
        if (w.pending_place_type(0, 0) < 0) { built = t; break; }
    }
    CHECK(built >= 0);
    CHECK(w.queue(0, QUEUE_BUILDING).empty());
    CHECK(w.occupant({14, 11}) >= 0);
    CHECK(w.actor(size_t(w.index_of(own))).alive);
    std::printf("Bauen ueber eigener Einheit: Panzer ausgewichen, Gebaeude nach %d Ticks gesetzt\n", built);
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
    const size_t ti = size_t(w.index_of(tank_id));
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


static void test_armament_versus() {
    World w;
    std::vector<uint8_t> cost(96 * 96, 1);
    w.set_map(96, 96, cost.data());

    auto set_versus = [](Weapon& x, int none, int wood, int light, int heavy, int concrete) {
        x.versus[ARMOR_NONE] = none; x.versus[ARMOR_WOOD] = wood; x.versus[ARMOR_LIGHT] = light;
        x.versus[ARMOR_HEAVY] = heavy; x.versus[ARMOR_CONCRETE] = concrete; x.versus[ARMOR_TREE] = wood;
    };

    Weapon w120; w120.range = 4864; w120.reload = 90; w120.burst = 2; w120.burst_delay = 5;
    w120.damage = 6000; w120.spread = 128; w120.invalid_targets = TT_AIRBORNE | TT_INFANTRY;
    w120.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR;
    set_versus(w120, 30, 75, 75, 115, 50);

    Weapon tusk; tusk.range = 6656; tusk.reload = 60; tusk.burst = 2; tusk.burst_delay = 5;
    tusk.damage = 5000; tusk.spread = 256; tusk.min_range = 512;
    tusk.valid_targets = TT_AIRBORNE | TT_INFANTRY;
    set_versus(tusk, 100, 74, 60, 24, 50);

    Weapon flak_ag; flak_ag.range = 6144; flak_ag.reload = 10; flak_ag.damage = 2000; flak_ag.spread = 213;
    flak_ag.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR;
    set_versus(flak_ag, 40, 10, 60, 10, 20);
    Weapon flak_aa; flak_aa.range = 8192; flak_aa.reload = 10; flak_aa.damage = 1200; flak_aa.spread = 213;
    flak_aa.valid_targets = TT_AIRBORNE;

    Weapon dragon; dragon.range = 5120; dragon.reload = 50; dragon.damage = 5000; dragon.spread = 128;
    dragon.min_range = 512; dragon.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR;
    set_versus(dragon, 10, 74, 34, 100, 50);
    Weapon redeye; redeye.range = 7680; redeye.reload = 50; redeye.damage = 2400; redeye.spread = 128;
    redeye.min_range = 512; redeye.valid_targets = TT_AIRBORNE;
    set_versus(redeye, 10, 74, 100, 100, 50);

    Weapon w25; w25.range = 4864; w25.reload = 21; w25.damage = 2500; w25.spread = 128;
    w25.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR;
    set_versus(w25, 32, 52, 116, 48, 32);

    Weapon w8in; w8in.range = 20480; w8in.reload = 250; w8in.burst = 2; w8in.burst_delay = 5;
    w8in.damage = 2500; w8in.spread = 213; w8in.min_range = 3072;
    w8in.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR;
    set_versus(w8in, 60, 35, 60, 25, 100);
    const int i120 = w.define_weapon(w120), itusk = w.define_weapon(tusk);
    const int iag = w.define_weapon(flak_ag), iaa = w.define_weapon(flak_aa);
    const int idr = w.define_weapon(dragon), ire = w.define_weapon(redeye);
    const int i25 = w.define_weapon(w25), i8 = w.define_weapon(w8in);


    auto shooter = [](int32_t primary, int32_t secondary, int32_t armor) {
        UnitType t;
        t.speed = 1; t.turn_rate = 1024; t.facing_tolerance = 1024; t.hp = 400000; t.armor = armor;
        t.hit_radius = 426; t.weapon = primary; t.weapon_secondary = secondary;
        t.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
        t.auto_target_mask = TT_INFANTRY | TT_VEHICLE | TT_AIRBORNE;
        return t;
    };
    const int t_4tnk = w.define_type(shooter(i120, itusk, ARMOR_HEAVY));
    const int t_ftrk = w.define_type(shooter(iag, iaa, ARMOR_LIGHT));
    UnitType e3 = shooter(idr, ire, ARMOR_NONE);
    e3.infantry = true; e3.hit_radius = 128; e3.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_e3 = w.define_type(e3);
    const int t_1tnk = w.define_type(shooter(i25, -1, ARMOR_HEAVY));

    const int t_ca = w.define_type(shooter(i8, i8, ARMOR_HEAVY));


    UnitType foot; foot.speed = 1; foot.turn_rate = 1024; foot.infantry = true; foot.hp = 400000;
    foot.hit_radius = 128; foot.armor = ARMOR_NONE; foot.no_auto_target = true;
    foot.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    UnitType tank; tank.speed = 1; tank.turn_rate = 1024; tank.hp = 400000; tank.hit_radius = 426;
    tank.armor = ARMOR_HEAVY; tank.no_auto_target = true;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType plane; plane.aircraft = true; plane.can_hover = true; plane.speed = 1; plane.turn_rate = 16;
    plane.cruise_altitude = 1280; plane.hp = 400000; plane.hit_radius = 426; plane.armor = ARMOR_LIGHT;
    plane.no_auto_target = true; plane.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    plane.target_types_airborne = TT_AIRBORNE;
    const int t_foot = w.define_type(foot), t_tank = w.define_type(tank), t_plane = w.define_type(plane);


    struct Pair { const char* name; int shooter; int target; bool air; int cells; int per_hit; int hits; };
    const Pair pairs[] = {
        {"4TNK MammothTusk gegen Infanterie", t_4tnk, t_foot, false, 4, 5000, 2},
        {"4TNK 120mm gegen Panzer",           t_4tnk, t_tank, false, 4, 6900, 2},
        {"4TNK MammothTusk gegen Flugzeug",   t_4tnk, t_plane, true, 4, 3000, 2},
        {"FTRK FLAK-23-AG gegen Infanterie",  t_ftrk, t_foot, false, 4,  800, 0},
        {"FTRK FLAK-23-AA gegen Flugzeug",    t_ftrk, t_plane, true, 4, 1200, 0},
        {"E3 Dragon gegen Panzer",            t_e3,   t_tank, false, 4, 5000, 1},
        {"E3 RedEye gegen Flugzeug",          t_e3,   t_plane, true, 4, 2400, 1},
        {"1TNK 25mm gegen Panzer",            t_1tnk, t_tank, false, 4, 1200, 0},
        {"CA zwei 8Inch-Türme gegen Panzer",  t_ca,   t_tank, false, 6,  625, 4},
    };
    const int n = int(sizeof(pairs) / sizeof(pairs[0]));
    std::vector<int32_t> tids;
    for (int k = 0; k < n; ++k) {
        const int x = 6 + (k % 3) * 30, y = 8 + (k / 3) * 20;
        w.spawn(pairs[k].shooter, 0, {x, y});
        tids.push_back(w.spawn(pairs[k].target, 1, {x + pairs[k].cells, y}, 0, 100, pairs[k].air));
    }
    for (int t = 0; t < 40; ++t) w.step();
    for (int k = 0; k < n; ++k) {
        const int idx = w.index_of(tids[size_t(k)]);
        CHECK(idx >= 0);
        const int32_t dmg = 400000 - w.actor(size_t(idx)).hp;
        std::printf("  %-38s %6d Schaden = %d x %d\n", pairs[k].name, dmg,
                    dmg / pairs[k].per_hit, pairs[k].per_hit);
        CHECK(dmg > 0);
        CHECK(dmg % pairs[k].per_hit == 0);
        if (pairs[k].hits > 0) CHECK(dmg == pairs[k].per_hit * pairs[k].hits);
    }
    std::printf("Bewaffnung/Versus: %d Paarungen mit dem erwarteten Schaden\n", n);
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

    EffectSeq up; up.first_frame = 0; up.length = 4; up.ticks_per_frame = 1;
    EffectSeq down; down.first_frame = 10; down.length = 4; down.ticks_per_frame = 1;
    const int fx_up = w.define_effect(up);
    const int fx_down = w.define_effect(down);
    UnitType mslo = iron; mslo.support_power = SP_NUKE; mslo.sp_weapon = w_nuke; mslo.sp_flight = 40; mslo.sp_notify_ready = -1;
    mslo.sp_launch_effect = fx_up; mslo.sp_impact_effect = fx_down;
    const int t_iron = w.define_type(iron), t_pdox = w.define_type(pdox), t_mslo = w.define_type(mslo);
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 10000;
    const int t_tank = w.define_type(tank);
    w.spawn_building(t_iron, 0, {2, 2});
    w.spawn_building(t_pdox, 0, {2, 6});
    const int32_t silo_id = w.spawn_building(t_mslo, 0, {2, 10});
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
    const size_t si = size_t(w.index_of(silo_id));
    CHECK(w.activate_support_power(0, SP_NUKE, {25, 25}, {0, 0}));

    CHECK(w.actor(si).active_ticks > 0);


    auto nuke_sprite = [&](int32_t seq, WVec& pos, WDist& alt) {
        std::vector<RenderSprite> rs;
        w.render_sprites(0, rs);
        for (const RenderSprite& r : rs)
            if (r.weapon < 0 && r.seq == seq) { pos = WVec{r.x, r.y}; alt = r.alt; return true; }
        return false;
    };
    WVec up_pos{}, down_pos{};
    WDist up_alt0 = 0, up_alt1 = 0, down_alt0 = 0, down_alt1 = 0;
    CHECK(nuke_sprite(fx_up, up_pos, up_alt0));
    CHECK(up_pos.x == w.actor(si).pos.x && up_pos.y == w.actor(si).pos.y);
    CHECK(up_alt0 == 0);
    for (int t = 0; t < 10; ++t) w.step();
    CHECK(nuke_sprite(fx_up, up_pos, up_alt1));
    CHECK(up_alt1 > up_alt0);
    for (int t = 0; t < 15; ++t) w.step();
    CHECK(nuke_sprite(fx_down, down_pos, down_alt0));
    CHECK(down_pos.x / CELL == 25 && down_pos.y / CELL == 25);
    for (int t = 0; t < 10; ++t) w.step();
    CHECK(nuke_sprite(fx_down, down_pos, down_alt1));
    CHECK(down_alt1 < down_alt0);
    CHECK(w.actor(ei).hp == 10000);
    for (int t = 0; t < 4; ++t) w.step();
    CHECK(w.actor(ei).hp == 10000);
    w.step();
    CHECK(w.actor(ei).hp < 10000);
    {
        std::vector<RenderSprite> rs;
        w.render_sprites(0, rs);
        for (const RenderSprite& r : rs) CHECK(!(r.weapon < 0 && (r.seq == fx_up || r.seq == fx_down)));
    }
    (void)my_tank;
    std::printf("Superwaffen OK (Gegner nach Atomschlag %d HP; Rakete stieg auf %d, sank von %d, Silo-Klappe lief)\n",
                w.actor(ei).hp, up_alt1, down_alt0);
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


static void test_nuke_falloff_rings() {
    World w;
    std::vector<uint8_t> cost(60 * 60, 1);
    w.set_map(60, 60, cost.data());
    Weapon atomic = make_atomic_weapon();
    atomic.reload = 1000000;
    const int w_nuke = w.define_weapon(atomic);


    UnitType sensor;
    sensor.speed = 0; sensor.turn_rate = 1024; sensor.hp = 1000000; sensor.armor = ARMOR_NONE;
    sensor.hit_radius = 0; sensor.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_sensor = w.define_type(sensor);
    UnitType launcher;
    launcher.speed = 1; launcher.turn_rate = 1024; launcher.hp = 100000; launcher.weapon = w_nuke;
    launcher.facing_tolerance = 1024; launcher.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_launcher = w.define_type(launcher);

    const CPos ground_zero{30, 30};
    const int32_t expect[7] = {390000, 246600, 162990, 113520, 80040, 60090, 45540};
    int32_t ids[7];
    for (int c = 0; c < 7; ++c) ids[c] = w.spawn(t_sensor, 1, {30 + c, 30});

    const int32_t launcher_id = w.spawn(t_launcher, 0, {5, 30});
    w.order_attack_cell(&launcher_id, 1, ground_zero);
    for (int t = 0; t < 60; ++t) w.step();

    bool ok = true;
    for (int c = 0; c < 7; ++c) {
        const int i = w.index_of(ids[c]);
        const int32_t got = 1000000 - w.actor(size_t(i)).hp;
        std::printf("Atombombe Ring %d Zellen: %d Schaden (OpenRA-Formel %d)\n", c, got, expect[c]);
        CHECK(got == expect[c]);
        ok = ok && got == expect[c];
    }
    (void)ok;
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


static uint64_t state_hash(const World& w);


static void test_deploy_special() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    w.set_alliance(0, 1, false);

    Weapon thump;
    thump.damage = 1; thump.damage_percent = true; thump.spread = 7 * CELL;
    thump.falloff_steps = 2; thump.falloff[0] = 100; thump.falloff[1] = 100;
    const int32_t w_thump = w.define_weapon(thump);
    Weapon boom;
    boom.damage = 19; boom.damage_percent = true; boom.spread = 7 * CELL;
    boom.falloff_steps = 2; boom.falloff[0] = 100; boom.falloff[1] = 100;
    const int32_t w_boom = w.define_weapon(boom);
    Weapon nuke;
    nuke.damage = 15000; nuke.spread = CELL;
    const int32_t w_nuke = w.define_weapon(nuke);

    UnitType e1; e1.speed = 40; e1.turn_rate = 1024; e1.hp = 5000; e1.infantry = true; e1.locomotor = LOCO_FOOT;
    const int32_t t_e1 = w.define_type(e1);
    UnitType qtnk; qtnk.speed = 46; qtnk.turn_rate = 1024; qtnk.hp = 90000; qtnk.armor = ARMOR_HEAVY;
    qtnk.mad_charge_delay = 96; qtnk.mad_detonation_delay = 42; qtnk.mad_thump_interval = 8;
    qtnk.mad_thump_weapon = w_thump; qtnk.mad_detonation_weapon = w_boom;
    const int32_t t_qtnk = w.define_type(qtnk);
    w.set_mad_driver(t_qtnk, t_e1);
    UnitType dtrk; dtrk.speed = 67; dtrk.turn_rate = 1024; dtrk.hp = 2800; dtrk.armor = ARMOR_LIGHT;
    dtrk.detonate_on_deploy = true; dtrk.death_weapon = w_nuke;
    const int32_t t_dtrk = w.define_type(dtrk);
    UnitType ctnk; ctnk.speed = 86; ctnk.turn_rate = 1024; ctnk.hp = 40000; ctnk.armor = ARMOR_LIGHT;
    ctnk.chrono_charge_delay = 250; ctnk.chrono_max_distance = 12;
    const int32_t t_ctnk = w.define_type(ctnk);
    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 40000; tank.armor = ARMOR_HEAVY;
    const int32_t t_tank = w.define_type(tank);
    UnitType bldg; bldg.building = true; bldg.foot_w = 2; bldg.foot_h = 2; bldg.footprint = {1, 1, 1, 1};
    bldg.sprite_h = 2; bldg.hp = 40000; bldg.armor = ARMOR_WOOD;
    const int32_t t_bldg = w.define_type(bldg);


    const int32_t mad = w.spawn(t_qtnk, 0, {10, 10});
    const int32_t victim = w.spawn(t_tank, 1, {13, 10});
    const int32_t bldg_id = w.spawn_building(t_bldg, 1, {14, 12});
    const int32_t far_away = w.spawn(t_tank, 1, {30, 10});
    CHECK(w.can_detonate(mad));
    CHECK(!w.detonating(mad));
    w.order_detonate(&mad, 1);
    CHECK(w.detonating(mad));
    CHECK(!w.can_detonate(mad));

    int drivers = 0;
    for (size_t i = 0; i < w.actor_count(); ++i) if (w.actor(i).alive && w.actor(i).type == t_e1) ++drivers;
    CHECK(drivers == 1);

    const WVec mad_pos = w.actor(size_t(w.index_of(mad))).pos;
    w.order_move(&mad, 1, {20, 20});
    for (int t = 0; t < 40; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(mad))).pos == mad_pos);

    const int32_t hp_after_thumps = w.actor(size_t(w.index_of(victim))).hp;
    CHECK(hp_after_thumps < 40000 && hp_after_thumps > 30000);
    CHECK(w.actor(size_t(w.index_of(far_away))).hp == 40000);

    for (int t = 0; t < 110; ++t) w.step();
    CHECK(!w.actor(size_t(w.index_of(mad))).alive);
    const int32_t hp_end = w.actor(size_t(w.index_of(victim))).hp;

    CHECK(hp_end < 27000 && hp_end > 24000);
    CHECK(w.actor(size_t(w.index_of(bldg_id))).hp < 40000);
    CHECK(w.actor(size_t(w.index_of(far_away))).hp == 40000);


    const int32_t truck = w.spawn(t_dtrk, 0, {20, 30});
    const int32_t near_truck = w.spawn(t_tank, 1, {20, 31});
    CHECK(w.can_detonate(truck));
    w.order_detonate(&truck, 1);
    w.step();
    CHECK(!w.actor(size_t(w.index_of(truck))).alive);
    CHECK(w.actor(size_t(w.index_of(near_truck))).hp < 40000);


    const int32_t ct = w.spawn(t_ctnk, 0, {5, 30});
    CHECK(w.can_chrono(ct));
    CHECK(w.chrono_max_cells(ct) == 12);
    CHECK(w.order_chrono(&ct, 1, {5, 25}));
    CHECK(w.actor(size_t(w.index_of(ct))).pos == cell_center(CPos{5, 25}));
    CHECK(!w.can_chrono(ct));
    CHECK(w.chrono_charge_left(ct) == 250);
    CHECK(!w.order_chrono(&ct, 1, {5, 20}));
    for (int t = 0; t < 250; ++t) w.step();
    CHECK(w.can_chrono(ct));

    CHECK(w.order_chrono(&ct, 1, {5, 5}));
    const CPos landed = w.mobile(size_t(w.index_of(ct))).cell;
    CHECK(landed.y >= 12 && landed.y <= 14);


    UnitType ctnk_far = ctnk; ctnk_far.chrono_max_distance = 0;
    const int32_t t_ctnk_far = w.define_type(ctnk_far);
    const int32_t ctf = w.spawn(t_ctnk_far, 0, {3, 3});
    CHECK(w.chrono_max_cells(ctf) == 0);
    CHECK(w.can_chrono(ctf));
    CHECK(w.order_chrono(&ctf, 1, {36, 36}));
    const CPos far_landed = w.mobile(size_t(w.index_of(ctf))).cell;
    CHECK(far_landed.x == 36 && far_landed.y == 36);
    CHECK(w.chrono_charge_left(ctf) == 250);
    std::printf("Chrono: unbegrenzter Sprung 3,3 → %d,%d (33 Zellen je Achse), Abklingzeit %d Ticks\n",
                far_landed.x, far_landed.y, w.chrono_charge_left(ctf));
    for (int t = 0; t < 250; ++t) w.step();
    CHECK(w.can_chrono(ctf));

    CHECK(!w.order_chrono(&ctf, 1, {-5, 30}));
    CHECK(w.can_chrono(ctf));


    World w2;
    w2.set_map(40, 40, cost.data());
    w2.set_alliance(0, 1, false);
    w2.define_weapon(thump); w2.define_weapon(boom); w2.define_weapon(nuke);
    w2.define_type(e1); w2.define_type(qtnk); w2.define_type(dtrk); w2.define_type(ctnk);
    w2.define_type(tank); w2.define_type(bldg);
    w2.set_mad_driver(t_qtnk, t_e1);
    const int32_t mad2 = w2.spawn(t_qtnk, 0, {10, 10});
    w2.spawn(t_tank, 1, {13, 10});
    w2.order_detonate(&mad2, 1);
    for (int t = 0; t < 50; ++t) w2.step();
    std::vector<uint8_t> blob;
    CHECK(w2.save(blob));
    World w3;
    w3.set_map(40, 40, cost.data());
    w3.set_alliance(0, 1, false);
    w3.define_weapon(thump); w3.define_weapon(boom); w3.define_weapon(nuke);
    w3.define_type(e1); w3.define_type(qtnk); w3.define_type(dtrk); w3.define_type(ctnk);
    w3.define_type(tank); w3.define_type(bldg);
    w3.set_mad_driver(t_qtnk, t_e1);
    CHECK(w3.load(blob));
    CHECK(w3.detonating(mad2));
    for (int t = 0; t < 120; ++t) { w2.step(); w3.step(); }
    CHECK(state_hash(w2) == state_hash(w3));
    CHECK(!w3.actor(size_t(w3.index_of(mad2))).alive);
    std::printf("Entfalten OK (MAD-Panzer detoniert, LKW zündet, Chrono springt %d Zellen)\n",
                25 - landed.y);
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


        crate.passenger_weight = 1; crate.fall_rate = 26;
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
        std::vector<uint8_t> cost(40 * 40, 1);
        w.set_map(40, 40, cost.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 100, 0);
        UnitType badr;
        badr.speed = 180; badr.turn_rate = 20; badr.hp = 10000; badr.aircraft = true;
        badr.cruise_altitude = 2560; badr.altitude_velocity = 43; badr.cargo_max_weight = 10;
        const int t_badr = w.define_type(badr);
        CrateSpawnerParams p;
        p.enabled = true; p.crate_type = tc; p.minimum = 1; p.maximum = 1;
        p.spawn_interval = 100000; p.initial_delay = 1;
        p.delivery_type = t_badr; p.quantized_facings = 16;
        w.set_crate_spawner(p);
        w.step();

        int planes = 0;
        for (size_t i = 0; i < w.actor_count(); ++i)
            if (w.actor(i).alive && w.actor(i).type == t_badr) ++planes;
        CHECK(planes == 1);
        CHECK(w.crate_count() == 1);
        int in_transport = 0;
        for (size_t i = 0; i < w.actor_count(); ++i)
            if (w.actor(i).alive && w.actor(i).type == tc && w.actor(i).transport >= 0) ++in_transport;
        CHECK(in_transport == 1);

        bool dropped = false, landed = false;
        int alt_seen = 0;
        for (int t = 0; t < 4000 && !landed; ++t) {
            w.step();
            for (size_t i = 0; i < w.actor_count(); ++i) {
                const Actor& a = w.actor(i);
                if (!a.alive || a.type != tc || a.transport >= 0) continue;
                dropped = true;
                if (w.air(i).alt > 0) alt_seen = w.air(i).alt;
                else if (dropped) landed = true;
            }
        }
        CHECK(dropped);
        CHECK(alt_seen > 0);
        CHECK(landed);

        int left = 0;
        for (int t = 0; t < 3000; ++t) {
            w.step();
            left = 0;
            for (size_t i = 0; i < w.actor_count(); ++i)
                if (w.actor(i).alive && w.actor(i).type == t_badr) ++left;
            if (left == 0) break;
        }
        CHECK(left == 0);
        CHECK(w.crate_count() == 1);
        std::printf("Kisten: Badger warf die Kiste am Fallschirm ab (Höhe %d), flog weiter und verschwand\n", alt_seen);
    }


    {
        World w;
        std::vector<uint8_t> terrain(20 * 20, uint8_t(TER_CLEAR));
        w.set_terrain(20, 20, terrain.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 0, 0);
        UnitType boat; boat.speed = 44; boat.turn_rate = 1024; boat.hp = 80000;
        boat.locomotor = LOCO_NAVAL; boat.cost = 2400;
        const int32_t tb = w.define_type(boat);
        CrateAction ship; ship.kind = CRATE_UNIT; ship.shares = 100; ship.units = {tb};
        UnitType crate; crate.crate = true; crate.crate_duration = 0; crate.targetable = false;
        crate.crush_classes = CRUSH_CRATE; crate.hp = 1;
        crate.crate_actions = {ship};
        const int32_t tcs = w.define_type(crate);
        w.spawn(tcs, 1, {8, 5});
        const int32_t tid = w.spawn(tt, 0, {2, 5});
        w.order_move(&tid, 1, {15, 5}, 0);
        for (int t = 0; t < 400; ++t) w.step();
        int ships = 0;
        for (size_t i = 0; i < w.actor_count(); ++i)
            if (w.actor(i).alive && w.actor(i).type == tb) ++ships;
        CHECK(w.crate_count() == 0);
        CHECK(ships == 0);
        std::printf("Kisten: Karte ohne Wasser gibt kein Schiff aus (%d Schiffe)\n", ships);
    }

    {
        World w;
        std::vector<uint8_t> terrain(20 * 20, uint8_t(TER_CLEAR));
        for (int x = 0; x < 20; ++x) terrain[size_t(7 * 20 + x)] = uint8_t(TER_WATER);
        w.set_terrain(20, 20, terrain.data());
        int32_t tc = 0, tt = 0, ti = 0;
        make(w, tc, tt, ti, 0, 0);
        UnitType boat; boat.speed = 44; boat.turn_rate = 1024; boat.hp = 80000;
        boat.locomotor = LOCO_NAVAL; boat.cost = 2400;
        const int32_t tb = w.define_type(boat);
        CrateAction ship; ship.kind = CRATE_UNIT; ship.shares = 100; ship.units = {tb};
        UnitType crate; crate.crate = true; crate.crate_duration = 0; crate.targetable = false;
        crate.crush_classes = CRUSH_CRATE; crate.hp = 1;
        crate.crate_actions = {ship};
        const int32_t tcs = w.define_type(crate);
        w.spawn(tcs, 1, {8, 5});
        const int32_t tid = w.spawn(tt, 0, {2, 5});
        w.order_move(&tid, 1, {15, 5}, 0);
        for (int t = 0; t < 400; ++t) w.step();
        int ships = 0;
        for (size_t i = 0; i < w.actor_count(); ++i)
            if (w.actor(i).alive && w.actor(i).type == tb) {
                ++ships;
                CHECK(w.map().terrain(w.mobile(i).cell) == TER_WATER);
            }
        CHECK(ships == 1);
        std::printf("Kisten: mit Wasser in Reichweite kommt das Schiff aufs Wasser\n");
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


    {
        World w;
        std::vector<uint8_t> cost(20 * 20, 0);
        for (int x = 0; x < 20; ++x) cost[size_t(5 * 20 + x)] = 1;
        w.set_map(20, 20, cost.data());
        w.set_alliance(0, 1, false);

        Weapon boom;
        boom.damage = 5000; boom.spread = 426;
        boom.falloff_steps = 7;
        const int32_t fo[7] = {1000, 368, 135, 50, 18, 7, 0};
        for (int k = 0; k < 7; ++k) boom.falloff[k] = fo[k];
        for (int k = 0; k < NUM_ARMOR; ++k) boom.versus[k] = 100;
        boom.versus[ARMOR_NONE] = 90; boom.versus[ARMOR_WOOD] = 75;
        boom.versus[ARMOR_LIGHT] = 60; boom.versus[ARMOR_HEAVY] = 25;
        const int32_t w_boom = w.define_weapon(boom);

        UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 40000;
        tank.armor = ARMOR_HEAVY; tank.crushes = CRUSH_CRATE;
        const int32_t tt2 = w.define_type(tank);
        UnitType crate; crate.crate = true; crate.crate_duration = 0; crate.targetable = false;
        crate.crush_classes = CRUSH_CRATE; crate.hp = 1;
        CrateAction boomca; boomca.kind = CRATE_EXPLODE; boomca.shares = 100; boomca.weapon = w_boom;
        crate.crate_actions = {boomca};
        const int32_t tcb = w.define_type(crate);

        w.spawn(tcb, 1, {8, 5});
        const int32_t tid = w.spawn(tt2, 0, {2, 5});
        const int32_t mate = w.spawn(tt2, 0, {9, 5});
        const int32_t away = w.spawn(tt2, 0, {18, 5});
        w.order_move(&tid, 1, {8, 5}, 0);
        for (int t = 0; t < 400; ++t) w.step();
        CHECK(w.crate_count() == 0);
        const int32_t hp_col = w.actor(size_t(w.index_of(tid))).hp;
        const int32_t hp_mate = w.actor(size_t(w.index_of(mate))).hp;
        const int32_t hp_away = w.actor(size_t(w.index_of(away))).hp;


        CHECK(hp_col == 40000 - 12500);
        CHECK(hp_mate < 40000);
        CHECK(hp_away == 40000);
        std::printf("Kisten: Explosionskiste — Sammler %d (−12500), eigener Nachbar %d, 10 Zellen weit %d\n",
                    hp_col, hp_mate, hp_away);
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


static void test_defense_attacks_buildings() {

    Weapon flame;
    flame.damage = 8000; flame.spread = 100; flame.range = 5 * CELL; flame.reload = 20; flame.speed = 250;
    flame.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR;
    for (int i = 0; i < NUM_ARMOR; ++i) flame.versus[i] = 100;


    const uint32_t auto_ground = TT_INFANTRY | TT_VEHICLE | TT_SHIP | TT_UNDERWATER | TT_DEFENSE | TT_MINE;

    UnitType ftur;
    ftur.building = true; ftur.foot_w = 1; ftur.foot_h = 1; ftur.footprint = {1};
    ftur.hp = 40000; ftur.targetable = true; ftur.turreted = true; ftur.turret_count = 1;
    ftur.turret_turn = 512; ftur.facing_tolerance = 1024;
    ftur.target_types = TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE;
    ftur.auto_target_mask = auto_ground;

    UnitType hall;
    hall.building = true; hall.foot_w = 2; hall.foot_h = 2; hall.footprint = {1, 1, 1, 1};
    hall.hp = 30000; hall.targetable = true; hall.armor = ARMOR_WOOD;
    hall.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;

    UnitType tnk;
    tnk.speed = 72; tnk.turn_rate = 1024; tnk.hp = 40000; tnk.targetable = true;
    tnk.turreted = true; tnk.turret_count = 1; tnk.turret_turn = 512; tnk.facing_tolerance = 1024;
    tnk.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    tnk.auto_target_mask = auto_ground;


    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());
    const int w_flame = w.define_weapon(flame);
    UnitType a_ftur = ftur; a_ftur.weapon = w_flame;
    UnitType a_tnk = tnk; a_tnk.weapon = w_flame;
    const int t_ftur = w.define_type(a_ftur), t_hall = w.define_type(hall), t_tnk = w.define_type(a_tnk);
    const int32_t turret = w.spawn_building(t_ftur, 0, {10, 10});
    const int32_t foe = w.spawn_building(t_hall, 1, {13, 10});
    const int32_t foe_hp0 = w.actor(size_t(w.index_of(foe))).hp;
    int first_hit = -1, killed = -1;
    for (int t = 0; t < 400; ++t) {
        w.step();
        const int fi = w.index_of(foe);
        if (fi < 0 || !w.actor(size_t(fi)).alive) { killed = t; break; }
        if (first_hit < 0 && w.actor(size_t(fi)).hp < foe_hp0) first_hit = t;
    }
    CHECK(first_hit >= 0 && first_hit <= 30);
    CHECK(killed > 0);
    CHECK(w.actor(size_t(w.index_of(turret))).alive);


    World v;
    std::vector<uint8_t> vcost(30 * 30, 1);
    v.set_map(30, 30, vcost.data());
    const int v_flame = v.define_weapon(flame);
    UnitType v_tnk = tnk; v_tnk.weapon = v_flame;
    const int vt_tnk = v.define_type(v_tnk), vt_hall = v.define_type(hall);
    v.spawn(vt_tnk, 0, {10, 10});
    const int32_t vfoe = v.spawn_building(vt_hall, 1, {13, 10});
    const int32_t vfoe_hp0 = v.actor(size_t(v.index_of(vfoe))).hp;
    for (int t = 0; t < 200; ++t) v.step();
    CHECK(v.actor(size_t(v.index_of(vfoe))).hp == vfoe_hp0);


    World f;
    std::vector<uint8_t> fcost(30 * 30, 1);
    f.set_map(30, 30, fcost.data());
    const int f_flame = f.define_weapon(flame);
    UnitType f_ftur = ftur; f_ftur.weapon = f_flame;
    const int ft_ftur = f.define_type(f_ftur), ft_hall = f.define_type(hall);
    const int32_t f_turret = f.spawn_building(ft_ftur, 0, {10, 10});
    const int32_t own = f.spawn_building(ft_hall, 0, {13, 10});
    const int32_t own_hp0 = f.actor(size_t(f.index_of(own))).hp;
    f.order_attack(&f_turret, 1, own, false);
    for (int t = 0; t < 60; ++t) f.step();
    CHECK(!f.force_attacking(f_turret));
    CHECK(f.actor(size_t(f.index_of(own))).hp == own_hp0);
    f.order_attack(&f_turret, 1, own, true);
    CHECK(f.force_attacking(f_turret));
    int f_killed = -1;
    for (int t = 0; t < 400; ++t) {
        f.step();
        const int oi = f.index_of(own);
        if (oi < 0 || !f.actor(size_t(oi)).alive) { f_killed = t; break; }

        CHECK(f.force_attacking(f_turret));
    }
    CHECK(f_killed > 0);
    CHECK(!f.force_attacking(f_turret));


    World g;
    std::vector<uint8_t> gcost(40 * 40, 1);
    g.set_map(40, 40, gcost.data());
    const int g_flame = g.define_weapon(flame);
    UnitType g_ftur = ftur; g_ftur.weapon = g_flame;
    const int gt_ftur = g.define_type(g_ftur), gt_hall = g.define_type(hall);
    const int32_t g_turret = g.spawn_building(gt_ftur, 0, {10, 10});
    const int32_t far_own = g.spawn_building(gt_hall, 0, {30, 10});
    g.order_attack(&g_turret, 1, far_own, true);
    for (int t = 0; t < 20; ++t) g.step();
    CHECK(!g.force_attacking(g_turret));
    CHECK(g.actor(size_t(g.index_of(far_own))).alive);
    const int32_t near_foe = g.spawn_building(gt_hall, 1, {13, 10});
    const int32_t near_hp0 = g.actor(size_t(g.index_of(near_foe))).hp;
    for (int t = 0; t < 60; ++t) g.step();
    CHECK(g.actor(size_t(g.index_of(near_foe))).hp < near_hp0);

    std::printf("Wehrturm: Gebäude automatisch ab Tick %d, zerstört nach %d Ticks; Fahrzeug lässt es "
                "stehen; Zwangsfeuer aufs eigene Gebäude hält %d Ticks bis zur Zerstörung; "
                "Ziel außer Reichweite verworfen, Turm bleibt wach\n", first_hit, killed, f_killed);
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


static void test_tesla_tank() {
    World w;
    std::vector<uint8_t> cost(30 * 30, 1);
    w.set_map(30, 30, cost.data());
    w.set_alliance(0, 1, false);
    EffectSeq lit; lit.first_frame = 200; lit.length = 4; lit.ticks_per_frame = 1;
    const int fx_bright = w.define_effect(lit);
    lit.first_frame = 204;
    const int fx_dim = w.define_effect(lit);
    Weapon ttz;
    ttz.range = 7 * CELL; ttz.reload = 120; ttz.damage = 10000; ttz.spread = 42; ttz.speed = 0;
    for (int i = 0; i < NUM_ARMOR; ++i) ttz.versus[i] = 100;
    ttz.versus[ARMOR_NONE] = 1000;
    ttz.zap_duration = 2; ttz.zap_bright = fx_bright; ttz.zap_dim = fx_dim;
    const int w_ttz = w.define_weapon(ttz);

    UnitType ttnk;
    ttnk.speed = 92; ttnk.turn_rate = 20; ttnk.hp = 40000; ttnk.armor = ARMOR_LIGHT;
    ttnk.weapon = w_ttz; ttnk.turreted = true; ttnk.turret_turn = 512; ttnk.facing_tolerance = 1024;
    ttnk.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    ttnk.auto_target_mask = TT_INFANTRY | TT_VEHICLE | TT_DEFENSE;
    const int t_ttnk = w.define_type(ttnk);
    UnitType foot;
    foot.speed = 1; foot.turn_rate = 1024; foot.infantry = true; foot.hp = 5000; foot.armor = ARMOR_NONE;
    foot.target_types = TT_GROUND_ACTOR | TT_INFANTRY; foot.no_auto_target = true;
    UnitType tank;
    tank.speed = 1; tank.turn_rate = 1024; tank.hp = 400000; tank.armor = ARMOR_HEAVY;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tank.no_auto_target = true;
    UnitType hut;
    hut.building = true; hut.foot_w = 1; hut.foot_h = 1; hut.footprint = {1};
    hut.hp = 400000; hut.armor = ARMOR_WOOD; hut.target_types = TT_GROUND_ACTOR;
    const int t_foot = w.define_type(foot), t_tank = w.define_type(tank), t_hut = w.define_type(hut);


    const int32_t shooter = w.spawn(t_ttnk, 0, {5, 5});
    const int32_t far_id = w.spawn(t_tank, 1, {20, 5});
    for (int t = 0; t < 40; ++t) w.step();
    CHECK(w.actor(1).hp == 400000);
    w.destroy(far_id);


    const int32_t tank_id = w.spawn(t_tank, 1, {11, 5});
    (void)tank_id;
    const size_t ti = size_t(w.index_of(tank_id));
    int32_t zap_seen = 0;
    for (int t = 0; t < 40; ++t) { w.step(); zap_seen += int32_t(w.zaps().size()); }
    const int32_t on_tank = 400000 - w.actor(ti).hp;
    CHECK(on_tank == 10000);
    CHECK(zap_seen >= 1);
    std::printf("Tesla-Panzer: %d Schaden am schweren Panzer, Blitz %d Ticks sichtbar\n", on_tank, zap_seen);
    for (int t = 0; t < 100; ++t) w.step();
    CHECK(400000 - w.actor(ti).hp == 20000);
    w.destroy(tank_id);


    const int32_t man = w.spawn(t_foot, 1, {9, 5});
    const size_t mi = size_t(w.index_of(man));
    for (int t = 0; t < 140 && w.actor(mi).alive; ++t) w.step();
    CHECK(!w.actor(mi).alive);
    std::printf("Tesla-Panzer: Fußtruppe nach einem Blitz tot (Versus None 1000)\n");


    const int32_t bld = w.spawn_building(t_hut, 1, {9, 9});
    const size_t bi = size_t(w.index_of(bld));
    const int32_t hut_hp = w.actor(bi).hp;
    w.order_attack(&shooter, 1, bld);
    for (int t = 0; t < 200 && w.actor(bi).hp == hut_hp; ++t) w.step();
    CHECK(hut_hp - w.actor(bi).hp == 10000);
    std::printf("Tesla-Panzer: %d Schaden am Holzgebäude (TTankZap ohne Wood-Abschlag)\n",
                hut_hp - w.actor(bi).hp);
}


static void test_side_prerequisites() {
    World w;
    std::vector<uint8_t> cost(20 * 20, 1);
    w.set_map(20, 20, cost.data());
    UnitType weap;
    weap.building = true; weap.foot_w = 1; weap.foot_h = 1; weap.footprint = {1};
    weap.hp = 40000;
    weap.provides = {"vehicles.soviet", "vehicles.russia", "vehicles.ukraine",
                     "vehicles.allies", "vehicles.england", "vehicles.france", "vehicles.germany"};
    weap.provides_factions = {"soviet,russia,ukraine", "russia,soviet", "ukraine,soviet",
                              "allies,england,france,germany", "england,allies", "france,allies", "germany,allies"};
    const int t_weap = w.define_type(weap);
    UnitType ttnk; ttnk.hp = 40000; ttnk.cost = 1350; ttnk.queue_kind = QUEUE_VEHICLE;
    ttnk.prerequisites = {"vehicles.russia"}; ttnk.prerequisites_hidden = {"vehicles.russia"};
    UnitType dtrk = ttnk; dtrk.cost = 2500;
    dtrk.prerequisites = {"vehicles.ukraine"}; dtrk.prerequisites_hidden = {"vehicles.ukraine"};
    UnitType ctnk = ttnk;
    ctnk.prerequisites = {"vehicles.germany"}; ctnk.prerequisites_hidden = {"vehicles.germany"};
    UnitType stnk = ttnk; stnk.cost = 1000;
    stnk.prerequisites = {"vehicles.france"}; stnk.prerequisites_hidden = {"vehicles.france"};
    const int t_ttnk = w.define_type(ttnk), t_dtrk = w.define_type(dtrk);
    const int t_ctnk = w.define_type(ctnk), t_stnk = w.define_type(stnk);

    w.set_faction(0, "soviet");
    w.spawn_building(t_weap, 0, {5, 5});
    for (int t = 0; t < 4; ++t) w.step();
    CHECK(w.has_prerequisite(0, "vehicles.russia") && w.has_prerequisite(0, "vehicles.ukraine"));
    CHECK(!w.has_prerequisite(0, "vehicles.germany") && !w.has_prerequisite(0, "vehicles.france"));
    CHECK(!w.item_hidden(0, t_ttnk) && !w.item_hidden(0, t_dtrk));
    CHECK(w.item_hidden(0, t_ctnk) && w.item_hidden(0, t_stnk));

    w.set_faction(1, "allies");
    w.spawn_building(t_weap, 1, {12, 12});
    for (int t = 0; t < 4; ++t) w.step();
    CHECK(w.has_prerequisite(1, "vehicles.germany") && w.has_prerequisite(1, "vehicles.france")
          && w.has_prerequisite(1, "vehicles.england"));
    CHECK(!w.has_prerequisite(1, "vehicles.russia") && !w.has_prerequisite(1, "vehicles.ukraine"));
    CHECK(!w.item_hidden(1, t_ctnk) && !w.item_hidden(1, t_stnk));
    CHECK(w.item_hidden(1, t_ttnk) && w.item_hidden(1, t_dtrk));
    std::printf("Fraktionen: Sowjets bekommen russia+ukraine, Alliierte england+france+germany\n");
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


namespace seed_fixture {

inline UnitType mine_type(int32_t res) {
    UnitType m;
    m.building = true; m.foot_w = 1; m.foot_h = 1; m.footprint = {1}; m.build_block = m.footprint;
    m.hp = 1;
    m.seeds_resource = res; m.seed_interval = 75; m.seed_max_range = 100;
    return m;
}

inline int64_t total(World& w, int size, int32_t res) {
    int64_t s = 0;
    for (int y = 0; y < size; ++y)
        for (int x = 0; x < size; ++x)
            if (w.resource_type({x, y}) == res) s += w.resource_density({x, y});
    return s;
}

}


static void test_seeds_rate() {
    using namespace seed_fixture;
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    const int t = w.define_type(mine_type(RES_ORE));
    w.set_rng_seed(4711);
    w.spawn_building(t, 2, {32, 32});
    for (int i = 0; i < 1000; ++i) w.step();
    const int64_t grown = total(w, 64, RES_ORE);
    std::printf("Erzmine frei: %lld Dichtestufen je 1000 Ticks (OpenRA: 13)\n", (long long)grown);
    CHECK(grown >= 12 && grown <= 14);

    for (int y = 0; y < 64; ++y)
        for (int x = 0; x < 64; ++x)
            if (w.resource_density({x, y}) > 0)
                CHECK(std::abs(x - 32) <= 100 && std::abs(y - 32) <= 100);
}


static void test_seeds_none_without_mine() {
    using namespace seed_fixture;
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    w.set_rng_seed(4711);
    for (int y = 20; y < 26; ++y)
        for (int x = 20; x < 26; ++x) w.set_resource({x, y}, RES_ORE, 6);
    const int64_t before = total(w, 64, RES_ORE);
    for (int i = 0; i < 2000; ++i) w.step();
    CHECK(total(w, 64, RES_ORE) == before);
}


static void test_seeds_max_density() {
    using namespace seed_fixture;
    World w;
    std::vector<uint8_t> terrain(64 * 64, uint8_t(TER_CLEAR));

    for (int y = 0; y < 64; ++y)
        for (int x = 0; x < 64; ++x)
            if (x < 31 || x > 33 || y < 31 || y > 33) terrain[y * 64 + x] = uint8_t(TER_WATER);
    w.set_terrain(64, 64, terrain.data());
    const int t = w.define_type(mine_type(RES_ORE));
    w.set_rng_seed(99);
    w.spawn_building(t, 2, {32, 32});
    for (int i = 0; i < 120000; ++i) w.step();
    std::printf("Kessel 3x3: %lld von %d Stufen gefuellt\n", (long long)total(w, 64, RES_ORE), 8 * ORE_MAX_DENSITY);
    CHECK(total(w, 64, RES_ORE) == 8 * ORE_MAX_DENSITY);
    for (int y = 31; y <= 33; ++y)
        for (int x = 31; x <= 33; ++x)
            CHECK(w.resource_density({x, y}) <= ORE_MAX_DENSITY);
    CHECK(w.resource_density({32, 32}) == 0);
}


static void test_seeds_gems() {
    using namespace seed_fixture;
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    const int t = w.define_type(mine_type(RES_GEMS));
    w.set_rng_seed(2024);
    w.spawn_building(t, 2, {32, 32});
    for (int i = 0; i < 1000; ++i) w.step();
    const int64_t gems = total(w, 64, RES_GEMS);
    std::printf("Diamantmine: %lld Dichtestufen je 1000 Ticks (OpenRA: 13)\n", (long long)gems);
    CHECK(gems >= 12 && gems <= 14);
    CHECK(total(w, 64, RES_ORE) == 0);
    for (int y = 0; y < 64; ++y)
        for (int x = 0; x < 64; ++x)
            CHECK(w.resource_density({x, y}) <= GEMS_MAX_DENSITY);
}


static void test_seeds_blocked_walk() {
    using namespace seed_fixture;
    World w;
    std::vector<uint8_t> terrain(64 * 64, uint8_t(TER_CLEAR));

    for (int y = 0; y < 64; ++y)
        for (int x = 0; x < 64; ++x)
            if ((x < 27 || x > 37 || y < 27 || y > 37) && !(y == 32 && x >= 27 && x < 50))
                terrain[y * 64 + x] = uint8_t(TER_WATER);
    w.set_terrain(64, 64, terrain.data());
    const int t = w.define_type(mine_type(RES_ORE));
    w.set_rng_seed(31337);
    w.spawn_building(t, 2, {32, 32});
    for (int y = 27; y <= 37; ++y)
        for (int x = 27; x <= 37; ++x)
            if (!(x == 32 && y == 32)) w.set_resource({x, y}, RES_ORE, ORE_MAX_DENSITY);
    const int64_t before = total(w, 64, RES_ORE);
    for (int i = 0; i < 10000; ++i) w.step();
    const int64_t grown = total(w, 64, RES_ORE) - before;
    const int64_t free_rate = 133;
    std::printf("Erzmine im Kessel: %lld von %lld möglichen Streuungen (%lld %%)\n",
                (long long)grown, (long long)free_rate, (long long)(100 * grown / free_rate));
    CHECK(grown > 0);
    CHECK(grown < free_rate / 2);
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


namespace harv_fixture {


inline UnitType harv_type() {
    UnitType h;
    h.speed = 72; h.turn_rate = 1024; h.hp = 60000; h.harvester = true; h.capacity = 20;
    h.bale_load_delay = 4; h.bale_unload_delay = 1;
    h.search_from_proc = 15; h.search_from_harv = 8;
    h.wait_duration = 25; h.harvest_facings = 0;
    h.hit_radius = 512;
    return h;
}

inline UnitType proc_type() {
    UnitType p;
    p.building = true; p.foot_w = 3; p.foot_h = 3; p.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0};
    p.build_block = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    p.sprite_h = 3; p.hp = 90000; p.refinery = true; p.dock_dx = 1; p.dock_dy = 2; p.dock_angle = 256;
    return p;
}

inline UnitType fact_type() {
    UnitType f;
    f.building = true; f.foot_w = 3; f.foot_h = 2; f.footprint = {1, 1, 1, 1, 1, 1};
    f.build_block = {1, 1, 1, 1, 1, 1};
    f.sprite_h = 2; f.hp = 100000; f.base_provider = true;
    return f;
}

}


static void test_harvester_queue() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    const int t_harv = w.define_type(harv_fixture::harv_type());
    const int t_proc = w.define_type(harv_fixture::proc_type());
    w.spawn_building(t_proc, 0, {10, 10});
    for (int y = 20; y < 34; ++y)
        for (int x = 8; x < 22; ++x) w.set_resource({x, y}, RES_ORE, 12);

    std::vector<int32_t> ids;
    for (int k = 0; k < 6; ++k) ids.push_back(w.spawn(t_harv, 0, {14 + k, 16}));


    std::vector<int32_t> loads(ids.size(), 0), stall(ids.size(), 0), worst(ids.size(), 0);
    std::vector<int32_t> last_bales(ids.size(), 0);
    std::vector<CPos> last_cell(ids.size());
    std::vector<int> last_state(ids.size(), -1);
    for (size_t k = 0; k < ids.size(); ++k) last_cell[k] = w.mobile(size_t(w.index_of(ids[k]))).cell;

    for (int t = 0; t < 9000; ++t) {
        w.step();
        for (size_t k = 0; k < ids.size(); ++k) {
            const size_t i = size_t(w.index_of(ids[k]));
            const Harvest& h = w.harvest(i);
            if (last_bales[k] > 0 && h.bales == 0) ++loads[k];
            last_bales[k] = h.bales;
            const CPos c = w.mobile(i).cell;
            if (c == last_cell[k] && int(h.state) == last_state[k]) {
                if (++stall[k] > worst[k]) worst[k] = stall[k];
            } else {
                stall[k] = 0;
            }
            last_cell[k] = c;
            last_state[k] = int(h.state);
        }
    }
    int32_t min_loads = 1 << 30, max_stall = 0;
    for (size_t k = 0; k < ids.size(); ++k) {
        if (loads[k] < min_loads) min_loads = loads[k];
        if (worst[k] > max_stall) max_stall = worst[k];
    }
    std::printf("Sechs Ernteeinheiten an einer Raffinerie: %lld Credits, mindestens %d Fuhren je "
                "Einheit, längster Stillstand %d Ticks\n",
                static_cast<long long>(w.credits(0)), min_loads, max_stall);
    CHECK(min_loads >= 2);
    CHECK(max_stall < 600);
    CHECK(w.credits(0) >= 6000);
}


static void test_harvester_far_ore() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    const int t_harv = w.define_type(harv_fixture::harv_type());
    const int t_proc = w.define_type(harv_fixture::proc_type());
    w.spawn_building(t_proc, 0, {6, 6});
    for (int y = 46; y < 52; ++y)
        for (int x = 46; x < 52; ++x) w.set_resource({x, y}, RES_ORE, 12);
    const int32_t h = w.spawn(t_harv, 0, {9, 9});
    const size_t i = size_t(w.index_of(h));
    int reached = -1;
    for (int t = 0; t < 6000; ++t) {
        w.step();
        if (reached < 0 && w.harvest(i).bales > 0) reached = t;
    }
    std::printf("Fernes Erzfeld (40 Zellen, außerhalb beider Suchradien): erster Ballen bei Tick %d, "
                "%lld Credits\n", reached, static_cast<long long>(w.credits(0)));
    CHECK(reached > 0);
    CHECK(w.credits(0) > 0);
}


static void test_harvester_gems_and_richness() {
    {
        World w;
        std::vector<uint8_t> cost(48 * 48, 1);
        w.set_map(48, 48, cost.data());
        const int t_harv = w.define_type(harv_fixture::harv_type());
        const int t_proc = w.define_type(harv_fixture::proc_type());
        w.spawn_building(t_proc, 0, {22, 4});
        for (int y = 20; y < 26; ++y) {
            for (int x = 10; x < 16; ++x) w.set_resource({x, y}, RES_ORE, 12);
            for (int x = 32; x < 38; ++x) w.set_resource({x, y}, RES_GEMS, 3);
        }
        const int32_t h = w.spawn(t_harv, 0, {24, 23});
        const size_t i = size_t(w.index_of(h));


        for (int t = 0; t < 400 && w.harvest(i).state != Harvest::TO_FIELD &&
                        w.harvest(i).state != Harvest::HARVESTING; ++t) w.step();
        const CPos target = w.harvest(i).target;
        std::printf("Diamanten-Vorzug: Ziel (%d,%d) — %s\n", target.x, target.y,
                    target.x > 24 ? "Diamantenfeld" : "Erzfeld");
        CHECK(target.x > 24);
    }
    {
        World w;
        std::vector<uint8_t> cost(48 * 48, 1);
        w.set_map(48, 48, cost.data());
        const int t_harv = w.define_type(harv_fixture::harv_type());
        const int t_proc = w.define_type(harv_fixture::proc_type());
        w.spawn_building(t_proc, 0, {4, 4});
        for (int x = 12; x < 15; ++x) w.set_resource({x, 12}, RES_ORE, 12);
        for (int y = 28; y < 36; ++y)
            for (int x = 28; x < 36; ++x) w.set_resource({x, y}, RES_ORE, 12);
        const int32_t h = w.spawn(t_harv, 0, {10, 10});
        const size_t i = size_t(w.index_of(h));
        for (int t = 0; t < 400 && w.harvest(i).state != Harvest::TO_FIELD &&
                        w.harvest(i).state != Harvest::HARVESTING; ++t) w.step();
        const CPos target = w.harvest(i).target;
        std::printf("Ergiebigkeit: Ziel (%d,%d) — %s\n", target.x, target.y,
                    target.y >= 28 ? "großes Feld" : "Restzellen");
        CHECK(target.y >= 28);
    }
}


static void test_harvester_gems() {
    struct Setup {
        World w;
        int t_harv = -1;
        size_t i = 0;
        int32_t id = -1;
    };
    auto build = [](Setup& s, int gem_density, int gem_x0, int gem_x1, int ore_x0, int ore_x1) {
        std::vector<uint8_t> cost(64 * 64, 1);
        s.w.set_map(64, 64, cost.data());
        s.w.set_visibility_players(0);
        UnitType ht = harv_fixture::harv_type();
        ht.search_from_proc = 15; ht.search_from_harv = 8;
        s.t_harv = s.w.define_type(ht);
        const int t_proc = s.w.define_type(harv_fixture::proc_type());
        s.w.spawn_building(t_proc, 0, {4, 10});
        for (int y = 10; y <= 13; ++y)
            for (int x = gem_x0; x <= gem_x1; ++x) s.w.set_resource({x, y}, RES_GEMS, gem_density);
        for (int y = 8; y <= 15; ++y)
            for (int x = ore_x0; x <= ore_x1; ++x) s.w.set_resource({x, y}, RES_ORE, 12);
        s.id = s.w.spawn(s.t_harv, 0, {12, 12});
        s.i = size_t(s.w.index_of(s.id));
    };
    auto settle = [](Setup& s) {
        for (int t = 0; t < 600 && s.w.harvest(s.i).state != Harvest::TO_FIELD &&
                        s.w.harvest(s.i).state != Harvest::HARVESTING; ++t) s.w.step();
        CHECK(s.w.harvest(s.i).state == Harvest::TO_FIELD || s.w.harvest(s.i).state == Harvest::HARVESTING);
        return s.w.harvest(s.i).target;
    };

    Setup a; build(a, 1, 16, 19, 26, 33);
    const CPos ta = settle(a);
    std::printf("Diamanten (a) Feld nebenan gegen fernes Erz: Ziel (%d,%d) Typ %d\n", ta.x, ta.y, a.w.resource_type(ta));
    CHECK(a.w.resource_type(ta) == RES_GEMS);

    Setup b; build(b, 2, 24, 27, 14, 17);
    const CPos tb = settle(b);
    std::printf("Diamanten (b) nahes Erz gegen ferne Diamanten: Ziel (%d,%d) Typ %d\n", tb.x, tb.y, b.w.resource_type(tb));
    CHECK(b.w.resource_type(tb) == RES_ORE);

    Setup c; build(c, 1, 24, 27, 14, 17);
    const int32_t other = c.w.spawn(c.t_harv, 0, {25, 11});
    const size_t oi = size_t(c.w.index_of(other));
    for (int t = 0; t < 200 && c.w.harvest(oi).state != Harvest::HARVESTING; ++t) c.w.step();
    CHECK(c.w.harvest(oi).state == Harvest::HARVESTING);
    const CPos claimed = c.w.harvest(oi).target;
    c.w.order_harvest(&c.id, 1, claimed);
    const CPos tc = settle(c);
    std::printf("Diamanten (c) Befehl auf beanspruchte Zelle (%d,%d): Ziel (%d,%d) Typ %d\n",
                claimed.x, claimed.y, tc.x, tc.y, c.w.resource_type(tc));
    CHECK(c.w.resource_type(tc) == RES_GEMS);
    CHECK(!(tc == claimed));
}

static void test_harvester_prefers_full_field() {

    auto first_target = [](int thin_density, int thin_x0, int thin_x1, int full_x0, int full_x1) {
        World w;
        std::vector<uint8_t> cost(48 * 48, 1);
        w.set_map(48, 48, cost.data());
        UnitType ht = harv_fixture::harv_type();
        ht.search_from_proc = 40;
        const int t_harv = w.define_type(ht);
        const int t_proc = w.define_type(harv_fixture::proc_type());
        w.spawn_building(t_proc, 0, {4, 10});
        for (int y = 9; y <= 15; ++y)
            for (int x = thin_x0; x <= thin_x1; ++x) w.set_resource({x, y}, RES_ORE, thin_density);
        for (int y = 9; y <= 14; ++y)
            for (int x = full_x0; x <= full_x1; ++x) w.set_resource({x, y}, RES_ORE, 12);
        const int32_t h = w.spawn(t_harv, 0, {12, 12});
        const size_t i = size_t(w.index_of(h));
        for (int t = 0; t < 400 && w.harvest(i).state != Harvest::TO_FIELD &&
                        w.harvest(i).state != Harvest::HARVESTING; ++t) w.step();
        CHECK(w.harvest(i).state == Harvest::TO_FIELD || w.harvest(i).state == Harvest::HARVESTING);
        return w.harvest(i).target;
    };


    const CPos a = first_target(1, 14, 20, 24, 29);
    std::printf("Erzwahl (a) dünnes Feld nebenan, volles fern: Ziel (%d,%d) — %s\n", a.x, a.y,
                a.x >= 24 ? "volles Feld" : "dünnes Feld");
    CHECK(a.x >= 24);


    const CPos b = first_target(12, 14, 20, 24, 29);
    std::printf("Erzwahl (b) beide voll: Ziel (%d,%d) — %s\n", b.x, b.y, b.x <= 20 ? "nahes Feld" : "fernes Feld");
    CHECK(b.x <= 20);


    const CPos c = first_target(1, 13, 13, 18, 23);
    std::printf("Erzwahl (c) Einzelzelle nebenan, volles Feld nah: Ziel (%d,%d) — %s\n", c.x, c.y,
                c.x >= 18 ? "volles Feld" : "Einzelzelle");
    CHECK(c.x >= 18);


    const CPos d = first_target(1, 13, 13, 18, 23);
    CHECK(c == d);


    {
        World w;
        std::vector<uint8_t> cost(16 * 16, 1);
        w.set_map(16, 16, cost.data());
        w.set_resource({2, 2}, RES_ORE, 1);
        CHECK(w.cell_fullness({2, 2}) == FULLNESS_OWN_WEIGHT * 1);
        for (int y = 7; y <= 9; ++y)
            for (int x = 7; x <= 9; ++x) w.set_resource({x, y}, RES_ORE, 12);
        CHECK(w.cell_fullness({8, 8}) == FULLNESS_MAX);
        for (int y = 12; y <= 14; ++y)
            for (int x = 12; x <= 14; ++x) w.set_resource({x, y}, RES_GEMS, 3);
        CHECK(w.cell_fullness({13, 13}) == FULLNESS_MAX);
        CHECK(w.cell_fullness({0, 0}) == 0);
    }
}


static void test_harvester_park() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    const int t_harv = w.define_type(harv_fixture::harv_type());
    const int t_proc = w.define_type(harv_fixture::proc_type());
    const int t_fact = w.define_type(harv_fixture::fact_type());
    w.spawn_building(t_fact, 0, {6, 6});
    w.spawn_building(t_proc, 0, {12, 6});
    for (int y = 26; y < 34; ++y)
        for (int x = 26; x < 34; ++x) w.set_resource({x, y}, RES_ORE, 12);
    std::vector<int32_t> ids;
    for (int k = 0; k < 4; ++k) ids.push_back(w.spawn(t_harv, 0, {20 + k, 20}));
    for (int t = 0; t < 300; ++t) w.step();


    const std::vector<int32_t> park_cmd = {25, 0, 0, 0, 0, 0};
    CHECK(w.apply_order(0, park_cmd.data(), park_cmd.size()));
    for (int t = 0; t < 2500; ++t) w.step();

    std::vector<CPos> cells;
    int parked = 0;
    for (int32_t id : ids) {
        const size_t i = size_t(w.index_of(id));
        if (w.harvest(i).state == Harvest::PARKED) ++parked;
        cells.push_back(w.mobile(i).cell);
    }
    bool distinct = true;
    for (size_t a = 0; a < cells.size(); ++a)
        for (size_t b = a + 1; b < cells.size(); ++b)
            if (cells[a] == cells[b]) distinct = false;
    int64_t max_dist = 0;
    for (CPos c : cells) {
        const int64_t d = cell_dist_sq(c, CPos{7, 7});
        if (d > max_dist) max_dist = d;
    }
    std::printf("Zur Basis: %d von %d geparkt, eigene Zellen %s, weiteste %lld Zellen² vom Bauhof\n",
                parked, int(ids.size()), distinct ? "ja" : "NEIN", static_cast<long long>(max_dist));
    CHECK(parked == int(ids.size()));
    CHECK(distinct);
    CHECK(max_dist <= 100);


    const int64_t before = w.credits(0);
    for (int t = 0; t < 1200; ++t) w.step();
    CHECK(w.credits(0) == before);


    const std::vector<int32_t> resume_cmd = {26, 0, 0, 0, 0, 0};
    CHECK(w.apply_order(0, resume_cmd.data(), resume_cmd.size()));
    for (int t = 0; t < 4000; ++t) w.step();
    std::printf("Weitersammeln: %lld Credits (vorher %lld)\n",
                static_cast<long long>(w.credits(0)), static_cast<long long>(before));
    CHECK(w.credits(0) > before);
}


static void test_harvester_explore() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    w.set_visibility_players(1u);
    UnitType ht = harv_fixture::harv_type();
    ht.reveal_cells = 5; ht.reveal_range = 5 * 1024;
    UnitType pt = harv_fixture::proc_type();
    pt.reveal_cells = 6; pt.reveal_range = 6 * 1024;
    const int t_harv = w.define_type(ht);
    const int t_proc = w.define_type(pt);
    w.spawn_building(t_proc, 0, {6, 6});
    for (int y = 30; y < 38; ++y)
        for (int x = 30; x < 38; ++x) w.set_resource({x, y}, RES_ORE, 12);
    const int32_t h = w.spawn(t_harv, 0, {9, 9});
    const size_t i = size_t(w.index_of(h));

    for (int t = 0; t < 30; ++t) w.step();
    const bool knew_ore = w.explored(0, CPos{33, 33});
    const Harvest::State early = w.harvest(i).state;
    CHECK(!knew_ore);
    CHECK(early == Harvest::EXPLORE || early == Harvest::WAIT);

    int found = -1;
    for (int t = 0; t < 12000; ++t) {
        w.step();
        if (found < 0 && w.harvest(i).bales > 0) found = t;
    }
    std::printf("Erkundungsfahrt: Erz zu Beginn unbekannt (%s), erster Ballen bei Tick %d, %lld Credits\n",
                knew_ore ? "NEIN" : "ja", found, static_cast<long long>(w.credits(0)));
    CHECK(found > 0);
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


struct EconTypes {
    int t_fact = -1, t_powr = -1, t_proc = -1, t_harv = -1;
};

static EconTypes econ_basics(World& w) {
    EconTypes e;
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.base_provider = true; fact.cost = 2000;
    fact.produces = (1u << QUEUE_BUILDING) | (1u << QUEUE_VEHICLE) | (1u << QUEUE_DEFENSE);
    fact.provides = {"fact"}; fact.exit_dx = 1; fact.exit_dy = 3;
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.build_block = powr.footprint; powr.hp = 40000; powr.power = 100; powr.cost = 300;
    powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"}; powr.ai_building_fraction = 10;
    UnitType harv;
    harv.speed = 72; harv.turn_rate = 20; harv.hp = 60000; harv.harvester = true; harv.capacity = 20;
    harv.bale_load_delay = 4; harv.bale_unload_delay = 1; harv.search_from_proc = 15; harv.search_from_harv = 8;
    harv.wait_duration = 25; harv.cost = 1400; harv.queue_kind = QUEUE_VEHICLE; harv.ai_unit_share = 15;
    harv.ai_unit_limit = 12;
    e.t_fact = w.define_type(fact); e.t_powr = w.define_type(powr); e.t_harv = w.define_type(harv);
    UnitType proc;
    proc.building = true; proc.foot_w = 3; proc.foot_h = 3; proc.footprint = {0, 1, 0, 1, 1, 1, 1, 0, 0};
    proc.build_block = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    proc.hp = 90000; proc.power = -30; proc.cost = 1400; proc.queue_kind = QUEUE_BUILDING;
    proc.prerequisites = {"anypower"}; proc.provides = {"proc"}; proc.refinery = true;
    proc.dock_dx = 1; proc.dock_dy = 2; proc.ai_building_fraction = 10;
    proc.free_actor = e.t_harv; proc.free_dx = 1; proc.free_dy = 2;
    e.t_proc = w.define_type(proc);
    return e;
}


static void test_bot_harvesters_by_ore() {
    auto target_with_ore = [](int ore_side) {
        World w;
        std::vector<uint8_t> cost(64 * 64, 1);
        w.set_map(64, 64, cost.data());
        const EconTypes e = econ_basics(w);
        w.spawn_building(e.t_fact, 1, {8, 8});
        w.spawn_building(e.t_proc, 1, {13, 8});
        for (int y = 20; y < 20 + ore_side; ++y)
            for (int x = 8; x < 8 + ore_side; ++x) w.set_resource({x, y}, RES_ORE, 12);
        w.give_credits(1, 20000);
        BotParams bp;
        bp.squad_size = 1000;
        w.enable_bot(1, bp);
        w.step();
        return w.bot_harvester_target(1);
    };
    const int32_t many = target_with_ore(16);
    const int32_t few = target_with_ore(3);
    std::printf("KI-Ernte nach Erzangebot: 256 Erzzellen → %d Ernteeinheiten, 9 Erzzellen → %d\n", many, few);
    CHECK(many == 3);
    CHECK(few >= 1 && few <= 1);
    CHECK(many > few);
}


static void test_bot_spend_surplus() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    const EconTypes e = econ_basics(w);
    UnitType barr;
    barr.building = true; barr.foot_w = 2; barr.foot_h = 2; barr.footprint = {1, 1, 1, 1};
    barr.build_block = barr.footprint; barr.hp = 40000; barr.power = -20; barr.cost = 500;
    barr.queue_kind = QUEUE_BUILDING; barr.prerequisites = {"anypower"}; barr.provides = {"barr"};
    barr.produces = 1u << QUEUE_INFANTRY; barr.exit_dx = 0; barr.exit_dy = 2;
    UnitType dome;
    dome.building = true; dome.foot_w = 2; dome.foot_h = 2; dome.footprint = {1, 1, 1, 1};
    dome.build_block = dome.footprint; dome.hp = 40000; dome.power = -40; dome.cost = 1400;
    dome.queue_kind = QUEUE_BUILDING; dome.prerequisites = {"anypower"}; dome.provides = {"dome"};
    dome.provides_radar = true;
    UnitType mslo;
    mslo.building = true; mslo.foot_w = 2; mslo.foot_h = 2; mslo.footprint = {1, 1, 1, 1};
    mslo.build_block = mslo.footprint; mslo.hp = 40000; mslo.power = -100; mslo.cost = 2500;
    mslo.queue_kind = QUEUE_BUILDING; mslo.prerequisites = {"dome"}; mslo.provides = {"mslo"};
    mslo.support_power = SP_NUKE;
    const int t_barr = w.define_type(barr), t_dome = w.define_type(dome), t_mslo = w.define_type(mslo);

    w.spawn_building(e.t_fact, 1, {8, 8});
    w.spawn_building(e.t_powr, 1, {13, 8});
    w.spawn_building(e.t_proc, 1, {8, 13});
    w.spawn_building(t_barr, 1, {13, 13});
    for (int y = 24; y < 32; ++y)
        for (int x = 8; x < 16; ++x) w.set_resource({x, y}, RES_ORE, 12);
    BotParams bp;
    bp.squad_size = 1000;
    w.enable_bot(1, bp);
    w.step();

    std::vector<int32_t> list;
    w.buildable(1, QUEUE_BUILDING, list);
    std::vector<int32_t> count(w.type_count(), 0);
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        if (a.alive && a.owner == 1 && w.type(a.type).building) ++count[size_t(a.type)];
    }

    const int32_t poor = w.bot_spend_surplus(1, QUEUE_BUILDING, list, count);
    w.give_credits(1, 9000);

    const int32_t first = w.bot_spend_surplus(1, QUEUE_BUILDING, list, count);
    count[size_t(t_barr)] = 3;

    const int32_t second = w.bot_spend_surplus(1, QUEUE_BUILDING, list, count);
    count[size_t(t_dome)] = 2;
    w.spawn_building(t_dome, 1, {18, 8});
    w.step();
    w.buildable(1, QUEUE_BUILDING, list);

    const int32_t third = w.bot_spend_surplus(1, QUEUE_BUILDING, list, count);
    std::printf("KI-Überschuss: ohne Geld %d, dann Reihenfolge %d (Kaserne %d), %d (Radar %d), %d (Superwaffe %d)\n",
                poor, first, t_barr, second, t_dome, third, t_mslo);
    CHECK(poor < 0);
    CHECK(first == t_barr);
    CHECK(second == t_dome);
    CHECK(third == t_mslo);


    const int64_t before = w.credits(1);
    int32_t buildings_before = 0;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).alive && w.actor(i).owner == 1 && w.type(w.actor(i).type).building) ++buildings_before;
    for (int t = 0; t < 3000; ++t) w.step();
    int32_t buildings_after = 0;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).alive && w.actor(i).owner == 1 && w.type(w.actor(i).type).building) ++buildings_after;
    std::printf("KI-Überschuss im Lauf: Guthaben %lld → %lld, Gebäude %d → %d\n",
                static_cast<long long>(before), static_cast<long long>(w.credits(1)),
                buildings_before, buildings_after);
    CHECK(buildings_after > buildings_before);
}


static void test_bot_defense_budget() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    const EconTypes e = econ_basics(w);
    Weapon cannon; cannon.range = 5 * CELL; cannon.reload = 40; cannon.damage = 5000;
    cannon.versus[ARMOR_NONE] = 25; cannon.versus[ARMOR_HEAVY] = 100;
    Weapon mg; mg.range = 4 * CELL; mg.reload = 20; mg.damage = 1500;
    mg.versus[ARMOR_NONE] = 100; mg.versus[ARMOR_HEAVY] = 25;
    Weapon flak; flak.range = 6 * CELL; flak.reload = 30; flak.damage = 3000;
    flak.valid_targets = TT_AIRBORNE;
    const int w_cannon = w.define_weapon(cannon), w_mg = w.define_weapon(mg), w_flak = w.define_weapon(flak);
    UnitType gun;
    gun.building = true; gun.foot_w = 1; gun.foot_h = 1; gun.footprint = {1}; gun.build_block = gun.footprint;
    gun.hp = 40000; gun.cost = 600; gun.queue_kind = QUEUE_DEFENSE; gun.defense = true;
    gun.prerequisites = {"anypower"}; gun.provides = {"gun"}; gun.weapon = w_cannon; gun.ai_building_fraction = 5;
    UnitType pbox;
    pbox.building = true; pbox.foot_w = 1; pbox.foot_h = 1; pbox.footprint = {1}; pbox.build_block = pbox.footprint;
    pbox.hp = 40000; pbox.cost = 400; pbox.queue_kind = QUEUE_DEFENSE; pbox.defense = true;
    pbox.prerequisites = {"anypower"}; pbox.provides = {"pbox"}; pbox.weapon = w_mg; pbox.ai_building_fraction = 5;
    UnitType sam;
    sam.building = true; sam.foot_w = 1; sam.foot_h = 1; sam.footprint = {1}; sam.build_block = sam.footprint;
    sam.hp = 40000; sam.cost = 750; sam.queue_kind = QUEUE_DEFENSE; sam.defense = true;
    sam.prerequisites = {"anypower"}; sam.provides = {"sam"}; sam.weapon = w_flak; sam.ai_building_fraction = 5;
    UnitType tank;
    tank.speed = 85; tank.turn_rate = 20; tank.hp = 40000; tank.cost = 1150; tank.weapon = w_cannon;
    tank.armor = ARMOR_HEAVY; tank.queue_kind = QUEUE_VEHICLE;
    UnitType hpad;
    hpad.building = true; hpad.foot_w = 2; hpad.foot_h = 2; hpad.footprint = {1, 1, 1, 1};
    hpad.build_block = hpad.footprint; hpad.hp = 40000; hpad.cost = 500; hpad.produces = 1u << QUEUE_AIRCRAFT;
    const int t_gun = w.define_type(gun), t_pbox = w.define_type(pbox), t_sam = w.define_type(sam);
    const int t_tank = w.define_type(tank), t_hpad = w.define_type(hpad);

    w.spawn_building(e.t_fact, 1, {8, 8});
    w.spawn_building(e.t_powr, 1, {13, 8});
    w.spawn_building(e.t_proc, 1, {8, 13});
    BotParams bp;
    bp.squad_size = 1000;
    w.enable_bot(1, bp);
    w.step();

    std::vector<int32_t> list;
    w.buildable(1, QUEUE_DEFENSE, list);
    std::vector<int32_t> count(w.type_count(), 0);


    for (int i = 0; i < 4; ++i) w.spawn(t_tank, 2, CPos{20 + i, 20});
    w.step();
    const int32_t budget = w.bot_defense_budget(1);
    const int32_t want_ground = w.bot_defense_request(1, list, count);

    std::vector<int32_t> only_sam{t_sam};
    const int32_t no_air = w.bot_defense_request(1, only_sam, count);

    w.spawn_building(t_hpad, 2, {30, 30});
    w.step();
    const int32_t with_air = w.bot_defense_request(1, list, count);
    std::printf("KI-Verteidigungsbudget: Soll %d, gewählter Turm %d (gun %d / pbox %d), ohne Gegnerflieger %d, "
                "mit Landeplatz %d (sam %d)\n",
                budget, want_ground, t_gun, t_pbox, no_air, with_air, t_sam);
    CHECK(budget > 0);
    CHECK(want_ground == t_gun || want_ground == t_pbox);
    CHECK(want_ground != t_sam);
    CHECK(no_air < 0);
    CHECK(with_air == t_sam);
}


struct CounterTypes {
    int t_tank = -1, t_rocket = -1, t_flame = -1, t_arty = -1;
};

static CounterTypes counter_units(World& w) {
    CounterTypes c;
    Weapon cannon; cannon.range = 5 * CELL; cannon.reload = 40; cannon.damage = 5000;
    cannon.versus[ARMOR_NONE] = 50; cannon.versus[ARMOR_HEAVY] = 100;
    cannon.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_INFANTRY;
    Weapon rocket; rocket.range = 6 * CELL; rocket.reload = 50; rocket.damage = 4000;
    rocket.versus[ARMOR_NONE] = 25; rocket.versus[ARMOR_HEAVY] = 100;
    rocket.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_INFANTRY;
    Weapon flame; flame.range = 3 * CELL; flame.reload = 30; flame.damage = 3000;
    flame.versus[ARMOR_NONE] = 100; flame.versus[ARMOR_HEAVY] = 25;
    flame.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_VEHICLE | TT_INFANTRY;
    Weapon shell; shell.range = 11 * CELL; shell.min_range = 4 * CELL; shell.reload = 60; shell.damage = 2000;
    shell.valid_targets = TT_GROUND_ACTOR | TT_STRUCTURE | TT_DEFENSE | TT_VEHICLE | TT_INFANTRY;
    const int w_cannon = w.define_weapon(cannon), w_rocket = w.define_weapon(rocket);
    const int w_flame = w.define_weapon(flame), w_shell = w.define_weapon(shell);

    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 40000; tank.cost = 800; tank.weapon = w_cannon;
    tank.armor = ARMOR_HEAVY; tank.queue_kind = QUEUE_VEHICLE; tank.ai_unit_share = 40; tank.ai_unit_limit = 99;
    tank.hit_radius = 426; tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType rock;
    rock.speed = 60; rock.turn_rate = 20; rock.hp = 30000; rock.cost = 700; rock.weapon = w_rocket;
    rock.armor = ARMOR_LIGHT; rock.queue_kind = QUEUE_VEHICLE; rock.ai_unit_share = 20; rock.ai_unit_limit = 99;
    rock.hit_radius = 426; rock.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType flam;
    flam.speed = 60; flam.turn_rate = 20; flam.hp = 30000; flam.cost = 700; flam.weapon = w_flame;
    flam.armor = ARMOR_LIGHT; flam.queue_kind = QUEUE_VEHICLE; flam.ai_unit_share = 20; flam.ai_unit_limit = 99;
    flam.hit_radius = 426; flam.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType arty;
    arty.speed = 45; arty.turn_rate = 20; arty.hp = 15000; arty.cost = 600; arty.weapon = w_shell;
    arty.armor = ARMOR_LIGHT; arty.queue_kind = QUEUE_VEHICLE; arty.ai_unit_share = 10; arty.ai_unit_limit = 99;
    arty.hit_radius = 426; arty.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    c.t_tank = w.define_type(tank);
    c.t_rocket = w.define_type(rock);
    c.t_flame = w.define_type(flam);
    c.t_arty = w.define_type(arty);
    return c;
}


static void test_bot_orders() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    const EconTypes e = econ_basics(w);
    const CounterTypes c = counter_units(w);
    w.spawn_building(e.t_fact, 1, {8, 8});
    w.spawn_building(e.t_powr, 1, {13, 8});
    w.give_credits(1, 30000);
    BotParams bp;
    bp.squad_size = 1000;
    bp.counter_interval = 0;
    w.enable_bot(1, bp);
    w.step();


    CHECK(w.bot_role_of_type(size_t(c.t_arty)) == ROLE_SIEGE);
    CHECK(w.bot_role_of_type(size_t(c.t_tank)) == ROLE_TANK);
    CHECK(w.bot_role_of_type(size_t(e.t_harv)) < 0);


    w.bot_vorhaben_start(1, VH_SIEGE);
    CHECK(w.bot_state(1).vh_orders[ROLE_TANK] == 5);
    CHECK(w.bot_state(1).vh_orders[ROLE_SIEGE] == 3);
    int tanks = 0, artys = 0, others = 0;
    for (int k = 0; k < 8; ++k) {
        const int32_t t = w.bot_choose_unit(1, QUEUE_VEHICLE);
        if (t == c.t_tank) ++tanks;
        else if (t == c.t_arty) ++artys;
        else ++others;
    }
    CHECK(tanks == 5 && artys == 3 && others == 0);

    CHECK(w.bot_state(1).vh_orders[ROLE_TANK] == 0);
    CHECK(w.bot_state(1).vh_orders[ROLE_SIEGE] == 0);
    std::printf("KI-Bestellungen: Belagerung bestellt 5 Panzer + 3 Belagerer, geliefert %d/%d (sonstige %d)\n",
                tanks, artys, others);
}


static void test_bot_counter() {
    auto shares = [](int32_t counter_interval, int32_t& rocket_pct, int32_t& flame_pct) {
        World w;
        std::vector<uint8_t> cost(64 * 64, 1);
        w.set_map(64, 64, cost.data());
        const EconTypes e = econ_basics(w);
        const CounterTypes c = counter_units(w);
        w.set_alliance(1, 2, false);
        w.spawn_building(e.t_fact, 1, {8, 8});
        w.spawn_building(e.t_powr, 1, {13, 8});


        for (int k = 0; k < 3; ++k) w.spawn(c.t_tank, 1, {20 + k, 20});
        for (int k = 0; k < 6; ++k) w.spawn(c.t_tank, 2, {22 + k, 22});
        BotParams bp;
        bp.squad_size = 1000;
        bp.threat_map_interval = 5;
        bp.counter_interval = counter_interval;
        w.enable_bot(1, bp);
        for (int k = 0; k < 120; ++k) w.step();
        rocket_pct = w.bot_counter_share(1, size_t(c.t_rocket));
        flame_pct = w.bot_counter_share(1, size_t(c.t_flame));
    };
    int32_t rocket_on = 0, flame_on = 0, rocket_off = 0, flame_off = 0;
    shares(20, rocket_on, flame_on);
    shares(0, rocket_off, flame_off);
    CHECK(rocket_on > 100);
    CHECK(flame_on <= 100);
    CHECK(rocket_on > flame_on);
    CHECK(rocket_off == 100 && flame_off == 100);
    std::printf("KI-Konter: Gegner nur Panzer → Raketenwagen %d %%, Flammenwagen %d %%; ohne Konter %d/%d %%\n",
                rocket_on, flame_on, rocket_off, flame_off);
}


static void test_bot_expansion_all_fields() {
    World w;
    std::vector<uint8_t> cost(96 * 96, 1);
    w.set_map(96, 96, cost.data());
    const EconTypes e = econ_basics(w);
    UnitType mcv;
    mcv.speed = 60; mcv.turn_rate = 20; mcv.hp = 60000; mcv.cost = 2000; mcv.queue_kind = QUEUE_VEHICLE;
    mcv.transforms_into = e.t_fact;
    const int t_mcv = w.define_type(mcv);


    const CPos fields[3] = {{20, 12}, {74, 20}, {74, 74}};
    for (const CPos& f : fields)
        for (int y = f.y - 5; y <= f.y + 5; ++y)
            for (int x = f.x - 5; x <= f.x + 5; ++x) w.set_resource({x, y}, RES_ORE, 12);

    w.spawn_building(e.t_fact, 1, {10, 10});
    w.give_credits(1, 40000);
    BotParams bp;
    bp.squad_size = 1000;
    w.enable_bot(1, bp);
    w.step();


    const int32_t free_fields = w.bot_free_resource_fields(1);
    const int32_t should_have = w.bot_max_conyards(1, 1);
    for (int t = 1; t <= 15000; ++t) w.step();
    int32_t yards = 0, at_field[3] = {0, 0, 0};
    for (size_t i = 0; i < w.actor_count(); ++i) {
        const Actor& a = w.actor(i);
        if (!a.alive || a.owner != 1 || a.type != e.t_fact) continue;
        ++yards;
        for (int k = 0; k < 3; ++k) if (cell_dist_sq(a.origin, fields[k]) <= 22 * 22) ++at_field[k];
    }
    std::printf("KI-Ausbau auf alle Felder: %d freie Erzfelder, Soll %d Bauhöfe, gebaut %d (Felder %d/%d/%d)\n",
                free_fields, should_have, yards, at_field[0], at_field[1], at_field[2]);
    CHECK(free_fields >= 3);
    CHECK(should_have >= 3);
    CHECK(yards >= 3);
    (void)t_mcv;
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


static uint32_t bot_reaction_gap(int32_t reaction) {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.armor = ARMOR_WOOD;
    fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true; fact.provides = {"fact"};
    UnitType weap;
    weap.building = true; weap.foot_w = 3; weap.foot_h = 3; weap.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    weap.build_block = weap.footprint; weap.hp = 150000; weap.armor = ARMOR_WOOD;
    weap.provides = {"weap"}; weap.produces = 1u << QUEUE_VEHICLE; weap.exit_dx = 1; weap.exit_dy = 3;
    UnitType tank;
    tank.speed = 85; tank.turn_rate = 20; tank.hp = 40000; tank.cost = 600;
    tank.queue_kind = QUEUE_VEHICLE; tank.prerequisites = {"weap"}; tank.ai_unit_share = 50;
    const int t_fact = w.define_type(fact), t_weap = w.define_type(weap), t_tank = w.define_type(tank);
    w.spawn_building(t_fact, 1, {8, 8});
    w.spawn_building(t_weap, 1, {14, 8});
    w.give_credits(1, 20000);
    BotParams bp;
    bp.reaction_min_ticks = reaction;
    bp.reaction_max_ticks = reaction;
    w.enable_bot(1, bp);
    uint32_t first = 0, second = 0;
    for (int t = 0; t < 4000 && second == 0; ++t) {
        w.step();
        int n = 0;
        for (size_t i = 0; i < w.actor_count(); ++i) {
            const Actor& a = w.actor(i);
            if (a.alive && a.owner == 1 && a.type == t_tank) ++n;
        }
        if (n >= 1 && first == 0) first = w.tick();
        if (n >= 2 && second == 0) second = w.tick();
    }
    CHECK(first > 0 && second > first);
    return second - first;
}

static void test_bot_build_reaction() {
    const uint32_t gap0 = bot_reaction_gap(0);
    const uint32_t gap1 = bot_reaction_gap(200);
    std::printf("KI Bau-Versatz: Panzerabstand ohne %u Ticks, mit Versatz 200: %u Ticks\n", gap0, gap1);
    CHECK(gap1 >= gap0 + 170 && gap1 <= gap0 + 260);
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


    CHECK(!w.can_unload(apc_id));
    w.order_unload(&apc_id, 1);
    CHECK(!w.actor(size_t(w.index_of(apc_id))).unloading);


    w.order_enter_transport(troop.data(), troop.size(), apc_id);
    for (int t = 0; t < 400; ++t) w.step();
    CHECK(w.cargo_weight(apc_id) == 5);
    w.order_unload(&apc_id, 1);
    CHECK(w.actor(size_t(w.index_of(apc_id))).unloading);
    w.order_move(&apc_id, 1, {6, 6});
    CHECK(!w.actor(size_t(w.index_of(apc_id))).unloading);
    for (int t = 0; t < 60; ++t) w.step();
    CHECK(w.cargo_weight(apc_id) == 5);
    std::printf("Transport: Entladebefehl durch Fahrbefehl ersetzt, weiter %d an Bord\n",
                w.cargo_weight(apc_id));


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


static void test_cargo_helicopter() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    UnitType tran;
    tran.aircraft = true; tran.can_hover = true; tran.vtol = true;
    tran.speed = 128; tran.turn_rate = 20; tran.cruise_altitude = 1280; tran.altitude_velocity = 58;
    tran.hp = 14000; tran.hit_radius = 426;
    tran.cargo_max_weight = 8; tran.cargo_types = TT_INFANTRY;
    tran.before_unload_delay = 8; tran.between_unload_delay = 0;
    tran.after_unload_delay = 40; tran.after_load_delay = 8;
    tran.target_types = TT_GROUND_ACTOR; tran.target_types_airborne = TT_AIRBORNE;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.hit_radius = 128;
    e1.passenger_weight = 1; e1.passenger_type = TT_INFANTRY;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_tran = w.define_type(tran);
    const int t_e1 = w.define_type(e1);

    const int32_t heli = w.spawn(t_tran, 0, {20, 20}, 0, 100, true);
    const size_t hi = size_t(w.index_of(heli));
    CHECK(w.air(hi).alt == 1280);
    std::vector<int32_t> troop;
    for (int i = 0; i < 3; ++i) troop.push_back(w.spawn(t_e1, 0, {25 + i, 20}));


    w.order_enter_transport(troop.data(), troop.size(), heli);
    bool touched_down = false;
    for (int t = 0; t < 800; ++t) {
        w.step();
        if (w.air(hi).alt == 0) touched_down = true;
        if (w.cargo_weight(heli) == 3) break;
    }
    CHECK(touched_down);
    CHECK(w.cargo_weight(heli) == 3);
    std::printf("Transporthubschrauber: von selbst gelandet, %d/3 an Bord\n", w.cargo_weight(heli));


    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.air(hi).alt == 1280);
    CHECK(!w.actor(hi).load_lock);
    std::printf("Transporthubschrauber: nach dem Beladen wieder auf %d Höhe\n", w.air(hi).alt);


    w.order_move(&heli, 1, {34, 34});
    for (int t = 0; t < 300; ++t) w.step();
    CHECK(w.air(hi).alt == 1280);
    CHECK(w.can_unload(heli));
    w.order_unload(&heli, 1);
    CHECK(w.actor(hi).unload_takeoff);
    for (int t = 0; t < 400; ++t) {
        w.step();
        if (w.cargo_weight(heli) == 0 && !w.actor(hi).unloading) break;
    }
    CHECK(w.cargo_weight(heli) == 0);
    int out = 0;
    for (const int32_t id : troop) {
        const int i = w.index_of(id);
        if (i >= 0 && w.actor(size_t(i)).alive && w.actor(size_t(i)).transport < 0
            && w.air(size_t(i)).alt == 0) ++out;
    }
    CHECK(out == 3);
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.air(hi).alt == 1280);
    std::printf("Transporthubschrauber: %d/3 abgesetzt und wieder auf %d Höhe\n", out, w.air(hi).alt);
}


static void test_paradrop_own_cell() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 0);
    for (int x = 0; x <= 8; ++x) cost[size_t(32 * 64 + x)] = 1;
    for (int x = 10; x < 60; x += 2) cost[size_t(32 * 64 + x)] = 1;
    w.set_map(64, 64, cost.data());
    UnitType badr;
    badr.aircraft = true; badr.speed = 30; badr.turn_rate = 20; badr.cruise_altitude = 2560;
    badr.altitude_velocity = 43; badr.hp = 40000; badr.cargo_max_weight = 10; badr.cargo_types = TT_INFANTRY;
    badr.target_types = TT_GROUND_ACTOR; badr.target_types_airborne = TT_AIRBORNE;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.locomotor = LOCO_FOOT;
    e1.hp = 5000; e1.hit_radius = 128;
    e1.passenger_weight = 1; e1.passenger_type = TT_INFANTRY; e1.fall_rate = 26;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_badr = w.define_type(badr);
    const int t_e1 = w.define_type(e1);

    const int32_t plane = w.spawn(t_badr, 0, {2, 32}, 768, 100, true);
    std::vector<int32_t> troop;
    for (int i = 0; i < 5; ++i) {
        const int32_t id = w.spawn(t_e1, 0, {2, 32});
        troop.push_back(id);
        CHECK(w.load_passenger(plane, id));
    }
    w.order_move(&plane, 1, {62, 32});
    w.order_paradrop(plane, {32, 32});

    int dropped = 0, on_plane_cell = 0;
    std::vector<int32_t> aboard = troop;
    for (int t = 0; t < 3000 && dropped < 5; ++t) {
        w.step();
        const int pi = w.index_of(plane);
        if (pi < 0) break;


        const CPos plane_cell = to_cell(w.actor(size_t(pi)).pos);
        for (size_t k = 0; k < aboard.size();) {
            const int i = w.index_of(aboard[k]);
            if (i >= 0 && w.actor(size_t(i)).transport < 0) {
                ++dropped;
                if (w.mobile(size_t(i)).cell == plane_cell) ++on_plane_cell;
                aboard.erase(aboard.begin() + long(k));
            } else {
                ++k;
            }
        }
    }
    CHECK(dropped == 5);
    CHECK(on_plane_cell == 5);
    for (int t = 0; t < 400; ++t) w.step();
    int landed = 0;
    for (const int32_t id : troop) {
        const int i = w.index_of(id);
        if (i >= 0 && w.actor(size_t(i)).alive && w.air(size_t(i)).alt == 0) ++landed;
    }
    CHECK(landed == 5);
    std::printf("Fallschirme: %d von 5 in genau der Zelle des Flugzeugs abgesetzt, %d gelandet\n",
                on_plane_cell, landed);
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


    {
        const int32_t ghost = w.spawn(t_tank, 1, {30, 30});
        w.order_attack(&h, 1, ghost);
        for (int t = 0; t < 400; ++t) {
            w.step();
            if (w.air(size_t(w.index_of(h))).alt >= 1280) break;
        }
        w.destroy(ghost);
        int idle_hi = w.index_of(h);
        CHECK(w.air(size_t(idle_hi)).ammo > 0);
        bool went_home = false;
        int idle_from = -1, laps_ticks = 0;
        for (int t = 0; t < 900; ++t) {
            w.step();
            idle_hi = w.index_of(h);
            if (idle_hi < 0) break;
            const Air& ai = w.air(size_t(idle_hi));


            if (idle_from < 0 && !ai.has_goal && !ai.returning) idle_from = t;
            if (ai.returning) { went_home = true; laps_ticks = t - idle_from; break; }
        }

        CHECK(went_home);
        CHECK(idle_from >= 0);
        CHECK(laps_ticks >= 120 && laps_ticks <= 140);
        std::printf("Leerlauf: Flieger kreiste %d Ticks im Leerlauf (zwei Platzrunden = 128) und flog dann zurück\n",
                    laps_ticks);
        for (int t = 0; t < 2000; ++t) {
            w.step();
            idle_hi = w.index_of(h);
            if (idle_hi >= 0 && w.air(size_t(idle_hi)).state == Air::LANDED) break;
        }
        CHECK(w.air(size_t(w.index_of(h))).state == Air::LANDED);
    }


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


static void test_air_armaments() {
    World w;
    std::vector<uint8_t> cost(48 * 48, 1);
    w.set_map(48, 48, cost.data());
    Weapon ag;
    ag.range = 5 * CELL; ag.reload = 34; ag.damage = 3000; ag.spread = 128; ag.speed = 0;
    ag.valid_targets = TT_GROUND_ACTOR;
    Weapon aa;
    aa.range = 4 * CELL; aa.reload = 30; aa.damage = 3000; aa.spread = 128; aa.speed = 0;
    aa.valid_targets = TT_AIRBORNE;
    const int w_ag = w.define_weapon(ag);
    const int w_aa = w.define_weapon(aa);

    UnitType hpad;
    hpad.building = true; hpad.foot_w = 2; hpad.foot_h = 2; hpad.footprint = {1, 1, 1, 1};
    hpad.build_block = hpad.footprint; hpad.hp = 80000;
    hpad.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_hpad = w.define_type(hpad);

    UnitType heli;
    heli.aircraft = true; heli.can_hover = true; heli.vtol = true; heli.speed = 149; heli.turn_rate = 16;
    heli.cruise_altitude = 1280; heli.altitude_velocity = 43; heli.hp = 12000;
    heli.weapon = w_ag; heli.weapon_secondary = w_aa;
    heli.ammo_max = 8; heli.ammo_reload = 20; heli.air_attack_type = 1; heli.facing_tolerance = 80;
    heli.hit_radius = 426; heli.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    heli.target_types_airborne = TT_AIRBORNE; heli.rearm_actors = {t_hpad};
    const int t_heli = w.define_type(heli);

    UnitType mig;
    mig.aircraft = true; mig.speed = 186; mig.turn_rate = 5; mig.cruise_altitude = 2560;
    mig.altitude_velocity = 86; mig.hp = 8000; mig.weapon = w_ag; mig.ammo_max = 8;
    mig.ammo_reload = 20; mig.air_attack_type = 0; mig.facing_tolerance = 80; mig.hit_radius = 426;
    mig.target_types = TT_GROUND_ACTOR | TT_VEHICLE; mig.target_types_airborne = TT_AIRBORNE;
    mig.rearm_actors = {t_hpad};
    const int t_mig = w.define_type(mig);

    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 40000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_tank = w.define_type(tank);

    w.spawn_building(t_hpad, 0, {4, 4});
    const int32_t h = w.spawn(t_heli, 0, {6, 6});
    const int32_t ground = w.spawn(t_tank, 1, {20, 6});
    w.order_attack(&h, 1, ground);
    for (int t = 0; t < 900; ++t) {
        w.step();
        const int gi = w.index_of(ground);
        if (gi < 0 || w.actor(size_t(gi)).hp < 40000) break;
    }
    const int gi = w.index_of(ground);
    std::printf("Longbow gegen Panzer: HP %d, Munition %d\n",
                gi >= 0 ? w.actor(size_t(gi)).hp : 0, w.air(size_t(w.index_of(h))).ammo);
    CHECK(gi >= 0 && w.actor(size_t(gi)).hp < 40000);
    CHECK(w.air(size_t(w.index_of(h))).ammo < 8);


    World w2;
    w2.set_map(48, 48, cost.data());
    w2.define_weapon(ag); w2.define_weapon(aa);
    w2.define_type(hpad); const int t2_heli = w2.define_type(heli);
    w2.define_type(mig); w2.define_type(tank);
    w2.spawn_building(t_hpad, 0, {4, 4});
    const int32_t h2 = w2.spawn(t2_heli, 0, {10, 10}, 0, 100, true);
    const int32_t flyer = w2.spawn(t_mig, 1, {12, 10}, 0, 100, true);
    w2.order_attack(&h2, 1, flyer);
    for (int t = 0; t < 200 && w2.air(size_t(w2.index_of(h2))).alt < 1280; ++t) w2.step();
    const int32_t ammo_before = w2.air(size_t(w2.index_of(h2))).ammo;
    for (int t = 0; t < 60; ++t) {
        w2.step();
        if (w2.index_of(flyer) < 0 || !w2.actor(size_t(w2.index_of(flyer))).alive) break;
    }
    const int hi2 = w2.index_of(h2);
    const int32_t shots = ammo_before - w2.air(size_t(hi2)).ammo;
    std::printf("Longbow gegen Flugziel: %d Schuss in 60 Ticks (ReloadDelay 30)\n", shots);
    CHECK(shots >= 1);
    CHECK(shots <= 3);


    World w3;
    w3.set_map(48, 48, cost.data());
    w3.define_weapon(ag); w3.define_weapon(aa);
    w3.define_type(hpad); w3.define_type(heli);
    const int t3_mig = w3.define_type(mig); w3.define_type(tank);
    w3.spawn_building(t_hpad, 0, {4, 4});
    const int32_t m3 = w3.spawn(t3_mig, 0, {10, 10}, 0, 100, true);
    const int32_t foe3 = w3.spawn(t3_mig, 1, {13, 10}, 0, 100, true);
    w3.order_attack(&m3, 1, foe3);
    for (int t = 0; t < 300; ++t) w3.step();
    const int mi3 = w3.index_of(m3), fi3 = w3.index_of(foe3);
    std::printf("MiG gegen Flugziel: Ziel %d, Munition %d, Gegner-HP %d\n",
                w3.combat(size_t(mi3)).target, w3.air(size_t(mi3)).ammo,
                fi3 >= 0 ? w3.actor(size_t(fi3)).hp : 0);
    CHECK(w3.combat(size_t(mi3)).target < 0);
    CHECK(w3.air(size_t(mi3)).ammo == 8);
    CHECK(fi3 >= 0 && w3.actor(size_t(fi3)).hp == 8000);
}


static void test_air_attack_run() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());
    Weapon gun;
    gun.range = 5 * CELL; gun.min_range = 2 * CELL + 512; gun.reload = 3; gun.burst = 2;
    gun.damage = 4000; gun.spread = 128; gun.speed = 0; gun.valid_targets = TT_GROUND_ACTOR;
    const int w_gun = w.define_weapon(gun);

    UnitType afld;
    afld.building = true; afld.foot_w = 2; afld.foot_h = 2; afld.footprint = {1, 1, 1, 1};
    afld.build_block = afld.footprint; afld.hp = 100000;
    afld.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    const int t_afld = w.define_type(afld);

    UnitType yak;
    yak.aircraft = true; yak.speed = 149; yak.turn_rate = 5; yak.cruise_altitude = 2560;
    yak.altitude_velocity = 86; yak.hp = 12000; yak.weapon = w_gun; yak.ammo_max = 18;
    yak.ammo_reload = 11; yak.air_attack_type = 0; yak.facing_tolerance = 80; yak.hit_radius = 426;
    yak.target_types = TT_GROUND_ACTOR | TT_VEHICLE; yak.target_types_airborne = TT_AIRBORNE;
    yak.rearm_actors = {t_afld};
    const int t_yak = w.define_type(yak);

    UnitType tank;
    tank.speed = 0; tank.turn_rate = 20; tank.hp = 200000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_tank = w.define_type(tank);

    w.spawn_building(t_afld, 0, {6, 6});
    const int32_t y = w.spawn(t_yak, 0, {8, 8}, 0, 100, true);
    const int32_t foe = w.spawn(t_tank, 1, {32, 32});
    w.order_attack(&y, 1, foe);
    int passes = 0;
    bool was_out = true;
    int32_t last_ammo = 18;
    for (int t = 0; t < 2000; ++t) {
        w.step();
        const int yi = w.index_of(y), fi = w.index_of(foe);
        if (yi < 0 || fi < 0) break;
        const int64_t d = length(w.actor(size_t(fi)).pos - w.actor(size_t(yi)).pos);
        if (d > 6 * CELL) was_out = true;
        const int32_t ammo = w.air(size_t(yi)).ammo;
        if (ammo < last_ammo) {
            if (was_out) { ++passes; was_out = false; }
            last_ammo = ammo;
        }
        if (ammo <= 0) break;
    }
    const int yi = w.index_of(y), fi = w.index_of(foe);
    std::printf("Angriffsflug: %d Anflüge, Munition %d/18, Ziel-HP %d\n",
                passes, w.air(size_t(yi)).ammo, w.actor(size_t(fi)).hp);
    CHECK(passes >= 2);
    CHECK(w.air(size_t(yi)).ammo == 0);
    CHECK(w.actor(size_t(fi)).hp < 200000 - 8 * 4000);

    for (int t = 0; t < 3000; ++t) {
        w.step();
        const int k = w.index_of(y);
        if (w.air(size_t(k)).state == Air::LANDED && w.air(size_t(k)).ammo >= 18) break;
    }
    const int yi2 = w.index_of(y);
    std::printf("Angriffsflug: nach dem Rückflug Zustand %d, Munition %d\n",
                w.air(size_t(yi2)).state, w.air(size_t(yi2)).ammo);
    CHECK(w.air(size_t(yi2)).state == Air::LANDED);
    CHECK(w.air(size_t(yi2)).ammo == 18);
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


    const int32_t pad2 = w.spawn_building(t_hpad, 0, {16, 16});
    CHECK(pad2 >= 0);
    CHECK(w.set_rally(pad2, {20, 20}));
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


static void test_landing_facing() {
    World w;
    std::vector<uint8_t> cost(64 * 64, 1);
    w.set_map(64, 64, cost.data());

    UnitType hpad;
    hpad.building = true; hpad.foot_w = 2; hpad.foot_h = 2; hpad.footprint = {1, 1, 1, 1};
    hpad.build_block = hpad.footprint; hpad.hp = 80000; hpad.provides = {"hpad"};
    hpad.exit_dx = 0; hpad.exit_dy = 0; hpad.exit_ox = 0; hpad.exit_oy = -256;
    hpad.exit_facing = 896;
    UnitType afld;
    afld.building = true; afld.foot_w = 3; afld.foot_h = 3;
    afld.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    afld.build_block = afld.footprint; afld.hp = 100000; afld.provides = {"afld"};
    afld.exit_dx = 1; afld.exit_dy = 1; afld.exit_ox = 0; afld.exit_oy = 0;
    afld.exit_facing = 768;
    const int t_hpad = w.define_type(hpad), t_afld = w.define_type(afld);

    UnitType heli;
    heli.aircraft = true; heli.can_hover = true; heli.vtol = true; heli.speed = 149;
    heli.turn_rate = 16; heli.cruise_altitude = 1280; heli.altitude_velocity = 43;
    heli.hp = 12000; heli.hit_radius = 426;
    heli.rearm_actors = {t_hpad}; heli.land_actors = {t_hpad};
    UnitType yak;
    yak.aircraft = true; yak.speed = 178; yak.turn_rate = 16; yak.cruise_altitude = 2560;
    yak.altitude_velocity = 43; yak.hp = 12000; yak.hit_radius = 426;
    yak.rearm_actors = {t_afld}; yak.land_actors = {t_afld};
    const int t_heli = w.define_type(heli), t_yak = w.define_type(yak);

    const int32_t pad = w.spawn_building(t_hpad, 0, {12, 12});
    const int32_t fld = w.spawn_building(t_afld, 0, {40, 40});
    const int pi = w.index_of(pad), fi = w.index_of(fld);


    const int32_t h = w.spawn(t_heli, 0, CPos{40, 12}, -1, 100, true);

    CHECK(w.actor(size_t(w.index_of(h))).facing == AIRCRAFT_INITIAL_FACING);
    WAngle heli_face[2] = {-1, -1};
    for (int run = 0; run < 2; ++run) {
        CHECK(w.can_resupply_at(h, pad));
        w.order_resupply(&h, 1, pad);
        int hi = w.index_of(h);
        for (int t = 0; t < 2000; ++t) {
            w.step();
            hi = w.index_of(h);
            if (w.air(size_t(hi)).state == Air::LANDED) break;
        }
        hi = w.index_of(h);
        CHECK(w.air(size_t(hi)).state == Air::LANDED);
        CHECK(w.actor(size_t(hi)).facing == hpad.exit_facing);
        CHECK(w.actor(size_t(hi)).pos.x == w.actor(size_t(pi)).pos.x + hpad.exit_ox);
        CHECK(w.actor(size_t(hi)).pos.y == w.actor(size_t(pi)).pos.y + hpad.exit_oy);
        heli_face[run] = w.actor(size_t(hi)).facing;

        const CPos away = run == 0 ? CPos{12, 45} : CPos{12, 12};
        w.order_move(&h, 1, away, 0);
        for (int t = 0; t < 900; ++t) {
            w.step();
            hi = w.index_of(h);


            if (w.air(size_t(hi)).state == Air::TAKING_OFF)
                CHECK(w.actor(size_t(hi)).facing == hpad.exit_facing);
            if (!w.air(size_t(hi)).has_goal && w.air(size_t(hi)).state == Air::CRUISING) break;
        }
    }
    CHECK(heli_face[0] == heli_face[1]);
    std::printf("Landerichtung: Hubschrauber auf hpad %d und %d (Exit.Facing %d)\n",
                heli_face[0], heli_face[1], hpad.exit_facing);


    const CPos starts[3] = {{6, 40}, {40, 6}, {58, 58}};
    for (int run = 0; run < 3; ++run) {
        const int32_t y = w.spawn(t_yak, 0, starts[run], -1, 100, true);
        int yi = w.index_of(y);
        CHECK(w.can_resupply_at(y, fld));
        w.order_resupply(&y, 1, fld);
        for (int t = 0; t < 3000; ++t) {
            w.step();
            yi = w.index_of(y);
            if (w.air(size_t(yi)).state == Air::LANDED) break;
        }
        yi = w.index_of(y);
        CHECK(w.air(size_t(yi)).state == Air::LANDED);
        CHECK(w.air(size_t(yi)).alt == 0);
        CHECK(w.actor(size_t(yi)).facing == afld.exit_facing);
        CHECK(w.actor(size_t(yi)).pos.x == w.actor(size_t(fi)).pos.x + afld.exit_ox);
        CHECK(w.actor(size_t(yi)).pos.y == w.actor(size_t(fi)).pos.y + afld.exit_oy);
        std::printf("Landerichtung: Jak aus (%d,%d) auf afld %d (Pistenrichtung %d)\n",
                    starts[run].x, starts[run].y, w.actor(size_t(yi)).facing, afld.exit_facing);

        w.destroy(w.actor(size_t(yi)).id);
        for (int t = 0; t < 5; ++t) w.step();
    }


    const int32_t h2 = w.spawn(t_yak, 0, CPos{41, 41}, -1, 100, false);
    const int h2i = w.index_of(h2);
    CHECK(w.air(size_t(h2i)).state == Air::LANDED);
    CHECK(w.actor(size_t(h2i)).facing == afld.exit_facing);
    CHECK(w.actor(size_t(h2i)).pos.x == w.actor(size_t(fi)).pos.x + afld.exit_ox);
    std::printf("Landerichtung: von der Karte gesetzte Jak steht angedockt in %d\n",
                w.actor(size_t(h2i)).facing);
}


static void test_landing_pads() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.hp = 150000; fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true;
    fact.provides = {"fact"};
    UnitType afld;
    afld.building = true; afld.foot_w = 2; afld.foot_h = 2; afld.footprint = {1, 1, 1, 1};
    afld.build_block = afld.footprint; afld.hp = 80000; afld.produces = 1u << QUEUE_AIRCRAFT;
    afld.target_types = TT_GROUND_ACTOR | TT_STRUCTURE; afld.provides = {"afld"};
    afld.reservable = true;
    afld.exit_dx = 0; afld.exit_dy = 0; afld.rally_dx = 0; afld.rally_dy = 1;
    UnitType mig;
    mig.aircraft = true; mig.speed = 186; mig.turn_rate = 20;
    mig.cruise_altitude = 2560; mig.altitude_velocity = 43; mig.hp = 8000;
    mig.hit_radius = 426; mig.cost = 100; mig.queue_kind = QUEUE_AIRCRAFT;
    mig.prerequisites = {"afld"};
    mig.target_types = TT_GROUND_ACTOR | TT_VEHICLE; mig.target_types_airborne = TT_AIRBORNE;
    const int t_fact = w.define_type(fact), t_afld = w.define_type(afld);
    mig.land_actors = {t_afld};
    const int t_mig = w.define_type(mig);

    w.spawn_building(t_fact, 0, {10, 10});
    const int32_t pad1 = w.spawn_building(t_afld, 0, {16, 10});
    const int32_t pad2 = w.spawn_building(t_afld, 0, {16, 14});
    w.give_credits(0, 5000);


    std::vector<int32_t> ids;
    for (int n = 0; n < 2; ++n) {
        const size_t before = w.actor_count();
        CHECK(w.queue_build(0, t_mig));
        for (int t = 0; t < 400 && w.actor_count() == before; ++t) w.step();
        CHECK(w.actor_count() == before + 1);
        ids.push_back(w.actor(before).id);
        for (int t = 0; t < 20; ++t) w.step();
    }
    const int a0 = w.index_of(ids[0]), a1 = w.index_of(ids[1]);
    CHECK(a0 >= 0 && a1 >= 0);
    CHECK(w.air(size_t(a0)).base != w.air(size_t(a1)).base);
    CHECK(w.air(size_t(a0)).base == pad1 || w.air(size_t(a0)).base == pad2);
    CHECK(w.air(size_t(a1)).base == pad1 || w.air(size_t(a1)).base == pad2);
    CHECK(w.actor(size_t(a0)).pos.x != w.actor(size_t(a1)).pos.x ||
          w.actor(size_t(a0)).pos.y != w.actor(size_t(a1)).pos.y);
    std::printf("Landeplätze: MiG 1 auf %d, MiG 2 auf %d (Plätze %d/%d)\n",
                w.air(size_t(a0)).base, w.air(size_t(a1)).base, pad1, pad2);


    std::vector<int32_t> list;
    w.buildable(0, QUEUE_AIRCRAFT, list);
    CHECK(std::find(list.begin(), list.end(), int32_t(t_mig)) == list.end());
    CHECK(w.free_landing_pads(0, t_mig) <= 0);


    const int32_t pad3 = w.spawn_building(t_afld, 0, {16, 18});
    w.buildable(0, QUEUE_AIRCRAFT, list);
    CHECK(std::find(list.begin(), list.end(), int32_t(t_mig)) != list.end());
    CHECK(w.free_landing_pads(0, t_mig) == 1);
    const size_t before3 = w.actor_count();
    CHECK(w.queue_build(0, t_mig));
    for (int t = 0; t < 400 && w.actor_count() == before3; ++t) w.step();
    CHECK(w.actor_count() == before3 + 1);
    const int32_t third = w.actor(before3).id;
    for (int t = 0; t < 20; ++t) w.step();
    CHECK(w.air(size_t(w.index_of(third))).base == pad3);
    std::printf("Landeplätze: dritte MiG erst mit drittem Flugplatz baubar, Platz %d\n", pad3);


    w.destroy(third);
    const int32_t victim_pad = w.air(size_t(w.index_of(ids[0]))).base;
    w.destroy(victim_pad);
    for (int t = 0; t < 600; ++t) w.step();
    const int again = w.index_of(ids[0]);
    CHECK(again >= 0 && w.actor(size_t(again)).alive);
    CHECK(w.air(size_t(again)).base == pad3);
    CHECK(w.air(size_t(again)).base != w.air(size_t(w.index_of(ids[1]))).base);
    std::printf("Landeplätze: nach der Zerstörung von Platz %d landet die MiG auf %d\n",
                victim_pad, w.air(size_t(again)).base);


    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    const int32_t base0 = w.air(size_t(w.index_of(ids[0]))).base;
    const int32_t base1 = w.air(size_t(w.index_of(ids[1]))).base;
    for (int t = 0; t < 50; ++t) w.step();
    CHECK(w.load(blob));
    CHECK(w.air(size_t(w.index_of(ids[0]))).base == base0);
    CHECK(w.air(size_t(w.index_of(ids[1]))).base == base1);
    CHECK(w.free_landing_pads(0, t_mig) == 0);
    std::printf("Landeplätze: Reservierungen %d/%d nach dem Laden unverändert\n", base0, base1);
}


static void test_fall_to_earth() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    Weapon boom;
    boom.range = 0; boom.reload = 1; boom.damage = 5000; boom.spread = 426;
    boom.speed = 0; boom.valid_targets = TT_GROUND_ACTOR;
    const int w_boom = w.define_weapon(boom);

    UnitType plane_husk;
    plane_husk.aircraft = true; plane_husk.husk = true; plane_husk.speed = 186; plane_husk.turn_rate = 20;
    plane_husk.hp = 28000; plane_husk.cruise_altitude = 2560; plane_husk.altitude_velocity = 43;
    plane_husk.falls_to_earth = true; plane_husk.fall_moves = true; plane_husk.fall_velocity = 86;
    plane_husk.fall_max_spin = 0; plane_husk.fall_weapon = w_boom;
    plane_husk.target_types_airborne = TT_AIRBORNE;
    UnitType heli_husk = plane_husk;
    heli_husk.fall_moves = false; heli_husk.fall_velocity = 43; heli_husk.fall_max_spin = -1;
    heli_husk.speed = 149;
    const int t_ph = w.define_type(plane_husk), t_hh = w.define_type(heli_husk);

    UnitType mig;
    mig.aircraft = true; mig.speed = 186; mig.turn_rate = 20; mig.hp = 8000;
    mig.cruise_altitude = 2560; mig.altitude_velocity = 43; mig.hit_radius = 426;
    mig.husk_actor = t_ph;
    mig.target_types = TT_GROUND_ACTOR | TT_VEHICLE; mig.target_types_airborne = TT_AIRBORNE;
    UnitType heli = mig;
    heli.can_hover = true; heli.vtol = true; heli.speed = 149; heli.cruise_altitude = 1280;
    heli.husk_actor = t_hh;
    UnitType tank;
    tank.speed = 0; tank.turn_rate = 20; tank.hp = 40000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    const int t_mig = w.define_type(mig), t_heli = w.define_type(heli), t_tank = w.define_type(tank);


    const int32_t m = w.spawn(t_mig, 0, {20, 20}, 0, 100, true);
    int mi = w.index_of(m);
    CHECK(w.air(size_t(mi)).alt == 2560);
    const WVec start = w.actor(size_t(mi)).pos;
    w.destroy(m);
    mi = w.index_of(m);
    CHECK(mi >= 0);
    CHECK(w.actor(size_t(mi)).alive);
    CHECK(w.actor(size_t(mi)).type == t_ph);
    CHECK(w.air(size_t(mi)).state == Air::FALLING);
    CHECK(w.air(size_t(mi)).spin == 0);
    const WAngle face0 = w.actor(size_t(mi)).facing;
    int ticks = 0;
    int32_t last_alt = w.air(size_t(mi)).alt;
    while (w.actor(size_t(w.index_of(m))).alive && ticks < 200) {
        w.step();
        ++ticks;
        const int k = w.index_of(m);
        if (k < 0 || !w.actor(size_t(k)).alive) break;
        CHECK(w.air(size_t(k)).alt < last_alt);
        last_alt = w.air(size_t(k)).alt;
        CHECK(w.actor(size_t(k)).facing == face0);
    }

    CHECK(ticks == 31);
    const int mk = w.index_of(m);
    CHECK(mk < 0 || !w.actor(size_t(mk)).alive);
    const WVec end = mk >= 0 ? w.actor(size_t(mk)).pos : start;
    CHECK(end.x != start.x || end.y != start.y);
    std::printf("Absturz Flugzeug: %d Ticks bis zum Aufschlag, %d Welteinheiten vorwärts\n",
                ticks, int(length(end - start)));


    const int32_t hcopter = w.spawn(t_heli, 0, {30, 30}, 0, 100, true);
    const int32_t below = w.spawn(t_tank, 1, {30, 30});
    const int32_t hp_before = w.actor(size_t(w.index_of(below))).hp;
    int hi = w.index_of(hcopter);
    const WVec hstart = w.actor(size_t(hi)).pos;
    const WAngle hface = w.actor(size_t(hi)).facing;
    w.destroy(hcopter);
    hi = w.index_of(hcopter);
    CHECK(w.air(size_t(hi)).state == Air::FALLING);
    CHECK(w.air(size_t(hi)).spin != 0);
    for (int t = 0; t < 200; ++t) {
        w.step();
        const int k = w.index_of(hcopter);
        if (k < 0 || !w.actor(size_t(k)).alive) break;
    }
    const int hk = w.index_of(hcopter);
    CHECK(hk >= 0);
    CHECK(!w.actor(size_t(hk)).alive);
    CHECK(w.actor(size_t(hk)).pos.x == hstart.x && w.actor(size_t(hk)).pos.y == hstart.y);
    CHECK(w.actor(size_t(hk)).facing != hface);
    const int bi = w.index_of(below);
    CHECK(bi >= 0 && w.actor(size_t(bi)).hp < hp_before);
    std::printf("Absturz Hubschrauber: senkrecht gefallen, Blickrichtung %d → %d (Trudeln), "
                "Panzer darunter %d → %d HP\n",
                hface, w.actor(size_t(hk)).facing, hp_before, w.actor(size_t(bi)).hp);


    const int32_t h2 = w.spawn(t_heli, 0, {10, 30}, 0, 100, true);
    w.destroy(h2);
    for (int t = 0; t < 5; ++t) w.step();
    int k2 = w.index_of(h2);
    CHECK(k2 >= 0 && w.air(size_t(k2)).state == Air::FALLING);
    const int32_t alt2 = w.air(size_t(k2)).alt, spin2 = w.air(size_t(k2)).spin;
    const int32_t type2 = w.actor(size_t(k2)).type;
    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    int fall1 = 0;
    while (fall1 < 200) {
        w.step(); ++fall1;
        const int k = w.index_of(h2);
        if (k < 0 || !w.actor(size_t(k)).alive) break;
    }
    CHECK(w.load(blob));
    k2 = w.index_of(h2);
    CHECK(k2 >= 0 && w.actor(size_t(k2)).alive);
    CHECK(w.air(size_t(k2)).state == Air::FALLING);
    CHECK(w.air(size_t(k2)).alt == alt2 && w.air(size_t(k2)).spin == spin2);
    CHECK(w.actor(size_t(k2)).type == type2);
    int fall2 = 0;
    while (fall2 < 200) {
        w.step(); ++fall2;
        const int k = w.index_of(h2);
        if (k < 0 || !w.actor(size_t(k)).alive) break;
    }
    CHECK(fall1 == fall2);
    std::printf("Absturz: Spielstand mitten im Trudeln — Höhe %d, Drehung %d, Aufschlag nach %d Ticks\n",
                alt2, spin2, fall2);


    const int32_t parked = w.spawn(t_mig, 0, {12, 12}, 0, 100, false);
    const int pi = w.index_of(parked);
    CHECK(w.air(size_t(pi)).alt == 0);
    w.destroy(parked);
    const int pk = w.index_of(parked);
    CHECK(pk < 0 || !w.actor(size_t(pk)).alive);
    std::printf("Absturz: am Boden getroffene Maschine explodiert ohne Wrack\n");
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


struct MpSetup {
    std::vector<int32_t> troop0, troop1;
    int32_t t_powr = -1, t_e1 = -1;
};


static MpSetup build_mp(World& w, uint32_t seed, uint32_t vis_mask) {
    MpSetup s;
    w.set_rng_seed(seed);
    std::vector<uint8_t> cost(64 * 64, 1);
    for (int i = 0; i < 64 * 64; i += 53) cost[size_t(i)] = 0;
    w.set_map(64, 64, cost.data());

    Weapon gun; gun.range = 5 * CELL; gun.reload = 40; gun.damage = 2500; gun.spread = 128; gun.speed = 0;
    const int wgun = w.define_weapon(gun);
    UnitType fact;
    fact.building = true; fact.foot_w = 3; fact.foot_h = 3; fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1};
    fact.build_block = fact.footprint; fact.hp = 150000; fact.armor = ARMOR_WOOD; fact.cost = 2000;
    fact.produces = 1u << QUEUE_BUILDING; fact.base_provider = true; fact.provides = {"fact"};
    fact.reveal_range = 6 * CELL;
    UnitType powr;
    powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.build_block = powr.footprint; powr.hp = 40000; powr.armor = ARMOR_WOOD; powr.power = 100;
    powr.cost = 300; powr.queue_kind = QUEUE_BUILDING; powr.provides = {"powr", "anypower"};
    powr.make_ticks = 20; powr.ai_building_fraction = 1; powr.reveal_range = 4 * CELL;
    UnitType tent;
    tent.building = true; tent.foot_w = 2; tent.foot_h = 2; tent.footprint = {1, 1, 1, 1};
    tent.build_block = tent.footprint; tent.hp = 60000; tent.armor = ARMOR_WOOD; tent.power = -20;
    tent.cost = 500; tent.queue_kind = QUEUE_BUILDING; tent.prerequisites = {"anypower"};
    tent.provides = {"tent", "barracks"}; tent.produces = 1u << QUEUE_INFANTRY;
    tent.exit_dx = 1; tent.exit_dy = 2; tent.make_ticks = 20; tent.ai_building_fraction = 3;
    UnitType e1;
    e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.cost = 100; e1.weapon = wgun;
    e1.hit_radius = 128; e1.queue_kind = QUEUE_INFANTRY; e1.prerequisites = {"barracks"};
    e1.ai_unit_share = 100; e1.locomotor = LOCO_FOOT; e1.reveal_range = 4 * CELL;

    const int t_fact = w.define_type(fact);
    s.t_powr = w.define_type(powr);
    w.define_type(tent);
    s.t_e1 = w.define_type(e1);

    w.spawn_building(t_fact, 0, {6, 6});
    w.spawn_building(t_fact, 1, {50, 50});
    w.spawn_building(t_fact, 4, {50, 6});
    w.give_credits(0, 20000);
    w.give_credits(1, 20000);
    w.give_credits(4, 20000);
    BotParams bp; bp.squad_size = 4; bp.squad_size_random_bonus = 2;
    w.enable_bot(4, bp);
    for (int i = 0; i < 10; ++i) s.troop0.push_back(w.spawn(s.t_e1, 0, {10 + i, 20}));
    for (int i = 0; i < 10; ++i) s.troop1.push_back(w.spawn(s.t_e1, 1, {40 + i, 44}));

    w.set_visibility_players(vis_mask);
    return s;
}


static std::vector<int32_t> mp_cmd(int32_t op, int32_t a, int32_t b, int32_t c, int32_t d,
                                   const std::vector<int32_t>& ids) {
    std::vector<int32_t> v = {op, a, b, c, d, int32_t(ids.size())};
    v.insert(v.end(), ids.begin(), ids.end());
    return v;
}
static bool mp_apply(World& w, int32_t player, const std::vector<int32_t>& v) {
    return w.apply_order(player, v.data(), v.size());
}


static void mp_script(World& w, const MpSetup& s, uint32_t t) {
    if (t % 37 == 0) {
        const size_t k = (t / 37) % s.troop0.size();
        mp_apply(w, 0, mp_cmd(1, int32_t(5 + (t * 7) % 55), int32_t(5 + (t * 11) % 55), 0, 0, {s.troop0[k]}));
    }
    if (t % 41 == 0) {
        const size_t k = (t / 41) % s.troop1.size();
        const int32_t queued = ((t / 41) % 2 == 0) ? 0 : 1;
        mp_apply(w, 1, mp_cmd(0, int32_t(5 + (t * 13) % 55), int32_t(5 + (t * 3) % 55), queued, 0, {s.troop1[k]}));
    }
    if (t % 97 == 0) {
        mp_apply(w, 0, mp_cmd(30, s.t_powr, 0, 0, 0, {}));
        mp_apply(w, 1, mp_cmd(30, s.t_powr, 0, 0, 0, {}));
    }
    if (t % 211 == 0) {

        static const CPos spots0[6] = {{4, 4}, {9, 4}, {4, 9}, {9, 9}, {4, 6}, {9, 6}};
        static const CPos spots1[6] = {{48, 48}, {53, 48}, {48, 53}, {53, 53}, {48, 50}, {53, 50}};
        const size_t k = (t / 211) % 6;
        mp_apply(w, 0, mp_cmd(33, s.t_powr, spots0[k].x, spots0[k].y, 0, {}));
        mp_apply(w, 1, mp_cmd(33, s.t_powr, spots1[k].x, spots1[k].y, 0, {}));
    }
    if (t % 313 == 0) {
        mp_apply(w, 0, mp_cmd(24, int32_t((t / 313) % 4), 0, 0, 0, s.troop0));
        mp_apply(w, 1, mp_cmd(4, 0, 0, 0, 0, s.troop1));
    }
}

static void test_mp_lockstep() {
    World a, b;
    const MpSetup sa = build_mp(a, 0x13579BDFu, 0b0000'0011u);
    const MpSetup sb = build_mp(b, 0x13579BDFu, 0b0000'0011u);
    uint32_t first_diff = 0;
    for (uint32_t t = 0; t < 5000; ++t) {
        mp_script(a, sa, t);
        mp_script(b, sb, t);
        a.step();
        b.step();
        if (first_diff == 0 && a.state_hash() != b.state_hash()) first_diff = t + 1;
    }
    CHECK(first_diff == 0);
    CHECK(a.state_hash() == b.state_hash());


    CHECK(a.state_hash_full() == b.state_hash_full());
    std::printf("Gleichschritt: 5000 Ticks, 2 Plätze + KI, Hash %016llx %s\n",
                static_cast<unsigned long long>(a.state_hash()),
                first_diff == 0 ? "Tick für Tick identisch" : "ABWEICHUNG");
}


static void test_mp_desync_detected() {
    World a, b;
    const MpSetup sa = build_mp(a, 0x2468ACE0u, 0b0000'0011u);
    const MpSetup sb = build_mp(b, 0x2468ACE0u, 0b0000'0011u);
    uint32_t first_diff = 0;
    for (uint32_t t = 0; t < 1200; ++t) {
        mp_script(a, sa, t);
        mp_script(b, sb, t);
        if (t == 600) b.give_credits(1, 1);
        a.step();
        b.step();
        if (first_diff == 0 && a.state_hash() != b.state_hash()) first_diff = t + 1;
    }
    CHECK(first_diff == 601);
    CHECK(a.state_hash() != b.state_hash());
    std::printf("Desync: ein Credit Unterschied fällt in Tick %u auf\n", first_diff);
}


static void test_mp_visibility_mask() {
    auto lit_cells = [](const World& w, int32_t p) {
        const std::vector<uint8_t>& v = w.visibility(p);
        size_t n = 0;
        for (const uint8_t c : v) n += (c != 0) ? 1 : 0;
        return n;
    };


    World one;
    build_mp(one, 0xABCDEF01u, 0b0000'0001u);
    for (int t = 0; t < 60; ++t) one.step();
    CHECK(one.visibility_players() == 0b0000'0001u);
    CHECK(lit_cells(one, 0) > 0);
    CHECK(lit_cells(one, 1) == 0);


    World a, b;
    build_mp(a, 0xABCDEF01u, 0b0000'0011u);
    build_mp(b, 0xABCDEF01u, 0b0000'0011u);
    for (int t = 0; t < 300; ++t) { a.step(); b.step(); }
    CHECK(lit_cells(a, 0) > 0 && lit_cells(a, 1) > 0);
    CHECK(a.visibility(0) == b.visibility(0));
    CHECK(a.visibility(1) == b.visibility(1));
    CHECK(a.state_hash() == b.state_hash());


    World six;
    const MpSetup ss = build_mp(six, 0x5A5A5A5Au, 0b0011'0011u);
    six.spawn(ss.t_e1, 5, {30, 30});
    six.spawn(ss.t_e1, 2, {20, 30});
    six.spawn(ss.t_e1, 3, {22, 30});
    for (int t = 0; t < 60; ++t) six.step();
    CHECK(six.visibility_players() == 0b0011'0011u);
    for (const int32_t p : {0, 1, 4, 5}) CHECK(lit_cells(six, p) > 0);
    for (const int32_t p : {2, 3}) CHECK(lit_cells(six, p) == 0);
    std::printf("Sicht: Maske 0b110011 — Plätze 0/1/4/5 gepflegt, 2/3 leer\n");
}


static void test_mp_apply_order_owner() {
    World w;
    const MpSetup s = build_mp(w, 0x0F0F0F0Fu, 0b0000'0011u);
    const int32_t mine = s.troop0[0], theirs = s.troop1[0];


    const CPos before = w.mobile(size_t(w.index_of(theirs))).cell;
    CHECK(!mp_apply(w, 0, mp_cmd(0, 5, 5, 0, 0, {theirs})));
    CHECK(!w.has_move_order(theirs));
    for (int t = 0; t < 20; ++t) w.step();
    CHECK(w.mobile(size_t(w.index_of(theirs))).cell == before);


    CHECK(mp_apply(w, 0, mp_cmd(0, 30, 30, 0, 0, {theirs, mine, 999999})));
    CHECK(w.has_move_order(mine));
    CHECK(!w.has_move_order(theirs));


    CHECK(mp_apply(w, 1, mp_cmd(30, s.t_powr, 0, 0, 0, {})));
    for (int t = 0; t < 3000 && (w.queue(1, QUEUE_BUILDING).empty() || !w.queue(1, QUEUE_BUILDING).front().done); ++t)
        w.step();
    CHECK(!w.queue(1, QUEUE_BUILDING).empty() && w.queue(1, QUEUE_BUILDING).front().done);

    CPos spot{-1, -1};
    for (int y = 46; y < 56 && spot.x < 0; ++y)
        for (int x = 46; x < 56; ++x)
            if (w.can_place(1, s.t_powr, CPos{x, y}, nullptr)) { spot = CPos{x, y}; break; }
    CHECK(spot.x >= 0);


    const size_t actors_before = w.actor_count();
    CHECK(mp_apply(w, 0, mp_cmd(33, s.t_powr, spot.x, spot.y, 0, {})));
    CHECK(w.actor_count() == actors_before);
    CHECK(mp_apply(w, 1, mp_cmd(33, s.t_powr, spot.x, spot.y, 0, {})));
    CHECK(w.actor_count() == actors_before + 1);
    CHECK(w.actor(actors_before).owner == 1);


    const int32_t foreign_building = w.actor(actors_before).id;
    CHECK(!mp_apply(w, 0, mp_cmd(34, 0, 0, 0, 0, {foreign_building})));
    CHECK(w.index_of(foreign_building) >= 0);
    CHECK(w.actor(size_t(w.index_of(foreign_building))).sell_ticks < 0);


    const std::vector<int32_t> short_cmd = {0, 1, 2};
    CHECK(!w.apply_order(0, short_cmd.data(), short_cmd.size()));
    CHECK(!mp_apply(w, 0, mp_cmd(99, 0, 0, 0, 0, {})));
    CHECK(!mp_apply(w, MAX_PLAYERS, mp_cmd(4, 0, 0, 0, 0, {mine})));
    CHECK(!mp_apply(w, -1, mp_cmd(4, 0, 0, 0, 0, {mine})));


    CHECK(mp_apply(w, 1, mp_cmd(50, 0, 0, 0, 0, {})));
    CHECK(w.win_state(1) == WIN_LOST);
    CHECK(w.win_state(0) == WIN_UNDEFINED);
    std::printf("apply_order: fremde Kennungen verworfen, Baubefehle auf den Absender gestempelt\n");
}


static void bench_visibility() {
    {
        World w;
        build_mp(w, 0x77777777u, 0b0000'0001u);
        for (int t = 0; t < 200; ++t) w.step();
        int64_t best = INT64_MAX;
        for (int r = 0; r < 3; ++r) {
            const auto t0 = std::chrono::steady_clock::now();
            for (int k = 0; k < 500; ++k) w.update_visibility(0);
            const int64_t us = std::chrono::duration_cast<std::chrono::microseconds>(
                                   std::chrono::steady_clock::now() - t0).count();
            best = std::min(best, us);
        }
        std::printf("Sicht-Benchmark: eine Auflösung (64x64, %zu Actors): %.1f µs\n",
                    w.actor_count(), double(best) / 500.0);
    }


    for (const uint32_t mask : {0b0000'0001u, 0b0001'0011u, 0b1111'0011u}) {
        int bits = 0;
        for (int p = 0; p < MAX_PLAYERS; ++p) bits += int((mask >> p) & 1u);
        int64_t best = INT64_MAX;
        for (int r = 0; r < 3; ++r) {
            World w;
            const MpSetup s = build_mp(w, 0x77777777u, mask);
            for (int p = 2; p < MAX_PLAYERS; ++p) w.spawn(s.t_e1, int32_t(p), {20 + p, 30});
            for (int t = 0; t < 200; ++t) w.step();
            const auto t0 = std::chrono::steady_clock::now();
            const int ticks = 1000;
            for (int t = 0; t < ticks; ++t) w.step();
            const int64_t us = std::chrono::duration_cast<std::chrono::microseconds>(
                                   std::chrono::steady_clock::now() - t0).count();
            best = std::min(best, us);
        }
        std::printf("Sicht-Benchmark: %d Betrachter, 64x64: %.1f µs/Tick (Budget bei 25 Hz: 40000 µs)\n",
                    bits, double(best) / 1000.0);
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
        mix(a.load_lock ? 1 : 0); mix(a.load_takeoff ? 1 : 0); mix(a.after_load_ticks);
        mix(a.unload_takeoff ? 1 : 0);
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


static void test_c4_vehicles() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    w.set_alliance(0, 2, true);
    UnitType tank; tank.speed = 85; tank.turn_rate = 20; tank.hp = 60000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tank.demolishable = true; tank.capturable = true;
    UnitType apc; apc.speed = 128; apc.turn_rate = 20; apc.hp = 35000; apc.hit_radius = 426;
    apc.cargo_max_weight = 5; apc.cargo_types = TT_INFANTRY;
    apc.target_types = TT_GROUND_ACTOR | TT_VEHICLE; apc.demolishable = true;
    UnitType tanya; tanya.speed = 68; tanya.turn_rate = 1024; tanya.infantry = true; tanya.hp = 10000;
    tanya.demolition_delay = 45; tanya.locomotor = LOCO_FOOT;
    tanya.passenger_weight = 1; tanya.passenger_type = TT_INFANTRY;
    tanya.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_tank = w.define_type(tank), t_apc = w.define_type(apc), t_tanya = w.define_type(tanya);


    const int32_t foe = w.spawn(t_tank, 1, {24, 10});
    const int32_t t1 = w.spawn(t_tanya, 0, {18, 10});
    CHECK(w.enter_kind_for(size_t(w.index_of(t1)), size_t(w.index_of(foe))) == ENTER_DEMOLISH);
    w.order_enter(&t1, 1, foe, ENTER_NONE);
    int planted = 0;
    for (; planted < 900 && w.actor(size_t(w.index_of(foe))).demolish_ticks < 0; ++planted) w.step();
    CHECK(w.actor(size_t(w.index_of(foe))).demolish_ticks >= 0);
    const int32_t fuse = w.actor(size_t(w.index_of(foe))).demolish_ticks;
    CHECK(fuse <= 45);
    int boom = 0;
    for (; boom < 200 && w.index_of(foe) >= 0 && w.actor(size_t(w.index_of(foe))).alive; ++boom) w.step();
    CHECK(w.index_of(foe) < 0 || !w.actor(size_t(w.index_of(foe))).alive);
    CHECK(boom <= 46);
    const int ti = w.index_of(t1);
    CHECK(ti >= 0 && w.actor(size_t(ti)).alive);
    CHECK(!w.actor(size_t(ti)).inside);


    const int32_t own = w.spawn(t_tank, 0, {18, 14});
    const int32_t ally = w.spawn(t_tank, 2, {18, 16});
    CHECK(w.enter_kind_for(size_t(w.index_of(t1)), size_t(w.index_of(own))) == ENTER_NONE);
    CHECK(w.enter_kind_for(size_t(w.index_of(t1)), size_t(w.index_of(ally))) == ENTER_NONE);
    w.order_enter(&t1, 1, own, ENTER_NONE);
    for (int t = 0; t < 60; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(own))).demolish_ticks < 0);
    CHECK(!w.actor(size_t(w.index_of(t1))).inside);


    const int32_t bus = w.spawn(t_apc, 0, {14, 10});
    w.order_enter_transport(&t1, 1, bus);
    for (int t = 0; t < 400 && w.transport_of(t1) != bus; ++t) w.step();
    CHECK(w.transport_of(t1) == bus);
    std::printf("C4 gegen Fahrzeuge: Zünder %d Ticks, Panzer nach %d Ticks zerstört, "
                "eigenes/verbündetes Fahrzeug kein Ziel, MTW nimmt Tanya weiter auf\n", fuse, boom);
}


static void test_c4_moving_vehicle_exit() {
    World w;
    std::vector<uint8_t> cost(60 * 60, 1);
    w.set_map(60, 60, cost.data());
    UnitType tank; tank.speed = 85; tank.turn_rate = 20; tank.hp = 60000; tank.hit_radius = 426;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tank.demolishable = true;
    UnitType hall; hall.building = true; hall.foot_w = 2; hall.foot_h = 2; hall.footprint = {1, 1, 1, 1};
    hall.sprite_h = 2; hall.hp = 40000; hall.target_types = TT_STRUCTURE;
    UnitType tanya; tanya.speed = 68; tanya.turn_rate = 1024; tanya.infantry = true; tanya.hp = 10000;
    tanya.demolition_delay = 45; tanya.locomotor = LOCO_FOOT;
    tanya.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    const int t_tank = w.define_type(tank), t_hall = w.define_type(hall), t_tanya = w.define_type(tanya);


    const int32_t foe = w.spawn(t_tank, 1, {24, 10});
    const int32_t t1 = w.spawn(t_tanya, 0, {40, 44});
    w.order_move(&foe, 1, {42, 40});
    for (int t = 0; t < 900 && w.mobile(size_t(w.index_of(foe))).cell.x < 40; ++t) w.step();
    const CPos far_cell = w.mobile(size_t(w.index_of(foe))).cell;
    CHECK(far_cell.x > 30);
    w.spawn_building(t_hall, 1, {23, 9});
    CHECK(w.actor(size_t(w.index_of(foe))).origin.x == 24);

    CHECK(w.enter_kind_for(size_t(w.index_of(t1)), size_t(w.index_of(foe))) == ENTER_DEMOLISH);
    w.order_enter(&t1, 1, foe, ENTER_NONE);
    int planted = 0;
    for (; planted < 900 && w.actor(size_t(w.index_of(foe))).demolish_ticks < 0; ++planted) w.step();
    CHECK(w.actor(size_t(w.index_of(foe))).demolish_ticks >= 0);


    const CPos boom_cell = w.mobile(size_t(w.index_of(foe))).cell;
    for (int t = 0; t < 5; ++t) w.step();
    const int ti = w.index_of(t1);
    CHECK(ti >= 0 && w.actor(size_t(ti)).alive);
    CHECK(!w.actor(size_t(ti)).inside);
    const CPos tc = w.mobile(size_t(ti)).cell;
    CHECK(std::abs(tc.x - boom_cell.x) <= 2 && std::abs(tc.y - boom_cell.y) <= 2);
    CHECK(std::abs(tc.x - 24) > 2 || std::abs(tc.y - 10) > 2);
    for (int t = 0; t < 120 && w.index_of(foe) >= 0 && w.actor(size_t(w.index_of(foe))).alive; ++t) w.step();
    CHECK(w.index_of(foe) < 0 || !w.actor(size_t(w.index_of(foe))).alive);
    std::printf("C4 auf fahrenden Panzer: Ladung bei (%d,%d) gelegt, Tanya steigt bei (%d,%d) aus "
                "(Ursprung 24,10), Panzer zerstört\n", boom_cell.x, boom_cell.y, tc.x, tc.y);
}


static void test_demolish_neutral() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    w.set_neutral_player(3);
    w.set_non_combatant(3, true);
    w.set_alliance(0, 2, true);

    UnitType civ; civ.building = true; civ.foot_w = 2; civ.foot_h = 2; civ.footprint = {1, 1, 1, 1};
    civ.sprite_h = 2; civ.hp = 40000; civ.demolishable = true;
    civ.target_types = TT_GROUND_ACTOR | TT_STRUCTURE | TT_C4;
    UnitType tanya; tanya.speed = 68; tanya.turn_rate = 1024; tanya.infantry = true; tanya.hp = 10000;
    tanya.demolition_delay = 45; tanya.locomotor = LOCO_FOOT;
    const int t_civ = w.define_type(civ), t_tanya = w.define_type(tanya);

    const int32_t house = w.spawn_building(t_civ, 3, {20, 10});
    const int32_t friend_house = w.spawn_building(t_civ, 2, {20, 20});
    const int32_t t1 = w.spawn(t_tanya, 0, {14, 10});
    CHECK(!w.hostile(0, 3));
    CHECK(w.enter_kind_for(size_t(w.index_of(t1)), size_t(w.index_of(house))) == ENTER_DEMOLISH);
    CHECK(w.enter_kind_for(size_t(w.index_of(t1)), size_t(w.index_of(friend_house))) == ENTER_NONE);
    w.order_enter(&t1, 1, house, ENTER_NONE);
    int planted = 0;
    for (; planted < 900 && w.actor(size_t(w.index_of(house))).demolish_ticks < 0; ++planted) w.step();
    CHECK(w.actor(size_t(w.index_of(house))).demolish_ticks >= 0);
    int boom = 0;
    for (; boom < 200 && w.index_of(house) >= 0 && w.actor(size_t(w.index_of(house))).alive; ++boom) w.step();
    CHECK(w.index_of(house) < 0 || !w.actor(size_t(w.index_of(house))).alive);
    CHECK(boom <= 46);
    const int ti = w.index_of(t1);
    CHECK(ti >= 0 && w.actor(size_t(ti)).alive && !w.actor(size_t(ti)).inside);

    w.order_enter(&t1, 1, friend_house, ENTER_NONE);
    for (int t = 0; t < 400; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(friend_house))).demolish_ticks < 0);
    std::printf("C4 auf Zivilgebäude: neutraler Besitzer gesprengt (%d Ticks Anmarsch, %d Zünder), "
                "verbündetes Haus unangetastet\n", planted, boom);
}


static void test_bridge_demolition() {
    World w;

    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    for (int y = 0; y < 40; ++y)
        for (int x = 18; x <= 21; ++x) terrain[size_t(y * 40 + x)] = uint8_t(TER_WATER);
    for (int x = 18; x <= 21; ++x) terrain[size_t(10 * 40 + x)] = uint8_t(TER_BRIDGE);
    w.set_terrain(40, 40, terrain.data());
    w.set_neutral_player(3);
    w.set_non_combatant(3, true);

    UnitType br; br.building = true; br.foot_w = 4; br.foot_h = 1; br.footprint = {0, 0, 0, 0};
    br.sprite_h = 1; br.hp = 100000; br.demolishable = true;
    br.target_types = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_BRIDGE;
    UnitType tanya; tanya.speed = 68; tanya.turn_rate = 1024; tanya.infantry = true; tanya.hp = 10000;
    tanya.demolition_delay = 45; tanya.locomotor = LOCO_FOOT;
    UnitType e1; e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000; e1.locomotor = LOCO_FOOT;
    const int t_br = w.define_type(br), t_tanya = w.define_type(tanya), t_e1 = w.define_type(e1);

    const int32_t bridge = w.spawn_building(t_br, 3, {18, 10});
    const int32_t t1 = w.spawn(t_tanya, 0, {14, 10});
    const int32_t walker = w.spawn(t_e1, 0, {12, 12});

    w.order_move(&walker, 1, {26, 12}, 0);
    int steps = 0;
    for (; steps < 900 && w.mobile(size_t(w.index_of(walker))).cell.x < 24; ++steps) w.step();
    CHECK(w.mobile(size_t(w.index_of(walker))).cell.x >= 24);

    CHECK(w.enter_kind_for(size_t(w.index_of(t1)), size_t(w.index_of(bridge))) == ENTER_DEMOLISH);
    w.order_enter(&t1, 1, bridge, ENTER_NONE);
    int planted = 0;
    for (; planted < 900 && w.actor(size_t(w.index_of(bridge))).demolish_ticks < 0; ++planted) w.step();
    CHECK(w.actor(size_t(w.index_of(bridge))).demolish_ticks >= 0);

    const CPos tc = w.mobile(size_t(w.index_of(t1))).cell;
    CHECK(tc.x < 18 || tc.x > 21);
    for (int t = 0; t < 200 && w.index_of(bridge) >= 0 && w.actor(size_t(w.index_of(bridge))).alive; ++t) w.step();
    CHECK(w.index_of(bridge) < 0 || !w.actor(size_t(w.index_of(bridge))).alive);
    CHECK(w.actor(size_t(w.index_of(t1))).alive);


    const int32_t back = w.spawn(t_e1, 0, {19, 10});
    for (int x = 18; x <= 21; ++x) w.set_map_terrain(CPos{x, 10}, TER_WATER);
    CHECK(!w.map().passable(CPos{19, 10}));
    CHECK(w.index_of(back) < 0 || !w.actor(size_t(w.index_of(back))).alive);
    CHECK(w.fields().size() == 0);

    const CPos before = w.mobile(size_t(w.index_of(walker))).cell;
    w.order_move(&walker, 1, {12, 12}, 0);
    for (int t = 0; t < 600; ++t) w.step();
    const CPos after = w.mobile(size_t(w.index_of(walker))).cell;
    CHECK(after.x > 21);
    std::printf("Brücke gesprengt: Tanya legt bei (%d,%d) am Ufer, Abschnitt fällt, "
                "Wegfindung bleibt am Ostufer (%d,%d → %d,%d)\n",
                tc.x, tc.y, before.x, before.y, after.x, after.y);
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

    e1.locomotor = LOCO_FOOT; e1.weapon = wr;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY | TT_DISGUISE;
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


static void test_disguise_targets() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    Weapon ppk; ppk.range = 4 * CELL; ppk.reload = 20; ppk.damage = 500; ppk.spread = 128;
    ppk.valid_targets = TT_INFANTRY;
    const int wp = w.define_weapon(ppk);
    UnitType e1; e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000;
    e1.locomotor = LOCO_FOOT; e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY | TT_DISGUISE;
    UnitType tank; tank.speed = 78; tank.turn_rate = 20; tank.hp = 40000; tank.locomotor = LOCO_WHEELED;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType spy = e1; spy.disguise = true; spy.weapon = wp; spy.no_auto_target = true;
    const int te1 = w.define_type(e1), ttank = w.define_type(tank), tspy = w.define_type(spy);

    const int32_t foe = w.spawn(te1, 1, {20, 20});
    const int32_t veh = w.spawn(ttank, 1, {20, 24});
    const int32_t s = w.spawn(tspy, 0, {22, 20});

    CHECK(!w.order_disguise(s, veh));
    CHECK(w.actor(size_t(w.index_of(s))).disguise_type < 0);

    CHECK(w.order_disguise(s, foe));
    CHECK(w.actor(size_t(w.index_of(s))).disguise_type == te1);
    CHECK(w.actor(size_t(w.index_of(s))).disguise_owner == 1);

    const int32_t s2 = w.spawn(tspy, 0, {23, 20});
    CHECK(w.order_disguise(s2, s));
    CHECK(w.actor(size_t(w.index_of(s2))).disguise_type == te1);
    CHECK(w.actor(size_t(w.index_of(s2))).disguise_owner == 1);

    w.order_attack(&s, 1, foe);
    for (int t = 0; t < 200 && w.actor(size_t(w.index_of(s))).disguise_type >= 0; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(s))).disguise_type < 0);
    std::printf("Verkleidung: Panzer abgelehnt, Schütze angenommen, Vorbild weitergereicht, Angriff deckt auf\n");
}


static void test_infiltrate_support_power_reset() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    w.init_layers();
    UnitType mslo; mslo.building = true; mslo.foot_w = 2; mslo.foot_h = 2; mslo.footprint = {1, 1, 1, 1};
    mslo.sprite_h = 2; mslo.hp = 100000; mslo.target_types = TT_STRUCTURE | TT_SPY_INFILTRATE;

    mslo.support_power = SP_NUKE; mslo.sp_charge = 3000; mslo.sp_weapon = -1;
    mslo.infil_reset = TT_SPY_INFILTRATE;
    UnitType spy; spy.speed = 71; spy.turn_rate = 1024; spy.infantry = true; spy.hp = 2500;
    spy.locomotor = LOCO_FOOT; spy.cost = 500; spy.infiltrates = TT_SPY_INFILTRATE;
    spy.target_types = TT_GROUND_ACTOR | TT_INFANTRY | TT_DISGUISE;
    const int tm = w.define_type(mslo), tsp = w.define_type(spy);

    const int32_t silo = w.spawn_building(tm, 1, {20, 10});
    int av = 0, rd = 0, pm = 0, ps = 0;
    for (int t = 0; t < 900; ++t) w.step();
    w.support_power_state(1, SP_NUKE, av, rd, pm, ps);
    CHECK(av == 1 && rd == 0 && pm > 250);
    const int charged = pm;
    const int32_t spy1 = w.spawn(tsp, 0, {14, 10});
    w.order_capture(&spy1, 1, silo);
    for (int t = 0; t < 600 && w.index_of(spy1) >= 0 && w.actor(size_t(w.index_of(spy1))).alive; ++t) w.step();
    w.support_power_state(1, SP_NUKE, av, rd, pm, ps);
    CHECK(av == 1 && rd == 0);
    CHECK(pm < charged);
    std::printf("Infiltration: Superwaffen-Ladung von %d‰ auf %d‰ zurückgesetzt\n", charged, pm);
}


static void test_capture_notifications() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());


    w.set_conquest_victory(false);
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.sprite_h = 2; powr.hp = 40000; powr.capturable = true; powr.target_types = TT_STRUCTURE;
    UnitType jeep; jeep.speed = 100; jeep.turn_rate = 20; jeep.hp = 15000; jeep.locomotor = LOCO_WHEELED;
    jeep.capturable = true; jeep.capturable_types = CAP_VEHICLE; jeep.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    UnitType eng; eng.speed = 54; eng.turn_rate = 1024; eng.infantry = true; eng.hp = 2500;
    eng.captures = true; eng.capture_types = CAP_BUILDING | CAP_VEHICLE; eng.capture_delay = 20;
    eng.locomotor = LOCO_FOOT;
    const int tp = w.define_type(powr), tj = w.define_type(jeep), te = w.define_type(eng);

    std::vector<int32_t> notes;
    const int32_t foe = w.spawn_building(tp, 1, {20, 10});
    const int32_t e1 = w.spawn(te, 0, {14, 10});
    w.order_capture(&e1, 1, foe);
    for (int t = 0; t < 600 && w.actor(size_t(w.index_of(foe))).owner != 0; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(foe))).owner == 0);
    w.drain_notifications(0, notes);
    CHECK(std::find(notes.begin(), notes.end(), int32_t(NOTIFY_BUILDING_CAPTURED)) != notes.end());
    CHECK(std::find(notes.begin(), notes.end(), int32_t(NOTIFY_UNIT_STOLEN)) == notes.end());


    const int32_t car = w.spawn(tj, 1, {20, 24});
    const int32_t e2 = w.spawn(te, 0, {14, 24});
    const CPos far_away{34, 24};
    w.order_move(&car, 1, far_away);
    for (int t = 0; t < 60; ++t) w.step();
    CHECK(w.mobile(size_t(w.index_of(car))).cell.x > 20);
    w.order_capture(&e2, 1, car);
    for (int t = 0; t < 1200 && w.actor(size_t(w.index_of(car))).owner != 0; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(car))).owner == 0);
    w.drain_notifications(0, notes);
    CHECK(std::find(notes.begin(), notes.end(), int32_t(NOTIFY_UNIT_STOLEN)) != notes.end());
    std::vector<int32_t> lost;
    w.drain_notifications(1, lost);
    CHECK(std::find(lost.begin(), lost.end(), int32_t(NOTIFY_UNIT_LOST)) != lost.end());
    std::printf("Eroberung: BuildingCaptured beim Gebäude, UnitStolen/UnitLost beim Fahrzeug\n");
}


static void test_bridge_repair() {
    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());

    UnitType br; br.building = true; br.foot_w = 4; br.foot_h = 2;
    br.footprint = {0, 0, 0, 0, 0, 0, 0, 0};
    br.sprite_h = 2; br.hp = 100000; br.target_types = TT_GROUND_ACTOR | TT_BRIDGE;
    UnitType eng; eng.speed = 54; eng.turn_rate = 1024; eng.infantry = true; eng.hp = 2500;
    eng.repairs_bridges = true; eng.locomotor = LOCO_FOOT;
    const int tb = w.define_type(br), te = w.define_type(eng);

    const int32_t bid = w.spawn_building(tb, 2, {20, 10});
    w.set_health(bid, 30000);
    const int32_t e1 = w.spawn(te, 0, {14, 10});
    CHECK(w.enter_kind_for(size_t(w.index_of(e1)), size_t(w.index_of(bid))) == ENTER_REPAIR_BRIDGE);
    w.order_capture(&e1, 1, bid);
    for (int t = 0; t < 600 && w.actor(size_t(w.index_of(bid))).hp < 100000; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(bid))).hp == 100000);
    CHECK(w.index_of(e1) < 0 || !w.actor(size_t(w.index_of(e1))).alive);

    const int32_t e2 = w.spawn(te, 0, {14, 10});
    CHECK(w.enter_kind_for(size_t(w.index_of(e2)), size_t(w.index_of(bid))) == ENTER_NONE);
    std::printf("Brücke: Pionier repariert 30000 → 100000 HP und geht dabei auf\n");
}


static void test_spy_save_load() {
    World a;
    std::vector<uint8_t> cost(40 * 40, 1);
    a.set_map(40, 40, cost.data());
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.sprite_h = 2; powr.hp = 40000; powr.demolishable = true; powr.capturable = true;
    powr.target_types = TT_STRUCTURE | TT_SPY_INFILTRATE;
    powr.infil_power = TT_SPY_INFILTRATE; powr.infil_power_duration = 500;
    UnitType e1; e1.speed = 56; e1.turn_rate = 1024; e1.infantry = true; e1.hp = 5000;
    e1.locomotor = LOCO_FOOT; e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY | TT_DISGUISE;
    UnitType spy = e1; spy.disguise = true; spy.infiltrates = TT_SPY_INFILTRATE; spy.cost = 500;
    UnitType tanya = e1; tanya.demolition_delay = 400; tanya.hp = 10000;
    const int tp = a.define_type(powr), te1 = a.define_type(e1);
    const int tsp = a.define_type(spy), tt = a.define_type(tanya);

    const int32_t foe = a.spawn_building(tp, 1, {20, 10});
    const int32_t guard = a.spawn(te1, 1, {24, 14});
    const int32_t s = a.spawn(tsp, 0, {14, 10});
    const int32_t ty = a.spawn(tt, 0, {14, 12});
    CHECK(a.order_disguise(s, guard));
    a.order_capture(&ty, 1, foe);
    for (int t = 0; t < 600 && a.actor(size_t(a.index_of(foe))).demolish_ticks < 0; ++t) a.step();
    CHECK(a.actor(size_t(a.index_of(foe))).demolish_ticks > 0);
    const int32_t sid = a.spawn(tsp, 0, {14, 16});
    a.order_capture(&sid, 1, foe);
    for (int t = 0; t < 20; ++t) a.step();
    const int32_t saved_demo = a.actor(size_t(a.index_of(foe))).demolish_ticks;
    const int32_t saved_dt = a.actor(size_t(a.index_of(s))).disguise_type;
    const int32_t saved_do = a.actor(size_t(a.index_of(s))).disguise_owner;
    const int32_t saved_kind = a.actor(size_t(a.index_of(sid))).enter_kind;

    std::vector<uint8_t> blob;
    CHECK(a.save(blob));
    World b;
    b.set_map(40, 40, cost.data());
    b.define_type(powr); b.define_type(e1); b.define_type(spy); b.define_type(tanya);
    CHECK(b.load(blob));
    CHECK(b.actor(size_t(b.index_of(foe))).demolish_ticks == saved_demo);
    CHECK(b.actor(size_t(b.index_of(s))).disguise_type == saved_dt);
    CHECK(b.actor(size_t(b.index_of(s))).disguise_owner == saved_do);
    CHECK(b.actor(size_t(b.index_of(sid))).enter_kind == saved_kind);
    CHECK(b.actor(size_t(b.index_of(sid))).capture_target == foe);

    int ta = 0, tb2 = 0;
    for (; ta < 900 && a.actor(size_t(a.index_of(foe))).alive; ++ta) a.step();
    for (; tb2 < 900 && b.actor(size_t(b.index_of(foe))).alive; ++tb2) b.step();
    CHECK(ta == tb2);
    CHECK(state_hash(a) == state_hash(b));
    std::printf("Speichern/Laden: Verkleidung, C4-Zünder (%d Ticks) und Enter-Anmarsch erhalten, Hash gleich\n", saved_demo);
}


static constexpr int SEA_W = 40, SEA_H = 30, BEACH_X = 14;

struct NavalIds {
    int t_tank = -1, t_pt = -1, t_ss = -1, t_dd = -1, t_lst = -1, t_e1 = -1;
    int t_msub = -1, t_ca = -1, t_heli = -1;
    int t_yard = -1, t_fact = -1;
    int w_torp = -1, w_depth = -1, w_gun = -1, w_submissile = -1, w_aa = -1, w_8inch = -1;
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


    Weapon subm; subm.range = 20 * CELL; subm.reload = 300; subm.damage = 2500; subm.spread = 426;
    subm.burst = 2; subm.burst_delay = 5;
    for (int i = 0; i < NUM_ARMOR; ++i) subm.versus[i] = 100;
    subm.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_STRUCTURE | TT_SHIP;
    id.w_submissile = w.define_weapon(subm);

    Weapon aa; aa.range = 7 * CELL + 512; aa.reload = 60; aa.damage = 1650; aa.spread = 128;
    for (int i = 0; i < NUM_ARMOR; ++i) aa.versus[i] = 100;
    aa.valid_targets = TT_AIRBORNE;
    id.w_aa = w.define_weapon(aa);

    Weapon eight; eight.range = 20 * CELL; eight.min_range = 3 * CELL; eight.reload = 250;
    eight.damage = 2500; eight.spread = 213; eight.burst = 2; eight.burst_delay = 5;
    for (int i = 0; i < NUM_ARMOR; ++i) eight.versus[i] = 100;
    eight.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_STRUCTURE | TT_SHIP;
    id.w_8inch = w.define_weapon(eight);

    UnitType tank; tank.speed = 72; tank.turn_rate = 1024; tank.hp = 10000; tank.locomotor = LOCO_TRACKED;
    tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE; tank.weapon = id.w_gun; tank.repairable = true;
    id.t_tank = w.define_type(tank);
    UnitType e1; e1.speed = 42; e1.turn_rate = 1024; e1.hp = 5000; e1.infantry = true; e1.locomotor = LOCO_FOOT;
    e1.target_types = TT_GROUND_ACTOR | TT_INFANTRY; e1.passenger_weight = 1; e1.passenger_type = TT_INFANTRY;
    id.t_e1 = w.define_type(e1);


    UnitType pt; pt.speed = 142; pt.turn_rate = 28; pt.hp = 20000; pt.armor = ARMOR_HEAVY;
    pt.locomotor = LOCO_NAVAL; pt.weapon = id.w_gun; pt.weapon_secondary = id.w_depth;
    pt.target_types = TT_WATER_ACTOR | TT_SHIP; pt.turreted = true;
    pt.detect_range = 4 * CELL; pt.detect_types = DETECT_UNDERWATER; pt.repairable = true;
    pt.auto_target_mask = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_SHIP | TT_UNDERWATER;
    id.t_pt = w.define_type(pt);

    UnitType dd = pt; dd.speed = 92; dd.hp = 40000; dd.detect_range = 4 * CELL;
    dd.weapon_tertiary = id.w_aa;
    dd.auto_target_mask |= TT_AIRBORNE;
    id.t_dd = w.define_type(dd);


    UnitType ca; ca.speed = 44; ca.turn_rate = 12; ca.hp = 80000; ca.armor = ARMOR_HEAVY;
    ca.locomotor = LOCO_NAVAL; ca.turreted = true; ca.turret_turn = 12;
    ca.weapon = id.w_8inch; ca.weapon_secondary = id.w_8inch;
    ca.turret_count = 2;
    ca.turret_ox[0] = -896; ca.turret_oz[0] = 128;
    ca.turret_ox[1] = 768;  ca.turret_oz[1] = 128;
    ca.arm_turret[0] = 0; ca.arm_turret[1] = 1;
    ca.target_types = TT_WATER_ACTOR | TT_SHIP;
    ca.auto_target_mask = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_SHIP | TT_STRUCTURE;
    ca.repairable = true;
    id.t_ca = w.define_type(ca);


    UnitType msub; msub.speed = 44; msub.turn_rate = 12; msub.hp = 40000; msub.armor = ARMOR_LIGHT;
    msub.locomotor = LOCO_NAVAL; msub.weapon = id.w_submissile; msub.weapon_secondary = id.w_aa;
    msub.target_types = TT_WATER_ACTOR | TT_SHIP | TT_SUBMARINE;
    msub.target_types_underwater = TT_UNDERWATER | TT_SUBMARINE;
    msub.cloak = true; msub.cloak_initial_delay = 0; msub.cloak_delay = 100;
    msub.cloak_types = DETECT_UNDERWATER; msub.uncloak_on = UNCLOAK_ATTACK;
    msub.cloak_pause_critical = true;
    msub.detect_range = 4 * CELL; msub.detect_types = DETECT_UNDERWATER;
    msub.initial_stance = STANCE_HOLD_FIRE; msub.initial_stance_ai = STANCE_RETURN_FIRE;
    msub.auto_target_mask = TT_GROUND_ACTOR | TT_WATER_ACTOR | TT_STRUCTURE | TT_AIRBORNE;
    msub.repairable = true;
    id.t_msub = w.define_type(msub);

    UnitType heli; heli.aircraft = true; heli.can_hover = true; heli.vtol = true; heli.speed = 149;
    heli.turn_rate = 16; heli.hp = 12000; heli.armor = ARMOR_LIGHT;
    heli.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    heli.target_types_airborne = TT_AIRBORNE; heli.cruise_altitude = 1280;
    id.t_heli = w.define_type(heli);

    UnitType ss; ss.speed = 78; ss.turn_rate = 20; ss.hp = 25000; ss.armor = ARMOR_LIGHT;
    ss.locomotor = LOCO_NAVAL; ss.weapon = id.w_torp;
    ss.target_types = TT_WATER_ACTOR | TT_SHIP | TT_SUBMARINE;
    ss.target_types_underwater = TT_UNDERWATER | TT_SUBMARINE;
    ss.cloak = true; ss.cloak_initial_delay = 0; ss.cloak_delay = 50;
    ss.cloak_types = DETECT_UNDERWATER; ss.uncloak_on = UNCLOAK_ATTACK;

    ss.cloak_pause_critical = true;
    ss.auto_target_mask = TT_WATER_ACTOR | TT_UNDERWATER;
    ss.repairable = true;
    id.t_ss = w.define_type(ss);

    UnitType lst; lst.speed = 115; lst.turn_rate = 28; lst.hp = 40000; lst.armor = ARMOR_HEAVY;
    lst.locomotor = LOCO_LCRAFT; lst.cargo_max_weight = 5; lst.target_types = TT_WATER_ACTOR | TT_SHIP; lst.repairable = true;


    lst.ramp_terrain = (1u << TER_CLEAR) | (1u << TER_ROUGH) | (1u << TER_ROAD) | (1u << TER_ORE)
                     | (1u << TER_GEMS) | (1u << TER_BEACH);
    lst.ramp_ticks = 15;
    id.t_lst = w.define_type(lst);


    UnitType yard; yard.building = true; yard.foot_w = 3; yard.foot_h = 3;
    yard.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1}; yard.build_block = yard.footprint;
    yard.hp = 100000; yard.terrain_mask = 1u << TER_WATER; yard.adjacent = 8;
    yard.produces = 1u << QUEUE_SHIP; yard.exit_dx = 0; yard.exit_dy = 3; yard.rally_dx = 0; yard.rally_dy = 4;
    yard.gives_buildable_area = false; yard.repairs_units = true; yard.cost = 1000;
    yard.requires_base_provider = true;
    yard.queue_kind = QUEUE_BUILDING; yard.sellable = true;
    yard.target_types = TT_WATER_ACTOR | TT_STRUCTURE;
    id.t_yard = w.define_type(yard);

    UnitType fact; fact.building = true; fact.foot_w = 3; fact.foot_h = 3;
    fact.footprint = {1, 1, 1, 1, 1, 1, 1, 1, 1}; fact.build_block = fact.footprint;
    fact.hp = 100000; fact.base_provider = true; fact.base_range = 20 * CELL;
    fact.produces = 1u << QUEUE_BUILDING;
    fact.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
    id.t_fact = w.define_type(fact);


    const int32_t yard_only[] = {id.t_yard};
    for (int t : {id.t_pt, id.t_dd, id.t_ca, id.t_ss, id.t_msub, id.t_lst})
        w.set_repair_actors(t, yard_only, 1);
    const int32_t fix_only[] = {id.t_fact};
    w.set_repair_actors(id.t_tank, fix_only, 1);
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


static void test_cloak_timing() {
    World w;
    const NavalIds id = build_naval(w);
    w.set_alliance(0, 1, false);
    const int32_t sub = w.spawn(id.t_ss, 1, {30, 15});
    const size_t si = size_t(w.index_of(sub));
    w.step();
    CHECK(w.cloaked(si));


    w.uncloak(si, UNCLOAK_ATTACK);
    CHECK(!w.cloaked(si));
    int ticks = 0;
    for (; ticks < 200 && !w.cloaked(si); ++ticks) w.step();
    CHECK(ticks == 50);


    const int32_t ms = w.spawn(id.t_msub, 1, {32, 20});
    const size_t mi = size_t(w.index_of(ms));
    w.step();
    CHECK(w.cloaked(mi));
    w.uncloak(mi, UNCLOAK_ATTACK);
    int ticks2 = 0;
    for (; ticks2 < 300 && !w.cloaked(mi); ++ticks2) w.step();
    CHECK(ticks2 == 100);


    w.set_health(sub, 100);
    CHECK(w.cloak_paused(si));
    for (int t = 0; t < 120; ++t) w.step();
    CHECK(!w.cloaked(si));

    w.set_health(sub, 25000);
    w.step();
    CHECK(w.cloaked(si));
    std::printf("Tarnung: ss %d Ticks, msub %d Ticks bis zum Abtauchen; kritisch = bleibt oben\n",
                ticks, ticks2);
}


static void test_missile_sub() {
    World w;
    const NavalIds id = build_naval(w);
    w.set_alliance(0, 1, false);

    const int32_t target = w.spawn_building(id.t_fact, 1, {10, 15});
    const size_t tgt = size_t(w.index_of(target));
    const int32_t ms = w.spawn(id.t_msub, 0, {20, 15});
    const size_t mi = size_t(w.index_of(ms));
    for (int t = 0; t < 60; ++t) w.step();

    CHECK(w.actor(tgt).hp == 100000);
    CHECK(w.cloaked(mi));

    w.order_attack(&ms, 1, target);
    int fired = -1;
    bool surfaced = false;
    for (int t = 0; t < 900; ++t) {
        w.step();
        if (fired < 0 && w.actor(tgt).hp < 100000) fired = t;
        if (!w.cloaked(mi)) surfaced = true;
    }
    CHECK(fired >= 0);
    CHECK(surfaced);
    CHECK(w.actor(mi).alive);
    std::printf("Raketen-U-Boot: Gebäude ab Tick %d unter Beschuss (%d HP), U-Boot aufgetaucht\n",
                fired, w.actor(tgt).hp);
}


static void test_destroyer_aa() {
    World w;
    const NavalIds id = build_naval(w);
    w.set_alliance(0, 1, false);
    const int32_t dd = w.spawn(id.t_dd, 0, {25, 15});
    const int32_t heli = w.spawn(id.t_heli, 1, {28, 15}, 0, 100, true);
    const size_t hi = size_t(w.index_of(heli));
    w.set_stance(dd, STANCE_ATTACK_ANYTHING);
    for (int t = 0; t < 400 && w.actor(hi).alive && w.actor(hi).hp == 12000; ++t) w.step();
    CHECK(w.actor(hi).hp < 12000);
    std::printf("Zerstörer: Flugabwehr trifft (Hubschrauber %d HP)\n",
                w.actor(hi).alive ? w.actor(hi).hp : 0);
}


static void test_cruiser_twin_turrets() {
    World w;
    const NavalIds id = build_naval(w);
    w.set_alliance(0, 1, false);
    const int32_t target = w.spawn_building(id.t_fact, 1, {10, 15});
    const size_t tgt = size_t(w.index_of(target));
    const int32_t ca = w.spawn(id.t_ca, 0, {22, 15});
    const size_t ci = size_t(w.index_of(ca));
    w.order_attack(&ca, 1, target);
    for (int t = 0; t < 400; ++t) w.step();

    CHECK(w.actor(tgt).hp < 100000);
    CHECK(w.combat(ci).reload > 0 && w.combat(ci).reload2 > 0);

    CHECK(abs_angle_diff(w.combat(ci).turret, w.combat(ci).turret2) <= 32);
    std::printf("Kreuzer: beide Türme feuern (Nachladen %d/%d), Ziel %d HP\n",
                w.combat(ci).reload, w.combat(ci).reload2, w.actor(tgt).hp);


    World w2;
    const NavalIds id2 = build_naval(w2);
    w2.set_alliance(0, 1, false);
    const int32_t near_ship = w2.spawn(id2.t_pt, 1, {23, 15});
    const size_t ni = size_t(w2.index_of(near_ship));
    const int32_t ca2 = w2.spawn(id2.t_ca, 0, {22, 15});
    w2.order_attack(&ca2, 1, near_ship);
    for (int t = 0; t < 300; ++t) w2.step();
    CHECK(w2.actor(ni).hp == 20000);
    std::printf("Kreuzer: Ziel innerhalb MinRange bleibt unbeschossen (%d HP)\n", w2.actor(ni).hp);
}


static void test_ship_repair() {
    World w;
    const NavalIds id = build_naval(w);
    w.spawn_building(id.t_fact, 0, {10, 10});
    const int32_t yard = w.spawn_building(id.t_yard, 0, {16, 10});
    CHECK(yard > 0);
    w.give_credits(0, 10000);
    const int32_t boat = w.spawn(id.t_pt, 0, {25, 12});
    const size_t bi = size_t(w.index_of(boat));
    w.set_health(boat, 8000);
    const int32_t hurt = w.actor(bi).hp;
    CHECK(hurt < 20000);
    w.order_repair(&boat, 1, yard);
    for (int t = 0; t < 1200 && w.actor(bi).hp < 20000; ++t) w.step();
    CHECK(w.actor(bi).hp == 20000);
    CHECK(w.credits(0) < 10000);
    std::printf("Werft: Kanonenboot von %d auf %d HP repariert (Rest %lld Credits)\n",
                hurt, w.actor(bi).hp, static_cast<long long>(w.credits(0)));


    const int32_t tank = w.spawn(id.t_tank, 0, {12, 12});
    const size_t ti = size_t(w.index_of(tank));
    w.set_health(tank, 5000);
    w.order_repair(&tank, 1, yard);
    CHECK(w.actor(ti).repair_depot < 0);
    std::printf("Werft: Panzer abgewiesen (repair_depot %d)\n", w.actor(ti).repair_depot);
}


static void test_naval_deadlock() {
    World w;
    const NavalIds id = build_naval(w);
    std::vector<int32_t> east, west;
    for (int k = 0; k < 4; ++k) {
        east.push_back(w.spawn(id.t_pt, 0, {17, 10 + k}));
        west.push_back(w.spawn(id.t_pt, 0, {36, 10 + k}));
    }
    for (int32_t a : east) w.order_move(&a, 1, {36, 20});
    for (int32_t a : west) w.order_move(&a, 1, {17, 20});
    for (int t = 0; t < 3000; ++t) w.step();
    int arrived = 0, moving = 0;
    for (int32_t a : east) {
        const size_t i = size_t(w.index_of(a));
        if (w.mobile(i).moving || w.mobile(i).in_transit) ++moving;
        if (w.mobile(i).cell.x >= 30) ++arrived;
    }
    for (int32_t a : west) {
        const size_t i = size_t(w.index_of(a));
        if (w.mobile(i).moving || w.mobile(i).in_transit) ++moving;
        if (w.mobile(i).cell.x <= 23) ++arrived;
    }
    CHECK(moving == 0);
    CHECK(arrived >= 7);
    std::printf("Wasser-Wegfindung: %d von 8 Schiffen am Ziel, %d noch unterwegs\n", arrived, moving);
}


static void test_naval_bridge() {
    World w;
    const NavalIds id = build_naval(w);

    for (int y = 0; y < SEA_H; ++y) w.set_map_terrain({25, y}, TER_BRIDGE);
    CHECK(!w.map().passable({25, 15}, MC_NAVAL));
    const int32_t boat = w.spawn(id.t_pt, 0, {20, 15});
    const size_t bi = size_t(w.index_of(boat));
    w.order_move(&boat, 1, {35, 15});
    for (int t = 0; t < 800; ++t) w.step();
    CHECK(w.mobile(bi).cell.x < 25);
    const int blocked_x = w.mobile(bi).cell.x;


    for (int y = 13; y < 18; ++y) w.set_map_terrain({25, y}, TER_WATER);
    CHECK(w.map().passable({25, 15}, MC_NAVAL));
    w.order_move(&boat, 1, {35, 15});
    for (int t = 0; t < 1200; ++t) w.step();
    CHECK(w.mobile(bi).cell.x > 25);
    std::printf("Bruecke: Schiff blieb bei x=%d stehen, nach der Zerstoerung bei x=%d\n",
                blocked_x, w.mobile(bi).cell.x);
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


    CHECK(!w.can_unload(lst));
    w.order_unload(&lst, 1);
    CHECK(!w.actor(li).unloading);
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.cargo_weight(lst) == 3);
    std::printf("Landungsboot: Entladebefehl auf offener See abgewiesen, weiter %d/3 an Bord\n", w.cargo_weight(lst));


    w.order_move(&lst, 1, {BEACH_X, 10});
    for (int t = 0; t < 600; ++t) w.step();
    CHECK(w.can_unload(lst));
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


static void test_lst_ramp() {
    World w;
    const NavalIds id = build_naval(w);
    const int32_t lst = w.spawn(id.t_lst, 0, {30, 10});
    const size_t li = size_t(w.index_of(lst));
    const int32_t ramp_ticks = 15;


    for (int t = 0; t < 40; ++t) w.step();
    CHECK(w.map().terrain(w.mobile(li).cell) == TER_WATER);
    CHECK(w.ramp_state(lst) == RAMP_CLOSED);


    w.order_move(&lst, 1, {BEACH_X, 10});
    for (int t = 0; t < 5; ++t) w.step();
    CHECK(w.ramp_state(lst) == RAMP_CLOSED);
    int moving_open = 0;
    for (int t = 0; t < 600 && (w.mobile(li).moving || w.mobile(li).in_transit); ++t) {
        w.step();
        if ((w.mobile(li).moving || w.mobile(li).in_transit) && w.ramp_state(lst) != RAMP_CLOSED) ++moving_open;
    }
    CHECK(moving_open == 0);
    CHECK(!w.mobile(li).moving && !w.mobile(li).in_transit);


    CHECK(w.ramp_state(lst) == RAMP_OPENING);
    CHECK(w.actor(li).ramp_frame == 0);
    int opening = 0;
    while (w.ramp_state(lst) == RAMP_OPENING && opening < 100) { w.step(); ++opening; }
    CHECK(opening == ramp_ticks);
    CHECK(w.ramp_state(lst) == RAMP_OPEN);
    std::printf("Landungsboot: Rampe nach %d Ticks offen (Zelle %d,%d)\n",
                opening, w.mobile(li).cell.x, w.mobile(li).cell.y);


    std::vector<int32_t> troop;
    for (int i = 0; i < 3; ++i) troop.push_back(w.spawn(id.t_e1, 0, {BEACH_X - 2, 9 + i}));
    for (const int32_t p : troop) CHECK(w.load_passenger(lst, p));
    CHECK(w.can_unload(lst));
    w.order_unload(&lst, 1);
    int unload_closed = 0;
    for (int t = 0; t < 300; ++t) {
        w.step();
        if (w.actor(li).unloading && w.ramp_state(lst) != RAMP_OPEN) ++unload_closed;
    }
    CHECK(unload_closed == 0);
    CHECK(w.cargo_weight(lst) == 0);
    CHECK(w.ramp_state(lst) == RAMP_OPEN);
    std::printf("Landungsboot: Rampe während des Entladens durchgehend offen, %d Passagiere abgesetzt\n",
                int(troop.size()));


    w.order_move(&lst, 1, {SEA_W - 3, 10});
    w.step();
    CHECK(w.ramp_state(lst) == RAMP_CLOSING);


    for (int t = 0; t < 5; ++t) w.step();
    CHECK(w.ramp_state(lst) == RAMP_CLOSING);
    const int32_t frame_before = w.actor(li).ramp_frame;
    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    World reloaded;
    build_naval(reloaded);
    CHECK(reloaded.load(blob));
    CHECK(reloaded.ramp_state(lst) == RAMP_CLOSING);
    CHECK(reloaded.actor(size_t(reloaded.index_of(lst))).ramp_frame == frame_before);


    int closing = frame_before;
    while (w.ramp_state(lst) == RAMP_CLOSING && closing < 100) { w.step(); ++closing; }
    CHECK(closing == ramp_ticks);
    CHECK(w.ramp_state(lst) == RAMP_CLOSED);
    for (int t = 0; t < 300; ++t) w.step();
    CHECK(w.ramp_state(lst) == RAMP_CLOSED);
    std::printf("Landungsboot: Rampe beim Ablegen wieder zu (idle→open→unload→close vollständig)\n");


    const int32_t pt = w.spawn(id.t_pt, 0, {BEACH_X + 1, 20});
    for (int t = 0; t < 60; ++t) w.step();
    CHECK(w.ramp_state(pt) == RAMP_CLOSED);
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


static void build_frozen_world(World& w, int& t_hq, int& t_scout) {
    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    w.set_terrain(40, 40, terrain.data());
    UnitType hq; hq.building = true; hq.foot_w = 2; hq.foot_h = 2; hq.footprint = {1, 1, 1, 1};
    hq.hp = 40000;
    UnitType scout; scout.speed = 0; scout.infantry = true; scout.hp = 2500; scout.locomotor = LOCO_FOOT;
    scout.reveal_range = 6 * CELL; scout.reveal_gap_range = 6 * CELL;
    t_hq = w.define_type(hq);
    t_scout = w.define_type(scout);
}

static void test_frozen_actors() {
    World w;
    int t_hq = 0, t_scout = 0;
    build_frozen_world(w, t_hq, t_scout);

    const int32_t bld = w.spawn_building(t_hq, 1, {20, 20});
    const size_t bi = size_t(w.index_of(bld));

    const int32_t far = w.spawn_building(t_hq, 1, {34, 34});
    const size_t fi = size_t(w.index_of(far));

    w.update_visibility(0);
    CHECK(w.frozen(0).empty());
    CHECK(!w.actor_visible_to(0, bi));


    const int32_t sc = w.spawn(t_scout, 0, {20, 24});
    w.update_visibility(0);
    CHECK(w.actor_visible_to(0, bi));
    CHECK(w.frozen(0).empty());


    w.destroy(sc);
    w.update_visibility(0);
    CHECK(w.frozen(0).size() == 1);
    CHECK(w.frozen(0)[0].id == bld);
    CHECK(w.frozen(0)[0].owner == 1);
    CHECK(w.frozen(0)[0].hp_permille == 1000);
    CHECK(w.frozen_has(0, bld));
    CHECK(!w.frozen_has(0, far));


    w.set_health(bld, 10000);
    w.update_visibility(0);
    CHECK(w.frozen(0)[0].hp_permille == 1000);


    w.destroy(bld);
    w.update_visibility(0);
    CHECK(w.frozen(0).size() == 1);
    std::vector<RenderActor> buf(w.actor_count());
    w.render(0, buf.data());
    CHECK(buf[bi].alive == 0);
    w.apply_frozen(0, buf.data(), buf.size());
    CHECK(buf[bi].alive == 1 && buf[bi].visible == 1);
    CHECK(buf[bi].hp_permille == 1000 && buf[bi].owner == 1);


    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    World r;
    int r_hq = 0, r_scout = 0;
    build_frozen_world(r, r_hq, r_scout);
    CHECK(r.load(blob));
    CHECK(r.frozen(0).size() == 1 && r.frozen(0)[0].id == bld);
    CHECK(r.frozen(0)[0].hp_permille == 1000);


    w.spawn(t_scout, 0, {20, 24});
    w.update_visibility(0);
    CHECK(w.frozen(0).empty());
    std::vector<RenderActor> buf2(w.actor_count());
    w.render(0, buf2.data());
    w.apply_frozen(0, buf2.data(), buf2.size());
    CHECK(buf2[bi].alive == 0);
    CHECK(!w.actor_visible_to(0, fi));
    std::printf("FrozenUnderFog: Momentaufnahme beim Nebelschluss, Zerstoerung bleibt bis zum Sichtkontakt stehen\n");
}


static void test_fog_disabled() {
    World w;
    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    w.set_terrain(40, 40, terrain.data());
    UnitType scout; scout.speed = 0; scout.infantry = true; scout.hp = 2500; scout.locomotor = LOCO_FOOT;
    scout.reveal_range = 4 * CELL; scout.reveal_gap_range = 4 * CELL;
    UnitType foe; foe.speed = 0; foe.infantry = true; foe.hp = 2500; foe.locomotor = LOCO_FOOT;
    UnitType hq; hq.building = true; hq.foot_w = 2; hq.foot_h = 2; hq.footprint = {1, 1, 1, 1}; hq.hp = 40000;
    const int t_scout = w.define_type(scout);
    const int t_foe = w.define_type(foe);
    const int t_hq = w.define_type(hq);

    const int32_t sc = w.spawn(t_scout, 0, {20, 20});
    const size_t near_i = size_t(w.index_of(w.spawn(t_foe, 1, {20, 22})));
    const size_t far_i = size_t(w.index_of(w.spawn(t_foe, 1, {20, 34})));
    const size_t bld_i = size_t(w.index_of(w.spawn_building(t_hq, 1, {30, 20})));

    CHECK(w.fog_enabled());
    w.update_visibility(0);
    CHECK(w.actor_visible_to(0, near_i));
    CHECK(!w.actor_visible_to(0, far_i));


    w.destroy(sc);
    w.update_visibility(0);
    CHECK(!w.actor_visible_to(0, near_i));
    CHECK(w.visibility(0)[size_t(22 * 40 + 20)] == 1);


    w.set_fog_enabled(false);
    CHECK(w.visibility(0)[size_t(22 * 40 + 20)] == 2);
    CHECK(w.actor_visible_to(0, near_i));
    CHECK(!w.actor_visible_to(0, far_i));
    CHECK(w.visibility(0)[size_t(34 * 40 + 20)] == 0);


    CHECK(!w.actor_visible_to(0, bld_i));
    w.reveal(0, {30, 20}, 3);
    CHECK(w.actor_visible_to(0, bld_i));


    w.set_fog_enabled(true);
    w.update_visibility(0);
    CHECK(!w.actor_visible_to(0, near_i));
    std::printf("Nebel aus: erkundete Zellen loesen als sichtbar auf, der Shroud bleibt\n");
}


static void test_gps_dots() {
    World w;
    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    w.set_terrain(40, 40, terrain.data());

    UnitType atek; atek.building = true; atek.foot_w = 2; atek.foot_h = 2;
    atek.footprint = {1, 1, 1, 1}; atek.hp = 60000;
    atek.support_power = SP_GPS; atek.sp_charge = 20; atek.sp_reveal_delay = 5; atek.sp_one_shot = true;
    UnitType dome; dome.building = true; dome.foot_w = 2; dome.foot_h = 2;
    dome.footprint = {1, 1, 1, 1}; dome.hp = 40000; dome.provides_radar = true;
    UnitType hq; hq.building = true; hq.foot_w = 2; hq.foot_h = 2; hq.footprint = {1, 1, 1, 1};
    hq.hp = 40000; hq.gps_dot = true;
    UnitType tank; tank.speed = 60; tank.hp = 40000; tank.locomotor = LOCO_TRACKED;
    tank.gps_dot = true;
    UnitType gap; gap.building = true; gap.foot_w = 1; gap.foot_h = 1; gap.footprint = {1};
    gap.hp = 50000; gap.creates_shroud_range = 6 * CELL; gap.gps_dot = true;
    const int t_atek = w.define_type(atek), t_dome = w.define_type(dome);
    const int t_hq = w.define_type(hq), t_tank = w.define_type(tank), t_gap = w.define_type(gap);

    w.spawn_building(t_atek, 0, {4, 4});
    const int32_t radar = w.spawn_building(t_dome, 0, {8, 4});
    w.spawn_building(t_hq, 1, {28, 28});
    w.spawn(t_tank, 1, {24, 24});
    w.spawn_building(t_gap, 1, {34, 10});
    w.spawn(t_tank, 1, {34, 12});

    std::vector<World::GpsDotInfo> dots;
    w.gps_dots(0, dots);
    CHECK(dots.empty() && !w.gps_granted(0));

    for (int t = 0; t < 30; ++t) w.step();
    CHECK(w.gps_launched(0));
    CHECK(w.gps_granted(0));
    w.gps_dots(0, dots);


    CHECK(dots.size() == 2);
    int buildings = 0, units = 0;
    for (const World::GpsDotInfo& d : dots) {
        CHECK(d.owner == 1);
        if (d.building) ++buildings; else ++units;
    }
    CHECK(buildings == 1 && units == 1);


    w.destroy(radar);
    w.step();
    CHECK(!w.gps_granted(0));
    w.gps_dots(0, dots);
    CHECK(dots.empty());
    std::printf("GpsDot: %d Gebaeude und %d Einheiten im Nebel, Tarnflaeche punktfrei, ohne Radar keine Punkte\n",
                buildings, units);
}


static void test_husks() {
    World w;
    std::vector<uint8_t> terrain(32 * 32, uint8_t(TER_CLEAR));
    w.set_terrain(32, 32, terrain.data());

    UnitType husk;
    husk.speed = 0; husk.hp = 28000; husk.armor = ARMOR_HEAVY; husk.locomotor = LOCO_TRACKED;
    husk.husk = true;
    husk.husk_terrain = (1u << TER_CLEAR) | (1u << TER_ROUGH) | (1u << TER_ROAD);
    husk.crushes = (1u << 0);
    husk.target_types = TT_GROUND_ACTOR | TT_HUSK | TT_NO_AUTO_TARGET;

    husk.heal_step = -200; husk.heal_delay = 8; husk.heal_start_below = 101;
    const int t_husk = w.define_type(husk);

    UnitType tank;
    tank.speed = 0; tank.turn_rate = 1024; tank.hp = 4000; tank.armor = ARMOR_HEAVY;
    tank.hit_radius = 400; tank.locomotor = LOCO_TRACKED; tank.crushes = (1u << 0);
    tank.husk_actor = t_husk;
    const int t_tank = w.define_type(tank);

    UnitType rifle;
    rifle.speed = 0; rifle.hp = 500; rifle.infantry = true; rifle.locomotor = LOCO_FOOT;
    rifle.hit_radius = 128; rifle.crush_classes = (1u << 0);
    const int t_rifle = w.define_type(rifle);

    const int32_t tank_id = w.spawn(t_tank, 0, {10, 10}, 384);
    CHECK(w.alive_count(0) == 1);
    w.destroy(tank_id);
    CHECK(w.index_of(tank_id) >= 0 && !w.actor(size_t(w.index_of(tank_id))).alive);
    w.step();

    int hi = -1;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).alive && w.actor(i).type == t_husk) hi = int(i);
    CHECK(hi >= 0);
    CHECK(w.actor(size_t(hi)).facing == 384);
    CHECK(w.actor(size_t(hi)).owner == 0);
    CHECK((w.mobile(size_t(hi)).cell == CPos{10, 10}));
    CHECK(w.actor(size_t(hi)).hp == 28000);
    CHECK(w.occupant({10, 10}) == hi);
    CHECK(!w.cell_empty({10, 10}));


    for (int t = 0; t < 1100; ++t) w.step();
    const int32_t hp_left = w.actor(size_t(hi)).hp;
    CHECK(hp_left > 0 && hp_left < 28000);
    std::printf("Wrack: nach 1100 Ticks noch %d von 28000 HP (Step -200, Delay 8)\n", hp_left);
    for (int t = 0; t < 60; ++t) w.step();
    CHECK(!w.actor(size_t(hi)).alive);
    CHECK(w.cell_empty({10, 10}));


    const int32_t tank2 = w.spawn(t_tank, 0, {14, 14}, 128);
    w.destroy(tank2);
    const int32_t man = w.spawn(t_rifle, 0, {14, 14});
    CHECK(man >= 0);
    CHECK((w.mobile(size_t(w.index_of(man))).cell == CPos{14, 14}));
    w.step();
    CHECK(w.index_of(man) >= 0 && !w.actor(size_t(w.index_of(man))).alive);
    int hi2 = -1;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).alive && w.actor(i).type == t_husk) hi2 = int(i);
    CHECK((hi2 >= 0 && w.mobile(size_t(hi2)).cell == CPos{14, 14}));
    std::printf("Wrack: Infanterie in der Zelle zerquetscht, Wrack steht\n");


    for (int t = 0; t < 100; ++t) w.step();
    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    World w2;
    w2.set_terrain(32, 32, terrain.data());
    w2.define_type(husk);
    w2.define_type(tank);
    w2.define_type(rifle);
    CHECK(w2.load(blob));
    CHECK(w2.actor(size_t(hi2)).hp == w.actor(size_t(hi2)).hp);
    CHECK(w2.actor(size_t(hi2)).self_heal_ticks == w.actor(size_t(hi2)).self_heal_ticks);
    for (int t = 0; t < 300; ++t) { w.step(); w2.step(); }
    CHECK(w2.actor(size_t(hi2)).hp == w.actor(size_t(hi2)).hp);
    CHECK(w2.actor(size_t(hi2)).alive == w.actor(size_t(hi2)).alive);
}


static void test_smudges() {
    std::vector<uint8_t> terrain(32 * 32, uint8_t(TER_CLEAR));
    for (int y = 0; y < 32; ++y) terrain[size_t(y) * 32 + 20] = uint8_t(TER_WATER);

    auto build = [&](World& w) {
        w.set_terrain(32, 32, terrain.data());
        w.set_smudge_sprites(SMUDGE_SCORCH, 6, 5);
        w.set_smudge_sprites(SMUDGE_CRATER, 6, 5);
    };
    World w;
    build(w);


    Weapon crater;
    crater.damage = 0; crater.spread = 128;
    crater.smudge_type = SMUDGE_CRATER; crater.smudge_size = 1;
    const int w_crater = w.define_weapon(crater);
    Weapon scorch;
    scorch.damage = 0; scorch.spread = 128;
    scorch.smudge_type = SMUDGE_SCORCH; scorch.smudge_size = 0;
    const int w_scorch = w.define_weapon(scorch);
    UnitType dummy;
    dummy.speed = 0; dummy.hp = 100;
    w.define_type(dummy);

    CHECK(w.smudge_count() == 0);
    const uint32_t v0 = w.smudge_version();
    w.impact_for_test(cell_center({10, 10}), w_crater);

    CHECK(w.smudge_count() == 5);
    CHECK(w.smudge_kind({10, 10}) == SMUDGE_CRATER);
    CHECK(w.smudge_kind({9, 10}) == SMUDGE_CRATER);
    CHECK(w.smudge_kind({9, 9}) == SMUDGE_NONE);
    CHECK(w.smudge_depth({10, 10}) == 0);
    CHECK(w.smudge_version() > v0);


    w.impact_for_test(cell_center({10, 10}), w_scorch);
    CHECK(w.smudge_kind({10, 10}) == SMUDGE_CRATER);
    CHECK(w.smudge_depth({10, 10}) == 1);
    for (int i = 0; i < 10; ++i) w.impact_for_test(cell_center({10, 10}), w_scorch);
    CHECK(w.smudge_depth({10, 10}) == 4);


    w.impact_for_test(cell_center({20, 5}), w_scorch);
    CHECK(w.smudge_kind({20, 5}) == SMUDGE_NONE);


    World w3;
    build(w3);
    w3.define_weapon(crater);
    w3.define_weapon(scorch);
    w3.define_type(dummy);
    w3.impact_for_test(cell_center({10, 10}), w_crater);
    CHECK(w3.smudge_variant({10, 10}) == w.smudge_variant({10, 10}));
    CHECK(w3.smudge_variant({9, 10}) == w.smudge_variant({9, 10}));


    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    World w2;
    build(w2);
    w2.define_weapon(crater);
    w2.define_weapon(scorch);
    w2.define_type(dummy);
    CHECK(w2.load(blob));
    CHECK(w2.smudge_count() == w.smudge_count());
    CHECK(w2.smudge_kind({10, 10}) == SMUDGE_CRATER);
    CHECK(w2.smudge_depth({10, 10}) == 4);
    CHECK(w2.smudge_variant({10, 10}) == w.smudge_variant({10, 10}));
    std::vector<SmudgeInfo> a, b;
    w.smudges(a);
    w2.smudges(b);
    CHECK(a.size() == b.size());
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) {
        CHECK(a[i].cell == b[i].cell && a[i].kind == b[i].kind);
        CHECK(a[i].variant == b[i].variant && a[i].depth == b[i].depth);
    }
    std::printf("Brandflecken: %u Zellen, Krater Tiefe %d, Wasser bleibt frei, Save/Load gleich\n",
                w.smudge_count(), w.smudge_depth({10, 10}));
}


static void test_gap_generator() {
    World w;
    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    w.set_terrain(40, 40, terrain.data());
    const auto cell = [](int x, int y) { return size_t(y * 40 + x); };

    UnitType gap; gap.building = true; gap.foot_w = 1; gap.foot_h = 1; gap.footprint = {1};
    gap.hp = 50000; gap.power = -60; gap.needs_power = true;
    gap.reveal_range = 6 * CELL; gap.reveal_gap_range = 5 * CELL;
    gap.creates_shroud_range = 6 * CELL;
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.hp = 40000; powr.power = 100;

    UnitType scout; scout.speed = 0; scout.infantry = true; scout.hp = 2500; scout.locomotor = LOCO_FOOT;
    scout.reveal_range = 6 * CELL; scout.reveal_gap_range = 0;
    UnitType spotter = scout; spotter.reveal_gap_range = 6 * CELL;
    UnitType soldier; soldier.speed = 0; soldier.infantry = true; soldier.hp = 2500; soldier.locomotor = LOCO_FOOT;
    const int t_gap = w.define_type(gap), t_powr = w.define_type(powr);
    const int t_scout = w.define_type(scout), t_spot = w.define_type(spotter), t_sol = w.define_type(soldier);

    w.spawn_building(t_powr, 0, {2, 2});
    w.spawn_building(t_gap, 0, {20, 20});
    const int32_t sol = w.spawn(t_sol, 0, {22, 20});
    w.step();


    w.explore_all(1);
    CHECK(w.explored(1, CPos{20, 20}));
    CHECK(w.visibility(1)[cell(20, 20)] == 0);
    CHECK(w.visibility(1)[cell(24, 20)] == 0);
    CHECK(w.visibility(1)[cell(30, 20)] == 1);

    w.update_visibility(0);
    CHECK(w.visibility(0)[cell(20, 20)] == 2);
    CHECK(w.visibility(0)[cell(22, 20)] == 2);


    const int32_t sc = w.spawn(t_scout, 1, {23, 20});
    w.update_visibility(1);
    CHECK(w.visibility(1)[cell(22, 20)] == 0);
    CHECK(!w.actor_visible_to(1, size_t(w.index_of(sol))));

    w.destroy(sc);
    w.spawn(t_spot, 1, {23, 20});
    w.update_visibility(1);
    CHECK(w.visibility(1)[cell(22, 20)] == 2);
    CHECK(w.actor_visible_to(1, size_t(w.index_of(sol))));
    std::printf("Tarngenerator: Flaeche beim Gegner schwarz trotz Erkundung, Sicht mit RevealGeneratedShroud sticht sie\n");
}


static void test_low_power_notification() {
    const auto has_low = [](World& w) {
        std::vector<int32_t> notes;
        w.drain_notifications(0, notes);
        return std::find(notes.begin(), notes.end(), int32_t(NOTIFY_LOW_POWER)) != notes.end();
    };
    World w;
    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    w.set_terrain(40, 40, terrain.data());
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.hp = 40000; powr.power = 100;
    UnitType dome; dome.building = true; dome.foot_w = 2; dome.foot_h = 2; dome.footprint = {1, 1, 1, 1};
    dome.hp = 40000; dome.power = -60;
    const int t_powr = w.define_type(powr), t_dome = w.define_type(dome);
    const int32_t pid = w.spawn_building(t_powr, 0, {2, 2});
    w.spawn_building(t_dome, 0, {6, 2});
    w.step();
    CHECK(!has_low(w));
    const int32_t d2 = w.spawn_building(t_dome, 0, {10, 2});
    w.step();
    CHECK(has_low(w));
    w.step();
    CHECK(!has_low(w));

    w.destroy(d2);
    w.step();
    CHECK(!has_low(w));

    w.spawn_building(t_dome, 0, {14, 2});
    w.step();
    CHECK(has_low(w));

    for (int t = 0; t < 10 * TICKS_PER_SECOND + 1; ++t) w.step();
    CHECK(has_low(w));
    (void)pid;
    std::printf("Strommangel: Ansage sofort beim Kippen, Wiederholung nach 10 s\n");
}

static void test_gap_generator_power() {
    World w;
    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    w.set_terrain(40, 40, terrain.data());
    const auto cell = [](int x, int y) { return size_t(y * 40 + x); };
    UnitType gap; gap.building = true; gap.foot_w = 1; gap.foot_h = 1; gap.footprint = {1};
    gap.hp = 50000; gap.power = -60; gap.needs_power = true; gap.creates_shroud_range = 6 * CELL;
    UnitType powr; powr.building = true; powr.foot_w = 2; powr.foot_h = 2; powr.footprint = {1, 1, 1, 1};
    powr.hp = 40000; powr.power = 100;
    const int t_gap = w.define_type(gap), t_powr = w.define_type(powr);
    const int32_t pid = w.spawn_building(t_powr, 0, {2, 2});
    w.spawn_building(t_gap, 0, {20, 20});
    w.step();
    w.explore_all(1);
    CHECK(w.visibility(1)[cell(20, 20)] == 0);

    w.destroy(pid);
    w.step();
    w.update_visibility(1);
    CHECK(w.visibility(1)[cell(20, 20)] == 1);
    CHECK(!w.shroud_generated(1, CPos{20, 20}));

    World w2;
    std::vector<uint8_t> t2(40 * 40, uint8_t(TER_CLEAR));
    w2.set_terrain(40, 40, t2.data());
    w2.define_type(gap); w2.define_type(powr);
    const int32_t pid2 = w2.spawn_building(t_powr, 0, {2, 2});
    w2.spawn_building(t_gap, 0, {20, 20});
    w2.step();
    w2.explore_all(1);
    std::vector<uint8_t> blob;
    CHECK(w2.save(blob));
    World w3;
    w3.define_type(gap); w3.define_type(powr);
    CHECK(w3.load(blob));
    w3.update_visibility(1);
    CHECK(w3.explored(1, CPos{20, 20}));
    CHECK(w3.visibility(1)[cell(20, 20)] == 0);
    CHECK(w3.visibility(1)[cell(30, 20)] == 1);
    w3.destroy(pid2);
    w3.step();
    w3.update_visibility(1);
    CHECK(w3.visibility(1)[cell(20, 20)] == 1);
    std::printf("Tarngenerator: ohne Strom keine Tarnung; Erkundungsschicht ueberlebt Speichern/Laden\n");
}


static void test_radar_jammer() {
    World w;
    std::vector<uint8_t> terrain(60 * 60, uint8_t(TER_CLEAR));
    w.set_terrain(60, 60, terrain.data());
    w.set_alliance(0, 2, true);
    UnitType dome; dome.building = true; dome.foot_w = 2; dome.foot_h = 2; dome.footprint = {1, 1, 1, 1};
    dome.hp = 100000; dome.provides_radar = true;
    UnitType mrj; mrj.speed = 68; mrj.turn_rate = 1024; mrj.hp = 22000; mrj.jammer_range = 18 * CELL;
    const int t_dome = w.define_type(dome), t_mrj = w.define_type(mrj);
    const int32_t did = w.spawn_building(t_dome, 0, {10, 10});
    w.step();
    CHECK(!w.radar_jammed(0));
    CHECK(!w.actor_jammed(did));

    const int32_t far = w.spawn(t_mrj, 1, {45, 10});
    w.step();
    CHECK(!w.actor_jammed(did));

    const int32_t near = w.spawn(t_mrj, 1, {16, 11});
    w.step();
    CHECK(w.actor_jammed(did));
    CHECK(w.radar_jammed(0));

    const int32_t ally = w.spawn(t_mrj, 2, {12, 12});
    w.destroy(near);
    w.step();
    CHECK(!w.actor_jammed(did));
    CHECK(!w.radar_jammed(0));

    w.destroy(did);
    w.step();
    CHECK(!w.radar_jammed(0));
    (void)far; (void)ally;
    std::printf("Stoersender: Radarkuppel faellt ab 18 Zellen Naehe aus, Verbuendete stoeren nicht\n");
}


static void test_mechanic_husk() {
    World w;
    std::vector<uint8_t> terrain(40 * 40, uint8_t(TER_CLEAR));
    w.set_terrain(40, 40, terrain.data());
    UnitType tank; tank.speed = 85; tank.turn_rate = 1024; tank.hp = 40000; tank.armor = ARMOR_HEAVY;
    UnitType husk; husk.speed = 0; husk.hp = 28000; husk.armor = ARMOR_HEAVY; husk.husk = true;
    husk.target_types = TT_GROUND_ACTOR | TT_HUSK | TT_NO_AUTO_TARGET;
    husk.capturable = true; husk.capturable_types = CAP_HUSK;
    husk.infil_transform = TT_HUSK;
    UnitType mech; mech.speed = 49; mech.turn_rate = 1024; mech.infantry = true; mech.hp = 8000;
    mech.locomotor = LOCO_FOOT; mech.captures = true; mech.capture_types = CAP_HUSK; mech.capture_delay = 0;
    mech.infiltrates_ally = TT_HUSK;
    const int t_tank = w.define_type(tank);
    const int t_husk = w.define_type(husk);
    const int t_mech = w.define_type(mech);
    w.set_capture_actor(t_husk, t_tank, 15);


    const int32_t hid = w.spawn(t_husk, 1, {20, 20});
    const int32_t mid = w.spawn(t_mech, 0, {14, 20});
    w.order_capture(&mid, 1, hid);
    const auto gone = [&](int32_t id) {
        const int i = w.index_of(id);
        return i < 0 || !w.actor(size_t(i)).alive;
    };
    for (int t = 0; t < 600 && !gone(hid); ++t) w.step();
    CHECK(gone(hid));
    CHECK(gone(mid));
    int found = -1;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).alive && w.actor(i).type == t_tank) found = int(i);
    CHECK(found >= 0);
    CHECK(w.actor(size_t(found)).owner == 0);
    CHECK(w.actor(size_t(found)).hp == 40000 * 15 / 100);
    CHECK(w.mobile(size_t(found)).cell.x == 20 && w.mobile(size_t(found)).cell.y == 20);


    const int32_t hid2 = w.spawn(t_husk, 0, {26, 20});
    const int32_t mid2 = w.spawn(t_mech, 0, {30, 20});
    w.order_capture(&mid2, 1, hid2);
    for (int t = 0; t < 600 && !gone(hid2); ++t) w.step();
    CHECK(gone(hid2));
    CHECK(gone(mid2));
    int tanks = 0;
    for (size_t i = 0; i < w.actor_count(); ++i)
        if (w.actor(i).alive && w.actor(i).type == t_tank && w.actor(i).owner == 0) ++tanks;
    CHECK(tanks == 2);
    std::printf("Mechaniker: fremdes und eigenes Wrack werden wieder zum Panzer (2 Stueck, 15 %% HP)\n");
}


static void test_wall_target() {
    World w;
    std::vector<uint8_t> cost(32 * 32, 1);
    w.set_map(32, 32, cost.data());
    Weapon cannon;
    cannon.range = 5 * CELL; cannon.reload = 30; cannon.damage = 4000; cannon.spread = 128;
    cannon.speed = 682;
    cannon.valid_targets = TT_GROUND_ACTOR | TT_WATER_ACTOR;
    for (int i = 0; i < NUM_ARMOR; ++i) cannon.versus[i] = 100;
    const int32_t w_cannon = w.define_weapon(cannon);
    UnitType tank;
    tank.speed = 72; tank.turn_rate = 20; tank.hp = 46000; tank.armor = ARMOR_HEAVY;
    tank.weapon = w_cannon; tank.turreted = true; tank.turret_turn = 20; tank.hit_radius = 400;
    tank.targetable = true; tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    tank.crushes = CRUSH_WALL;
    UnitType wall;
    wall.building = true; wall.foot_w = 1; wall.foot_h = 1; wall.footprint = {1};
    wall.sprite_h = 1; wall.hp = 10000; wall.armor = ARMOR_WOOD; wall.hit_radius = 512;
    wall.targetable = true;
    wall.target_types = TT_GROUND_ACTOR | TT_DETONATE | TT_WALL | TT_NO_AUTO_TARGET;
    wall.crush_classes = CRUSH_WALL;
    UnitType tree;
    tree.building = true; tree.foot_w = 1; tree.foot_h = 1; tree.footprint = {1};
    tree.sprite_h = 1; tree.hp = 10000; tree.armor = ARMOR_WOOD; tree.hit_radius = 512;
    tree.targetable = true; tree.target_types = TT_TREES;
    const int t_tank = w.define_type(tank), t_wall = w.define_type(wall), t_tree = w.define_type(tree);


    const int32_t att = w.spawn(t_tank, 0, {10, 10});
    const int32_t foe_wall = w.spawn_building(t_wall, 1, {13, 10});
    CHECK(w.may_attack(size_t(w.index_of(att)), size_t(w.index_of(foe_wall)), false));
    w.order_attack(&att, 1, foe_wall);
    int ticks = 0;
    for (; ticks < 600 && w.index_of(foe_wall) >= 0 && w.actor(size_t(w.index_of(foe_wall))).alive; ++ticks) w.step();
    CHECK(w.index_of(foe_wall) < 0 || !w.actor(size_t(w.index_of(foe_wall))).alive);


    const int32_t own_wall = w.spawn_building(t_wall, 0, {10, 13});
    const int32_t hp0 = w.actor(size_t(w.index_of(own_wall))).hp;
    CHECK(!w.may_attack(size_t(w.index_of(att)), size_t(w.index_of(own_wall)), false));
    w.order_attack(&att, 1, own_wall);
    for (int t = 0; t < 200; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(own_wall))).hp == hp0);
    CHECK(w.may_attack(size_t(w.index_of(att)), size_t(w.index_of(own_wall)), true));
    w.order_attack(&att, 1, own_wall, true);
    int forced = 0;
    for (; forced < 600 && w.index_of(own_wall) >= 0 && w.actor(size_t(w.index_of(own_wall))).alive; ++forced) w.step();
    CHECK(w.index_of(own_wall) < 0 || !w.actor(size_t(w.index_of(own_wall))).alive);


    const int32_t foe_tree = w.spawn_building(t_tree, 1, {10, 7});
    const int32_t tree_hp0 = w.actor(size_t(w.index_of(foe_tree))).hp;
    w.order_attack(&att, 1, foe_tree, true);
    for (int t = 0; t < 300; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(foe_tree))).hp == tree_hp0);


    const int32_t near_wall = w.spawn_building(t_wall, 1, {12, 7});
    const int32_t near_hp0 = w.actor(size_t(w.index_of(near_wall))).hp;
    w.order_stop(&att, 1);
    for (int t = 0; t < 400; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(near_wall))).hp == near_hp0);


    const int32_t crusher = w.spawn(t_tank, 0, {20, 20});
    const int32_t crush_wall = w.spawn_building(t_wall, 1, {20, 24});
    const int32_t crush_hp0 = w.actor(size_t(w.index_of(crush_wall))).hp;
    w.order_move(&crusher, 1, {20, 27});
    for (int t = 0; t < 900; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(crush_wall))).hp == crush_hp0);
    CHECK(w.mobile(size_t(w.index_of(crusher))).cell.y >= 26);
    std::printf("Mauern: fremde Mauer nach %d Ticks beschossen und zerstört, eigene nur mit Zwangsfeuer (%d Ticks), "
                "Baum unantastbar, NoAutoTarget hält das Feuer zurück, Überfahren weiter nicht umgesetzt (§3a)\n",
                ticks, forced);
}

static void test_force_fire() {
    auto build = [](World& w, int32_t& w_cannon, int& t_tank, int& t_bldg) {
        static std::vector<uint8_t> cost(32 * 32, 1);
        w.set_map(32, 32, cost.data());
        Weapon cannon;
        cannon.range = 5 * CELL; cannon.reload = 30; cannon.damage = 4000; cannon.spread = 128;
        cannon.speed = 682;
        cannon.valid_targets = TT_GROUND_ACTOR;
        for (int i = 0; i < NUM_ARMOR; ++i) cannon.versus[i] = 100;
        w_cannon = w.define_weapon(cannon);
        UnitType tank;
        tank.speed = 72; tank.turn_rate = 20; tank.hp = 46000; tank.armor = ARMOR_HEAVY;
        tank.weapon = w_cannon; tank.turreted = true; tank.turret_turn = 20; tank.hit_radius = 400;
        tank.targetable = true; tank.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
        UnitType bldg;
        bldg.building = true; bldg.foot_w = 2; bldg.foot_h = 2; bldg.footprint = {1, 1, 1, 1};
        bldg.sprite_h = 2; bldg.hp = 40000; bldg.armor = ARMOR_WOOD; bldg.hit_radius = 512;
        bldg.targetable = true; bldg.target_types = TT_GROUND_ACTOR | TT_STRUCTURE;
        t_tank = w.define_type(tank);
        t_bldg = w.define_type(bldg);
    };


    World w;
    int32_t w_cannon = -1;
    int t_tank = -1, t_bldg = -1;
    build(w, w_cannon, t_tank, t_bldg);
    const int32_t att = w.spawn(t_tank, 0, {10, 10});
    const int32_t own = w.spawn(t_tank, 0, {13, 10});
    const int32_t foe = w.spawn(t_tank, 1, {10, 16});
    const int32_t bld = w.spawn_building(t_bldg, 0, {10, 13});
    const int32_t own_hp0 = w.actor(size_t(w.index_of(own))).hp;

    w.order_attack(&att, 1, own);
    CHECK(!w.force_attacking(att));
    for (int t = 0; t < 200; ++t) w.step();
    const int32_t own_hp_noforce = w.actor(size_t(w.index_of(own))).hp;
    CHECK(own_hp_noforce == own_hp0);


    w.order_attack(&att, 1, own, true);
    CHECK(w.force_attacking(att));


    std::vector<uint8_t> blob;
    CHECK(w.save(blob));
    World w2;
    int32_t c2 = -1; int tt2 = -1, tb2 = -1;
    build(w2, c2, tt2, tb2);
    CHECK(w2.load(blob));
    CHECK(w2.force_attacking(att));

    for (int t = 0; t < 200; ++t) { w.step(); w2.step(); }
    const int32_t own_hp_force = w.actor(size_t(w.index_of(own))).hp;
    CHECK(own_hp_force < own_hp0);
    CHECK(w2.actor(size_t(w2.index_of(own))).hp == own_hp_force);
    std::printf("Zwangsfeuer: eigener Panzer ohne Force %d HP, mit Force %d HP (Start %d), Stand gleich\n",
                own_hp_noforce, own_hp_force, own_hp0);


    for (int t = 0; t < 1200 && w.actor(size_t(w.index_of(own))).alive; ++t) w.step();
    CHECK(!w.actor(size_t(w.index_of(own))).alive);
    for (int t = 0; t < 20; ++t) w.step();
    CHECK(!w.force_attacking(att));
    CHECK(w.actor(size_t(w.index_of(foe))).hp == 46000);
    std::printf("Zwangsfeuer: Befehl endet mit dem Ziel (force_attacking %d)\n", int(w.force_attacking(att)));


    const int32_t bld_hp0 = w.actor(size_t(w.index_of(bld))).hp;
    w.order_attack(&att, 1, bld);
    for (int t = 0; t < 150; ++t) w.step();
    CHECK(w.actor(size_t(w.index_of(bld))).hp == bld_hp0);
    w.order_attack(&att, 1, bld, true);
    for (int t = 0; t < 400; ++t) w.step();
    const int32_t bld_hp = w.actor(size_t(w.index_of(bld))).hp;
    CHECK(bld_hp < bld_hp0);
    std::printf("Zwangsfeuer: eigenes Gebäude %d → %d HP\n", bld_hp0, bld_hp);


    World g;
    int32_t gc = -1; int gt = -1, gb = -1;
    build(g, gc, gt, gb);
    const int32_t g_att = g.spawn(gt, 0, {10, 10});
    const int32_t g_own = g.spawn(gt, 0, {13, 10});
    const int32_t g_hp0 = g.actor(size_t(g.index_of(g_own))).hp;
    g.order_attack_cell(&g_att, 1, {13, 10});
    CHECK(g.force_attacking(g_att));
    for (int t = 0; t < 300; ++t) g.step();
    const int32_t g_hp = g.actor(size_t(g.index_of(g_own))).hp;
    CHECK(g_hp < g_hp0);
    std::printf("Zwangsfeuer auf den Boden: eigene Einheit auf der Zielzelle %d → %d HP\n", g_hp0, g_hp);


    g.order_stop(&g_att, 1);
    CHECK(!g.force_attacking(g_att));
}


static void test_retreat_under_fire() {
    Weapon shell;
    shell.damage = 3000; shell.spread = 128; shell.range = 6 * CELL; shell.reload = 20;
    shell.valid_targets = TT_GROUND_ACTOR;
    Weapon flak;
    flak.damage = 400; flak.spread = 128; flak.range = 14 * CELL; flak.reload = 8;
    flak.valid_targets = TT_GROUND_ACTOR;

    UnitType tnk;
    tnk.speed = 85; tnk.turn_rate = 20; tnk.hp = 60000; tnk.armor = ARMOR_HEAVY;
    tnk.target_types = TT_GROUND_ACTOR | TT_VEHICLE;
    tnk.turreted = true; tnk.turret_turn = 30;
    tnk.auto_target_mask = TT_INFANTRY | TT_VEHICLE | TT_DEFENSE;
    UnitType gun;
    gun.building = true; gun.foot_w = 1; gun.foot_h = 1; gun.footprint = {1};
    gun.hp = 90000; gun.armor = ARMOR_WOOD; gun.target_types = TT_GROUND_ACTOR | TT_DEFENSE;
    gun.turreted = true; gun.turret_turn = 40;
    gun.auto_target_mask = TT_INFANTRY | TT_VEHICLE;
    UnitType dummy;
    dummy.speed = 1; dummy.turn_rate = 1024; dummy.hp = 400000; dummy.armor = ARMOR_HEAVY;
    dummy.target_types = TT_GROUND_ACTOR | TT_VEHICLE; dummy.weapon = -1; dummy.no_auto_target = true;


    World w;
    std::vector<uint8_t> cost(40 * 40, 1);
    w.set_map(40, 40, cost.data());
    UnitType a_tnk = tnk; a_tnk.weapon = w.define_weapon(shell);
    UnitType a_gun = gun; a_gun.weapon = w.define_weapon(flak);
    const int at_tnk = w.define_type(a_tnk), at_gun = w.define_type(a_gun);


    w.spawn_building(at_gun, 1, {24, 10});
    int32_t squad[4];
    for (int k = 0; k < 4; ++k) squad[k] = w.spawn(at_tnk, 0, CPos{20, 9 + k});
    size_t si[4];
    WDist prev_x[4];
    int32_t hp0 = 0;
    for (int k = 0; k < 4; ++k) {
        si[k] = size_t(w.index_of(squad[k]));
        prev_x[k] = w.actor(si[k]).pos.x;
        hp0 += w.actor(si[k]).hp;
    }
    w.order_move(squad, 4, {2, 10}, 0);
    bool never_back = true, never_targeted = true;
    for (int t = 0; t < 700; ++t) {
        w.step();


        const WDist lead_x = w.actor(si[0]).pos.x;
        if (lead_x > prev_x[0]) never_back = false;
        prev_x[0] = lead_x;
        for (int k = 0; k < 4; ++k) {

            if (w.combat(si[k]).target >= 0) never_targeted = false;
        }
    }
    CHECK(never_back);
    CHECK(never_targeted);
    int32_t hp1 = 0, arrived = 0;
    for (int k = 0; k < 4; ++k) {
        hp1 += w.actor(si[k]).hp;
        CHECK(w.actor(si[k]).alive);
        if (w.mobile(si[k]).cell.x <= 5) ++arrived;
    }
    CHECK(hp1 < hp0);
    CHECK(arrived == 4);


    World v;
    std::vector<uint8_t> vcost(40 * 40, 1);
    v.set_map(40, 40, vcost.data());
    UnitType v_tnk = tnk; v_tnk.weapon = v.define_weapon(shell);
    const int vt_tnk = v.define_type(v_tnk), vt_dummy = v.define_type(dummy);
    const int32_t vtank = v.spawn(vt_tnk, 0, {5, 10});
    const int32_t vfoe = v.spawn(vt_dummy, 1, {20, 6});
    const size_t vi = size_t(v.index_of(vtank)), vfi = size_t(v.index_of(vfoe));
    const int32_t vfoe_hp0 = v.actor(vfi).hp;
    v.order_move(&vtank, 1, {35, 10}, 0);
    WDist vprev = v.actor(vi).pos.x;
    bool v_forward = true, v_requested = false;
    int32_t opp_seen = -1;
    for (int t = 0; t < 500; ++t) {
        v.step();
        const WDist x = v.actor(vi).pos.x;
        if (x < vprev) v_forward = false;
        vprev = x;
        if (v.combat(vi).target >= 0) v_requested = true;
        if (opp_seen < 0 && v.combat(vi).opp_target >= 0) opp_seen = t;
    }
    const int32_t hit = vfoe_hp0 - v.actor(vfi).hp;
    CHECK(hit > 0);
    CHECK(opp_seen >= 0);
    CHECK(!v_requested);
    CHECK(v_forward);
    CHECK(v.mobile(vi).cell.x >= 34);


    World f;
    std::vector<uint8_t> fcost(40 * 40, 1);
    f.set_map(40, 40, fcost.data());
    UnitType foot;
    foot.speed = 56; foot.turn_rate = 1024; foot.infantry = true; foot.locomotor = LOCO_FOOT;
    foot.hp = 5000; foot.armor = ARMOR_NONE; foot.target_types = TT_GROUND_ACTOR | TT_INFANTRY;
    foot.facing_tolerance = 0;
    foot.auto_target_mask = TT_INFANTRY | TT_VEHICLE | TT_DEFENSE;
    foot.weapon = f.define_weapon(shell);
    const int ft_foot = f.define_type(foot), ft_dummy = f.define_type(dummy);
    const int32_t frifle = f.spawn(ft_foot, 0, {5, 10});
    const int32_t ffoe = f.spawn(ft_dummy, 1, {20, 6});
    const size_t fi = size_t(f.index_of(frifle)), ffi = size_t(f.index_of(ffoe));
    const int32_t ffoe_hp0 = f.actor(ffi).hp;
    f.order_move(&frifle, 1, {35, 10}, 0);
    for (int t = 0; t < 700; ++t) f.step();
    CHECK(f.actor(ffi).hp == ffoe_hp0);
    CHECK(f.mobile(fi).cell.x >= 34);

    const int32_t fnear = f.spawn(ft_dummy, 1, {33, 10});
    const size_t fni = size_t(f.index_of(fnear));
    const int32_t fnear_hp0 = f.actor(fni).hp;
    for (int t = 0; t < 60; ++t) f.step();
    CHECK(f.actor(fni).hp < fnear_hp0);


    World r;
    std::vector<uint8_t> rcost(40 * 40, 1);
    r.set_map(40, 40, rcost.data());
    UnitType r_tnk = tnk; r_tnk.weapon = r.define_weapon(shell);
    const int rt_tnk = r.define_type(r_tnk);
    const int32_t rdef = r.spawn(rt_tnk, 0, {10, 10});
    const int32_t ratt = r.spawn(rt_tnk, 1, {13, 10});
    const size_t rdi = size_t(r.index_of(rdef)), rai = size_t(r.index_of(ratt));
    r.set_stance(rdef, STANCE_RETURN_FIRE);
    const int32_t ratt_hp0 = r.actor(rai).hp;
    r.order_attack(&ratt, 1, rdef);
    for (int t = 0; t < 120; ++t) r.step();
    CHECK(r.actor(rai).hp < ratt_hp0);
    CHECK(r.combat(rdi).target == ratt);

    std::printf("Rückzug: Trupp erreicht das Ziel unter Feuer (%d/4, %d HP verloren, nie angehalten=%d), "
                "Turmpanzer trifft in der Fahrt (%d Schaden ab Tick %d), Infanterie nicht, "
                "ReturnFire im Stand unverändert\n",
                arrived, hp0 - hp1, int(never_targeted && never_back), hit, opp_seen);
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
    test_barrels_owned_by_player();
    test_auto_target_tanya();
    test_bot();
    test_bot_repair();
    test_bot_naval();
    test_bot_naval_alarm();
    test_bot_saboteurs();
    test_bot_difficulty();
    test_bot_personality();
    test_bot_target_value();
    test_bot_support_power();
    test_bot_air_squad();
    test_bot_siege_holds_range();
    test_bot_gather();
    test_bot_gather_leaves_without_building();
    test_bot_vorhaben_form_timeout();
    test_bot_difficulty_params();
    test_bot_vorhaben_wahl();
    test_bot_stats();
    test_bot_determinism();
    test_build_area();
    test_place_over_unit();
    test_defense_depot_victory();
    test_deploy_faction();
    test_capture();
    test_enter_activity();
    test_c4_vehicles();
    test_c4_moving_vehicle_exit();
    test_demolish_neutral();
    test_bridge_demolition();
    test_infiltration();
    test_infiltrate_support_power_reset();
    test_capture_notifications();
    test_bridge_repair();
    test_disguise();
    test_disguise_targets();
    test_spy_save_load();
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
    test_husks();
    test_smudges();
    test_defense_attacks_buildings();
    test_tesla();
    test_tesla_tank();
    test_side_prerequisites();
    test_weapon_rules();
    test_missile_projectile();
    test_missile_range_limit();
    test_armaments();
    test_armament_versus();
    test_force_fire();
    test_wall_target();
    test_dog_leap();
    test_dog_leap_miss();
    test_dog_leap_save_load();
    test_economy_rules();
    test_bot_recovery();
    test_bot_intervals();
    test_seeds_rate();
    test_seeds_none_without_mine();
    test_seeds_max_density();
    test_seeds_gems();
    test_seeds_blocked_walk();
    test_bot_harvester_redirect();
    test_bot_expansion();
    test_bot_harvesters_by_ore();
    test_bot_spend_surplus();
    test_bot_defense_budget();
    test_bot_orders();
    test_bot_counter();
    test_bot_expansion_all_fields();
    test_bot_refinery_reachable();
    test_order_deliver();
    test_harvester_queue();
    test_harvester_far_ore();
    test_harvester_gems_and_richness();
    test_harvester_gems();
    test_harvester_prefers_full_field();
    test_harvester_park();
    test_harvester_explore();
    test_bot_squad_advance();
    test_bot_vehicle_timing();
    test_bot_build_reaction();
    test_no_backwards_movement();
    test_cargo();
    test_cargo_helicopter();
    test_aircraft();
    test_air_armaments();
    test_air_attack_run();
    test_air_production();
    test_landing_facing();
    test_landing_pads();
    test_fall_to_earth();
    test_new_options();
    test_paradrop();
    test_paradrop_own_cell();
    test_dual_armament();
    test_cash_trickler();
    test_deploy_special();
    test_mines_and_cloak();
    test_damage_sounds();
    test_support_powers();
    test_nuke_warhead_chain();
    test_nuke_falloff_rings();
    test_determinism_hash();
    test_mp_lockstep();
    test_mp_desync_detected();
    test_mp_visibility_mask();
    test_mp_apply_order_owner();
    bench_visibility();
    test_save_load();
    test_save_load_extras();
    test_save_missile();
    test_save_nuke_chain();
    test_save_size();
    test_naval();
    test_submarine();
    test_cloak_timing();
    test_missile_sub();
    test_destroyer_aa();
    test_cruiser_twin_turrets();
    test_ship_repair();
    test_naval_deadlock();
    test_naval_bridge();
    test_landing_craft();
    test_lst_full_cycle();
    test_lst_ramp();
    test_save_naval();
    test_gps();
    test_frozen_actors();
    test_fog_disabled();
    test_gps_dots();
    test_gap_generator();
    test_gap_generator_power();
    test_radar_jammer();
    test_mechanic_husk();
    test_retreat_under_fire();
    test_low_power_notification();
    bench();
    if (failures == 0) std::printf("OK — alle Tests bestanden (sim v%s)\n", version());
    return failures == 0 ? 0 : 1;
}
