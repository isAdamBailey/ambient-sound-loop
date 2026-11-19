# miniaudio desktop harness.
add_executable(humspan_play main.cpp)
target_include_directories(humspan_play SYSTEM PRIVATE ${MINIAUDIO_INCLUDE_DIR})
target_link_libraries(humspan_play PRIVATE humspan::synth)
target_compile_features(humspan_play PRIVATE cxx_std_20)

find_package(Threads REQUIRED)
target_link_libraries(humspan_play PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
if(UNIX AND NOT APPLE)
    target_link_libraries(humspan_play PRIVATE m)
endif()
if(APPLE)
    target_link_libraries(humspan_play PRIVATE "-framework CoreFoundation" "-framework CoreAudio" "-framework AudioToolbox")
endif()
