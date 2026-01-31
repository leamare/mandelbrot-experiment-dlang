module utils.precision_auto;

import std.math : log, log10, pow, floor, isFinite;
import std.algorithm : max, min, countUntil;
import std.conv : to;

import types.render : RenderConfig;

enum uint PRECISION_DIGITS_DOUBLE = 15;

enum uint PRECISION_DIGITS_QUADDOUBLE = 62;

enum uint PRECISION_DIGITS_MIN_MPFR = 50;

enum uint PRECISION_SAFETY_MARGIN = 20;

int getZoomExponent(string radiusStr) {
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

double computeLog10FromDecimal(string s) {
    if (s.length == 0) return 0.0;
    
    bool negative = false;
    if (s[0] == '-') {
        negative = true;
        s = s[1 .. $];
    } else if (s[0] == '+') {
        s = s[1 .. $];
    }
    
    auto ePos = s.countUntil!(c => c == 'e' || c == 'E')();
    if (ePos >= 0) {
        try {
            int exp = to!int(s[ePos + 1 .. $]);
            string mantissa = s[0 .. ePos];
            
            double mantVal = to!double(mantissa);
            if (mantVal > 0) {
                return log10(mantVal) + exp;
            }
        } catch (Exception) {}
    }
    
    try {
        double val = to!double(s);
        if (val > 0) return log10(val);
    } catch (Exception) {}
    
    return 0.0;
}

uint coordinatePrecisionDigits(string coordStr) {
    if (coordStr.length == 0) return 0;
    
    size_t start = 0;
    if (coordStr[0] == '-' || coordStr[0] == '+') start = 1;
    
    uint digitCount = 0;
    bool foundNonZero = false;
    bool inFraction = false;
    
    foreach (c; coordStr[start .. $]) {
        if (c == '.') {
            inFraction = true;
            continue;
        }
        if (c == 'e' || c == 'E') break;
        
        if (c >= '0' && c <= '9') {
            if (c != '0') foundNonZero = true;
            if (foundNonZero) digitCount++;
        }
    }
    
    return digitCount;
}

uint viewportPrecisionDigits(double radius, int width, int height) {
    if (radius <= 0 || !isFinite(radius)) return PRECISION_DIGITS_DOUBLE;
    
    int maxDim = max(width, height);
    if (maxDim <= 0) return PRECISION_DIGITS_DOUBLE;
    
    double pixelSpacing = (radius * 2.0) / maxDim;
    if (pixelSpacing <= 0 || !isFinite(pixelSpacing)) {
        return PRECISION_DIGITS_DOUBLE;
    }
    
    return cast(uint)max(0, -log10(pixelSpacing)) + PRECISION_SAFETY_MARGIN;
}

double digitsPerPixel(double radius, int width, int height, string radiusStr = "") {
    int maxDim = max(width, height);
    if (maxDim <= 0) return 0.0;
    
    double pixelSpacing = (radius * 2.0) / maxDim;
    if (pixelSpacing > 0 && isFinite(pixelSpacing)) {
        return -log10(pixelSpacing);
    }
    
    if (radiusStr.length > 0) {
        int exp = getZoomExponent(radiusStr);
        if (exp != 0) {
            double logMaxDim = log10(cast(double)maxDim);
            double logPixelSpacing = log10(2.0) + exp - logMaxDim;
            return -logPixelSpacing * 1.25;
        }
    }
    
    return 0.0;
}

string trimCoordinatePrecision(string coordStr, uint maxDigits) {
    if (coordStr.length == 0 || maxDigits == 0) return coordStr;
    
    size_t start = 0;
    if (coordStr[0] == '-' || coordStr[0] == '+') start = 1;
    
    uint digitCount = 0;
    size_t lastDigit = start;
    bool foundNonZero = false;
    
    foreach (i, c; coordStr[start .. $]) {
        if (c == 'e' || c == 'E') {
            lastDigit = start + i;
            break;
        }
        if (c >= '0' && c <= '9') {
            if (c != '0') foundNonZero = true;
            if (foundNonZero) {
                digitCount++;
                lastDigit = start + i + 1;
                if (digitCount >= maxDigits) break;
            }
        }
    }
    
    auto ePos = coordStr.countUntil!(c => c == 'e' || c == 'E')();
    if (ePos >= 0) {
        return coordStr[0 .. lastDigit] ~ coordStr[ePos .. $];
    }
    
    return coordStr[0 .. lastDigit];
}

uint clampCoordinateDigits(string coordStr, uint maxDigits) {
    uint actual = coordinatePrecisionDigits(coordStr);
    return min(actual, maxDigits);
}

uint combinedPrecisionDigits(string originXStr, string originYStr, 
                             string radiusStr, double radius) {
    uint xDigits = coordinatePrecisionDigits(originXStr);
    uint yDigits = coordinatePrecisionDigits(originYStr);
    uint rDigits = coordinatePrecisionDigits(radiusStr);
    
    uint coordDigits = max(xDigits, max(yDigits, rDigits));
    
    double logRadius = computeLog10FromDecimal(radiusStr);
    if (logRadius < -10) {
        coordDigits = cast(uint)max(coordDigits, -logRadius + PRECISION_SAFETY_MARGIN);
    }
    
    return max(coordDigits, PRECISION_DIGITS_MIN_MPFR);
}

