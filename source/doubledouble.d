module doubledouble;

import std.math;
import std.conv;
import std.string;
import std.algorithm;

/**
 * Double-double arithmetic for extended precision (~31 decimal digits).
 * 
 * Represents a number as the unevaluated sum of two doubles: value = hi + lo
 * where |lo| <= ulp(hi)/2. This gives approximately 106 bits of mantissa
 * precision (~31 decimal digits) compared to double's 53 bits (~15 digits).
 * 
 * Much faster than arbitrary precision (BigInt) while sufficient for most
 * deep Mandelbrot zooms (down to about 10^-29).
 */
struct DoubleDouble {
    double hi = 0.0;  // High part
    double lo = 0.0;  // Low part (correction term)
    
    /// Construct from a single double
    this(double value) {
        hi = value;
        lo = 0.0;
    }
    
    /// Construct from a real
    this(real value) {
        hi = cast(double)value;
        lo = cast(double)(value - cast(real)hi);
    }
    
    /// Construct from two doubles (hi + lo)
    this(double h, double l) {
        // Normalize: ensure |lo| <= ulp(hi)/2
        auto s = h + l;
        auto e = l - (s - h);
        hi = s;
        lo = e;
    }
    
    /// Construct from string
    this(string str) {
        // Parse string to get high precision value
        // For very precise strings, we parse in parts
        str = str.strip();
        if (str.length == 0) {
            hi = 0;
            lo = 0;
            return;
        }
        
        // Try direct parsing first (works for most cases)
        try {
            real val = to!real(str);
            hi = cast(double)val;
            lo = cast(double)(val - cast(real)hi);
        } catch (Exception) {
            hi = 0;
            lo = 0;
        }
    }
    
    /// Convert to double (loses precision)
    double toDouble() const {
        return hi + lo;
    }
    
    /// Convert to real
    real toReal() const {
        return cast(real)hi + cast(real)lo;
    }
    
    /// Check if zero
    bool isZero() const {
        return hi == 0.0 && lo == 0.0;
    }
    
    /// Get sign
    int sign() const {
        if (hi > 0) return 1;
        if (hi < 0) return -1;
        if (lo > 0) return 1;
        if (lo < 0) return -1;
        return 0;
    }
    
    // =========================================================================
    // Core arithmetic operations using Dekker/Knuth algorithms
    // =========================================================================
    
    /// Quick two-sum: a + b = s + e (assumes |a| >= |b|)
    private static void quickTwoSum(double a, double b, out double s, out double e) {
        s = a + b;
        e = b - (s - a);
    }
    
    /// Two-sum: a + b = s + e (no assumption on magnitudes)
    private static void twoSum(double a, double b, out double s, out double e) {
        s = a + b;
        double v = s - a;
        e = (a - (s - v)) + (b - v);
    }
    
    /// Split a double into high and low parts for multiplication
    private static void split(double a, out double ahi, out double alo) {
        enum double SPLIT_FACTOR = 134217729.0; // 2^27 + 1
        double t = SPLIT_FACTOR * a;
        ahi = t - (t - a);
        alo = a - ahi;
    }
    
    /// Two-product: a * b = p + e
    private static void twoProd(double a, double b, out double p, out double e) {
        p = a * b;
        double ahi, alo, bhi, blo;
        split(a, ahi, alo);
        split(b, bhi, blo);
        e = ((ahi * bhi - p) + ahi * blo + alo * bhi) + alo * blo;
    }
    
    // =========================================================================
    // Arithmetic operators
    // =========================================================================
    
    /// Negation
    DoubleDouble opUnary(string op)() const if (op == "-") {
        return DoubleDouble(-hi, -lo);
    }
    
    /// Addition
    DoubleDouble opBinary(string op)(const DoubleDouble rhs) const if (op == "+") {
        double s1, s2, t1, t2;
        twoSum(hi, rhs.hi, s1, s2);
        twoSum(lo, rhs.lo, t1, t2);
        s2 += t1;
        quickTwoSum(s1, s2, s1, s2);
        s2 += t2;
        quickTwoSum(s1, s2, s1, s2);
        return DoubleDouble(s1, s2);
    }
    
    /// Subtraction
    DoubleDouble opBinary(string op)(const DoubleDouble rhs) const if (op == "-") {
        return this + (-rhs);
    }
    
    /// Multiplication
    DoubleDouble opBinary(string op)(const DoubleDouble rhs) const if (op == "*") {
        double p1, p2;
        twoProd(hi, rhs.hi, p1, p2);
        p2 += hi * rhs.lo + lo * rhs.hi;
        quickTwoSum(p1, p2, p1, p2);
        return DoubleDouble(p1, p2);
    }
    
