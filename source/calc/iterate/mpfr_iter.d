module calc.iterate.mpfr_iter;

import std.math : log;
import std.algorithm : min, max;

import deimos.mpfr : mpfr_rnd_t;

import types.iter_result;
import types.fractal;
import types.render;
import calc.iterate.common;
import calc.types.mpfr;

struct MPFRPixelConverter {
    GMPFloat originX;
    GMPFloat originY;
    GMPFloat radius;
    GMPFloat pixelSize;
    int width, height;
    double di, dr;
    
    @disable this();
    @disable this(this);
    
    this(int w, int h, string originXStr, string originYStr, string radiusStr) {
        width = w;
        height = h;
        
        originX = GMPFloat(originXStr);
        originY = GMPFloat(originYStr);
        radius = GMPFloat(radiusStr);
        
        double wd = cast(double)w;
        double hd = cast(double)h;
        double minDim = min(wd, hd);
        
        di = 0;
        dr = 0;
        if (w != h) {
            double diff = (max(wd, hd) - minDim) / minDim;
            di = w > h ? diff : 0;
            dr = w > h ? 0 : diff;
        }
        
        // pixelSize = radius * 2 / minDim
        auto two = GMPFloat(2.0);
        auto minDimGMP = GMPFloat(minDim);
        pixelSize = (radius * two) / minDimGMP;
    }
    
    void pixelToComplex(int px, int py, ref GMPComplex result) const {
        auto pxCenter = GMPFloat(cast(double)px + 0.5);
        auto pyCenter = GMPFloat(cast(double)py + 0.5);
        
        auto onePlusDi = GMPFloat(1.0 + di);
        auto term1 = pxCenter * pixelSize;
        auto term2 = radius * onePlusDi;
        auto cReal = term1 + originX - term2;
        
        auto onePlusDr = GMPFloat(1.0 + dr);
        auto term3 = pyCenter * pixelSize;
        auto negTerm3 = -term3;
        auto term4 = radius * onePlusDr;
        auto cImag = negTerm3 + originY + term4;
        
        result.re = cReal;
        result.im = cImag;
    }
    
    void getCenter(ref GMPComplex result) const {
        result.re = GMPFloat(originX.toString());
        result.im = GMPFloat(originY.toString());
    }
}

IterResult iterateMPFR(
    int px, int py,
    const ref RenderConfig cfg,
    ref const MPFRPixelConverter converter,
    GMPFractalOptions gmpOptions = GMPFractalOptions.init
) {
    auto c = GMPComplex.zero();
    converter.pixelToComplex(px, py, c);
    
    return iterateMPFRComplex(c, IterParams.fromConfig(cfg), gmpOptions);
}

IterResult iterateMPFRComplex(
    ref GMPComplex c,
    IterParams params,
    GMPFractalOptions gmpOptions = GMPFractalOptions.init
) {
    auto z = GMPComplex.zero();
    int iter = 0;
    
    final switch (params.fractalType) {
        case FractalType.mandelbrot:
            while (iter < params.maxIterations) {
                double mag2 = z.magnitudeSquaredDouble();
                if (mag2 > params.escapeRadius2) break;
                z.squareAndAdd(c);
                iter++;
            }
            break;
            
        case FractalType.ship:
            while (iter < params.maxIterations) {
                double mag2 = z.magnitudeSquaredDouble();
                if (mag2 > params.escapeRadius2) break;
                z.absComponents();
                z.squareAndAdd(c);
                iter++;
            }
            break;
            
        case FractalType.multibrot:
            iter = iterateMultibrotMPFR(z, c, params, gmpOptions);
            break;
            
        case FractalType.mandelbar:
            while (iter < params.maxIterations) {
                double mag2 = z.magnitudeSquaredDouble();
                if (mag2 > params.escapeRadius2) break;
                z.conjugateSquareAndAdd(c);
                iter++;
            }
            break;
    }
    
    double mag2 = z.magnitudeSquaredDouble();
    double smoothed = smoothIterations(iter, mag2, params.maxIterations);
    return IterResult(iter, smoothed);
}

