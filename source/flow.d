module flow;

import std.stdio;
import std.file;
import std.conv;
import std.math;
import std.typecons;
import std.string;
import std.json;
import std.array;
import std.range;
import std.parallelism;
import std.algorithm : min, max, countUntil, map;
import std.format : format;
import std.process : environment;

import cerealed;
import dlib.image;

import mandel;
import gmp_arb;
import perturbation_bla;
import perturbation_bla_hp;
import multidouble : calculateNumDoubles, MultiDouble, MultiDoubleComplex, MULTIDOUBLE_MAX_COMPONENTS;
import doubledouble : DDComplex, DoubleDouble;
import bigfloat : BigFloat, BigFloatComplex;
import precision_unified : estimatePrecisionFromString;

// =============================================================================
// Module-level Configuration
// =============================================================================

enum uint PRECISION_THRESHOLD_DOUBLE = 15;
enum uint PRECISION_THRESHOLD_BIGFLOAT = 50;
enum uint PRECISION_THRESHOLD_MULTIDOUBLE = 600;
enum uint PRECISION_THRESHOLD_GMP = 241;

enum uint MULTIDOUBLE_MIN_DOUBLES = 2;
enum uint MULTIDOUBLE_MAX_DOUBLES = 40;
enum uint MULTIDOUBLE_MAX_DIGITS = MULTIDOUBLE_MAX_DOUBLES * 15;

enum double SCALED_DELTA_THRESHOLD = 1e-18;
enum double SCALED_DELTA_THRESHOLD_SQUARED = SCALED_DELTA_THRESHOLD * SCALED_DELTA_THRESHOLD;
enum double LOG10_OF_TWO = std.math.log10(2.0);
enum double LOG10_THRESHOLD = std.math.log10(SCALED_DELTA_THRESHOLD);
string workdir = "out";
int saveProgress = 0;
bool skipExisting = false;

// =============================================================================
// Render Parameters
// =============================================================================

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
    
    string forcePrecision = "";
    
    string arbitraryPrecisionMethod = "";
    
    int x_px_offset = 0;
    int y_px_offset = 0;
    
    void applyPixelOffset() {
        if (x_px_offset == 0 && y_px_offset == 0) {
            return;
        }
        
        double minDim = min(cast(double)width, cast(double)height);
        double pixelSpacing = (radius * 2.0) / minDim;
        
        double offsetX = -x_px_offset * pixelSpacing;
        double offsetY = y_px_offset * pixelSpacing;
        
        originX += offsetX;
        originY += offsetY;
        
        if (originXStr.length > 0) {
            try {
                real currentX = to!real(originXStr);
                originXStr = format!"%.20g"(currentX + offsetX);
            } catch (Exception) {
                originXStr = format!"%.20g"(originX);
            }
        } else {
            originXStr = format!"%.20g"(originX);
        }
        
        if (originYStr.length > 0) {
            try {
                real currentY = to!real(originYStr);
                originYStr = format!"%.20g"(currentY + offsetY);
            } catch (Exception) {
                originYStr = format!"%.20g"(originY);
            }
        } else {
            originYStr = format!"%.20g"(originY);
        }
    }
    
    PrecisionMode precisionMode() const {
        if (forcePrecision.length > 0) {
            string mode = forcePrecision.toLower().strip();
            if (mode == "arbitrary" || mode == "gmp" || mode == "high") {
                return PrecisionMode.arbitrary;
            } else if (mode == "standard" || mode == "double" || mode == "low") {
                return PrecisionMode.standard;
            }
        }
        
        if (radiusStr.length > 0) {
            auto ePos = radiusStr.countUntil!(c => c == 'e' || c == 'E')();
            if (ePos >= 0) {
                try {
                    int exp = to!int(radiusStr[ePos + 1 .. $]);
                    if (exp < -12) return PrecisionMode.arbitrary;
                } catch (Exception) {}
            }
        }
        return RenderConfig.detectPrecisionMode(radius);
    }
    
    uint requiredPrecision() const {
        return RenderConfig.calculateOptimalPrecision(radius, width, height);
    }
    
    RenderConfig toRenderConfig() const {
        RenderConfig cfg;
        cfg.originX = originX;
        cfg.originY = originY;
        cfg.radius = radius;
        cfg.originXStr = originXStr;
        cfg.originYStr = originYStr;
        cfg.radiusStr = radiusStr;
        cfg.width = width;
        cfg.height = height;
        cfg.maxIterations = dwell;
        cfg.fractalType = fractalType;
        cfg.multibrotExp = multibrotExp;
        cfg.colorFunc = colorfunc;
        cfg.paletteSize = palette > 0 ? palette : dwell;
        cfg.paletteOffset = paletteOffset;
        cfg.paletteFile = paletteFile;
        cfg.paletteReverse = paletteReverse;
        cfg.buddhaMode = buddha;
        cfg.precisionMode = precisionMode();
        cfg.arbitraryPrecision = requiredPrecision();
        return cfg;
    }
}

// =============================================================================
// Buddhabrot Data Collection (Thread-Safe)
// =============================================================================

struct BuddhaAccumulator {
    private int[][] globalData;
    private int width, height;
    
    this(int w, int h) {
        width = w;
        height = h;
        globalData = new int[][](w, h);
        foreach (ref row; globalData) {
            row[] = 0;
        }
    }
    
    int[][] createLocalBuffer() {
        auto local = new int[][](width, height);
        foreach (ref row; local) {
            row[] = 0;
        }
        return local;
    }
    
    void mergeLocal(int[][] local) {
        foreach (x; 0 .. width) {
            foreach (y; 0 .. height) {
                globalData[x][y] += local[x][y];
            }
        }
    }
    
    static void recordHit(ref int[][] buffer, int x, int y, int width, int height) {
        if (x >= 0 && x < width && y >= 0 && y < height) {
            buffer[x][y]++;
        }
    }
    
    int maxHits() {
        int maxVal = 0;
        foreach (row; globalData) {
            foreach (val; row) {
                if (val > maxVal) maxVal = val;
            }
        }
        return maxVal;
    }
    
    ref int[][] data() { return globalData; }
}

// =============================================================================
// Auto-Dwell Calculation
// =============================================================================

int getZoomExponent(string radiusStr) {
    auto ePos = radiusStr.countUntil!(c => c == 'e' || c == 'E')();
    if (ePos >= 0) {
        return to!int(radiusStr[ePos + 1 .. $]);
    }
    // Try parsing as double
    try {
        double r = to!double(radiusStr);
        if (r > 0) return cast(int)floor(log10(r));
    } catch (Exception) {}
    return 0;
}

uint estimateDwell(string radiusStr) {
    int exp = getZoomExponent(radiusStr);
    int zoomDepth = -exp;
    
    if (zoomDepth <= 0) return 100;
    
    if (zoomDepth <= 15) {
        return cast(uint)(100 + zoomDepth * zoomDepth * 10);
    } else if (zoomDepth <= 50) {
        return cast(uint)(1000 + pow(cast(double)zoomDepth, 1.5) * 50);
    } else if (zoomDepth <= 200) {
        return cast(uint)(5000 + pow(cast(double)zoomDepth, 1.3) * 100);
    } else {
        return cast(uint)(20000 + pow(cast(double)zoomDepth, 1.2) * 50);
    }
}

double digitsPerPixel(const RenderParams desc) {
    import std.math : log10, isFinite;
    int maxDim = max(desc.width, desc.height);
    if (maxDim <= 0) {
        return 0.0;
    }
    real radiusReal = desc.radius;
    real spacingReal = (radiusReal * 2.0L) / cast(real)maxDim;
    double pixelSpacing = cast(double)spacingReal;
    if (pixelSpacing > 0 && isFinite(pixelSpacing)) {
        return -log10(pixelSpacing);
    }
    int exp = getZoomExponent(desc.radiusStr);
    if (exp == 0) {
        return 0.0;
    }
    double logMaxDim = log10(cast(double)maxDim);
    double logPixelSpacing = log10(2.0) + exp - logMaxDim;
    return -logPixelSpacing * 1.25;
}

uint viewportPrecisionDigits(const RenderParams desc) {
    import std.math : isFinite;
    real radiusReal = desc.radius;
    if ((!isFinite(radiusReal) || radiusReal <= 0) && desc.radiusStr.length > 0) {
        try {
            radiusReal = to!real(desc.radiusStr);
        } catch (Exception) {
            radiusReal = 0;
        }
    }
    if (radiusReal > 0 && isFinite(radiusReal)) {
        return RenderConfig.calculateOptimalPrecision(radiusReal, desc.width, desc.height);
    }
    auto coordLen = max(desc.originXStr.length, desc.originYStr.length);
    return cast(uint)max(50, coordLen + 20);
}

uint coordinatePrecisionDigits(const RenderParams desc) {
    return estimatePrecisionFromString(desc.originXStr, desc.originYStr);
}

enum uint COORDINATE_SAFETY_MARGIN = 30;

private uint clampCoordinateDigits(uint viewportDigits, uint coordDigitsRaw) {
    return coordDigitsRaw > viewportDigits + COORDINATE_SAFETY_MARGIN
        ? viewportDigits + COORDINATE_SAFETY_MARGIN
        : coordDigitsRaw;
}

