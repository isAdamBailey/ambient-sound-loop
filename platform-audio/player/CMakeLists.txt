# The app's native audio layer (engine + miniaudio stream). The app builds it
# with its own build hook; this target compiles it in CI on every desktop OS.
add_library(ambient_player STATIC ambient_player.cpp miniaudio_impl.cpp)
target_include_directories(ambient_player PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_include_directories(ambient_player SYSTEM PRIVATE ${MINIAUDIO_INCLUDE_DIR})
target_compile_definitions(ambient_player PRIVATE
    MA_NO_DECODING MA_NO_ENCODING MA_NO_GENERATION MA_NO_RESOURCE_MANAGER MA_NO_NODE_GRAPH MA_NO_ENGINE)
target_link_libraries(ambient_player PUBLIC ambient::synth)
target_compile_features(ambient_player PRIVATE cxx_std_20)
