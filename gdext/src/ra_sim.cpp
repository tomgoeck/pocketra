#include "ra_sim.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/rendering_server.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <chrono>

namespace godot {

constexpr float CELL_PX = 24.0f;


constexpr float SHADOW_ROW = -1.0f;
constexpr float WORLD_TO_PX = CELL_PX / float(ra::CELL);


constexpr int CAMERA_PITCH_SIN = 654;


static void body_offset_px(ra::WAngle facing, int ox, int oy, int oz, float& dx, float& dy) {
    const ra::WVec fwd = ra::direction_of(facing);
    const ra::WVec right = ra::direction_of(ra::wrap_angle(facing - 256));
    const int64_t wx = (int64_t(fwd.x) * ox + int64_t(right.x) * oy) / 1024;
    const int64_t wy = (int64_t(fwd.y) * ox + int64_t(right.y) * oy) * CAMERA_PITCH_SIN / (1024 * 1024);
    dx = float(wx) * WORLD_TO_PX;
    dy = float(wy - oz) * WORLD_TO_PX;
}


template <class Sprite>
static bool make_running(const ra::RenderActor& r, const Sprite& s) {
    return r.make_ticks > 0 && s.make_len > 0 && s.make_ticks > 0;
}


static const int CLASSIC_RANGES[32] = {
    20, 56, 88, 132, 156, 184, 212, 240, 268, 296, 324, 352, 384, 416, 452, 488,
    532, 568, 604, 644, 668, 696, 724, 752, 780, 808, 836, 864, 896, 928, 964, 1000,
};


static const int CLASSIC_FACINGS[32] = {
    0, 40, 74, 112, 146, 172, 200, 228, 256, 284, 312, 340, 370, 402, 436, 472,
    512, 552, 588, 626, 658, 684, 712, 740, 768, 796, 824, 852, 882, 914, 948, 984,
};

static int facing_to_frame(int angle, int facings, bool classic) {
    angle = ra::wrap_angle(angle);
    if (classic) {
        for (int i = 0; i < 32; ++i) {
            if (angle < CLASSIC_RANGES[i]) return i;
        }
        return 0;
    }
    const int step = ra::FULL_TURN / facings;
    return ((angle + step / 2) / step) % facings;
}


static ra::WAngle quantize_facing(ra::WAngle angle, int facings, bool classic) {
    if (facings <= 1) return 0;
    if (classic && facings == 32) return CLASSIC_FACINGS[facing_to_frame(angle, 32, true)];
    return facing_to_frame(angle, facings, false) * (ra::FULL_TURN / facings);
}

static void put_instance(float*& p, float ox, float oy, float frame, float player) {

    *p++ = 1.0f; *p++ = 0.0f; *p++ = 0.0f; *p++ = ox;
    *p++ = 0.0f; *p++ = 1.0f; *p++ = 0.0f; *p++ = oy;
    *p++ = frame; *p++ = player; *p++ = 0.0f; *p++ = 0.0f;
}


static void put_instance_flipped(float*& p, float ox, float oy, float w, float frame, float player) {
    *p++ = -1.0f; *p++ = 0.0f; *p++ = 0.0f; *p++ = ox + w;
    *p++ = 0.0f; *p++ = 1.0f; *p++ = 0.0f; *p++ = oy;
    *p++ = frame; *p++ = player; *p++ = 0.0f; *p++ = 0.0f;
}

void RaSim::_bind_methods() {
    ClassDB::bind_method(D_METHOD("version"), &RaSim::version);
    ClassDB::bind_method(D_METHOD("cell_size"), &RaSim::cell_size);
    ClassDB::bind_method(D_METHOD("ticks_per_second"), &RaSim::ticks_per_second);
    ClassDB::bind_method(D_METHOD("set_map", "width", "height", "cost"), &RaSim::set_map);
    ClassDB::bind_method(D_METHOD("set_terrain", "width", "height", "terrain"), &RaSim::set_terrain);
    ClassDB::bind_method(D_METHOD("set_terrain_cell", "cell_x", "cell_y", "terrain"), &RaSim::set_terrain_cell);
    ClassDB::bind_method(D_METHOD("set_non_combatant", "owner", "value"), &RaSim::set_non_combatant);
    ClassDB::bind_method(D_METHOD("set_faction", "owner", "faction"), &RaSim::set_faction);
    ClassDB::bind_method(D_METHOD("set_local_player", "player"), &RaSim::set_local_player);
    ClassDB::bind_method(D_METHOD("local_player"), &RaSim::local_player);
    ClassDB::bind_method(D_METHOD("set_visibility_players", "mask"), &RaSim::set_visibility_players);
    ClassDB::bind_method(D_METHOD("visibility_players"), &RaSim::visibility_players);
    ClassDB::bind_method(D_METHOD("set_fog_enabled", "on"), &RaSim::set_fog_enabled);
    ClassDB::bind_method(D_METHOD("fog_enabled"), &RaSim::fog_enabled);
    ClassDB::bind_method(D_METHOD("set_rng_seed", "seed"), &RaSim::set_rng_seed);
    ClassDB::bind_method(D_METHOD("state_hash"), &RaSim::state_hash);
    ClassDB::bind_method(D_METHOD("state_hash_full"), &RaSim::state_hash_full);
    ClassDB::bind_method(D_METHOD("apply_order", "player", "cmd"), &RaSim::apply_order);
    ClassDB::bind_method(D_METHOD("visibility_map", "owner"), &RaSim::visibility_map, DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("set_alliance", "a", "b", "value"), &RaSim::set_alliance);
    ClassDB::bind_method(D_METHOD("set_enemy", "a", "b", "value"), &RaSim::set_enemy);
    ClassDB::bind_method(D_METHOD("set_neutral_player", "owner"), &RaSim::set_neutral_player);
    ClassDB::bind_method(D_METHOD("set_conquest_victory", "on"), &RaSim::set_conquest_victory);
    ClassDB::bind_method(D_METHOD("set_win_state", "owner", "state"), &RaSim::set_win_state);
    ClassDB::bind_method(D_METHOD("destroy", "id", "damage_type"), &RaSim::destroy, DEFVAL(int(ra::DAMAGE_EXPLOSION)));
    ClassDB::bind_method(D_METHOD("test_impact", "weapon", "pos", "alt"), &RaSim::test_impact, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("remove_actor", "id"), &RaSim::remove_actor);
    ClassDB::bind_method(D_METHOD("has_prerequisite", "owner", "token"), &RaSim::has_prerequisite);
    ClassDB::bind_method(D_METHOD("hostile", "a", "b"), &RaSim::hostile);
    ClassDB::bind_method(D_METHOD("reveal", "owner", "cell_x", "cell_y", "radius"), &RaSim::reveal);
    ClassDB::bind_method(D_METHOD("reveal_source", "owner", "cell_x", "cell_y", "radius"), &RaSim::reveal_source);
    ClassDB::bind_method(D_METHOD("remove_reveal_source", "id"), &RaSim::remove_reveal_source);
    ClassDB::bind_method(D_METHOD("set_stance", "id", "stance"), &RaSim::set_stance);
    ClassDB::bind_method(D_METHOD("stance", "id"), &RaSim::stance);
    ClassDB::bind_method(D_METHOD("order_capture", "ids", "target_id"), &RaSim::order_capture);
    ClassDB::bind_method(D_METHOD("order_enter", "ids", "target_id"), &RaSim::order_enter);
    ClassDB::bind_method(D_METHOD("enter_kind_for", "id", "target_id"), &RaSim::enter_kind_for);
    ClassDB::bind_method(D_METHOD("enter_progress", "id"), &RaSim::enter_progress);
    ClassDB::bind_method(D_METHOD("order_disguise", "id", "target_id"), &RaSim::order_disguise);
    ClassDB::bind_method(D_METHOD("set_disguise", "id", "type", "owner"), &RaSim::set_disguise);
    ClassDB::bind_method(D_METHOD("order_demolish", "ids", "target_id"), &RaSim::order_demolish);
    ClassDB::bind_method(D_METHOD("order_infiltrate", "ids", "target_id"), &RaSim::order_infiltrate);
    ClassDB::bind_method(D_METHOD("disguise_type", "id"), &RaSim::disguise_type);
    ClassDB::bind_method(D_METHOD("power_outage", "owner"), &RaSim::power_outage);
    ClassDB::bind_method(D_METHOD("infiltrated_count", "id"), &RaSim::infiltrated_count);
    ClassDB::bind_method(D_METHOD("infiltrated_by", "id"), &RaSim::infiltrated_by);
    ClassDB::bind_method(D_METHOD("set_owner", "id", "owner"), &RaSim::set_owner);
    ClassDB::bind_method(D_METHOD("set_health", "id", "hp"), &RaSim::set_health);
    ClassDB::bind_method(D_METHOD("actor_hp", "id"), &RaSim::actor_hp);
    ClassDB::bind_method(D_METHOD("actor_cell", "id"), &RaSim::actor_cell);
    ClassDB::bind_method(D_METHOD("cell_terrain", "cell_x", "cell_y"), &RaSim::cell_terrain);
    ClassDB::bind_method(D_METHOD("actor_owner", "id"), &RaSim::actor_owner);
    ClassDB::bind_method(D_METHOD("last_attacker", "id"), &RaSim::last_attacker);
    ClassDB::bind_method(D_METHOD("last_attacker_owner", "id"), &RaSim::last_attacker_owner);
    ClassDB::bind_method(D_METHOD("last_damage_type", "id"), &RaSim::last_damage_type);
    ClassDB::bind_method(D_METHOD("teleport", "id", "cell_x", "cell_y"), &RaSim::teleport);
    ClassDB::bind_method(D_METHOD("order_deploy", "ids"), &RaSim::order_deploy);
    ClassDB::bind_method(D_METHOD("can_deploy", "id"), &RaSim::can_deploy);
    ClassDB::bind_method(D_METHOD("order_lay_mine", "ids"), &RaSim::order_lay_mine);
    ClassDB::bind_method(D_METHOD("can_detonate", "id"), &RaSim::can_detonate);
    ClassDB::bind_method(D_METHOD("detonating", "id"), &RaSim::detonating);
    ClassDB::bind_method(D_METHOD("order_detonate", "ids"), &RaSim::order_detonate);
    ClassDB::bind_method(D_METHOD("can_chrono", "id"), &RaSim::can_chrono);
    ClassDB::bind_method(D_METHOD("chrono_charge_left", "id"), &RaSim::chrono_charge_left);
    ClassDB::bind_method(D_METHOD("chrono_max_cells", "id"), &RaSim::chrono_max_cells);
    ClassDB::bind_method(D_METHOD("order_chrono", "ids", "cx", "cy"), &RaSim::order_chrono);
    ClassDB::bind_method(D_METHOD("set_mad_driver", "type", "driver_type"), &RaSim::set_mad_driver);
    ClassDB::bind_method(D_METHOD("can_lay_mine", "id"), &RaSim::can_lay_mine);
    ClassDB::bind_method(D_METHOD("set_minelayer", "type", "mine_type"), &RaSim::set_minelayer);
    ClassDB::bind_method(D_METHOD("set_husk_actor", "type", "husk_type"), &RaSim::set_husk_actor);
    ClassDB::bind_method(D_METHOD("set_capture_actor", "type", "into_type", "health_percent"), &RaSim::set_capture_actor);
    ClassDB::bind_method(D_METHOD("actor_jammed", "id"), &RaSim::actor_jammed);
    ClassDB::bind_method(D_METHOD("radar_jammed", "owner"), &RaSim::radar_jammed);
    ClassDB::bind_method(D_METHOD("set_repair_actors", "type", "depots"), &RaSim::set_repair_actors);
    ClassDB::bind_method(D_METHOD("set_land_actors", "type", "pads"), &RaSim::set_land_actors);
    ClassDB::bind_method(D_METHOD("support_powers", "owner"), &RaSim::support_powers);
    ClassDB::bind_method(D_METHOD("activate_support_power", "owner", "kind", "cell_x", "cell_y", "cell2_x", "cell2_y"), &RaSim::activate_support_power);
    ClassDB::bind_method(D_METHOD("define_weapon", "def"), &RaSim::define_weapon);
    ClassDB::bind_method(D_METHOD("define_effect", "def"), &RaSim::define_effect);
    ClassDB::bind_method(D_METHOD("define_type", "def"), &RaSim::define_type);
    ClassDB::bind_method(D_METHOD("spawn", "type", "owner", "cell_x", "cell_y", "facing", "health_percent", "airborne"), &RaSim::spawn, DEFVAL(-1), DEFVAL(100), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("spawn_building", "type", "owner", "cell_x", "cell_y", "health_percent"), &RaSim::spawn_building, DEFVAL(100));
    ClassDB::bind_method(D_METHOD("order_move", "ids", "cell_x", "cell_y", "queued"), &RaSim::order_move, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("order_attack_move", "ids", "cell_x", "cell_y", "queued"), &RaSim::order_attack_move, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("order_attack", "ids", "target_id", "queued", "force"), &RaSim::order_attack,
                         DEFVAL(false), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("force_attacking", "id"), &RaSim::force_attacking);
    ClassDB::bind_method(D_METHOD("has_move_order", "id"), &RaSim::has_move_order);
    ClassDB::bind_method(D_METHOD("order_harvest", "ids", "cell_x", "cell_y"), &RaSim::order_harvest);
    ClassDB::bind_method(D_METHOD("order_deliver", "ids", "refinery_id"), &RaSim::order_deliver);
    ClassDB::bind_method(D_METHOD("order_harvesters_return_to_base", "owner"), &RaSim::order_harvesters_return_to_base);
    ClassDB::bind_method(D_METHOD("order_harvesters_resume", "owner"), &RaSim::order_harvesters_resume);
    ClassDB::bind_method(D_METHOD("harvest_state", "id"), &RaSim::harvest_state);
    ClassDB::bind_method(D_METHOD("harvest_bales", "id"), &RaSim::harvest_bales);
    ClassDB::bind_method(D_METHOD("order_stop", "ids"), &RaSim::order_stop);
    ClassDB::bind_method(D_METHOD("order_scatter", "ids"), &RaSim::order_scatter);
    ClassDB::bind_method(D_METHOD("order_guard", "ids", "target_id", "queued"), &RaSim::order_guard, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("order_attack_cell", "ids", "cell_x", "cell_y"), &RaSim::order_attack_cell);
    ClassDB::bind_method(D_METHOD("order_enter_transport", "ids", "transport_id"), &RaSim::order_enter_transport);
    ClassDB::bind_method(D_METHOD("order_unload", "ids"), &RaSim::order_unload);
    ClassDB::bind_method(D_METHOD("can_load", "transport_id", "passenger_id"), &RaSim::can_load);
    ClassDB::bind_method(D_METHOD("load_passenger", "transport_id", "passenger_id"), &RaSim::load_passenger);
    ClassDB::bind_method(D_METHOD("cargo_weight", "transport_id"), &RaSim::cargo_weight);
    ClassDB::bind_method(D_METHOD("can_unload", "transport_id"), &RaSim::can_unload);
    ClassDB::bind_method(D_METHOD("ramp_state", "id"), &RaSim::ramp_state);
    ClassDB::bind_method(D_METHOD("transport_of", "id"), &RaSim::transport_of);
    ClassDB::bind_method(D_METHOD("cargo_of", "transport_id"), &RaSim::cargo_of);
    ClassDB::bind_method(D_METHOD("air_altitude", "id"), &RaSim::air_altitude);
    ClassDB::bind_method(D_METHOD("order_paradrop", "id", "cell_x", "cell_y"), &RaSim::order_paradrop);
    ClassDB::bind_method(D_METHOD("order_land", "ids", "cell_x", "cell_y"), &RaSim::order_land);
    ClassDB::bind_method(D_METHOD("can_resupply_at", "id", "target_id"), &RaSim::can_resupply_at);
    ClassDB::bind_method(D_METHOD("order_resupply", "ids", "target_id"), &RaSim::order_resupply);
    ClassDB::bind_method(D_METHOD("set_parachute_sprite", "frame", "w", "h"), &RaSim::set_parachute_sprite);
    ClassDB::bind_method(D_METHOD("sell_value", "id"), &RaSim::sell_value);
    ClassDB::bind_method(D_METHOD("sell", "id"), &RaSim::sell);
    ClassDB::bind_method(D_METHOD("toggle_repair", "id"), &RaSim::toggle_repair);
    ClassDB::bind_method(D_METHOD("set_rally", "id", "cell_x", "cell_y"), &RaSim::set_rally);
    ClassDB::bind_method(D_METHOD("set_primary", "id"), &RaSim::set_primary);
    ClassDB::bind_method(D_METHOD("enable_bot", "owner", "params"), &RaSim::enable_bot);
    ClassDB::bind_method(D_METHOD("pick_bot_personality"), &RaSim::pick_bot_personality);
    ClassDB::bind_method(D_METHOD("bot_personality", "owner"), &RaSim::bot_personality);
    ClassDB::bind_method(D_METHOD("bot_plan", "owner"), &RaSim::bot_plan);
    ClassDB::bind_method(D_METHOD("bot_stat", "owner", "which"), &RaSim::bot_stat);
    ClassDB::bind_method(D_METHOD("set_handicap", "owner", "percent"), &RaSim::set_handicap);
    ClassDB::bind_method(D_METHOD("handicap", "owner"), &RaSim::handicap);
    ClassDB::bind_method(D_METHOD("set_crate_spawner", "params"), &RaSim::set_crate_spawner);
    ClassDB::bind_method(D_METHOD("crate_count"), &RaSim::crate_count);
    ClassDB::bind_method(D_METHOD("order_repair", "ids", "depot_id"), &RaSim::order_repair);
    ClassDB::bind_method(D_METHOD("win_state", "owner"), &RaSim::win_state);
    ClassDB::bind_method(D_METHOD("bot_squad_count", "owner"), &RaSim::bot_squad_count);
    ClassDB::bind_method(D_METHOD("set_resource", "cell_x", "cell_y", "type", "density"), &RaSim::set_resource);
    ClassDB::bind_method(D_METHOD("resource_density", "cell_x", "cell_y"), &RaSim::resource_density);
    ClassDB::bind_method(D_METHOD("resource_version"), &RaSim::resource_version);
    ClassDB::bind_method(D_METHOD("resource_map"), &RaSim::resource_map);
    ClassDB::bind_method(D_METHOD("set_smudge_sprites", "kind", "variants", "depth"), &RaSim::set_smudge_sprites);
    ClassDB::bind_method(D_METHOD("smudge_version"), &RaSim::smudge_version);
    ClassDB::bind_method(D_METHOD("smudges"), &RaSim::smudges);
    ClassDB::bind_method(D_METHOD("credits", "owner"), &RaSim::credits);
    ClassDB::bind_method(D_METHOD("earned", "owner"), &RaSim::earned);
    ClassDB::bind_method(D_METHOD("give_credits", "owner", "amount"), &RaSim::give_credits);
    ClassDB::bind_method(D_METHOD("set_resources", "owner", "amount"), &RaSim::set_resources);
    ClassDB::bind_method(D_METHOD("queue_build", "owner", "type"), &RaSim::queue_build);
    ClassDB::bind_method(D_METHOD("cancel_build", "owner", "kind", "type"), &RaSim::cancel_build);
    ClassDB::bind_method(D_METHOD("pause_build", "owner", "kind", "hold"), &RaSim::pause_build);
    ClassDB::bind_method(D_METHOD("build_paused", "owner", "kind"), &RaSim::build_paused);
    ClassDB::bind_method(D_METHOD("build_limit_reached", "owner", "type"), &RaSim::build_limit_reached);
    ClassDB::bind_method(D_METHOD("free_landing_pads", "owner", "type"), &RaSim::free_landing_pads);
    ClassDB::bind_method(D_METHOD("build_limit", "type"), &RaSim::build_limit);
    ClassDB::bind_method(D_METHOD("storage_capacity", "owner"), &RaSim::storage_capacity);
    ClassDB::bind_method(D_METHOD("resources_stored", "owner"), &RaSim::resources_stored);
    ClassDB::bind_method(D_METHOD("cash", "owner"), &RaSim::cash);
    ClassDB::bind_method(D_METHOD("queue_state", "owner", "kind"), &RaSim::queue_state);
    ClassDB::bind_method(D_METHOD("buildable", "owner", "kind"), &RaSim::buildable);
    ClassDB::bind_method(D_METHOD("hidden_items", "owner", "kind"), &RaSim::hidden_items);
    ClassDB::bind_method(D_METHOD("set_palette_dim_offset", "rows"), &RaSim::set_palette_dim_offset);
    ClassDB::bind_method(D_METHOD("set_palette_invuln_offset", "rows"), &RaSim::set_palette_invuln_offset);
    ClassDB::bind_method(D_METHOD("set_palette_husk_offset", "rows"), &RaSim::set_palette_husk_offset);
    ClassDB::bind_method(D_METHOD("set_palette_submerged_row", "row"), &RaSim::set_palette_submerged_row);
    ClassDB::bind_method(D_METHOD("can_place", "owner", "type", "cell_x", "cell_y"), &RaSim::can_place);
    ClassDB::bind_method(D_METHOD("build_area", "owner", "adjacent"), &RaSim::build_area);
    ClassDB::bind_method(D_METHOD("pending_place", "owner", "kind"), &RaSim::pending_place);
    ClassDB::bind_method(D_METHOD("cancel_pending_place", "owner", "kind"), &RaSim::cancel_pending_place);
    ClassDB::bind_method(D_METHOD("place_building", "owner", "type", "cell_x", "cell_y"), &RaSim::place_building);
    ClassDB::bind_method(D_METHOD("power_provided", "owner"), &RaSim::power_provided);
    ClassDB::bind_method(D_METHOD("power_drained", "owner"), &RaSim::power_drained);
    ClassDB::bind_method(D_METHOD("build_time", "type"), &RaSim::build_time);
    ClassDB::bind_method(D_METHOD("type_cost", "type"), &RaSim::type_cost);
    ClassDB::bind_method(D_METHOD("drain_notifications", "owner"), &RaSim::drain_notifications, DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("save_state"), &RaSim::save_state);
    ClassDB::bind_method(D_METHOD("load_state", "data"), &RaSim::load_state);
    ClassDB::bind_method(D_METHOD("state_version"), &RaSim::state_version);
    ClassDB::bind_method(D_METHOD("rules_hash"), &RaSim::rules_hash);
    ClassDB::bind_method(D_METHOD("step"), &RaSim::step);
    ClassDB::bind_method(D_METHOD("tick"), &RaSim::tick);
    ClassDB::bind_method(D_METHOD("actor_count"), &RaSim::actor_count);
    ClassDB::bind_method(D_METHOD("alive_count", "owner"), &RaSim::alive_count);
    ClassDB::bind_method(D_METHOD("moving_count"), &RaSim::moving_count);
    ClassDB::bind_method(D_METHOD("field_count"), &RaSim::field_count);
    ClassDB::bind_method(D_METHOD("projectile_count"), &RaSim::projectile_count);
    ClassDB::bind_method(D_METHOD("last_step_usec"), &RaSim::last_step_usec);
    ClassDB::bind_method(D_METHOD("render_state", "alpha"), &RaSim::render_state);
    ClassDB::bind_method(D_METHOD("render_buffer", "alpha"), &RaSim::render_buffer);
    ClassDB::bind_method(D_METHOD("fill_multimesh", "multimesh", "alpha"), &RaSim::fill_multimesh);
    ClassDB::bind_method(D_METHOD("drain_sounds"), &RaSim::drain_sounds);
    ClassDB::bind_method(D_METHOD("drain_cash_ticks"), &RaSim::drain_cash_ticks);
    ClassDB::bind_method(D_METHOD("pending_nukes"), &RaSim::pending_nukes);
    ClassDB::bind_method(D_METHOD("gps_dots"), &RaSim::gps_dots);
    ClassDB::bind_method(D_METHOD("gps_active"), &RaSim::gps_active);
    ClassDB::bind_method(D_METHOD("frozen_actors"), &RaSim::frozen_actors);
}

String RaSim::version() const { return String(ra::version()); }
int RaSim::cell_size() const { return ra::CELL; }
int RaSim::ticks_per_second() const { return ra::TICKS_PER_SECOND; }

void RaSim::set_terrain(int width, int height, const PackedByteArray& terrain) {
    if (terrain.size() < int64_t(width) * height) return;
    world_.set_terrain(width, height, terrain.ptr());
}
void RaSim::set_terrain_cell(int cell_x, int cell_y, int terrain) { world_.set_map_terrain({cell_x, cell_y}, terrain); }
void RaSim::set_non_combatant(int owner, bool value) { world_.set_non_combatant(owner, value); }
void RaSim::set_faction(int owner, const String& faction) { world_.set_faction(owner, faction.utf8().get_data()); }
void RaSim::set_alliance(int a, int b, bool value) { world_.set_alliance(a, b, value); }
void RaSim::set_enemy(int a, int b, bool value) { world_.set_enemy(a, b, value); }
void RaSim::set_neutral_player(int owner) { world_.set_neutral_player(owner); }
void RaSim::set_conquest_victory(bool on) { world_.set_conquest_victory(on); }
void RaSim::set_win_state(int owner, int state) { world_.set_win_state(owner, state); }
void RaSim::destroy(int id, int damage_type) { world_.destroy(id, damage_type); }
void RaSim::test_impact(int weapon, const Vector2i& pos, int alt) {
    world_.test_impact({pos.x, pos.y}, weapon, alt);
}
bool RaSim::remove_actor(int id) { return world_.remove_actor(id); }
bool RaSim::hostile(int a, int b) const { return world_.hostile(a, b); }
void RaSim::order_capture(const PackedInt32Array& ids, int target_id) { world_.order_capture(ids.ptr(), ids.size(), target_id); }
void RaSim::order_enter(const PackedInt32Array& ids, int target_id) { world_.order_enter(ids.ptr(), ids.size(), target_id, ra::ENTER_NONE); }
int RaSim::enter_kind_for(int id, int target_id) const {
    const int i = world_.index_of(id), t = world_.index_of(target_id);
    return (i < 0 || t < 0) ? int(ra::ENTER_NONE) : world_.enter_kind_for(size_t(i), size_t(t));
}
int RaSim::enter_progress(int id) const { return world_.enter_progress(id); }
bool RaSim::order_disguise(int id, int target_id) { return world_.order_disguise(id, target_id); }
bool RaSim::set_disguise(int id, int type, int owner) { return world_.set_disguise(id, type, owner); }
void RaSim::order_demolish(const PackedInt32Array& ids, int target_id) { world_.order_enter(ids.ptr(), ids.size(), target_id, ra::ENTER_DEMOLISH); }
void RaSim::order_infiltrate(const PackedInt32Array& ids, int target_id) { world_.order_enter(ids.ptr(), ids.size(), target_id, ra::ENTER_INFILTRATE); }
int RaSim::disguise_type(int id) const { const int i = world_.index_of(id); return i < 0 ? -1 : world_.actor(size_t(i)).disguise_type; }
int RaSim::power_outage(int owner) const { return world_.power_outage(owner); }
int RaSim::infiltrated_count(int id) const { return world_.infiltrated_count(id); }
int RaSim::infiltrated_by(int id) const { return world_.infiltrated_by(id); }
void RaSim::reveal(int owner, int cell_x, int cell_y, int radius) { world_.reveal(owner, ra::CPos{cell_x, cell_y}, radius); }
bool RaSim::has_prerequisite(int owner, const String& token) const { return world_.has_prerequisite(owner, token.utf8().get_data()); }
bool RaSim::set_owner(int id, int owner) { return world_.set_owner_id(id, owner); }
bool RaSim::set_health(int id, int hp) { return world_.set_health(id, hp); }
int RaSim::actor_hp(int id) const { const int i = world_.index_of(id); return i < 0 ? 0 : world_.actor(size_t(i)).hp; }


Vector2i RaSim::actor_cell(int id) const {
    const int i = world_.index_of(id);
    if (i < 0) return Vector2i(-1, -1);
    const ra::CPos c = world_.mobile(size_t(i)).cell;
    return Vector2i(c.x, c.y);
}


int RaSim::cell_terrain(int cell_x, int cell_y) const { return world_.map().terrain({cell_x, cell_y}); }
int RaSim::actor_owner(int id) const { const int i = world_.index_of(id); return i < 0 ? -1 : world_.actor(size_t(i)).owner; }
int RaSim::last_attacker(int id) const { const int i = world_.index_of(id); return i < 0 ? -1 : world_.actor(size_t(i)).last_attacker; }
int RaSim::last_attacker_owner(int id) const { const int i = world_.index_of(id); return i < 0 ? -1 : world_.actor(size_t(i)).last_attacker_owner; }
int RaSim::last_damage_type(int id) const { const int i = world_.index_of(id); return i < 0 ? -1 : world_.actor(size_t(i)).last_damage_type; }
bool RaSim::teleport(int id, int cell_x, int cell_y) { return world_.teleport(id, {cell_x, cell_y}); }


PackedByteArray RaSim::save_state() {
    std::vector<uint8_t> blob;
    PackedByteArray out;
    if (!world_.save(blob)) return out;
    out.resize(int64_t(blob.size()));
    if (!blob.empty()) std::memcpy(out.ptrw(), blob.data(), blob.size());
    return out;
}

bool RaSim::load_state(const PackedByteArray& data) {
    if (data.is_empty()) return false;
    const std::vector<uint8_t> blob(data.ptr(), data.ptr() + data.size());
    return world_.load(blob);
}

int RaSim::state_version() const { return int(ra::World::state_version()); }

String RaSim::rules_hash() const { return String::num_uint64(int64_t(world_.rules_hash()), 16); }


void RaSim::set_local_player(int player) {
    local_player_ = (player < 0 || player >= ra::MAX_PLAYERS) ? 0 : player;
}
void RaSim::set_visibility_players(int mask) { world_.set_visibility_players(uint32_t(mask)); }
int RaSim::visibility_players() const { return int(world_.visibility_players()); }
void RaSim::set_fog_enabled(bool on) { world_.set_fog_enabled(on); }
bool RaSim::fog_enabled() const { return world_.fog_enabled(); }
void RaSim::set_rng_seed(int seed) { world_.set_rng_seed(uint32_t(seed)); }
String RaSim::state_hash() const { return String::num_uint64(int64_t(world_.state_hash()), 16); }
String RaSim::state_hash_full() { return String::num_uint64(int64_t(world_.state_hash_full()), 16); }
bool RaSim::apply_order(int player, const PackedInt32Array& cmd) {
    return world_.apply_order(player, cmd.ptr(), size_t(cmd.size()));
}

PackedByteArray RaSim::visibility_map(int owner) const {
    const std::vector<uint8_t>& v = world_.visibility(owner < 0 ? local_player_ : owner);
    PackedByteArray out;
    out.resize(int64_t(v.size()));
    if (!v.empty()) std::memcpy(out.ptrw(), v.data(), v.size());
    return out;
}
void RaSim::order_deploy(const PackedInt32Array& ids) { world_.order_deploy(ids.ptr(), ids.size()); }
bool RaSim::can_deploy(int id) const { return world_.can_deploy(id); }
void RaSim::order_lay_mine(const PackedInt32Array& ids) { world_.order_lay_mine(ids.ptr(), ids.size()); }
bool RaSim::can_detonate(int id) const { return world_.can_detonate(id); }
bool RaSim::detonating(int id) const { return world_.detonating(id); }
void RaSim::order_detonate(const PackedInt32Array& ids) { world_.order_detonate(ids.ptr(), ids.size()); }
bool RaSim::can_chrono(int id) const { return world_.can_chrono(id); }
int RaSim::chrono_charge_left(int id) const { return world_.chrono_charge_left(id); }
int RaSim::chrono_max_cells(int id) const { return world_.chrono_max_cells(id); }
bool RaSim::order_chrono(const PackedInt32Array& ids, int cx, int cy) {
    return world_.order_chrono(ids.ptr(), ids.size(), ra::CPos{cx, cy});
}
void RaSim::set_mad_driver(int type, int driver_type) { world_.set_mad_driver(type, driver_type); }
bool RaSim::can_lay_mine(int id) const { return world_.can_lay_mine(id); }
void RaSim::set_minelayer(int type, int mine_type) { world_.set_minelayer(type, mine_type); }
void RaSim::set_husk_actor(int type, int husk_type) { world_.set_husk_actor(type, husk_type); }

void RaSim::set_capture_actor(int type, int into_type, int health_percent) {
    world_.set_capture_actor(type, into_type, health_percent);
}
bool RaSim::actor_jammed(int id) const { return world_.actor_jammed(id); }
bool RaSim::radar_jammed(int owner) const { return world_.radar_jammed(owner); }
void RaSim::set_land_actors(int type, const PackedInt32Array& pads) {
    world_.set_land_actors(type, pads.ptr(), size_t(pads.size()));
}
void RaSim::set_repair_actors(int type, const PackedInt32Array& depots) {
    world_.set_repair_actors(type, depots.ptr(), size_t(depots.size()));
}
PackedInt32Array RaSim::support_powers(int owner) const {
    PackedInt32Array out;
    for (int k = 0; k < ra::SP_COUNT; ++k) {
        int avail = 0, ready = 0, permille = 0, paused = 0;
        world_.support_power_state(owner, k, avail, ready, permille, paused);
        out.push_back(avail); out.push_back(ready); out.push_back(permille); out.push_back(paused);
    }
    return out;
}
bool RaSim::activate_support_power(int owner, int kind, int cell_x, int cell_y, int cell2_x, int cell2_y) {
    return world_.activate_support_power(owner, kind, ra::CPos{cell_x, cell_y}, ra::CPos{cell2_x, cell2_y});
}

void RaSim::set_map(int width, int height, const PackedByteArray& cost) {
    if (cost.size() < int64_t(width) * height) return;
    world_.set_map(width, height, cost.ptr());
}

int RaSim::define_weapon(const Dictionary& def) {
    ra::Weapon w;
    w.range = int(def.get("range", 0));
    w.reload = int(def.get("reload", 1));
    w.burst = int(def.get("burst", 1));
    w.burst_delay = int(def.get("burst_delay", 5));
    w.damage = int(def.get("damage", 0));
    w.damage_percent = bool(def.get("damage_percent", false));
    w.spread = std::max(1, int(def.get("spread", 43)));
    w.damage_type = int(def.get("damage_type", ra::DAMAGE_BULLET));
    w.speed = int(def.get("speed", 0));
    w.inaccuracy = int(def.get("inaccuracy", 0));
    w.delay = int(def.get("delay", 0));


    const Array impacts = def.get("impacts", Array());
    for (int i = 0; i < impacts.size() && w.impact_effect_count < ra::MAX_IMPACT_EFFECTS; ++i) {
        const Dictionary gd = impacts[i];
        ra::ImpactEffect& g = w.impact_effects[w.impact_effect_count];
        const PackedInt32Array fx = gd.get("effects", PackedInt32Array());
        for (int k = 0; k < fx.size() && g.effect_count < ra::MAX_IMPACT_EXPLOSIONS; ++k)
            g.effects[g.effect_count++] = fx[k];
        g.sound = int(gd.get("sound", -1));
        g.sound_chance = int(gd.get("sound_chance", 100));
        g.delay = int(gd.get("delay", 0));
        g.impact_actors = bool(gd.get("impact_actors", true));
        g.valid_targets = uint32_t(int64_t(gd.get("valid_targets", 0)));
        g.invalid_targets = uint32_t(int64_t(gd.get("invalid_targets", 0)));
        g.valid_terrain = uint32_t(int64_t(gd.get("valid_terrain", 0)));
        g.invalid_terrain = uint32_t(int64_t(gd.get("invalid_terrain", 0)));
        if (g.effect_count > 0 || g.sound >= 0) ++w.impact_effect_count;
        else g = ra::ImpactEffect();
    }
    w.report_sound = int(def.get("report_sound", -1));
    const Array versus = def.get("versus", Array());
    for (int i = 0; i < ra::NUM_ARMOR && i < versus.size(); ++i) w.versus[i] = int(versus[i]);
    w.min_range = int(def.get("min_range", 0));
    const Array falloff = def.get("falloff", Array());
    if (!falloff.is_empty()) {


        w.falloff_steps = std::max(1, std::min(8, int(falloff.size())));
        for (int i = 0; i < w.falloff_steps; ++i) w.falloff[i] = int(falloff[i]);
    }
    w.valid_targets = uint32_t(int64_t(def.get("valid_targets", 0)));
    w.invalid_targets = uint32_t(int64_t(def.get("invalid_targets", 0)));

    w.smudge_type = int(def.get("smudge_type", int(ra::SMUDGE_NONE)));
    w.smudge_size = int(def.get("smudge_size", 0));
    w.smudge_size_inner = int(def.get("smudge_size_inner", 0));
    w.smudge_chance = int(def.get("smudge_chance", 100));
    w.smudge_valid_targets = uint32_t(int64_t(def.get("smudge_valid_targets", 0)));
    w.smudge_invalid_targets = uint32_t(int64_t(def.get("smudge_invalid_targets", 0)));
    w.relation = int(def.get("relation", 0));


    w.hits_allies = bool(def.get("hits_allies", false));
    w.trigger_prone = bool(def.get("trigger_prone", false));
    w.prone_damage = int(def.get("prone_damage", 100));

    w.zap_duration = int(def.get("zap_duration", 0));
    w.zap_bright = int(def.get("zap_bright", -1));
    w.zap_dim = int(def.get("zap_dim", -1));

    w.cluster_weapon = int(def.get("cluster_weapon", -1));
    const PackedInt32Array cluster = def.get("cluster_offsets", PackedInt32Array());
    w.cluster_count = std::min(8, int(cluster.size() / 2));
    for (int k = 0; k < w.cluster_count; ++k) {
        w.cluster_dx[k] = int8_t(cluster[k * 2]);
        w.cluster_dy[k] = int8_t(cluster[k * 2 + 1]);
    }

    w.proj_missile = bool(def.get("missile", false));
    w.missile_turn_rate = int(def.get("missile_turn_rate", 20));
    w.missile_range_limit = int(def.get("missile_range_limit", 0));
    w.missile_arm = int(def.get("missile_arm", 0));
    w.missile_lock_on_probability = int(def.get("missile_lock_on_probability", 100));
    w.missile_lock_on_inaccuracy = int(def.get("missile_lock_on_inaccuracy", -1));
    w.missile_close_enough = int(def.get("missile_close_enough", 298));
    w.missile_trail_effect = int(def.get("missile_trail_effect", -1));
    w.missile_trail_interval = std::max(1, int(def.get("missile_trail_interval", 2)));

    const Array extra = def.get("extra_warheads", Array());
    w.extra_warhead_count = std::min(4, int(extra.size()));
    for (int i = 0; i < w.extra_warhead_count; ++i) {
        const Dictionary ed = extra[i];
        ra::ExtraWarhead& e = w.extra_warheads[i];
        e.delay = int(ed.get("delay", 0));
        e.spread = std::max(1, int(ed.get("spread", 43)));
        e.damage = int(ed.get("damage", 0));
        const Array efo = ed.get("falloff", Array());
        if (!efo.is_empty()) {
            e.falloff_steps = std::max(1, std::min(8, int(efo.size())));
            for (int j = 0; j < e.falloff_steps; ++j) e.falloff[j] = int(efo[j]);
        }
        const Array ev = ed.get("versus", Array());
        for (int j = 0; j < ra::NUM_ARMOR && j < ev.size(); ++j) e.versus[j] = int(ev[j]);
        e.valid_targets = uint32_t(int64_t(ed.get("valid_targets", 0)));
        e.invalid_targets = uint32_t(int64_t(ed.get("invalid_targets", 0)));
        e.trigger_prone = bool(ed.get("trigger_prone", false));
        e.prone_damage = int(ed.get("prone_damage", 100));
    }
    const Array dres = def.get("destroy_resource", Array());
    w.destroy_resource_count = std::min(6, int(dres.size()));
    for (int i = 0; i < w.destroy_resource_count; ++i) {
        const Dictionary dd = dres[i];
        w.destroy_resource[i].delay = int(dd.get("delay", 0));
        w.destroy_resource[i].size = int(dd.get("size", 0));
    }
    WeaponSprite ws;
    ws.frame = int(def.get("frame", -1));
    ws.facings = std::max(1, int(def.get("facings", 1)));
    ws.classic = bool(def.get("classic", false));
    ws.w = float(def.get("frame_w", 24));
    ws.h = float(def.get("frame_h", 24));
    weapon_sprites_.push_back(ws);
    return world_.define_weapon(w);
}

int RaSim::define_effect(const Dictionary& def) {
    EffectSprite es;
    es.facings = int(def.get("facings", 1));
    es.length = int(def.get("length", 1));
    es.w = float(def.get("frame_w", 24));
    es.h = float(def.get("frame_h", 24));


    es.off_x = float(int(def.get("offset_x", 0)));
    es.off_y = float(int(def.get("offset_y", 0)));

    es.behind = int(def.get("zoffset", 0)) < 0;
    es.flipx = bool(def.get("flipx", false));
    es.owner_palette = bool(def.get("owner_palette", false));
    const PackedInt32Array frames = def.get("frames", PackedInt32Array());
    es.frames.assign(frames.ptr(), frames.ptr() + frames.size());
    if (!es.frames.empty()) es.length = int(es.frames.size());
    effect_sprites_.push_back(std::move(es));
    ra::EffectSeq e;
    e.first_frame = int(def.get("first_frame", 0));
    e.length = effect_sprites_.back().length;
    e.ticks_per_frame = std::max(1, int(def.get("ticks_per_frame", 1)));
    return world_.define_effect(e);
}

int RaSim::define_type(const Dictionary& def) {
    ra::UnitType t;
    t.speed = int(def.get("speed", 64));
    t.turn_rate = int(def.get("turn_rate", 20));
    t.infantry = bool(def.get("infantry", false));
    t.hp = int(def.get("hp", 1));
    t.armor = std::max(0, std::min(int(ra::NUM_ARMOR) - 1, int(def.get("armor", 0))));
    t.weapon = int(def.get("weapon", -1));
    t.weapon_secondary = int(def.get("weapon_secondary", -1));
    t.weapon_tertiary = int(def.get("weapon_tertiary", -1));
    t.turreted = bool(def.get("turreted", false));
    t.turret_turn = int(def.get("turret_turn", 512));
    t.realign_delay = int(def.get("realign_delay", 40));


    const Array turret_offsets = def.get("turret_offsets", Array());
    t.turret_count = std::max(1, std::min(int(ra::MAX_TURRETS), int(turret_offsets.size())));
    for (int k = 0; k < int(turret_offsets.size()) && k < int(ra::MAX_TURRETS); ++k) {
        const Array o = turret_offsets[k];
        if (o.size() >= 3) {
            t.turret_ox[k] = int(o[0]); t.turret_oy[k] = int(o[1]); t.turret_oz[k] = int(o[2]);
        }
    }
    const Array arm_turrets = def.get("arm_turrets", Array());
    for (int k = 0; k < int(arm_turrets.size()) && k < ra::NUM_ARMS; ++k)
        t.arm_turret[k] = std::max(0, std::min(int(ra::MAX_TURRETS) - 1, int(arm_turrets[k])));
    t.facing_tolerance = int(def.get("facing_tolerance", 512));

    t.leap = bool(def.get("leap", false));
    t.leap_speed = int(def.get("leap_speed", 426));
    t.leap_lock_ticks = int(def.get("leap_lock_ticks", 0));
    t.hit_radius = int(def.get("hit_radius", 0));
    t.range_radius = int(def.get("range_radius", 0));
    t.target_types = uint32_t(int64_t(def.get("target_types", 0)));
    t.target_types_damaged = uint32_t(int64_t(def.get("target_types_damaged", 0)));
    t.target_types_underwater = uint32_t(int64_t(def.get("target_types_underwater", 0)));
    t.crushes = uint32_t(int64_t(def.get("crushes", 0)));
    t.crush_classes = uint32_t(int64_t(def.get("crush_classes", 0)));
    t.crush_sound = int(def.get("crush_sound", -1));
    t.death_weapon = int(def.get("death_weapon", -1));
    t.max_charges = int(def.get("max_charges", 0));
    t.charge_reload = int(def.get("charge_reload", 120));
    t.initial_charge_delay = int(def.get("initial_charge_delay", 22));
    t.charge_delay = int(def.get("charge_delay", 3));
    t.charge_sound = int(def.get("charge_sound", -1));
    t.takes_cover = bool(def.get("takes_cover", false));
    t.prone_duration = int(def.get("prone_duration", 50));
    t.prone_speed = int(def.get("prone_speed", 50));
    t.no_auto_target = bool(def.get("no_auto_target", false));
    t.fully_loaded_speed = int(def.get("fully_loaded_speed", 85));
    t.idle_anim_len[0] = int(def.get("idle1_len", 0));
    t.idle_anim_len[1] = int(def.get("idle2_len", 0));
    t.idle_anim_ticks = std::max(1, int(def.get("idle_anim_ticks", 3)));
    const Array death_fx = def.get("death_effects", Array());
    for (int i = 0; i < death_fx.size() && i < ra::NUM_DAMAGE_TYPES; ++i) t.death_effect[i] = int(death_fx[i]);


    t.mad_charge_delay = int(def.get("mad_charge_delay", -1));
    t.mad_detonation_delay = int(def.get("mad_detonation_delay", 42));
    t.mad_thump_interval = std::max(1, int(def.get("mad_thump_interval", 8)));
    t.mad_thump_weapon = int(def.get("mad_thump_weapon", -1));
    t.mad_detonation_weapon = int(def.get("mad_detonation_weapon", -1));
    t.mad_charge_sound = int(def.get("mad_charge_sound", -1));
    t.mad_detonation_sound = int(def.get("mad_detonation_sound", -1));
    t.detonate_on_deploy = bool(def.get("detonate_on_deploy", false));
    t.chrono_charge_delay = int(def.get("chrono_charge_delay", 0));
    t.chrono_max_distance = int(def.get("chrono_max_distance", 12));
    t.chrono_sound = int(def.get("chrono_sound", -1));
    t.transforms_into = int(def.get("transforms_into", -1));
    t.transforms_dx = int(def.get("transforms_dx", 0));
    t.transforms_dy = int(def.get("transforms_dy", 0));
    t.death_sound = int(def.get("death_sound", -1));
    t.damaged_sound = int(def.get("damaged_sound", -1));
    t.destroyed_sound = int(def.get("destroyed_sound", -1));


    t.mine = bool(def.get("mine", false));
    t.mine_immune = bool(def.get("mine_immune", false));
    t.cloak = bool(def.get("cloak", false));
    t.cloak_initial_delay = int(def.get("cloak_initial_delay", 10));
    t.cloak_delay = int(def.get("cloak_delay", 30));
    t.cloak_types = uint32_t(int(def.get("cloak_types", 1)));
    t.uncloak_on = uint32_t(int(def.get("uncloak_on", 1)));
    t.detect_range = int(def.get("detect_range", 0));
    t.detect_types = uint32_t(int(def.get("detect_types", 0)));


    t.initial_stance = int(def.get("initial_stance", -1));
    t.initial_stance_ai = int(def.get("initial_stance_ai", -1));
    t.cloak_pause_critical = bool(def.get("cloak_pause_critical", false));
    t.cloak_sound = int(def.get("cloak_sound", -1));


    const String footprint = def.get("footprint", "");
    if (footprint.length() > 0) {
        t.building = true;
        const PackedStringArray rows = footprint.split(" ", false);
        t.foot_h = int(rows.size());
        t.foot_w = rows.size() > 0 ? int(rows[0].length()) : 0;
        t.footprint.assign(size_t(t.foot_w * t.foot_h), 0);
        t.build_block.assign(size_t(t.foot_w * t.foot_h), 0);
        for (int y = 0; y < t.foot_h; ++y) {
            for (int x = 0; x < t.foot_w && x < int(rows[y].length()); ++x) {
                const char32_t ch = rows[y][x];
                t.footprint[size_t(y * t.foot_w + x)] = (ch == 'x' || ch == 'X') ? 1 : 0;
                t.build_block[size_t(y * t.foot_w + x)] = (ch != '_') ? 1 : 0;
            }
        }
        t.sprite_h = int(def.get("sprite_h", t.foot_h));
        t.refinery = bool(def.get("refinery", false));
        t.seeds_resource = int(def.get("seeds_resource", ra::RES_NONE));
        t.seed_interval = std::max(1, int(def.get("seed_interval", 75)));
        t.seed_max_range = int(def.get("seed_max_range", 100));
        t.cash_interval = std::max(1, int(def.get("cash_interval", 50)));
        t.support_power = int(def.get("support_power", -1));
        t.sp_charge = std::max(1, int(def.get("sp_charge", 3000)));
        t.sp_duration = int(def.get("sp_duration", 400));
        t.sp_dim_w = std::max(1, int(def.get("sp_dim_w", 1)));
        t.sp_dim_h = std::max(1, int(def.get("sp_dim_h", 1)));
        {
            const String fp = def.get("sp_footprint", "");
            const PackedStringArray rows = fp.split(" ", false);
            t.sp_footprint.assign(size_t(t.sp_dim_w * t.sp_dim_h), 1);
            for (int y = 0; y < t.sp_dim_h && y < int(rows.size()); ++y)
                for (int x = 0; x < t.sp_dim_w && x < int(rows[y].length()); ++x)
                    t.sp_footprint[size_t(y * t.sp_dim_w + x)] = rows[y][x] == '_' ? 0 : 1;
        }
        t.sp_weapon = int(def.get("sp_weapon", -1));
        t.sp_flight = int(def.get("sp_flight", 405));
        t.sp_sound = int(def.get("sp_sound", -1));
        t.sp_launch_effect = int(def.get("sp_launch_effect", -1));
        t.sp_impact_effect = int(def.get("sp_impact_effect", -1));
        t.sp_camera_range = int(def.get("sp_camera_range", 0));
        t.sp_notify_charging = int(def.get("sp_notify_charging", -1));
        t.sp_notify_ready = int(def.get("sp_notify_ready", -1));
        t.sp_notify_launch = int(def.get("sp_notify_launch", -1));
        t.sp_reveal_delay = int(def.get("sp_reveal_delay", 0));
        t.sp_one_shot = bool(def.get("sp_one_shot", false));
        t.cash_amount = int(def.get("cash_amount", 0));
        t.dock_dx = int(def.get("dock_dx", 0));
        t.dock_dy = int(def.get("dock_dy", 0));
        t.dock_angle = int(def.get("dock_angle", 0));
    }

    t.cost = int(def.get("cost", 0));
    t.queue_kind = int(def.get("queue", -1));
    t.palette_order = int(def.get("palette_order", 0));
    const Array prereqs = def.get("prerequisites", Array());
    for (int i = 0; i < prereqs.size(); ++i) t.prerequisites.push_back(String(prereqs[i]).utf8().get_data());
    const Array prereqs_not = def.get("prerequisites_not", Array());
    for (int i = 0; i < prereqs_not.size(); ++i) t.prerequisites_not.push_back(String(prereqs_not[i]).utf8().get_data());
    const Array prereqs_hidden = def.get("prerequisites_hidden", Array());
    for (int i = 0; i < prereqs_hidden.size(); ++i) t.prerequisites_hidden.push_back(String(prereqs_hidden[i]).utf8().get_data());
    const Array provides = def.get("provides", Array());
    for (int i = 0; i < provides.size(); ++i) t.provides.push_back(String(provides[i]).utf8().get_data());
    const Array pf = def.get("provides_factions", Array());
    for (int i = 0; i < pf.size(); ++i) t.provides_factions.push_back(String(pf[i]).utf8().get_data());
    const Array pr = def.get("provides_requires", Array());
    for (int i = 0; i < pr.size(); ++i) t.provides_requires.push_back(String(pr[i]).utf8().get_data());
    t.power = int(def.get("power", 0));
    const Array produces = def.get("produces", Array());
    for (int i = 0; i < produces.size(); ++i) t.produces |= 1u << int(produces[i]);
    t.exit_dx = int(def.get("exit_dx", 1));
    t.exit_dy = int(def.get("exit_dy", 2));
    t.exit_facing = int(def.get("exit_facing", 0));
    t.exit_ox = int(def.get("exit_ox", 0));
    t.exit_oy = int(def.get("exit_oy", 0));
    t.rally_dx = int(def.get("rally_dx", t.exit_dx));
    t.rally_dy = int(def.get("rally_dy", t.exit_dy + 1));
    t.free_dx = int(def.get("free_dx", 0));
    t.free_dy = int(def.get("free_dy", 0));
    t.sell_value = int(def.get("sell_value", -1));
    t.sellable = bool(def.get("sellable", false));
    t.adjacent = int(def.get("adjacent", 2));
    t.terrain_mask = uint32_t(int64_t(def.get("terrain_mask", 0)));
    t.scale_power_with_health = bool(def.get("scale_power_with_health", false));
    t.needs_power = bool(def.get("needs_power", false));
    t.base_provider = bool(def.get("base_provider", false));


    t.requires_base_provider = bool(def.get("requires_base_provider", false));
    t.base_range = int(def.get("base_range", 16 * ra::CELL));
    t.make_ticks = int(def.get("make_ticks", 0));
    t.door_len = int(def.get("door_len", 0));
    t.free_actor = int(def.get("free_actor", -1));
    t.sell_sound = int(def.get("sell_sound", -1));
    t.defense = bool(def.get("defense", false));
    t.gives_buildable_area = bool(def.get("gives_buildable_area", true));
    t.auto_target_mask = uint32_t(int64_t(def.get("auto_target_mask", 0)));
    t.targetable = bool(def.get("targetable", true));
    t.required_short_game = int(def.get("required_short_game", -1));
    t.reveal_cells = int(def.get("reveal_cells", 0));
    t.reveal_range = int(def.get("reveal_range", t.reveal_cells * ra::CELL));

    t.reveal_gap_range = int(def.get("reveal_gap_range", t.reveal_range));
    t.creates_shroud_range = int(def.get("creates_shroud_range", 0));
    t.jammer_range = int(def.get("jammer_range", 0));
    t.provides_radar = bool(def.get("provides_radar", false));
    t.gps_dot = bool(def.get("gps_dot", false));
    t.wall = bool(def.get("wall", false));
    t.captures = bool(def.get("captures", false));
    t.capture_delay = int(def.get("capture_delay", 200));
    t.capture_types = uint32_t(int64_t(def.get("capture_types", 0)));
    t.capturable = bool(def.get("capturable", false));
    t.capturable_types = uint32_t(int64_t(def.get("capturable_types", 0)));

    t.instantly_repairs = bool(def.get("instantly_repairs", false));
    t.instantly_repairable = bool(def.get("instantly_repairable", false));
    t.repairs_bridges = bool(def.get("repairs_bridges", false));
    t.demolition_delay = int(def.get("demolition_delay", -1));
    t.demolishable = bool(def.get("demolishable", false));
    t.infiltrates = uint32_t(int64_t(def.get("infiltrates", 0)));
    t.infiltrates_ally = uint32_t(int64_t(def.get("infiltrates_ally", 0)));
    t.infil_transform = uint32_t(int64_t(def.get("infil_transform", 0)));
    t.capture_health_percent = int(def.get("capture_health", 0));
    t.disguise = bool(def.get("disguise", false));
    t.ignores_disguise = bool(def.get("ignores_disguise", false));
    t.infil_cash = uint32_t(int64_t(def.get("infil_cash", 0)));
    t.infil_cash_percent = int(def.get("infil_cash_percent", 50));
    t.infil_cash_min = int(def.get("infil_cash_min", -1));
    t.infil_cash_max = int(def.get("infil_cash_max", INT32_MAX));
    t.infil_explore = uint32_t(int64_t(def.get("infil_explore", 0)));
    t.infil_power = uint32_t(int64_t(def.get("infil_power", 0)));
    t.infil_power_duration = int(def.get("infil_power_duration", 500));
    t.infil_support = uint32_t(int64_t(def.get("infil_support", 0)));
    t.infil_proxy = std::string(String(def.get("infil_proxy", "")).utf8().get_data());
    t.infil_reset = uint32_t(int64_t(def.get("infil_reset", 0)));

    const Array prod_pre = def.get("producible_prereqs", Array());
    for (int i = 0; i < prod_pre.size(); ++i)
        t.producible_prereqs.push_back(std::string(String(prod_pre[i]).utf8().get_data()));
    t.producible_levels = int(def.get("producible_levels", 1));
    t.storage = int(def.get("storage", 0));


    const String loco = def.get("locomotor", "tracked");
    if (loco == "foot") t.locomotor = ra::LOCO_FOOT;
    else if (loco == "wheeled" || loco == "heavywheeled") t.locomotor = ra::LOCO_WHEELED;
    else if (loco == "naval") t.locomotor = ra::LOCO_NAVAL;
    else if (loco == "lcraft") t.locomotor = ra::LOCO_LCRAFT;
    else t.locomotor = ra::LOCO_TRACKED;
    t.repairs_units = bool(def.get("repairs_units", false));
    t.repairable = bool(def.get("repairable", false));
    t.ai_building_fraction = int(def.get("ai_building_fraction", -1));
    t.ai_building_limit = int(def.get("ai_building_limit", INT32_MAX));
    t.ai_building_delay = int(def.get("ai_building_delay", 0));
    t.ai_unit_share = int(def.get("ai_unit_share", -1));
    t.ai_unit_limit = int(def.get("ai_unit_limit", INT32_MAX));
    t.exclude_from_squads = bool(def.get("exclude_from_squads", false));
    t.build_limit = int(def.get("build_limit", 0));
    t.build_duration = int(def.get("build_duration", -1));
    t.build_duration_pct = int(def.get("build_duration_pct", 60));
    t.repair_step = int(def.get("repair_step", 700));
    t.repair_hp_step = int(def.get("repair_hp_step", 1000));
    t.repair_units_interval = int(def.get("repair_interval", 7));
    t.repair_value_percent = int(def.get("repair_value_percent", 20));

    const Array xp_required = def.get("xp_required", Array());
    t.xp_levels = std::min(int(xp_required.size()), ra::MAX_RANKS);
    for (int i = 0; i < t.xp_levels; ++i) t.xp_required[i] = int(xp_required[i]);
    const Array ranks = def.get("ranks", Array());
    for (int i = 0; i < ranks.size() && i < ra::MAX_RANKS; ++i) {
        const Array r = ranks[i];
        if (r.size() < 4) continue;
        t.ranks[i].firepower = int(r[0]);
        t.ranks[i].damage = int(r[1]);
        t.ranks[i].speed = int(r[2]);
        t.ranks[i].reload = int(r[3]);
    }
    t.gives_experience = int(def.get("gives_experience", -1));
    t.levelup_sound = int(def.get("levelup_sound", -1));
    t.levelup_effect = int(def.get("levelup_effect", -1));
    t.elite_heal_step = int(def.get("elite_heal_step", 0));
    t.elite_heal_percent = int(def.get("elite_heal_percent", 0));
    t.elite_heal_delay = int(def.get("elite_heal_delay", 0));
    t.elite_heal_start_below = int(def.get("elite_heal_start_below", 100));
    t.elite_heal_cooldown = int(def.get("elite_heal_cooldown", 0));

    t.heal_step = int(def.get("heal_step", 0));
    t.heal_percent = int(def.get("heal_percent", 0));
    t.heal_delay = int(def.get("heal_delay", 0));
    t.heal_start_below = int(def.get("heal_start_below", 50));
    t.heal_damage_cooldown = int(def.get("heal_damage_cooldown", 0));


    t.crate = bool(def.get("crate", false));
    t.crate_duration = int(def.get("crate_duration", 0));
    const Array crate_actions = def.get("crate_actions", Array());
    for (int i = 0; i < crate_actions.size(); ++i) {
        const Dictionary cd = crate_actions[i];
        ra::CrateAction ca;
        ca.kind = int(cd.get("kind", 0));
        ca.shares = int(cd.get("shares", 10));
        ca.no_base_shares = int(cd.get("no_base_shares", 1000));
        ca.amount = int(cd.get("amount", 0));
        ca.min_amount = int(cd.get("min_amount", 1));
        ca.max_amount = int(cd.get("max_amount", 2));
        ca.max_value = int(cd.get("max_value", -1));
        ca.max_radius = int(cd.get("max_radius", 4));
        ca.weapon = int(cd.get("weapon", -1));
        ca.time_delay = int(cd.get("time_delay", 0));
        ca.sound = int(cd.get("sound", -1));
        ca.effect = int(cd.get("effect", -1));
        const Array units = cd.get("units", Array());
        for (int k = 0; k < units.size(); ++k) ca.units.push_back(int(units[k]));
        const Array facs = cd.get("factions", Array());
        for (int k = 0; k < facs.size(); ++k) ca.factions.push_back(String(facs[k]).utf8().get_data());
        const Array pre = cd.get("prerequisites", Array());
        for (int k = 0; k < pre.size(); ++k) ca.prerequisites.push_back(String(pre[k]).utf8().get_data());
        t.crate_actions.push_back(ca);
    }
    t.harvester = bool(def.get("harvester", false));
    t.capacity = int(def.get("capacity", 20));
    t.bale_load_delay = int(def.get("bale_load_delay", 4));
    t.bale_unload_delay = int(def.get("bale_unload_delay", 4));
    t.search_from_proc = int(def.get("search_from_proc", 24));
    t.search_from_harv = int(def.get("search_from_harv", 12));
    t.wait_duration = int(def.get("wait_duration", 25));
    t.harvest_facings = int(def.get("harvest_facings", 8));


    t.cargo_max_weight = int(def.get("cargo_max_weight", 0));
    t.cargo_types = uint32_t(int64_t(def.get("cargo_types", 0)));
    t.before_unload_delay = int(def.get("before_unload_delay", 8));
    t.between_unload_delay = int(def.get("between_unload_delay", 0));
    t.after_unload_delay = int(def.get("after_unload_delay", 25));
    t.after_load_delay = int(def.get("after_load_delay", 8));
    t.cargo_eject_on_death = bool(def.get("cargo_eject_on_death", false));
    t.passenger_weight = int(def.get("passenger_weight", 0));
    t.passenger_type = uint32_t(int64_t(def.get("passenger_type", 0)));


    t.ramp_terrain = uint32_t(int64_t(def.get("ramp_terrain", 0)));
    t.ramp_ticks = std::max(1, int(def.get("ramp_ticks", 15)));


    t.aircraft = bool(def.get("aircraft", false));
    t.cruise_altitude = int(def.get("cruise_altitude", 1280));
    t.altitude_velocity = int(def.get("altitude_velocity", 43));
    t.can_hover = bool(def.get("can_hover", false));
    t.vtol = bool(def.get("vtol", false));
    t.idle_behavior = int(def.get("idle_behavior", 0));
    t.landable_terrain = uint32_t(int64_t(def.get("landable_terrain", 0)));
    t.ammo_max = int(def.get("ammo_max", 0));
    t.ammo_reload = int(def.get("ammo_reload", 50));
    t.rearm_sound = int(def.get("rearm_sound", -1));
    t.air_attack_type = int(def.get("air_attack_type", 0));
    const Array rearm = def.get("rearm_actors", Array());
    for (int i = 0; i < rearm.size(); ++i) t.rearm_actors.push_back(int(rearm[i]));
    t.fall_rate = int(def.get("fall_rate", 43));
    t.reservable = bool(def.get("reservable", false));

    t.falls_to_earth = bool(def.get("falls_to_earth", false));
    t.fall_moves = bool(def.get("fall_moves", false));
    t.fall_velocity = int(def.get("fall_velocity", 43));
    t.fall_max_spin = int(def.get("fall_max_spin", -1));
    t.fall_weapon = int(def.get("fall_weapon", -1));
    t.target_types_airborne = uint32_t(int64_t(def.get("target_types_airborne", 0)));


    t.husk = bool(def.get("husk", false));
    t.husk_actor = int(def.get("husk_actor", -1));
    t.husk_probability = int(def.get("husk_probability", 100));
    t.husk_terrain = uint32_t(int64_t(def.get("husk_terrain", 0)));

    SpriteInfo s;


    s.husk = t.husk && !t.aircraft;
    s.cloak_color = t.cloak && (t.cloak_types & uint32_t(ra::DETECT_UNDERWATER)) != 0;
    s.facings = int(def.get("facings", 32));
    s.classic = bool(def.get("classic", s.facings == 32));
    s.first_frame = int(def.get("first_frame", 0));
    s.run_start = int(def.get("run_start", -1));
    s.run_len = int(def.get("run_len", 0));
    s.shoot_start = int(def.get("shoot_start", -1));
    s.shoot_len = int(def.get("shoot_len", 0));
    s.shoot2_start = int(def.get("shoot2_start", -1));
    s.shoot2_len = int(def.get("shoot2_len", 0));
    {
        const Array sf = def.get("shoot_frames", Array());
        for (int i = 0; i < sf.size(); ++i) s.shoot_frames.push_back(int(sf[i]));
        const Array sf2 = def.get("shoot2_frames", Array());
        for (int i = 0; i < sf2.size(); ++i) s.shoot2_frames.push_back(int(sf2[i]));
        const Array jf = def.get("jump_frames", Array());
        for (int i = 0; i < jf.size(); ++i) s.jump_frames.push_back(int(jf[i]));
        const Array mf = def.get("mad_frames", Array());
        for (int i = 0; i < mf.size(); ++i) s.mad_frames.push_back(int(mf[i]));
    }
    s.jump_len = int(def.get("jump_len", 0));
    s.mad_len = int(def.get("mad_len", 0));
    {

        const Array ro = def.get("ramp_open", Array());
        for (int i = 0; i < ro.size(); ++i) s.ramp_open.push_back(int(ro[i]));
        const Array rc = def.get("ramp_close", Array());
        for (int i = 0; i < rc.size(); ++i) s.ramp_close.push_back(int(rc[i]));
        s.ramp_hold = int(def.get("ramp_hold", -1));
        s.ramp_ticks = std::max(1, t.ramp_ticks);
    }
    s.empty_start = int(def.get("empty_start", -1));
    s.turret_first = int(def.get("turret_first", -1));
    {
        const Array to = def.get("turret_offsets", Array());
        s.turret_count = std::max(1, std::min(2, int(to.size())));
        for (int k = 0; k < int(to.size()) && k < 2; ++k) {
            const Array o = to[k];
            if (o.size() >= 3) { s.turret_ox[k] = int(o[0]); s.turret_oy[k] = int(o[1]); s.turret_oz[k] = int(o[2]); }
        }
    }
    s.turret_w = float(def.get("turret_w", 24));
    s.turret_h = float(def.get("turret_h", 24));
    s.turret_off_x = float(int(def.get("turret_off_x", 0)));
    s.turret_off_y = float(int(def.get("turret_off_y", 0)));
    s.turret_facings = std::max(1, int(def.get("turret_facings", 32)));
    s.turret_classic = bool(def.get("turret_classic", true));
    s.harvest_start = int(def.get("harvest_start", -1));
    s.harvest_len = int(def.get("harvest_len", 0));
    s.dock_start = int(def.get("dock_start", -1));
    s.dock_len = int(def.get("dock_len", 0));
    s.loop_len = int(def.get("loop_len", 0));
    s.damaged_frame = int(def.get("damaged_frame", -1));
    s.idle_len = std::max(1, int(def.get("idle_len", 1)));
    s.stage_len = int(def.get("stage_len", 0));
    s.resource_stages = std::max(1, int(def.get("resource_stages", 10)));
    s.idle1_start = int(def.get("idle1_start", -1));
    s.idle2_start = int(def.get("idle2_start", -1));
    s.idle_anim_ticks = t.idle_anim_ticks;
    s.make_first = int(def.get("make_first", -1));
    s.make_len = int(def.get("make_len", 0));
    s.make_ticks = t.make_ticks;
    s.make_w = float(def.get("make_w", 24));
    s.make_h = float(def.get("make_h", 24));
    s.make_off_x = float(int(def.get("make_off_x", 0)));
    s.make_off_y = float(int(def.get("make_off_y", 0)));

    s.burn_first = int(def.get("burn_first", -1));
    s.burn_len = std::max(1, int(def.get("burn_len", 1)));
    s.burn_ticks = std::max(1, int(def.get("burn_ticks", 1)));
    s.burn_off_x = float(def.get("burn_off_x", 0.0));
    s.burn_off_y = float(def.get("burn_off_y", 0.0));
    s.burn_w = float(def.get("burn_w", 24.0));
    s.burn_h = float(def.get("burn_h", 24.0));
    s.muzzle_first = int(def.get("muzzle_first", -1));
    s.muzzle_len = std::max(1, int(def.get("muzzle_len", 1)));
    s.muzzle_ox = int(def.get("muzzle_ox", 0));
    s.muzzle_oy = int(def.get("muzzle_oy", 0));
    s.muzzle_oz = int(def.get("muzzle_oz", 0));
    s.muzzle_turret = bool(def.get("muzzle_turret", false));
    s.muzzle_w = float(def.get("muzzle_w", 24.0));
    s.muzzle_h = float(def.get("muzzle_h", 24.0));
    s.overlay_first = int(def.get("overlay_first", -1));
    s.overlay_len = int(def.get("overlay_len", 0));
    s.overlay_damaged_first = int(def.get("overlay_damaged_first", -1));
    s.overlay_damaged_len = int(def.get("overlay_damaged_len", 0));
    s.active_start = int(def.get("active_start", -1));
    s.wall = bool(def.get("wall", false));
    s.aircraft = t.aircraft;
    const Array rotors = def.get("rotors", Array());
    for (int i = 0; i < rotors.size() && s.rotor_count < 2; ++i) {
        const Dictionary rd = rotors[i];
        SpriteInfo::Rotor& rot = s.rotors[s.rotor_count];
        rot.air_first = int(rd.get("air_first", -1));
        rot.air_len = std::max(1, int(rd.get("air_len", 1)));
        rot.air_ticks = std::max(1, int(rd.get("air_ticks", 1)));
        rot.ground_first = int(rd.get("ground_first", rot.air_first));
        rot.ground_len = std::max(1, int(rd.get("ground_len", rot.air_len)));
        rot.ground_ticks = std::max(1, int(rd.get("ground_ticks", rot.air_ticks)));
        rot.ox = int(rd.get("ox", 0));
        rot.oy = int(rd.get("oy", 0));
        rot.oz = int(rd.get("oz", 0));
        rot.w = float(rd.get("w", 24.0));
        rot.h = float(rd.get("h", 24.0));
        rot.off_x = float(rd.get("off_x", 0.0));
        rot.off_y = float(rd.get("off_y", 0.0));
        if (rot.air_first >= 0) ++s.rotor_count;
    }
    s.active_len = int(def.get("active_len", 0));
    s.active_damaged_start = int(def.get("active_damaged_start", -1));
    s.active_tick = std::max(1, int(def.get("active_tick", 40)));
    s.off_x = float(def.get("offset_x", 0));
    s.off_y = float(def.get("offset_y", 0));
    s.z_offset = int(def.get("z_offset", 0));
    s.frame_w = float(def.get("frame_w", 24));
    s.frame_h = float(def.get("frame_h", 24));
    sprites_.push_back(s);
    return world_.define_type(t);
}

int RaSim::spawn(int type, int owner, int cell_x, int cell_y, int facing, int health_percent, bool airborne) {
    return world_.spawn(type, owner, {cell_x, cell_y}, facing, health_percent, airborne);
}


void RaSim::order_enter_transport(const PackedInt32Array& ids, int transport_id) {
    world_.order_enter_transport(ids.ptr(), ids.size(), transport_id);
}
void RaSim::order_unload(const PackedInt32Array& ids) { world_.order_unload(ids.ptr(), ids.size()); }
bool RaSim::can_load(int transport_id, int passenger_id) const { return world_.can_load(transport_id, passenger_id); }
bool RaSim::load_passenger(int transport_id, int passenger_id) { return world_.load_passenger(transport_id, passenger_id); }
int RaSim::cargo_weight(int transport_id) const { return world_.cargo_weight(transport_id); }


bool RaSim::can_unload(int transport_id) const { return world_.can_unload(transport_id); }

int RaSim::ramp_state(int id) const { return world_.ramp_state(id); }
int RaSim::transport_of(int id) const { return world_.transport_of(id); }
PackedInt32Array RaSim::cargo_of(int transport_id) const {
    PackedInt32Array out;
    const int i = world_.index_of(transport_id);
    if (i < 0) return out;
    const std::vector<int32_t>& list = world_.cargo_of(size_t(i));
    out.resize(int64_t(list.size()));
    for (size_t k = 0; k < list.size(); ++k) out.set(int64_t(k), list[k]);
    return out;
}
int RaSim::air_altitude(int id) const { return world_.air_altitude(id); }
void RaSim::order_paradrop(int id, int cell_x, int cell_y) { world_.order_paradrop(id, ra::CPos{cell_x, cell_y}); }
bool RaSim::can_resupply_at(int id, int target_id) const { return world_.can_resupply_at(id, target_id); }
void RaSim::order_resupply(const PackedInt32Array& ids, int target_id) {
    world_.order_resupply(ids.ptr(), ids.size(), target_id);
}
void RaSim::order_land(const PackedInt32Array& ids, int cell_x, int cell_y) {
    world_.order_land(ids.ptr(), ids.size(), ra::CPos{cell_x, cell_y});
}
void RaSim::set_parachute_sprite(int frame, float w, float h) {
    parachute_frame_ = frame;
    parachute_w_ = w;
    parachute_h_ = h;
}
int RaSim::spawn_building(int type, int owner, int cell_x, int cell_y, int health_percent) {
    return world_.spawn_building(type, owner, {cell_x, cell_y}, health_percent);
}


void RaSim::order_move(const PackedInt32Array& ids, int cell_x, int cell_y, bool queued) {
    if (queued) {
        ra::QueuedOrder o;
        o.kind = ra::QueuedOrder::MOVE;
        o.cell = {cell_x, cell_y};
        world_.queue_order(ids.ptr(), ids.size(), o);
        return;
    }
    world_.order_move(ids.ptr(), ids.size(), {cell_x, cell_y});
}
void RaSim::order_attack_move(const PackedInt32Array& ids, int cell_x, int cell_y, bool queued) {
    if (queued) {
        ra::QueuedOrder o;
        o.kind = ra::QueuedOrder::ATTACK_MOVE;
        o.cell = {cell_x, cell_y};
        world_.queue_order(ids.ptr(), ids.size(), o);
        return;
    }
    world_.order_attack_move(ids.ptr(), ids.size(), {cell_x, cell_y});
}
void RaSim::order_attack(const PackedInt32Array& ids, int target_id, bool queued, bool force) {
    if (queued) {
        ra::QueuedOrder o;
        o.kind = ra::QueuedOrder::ATTACK;
        o.target = target_id;
        o.force = force;
        world_.queue_order(ids.ptr(), ids.size(), o);
        return;
    }
    world_.order_attack(ids.ptr(), ids.size(), target_id, force);
}
bool RaSim::force_attacking(int id) const { return world_.force_attacking(id); }
bool RaSim::has_move_order(int id) const { return world_.has_move_order(id); }
int RaSim::reveal_source(int owner, int cell_x, int cell_y, int radius) {
    return world_.reveal_source(owner, ra::CPos{cell_x, cell_y}, radius);
}
void RaSim::remove_reveal_source(int id) { world_.remove_reveal_source(id); }
void RaSim::set_stance(int id, int stance) { world_.set_stance(id, stance); }
int RaSim::stance(int id) const { return world_.stance(id); }
void RaSim::order_harvest(const PackedInt32Array& ids, int cell_x, int cell_y) {
    world_.order_harvest(ids.ptr(), ids.size(), {cell_x, cell_y});
}

bool RaSim::order_deliver(const PackedInt32Array& ids, int refinery_id) {
    return world_.order_deliver(ids.ptr(), ids.size(), refinery_id);
}

void RaSim::order_harvesters_return_to_base(int owner) {
    world_.order_harvesters_return_to_base(owner);
}

void RaSim::order_harvesters_resume(int owner) {
    world_.order_harvesters_resume(owner);
}

int RaSim::harvest_state(int id) const {
    const int i = world_.index_of(id);
    if (i < 0) return -1;
    return int(world_.harvest(size_t(i)).state);
}

int RaSim::harvest_bales(int id) const {
    const int i = world_.index_of(id);
    if (i < 0) return -1;
    return world_.harvest(size_t(i)).bales;
}
void RaSim::order_stop(const PackedInt32Array& ids) { world_.order_stop(ids.ptr(), ids.size()); }
void RaSim::order_scatter(const PackedInt32Array& ids) { world_.order_scatter(ids.ptr(), ids.size()); }
void RaSim::order_guard(const PackedInt32Array& ids, int target_id, bool queued) {
    if (queued) {
        ra::QueuedOrder o;
        o.kind = ra::QueuedOrder::GUARD;
        o.target = target_id;
        world_.queue_order(ids.ptr(), ids.size(), o);
        return;
    }
    world_.order_guard(ids.ptr(), ids.size(), target_id);
}
void RaSim::order_attack_cell(const PackedInt32Array& ids, int cell_x, int cell_y) {
    world_.order_attack_cell(ids.ptr(), ids.size(), ra::CPos{cell_x, cell_y});
}
bool RaSim::pause_build(int owner, int kind, bool hold) { return world_.pause_build(owner, kind, hold); }
bool RaSim::build_paused(int owner, int kind) const { return world_.build_paused(owner, kind); }
bool RaSim::build_limit_reached(int owner, int type) const { return world_.build_limit_reached(owner, type); }

int RaSim::free_landing_pads(int owner, int type) const { return world_.free_landing_pads(owner, type); }
int RaSim::build_limit(int type) const {
    return (type >= 0 && size_t(type) < world_.type_count()) ? world_.type(type).build_limit : 0;
}
int RaSim::storage_capacity(int owner) const { return int(world_.storage_capacity(owner)); }
int RaSim::resources_stored(int owner) const { return int(world_.resources_stored(owner)); }
int RaSim::cash(int owner) const { return int(world_.cash(owner)); }
int RaSim::sell_value(int id) const { return int(world_.sell_value(id)); }
bool RaSim::sell(int id) { return world_.sell(id); }
bool RaSim::toggle_repair(int id) { return world_.toggle_repair(id); }
bool RaSim::set_rally(int id, int cell_x, int cell_y) { return world_.set_rally(id, ra::CPos{cell_x, cell_y}); }
bool RaSim::set_primary(int id) { return world_.set_primary(id); }


void RaSim::enable_bot(int owner, const Dictionary& params) {
    ra::BotParams p;


    ra::World::bot_apply_personality(p, int(params.get("personality", int(ra::BOT_P_NORMAL))));
    p.strategy_interval = int(params.get("strategy_interval", p.strategy_interval));
    p.threat_map_interval = int(params.get("threat_map_interval", p.threat_map_interval));
    p.threat_map_side = int(params.get("threat_map_side", p.threat_map_side));
    p.target_value_weight = int(params.get("target_value_weight", p.target_value_weight));
    p.target_threat_weight = int(params.get("target_threat_weight", p.target_threat_weight));
    p.sp_scan_interval = int(params.get("sp_scan_interval", p.sp_scan_interval));
    p.nuke_min_attractiveness = int(params.get("nuke_min_attractiveness", p.nuke_min_attractiveness));
    p.iron_min_attractiveness = int(params.get("iron_min_attractiveness", p.iron_min_attractiveness));
    p.chrono_min_attractiveness = int(params.get("chrono_min_attractiveness", p.chrono_min_attractiveness));
    p.air_squad_size = int(params.get("air_squad_size", p.air_squad_size));
    p.raid_squad_size = int(params.get("raid_squad_size", p.raid_squad_size));
    p.raid_interval = int(params.get("raid_interval", p.raid_interval));
    p.first_attack_tick = int(params.get("first_attack_tick", p.first_attack_tick));
    p.squad_size = int(params.get("squad_size", p.squad_size));
    p.squad_size_random_bonus = int(params.get("squad_size_random_bonus", p.squad_size_random_bonus));
    p.rush_interval = int(params.get("rush_interval", p.rush_interval));
    p.attack_force_interval = int(params.get("attack_force_interval", p.attack_force_interval));
    p.min_attack_force_delay = int(params.get("min_attack_force_delay", p.min_attack_force_delay));
    p.protect_unit_scan_radius = int(params.get("protect_unit_scan_radius", p.protect_unit_scan_radius));
    p.protection_scan_radius = int(params.get("protection_scan_radius", p.protection_scan_radius));
    p.initial_harvesters = int(params.get("initial_harvesters", p.initial_harvesters));
    p.new_production_cash_threshold = int(params.get("new_production_cash_threshold", p.new_production_cash_threshold));
    p.max_base_radius = int(params.get("max_base_radius", p.max_base_radius));
    p.min_excess_power = int(params.get("min_excess_power", p.min_excess_power));
    p.max_excess_power = int(params.get("max_excess_power", p.max_excess_power));
    p.excess_power_increment = int(params.get("excess_power_increment", p.excess_power_increment));
    p.excess_power_threshold = int(params.get("excess_power_threshold", p.excess_power_threshold));
    p.initial_min_refineries = int(params.get("initial_min_refineries", p.initial_min_refineries));
    p.additional_min_refineries = int(params.get("additional_min_refineries", p.additional_min_refineries));
    p.min_construction_yards = int(params.get("min_construction_yards", p.min_construction_yards));
    static const char* TABLE_KEYS[5] = {"building_fraction", "building_limit", "building_delay", "unit_share", "unit_limit"};
    std::vector<int32_t>* tables[5] = {&p.building_fraction, &p.building_limit, &p.building_delay, &p.unit_share, &p.unit_limit};
    for (int k = 0; k < 5; ++k) {
        const PackedInt32Array v = params.get(TABLE_KEYS[k], PackedInt32Array());
        tables[k]->assign(v.ptr(), v.ptr() + v.size());
    }
    world_.enable_bot(owner, p);
}

void RaSim::set_handicap(int owner, int percent) { world_.set_handicap(owner, percent); }
int RaSim::handicap(int owner) const { return world_.handicap(owner); }
int RaSim::bot_squad_count(int owner) const { return int(world_.bot_squad_count(owner)); }

int RaSim::pick_bot_personality() { return int(world_.bot_pick_personality()); }
int RaSim::bot_personality(int owner) const { return int(world_.bot_personality(owner)); }
int RaSim::bot_plan(int owner) const { return int(world_.bot_plan(owner)); }

int RaSim::bot_stat(int owner, int which) const { return int(world_.bot_stat(owner, which)); }


void RaSim::set_crate_spawner(const Dictionary& params) {
    ra::CrateSpawnerParams p;
    p.enabled = bool(params.get("enabled", false));
    p.crate_type = int(params.get("crate_type", -1));
    p.minimum = int(params.get("minimum", p.minimum));
    p.maximum = int(params.get("maximum", p.maximum));
    p.spawn_interval = int(params.get("spawn_interval", p.spawn_interval));
    p.initial_delay = int(params.get("initial_delay", p.initial_delay));
    p.valid_ground = uint32_t(int64_t(params.get("valid_ground", 0)));
    world_.set_crate_spawner(p);
}
int RaSim::crate_count() const { return int(world_.crate_count()); }
void RaSim::order_repair(const PackedInt32Array& ids, int depot_id) { world_.order_repair(ids.ptr(), ids.size(), depot_id); }
int RaSim::win_state(int owner) const { return world_.win_state(owner); }

void RaSim::set_resource(int cell_x, int cell_y, int type, int density) {
    world_.set_resource({cell_x, cell_y}, type, density);
}
int RaSim::resource_density(int cell_x, int cell_y) const { return world_.resource_density({cell_x, cell_y}); }
int RaSim::resource_version() const { return int(world_.resource_version()); }

PackedByteArray RaSim::resource_map() const {
    const auto& types = world_.resource_types();
    const auto& dens = world_.resource_densities();
    PackedByteArray out;
    out.resize(int64_t(types.size()));
    uint8_t* p = out.ptrw();
    for (size_t i = 0; i < types.size(); ++i) p[i] = uint8_t((types[i] << 4) | (dens[i] & 0x0F));
    return out;
}

void RaSim::set_smudge_sprites(int kind, int variants, int depth) { world_.set_smudge_sprites(kind, variants, depth); }
int RaSim::smudge_version() const { return int(world_.smudge_version()); }

PackedInt32Array RaSim::smudges() const {
    std::vector<ra::SmudgeInfo> list;
    world_.smudges(list);
    PackedInt32Array out;
    out.resize(int64_t(list.size()) * 5);
    int32_t* p = out.ptrw();
    for (const ra::SmudgeInfo& s : list) {
        *p++ = s.cell.x;
        *p++ = s.cell.y;
        *p++ = s.kind;
        *p++ = s.variant;
        *p++ = s.depth;
    }
    return out;
}

int RaSim::credits(int owner) const { return int(world_.credits(owner)); }
int RaSim::earned(int owner) const { return int(world_.earned(owner)); }
void RaSim::give_credits(int owner, int amount) { world_.give_credits(owner, amount); }
void RaSim::set_resources(int owner, int amount) { world_.set_resources(owner, amount); }

bool RaSim::queue_build(int owner, int type) { return world_.queue_build(owner, type); }
bool RaSim::cancel_build(int owner, int kind, int type) { return world_.cancel_build(owner, kind, type); }

PackedInt32Array RaSim::queue_state(int owner, int kind) const {
    const auto& q = world_.queue(owner, kind);
    PackedInt32Array out;
    out.resize(int64_t(q.size()) * 7);
    int32_t* p = out.ptrw();
    for (const ra::BuildItem& it : q) {
        *p++ = it.type;
        *p++ = it.total_time > 0 ? (it.total_time - it.remaining_time) * 1000 / it.total_time : 0;
        *p++ = it.done ? 1 : 0;
        *p++ = it.remaining_cost;
        *p++ = it.paused ? 1 : 0;


        *p++ = it.total_time;
        *p++ = it.remaining_time;
    }
    return out;
}


PackedInt32Array RaSim::hidden_items(int owner, int kind) const {
    PackedInt32Array out;
    for (int t = 0; t < int(world_.type_count()); ++t) {
        if (world_.type(t).queue_kind != kind) continue;
        if (world_.item_hidden(owner, t)) out.push_back(t);
    }
    return out;
}

PackedInt32Array RaSim::buildable(int owner, int kind) const {
    std::vector<int32_t> list;
    world_.buildable(owner, kind, list);
    PackedInt32Array out;
    out.resize(int64_t(list.size()));
    for (size_t i = 0; i < list.size(); ++i) out.set(int64_t(i), list[i]);
    return out;
}

PackedByteArray RaSim::can_place(int owner, int type, int cell_x, int cell_y) const {
    std::vector<uint8_t> cells;
    const bool ok = world_.can_place(owner, type, {cell_x, cell_y}, &cells);
    PackedByteArray out;
    out.resize(int64_t(cells.size()) + 1);
    out.set(0, ok ? 1 : 0);
    for (size_t i = 0; i < cells.size(); ++i) out.set(int64_t(i) + 1, cells[i]);
    return out;
}

PackedByteArray RaSim::build_area(int owner, int adjacent) const {
    std::vector<uint8_t> cells;
    world_.buildable_area(owner, adjacent, cells);
    PackedByteArray out;
    out.resize(int64_t(cells.size()));
    for (size_t i = 0; i < cells.size(); ++i) out.set(int64_t(i), cells[i]);
    return out;
}

PackedInt32Array RaSim::pending_place(int owner, int kind) const {
    PackedInt32Array out;
    const int t = world_.pending_place_type(owner, kind);
    if (t < 0) return out;
    const ra::CPos c = world_.pending_place_origin(owner, kind);
    out.push_back(t);
    out.push_back(c.x);
    out.push_back(c.y);
    return out;
}

void RaSim::cancel_pending_place(int owner, int kind) { world_.cancel_pending_place(owner, kind); }

bool RaSim::place_building(int owner, int type, int cell_x, int cell_y) {
    return world_.place_building(owner, type, {cell_x, cell_y});
}
int RaSim::power_provided(int owner) const { return world_.power_provided(owner); }
int RaSim::power_drained(int owner) const { return world_.power_drained(owner); }
int RaSim::build_time(int type) const { return world_.build_time(type); }
int RaSim::type_cost(int type) const { return type >= 0 && type < int(world_.type_count()) ? world_.type(type).cost : 0; }

PackedInt32Array RaSim::drain_notifications(int owner) {
    world_.drain_notifications(owner < 0 ? local_player_ : owner, int_scratch_);
    PackedInt32Array out;
    out.resize(int64_t(int_scratch_.size()));
    for (size_t i = 0; i < int_scratch_.size(); ++i) out.set(int64_t(i), int_scratch_[i]);
    return out;
}

int RaSim::step() {
    const auto t0 = std::chrono::steady_clock::now();
    world_.step();
    last_step_usec_ = int(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count());
    return int(world_.tick());
}
int RaSim::tick() const { return int(world_.tick()); }
int RaSim::actor_count() const { return int(world_.actor_count()); }
int RaSim::alive_count(int owner) const { return int(world_.alive_count(owner)); }
int RaSim::moving_count() const { return int(world_.moving_count()); }
int RaSim::field_count() const { return int(world_.fields().size()); }
int RaSim::projectile_count() const { return int(world_.projectile_count()); }

void RaSim::fill_scratch(float alpha) {
    scratch_.resize(world_.actor_count());
    const int a = std::clamp(int(alpha * 1024.0f), 0, 1024);
    world_.render(a, scratch_.data(), local_player_);
    sprites_scratch_.clear();
    world_.render_sprites(a, sprites_scratch_);
}

int RaSim::frame_for(const ra::RenderActor& r) const {
    const SpriteInfo& s = sprites_[r.type];
    if (s.damaged_frame >= 0) {

        if (r.make_ticks > 0 && s.make_len > 0 && s.make_ticks > 0) {
            const int done = s.make_ticks - r.make_ticks;
            return s.make_first + std::min(s.make_len - 1, done * s.make_len / s.make_ticks);
        }
        if (s.wall) {
            const int block = (r.hp_permille < 500 && s.idle_len >= 32) ? 16 : 0;
            return s.first_frame + block + r.wall_mask;
        }


        if (r.activity == ra::ACT_ACTIVE && s.active_len > 0) {
            const int start = (r.hp_permille < 500 && s.active_damaged_start >= 0) ? s.active_damaged_start : s.active_start;
            return s.first_frame + start + int((r.anim * 40 / uint32_t(s.active_tick)) % uint32_t(s.active_len));
        }


        if (s.stage_len > 0) {
            const int64_t cap = world_.storage_capacity(r.owner);
            int stage = 0;
            if (cap > 0) {
                const int64_t stored = world_.resources_stored(r.owner);
                const int64_t num = int64_t(s.resource_stages) * s.stage_len - 1;
                stage = int(num * stored / (int64_t(s.resource_stages) * cap));
                stage = std::max(0, std::min(s.stage_len - 1, stage));
            }
            return s.first_frame + (r.hp_permille < 500 ? s.damaged_frame : 0) + stage;
        }

        const int anim = (s.idle_len > 1 && !r.unpowered) ? int((r.anim / 3) % uint32_t(s.idle_len)) : 0;
        return s.first_frame + (r.hp_permille < 500 ? s.damaged_frame : 0) + anim;
    }


    if (r.ramp != ra::RAMP_CLOSED && !s.ramp_open.empty()) {
        const std::vector<int>& seq = (r.ramp == ra::RAMP_CLOSING && !s.ramp_close.empty())
            ? s.ramp_close : s.ramp_open;
        const int len = int(seq.size());
        if (r.ramp == ra::RAMP_OPEN)
            return s.ramp_hold >= 0 ? s.ramp_hold : seq[size_t(len - 1)];
        int step = int(int64_t(r.ramp_frame) * len / std::max(1, s.ramp_ticks));
        step = std::max(0, std::min(len - 1, step));


        if (r.ramp == ra::RAMP_CLOSING && s.ramp_close.empty()) step = len - 1 - step;
        return seq[size_t(step)];
    }
    int f = facing_to_frame(r.facing, s.facings, s.classic);
    if (r.reloading && s.empty_start >= 0) {


        return s.first_frame + s.empty_start + f;
    }
    if (r.activity == ra::ACT_HARVESTING && s.harvest_len > 0) {

        const int f8 = facing_to_frame(r.facing, 8, false);
        f = s.harvest_start + f8 * s.harvest_len + int(r.anim % uint32_t(s.harvest_len));
    } else if (r.activity == ra::ACT_DOCKING && s.dock_len > 0) {

        const int a = int(r.anim);
        f = a < s.dock_len ? s.dock_start + a : s.dock_start + s.dock_len + ((a - s.dock_len) % std::max(1, s.loop_len));
    } else if (r.deploying && s.mad_len > 0 && !s.mad_frames.empty()) {


        const int f8 = facing_to_frame(r.facing, 8, false);
        const int step = (r.deploy_frame / 2) % s.mad_len;
        const size_t idx = size_t(f8) * size_t(s.mad_len) + size_t(step);
        return idx < s.mad_frames.size() ? s.mad_frames[idx] : s.first_frame + f;
    } else if (r.leaping && s.jump_len > 0 && !s.jump_frames.empty()) {


        const int len = s.jump_len;
        const int step = std::min(r.leap_frame, len - 1);
        const size_t idx = size_t(f) * size_t(len) + size_t(step);
        return idx < s.jump_frames.size() ? s.jump_frames[idx] : s.first_frame + f * len + step;
    } else if (r.firing && s.shoot_len > 0) {


        const bool alt = r.barrel_flip && s.shoot2_len > 0;
        const int len = alt ? s.shoot2_len : s.shoot_len;
        const int step = std::min(r.fire_frame, len - 1);
        const std::vector<int>& frames = alt ? s.shoot2_frames : s.shoot_frames;
        if (!frames.empty()) {


            const size_t idx = size_t(f) * size_t(len) + size_t(step);
            return idx < frames.size() ? frames[idx] : s.first_frame + f * len + step;
        }
        const int start = alt ? s.shoot2_start : s.shoot_start;
        f = start + f * len + step;
    } else if (r.idle_seq >= 0 && (r.idle_seq == 0 ? s.idle1_start : s.idle2_start) >= 0) {

        const int start = r.idle_seq == 0 ? s.idle1_start : s.idle2_start;
        f = start + int(r.idle_anim) / std::max(1, s.idle_anim_ticks);
    } else if (r.moving && s.run_len > 0) {

        f = s.run_start + f * s.run_len + int((r.anim * 2 / 5) % uint32_t(s.run_len));
    }
    return s.first_frame + f;
}


int RaSim::overlay_frame_for(const ra::RenderActor& r) const {
    const SpriteInfo& s = sprites_[r.type];
    int first = s.overlay_first, len = s.overlay_len;
    if (first < 0) return -1;
    if (r.make_ticks > 0) return -1;
    if (r.hp_permille < 500 && s.overlay_damaged_first >= 0) {
        first = s.overlay_damaged_first;
        len = s.overlay_damaged_len;
    }


    if (len <= 1 || r.door_ticks <= 0 || r.unpowered) return first;
    const int open = r.door_ticks > len ? (2 * len - r.door_ticks) : r.door_ticks;
    return first + std::clamp(open, 0, len - 1);
}


static inline int32_t eff_sprite_type(const ra::RenderActor& r) { return r.disguise_type >= 0 ? r.disguise_type : r.type; }


static constexpr int RENDER_STRIDE = 19;

PackedFloat32Array RaSim::render_state(float alpha) {
    fill_scratch(alpha);
    PackedFloat32Array out;
    out.resize(int64_t(scratch_.size()) * RENDER_STRIDE);
    float* p = out.ptrw();
    for (const ra::RenderActor& r : scratch_) {
        *p++ = float(r.id);
        *p++ = float(r.type);
        *p++ = float(r.owner);
        *p++ = float(r.x) * WORLD_TO_PX;
        *p++ = float(r.y) * WORLD_TO_PX;
        *p++ = float(r.facing);
        *p++ = float(r.moving);
        *p++ = float(r.alive);
        *p++ = float(r.hp_permille);
        *p++ = float(r.firing);
        *p++ = float(r.cargo_permille);


        *p++ = float(r.repairing | (r.selling << 1) | (r.primary << 2) | (r.visible << 3) | (r.rank << 4)
                     | (r.unpowered << 7) | (r.demolishing << 8) | (r.invulnerable << 9)
                     | (uint32_t(r.demolish_left) << 10));
        *p++ = float(r.rally.x);
        *p++ = float(r.rally.y);
        *p++ = float(r.altitude) * WORLD_TO_PX;
        *p++ = float(r.passengers);
        *p++ = float(r.cargo_max);
        *p++ = float(r.ammo);
        *p++ = float(r.ammo_max);
    }
    return out;
}


namespace {

struct float2_pair { float x, y; };


const int ZAP_STEPS[8][5] = {
    {8, 8, 4, 4, 0},  {-8, -8, -4, -4, 0}, {8, 0, 4, 4, 1},   {-8, 0, -4, 4, 1},
    {0, 8, 4, 4, 2},  {0, -8, 4, -4, 2},   {-8, 8, -4, 4, 3}, {8, -8, 4, -4, 3},
};

struct ZapRng {
    uint32_t state = 0x9e3779b9u;
    uint32_t next() {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        return state;
    }

