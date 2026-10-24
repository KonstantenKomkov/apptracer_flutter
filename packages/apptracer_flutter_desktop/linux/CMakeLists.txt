cmake_minimum_required(VERSION 3.22)
project(apptracer_flutter_desktop LANGUAGES CXX)

# Flutter configures FFI plugins after method-channel plugins, so the pinned
# sentry_flutter dependency has already declared its native crash daemon.
if(NOT TARGET sentry-crash)
  message(FATAL_ERROR "apptracer Linux requires SENTRY_NATIVE_BACKEND=native")
endif()

# Enrich frames in the healthy daemon process, after the SDK assembles its
# event and before serialization. This GNU linker hook is tied to SDK 0.16.6.
# The app's signal handler and the SDK's transport/queue remain unchanged.
target_sources(sentry-crash PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/native_symbols.cc")
target_compile_features(sentry-crash PRIVATE cxx_std_17)
target_link_options(sentry-crash PRIVATE "-Wl,--wrap=sentry_value_set_by_key")
set(apptracer_flutter_desktop_bundled_libraries "" PARENT_SCOPE)
