/**
 * Automatic calculation of dwell, palette, and precision
 */
module precision.auto_settings;

import std.math : log10, floor, ceil, abs;
import std.conv : to;
import std.string : strip, indexOf;
import std.algorithm : max, min, countUntil;

import precision.constants;
import precision.method;

// =============================================================================
// Auto-Dwell Estimation
// =============================================================================

uint estimateDwell(string radiusStr) {
    double log10Radius = computeLog10FromDecimal(radiusStr, 2.0);
    double depth = -log10Radius;
    
    if (depth <= 0) {
        return 100;
    }
    
    double estimated = 100.0 * pow(depth, 1.5);
    
    uint result = cast(uint)min(max(estimated, 100.0), 1_000_000.0);
    
    if (result > 1000) {
        result = (result / 1000) * 1000;
    } else if (result > 100) {
        result = (result / 100) * 100;
    }
    
    return result;
}

uint estimatePalette(uint dwell) {
    uint estimated = max(100, dwell / 5);
    
    if (estimated > 1000) {
        estimated = (estimated / 100) * 100;
    } else if (estimated > 100) {
        estimated = (estimated / 50) * 50;
    }
    
    return min(estimated, 10000);
}

// =============================================================================
// Precision Estimation
// =============================================================================

uint viewportPrecisionDigits(string radiusStr, real fallbackRadius = 2.0) {
    double log10Radius = computeLog10FromDecimal(radiusStr, fallbackRadius);
    
    if (log10Radius >= 0) {
        return 0;
    }
    
    return cast(uint)ceil(-log10Radius) + PRECISION_SAFETY_MARGIN;
}

uint coordinatePrecisionDigits(string coordStr) {
    coordStr = coordStr.strip();
    if (coordStr.length == 0) return 0;
    
    auto dotPos = coordStr.indexOf('.');
    if (dotPos < 0) return 0;
    
    uint digits = 0;
    for (size_t i = dotPos + 1; i < coordStr.length; i++) {
        char c = coordStr[i];
        if (c >= '0' && c <= '9') {
            digits++;
        } else if (c == 'e' || c == 'E') {
            break;
        }
    }
    
    auto ePos = coordStr.countUntil!(c => c == 'e' || c == 'E')();
    if (ePos >= 0) {
        try {
            int exp = to!int(coordStr[ePos + 1 .. $]);
            if (exp < 0) {
                digits += cast(uint)(-exp);
            }
        } catch (Exception) {}
    }
    
    return digits;
}

uint combinedPrecisionDigits(string originXStr, string originYStr, string radiusStr, real fallbackRadius = 2.0) {
    uint viewportDigits = viewportPrecisionDigits(radiusStr, fallbackRadius);
    uint coordXDigits = coordinatePrecisionDigits(originXStr);
    uint coordYDigits = coordinatePrecisionDigits(originYStr);
    uint coordDigits = max(coordXDigits, coordYDigits);
    
    return max(viewportDigits, coordDigits);
}

double digitsPerPixel(int imageSize, string radiusStr, real fallbackRadius = 2.0) {
    if (imageSize <= 0) return 0;
    
    double log10Radius = computeLog10FromDecimal(radiusStr, fallbackRadius);
    double pixelRadius = log10Radius - log10(cast(double)imageSize);
    
    return max(0.0, -pixelRadius + 5.0);
}

// =============================================================================
// Helpers
// =============================================================================

double computeLog10FromDecimal(string str, real fallback = 1.0) {
    str = str.strip();
    if (str.length == 0) {
        return log10(cast(double)abs(fallback));
    }
    
    auto ePos = str.countUntil!(c => c == 'e' || c == 'E')();
    if (ePos >= 0) {
        try {
            string mantissaStr = str[0 .. ePos];
            int exp = to!int(str[ePos + 1 .. $]);
            
            double mantissa = 1.0;
            try {
                mantissa = to!double(mantissaStr);
            } catch (Exception) {}
            
            return log10(abs(mantissa)) + cast(double)exp;
        } catch (Exception) {}
    }
    
    try {
        double val = to!double(str);
        if (val != 0 && !val.isNaN && !val.isInfinity) {
            return log10(abs(val));
        }
    } catch (Exception) {}
    
    return log10(cast(double)abs(fallback));
}

private double pow(double base, double exp) {
    import std.math : pow_ = pow;
    return pow_(base, exp);
}

private bool isNaN(double x) {
    return x != x;
}

private bool isInfinity(double x) {
    return x == double.infinity || x == -double.infinity;
}

