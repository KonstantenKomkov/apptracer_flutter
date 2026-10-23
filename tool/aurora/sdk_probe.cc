// Load/resolve only. This diagnostic never calls init, imports dumps or uploads.
#include <dlfcn.h>
#include <iostream>

int main(int argc, char** argv) {
  if (argc != 2 || argv[1][0] != '/') {
    std::cerr << "usage: apptracer_aurora_sdk_probe /absolute/path/libtracernative.so\n";
    return 2;
  }
  void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    std::cerr << "Aurora SDK could not be loaded: " << dlerror() << '\n';
    return 1;
  }
  const char* required[] = {
      "tracer_init", "tracer_set_platform_info2", "tracer_set_key",
      "tracer_set_userid", "tracer_log", "tracer_upload", "tracer_disable_upload",
      "tracer_aurora_collect_minidump_from_cachedir"};
  for (const char* name : required) {
    dlerror();
    void* symbol = dlsym(library, name);
    if (dlerror() || !symbol) {
      std::cerr << "Aurora SDK is missing an expected export: " << name << '\n';
      dlclose(library);
      return 1;
    }
  }
  dlclose(library);
  std::cout << "{\"native_api_resolved\":true,\"sdk_initialized\":false,"
               "\"collection_contract_supported\":false}\n";
  return 0;
}
