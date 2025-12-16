module arbitrary;

import std.algorithm;
import std.array;
import std.conv;
import std.math;
import std.range;
import std.string;

struct ArbFloat {
    private ubyte[] digits;
    private long exponent;
    private bool negative;
    
    static uint precision = 200;
    
    static ArbFloat zero() {
        ArbFloat z;
        z.digits = [0];
        z.exponent = 0;
        z.negative = false;
        return z;
    }
    
    this(double value) {
        if (value == 0 || !isFinite(value)) {
            digits = [0];
            exponent = 0;
            negative = false;
            return;
        }
        
        bool wasNegative = value < 0;
        value = fabs(value);
        
        string str = format!"%.17g"(value);
        parseString(str);
        negative = wasNegative;
    }
    
    this(string str) {
        parseString(str);
    }
    
    private void parseString(string str) {
        str = str.strip();
        
        if (str.length == 0 || str == "0") {
            digits = [0];
            exponent = 0;
            negative = false;
            return;
        }
        
        negative = false;
        if (str[0] == '-') {
            negative = true;
            str = str[1..$];
        } else if (str[0] == '+') {
            str = str[1..$];
        }
        
        long exp10 = 0;
        auto ePos = str.countUntil!(c => c == 'e' || c == 'E')();
        if (ePos >= 0) {
            exp10 = to!long(str[ePos + 1 .. $]);
            str = str[0 .. ePos];
        }
        
        auto dotPos = str.countUntil('.');
        string intPart, fracPart;
        
        if (dotPos >= 0) {
            intPart = str[0 .. dotPos];
            fracPart = str[dotPos + 1 .. $];
        } else {
            intPart = str;
            fracPart = "";
        }
        
        string allDigits = intPart ~ fracPart;
        
        while (allDigits.length > 1 && allDigits[0] == '0') {
            allDigits = allDigits[1..$];
        }
        
        if (allDigits.length == 0 || allDigits == "0") {
            digits = [0];
            exponent = 0;
            negative = false;
            return;
        }
        
        exponent = exp10 - cast(long)fracPart.length;
        
        digits.length = allDigits.length;
        foreach (i, c; allDigits) {
            digits[$ - 1 - i] = cast(ubyte)(c - '0');
        }
        
        normalize();
    }
    
    private void normalize() {
        while (digits.length > 1 && digits[0] == 0) {
            digits = digits[1..$];
            exponent++;
        }
        
        while (digits.length > 1 && digits[$-1] == 0) {
            digits = digits[0..$-1];
        }
        
        if (digits.length == 1 && digits[0] == 0) {
            exponent = 0;
            negative = false;
            return;
        }
        
        if (digits.length > precision) {
            auto excess = digits.length - precision;
            digits = digits[excess..$];
            exponent += excess;
        }
    }
    
    bool isZero() const {
        return digits.length == 1 && digits[0] == 0;
    }
    
    double toDouble() const {
        if (isZero()) return 0.0;
        
        long topExponent = exponent + cast(long)digits.length - 1;
        
        if (topExponent > 308) return negative ? -double.infinity : double.infinity;
        if (topExponent < -308) return 0.0;
        
        double result = 0;
        double multiplier = pow(10.0, cast(double)topExponent);
        
        size_t digitsNeeded = min(digits.length, 17);
        
        foreach_reverse (i, d; digits[$ - digitsNeeded .. $]) {
            result += cast(double)d * multiplier;
            multiplier /= 10;
        }
        
        return negative ? -result : result;
    }
    
    ArbFloat opUnary(string op)() const if (op == "-") {
        ArbFloat result;
        result.digits = digits.dup;
        result.exponent = exponent;
        result.negative = !negative;
        if (result.isZero()) result.negative = false;
        return result;
    }
    
    ArbFloat abs() const {
        ArbFloat result;
        result.digits = digits.dup;
        result.exponent = exponent;
        result.negative = false;
        return result;
    }
    