enum uint COORDINATE_TRIM_EXTRA_DIGITS = 8;

private string trimCoordinatePrecision(string value, uint maxFractionDigits) {
    if (maxFractionDigits == uint.max) {
        return value;
    }
    auto str = value.strip();
    if (str.length == 0) {
        return str;
    }
    auto ePos = str.countUntil!(c => c == 'e' || c == 'E')();
    string exponentPart = ePos >= 0 ? str[ePos .. $] : "";
    string mantissa = ePos >= 0 ? str[0 .. ePos] : str;
    auto dotPos = mantissa.countUntil('.');
    if (dotPos < 0) {
        return str;
    }

    size_t start = dotPos + 1;
    size_t available = mantissa.length > start ? mantissa.length - start : 0;
    size_t keepDigits = cast(size_t)maxFractionDigits + COORDINATE_TRIM_EXTRA_DIGITS;
    if (available <= keepDigits) {
        return str;
    }

    size_t end = min(mantissa.length, start + keepDigits);
    string trimmed;
    if (keepDigits == 0) {
        trimmed = mantissa[0 .. dotPos];
    } else {
        trimmed = mantissa[0 .. end];
    }
    if (trimmed.length > 0 && trimmed[$ - 1] == '.') {
        trimmed = trimmed[0 .. $ - 1];
    }
    return trimmed ~ exponentPart;
}

private string bigFloatToString(const BigFloat bf, uint maxDigits) {
    import std.format : format;
    import std.bigint : BigInt;
    if (bf.mantissa == 0) return "0";
    
    BigInt absMant = bf.mantissa < 0 ? -bf.mantissa : bf.mantissa;
    string mantStr = absMant.to!string();
    
    long totalExp = bf.exponent + cast(long)(mantStr.length - 1);
    string result;
    if (mantStr.length == 1) {
        result = mantStr;
    } else {
        result = mantStr[0] ~ "." ~ mantStr[1..$];
        if (result.length > maxDigits + 2) {
            result = result[0..maxDigits+2];
        }
    }
    result ~= "e" ~ to!string(totalExp);
    if (bf.mantissa < 0) {
        result = "-" ~ result;
    }
    return result;
}

double computeLog10FromDecimal(string value, double fallbackValue) {
    import std.math : isFinite, log10;
    string trimmed = value.strip();
    double fallbackLog = fallbackValue > 0 && isFinite(fallbackValue)
        ? log10(fallbackValue)
        : 0.0;
    if (trimmed.length == 0) {
        return fallbackLog;
    }
    try {
        auto bigValue = BigFloat(trimmed);
        if (bigValue.mantissa == 0) {
            return -double.infinity;
        }
        auto mantissa = bigValue.mantissa;
        if (mantissa < 0) {
            mantissa = -mantissa;
        }
        string digits = to!string(mantissa);
        if (digits.length == 0) {
            return fallbackLog;
        }
        string normalized;
        if (digits.length == 1) {
            normalized = digits;
        } else {
            size_t keep = min(size_t(16), digits.length - 1);
            normalized = digits[0] ~ "." ~ digits[1 .. 1 + keep];
        }
        double normalizedValue = to!double(normalized);
        double log10Mantissa = log10(normalizedValue) + cast(double)(digits.length - 1);
        return log10Mantissa + cast(double)bigValue.exponent;
    } catch (Exception) {
        try {
            real parsed = to!real(trimmed);
            if (parsed > 0) {
                return log10(cast(double)parsed);
            } else if (parsed < 0) {
                return log10(-cast(double)parsed);
            }
            return -double.infinity;
        } catch (Exception) {
            return fallbackLog;
        }
    }
}

uint combinedPrecisionDigits(const RenderParams desc) {
    auto viewportDigits = viewportPrecisionDigits(desc);
    auto coordDigitsRaw = coordinatePrecisionDigits(desc);
    auto coordDigits = clampCoordinateDigits(viewportDigits, coordDigitsRaw);
    return max(viewportDigits, coordDigits);
}

int estimatePalette(uint dwell) {
    if (dwell <= 1000) {
        return max(50, cast(int)(dwell * 0.5));
    } else if (dwell <= 10000) {
        return max(100, cast(int)(sqrt(cast(double)dwell) * 10));
    } else if (dwell <= 100000) {
        return max(200, min(cast(int)(sqrt(cast(double)dwell) * 5), 2000));
    } else {
        return max(500, min(cast(int)(sqrt(cast(double)dwell)), 3000));
    }
}

uint extraMultiDoubleComponents(const RenderParams desc) {
    import std.math : ceil;
    double digitsForPixels = digitsPerPixel(desc);

    enum double PIXEL_GUARD_START = 18.0;
    enum double PIXEL_SLOPE = 0.65;
    double excess = digitsForPixels > PIXEL_GUARD_START
        ? digitsForPixels - PIXEL_GUARD_START
        : 0.0;
    uint extraFromPixels = excess > 0
        ? cast(uint)ceil(excess * PIXEL_SLOPE)
        : 0;

    int zoomExp = getZoomExponent(desc.radiusStr);
    int zoomDepth = zoomExp < 0 ? -zoomExp : 0;
    enum int ZOOM_THRESHOLD = 35;
    uint extraFromZoom = zoomDepth > ZOOM_THRESHOLD
        ? cast(uint)min(12, (zoomDepth - ZOOM_THRESHOLD + 2) / 2)
        : 0;

    return extraFromPixels + extraFromZoom;
}

uint selectMultiDoubleComponents(uint digits, const RenderParams desc) {
    uint base = calculateNumDoubles(digits);
    uint extra = extraMultiDoubleComponents(desc);
    return min(base + extra, MULTIDOUBLE_MAX_COMPONENTS);
}

uint selectDeltaMultiDoubleComponents(double perPixelDigits, uint referenceComponents) {
    import std.math : ceil;
    import multidouble : MULTIDOUBLE_DIGITS_PER_COMPONENT;
    uint needed = cast(uint)ceil(perPixelDigits / cast(double)MULTIDOUBLE_DIGITS_PER_COMPONENT);
    if (needed < MULTIDOUBLE_MIN_DOUBLES) {
        needed = MULTIDOUBLE_MIN_DOUBLES;
    }
    if (referenceComponents > 0) {
        needed = min(needed, referenceComponents);
    }
    return needed;
}

// =============================================================================
// Main Render Flow
// =============================================================================

void brotFlow(RenderParams desc) {
    if (skipExisting && exists(workdir ~ "/" ~ desc.filename ~ ".png")) {
        writeln("File `" ~ desc.filename ~ "` exists, skipping...\n");
        return;
    }
    
    if (desc.autoDwell) {
        desc.dwell = estimateDwell(desc.radiusStr);
        if (desc.palette == 0) {
            desc.palette = estimatePalette(desc.dwell);
        }
        writeln("Auto-dwell: estimated ", desc.dwell, " iterations for this zoom depth");
    }
    
    if (desc.x_px_offset != 0 || desc.y_px_offset != 0) {
        desc.applyPixelOffset();
        writeln("Applied pixel offset: x=", desc.x_px_offset, ", y=", desc.y_px_offset);
        if (desc.filename.length == 0 || desc.filename == desc.generateFileName()) {
            desc.filename = desc.generateFileName();
        }
    }
    
    auto cfg = desc.toRenderConfig();
    
    const int wfactor = desc.width > 100 ? to!int(floor(to!double(desc.width) / 100.0)) : 1;
    
    writeln("Iterations: ", desc.dwell, desc.autoDwell ? " (auto)" : "");
    writeln("Image size: ", desc.width, " x ", desc.height);
    writeln("Origin: ", desc.originXStr.length > 40 ? desc.originXStr[0..40] ~ "..." : format!"%.17g"(desc.originX),
            (desc.originY < 0 ? " - " : " + "), 
            desc.originYStr.length > 40 ? desc.originYStr[0..40] ~ "..." : format!"%.17g"(abs(desc.originY)), "i");
    writeln("Viewpoint radius: ", desc.radiusStr);
    writeln("Palette size: ", cfg.paletteSize, " + ", desc.paletteOffset);
    writeln("Buddha: ", to!string(desc.buddha));
    string precisionMsg = cfg.precisionMode == PrecisionMode.arbitrary ? 
            "GMP Arbitrary Precision" : "Standard";
    if (desc.forcePrecision.length > 0) {
        precisionMsg ~= " (forced: " ~ desc.forcePrecision ~ ")";
    }
    writeln("Precision: ", precisionMsg);
    writeln("Filename: ", desc.filename);

    IterResult[][] iters = new IterResult[][](desc.width, desc.height);

	writeln("\nIterating");

    if (desc.buddha != BuddhaMode.none) {
        iterateBuddhabrot(iters, cfg, desc, wfactor);
    } else if (saveProgress > 0 && saveProgress < 50) {
        iterateWithProgress(iters, cfg, desc, wfactor);
    } else {
        iterateSimple(iters, cfg, desc, wfactor);
    }
    
    SuperImage img = image(desc.width, desc.height);
    
    writeln("\nGenerating image");
    auto wRange = iota(0, desc.width);
    foreach (i; parallel(wRange)) {
        for (int j = 0; j < desc.height; j++) {
            img[i, j] = computeColor(iters[i][j], cfg);
        }
        if (i % wfactor == 0) {
            write('.');
            stdout.flush();
        }
    }
    
    writeln("\nSaving: " ~ workdir ~ "/" ~ desc.filename ~ ".png");
    savePNG(img, workdir ~ "/" ~ desc.filename ~ ".png");
    
    writeln("--------------------\n");
}

