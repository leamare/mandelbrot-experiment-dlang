
module calc.iterator;

import std.math : sqrt, log, log2;
import std.complex : Complex;

import types.iter_result;
import types.fractal;
import types.render;
import precision.method;
import precision.constants;

private T localAbs(T)(T x) {
    return x < 0 ? -x : x;
}

IterResult iterateDouble(
    double cx, double cy,
    uint maxIterations,
    double escapeRadius2 = 4.0,
    FractalType fractalType = FractalType.mandelbrot,
    float exponent = 2.0
) {
    double zx = 0.0;
    double zy = 0.0;
    double zx2 = 0.0;
    double zy2 = 0.0;
    
    int iter = 0;
    
    while (iter < maxIterations && (zx2 + zy2) < escapeRadius2) {
        final switch (fractalType) {
            case FractalType.mandelbrot:
                zy = 2.0 * zx * zy + cy;
                zx = zx2 - zy2 + cx;
                break;
                
            case FractalType.ship:
                zy = localAbs(2.0 * zx * zy) + cy;
                zx = zx2 - zy2 + cx;
                break;
                
            case FractalType.mandelbar:
                zy = -2.0 * zx * zy + cy;
                zx = zx2 - zy2 + cx;
                break;
                
            case FractalType.multibrot:
                if (exponent == 2.0) {
                    zy = 2.0 * zx * zy + cy;
                    zx = zx2 - zy2 + cx;
                } else {
                    auto z = Complex!double(zx, zy);
                    import std.complex : abs, arg;
                    import std.math : cos, sin, pow;
                    double r = abs(z);
                    double theta = arg(z);
                    double rn = pow(r, exponent);
                    double ntheta = exponent * theta;
                    zx = rn * cos(ntheta) + cx;
                    zy = rn * sin(ntheta) + cy;
                }
                break;
        }
        
        zx2 = zx * zx;
        zy2 = zy * zy;
        iter++;
    }
    
    double smoothed = cast(double)iter;
    if (iter < maxIterations) {
        double mag2 = zx2 + zy2;
        if (mag2 > 1.0) {
            double logZn = log(mag2) / 2.0;
            double nu = log(logZn / log(2.0)) / log(2.0);
            smoothed = iter + 1.0 - nu;
        }
    }
    
    return IterResult(iter, smoothed);
}

IterResult iterateQuadDouble(
    int px, int py,
    const ref RenderConfig cfg,
    ref const QDPixelConverter converter
) {
    import calc.types.quaddouble : QuadDouble, QDComplex, QDPixelConverter, sqr;
    
    auto c = converter.pixelToComplex(px, py);
    auto z = QDComplex.zero();
    
    int iter = 0;
    double escapeRadius2 = cfg.escapeRadius * cfg.escapeRadius;
    
    while (iter < cfg.maxIterations) {
        double mag2 = z.magnitudeSquaredDouble();
        if (mag2 > escapeRadius2) break;
        
        z.squareAndAdd(c);
        iter++;
    }
    
    double smoothed = cast(double)iter;
    if (iter < cfg.maxIterations) {
        double mag2 = z.magnitudeSquaredDouble();
        if (mag2 > 1.0) {
            double logZn = log(mag2) / 2.0;
            double nu = log(logZn / log(2.0)) / log(2.0);
            smoothed = iter + 1.0 - nu;
        }
    }
    
    return IterResult(iter, smoothed);
}

import calc.quaddouble : QDPixelConverter;

