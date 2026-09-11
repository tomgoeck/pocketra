

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <algorithm>
#include <vector>

#include "ra/sim.h"

namespace godot {

class RaSim : public RefCounted {
    GDCLASS(RaSim, RefCounted)

public:
    String version() const;
    int cell_size() const;
    int ticks_per_second() const;

    void set_map(int width, int height, const PackedByteArray& cost);
    void set_terrain(int width, int height, const PackedByteArray& terrain);

    void set_terrain_cell(int cell_x, int cell_y, int terrain);
    void set_non_combatant(int owner, bool value);
    void set_faction(int owner, const String& faction);


    void set_local_player(int player);
    int local_player() const { return local_player_; }


    void set_visibility_players(int mask);
    int visibility_players() const;


    void set_fog_enabled(bool on);
    bool fog_enabled() const;

    void set_rng_seed(int seed);


    String state_hash() const;


    String state_hash_full();


    bool apply_order(int player, const PackedInt32Array& cmd);


    PackedByteArray visibility_map(int owner = -1) const;
    void set_alliance(int a, int b, bool value);
    void set_enemy(int a, int b, bool value);
    void set_neutral_player(int owner);
    void set_conquest_victory(bool on);
    void set_win_state(int owner, int state);
    void destroy(int id, int damage_type);
    void test_impact(int weapon, const Vector2i& pos, int alt);

    bool remove_actor(int id);
    bool has_prerequisite(int owner, const String& token) const;
    bool hostile(int a, int b) const;
    void reveal(int owner, int cell_x, int cell_y, int radius);
    int reveal_source(int owner, int cell_x, int cell_y, int radius);
    void remove_reveal_source(int id);
    void set_stance(int id, int stance);
    int stance(int id) const;
    void order_capture(const PackedInt32Array& ids, int target_id);

    void order_enter(const PackedInt32Array& ids, int target_id);
    int enter_kind_for(int id, int target_id) const;
    int enter_progress(int id) const;
    bool order_disguise(int id, int target_id);
    bool set_disguise(int id, int type, int owner);
    void order_demolish(const PackedInt32Array& ids, int target_id);
    void order_infiltrate(const PackedInt32Array& ids, int target_id);
    int disguise_type(int id) const;
    int power_outage(int owner) const;
    int infiltrated_count(int id) const;
    int infiltrated_by(int id) const;

    bool set_owner(int id, int owner);

    bool set_health(int id, int hp);
    int actor_hp(int id) const;
    Vector2i actor_cell(int id) const;
    int cell_terrain(int cell_x, int cell_y) const;
    int actor_owner(int id) const;


    int last_attacker(int id) const;
    int last_attacker_owner(int id) const;
    int last_damage_type(int id) const;

    bool teleport(int id, int cell_x, int cell_y);
    void order_deploy(const PackedInt32Array& ids);
    bool can_deploy(int id) const;
    void order_lay_mine(const PackedInt32Array& ids);

    bool can_detonate(int id) const;
    bool detonating(int id) const;
    void order_detonate(const PackedInt32Array& ids);
    bool can_chrono(int id) const;
    int chrono_charge_left(int id) const;
    int chrono_max_cells(int id) const;
    bool order_chrono(const PackedInt32Array& ids, int cx, int cy);
    void set_mad_driver(int type, int driver_type);
    bool can_lay_mine(int id) const;
    void set_minelayer(int type, int mine_type);

    void set_husk_actor(int type, int husk_type);

    void set_capture_actor(int type, int into_type, int health_percent);

    bool actor_jammed(int id) const;
    bool radar_jammed(int owner) const;
    void set_repair_actors(int type, const PackedInt32Array& depots);
    void set_land_actors(int type, const PackedInt32Array& pads);
    PackedInt32Array support_powers(int owner) const;
    bool activate_support_power(int owner, int kind, int cell_x, int cell_y, int cell2_x, int cell2_y);
    int define_weapon(const Dictionary& def);
    int define_effect(const Dictionary& def);
    int define_type(const Dictionary& def);
    int spawn(int type, int owner, int cell_x, int cell_y, int facing = -1, int health_percent = 100,
              bool airborne = false);
    int spawn_building(int type, int owner, int cell_x, int cell_y, int health_percent = 100);
    void order_move(const PackedInt32Array& ids, int cell_x, int cell_y, bool queued = false);
    void order_attack_move(const PackedInt32Array& ids, int cell_x, int cell_y, bool queued = false);


    void order_attack(const PackedInt32Array& ids, int target_id, bool queued = false, bool force = false);
    bool force_attacking(int id) const;
    bool has_move_order(int id) const;
    void order_harvest(const PackedInt32Array& ids, int cell_x, int cell_y);