private void iterateSimple(ref IterResult[][] iters, const ref RenderConfig cfg, 
                          const ref RenderParams desc, int wfactor) {
    
    if (cfg.precisionMode == PrecisionMode.arbitrary) {
        iterateGMPMode(iters, cfg, desc, wfactor);
    } else {
        auto wRange = iota(0, desc.width);
        foreach (i; parallel(wRange)) {
            for (int j = 0; j < desc.height; j++) {
                iters[i][j] = iterate(i, j, cfg);
            }
            if (i % wfactor == 0) {
                write('.');
                stdout.flush();
            }
        }
    }
}

private void iterateGMPMode(ref IterResult[][] iters, const ref RenderConfig cfg,
                            const ref RenderParams desc, int wfactor) {
    import precision_unified : PrecisionMethod, parsePrecisionMethod, selectPrecisionMethod;
    import gmp_arb : GMPFloat;
    import std.complex;
    import core.atomic;

    if (cfg.fractalType != FractalType.mandelbrot) {
        writeln("Perturbation+BLA currently supports only the Mandelbrot set; falling back to direct iteration.");
        iterateGMPDirectMode(iters, cfg, desc, wfactor);
        return;
    }
    
    PrecisionMethod precisionMethod = PrecisionMethod.auto_;
    if (desc.arbitraryPrecisionMethod.length > 0) {
        precisionMethod = parsePrecisionMethod(desc.arbitraryPrecisionMethod);
        writeln("Using forced precision method: ", desc.arbitraryPrecisionMethod);
    } else if (desc.forcePrecision.length > 0) {
        string mode = desc.forcePrecision.toLower().strip();
        if (mode == "dd" || mode == "doubledouble") {
            precisionMethod = PrecisionMethod.bigfloat;
        } else if (mode == "bigint" || mode == "bigfloat") {
            precisionMethod = PrecisionMethod.bigint;
        } else if (mode == "gmp" || mode == "arbitrary") {
            precisionMethod = PrecisionMethod.gmp;
        } else if (mode == "double" || mode == "standard") {
            precisionMethod = PrecisionMethod.double_;
        } else {
            precisionMethod = parsePrecisionMethod(mode);
        }
    }
    
    uint viewportDigits = viewportPrecisionDigits(desc);
    uint coordDigitsRaw = coordinatePrecisionDigits(desc);
    uint coordDigits = clampCoordinateDigits(viewportDigits, coordDigitsRaw);
    uint combinedDigits = max(viewportDigits, coordDigits);
    string originXHP = desc.originXStr.length > 0
        ? desc.originXStr
        : format!"%.20g"(desc.originX);
    string originYHP = desc.originYStr.length > 0
        ? desc.originYStr
        : format!"%.20g"(desc.originY);
    string radiusHP = desc.radiusStr.length > 0
        ? desc.radiusStr
        : format!"%.20g"(desc.radius);
    uint coordDigitsTrim = coordDigitsRaw > 0 ? uint.max : coordDigits;
    uint radiusDigitsTrim = uint.max;
    originXHP = trimCoordinatePrecision(originXHP, coordDigitsTrim);
    originYHP = trimCoordinatePrecision(originYHP, coordDigitsTrim);
    radiusHP = trimCoordinatePrecision(radiusHP, radiusDigitsTrim);
    double radiusLog10 = computeLog10FromDecimal(radiusHP, desc.radius > 0 ? desc.radius : 1.0);
    bool forceScaledDelta = (radiusLog10 + LOG10_OF_TWO) <= LOG10_THRESHOLD;
    RenderParams descHP = desc;
    descHP.originXStr = originXHP;
    descHP.originYStr = originYHP;
    descHP.radiusStr = radiusHP;
    
    if (precisionMethod == PrecisionMethod.auto_) {
        uint digits = combinedDigits;
        
        PrecisionMethod arbitraryMethod = PrecisionMethod.bigint;
        bool arbitraryMethodWasBigInt = true;
        if (desc.arbitraryPrecisionMethod.length > 0) {
            auto arbMethod = parsePrecisionMethod(desc.arbitraryPrecisionMethod);
            if (arbMethod == PrecisionMethod.bigint || arbMethod == PrecisionMethod.gmp) {
                arbitraryMethod = arbMethod;
                arbitraryMethodWasBigInt = (arbMethod == PrecisionMethod.bigint);
            }
        }
        
        precisionMethod = selectPrecisionMethod(digits, arbitraryMethod);
        
        string methodName = 
            precisionMethod == PrecisionMethod.double_ ? "double" :
            precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" :
            precisionMethod == PrecisionMethod.multidouble ? "multidouble" :
            precisionMethod == PrecisionMethod.gmp ? "gmp" :
            precisionMethod == PrecisionMethod.bigint ? "bigfloat (BigInt)" :
            "auto";
        
        if (precisionMethod == PrecisionMethod.multidouble) {
            uint numDoubles = selectMultiDoubleComponents(digits, desc);
            writeln("Auto-selected precision method: ", methodName,
                    " (", numDoubles, " doubles, based on ", digits,
                    " required digits; viewport=", viewportDigits,
                    ", coords=", coordDigits, " (raw ", coordDigitsRaw, "))");
        } else {
            writeln("Auto-selected precision method: ", methodName,
                    " (based on ", digits, " required digits; viewport=",
                    viewportDigits, ", coords=", coordDigits, " (raw ",
                    coordDigitsRaw, "))");
        }
        if (digits > 100 && precisionMethod == PrecisionMethod.gmp) {
            string arbName = arbitraryMethodWasBigInt ? "BigFloat" : "GMP";
            writeln("  Using ", arbName, " for very high precision");
        }
    }
    
    double perPixelDigitsEstimate = 0;
    double multiDoubleCapacityDigits = 0;
    bool havePerPixelEstimate = false;
    uint numDoublesForMD = 0;

    if (precisionMethod == PrecisionMethod.gmp) {
        uint digits = combinedDigits;
        GMPFloat.setPrecisionDigits(digits);
        writeln("Using Perturbation+BLA for deep zoom (GMP)");
        writeln("Reference orbit precision: ", digits, " digits");
    } else if (precisionMethod == PrecisionMethod.multidouble) {
        uint digits = combinedDigits;
        uint numDoubles = selectMultiDoubleComponents(digits, desc);
        numDoublesForMD = numDoubles;
        double perPixelDigits = digitsPerPixel(desc);
        uint numDoublesDelta = selectDeltaMultiDoubleComponents(perPixelDigits, numDoubles);
        writeln("Using Perturbation+BLA with multidouble precision (reference ",
                numDoubles, " doubles, per-pixel ", numDoublesDelta, " doubles)");
        writeln("Reference orbit precision: ", digits, " digits");
        import multidouble : MULTIDOUBLE_DIGITS_PER_COMPONENT;
        auto mdCapacity = numDoubles * cast(double)MULTIDOUBLE_DIGITS_PER_COMPONENT;
        perPixelDigitsEstimate = perPixelDigits;
        multiDoubleCapacityDigits = mdCapacity;
        havePerPixelEstimate = true;
        writeln("Per-pixel delta requires ~", format!"%.1f"(perPixelDigits),
                " digits; MultiDouble capacity ≈ ", format!"%.0f"(mdCapacity), " digits");
        if (perPixelDigits > mdCapacity * 0.85) {
            writeln("  Warning: pixel spacing is close to the MultiDouble limit; expect targeted fallbacks if artifacts appear.");
        }
    } else if (precisionMethod == PrecisionMethod.bigint) {
        writeln("Using Perturbation+BLA with BigFloat precision (BigInt-based)");
    } else {
        writeln("Using Perturbation+BLA with ", 
                precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" : "double", " precision");
    }
    
    int centerPx = desc.width / 2;
    int centerPy = desc.height / 2;
    
    string centerXHP = originXHP;
    string centerYHP = originYHP;
    
    import gmp_arb : GMPPixelConverter;
    auto centerConverter = GMPPixelConverter(
        desc.width, desc.height,
        originXHP, originYHP, radiusHP
    );
    auto centerC = centerConverter.getCenter();
    string centerXHPVerify = centerC.re.toString();
    string centerYHPVerify = centerC.im.toString();
    
    centerXHP = centerXHPVerify;
    centerYHP = centerYHPVerify;
    
    writeln("Computing reference orbit at exact center pixel (", centerPx, ", ", centerPy, "):");
    writeln("  X: ", centerXHP.length > 80 ? centerXHP[0..80] ~ "..." : centerXHP);
    writeln("  Y: ", centerYHP.length > 80 ? centerYHP[0..80] ~ "..." : centerYHP);
    writeln("  Iterations: ", desc.dwell);
    stdout.flush();
    
    debug(gmpdebug) {
        writeln("DEBUG: About to call computeReferenceOrbit with:");
        writeln("DEBUG:   centerXHP length: ", centerXHP.length);
        writeln("DEBUG:   centerYHP length: ", centerYHP.length);
        writeln("DEBUG:   precisionMethod: ", 
                precisionMethod == PrecisionMethod.double_ ? "double" :
                precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" :
                precisionMethod == PrecisionMethod.multidouble ? "multidouble" :
                precisionMethod == PrecisionMethod.bigint ? "bigint" :
                precisionMethod == PrecisionMethod.gmp ? "gmp" : "auto");
        stdout.flush();
    }
    
    debug(gmpdebug) {
        writeln("DEBUG: Calling computeReferenceOrbit...");
        stdout.flush();
    }
    auto refOrbit = computeReferenceOrbit(
        centerXHP, centerYHP, desc.dwell, precisionMethod
    );
    debug(gmpdebug) {
        writeln("DEBUG: computeReferenceOrbit returned successfully");
        stdout.flush();
    }
    ReferenceOrbit bigFloatFallbackOrbit = ReferenceOrbit.init;
    bool haveBigFloatFallback = false;
    
    writeln("Reference orbit computed with precision method: ", 
            precisionMethod == PrecisionMethod.double_ ? "double" :
            precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" :
            precisionMethod == PrecisionMethod.multidouble ? "multidouble" :
            precisionMethod == PrecisionMethod.bigint ? "bigfloat (BigInt)" :
            precisionMethod == PrecisionMethod.gmp ? "gmp" : "auto");

    if (precisionMethod == PrecisionMethod.multidouble &&
        havePerPixelEstimate &&
        multiDoubleCapacityDigits > 0 &&
        perPixelDigitsEstimate > multiDoubleCapacityDigits * 0.9) {
        writeln("Per-pixel deltas exceed MultiDouble resolution (",
                format!"%.1f"(perPixelDigitsEstimate), " vs ",
                format!"%.1f"(multiDoubleCapacityDigits), " digits). Preparing BigFloat fallback orbit...");
        bigFloatFallbackOrbit = computeReferenceOrbit(
            centerXHP, centerYHP, desc.dwell, PrecisionMethod.bigint
        );
        haveBigFloatFallback = bigFloatFallbackOrbit.zRefBigFloat.length > 0;
        if (!haveBigFloatFallback) {
            writeln("Warning: BigFloat fallback orbit failed to produce data; continuing with MultiDouble only.");
        }
    }
    
    if (refOrbit.zRef.length < 2) {
        writeln("ERROR: Reference orbit too short, falling back to direct GMP");
        iterateGMPDirectMode(iters, cfg, descHP, wfactor);
        return;
    }

    IterResult referencePixelIter;
    {
        int referenceIterations = min(refOrbit.refIterations, cast(int)desc.dwell);
        double referenceSmoothed = cast(double)referenceIterations;
        if (refOrbit.escaped &&
            referenceIterations >= 0 &&
            referenceIterations < refOrbit.zRef.length) {
            auto zAtEscape = refOrbit.zRef[referenceIterations];
            double zMag2 = zAtEscape.re * zAtEscape.re + zAtEscape.im * zAtEscape.im;
            if (zMag2 > 0 && std.math.isFinite(zMag2)) {
                double logZn = std.math.log(zMag2) * 0.5;
                double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                referenceSmoothed = 1 + cast(double)referenceIterations - nu;
            }
        } else if (!refOrbit.escaped) {
            referenceIterations = cast(int)desc.dwell;
            referenceSmoothed = cast(double)desc.dwell;
        }
        referencePixelIter = IterResult(referenceIterations, referenceSmoothed);
    }
    
    if (numDoublesForMD == 0) {
        numDoublesForMD = refOrbit.multiDoubleComponents;
    }
    auto refOrbitForBLA = haveBigFloatFallback ? &bigFloatFallbackOrbit : &refOrbit;
    BLATable blaTable = buildBLATable(*refOrbitForBLA);
    
    writeln("Starting perturbation iteration with BLA...");
    
    import gmp_arb : GMPFloat, GMPPixelConverter, GMPComplex;
    
    GMPComplex cRefGMP = GMPComplex.zero();
    GMPPixelConverter pixelConverterGMP = GMPPixelConverter.init;
    
    switch (precisionMethod) {
        default: {
            pixelConverterGMP = GMPPixelConverter(
                desc.width, desc.height,
                originXHP, originYHP, radiusHP
            );
            cRefGMP = GMPComplex(centerXHP, centerYHP);
            break;
        }
    }
    
    double minDim = min(cast(double)desc.width, cast(double)desc.height);
    
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: About to create radiusGMP from: ", radiusHP);
        stderr.flush();
    }
    GMPFloat radiusGMP = GMPFloat(radiusHP);
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: radiusGMP created successfully");
        stderr.flush();
    }
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: About to create twoGMP...");
        stderr.flush();
    }
    GMPFloat twoGMP = GMPFloat(2.0);
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: twoGMP created successfully");
        stderr.flush();
    }
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: About to create minDimGMP...");
        stderr.flush();
    }
    GMPFloat minDimGMP = GMPFloat(minDim);
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: minDimGMP created successfully");
        stderr.flush();
    }
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: About to compute pixelSizeGMP...");
        stderr.flush();
    }
    GMPFloat pixelSizeGMP = (radiusGMP * twoGMP) / minDimGMP;
    debug(gmpdebug) {
        import std.stdio;
        stderr.writeln("DEBUG: pixelSizeGMP computed successfully");
        stderr.flush();
    }
    
    import doubledouble : DoubleDouble, DDComplex;
    DoubleDouble pixelSizeDD = DoubleDouble(pixelSizeGMP.toString());

    MultiDouble pixelSizeMD;
    MultiDoubleComplex centerCoordMD;
    bool useMultiDoubleForDeltas = false;
    if (precisionMethod == PrecisionMethod.multidouble && numDoublesForMD > 0) {
        int zoomExp = getZoomExponent(radiusHP);
        int zoomDepth = zoomExp < 0 ? -zoomExp : 0;
        if (zoomDepth <= 45) {
            useMultiDoubleForDeltas = true;
            auto pixelSizeStr = pixelSizeGMP.toString();
            pixelSizeMD = MultiDouble(numDoublesForMD, pixelSizeStr);
            centerCoordMD = MultiDoubleComplex(numDoublesForMD, originXHP, originYHP);
        }
    }
    
    shared int processedPixels = 0;
    int totalPixels = desc.width * desc.height;
    int progressInterval = max(1, totalPixels / 40);
    shared int lastPercent = -1;
    
    bool allowSecondPass = (precisionMethod == PrecisionMethod.multidouble ||
                            precisionMethod == PrecisionMethod.bigint ||
                            precisionMethod == PrecisionMethod.gmp);
    bool[][] uncertainMask;
    if (allowSecondPass) {
        uncertainMask.length = desc.width;
        foreach (i; 0 .. desc.width) {
            uncertainMask[i] = new bool[](desc.height);
        }
    }

    write("Progress: ");
    stdout.flush();
    
    const Complex!double[] zRefArray = refOrbitForBLA.zRef.dup;
    const DDComplex[] zRefArrayDD = refOrbit.zRefDoubleDouble.dup;
    const MultiDoubleComplex[] zRefArrayMD = refOrbit.zRefMultiDouble.dup;
    // const GMPComplex[] zRefArrayGMP = refOrbit.zRefGMP.dup;
    GMPComplex[] zRefArrayGMP;
    if (refOrbit.zRefGMP.length > 0) {
        import std.array : array;
        zRefArrayGMP = refOrbit.zRefGMP.map!(z => GMPComplex(z)).array;
    }

    const BigFloatComplex[] zRefArrayBF =
        precisionMethod == PrecisionMethod.bigint ? refOrbit.zRefBigFloat.dup :
        haveBigFloatFallback ? bigFloatFallbackOrbit.zRefBigFloat.dup :
        null;
    const BLAEntry[] blaEntriesArray = blaTable.entries.dup;
    const double escapeRadius2 = refOrbit.escapeRadius2;

    auto wRange = iota(0, desc.width);
    foreach (i; parallel(wRange)) {
        for (int j = 0; j < desc.height; j++) {
            int dx = i - centerPx;
            int dy = centerPy - j;
            bool isCenterPixel = (dx == 0 && dy == 0);
            
            DDComplex delta0DD;
            Complex!double delta0;
            GMPComplex delta0GMP = GMPComplex.zero();
            MultiDoubleComplex delta0MD;
            BigFloatComplex delta0BF;
            
            if (!isCenterPixel) {
                DoubleDouble dxDD = DoubleDouble(cast(double)dx);
                DoubleDouble dyDD = DoubleDouble(cast(double)dy);
                
                DoubleDouble deltaReDD = dxDD * pixelSizeDD;
                DoubleDouble deltaImDD = dyDD * pixelSizeDD;
                delta0DD = DDComplex(deltaReDD, deltaImDD);
                
                delta0 = Complex!double(deltaReDD.toDouble(), deltaImDD.toDouble());
                
                if (precisionMethod == PrecisionMethod.gmp) {
                    auto pixelC = pixelConverterGMP.pixelToComplex(i, j);
                    delta0GMP = pixelC - cRefGMP;
                }
                
                if (useMultiDoubleForDeltas) {
                    DoubleDouble dxMD = DoubleDouble(cast(double)dx);
                    DoubleDouble dyMD = DoubleDouble(cast(double)dy);
                    auto deltaReMD = MultiDouble(numDoublesForMD, dxMD.toDouble()) * pixelSizeMD;
                    auto deltaImMD = MultiDouble(numDoublesForMD, dyMD.toDouble()) * pixelSizeMD;
                    delta0MD = MultiDoubleComplex(deltaReMD, deltaImMD);
                }
                
                if (precisionMethod == PrecisionMethod.bigint) {
                    import bigfloat : BigFloat, BigFloatComplex;
                    BigFloat dxBF = BigFloat(cast(double)dx);
                    BigFloat dyBF = BigFloat(cast(double)dy);
                    BigFloat pixelSizeBF = BigFloat(pixelSizeGMP.toString());
                    auto deltaReBF = dxBF * pixelSizeBF;
                    auto deltaImBF = dyBF * pixelSizeBF;
                    delta0BF = BigFloatComplex(deltaReBF, deltaImBF);
                }
            }

            bool usedBigFloatFallback = false;
            PerturbResult fallbackPerturb;
            
            if (!isCenterPixel) {
                auto runDoublePerturb = () {
                    import perturbation_bla_hp : perturbIterateBLADDComplex;
                    return perturbIterateBLADDComplex(
                        zRefArrayDD.length > 0 ? zRefArrayDD : 
                            zRefArray.map!(z => DDComplex(DoubleDouble(z.re), DoubleDouble(z.im))).array,
                        escapeRadius2, blaEntriesArray, delta0DD, desc.dwell
                    );
                };

                bool handled = false;
                PerturbResult perturbResult;

                switch (precisionMethod) {
                    case PrecisionMethod.multidouble: {
                        if (useMultiDoubleForDeltas && zRefArrayMD.length > 0 && numDoublesForMD > 0) {
                            import perturbation_bla_hp : perturbIterateBLAMultiDouble;
                            perturbResult = perturbIterateBLAMultiDouble(
                                zRefArrayMD, escapeRadius2, blaEntriesArray,
                                delta0MD, desc.dwell, numDoublesForMD
                            );
                        } else {
                            perturbResult = runDoublePerturb();
                        }
                        handled = true;
                        break;
                    }
                    case PrecisionMethod.bigfloat: {
                        perturbResult = runDoublePerturb();
                        handled = true;
                        break;
                    }
                    case PrecisionMethod.gmp: {
                        if (zRefArrayGMP.length > 0) {
                            auto zRefDD = zRefArrayGMP.map!(z => 
                                DDComplex(DoubleDouble(z.re.toString()), DoubleDouble(z.im.toString()))
                            ).array;
                            import perturbation_bla_hp : perturbIterateBLADDComplex;
                            perturbResult = perturbIterateBLADDComplex(
                                zRefDD, escapeRadius2, blaEntriesArray, delta0DD, desc.dwell
                            );
                        } else {
                            perturbResult = runDoublePerturb();
                        }
                        handled = true;
                        break;
                    }
                    case PrecisionMethod.bigint: {
                        if (zRefArrayBF.length > 0) {
                            auto zRefDD = zRefArrayBF.map!(z => 
                                DDComplex(DoubleDouble(bigFloatToString(z.re, 50)), DoubleDouble(bigFloatToString(z.im, 50)))
                            ).array;
                            import perturbation_bla_hp : perturbIterateBLADDComplex;
                            perturbResult = perturbIterateBLADDComplex(
                                zRefDD, escapeRadius2, blaEntriesArray, delta0DD, desc.dwell
                            );
                        } else {
                            perturbResult = runDoublePerturb();
                        }
                        handled = true;
                        break;
                    }
                    default: {
                        perturbResult = runDoublePerturb();
                        handled = true;
                        break;
                    }
                }

                if (handled) {
                    debug(gmpdebug) {
                        import std.stdio;
                        static int debugPixelCount = 0;
                        if (debugPixelCount < 20 && i < 10 && j < 10) {
                            stderr.writeln("[PIXEL DEBUG] Pixel [", i, ",", j, "]: iterations=", 
                                          perturbResult.iterations, " smoothed=", perturbResult.smoothed,
                                          " maxIter=", desc.dwell);
                            stderr.flush();
                            debugPixelCount++;
                        }
                    }
                    iters[i][j] = IterResult(
                        perturbResult.iterations,
                        perturbResult.smoothed
                    );
                    if (allowSecondPass) {
                        bool markUncertain = perturbResult.uncertain;
                        if (uncertainMask.length > 0 && uncertainMask[i].length > 0) {
                            uncertainMask[i][j] = markUncertain;
                        }
                    }
                } else {
                    iters[i][j] = referencePixelIter;
                    if (allowSecondPass) {
                        uncertainMask[i][j] = false;
                    }
                }
            } else if (usedBigFloatFallback) {
                iters[i][j] = IterResult(
                    fallbackPerturb.iterations,
                    fallbackPerturb.smoothed
                );
                if (allowSecondPass) {
                    uncertainMask[i][j] = false;
                }
            } else {
                iters[i][j] = referencePixelIter;
                if (allowSecondPass) {
                    uncertainMask[i][j] = false;
                }
            }
            
            int current = atomicOp!"+="(processedPixels, 1);
            if (current % progressInterval == 0 || current == totalPixels) {
                long percent = (cast(long)current * 100L) / cast(long)totalPixels;
                int oldPercent = atomicLoad(lastPercent);
                if (percent != oldPercent && percent >= 0 && percent <= 100) {
                    atomicStore(lastPercent, cast(int)percent);
                    if (atomicLoad(lastPercent) == cast(int)percent) {
                        write(cast(int)percent, "% ");
                        stdout.flush();
                    }
                }
            }
        }
    }
    writeln();
    int minIterFirst = int.max;
    int maxIterFirst = int.min;
    long maxIterCountFirst = 0;
    foreach (i; 0 .. desc.width) {
        for (int j = 0; j < desc.height; j++) {
            auto iterVal = iters[i][j].iterations;
            if (iterVal < minIterFirst) {
                minIterFirst = iterVal;
            }
            if (iterVal > maxIterFirst) {
                maxIterFirst = iterVal;
                maxIterCountFirst = 1;
            } else if (iterVal == maxIterFirst) {
                maxIterCountFirst++;
            }
        }
    }
    if (minIterFirst == int.max) minIterFirst = 0;
    if (maxIterFirst == int.min) maxIterFirst = 0;
    
    bool forceDirectSecondPass = false;
    if (allowSecondPass &&
        precisionMethod == PrecisionMethod.multidouble &&
        maxIterFirst == desc.dwell &&
        maxIterCountFirst == totalPixels) {
        writeln("All pixels reached the max iteration cap; forcing direct MultiDouble recomputation.");
        forceDirectSecondPass = true;
        foreach (i; 0 .. desc.width) {
            foreach (j; 0 .. desc.height) {
                uncertainMask[i][j] = true;
            }
        }
    }
    
    if (allowSecondPass) {
        int uncertainCount = 0;
        foreach (i; 0 .. desc.width) {
            foreach (j; 0 .. desc.height) {
                if (uncertainMask[i][j]) {
                    uncertainCount++;
                }
            }
        }

        if (uncertainCount > 0) {
            writeln("Second pass: Recomputing ", uncertainCount, " uncertain pixels with higher precision...");
            int progressInterval2 = max(1, uncertainCount / 40);
            int processedSecondPass = 0;
            if (precisionMethod == PrecisionMethod.multidouble &&
                numDoublesForMD > 0 &&
                zRefArrayMD.length > 0) {
                import perturbation_bla_hp : perturbIterateBLAMultiDouble;
                import perturbation_bla_hp : iterateDirectMultiDouble;
                int recomputed = 0;
                foreach (i; 0 .. desc.width) {
                    for (int j = 0; j < desc.height; j++) {
                        if (!uncertainMask[i][j]) continue;
                        int dx = i - centerPx;
                        int dy = centerPy - j;
                        auto dxMD = MultiDouble(numDoublesForMD, cast(double)dx);
                        auto dyMD = MultiDouble(numDoublesForMD, cast(double)dy);
                        auto delta0MDHigh = MultiDoubleComplex(
                            dxMD * pixelSizeMD,
                            dyMD * pixelSizeMD
                        );
                        PerturbResult perturbResult;
                        if (forceDirectSecondPass) {
                            auto cPixel = centerCoordMD + delta0MDHigh;
                            perturbResult = iterateDirectMultiDouble(
                                cPixel, desc.dwell, numDoublesForMD, escapeRadius2
                            );
                        } else {
                            perturbResult = perturbIterateBLAMultiDouble(
                                zRefArrayMD, escapeRadius2, blaEntriesArray,
                                delta0MDHigh, desc.dwell, numDoublesForMD
                            );
                        }
                        iters[i][j] = IterResult(perturbResult.iterations, perturbResult.smoothed);
                        uncertainMask[i][j] = false;
                        recomputed++;
                        processedSecondPass++;
                        if (processedSecondPass % progressInterval2 == 0 || processedSecondPass == uncertainCount) {
                            int pct = cast(int)((processedSecondPass * 100L) / uncertainCount);
                            write(pct, "% ");
                            stdout.flush();
                        }
                    }
                }
                writeln();
                writeln("Second pass (MultiDouble) recomputed ", recomputed, " pixels.");
            } else if (precisionMethod == PrecisionMethod.bigint && zRefArrayBF.length > 0) {
                import perturbation_bla_hp : perturbIterateBLABigFloat;
                int recomputed = 0;
                foreach (i; 0 .. desc.width) {
                    for (int j = 0; j < desc.height; j++) {
                        if (!uncertainMask[i][j]) continue;
                        int dx = i - centerPx;
                        int dy = centerPy - j;
                        import bigfloat : BigFloat, BigFloatComplex;
                        BigFloat dxBF = BigFloat(cast(double)dx);
                        BigFloat dyBF = BigFloat(cast(double)dy);
                        BigFloat pixelSizeBF = BigFloat(pixelSizeGMP.toString());
                        auto deltaReBF = dxBF * pixelSizeBF;
                        auto deltaImBF = dyBF * pixelSizeBF;
                        auto deltaLocal = BigFloatComplex(deltaReBF, deltaImBF);
                        auto perturbResult = perturbIterateBLABigFloat(
                            zRefArrayBF, escapeRadius2, blaEntriesArray,
                            deltaLocal, desc.dwell
                        );
                        iters[i][j] = IterResult(perturbResult.iterations, perturbResult.smoothed);
                        uncertainMask[i][j] = false;
                        recomputed++;
                        processedSecondPass++;
                        if (processedSecondPass % progressInterval2 == 0 || processedSecondPass == uncertainCount) {
                            int pct = cast(int)((processedSecondPass * 100L) / uncertainCount);
                            write(pct, "% ");
                            stdout.flush();
                        }
                    }
                }
                writeln();
                writeln("Second pass (BigFloat) recomputed ", recomputed, " pixels.");
            } else if (precisionMethod == PrecisionMethod.gmp && zRefArrayGMP.length > 0) {
                import perturbation_bla_hp : perturbIterateBLAGMP;
                int recomputed = 0;
                foreach (i; 0 .. desc.width) {
                    for (int j = 0; j < desc.height; j++) {
                        if (!uncertainMask[i][j]) continue;
                        auto deltaExact = pixelConverterGMP.pixelToComplex(i, j) - cRefGMP;
                        auto perturbResult = perturbIterateBLAGMP(
                            zRefArrayGMP, escapeRadius2, blaEntriesArray,
                            deltaExact, desc.dwell
                        );
                        iters[i][j] = IterResult(perturbResult.iterations, perturbResult.smoothed);
                        uncertainMask[i][j] = false;
                        recomputed++;
                        processedSecondPass++;
                        if (processedSecondPass % progressInterval2 == 0 || processedSecondPass == uncertainCount) {
                            int pct = cast(int)((processedSecondPass * 100L) / uncertainCount);
                            write(pct, "% ");
                            stdout.flush();
                        }
                    }
                }
                writeln();
                writeln("Second pass (GMP) recomputed ", recomputed, " pixels.");
            } else {
                writeln("Second pass skipped: no higher precision method available.");
            }
        } else {
            writeln("No uncertain pixels found, skipping second pass");
        }
    }

    int minIter = int.max;
    int maxIter = int.min;
    long maxIterCount = 0;
    foreach (i; 0 .. desc.width) {
        for (int j = 0; j < desc.height; j++) {
            auto iterVal = iters[i][j].iterations;
            if (iterVal < minIter) {
                minIter = iterVal;
            }
            if (iterVal > maxIter) {
                maxIter = iterVal;
                maxIterCount = 1;
            } else if (iterVal == maxIter) {
                maxIterCount++;
            }
        }
    }
    if (minIter == int.max) {
        minIter = 0;
    }
    if (maxIter == int.min) {
        maxIter = 0;
    }
    writeln("Iteration stats: min=", minIter, ", max=", maxIter,
            ", pixels at max=", maxIterCount, "/", desc.width * desc.height);

    if ("MANDEL_VERIFY" in environment) {
        writeln("MANDEL_VERIFY set; verifying sample pixels via direct GMP iteration...");
        import gmp_arb : GMPPixelConverter;
        auto verifyConverter = GMPPixelConverter(
            desc.width, desc.height,
            originXHP, originYHP, radiusHP
        );
        auto verifyOptions = determineGMPFractalOptions(cfg.multibrotExp);
        Coord[] samples;
        samples ~= Coord(desc.width / 2, desc.height / 2);
        samples ~= Coord(desc.width / 4, desc.height / 4);
        samples ~= Coord(3 * desc.width / 4, desc.height / 4);
        samples ~= Coord(desc.width / 4, 3 * desc.height / 4);
        samples ~= Coord(3 * desc.width / 4, 3 * desc.height / 4);
        size_t verified = 0;
        auto refPixel = verifyConverter.pixelToComplex(desc.width / 2, desc.height / 2);
        MultiDoubleComplex cRefMD;
        bool haveCRefMD = false;
        if (precisionMethod == PrecisionMethod.multidouble && numDoublesForMD > 0) {
            cRefMD = MultiDoubleComplex(numDoublesForMD, originXHP, originYHP);
            haveCRefMD = true;
        }
        foreach (sample; samples) {
            auto px = max(0, min(sample[0], desc.width - 1));
            auto py = max(0, min(sample[1], desc.height - 1));
            auto gmpResult = iterateGMPDirect(px, py, cfg, verifyConverter, verifyOptions);
            auto perturbResult = iters[px][py];
            auto diff = gmpResult.iterations - perturbResult.iterations;
            auto diffSmooth = gmpResult.smoothed - perturbResult.smoothed;
            writeln("  Pixel(", px, ",", py, "): perturb=", perturbResult.iterations,
                    ", GMP=", gmpResult.iterations, ", diff=", diff,
                    ", smooth diff=", format!"%.6f"(diffSmooth));
            if (precisionMethod == PrecisionMethod.multidouble &&
                haveCRefMD &&
                useMultiDoubleForDeltas) {
                int dx = px - centerPx;
                int dy = centerPy - py;
                auto dxMD = MultiDouble(numDoublesForMD, cast(double)dx);
                auto dyMD = MultiDouble(numDoublesForMD, cast(double)dy);
                auto deltaReMDComp = dxMD * pixelSizeMD;
                auto deltaImMDComp = dyMD * pixelSizeMD;
                auto deltaReMD = deltaReMDComp.toDouble();
                auto deltaImMD = deltaImMDComp.toDouble();
                auto pixelGMP = verifyConverter.pixelToComplex(px, py);
                auto deltaGMPRe = (pixelGMP.re - refPixel.re).toDouble();
                auto deltaGMPIm = (pixelGMP.im - refPixel.im).toDouble();
                writeln("    Δapprox=( ", deltaReMD, ", ", deltaImMD, " ) vs Δexact=( ",
                        deltaGMPRe, ", ", deltaGMPIm, " )");
                auto cActualMD = MultiDoubleComplex(deltaReMDComp, deltaImMDComp) + cRefMD;
                auto mdDirect = iterateDirectMultiDouble(
                    cActualMD, desc.dwell, numDoublesForMD, refOrbit.escapeRadius2
                );
                writeln("    direct MultiDouble iterations=", mdDirect.iterations,
                        ", diff vs perturb=", mdDirect.iterations - perturbResult.iterations);
            }
            verified++;
        }
        if (verified == 0) {
            writeln("  No pixels verified (image too small).");
        }
    }
}

