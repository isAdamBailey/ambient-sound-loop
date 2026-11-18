// The miniaudio implementation, compiled once. On Apple platforms it is built
// from miniaudio_impl.mm instead, because the iOS backend is Objective-C.
// Feature switches (MA_NO_DECODING etc.) come from the build so that every
// file including miniaudio.h sees the same configuration.
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
