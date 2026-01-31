/**
 * Coloring Functions
 */
module render.coloring;

import std.math : log, sqrt, floor, sin, PI, isNaN, isInfinity;
import dlib.image.color;
import dlib.image.hsv : hsv;

import types.fractal;
import types.iter_result;
import types.render;
import config.palette : loadPaletteFromFileSilent, reversePalette, getPaletteInfo, PaletteInfo, PaletteMetadata;
import std.conv : to;

private __gshared Color4f[][string] _loadedPaletteCache;
private __gshared PaletteInfo*[string] _loadedPaletteInfoCache;
private __gshared Object _paletteCacheLock;

shared static this() {
    _paletteCacheLock = new Object();
}

private string colorFuncToFilename(ColorFunc cf) {
    final switch (cf) {
        case ColorFunc.ultrafrac: return "ultrafrac.json";
        case ColorFunc.seashore: return "seashore.json";
        case ColorFunc.fire: return "fire.json";
        case ColorFunc.oceanid: return "oceanid.json";
        case ColorFunc.cnfsso: return "cnfsso.json";
        case ColorFunc.acid: return "acid.json";
        case ColorFunc.softhours: return "softhours.json";
        case ColorFunc.hsv: return "hsv.json";
        case ColorFunc.gray: return "gray.json";
        case ColorFunc.blue: return "blue.json";
        case ColorFunc.red: return "red.json";
        case ColorFunc.base: return "base.json";
    }
}

private PaletteInfo* getCachedPaletteInfo(string paletteFile, bool reverse) {
    if (paletteFile.length == 0) return null;
    
    string cacheKey = paletteFile ~ (reverse ? ":r" : ":n");
    
    synchronized (_paletteCacheLock) {
        if (cacheKey in _loadedPaletteInfoCache) {
            return _loadedPaletteInfoCache[cacheKey];
        }
        
        PaletteInfo* info = getPaletteInfo(paletteFile, reverse);
        
        _loadedPaletteInfoCache[cacheKey] = info;
        return info;
    }
}

Color4f computeColor(const ref IterResult result, const ref RenderConfig cfg) {
    string paletteFile;
    
    if (cfg.paletteFile.length > 0) {
        paletteFile = cfg.paletteFile;
    } else {
        paletteFile = colorFuncToFilename(cfg.colorFunc);
    }
    
    if (paletteFile.length > 0) {
        PaletteInfo* info = getCachedPaletteInfo(paletteFile, cfg.paletteReverse);
        
        if (info !is null && info.colors.length > 0) {
            return computeColorWithPalette(result, cfg, info.colors);
        }
    }
    
    return computeColorWithPalette(result, cfg, null);
}

