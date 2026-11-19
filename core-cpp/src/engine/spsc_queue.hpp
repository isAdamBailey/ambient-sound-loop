// Bounded single-producer single-consumer lock-free queue. Storage is inline,
// so neither push nor pop ever allocates.
#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <optional>
#include <type_traits>

namespace humspan::engine {

template <typename T, std::size_t Capacity>
class SpscQueue {
    static_assert(std::is_trivially_copyable_v<T>);
    static_assert((Capacity & (Capacity - 1)) == 0, "Capacity must be a power of two");

public:
    // Producer thread only. Returns false when full (never blocks).
    bool push(const T& item) noexcept {
        const std::size_t head = head_.load(std::memory_order_relaxed);
        if (head - tail_.load(std::memory_order_acquire) == Capacity) {
            return false;
        }
        slots_[head & (Capacity - 1)] = item;
        head_.store(head + 1, std::memory_order_release);
        return true;
    }

    // Consumer thread only.
    std::optional<T> pop() noexcept {
        const std::size_t tail = tail_.load(std::memory_order_relaxed);
        if (tail == head_.load(std::memory_order_acquire)) {
            return std::nullopt;
        }
        T item = slots_[tail & (Capacity - 1)];
        tail_.store(tail + 1, std::memory_order_release);
        return item;
    }

private:
    std::array<T, Capacity> slots_{};
    alignas(64) std::atomic<std::size_t> head_{0};
    alignas(64) std::atomic<std::size_t> tail_{0};
};

} // namespace humspan::engine
