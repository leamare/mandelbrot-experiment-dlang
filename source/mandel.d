module mandel;

import std.stdio;
import std.math;
import std.algorithm;
import std.conv;
import std.typecons;
import std.complex;

import dlib.image.color;
import dlib.image.hsv;

import gmp_arb;

// =============================================================================
// Types and Constants
// =============================================================================

const real LOG_BASE = 1.0 / log(2.0);

alias Complex = Tuple!(real, real);
alias Coord = Tuple!(int, int);

struct IterResult {
    int iterations;
    double smoothed;
    
    this(int i, double s) {
        iterations = i;
        smoothed = s;
    }
}

struct GMPFractalOptions {
    bool hasIntegerPower;
    uint integerPower;
}

enum FractalType { 
    mandelbrot, 
    multibrot, 
    ship 
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

enum BuddhaMode { 
    none, 
    buddha, 
    antibuddha 
}

enum PrecisionMode {
    standard,
    arbitrary
}

// =============================================================================
// Configuration Structs (no mutable global state)
// =============================================================================

struct RenderConfig {
    real originX = -0.5;
    real originY = 0.0;
    real radius = 2.0;
    
    string originXStr = "-0.5";
    string originYStr = "0.0";
    string radiusStr = "2.0";
    
    int width = 800;
    int height = 800;
    
    uint maxIterations = 100;
    
    FractalType fractalType = FractalType.mandelbrot;
    float multibrotExp = 2.0;
    
    ColorFunc colorFunc = ColorFunc.ultrafrac;
    int paletteSize = 100;
    float paletteOffset = 0.0;
    bool paletteReverse = false;
    string paletteFile = "";
    
    BuddhaMode buddhaMode = BuddhaMode.none;
    
    PrecisionMode precisionMode = PrecisionMode.standard;
    uint arbitraryPrecision = 50;
    
    static PrecisionMode detectPrecisionMode(real radius) {
        if (radius < 1e-12) {
            return PrecisionMode.arbitrary;
        }
        return PrecisionMode.standard;
    }
    
    static uint calculatePrecision(real radius) {
        // TODO: this looks like shit
        if (radius >= 1e-10) return 30;
        if (radius >= 1e-15) return 50;
        if (radius >= 1e-20) return 70;
        if (radius >= 1e-30) return 100;
        return 150;
    }
    
