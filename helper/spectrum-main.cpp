#include "spectrum-core.h"
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>
#include <sys/prctl.h>
#include <algorithm>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <stdexcept>
#include <string>
#include <unistd.h>

// Captures the default sink's monitor and prints one line of band levels per
// frame on stdout. Levels never leave this process except through that pipe.
namespace {
using Island::Spectrum::Analyzer;

struct Capture {
    pw_main_loop *loop = nullptr;
    pw_stream *stream = nullptr;
    std::optional<Analyzer> analyzer;
    int fps = Island::Spectrum::MaxFps;
    int exitCode = 0;
    bool quitting = false;
};

// The first stop decides the exit code. Teardown after the loop has quit
// (pw_stream_destroy disconnects the stream) must not rewrite it.
void stop(Capture *capture, int exitCode) {
    if (capture->quitting) return;
    capture->quitting = true;
    capture->exitCode = exitCode;
    pw_main_loop_quit(capture->loop);
}

void onSignal(void *data, int) { stop(static_cast<Capture *>(data), 0); }

void onStateChanged(void *data, pw_stream_state, pw_stream_state state, const char *error) {
    auto *capture = static_cast<Capture *>(data);
    // Already stopping: this is the teardown's own disconnect.
    if (capture->quitting) return;
    if (state == PW_STREAM_STATE_ERROR) {
        std::fprintf(stderr, "nookisle-spectrum: stream error: %s\n", error ? error : "unknown");
        return stop(capture, 2);
    }
    // The daemon went away (a PipeWire restart) or the session manager removed
    // the node. The stream never reconnects by itself, so an idle process
    // would sit here forever drawing nothing. Exit 1, a transient failure the
    // Service retries with backoff, unlike the permanent 2.
    if (state == PW_STREAM_STATE_UNCONNECTED) {
        std::fprintf(stderr, "nookisle-spectrum: disconnected\n");
        stop(capture, 1);
    }
}

void onParamChanged(void *data, uint32_t id, const spa_pod *param) {
    auto *capture = static_cast<Capture *>(data);
    if (id != SPA_PARAM_Format || !param) return;
    spa_audio_info_raw info;
    std::memset(&info, 0, sizeof info);
    if (spa_format_audio_raw_parse(param, &info) < 0 || info.format != SPA_AUDIO_FORMAT_F32
        || info.channels != 1) {
        std::fprintf(stderr, "nookisle-spectrum: unexpected capture format\n");
        return stop(capture, 2);
    }
    try {
        capture->analyzer.emplace(double(info.rate), capture->fps);
    } catch (const std::exception &error) {
        std::fprintf(stderr, "nookisle-spectrum: %s\n", error.what());
        stop(capture, 2);
    }
}

void onProcess(void *data) {
    auto *capture = static_cast<Capture *>(data);
    pw_buffer *buffer = pw_stream_dequeue_buffer(capture->stream);
    if (!buffer) return;
    bool readerGone = false;
    const spa_buffer *raw = buffer->buffer;
    if (capture->analyzer && raw->n_datas > 0 && raw->datas[0].data && raw->datas[0].chunk) {
        const spa_data &plane = raw->datas[0];
        // Trust nothing the chunk says beyond the mapped size.
        const uint32_t offset = std::min(plane.chunk->offset, plane.maxsize);
        const uint32_t size = std::min(plane.chunk->size, plane.maxsize - offset);
        const auto *samples = reinterpret_cast<const float *>(static_cast<const char *>(plane.data) + offset);
        try {
            const auto lines = capture->analyzer->push(samples, size / sizeof(float));
            for (const auto &line : lines)
                if (std::fwrite(line.data(), 1, line.size(), stdout) != line.size()) readerGone = true;
            if (!lines.empty() && std::fflush(stdout) != 0) readerGone = true;
        } catch (const std::exception &) {
            pw_stream_queue_buffer(capture->stream, buffer);
            return stop(capture, 2);
        }
    }
    pw_stream_queue_buffer(capture->stream, buffer);
    // The reader has gone: there is no one left to draw for.
    if (readerGone) stop(capture, 0);
}

const pw_stream_events streamEvents = [] {
    pw_stream_events events;
    std::memset(&events, 0, sizeof events);
    events.version = PW_VERSION_STREAM_EVENTS;
    events.state_changed = onStateChanged;
    events.param_changed = onParamChanged;
    events.process = onProcess;
    return events;
}();

bool parseArguments(int argc, char **argv, int *fps) {
    if (argc == 1) return true;
    if (argc != 3 || std::strcmp(argv[1], "--fps") != 0) return false;
    char *end = nullptr;
    const long value = std::strtol(argv[2], &end, 10);
    if (end == argv[2] || *end || value < 1 || value > Island::Spectrum::MaxFps) return false;
    *fps = int(value);
    return true;
}
}

