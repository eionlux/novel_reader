#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

const wchar_t kInstanceMutex[] = L"Local\\DanQingReaderInstance";
const wchar_t kRequestFileName[] = L"open_request.txt";

std::string LowerAscii(const std::string& value) {
  std::string result = value;
  std::transform(result.begin(), result.end(), result.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return result;
}

bool LooksLikeBookFile(const std::string& path) {
  const std::string lower = LowerAscii(path);
  const char* kExtensions[] = {".txt", ".md", ".epub", ".mobi", ".azw3", ".azw"};
  for (const auto& extension : kExtensions) {
    if (lower.size() >= std::strlen(extension) &&
        lower.compare(lower.size() - std::strlen(extension), std::strlen(extension), extension) == 0) {
      return true;
    }
  }
  return false;
}

// Write the external file path to %APPDATA%\DanQingReader\open_request.txt.
// Dart reads and deletes it after startup, so no MethodChannel is needed here.
void WriteOpenRequest(const std::string& utf8_path) {
  wchar_t app_data[MAX_PATH] = {};
  if (::GetEnvironmentVariableW(L"APPDATA", app_data, MAX_PATH) == 0) {
    return;
  }
  std::wstring dir = std::wstring(app_data) + L"\\DanQingReader";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  std::wstring file_path = dir + L"\\" + kRequestFileName;

  HANDLE handle = ::CreateFileW(file_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                                nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return;
  }
  ::WriteFile(handle, utf8_path.data(), static_cast<DWORD>(utf8_path.size()), nullptr, nullptr);
  ::CloseHandle(handle);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Single instance: hand the file to the running window, then exit.
  HANDLE instance_mutex = ::CreateMutexW(nullptr, TRUE, kInstanceMutex);
  const bool already_running =
      instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;

  for (const auto& argument : command_line_arguments) {
    if (LooksLikeBookFile(argument)) {
      WriteOpenRequest(argument);
      break;
    }
  }

  if (already_running) {
    if (instance_mutex != nullptr) {
      ::CloseHandle(instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(60, 50);
  Win32Window::Size size(1080, 780);
  if (!window.Create(L"DanQing Reader", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