    ArbFloat opBinary(string op)(const ArbFloat rhs) const if (op == "+") {
        if (isZero()) {
            ArbFloat result;
            result.digits = rhs.digits.dup;
            result.exponent = rhs.exponent;
            result.negative = rhs.negative;
            return result;
        }
        if (rhs.isZero()) {
            ArbFloat result;
            result.digits = digits.dup;
            result.exponent = exponent;
            result.negative = negative;
            return result;
        }
        
        if (negative != rhs.negative) {
            if (negative) {
                return rhs - (-this);
            } else {
                return this - (-rhs);
            }
        }
        
        ArbFloat result;
        result.negative = negative;
        
        long minExp = min(exponent, rhs.exponent);
        size_t lhsOffset = cast(size_t)(exponent - minExp);
        size_t rhsOffset = cast(size_t)(rhs.exponent - minExp);
        
        size_t maxLen = max(digits.length + lhsOffset, rhs.digits.length + rhsOffset) + 1;
        result.digits = new ubyte[](maxLen);
        result.digits[] = 0;
        result.exponent = minExp;
        
        foreach (i, d; digits) {
            result.digits[i + lhsOffset] += d;
        }
        foreach (i, d; rhs.digits) {
            result.digits[i + rhsOffset] += d;
        }
        
        ubyte carry = 0;
        foreach (ref d; result.digits) {
            uint sum = d + carry;
            d = cast(ubyte)(sum % 10);
            carry = cast(ubyte)(sum / 10);
        }
        
        result.normalize();
        return result;
    }
    
    ArbFloat opBinary(string op)(const ArbFloat rhs) const if (op == "-") {
        if (rhs.isZero()) {
            ArbFloat result;
            result.digits = digits.dup;
            result.exponent = exponent;
            result.negative = negative;
            return result;
        }
        if (isZero()) {
            return -rhs;
        }
        
        if (negative != rhs.negative) {
            return this + (-rhs);
        }
        
        int cmp = cmpMagnitude(rhs);
        if (cmp == 0) return ArbFloat.zero();
        
        const(ubyte)[] larger, smaller;
        long largerExp, smallerExp;
        bool resultNeg;
        
        if (cmp > 0) {
            larger = digits;
            largerExp = exponent;
            smaller = rhs.digits;
            smallerExp = rhs.exponent;
            resultNeg = negative;
        } else {
            larger = rhs.digits;
            largerExp = rhs.exponent;
            smaller = digits;
            smallerExp = exponent;
            resultNeg = !negative;
        }
        
        long minExp = min(largerExp, smallerExp);
        size_t largerOff = cast(size_t)(largerExp - minExp);
        size_t smallerOff = cast(size_t)(smallerExp - minExp);
        size_t maxLen = max(larger.length + largerOff, smaller.length + smallerOff);
        
        ArbFloat result;
        result.digits = new ubyte[](maxLen);
        result.exponent = minExp;
        result.negative = resultNeg;
        
        result.digits[] = 0;
        foreach (i, d; larger) {
            result.digits[i + largerOff] = d;
        }
        
        int borrow = 0;
        foreach (i; 0 .. maxLen) {
            int diff = cast(int)result.digits[i] - borrow;
            if (i >= smallerOff && i - smallerOff < smaller.length) {
                diff -= smaller[i - smallerOff];
            }
            if (diff < 0) {
                diff += 10;
                borrow = 1;
            } else {
                borrow = 0;
            }
            result.digits[i] = cast(ubyte)diff;
        }
        
        result.normalize();
        return result;
    }
    
    ArbFloat opBinary(string op)(const ArbFloat rhs) const if (op == "*") {
        if (isZero() || rhs.isZero()) return ArbFloat.zero();
        
        ArbFloat result;
        result.negative = negative != rhs.negative;
        result.exponent = exponent + rhs.exponent;
        
        size_t resultLen = digits.length + rhs.digits.length;
        result.digits = new ubyte[](resultLen);
        result.digits[] = 0;
        
        foreach (i, a; digits) {
            uint carry = 0;
            foreach (j, b; rhs.digits) {
                uint prod = cast(uint)a * cast(uint)b + result.digits[i + j] + carry;
                result.digits[i + j] = cast(ubyte)(prod % 10);
                carry = prod / 10;
            }
            if (carry > 0 && i + rhs.digits.length < resultLen) {
                result.digits[i + rhs.digits.length] += cast(ubyte)carry;
            }
        }
        
        result.normalize();
        return result;
    }
    
    ArbFloat opBinary(string op)(double rhs) const if (op == "*") {
        return this * ArbFloat(rhs);
    }
    
    ArbFloat opBinaryRight(string op)(double lhs) const if (op == "*") {
        return ArbFloat(lhs) * this;
    }
    
