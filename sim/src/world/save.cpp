

#include <algorithm>
#include <cstring>
#include <type_traits>

#include "ra/sim.h"

namespace ra {

void Map::restore(int width, int height, std::vector<uint8_t> cost, std::vector<uint8_t> terrain,
                  std::vector<uint8_t> base_terrain) {
    w_ = width;
    h_ = height;
    cost_[MC_LAND] = std::move(cost);
    terrain_ = std::move(terrain);
    base_terrain_ = std::move(base_terrain);
    cost_[MC_LAND].resize(size_t(w_) * size_t(h_), 0);


    for (int mc = 1; mc < NUM_MOVE_CLASSES; ++mc) cost_[mc].assign(size_t(w_) * size_t(h_), 0);
}

namespace {

constexpr uint32_t SAVE_MAGIC = 0x5653'4152u;


constexpr uint32_t SAVE_VERSION = 3;


enum Section : uint32_t {
    SEC_MAP = 0x2050'414Du,
    SEC_LAYERS = 0x5259'414Cu,
    SEC_ACTORS = 0x5254'4341u,
    SEC_SHOTS = 0x544F'4853u,   // „SHOT" — Projektile, Effekte, Blitze, Töne
    SEC_PLAYERS = 0x5259'4C50u,
    SEC_WORLD = 0x444C'5257u,   // „WRLD" — Tick, RNG, Bargeld, Kisten, Sicht
};

// ------------------------------------------------------------------ Bytefolge schreiben

class Writer {
public:
    explicit Writer(std::vector<uint8_t>& out) : b_(out) {}

    void u8(uint8_t v) { b_.push_back(v); }
    void u32(uint32_t v) {
        for (int i = 0; i < 4; ++i) b_.push_back(uint8_t((v >> (8 * i)) & 0xFF));
    }
    void u64(uint64_t v) {
        for (int i = 0; i < 8; ++i) b_.push_back(uint8_t((v >> (8 * i)) & 0xFF));
    }
    void raw(const void* p, size_t n) {
        const uint8_t* s = static_cast<const uint8_t*>(p);
        b_.insert(b_.end(), s, s + n);
    }
    // Längenrahmen: open() legt einen Platzhalter an, close() trägt die tatsächliche Länge nach.
    size_t open() {
        u32(0);
        return b_.size();
    }
    void close(size_t start) {
        const uint32_t len = uint32_t(b_.size() - start);
        for (int i = 0; i < 4; ++i) b_[start - 4 + size_t(i)] = uint8_t((len >> (8 * i)) & 0xFF);
    }

private:
    std::vector<uint8_t>& b_;
};

// ------------------------------------------------------------------ Bytefolge lesen

class Reader {
public:
    Reader(const uint8_t* data, size_t n) : p_(data), lim_(data + n) {}

    struct Block {
        const uint8_t* prev_lim;
        const uint8_t* stop;
    };

    bool ok() const { return ok_; }
    bool more() const { return p_ < lim_; }
    size_t left() const { return size_t(lim_ - p_); }