    bool order_deliver(const PackedInt32Array& ids, int refinery_id);


    void order_harvesters_return_to_base(int owner);

    void order_harvesters_resume(int owner);


    int harvest_state(int id) const;
    int harvest_bales(int id) const;
    void order_stop(const PackedInt32Array& ids);
    void order_scatter(const PackedInt32Array& ids);
    void order_guard(const PackedInt32Array& ids, int target_id, bool queued = false);
    void order_attack_cell(const PackedInt32Array& ids, int cell_x, int cell_y);

    void order_enter_transport(const PackedInt32Array& ids, int transport_id);
    void order_unload(const PackedInt32Array& ids);
    bool can_unload(int transport_id) const;

    int ramp_state(int id) const;
    bool can_load(int transport_id, int passenger_id) const;
    bool load_passenger(int transport_id, int passenger_id);
    int cargo_weight(int transport_id) const;
    int transport_of(int id) const;
    PackedInt32Array cargo_of(int transport_id) const;

    int air_altitude(int id) const;
    void order_paradrop(int id, int cell_x, int cell_y);
    void order_land(const PackedInt32Array& ids, int cell_x, int cell_y);

    bool can_resupply_at(int id, int target_id) const;
    void order_resupply(const PackedInt32Array& ids, int target_id);

    void set_parachute_sprite(int frame, float w, float h);

    int sell_value(int id) const;
    bool sell(int id);
    bool toggle_repair(int id);
    bool set_rally(int id, int cell_x, int cell_y);
    bool set_primary(int id);
    void enable_bot(int owner, const Dictionary& params);

    void set_handicap(int owner, int percent);
    int handicap(int owner) const;

    void set_crate_spawner(const Dictionary& params);
    int crate_count() const;
    int bot_squad_count(int owner) const;

    int pick_bot_personality();
    int bot_personality(int owner) const;
    int bot_plan(int owner) const;
    int bot_stat(int owner, int which) const;
    void order_repair(const PackedInt32Array& ids, int depot_id);
    int win_state(int owner) const;


    void set_resource(int cell_x, int cell_y, int type, int density);
    int resource_density(int cell_x, int cell_y) const;
    int resource_version() const;
    PackedByteArray resource_map() const;


    void set_smudge_sprites(int kind, int variants, int depth);
    int smudge_version() const;

    PackedInt32Array smudges() const;
    int credits(int owner) const;
    int earned(int owner) const;
    void give_credits(int owner, int amount);

    void set_resources(int owner, int amount);


    bool queue_build(int owner, int type);
    bool cancel_build(int owner, int kind, int type);
    bool pause_build(int owner, int kind, bool hold);
    bool build_paused(int owner, int kind) const;
    bool build_limit_reached(int owner, int type) const;
    int free_landing_pads(int owner, int type) const;
    int build_limit(int type) const;
    int storage_capacity(int owner) const;
    int resources_stored(int owner) const;
    int cash(int owner) const;

    PackedInt32Array queue_state(int owner, int kind) const;
    PackedInt32Array buildable(int owner, int kind) const;

    void set_palette_dim_offset(int rows) { dim_offset_ = std::max(0, rows); }


    void set_palette_invuln_offset(int rows) { invuln_offset_ = std::max(0, rows); }


    void set_palette_husk_offset(int rows) { husk_offset_ = std::max(0, rows); }


    void set_palette_submerged_row(int row) { submerged_row_ = std::max(0, row); }
    PackedInt32Array hidden_items(int owner, int kind) const;

    PackedByteArray can_place(int owner, int type, int cell_x, int cell_y) const;
    bool place_building(int owner, int type, int cell_x, int cell_y);
    int power_provided(int owner) const;
    int power_drained(int owner) const;
    int build_time(int type) const;
    int type_cost(int type) const;

    PackedInt32Array drain_notifications(int owner = -1);

    int step();
    int tick() const;


    PackedByteArray save_state();
    bool load_state(const PackedByteArray& data);
    int state_version() const;

    String rules_hash() const;
    int actor_count() const;
    int alive_count(int owner) const;
    int moving_count() const;
    int field_count() const;
    int projectile_count() const;
    int last_step_usec() const { return last_step_usec_; }


    PackedFloat32Array render_state(float alpha);


    PackedFloat32Array render_buffer(float alpha);
    int fill_multimesh(const RID& multimesh, float alpha);

    PackedInt32Array drain_sounds();

    PackedInt32Array drain_cash_ticks();


    PackedInt32Array pending_nukes() const;


    PackedInt32Array gps_dots() const;
    bool gps_active() const;


