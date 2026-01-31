
module calc.iterate.quaddouble_iter;

import std.math : log;
import std.algorithm : min, max;

import types.iter_result;
import types.fractal;
import types.render;
import calc.iterate.common;
import calc.types.quaddouble;

struct QDPixelConverterUnified {
    QuadDouble originX;
    QuadDouble originY;
    QuadDouble radius;
    QuadDouble pixelSize;
    int width, height;
    double di, dr;
    
    @disable this();
    
    this(int w, int h, string originXStr, string originYStr, string radiusStr) {
        width = w;
        height = h;
        
        originX = QuadDouble(originXStr);
        originY = QuadDouble(originYStr);
        radius = QuadDouble(radiusStr);
        
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
        auto two = QuadDouble(2.0);
        auto minDimQD = QuadDouble(minDim);
        pixelSize = (radius * two) / minDimQD;
    }
    
    static QDPixelConverterUnified fromConfig(const ref RenderConfig cfg) {
        return QDPixelConverterUnified(
            cfg.width, cfg.height,
            cfg.originXStr, cfg.originYStr, cfg.radiusStr
        );
    }
    
    QDComplex pixelToComplex(int px, int py) const {
        auto pxCenter = QuadDouble(cast(double)px + 0.5);
        auto pyCenter = QuadDouble(cast(double)py + 0.5);
        
        auto onePlusDi = QuadDouble(1.0 + di);
        auto cReal = pxCenter * pixelSize + originX - radius * onePlusDi;
        
        auto onePlusDr = QuadDouble(1.0 + dr);
        auto negPyPixelSize = -(pyCenter * pixelSize);
        auto cImag = negPyPixelSize + originY + radius * onePlusDr;
        
        return QDComplex(cReal, cImag);
    }
}

private QuadDouble opDiv(QuadDouble a, QuadDouble b) {
    double aD = a.toDouble();
    double bD = b.toDouble();
    return QuadDouble(aD / bD);
}

IterResult iterateQuadDouble(int px, int py, const ref RenderConfig cfg) {
    auto converter = QDPixelConverterUnified.fromConfig(cfg);
    auto c = converter.pixelToComplex(px, py);
    
    return iterateQDComplex(c, IterParams.fromConfig(cfg));
}

IterResult iterateQDComplex(QDComplex c, IterParams params) {
    auto z = QDComplex.zero();
    
    int iter = 0;
    
    while (iter < params.maxIterations) {
        double mag2 = z.magnitudeSquaredDouble();
        if (mag2 > params.escapeRadius2) break;
        
        final switch (params.fractalType) {
            case FractalType.mandelbrot:
                z.squareAndAdd(c);
                break;
                
            case FractalType.ship:
                z.re = calc.types.quaddouble.abs(z.re);
                z.im = calc.types.quaddouble.abs(z.im);
                z.squareAndAdd(c);
                break;
                
            case FractalType.mandelbar:
                z.im = -z.im;
                z.squareAndAdd(c);
                break;
                
            case FractalType.multibrot:
                z.squareAndAdd(c);
                break;
        }
        
        iter++;
    }
    
    double mag2 = z.magnitudeSquaredDouble();
    double smoothed = smoothIterations(iter, mag2, params.maxIterations);
    return IterResult(iter, smoothed);
}

