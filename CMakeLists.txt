# rea — the Rea front end for the PSCAL VM, and the shared engine Aether builds on.
#
# Rea parses its source into the shared PSCAL AST, which the shared bytecode
# compiler lowers and the PSCAL VM runs. These same sources are the shared
# front-end engine: Aether reuses them and installs its overrides at startup
# through the engine's frontend-hook seam (src/rea/frontend_hooks.h), so the
# engine itself carries no dependency on any specific front end.
#
# Pulls pscal-core in via FetchContent, so building this repo on its own fetches
# and builds the shared core automatically.
cmake_minimum_required(VERSION 3.18)
project(rea C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
add_compile_options(-Wall)
if(UNIX AND NOT APPLE)
    add_compile_definitions(_GNU_SOURCE _POSIX_C_SOURCE=200809L)
endif()
if(CMAKE_C_COMPILER_ID STREQUAL "AppleClang")
    add_compile_options(-Wno-nullability-completeness)
endif()

find_package(Threads REQUIRED)

include(FetchContent)
FetchContent_Declare(
    pscal_core
    GIT_REPOSITORY https://github.com/emkey1/pscal-core.git
    GIT_TAG main
)
FetchContent_MakeAvailable(pscal_core)

# Core public headers + the generated pscal_paths.h (configure_file in core
# writes it under the top-level binary dir), plus Rea's own headers.
include_directories(
    ${pscal_core_SOURCE_DIR}/src
    ${pscal_core_SOURCE_DIR}/src/third_party/yyjson
    ${CMAKE_BINARY_DIR}/generated
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

add_compile_definitions(
    PROGRAM_VERSION="0.0.0"
    PSCAL_GIT_TAG="untagged"
    ENABLE_EXT_BUILTIN_MATH ENABLE_EXT_BUILTIN_STRINGS ENABLE_EXT_BUILTIN_SYSTEM
    ENABLE_EXT_BUILTIN_USER ENABLE_EXT_BUILTIN_YYJSON ENABLE_EXT_BUILTIN_3D
    ENABLE_EXT_BUILTIN_GRAPHICS
)

set(REA_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/main.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/lexer.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/semantic.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/state.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/builtins/thread.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/type_stubs.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/rea/frontend_hooks.c
)

# Build the standalone `rea` executable only when this repo is the top-level
# project. When rea is consumed via FetchContent / add_subdirectory (e.g. by the
# aether repo, which compiles these engine sources into its own binary), the
# `rea` binary is unused, so skip it.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    add_executable(rea ${REA_SOURCES})
    target_link_libraries(rea PRIVATE pscal_core_static Threads::Threads m)

    # ---- Install --------------------------------------------------------------
    # `cmake --install build` puts `rea` on PATH and ships the example programs
    # and the language docs beside it. These rules live inside the top-level guard
    # because the `rea` target only exists here; when rea is consumed via
    # FetchContent (e.g. by aether) there is no `rea` target to install, and the
    # fetched pscal-core dependency declares no install rules of its own.
    include(GNUInstallDirs)
    install(TARGETS rea RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/examples/
            DESTINATION ${CMAKE_INSTALL_DATADIR}/rea/examples)
    install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/docs/
            DESTINATION ${CMAKE_INSTALL_DOCDIR})
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/README.md
            DESTINATION ${CMAKE_INSTALL_DOCDIR})

    # ---- Test -----------------------------------------------------------------
    # `ctest` runs the .rea conformance corpus in tests/ against the binary just
    # built. The runner defaults REA_BIN to ./build/rea; pin it at the freshly
    # built target so out-of-tree build dirs work too.
    enable_testing()
    add_test(NAME rea_tests COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/run.sh)
    set_tests_properties(rea_tests PROPERTIES
        ENVIRONMENT "REA_BIN=$<TARGET_FILE:rea>")
endif()
