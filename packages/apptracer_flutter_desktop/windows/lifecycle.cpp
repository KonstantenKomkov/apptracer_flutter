#include <windows.h>
#include <restartmanager.h>

#include <filesystem>
#include <string>
#include <vector>

// Restart Manager supplies both PID and creation time of processes holding an
// exact owned daemon lock. A stable process handle prevents PID-reuse races.
extern "C" __declspec(dllexport) DWORD apptracer_stop_daemons(
    const wchar_t* database) {
  try {
    const std::filesystem::path root(database);
    if (!std::filesystem::is_directory(root)) return ERROR_SUCCESS;
    std::vector<std::wstring> locks;
    for (const auto& entry : std::filesystem::directory_iterator(root)) {
      const auto name = entry.path().filename().wstring();
      if (name.size() == 52 && name.substr(36) == L".run.daemon.lock") {
        const DWORD attrs = GetFileAttributesW(entry.path().c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_REPARSE_POINT))
          return ERROR_INVALID_DATA;
        locks.push_back(entry.path().wstring());
      }
    }
    if (locks.empty()) return ERROR_SUCCESS;
    std::vector<LPCWSTR> paths;
    for (const auto& lock : locks) paths.push_back(lock.c_str());
    DWORD session = 0;
    wchar_t key[CCH_RM_SESSION_KEY + 1] = {};
    DWORD result = RmStartSession(&session, 0, key);
    if (result != ERROR_SUCCESS) return result;
    struct Session {
      DWORD value;
      ~Session() { RmEndSession(value); }
    } guard{session};
    result = RmRegisterResources(session, static_cast<UINT>(paths.size()),
                                 paths.data(), 0, nullptr, 0, nullptr);
    if (result != ERROR_SUCCESS) return result;
    UINT needed = 0, count = 0;
    DWORD reboot = 0;
    result = RmGetList(session, &needed, &count, nullptr, &reboot);
    if (result == ERROR_SUCCESS && needed == 0) return ERROR_SUCCESS;
    if (result != ERROR_MORE_DATA) return result;
    std::vector<RM_PROCESS_INFO> processes;
    for (int attempt = 0; attempt < 4; ++attempt) {
      processes.resize(needed);
      count = needed;
      result = RmGetList(session, &needed, &count, processes.data(), &reboot);
      if (result != ERROR_MORE_DATA) break;
    }
    if (result != ERROR_SUCCESS) return result;
    for (UINT i = 0; i < count; ++i) {
      const auto& identity = processes[i].Process;
      HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION |
          PROCESS_TERMINATE | SYNCHRONIZE, FALSE, identity.dwProcessId);
      if (!process) {
        if (GetLastError() == ERROR_INVALID_PARAMETER) continue;
        return GetLastError();
      }
      struct Handle {
        HANDLE value;
        ~Handle() { CloseHandle(value); }
      } handle{process};
      FILETIME created{}, exited{}, kernel{}, user{};
      if (!GetProcessTimes(process, &created, &exited, &kernel, &user))
        return GetLastError();
      if (CompareFileTime(&created, &identity.ProcessStartTime) != 0) continue;
      wchar_t executable[32768];
      DWORD size = 32768;
      if (!QueryFullProcessImageNameW(process, 0, executable, &size))
        return GetLastError();
      if (_wcsicmp(std::filesystem::path(executable).filename().c_str(),
                   L"sentry-crash.exe") != 0) return ERROR_INVALID_DATA;
      if (!TerminateProcess(process, 0) &&
          WaitForSingleObject(process, 0) != WAIT_OBJECT_0) return GetLastError();
      if (WaitForSingleObject(process, 5000) != WAIT_OBJECT_0) return ERROR_TIMEOUT;
    }
    return ERROR_SUCCESS;
  } catch (...) {
    return ERROR_INVALID_DATA;
  }
}

// Reject junctions as well as symlinks in every storage ancestor.
extern "C" __declspec(dllexport) DWORD apptracer_validate_storage(
    const wchar_t* storage) {
  try {
    auto path = std::filesystem::absolute(storage);
    while (!path.empty()) {
      const DWORD attrs = GetFileAttributesW(path.c_str());
      if (attrs == INVALID_FILE_ATTRIBUTES) {
        const DWORD error = GetLastError();
        if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND)
          return error;
      } else if (attrs & FILE_ATTRIBUTE_REPARSE_POINT) {
        return ERROR_REPARSE_TAG_INVALID;
      }
      const auto parent = path.parent_path();
      if (parent == path) break;
      path = parent;
    }
    return ERROR_SUCCESS;
  } catch (...) {
    return ERROR_INVALID_DATA;
  }
}
