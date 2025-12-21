module gmp_arb;

import bigfloat;
import std.conv;
import std.string;
import std.algorithm : max, min;
import std.math : log;

/// Thin wrapper around the BigFloat implementation so existing code can keep
/// referring to GMPFloat while we provide true arbitrary precision.
struct GMPFloat {
    BigFloat value;
    static uint precision = 256;

    private static GMPFloat fromBig(const BigFloat v) {
        GMPFloat r;
        r.value = v;
        return r;
    }

    this(double d) {
        value = BigFloat(d);
    }

    this(string s) {
        value = BigFloat(s);
    }

    this(ref const GMPFloat other) {
        value = other.value;
    }

    static GMPFloat zero() {
        return GMPFloat("0");
    }

    static void setPrecisionDigits(uint digits) {
        // BigFloat is arbitrary, but keep track for logging.
        precision = digits;
    }

    double toDouble() const {
        return value.toDouble();
    }

    string toString() const {
        import std.format : format;
        return format!"%.17g"(toDouble());
    }

    bool isZero() const {
        return value.sign() == 0;
    }

    GMPFloat opUnary(string op)() const if (op == "-") {
        return fromBig(-value);
    }

    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "+" || op == "-" || op == "*") {
        static if (op == "+") {
            return fromBig(value + rhs.value);
        } else static if (op == "-") {
            return fromBig(value - rhs.value);
        } else {
            return fromBig(value * rhs.value);
        }
    }

    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "/") {
        return fromBig(value / rhs.value);
    }

    GMPFloat opBinary(string op)(double rhs) const if (op == "*") {
        return fromBig(value * BigFloat(rhs));
    }

    GMPFloat opBinaryRight(string op)(double lhs) const if (op == "*") {
        return fromBig(BigFloat(lhs) * value);
    }

    int opCmp(const GMPFloat rhs) const {
        return (value - rhs.value).sign();
    }

    int opCmp(double rhs) const {
        return (value - BigFloat(rhs)).sign();
    }

    bool opEquals(const GMPFloat rhs) const {
        return value.mantissa == rhs.value.mantissa && value.exponent == rhs.value.exponent;
    }

    ref GMPFloat opOpAssign(string op, T)(T rhs) {
        this = mixin("this " ~ op ~ " rhs");
        return this;
    }

    ref GMPFloat opAssign(GMPFloat rhs) {
        value = rhs.value;
        return this;
    }

    ref GMPFloat opAssign(ref const GMPFloat rhs) {
        if (this is rhs) return this;
        value = rhs.value;
        return this;
    }
}

GMPFloat sqr(const GMPFloat x) {
    return GMPFloat.fromBig(x.value.sqr());
}

GMPFloat abs(const GMPFloat x) {
    return x.value.sign() < 0 ? GMPFloat.fromBig(-x.value) : GMPFloat.fromBig(x.value);
}

struct GMPComplex {
    GMPFloat re;
    GMPFloat im;

    this(GMPFloat r, GMPFloat i) {
        re = r;
        im = i;
    }

    this(double r, double i) {
        re = GMPFloat(r);
        im = GMPFloat(i);
    }

    this(string rStr, string iStr) {
        re = GMPFloat(rStr);
        im = GMPFloat(iStr);
    }

    this(ref const GMPComplex other) {
        re = other.re;
        im = other.im;
    }

    static GMPComplex zero() {
        return GMPComplex(GMPFloat.zero(), GMPFloat.zero());
    }

    GMPFloat magnitudeSquared() const {
        return sqr(re) + sqr(im);
    }

    double magnitudeSquaredDouble() const {
        auto r = re.toDouble();
        auto i = im.toDouble();
        return r * r + i * i;
    }

    GMPComplex opBinary(string op)(const GMPComplex rhs) const if (op == "+") {
        return GMPComplex(re + rhs.re, im + rhs.im);
    }

    GMPComplex opBinary(string op)(const GMPComplex rhs) const if (op == "-") {
        return GMPComplex(re - rhs.re, im - rhs.im);
    }

    GMPComplex opBinary(string op)(const GMPComplex rhs) const if (op == "*") {
        return GMPComplex(
            re * rhs.re - im * rhs.im,
            re * rhs.im + im * rhs.re
        );
    }

    GMPComplex opBinary(string op)(double rhs) const if (op == "*") {
        return GMPComplex(re * rhs, im * rhs);
    }

    GMPComplex square() const {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto two = GMPFloat(2.0);
        auto reim = re * im * two;
        return GMPComplex(re2 - im2, reim);
    }

    void squareAndAdd(const GMPComplex c) {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto two = GMPFloat(2.0);
        auto reim = re * im * two;
        re = re2 - im2 + c.re;
        im = reim + c.im;
    }
}

auto iterateGMP(string cRealStr, string cImagStr, uint maxIterations, double escapeRadius2 = 65536) {
    import std.typecons : tuple;

    auto c = GMPComplex(cRealStr, cImagStr);
    auto z = GMPComplex.zero();

    uint iter;
    for (iter = 0; iter < maxIterations; iter++) {
        z = z.square() + c;

        double mag2 = z.magnitudeSquaredDouble();
        if (mag2 > escapeRadius2) {
            double logZn = log(mag2) * 0.5;
            double nu = log(logZn / log(2.0)) / log(2.0);
            double smoothed = 1 + cast(double)iter - nu;
            return tuple(iter, smoothed);
        }
    }

    return tuple(maxIterations, cast(double)maxIterations);
}

struct GMPPixelConverter {
    GMPFloat originX;
    GMPFloat originY;
    GMPFloat radius;
    double minDim;
    double di, dr;
    int width, height;

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

    GMPComplex pixelToComplex(int px, int py) const {
        double relX = (cast(double)px / minDim) * 2.0 - (1.0 + di);
        double relY = (cast(double)py / minDim) * 2.0 - (1.0 + dr);
        GMPFloat relXGMP = GMPFloat(relX);
        GMPFloat relYGMP = GMPFloat(relY);
        auto two = GMPFloat(2.0);
        GMPFloat scale = radius * two;
        GMPFloat offsetX = scale * relXGMP;
        GMPFloat offsetY = scale * relYGMP;
        GMPFloat cReal = originX + offsetX;
        GMPFloat cImag = originY + offsetY;
        return GMPComplex(cReal, cImag);
    }
}

GMPComplex pixelToGMPComplex(
    int px, int py,
    int width, int height,
    string originXStr, string originYStr, string radiusStr
) {
    auto converter = GMPPixelConverter(width, height, originXStr, originYStr, radiusStr);
    return converter.pixelToComplex(px, py);
}
