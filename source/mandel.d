module mandel;

import std.stdio;
import std.math;
import std.algorithm;
import std.conv;
import std.typecons;
import std.complex;

import dlib.image.color;
import dlib.image.hsv;

import calc.types.mpfr;

public import types.fractal : FractalType, GMPFractalOptions, determineGMPFractalOptions,
                              ColorFunc, BuddhaMode, PrecisionMode;
public import types.iter_result : IterResult;

// =============================================================================
// Types and Constants
// =============================================================================

const real LOG_BASE = 1.0 / log(2.0);

alias Complex = Tuple!(real, real);

alias Coord = Tuple!(int, int);

public import types.render : RenderConfig;

// =============================================================================
// Color Palettes
// =============================================================================

__gshared Color4f[][string] _paletteCache;
__gshared Object _paletteCacheMutex = new Object();

Color4f[] getPalette(ColorFunc cf, string paletteFile = "", bool reverse = false) {
    import config.palette : loadPaletteFromFile, reversePalette;
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

Color4f computeBuddhaColor(int hitCount, int backgroundLevel, int maxLevel) {
    if (maxLevel == 0 || hitCount == 0) return Color4f(0, 0, 0);
    
    if (hitCount <= backgroundLevel) {
        return Color4f(0, 0, 0);
    }
    
    double range = cast(double)(maxLevel - backgroundLevel);
    if (range <= 0) return Color4f(0, 0, 0);
    
    double normalized = cast(double)(hitCount - backgroundLevel) / range;
    
    if (normalized > 1.0) normalized = 1.0;
    if (normalized < 0.0) normalized = 0.0;
    
    double logHit = log(1.0 + cast(double)(hitCount - backgroundLevel));
    double logMax = log(1.0 + range);
    double logNormalized = logHit / logMax;
    
    normalized = normalized * 0.3 + logNormalized * 0.7;
    
    double c = pow(normalized, 0.5);
    
    if (c > 1) c = 1;
    if (c < 0) c = 0;
    
    return Color4f(cast(float)c, cast(float)c, cast(float)c);
}
