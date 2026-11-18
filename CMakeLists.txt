cmake_minimum_required(VERSION 3.20)
project(ambient_sound_loop LANGUAGES CXX)

option(AMBIENT_BUILD_DESKTOP "Build the miniaudio desktop player and app audio layer (downloads miniaudio.h)" ON)

enable_testing()
add_subdirectory(core-cpp)

if(AMBIENT_BUILD_DESKTOP)
    include(cmake/miniaudio.cmake)
    add_subdirectory(platform-audio/desktop)
    add_subdirectory(platform-audio/player)
endif()
