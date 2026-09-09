#include <cstdlib>

#include "ra/sim.h"

namespace ra {

const char* version() { return "0.13.0"; }

int32_t isqrt(int64_t v) {
    if (v <= 0) return 0;
    int64_t x = v, y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + v / x) / 2;
    }
    return static_cast<int32_t>(x);
}


static int32_t atan_unit(int64_t t) {
    constexpr int64_t ONE = 65536;
    const int64_t g = t * (ONE - t) / ONE;
    const int64_t k = 16036 + (4345 * t) / ONE;
    const int64_t corr = (g * k) / ONE;
    return static_cast<int32_t>((128 * t + 163 * corr) / ONE);
}

WAngle iatan2(int64_t y, int64_t x) {
    if (x == 0 && y == 0) return 0;
    const int64_t ax = x < 0 ? -x : x;
    const int64_t ay = y < 0 ? -y : y;
    int32_t a = (ay <= ax) ? atan_unit(ay * 65536 / ax) : 256 - atan_unit(ax * 65536 / ay);
    if (x < 0) a = 512 - a;
    if (y < 0) a = -a;
    return wrap_angle(a);
}


static int32_t sin1024(WAngle a) {
    a = wrap_angle(a);
    const bool neg = a >= 512;
    if (neg) a -= 512;
    const int64_t t = int64_t(a) * 180 / 512;
    const int64_t p = t * (180 - t);
    const int64_t s = 4 * p * 1024 / (40500 - p);
    return static_cast<int32_t>(neg ? -s : s);
}

WVec direction_of(WAngle a) {

    return {-sin1024(a), -sin1024(a + 256)};
}

WAngle turn_towards(WAngle from, WAngle to, WAngle max_step) {
    WAngle d = angle_diff(from, to);
    if (d > max_step) d = max_step;
    if (d < -max_step) d = -max_step;
    return wrap_angle(from + d);
}

}
