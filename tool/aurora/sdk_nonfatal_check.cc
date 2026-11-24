// Run only in a fresh test process. No credentials, crash injection or upload.
#include <tracer.h>

#include <filesystem>
#include <iostream>

int main(int argc, char** argv) {
  if (argc != 2 || !std::filesystem::path(argv[1]).is_absolute() ||
      std::filesystem::exists(argv[1])) {
    std::cerr << "usage: sdk_nonfatal_check /absolute/path/to/new/session-dir\n";
    return 2;
  }
  const bool before = tracer_supports_arbitrary_dump();
  tracer_init("local-capability-check", argv[1]);
  tracer_set_platform_info2("2.0.0", 200);
  tracer_install_crash_handler();
  const bool after = tracer_supports_arbitrary_dump();
  tracer_report_nonfatal_from_here();

  unsigned dumps = 0;
  for (const auto& entry : std::filesystem::recursive_directory_iterator(argv[1])) {
    if (entry.is_regular_file() && entry.path().extension() == ".dmp") ++dumps;
  }
  std::cout << std::boolalpha << "{\"supported_before_init\":" << before
            << ",\"supported_after_init\":" << after
            << ",\"dump_files\":" << dumps << "}\n";
}
