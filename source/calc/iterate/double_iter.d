module calc.iterate.double_iter;

import std.math : pow, cos, sin, atan2, abs, log, round;
import std.algorithm : min, max;
import std.conv : to;
import std.typecons : Tuple;

import types.iter_result;
import types.fractal;
import types.render;
import calc.iterate.common;

alias ComplexD = Tuple!(double, double);

alias Coord = Tuple!(int, int);

struct DoublePixelConverter {
    double originX;
    double originY;
    double radius;
    PixelToComplexParams params;
    
    this(int w, int h, double ox, double oy, double r) {
        originX = ox;
        originY = oy;
        radius = r;
        params = PixelToComplexParams.fromDimensions(w, h, r);
    }
    
    static DoublePixelConverter fromConfig(const ref RenderConfig cfg) {
        return DoublePixelConverter(
            cfg.width, cfg.height,
            cast(double)cfg.originX, cast(double)cfg.originY, 
            cast(double)cfg.radius
        );
    }
    
    void pixelToComplex(int px, int py, out double cr, out double ci) const {
        params.toComplex(px, py, originX, originY, radius, cr, ci);
    }
}

IterResult iterateDouble(int px, int py, const ref RenderConfig cfg) {
    auto converter = DoublePixelConverter.fromConfig(cfg);
    double cx, cy;
    converter.pixelToComplex(px, py, cx, cy);
    
    return iterateDoubleComplex(cx, cy, IterParams.fromConfig(cfg));
}

IterResult iterateDoubleComplex(double cx, double cy, IterParams params) {
    double zx = 0.0;
    double zy = 0.0;
    double zx2 = 0.0;
    double zy2 = 0.0;
    
    int iter = 0;
    
    while (iter < params.maxIterations && (zx2 + zy2) < params.escapeRadius2) {
        final switch (params.fractalType) {
            case FractalType.mandelbrot:
                double newZy = 2.0 * zx * zy + cy;
                zx = zx2 - zy2 + cx;
                zy = newZy;
                break;
                
            case FractalType.ship:
                double absZy = abs(2.0 * zx * zy) + cy;
                zx = zx2 - zy2 + cx;
                zy = absZy;
                break;
                
            case FractalType.mandelbar:
                double conjZy = -2.0 * zx * zy + cy;
                zx = zx2 - zy2 + cx;
                zy = conjZy;
                break;
                
            case FractalType.multibrot:
                iterateMultibrotStep(zx, zy, cx, cy, params.multibrotExp);
                break;
        }
        
        zx2 = zx * zx;
        zy2 = zy * zy;
        iter++;
    }
    
    double smoothed = smoothIterations(iter, zx2 + zy2, params.maxIterations);
    return IterResult(iter, smoothed);
}

private void iterateMultibrotStep(ref double zx, ref double zy, 
                                  double cx, double cy, float exponent) {
    if (exponent == 2.0) {
        double newZy = 2.0 * zx * zy + cy;
        zx = zx * zx - zy * zy + cx;
        zy = newZy;
        return;
    }
    
    double mag2 = zx * zx + zy * zy;
    
    if (exponent > 0) {
        if (mag2 == 0.0) {
            zx = cx;
            zy = cy;
            return;
        }
        double r = pow(mag2, exponent / 2.0);
        double theta = atan2(zy, zx);
        double ntheta = exponent * theta;
        zx = r * cos(ntheta) + cx;
        zy = r * sin(ntheta) + cy;
    } else if (exponent < 0) {
        double m = -exponent;
        if (mag2 == 0.0) {
            zx = cx;
            zy = cy;
            return;
        }
        
        double r = pow(mag2, m / 2.0);
        double theta = atan2(zy, zx);
        double mtheta = m * theta;
        double zmRe = r * cos(mtheta);
        double zmIm = r * sin(mtheta);
        
        double zmMag2 = zmRe * zmRe + zmIm * zmIm;
        if (zmMag2 == 0.0) {
            zx = cx;
            zy = cy;
        } else {
            zx = zmRe / zmMag2 + cx;
            zy = -zmIm / zmMag2 + cy;
        }
    } else {
        zx = 1.0 + cx;
        zy = cy;
    }
}

ComplexD pixelToComplex(int px, int py, const ref RenderConfig cfg) {
    double di, dr;
    
    if (cfg.width == cfg.height) {
        di = 0;
        dr = 0;
    } else {
        double diff = cast(double)(max(cfg.width, cfg.height) - min(cfg.width, cfg.height)) / min(cfg.width, cfg.height);
        di = cfg.width > cfg.height ? diff : 0;
        dr = cfg.width > cfg.height ? 0 : diff;
    }
    
    const auto pixelSize = cfg.radius * 2 / min(cfg.width, cfg.height);
    
    double cr = (cast(double)px * pixelSize) - (-cfg.originX + cfg.radius * (1 + di));
    double ci = -(cast(double)py * pixelSize) + (cfg.originY + cfg.radius * (1 + dr));
    
    return ComplexD(cr, ci);
}

Coord complexToPixel(double cr, double ci, const ref RenderConfig cfg) {
    double di, dr;
    
    if (cfg.width == cfg.height) {
        di = 0;
        dr = 0;
    } else {
        double diff = cast(double)(max(cfg.width, cfg.height) - min(cfg.width, cfg.height)) / min(cfg.width, cfg.height);
        di = cfg.width > cfg.height ? diff : 0;
        dr = cfg.width > cfg.height ? 0 : diff;
    }
    
    const auto pixelSize = cfg.radius * 2 / min(cfg.width, cfg.height);
    
    int px = cast(int)(round((cr + (-cfg.originX) + cfg.radius * (1 + di)) / pixelSize));
    int py = cast(int)(round(cfg.height - (ci - cfg.originY + cfg.radius * (1 + dr)) / pixelSize));
    
    return Coord(px, py);
}

struct OrbitResult {
    IterResult iter;
    ComplexD[] orbit;
}

OrbitResult iterateWithOrbit(int px, int py, const ref RenderConfig cfg) {
    OrbitResult result;
    result.orbit.reserve(cfg.maxIterations);
    
    const ComplexD c = pixelToComplex(px, py, cfg);
    const double cr = c[0];
    const double ci = c[1];
    
    double zr = 0;
    double zi = 0;
    double zrTemp;
    int iter;
    
    const double escapeRadius = 1 << 16;
    
    if (cfg.fractalType == FractalType.ship) {
        for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
            zrTemp = zr*zr - zi*zi + cr;
            zi = abs(2*zr*zi) + ci;
            zr = zrTemp;
            result.orbit ~= ComplexD(zr, zi);
        }
    } else {
        for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
            zrTemp = zr*zr - zi*zi + cr;
            zi = 2*zr*zi + ci;
            zr = zrTemp;
            result.orbit ~= ComplexD(zr, zi);
        }
    }
    
    double smoothed = iter;
    if (iter < cfg.maxIterations) {
        const double logZn = log(zr*zr + zi*zi) * 0.5;
        const double nu = log(logZn / log(2.0)) / log(2.0);
        smoothed = 1 + iter - nu;
    }
    
    result.iter = IterResult(iter, smoothed);
    return result;
}

