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
    
    string originXStr;
    string originYStr;
    string radiusStr;
    
    uint maxIterations = 100;
    double escapeRadius = 4.0;
    
    ColorFunc colorFunc = ColorFunc.ultrafrac;
    uint paletteSize = 100;
    float paletteOffset = 0.0;
    bool paletteReverse = false;
    string paletteFile = "";
    
    FractalType fractalType = FractalType.mandelbrot;
    float multibrotExp = 2.0;
    
    PrecisionMode precisionMode = PrecisionMode.standard;
    
    BuddhaMode buddhaMode = BuddhaMode.none;
}

