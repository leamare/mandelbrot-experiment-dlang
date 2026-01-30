/**
 * QuadDouble - Quad-Precision Floating Point
 * 
 * Represents a number as the unevaluated sum of four doubles
 * 
 * Based on the QD library algorithms by Hida, Li, and Bailey.
 */
module calc.types.quaddouble;

import std.math;
import std.conv : to;
import std.string : strip;
import std.algorithm : countUntil;
import std.format : format;

struct QuadDouble {
    double[4] x;
    
    this(double a) {
        x[0] = a;
        x[1] = 0.0;
        x[2] = 0.0;
        x[3] = 0.0;
    }
    
    this(double x0, double x1, double x2, double x3) {
        x[0] = x0;
        x[1] = x1;
        x[2] = x2;
        x[3] = x3;
        renormalize();
    }
    
    this(string str) {
        x[] = 0.0;
        
        str = str.strip();
        if (str.length == 0) return;
        
        bool neg = false;
        if (str[0] == '-') {
            neg = true;
            str = str[1 .. $];
        } else if (str[0] == '+') {
            str = str[1 .. $];
        }
        
        int exponent = 0;
        auto ePos = str.countUntil!(c => c == 'e' || c == 'E')();
        if (ePos >= 0) {
            try {
                exponent = to!int(str[ePos + 1 .. $]);
            } catch (Exception) {}
            str = str[0 .. ePos];
        }
        
        QuadDouble result = QuadDouble(0.0);
        QuadDouble ten = QuadDouble(10.0);
        QuadDouble tenth = QuadDouble(0.1);
        
        bool pastDecimal = false;
        int decimalPlaces = 0;
        
        foreach (c; str) {
            if (c == '.') {
                pastDecimal = true;
                continue;
            }
            if (c < '0' || c > '9') continue;
            
            int digit = c - '0';
            result = result * ten + QuadDouble(cast(double)digit);
            
            if (pastDecimal) {
                decimalPlaces++;
            }
        }
        
        exponent -= decimalPlaces;
        
        if (exponent != 0) {
            QuadDouble scale = QuadDouble(1.0);
            int absExp = exponent < 0 ? -exponent : exponent;
            QuadDouble factor = exponent > 0 ? ten : tenth;
            
            while (absExp > 0) {
                if (absExp & 1) {
                    scale = scale * factor;
                }
                factor = factor * factor;
                absExp >>= 1;
            }
            
            result = result * scale;
        }
        
        if (neg) {
            result = -result;
        }
        
        x = result.x;
    }
    
    double toDouble() const {
        return x[0] + x[1] + x[2] + x[3];
    }
    
    string toFullString() const {
        return format!"%.60g"(toDouble());
    }
    
    bool isZero() const {
        return x[0] == 0.0;
    }
    
