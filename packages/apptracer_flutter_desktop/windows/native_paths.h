#include <windows.h>
#include <psapi.h>

// sentry-native 0.16.6's daemon uses ANSI module paths as JSON UTF-8. Use the
// Unicode Windows APIs before serializing, so non-ASCII installation paths work.
DWORD apptracer_module_path(HANDLE process, HMODULE module, LPSTR output, DWORD size);
HANDLE apptracer_open_path(LPCSTR path, DWORD access, DWORD share,
    LPSECURITY_ATTRIBUTES security, DWORD creation, DWORD flags, HANDLE template_file);
#undef GetModuleFileNameExA
#define GetModuleFileNameExA apptracer_module_path
#define CreateFileA apptracer_open_path
