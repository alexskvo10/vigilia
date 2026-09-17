# Тесты нативной оболочки (native_shell.cpp) без запуска приложения.
# Нужна папка windows/flutter/ephemeral — она появляется после `flutter build windows`.
#
#   cmake -S windows/runner/test -B build/native_test
#   cmake --build build/native_test --config Release
#   ctest --test-dir build/native_test -C Release --output-on-failure
cmake_minimum_required(VERSION 3.14)
project(native_shell_test LANGUAGES CXX)

set(EPHEMERAL "${CMAKE_CURRENT_SOURCE_DIR}/../../flutter/ephemeral")
set(WRAPPER "${EPHEMERAL}/cpp_client_wrapper")

add_executable(native_shell_test
  native_shell_test.cpp
  ../native_shell.cpp
  "${WRAPPER}/standard_codec.cc"
  "${WRAPPER}/engine_method_result.cc"
)
target_compile_features(native_shell_test PRIVATE cxx_std_17)
target_include_directories(native_shell_test PRIVATE .. "${WRAPPER}/include" "${WRAPPER}" "${EPHEMERAL}")
target_compile_definitions(native_shell_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(native_shell_test PRIVATE /W4 /WX /wd4100 /EHsc /utf-8)
# обёртка канала ссылается на C API движка; сам движок в тесте не запускается
target_link_libraries(native_shell_test PRIVATE "${EPHEMERAL}/flutter_windows.dll.lib" user32 shell32)
add_custom_command(TARGET native_shell_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:native_shell_test>")

enable_testing()
add_test(NAME native_shell COMMAND native_shell_test)
