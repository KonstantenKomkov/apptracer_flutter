#include "session.h"
#include <QFile>
#include <QJsonDocument>
#include <zlib.h>
#include <algorithm>
#include <array>
#include <fstream>

namespace apptracer {
namespace fs = std::filesystem;
namespace {
// Native 0.1.15 keeps both the input to its event builder and the event with
// its assigned UUID after a failed send. Refeeding both produces two events.
bool completeEvent(const fs::path& input, const fs::path& event) {
  std::ifstream type(event / "type.txt", std::ios::binary);
  if (type.get() != '0' || type.peek() != std::char_traits<char>::eof()) return false;
  QFile info(QString::fromStdString((event / "info.json").string()));
  if (!info.open(QIODevice::ReadOnly) || !QJsonDocument::fromJson(info.readAll()).isObject())
    return false;
  std::ifstream raw(input, std::ios::binary);
  std::ifstream copy(event / "dump.dmp", std::ios::binary);
  auto gzip = gzopen((event / "dump.dmp.gz").c_str(), "rb");
  if (!gzip) return false;
  std::array<char, 32768> original{}, queued{}, compressed{};
  bool matches = raw && copy && !gzdirect(gzip);
  while (matches) {
    raw.read(original.data(), original.size());
    const auto size = raw.gcount();
    copy.read(queued.data(), queued.size());
    const int unpacked = gzread(gzip, compressed.data(), compressed.size());
    matches = !raw.bad() && !copy.bad() && copy.gcount() == size && unpacked == size &&
        std::equal(original.begin(), original.begin() + size, queued.begin()) &&
        std::equal(original.begin(), original.begin() + size, compressed.begin());
    if (size == 0) break;
  }
  return gzclose(gzip) == Z_OK && matches;
}
}  // namespace

void prepareOfflineRetry(const fs::path& sdk) {
  if (!fs::is_directory(sdk)) return;
  for (const auto& session : fs::directory_iterator(sdk)) {
    if (!session.is_directory() || session.path().filename().string().rfind("session-", 0) != 0)
      continue;
    const auto original = session.path() / "crashes/minidump.dmp";
    const auto events = session.path() / "events";
    if (!fs::is_regular_file(original) || !fs::is_directory(events)) continue;
    for (const auto& event : fs::directory_iterator(events)) {
      if (event.is_directory() && event.path().filename().string().rfind("event-", 0) == 0 &&
          completeEvent(original, event.path())) {
        fs::remove(original);
        break;
      }
    }
  }
}
}  // namespace apptracer