    int pdf_length() {
        const int a = int(next() % 2048u) - 1024, b = int(next() % 2048u) - 1024;
        const int v = (a + b) / 2;
        return v < 0 ? -v : v;
    }
};

}


static float2_pair zap_line(float2_pair from, float2_pair to, int first_frame, std::vector<float>& out) {
    const float qx = -(to.y - from.y), qy = to.x - from.x;
    const float c = -(from.x * qx + from.y * qy);
    float2_pair z = from;
    for (int guard = 0; guard < 1000; ++guard) {
        const float dx = to.x - z.x, dy = to.y - z.y;
        if (dx <= 5.0f && dx >= -5.0f && dy <= 5.0f && dy >= -5.0f) break;
        const float d2 = dx * dx + dy * dy;
        int best = -1;
        float best_dev = 0.0f;
        for (int i = 0; i < 8; ++i) {
            const float nx = z.x + ZAP_STEPS[i][0], ny = z.y + ZAP_STEPS[i][1];
            const float ndx = to.x - nx, ndy = to.y - ny;
            if (ndx * ndx + ndy * ndy >= d2) continue;
            float dev = nx * qx + ny * qy + c;
            if (dev < 0.0f) dev = -dev;
            if (best < 0 || dev < best_dev) { best = i; best_dev = dev; }
        }
        if (best < 0) break;
        out.push_back(z.x + ZAP_STEPS[best][2]);
        out.push_back(z.y + ZAP_STEPS[best][3]);
        out.push_back(float(first_frame + ZAP_STEPS[best][4]));
        z.x += ZAP_STEPS[best][0];
        z.y += ZAP_STEPS[best][1];
    }
    return z;
}


static void zap_wandering(float2_pair from, float2_pair to, int first_frame, ZapRng& rng, std::vector<float>& out) {
    const float dx = to.x - from.x, dy = to.y - from.y;
    const float len = std::sqrt(dx * dx + dy * dy);
    if (len < 1.0f) return;
    const float nx = -dy / len, ny = dx / len;
    auto offset = [&](float f) {
        const float o = float(rng.pdf_length()) * len / 4096.0f;
        return float2_pair{from.x + f * dx + o * nx, from.y + f * dy + o * ny};
    };
    if (rng.next() % 2u != 0u) {
        float2_pair p1 = zap_line(from, offset(1.0f / 3.0f), first_frame, out);
        float2_pair p2 = zap_line(p1, offset(2.0f / 3.0f), first_frame, out);
        zap_line(p2, to, first_frame, out);
    } else {
        float2_pair p1 = zap_line(from, offset(0.5f), first_frame, out);
        zap_line(p1, to, first_frame, out);
    }
}


void RaSim::build_zaps() {
    zap_scratch_.clear();
    for (const ra::Zap& z : world_.zaps()) {
        const ra::Weapon& w = world_.weapon(z.weapon);
        if (w.zap_bright < 0 && w.zap_dim < 0) continue;
        const float2_pair from{float(z.from.x) * WORLD_TO_PX, float(z.from.y) * WORLD_TO_PX};
        const float2_pair to{float(z.to.x) * WORLD_TO_PX, float(z.to.y) * WORLD_TO_PX};
        ZapRng rng;
        rng.state = uint32_t(z.from.x) * 73856093u ^ uint32_t(z.to.y) * 19349663u ^ uint32_t(z.ticks) * 83492791u ^ zap_seed_;
        const size_t first = zap_scratch_.size();
        for (int n = 0; n < 2 && w.zap_dim >= 0; ++n) {
            zap_wandering(from, to, world_.effect_seq(w.zap_dim).first_frame, rng, zap_scratch_);
        }
        if (w.zap_bright >= 0) zap_wandering(from, to, world_.effect_seq(w.zap_bright).first_frame, rng, zap_scratch_);

        const EffectSprite& es = effect_sprites_[w.zap_bright >= 0 ? w.zap_bright : w.zap_dim];
        for (size_t k = first; k + 2 < zap_scratch_.size(); k += 3) {
            zap_scratch_[k] -= es.w * 0.5f;
            zap_scratch_[k + 1] -= es.h * 0.5f;
        }
    }
    ++zap_seed_;
}


void RaSim::put_effect(float*& p, const ra::RenderSprite& s) const {
    const EffectSprite& es = effect_sprites_[s.seq];
    const ra::EffectSeq& seq = world_.effect_seq(s.seq);
    int frame;
    if (!es.frames.empty()) {


        const int k = s.frame < int(es.frames.size()) ? s.frame : int(es.frames.size()) - 1;
        frame = es.frames[k < 0 ? 0 : k];
    } else if (es.facings > 1) {
        frame = seq.first_frame + facing_to_frame(s.facing, es.facings, false) * es.length + s.frame;
    } else {
        frame = seq.first_frame + s.frame;
    }
    const float alt = float(s.alt) * WORLD_TO_PX;
    const float ox = float(s.x) * WORLD_TO_PX - es.w * 0.5f + es.off_x;
    const float oy = float(s.y) * WORLD_TO_PX - es.h * 0.5f + es.off_y - alt;
    const float pal = (es.owner_palette && s.owner >= 0) ? float(s.owner) : 0.0f;
    if (es.flipx) put_instance_flipped(p, ox, oy, es.w, float(frame), pal);
    else put_instance(p, ox, oy, float(frame), pal);
}

PackedFloat32Array RaSim::render_buffer(float alpha) {
    fill_scratch(alpha);


    world_.apply_frozen(local_player_, scratch_.data(), scratch_.size());
    build_zaps();
    order_.clear();
    for (size_t i = 0; i < scratch_.size(); ++i) {


        const int32_t st = eff_sprite_type(scratch_[i]);
        if (scratch_[i].alive && scratch_[i].visible && sprites_[st].first_frame >= 0) {
            order_.push_back(int(i));
        }
    }


    auto sort_y = [&](int i) {
        return float(scratch_[i].y + sprites_[eff_sprite_type(scratch_[i])].z_offset) * WORLD_TO_PX
             + (scratch_[i].altitude > 0 ? 1.0e6f : 0.0f);
    };


    std::stable_sort(order_.begin(), order_.end(), [&](int a, int b) { return sort_y(a) < sort_y(b); });


    const uint32_t tick = world_.tick();
    int64_t instances = 0;
    for (int i : order_) {
        ++instances;
        if (scratch_[i].altitude > 0) ++instances;
        if (scratch_[i].altitude > 0 && !sprites_[scratch_[i].type].aircraft && parachute_frame_ >= 0) ++instances;
        if (sprites_[eff_sprite_type(scratch_[i])].turret_first >= 0
                && !make_running(scratch_[i], sprites_[eff_sprite_type(scratch_[i])]))
            instances += sprites_[eff_sprite_type(scratch_[i])].turret_count;
        if (overlay_frame_for(scratch_[i]) >= 0) ++instances;
        if (sprites_[scratch_[i].type].burn_first >= 0) ++instances;
        {
            const SpriteInfo& ms = sprites_[eff_sprite_type(scratch_[i])];
            if (ms.muzzle_first >= 0 && scratch_[i].firing && scratch_[i].fire_frame < ms.muzzle_len) ++instances;
        }
        instances += sprites_[scratch_[i].type].rotor_count;
    }
    for (const ra::RenderSprite& s : sprites_scratch_) {
        if (s.weapon < 0 || weapon_sprites_[s.weapon].frame >= 0) ++instances;
    }
    instances += int64_t(zap_scratch_.size() / 3);

    PackedFloat32Array out;
    out.resize(instances * 12);
    float* p = out.ptrw();

    for (int i : order_) {
        const ra::RenderActor& r = scratch_[i];
        if (r.altitude <= 0) continue;
        const SpriteInfo& s = sprites_[eff_sprite_type(r)];

        const float sx = float(r.x + 43) * WORLD_TO_PX - s.frame_w * 0.5f;
        const float sy = float(r.y + 128) * WORLD_TO_PX - s.frame_h * 0.5f;
        put_instance(p, sx, sy, float(frame_for(r)), SHADOW_ROW);
    }


    for (const ra::RenderSprite& s : sprites_scratch_) {
        if (s.weapon >= 0 || !effect_sprites_[s.seq].behind) continue;
        put_effect(p, s);
    }
    for (int i : order_) {

        ra::RenderActor r = scratch_[i];
        if (r.disguise_type >= 0) { r.type = r.disguise_type; r.owner = r.disguise_owner; }
        const SpriteInfo& s = sprites_[r.type];
        const float alt = float(r.altitude) * WORLD_TO_PX;


        const bool making = make_running(r, s);
        const float body_w = making ? s.make_w : s.frame_w;
        const float body_h = making ? s.make_h : s.frame_h;
        const float body_off_x = making ? s.make_off_x : s.off_x;
        const float body_off_y = making ? s.make_off_y : s.off_y;
        const float ox = float(r.x) * WORLD_TO_PX - body_w * 0.5f + body_off_x;
        const float oy = float(r.y) * WORLD_TO_PX - body_h * 0.5f + body_off_y - alt;


        float pal;
        if (s.cloak_color && r.cloaked && submerged_row_ > 0) {
            pal = float(submerged_row_);
        } else if (r.invulnerable) {
            pal = float(r.owner) + float(invuln_offset_);
        } else if (s.husk && husk_offset_ > 0) {
            pal = float(r.owner) + float(husk_offset_);
        } else if (r.unpowered || r.cloaked) {
            pal = float(r.owner) + float(dim_offset_);
        } else {
            pal = float(r.owner);
        }
        put_instance(p, ox, oy, float(frame_for(r)), pal);


        if (s.turret_first >= 0 && !making) {


            const float tx = float(r.x) * WORLD_TO_PX - s.turret_w * 0.5f + s.turret_off_x;
            const float ty = float(r.y) * WORLD_TO_PX - s.turret_h * 0.5f + s.turret_off_y - alt;
            const ra::WAngle bq = quantize_facing(r.facing, s.facings, s.classic);
            for (int k = 0; k < s.turret_count; ++k) {
                const ra::WAngle ang = (k == 0) ? r.turret : r.turret2;
                const int tf = s.turret_first + facing_to_frame(ang, s.turret_facings, s.turret_classic);
                float dx, dy;
                body_offset_px(bq, s.turret_ox[k], s.turret_oy[k], s.turret_oz[k], dx, dy);
                put_instance(p, tx + dx, ty + dy, float(tf), pal);
            }
        }
        const int of = overlay_frame_for(r);
        if (of >= 0) put_instance(p, ox, oy, float(of), pal);


        if (s.burn_first >= 0) {
            const int bf = s.burn_first + int((tick / uint32_t(s.burn_ticks)) % uint32_t(s.burn_len));
            put_instance(p, float(r.x) * WORLD_TO_PX - s.burn_w * 0.5f + s.burn_off_x,
                         float(r.y) * WORLD_TO_PX - s.burn_h * 0.5f + s.burn_off_y - alt, float(bf), 0.0f);
        }


        if (s.muzzle_first >= 0 && r.firing && r.fire_frame < s.muzzle_len) {
            const ra::WAngle dir = s.muzzle_turret && s.turret_first >= 0 ? r.turret : r.facing;
            float dx, dy;
            body_offset_px(dir, s.muzzle_ox, s.muzzle_oy, s.muzzle_oz, dx, dy);
            const float mx = float(r.x) * WORLD_TO_PX - s.muzzle_w * 0.5f + dx;
            const float my = float(r.y) * WORLD_TO_PX - s.muzzle_h * 0.5f - alt + dy;
            put_instance(p, mx, my, float(s.muzzle_first + r.fire_frame), 0.0f);
        }


        for (int k = 0; k < s.rotor_count; ++k) {
            const SpriteInfo::Rotor& rot = s.rotors[k];
            const bool airborne = r.altitude > 0;
            const int len = airborne ? rot.air_len : rot.ground_len;
            const int ticks = airborne ? rot.air_ticks : rot.ground_ticks;
            const int first = airborne ? rot.air_first : rot.ground_first;
            float dx, dy;
            body_offset_px(r.facing, rot.ox, rot.oy, rot.oz, dx, dy);
            const float rx = float(r.x) * WORLD_TO_PX - rot.w * 0.5f + rot.off_x + dx;
            const float ry = float(r.y) * WORLD_TO_PX - rot.h * 0.5f + rot.off_y - alt + dy;
            put_instance(p, rx, ry, float(first + int((r.anim / uint32_t(ticks)) % uint32_t(len))), pal);
        }

        if (r.altitude > 0 && !s.aircraft && parachute_frame_ >= 0) {
            put_instance(p, float(r.x) * WORLD_TO_PX - parachute_w_ * 0.5f,
                         oy - parachute_h_ * 0.5f, float(parachute_frame_), pal);
        }
    }
    for (const ra::RenderSprite& s : sprites_scratch_) {
        if (s.weapon < 0 && effect_sprites_[s.seq].behind) continue;
        const float alt = float(s.alt) * WORLD_TO_PX;
        if (s.weapon >= 0) {
            const WeaponSprite& ws = weapon_sprites_[s.weapon];
            if (ws.frame < 0) continue;


            const int wf = ws.frame + (ws.facings > 1 ? facing_to_frame(s.facing, ws.facings, ws.classic) : 0);
            put_instance(p, float(s.x) * WORLD_TO_PX - ws.w * 0.5f, float(s.y) * WORLD_TO_PX - ws.h * 0.5f - alt, float(wf), 0.0f);
        } else {
            put_effect(p, s);
        }
    }

    for (size_t k = 0; k + 2 < zap_scratch_.size(); k += 3) {
        put_instance(p, zap_scratch_[k], zap_scratch_[k + 1], zap_scratch_[k + 2], 0.0f);
    }
    return out;
}


PackedInt32Array RaSim::drain_cash_ticks() {
    world_.drain_cash_ticks(cash_scratch_);
    PackedInt32Array out;
    out.resize(int64_t(cash_scratch_.size()) * 4);
    int32_t* p = out.ptrw();
    for (const ra::CashTick& c : cash_scratch_) {
        *p++ = c.owner;
        *p++ = c.amount;
        *p++ = int32_t(float(c.pos.x) * WORLD_TO_PX);
        *p++ = int32_t(float(c.pos.y) * WORLD_TO_PX);
    }
    return out;
}


PackedInt32Array RaSim::pending_nukes() const {
    world_.pending_nukes(nuke_scratch_);
    PackedInt32Array out;
    out.resize(int64_t(nuke_scratch_.size()) * 4);
    int32_t* p = out.ptrw();
    for (const ra::NukeInfo& n : nuke_scratch_) {
        *p++ = n.owner;
        *p++ = int32_t(float(n.target.x) * WORLD_TO_PX);
        *p++ = int32_t(float(n.target.y) * WORLD_TO_PX);
        *p++ = n.ticks_left;
    }
    return out;
}


PackedInt32Array RaSim::gps_dots() const {
    world_.gps_dots(local_player_, gps_scratch_);
    PackedInt32Array out;
    out.resize(int64_t(gps_scratch_.size()) * 4);
    int32_t* p = out.ptrw();
    for (const ra::World::GpsDotInfo& d : gps_scratch_) {
        *p++ = int32_t(float(d.pos.x) * WORLD_TO_PX);
        *p++ = int32_t(float(d.pos.y) * WORLD_TO_PX);
        *p++ = d.owner;
        *p++ = d.building;
    }
    return out;
}

bool RaSim::gps_active() const { return world_.gps_granted(local_player_); }

PackedInt32Array RaSim::frozen_actors() const {
    const std::vector<ra::World::Frozen>& list = world_.frozen(local_player_);
    PackedInt32Array out;
    out.resize(int64_t(list.size()) * 6);
    int32_t* p = out.ptrw();
    for (const ra::World::Frozen& f : list) {
        const bool lit = world_.frozen_lit(local_player_, f);
        *p++ = f.id;
        *p++ = f.type;
        *p++ = f.owner;
        *p++ = int32_t(float(f.pos.x) * WORLD_TO_PX);
        *p++ = int32_t(float(f.pos.y) * WORLD_TO_PX);
        *p++ = lit ? f.hp_permille : -1;
    }
    return out;
}

PackedInt32Array RaSim::drain_sounds() {
    world_.drain_sounds(sounds_scratch_);
    PackedInt32Array out;
    out.resize(int64_t(sounds_scratch_.size()) * 3);
    int32_t* p = out.ptrw();
    for (const ra::SoundEvent& s : sounds_scratch_) {
        *p++ = s.sound;
        *p++ = int32_t(float(s.pos.x) * WORLD_TO_PX);
        *p++ = int32_t(float(s.pos.y) * WORLD_TO_PX);
    }
    return out;
}

}


int godot::RaSim::fill_multimesh(const RID& multimesh, float alpha) {
    PackedFloat32Array buf = render_buffer(alpha);
    const int n = int(buf.size() / 12);
    RenderingServer* rs = RenderingServer::get_singleton();
    const int cap = rs->multimesh_get_instance_count(multimesh);
    if (n > cap) {
        rs->multimesh_allocate_data(multimesh, std::max(n, cap * 2), RenderingServer::MULTIMESH_TRANSFORM_2D, false, true);
    }
    const float* p = buf.ptr();
    for (int i = 0; i < n; ++i, p += 12) {
        rs->multimesh_instance_set_transform_2d(multimesh, i,
            Transform2D(Vector2(p[0], p[4]), Vector2(p[1], p[5]), Vector2(p[3], p[7])));
        rs->multimesh_instance_set_custom_data(multimesh, i, Color(p[8], p[9], p[10], p[11]));
    }
    rs->multimesh_set_visible_instances(multimesh, n);
    return n;
}
