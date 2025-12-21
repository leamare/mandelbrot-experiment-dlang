module multidouble;

import std.math;
import std.conv;
import std.string;
import std.algorithm;
import std.typecons;
import std.bigint : BigInt;
import std.numeric : gcd;

/**
 * Multi-Double Arithmetic for Extended Precision
 */
enum uint MULTIDOUBLE_MIN_COMPONENTS = 2;
enum uint MULTIDOUBLE_MAX_COMPONENTS = 100;
enum uint MULTIDOUBLE_DIGITS_PER_COMPONENT = 16;
enum uint MULTIDOUBLE_EXTRA_COMPONENTS = 10;
enum double MULTIDOUBLE_NORMALIZE_THRESHOLD = 0.001;

private BigInt bigPow10(int exp) {
    BigInt result = BigInt(1);
    if (exp <= 0) {
        return result;
    }
    BigInt ten = BigInt(10);
    for (int i = 0; i < exp; ++i) {
        result *= ten;
    }
    return result;
}

private BigInt bigAbs(BigInt v) {
    return v < 0 ? -v : v;
}

private BigInt bigGcd(BigInt a, BigInt b) {
    a = bigAbs(a);
    b = bigAbs(b);
    while (b != 0) {
        BigInt t = a % b;
        a = b;
        b = t;
    }
    return a;
}

private struct BigRat {
    BigInt num;
    BigInt den;

    this(BigInt n, BigInt d) {
        assert(d != 0);
        num = n;
        den = d;
        normalize();
    }

    static BigRat fromDecimal(string s) {
        string str = s.strip();
        if (str.length == 0 || str == "0") {
            return BigRat(BigInt(0), BigInt(1));
        }
        bool neg = false;
        if (str[0] == '+' || str[0] == '-') {
            neg = (str[0] == '-');
            str = str[1 .. $];
        }
        int expPart = 0;
        auto ePos = str.countUntil!(c => c == 'e' || c == 'E')();
        if (ePos >= 0) {
            expPart = to!int(str[ePos + 1 .. $]);
            str = str[0 .. ePos];
        }
        int fracDigits = 0;
        auto dotPos = str.countUntil('.');
        if (dotPos >= 0) {
            fracDigits = cast(int)(str.length - dotPos - 1);
            str = str[0 .. dotPos] ~ str[dotPos + 1 .. $];
        }
        if (str.length == 0) {
            return BigRat(BigInt(0), BigInt(1));
        }
        BigInt mant = BigInt(str);
        int exp10 = expPart - fracDigits;
        BigInt num = mant;
        BigInt den = BigInt(1);
        if (exp10 >= 0) {
            num *= bigPow10(exp10);
        } else {
            den = bigPow10(-exp10);
        }
        if (neg) {
            num = -num;
        }
        return BigRat(num, den);
    }

    static BigRat fromDouble(double value) {
        if (value == 0.0) {
            return BigRat(BigInt(0), BigInt(1));
        }
        int exp;
        double mant = frexp(fabs(value), exp);
        long mantInt = cast(long)ldexp(mant, 53);
        exp -= 53;
        BigInt num = BigInt(mantInt);
        BigInt den = BigInt(1);
        if (exp >= 0) {
            num <<= exp;
        } else {
            den <<= (-exp);
        }
        if (value < 0) {
            num = -num;
        }
        return BigRat(num, den);
    }

    double toDouble() const {
        if (num == 0) {
            return 0.0;
        }
        real n = num.to!real();
        real d = den.to!real();
        return cast(double)(n / d);
    }

    void normalize() {
        if (den < 0) {
            num = -num;
            den = -den;
        }
        if (num == 0) {
            den = BigInt(1);
            return;
        }
        auto g = bigGcd(num, den);
        if (g != 0 && g != 1) {
            num /= g;
            den /= g;
        }
    }

    BigRat opBinary(string op)(const BigRat rhs) const if (op == "+" || op == "-") {
        BigInt lcmDen = den * rhs.den;
        BigInt leftScaled = num * rhs.den;
        BigInt rightScaled = rhs.num * den;
        BigInt resultNum = op == "+" ? leftScaled + rightScaled : leftScaled - rightScaled;
        return BigRat(resultNum, lcmDen);
    }
}

struct MultiDouble {
    private double[] components;

    this(this) {
        components = components.dup;
    }
    
    ref MultiDouble opAssign(ref const MultiDouble rhs) {
        components = rhs.components.dup;
        return this;
    }
    
    ref MultiDouble opAssign(MultiDouble rhs) {
        components = rhs.components.dup;
        return this;
    }
    
