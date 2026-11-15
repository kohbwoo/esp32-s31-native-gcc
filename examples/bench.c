/* Same loops as the MicroPython test: sum(range(1000000)) and an XOR loop.
 * volatile keeps the compiler from replacing the loop with a formula. */
#include <stdio.h>
#include <stdint.h>
#include <time.h>

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

int main(void) {
    const uint32_t N = 1000000;

    double t0 = now_ms();
    volatile uint64_t sum = 0;
    for (uint32_t i = 0; i < N; i++) sum += i;
    double t1 = now_ms();

    volatile uint32_t x = 0;
    for (uint32_t i = 0; i < N; i++) x ^= i;
    double t2 = now_ms();

    printf("sum = %llu  %.2f ms\n", (unsigned long long)sum, t1 - t0);
    printf("xor = %u  %.2f ms\n", (unsigned)x, t2 - t1);
    return 0;
}
