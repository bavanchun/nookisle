#include <nlohmann/json.hpp>
#include <openssl/sha.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <cerrno>
#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

namespace {
constexpr size_t FrameLimit = 65536, QueueLimit = 131072;
using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;
struct Descriptor {
    int value;
    explicit Descriptor(int fd) : value(fd) {}
    ~Descriptor() { if (value >= 0) ::close(value); }
    Descriptor(const Descriptor &) = delete;
    Descriptor &operator=(const Descriptor &) = delete;
};
Json parseObject(std::string_view bytes) {
    if (bytes.empty() || bytes.size() > FrameLimit) return {};
    struct DepthLimit {};
    try {
        auto result = Json::parse(bytes.begin(), bytes.end(), [](int depth, Json::parse_event_t event, Json &) {
            // Returning false would silently discard a subtree. Throw to reject
            // the complete frame before allocating beyond the protocol depth.
            if (depth >= 32 && (event == Json::parse_event_t::object_start || event == Json::parse_event_t::array_start))
                throw DepthLimit{};
            return true;
        }, false);
        return result.is_object() ? result : Json();
    } catch (const DepthLimit &) { return {}; }
}
std::string field(const Json &object, const char *name) {
    const auto value = object.find(name);
    return value != object.end() && value->is_string() ? value->get<std::string>() : std::string();
}
bool versionOne(const Json &object) {
    const auto version = object.find("protocolVersion");
    return version != object.end() && version->is_number() && version->get<double>() == 1.0;
}
std::string compact(const Json &object) { return object.dump(); }
bool privateDirectory(const std::string &path) {
    struct stat info {};
    return !path.empty() && !lstat(path.c_str(), &info) && S_ISDIR(info.st_mode)
        && info.st_uid == getuid() && !(info.st_mode & 0077);
}
Json privateJson(const std::string &path) {
    Descriptor file(::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
    struct stat info {};
    if (file.value < 0 || fstat(file.value, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid()
        || (info.st_mode & 0077) || info.st_size < 1 || info.st_size > 4096) return {};
    std::string bytes;
    std::array<char, 4097> buffer {};
    while (bytes.size() <= 4096) {
        const auto count = ::read(file.value, buffer.data(), buffer.size() - bytes.size());
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) return {};
        if (!count) return parseObject(bytes);
        bytes.append(buffer.data(), static_cast<size_t>(count));
    }
    return {};
}
std::string environment(const char *name) {
    const char *value = std::getenv(name);
    return value ? value : "";
}
std::string configDirectory() {
    auto config = environment("XDG_CONFIG_HOME");
    if (!config.empty() && config.front() == '/') return config;
    auto home = environment("HOME");
    if (home.empty()) { if (const auto *entry = getpwuid(getuid())) home = entry->pw_dir; }
    return home.empty() || home.front() != '/' ? "" : home + "/.config";
}
bool nonblocking(int fd) {
    const int flags = fcntl(fd, F_GETFL);
    return flags >= 0 && !fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}
bool append(std::string &queue, std::string_view bytes) {
    if (bytes.size() > QueueLimit - queue.size()) return false;
    queue.append(bytes); return true;
}
bool flush(int fd, std::string &queue) {
    while (!queue.empty()) {
        const auto count = ::write(fd, queue.data(), queue.size());
        if (count < 0) {
            if (errno == EINTR) continue;
            return errno == EAGAIN || errno == EWOULDBLOCK;
        }
        if (!count) return false;
        queue.erase(0, static_cast<size_t>(count));
    }
    return true;
}
class NativeHost {
public:
    int run(const std::string &path, const std::string &secret) {
        sockaddr_un address {}; address.sun_family = AF_UNIX;
        if (path.size() >= sizeof address.sun_path) return 1;
        std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
        Descriptor socket(::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0));
        if (socket.value < 0) return 1;
        const auto deadline = Clock::now() + std::chrono::seconds(3);
        bool connecting = ::connect(socket.value, reinterpret_cast<sockaddr *>(&address), sizeof address) != 0;
        if (connecting && errno != EINPROGRESS) return 1;
        bool authenticated = false;
        while (true) {
            if (!connecting && !authenticated) {
                ucred credentials {}; socklen_t size = sizeof credentials;
                if (getsockopt(socket.value, SOL_SOCKET, SO_PEERCRED, &credentials, &size) || credentials.uid != getuid()) return 1;
                const Json auth{{"protocolVersion", 1}, {"type", "bridgeAuth"}, {"secret", secret}};
                if (!append(toSocket_, compact(auth) + '\n')) return 1;
                authenticated = true;
            }
            if (!flush(STDOUT_FILENO, toChrome_) || (!connecting && !flush(socket.value, toSocket_))) return 1;
            int timeout = -1;
            if (!ready_) {
                const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
                if (remaining <= 0) return 1;
                timeout = static_cast<int>(remaining);
            }
            pollfd descriptors[] = {{STDIN_FILENO, POLLIN, 0},
                {STDOUT_FILENO, static_cast<short>(toChrome_.empty() ? 0 : POLLOUT), 0},
                {socket.value, static_cast<short>(POLLIN | ((connecting || !toSocket_.empty()) ? POLLOUT : 0)), 0}};
            const int count = ::poll(descriptors, 3, timeout);
            if (count < 0) { if (errno == EINTR) continue; return 1; }
            if (!count) return 1;
            if ((descriptors[0].revents | descriptors[1].revents | descriptors[2].revents) & POLLNVAL) return 1;
            if (descriptors[1].revents & (POLLERR | POLLHUP)) return 1;
            if (descriptors[0].revents & (POLLIN | POLLHUP | POLLERR)) {
                const int result = readChrome();
                if (result >= 0) return result;
            }
            if (connecting && descriptors[2].revents) {
                int error = 0; socklen_t length = sizeof error;
                if (getsockopt(socket.value, SOL_SOCKET, SO_ERROR, &error, &length) || error) return 1;
                connecting = false;
                continue;
            }
            if (descriptors[2].revents & (POLLIN | POLLHUP | POLLERR)) {
                if (!readSocket(socket.value)) return 1;
            }
        }
    }
private:
    std::string chromeInput_, socketInput_, toSocket_, toChrome_;
    bool ready_ = false;
    int readChrome() {
        std::array<char, 8192> buffer {};
        const auto count = ::read(STDIN_FILENO, buffer.data(), buffer.size());
        if (!count) return chromeInput_.empty() ? 0 : 1;
        if (count < 0) return errno == EINTR || errno == EAGAIN ? -1 : 1;
        chromeInput_.append(buffer.data(), static_cast<size_t>(count));
        while (chromeInput_.size() >= 4) {
            uint32_t length; std::memcpy(&length, chromeInput_.data(), sizeof length);
            if (!length || length > FrameLimit) return 1;
            if (chromeInput_.size() < length + 4) break;
            auto object = parseObject(std::string_view(chromeInput_).substr(4, length));
            if (!ready_ || !object.is_object()) return 1;
            auto bytes = compact(object) + '\n';
            if (bytes.size() > FrameLimit || !append(toSocket_, bytes)) return 1;
            chromeInput_.erase(0, length + 4);
        }
        return -1;
    }
    bool readSocket(int fd) {
        std::array<char, 8192> buffer {};
        const auto count = ::read(fd, buffer.data(), buffer.size());
        if (count < 0) return errno == EINTR || errno == EAGAIN;
        if (!count) return false;
        socketInput_.append(buffer.data(), static_cast<size_t>(count));
        while (true) {
            const auto end = socketInput_.find('\n');
            if (end == std::string::npos) return socketInput_.size() < FrameLimit;
            if (end + 1 > FrameLimit) return false;
            auto object = parseObject(std::string_view(socketInput_).substr(0, end));
            if (!object.is_object()) return false;
            if (!ready_) {
                if (field(object, "type") != "bridgeHello" || !versionOne(object)
                    || field(object, "bridgeSession").empty() || field(object, "busEpoch").empty()) return false;
                ready_ = true;
            }
            const auto bytes = compact(object);
            const uint32_t length = bytes.size();
            if (bytes.size() > FrameLimit || toChrome_.size() + 4 + bytes.size() > QueueLimit) return false;
            toChrome_.append(reinterpret_cast<const char *>(&length), sizeof length); toChrome_ += bytes;
            socketInput_.erase(0, end + 1);
        }
    }
};
int execute(int argc, char **argv) {
    if (argc < 2) return 1;
    const std::string origin = argv[1], prefix = "chrome-extension://";
    if (origin.size() != prefix.size() + 33 || !origin.starts_with(prefix) || origin.back() != '/') return 1;
    if (!std::all_of(origin.begin() + static_cast<ptrdiff_t>(prefix.size()), origin.end() - 1,
        [](char ch) { return ch >= 'a' && ch <= 'p'; })) return 1;
    const auto configPath = configDirectory();
    if (configPath.empty()) return 1;
    auto config = privateJson(configPath + "/nookisle/native-host.json");
    if (field(config, "allowedOrigin") != origin) return 1;
    const auto runtime = environment("XDG_RUNTIME_DIR"), address = environment("DBUS_SESSION_BUS_ADDRESS");
    if (address.empty() || !privateDirectory(runtime)) return 1;
    std::array<unsigned char, SHA256_DIGEST_LENGTH> digest {};
    if (!SHA256(reinterpret_cast<const unsigned char *>(address.data()), address.size(), digest.data())) return 1;
    constexpr char hex[] = "0123456789abcdef";
    std::string hash;
    for (size_t i = 0; i < 8; ++i) { hash += hex[digest[i] >> 4]; hash += hex[digest[i] & 15]; }
    const auto directory = runtime + "/nookisle-" + hash;
    if (!privateDirectory(directory)) return 1;
    auto auth = privateJson(directory + "/browser.json");
    const auto socketPath = field(auth, "socket"), secret = field(auth, "secret");
    if (!versionOne(auth) || socketPath != directory + "/browser.sock" || secret.size() < 16 || secret.size() > 128) return 1;
    signal(SIGPIPE, SIG_IGN);
    if (!nonblocking(STDIN_FILENO) || !nonblocking(STDOUT_FILENO)) return 1;
    return NativeHost().run(socketPath, secret);
}
}
int main(int argc, char **argv) {
    try { return execute(argc, argv); } catch (...) { return 1; }
}
