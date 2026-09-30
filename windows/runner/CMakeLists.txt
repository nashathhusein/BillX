cmake_minimum_required(VERSION 3.14)

project(runner LANGUAGES CXX)

# Silence MSVC experimental coroutine deprecation error.
# Required for local_auth_windows with newer Visual Studio/MSVC.
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# Define the application target.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE
  "FLUTTER_VERSION=\"${FLUTTER_VERSION}\""
  "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}"
  "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}"
  "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}"
  "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}"
)

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE
  "NOMINMAX"
)

# Add dependency libraries and include directories.
target_link_libraries(${BINARY_NAME} PRIVATE
  flutter
  flutter_wrapper_app
)

target_link_libraries(${BINARY_NAME} PRIVATE
  "dwmapi.lib"
)

target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}"
)

# Run the Flutter tool portions of the build.
add_dependencies(${BINARY_NAME} flutter_assemble)

# ---------------------------------------------------------
# IMPORTANT:
# Keep the coroutine warning suppression for all generated
# Flutter plugins, including local_auth_windows.
# ---------------------------------------------------------
add_compile_definitions(
  _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
)