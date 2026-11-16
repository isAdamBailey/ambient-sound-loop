# miniaudio desktop harness. miniaudio is a single header, downloaded at
# configure time and pinned by hash.
set(MINIAUDIO_VERSION 0.11.21)
set(MINIAUDIO_HEADER ${CMAKE_CURRENT_BINARY_DIR}/third_party/miniaudio.h)
if(NOT EXISTS ${MINIAUDIO_HEADER})
    file(DOWNLOAD
        https://raw.githubusercontent.com/mackron/miniaudio/${MINIAUDIO_VERSION}/miniaudio.h
        ${MINIAUDIO_HEADER}
        EXPECTED_HASH SHA256=6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9
        TLS_VERIFY ON
        STATUS MINIAUDIO_STATUS)
    list(GET MINIAUDIO_STATUS 0 MINIAUDIO_STATUS_CODE)
    if(NOT MINIAUDIO_STATUS_CODE EQUAL 0)
        message(FATAL_ERROR "Downloading miniaudio failed: ${MINIAUDIO_STATUS}")
    endif()
endif()

add_executable(ambient_play main.cpp)
target_include_directories(ambient_play SYSTEM PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/third_party)
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