private void iterateGMPDirectMode(ref IterResult[][] iters, const ref RenderConfig cfg,
                                  const ref RenderParams desc, int wfactor) {
    import gmp_arb : GMPFloat, GMPPixelConverter;
    import core.atomic;
    
    uint digits = combinedPrecisionDigits(desc);
    
    GMPFloat.setPrecisionDigits(digits);
    auto converter = GMPPixelConverter(
        desc.width, desc.height,
        desc.originXStr, desc.originYStr, desc.radiusStr
    );
    
    auto gmpOptions = determineGMPFractalOptions(cfg.multibrotExp);
    bool gmpSupports = true;
    final switch (cfg.fractalType) {
        case FractalType.mandelbrot:
            break;
        case FractalType.ship:
            break;
        case FractalType.multibrot:
        case FractalType.mandelbar:
            gmpSupports = gmpOptions.hasIntegerPower;
            break;
    }
    if (!gmpSupports) {
        writeln("GMP direct iteration does not support ", cfg.fractalType,
                " with exponent ", cfg.multibrotExp,
                "; falling back to standard double precision for this render.");
    }
    
    auto wRange = iota(0, desc.width);
    foreach (i; parallel(wRange)) {
        for (int j = 0; j < desc.height; j++) {
            if (gmpSupports) {
                iters[i][j] = iterateGMPDirect(i, j, cfg, converter, gmpOptions);
            } else {
                iters[i][j] = iterate(i, j, cfg);
            }
        }
    }
}

