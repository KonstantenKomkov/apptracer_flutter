cmake_minimum_required(VERSION 3.14)
project(apptracer_aurora_preparation LANGUAGES CXX)

set(APPTRACER_AURORA_SDK_ROOT "" CACHE PATH "Directory prepared by prepare_aurora_sdk.py")
if(NOT EXISTS "${APPTRACER_AURORA_SDK_ROOT}/include/tracer.h")
  message(FATAL_ERROR "Set APPTRACER_AURORA_SDK_ROOT to the prepared SDK")
endif()
file(SHA256 "${APPTRACER_AURORA_SDK_ROOT}/include/tracer.h" header_hash)
if(NOT header_hash STREQUAL "bf910544edc6050e6aeb99b36fdfc8801e470977c7a3c047ba13b02addfba8b7")
  message(FATAL_ERROR "Unexpected Tracer header; re-audit the SDK before upgrading")
endif()

# This object can be compiled on macOS to verify declarations, without linking
# an ELF library or claiming target ABI/runtime compatibility.
add_library(aurora_sdk_api_check OBJECT sdk_api_check.cc)
target_compile_features(aurora_sdk_api_check PRIVATE cxx_std_17)
target_compile_definitions(aurora_sdk_api_check PRIVATE AURORA)
target_include_directories(aurora_sdk_api_check PRIVATE "${APPTRACER_AURORA_SDK_ROOT}/include")

add_executable(apptracer_aurora_sdk_probe sdk_probe.cc)
target_compile_features(apptracer_aurora_sdk_probe PRIVATE cxx_std_17)
target_link_libraries(apptracer_aurora_sdk_probe PRIVATE ${CMAKE_DL_LIBS})
