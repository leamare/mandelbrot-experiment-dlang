module config.params;

import std.conv : to;
import std.format : format;
import std.math : abs, floor;
import std.string : toLower, strip;

import types.fractal;
import types.render;
import precision.method;
import precision.auto_settings;

struct RenderParams {
    int width = 800;
    int height = 800;
    
    string originXStr = "-0.5";
    string originYStr = "0.0";
    string radiusStr = "2.0";
    
    real originX = -0.5;
    real originY = 0.0;
    real radius = 2.0;
    
    int palette = 0;
    float paletteOffset = 0.0;
    bool paletteReverse = false;
    string paletteFile = "";
    uint dwell = 100;
    bool autoDwell = false;
    string filename;
    
    float multibrotExp = 2.0;
    
    FractalType fractalType = FractalType.mandelbrot;
    ColorFunc colorfunc = ColorFunc.ultrafrac;
    BuddhaMode buddha = BuddhaMode.none;
    
    // "standard" or "arbitrary"
    string forcePrecision = "";
    // "auto", "double", "quaddouble", "mpfr"
    string arbitraryPrecisionMethod = "";
    
    // "auto", "enabled", "disabled"
    string perturbations = "auto";
    
    int x_px_offset = 0;
    int y_px_offset = 0;
    
    RenderConfig toRenderConfig() const {
        RenderConfig cfg;
        
        cfg.originX = originX;
        cfg.originY = originY;
        cfg.radius = radius;
        cfg.width = width;
        cfg.height = height;
        cfg.originXStr = originXStr;
        cfg.originYStr = originYStr;
        cfg.radiusStr = radiusStr;
        
        cfg.maxIterations = dwell;
        cfg.escapeRadius = 4.0;
        
        cfg.colorFunc = colorfunc;
        cfg.paletteSize = palette > 0 ? palette : dwell;
        cfg.paletteOffset = paletteOffset;
        cfg.paletteReverse = paletteReverse;
        cfg.paletteFile = paletteFile;
        
        cfg.fractalType = fractalType;
        cfg.multibrotExp = multibrotExp;
        cfg.buddhaMode = buddha;
        
        cfg.precisionMode = determinePrecisionMode();
        
        return cfg;
    }
    
    PrecisionMode determinePrecisionMode() const {
        if (forcePrecision.length > 0) {
            string mode = forcePrecision.toLower().strip();
            if (mode == "standard" || mode == "double") {
                return PrecisionMode.standard;
            } else if (mode == "arbitrary" || mode == "gmp" || mode == "mpfr" || 
                       mode == "quaddouble" || mode == "bigfloat") {
                return PrecisionMode.arbitrary;
            }
        }
        
        if (arbitraryPrecisionMethod.length > 0) {
            auto method = parsePrecisionMethod(arbitraryPrecisionMethod);
            if (method != PrecisionMethod.auto_ && method != PrecisionMethod.double_) {
                return PrecisionMode.arbitrary;
            }
        }
        
        uint digits = combinedPrecisionDigits(originXStr, originYStr, radiusStr, radius);
        
        import precision.constants : PRECISION_THRESHOLD_DOUBLE;
        if (digits > PRECISION_THRESHOLD_DOUBLE) {
            return PrecisionMode.arbitrary;
        }
        
        return PrecisionMode.standard;
    }
    
    PerturbationMode getPerturbationMode() const {
        return parsePerturbationMode(perturbations);
    }
    
    void applyPixelOffset() {
        if (x_px_offset == 0 && y_px_offset == 0) return;
        
        import calc.types.mpfr : GMPFloat, GMPPixelConverter;
        
        uint digits = combinedPrecisionDigits(originXStr, originYStr, radiusStr, radius);
        digits = digits > 50 ? digits : 50;
        
        GMPFloat.setPrecisionDigits(digits);
        
        auto converter = GMPPixelConverter(
            width, height,
            originXStr, originYStr, radiusStr
        );
        
        int newCenterX = width / 2 + x_px_offset;
        int newCenterY = height / 2 + y_px_offset;
        
        import calc.types.mpfr : GMPComplex;
        auto newOrigin = GMPComplex.zero();
        converter.pixelToComplex(newCenterX, newCenterY, newOrigin);
        
        originXStr = newOrigin.re.toString();
        originYStr = newOrigin.im.toString();
        
        originX = newOrigin.re.toDouble();
        originY = newOrigin.im.toDouble();
    }
}

