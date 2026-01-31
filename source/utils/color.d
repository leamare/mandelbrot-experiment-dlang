module utils.color;

import std.math : log, log10, pow, floor;

uint estimatePalette(uint dwell) {
    if (dwell <= 100) return dwell;
    if (dwell <= 1000) return cast(uint)(dwell * 0.5 + 50);
    if (dwell <= 10000) return cast(uint)(dwell * 0.3 + 200);
    return cast(uint)(dwell * 0.2 + 1000);
}

