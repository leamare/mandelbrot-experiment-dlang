/**
 * Coloring Functions
 */
module render.coloring;

import std.math : log, sqrt, floor, sin, PI;
import dlib.image.color;
import dlib.image.hsv : hsv;

import types.fractal;
import types.iter_result;
import types.render;
import config.palette;
import std.conv : to;

private __gshared Color4f[][string] _loadedPaletteCache;
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

private Color4f[] getCachedPalette(string paletteFile, bool reverse) {
    if (paletteFile.length == 0) return null;
    
    string cacheKey = paletteFile ~ (reverse ? ":r" : ":n");
    
    synchronized (_paletteCacheLock) {
        if (cacheKey in _loadedPaletteCache) {
            return _loadedPaletteCache[cacheKey];
        }
        
        Color4f[] palette = loadPaletteFromFileSilent(paletteFile);
        if (palette !is null && reverse) {
            palette = reversePalette(palette);
        }
        
        _loadedPaletteCache[cacheKey] = palette;
        return palette;
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
        Color4f[] palette = getCachedPalette(paletteFile, cfg.paletteReverse);
        
        if (palette !is null && palette.length > 0) {
            return computeColorWithPalette(result, cfg, palette);
        }
    }
    
    return computeColorWithPalette(result, cfg, null);
}

Color4f computeColorWithPalette(
    const ref IterResult result,
    const ref RenderConfig cfg,
    const Color4f[] externalPalette
) {
    if (result.iterations >= cfg.maxIterations) {
        return Color4f(0, 0, 0);
    }
    
    double smoothed = result.smoothed;
    
    smoothed += cfg.paletteOffset * cfg.paletteSize;
    
    if (externalPalette !is null && externalPalette.length > 0) {
        return interpolatePalette(smoothed, externalPalette, cfg.paletteSize);
    }
    
    final switch (cfg.colorFunc) {
        case ColorFunc.ultrafrac:
            return colorUltrafrac(smoothed, cfg.paletteSize, cfg.paletteReverse);
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
        case ColorFunc.seashore:
            return colorSeashore(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.fire:
            return colorFire(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.oceanid:
            return colorOceanid(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.cnfsso:
            return colorCnfsso(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.acid:
            return colorAcid(smoothed, cfg.paletteSize, cfg.paletteReverse);
        case ColorFunc.softhours:
            return colorSofthours(smoothed, cfg.paletteSize, cfg.paletteReverse);
    }
}

private Color4f interpolatePalette(double value, const Color4f[] palette, uint paletteSize) {
    if (palette.length == 0) return Color4f(0, 0, 0);
    if (palette.length == 1) return palette[0];
    
    double cyclePos = value / paletteSize;
    
    cyclePos = cyclePos - floor(cyclePos);
    
    double palettePos = cyclePos * palette.length;
    size_t idx = cast(size_t)floor(palettePos);
    double frac = palettePos - idx;
    
    idx = idx % palette.length;
    
    auto c1 = palette[idx];
    auto c2 = palette[(idx + 1) % palette.length];
    
    return Color4f(
        c1.r + (c2.r - c1.r) * cast(float)frac,
        c1.g + (c2.g - c1.g) * cast(float)frac,
        c1.b + (c2.b - c1.b) * cast(float)frac
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

private Color4f colorSeashore(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float wave = cast(float)(0.5 + 0.5 * sin(2 * PI * t));
    float r = cast(float)(0.1 + 0.2 * wave);
    float g = cast(float)(0.4 + 0.4 * wave);
    float b = cast(float)(0.6 + 0.3 * wave);
    
    return Color4f(r, g, b);
}

private Color4f colorFire(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float r = cast(float)(0.5 + 0.5 * sin(2 * PI * (t + 0.0)));
    float g = cast(float)(0.5 + 0.5 * sin(2 * PI * (t + 0.25)));
    float b = cast(float)(0.5 + 0.5 * sin(2 * PI * (t + 0.5)));
    
    return Color4f(r, g, b);
}

private Color4f colorOceanid(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float wave = cast(float)(0.5 + 0.5 * sin(2 * PI * t));
    float r = cast(float)(0.05 + 0.2 * wave);
    float g = cast(float)(0.1 + 0.4 * wave);
    float b = cast(float)(0.3 + 0.5 * wave);
    
    return Color4f(r, g, b);
}

private Color4f colorCnfsso(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float r = cast(float)(0.5 + 0.5 * sin(2 * PI * (t * 3 + 0.0)));
    float g = cast(float)(0.5 + 0.5 * sin(2 * PI * (t * 5 + 0.25)));
    float b = cast(float)(0.5 + 0.5 * sin(2 * PI * (t * 7 + 0.5)));
    
    return Color4f(r, g, b);
}

private Color4f colorAcid(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float wave = cast(float)(0.5 + 0.5 * sin(2 * PI * t));
    float r = cast(float)(0.5 + 0.5 * wave);
    float g = cast(float)(0.8 + 0.2 * sin(2 * PI * t * 4));
    float b = cast(float)(0.1 + 0.2 * wave);
    
    return Color4f(r, g, b);
}

private Color4f colorSofthours(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float r = cast(float)(0.6 + 0.3 * sin(2 * PI * t));
    float g = cast(float)(0.5 + 0.3 * sin(2 * PI * (t + 0.33)));
    float b = cast(float)(0.7 + 0.2 * sin(2 * PI * (t + 0.67)));
    
    return Color4f(r, g, b);
}

