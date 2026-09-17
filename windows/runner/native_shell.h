#ifndef RUNNER_NATIVE_SHELL_H_
#define RUNNER_NATIVE_SHELL_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <array>
#include <memory>
#include <optional>
#include <string>

// Трей (иконка, подсказка, меню), уведомления и глобальная горячая клавиша.
// Канал "vigilia/native":
//   Dart → C++: setTray{on, accent, tooltip, toggle, show, quit}, notify{title, body},
//               setHotkey{on, mods, vk} → bool, removeTray
//   C++ → Dart: trayClick, menu(id), hotkey
class NativeShell {
 public:
  NativeShell(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~NativeShell();

  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void SetTray(const flutter::EncodableMap& args);
  void Notify(const flutter::EncodableMap& args);
  bool SetHotkey(bool enabled, UINT mods, UINT vk);
  void RemoveTray();
  void ShowMenu();
  void Invoke(const std::string& method, const std::string& arg = "");

  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  UINT taskbar_created_;
  bool added_ = false;
  bool hotkey_ = false;
  HICON TrayIcon();

  static constexpr int kAccents = 6;
  std::array<HICON, kAccents> icons_on_{};
  std::array<HICON, kAccents> icons_off_{};
  HICON icon_large_ = nullptr;
  bool on_ = false;
  int accent_ = 0;
  std::wstring tooltip_, toggle_, show_, quit_;
};

#endif  // RUNNER_NATIVE_SHELL_H_