    uint8_t u8() {
        if (p_ >= lim_) return 0;
        return *p_++;
    }
    uint32_t u32() {
        uint32_t v = 0;
        for (int i = 0; i < 4; ++i) v |= uint32_t(u8()) << (8 * i);
        return v;
    }
    uint64_t u64() {
        uint64_t v = 0;
        for (int i = 0; i < 8; ++i) v |= uint64_t(u8()) << (8 * i);
        return v;
    }
    void raw(void* dst, size_t n) {
        const size_t take = std::min(n, left());
        if (take) std::memcpy(dst, p_, take);
        if (take < n) {
            std::memset(static_cast<uint8_t*>(dst) + take, 0, n - take);
            ok_ = false;
        }
        p_ += take;
    }
    Block open() {
        const uint32_t len = u32();
        if (size_t(len) > left()) ok_ = false;   // abgeschnittene Datei
        const uint8_t* stop = p_ + std::min(size_t(len), left());
        const Block b{lim_, stop};
        lim_ = stop;
        return b;
    }
    void close(const Block& b) {
        p_ = b.stop;
        lim_ = b.prev_lim;
    }
    void fail() { ok_ = false; }

private:
    const uint8_t* p_;
    const uint8_t* lim_;   // Ende des laufenden Blocks
    bool ok_ = true;
};

// ------------------------------------------------------------------ Besucher
//
// Jede Struktur wird genau einmal beschrieben (visit(...) weiter unten) und von zwei Besuchern
// abgelaufen: Save schreibt, Load liest. Damit kann ein Feld nicht in einem der beiden Wege vergessen
// werden — die Forderung „ein zentraler Ort je Struktur".

struct Save;
struct Load;

template <class V> void visit_fields(V& v, Actor& a);
template <class V> void visit_fields(V& v, Mobile& m);
template <class V> void visit_fields(V& v, Combat& c);
template <class V> void visit_fields(V& v, Harvest& h);
template <class V> void visit_fields(V& v, Air& a);
template <class V> void visit_fields(V& v, SupportPowerState& p);
template <class V> void visit_fields(V& v, QueuedOrder& o);
template <class V> void visit_fields(V& v, Projectile& p);
template <class V> void visit_fields(V& v, Effect& e);
template <class V> void visit_fields(V& v, Zap& z);
template <class V> void visit_fields(V& v, SoundEvent& s);
template <class V> void visit_fields(V& v, CashTick& c);
template <class V> void visit_fields(V& v, BuildItem& b);
template <class V> void visit_fields(V& v, BotParams& p);
template <class V> void visit_fields(V& v, BotSquad& s);
template <class V> void visit_fields(V& v, BotResourceIndice& r);
template <class V> void visit_fields(V& v, BotActiveMcv& m);
template <class V> void visit_fields(V& v, BotRefineryRequest& r);
template <class V> void visit_fields(V& v, BotState& b);
template <class V> void visit_fields(V& v, PlayerState& p);
template <class V> void visit_fields(V& v, CrateSpawnerParams& c);

struct Save {
    Writer& w;

    void operator()(bool& v) { w.u8(v ? 1 : 0); }
    void operator()(int32_t& v) { w.u32(uint32_t(v)); }
    void operator()(uint32_t& v) { w.u32(v); }
    void operator()(int64_t& v) { w.u64(uint64_t(v)); }
    void operator()(uint64_t& v) { w.u64(v); }
    void operator()(CPos& c) { w.u32(uint32_t(c.x)); w.u32(uint32_t(c.y)); }
    void operator()(WVec& v) { w.u32(uint32_t(v.x)); w.u32(uint32_t(v.y)); }
    void operator()(std::string& s) {
        w.u32(uint32_t(s.size()));
        w.raw(s.data(), s.size());
    }
    template <class T, size_t N> void operator()(T (&a)[N]) {
        for (auto& e : a) (*this)(e);
    }
    template <class T> void operator()(std::vector<T>& v) {
        w.u32(uint32_t(v.size()));
        for (auto& e : v) (*this)(e);
    }
    template <class T> void operator()(T& x) {
        if constexpr (std::is_enum_v<T>) {
            int32_t e = int32_t(x);
            (*this)(e);
        } else {
            const size_t b = w.open();
            visit_fields(*this, x);
            w.close(b);
        }
    }
};

struct Load {
    Reader& r;

