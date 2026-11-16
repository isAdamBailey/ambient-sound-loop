cmake_minimum_required(VERSION 3.20)
project(libambientsynth VERSION 0.1.0 LANGUAGES CXX)

option(AMBIENT_BUILD_TESTS "Build libambientsynth unit tests" ON)

add_library(ambientsynth STATIC
    src/engine/engine.cpp
)
add_library(ambient::synth ALIAS ambientsynth)

target_include_directories(ambientsynth
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src ${CMAKE_CURRENT_SOURCE_DIR}/src/engine
)
target_compile_features(ambientsynth PUBLIC cxx_std_20)
set_target_properties(ambientsynth PROPERTIES CXX_EXTENSIONS OFF POSITION_INDEPENDENT_CODE ON)

if(MSVC)
    target_compile_options(ambientsynth PRIVATE /W4 /permissive-)
else()
    target_compile_options(ambientsynth PRIVATE -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wno-sign-conversion)
endif()

if(AMBIENT_BUILD_TESTS)
    enable_testing()
    add_executable(ambientsynth_tests tests/engine_tests.cpp)
    target_link_libraries(ambientsynth_tests PRIVATE ambient::synth)
    target_include_directories(ambientsynth_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    add_test(NAME ambientsynth_tests COMMAND ambientsynth_tests)
endif()