    static uint calculateOptimalPrecision(real radius, int width, int height) {
        import std.math : log10, ceil;
        import std.algorithm : max;
        
        int maxDim = max(width, height);
        real pixelSpacing = (radius * 2.0) / maxDim;
        
        real logPixelSpacing = log10(pixelSpacing);
        uint digitsNeeded = cast(uint)(ceil(-logPixelSpacing) + 25);
        
        uint minPrecision = 50;
        
        uint maxPrecision = 500;
        
        return max(minPrecision, min(digitsNeeded, maxPrecision));
    }
}

// =============================================================================
// Color Palettes
// =============================================================================

__gshared Color4f[][string] _paletteCache;
__gshared Object _paletteCacheMutex = new Object();

Color4f[] getPalette(ColorFunc cf, string paletteFile = "", bool reverse = false) {
    import palette_loader : loadPaletteFromFile, reversePalette;
    import std.conv;
    import std.format;
    
    // TODO: load arbitrary palettes
    string targetFile;
    if (paletteFile.length > 0) {
        targetFile = paletteFile;
    } else {
        final switch (cf) {
            case ColorFunc.ultrafrac: targetFile = "ultrafrac.json"; break;
            case ColorFunc.seashore: targetFile = "seashore.json"; break;
            case ColorFunc.fire: targetFile = "fire.json"; break;
            case ColorFunc.oceanid: targetFile = "oceanid.json"; break;
            case ColorFunc.cnfsso: targetFile = "cnfsso.json"; break;
            case ColorFunc.acid: targetFile = "acid.json"; break;
            case ColorFunc.softhours: targetFile = "softhours.json"; break;
            case ColorFunc.hsv:
            case ColorFunc.gray:
            case ColorFunc.blue:
            case ColorFunc.red:
            case ColorFunc.base:
                targetFile = "ultrafrac.json";
                break;
        }
    }
    
    string cacheKey = format!"%s:%s"(targetFile, reverse ? "r" : "n");
    
    synchronized (_paletteCacheMutex) {
        if (cacheKey in _paletteCache) {
            return _paletteCache[cacheKey].dup;
        }
        
        Color4f[] loaded = null;
        
        if (paletteFile.length > 0) {
            loaded = loadPaletteFromFile(paletteFile);
            if (loaded is null) {
                writeln("WARNING: Failed to load palette from '", paletteFile, "', trying default");
            }
        }
        
        if (loaded is null) {
            loaded = loadPaletteFromFile(targetFile);
        }
        
        if (loaded is null && targetFile != "ultrafrac.json") {
            loaded = loadPaletteFromFile("ultrafrac.json");
            if (loaded !is null) {
                writeln("WARNING: Palette '", targetFile, "' not found, using ultrafrac.json");
            }
        }
        
        if (loaded is null) {
            writeln("ERROR: No palette files found, using fallback gradient");
            Color4f[] fallback;
            for (int i = 0; i < 256; i++) {
                float v = cast(float)i / 255.0f;
                fallback ~= Color4f(v, v, v);
            }
            loaded = fallback;
        }
        
        if (reverse) {
            loaded = reversePalette(loaded);
        }
        
        _paletteCache[cacheKey] = loaded;
        
        return loaded;
    }
}

// =============================================================================
// Coordinate Conversion
// =============================================================================

/// Convert pixel coordinates to complex plane coordinates
/// px = column (0 to width-1), py = row (0 to height-1)
Complex pixelToComplex(int px, int py, const ref RenderConfig cfg) {
    real di, dr;
    
    if (cfg.width == cfg.height) {
        di = 0;
        dr = 0;
    } else {
        real diff = cast(real)(max(cfg.width, cfg.height) - min(cfg.width, cfg.height)) / min(cfg.width, cfg.height);
        di = cfg.width > cfg.height ? diff : 0;
        dr = cfg.width > cfg.height ? 0 : diff;
    }
    
    const auto pixelSize = cfg.radius * 2 / min(cfg.width, cfg.height);
    
    real cr = (to!real(px) * pixelSize) - (-cfg.originX + cfg.radius * (1 + di));
    real ci = -(to!real(py) * pixelSize) + (cfg.originY + cfg.radius * (1 + dr));
    
    return Complex(cr, ci);
}

/// Convert complex coordinates back to pixel
/// Returns Coord(column, row) = (px, py)
Coord complexToPixel(real cr, real ci, const ref RenderConfig cfg) {
    real di, dr;
    
    if (cfg.width == cfg.height) {
        di = 0;
        dr = 0;
    } else {
        real diff = cast(real)(max(cfg.width, cfg.height) - min(cfg.width, cfg.height)) / min(cfg.width, cfg.height);
        di = cfg.width > cfg.height ? diff : 0;
        dr = cfg.width > cfg.height ? 0 : diff;
    }
    
    const auto pixelSize = cfg.radius * 2 / min(cfg.width, cfg.height);
    
    int px = cast(int)(round((cr + (-cfg.originX) + cfg.radius * (1 + di)) / pixelSize));
    int py = cast(int)(round(cfg.height - (ci - cfg.originY + cfg.radius * (1 + dr)) / pixelSize));
    
    return Coord(px, py);
}

// =============================================================================
// Iteration Functions (Pure, No Side Effects)
// =============================================================================

/// Standard precision Mandelbrot iteration
IterResult iterateStandard(int px, int py, const ref RenderConfig cfg) {
    const Complex c = pixelToComplex(px, py, cfg);
    const real cr = c[0];
    const real ci = c[1];
    
    real zr = 0;
    real zi = 0;
    real zrTemp;
    int iter;
    
    const real escapeRadius = 1 << 16;
    
    if (cfg.fractalType == FractalType.multibrot && cfg.multibrotExp != 2.0) {
        real r;
        
        if (cfg.multibrotExp > 0) {
            for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
                r = pow(zr*zr + zi*zi, cfg.multibrotExp/2);
                zrTemp = r * cos(cfg.multibrotExp * atan2(zi, zr)) + cr;
                zi = r * sin(cfg.multibrotExp * atan2(zi, zr)) + ci;
                zr = zrTemp;
            }
        } else if (cfg.multibrotExp < 0) {
            auto m = -cfg.multibrotExp;
            for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
                r = pow(zr*zr + zi*zi, m/2);
                zrTemp = r * cos(m * atan2(zi, zr));
                zi = r * sin(m * atan2(zi, zr));
                zr = zrTemp;
                
                r = zr*zr + zi*zi;
                if (r == 0) {
                    zr = cr;
                    zi = ci;
                } else {
                    zrTemp = zr / r + cr;
                    zi = -zi / r + ci;
                    zr = zrTemp;
                }
            }
        } else {
            for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
                zr = 1 + cr;
                zi = ci;
            }
        }
    } else if (cfg.fractalType == FractalType.mandelbar) {
        if (cfg.multibrotExp == 2.0) {
            for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
                zrTemp = zr*zr - zi*zi + cr;
                zi = -2*zr*zi + ci;
                zr = zrTemp;
            }
        } else {
            real r;
            for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
                r = pow(zr*zr + zi*zi, cfg.multibrotExp/2);
                auto theta = cfg.multibrotExp * atan2(-zi, zr);
                zrTemp = r * cos(theta) + cr;
                zi = r * sin(theta) + ci;
                zr = zrTemp;
            }
        }
    } else if (cfg.fractalType == FractalType.ship) {
        for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
            zrTemp = zr*zr - zi*zi + cr;
            zi = abs(2*zr*zi) + ci;
            zr = zrTemp;
      }
    } else {
        for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
            zrTemp = zr*zr - zi*zi + cr;
            zi = 2*zr*zi + ci;
            zr = zrTemp;
        }
    }
    
    // Smooth iteration count
    double smoothed = iter;
    
    if (cfg.fractalType == FractalType.multibrot && cfg.multibrotExp <= 1) {
        iter = cfg.maxIterations - iter;
    }
    
    if (iter < cfg.maxIterations) {
        const real logZn = log(zr*zr + zi*zi) * 0.5;
        const double nu = log(logZn * LOG_BASE) * LOG_BASE;
        smoothed = 1 + to!double(iter) - nu;
    }
    
    return IterResult(iter, smoothed);
}

