module gmp_arb;

version (NoGMP) {
    static assert(false, "GMP not available. Please install gmp-d or implement bigint fallback.");
} else {
    import gmp;
}

import std.conv;
import std.string;
import std.algorithm : max, min, countUntil;
import std.math : log10, floor, pow, sqrt, log;

/**
 * GMP-based Arbitrary Precision Float using fixed-point arithmetic
 * Uses MpZ (integers) with a scale factor to represent decimals
 */
struct GMPFloat {
    private MpZ value;
    private static long scale = 1000000000000000000L;
    
    static uint precision = 256;
    
    static void setPrecisionDigits(uint digits) {
        precision = cast(uint)(digits * 3.32 + 32);
        scale = cast(long)pow(10.0, cast(double)min(digits, 18));
    }
    
    /// Construct zero
    static GMPFloat zero() {
        GMPFloat r;
        r.value = MpZ(0);
        return r;
    }
    
    /// Construct from double
    this(double d) {
        value = MpZ(cast(long)(d * scale));
    }
    
    /// Construct from string
    this(string s) {
        s = s.strip();
        if (s.length == 0 || s == "0") {
            value = MpZ(0);
            return;
        }
        
        // Parse string and scale
        double d;
        try {
            d = to!double(s);
            value = MpZ(cast(long)(d * scale));
        } catch (Exception) {
            value = MpZ(0);
        }
    }
    
    /// Copy constructor - create new MpZ from value
    this(ref const GMPFloat other) {
        // Revert to string conversion - arithmetic copying caused segfaults
        // The issue is that MpZ arithmetic might not create proper independent copies
        string str = other.value.toString();
        value = MpZ(str);
    }
    
    /// Convert to double
    /// Uses string conversion for safety (avoids overflow from cast(long))
    double toDouble() const {
        // Direct cast to long can overflow for large MpZ values, causing segfaults
        // Use MpZ's toString() method directly (not our toString() to avoid circular dependency)
        string str = value.toString();  // This is MpZ's toString, not GMPFloat's
        double d;
        try {
            d = to!double(str);
        } catch (Exception) {
            // If string conversion fails, try direct cast as fallback
            try {
                long v = cast(long)value;
                return cast(double)v / cast(double)scale;
            } catch (Exception) {
                return 0.0;
            }
        }
        return d / cast(double)scale;
    }
    
    /// Convert to string
    string toString() const {
        // Use toDouble() which uses MpZ's toString() directly (no circular dependency)
        double d = toDouble();
        return format!"%.17g"(d);
    }
    
    /// Check if zero
    bool isZero() const {
        return value == 0;
    }
    
    /// Negation
    GMPFloat opUnary(string op)() const if (op == "-") {
        GMPFloat r;
        r.value = -value;
        return r;
    }
    
    /// Absolute value
    GMPFloat abs() const {
        GMPFloat r;
        if (value < 0) {
            r.value = -value;
        } else {
            r.value = value;
        }
        return r;
    }
    
    /// Addition
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "+") {
        GMPFloat r;
        r.value = value + rhs.value;
        return r;
    }
    
    /// Subtraction
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "-") {
        GMPFloat r;
        r.value = value - rhs.value;
        return r;
    }
    
    /// Multiplication
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "*") {
        GMPFloat r;
        // (a * scale) * (b * scale) / scale = a * b * scale
        r.value = (value * rhs.value) / scale;
        return r;
    }
    
    /// Division
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "/") {
        GMPFloat r;
        // (a * scale) / (b * scale) * scale = (a / b) * scale
        r.value = (value * scale) / rhs.value;
        return r;
    }
    
    /// Scalar multiplication (double)
    GMPFloat opBinary(string op)(double rhs) const if (op == "*") {
        GMPFloat r;
        r.value = (value * cast(long)(rhs * scale)) / scale;
        return r;
    }
    
    GMPFloat opBinaryRight(string op)(double lhs) const if (op == "*") {
        return this * lhs;
    }
    
    /// Comparison
    int opCmp(const GMPFloat rhs) const {
        if (value < rhs.value) return -1;
        if (value > rhs.value) return 1;
        return 0;
    }
    
    int opCmp(double rhs) const {
        return opCmp(GMPFloat(rhs));
    }
    
    bool opEquals(const GMPFloat rhs) const {
        return value == rhs.value;
    }
    
    /// Op-assign
    ref GMPFloat opOpAssign(string op, T)(T rhs) {
        this = mixin("this " ~ op ~ " rhs");
        return this;
    }
    
    /// Assignment operator (by value - for rvalues)
    ref GMPFloat opAssign(GMPFloat rhs) {
        // Try direct MpZ assignment first (faster than string conversion)
        // MpZ should support direct assignment
        value = rhs.value;
        return this;
    }
    
    /// Assignment operator (by ref - for lvalues)
    ref GMPFloat opAssign(ref const GMPFloat rhs) {
        if (this is rhs) return this;
        // Try direct MpZ assignment first (faster than string conversion)
        value = rhs.value;
        return this;
    }
}