    this(uint numDoubles, double value = 0.0) {
        assert(numDoubles >= MULTIDOUBLE_MIN_COMPONENTS && numDoubles <= MULTIDOUBLE_MAX_COMPONENTS,
               "MultiDouble requires between "~to!string(MULTIDOUBLE_MIN_COMPONENTS)~" and "~to!string(MULTIDOUBLE_MAX_COMPONENTS)~" doubles");
        components = new double[](numDoubles);
        components[] = 0.0;
        components[0] = value;
    }
    
    this(uint numDoubles, string str) {
        assert(numDoubles >= MULTIDOUBLE_MIN_COMPONENTS && numDoubles <= MULTIDOUBLE_MAX_COMPONENTS,
               "MultiDouble requires between "~to!string(MULTIDOUBLE_MIN_COMPONENTS)~" and "~to!string(MULTIDOUBLE_MAX_COMPONENTS)~" doubles");
        components = new double[](numDoubles);
        components[] = 0.0;
        
        str = str.strip();
        if (str.length == 0) {
            return;
        }
        
        auto value = BigRat.fromDecimal(str);
        auto remaining = value;
        for (uint i = 0; i < numDoubles; ++i) {
            double comp = remaining.toDouble();
            components[i] = comp;
            if (comp == 0.0) {
                continue;
            }
            remaining = remaining - BigRat.fromDouble(comp);
            if (remaining.num == 0) {
                break;
            }
        }
        normalize();
    }
    
    uint numComponents() const {
        return cast(uint)components.length;
    }
    
    uint precisionDigits() const {
        return cast(uint)(components.length * MULTIDOUBLE_DIGITS_PER_COMPONENT);
    }
    
    double toDouble() const {
        double sum = 0.0;
        foreach (c; components) {
            sum += c;
        }
        return sum;
    }
    
    bool isZero() const {
        foreach (c; components) {
            if (c != 0.0) return false;
        }
        return true;
    }

    int sign() const {
        foreach (c; components) {
            if (c > 0) return 1;
            if (c < 0) return -1;
        }
        return 0;
    }
    
    private static void quickTwoSum(double a, double b, out double s, out double e) {
        s = a + b;
        e = b - (s - a);
    }
    
    private static void twoSum(double a, double b, out double s, out double e) {
        s = a + b;
        double v = s - a;
        e = (a - (s - v)) + (b - v);
    }
    
    private static void split(double a, out double ahi, out double alo) {
        enum double SPLIT_FACTOR = 134217729.0;
        double t = SPLIT_FACTOR * a;
        ahi = t - (t - a);
        alo = a - ahi;
    }
    
    private static void twoProd(double a, double b, out double p, out double e) {
        if (std.math.isNaN(a) || std.math.isNaN(b) || std.math.isInfinity(a) || std.math.isInfinity(b)) {
            p = double.nan;
            e = double.nan;
            return;
        }
        p = a * b;
        if (std.math.isInfinity(p) || p == 0.0) {
            e = 0.0;
            return;
        }
        double ahi, alo, bhi, blo;
        split(a, ahi, alo);
        split(b, bhi, blo);
        e = ((ahi * bhi - p) + ahi * blo + alo * bhi) + alo * blo;
        if (std.math.isNaN(e)) {
            e = 0.0;
        }
    }
    
    private void normalize() {
        if (components.length < 2) return;
        
        uint writeIdx = 0;
        for (uint i = 0; i < components.length; i++) {
            if (components[i] != 0.0) {
                if (writeIdx != i) {
                    components[writeIdx] = components[i];
                }
                writeIdx++;
            }
        }
        for (uint i = writeIdx; i < components.length; i++) {
            components[i] = 0.0;
        }
        
        if (writeIdx == 0) {
            return;
        }
        
        
        for (uint i = 0; i + 1 < components.length; i++) {
            if (components[i] == 0.0 || components[i + 1] == 0.0) {
                continue;
            }
            
            double absI = std.math.abs(components[i]);
            double absI1 = std.math.abs(components[i + 1]);
            
            if (absI > 0 && absI1 > absI * MULTIDOUBLE_NORMALIZE_THRESHOLD) {
                double s, e;
                twoSum(components[i], components[i + 1], s, e);
                components[i] = s;
                components[i + 1] = e;
            }
        }
    }
    
    MultiDouble opUnary(string op)() const if (op == "-") {
        MultiDouble result;
        result.components = new double[](components.length);
        foreach (i; 0 .. components.length) {
            result.components[i] = -components[i];
        }
        return result;
    }
    