    /// Division
    DoubleDouble opBinary(string op)(const DoubleDouble rhs) const if (op == "/") {
        double q1 = hi / rhs.hi;
        
        // Compute remainder: this - q1 * rhs
        double p1, p2;
        twoProd(q1, rhs.hi, p1, p2);
        double s, e;
        twoSum(hi, -p1, s, e);
        e += lo;
        e -= q1 * rhs.lo;
        e -= p2;
        
        double q2 = (s + e) / rhs.hi;
        quickTwoSum(q1, q2, q1, q2);
        return DoubleDouble(q1, q2);
    }
    
    /// Scalar operations
    DoubleDouble opBinary(string op)(double rhs) const if (op == "+" || op == "-" || op == "*" || op == "/") {
        return mixin("this " ~ op ~ " DoubleDouble(rhs)");
    }
    
    DoubleDouble opBinaryRight(string op)(double lhs) const if (op == "+" || op == "-" || op == "*" || op == "/") {
        return mixin("DoubleDouble(lhs) " ~ op ~ " this");
    }
    
    /// Comparison
    int opCmp(const DoubleDouble rhs) const {
        if (hi < rhs.hi) return -1;
        if (hi > rhs.hi) return 1;
        if (lo < rhs.lo) return -1;
        if (lo > rhs.lo) return 1;
        return 0;
    }
    
    int opCmp(double rhs) const {
        return opCmp(DoubleDouble(rhs));
    }
    
    bool opEquals(const DoubleDouble rhs) const {
        return hi == rhs.hi && lo == rhs.lo;
    }
    
    /// Op-assign
    ref DoubleDouble opOpAssign(string op, T)(T rhs) {
        this = mixin("this " ~ op ~ " rhs");
        return this;
    }
    
    /// String representation
    string toString() const {
        return format!"%.17g"(hi + lo);
    }
}

/// Square (optimized)
DoubleDouble sqr(const DoubleDouble x) {
    double p1, p2;
    DoubleDouble.twoProd(x.hi, x.hi, p1, p2);
    p2 += 2.0 * x.hi * x.lo;
    DoubleDouble.quickTwoSum(p1, p2, p1, p2);
    return DoubleDouble(p1, p2);
}

/// Absolute value
DoubleDouble abs(const DoubleDouble x) {
    if (x.hi < 0 || (x.hi == 0 && x.lo < 0)) {
        return -x;
    }
    return x;
}

/**
 * Complex number using double-double precision
 */
struct DDComplex {
    DoubleDouble re;
    DoubleDouble im;
    
    this(DoubleDouble r, DoubleDouble i) {
        re = r;
        im = i;
    }
    
    this(double r, double i) {
        re = DoubleDouble(r);
        im = DoubleDouble(i);
    }
    
    this(real r, real i) {
        re = DoubleDouble(r);
        im = DoubleDouble(i);
    }
    
    /// Magnitude squared
    DoubleDouble magnitudeSquared() const {
        return sqr(re) + sqr(im);
    }
    
    /// Addition
    DDComplex opBinary(string op)(const DDComplex rhs) const if (op == "+") {
        return DDComplex(re + rhs.re, im + rhs.im);
    }
    
    /// Subtraction
    DDComplex opBinary(string op)(const DDComplex rhs) const if (op == "-") {
        return DDComplex(re - rhs.re, im - rhs.im);
    }
    
    /// Multiplication
    DDComplex opBinary(string op)(const DDComplex rhs) const if (op == "*") {
        return DDComplex(
            re * rhs.re - im * rhs.im,
            re * rhs.im + im * rhs.re
        );
    }
    
    /// Square (optimized)
    DDComplex square() const {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto reim = re * im;
        return DDComplex(re2 - im2, reim + reim);
    }
}

// =============================================================================
// Backward compatibility aliases
// =============================================================================

/// Alias for compatibility with existing code
alias BigFloat = DoubleDouble;
alias BigComplex = DDComplex;

// =============================================================================
// Unit tests
// =============================================================================

unittest {
    // Test basic construction
    auto a = DoubleDouble(1.5);
    assert(a.toDouble() == 1.5);
    
    // Test arithmetic
    auto b = DoubleDouble(2.5);
    auto sum = a + b;
    assert(abs(sum.toDouble() - 4.0) < 1e-15);
    
    auto prod = a * b;
    assert(abs(prod.toDouble() - 3.75) < 1e-15);
    
    // Test precision preservation
    auto small = DoubleDouble(1e-20);
    auto large = DoubleDouble(1.0);
    auto result = large + small;
    // The small value should be preserved in the low part
    assert(result.lo != 0);
    
    // Test complex operations
    auto z = DDComplex(DoubleDouble(0), DoubleDouble(0));
    auto c = DDComplex(DoubleDouble(-0.5), DoubleDouble(0));
    z = z.square() + c;
    assert(abs(z.re.toDouble() - (-0.5)) < 1e-15);
}
