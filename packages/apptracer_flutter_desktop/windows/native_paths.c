#include <windows.h>
#include <psapi.h>

DWORD apptracer_module_path(HANDLE process, HMODULE module, LPSTR output, DWORD size) {
  wchar_t path[32768];
  DWORD length = GetModuleFileNameExW(process, module, path, 32768);
  if (length == 0 || length >= 32768) return 0;
  int converted = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path, -1,
      output, (int)size, NULL, NULL);
  return converted > 0 ? (DWORD)(converted - 1) : 0;
}

HANDLE apptracer_open_path(LPCSTR path, DWORD access, DWORD share,
    LPSECURITY_ATTRIBUTES security, DWORD creation, DWORD flags, HANDLE template_file) {
  wchar_t wide[32768];
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, 32768))
    return INVALID_HANDLE_VALUE;
  return CreateFileW(wide, access, share, security, creation, flags, template_file);
}