    PackedInt32Array frozen_actors() const;

protected:
    static void _bind_methods();

private:
    struct SpriteInfo {
        int facings = 32;
        bool classic = true;
        int first_frame = 0;
        int run_start = -1;
        int run_len = 0;
        int shoot_start = -1;
        int shoot_len = 0;


        int shoot2_start = -1;
        int shoot2_len = 0;


        std::vector<int> shoot_frames;
        std::vector<int> shoot2_frames;


        std::vector<int> jump_frames;
        int jump_len = 0;

        std::vector<int> mad_frames;
        int mad_len = 0;


        std::vector<int> ramp_open;
        std::vector<int> ramp_close;
        int ramp_hold = -1;
        int ramp_ticks = 15;


        int empty_start = -1;
        int turret_first = -1;


        int turret_count = 1;
        int turret_ox[2] = {0, 0}, turret_oy[2] = {0, 0}, turret_oz[2] = {0, 0};


        float turret_w = 24, turret_h = 24;
        float turret_off_x = 0, turret_off_y = 0;


        int turret_facings = 32;
        bool turret_classic = true;
        int harvest_start = -1;
        int harvest_len = 0;
        int dock_start = -1;
        int dock_len = 0;
        int loop_len = 0;
        int damaged_frame = -1;
        int idle_len = 1;


        int stage_len = 0;
        int resource_stages = 10;
        int idle1_start = -1, idle2_start = -1;
        int idle_anim_ticks = 3;
        int make_first = -1;
        int make_len = 0;
        int make_ticks = 0;


        float make_w = 24, make_h = 24;
        float make_off_x = 0, make_off_y = 0;


        int burn_first = -1, burn_len = 0, burn_ticks = 1;
        float burn_off_x = 0, burn_off_y = 0;
        float burn_w = 24, burn_h = 24;


        int muzzle_first = -1, muzzle_len = 0;
        int muzzle_ox = 0, muzzle_oy = 0, muzzle_oz = 0;
        bool muzzle_turret = false;
        float muzzle_w = 24, muzzle_h = 24;

        int overlay_first = -1, overlay_len = 0;
        int overlay_damaged_first = -1, overlay_damaged_len = 0;
        int active_start = -1;
        int active_len = 0;
        int active_damaged_start = -1;
        int active_tick = 40;
        bool wall = false;


        float off_x = 0, off_y = 0;


        int z_offset = 0;
        bool aircraft = false;
        float frame_w = 24, frame_h = 24;


        struct Rotor {
            int air_first = -1, air_len = 0, air_ticks = 1;
            int ground_first = -1, ground_len = 0, ground_ticks = 1;
            int ox = 0, oy = 0, oz = 0;


            float w = 24, h = 24;
            float off_x = 0, off_y = 0;
        };
        Rotor rotors[2];
        int rotor_count = 0;


        bool husk = false;


        bool cloak_color = false;
    };
    struct WeaponSprite {
        int frame = -1;
        int facings = 1;
        bool classic = false;
        float w = 24, h = 24;
    };
    struct EffectSprite {
        int facings = 1;
        int length = 1;
        float w = 24, h = 24;
        float off_x = 0, off_y = 0;
        bool behind = false;
        bool flipx = false;
        bool owner_palette = false;
        std::vector<int> frames;
    };

    void put_effect(float*& p, const ra::RenderSprite& s) const;

    ra::World world_;
    std::vector<SpriteInfo> sprites_;
    std::vector<WeaponSprite> weapon_sprites_;
    std::vector<EffectSprite> effect_sprites_;
    std::vector<ra::RenderActor> scratch_;
    std::vector<ra::RenderSprite> sprites_scratch_;
    std::vector<ra::SoundEvent> sounds_scratch_;
    std::vector<ra::CashTick> cash_scratch_;
    mutable std::vector<ra::NukeInfo> nuke_scratch_;
    mutable std::vector<ra::World::GpsDotInfo> gps_scratch_;
    std::vector<int32_t> int_scratch_;
    std::vector<uint8_t> byte_scratch_;
    std::vector<int> order_;

    std::vector<float> zap_scratch_;
    uint32_t zap_seed_ = 1;
    int last_step_usec_ = 0;
    int parachute_frame_ = -1;
    float parachute_w_ = 24, parachute_h_ = 24;


    int dim_offset_ = 0;
    int invuln_offset_ = 0;

    int local_player_ = 0;


    int husk_offset_ = 0;
    int submerged_row_ = 0;

    void fill_scratch(float alpha);
    void build_zaps();
    int frame_for(const ra::RenderActor& r) const;
    int overlay_frame_for(const ra::RenderActor& r) const;
};

}
