cmake_minimum_required(VERSION 3.20)
project(libhumspansynth VERSION 0.1.0 LANGUAGES CXX)

option(HUMSPAN_BUILD_TESTS "Build libhumspansynth unit tests" ON)

add_library(humspansynth STATIC
    src/engine/engine.cpp
)
add_library(humspan::synth ALIAS humspansynth)

target_include_directories(humspansynth
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src ${CMAKE_CURRENT_SOURCE_DIR}/src/engine
)
target_compile_features(humspansynth PUBLIC cxx_std_20)
set_target_properties(humspansynth PROPERTIES CXX_EXTENSIONS OFF POSITION_INDEPENDENT_CODE ON)

if(MSVC)
    target_compile_options(humspansynth PRIVATE /W4 /permissive-)
else()
    target_compile_options(humspansynth PRIVATE -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wno-sign-conversion)
endif()

if(HUMSPAN_BUILD_TESTS)
    enable_testing()
    add_executable(humspansynth_tests tests/engine_tests.cpp)
    target_link_libraries(humspansynth_tests PRIVATE humspan::synth)
    target_include_directories(humspansynth_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    add_test(NAME humspansynth_tests COMMAND humspansynth_tests)
endif()
