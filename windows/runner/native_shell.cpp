#include "native_shell.h"

#include <shellapi.h>

#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr int kHotkeyId = 1;
constexpr UINT kMenuToggle = 1, kMenuShow = 2, kMenuQuit = 3;

std::wstring Wide(const std::string& s) {
  if (s.empty()) return {};
  int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
  return out;
}

std::string Str(const flutter::EncodableMap& m, const char* key) {
  auto it = m.find(flutter::EncodableValue(key));
  if (it == m.end()) return {};
  if (auto* v = std::get_if<std::string>(&it->second)) return *v;
  return {};
}

bool Bool(const flutter::EncodableMap& m, const char* key) {
  auto it = m.find(flutter::EncodableValue(key));
  if (it == m.end()) return false;
  if (auto* v = std::get_if<bool>(&it->second)) return *v;
  return false;
}

// Иконки трея лежат рядом с exe: data/flutter_assets/assets/*.ico
HICON LoadTrayIcon(const wchar_t* name) {
  wchar_t exe[MAX_PATH];
  ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  std::wstring path(exe);
  path = path.substr(0, path.find_last_of(L'\\')) + L"\\data\\flutter_assets\\assets\\" + name;
  return static_cast<HICON>(::LoadImageW(nullptr, path.c_str(), IMAGE_ICON,
                                         ::GetSystemMetrics(SM_CXSMICON),
                                         ::GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
}

void Copy(wchar_t* dst, size_t cap, const std::wstring& src) {
  wcsncpy_s(dst, cap, src.c_str(), _TRUNCATE);
}

}  // namespace

NativeShell::NativeShell(HWND hwnd, flutter::BinaryMessenger* messenger)
    : hwnd_(hwnd), taskbar_created_(::RegisterWindowMessageW(L"TaskbarCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "vigilia/native", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& name = call.method_name();
    const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
    if (name == "setTray" && map) {
      SetTray(*map);
      result->Success();
    } else if (name == "notify" && map) {
      Notify(*map);
      result->Success();
    } else if (name == "setHotkey") {
      const auto* on = std::get_if<bool>(call.arguments());
      result->Success(flutter::EncodableValue(SetHotkey(on && *on)));
    } else if (name == "removeTray") {
      RemoveTray();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

NativeShell::~NativeShell() {
  channel_->SetMethodCallHandler(nullptr);
  SetHotkey(false);
  RemoveTray();
  if (icon_on_) ::DestroyIcon(icon_on_);
  if (icon_off_) ::DestroyIcon(icon_off_);
  if (icon_large_) ::DestroyIcon(icon_large_);
}

void NativeShell::SetTray(const flutter::EncodableMap& args) {
  if (!icon_on_) icon_on_ = LoadTrayIcon(L"tray_on.ico");
  if (!icon_off_) icon_off_ = LoadTrayIcon(L"tray_off.ico");
  on_ = Bool(args, "on");
  tooltip_ = Wide(Str(args, "tooltip"));
  toggle_ = Wide(Str(args, "toggle"));
  show_ = Wide(Str(args, "show"));
  quit_ = Wide(Str(args, "quit"));

  NOTIFYICONDATAW nid = {sizeof(nid)};
  nid.hWnd = hwnd_;
  nid.uID = kTrayId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayMessage;
  nid.hIcon = on_ ? icon_on_ : icon_off_;
  Copy(nid.szTip, ARRAYSIZE(nid.szTip), tooltip_);
  if (added_ && ::Shell_NotifyIconW(NIM_MODIFY, &nid)) return;
  // Если панель задач ещё не готова (автозапуск), иконку добавит TaskbarCreated
  added_ = ::Shell_NotifyIconW(NIM_ADD, &nid) != FALSE;
}

void NativeShell::Notify(const flutter::EncodableMap& args) {
  if (!added_) return;
  NOTIFYICONDATAW nid = {sizeof(nid)};
  nid.hWnd = hwnd_;
  nid.uID = kTrayId;
  nid.uFlags = NIF_INFO;
  // звук играет само приложение, у уведомления — без звука
  nid.dwInfoFlags = NIIF_USER | NIIF_LARGE_ICON | NIIF_NOSOUND;
  if (!icon_large_) {
    icon_large_ = static_cast<HICON>(
        ::LoadImageW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
                     ::GetSystemMetrics(SM_CXICON), ::GetSystemMetrics(SM_CYICON), 0));
  }
  nid.hBalloonIcon = icon_large_;
  Copy(nid.szInfoTitle, ARRAYSIZE(nid.szInfoTitle), Wide(Str(args, "title")));
  Copy(nid.szInfo, ARRAYSIZE(nid.szInfo), Wide(Str(args, "body")));
  ::Shell_NotifyIconW(NIM_MODIFY, &nid);
}

bool NativeShell::SetHotkey(bool enabled) {
  if (hotkey_ && !enabled) {
    ::UnregisterHotKey(hwnd_, kHotkeyId);
    hotkey_ = false;
  } else if (!hotkey_ && enabled) {
    hotkey_ = ::RegisterHotKey(hwnd_, kHotkeyId, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'V') != FALSE;
  }
  return hotkey_;
}

void NativeShell::RemoveTray() {
  if (!added_) return;
  NOTIFYICONDATAW nid = {sizeof(nid)};
  nid.hWnd = hwnd_;
  nid.uID = kTrayId;
  ::Shell_NotifyIconW(NIM_DELETE, &nid);
  added_ = false;
}

void NativeShell::ShowMenu() {
  HMENU menu = ::CreatePopupMenu();
  ::AppendMenuW(menu, MF_STRING, kMenuToggle, toggle_.c_str());
  ::AppendMenuW(menu, MF_STRING, kMenuShow, show_.c_str());
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, quit_.c_str());
  POINT pt;
  ::GetCursorPos(&pt);
  // без этого меню не закрывается кликом мимо
  ::SetForegroundWindow(hwnd_);
  UINT cmd = ::TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
                              pt.x, pt.y, 0, hwnd_, nullptr);
  ::PostMessageW(hwnd_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  switch (cmd) {
    case kMenuToggle: Invoke("menu", "toggle"); break;
    case kMenuShow: Invoke("menu", "show"); break;
    case kMenuQuit: Invoke("menu", "quit"); break;
  }
}

void NativeShell::Invoke(const std::string& method, const std::string& arg) {
  channel_->InvokeMethod(method, arg.empty() ? nullptr
                                             : std::make_unique<flutter::EncodableValue>(arg));
}

std::optional<LRESULT> NativeShell::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP: Invoke("trayClick"); break;
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU: ShowMenu(); break;
    }
    return 0;
  }
  if (message == WM_HOTKEY && wparam == kHotkeyId) {
    Invoke("hotkey");
    return 0;
  }
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    // Explorer перезапустился (или только что стартовал) — возвращаем иконку
    added_ = false;
    NOTIFYICONDATAW nid = {sizeof(nid)};
    nid.hWnd = hwnd_;
    nid.uID = kTrayId;
    nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    nid.uCallbackMessage = kTrayMessage;
    nid.hIcon = on_ ? icon_on_ : icon_off_;
    Copy(nid.szTip, ARRAYSIZE(nid.szTip), tooltip_);
    if (nid.hIcon) added_ = ::Shell_NotifyIconW(NIM_ADD, &nid) != FALSE;
    return std::nullopt;
  }
  return std::nullopt;
}
