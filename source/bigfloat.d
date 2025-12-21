module bigfloat;

import std.bigint : BigInt;
import std.conv : to;
import std.math : pow;
import std.string : strip;
import std.algorithm : countUntil;

private BigInt pow10(size_t exp) {
    BigInt result = BigInt(1);
    BigInt base = BigInt(10);
    size_t e = exp;
    while (e > 0) {
        if (e & 1) {
            result *= base;
        }
        e >>= 1;
        if (e == 0) break;
        base *= base;
    }
    return result;
}

struct BigFloat {
    BigInt mantissa;
    long exponent;

    this(BigInt m, long e) {
        mantissa = m;
        exponent = e;
        normalize();
    }

    this(double value) {
        import std.format : format;
        auto str = format!"%.17g"(value);
        this(str);
    }

    this(string str) {
        str = str.strip();
        if (str.length == 0 || str == "0") {
            mantissa = BigInt(0);
            exponent = 0;
            return;
        }
        bool neg = false;
        if (str[0] == '+' || str[0] == '-') {
            neg = str[0] == '-';
            str = str[1 .. $];
        }
        long expPart = 0;
        auto ePos = str.countUntil!(c => c == 'e' || c == 'E')();
        if (ePos >= 0) {
            expPart = to!long(str[ePos + 1 .. $]);
            str = str[0 .. ePos];
        }
        long fracDigits = 0;
        auto dotPos = str.countUntil('.');
        if (dotPos >= 0) {
            fracDigits = cast(long)(str.length - dotPos - 1);
            str = str[0 .. dotPos] ~ str[dotPos + 1 .. $];
        }

        size_t firstNonZero = 0;
        while (firstNonZero < str.length && str[firstNonZero] == '0') {
            firstNonZero++;
        }
        if (firstNonZero == str.length) {
            mantissa = BigInt(0);
            exponent = 0;
            return;
        }
        str = str[firstNonZero .. $];
        exponent = expPart - fracDigits;
        mantissa = BigInt(str);
        if (neg) {
            mantissa = -mantissa;
        }
        normalize();
    }

    void normalize() {
        if (mantissa == 0) {
            exponent = 0;
            return;
        }
        BigInt ten = BigInt(10);
        BigInt rem;
        while (true) {
            rem = mantissa % ten;
            if (rem != 0) break;
            mantissa /= ten;
            exponent += 1;
        }
    }

    int sign() const {
        if (mantissa == 0) return 0;
        return mantissa > 0 ? 1 : -1;
    }

    BigFloat opUnary(string op)() const if (op == "-") {
        return BigFloat(-mantissa, exponent);
    }

    BigFloat abs() const {
        return BigFloat(mantissa < 0 ? -mantissa : mantissa, exponent);
    }

    BigFloat opBinary(string op)(const BigFloat rhs) const if (op == "+" || op == "-") {
        BigFloat left = this;
        BigFloat right = (op == "+") ? rhs : -rhs;
        if (left.mantissa == 0) return right;
        if (right.mantissa == 0) return left;

        BigInt lm = left.mantissa;
        BigInt rm = right.mantissa;
        long expResult;

        if (left.exponent > right.exponent) {
            auto diff = cast(size_t)(left.exponent - right.exponent);
            lm *= pow10(diff);
            expResult = right.exponent;
        } else if (right.exponent > left.exponent) {
            auto diff = cast(size_t)(right.exponent - left.exponent);
            rm *= pow10(diff);
            expResult = left.exponent;
        } else {
            expResult = left.exponent;
        }

        BigFloat result;
        result.mantissa = lm + rm;
        result.exponent = expResult;
        result.normalize();
        return result;
    }

    BigFloat opBinary(string op)(const BigFloat rhs) const if (op == "*") {
        BigFloat result;
        result.mantissa = mantissa * rhs.mantissa;
        result.exponent = exponent + rhs.exponent;
        result.normalize();
        return result;
    }

    BigFloat sqr() const {
        BigFloat result;
        result.mantissa = mantissa * mantissa;
        result.exponent = exponent * 2;
        result.normalize();
        return result;
    }

    double toDouble() const {
        if (mantissa == 0) {
            return 0.0;
        }

        auto absMantissa = mantissa < 0 ? -mantissa : mantissa;
        auto mantStr = absMantissa.to!string();
        immutable size_t leadingDigits = mantStr.length > 18 ? 18 : mantStr.length;
        double leading = to!double(mantStr[0 .. leadingDigits]);
        long scaleExp = exponent + cast(long)(mantStr.length - leadingDigits);

        enum long MIN_EXP = -350;
        enum long MAX_EXP = 350;

        if (scaleExp > MAX_EXP) {
            return mantissa > 0 ? double.infinity : -double.infinity;
        }
        if (scaleExp < MIN_EXP) {
            return 0.0;
        }

        double scale = pow(10.0, cast(double)scaleExp);
        double result = leading * scale;
        return mantissa < 0 ? -result : result;
    }
}

struct BigFloatComplex {
    BigFloat re;
    BigFloat im;

    this(string realStr, string imagStr) {
        re = BigFloat(realStr);
        im = BigFloat(imagStr);
    }

    this(BigFloat r, BigFloat i) {
        re = r;
        im = i;
    }

    BigFloatComplex opBinary(string op)(const BigFloatComplex rhs) const if (op == "+") {
        return BigFloatComplex(re + rhs.re, im + rhs.im);
    }

    BigFloatComplex opBinary(string op)(const BigFloatComplex rhs) const if (op == "-") {
        return BigFloatComplex(re - rhs.re, im - rhs.im);
    }

    BigFloatComplex opBinary(string op)(const BigFloat rhs) const if (op == "*") {
        return BigFloatComplex(re * rhs, im * rhs);
    }

    BigFloatComplex opBinary(string op)(const BigFloatComplex rhs) const if (op == "*") {
        auto ac = re * rhs.re;
        auto bd = im * rhs.im;
        auto ad = re * rhs.im;
        auto bc = im * rhs.re;
        return BigFloatComplex(ac - bd, ad + bc);
    }

    BigFloatComplex square() const {
        auto reSq = re.sqr();
        auto imSq = im.sqr();
        auto reIm = re * im;
        return BigFloatComplex(reSq - imSq, reIm + reIm);
    }

    void squareAndAdd(const BigFloatComplex c) {
        auto zr2 = re.sqr();
        auto zi2 = im.sqr();
        auto reIm = re * im;
        re = (zr2 - zi2) + c.re;
        im = (reIm + reIm) + c.im;
    }

    BigFloat magnitudeSquared() const {
        auto reSq = re.sqr();
        auto imSq = im.sqr();
        return reSq + imSq;
    }

    double magnitudeSquaredDouble() const {
        return magnitudeSquared().toDouble();
    }
}