private void iterateWithProgress(ref IterResult[][] iters, const ref RenderConfig cfg,
                                 const ref RenderParams desc, int wfactor) {
		int loaded = 0;
		if (exists(workdir ~ "/" ~ desc.filename ~ ".tmp")) {
			writeln("-- Progress data found --");
			auto progdata = cast(const(ubyte)[])read(workdir ~ "/" ~ desc.filename ~ ".tmp");
        iters = decerealise!(IterResult[][])(progdata);
			if (iters.length == desc.width) {
				loaded = 0;
				foreach (line; iters) {
					if (line.length == desc.height) {
						loaded++;
					} else {
						break;
					}
				}
				writeln("-- Data loaded, ", loaded, " lines --");
			} else {
            iters = new IterResult[][](desc.width, desc.height);
        }
    }
    
		const int blockSize = saveProgress * wfactor;
    const int endp = to!int(ceil(desc.width / to!double(blockSize)));
    
    for (int block = 0; block < endp; block++) {
        auto blockEnd = (block + 1) * blockSize;
        auto wRange = iota(block * blockSize, min(blockEnd, desc.width));

			foreach (i; parallel(wRange)) {
            if (iters[i].length != desc.height || i >= loaded) {
                for (int j = 0; j < desc.height; j++) {
                    iters[i][j] = iterate(i, j, cfg);
					}
				} 
				if (i % wfactor == 0) {
                write('.');
                stdout.flush();
				}
			}
        write(' ');
        stdout.flush();

			if (loaded >= blockEnd || desc.width <= blockEnd)
				continue;

			auto progdata = iters.cerealise;
			std.file.write(workdir ~ "/" ~ desc.filename ~ ".tmp", progdata);
        write("! ");
    }
    
    if (exists(workdir ~ "/" ~ desc.filename ~ ".tmp")) {
		remove(workdir ~ "/" ~ desc.filename ~ ".tmp");
    }
}