/// GMP-based arbitrary precision iteration
IterResult iterateGMPDirect(int px, int py, const ref RenderConfig cfg, 
                            const ref GMPPixelConverter converter,
                            const GMPFractalOptions options) {
    const double escapeRadius2 = (1 << 16);
    auto c = converter.pixelToComplex(px, py);
    auto z = GMPComplex.zero();
    
    auto powComplexInt = (GMPComplex base, uint exponent) {
        GMPComplex result = GMPComplex(GMPFloat(1.0), GMPFloat(0.0));
        GMPComplex factor = base;
        uint exp = exponent;
        while (exp > 0) {
            if (exp & 1) {
                result = result * factor;
            }
            exp >>= 1;
            if (exp > 0) {
                factor = factor * factor;
            }
        }
        return result;
    };

    for (int iter = 0; iter < cfg.maxIterations; iter++) {
        final switch (cfg.fractalType) {
            case FractalType.mandelbrot: {
                z.squareAndAdd(c);
                break;
            }
            case FractalType.ship: {
                auto zr2 = gmp_arb.sqr(z.re);
                auto zi2 = gmp_arb.sqr(z.im);
                auto two = GMPFloat(2.0);
                auto zrIm = z.re * z.im * two;
                auto ziAbs = gmp_arb.abs(zrIm);
                z = GMPComplex(zr2 - zi2 + c.re, ziAbs + c.im);
                break;
            }
            case FractalType.multibrot: {
                uint power = options.integerPower > 0 ? options.integerPower : 2;
                if (power <= 2) {
                    z.squareAndAdd(c);
                } else {
                    auto raised = powComplexInt(z, power);
                    z = raised + c;
                }
                break;
            }
            case FractalType.mandelbar: {
                uint power = options.integerPower > 0 ? options.integerPower : 2;
                auto conjZ = GMPComplex(z.re, -z.im);
                auto raised = powComplexInt(conjZ, power);
                z = raised + c;
                break;
            }
        }
        
        double mag2 = z.magnitudeSquaredDouble();
        if (!mag2.isFinite) {
            return IterResult(iter, cast(double)iter);
        }
        if (mag2 > escapeRadius2) {
            double logZn = log(mag2) * 0.5;
            double nu = log(logZn / log(2.0)) / log(2.0);
            double smoothed = 1 + cast(double)iter - nu;
            return IterResult(iter, smoothed);
        }
    }

    return IterResult(cast(int)cfg.maxIterations, cast(double)cfg.maxIterations);
}

IterResult iterate(int px, int py, const ref RenderConfig cfg) {
    return iterateStandard(px, py, cfg);
}

struct OrbitResult {
    IterResult iter;
    Complex[] orbit;
}

