cmake_minimum_required(VERSION 3.20)
project(sf_voice VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── options ────────────────────────────────────────────────────────────────
option(SF_VOICE_INSTALL "Install cmake targets and headers" ON)
option(SF_VOICE_EXAMPLES "Build the bundled examples" OFF)

# ── dependencies via FetchContent ──────────────────────────────────────────
include(FetchContent)

# nlohmann/json — header-only json library
FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
    GIT_SHALLOW    TRUE
)

# cpr — curl wrapper with a clean c++ api
FetchContent_Declare(
    cpr
    GIT_REPOSITORY https://github.com/libcpr/cpr.git
    GIT_TAG        1.10.5
    GIT_SHALLOW    TRUE
)

# only build what we need from cpr
set(CPR_BUILD_TESTS     OFF CACHE BOOL "" FORCE)
set(CPR_BUILD_EXAMPLES  OFF CACHE BOOL "" FORCE)
set(CPR_USE_SYSTEM_CURL ON  CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(nlohmann_json cpr)

# ── interface library ──────────────────────────────────────────────────────
# header-only: INTERFACE target, no compiled translation units
add_library(sf_voice INTERFACE)
add_library(sf_voice::sf_voice ALIAS sf_voice)

target_include_directories(sf_voice
    INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)

target_link_libraries(sf_voice
    INTERFACE
        nlohmann_json::nlohmann_json
        cpr::cpr
)

target_compile_features(sf_voice INTERFACE cxx_std_17)

# ── optional examples ──────────────────────────────────────────────────────
if(SF_VOICE_EXAMPLES)
    add_subdirectory(examples)
endif()

# ── install rules ──────────────────────────────────────────────────────────
if(SF_VOICE_INSTALL)
    include(GNUInstallDirs)
    include(CMakePackageConfigHelpers)

    install(
        TARGETS sf_voice
        EXPORT  sf_voiceTargets
    )

    install(
        DIRECTORY include/
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )

    install(
        EXPORT      sf_voiceTargets
        FILE        sf_voiceTargets.cmake
        NAMESPACE   sf_voice::
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/sf_voice
    )

    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/sf_voiceConfigVersion.cmake"
        VERSION       ${PROJECT_VERSION}
        COMPATIBILITY SameMajorVersion
    )

    configure_package_config_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/sf_voiceConfig.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/sf_voiceConfig.cmake"
        INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/sf_voice
    )

    install(
        FILES
            "${CMAKE_CURRENT_BINARY_DIR}/sf_voiceConfig.cmake"
            "${CMAKE_CURRENT_BINARY_DIR}/sf_voiceConfigVersion.cmake"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/sf_voice
    )
endif()
