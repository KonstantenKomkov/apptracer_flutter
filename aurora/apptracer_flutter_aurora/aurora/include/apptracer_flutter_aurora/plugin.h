#pragma once

#include <flutter_aurora/engine_api.h>

#ifdef APPTRACER_AURORA_IMPL
#define APPTRACER_AURORA_EXPORT __attribute__((visibility("default")))
#else
#define APPTRACER_AURORA_EXPORT
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// Call before constructing FlutterApp to enable consent-controlled native collection.
APPTRACER_AURORA_EXPORT void ApptracerFlutterAuroraPrepareRunner(int argc, char** argv);

APPTRACER_AURORA_EXPORT void ApptracerFlutterAuroraRegister(
    FlutterAuroraPluginContext* context);

#if defined(__cplusplus)
}  // extern "C"
#endif
