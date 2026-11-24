#pragma once

#include <QJsonObject>
#include <filesystem>
#include <string>

namespace apptracer {
std::filesystem::path sdkPath();
bool bootstrapInstalled();
void bootstrap(int argc, char** argv);
std::string handleCollection(const std::string& method, const QJsonObject& args);
bool workerHasSessionLock(int fd);
void prepareOfflineRetry(const std::filesystem::path& sdk);
}  // namespace apptracer
