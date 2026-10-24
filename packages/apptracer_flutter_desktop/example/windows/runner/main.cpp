#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <cstdio>
#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // The opt-in lifecycle driver communicates over inherited anonymous pipes.
  // A GUI subsystem application has no CRT streams unless they are attached.
  wchar_t scenario[32] = {};
  GetEnvironmentVariableW(L"TRACER_SCENARIO", scenario, 32);
  if (std::wstring(scenario) == L"lifecycle") {
    const DWORD handles[] = {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
    FILE* streams[] = {stdin, stdout, stderr};
    const char* modes[] = {"r", "w", "w"};
    for (int i = 0; i < 3; ++i) {
      HANDLE original = GetStdHandle(handles[i]);
      HANDLE copied = nullptr;
      if (original && original != INVALID_HANDLE_VALUE &&
          DuplicateHandle(GetCurrentProcess(), original, GetCurrentProcess(),
                          &copied, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
        const int descriptor = _open_osfhandle(reinterpret_cast<intptr_t>(copied),
                                               i == 0 ? _O_RDONLY : _O_WRONLY);
        if (descriptor >= 0) {
          FILE* ignored = nullptr;
          if (freopen_s(&ignored, "NUL", modes[i], streams[i]) == 0) {
            _dup2(descriptor, _fileno(streams[i]));
            SetStdHandle(handles[i], reinterpret_cast<HANDLE>(
                _get_osfhandle(_fileno(streams[i]))));
            setvbuf(streams[i], nullptr, _IONBF, 0);
          }
          _close(descriptor);
        } else {
          CloseHandle(copied);
        }
      }
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"apptracer_desktop_example", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
