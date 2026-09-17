// Тесты NativeShell: канал vigilia/native и глобальная клавиша.
// Окна — невидимые message-only, канал — поддельный мессенджер вместо движка Flutter.
// Трей не трогается: иконка появилась бы в панели задач того, кто запускает тест.
#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdio>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "native_shell.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

int failures = 0;

#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                \
    }                                                            \
  } while (0)

const flutter::StandardMethodCodec& Codec() { return flutter::StandardMethodCodec::GetInstance(); }

// Мессенджер вместо движка: запоминает вызовы C++ → Dart и умеет вызывать обработчик Dart → C++.
class FakeMessenger : public flutter::BinaryMessenger {
 public:
  void Send(const std::string& channel, const uint8_t* message, size_t message_size,
            flutter::BinaryReply reply) const override {
    auto call = Codec().DecodeMethodCall(message, message_size);
    std::string arg;
    if (auto* s = std::get_if<std::string>(call->arguments())) arg = *s;
    sent.emplace_back(call->method_name(), arg);
  }

  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler handler) override {
    handlers[channel] = std::move(handler);
  }

  struct Reply {
    bool not_implemented = false;
    std::optional<EncodableValue> value;
  };

  // Вызов метода «из Dart».
  Reply Call(const std::string& method, EncodableValue args) {
    auto message = Codec().EncodeMethodCall(
        flutter::MethodCall<EncodableValue>(method, std::make_unique<EncodableValue>(std::move(args))));
    std::vector<uint8_t> response;
    handlers["vigilia/native"](message->data(), message->size(), [&](const uint8_t* data, size_t size) {
      if (data) response.assign(data, data + size);
    });
    Reply reply;
    if (response.empty()) {
      reply.not_implemented = true;
      return reply;
    }
    flutter::MethodResultFunctions<EncodableValue> result(
        [&](const EncodableValue* v) { reply.value = v ? *v : EncodableValue(); }, nullptr, nullptr);
    Codec().DecodeAndProcessResponseEnvelope(response.data(), response.size(), &result);
    return reply;
  }

  mutable std::vector<std::pair<std::string, std::string>> sent;
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
};

HWND HiddenWindow() {
  return ::CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                           ::GetModuleHandleW(nullptr), nullptr);
}

// Редкое сочетание, чтобы не столкнуться с программами пользователя.
constexpr int kMods = MOD_CONTROL | MOD_ALT | MOD_SHIFT;
constexpr int kF23 = VK_F23, kF24 = VK_F24;

EncodableValue HotkeyArgs(bool on, int vk) {
  return EncodableValue(EncodableMap{
      {EncodableValue("on"), EncodableValue(on)},
      {EncodableValue("mods"), EncodableValue(kMods)},
      {EncodableValue("vk"), EncodableValue(vk)},
  });
}

bool SetHotkey(FakeMessenger& m, bool on, int vk) {
  auto reply = m.Call("setHotkey", HotkeyArgs(on, vk));
  auto* ok = reply.value ? std::get_if<bool>(&*reply.value) : nullptr;
  return ok && *ok;
}

void TestUnknownMethod() {
  HWND hwnd = HiddenWindow();
  FakeMessenger m;
  {
    NativeShell shell(hwnd, &m);
    CHECK(m.Call("nope", EncodableValue()).not_implemented);
    // аргументы не той формы — тоже «не реализовано», а не падение
    CHECK(m.Call("setHotkey", EncodableValue(true)).not_implemented);
    CHECK(m.Call("setTray", EncodableValue("x")).not_implemented);
  }
  ::DestroyWindow(hwnd);
}

void TestHotkey() {
  HWND a = HiddenWindow(), b = HiddenWindow();
  FakeMessenger ma, mb;
  auto shell_a = std::make_unique<NativeShell>(a, &ma);
  auto shell_b = std::make_unique<NativeShell>(b, &mb);

  CHECK(SetHotkey(ma, true, kF24));
  CHECK(!SetHotkey(mb, true, kF24));  // занято первым окном

  CHECK(SetHotkey(ma, true, kF23));  // смена сочетания снимает старое
  CHECK(SetHotkey(mb, true, kF24));

  CHECK(!SetHotkey(ma, true, 0));  // без клавиши — ничего не регистрируется
  CHECK(SetHotkey(mb, true, kF23));  // и прежнее сочетание снято

  CHECK(!SetHotkey(mb, false, kF23));
  CHECK(SetHotkey(ma, true, kF23));

  shell_a.reset();  // разрушение снимает регистрацию
  CHECK(SetHotkey(mb, true, kF23));
  shell_b.reset();
  ::DestroyWindow(a);
  ::DestroyWindow(b);
}

void TestMessages() {
  HWND hwnd = HiddenWindow();
  FakeMessenger m;
  {
    NativeShell shell(hwnd, &m);
    auto handled = shell.HandleMessage(WM_HOTKEY, 1, 0);
    CHECK(handled.has_value());
    CHECK(!shell.HandleMessage(WM_HOTKEY, 2, 0).has_value());  // чужой идентификатор
    CHECK(shell.HandleMessage(WM_APP + 1, 1, WM_LBUTTONUP).has_value());
    CHECK(shell.HandleMessage(WM_APP + 1, 1, WM_MOUSEMOVE).has_value());  // наше сообщение, но без действия
    CHECK(!shell.HandleMessage(WM_PAINT, 0, 0).has_value());
    CHECK(m.sent.size() == 2);
    if (m.sent.size() == 2) {
      CHECK(m.sent[0].first == "hotkey");
      CHECK(m.sent[1].first == "trayClick");
    }

    // без иконки уведомление и удаление — тихие пустые операции
    auto notify = m.Call("notify", EncodableValue(EncodableMap{
                                       {EncodableValue("title"), EncodableValue("t")},
                                       {EncodableValue("body"), EncodableValue("b")},
                                   }));
    CHECK(!notify.not_implemented);
    CHECK(!m.Call("removeTray", EncodableValue()).not_implemented);
    CHECK(m.sent.size() == 2);
  }
  ::DestroyWindow(hwnd);
}

}  // namespace

int main() {
  TestUnknownMethod();
  TestHotkey();
  TestMessages();
  if (failures == 0) std::printf("native_shell: all tests passed\n");
  return failures == 0 ? 0 : 1;
}
