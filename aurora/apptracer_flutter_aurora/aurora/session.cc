#include "session.h"
#include "worker.h"
#include "minidump.h"
#include <apptracer_flutter_aurora/plugin.h>
#include <appdir_cpp.h>
#include <QCryptographicHash>
#include <QSaveFile>
#include <QFile>
#include <QJsonDocument>
#include <memory>
#include <algorithm>
#include <QUuid>
#include <array>
#include <cerrno>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <fstream>
#include <mutex>
#include <stdexcept>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace apptracer {
namespace fs = std::filesystem;
namespace {
int initialMode = -1;
class Fd {
 public:
  explicit Fd(int fd) : value(fd) {}
  ~Fd() { if (value >= 0) close(value); }
  Fd(const Fd&) = delete;
  Fd& operator=(const Fd&) = delete;
  int value;
};
void setMode(int value) {
  if (prctl(PR_SET_DUMPABLE, static_cast<long>(value), 0L, 0L, 0L) < 0 ||
      prctl(PR_GET_DUMPABLE, 0L, 0L, 0L, 0L) != value)
    throw std::runtime_error("dump_policy_unavailable");
}
fs::path appPath(AppDir::PathType type) {
  fs::path path(AppDir::getPath(type));
  const fs::path app(AppDir::applicationName());
  const fs::path organization(AppDir::organizationName());
  if (app.empty() || organization.empty() || app != app.filename() ||
      organization != organization.filename() || app == "." || app == ".." ||
      organization == "." || organization == ".." || !path.is_absolute() ||
      path.filename() != app || path.parent_path().filename() != organization)
    throw std::runtime_error("app_directory_unavailable");
  return path;
}
void syncDirectory(const fs::path& directory) {
  Fd fd(open(directory.c_str(), O_RDONLY | O_CLOEXEC | O_DIRECTORY));
  if (fd.value < 0 || fsync(fd.value)) throw std::runtime_error("consent_sync_failed");
}
void wipeCache(const fs::path& cache) {
  for (const char* name : {"minidump", "time", "version"}) {
    const auto path = cache / name;
    Fd fd(open(path.c_str(), O_WRONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
    if (fd.value < 0 && errno == ENOENT) continue;
    struct stat st{};
    if (fd.value < 0 || fstat(fd.value, &st) || !S_ISREG(st.st_mode) ||
        st.st_nlink != 1 || ftruncate(fd.value, 0) || fsync(fd.value))
      throw std::runtime_error("system_cache_cleanup_failed");
    if (unlink(path.c_str()) && errno != EACCES && errno != EPERM && errno != ENOENT)
      throw std::runtime_error("system_cache_cleanup_failed");
  }
}
bool copyRegular(const fs::path& source, const fs::path& destination) {
  Fd fd(open(source.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
  if (fd.value < 0 && errno == ENOENT) return false;
  struct stat st{};
  if (fd.value < 0 || fstat(fd.value, &st) || !S_ISREG(st.st_mode))
    throw std::runtime_error("snapshot_read_failed");
  if (!st.st_size) return false;
  QFile input;
  if (!input.open(fd.value, QIODevice::ReadOnly)) throw std::runtime_error("snapshot_read_failed");
  QSaveFile out(QString::fromStdString(destination.string()));
  if (!out.open(QIODevice::WriteOnly)) throw std::runtime_error("snapshot_write_failed");
  std::array<char, 65536> buffer{};
  qint64 remaining = st.st_size;
  while (remaining > 0) {
    const auto n = input.read(buffer.data(), std::min<qint64>(remaining, buffer.size()));
    if (n <= 0 || out.write(buffer.data(), n) != n) throw std::runtime_error("snapshot_copy_failed");
    remaining -= n;
  }
  if (!out.commit()) throw std::runtime_error("snapshot_write_failed");
  return true;
}
QString required(const QJsonObject& args, const char* key) {
  const auto value = args.value(key).toString();
  if (value.isEmpty() || value.contains(QChar::Null)) throw std::runtime_error("invalid_arguments");
  return value;
}
struct Store {
  fs::path cache = appPath(AppLocalCacheLocation);
  fs::path root = appPath(AppLocalDataLocation) / "apptracer-native-v2";
  fs::path sessions = root / "sessions";
  fs::path lease = root / "consent";
  int lock = -1;
  Store() {
    fs::create_directories(root);
    if (!fs::is_directory(fs::symlink_status(root)) || chmod(root.c_str(), 0700))
      throw std::runtime_error("private_storage_unavailable");
    lock = open((root / "lock").c_str(), O_CREAT | O_NOFOLLOW | O_RDWR | O_CLOEXEC, 0600);
    if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB)) {
      if (lock >= 0) close(lock);
      throw std::runtime_error("collection_store_busy");
    }
  }
  ~Store() { close(lock); }
  Store(const Store&) = delete;
  Store& operator=(const Store&) = delete;
  void clear() {
    // Revocation becomes visible before any fallible queue/cache cleanup.
    fs::remove(lease);
    syncDirectory(root);
    fs::remove_all(sessions);
    wipeCache(cache);
  }
};

class Session {
 public:
  ~Session() { worker_.stop(); unmap(); }
  std::string call(const std::string& method, const QJsonObject& args) {
    std::lock_guard<std::mutex> guard(mutex_);
    if (!bootstrapInstalled()) throw std::runtime_error("runner_bootstrap_required");
    if (method == "prepare") return prepare(args);
    if (method == "activate") {
      if (ticket_.isEmpty() || required(args, "ticket").toLatin1() != ticket_)
        throw std::runtime_error("start_superseded");
      try {
        setMode(1);
        worker_.request({{"op", "upload"}});
        ticket_.clear();
        return "active";
      } catch (...) {
        withdraw();
        throw;
      }
    }
    if (method == "withdraw") {
      withdraw();
      return "disabled";
    }
    if (!ticket_.isEmpty()) throw std::runtime_error("collection_disabled");
    if (activeOwner_.isEmpty()) throw std::runtime_error("collection_disabled");
    if (method == "status") return worker_.request({{"op", "status"}}).toStdString();
    auto command = args;
    if (method == "key") required(args, "key");
    if (!args.value("value").isString() || args.value("value").toString().contains(QChar::Null))
      throw std::runtime_error("invalid_arguments");
    command.insert("op", QString::fromStdString(method));
    worker_.request(command);
    return "ok";
  }

 private:
  void withdraw() {
    worker_.stop();
    activeOwner_.clear();
    ticket_.clear();
    setMode(0);
    unmap();
    if (!store_) store_ = std::make_unique<Store>();
    fs::remove(store_->lease);
    syncDirectory(store_->root);
    fs::remove_all(store_->sessions);
    wipeCache(store_->cache);
    store_.reset();
  }
  void unmap() {
    if (mapping_ != MAP_FAILED) { munmap(mapping_, 4096); mapping_ = MAP_FAILED; }
  }
  std::string prepare(const QJsonObject& args) {
    const auto token = required(args, "token");
    // An unscoped session may collect a crash, but cannot authorize its replay.
    const bool scoped = !args.value("account").isNull();
    const auto account = scoped ? required(args, "account") : QString();
    if (!scoped && args.value("preserve").toBool()) throw std::runtime_error("account_scope_required");
    required(args, "version");
    if (args.value("build").toInt(-1) < 0 || !args.value("preserve").isBool())
      throw std::runtime_error("invalid_arguments");
    const auto keys = args.value("keys").toObject();
    for (auto it = keys.begin(); it != keys.end(); ++it) {
      if (it.key().isEmpty() || it.key().contains(QChar::Null) || !it.value().isString() ||
          it.value().toString().contains(QChar::Null)) throw std::runtime_error("invalid_arguments");
    }
    if (args.value("user").toString().contains(QChar::Null)) throw std::runtime_error("invalid_arguments");
    const auto owner = QCryptographicHash::hash(token.toUtf8() + '\0' + account.toUtf8(),
                                               QCryptographicHash::Sha256).toHex();
    if (owner == activeOwner_ && ticket_.isEmpty() && !args.value("replace").toBool()) {
      worker_.request({{"op", "status"}});
      return R"({"result":"active"})";
    }
    std::ifstream sysctl("/proc/sys/kernel/core_pattern");
    std::string handler;
    if (sysctl >> handler && handler != "|/usr/bin/crash-dumper")
      throw std::runtime_error("crash_dumper_unconfigured");
    if (initialMode != 1) throw std::runtime_error("dump_policy_restricted");
    setMode(0);
    worker_.stop();
    ticket_.clear();
    activeOwner_.clear();
    unmap();
    if (!store_) store_ = std::make_unique<Store>();
    auto& db = *store_;
    bool committed = false;
    try {
      QFile lease(QString::fromStdString(db.lease.string()));
      QJsonObject previous;
      if (lease.open(QIODevice::ReadOnly))
        previous = QJsonDocument::fromJson(lease.read(4096)).object();
      lease.close();
      const auto old = previous.value("marker").toString().toLatin1();
      // Earlier facade builds used the literal "no-replay" for anonymous sessions.
      const bool priorScoped = previous.value("scoped").toBool(account != "no-replay");
      const bool preserve = scoped && priorScoped && args.value("preserve").toBool() &&
          previous.value("owner").toString().toLatin1() == owner &&
          old.size() == 32 && QByteArray::fromHex(old).toHex() == old;
      if (!preserve) db.clear();
      fs::create_directories(db.sessions);
      const auto sdk = db.sessions / "sdk";
      const auto backups = db.sessions / "rollback";
      const auto backup = backups / old.constData();
      // No upload runs until the lease commits. Restore a pre-import SDK tree
      // after interruption so the same dump is never imported into it twice.
      if (preserve && fs::is_directory(backup)) {
        fs::remove_all(sdk);
        fs::rename(backup, sdk);
      }
      fs::remove_all(backups);
      prepareOfflineRetry(sdk);
      const auto staging = db.sessions / "snapshot";
      fs::remove_all(staging);
      bool replay = false;
      if (preserve) {
        const auto previousMarker = db.sessions / old.constData();
        fs::create_directory(staging);
        if (copyRegular(db.cache / "minidump", staging / "minidump"))
          replay = containsSessionMapping(staging / "minidump", previousMarker);
        if (replay) {
          if (!fs::is_directory(sdk)) throw std::runtime_error("previous_session_missing");
          fs::create_directory(backups);
          const auto building = backups / "building";
          fs::copy(sdk, building, fs::copy_options::recursive);
          fs::rename(building, backup);
          for (const char* name : {"time", "version"})
            copyRegular(db.cache / name, staging / name);
        }
      }
      const auto id = QUuid::createUuid().toRfc4122().toHex();
      const auto marker = db.sessions / id.constData();
      Fd fd(open(marker.c_str(), O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0600));
      if (fd.value < 0 || ftruncate(fd.value, 4096)) throw std::runtime_error("marker_create_failed");
      mapping_ = mmap(nullptr, 4096, PROT_READ, MAP_SHARED, fd.value, 0);
      if (mapping_ == MAP_FAILED) throw std::runtime_error("marker_map_failed");
      worker_.launch(db.lock);
      auto init = args;
      init.insert("op", "init");
      init.insert("root", QString::fromStdString((db.sessions / "sdk").string()));
      if (replay) init.insert("stage", QString::fromStdString(staging.string()));
      else init.remove("stage");
      worker_.request(init);
      // Commit the new lease before allowing either the next dump or upload.
      QSaveFile next(QString::fromStdString(db.lease.string()));
      const auto content = QJsonDocument(QJsonObject{{"scoped", scoped}, {"owner", QString::fromLatin1(owner)},
                                             {"marker", QString::fromLatin1(id)}}).toJson(QJsonDocument::Compact);
      if (!next.open(QIODevice::WriteOnly) || next.write(content) != content.size() || !next.commit())
        throw std::runtime_error("consent_commit_failed");
      committed = true;
      syncDirectory(db.root);
      fs::remove_all(backups);
      wipeCache(db.cache);
      fs::remove_all(staging);
      // Remove orphaned markers from interrupted starts as well.
      for (const auto& entry : fs::directory_iterator(db.sessions)) {
        if (entry.is_regular_file() && entry.path() != marker) fs::remove(entry.path());
      }
      ticket_ = id;
      activeOwner_ = owner;
      return QJsonDocument(QJsonObject{{"result", replay ? "replayed" : "started"},
          {"ticket", QString::fromLatin1(id)}}).toJson(QJsonDocument::Compact).toStdString();
    } catch (...) {
      worker_.stop();
      unmap();
      setMode(0);
      if (committed) db.clear();
      store_.reset();
      throw;
    }
  }
  std::mutex mutex_;
  Worker worker_;
  void* mapping_ = MAP_FAILED;
  QByteArray activeOwner_;
  QByteArray ticket_;
  std::unique_ptr<Store> store_;
};
}  // namespace

fs::path sdkPath() {
  Dl_info info{};
  if (!dladdr(reinterpret_cast<void*>(&ApptracerFlutterAuroraRegister), &info) ||
      !info.dli_fname || !fs::path(info.dli_fname).is_absolute())
    throw std::runtime_error("plugin_path_unavailable");
  return fs::path(info.dli_fname).parent_path() / "libtracernative.so";
}
bool bootstrapInstalled() { return initialMode >= 0; }
void bootstrap(int argc, char** argv) {
  const bool child = argc == 2 && std::strcmp(argv[1], "--apptracer-aurora-worker") == 0;
  if (initialMode >= 0) return;
  const int original = prctl(PR_GET_DUMPABLE, 0L, 0L, 0L, 0L);
  if (original < 0 || prctl(PR_SET_DUMPABLE, 0L, 0L, 0L, 0L) < 0) {
    if (child) _exit(1);
    return;
  }
  initialMode = original;
  if (child) _exit(runWorker());
}
bool workerHasSessionLock(int fd) {
  const auto file = appPath(AppLocalDataLocation) / "apptracer-native-v2/lock";
  struct stat actual{}, expected{};
  return fstat(fd, &actual) == 0 && lstat(file.c_str(), &expected) == 0 &&
      S_ISREG(expected.st_mode) && expected.st_uid == geteuid() &&
      actual.st_ino == expected.st_ino && actual.st_dev == expected.st_dev;
}
std::string handleCollection(const std::string& method, const QJsonObject& args) {
  static Session session;
  return session.call(method, args);
}
}  // namespace apptracer

void ApptracerFlutterAuroraPrepareRunner(int argc, char** argv) {
  apptracer::bootstrap(argc, argv);
}