    int sign() const {
        if (x[0] > 0) return 1;
        if (x[0] < 0) return -1;
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
    
    private static void split(double a, out double hi, out double lo) {
        enum double SPLIT = 134217729.0;
        double t = SPLIT * a;
        hi = t - (t - a);
        lo = a - hi;
    }
    
    private static void twoProd(double a, double b, out double p, out double e) {
        p = a * b;
        double ahi, alo, bhi, blo;
        split(a, ahi, alo);
        split(b, bhi, blo);
        e = ((ahi * bhi - p) + ahi * blo + alo * bhi) + alo * blo;
    }
    
    private void renormalize() {
        double s0, s1, s2, s3;
        double c0, c1, c2, c3;
        double e;
        
        quickTwoSum(x[2], x[3], s0, c0);
        quickTwoSum(x[1], s0, s1, c1);
        quickTwoSum(x[0], s1, x[0], c2);
        
        s0 = c0;
        s1 = c1;
        s2 = c2;
        
        quickTwoSum(s1, s0, s0, e);
        s1 = e;
        quickTwoSum(s2, s0, x[1], e);
        
        quickTwoSum(e, s1, x[2], x[3]);
    }
    
    QuadDouble opUnary(string op)() const if (op == "-") {
        return QuadDouble(-x[0], -x[1], -x[2], -x[3]);
    }
    
    QuadDouble opBinary(string op)(const QuadDouble b) const if (op == "+") {
        double s0, s1, s2, s3;
        double t0, t1, t2, t3;
        double v0, v1, v2, v3;
        double u0, u1, u2, u3;
        double w0, w1, w2, w3;
        
        s0 = x[0] + b.x[0];
        s1 = x[1] + b.x[1];
        s2 = x[2] + b.x[2];
        s3 = x[3] + b.x[3];
        
        v0 = s0 - x[0];
        v1 = s1 - x[1];
        v2 = s2 - x[2];
        v3 = s3 - x[3];
        
        u0 = s0 - v0;
        u1 = s1 - v1;
        u2 = s2 - v2;
        u3 = s3 - v3;
        
        w0 = x[0] - u0;
        w1 = x[1] - u1;
        w2 = x[2] - u2;
        w3 = x[3] - u3;
        
        u0 = b.x[0] - v0;
        u1 = b.x[1] - v1;
        u2 = b.x[2] - v2;
        u3 = b.x[3] - v3;
        
        t0 = w0 + u0;
        t1 = w1 + u1;
        t2 = w2 + u2;
        t3 = w3 + u3;
        
        double e;
        twoSum(s1, t0, s1, t0);
        twoSum(s2, t0, s2, t0);
        twoSum(s2, t1, s2, t1);
        twoSum(s3, t0, s3, t0);
        twoSum(s3, t1, s3, t1);
        twoSum(s3, t2, s3, t2);
        
        t0 = t0 + t1 + t2 + t3;
        
        QuadDouble result;
        quickTwoSum(s0, s1, result.x[0], e);
        quickTwoSum(e, s2, result.x[1], e);
        quickTwoSum(e, s3, result.x[2], e);
        result.x[3] = e + t0;
        result.renormalize();
        
        return result;
    }
    
    QuadDouble opBinary(string op)(const QuadDouble b) const if (op == "-") {
        return this + (-b);
    }
    
    QuadDouble opBinary(string op)(const QuadDouble b) const if (op == "*") {
        double p0, p1, p2, p3, p4, p5;
        double q0, q1, q2, q3, q4, q5;
        double p6, p7, p8, p9;
        double q6, q7, q8, q9;
        double r0, r1;
        double t0, t1;
        double s0, s1, s2;
        
        twoProd(x[0], b.x[0], p0, q0);
        twoProd(x[0], b.x[1], p1, q1);
        twoProd(x[1], b.x[0], p2, q2);
        twoProd(x[0], b.x[2], p3, q3);
        twoProd(x[1], b.x[1], p4, q4);
        twoProd(x[2], b.x[0], p5, q5);
        
        twoSum(p1, p2, p1, p2);
        twoSum(q0, p1, q0, p1);
        twoSum(p2, p1, p2, p1);
        twoSum(q1, q2, q1, q2);
        
        r0 = p0;
        
        twoSum(q0, p3, s0, t0);
        twoSum(s0, p4, s0, t1);
        twoSum(s0, p5, s0, s1);
        t0 = t0 + t1 + s1;
        
        twoSum(s0, p2, s0, t1);
        t0 = t0 + t1;
        
        r1 = s0;
        
        t0 = t0 + p1 + q1 + q2 + q3 + q4 + q5;
        t0 = t0 + x[0] * b.x[3] + x[1] * b.x[2] + x[2] * b.x[1] + x[3] * b.x[0];
        
        QuadDouble result;
        quickTwoSum(r0, r1, result.x[0], result.x[1]);
        quickTwoSum(result.x[1], t0, result.x[1], result.x[2]);
        result.x[3] = 0.0;
        result.renormalize();
        
        return result;
    }
    
    QuadDouble opBinary(string op)(double b) const if (op == "+") {
        return this + QuadDouble(b);
    }
    
    QuadDouble opBinary(string op)(double b) const if (op == "-") {
        return this - QuadDouble(b);
    }
    
    QuadDouble opBinary(string op)(double b) const if (op == "*") {
        double p0, p1, p2, p3;
        double q0, q1, q2;
        double s0, s1, s2, s3, s4;
        
        twoProd(x[0], b, p0, q0);
        twoProd(x[1], b, p1, q1);
        twoProd(x[2], b, p2, q2);
        p3 = x[3] * b;
        
        s0 = p0;
        
        twoSum(q0, p1, s1, s2);
        twoSum(s2, p2, s2, s3);
        twoSum(q1, s2, s2, s4);
        
        s3 = s3 + s4 + q2 + p3;
        twoSum(s2, s3, s2, s3);
        
        QuadDouble result;
        quickTwoSum(s0, s1, result.x[0], result.x[1]);
        quickTwoSum(result.x[1], s2, result.x[1], result.x[2]);
        quickTwoSum(result.x[2], s3, result.x[2], result.x[3]);
        result.renormalize();
        
        return result;
    }
    
    int opCmp(const QuadDouble b) const {
        if (x[0] < b.x[0]) return -1;
        if (x[0] > b.x[0]) return 1;
        if (x[1] < b.x[1]) return -1;
        if (x[1] > b.x[1]) return 1;
        if (x[2] < b.x[2]) return -1;
        if (x[2] > b.x[2]) return 1;
        if (x[3] < b.x[3]) return -1;
        if (x[3] > b.x[3]) return 1;
        return 0;
    }
    
    bool opEquals(const QuadDouble b) const {
        return x[0] == b.x[0] && x[1] == b.x[1] && x[2] == b.x[2] && x[3] == b.x[3];
    }
}

QuadDouble sqr(const QuadDouble a) {
    double p0, p1, p2, p3, p4, p5;
    double q0, q1, q2, q3;
    double s0, s1, s2;
    double t0, t1;
    
    QuadDouble.twoProd(a.x[0], a.x[0], p0, q0);
    p1 = 2.0 * a.x[0] * a.x[1];
    p2 = 2.0 * a.x[0] * a.x[2] + a.x[1] * a.x[1];
    p3 = 2.0 * (a.x[0] * a.x[3] + a.x[1] * a.x[2]);
    
    s0 = p0;
    
    QuadDouble.twoSum(q0, p1, s1, t0);
    QuadDouble.twoSum(t0, p2, s2, t1);
    t1 = t1 + p3;
    
    QuadDouble result;
    QuadDouble.quickTwoSum(s0, s1, result.x[0], result.x[1]);
    QuadDouble.quickTwoSum(result.x[1], s2, result.x[1], result.x[2]);
    QuadDouble.quickTwoSum(result.x[2], t1, result.x[2], result.x[3]);
    result.renormalize();
    
    return result;
}

QuadDouble abs(const QuadDouble a) {
    if (a.x[0] < 0) return -a;
    return a;
}

struct QDComplex {
    QuadDouble re;
    QuadDouble im;
    