private int iterateMultibrotMPFR(
    ref GMPComplex z,
    ref GMPComplex c,
    IterParams params,
    GMPFractalOptions gmpOptions
) {
    import deimos.mpfr : mpfr_sqrt, mpfr_pow, mpfr_atan2, mpfr_sin, mpfr_cos,
                        mpfr_div, mpfr_neg;
    
    double exponent = params.multibrotExp;
    int iter = 0;
    
    if (gmpOptions.hasIntegerPower && exponent > 0) {
        uint power = gmpOptions.integerPower;
        while (iter < params.maxIterations) {
            double mag2 = z.magnitudeSquaredDouble();
            if (mag2 > params.escapeRadius2) break;
            z.powAndAdd(power, c);
            iter++;
        }
    } else if (exponent > 0) {
        while (iter < params.maxIterations) {
            double mag2 = z.magnitudeSquaredDouble();
            if (mag2 > params.escapeRadius2) break;
            z.powFractionalAndAdd(exponent, c);
            iter++;
        }
    } else if (exponent < 0) {
        double absExp = -exponent;
        while (iter < params.maxIterations) {
            double mag2 = z.magnitudeSquaredDouble();
            if (mag2 > params.escapeRadius2) break;
            
            // Handle z = 0 case
            if (mag2 == 0.0) {
                z.re = GMPFloat(c.re);
                z.im = GMPFloat(c.im);
                iter++;
                continue;
            }
            
            auto zPow = z.powFractional(absExp);
            
            auto zPowMag2 = zPow.magnitudeSquared();
            
            if (zPowMag2.toDouble() == 0.0) {
                z.re = GMPFloat(c.re);
                z.im = GMPFloat(c.im);
                iter++;
                continue;
            }
            
            auto invRe = zPow.re / zPowMag2;
            auto invIm = -zPow.im / zPowMag2;
            
            // z = 1/z^|n| + c
            z.re = invRe + c.re;
            z.im = invIm + c.im;
            
            iter++;
        }
    } else {
        // exponent == 0: z^0 + c = 1 + c
        while (iter < params.maxIterations) {
            double mag2 = z.magnitudeSquaredDouble();
            if (mag2 > params.escapeRadius2) break;
            
            auto one = GMPFloat(1.0);
            z.re = one + c.re;
            z.im = GMPFloat(c.im);
            iter++;
        }
    }
    
    return iter;
}

struct MPFRReferenceOrbit {
    import std.complex : Complex;
    
    Complex!double[] zRef;
    GMPComplex[] zRefHP;
    string cRealStr, cImagStr;
    int refIterations;
    bool escaped;
    double escapeRadius2;
    uint precisionDigits;
}

MPFRReferenceOrbit computeReferenceOrbitMPFR(
    string cRealStr,
    string cImagStr,
    uint maxIterations,
    uint precisionDigits,
    double escapeRadius2 = 4.0,
    bool storeHighPrecision = false
) {
    import std.complex : Complex;
    
    MPFRReferenceOrbit orbit;
    orbit.cRealStr = cRealStr;
    orbit.cImagStr = cImagStr;
    orbit.precisionDigits = precisionDigits;
    orbit.escapeRadius2 = escapeRadius2;
    
    GMPFloat.setPrecisionDigits(precisionDigits);
    
    auto c = GMPComplex(cRealStr, cImagStr);
    auto z = GMPComplex.zero();
    
    orbit.zRef = new Complex!double[](maxIterations + 1);
    orbit.zRef[0] = Complex!double(0.0, 0.0);
    
    if (storeHighPrecision) {
        orbit.zRefHP.reserve(maxIterations + 1);
    }
    
    for (uint iter = 0; iter < maxIterations; iter++) {
        z.squareAndAdd(c);
        
        double zr = z.re.toDouble();
        double zi = z.im.toDouble();
        orbit.zRef[iter + 1] = Complex!double(zr, zi);
        
        if (storeHighPrecision) {
            orbit.zRefHP ~= GMPComplex(z);
        }
        
        double mag2 = zr * zr + zi * zi;
        if (mag2 > escapeRadius2) {
            orbit.escaped = true;
            orbit.refIterations = iter + 1;
            orbit.zRef = orbit.zRef[0 .. iter + 2];
            return orbit;
        }
    }
    
    orbit.escaped = false;
    orbit.refIterations = maxIterations;
    return orbit;
}

struct PerturbResult {
    IterResult result;
    bool needsRefinement;
    int rebaseCount;
}

