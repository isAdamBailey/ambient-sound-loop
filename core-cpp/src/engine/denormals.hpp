// Scoped flush-to-zero / denormals-are-zero for the render thread. IIR
// filters, the brown integrator and fade-outs decay towards zero; denormal
// arithmetic is very slow on x86 and would spike CPU in the overnight tail.
#pragma once

#include <cstdint>

#if defined(__SSE__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 1)
#include <xmmintrin.h>
#define AMBIENT_FTZ_SSE 1
#endif

namespace ambient::engine {

class ScopedFlushDenormals {
public:
    ScopedFlushDenormals() noexcept {
#if defined(AMBIENT_FTZ_SSE)
        saved_ = _mm_getcsr();
        _mm_setcsr(static_cast<unsigned>(saved_) | 0x8040u); // FTZ (bit 15) | DAZ (bit 6)
#elif defined(__aarch64__)
        uint64_t fpcr;
        __asm__ __volatile__("mrs %0, fpcr" : "=r"(fpcr));
        saved_ = fpcr;
        fpcr |= (1ull << 24); // FZ
        __asm__ __volatile__("msr fpcr, %0" : : "r"(fpcr));
#endif
    }

    ~ScopedFlushDenormals() {
#if defined(AMBIENT_FTZ_SSE)
        _mm_setcsr(static_cast<unsigned>(saved_));
#elif defined(__aarch64__)
        uint64_t fpcr = saved_;
        __asm__ __volatile__("msr fpcr, %0" : : "r"(fpcr));
#endif
    }

    ScopedFlushDenormals(const ScopedFlushDenormals&) = delete;
    ScopedFlushDenormals& operator=(const ScopedFlushDenormals&) = delete;

private:
    uint64_t saved_ = 0;
};

} // namespace ambient::engine