/// Square function
GMPFloat sqr(const GMPFloat x) {
    return x * x;
}

/// Absolute value function
GMPFloat abs(const GMPFloat x) {
    return x.abs();
}

/**
 * GMP-based Complex Number
 */
struct GMPComplex {
    GMPFloat re;
    GMPFloat im;
    
    // No postblit needed - copy constructor handles it
    
    /// Construct from two GMPFloats
    this(GMPFloat r, GMPFloat i) {
        re = r;
        im = i;
    }
    
    /// Construct from doubles
    this(double r, double i) {
        re = GMPFloat(r);
        im = GMPFloat(i);
    }
    
    /// Construct from strings
    this(string rStr, string iStr) {
        re = GMPFloat(rStr);
        im = GMPFloat(iStr);
    }
    
    /// Copy constructor - directly copy GMPFloat members (avoids string conversion)
    this(ref const GMPComplex other) {
        // Direct assignment - GMPFloat's opAssign will handle MpZ copying
        re = other.re;
        im = other.im;
    }
    
    /// Zero complex
    static GMPComplex zero() {
        return GMPComplex(GMPFloat.zero(), GMPFloat.zero());
    }
    
    /// Magnitude squared: |z|² = re² + im²
    GMPFloat magnitudeSquared() const {
        return sqr(re) + sqr(im);
    }
    
    /// Convert to double magnitude squared (for escape check)
    /// Optimized: tries to avoid full precision conversion when possible
    double magnitudeSquaredDouble() const {
        // Try to get approximate magnitude first using MpZ comparison
        // If the value is clearly huge, we can skip precise conversion
        double r = re.toDouble();
        double i = im.toDouble();
        return r * r + i * i;
    }
    
    /// Fast approximate magnitude check (avoids toDouble if possible)
    /// Returns true if magnitude is clearly > threshold
    bool magnitudeSquaredGreaterThanApprox(double threshold2) const {
        // Quick check: if either component is huge, we're definitely escaped
        // This avoids expensive toDouble() calls
        // For now, just use the regular method, but this is a placeholder for future optimization
        return magnitudeSquaredDouble() > threshold2;
    }
    
    /// Addition
    GMPComplex opBinary(string op)(const GMPComplex rhs) const if (op == "+") {
        return GMPComplex(re + rhs.re, im + rhs.im);
    }
    
    /// Subtraction
    GMPComplex opBinary(string op)(const GMPComplex rhs) const if (op == "-") {
        return GMPComplex(re - rhs.re, im - rhs.im);
    }
    
    /// Multiplication: (a+bi)(c+di) = (ac-bd) + (ad+bc)i
    GMPComplex opBinary(string op)(const GMPComplex rhs) const if (op == "*") {
        return GMPComplex(
            re * rhs.re - im * rhs.im,
            re * rhs.im + im * rhs.re
        );
    }
    
    /// Scalar multiplication
    GMPComplex opBinary(string op)(double rhs) const if (op == "*") {
        return GMPComplex(re * rhs, im * rhs);
    }
    
    /// Square: z² = (a+bi)² = a²-b² + 2abi
    GMPComplex square() const {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto reim2 = re * im * 2.0;
        return GMPComplex(re2 - im2, reim2);
    }
    
