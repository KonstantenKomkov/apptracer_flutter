// Acceptance RPM only. Exercise the real SDK transport with an unavailable
// network or a local TLS peer that withholds its reply until consent is revoked.
#include "generated_plugin_registrant.h"
#include <apptracer_flutter_aurora/plugin.h>
#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {
int testPort = 0;
std::filesystem::path attempt;
}

extern "C" __attribute__((visibility("default"))) int connect(
    int fd, const sockaddr* address, socklen_t size) {
  if (testPort != 0 && address &&
      (address->sa_family == AF_INET || address->sa_family == AF_INET6)) {
    if (testPort == -1) {
      std::ofstream(attempt).put('1');
      errno = ENETUNREACH;
      return -1;
    }
    int type = 0;
    socklen_t length = sizeof(type);
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &length) == 0 && type == SOCK_STREAM) {
      if (address->sa_family != AF_INET) { errno = ENETUNREACH; return -1; }
      sockaddr_in loop{};
      loop.sin_family = AF_INET;
      loop.sin_port = htons(testPort);
      loop.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      return syscall(SYS_connect, fd, &loop, sizeof(loop));
    }
  }
  return syscall(SYS_connect, fd, address, size);
}

// The faulting instruction is in the installed runner, for symbol verification.
extern "C" __attribute__((visibility("default"), noinline)) void AuroraAcceptanceCrash() {
  __builtin_trap();
}

int main(int argc, char** argv) {
  if (argc == 2 && !std::strcmp(argv[1], "--apptracer-aurora-worker")) {
    const auto base = std::filesystem::path(std::getenv("HOME")) /
        ".local/share/ru.apptracer/apptracer_flutter_aurora_example";
    int port = 0;
    if (std::ifstream(base / "fixture-network") >> port && port >= -1 && port <= 65535) {
      testPort = port;
      attempt = base / "fixture-attempt";
    }
  }
  ApptracerFlutterAuroraPrepareRunner(argc, argv);
  aurora::FlutterApp app(argc, argv);
  return app.exec();
}
