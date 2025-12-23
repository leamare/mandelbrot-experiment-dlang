module gmp_arb;

import mpfrd : Mpfr;
import deimos.mpfr : mpfr_rnd_t, mpfr_prec_t;

import std.conv;
import std.string;
import std.algorithm : max, min, countUntil;
import std.math : log10, floor, pow, sqrt, log;
import std.format : format;

/**
 * MPFR-based Arbitrary Precision Float
 * Uses MPFR (Multiple Precision Floating-Point Reliable) for high precision
 */
struct GMPFloat {
    private Mpfr value;
    private static mpfr_prec_t currentPrecision = 256;
    private bool isValid = false;
    
    @disable this();
    @disable this(this);
    
    static void setPrecisionDigits(uint digits) {
        currentPrecision = cast(mpfr_prec_t)(digits * 3.32 + 32);
        if (currentPrecision < 2) currentPrecision = 2;
        if (currentPrecision > 100000) currentPrecision = 100000;
    }
    
    static GMPFloat zero() {
        return GMPFloat(0.0);
    }
    
    this(double d) {
        value = Mpfr(d, currentPrecision);
        isValid = true;
    }
    
    this(string s) {
        s = s.strip();
        value = Mpfr(0.0, currentPrecision);
        import deimos.mpfr : mpfr_set_str;
        import std.string : toStringz;
        if (s.length == 0 || s == "0") {
            isValid = true;
            return;
        }
        auto cstr = toStringz(s);
        auto rc = mpfr_set_str(value.mpfr, cstr, 10, mpfr_rnd_t.MPFR_RNDN);
        assert(rc == 0, "mpfr_set_str failed for: "~s);
        isValid = true;
    }
    
