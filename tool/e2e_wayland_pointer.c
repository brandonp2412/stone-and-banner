// Headless E2E input helper. Sends a pointer click only to WAYLAND_DISPLAY.
// Requires a wlroots compositor advertising zwlr_virtual_pointer_manager_v1.
#include <wayland-client.h>
#include <linux/input-event-codes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const struct wl_interface pointerInterface;
static const struct wl_interface *pointerTypes[] = {&wl_seat_interface, &pointerInterface};
static const struct wl_interface *pointerOutputTypes[] = {
    &wl_seat_interface, &wl_output_interface, &pointerInterface,
};
static const struct wl_message managerRequests[] = {
    {"create_virtual_pointer", "?on", pointerTypes},
    {"destroy", "", NULL},
    {"create_virtual_pointer_with_output", "2?oon", pointerOutputTypes},
};
static const struct wl_interface managerInterface = {
    "zwlr_virtual_pointer_manager_v1", 2, 3, managerRequests, 0, NULL,
};
static const struct wl_message pointerRequests[] = {
    {"motion", "uff", NULL},
    {"motion_absolute", "uuuuu", NULL},
    {"button", "uuu", NULL},
    {"axis", "uuf", NULL},
    {"frame", "", NULL},
};
static const struct wl_interface pointerInterface = {
    "zwlr_virtual_pointer_v1", 1, 5, pointerRequests, 0, NULL,
};

struct Context {
    struct wl_registry *registry;
    struct wl_proxy *manager;
    struct wl_seat *seat;
    struct wl_output *output;
};

static void onGlobal(void *opaque, struct wl_registry *registry,
                     uint32_t name, const char *interface, uint32_t version) {
    struct Context *ctx = opaque;
    if (strcmp(interface, wl_seat_interface.name) == 0) {
        ctx->seat = wl_registry_bind(registry, name, &wl_seat_interface, version < 5 ? version : 5);
    }
    if (strcmp(interface, wl_output_interface.name) == 0) {
        ctx->output = wl_registry_bind(registry, name, &wl_output_interface, version < 4 ? version : 4);
    }
    if (strcmp(interface, managerInterface.name) == 0) {
        ctx->manager = (struct wl_proxy *)wl_registry_bind(
            registry, name, &managerInterface, version < 2 ? version : 2);
    }
}

static void onGlobalRemove(void *opaque, struct wl_registry *registry, uint32_t name) {
    (void)opaque; (void)registry; (void)name;
}

int main(int argc, char **argv) {
    if (argc != 5 && argc != 6) {
        fprintf(stderr, "usage: %s X Y WIDTH HEIGHT [SCROLL_DY]\n", argv[0]);
        return 2;
    }
    uint32_t x = (uint32_t)strtoul(argv[1], NULL, 10);
    uint32_t y = (uint32_t)strtoul(argv[2], NULL, 10);
    uint32_t width = (uint32_t)strtoul(argv[3], NULL, 10);
    uint32_t height = (uint32_t)strtoul(argv[4], NULL, 10);
    if (!width || !height || x >= width || y >= height) return 2;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { perror("wl_display_connect"); return 1; }
    struct Context ctx = {0};
    ctx.registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = {onGlobal, onGlobalRemove};
    wl_registry_add_listener(ctx.registry, &listener, &ctx);
    wl_display_roundtrip(display);
    if (!ctx.manager || !ctx.seat || !ctx.output) {
        fprintf(stderr, "This compositor does not advertise virtual pointer; no click sent.\n");
        wl_display_disconnect(display);
        return 3;
    }
    struct wl_proxy *pointer = wl_proxy_marshal_constructor_versioned(
        ctx.manager, 2, &pointerInterface, 1, ctx.seat, ctx.output, NULL);
    if (!pointer) return 4;
    wl_display_roundtrip(display);
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    uint32_t ms = (uint32_t)(now.tv_sec * 1000u + now.tv_nsec / 1000000u);
    wl_proxy_marshal_flags(pointer, 1, NULL, 1, 0, ms, x, y, width, height);
    wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0);
    wl_display_flush(display);
    usleep(150000); // Let the compositor deliver pointer enter before clicking.
    if (argc == 6) {
        wl_proxy_marshal_flags(pointer, 3, NULL, 1, 0, ms + 150u, 0u,
                               wl_fixed_from_double(atof(argv[5])));
        wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0);
        wl_display_flush(display);
    } else {
        wl_proxy_marshal_flags(pointer, 2, NULL, 1, 0, ms + 150u, (uint32_t)BTN_LEFT, 1u);
        wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0);
        wl_display_flush(display);
        usleep(150000);
        wl_proxy_marshal_flags(pointer, 2, NULL, 1, 0, ms + 300u, (uint32_t)BTN_LEFT, 0u);
        wl_proxy_marshal_flags(pointer, 4, NULL, 1, 0);
        wl_display_flush(display);
    }
    usleep(250000);
    wl_proxy_destroy(pointer);
    wl_proxy_destroy(ctx.manager);
    wl_registry_destroy(ctx.registry);
    wl_display_disconnect(display);
    return 0;
}
