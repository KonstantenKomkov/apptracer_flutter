#include "worker.h"
#include "session.h"
#include <tracer.h>
#include <QJsonDocument>
#include <atomic>
#include <thread>
#include <cerrno>
#include <csignal>
#include <cstring>
#include <dlfcn.h>
#include <spawn.h>
#include <stdexcept>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;
namespace apptracer {
namespace {
constexpr int maxPacket = 64 * 1024;
constexpr int inheritedLock = 19;
template<class T> T symbol(void* sdk, const char* name) {
  auto fn = reinterpret_cast<T>(dlsym(sdk, name));
  if (!fn) throw std::runtime_error("sdk_export_missing");
  return fn;
}
bool sendPacket(int fd, const QByteArray& data) {
  ssize_t n;
  do { n = send(fd, data.constData(), data.size(), MSG_NOSIGNAL); } while (n < 0 && errno == EINTR);
  return n == data.size();
}
QByteArray receive(int fd) {
  char data[maxPacket];
  ssize_t n;
  do { n = recv(fd, data, sizeof(data), MSG_TRUNC); } while (n < 0 && errno == EINTR);
  if (n <= 0 || n > maxPacket) return {};
  return QByteArray(data, static_cast<int>(n));
}
}  // namespace

Worker::~Worker() { stop(); }

void Worker::launch(int sessionLock) {
  int pair[2];
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair) < 0)
    throw std::runtime_error("worker_socket_failed");
  struct timeval timeout{5, 0};
  posix_spawn_file_actions_t actions;
  int rc = posix_spawn_file_actions_init(&actions);
  if (rc == 0) {
    rc = posix_spawn_file_actions_adddup2(&actions, pair[1], STDIN_FILENO);
    if (!rc) rc = posix_spawn_file_actions_adddup2(&actions, sessionLock, inheritedLock);
    char executable[] = "/proc/self/exe";
    char flag[] = "--apptracer-aurora-worker";
    char* argv[] = {executable, flag, nullptr};
    if (!rc && (setsockopt(pair[0], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) ||
                setsockopt(pair[0], SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)))) rc = errno;
    if (!rc) rc = posix_spawn(&pid_, executable, &actions, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
  }
  close(pair[1]);
  if (rc) {
    close(pair[0]);
    pid_ = -1;
    throw std::runtime_error("worker_start_failed");
  }
  socket_ = pair[0];
}

QByteArray Worker::request(const QJsonObject& message) {
  const auto data = QJsonDocument(message).toJson(QJsonDocument::Compact);
  if (data.size() > maxPacket) throw std::runtime_error("worker_message_too_large");
  if (pid_ <= 0 || !sendPacket(socket_, data)) throw std::runtime_error("worker_unavailable");
  const auto reply = receive(socket_);
  if (reply == "ok" || reply == "idle" || reply == "uploading") return reply;
  throw std::runtime_error(reply.isEmpty() ? "worker_unavailable" : reply.constData());
}

void Worker::stop() {
  if (pid_ > 0) {
    // An unreaped child PID cannot be reused. The inherited session lock stays
    // held even if the runner crashes while the child is inside the vendor SDK.
    pid_t waited;
    do { waited = waitpid(pid_, nullptr, WNOHANG); } while (waited < 0 && errno == EINTR);
    if (waited == 0) {
      kill(pid_, SIGKILL);
      while (waitpid(pid_, nullptr, 0) < 0 && errno == EINTR) {}
    }
    pid_ = -1;
  }
  if (socket_ >= 0) { close(socket_); socket_ = -1; }
}

int runWorker() {
  struct ucred peer{};
  socklen_t length = sizeof(peer);
  if (prctl(PR_SET_PDEATHSIG, SIGKILL, 0L, 0L, 0L) < 0 ||
      getsockopt(STDIN_FILENO, SOL_SOCKET, SO_PEERCRED, &peer, &length) < 0 ||
      peer.uid != geteuid() || peer.pid != getppid() || getppid() <= 1) return 2;
  try {
    if (!workerHasSessionLock(inheritedLock)) return 2;
    void* sdk = dlopen(sdkPath().c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!sdk) throw std::runtime_error("sdk_load_failed");
    const auto init = symbol<decltype(&tracer_init)>(sdk, "tracer_init");
    const auto collect = symbol<decltype(&tracer_aurora_collect_minidump_from_cachedir)>(sdk, "tracer_aurora_collect_minidump_from_cachedir");
    const auto version = symbol<decltype(&tracer_set_platform_info2)>(sdk, "tracer_set_platform_info2");
    const auto upload = symbol<decltype(&tracer_upload)>(sdk, "tracer_upload");
    const auto log = symbol<decltype(&tracer_log)>(sdk, "tracer_log");
    const auto user = symbol<decltype(&tracer_set_userid)>(sdk, "tracer_set_userid");
    const auto key = symbol<decltype(&tracer_set_key)>(sdk, "tracer_set_key");
    static std::atomic_bool uploading{false};
    bool initialized = false;
    for (;;) {
      const auto data = receive(STDIN_FILENO);
      if (data.isEmpty()) return 0;
      const auto args = QJsonDocument::fromJson(data).object();
      const auto op = args.value("op").toString();
      if (op == "init" && !initialized) {
        const auto root = args.value("root").toString().toUtf8();
        const auto stage = args.value("stage").toString().toUtf8();
        if (!stage.isEmpty()) collect(stage.constData(), root.constData());
        init(args.value("token").toString().toUtf8().constData(), root.constData());
        version(args.value("version").toString().toUtf8().constData(), args.value("build").toInt());
        const auto keys = args.value("keys").toObject();
        for (auto it = keys.begin(); it != keys.end(); ++it)
          key(it.key().toUtf8().constData(), it.value().toString().toUtf8().constData());
        if (args.value("user").isString())
          user(args.value("user").toString().toUtf8().constData());
        initialized = true;
      } else if (initialized && op == "upload") {
        if (!uploading.exchange(true)) {
          std::thread([upload] { upload(); uploading.store(false); }).detach();
        }
      } else if (initialized && op == "status") {
        if (!sendPacket(STDIN_FILENO, uploading ? "uploading" : "idle")) return 1;
        continue;
      } else if (initialized && op == "log") {
        log(args.value("value").toString().toUtf8().constData());
      } else if (initialized && op == "key") {
        key(args.value("key").toString().toUtf8().constData(), args.value("value").toString().toUtf8().constData());
      } else {
        throw std::runtime_error("worker_invalid_command");
      }
      if (!sendPacket(STDIN_FILENO, "ok")) return 1;
    }
  } catch (const std::runtime_error& e) {
    sendPacket(STDIN_FILENO, e.what());
    return 1;
  }
}
}  // namespace apptracer
