# miniaudio desktop harness.
add_executable(ambient_play main.cpp)
target_include_directories(ambient_play SYSTEM PRIVATE ${MINIAUDIO_INCLUDE_DIR})
target_link_libraries(ambient_play PRIVATE ambient::synth)
target_compile_features(ambient_play PRIVATE cxx_std_20)

find_package(Threads REQUIRED)
target_link_libraries(ambient_play PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
if(UNIX AND NOT APPLE)
    target_link_libraries(ambient_play PRIVATE m)
endif()
if(APPLE)
    target_link_libraries(ambient_play PRIVATE "-framework CoreFoundation" "-framework CoreAudio" "-framework AudioToolbox")
endif()
