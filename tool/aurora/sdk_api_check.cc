// Compile against the pinned vendor header; no SDK function is invoked here.
#include <tracer.h>
#include <type_traits>

static_assert(std::is_same<tracer_path_char, char>::value, "Aurora paths use char");
static_assert(std::is_same<decltype(&tracer_init),
                          void (*)(const char*, const char*)>::value, "init ABI");
static_assert(std::is_same<decltype(&tracer_set_platform_info2),
                          void (*)(const char*, int)>::value, "version ABI");
static_assert(std::is_same<decltype(&tracer_aurora_collect_minidump_from_cachedir),
                          void (*)(const char*, const char*)>::value, "import ABI");
static_assert(std::is_same<decltype(&tracer_set_key),
                          void (*)(const char*, const char*)>::value, "key ABI");
static_assert(std::is_same<decltype(&tracer_set_userid),
                          void (*)(const char*)>::value, "user ABI");
static_assert(std::is_same<decltype(&tracer_log),
                          void (*)(const char*)>::value, "log ABI");
static_assert(std::is_same<decltype(&tracer_upload), void (*)()>::value, "upload ABI");
static_assert(std::is_same<decltype(&tracer_disable_upload), void (*)()>::value,
              "disable upload is not shutdown or purge");