IterResult iterateGMP(
    int px, int py,
    const ref RenderConfig cfg,
    ref const GMPPixelConverter converter,
    GMPFractalOptions gmpOptions = GMPFractalOptions.init
) {
    import gmp_arb : GMPFloat, GMPComplex, GMPPixelConverter;
    
    auto c = GMPComplex.zero();
    converter.pixelToComplex(px, py, c);
    auto z = GMPComplex.zero();
    
    int iter = 0;
    double escapeRadius2 = cfg.escapeRadius * cfg.escapeRadius;
    
    final switch (cfg.fractalType) {
        case FractalType.mandelbrot:
            while (iter < cfg.maxIterations) {
                double mag2 = z.magnitudeSquaredDouble();
                if (mag2 > escapeRadius2) break;
                z.squareAndAdd(c);
                iter++;
            }
            break;
            
        case FractalType.ship:
            while (iter < cfg.maxIterations) {
                double mag2 = z.magnitudeSquaredDouble();
                if (mag2 > escapeRadius2) break;
                
                z.absComponents();
                z.squareAndAdd(c);
                iter++;
            }
            break;
            
        case FractalType.multibrot:
            if (gmpOptions.hasIntegerPower) {
                uint power = gmpOptions.integerPower;
                while (iter < cfg.maxIterations) {
                    double mag2 = z.magnitudeSquaredDouble();
                    if (mag2 > escapeRadius2) break;
                    z.powAndAdd(power, c);
                    iter++;
                }
            } else {
                return iterateDouble(
                    cfg.originX + (px - cfg.width/2.0) * cfg.radius * 2.0 / cfg.width,
                    cfg.originY + (py - cfg.height/2.0) * cfg.radius * 2.0 / cfg.height,
                    cfg.maxIterations,
                    cfg.escapeRadius,
                    cfg.fractalType,
                    cfg.multibrotExp
                );
            }
            break;
            
        case FractalType.mandelbar:
            while (iter < cfg.maxIterations) {
                double mag2 = z.magnitudeSquaredDouble();
                if (mag2 > escapeRadius2) break;
                z.conjugateSquareAndAdd(c);
                iter++;
            }
            break;
    }
    
    double smoothed = cast(double)iter;
    if (iter < cfg.maxIterations) {
        double mag2 = z.magnitudeSquaredDouble();
        if (mag2 > 1.0) {
            double logZn = log(mag2) / 2.0;
            double nu = log(logZn / log(2.0)) / log(2.0);
            smoothed = iter + 1.0 - nu;
        }
    }
    
    return IterResult(iter, smoothed);
}

import gmp_arb : GMPPixelConverter;

IterResult iterate(
    int px, int py,
    const ref RenderConfig cfg,
    PrecisionMethod method = PrecisionMethod.auto_
) {
    if (method == PrecisionMethod.double_ || 
        (method == PrecisionMethod.auto_ && cfg.precisionMode == PrecisionMode.standard)) {
        
        import std.algorithm : min, max;
        double wd = cast(double)cfg.width;
        double hd = cast(double)cfg.height;
        double minDim = min(wd, hd);
        
        double di = cfg.width > cfg.height ? (wd - minDim) / minDim : 0;
        double dr = cfg.width > cfg.height ? 0 : (hd - minDim) / minDim;
        
        double cx = cfg.originX + cfg.radius * ((px / minDim) * 2.0 - (1.0 + di));
        double cy = cfg.originY + cfg.radius * ((py / minDim) * 2.0 - (1.0 + dr));
        
        return iterateDouble(
            cx, cy,
            cfg.maxIterations,
            cfg.escapeRadius,
            cfg.fractalType,
            cfg.multibrotExp
        );
    }
    
    if (method == PrecisionMethod.quaddouble) {
        auto converter = QDPixelConverter(
            cfg.width, cfg.height,
            cfg.originXStr, cfg.originYStr, cfg.radiusStr
        );
        return iterateQuadDouble(px, py, cfg, converter);
    }
    
    import gmp_arb : GMPFloat;
    import precision.auto_settings : combinedPrecisionDigits;
    
    uint digits = combinedPrecisionDigits(cfg.originXStr, cfg.originYStr, cfg.radiusStr, cfg.radius);
    GMPFloat.setPrecisionDigits(digits);
    
    auto converter = GMPPixelConverter(
        cfg.width, cfg.height,
        cfg.originXStr, cfg.originYStr, cfg.radiusStr
    );
    
    auto gmpOptions = determineGMPFractalOptions(cfg.multibrotExp);
    return iterateGMP(px, py, cfg, converter, gmpOptions);
}