    this(QuadDouble r, QuadDouble i) {
        re = r;
        im = i;
    }
    
    this(double r, double i) {
        re = QuadDouble(r);
        im = QuadDouble(i);
    }
    
    this(string realStr, string imagStr) {
        re = QuadDouble(realStr);
        im = QuadDouble(imagStr);
    }
    
    static QDComplex zero() {
        return QDComplex(QuadDouble(0.0), QuadDouble(0.0));
    }
    
    QuadDouble magnitudeSquared() const {
        return sqr(re) + sqr(im);
    }
    
    double magnitudeSquaredDouble() const {
        return magnitudeSquared().toDouble();
    }
    
    QDComplex opBinary(string op)(const QDComplex b) const if (op == "+") {
        return QDComplex(re + b.re, im + b.im);
    }
    
    QDComplex opBinary(string op)(const QDComplex b) const if (op == "-") {
        return QDComplex(re - b.re, im - b.im);
    }
    
    QDComplex opBinary(string op)(const QDComplex b) const if (op == "*") {
        return QDComplex(
            re * b.re - im * b.im,
            re * b.im + im * b.re
        );
    }
    
    QDComplex square() const {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto reim = re * im;
        return QDComplex(re2 - im2, reim + reim);
    }
    
    void squareAndAdd(const QDComplex c) {
        auto zSq = square();
        re = zSq.re + c.re;
        im = zSq.im + c.im;
    }
    
    import std.typecons : Tuple;
    Tuple!(real, real) toDoubleComplex() const {
        return Tuple!(real, real)(cast(real)re.toDouble(), cast(real)im.toDouble());
    }
}

struct QDPixelConverter {
    QuadDouble originX;
    QuadDouble originY;
    QuadDouble radius;
    double minDim;
    double di, dr;
    int width, height;
    
    this(int w, int h, string originXStr, string originYStr, string radiusStr) {
        import std.algorithm : min, max;
        
        width = w;
        height = h;
        
        originX = QuadDouble(originXStr);
        originY = QuadDouble(originYStr);
        radius = QuadDouble(radiusStr);
        
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
    
    QDComplex pixelToComplex(int px, int py) const {
        double relX = (cast(double)px / minDim) * 2.0 - (1.0 + di);
        double relY = (cast(double)py / minDim) * 2.0 - (1.0 + dr);
        
        auto offsetX = radius * relX;
        auto offsetY = radius * relY;
        
        auto cReal = originX + offsetX;
        auto cImag = originY + offsetY;
        
        return QDComplex(cReal, cImag);
    }
}

