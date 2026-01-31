module types.render;

import types.fractal;

import std.typecons : Tuple;
alias Complex = Tuple!(real, real);

alias Coord = Tuple!(int, int);

struct RenderConfig {
    real originX = -0.5;
    real originY = 0.0;
    real radius = 2.0;
    int width = 800;
    int height = 800;
    
    string originXStr = "-0.5";
    string originYStr = "0.0";
    string radiusStr = "2.0";
    
    uint maxIterations = 100;
    double escapeRadius = 4.0;
    
    ColorFunc colorFunc = ColorFunc.ultrafrac;
    uint paletteSize = 100;
    float paletteOffset = 0.0;
    bool paletteReverse = false;
    string paletteFile = "";
    
    FractalType fractalType = FractalType.mandelbrot;
    float multibrotExp = 2.0;
    bool legacyIteration = false;
    
    PrecisionMode precisionMode = PrecisionMode.standard;
    uint arbitraryPrecision = 50;
    
    BuddhaMode buddhaMode = BuddhaMode.none;
    
    static PrecisionMode detectPrecisionMode(real radius) {
        if (radius < 1e-12) {
            return PrecisionMode.arbitrary;
        }
        return PrecisionMode.standard;
    }
    
    static uint calculatePrecision(real radius) {
        if (radius >= 1e-10) return 30;
        if (radius >= 1e-15) return 50;
        if (radius >= 1e-20) return 70;
        if (radius >= 1e-30) return 100;
        return 150;
    }
    
    static uint calculateOptimalPrecision(real radius, int width, int height) {
        import std.math : log10, ceil;
        import std.algorithm : max, min;
        
        int maxDim = max(width, height);
        real pixelSpacing = (radius * 2.0) / maxDim;
        
        real logPixelSpacing = log10(pixelSpacing);
        uint digitsNeeded = cast(uint)(ceil(-logPixelSpacing) + 25);
        
        uint minPrecision = 50;
        uint maxPrecision = 1200;
        
        return max(minPrecision, min(digitsNeeded, maxPrecision));
    }
}