    MultiDouble opBinary(string op)(const MultiDouble rhs) const if (op == "+") {
        if (isZero()) {
            MultiDouble result;
            result.components = rhs.components.dup;
            return result;
        }
        if (rhs.isZero()) {
            MultiDouble result;
            result.components = components.dup;
            return result;
        }
        
        uint maxComps = cast(uint)max(components.length, rhs.components.length);
        uint resultComps = min(maxComps, MULTIDOUBLE_MAX_COMPONENTS);
        
        double[] temp = new double[](resultComps * 2);
        temp[] = 0.0;
        uint tempLen = 0;
        
        for (uint i = 0; i < maxComps; i++) {
            double a = (i < components.length) ? components[i] : 0.0;
            double b = (i < rhs.components.length) ? rhs.components[i] : 0.0;
            
            if (a == 0.0 && b == 0.0) continue;
            
            if (a != 0.0 && b != 0.0) {
                double s, e;
                twoSum(a, b, s, e);
                if (tempLen < temp.length) {
                    temp[tempLen++] = s;
                }
                if (std.math.abs(e) > 1e-300 && tempLen < temp.length) {
                    temp[tempLen++] = e;
                }
            } else {
                if (tempLen < temp.length) {
                    temp[tempLen++] = (a != 0.0) ? a : b;
                }
            }
        }
        
        for (uint pass = 0; pass < 5; pass++) {
            bool changed = false;
            for (uint i = 0; i + 1 < tempLen; i++) {
                if (temp[i] != 0.0 && temp[i+1] != 0.0) {
                    double s, e;
                    twoSum(temp[i], temp[i+1], s, e);
                    if (s != temp[i] || e != temp[i+1]) {
                        temp[i] = s;
                        temp[i+1] = e;
                        changed = true;
                    }
                }
            }
            if (!changed) break;
        }
        
        MultiDouble result;
        result.components = new double[](resultComps);
        result.components[] = 0.0;
        for (uint i = 0; i < min(tempLen, resultComps); i++) {
            result.components[i] = temp[i];
        }
        
        bool hasNonZero = false;
        foreach (c; result.components) {
            if (c != 0.0) {
                hasNonZero = true;
                break;
            }
        }
        if (hasNonZero) {
            result.normalize();
        }
        return result;
    }
    
    MultiDouble opBinary(string op)(const MultiDouble rhs) const if (op == "-") {
        return this + (-rhs);
    }
    
    MultiDouble opBinary(string op)(const MultiDouble rhs) const if (op == "*") {
        if (isZero() || rhs.isZero()) {
            return MultiDouble(cast(uint)components.length, 0.0);
        }
        
        uint maxComps = cast(uint)max(components.length, rhs.components.length);
        uint resultComps = min(maxComps, MULTIDOUBLE_MAX_COMPONENTS);
        
        uint tempSize = min(cast(uint)(resultComps * 2), MULTIDOUBLE_MAX_COMPONENTS * 2);
        double[] temp = new double[](tempSize);
        temp[] = 0.0;
        
        for (uint i = 0; i < components.length; i++) {
            if (components[i] == 0.0) continue;
            for (uint j = 0; j < rhs.components.length; j++) {
                if (rhs.components[j] == 0.0) continue;
                
                double p, e;
                twoProd(components[i], rhs.components[j], p, e);
                
                uint idx = i + j;
                if (idx < temp.length) {
                    double s, err;
                    twoSum(temp[idx], p, s, err);
                    temp[idx] = s;
                    
                    double totalErr = err + e;
                    if (std.math.abs(totalErr) > 1e-300 && idx + 1 < temp.length) {
                        double s2, err2;
                        twoSum(temp[idx + 1], totalErr, s2, err2);
                        temp[idx + 1] = s2;
                        if (std.math.abs(err2) > 1e-300 && idx + 2 < temp.length) {
                            double s3, err3;
                            twoSum(temp[idx + 2], err2, s3, err3);
                            temp[idx + 2] = s3;
                            if (std.math.abs(err3) > 1e-300 && idx + 3 < temp.length) {
                                temp[idx + 3] += err3;
                            }
                        }
                    }
                }
            }
        }
        
        MultiDouble result;
        result.components = new double[](resultComps);
        result.components[] = 0.0;
        for (uint i = 0; i < min(temp.length, resultComps); i++) {
            result.components[i] = temp[i];
        }
        result.normalize();
        return result;
    }
    
    MultiDouble square() const {
        if (isZero()) {
            return MultiDouble(cast(uint)components.length, 0.0);
        }
        return this * this;
    }
    
    double magnitudeSquared() const {
        double sumSq = 0.0;
        double sumCross = 0.0;
        
        for (uint i = 0; i < components.length; i++) {
            if (components[i] != 0.0) {
                sumSq += components[i] * components[i];
                for (uint j = i + 1; j < components.length; j++) {
                    if (components[j] != 0.0) {
                        sumCross += components[i] * components[j];
                    }
                }
            }
        }
        
        return sumSq + 2.0 * sumCross;
    }
}