PerturbResult iteratePerturbationMPFR(
    ref GMPComplex deltaC,
    const ref MPFRReferenceOrbit orbit,
    uint maxIterations,
    double escapeRadius2 = 4.0
) {
    import std.complex : Complex;
    import std.math : sqrt, isNaN, isInfinity;
    
    PerturbResult pr;
    pr.needsRefinement = false;
    pr.rebaseCount = 0;
    
    double deltaRe = deltaC.re.toDouble();
    double deltaIm = deltaC.im.toDouble();
    double deltaCRe = deltaRe;
    double deltaCIm = deltaIm;
    
    int iter = 0;
    int refIter = 0;
    
    enum double REBASE_THRESHOLD = 1e-3;
    
    while (iter < maxIterations && refIter < orbit.refIterations) {
        auto zRef = orbit.zRef[refIter];
        
        double zRe = zRef.re + deltaRe;
        double zIm = zRef.im + deltaIm;
        double zMag2 = zRe * zRe + zIm * zIm;
        
        if (zMag2 > escapeRadius2) {
            double smoothed = smoothIterations(iter, zMag2, maxIterations);
            pr.result = IterResult(iter, smoothed);
            return pr;
        }
        
        if (isNaN(deltaRe) || isNaN(deltaIm) ||
            isInfinity(deltaRe) || isInfinity(deltaIm)) {
            pr.needsRefinement = true;
            pr.result = IterResult(iter, cast(double)iter);
            return pr;
        }
        
        double twoZRe = 2.0 * zRef.re;
        double twoZIm = 2.0 * zRef.im;
        
        double term1Re = twoZRe * deltaRe - twoZIm * deltaIm;
        double term1Im = twoZRe * deltaIm + twoZIm * deltaRe;
        
        double term2Re = deltaRe * deltaRe - deltaIm * deltaIm;
        double term2Im = 2.0 * deltaRe * deltaIm;
        
        deltaRe = term1Re + term2Re + deltaCRe;
        deltaIm = term1Im + term2Im + deltaCIm;
        
        // Check for rebasing need
        double deltaMag = sqrt(deltaRe * deltaRe + deltaIm * deltaIm);
        double zRefMag = sqrt(zRef.re * zRef.re + zRef.im * zRef.im);
        
        if (zRefMag > 0 && deltaMag / zRefMag > REBASE_THRESHOLD) {
            if (deltaMag > 1e10) {
                pr.needsRefinement = true;
            }
        }
        
        iter++;
        refIter++;
    }
    
    if (refIter >= orbit.refIterations && !orbit.escaped) {
        pr.result = IterResult(cast(int)maxIterations, cast(double)maxIterations);
        return pr;
    }
    
    if (iter < maxIterations) {
        pr.needsRefinement = true;
    }
    
    pr.result = IterResult(iter, cast(double)iter);
    return pr;
}

// MPFR Orbit Tracking for Buddhabrot
struct MPFROrbitResult {
    IterResult iter;
    double[2][] orbit;
}

