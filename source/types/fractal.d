module types.fractal;

enum FractalType { 
    mandelbrot, 
    multibrot, 
    ship,
    mandelbar
}

enum BuddhaMode { 
    none, 
    buddha, 
    antibuddha 
}

enum PrecisionMode {
    standard,
    quaddouble,
    arbitrary
}

enum ColorFunc {
    ultrafrac,
    hsv,
    gray,
    blue,
    red,
    base,
    seashore,
    fire,
    oceanid,
    cnfsso,
    acid,
    softhours
}

struct GMPFractalOptions {
    bool hasIntegerPower;
    uint integerPower;
}

GMPFractalOptions determineGMPFractalOptions(double exponent) {
    import std.math : round, fabs;
    GMPFractalOptions opts;
    double rounded = round(exponent);
    if (fabs(exponent - rounded) <= 1e-9 && rounded >= 2 && rounded <= uint.max) {
        opts.hasIntegerPower = true;
        opts.integerPower = cast(uint)rounded;
    }
    return opts;
}