    this(ref const GMPFloat other) {
        value = Mpfr(0.0, currentPrecision);
        import deimos.mpfr : mpfr_set;
        if (other.isValid) {
            mpfr_set(value.mpfr, other.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
            isValid = true;
        } else {
            import deimos.mpfr : mpfr_set_d;
            mpfr_set_d(value.mpfr, 0.0, mpfr_rnd_t.MPFR_RNDN);
            isValid = true;
        }
    }
    
    ~this() {
        if (!isValid) {
            try {
                import deimos.mpfr : mpfr_init2, mpfr_set_d;
                mpfr_init2(value.mpfr, currentPrecision);
                mpfr_set_d(value.mpfr, 0.0, mpfr_rnd_t.MPFR_RNDN);
                isValid = true;
            } catch (Exception e) {
            }
        }
    }
    
    double toDouble() const {
        import deimos.mpfr : mpfr_get_d;
        return mpfr_get_d(value.mpfr, mpfr_rnd_t.MPFR_RNDN);
    }
    
    string toString() const {
        return value.toString();
    }
    
    bool isZero() const {
        return value == 0.0;
    }
    
    GMPFloat opUnary(string op)() const if (op == "-") {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_neg;
        mpfr_neg(result.value.mpfr, this.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "+") {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_add;
        mpfr_add(result.value.mpfr, this.value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "-") {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_sub;
        mpfr_sub(result.value.mpfr, this.value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "*") {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_mul;
        mpfr_mul(result.value.mpfr, this.value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op)(const GMPFloat rhs) const if (op == "/") {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_div;
        mpfr_div(result.value.mpfr, this.value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op)(double rhs) const if (op == "*") {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_mul_d;
        mpfr_mul_d(result.value.mpfr, this.value.mpfr, rhs, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
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
    
    ref GMPFloat opAssign(GMPFloat rhs) {
        if (!isValid) {
            import deimos.mpfr : mpfr_init2, mpfr_set_d;
            mpfr_init2(value.mpfr, currentPrecision);
            mpfr_set_d(value.mpfr, 0.0, mpfr_rnd_t.MPFR_RNDN);
            isValid = true;
        }
        
        if (!rhs.isValid) {
            import deimos.mpfr : mpfr_set_d;
            mpfr_set_d(value.mpfr, 0.0, mpfr_rnd_t.MPFR_RNDN);
            isValid = true;
            return this;
        }
        
        import deimos.mpfr : mpfr_set, mpfr_rnd_t;
        mpfr_set(value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return this;
    }
    
    ref GMPFloat opAssign(ref const GMPFloat rhs) {
        if (this is rhs) return this;
        
        if (!isValid) {
            import deimos.mpfr : mpfr_init2, mpfr_set_d;
            mpfr_init2(value.mpfr, currentPrecision);
            mpfr_set_d(value.mpfr, 0.0, mpfr_rnd_t.MPFR_RNDN);
            isValid = true;
        }
        
        if (!rhs.isValid) {
            import deimos.mpfr : mpfr_set_d;
            mpfr_set_d(value.mpfr, 0.0, mpfr_rnd_t.MPFR_RNDN);
            isValid = true;
            return this;
        }
        
        import deimos.mpfr : mpfr_set, mpfr_rnd_t;
        mpfr_set(value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return this;
    }
}

GMPFloat sqr(const GMPFloat x) {
    return x * x;
}

GMPFloat abs(GMPFloat x) {
    return x < 0 ? -x : x;
}

/**
 * GMP-based Complex Number
 */
struct GMPComplex {
    GMPFloat re;
    GMPFloat im;
    
    @disable this();
    @disable this(this);
    
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
        re = GMPFloat(other.re);
        im = GMPFloat(other.im);
    }
    
    static GMPComplex zero() {
        return GMPComplex(GMPFloat(0.0), GMPFloat(0.0));
    }
    
    GMPFloat magnitudeSquared() const {
        return sqr(re) + sqr(im);
    }
    
    double magnitudeSquaredDouble() const {
        double r = re.toDouble();
        double i = im.toDouble();
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
    
    ref GMPComplex opAssign(GMPComplex rhs) {
        re = rhs.re;
        im = rhs.im;
        return this;
    }
    
    ref GMPComplex opAssign(ref const GMPComplex rhs) {
        if (this is rhs) return this;
        re = GMPFloat(rhs.re);
        im = GMPFloat(rhs.im);
        return this;
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

/**
 * pixel converter
 */
struct GMPPixelConverter {
    GMPFloat originX;
    GMPFloat originY;
    GMPFloat radius;
    GMPFloat pixelSize;
    double minDim;
    double di, dr;
    int width, height;
    
    @disable this();
    
    this(int w, int h, string centerXStr, string centerYStr, string radiusStr) {
        width = w;
        height = h;
        
        originX = GMPFloat(centerXStr);
        originY = GMPFloat(centerYStr);
        radius  = GMPFloat(radiusStr);
        
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

        GMPFloat two = GMPFloat(2.0);
        pixelSize = (radius * two) / GMPFloat(minDim);
    }
    
    GMPComplex pixelToComplex(int px, int py) const {
        GMPFloat pxG = GMPFloat(cast(double)px);
        GMPFloat pyG = GMPFloat(cast(double)py);

        // cr = px * pixelSize - (-originX + radius * (1 + di))
        GMPFloat termRe1 = pxG * pixelSize;
        GMPFloat negOriginX = GMPFloat(0.0) - originX;
        GMPFloat onePlusDi = GMPFloat(1.0 + di);
        GMPFloat termRe2 = negOriginX + radius * onePlusDi;
        GMPFloat cReal = termRe1 - termRe2;

        // ci = -(py * pixelSize) + (originY + radius * (1 + dr))
        GMPFloat termIm1 = pyG * pixelSize;
        GMPFloat negTermIm1 = GMPFloat(0.0) - termIm1;
        GMPFloat onePlusDr = GMPFloat(1.0 + dr);
        GMPFloat termIm2 = originY + radius * onePlusDr;
        GMPFloat cImag = negTermIm1 + termIm2;
        
        return GMPComplex(cReal, cImag);
    }
    
    GMPComplex getCenter() const {
        return GMPComplex(originX.toString(), originY.toString());
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