MPFROrbitResult iterateMPFRWithOrbit(
    int px, int py,
    const ref RenderConfig cfg,
    ref MPFRPixelConverter converter,
    const ref GMPFractalOptions options
) {
    MPFROrbitResult result;
    result.orbit.reserve(cfg.maxIterations);
    
    auto c = GMPComplex("0", "0");
    converter.pixelToComplex(px, py, c);
    
    auto z = GMPComplex("0", "0");
    
    auto escapeThreshold = GMPFloat(1 << 16);
    
    int iter;
    
    if (cfg.fractalType == FractalType.mandelbrot) {
        for (iter = 0; iter < cfg.maxIterations; iter++) {
            auto zrSq = z.re.sqr();
            auto ziSq = z.im.sqr();
            auto magSq = zrSq + ziSq;
            
            if (magSq.toDouble() > escapeThreshold.toDouble()) {
                break;
            }
            
            result.orbit ~= [z.re.toDouble(), z.im.toDouble()];
            
            auto newRe = zrSq - ziSq + c.re;
            auto newIm = z.re * z.im * GMPFloat(2.0) + c.im;
            z.re = newRe;
            z.im = newIm;
        }
    }
    else if (cfg.fractalType == FractalType.ship) {
        for (iter = 0; iter < cfg.maxIterations; iter++) {
            auto zrSq = z.re.sqr();
            auto ziSq = z.im.sqr();
            auto magSq = zrSq + ziSq;
            
            if (magSq.toDouble() > escapeThreshold.toDouble()) {
                break;
            }
            
            result.orbit ~= [z.re.toDouble(), z.im.toDouble()];
            
            auto absRe = z.re;
            auto absIm = z.im;
            if (absRe.toDouble() < 0) absRe = -absRe;
            if (absIm.toDouble() < 0) absIm = -absIm;
            
            auto newRe = absRe.sqr() - absIm.sqr() + c.re;
            auto newIm = absRe * absIm * GMPFloat(2.0) + c.im;
            z.re = newRe;
            z.im = newIm;
        }
    }
    else if (cfg.fractalType == FractalType.mandelbar) {
        for (iter = 0; iter < cfg.maxIterations; iter++) {
            auto zrSq = z.re.sqr();
            auto ziSq = z.im.sqr();
            auto magSq = zrSq + ziSq;
            
            if (magSq.toDouble() > escapeThreshold.toDouble()) {
                break;
            }
            
            result.orbit ~= [z.re.toDouble(), z.im.toDouble()];
            
            auto conjIm = -z.im;
            auto newRe = zrSq - ziSq + c.re;
            auto newIm = z.re * conjIm * GMPFloat(2.0) + c.im;
            z.re = newRe;
            z.im = newIm;
        }
    }
    else if (cfg.fractalType == FractalType.multibrot) {
        double exp = cfg.multibrotExp;
        
        for (iter = 0; iter < cfg.maxIterations; iter++) {
            auto zrSq = z.re.sqr();
            auto ziSq = z.im.sqr();
            auto magSq = zrSq + ziSq;
            
            if (magSq.toDouble() > escapeThreshold.toDouble()) {
                break;
            }
            
            result.orbit ~= [z.re.toDouble(), z.im.toDouble()];
            
            if (options.hasIntegerPower && options.integerPower >= 0) {
                z.powAndAdd(options.integerPower, c);
            } else {
                double zrD = z.re.toDouble();
                double ziD = z.im.toDouble();
                
                import std.math : sqrt, atan2, cos, sin, pow, log;
                double mag = sqrt(zrD * zrD + ziD * ziD);
                
                if (mag < 1e-300) {
                    z.re = c.re;
                    z.im = c.im;
                } else if (exp < 0) {
                    double posExp = -exp;
                    double newMag = pow(mag, posExp);
                    if (newMag > 1e300) {
                        break;
                    }
                    double invMag = 1.0 / newMag;
                    double theta = atan2(ziD, zrD);
                    double newTheta = -posExp * theta;
                    
                    z.re = GMPFloat(invMag * cos(newTheta)) + c.re;
                    z.im = GMPFloat(invMag * sin(newTheta)) + c.im;
                } else {
                    double newMag = pow(mag, exp);
                    double theta = atan2(ziD, zrD);
                    double newTheta = exp * theta;
                    
                    z.re = GMPFloat(newMag * cos(newTheta)) + c.re;
                    z.im = GMPFloat(newMag * sin(newTheta)) + c.im;
                }
            }
        }
    }
    else {
        for (iter = 0; iter < cfg.maxIterations; iter++) {
            auto zrSq = z.re.sqr();
            auto ziSq = z.im.sqr();
            auto magSq = zrSq + ziSq;
            
            if (magSq.toDouble() > escapeThreshold.toDouble()) {
                break;
            }
            
            result.orbit ~= [z.re.toDouble(), z.im.toDouble()];
            
            auto newRe = zrSq - ziSq + c.re;
            auto newIm = z.re * z.im * GMPFloat(2.0) + c.im;
            z.re = newRe;
            z.im = newIm;
        }
    }
    
    double smoothed = cast(double)iter;
    if (iter < cfg.maxIterations && iter > 0) {
        auto zrSq = z.re.sqr();
        auto ziSq = z.im.sqr();
        auto finalMag = (zrSq + ziSq).toDouble();
        if (finalMag > 1) {
            smoothed = iter + 1 - log(log(finalMag) / 2) / log(2.0);
        }
    }
    
    result.iter = IterResult(iter, smoothed);
    return result;
}

