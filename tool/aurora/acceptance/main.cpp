// Entry point for the isolated acceptance RPM, which uses the example's app ID.
#include "generated_plugin_registrant.h"
#include <tracer.h>

#include <chrono>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>

int main(int argc, char** argv) {
  if (argc != 2 || std::strcmp(argv[1], "--apptracer-test-worker") != 0) {
    aurora::FlutterApp app(argc, argv);
    return app.exec();
  }

  std::string mode;
  std::string token;
  const char* home = std::getenv("HOME");
  if (!home || !std::getline(std::cin, mode) || !std::getline(std::cin, token) ||
      token.empty() || (mode != "arm" && mode != "upload")) {
    return 2;
  }
  const std::filesystem::path base(home);
  const auto root = base / ".local/share/ru.apptracer/apptracer_flutter_aurora_example/explicit-test";
  const auto cache = base / ".cache/ru.apptracer/apptracer_flutter_aurora_example";
  const auto marker = root / "armed-by-fixture";
  std::filesystem::create_directories(root);
  if (mode == "upload") {
    // A test operator explicitly requests both runs on a fresh example installation.
    if (!std::filesystem::exists(cache / "minidump") ||
        !std::filesystem::remove(marker)) return 3;
    tracer_aurora_collect_minidump_from_cachedir(cache.c_str(), root.c_str());
  }
  tracer_init(token.c_str(), root.c_str());
  tracer_set_platform_info2("2.0.0", 201);
  if (mode == "upload") {
    tracer_upload();
  } else {
    tracer_set_key("aurora_runner", "flutter-sandbox");
    tracer_log(u8"Контрольное падение Flutter runner в песочнице Авроры");
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    std::ofstream output(marker);
    output << "arm";
    output.close();
    if (!output) return 4;
  }
  return 0;
}