int main(int argc, char **argv) {
    // Before pw_init, which may log: a closed pipe must surface as a write
    // error, and the capture must never outlive the shell that started it.
    std::signal(SIGPIPE, SIG_IGN);
    const pid_t parent = getppid();
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 || getppid() != parent) return 0;

    Capture capture;
    if (!parseArguments(argc, argv, &capture.fps)) {
        std::fprintf(stderr, "usage: nookisle-spectrum [--fps 1..%d]\n", Island::Spectrum::MaxFps);
        return 2;
    }

    pw_init(&argc, &argv);
    capture.loop = pw_main_loop_new(nullptr);
    if (!capture.loop) {
        pw_deinit();
        return 2;
    }
    pw_loop *loop = pw_main_loop_get_loop(capture.loop);
    pw_loop_add_signal(loop, SIGTERM, onSignal, &capture);
    pw_loop_add_signal(loop, SIGINT, onSignal, &capture);

    // No media.role: on a capture stream it adds nothing and invites
    // role-based session policy. No target object, so it follows the default sink.
    pw_properties *properties = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_STREAM_CAPTURE_SINK, "true",
        PW_KEY_NODE_NAME, "nookisle-spectrum",
        PW_KEY_NODE_DESCRIPTION, "Nookisle spectrum",
        PW_KEY_NODE_PASSIVE, "true",
        PW_KEY_NODE_LATENCY, "1024/48000",
        nullptr);
    capture.stream = pw_stream_new_simple(loop, "nookisle-spectrum", properties, &streamEvents, &capture);
    if (!capture.stream) {
        pw_main_loop_destroy(capture.loop);
        pw_deinit();
        return 2;
    }

    // Built field by field: the SPA initializer macros are C99 compound
    // literals. The rate is left open, so the graph rate is kept and the
    // adapter downmixes to mono.
    uint8_t podBuffer[1024];
    spa_pod_builder builder;
    spa_pod_builder_init(&builder, podBuffer, sizeof podBuffer);
    spa_audio_info_raw format;
    std::memset(&format, 0, sizeof format);
    format.format = SPA_AUDIO_FORMAT_F32;
    format.channels = 1;
    format.position[0] = SPA_AUDIO_CHANNEL_MONO;
    const spa_pod *params[1] = {spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat, &format)};

    // Never RT_PROCESS: process() writes to a pipe that may block, so it runs
    // on this main loop rather than the realtime thread.
    const auto flags = pw_stream_flags(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS);
    if (!params[0] || pw_stream_connect(capture.stream, PW_DIRECTION_INPUT, PW_ID_ANY, flags, params, 1) < 0) {
        std::fprintf(stderr, "nookisle-spectrum: cannot connect the capture stream\n");
        capture.exitCode = 2;
    } else {
        // A stop during connect must not be lost: a quit issued before
        // pw_main_loop_run starts is overwritten when the loop starts.
        if (!capture.quitting) pw_main_loop_run(capture.loop);
    }

    pw_stream_destroy(capture.stream);
    pw_main_loop_destroy(capture.loop);
    pw_deinit();
    return capture.exitCode;
}
