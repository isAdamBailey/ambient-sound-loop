# miniaudio is a single header, downloaded at configure time and pinned by
# hash. The app's build hook (app-ui/native/hook/build.dart) pins the same
# version and hash.
set(MINIAUDIO_VERSION 0.11.21)
set(MINIAUDIO_INCLUDE_DIR ${CMAKE_BINARY_DIR}/third_party)
set(MINIAUDIO_HEADER ${MINIAUDIO_INCLUDE_DIR}/miniaudio.h)
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