    /// In-place square and add: z = z² + c
    /// Optimized to use direct MpZ assignment (faster than string conversion)
    void squareAndAdd(const GMPComplex c) {
        // Compute z² components using arithmetic (creates new MpZ values internally)
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto reim2 = re * im * 2.0;
        
        // Compute new values: z² + c
        // New re = (re² - im²) + c.re
        // New im = (2*re*im) + c.im
        // These arithmetic operations create new GMPFloat objects with new MpZ values
        auto newRe = re2 - im2 + c.re;
        auto newIm = reim2 + c.im;
        
        // Use direct MpZ assignment (should be faster than string conversion)
        // MpZ supports direct assignment which creates a copy
        re.value = newRe.value;
        im.value = newIm.value;
    }
    
    /// Assignment operator (by value - for rvalues)
    ref GMPComplex opAssign(GMPComplex rhs) {
        // Direct assignment - GMPFloat's opAssign handles copying
        re = rhs.re;
        im = rhs.im;
        return this;
    }
    
    /// Assignment operator (by ref - for lvalues)
    ref GMPComplex opAssign(ref const GMPComplex rhs) {
        if (this is rhs) return this;
        // Direct assignment - GMPFloat's opAssign handles copying
        re = rhs.re;
        im = rhs.im;
        return this;
    }
}

/**
 * Iterate Mandelbrot using GMP arbitrary precision
 * Returns: tuple of (iterations, smoothed_value)
 */
auto iterateGMP(string cRealStr, string cImagStr, uint maxIterations, double escapeRadius2 = 65536) {
    import std.typecons : tuple;
    
    auto c = GMPComplex(cRealStr, cImagStr);
    auto z = GMPComplex.zero();
    
    uint iter;
    for (iter = 0; iter < maxIterations; iter++) {
        // z = z² + c
        z = z.square() + c;
        
        // Check escape using double precision (faster)
        double mag2 = z.magnitudeSquaredDouble();
        if (mag2 > escapeRadius2) {
            // Smooth coloring
            double logZn = log(mag2) * 0.5;
            double nu = log(logZn / log(2.0)) / log(2.0);
            double smoothed = 1 + cast(double)iter - nu;
            return tuple(iter, smoothed);
        }
    }
    
    return tuple(maxIterations, cast(double)maxIterations);
}

/**
 * Pre-parsed constants for pixel-to-complex conversion
 * This avoids parsing strings for every pixel
 */
struct GMPPixelConverter {
    GMPFloat originX;
    GMPFloat originY;
    GMPFloat radius;
    double minDim;
    double di, dr;
    int width, height;
    
    /// Initialize converter with pre-parsed constants
    this(int w, int h, string originXStr, string originYStr, string radiusStr) {
        width = w;
        height = h;
        
        originX = GMPFloat(originXStr);
        originY = GMPFloat(originYStr);
        radius = GMPFloat(radiusStr);
        
        double wd = cast(double)w;
        double hd = cast(double)h;
        minDim = min(wd, hd);
        
        di = 0;
        dr = 0;
        if (w != h) {
            double diff = (max(wd, hd) - minDim) / minDim;
            di = w > h ? diff : 0;
            dr = w > h ? 0 : diff;
        }
    }
    
    /// Convert pixel to complex number
    GMPComplex pixelToComplex(int px, int py) const {
        double relX = (cast(double)px / minDim) * 2.0 - (1.0 + di);
        double relY = -((cast(double)py / minDim) * 2.0 - (1.0 + dr));
        
        GMPFloat relXGMP = GMPFloat(relX);
        GMPFloat relYGMP = GMPFloat(relY);
        
        GMPFloat offsetX = radius * relXGMP;
        GMPFloat offsetY = radius * relYGMP;
        
        GMPFloat cReal = originX + offsetX;
        GMPFloat cImag = originY + offsetY;
        
        return GMPComplex(cReal, cImag);
    }
}

/**
 * Convert pixel coordinates to complex number
 */
GMPComplex pixelToGMPComplex(
    int px, int py,
    int width, int height,
    string originXStr, string originYStr, string radiusStr
) {
    auto converter = GMPPixelConverter(width, height, originXStr, originYStr, radiusStr);
    return converter.pixelToComplex(px, py);
}
