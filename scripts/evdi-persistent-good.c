#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include "evdi_lib.h"
#include <sys/select.h>

static volatile sig_atomic_t display_on = 1;
static volatile sig_atomic_t requested_buffer = -1;
static evdi_handle global_handle = NULL;

static void request_next_buffer(void);


#define WIDTH  2560
#define HEIGHT 1440
#define BPP    4
#define STRIDE (WIDTH * BPP)
#define SIZE   ((size_t)STRIDE * HEIGHT)
#define BUFFERS 2

static volatile sig_atomic_t running = 1;

static void update_ready_handler(int buffer_id, void *user_data)
{
    evdi_handle handle = (evdi_handle)user_data;

    if (requested_buffer != buffer_id) {
        printf("Unexpected update: buffer=%d requested=%d\n",
               buffer_id, requested_buffer);
        return;
    }

    struct evdi_rect rects[256];
    int num_rects = 256;

    printf("Update ready: buffer=%d -- grabbing pixels...\n", buffer_id);

    evdi_grab_pixels(handle, rects, &num_rects);

    printf("Grab complete: buffer=%d rects=%d\n", buffer_id, num_rects);

    requested_buffer = -1;
    request_next_buffer();
}

static void dpms_handler(int dpms_mode, void *user_data)
{
    (void)user_data;
    display_on = (dpms_mode == 0);
    printf("DPMS: %s (mode=%d)\n",
           display_on ? "ON" : "OFF", dpms_mode);

    if (!display_on)
        requested_buffer = -1;
    else
        request_next_buffer();
}

static void request_next_buffer(void)
{
    if (!global_handle || !display_on || requested_buffer >= 0)
        return;

    static int next_buffer = 0;

    requested_buffer = next_buffer;
    next_buffer = (next_buffer + 1) % BUFFERS;

    bool ready = evdi_request_update(global_handle, requested_buffer);

    if (ready) {
        int buffer_id = requested_buffer;
        struct evdi_rect rects[256];
        int num_rects = 256;

        printf("Update ready immediately: buffer=%d -- grabbing pixels...\n",
               buffer_id);

        evdi_grab_pixels(global_handle, rects, &num_rects);

        printf("Grab complete: buffer=%d rects=%d\n",
               buffer_id, num_rects);

        requested_buffer = -1;
        request_next_buffer();
    }
}

static void stop_handler(int sig)
{
    (void)sig;
    running = 0;
}

int main(void)
{
    const char *edid_path = "/usr/lib/firmware/edid/vkms-final-30modes-4k240.bin";

    signal(SIGINT, stop_handler);
    signal(SIGTERM, stop_handler);

    printf("Searching for EVDI device...\n");

    evdi_handle handle = NULL;

    for (int card = 0; card < 16; card++) {
        char path[64];
        snprintf(path, sizeof(path), "/dev/dri/card%d", card);

        if (access(path, R_OK | W_OK) != 0)
            continue;

        handle = evdi_open(card);

        if (handle) {
            printf("Found EVDI card%d\n", card);
            break;
        }
    }

    if (!handle) {
        fprintf(stderr, "Failed to open EVDI device.\n");
        return 1;
    }

    FILE *f = fopen(edid_path, "rb");
    if (!f) {
        perror("fopen EDID");
        return 1;
    }

    unsigned char *edid = malloc(4096);
    if (!edid) {
        fprintf(stderr, "EDID allocation failed.\n");
        fclose(f);
        return 1;
    }

    size_t edid_len = fread(edid, 1, 4096, f);
    fclose(f);

    if (edid_len == 0) {
        fprintf(stderr, "Failed to read EDID.\n");
        free(edid);
        return 1;
    }

    printf("Loaded EDID: %zu bytes\n", edid_len);

    evdi_connect(handle, edid, edid_len, 0);

    printf("EVDI connected with custom EDID.\n");
    printf("Creating %d persistent buffers...\n", BUFFERS);

    void *buffers[BUFFERS] = {0};

    for (int i = 0; i < BUFFERS; i++) {
        buffers[i] = calloc(1, SIZE);

        if (!buffers[i]) {
            fprintf(stderr, "Buffer %d allocation failed.\n", i);
            running = 0;
            break;
        }

        struct evdi_buffer buffer;
        memset(&buffer, 0, sizeof(buffer));

        buffer.id = i;
        buffer.width = WIDTH;
        buffer.height = HEIGHT;
        buffer.stride = STRIDE;
        buffer.rect_count = 0;
        buffer.buffer = buffers[i];

        evdi_register_buffer(handle, buffer);

        printf("Registered buffer %d: %zu bytes, stride %d\n",
               i, SIZE, STRIDE);
    }

    free(edid);

    if (!running) {
        for (int i = 0; i < BUFFERS; i++)
            free(buffers[i]);
        return 1;
    }

    evdi_selectable event_fd = evdi_get_event_ready(handle);
    global_handle = handle;

    printf("Event FD: %d\n", event_fd);
    printf("Persistent EVDI display is running.\n");
    printf("Press Ctrl+C to stop.\n");

    request_next_buffer();

    while (running) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(event_fd, &rfds);

        int ret = select(event_fd + 1, &rfds, NULL, NULL, NULL);

        if (ret < 0) {
            if (running)
                perror("select");
            break;
        }

        if (FD_ISSET(event_fd, &rfds)) {
            struct evdi_event_context context;
            memset(&context, 0, sizeof(context));
            context.dpms_handler = dpms_handler;
            context.update_ready_handler = update_ready_handler;
            context.user_data = handle;

            evdi_handle_events(handle, &context);
        }
    }

    printf("Stopping EVDI display...\n");

    for (int i = 0; i < BUFFERS; i++)
        free(buffers[i]);

    return 0;
}