    void operator()(bool& v) { if (r.more()) v = r.u8() != 0; }
    void operator()(int32_t& v) { if (r.more()) v = int32_t(r.u32()); }
    void operator()(uint32_t& v) { if (r.more()) v = r.u32(); }
    void operator()(int64_t& v) { if (r.more()) v = int64_t(r.u64()); }
    void operator()(uint64_t& v) { if (r.more()) v = r.u64(); }
    void operator()(CPos& c) { if (r.more()) { c.x = int32_t(r.u32()); c.y = int32_t(r.u32()); } }
    void operator()(WVec& v) { if (r.more()) { v.x = int32_t(r.u32()); v.y = int32_t(r.u32()); } }
    void operator()(std::string& s) {
        if (!r.more()) return;
        const uint32_t n = r.u32();
        if (n > r.left()) { r.fail(); s.clear(); return; }
        s.assign(n, '\0');
        r.raw(&s[0], n);
    }
    template <class T, size_t N> void operator()(T (&a)[N]) {
        for (auto& e : a) (*this)(e);
    }
    template <class T> void operator()(std::vector<T>& v) {
        v.clear();
        if (!r.more()) return;
        const uint32_t n = r.u32();

        if (n > r.left()) { r.fail(); return; }
        v.resize(n);
        for (auto& e : v) (*this)(e);
    }
    template <class T> void operator()(T& x) {
        if constexpr (std::is_enum_v<T>) {
            int32_t v = int32_t(x);
            (*this)(v);
            x = T(v);
        } else {
            if (!r.more()) return;
            const auto b = r.open();
            visit_fields(*this, x);
            r.close(b);
        }
    }
};


template <class V> void visit_fields(V& v, Actor& a) {
    v(a.id); v(a.type); v(a.owner); v(a.pos); v(a.facing); v(a.hp); v(a.alive);
    v(a.origin); v(a.make_ticks); v(a.rally);
    v(a.repairing); v(a.repair_ticks); v(a.sell_ticks); v(a.primary);
    v(a.repair_depot); v(a.repair_wait); v(a.being_repaired);
    v(a.active_ticks); v(a.active_anim); v(a.vanished);
    v(a.capture_target); v(a.capture_ticks); v(a.capture_total);
    v(a.enter_kind); v(a.enter_state); v(a.enter_return); v(a.inside);
    v(a.demolish_ticks); v(a.demolish_by);
    v(a.disguise_type); v(a.disguise_owner);
    v(a.infiltrated_count); v(a.infiltrated_by);
    v(a.prone_ticks); v(a.life_ticks);
    v(a.experience); v(a.level); v(a.heal_ticks); v(a.heal_cooldown); v(a.door_ticks);
    v(a.last_attacker); v(a.last_attacker_owner); v(a.last_damage_type);


    v(a.transport); v(a.enter_target); v(a.unload_ticks); v(a.unloading);
    v(a.cloak_timer); v(a.invulnerable_ticks); v(a.chrono_return); v(a.chrono_origin);


    v(a.faction_owner);

    v(a.rally_set);


    v(a.self_heal_ticks); v(a.self_heal_cooldown);
}


template <class V> void visit_fields(V& v, Air& a) {
    v(a.state); v(a.alt); v(a.ammo); v(a.reload); v(a.base);
    v(a.returning); v(a.goal); v(a.has_goal); v(a.land_at_goal); v(a.spin);
}


template <class V> void visit_fields(V& v, SupportPowerState& p) {
    v(p.available); v(p.ready); v(p.charge);
    v(p.used);
}

template <class V> void visit_fields(V& v, Mobile& m) {
    v(m.cell); v(m.to_cell); v(m.sub); v(m.to_sub);
    v(m.in_transit); v(m.moving); v(m.arrived);


    v(m.field);
    v(m.goal); v(m.near_enough); v(m.has_waited); v(m.wait); v(m.is_blocking); v(m.near_cycles);
    v(m.detour); v(m.anim); v(m.progress); v(m.transit_from); v(m.transit_dist);
    v(m.crush_victims); v(m.crush_count);
    v(m.idle_seq); v(m.idle_delay); v(m.idle_anim);
}

template <class V> void visit_fields(V& v, Combat& c) {
    v(c.target); v(c.auto_target); v(c.reload); v(c.burst_left); v(c.scan); v(c.turret);
    v(c.attack_move); v(c.am_goal); v(c.chase_cell); v(c.fire_anim);
    v(c.charges); v(c.recharge); v(c.charge_wait);
    v(c.guard); v(c.attack_cell); v(c.since_shot); v(c.realign); v(c.stance);

    v(c.reload2); v(c.burst2); v(c.since_shot2);

    v(c.barrel_flip);

    v(c.leap_ticks); v(c.leap_len); v(c.leap_origin); v(c.leap_last_target); v(c.leap_dest_cell);
    v(c.leap_lock);
}

template <class V> void visit_fields(V& v, Harvest& h) {
    v(h.state); v(h.automated); v(h.bales); v(h.bale_value); v(h.target); v(h.claim);
    v(h.has_last); v(h.last_cell); v(h.has_order); v(h.order_cell);
    v(h.proc); v(h.linked_proc); v(h.timer); v(h.anim);
}

template <class V> void visit_fields(V& v, QueuedOrder& o) {
    v(o.kind); v(o.cell); v(o.target); v(o.near_enough);
}

template <class V> void visit_fields(V& v, Projectile& p) {
    v(p.pos); v(p.target); v(p.weapon); v(p.owner); v(p.source); v(p.facing); v(p.alive);
    v(p.alt); v(p.target_alt);


    v(p.track_target); v(p.distance_covered); v(p.ticks_alive); v(p.trail_wait);
}

template <class V> void visit_fields(V& v, Effect& e) {
    v(e.pos); v(e.seq); v(e.frame); v(e.ticks); v(e.facing); v(e.alt);
}

template <class V> void visit_fields(V& v, Zap& z) {
    v(z.from); v(z.to); v(z.weapon); v(z.ticks);
}

template <class V> void visit_fields(V& v, SoundEvent& s) {
    v(s.sound); v(s.pos);
}

template <class V> void visit_fields(V& v, CashTick& c) {
    v(c.owner); v(c.amount); v(c.pos);
}

template <class V> void visit_fields(V& v, BuildItem& b) {
    v(b.type); v(b.total_cost); v(b.remaining_cost); v(b.total_time); v(b.remaining_time);
    v(b.slowdown); v(b.started); v(b.paused); v(b.done);
}

template <class V> void visit_fields(V& v, BotParams& p) {
    v(p.min_excess_power); v(p.max_excess_power); v(p.excess_power_increment); v(p.excess_power_threshold);
    v(p.initial_min_refineries); v(p.additional_min_refineries);
    v(p.structure_inactive_delay); v(p.structure_active_delay); v(p.structure_random_delay);
    v(p.structure_resume_delay); v(p.max_failed_placements);
    v(p.min_base_radius); v(p.max_base_radius); v(p.max_resource_cells_to_check);
    v(p.new_production_cash_threshold); v(p.new_production_chance); v(p.production_min_cash);
    v(p.check_best_resource_interval); v(p.max_refinery_per_indice);
    v(p.sell_refinery_interval); v(p.sell_refinery_too_close); v(p.sell_refinery_no_resource);
    v(p.resource_map_stride_radius); v(p.update_resource_map_interval); v(p.resource_map_sweep_intervals);
    v(p.min_construction_yards); v(p.additional_construction_yards); v(p.build_additional_mcv_cash);
    v(p.mcv_scan_interval); v(p.build_mcv_interval);
    v(p.cr_min_deploy_radius); v(p.cr_max_deploy_radius); v(p.cr_try_maintain_range);
    v(p.cr_conyard_dislike_range); v(p.cr_refinery_dislike_range);
    v(p.cb_min_deploy_radius); v(p.cb_max_deploy_radius);
    v(p.unit_feedback_time); v(p.unit_min_cash);
    v(p.initial_harvesters); v(p.scan_idle_harvesters_interval);
    v(p.scan_low_effect_interval); v(p.resource_cells_per_harvester); v(p.harvester_enemy_avoidance);
    v(p.squad_size); v(p.squad_size_random_bonus); v(p.assign_roles_interval); v(p.rush_interval);
    v(p.attack_force_interval); v(p.min_attack_force_delay); v(p.rush_scan_radius);
    v(p.protect_unit_scan_radius); v(p.idle_scan_radius); v(p.danger_scan_radius); v(p.attack_scan_radius);
    v(p.protection_scan_radius);
    v(p.building_fraction); v(p.building_limit); v(p.building_delay); v(p.unit_share); v(p.unit_limit);
}

template <class V> void visit_fields(V& v, BotSquad& s) {
    v(s.type); v(s.state); v(s.units); v(s.target); v(s.leader); v(s.last_updated);
    v(s.last_leader_cell); v(s.last_target); v(s.backoff); v(s.dead);
}

template <class V> void visit_fields(V& v, BotResourceIndice& r) {
    v(r.ix); v(r.iy); v(r.center); v(r.res_center); v(r.res_cells);
    v(r.refineries); v(r.harvesters);
    v(r.enemy_units); v(r.enemy_bases); v(r.friendly_units); v(r.friendly_bases);
}

template <class V> void visit_fields(V& v, BotActiveMcv& m) {
    v(m.id); v(m.dest); v(m.check_spot); v(m.scans);
}

template <class V> void visit_fields(V& v, BotRefineryRequest& r) {
    v(r.mcv_id); v(r.conyard); v(r.resource);
}

template <class V> void visit_fields(V& v, BotState& b) {
    v(b.enabled); v(b.p);
    v(b.wait_ticks_q); v(b.fail_count_q); v(b.fail_retry_q);
    v(b.builder_index); v(b.cached_buildings); v(b.cached_bases); v(b.min_excess_power);
    v(b.unit_ticks); v(b.queue_index); v(b.build_requests);
    v(b.scan_idle_harvesters_ticks); v(b.low_effect_ticks);
    v(b.squads); v(b.active_units); v(b.idle_base_units);
    v(b.rush_ticks); v(b.assign_roles_ticks); v(b.attack_force_ticks); v(b.min_attack_force_delay_ticks);
    v(b.respond_cooldown); v(b.protect_from); v(b.first_tick);
    v(b.initial_base_center); v(b.mcv_ticks); v(b.mcv_scan_ticks);
    v(b.expansion_mode); v(b.failed_attempts); v(b.max_failed_attempts); v(b.last_failed_spot);
    v(b.active_mcvs); v(b.resource_map);
    v(b.rmap_cols); v(b.rmap_rows); v(b.rmap_side); v(b.rmap_scan);
    v(b.rmap_index); v(b.rmap_ticks); v(b.rmap_built);
    v(b.resource_conyard_center); v(b.best_resource_ticks); v(b.sell_refinery_ticks);
    v(b.requested_refineries); v(b.repair_all_tick); v(b.defense_center);
    v(b.harv_respond_cooldown); v(b.mcv_respond_cooldown); v(b.rally_ticks);
}

template <class V> void visit_fields(V& v, PlayerState& p) {
    v(p.queues); v(p.bot); v(p.primary); v(p.win_state); v(p.non_combatant); v(p.faction);
    v(p.allies); v(p.enemies); v(p.explicit_enemies); v(p.participant); v(p.had_required);
    v(p.power_outage); v(p.infiltrated_tokens); v(p.handicap);
    v(p.powers);
}

template <class V> void visit_fields(V& v, CrateSpawnerParams& c) {
    v(c.enabled); v(c.crate_type); v(c.minimum); v(c.maximum);
    v(c.spawn_interval); v(c.initial_delay); v(c.valid_ground);
}


inline void put_elem(Writer& w, uint8_t v) { w.u8(v); }
inline void put_elem(Writer& w, int32_t v) { w.u32(uint32_t(v)); }
inline void put_elem(Writer& w, uint32_t v) { w.u32(v); }
inline void get_elem(Reader& r, uint8_t& v) { v = r.u8(); }
inline void get_elem(Reader& r, int32_t& v) { v = int32_t(r.u32()); }
inline void get_elem(Reader& r, uint32_t& v) { v = r.u32(); }


template <class T> void write_packed(Writer& w, const std::vector<T>& v) {
    size_t runs = 0;
    for (size_t i = 0; i < v.size();) {
        size_t j = i + 1;
        while (j < v.size() && v[j] == v[i]) ++j;
        ++runs;
        i = j;
    }
    const bool rle = runs * (4 + sizeof(T)) < v.size() * sizeof(T);
    w.u8(rle ? 1 : 0);
    w.u32(uint32_t(v.size()));
    if (!rle) {
        for (const T& e : v) put_elem(w, e);
        return;
    }
    for (size_t i = 0; i < v.size();) {
        size_t j = i + 1;
        while (j < v.size() && v[j] == v[i]) ++j;
        w.u32(uint32_t(j - i));
        put_elem(w, v[i]);
        i = j;
    }
}

template <class T> void read_packed(Reader& r, std::vector<T>& v) {
    v.clear();
    if (!r.more()) return;
    const bool rle = r.u8() != 0;
    const uint32_t n = r.u32();
    if (n > (1u << 28) || (!rle && size_t(n) * sizeof(T) > r.left())) { r.fail(); return; }
    v.reserve(n);
    if (!rle) {
        v.resize(n);
        for (T& e : v) get_elem(r, e);
        return;
    }
    while (v.size() < n && r.more()) {
        const uint32_t run = r.u32();
        T value{};
        get_elem(r, value);
        const size_t take = std::min(size_t(run), size_t(n) - v.size());
        v.insert(v.end(), take, value);
    }
    v.resize(n, T{});
}

}


uint64_t World::rules_hash() const {
    uint64_t h = 1469598103934665603ull;
    auto mix = [&h](int64_t v) {
        for (int b = 0; b < 8; ++b) {
            h ^= uint64_t((v >> (8 * b)) & 0xFF);
            h *= 1099511628211ull;
        }
    };
    auto mix_str = [&h](const std::string& s) {
        for (const char c : s) {
            h ^= uint64_t(uint8_t(c));
            h *= 1099511628211ull;
        }
        h ^= 0xFFu;
        h *= 1099511628211ull;
    };
    mix(int64_t(types_.size()));
    mix(int64_t(weapons_.size()));
    mix(int64_t(effects_def_.size()));
    for (const UnitType& t : types_) {
        mix(t.hp); mix(t.cost); mix(t.speed); mix(t.armor); mix(t.weapon);
        mix(t.building ? 1 : 0); mix(t.foot_w); mix(t.foot_h); mix(t.power); mix(t.queue_kind);
        for (const std::string& s : t.provides) mix_str(s);
        for (const std::string& s : t.prerequisites) mix_str(s);
    }
    for (const Weapon& w : weapons_) { mix(w.range); mix(w.damage); mix(w.reload); mix(w.speed); }
    for (const EffectSeq& e : effects_def_) { mix(e.first_frame); mix(e.length); mix(e.ticks_per_frame); }
    return h;
}

uint32_t World::state_version() { return SAVE_VERSION; }


bool World::save(std::vector<uint8_t>& out) {
    out.clear();


    fields_.clear();
    Writer w(out);
    Save v{w};

    w.u32(SAVE_MAGIC);
    w.u32(SAVE_VERSION);
    w.u64(rules_hash());

    auto section = [&](uint32_t tag, auto body) {
        w.u32(tag);
        const size_t b = w.open();
        body();
        w.close(b);
    };

    section(SEC_MAP, [&] {
        w.u32(uint32_t(map_.width()));
        w.u32(uint32_t(map_.height()));
        write_packed(w, map_.raw_cost());
        write_packed(w, map_.raw_terrain());
        write_packed(w, map_.raw_base_terrain());


        for (int mc = 1; mc < NUM_MOVE_CLASSES; ++mc) write_packed(w, map_.raw_cost(mc));
    });

    section(SEC_LAYERS, [&] {
        write_packed(w, res_type_);
        write_packed(w, res_density_);
        write_packed(w, cell_slots_);
        write_packed(w, bib_owner_);
        write_packed(w, claims_);
        w.u32(resource_version_);
        for (int p = 0; p < MAX_PLAYERS; ++p) write_packed(w, vis_[p]);
        write_packed(w, seen_mask_);
        v(reveals_);
        v(reveal_ids_);
    });

    section(SEC_ACTORS, [&] {
        w.u32(uint32_t(actors_.size()));
        for (size_t i = 0; i < actors_.size(); ++i) {


            const size_t b = w.open();
            v(actors_[i]);
            v(mobiles_[i]);
            v(combats_[i]);
            v(harvests_[i]);
            v(order_queue_[i]);
            v(prev_pos_[i]);
            v(prev_facing_[i]);
            v(prev_turret_[i]);
            v(airs_[i]);
            v(cargo_[i]);
            v(paradrop_lz_[i]);
            v(paradrop_delay_[i]);
            w.close(b);
        }
    });

    section(SEC_SHOTS, [&] {
        v(projectiles_);
        v(effects_);
        v(zaps_);
        v(sounds_);
        v(cash_ticks_);
    });

    section(SEC_PLAYERS, [&] {
        for (int p = 0; p < MAX_PLAYERS; ++p) v(players_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(credits_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(resources_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(earned_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(silos_notified_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(funds_notified_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(power_notified_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(new_options_pending_[p]);
        for (int p = 0; p < MAX_PLAYERS; ++p) v(power_balance_[p]);


        for (int p = 0; p < MAX_PLAYERS; ++p) v(notifications_[p]);
    });

    section(SEC_WORLD, [&] {
        v(tick_);
        v(next_id_);
        v(rng_);
        v(conquest_victory_);
        v(neutral_player_);
        v(has_storage_);
        v(crate_p_);
        v(crate_ticks_);
        v(crate_pickups_);
        v(stamp_);

        w.u32(uint32_t(pending_mines_.size()));
        for (auto& m : pending_mines_) { v(m.owner); v(m.type); v(m.cell); }
        w.u32(uint32_t(pending_nukes_.size()));
        for (auto& n : pending_nukes_) { v(n.owner); v(n.type); v(n.target); v(n.ticks); }

        w.u32(uint32_t(pending_gps_.size()));
        for (auto& gp : pending_gps_) { v(gp.owner); v(gp.ticks); }


        for (auto& n : pending_nukes_) { v(n.launch_pos); v(n.total); v(n.reveal_id); }
        w.u32(uint32_t(pending_impacts_.size()));
        for (auto& p : pending_impacts_) {
            v(p.pos); v(p.weapon); v(p.kind); v(p.index); v(p.attacker_id); v(p.attacker_owner); v(p.alt); v(p.ticks);
        }
    });

    return true;
}


bool World::load(const std::vector<uint8_t>& in) {
    Reader r(in.data(), in.size());
    if (r.u32() != SAVE_MAGIC) return false;
    const uint32_t version = r.u32();
    if (version > SAVE_VERSION) return false;
    const uint64_t hash = r.u64();
    if (hash != rules_hash()) return false;


    std::vector<UnitType> types = std::move(types_);
    std::vector<Weapon> weapons = std::move(weapons_);
    std::vector<EffectSeq> effects = std::move(effects_def_);
    *this = World();
    types_ = std::move(types);
    weapons_ = std::move(weapons);
    effects_def_ = std::move(effects);
    has_storage_ = false;
    for (const UnitType& t : types_) if (t.storage > 0) has_storage_ = true;

    Load v{r};
    int32_t width = 0, height = 0;
    size_t actor_count = 0;

    while (r.more()) {
        const uint32_t tag = r.u32();
        const auto block = r.open();
        switch (tag) {
        case SEC_MAP: {
            width = int32_t(r.u32());
            height = int32_t(r.u32());
            std::vector<uint8_t> cost, terrain, base;
            read_packed(r, cost);
            read_packed(r, terrain);
            read_packed(r, base);
            map_.restore(width, height, std::move(cost), std::move(terrain), std::move(base));
            {
                bool complete = true;
                for (int mc = 1; mc < NUM_MOVE_CLASSES; ++mc) {
                    std::vector<uint8_t> layer;
                    read_packed(r, layer);
                    if (layer.size() != size_t(width) * size_t(height)) { complete = false; break; }
                    map_.restore_cost_layer(mc, std::move(layer));
                }

                if (!complete) map_.rebuild_water_costs();
            }
            break;
        }
        case SEC_LAYERS:
            read_packed(r, res_type_);
            read_packed(r, res_density_);
            read_packed(r, cell_slots_);
            read_packed(r, bib_owner_);
            read_packed(r, claims_);
            resource_version_ = r.u32();
            for (int p = 0; p < MAX_PLAYERS; ++p) read_packed(r, vis_[p]);
            read_packed(r, seen_mask_);
            v(reveals_);
            v(reveal_ids_);
            break;
        case SEC_ACTORS: {
            actor_count = r.u32();
            if (actor_count > r.left()) { r.fail(); break; }
            actors_.resize(actor_count);
            mobiles_.resize(actor_count);
            combats_.resize(actor_count);
            harvests_.resize(actor_count);
            order_queue_.resize(actor_count);
            prev_pos_.resize(actor_count);
            prev_facing_.resize(actor_count);
            prev_turret_.resize(actor_count);
            airs_.resize(actor_count);
            cargo_.resize(actor_count);
            paradrop_lz_.resize(actor_count, CPos{-1, -1});
            paradrop_delay_.resize(actor_count, 0);
            for (size_t i = 0; i < actor_count; ++i) {
                const auto ab = r.open();
                actors_[i].faction_owner = -1;
                v(actors_[i]);
                v(mobiles_[i]);
                v(combats_[i]);
                v(harvests_[i]);
                v(order_queue_[i]);
                v(prev_pos_[i]);
                v(prev_facing_[i]);
                v(prev_turret_[i]);
                v(airs_[i]);
                v(cargo_[i]);
                v(paradrop_lz_[i]);
                v(paradrop_delay_[i]);

                if (actors_[i].faction_owner < 0) actors_[i].faction_owner = actors_[i].owner;
                r.close(ab);
            }
            break;
        }
        case SEC_SHOTS:
            v(projectiles_);
            v(effects_);
            v(zaps_);
            v(sounds_);
            v(cash_ticks_);
            break;
        case SEC_PLAYERS:
            for (int p = 0; p < MAX_PLAYERS; ++p) v(players_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(credits_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(resources_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(earned_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(silos_notified_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(funds_notified_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(power_notified_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(new_options_pending_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(power_balance_[p]);
            for (int p = 0; p < MAX_PLAYERS; ++p) v(notifications_[p]);
            break;
        case SEC_WORLD:
            v(tick_);
            v(next_id_);
            v(rng_);
            v(conquest_victory_);
            v(neutral_player_);
            v(has_storage_);
            v(crate_p_);
            v(crate_ticks_);
            v(crate_pickups_);
            v(stamp_);
            if (r.more()) {
                const uint32_t nm = r.u32();
                if (nm > r.left()) { r.fail(); break; }
                pending_mines_.resize(nm);
                for (auto& m : pending_mines_) { v(m.owner); v(m.type); v(m.cell); }
            }
            if (r.more()) {
                const uint32_t nn = r.u32();
                if (nn > r.left()) { r.fail(); break; }
                pending_nukes_.resize(nn);
                for (auto& n : pending_nukes_) { v(n.owner); v(n.type); v(n.target); v(n.ticks); }
            }

            if (r.more()) {
                const uint32_t ng = r.u32();
                if (ng > r.left()) { r.fail(); break; }
                pending_gps_.resize(ng);
                for (auto& gp : pending_gps_) { v(gp.owner); v(gp.ticks); }
            }


            if (r.more()) {
                for (auto& n : pending_nukes_) { v(n.launch_pos); v(n.total); v(n.reveal_id); }
            }
            if (r.more()) {
                const uint32_t np = r.u32();
                if (np > r.left()) { r.fail(); break; }
                pending_impacts_.resize(np);
                for (auto& p : pending_impacts_) {
                    v(p.pos); v(p.weapon); v(p.kind); v(p.index); v(p.attacker_id); v(p.attacker_owner);
                    v(p.alt); v(p.ticks);
                }
            }
            break;
        default:
            break;
        }
        r.close(block);
    }
    if (!r.ok()) return false;


    const size_t cells = size_t(map_.cells());
    res_type_.resize(cells, RES_NONE);
    res_density_.resize(cells, 0);
    cell_slots_.resize(cells * CELL_SLOTS, -1);
    bib_owner_.resize(cells, -1);
    claims_.resize(cells, -1);
    for (auto& vis : vis_) vis.resize(cells, 0);
    seen_mask_.resize(actors_.size(), 0);
    airs_.resize(actors_.size());
    cargo_.resize(actors_.size());
    paradrop_lz_.resize(actors_.size(), CPos{-1, -1});
    paradrop_delay_.resize(actors_.size(), 0);

    detected_.assign(actors_.size(), 0);


    visit_stamp_.assign(cells, 0);
    parent_.assign(cells, -1);
    queue_.clear();
    queue_.reserve(cells);


    fields_.clear();
    for (Mobile& m : mobiles_) m.field_gen = 0;
    index_by_id_.clear();
    index_by_id_.reserve(actors_.size());
    for (size_t i = 0; i < actors_.size(); ++i) index_by_id_[actors_[i].id] = int(i);
    return true;
}

}
