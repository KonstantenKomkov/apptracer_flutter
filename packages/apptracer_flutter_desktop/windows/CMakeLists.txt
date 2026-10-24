cmake_minimum_required(VERSION 3.14)
project(apptracer_flutter_desktop LANGUAGES CXX)

if(NOT TARGET sentry-crash)
  message(FATAL_ERROR "apptracer Windows requires SENTRY_NATIVE_BACKEND=native")
endif()

# Intercept only event assembly in the healthy crash daemon. Keep the pinned
# SDK sources pristine; no handler or transport implementation is replaced.
get_target_property(daemon_sources sentry-crash SOURCES)
set(daemon_wrapper "${CMAKE_CURRENT_BINARY_DIR}/apptracer_daemon.c")
set(found_daemon FALSE)
foreach(source IN LISTS daemon_sources)
  if(source MATCHES "/sentry_crash_daemon\\.c$")
    file(TO_CMAKE_PATH "${source}" source_path)
    set(wrapper_content "#include \"sentry.h\"\n#include \"${CMAKE_CURRENT_SOURCE_DIR}/native_paths.h\"\nint apptracer_set_value(sentry_value_t, const char *, sentry_value_t);\n#define sentry_value_set_by_key apptracer_set_value\n#include \"${source_path}\"\n")
    set(old_content "")
    if(EXISTS "${daemon_wrapper}")
      file(READ "${daemon_wrapper}" old_content)
    endif()
    if(NOT old_content STREQUAL wrapper_content)
      file(WRITE "${daemon_wrapper}" "${wrapper_content}")
    endif()
    list(REMOVE_ITEM daemon_sources "${source}")
    set(found_daemon TRUE)
  endif()
endforeach()
if(NOT found_daemon)
  message(FATAL_ERROR "Unsupported Sentry daemon sources; re-audit SDK integration")
endif()
set_property(TARGET sentry-crash PROPERTY SOURCES "${daemon_sources}")
target_sources(sentry-crash PRIVATE "${daemon_wrapper}" "${CMAKE_CURRENT_SOURCE_DIR}/native_symbols.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/native_paths.c")
target_compile_features(sentry-crash PRIVATE cxx_std_17)

add_library(apptracer_windows SHARED "lifecycle.cpp")
target_compile_features(apptracer_windows PRIVATE cxx_std_17)
target_compile_definitions(apptracer_windows PRIVATE UNICODE _UNICODE)
target_link_libraries(apptracer_windows PRIVATE Rstrtmgr)
# Carry the redistributable MSVC DLLs beside the application. A compiler/IDE
# installation is not a runtime prerequisite on the target Windows machine.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
include(InstallRequiredSystemLibraries)
set(apptracer_flutter_desktop_bundled_libraries
  $<TARGET_FILE:apptracer_windows>
  $<TARGET_FILE:sentry-crash>
  $<TARGET_FILE:sentry-wer>
  ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
  PARENT_SCOPE)