OrbitResult iterateWithOrbit(int px, int py, const ref RenderConfig cfg) {
    OrbitResult result;
    result.orbit.reserve(cfg.maxIterations);
    
    const Complex c = pixelToComplex(px, py, cfg);
    const real cr = c[0];
    const real ci = c[1];
    
    real zr = 0;
    real zi = 0;
    real zrTemp;
    int iter;
    
    const real escapeRadius = 1 << 16;
    
    if (cfg.fractalType == FractalType.ship) {
        for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
            zrTemp = zr*zr - zi*zi + cr;
            zi = abs(2*zr*zi) + ci;
            zr = zrTemp;
            result.orbit ~= Complex(zr, zi);
        }
    } else {
        for (iter = 0; zr*zr + zi*zi <= escapeRadius && iter < cfg.maxIterations; iter++) {
            zrTemp = zr*zr - zi*zi + cr;
            zi = 2*zr*zi + ci;
            zr = zrTemp;
            result.orbit ~= Complex(zr, zi);
        }
    }
    
    double smoothed = iter;
    if (iter < cfg.maxIterations) {
        const real logZn = log(zr*zr + zi*zi) * 0.5;
        const double nu = log(logZn * LOG_BASE) * LOG_BASE;
        smoothed = 1 + to!double(iter) - nu;
    }
    
    result.iter = IterResult(iter, smoothed);
    return result;
}

// =============================================================================
// Coloring Functions (Pure)
// =============================================================================

/// Compute pixel color from iteration result
Color4f computeColor(IterResult iter, const ref RenderConfig cfg) {
    if (iter.iterations == cfg.maxIterations) {
        return Color4f(0, 0, 0);
    }
    
    double iterD = iter.smoothed;
    
    switch (cfg.colorFunc) {
        case ColorFunc.ultrafrac:
        case ColorFunc.seashore:
        case ColorFunc.fire:
        case ColorFunc.oceanid:
        case ColorFunc.cnfsso:
        case ColorFunc.acid:
        case ColorFunc.softhours:
            return paletteColor(iterD, cfg);
            
        case ColorFunc.hsv:
            return hsvColor(iterD, cfg);
            
        case ColorFunc.base:
            return iterD > 0 ? Color4f(1, 1, 1) : Color4f(0, 0, 0);
            
        case ColorFunc.gray:
        case ColorFunc.blue:
        case ColorFunc.red:
            return gradientColor(iterD, cfg);
            
        default:
            return Color4f(0, 0, 0);
    }
}

private Color4f paletteColor(double iterD, const ref RenderConfig cfg) {
    auto palette = getPalette(cfg.colorFunc, cfg.paletteFile, cfg.paletteReverse);
    
    double effectiveIter = iterD;
    if (cfg.maxIterations > 10000) {
        double remaining = cfg.maxIterations - iterD + 1;
        if (remaining > 0) {
            double logMax = log(cast(double)cfg.maxIterations);
            double logRemaining = log(remaining);
            effectiveIter = (logMax - logRemaining) / logMax * cfg.paletteSize * 2;
        }
    }
    
    double cyclePos = (effectiveIter + cfg.paletteOffset * cfg.paletteSize) / cfg.paletteSize;
    cyclePos = cyclePos - floor(cyclePos);
    
    double palettePos = cyclePos * palette.length;
    size_t c1 = cast(size_t)(floor(palettePos)) % palette.length;
    size_t c2 = (c1 + 1) % palette.length;
    
    double t = palettePos - floor(palettePos);
    double smooth_t = (1 - cos(t * PI)) / 2;
    
    return Color4f(
        palette[c1].r + (palette[c2].r - palette[c1].r) * smooth_t,
        palette[c1].g + (palette[c2].g - palette[c1].g) * smooth_t,
        palette[c1].b + (palette[c2].b - palette[c1].b) * smooth_t,
    );
}

private Color4f hsvColor(double iterD, const ref RenderConfig cfg, bool reverse = false) {
    auto v = 2 * (iterD / cfg.paletteSize) % 2;
    if (reverse) v = 2 - v;
    const auto vc = v > 1 ? 2 - v : v;
    v /= 2;
    auto vl = 0.25 + vc * 2;
    auto vs = 0.75 + vc * 2;

    auto c = hsv(360.0 * v, vs > 1 ? 1 : vs, vl > 1 ? 1 : vl);
    return Color4f(c.r, c.g, c.b);
}

private Color4f gradientColor(double iterD, const ref RenderConfig cfg, bool reverse = false) {
    auto v = 2 * iterD / cfg.paletteSize % 2;
    v = v > 1 ? 2 - v : v;
    if (reverse) v = 1.0 - v;
    
    switch (cfg.colorFunc) {
        case ColorFunc.blue:
            return Color4f(pow(v, 4), pow(v, 2) * 2, v * 3);
        case ColorFunc.red:
            return Color4f(v * 3, pow(v, 2) * 2, pow(v, 4));
        default:
    return Color4f(v, v, v);
  }
}

Color4f computeBuddhaColor(int hitCount, int maxHitCount) {
    if (maxHitCount == 0) return Color4f(0, 0, 0);
    
    double c = pow(cast(double)(hitCount) / cast(double)(maxHitCount), 0.25);
  if (c > 1) c = 1;

  return Color4f(c, c, c);
}