Color4f computeColorWithPalette(
    const ref IterResult result,
    const ref RenderConfig cfg,
    const Color4f[] externalPalette
) {
    bool useLegacyMultibrotColoring = cfg.legacyIteration;
    
    bool isInSet = result.iterations >= cfg.maxIterations;
    
    if (isInSet && !useLegacyMultibrotColoring) {
        return Color4f(0, 0, 0);
    }

    double smoothed = result.smoothed;
    int iter = result.iterations;
    
    if (useLegacyMultibrotColoring) {
        iter = cfg.maxIterations - result.iterations;
        
        double nu = cast(double)result.iterations + 1.0 - result.smoothed;
        
        if (iter < cfg.maxIterations) {
            smoothed = 1.0 + cast(double)iter - nu;
        } else {
            smoothed = cast(double)result.iterations;
        }
        
        smoothed += cfg.paletteOffset * cfg.paletteSize;
        smoothed = smoothed - floor(smoothed / cfg.maxIterations) * cfg.maxIterations;
        if (smoothed < 0) smoothed += cfg.maxIterations;
    } else {
        smoothed += cfg.paletteOffset * cfg.paletteSize;
    }
    
    Color4f[] palette;
    PaletteMetadata metadata;
    bool hasMetadata = false;
    
    if (externalPalette !is null && externalPalette.length > 0) {
        palette = externalPalette.dup;
    } else {
        string paletteFile = colorFuncToFilename(cfg.colorFunc);
        PaletteInfo* info = getCachedPaletteInfo(paletteFile, cfg.paletteReverse);
        if (info !is null) {
            palette = info.colors;
            metadata = info.metadata;
            hasMetadata = true;
        }
    }
    
    if (palette !is null && palette.length > 0) {
        if (useLegacyMultibrotColoring) {
            return interpolatePaletteLegacy(smoothed, iter, palette, cfg.paletteSize, cfg.maxIterations, cfg.paletteReverse);
        } else {
            return interpolatePalette(smoothed, palette, cfg.paletteSize, cfg.paletteSize, cfg.paletteReverse);
        }
    }
    
    final switch (cfg.colorFunc) {
        case ColorFunc.hsv:
            return colorHSV(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.gray:
            return colorGray(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.blue:
            return colorBlue(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.red:
            return colorRed(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.base:
            return colorBase(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.ultrafrac:
        case ColorFunc.seashore:
        case ColorFunc.fire:
        case ColorFunc.oceanid:
        case ColorFunc.cnfsso:
        case ColorFunc.acid:
        case ColorFunc.softhours:
            return Color4f(0, 0, 0);
    }
}

private Color4f interpolatePalette(double value, const Color4f[] palette, uint paletteSize, uint wrapValue, bool reverse) {
    import std.math : floor, abs;
    
    if (palette.length == 0) return Color4f(0, 0, 0);
    if (palette.length == 1) return palette[0];
    
    double t = value;
    if (reverse) t = -t;
    
    double paletteBlock = cast(double)paletteSize / palette.length;
    
    double absT = abs(t);
    size_t idx = cast(size_t)(floor(absT / paletteBlock)) % palette.length;
    
    double frac = (absT % paletteBlock) / paletteBlock;
    
    size_t idx2 = (idx + 1) % palette.length;
    
    auto c1 = palette[idx];
    auto c2 = palette[idx2];
    
    return Color4f(
        c1.r + (c2.r - c1.r) * cast(float)frac,
        c1.g + (c2.g - c1.g) * cast(float)frac,
        c1.b + (c2.b - c1.b) * cast(float)frac
    );
}

private Color4f interpolatePaletteLegacy(double iter_d, int iter, const Color4f[] palette, 
                                          uint paletteSize, uint maxIterations, bool reverse) {
    import std.math : floor, abs;
    import std.algorithm : min;
    
    if (palette.length == 0) return Color4f(0, 0, 0);
    if (palette.length == 1) return palette[0];
    
    double t = iter_d;
    if (reverse) t = cast(double)maxIterations - t;
    
    double paletteBlock = cast(double)paletteSize / palette.length;
    
    size_t c1 = cast(size_t)(floor(abs(t) / paletteBlock)) % palette.length;
    
    size_t c2;
    if (iter + paletteBlock >= maxIterations) {
        c2 = min(4, palette.length - 1);
    } else {
        c2 = (c1 + 1) % palette.length;
    }
    
    double vd = (t % paletteBlock) / paletteBlock;
    if (vd < 0) vd += 1.0;
    
    auto color1 = palette[c1];
    auto color2 = palette[c2];
    
    return Color4f(
        color1.r + (color2.r - color1.r) * cast(float)vd,
        color1.g + (color2.g - color1.g) * cast(float)vd,
        color1.b + (color2.b - color1.b) * cast(float)vd
    );
}

private Color4f colorUltrafrac(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);

    float r = cast(float)(0.5 + 0.5 * sin(2 * PI * (t + 0.0)));
    float g = cast(float)(0.5 + 0.5 * sin(2 * PI * (t + 0.33)));
    float b = cast(float)(0.5 + 0.5 * sin(2 * PI * (t + 0.67)));
    
    return Color4f(r, g, b);
}

private Color4f colorHSV(double value, uint paletteSize, bool reverse) {
    auto v = 2 * (value / paletteSize) % 2;
    if (reverse) v = 2 - v;
    const auto vc = v > 1 ? 2 - v : v;

    v /= 2;
    auto vl = 0.25 + vc * 2;
    auto vs = 0.75 + vc * 2;

    auto c = hsv(360.0 * v, vs > 1 ? 1 : vs, vl > 1 ? 1 : vl);
    return Color4f(c.r, c.g, c.b);
}

private Color4f colorGray(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float gray = cast(float)(0.5 + 0.5 * sin(2 * PI * t));
    return Color4f(gray, gray, gray);
}

private Color4f colorBlue(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);

    float blue = cast(float)(0.5 + 0.5 * sin(2 * PI * t));
    return Color4f(0, 0, blue);
}

private Color4f colorRed(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);

    float red = cast(float)(0.5 + 0.5 * sin(2 * PI * t));
    return Color4f(red, 0, 0);
}

private Color4f colorBase(double value, uint paletteSize, bool reverse) {
    return colorHSV(value, paletteSize, reverse);
}


