#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include "bridge_tbl.h"
#include "vk_bridge.h"
#include "utils.h"

// Vulkan rendering bypasses the bridge: Minecraft owns the swapchain and queue
// submits directly via libMoltenVK. These stubs exist so pojavInitOpenGL() can
// install a non-NULL bridge table and avoid crashes if any GL-shaped GLFW call
// reaches the dispatcher before/after the Vulkan path takes over.

static vk_render_window_t g_dummy;

static bool vk_init(void) {
    void* h = dlopen("@rpath/" RENDERER_NAME_VULKAN, RTLD_GLOBAL);
    if (!h) {
        NSLog(@"VKBridge: dlopen %s failed: %s", RENDERER_NAME_VULKAN, dlerror());
        return false;
    }
    return true;
}

static vk_render_window_t* vk_init_context(vk_render_window_t* share) {
    return &g_dummy;
}

static void vk_make_current(vk_render_window_t* bundle) {}
static void vk_swap_buffers(void) {}
static void vk_swap_interval(int interval) {}
static void vk_terminate(void) {}

void set_vk_bridge_tbl(void) {
    br_init = vk_init;
    br_init_context = (br_init_context_t) vk_init_context;
    br_make_current = (br_make_current_t) vk_make_current;
    br_swap_buffers = vk_swap_buffers;
    br_swap_interval = vk_swap_interval;
    br_terminate = vk_terminate;
}
