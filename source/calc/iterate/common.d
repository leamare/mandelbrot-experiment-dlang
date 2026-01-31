module calc.iterate.common;

import std.math : log, log2;

import types.iter_result;
import types.fractal;
import types.render;

struct IterParams {
    uint maxIterations = 100;
    double escapeRadius2 = 4.0;
    FractalType fractalType = FractalType.mandelbrot;
    float multibrotExp = 2.0;
    
    static IterParams fromConfig(const ref RenderConfig cfg) {
        IterParams p;
        p.maxIterations = cfg.maxIterations;
        p.escapeRadius2 = cfg.escapeRadius * cfg.escapeRadius;
        p.fractalType = cfg.fractalType;
        p.multibrotExp = cfg.multibrotExp;
        return p;
    }
}

double smoothIterations(int iter, double mag2, uint maxIterations) {
    if (iter >= maxIterations) {
        return cast(double)maxIterations;
    }
    
    if (mag2 <= 1.0) {
        return cast(double)iter;
    }
    
    double logZn = log(mag2) / 2.0;
    double nu = log(logZn / log(2.0)) / log(2.0);
    return iter + 1.0 - nu;
}

struct PixelToComplexParams {
    int width;
    int height;
    double minDim;
    double di;
    double dr;
    double pixelSize;
    
    static PixelToComplexParams fromDimensions(int w, int h, double radius) {
        import std.algorithm : min, max;
        
        PixelToComplexParams p;
        p.width = w;
        p.height = h;
        p.minDim = min(cast(double)w, cast(double)h);
        
        p.di = 0;
        p.dr = 0;
        if (w != h) {
            double diff = (max(cast(double)w, cast(double)h) - p.minDim) / p.minDim;
            p.di = w > h ? diff : 0;
            p.dr = w > h ? 0 : diff;
        }
        
        p.pixelSize = radius * 2.0 / p.minDim;
        return p;
    }
    
    void toComplex(int px, int py, double originX, double originY, double radius,
                   out double cr, out double ci) const {
        double pxCenter = cast(double)px + 0.5;
        double pyCenter = cast(double)py + 0.5;
        
        cr = pxCenter * pixelSize + originX - radius * (1.0 + di);
        ci = -pyCenter * pixelSize + originY + radius * (1.0 + dr);
    }
}

