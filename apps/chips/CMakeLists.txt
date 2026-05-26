cmake_minimum_required(VERSION 3.20)
project(chips_example VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# pull in the sf_voice SDK from the repo root
add_subdirectory(../../cpp sf_voice_build)

add_executable(chips_example src/main.cpp)

target_link_libraries(chips_example PRIVATE sf_voice)

target_include_directories(chips_example PRIVATE ../../cpp/include)
