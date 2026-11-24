#pragma once
#include <QJsonObject>
#include <sys/types.h>

namespace apptracer {
class Worker {
 public:
  Worker() = default;
  Worker(const Worker&) = delete;
  Worker& operator=(const Worker&) = delete;
  ~Worker();
  void launch(int sessionLock);
  QByteArray request(const QJsonObject& message);
  void stop();
 private:
  int socket_ = -1;
  pid_t pid_ = -1;
};
int runWorker();
}  // namespace apptracer
