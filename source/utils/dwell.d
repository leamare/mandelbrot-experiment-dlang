module utils.dwell;

import std.math : pow, floor, log10;
import std.algorithm : countUntil;
import std.conv : to;

private int getZoomExponent(string radiusStr) {
    auto ePos = radiusStr.countUntil!(c => c == 'e' || c == 'E')();
    if (ePos >= 0) {
        try {
            return to!int(radiusStr[ePos + 1 .. $]);
        } catch (Exception) {}
    }
    try {
        double r = to!double(radiusStr);
        if (r > 0) return cast(int)floor(log10(r));
    } catch (Exception) {}
    return 0;
}

uint estimateDwell(string radiusStr) {
    int exp = getZoomExponent(radiusStr);
    int zoomDepth = -exp;
    
    if (zoomDepth <= 0) return 100;
    
    if (zoomDepth <= 15) {
        return cast(uint)(100 + zoomDepth * zoomDepth * 10);
    } else if (zoomDepth <= 50) {
        return cast(uint)(1000 + pow(cast(double)zoomDepth, 1.5) * 50);
    } else if (zoomDepth <= 200) {
        return cast(uint)(5000 + pow(cast(double)zoomDepth, 1.3) * 100);
    } else {
        return cast(uint)(20000 + pow(cast(double)zoomDepth, 1.2) * 50);
    }
}

uint estimateDwellFromRadius(double radius) {
    import std.format : format;
    return estimateDwell(format!"%.20e"(radius));
}

