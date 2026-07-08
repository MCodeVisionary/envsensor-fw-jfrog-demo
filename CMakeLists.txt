cmake_minimum_required(VERSION 3.16)
project(envsensor_fw C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Single source of truth for the firmware version — see VERSION at repo
# root. scripts/build.sh and scripts/certify.sh read the same file so the
# binary's self-reported version, its Artifactory path, and its
# certification record can never drift apart.
file(STRINGS "${CMAKE_SOURCE_DIR}/VERSION" FW_VERSION_STRING LIMIT_COUNT 1)
string(REPLACE "." ";" FW_VERSION_LIST "${FW_VERSION_STRING}")
list(GET FW_VERSION_LIST 0 FW_VERSION_MAJOR)
list(GET FW_VERSION_LIST 1 FW_VERSION_MINOR)
list(GET FW_VERSION_LIST 2 FW_VERSION_PATCH)

if(NOT BOARD)
  message(FATAL_ERROR "Set -DBOARD=BOARD_A or -DBOARD=BOARD_B")
endif()
if(NOT BOARD STREQUAL "BOARD_A" AND NOT BOARD STREQUAL "BOARD_B")
  message(FATAL_ERROR "Unknown BOARD '${BOARD}'. Valid values: BOARD_A, BOARD_B")
endif()

# --- Cross toolchain (falls back to the host compiler for this demo) ------
find_program(ARM_GCC arm-none-eabi-gcc)
if(ARM_GCC AND CMAKE_C_COMPILER MATCHES "arm-none-eabi-gcc")
  message(STATUS "Cross-compiling for embedded target with ${CMAKE_C_COMPILER}")
else()
  message(WARNING
    "arm-none-eabi-gcc not found/selected — building a HOST SIMULATION "
    "binary with ${CMAKE_C_COMPILER} for demo purposes. Point "
    "CMAKE_TOOLCHAIN_FILE at a real cross toolchain to produce flashable "
    "firmware.")
endif()

# --- Reproducible-build plumbing ------------------------------------------
# SOURCE_DATE_EPOCH pins the embedded build timestamp so rebuilding the same
# commit on any machine, any day, produces a byte-identical artifact.
if(DEFINED ENV{SOURCE_DATE_EPOCH})
  set(FW_BUILD_EPOCH $ENV{SOURCE_DATE_EPOCH})
else()
  set(FW_BUILD_EPOCH 0)
endif()

find_package(Git QUIET)
if(GIT_FOUND)
  execute_process(
    COMMAND ${GIT_EXECUTABLE} rev-parse --short=12 HEAD
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    OUTPUT_VARIABLE FW_GIT_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
    RESULT_VARIABLE GIT_REV_RESULT)
endif()
if(NOT FW_GIT_COMMIT OR NOT GIT_REV_RESULT EQUAL 0)
  set(FW_GIT_COMMIT "unknown")
endif()

set(FW_BOARD_NAME ${BOARD})
configure_file(${CMAKE_SOURCE_DIR}/include/version.h.in
               ${CMAKE_BINARY_DIR}/generated/version.h @ONLY)

# Strip absolute build-path noise from debug info / macros (__FILE__, etc.)
# so two checkouts at different paths still produce identical bytes.
add_compile_options(
  -ffile-prefix-map=${CMAKE_SOURCE_DIR}=.
  -Wall -Wextra)

add_executable(envsensor_fw
  src/main.c
  src/sensor.c
  src/crc.c
  src/interop_checksum.c
  third_party/zlib-1.2.11/crc32.c)

target_include_directories(envsensor_fw PRIVATE
  include
  third_party/zlib-1.2.11
  ${CMAKE_BINARY_DIR}/generated)

target_compile_definitions(envsensor_fw PRIVATE ${BOARD})

# Vendored, unmodified upstream source (see third_party/README.md) — hold it
# to its own project's style, not ours.
set_source_files_properties(third_party/zlib-1.2.11/crc32.c PROPERTIES
  COMPILE_OPTIONS "-Wno-deprecated-non-prototype;-Wno-macro-redefined")

# --- Reproducibility fingerprint -------------------------------------------
add_custom_command(TARGET envsensor_fw POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E sha256sum $<TARGET_FILE:envsensor_fw>
  COMMENT "SHA-256 of freshly built artifact")

enable_testing()
add_subdirectory(tests)
