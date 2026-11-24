#include <apptracer_flutter_aurora/plugin.h>
#include <client_wrapper/basic_plugin.h>
#include <client_wrapper/plugin_registrar.h>

#include "session.h"
#include <QJsonDocument>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <string>

namespace {

class AuroraTracerPlugin final : public cw::BasicPlugin<> {
 public:
  explicit AuroraTracerPlugin(cw::PluginRegistrar* registrar)
      : BasicPlugin("apptracer_flutter/aurora", registrar->messenger()) {}

 private:
  Result HandleMethodCall(const std::string& method,
                          const cw::EncodableValue* arguments) override {
    try {
      if (method == "probe") return probe();
      if (method != "prepare" && method != "activate" && method != "withdraw" && method != "log" && method != "key" && method != "status")
        return cw::NotImplemented();
      QJsonObject args;
      if (arguments && std::holds_alternative<std::string>(*arguments)) {
        const auto doc = QJsonDocument::fromJson(QByteArray::fromStdString(std::get<std::string>(*arguments)));
        if (!doc.isObject()) return cw::FlutterError("invalid_arguments");
        args = doc.object();
      }
      return cw::EncodableValue(apptracer::handleCollection(method, args));
    } catch (const std::filesystem::filesystem_error&) {
      return cw::FlutterError("collection_storage_failed");
    } catch (const std::exception& e) {
      return cw::FlutterError(e.what());
    }
  }

  Result probe() {
    const auto sdk_path = apptracer::sdkPath();
    void* sdk = dlopen(sdk_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!sdk) return cw::FlutterError("sdk_load_failed", dlerror());
    for (const char* symbol : {"tracer_init", "tracer_set_platform_info2",
                               "tracer_set_key", "tracer_set_userid", "tracer_log",
                               "tracer_upload", "tracer_disable_upload",
                               "tracer_aurora_collect_minidump_from_cachedir"}) {
      if (!dlsym(sdk, symbol)) {
        dlclose(sdk);
        return cw::FlutterError("sdk_export_missing", symbol);
      }
    }
    dlclose(sdk);
    std::string pattern;
    std::ifstream sysctl("/proc/sys/kernel/core_pattern");
    std::getline(sysctl, pattern);
    const auto separator = pattern.find_first_of(" \t");
    const bool handler = pattern.substr(0, separator) == "|/usr/bin/crash-dumper";
    return cw::EncodableValue(cw::EncodableMap{
        {cw::EncodableValue("sdkVersion"), cw::EncodableValue("0.1.15")},
        {cw::EncodableValue("crashDumperConfigured"),
         pattern.empty() ? cw::EncodableValue() : cw::EncodableValue(handler)},
    });
  }
};

}  // namespace

void ApptracerFlutterAuroraRegister(FlutterAuroraPluginContext* context) {
  cw::PluginRegistrarManager::Register<AuroraTracerPlugin>(context);
}