private void iterateBuddhabrot(ref IterResult[][] iters, const ref RenderConfig cfg,
                               const ref RenderParams desc, int wfactor) {
    auto accumulator = BuddhaAccumulator(desc.width, desc.height);
    
    auto numThreads = totalCPUs;
    int[][] localBuffers;
    localBuffers.length = numThreads;
    
    foreach (i; 0 .. numThreads) {
        localBuffers[i] = new int[](desc.width * desc.height);
        localBuffers[i][] = 0;
    }
    
    writeln("Using ", numThreads, " threads for Buddhabrot");
    
    auto wRange = iota(0, desc.width);
    foreach (x; parallel(wRange)) {
        auto tid = x % numThreads;
        
        for (int y = 0; y < desc.height; y++) {
            auto result = iterateWithOrbit(x, y, cfg);
            iters[x][y] = result.iter;
            
            bool shouldAccumulate = (desc.buddha == BuddhaMode.antibuddha) || 
                                    (result.iter.iterations < cfg.maxIterations);
            
            if (shouldAccumulate) {
                foreach (point; result.orbit) {
                    auto pixel = complexToPixel(point[0], point[1], cfg);
                    int px = pixel[0];
                    int py = pixel[1];
                    if (px >= 0 && px < desc.width && py >= 0 && py < desc.height) {
                        localBuffers[tid][px * desc.height + py]++;
                    }
                }
            }
        }
        if (x % wfactor == 0) {
            write('.');
            stdout.flush();
        }
    }
    
    writeln("\nMerging Buddhabrot data...");

    foreach (tid; 0 .. numThreads) {
        foreach (x; 0 .. desc.width) {
            foreach (y; 0 .. desc.height) {
                accumulator.data[x][y] += localBuffers[tid][x * desc.height + y];
            }
        }
    }
    
    int maxVal = accumulator.maxHits();
    writeln("Max buddha hits: ", maxVal);
    
    SuperImage buddhaImg = image(desc.width, desc.height);
    
    foreach (x; 0 .. desc.width) {
        for (int y = 0; y < desc.height; y++) {
            buddhaImg[x, y] = computeBuddhaColor(accumulator.data[x][y], maxVal);
        }
        if (x % wfactor == 0) {
            write('.');
            stdout.flush();
        }
    }
    
    string buddhaPrefix = desc.buddha == BuddhaMode.buddha ? "buddha_" : "antibuddha_";
    writeln("\nSaving: " ~ workdir ~ "/" ~ buddhaPrefix ~ desc.filename ~ ".png");
    savePNG(buddhaImg, workdir ~ "/" ~ buddhaPrefix ~ desc.filename ~ ".png");
}