    private int cmpMagnitude(const ArbFloat rhs) const {
        long lhsTop = exponent + cast(long)digits.length;
        long rhsTop = rhs.exponent + cast(long)rhs.digits.length;
        
        if (lhsTop > rhsTop) return 1;
        if (lhsTop < rhsTop) return -1;
        
        long minExp = min(exponent, rhs.exponent);
        size_t lhsOff = cast(size_t)(exponent - minExp);
        size_t rhsOff = cast(size_t)(rhs.exponent - minExp);
        size_t maxLen = max(digits.length + lhsOff, rhs.digits.length + rhsOff);
        
        for (long i = maxLen - 1; i >= 0; i--) {
            ubyte lhsD = 0, rhsD = 0;
            if (i >= lhsOff && i - lhsOff < digits.length) {
                lhsD = digits[i - lhsOff];
            }
            if (i >= rhsOff && i - rhsOff < rhs.digits.length) {
                rhsD = rhs.digits[i - rhsOff];
            }
            if (lhsD > rhsD) return 1;
            if (lhsD < rhsD) return -1;
        }
        return 0;
    }
    
    int opCmp(const ArbFloat rhs) const {
        if (isZero() && rhs.isZero()) return 0;
        if (isZero()) return rhs.negative ? 1 : -1;
        if (rhs.isZero()) return negative ? -1 : 1;
        if (negative && !rhs.negative) return -1;
        if (!negative && rhs.negative) return 1;
        
        int mag = cmpMagnitude(rhs);
        return negative ? -mag : mag;
    }
    
    bool opEquals(const ArbFloat rhs) const {
        return opCmp(rhs) == 0;
    }
    
    int opCmp(double rhs) const {
        return opCmp(ArbFloat(rhs));
    }
    
    ref ArbFloat opOpAssign(string op, T)(T rhs) {
        this = mixin("this " ~ op ~ " rhs");
        return this;
    }
    
    string toString() const {
        if (isZero()) return "0";
        
        string digitStr = "";
        foreach_reverse (d; digits) {
            digitStr ~= cast(char)('0' + d);
        }
        
        while (digitStr.length > 1 && digitStr[0] == '0') {
            digitStr = digitStr[1..$];
        }
        
        long decPos = cast(long)digitStr.length + exponent;
        
        string result;
        if (decPos <= 0) {
            result = "0." ~ replicate("0", cast(size_t)(-decPos)) ~ digitStr;
        } else if (decPos >= digitStr.length) {
            result = digitStr ~ replicate("0", cast(size_t)(decPos - digitStr.length));
        } else {
            result = digitStr[0..cast(size_t)decPos] ~ "." ~ digitStr[cast(size_t)decPos..$];
        }
        
        return negative ? "-" ~ result : result;
    }
}

ArbFloat sqr(const ArbFloat x) {
    return x * x;
}

ArbFloat abs(const ArbFloat x) {
    return x.abs();
}

struct ArbComplex {
    ArbFloat re;
    ArbFloat im;
    
    this(ArbFloat r, ArbFloat i) {
        re = r;
        im = i;
    }
    
    this(double r, double i) {
        re = ArbFloat(r);
        im = ArbFloat(i);
    }
    
    this(string rStr, string iStr) {
        re = ArbFloat(rStr);
        im = ArbFloat(iStr);
    }
    
    static ArbComplex zero() {
        return ArbComplex(ArbFloat.zero(), ArbFloat.zero());
    }
    
    ArbFloat magnitudeSquared() const {
        return sqr(re) + sqr(im);
    }
    
    ArbComplex opBinary(string op)(const ArbComplex rhs) const if (op == "+") {
        return ArbComplex(re + rhs.re, im + rhs.im);
    }
    
    ArbComplex opBinary(string op)(const ArbComplex rhs) const if (op == "-") {
        return ArbComplex(re - rhs.re, im - rhs.im);
    }
    
    ArbComplex opBinary(string op)(const ArbComplex rhs) const if (op == "*") {
        return ArbComplex(
            re * rhs.re - im * rhs.im,
            re * rhs.im + im * rhs.re
        );
    }
    
    ArbComplex opBinary(string op)(double rhs) const if (op == "*") {
        return ArbComplex(re * rhs, im * rhs);
    }
    
    ArbComplex square() const {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto reim = re * im;
        return ArbComplex(re2 - im2, reim * 2.0);
    }
}

private string replicate(string s, size_t n) {
    auto result = appender!string();
    foreach (_; 0 .. n) {
        result ~= s;
    }
    return result.data;
}

