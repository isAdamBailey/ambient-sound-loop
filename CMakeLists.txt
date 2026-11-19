cmake_minimum_required(VERSION 3.20)
project(humspan LANGUAGES CXX)

option(HUMSPAN_BUILD_DESKTOP "Build the miniaudio desktop player and app audio layer (downloads miniaudio.h)" ON)

enable_testing()
add_subdirectory(core-cpp)

if(HUMSPAN_BUILD_DESKTOP)
    include(cmake/miniaudio.cmake)
    add_subdirectory(platform-audio/desktop)
    add_subdirectory(platform-audio/player)
endif()