// =============================================================================
// File Name Generation
// =============================================================================

string generateFileName(RenderParams s) {
    return to!string(s.fractalType) ~ 
    "_X=" ~ format!"%.17g"(s.originX) ~
    "_Y=" ~ format!"%.17g"(s.originY) ~
    "_R=" ~ format!"%.17g"(s.radius) ~
    "_W=" ~ to!string(s.width) ~
    "_H=" ~ to!string(s.height) ~
    "_I=" ~ to!string(s.dwell) ~ 
    "_P=" ~ to!string(s.palette ? s.palette : s.dwell) ~ 
    "_C=" ~ to!string(s.colorfunc) ~ 
        (s.fractalType == FractalType.multibrot ? "_E=" ~ to!string(s.multibrotExp) : "");
}

// =============================================================================
// JSON Parsing Helpers
// =============================================================================

private double getJsonNumber(JSONValue v) {
    if (v.type == JSONType.integer) {
        return cast(double)v.integer;
    } else if (v.type == JSONType.uinteger) {
        return cast(double)v.uinteger;
    } else if (v.type == JSONType.float_) {
        return v.floating;
    }
    return 0.0;
}

private int getJsonInt(JSONValue v) {
    if (v.type == JSONType.integer) {
        return cast(int)v.integer;
    } else if (v.type == JSONType.uinteger) {
        return cast(int)v.uinteger;
    } else if (v.type == JSONType.float_) {
        return cast(int)v.floating;
    }
    return 0;
}

private bool isNonZeroNumber(JSONValue v) {
    if (v.type == JSONType.integer) return v.integer != 0;
    if (v.type == JSONType.uinteger) return v.uinteger != 0;
    if (v.type == JSONType.float_) return v.floating != 0;
    return false;
}

// =============================================================================
// JSON Parsing
// =============================================================================

