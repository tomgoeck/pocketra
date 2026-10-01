#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "content/gd/aud_stream.h"
#include "content/gd/ra_content.h"
#include "content/gd/vqa_player.h"
#include "ra_sim.h"

using namespace godot;

void initialize_rasim(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(RaSim);


    GDREGISTER_CLASS(RaContent);
    GDREGISTER_CLASS(AudStream);
    GDREGISTER_CLASS(AudStreamPlayback);
    GDREGISTER_CLASS(VqaPlayer);
}

void uninitialize_rasim(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT rasim_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
                                              GDExtensionClassLibraryPtr p_library,
                                              GDExtensionInitialization* r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_rasim);
    init_obj.register_terminator(uninitialize_rasim);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
