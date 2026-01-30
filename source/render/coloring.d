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

Color4f computeColor(const ref IterResult result, const ref RenderConfig cfg) {
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
        return interpolatePalette(smoothed, externalPalette, cfg.paletteReverse);
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

private Color4f interpolatePalette(double value, const Color4f[] palette, bool reverse) {
    if (palette.length == 0) return Color4f(0, 0, 0);
    if (palette.length == 1) return palette[0];
    
    double t = value;
    if (reverse) t = -t;
    
    t = t - floor(t / palette.length) * palette.length;
    if (t < 0) t += palette.length;
    
    size_t idx = cast(size_t)floor(t);
    double frac = t - idx;
    
    if (idx >= palette.length - 1) {
        idx = palette.length - 2;
        frac = 1.0;
    }
    
    auto c1 = palette[idx];
    auto c2 = palette[idx + 1];
    
    return Color4f(
        c1.r + (c2.r - c1.r) * cast(float)frac,
        c1.g + (c2.g - c1.g) * cast(float)frac,
        c1.b + (c2.b - c1.b) * cast(float)frac
    );
}

// ============================================================================

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
    
    auto vc = 1 - v;
    auto vl = 0.5 + vc * 1.5;
    auto vs = 0.75 + vc * 2;
    
    auto c = hsv(360.0 * v, vs > 1 ? 1 : vs, vl > 1 ? 1 : vl);
    return Color4f(c.r, c.g, c.b);
}

private Color4f colorGray(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    float gray = cast(float)t;
    return Color4f(gray, gray, gray);
}

private Color4f colorBlue(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    return Color4f(0, 0, cast(float)t);
}

private Color4f colorRed(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    return Color4f(cast(float)t, 0, 0);
}

private Color4f colorBase(double value, uint paletteSize, bool reverse) {
    return colorHSV(value, paletteSize, reverse);
}

private Color4f colorSeashore(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float r = cast(float)(0.1 + 0.2 * t);
    float g = cast(float)(0.4 + 0.4 * t);
    float b = cast(float)(0.6 + 0.3 * t);
    
    return Color4f(r, g, b);
}

private Color4f colorFire(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float r = cast(float)(t < 0.33 ? t * 3 : 1.0);
    float g = cast(float)(t < 0.33 ? 0 : (t < 0.67 ? (t - 0.33) * 3 : 1.0));
    float b = cast(float)(t < 0.67 ? 0 : (t - 0.67) * 3);
    
    return Color4f(r, g, b);
}

private Color4f colorOceanid(double value, uint paletteSize, bool reverse) {
    if (reverse) value = -value;
    double t = value / paletteSize;
    t = t - floor(t);
    
    float r = cast(float)(0.05 + 0.2 * t);
    float g = cast(float)(0.1 + 0.4 * t);
    float b = cast(float)(0.3 + 0.5 * t);
    
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
    
    float r = cast(float)(0.5 + 0.5 * t);
    float g = cast(float)(0.8 + 0.2 * sin(t * PI * 4));
    float b = cast(float)(0.1 + 0.2 * t);
    
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

