module gmp_arb;

import mpfrd : Mpfr;
import deimos.mpfr : mpfr_rnd_t, mpfr_prec_t;

import std.conv;
import std.string;
import std.algorithm : max, min, countUntil;
import std.math : log10, floor, pow, sqrt, log;
import std.format : format;
import std.traits : Unqual;

private template isGMPFloat(T) {
    enum isGMPFloat = is(Unqual!T == GMPFloat);
}

private template isGMPComplex(T) {
    enum isGMPComplex = is(Unqual!T == GMPComplex);
}

struct GMPFloat {
    private Mpfr value;
    
    private static mpfr_prec_t currentPrecision() nothrow @nogc {
        return _tlsPrecision;
    }
    private static void currentPrecision(mpfr_prec_t p) nothrow @nogc {
        _tlsPrecision = p;
    }
    private static mpfr_prec_t _tlsPrecision = 256;
    
    private bool isValid = false;
    
    @disable this();
    @disable this(this);
    
    static void setPrecisionDigits(uint digits) {
        auto prec = cast(mpfr_prec_t)(digits * 3.32 + 32);
        if (prec < 2) prec = 2;
        if (prec > 100000) prec = 100000;
        currentPrecision = prec;
    }
    
    static mpfr_prec_t getPrecisionBits() nothrow @nogc {
        return currentPrecision;
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
    
    GMPFloat opBinary(string op, R)(auto ref R rhs) const if (op == "+" && isGMPFloat!R) {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_add;
        mpfr_add(result.value.mpfr, this.value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op, R)(auto ref R rhs) const if (op == "-" && isGMPFloat!R) {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_sub;
        mpfr_sub(result.value.mpfr, this.value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op, R)(auto ref R rhs) const if (op == "*" && isGMPFloat!R) {
        GMPFloat result = GMPFloat(0.0);
        import deimos.mpfr : mpfr_mul;
        mpfr_mul(result.value.mpfr, this.value.mpfr, rhs.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
        return result;
    }
    
    GMPFloat opBinary(string op, R)(auto ref R rhs) const if (op == "/" && isGMPFloat!R) {
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
    
    int opCmp(R)(auto ref R rhs) const if (isGMPFloat!R) {
        if (value < rhs.value) return -1;
        if (value > rhs.value) return 1;
        return 0;
    }
    
    int opCmp(double rhs) const {
        auto rhsGMP = GMPFloat(rhs);
        if (value < rhsGMP.value) return -1;
        if (value > rhsGMP.value) return 1;
        return 0;
    }
    
    bool opEquals(R)(auto ref R rhs) const if (isGMPFloat!R) {
        return value == rhs.value;
    }
    
    ref GMPFloat opAssign(GMPFloat rhs) return {
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
    
    ref GMPFloat opAssign(ref const GMPFloat rhs) return {
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

GMPFloat sqr(R)(auto ref R x) if (isGMPFloat!R) {
    GMPFloat result = GMPFloat(0.0);
    import deimos.mpfr : mpfr_sqr;
    mpfr_sqr(result.value.mpfr, x.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
    return result;
}

GMPFloat abs(R)(auto ref R x) if (isGMPFloat!R) {
    GMPFloat result = GMPFloat(0.0);
    import deimos.mpfr : mpfr_abs;
    mpfr_abs(result.value.mpfr, x.value.mpfr, mpfr_rnd_t.MPFR_RNDN);
    return result;
}

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
        return GMPComplex(0.0, 0.0);
    }
    
    GMPFloat magnitudeSquared() const {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        return re2 + im2;
    }
    
    double magnitudeSquaredDouble() const {
        double r = re.toDouble();
        double i = im.toDouble();
        return r * r + i * i;
    }
    
    GMPComplex opBinary(string op, R)(auto ref R rhs) const if (op == "+" && isGMPComplex!R) {
        auto newRe = re + rhs.re;
        auto newIm = im + rhs.im;
        return GMPComplex(newRe, newIm);
    }
    
    GMPComplex opBinary(string op, R)(auto ref R rhs) const if (op == "-" && isGMPComplex!R) {
        auto newRe = re - rhs.re;
        auto newIm = im - rhs.im;
        return GMPComplex(newRe, newIm);
    }
    
    GMPComplex opBinary(string op, R)(auto ref R rhs) const if (op == "*" && isGMPComplex!R) {
        auto ac = re * rhs.re;
        auto bd = im * rhs.im;
        auto ad = re * rhs.im;
        auto bc = im * rhs.re;
        auto newRe = ac - bd;
        auto newIm = ad + bc;
        return GMPComplex(newRe, newIm);
    }
    
    GMPComplex opBinary(string op)(double rhs) const if (op == "*") {
        auto newRe = re * rhs;
        auto newIm = im * rhs;
        return GMPComplex(newRe, newIm);
    }
    
    GMPComplex square() const {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto two = GMPFloat(2.0);
        auto reTimesIm = re * im;
        auto twoReIm = reTimesIm * two;
        auto newRe = re2 - im2;
        return GMPComplex(newRe, twoReIm);
    }
    
    void squareAndAdd(R)(auto ref R c) if (isGMPComplex!R) {
        auto re2 = sqr(re);
        auto im2 = sqr(im);
        auto two = GMPFloat(2.0);
        auto reTimesIm = re * im;
        auto twoReIm = reTimesIm * two;
        auto newRe = re2 - im2;
        re = newRe + c.re;
        im = twoReIm + c.im;
    }
    
    ref GMPComplex opAssign(GMPComplex rhs) return {
        re = rhs.re;
        im = rhs.im;
        return this;
    }
    
    ref GMPComplex opAssign(ref const GMPComplex rhs) return {
        re = rhs.re;
        im = rhs.im;
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

struct GMPPixelConverter {
    GMPFloat originX;
    GMPFloat originY;
    GMPFloat radius;
    GMPFloat pixelSize;
    double minDim;
    double di, dr;
    int width, height;
    
    @disable this();
    @disable this(this);
    
    this(int w, int h, string centerXStr, string centerYStr, string radiusStr) {
        width = w;
        height = h;
        
        originX = GMPFloat(centerXStr);
        originY = GMPFloat(centerYStr);
        
        auto radiusBase = GMPFloat(radiusStr);
        auto two = GMPFloat(2.0);
        radius = radiusBase * two;
        
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

        auto radiusTimeTwo = radius * two;
        auto minDimGMP = GMPFloat(minDim);
        pixelSize = radiusTimeTwo / minDimGMP;
    }
    
    void pixelToComplex(int px, int py, ref GMPComplex result) const {
        auto pxG = GMPFloat(cast(double)px + 0.5);
        auto pyG = GMPFloat(cast(double)(height - py + 0.5));

        auto termRe1 = pxG * pixelSize;
        auto negOriginX = -originX;
        auto onePlusDi = GMPFloat(1.0 + di);
        auto radiusTimesDi = radius * onePlusDi;
        auto termRe2 = negOriginX + radiusTimesDi;
        auto cReal = termRe1 - termRe2;

        auto termIm1 = pyG * pixelSize;
        auto negTermIm1 = -termIm1;
        auto onePlusDr = GMPFloat(1.0 + dr);
        auto radiusTimesDr = radius * onePlusDr;
        auto termIm2 = originY + radiusTimesDr;
        auto cImag = negTermIm1 + termIm2;
        
        result.re = cReal;
        result.im = cImag;
    }
    
    void getCenter(ref GMPComplex result) const {
        result.re = GMPFloat(originX.toString());
        result.im = GMPFloat(originY.toString());
    }
}

void pixelToGMPComplex(
    int px, int py,
    int width, int height,
    string originXStr, string originYStr, string radiusStr,
    ref GMPComplex result
) {
    auto converter = GMPPixelConverter(width, height, originXStr, originYStr, radiusStr);
    converter.pixelToComplex(px, py, result);
}