RenderParams createBrotDesc(JSONValue s) {
    RenderParams ret;
	
	if (s.type != JSONType.object) return ret;

    if ("width" in s && isNonZeroNumber(s["width"])) ret.width = getJsonInt(s["width"]);
    if ("height" in s && isNonZeroNumber(s["height"])) ret.height = getJsonInt(s["height"]);
    
    if ("amp" in s && isNonZeroNumber(s["amp"])) {
        ret.width = 16 * getJsonInt(s["amp"]);
        ret.height = 16 * getJsonInt(s["amp"]);
    }
    
	if ("x1" in s && "x2" in s && "y1" in s && "y2" in s) {
        const auto x = (getJsonNumber(s["x1"]) + getJsonNumber(s["x2"])) / 2;
        const auto y = (getJsonNumber(s["y1"]) + getJsonNumber(s["y2"])) / 2;
        const auto radX = max(getJsonNumber(s["x1"]), getJsonNumber(s["x2"])) - 
                         min(getJsonNumber(s["x1"]), getJsonNumber(s["x2"]));
        const auto radY = max(getJsonNumber(s["y1"]), getJsonNumber(s["y2"])) - 
                         min(getJsonNumber(s["y1"]), getJsonNumber(s["y2"]));

		ret.originX = x;
		ret.originY = y;
		ret.radius = max(radX, radY);
		
		ret.originXStr = format!"%.20g"(x);
		ret.originYStr = format!"%.20g"(y);
		ret.radiusStr = format!"%.20g"(ret.radius);
	}

    if ("x" in s) {
        if (s["x"].type == JSONType.string) {
            ret.originXStr = s["x"].str;
            try { ret.originX = to!real(s["x"].str); } catch (Exception) {}
        } else {
            ret.originX = getJsonNumber(s["x"]);
            ret.originXStr = format!"%.20g"(ret.originX);
        }
    }
    if ("y" in s) {
        if (s["y"].type == JSONType.string) {
            ret.originYStr = s["y"].str;
            try { ret.originY = to!real(s["y"].str); } catch (Exception) {}
        } else {
            ret.originY = getJsonNumber(s["y"]);
            ret.originYStr = format!"%.20g"(ret.originY);
        }
    }
    if ("radius" in s) {
        if (s["radius"].type == JSONType.string) {
            ret.radiusStr = s["radius"].str;
            try { ret.radius = to!real(s["radius"].str); } catch (Exception) {}
        } else {
            ret.radius = getJsonNumber(s["radius"]);
            ret.radiusStr = format!"%.20g"(ret.radius);
        }
    }
    
    if ("precision" in s && s["precision"].type == JSONType.string) {
        ret.forcePrecision = s["precision"].str;
    } else if ("precisionMode" in s && s["precisionMode"].type == JSONType.string) {
        ret.forcePrecision = s["precisionMode"].str;
    }
    
    if ("arbitrary_precision_method" in s && s["arbitrary_precision_method"].type == JSONType.string) {
        ret.arbitraryPrecisionMethod = s["arbitrary_precision_method"].str;
    } else if ("arbitraryPrecisionMethod" in s && s["arbitraryPrecisionMethod"].type == JSONType.string) {
        ret.arbitraryPrecisionMethod = s["arbitraryPrecisionMethod"].str;
    }
    
    if ("zoom" in s) {
        string zoomStr;
        if (s["zoom"].type == JSONType.string) {
            zoomStr = s["zoom"].str;
        } else {
            zoomStr = format!"%.20g"(getJsonNumber(s["zoom"]));
        }
        
        auto ePos = zoomStr.countUntil!(c => c == 'e' || c == 'E')();
        if (ePos >= 0) {
            string mantissa = zoomStr[0..ePos];
            int exp = to!int(zoomStr[ePos + 1 .. $]);
            double mant = to!double(mantissa);
            double invMant = 1.0 / mant;
            int newExp = -exp;
            ret.radiusStr = format!"%.10ge%d"(invMant, newExp);
            try { ret.radius = to!real(ret.radiusStr); } catch (Exception) {}
        } else {
            double zoom = to!double(zoomStr);
            ret.radius = 1.0 / zoom;
            ret.radiusStr = format!"%.20g"(ret.radius);
        }
    }
    
    if ("dwell" in s && isNonZeroNumber(s["dwell"])) ret.dwell = getJsonInt(s["dwell"]);
    if ("palette" in s) ret.palette = getJsonInt(s["palette"]);
    if ("paletteOffset" in s) ret.paletteOffset = cast(float)getJsonNumber(s["paletteOffset"]);
    if ("palette_reverse" in s && s["palette_reverse"].type == JSONType.true_) {
        ret.paletteReverse = true;
    } else if ("palette_reverse" in s && s["palette_reverse"].type == JSONType.false_) {
        ret.paletteReverse = false;
    }
    if ("paletteFile" in s && s["paletteFile"].type == JSONType.string) {
        ret.paletteFile = s["paletteFile"].str;
    } else if ("palette_file" in s && s["palette_file"].type == JSONType.string) {
        ret.paletteFile = s["palette_file"].str;
    }
    
    if ("multibrotExp" in s) ret.multibrotExp = cast(float)getJsonNumber(s["multibrotExp"]);
    
    if ("type" in s) ret.fractalType = to!FractalType(s["type"].str);
	if ("colorfunc" in s) ret.colorfunc = to!ColorFunc(s["colorfunc"].str);

    if ("buddha" in s && s["buddha"].type == JSONType.true_) {
        ret.buddha = BuddhaMode.buddha;
    } else if ("antibuddha" in s && s["antibuddha"].type == JSONType.true_) {
        ret.buddha = BuddhaMode.antibuddha;
    }
    
    if ("autoDwell" in s && s["autoDwell"].type == JSONType.true_) {
        ret.autoDwell = true;
    }
    
    if ("x_px_offset" in s) {
        ret.x_px_offset = getJsonInt(s["x_px_offset"]);
    }
    if ("y_px_offset" in s) {
        ret.y_px_offset = getJsonInt(s["y_px_offset"]);
    }
    
    if ("filename" in s) {
        ret.filename = s["filename"].str;
    } else {
        ret.filename = ret.generateFileName();
    }
    
    return ret;
}

// =============================================================================
// Animation and Chunking Sequences
// =============================================================================

void generateAnimateSequence(ref RenderParams[] queue, JSONValue animate) {
	const int frames = to!int(animate["animate"].integer);
	const int skip = "skip" in animate ? to!int(animate["skip"].integer) : 0;
    const RenderParams fromParams = createBrotDesc(animate["from"]);
    const RenderParams toParams = createBrotDesc(animate["to"]);
    const int w = fromParams.width;
    const int h = fromParams.height;

	const string fpath = "animate_FRAMES=" ~ to!string(frames) ~ 
		"_W=" ~ to!string(w) ~ "_H=" ~ to!string(h) ~
        "_X0=" ~ format!"%.17g"(fromParams.originX) ~ "_Y0=" ~ 
        format!"%.17g"(fromParams.originY) ~ "_Rn=" ~ format!"%.17g"(toParams.radius) ~ "/";

	if (!(workdir ~ "/" ~ fpath).exists) (workdir ~ "/" ~ fpath).mkdir;

    const double deltaX = (toParams.originX - fromParams.originX) / to!double(frames);
    const double deltaY = (toParams.originY - fromParams.originY) / to!double(frames);
    const double deltaRadius = (log(toParams.radius) - log(fromParams.radius)) / to!double(frames);
    const float deltaDwell = (log(cast(double)toParams.dwell) - log(cast(double)fromParams.dwell)) / to!double(frames);
    const float deltaPalette = (log(cast(double)(toParams.palette ? toParams.palette : toParams.dwell)) - 
        log(cast(double)(fromParams.palette ? fromParams.palette : fromParams.dwell))) / to!double(frames);
    const float deltaExp = (toParams.multibrotExp - fromParams.multibrotExp) / to!double(frames);
    
    for (int i = 0; i <= frames; i++) {
		if (i < skip) continue;
		
        RenderParams ret;

		ret.width = w;
		ret.height = h;
        ret.originX = fromParams.originX + deltaX * i;
        ret.originY = fromParams.originY + deltaY * i;
        ret.radius = exp(log(fromParams.radius) + deltaRadius * i);
        
        ret.originXStr = format!"%.20g"(ret.originX);
        ret.originYStr = format!"%.20g"(ret.originY);
        ret.radiusStr = format!"%.20g"(ret.radius);
        
        ret.dwell = cast(int)exp(log(cast(double)fromParams.dwell) + deltaDwell * i);
        ret.palette = cast(int)exp(log(cast(double)fromParams.palette) + deltaPalette * i);
        
        ret.multibrotExp = fromParams.multibrotExp + (deltaExp * i);
        
        ret.fractalType = fromParams.fractalType;
        ret.colorfunc = fromParams.colorfunc;
        ret.buddha = fromParams.buddha;

		ret.filename = fpath ~ "frame_" ~ format!"%06d"(i);

        queue ~= ret;
	}
}

void generateChunksSequence(ref RenderParams[] queue, JSONValue source) {
	const int chunks = to!int(source["chunks"].integer);
    const RenderParams s = createBrotDesc(source);

	const string fpath = "CHUNKED=" ~ to!string(chunks) ~ "_" ~ s.filename ~ "/";

	if (!(workdir ~ "/" ~ fpath).exists) (workdir ~ "/" ~ fpath).mkdir;

    if (s.buddha != BuddhaMode.none) {
		if (!(workdir ~ "/" ~ to!string(s.buddha) ~ "_" ~ fpath).exists) 
			(workdir ~ "/" ~ to!string(s.buddha) ~ "_" ~ fpath).mkdir;
	}

    const int w = cast(int)(s.width / to!double(chunks));
    const int h = cast(int)(s.height / to!double(chunks));

    const double diff = cast(double)(min(w, h)) / max(w, h);
    const double radiusX = s.radius * (w > h ? 1 : diff) / to!double(chunks);
    const double radiusY = s.radius * (w < h ? 1 : diff) / to!double(chunks);

    const double x1 = s.originX - (s.radius * (w > h ? 1 : diff) / to!double(chunks)) * (chunks / 2 + 2);
    const double y1 = s.originY + (s.radius * (w < h ? 1 : diff) / to!double(chunks)) * (chunks / 2 + 2);
    
    for (int i = 0; i < chunks; i++) {
        for (int j = 0; j < chunks; j++) {
            RenderParams ret;

			ret.width = w;
			ret.height = h;
			ret.originX = x1 + radiusX * 2 * (j + 0.5);
			ret.originY = y1 - radiusY * 2 * (i + 0.5);
			ret.radius = min(radiusX, radiusY);
            
            ret.originXStr = format!"%.20g"(ret.originX);
            ret.originYStr = format!"%.20g"(ret.originY);
            ret.radiusStr = format!"%.20g"(ret.radius);

			ret.dwell = s.dwell;
			ret.palette = s.palette;

			ret.multibrotExp = s.multibrotExp;

            ret.fractalType = s.fractalType;
			ret.colorfunc = s.colorfunc;
			ret.buddha = s.buddha;

            ret.filename = fpath ~ "chunk_" ~ format!"%06d"(i * chunks + j);

            queue ~= ret;
		}
	}
}