struct MultiDoubleComplex {
    MultiDouble re;
    MultiDouble im;
    
    this(uint numDoubles, double realVal, double imagVal) {
        re = MultiDouble(numDoubles, realVal);
        im = MultiDouble(numDoubles, imagVal);
    }
    
    this(uint numDoubles, string realStr, string imagStr) {
        re = MultiDouble(numDoubles, realStr);
        im = MultiDouble(numDoubles, imagStr);
    }
    
    this(MultiDouble realVal, MultiDouble imagVal) {
        re = realVal;
        im = imagVal;
    }
    
    static MultiDoubleComplex zero(uint numDoubles) {
        return MultiDoubleComplex(numDoubles, 0.0, 0.0);
    }
    
    MultiDoubleComplex square() const {
        auto reSq = re.square();
        auto imSq = im.square();
        auto reIm = re * im;
        
        MultiDoubleComplex result;
        result.re = reSq - imSq;
        result.im = reIm + reIm;
        return result;
    }
    
    MultiDoubleComplex opBinary(string op)(const MultiDoubleComplex rhs) const if (op == "+") {
        MultiDoubleComplex result;
        result.re = re + rhs.re;
        result.im = im + rhs.im;
        return result;
    }
    
    MultiDoubleComplex opBinary(string op)(const MultiDoubleComplex rhs) const if (op == "-") {
        MultiDoubleComplex result;
        result.re = re - rhs.re;
        result.im = im - rhs.im;
        return result;
    }
    
    MultiDoubleComplex opBinary(string op)(const MultiDoubleComplex rhs) const if (op == "*") {
        auto ac = re * rhs.re;
        auto bd = im * rhs.im;
        auto ad = re * rhs.im;
        auto bc = im * rhs.re;
        
        MultiDoubleComplex result;
        result.re = ac - bd;
        result.im = ad + bc;
        return result;
    }
    
    void squareAndAdd(const MultiDoubleComplex c) {
        auto zSq = this.square();
        re = zSq.re + c.re;
        im = zSq.im + c.im;
    }
    
    double magnitudeSquared() const {
        double reSq = re.magnitudeSquared();
        double imSq = im.magnitudeSquared();
        double result = reSq + imSq;
        
        if (!(result == result) || result == double.infinity || result == -double.infinity || result < 0.0) {
            double reD = re.toDouble();
            double imD = im.toDouble();
            double fallback = reD * reD + imD * imD;
            return (fallback >= 0.0) ? fallback : 0.0;
        }
        return (result >= 0.0) ? result : 0.0;
    }
    
    Tuple!(real, real) toDoubleComplex() const {
        return tuple(cast(real)re.toDouble(), cast(real)im.toDouble());
    }

}

uint calculateNumDoubles(uint requiredDigits) {
    uint baseDoubles = cast(uint)((requiredDigits + MULTIDOUBLE_DIGITS_PER_COMPONENT - 1) / MULTIDOUBLE_DIGITS_PER_COMPONENT);
    
    uint numDoubles = baseDoubles + MULTIDOUBLE_EXTRA_COMPONENTS;
    
    return min(max(numDoubles, MULTIDOUBLE_MIN_COMPONENTS), MULTIDOUBLE_MAX_COMPONENTS);
}

struct MultiDoublePixelConverter {
    MultiDouble originX;
    MultiDouble originY;
    MultiDouble radius;
    double minDim;
    double di, dr;
    int width, height;
    uint numDoubles;
    
    this(int w, int h, string originXStr, string originYStr, string radiusStr, uint numDoubles_) {
        width = w;
        height = h;
        numDoubles = numDoubles_;
        
        originX = MultiDouble(numDoubles, originXStr);
        originY = MultiDouble(numDoubles, originYStr);
        radius = MultiDouble(numDoubles, radiusStr);
        
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
    
    MultiDoubleComplex pixelToComplex(int px, int py) const {
        double relX = (cast(double)px / minDim) * 2.0 - (1.0 + di);
        double relY = (cast(double)py / minDim) * 2.0 - (1.0 + dr);
        
        MultiDouble relXMD = MultiDouble(numDoubles, relX);
        MultiDouble relYMD = MultiDouble(numDoubles, relY);
        
        MultiDouble offsetX = radius * relXMD;
        MultiDouble offsetY = radius * relYMD;
        
        MultiDouble cReal = originX + offsetX;
        MultiDouble cImag = originY + offsetY;
        
        MultiDoubleComplex result;
        result.re = cReal;
        result.im = cImag;
        return result;
    }
}
