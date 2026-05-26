"""
Conan 2 recipe for sf_voice — header-only C++17 SDK for the sf-voice media API.

Usage (consumer):
    conan install . --output-folder=build --build=missing
    cmake -B build -DCMAKE_TOOLCHAIN_FILE=build/conan_toolchain.cmake
    cmake --build build
"""

from conan import ConanFile
from conan.tools.cmake import CMake, CMakeToolchain, cmake_layout
from conan.tools.files import copy
import os


class SfVoiceMediaConan(ConanFile):
    name        = "sf_voice"
    version     = "0.1.0"
    license     = "MIT"
    description = "Header-only C++17 SDK for the sf-voice media API"
    url         = "https://github.com/sf-voice/sf-voice-core"
    homepage    = "https://sf-voice.com"
    topics      = ("media", "video", "audio", "sdk", "http", "header-only")

    # header-only: no compiler/os/arch settings needed
    package_type = "header-library"
    settings     = "os", "compiler", "build_type", "arch"

    # consumers need cpr and nlohmann_json at build time
    requires = [
        "cpr/1.10.5",
        "nlohmann_json/3.11.3",
    ]

    # nothing to compile — no generators beyond CMakeDeps/CMakeToolchain
    generators = "CMakeDeps", "CMakeToolchain"

    exports_sources = "include/*", "CMakeLists.txt", "cmake/*"

    def layout(self):
        cmake_layout(self)

    def package(self):
        # copy headers into the conan package store
        copy(self, "*.hpp",
             src=os.path.join(self.source_folder, "include"),
             dst=os.path.join(self.package_folder, "include"))

    def package_info(self):
        # header-only: no lib to link, just set the include path
        self.cpp_info.bindirs  = []
        self.cpp_info.libdirs  = []
        self.cpp_info.set_property("cmake_file_name",   "sf_voice")
        self.cpp_info.set_property("cmake_target_name", "sf_voice::sf_voice")

    def package_id(self):
        # header-only packages are abi-independent
        self.info.clear()
