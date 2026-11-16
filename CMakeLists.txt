cmake_minimum_required(VERSION 3.20)
project(ambient_sound_loop LANGUAGES CXX)

option(AMBIENT_BUILD_DESKTOP "Build the miniaudio desktop player (downloads miniaudio.h)" ON)

enable_testing()
add_subdirectory(core-cpp)

if(AMBIENT_BUILD_DESKTOP)
    add_subdirectory(platform-audio/desktop)
endif()
