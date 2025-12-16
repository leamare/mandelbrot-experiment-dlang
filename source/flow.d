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
import std.algorithm : min, max, countUntil;

import cerealed;
import dlib.image;

import mandel;
import gmp_arb;
import perturbation_bla;
import multidouble : calculateNumDoubles;

// =============================================================================
// Module-level Configuration
// =============================================================================

enum uint PRECISION_THRESHOLD_DOUBLE = 15;
enum uint PRECISION_THRESHOLD_BIGFLOAT = 50;
enum uint PRECISION_THRESHOLD_MULTIDOUBLE = 240;
enum uint PRECISION_THRESHOLD_GMP = 241;
enum uint MULTIDOUBLE_MIN_DOUBLES = 2;
enum uint MULTIDOUBLE_MAX_DOUBLES = 12;

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
    bool paletteReverse = false;
    string paletteFile = "";
    float paletteOffset = 0.0;
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
        cfg.buddhaMode = buddha;
        cfg.precisionMode = precisionMode();
        cfg.arbitraryPrecision = requiredPrecision();
        return cfg;
    }
}

// =============================================================================
// Buddhabrot Data Collection (Thread-Safe)
// =============================================================================

/// Accumulator for Buddhabrot hit counts
/// Uses task-local buffers to avoid contention
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

private void iterateGMPMode(ref IterResult[][] iters, const ref RenderConfig cfg, const ref RenderParams desc, int wfactor) {
    import precision_unified : PrecisionMethod, parsePrecisionMethod, selectPrecisionMethod;
    import gmp_arb : GMPFloat;
    import std.complex;
    import core.atomic;
    
    PrecisionMethod precisionMethod = PrecisionMethod.auto_;
    
    if (desc.arbitraryPrecisionMethod.length > 0) {
        precisionMethod = parsePrecisionMethod(desc.arbitraryPrecisionMethod);
        writeln("Using forced precision method: ", desc.arbitraryPrecisionMethod);
        if (precisionMethod == PrecisionMethod.bigint) {
            precisionMethod = PrecisionMethod.gmp;
            writeln("Note: bigint precision method uses GMP implementation");
        }
    } else if (desc.forcePrecision.length > 0) {
        string mode = desc.forcePrecision.toLower().strip();
        if (mode == "bigfloat" || mode == "dd" || mode == "doubledouble" || mode == "bigfixed") {
            precisionMethod = PrecisionMethod.bigfloat;
        } else if (mode == "gmp" || mode == "arbitrary") {
            precisionMethod = PrecisionMethod.gmp;
        } else if (mode == "double" || mode == "standard") {
            precisionMethod = PrecisionMethod.double_;
        } else if (mode == "bigint") {
            precisionMethod = PrecisionMethod.gmp;
            writeln("Note: bigint precision method uses GMP implementation");
        } else {
            precisionMethod = parsePrecisionMethod(mode);
            if (precisionMethod == PrecisionMethod.bigint) {
                precisionMethod = PrecisionMethod.gmp;
                writeln("Note: bigint precision method uses GMP implementation");
            }
        }
    }
    
    if (precisionMethod == PrecisionMethod.auto_) {
        uint digits;
        if (desc.radiusStr.length > 0) {
            real radius = desc.radius;
            digits = RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height);
        } else {
            auto coordLen = max(desc.originXStr.length, desc.originYStr.length);
            digits = cast(uint)max(50, coordLen + 20);
        }
        
        PrecisionMethod arbitraryMethod = PrecisionMethod.gmp;
        if (desc.arbitraryPrecisionMethod.length > 0) {
            auto arbMethod = parsePrecisionMethod(desc.arbitraryPrecisionMethod);
            if (arbMethod == PrecisionMethod.bigint || arbMethod == PrecisionMethod.gmp) {
                arbitraryMethod = arbMethod;
            }
        }
        
        precisionMethod = selectPrecisionMethod(digits, arbitraryMethod);
        
        string methodName = 
            precisionMethod == PrecisionMethod.double_ ? "double" :
            precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" :
            precisionMethod == PrecisionMethod.multidouble ? "multidouble" :
            precisionMethod == PrecisionMethod.gmp ? "gmp" :
            precisionMethod == PrecisionMethod.bigint ? "bigint" : "auto";
        
        if (precisionMethod == PrecisionMethod.multidouble) {
            uint numDoubles = calculateNumDoubles(digits);
            writeln("Auto-selected precision method: ", methodName, " (", numDoubles, " doubles, based on ", digits, " required digits)");
        } else {
            writeln("Auto-selected precision method: ", methodName, " (based on ", digits, " required digits)");
        }
        if (digits > 100) {
            writeln("  Using ", arbitraryMethod == PrecisionMethod.gmp ? "GMP" : "bigint", 
                    " for very high precision");
        }
    }
    
    if (precisionMethod == PrecisionMethod.gmp || precisionMethod == PrecisionMethod.bigint) {
        uint digits;
        if (desc.radiusStr.length > 0) {
            real radius = desc.radius;
            digits = RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height);
        } else {
            auto coordLen = max(desc.originXStr.length, desc.originYStr.length);
            digits = cast(uint)max(50, coordLen + 20);
        }
        GMPFloat.setPrecisionDigits(digits);
        writeln("Using Perturbation+BLA for deep zoom");
        writeln("Reference orbit precision: ", digits, " digits");
    } else if (precisionMethod == PrecisionMethod.multidouble) {
        uint digits;
        if (desc.radiusStr.length > 0) {
            real radius = desc.radius;
            digits = RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height);
        } else {
            auto coordLen = max(desc.originXStr.length, desc.originYStr.length);
            digits = cast(uint)max(50, coordLen + 20);
        }
        uint numDoubles = calculateNumDoubles(digits);
        writeln("Using Perturbation+BLA with multidouble precision (", numDoubles, " doubles)");
        writeln("Reference orbit precision: ", digits, " digits");
    } else {
        writeln("Using Perturbation+BLA with ", 
            precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" : "double", " precision");
    }
    
    writeln("Computing reference orbit at center:");
    writeln("  X: ", desc.originXStr);
    writeln("  Y: ", desc.originYStr);
    writeln("  Iterations: ", desc.dwell);
    stdout.flush();
    
    auto refOrbit = computeReferenceOrbit(
        desc.originXStr, desc.originYStr, desc.dwell, precisionMethod
    );

    writeln("Reference orbit computed with precision method: ", 
        precisionMethod == PrecisionMethod.double_ ? "double" :
        precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" :
        precisionMethod == PrecisionMethod.multidouble ? "multidouble" :
        precisionMethod == PrecisionMethod.gmp ? "gmp" : "auto");
        
    if (refOrbit.zRef.length < 2) {
        writeln("ERROR: Reference orbit too short, falling back to direct GMP");
        iterateGMPDirectMode(iters, cfg, desc, wfactor);
        return;
    }
        
    auto blaTable = buildBLATable(refOrbit);
    writeln("Starting perturbation iteration with BLA...");
        
    import gmp_arb : GMPFloat, GMPPixelConverter, GMPComplex;
    import multidouble : MultiDoublePixelConverter, MultiDoubleComplex;
    
    GMPComplex cRefGMP;
    GMPPixelConverter pixelConverterGMP;
    MultiDoublePixelConverter pixelConverterMD;
    MultiDoubleComplex cRefMD;
    bool usingMultiDoubleConverter = false;
    
    if (precisionMethod == PrecisionMethod.multidouble) {
        uint digits;
        if (desc.radiusStr.length > 0) {
            real radius = desc.radius;
            digits = RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height);
        } else {
            auto coordLen = max(desc.originXStr.length, desc.originYStr.length);
            digits = cast(uint)max(50, coordLen + 20);
        }
        uint numDoubles = calculateNumDoubles(digits);
        pixelConverterMD = MultiDoublePixelConverter(
            desc.width, desc.height,
            desc.originXStr, desc.originYStr, desc.radiusStr,
            numDoubles
        );
        cRefMD = MultiDoubleComplex(numDoubles, desc.originXStr, desc.originYStr);
        usingMultiDoubleConverter = true;
    } else {
        pixelConverterGMP = GMPPixelConverter(
            desc.width, desc.height,
            desc.originXStr, desc.originYStr, desc.radiusStr
        );
        cRefGMP = GMPComplex(desc.originXStr, desc.originYStr);
        usingMultiDoubleConverter = false;
    }
        
    double w = cast(double)desc.width;
    double h = cast(double)desc.height;
    double minDim = min(w, h);
    double di = 0, dr = 0;
    if (desc.width != desc.height) {
        double diff = (max(w, h) - minDim) / minDim;
        di = desc.width > desc.height ? diff : 0;
        dr = desc.width > desc.height ? 0 : diff;
    }
    
    shared int processedPixels = 0;
    int totalPixels = desc.width * desc.height;
    int progressInterval = max(1, totalPixels / 40);
    shared int lastPercent = -1;
    
    write("Progress: ");
    stdout.flush();
    
    const Complex!double[] zRefArray = refOrbit.zRef.dup;
    const BLAEntry[] blaEntriesArray = blaTable.entries.dup;
    const double escapeRadius2 = refOrbit.escapeRadius2;
    
    MultiDoubleComplex[] zRefArrayMD;
    uint numDoublesForMD = 0;
    if (precisionMethod == PrecisionMethod.multidouble) {
        import perturbation_bla_hp : computeReferenceOrbitMultiDouble;
        if (desc.radiusStr.length > 0) {
            real radius = desc.radius;
            numDoublesForMD = calculateNumDoubles(RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height));
        } else {
            auto coordLen = max(desc.originXStr.length, desc.originYStr.length);
            numDoublesForMD = calculateNumDoubles(cast(uint)max(50, coordLen + 20));
        }
        writeln("Computing MultiDouble reference orbit (", numDoublesForMD, " doubles) for first pass...");
        zRefArrayMD = computeReferenceOrbitMultiDouble(
            desc.originXStr, desc.originYStr, desc.dwell, numDoublesForMD
        );
        writeln("MultiDouble reference orbit computed: ", zRefArrayMD.length, " points");
    }
        
    auto wRange = iota(0, desc.width);
    foreach (i; parallel(wRange)) {
        for (int j = 0; j < desc.height; j++) {
            Complex!double delta0;
            double delta0LogScale = 0.0;
            bool useScaledDelta = false;
            
            if (usingMultiDoubleConverter) {
                auto pixelC = pixelConverterMD.pixelToComplex(i, j);
                auto delta0MD = pixelC - cRefMD;
                double delta0Real = delta0MD.re.toDouble();
                double delta0Imag = delta0MD.im.toDouble();
                
                double delta0Mag2 = delta0Real * delta0Real + delta0Imag * delta0Imag;
                double radius;
                try {
                    radius = to!double(desc.radiusStr);
                } catch (Exception) {
                    radius = 0;
                }
                bool isActuallyZero = delta0MD.re.isZero() && delta0MD.im.isZero();
                if ((radius <= 1e-300 || radius == 0) || (delta0Real == 0.0 && delta0Imag == 0.0 && !isActuallyZero)) {
                    // Delta is too small - use scaled representation
                    useScaledDelta = true;
                    double relX = (cast(double)i / minDim) * 2.0 - (1.0 + di);
                    double relY = -((cast(double)j / minDim) * 2.0 - (1.0 + dr));
                    delta0 = Complex!double(relX * 2.0, relY * 2.0);  // Normalized delta

                    auto ePos = desc.radiusStr.countUntil!(c => c == 'e' || c == 'E')();
                    if (ePos >= 0) {
                        delta0LogScale = to!double(desc.radiusStr[ePos + 1 .. $]);
                    } else {
                        delta0LogScale = std.math.log10(cast(double)desc.radius);
                    }
                } else {
                    delta0 = Complex!double(delta0Real, delta0Imag);
                }
            } else {
                auto pixelC = pixelConverterGMP.pixelToComplex(i, j);
                auto delta0GMP = pixelC - cRefGMP;
                double delta0Real = delta0GMP.re.toDouble();
                double delta0Imag = delta0GMP.im.toDouble();
                
                double delta0Mag2 = delta0Real * delta0Real + delta0Imag * delta0Imag;
                double radius;
                try {
                    radius = to!double(desc.radiusStr);
                } catch (Exception) {
                    radius = 0;
                }
                // Only use scaled delta if radius is unrepresentable OR delta0 rounds to zero
                if ((radius <= 1e-300 || radius == 0) || (delta0Real == 0.0 && delta0Imag == 0.0)) {
                    // Delta is too small - use scaled representation
                    useScaledDelta = true;
                    double relX = (cast(double)i / minDim) * 2.0 - (1.0 + di);
                    double relY = -((cast(double)j / minDim) * 2.0 - (1.0 + dr));
                    delta0 = Complex!double(relX * 2.0, relY * 2.0);

                    auto ePos = desc.radiusStr.countUntil!(c => c == 'e' || c == 'E')();
                    if (ePos >= 0) {
                        delta0LogScale = to!double(desc.radiusStr[ePos + 1 .. $]);
                    } else {
                        delta0LogScale = std.math.log10(cast(double)desc.radius);
                    }
                } else {
                    delta0 = Complex!double(delta0Real, delta0Imag);
                }
            }
            
            PerturbResult perturbResult;
            if (precisionMethod == PrecisionMethod.multidouble && zRefArrayMD.length > 0) {
                import perturbation_bla_hp : perturbIterateBLAMultiDouble;

                MultiDoubleComplex delta0MD;
                if (usingMultiDoubleConverter) {
                    auto pixelC = pixelConverterMD.pixelToComplex(i, j);
                    delta0MD = pixelC - cRefMD;
                } else {
                    delta0MD = MultiDoubleComplex(numDoublesForMD, delta0.re, delta0.im);
                }
                
                perturbResult = perturbIterateBLAMultiDouble(
                    zRefArrayMD, escapeRadius2, blaEntriesArray, 
                    delta0MD, desc.dwell, numDoublesForMD
                );
            } else if (useScaledDelta) {
                perturbResult = perturbIterateBLAScaledArrays(
                    zRefArray, escapeRadius2, blaEntriesArray, 
                    delta0, delta0LogScale, desc.dwell,
                    refOrbit.escaped ? refOrbit.refIterations : -1
                );
            } else {
                perturbResult = perturbIterateBLAArrays(
                    zRefArray, escapeRadius2, blaEntriesArray, delta0, desc.dwell
                );
            }
            
            iters[i][j] = IterResult(
                perturbResult.iterations,
                perturbResult.smoothed
            );
            
            static int debugPixelCount = 0;
            if (debugPixelCount < 10 && i < 10 && j < 10) {
                writeln("\n[ITER DEBUG] Pixel [", i, ",", j, "]: iterations=", perturbResult.iterations, 
                        ", smoothed=", perturbResult.smoothed, ", maxIter=", desc.dwell);
                debugPixelCount++;
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
    
    double radius;
    try {
        radius = to!double(desc.radiusStr);
    } catch (Exception) {
        radius = desc.radius;
    }
    
    bool hasNegativeExponent = desc.radiusStr.length > 0 && desc.radiusStr.indexOf("e-") >= 0;
    bool needsSecondPass = (radius <= 1e-25 || hasNegativeExponent);
    
    if (needsSecondPass) {
        writeln("Second pass: Recomputing uncertain pixels with higher precision...");
        
        int uncertainCount = 0;
        foreach (i; 0 .. desc.width) {
            for (int j = 0; j < desc.height; j++) {
                if (iters[i][j].iterations >= cast(int)desc.dwell - 10) {
                    uncertainCount++;
                }
            }
        }
        
        if (uncertainCount == 0) {
            writeln("No uncertain pixels found, skipping second pass");
        } else {
            writeln("Found ", uncertainCount, " uncertain pixels (", 
                   (uncertainCount * 100) / (desc.width * desc.height), "%)");
            
            if (precisionMethod == PrecisionMethod.multidouble) {
                import multidouble : MultiDoublePixelConverter, MultiDoubleComplex, calculateNumDoubles;
                import perturbation_bla_hp : perturbIterateBLAMultiDouble;
                uint digits = RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height);
                uint currentDoubles = calculateNumDoubles(digits);
                uint higherDoubles = min(currentDoubles + 2, 12u);
                
                if (higherDoubles > currentDoubles) {
                    writeln("Second pass: Using ", higherDoubles, " doubles (was ", currentDoubles, ") for full MultiDouble perturbation");

                    auto mdConverterHigher = MultiDoublePixelConverter(
                        desc.width, desc.height,
                        desc.originXStr, desc.originYStr, desc.radiusStr, higherDoubles
                    );
                    auto cRefMDHigher = MultiDoubleComplex(higherDoubles, refOrbit.cRef.re.toString(), refOrbit.cRef.im.toString());

                    writeln("Recomputing reference orbit in ", higherDoubles, "-double precision for second pass...");
                    import perturbation_bla_hp : computeReferenceOrbitMultiDouble;
                    auto zRefArrayMDHigher = computeReferenceOrbitMultiDouble(
                        desc.originXStr, desc.originYStr, desc.dwell, higherDoubles
                    );
                    writeln("Reference orbit recomputed: ", zRefArrayMDHigher.length, " points");
                    
                    int recomputed = 0;
                    auto wRange2 = iota(0, desc.width);
                    foreach (i; parallel(wRange2)) {
                        for (int j = 0; j < desc.height; j++) {
                            if (iters[i][j].iterations >= cast(int)desc.dwell - 10) {
                                auto pixelC = mdConverterHigher.pixelToComplex(i, j);
                                auto delta0MD = pixelC - cRefMDHigher;
                                
                                auto perturbResult = perturbIterateBLAMultiDouble(
                                    zRefArrayMDHigher, escapeRadius2, blaEntriesArray, 
                                    delta0MD, desc.dwell, higherDoubles
                                );
                                
                                if (recomputed == 0) {
                                    writeln("\n[FLOW DEBUG] Pixel [", i, ",", j, "]: iterations=", perturbResult.iterations, 
                                            ", smoothed=", perturbResult.smoothed, 
                                            ", glitched=", perturbResult.glitched);
                                }
                                
                                iters[i][j] = IterResult(perturbResult.iterations, perturbResult.smoothed);
                                recomputed++;
                                if (recomputed % 100 == 0) {
                                    write(".");
                                    stdout.flush();
                                }
                            }
                        }
                    }
                    writeln();
                    writeln("Recomputed ", recomputed, " pixels with full ", higherDoubles, "-double precision perturbation");
                } else {
                    writeln("Already at maximum MultiDouble precision (", currentDoubles, " doubles)");
                }
            } else if (precisionMethod == PrecisionMethod.gmp) {
                import gmp_arb : GMPFloat, GMPPixelConverter;
                uint digits = RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height);
                GMPFloat.setPrecisionDigits(digits + 50);
                auto gmpConverter = GMPPixelConverter(
                    desc.width, desc.height,
                    desc.originXStr, desc.originYStr, desc.radiusStr
                );
                
                int maxRecompute = min(uncertainCount, 50);
                int recomputed = 0;
                int skipped = 0;
                
                writeln("Recomputing up to ", maxRecompute, " pixels with GMP...");
                auto wRange2 = iota(0, desc.width);
                foreach (i; parallel(wRange2)) {
                    for (int j = 0; j < desc.height; j++) {
                        if (iters[i][j].iterations >= cast(int)desc.dwell - 10) {
                            if (recomputed < maxRecompute) {
                                auto gmpResult = iterateGMPDirect(i, j, cfg, gmpConverter);
                                iters[i][j] = gmpResult;
                                recomputed++;
                                if (recomputed % 10 == 0) {
                                    write(".");
                                    stdout.flush();
                                }
                            } else {
                                skipped++;
                            }
                        }
                    }
                }
                writeln();
                writeln("Recomputed ", recomputed, " pixels with GMP precision");
                if (skipped > 0) {
                    writeln("Skipped ", skipped, " pixels to avoid hanging");
                }
            } else {
                writeln("Skipping second pass - precision method ", precisionMethod, " doesn't support second pass yet");
            }
        }
    }
    writeln();
}

private void iterateGMPDirectMode(ref IterResult[][] iters, const ref RenderConfig cfg,
                                                                    const ref RenderParams desc, int wfactor) {
    import gmp_arb : GMPFloat, GMPPixelConverter;
    import core.atomic;
    
    uint digits;
    if (desc.radiusStr.length > 0) {
        real radius = desc.radius;
        digits = RenderConfig.calculateOptimalPrecision(radius, desc.width, desc.height);
    } else {
        auto coordLen = max(desc.originXStr.length, desc.originYStr.length);
        digits = cast(uint)max(50, coordLen + 20);
    }
    
    GMPFloat.setPrecisionDigits(digits);
    auto converter = GMPPixelConverter(
        desc.width, desc.height,
        desc.originXStr, desc.originYStr, desc.radiusStr
    );
    
    auto wRange = iota(0, desc.width);
    foreach (i; parallel(wRange)) {
        for (int j = 0; j < desc.height; j++) {
            iters[i][j] = iterateGMPDirect(i, j, cfg, converter);
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
    }
    write(' ');
    stdout.flush();

    if (loaded >= blockEnd || desc.width <= blockEnd)
        continue;

    auto progdata = iters.cerealise;
    std.file.write(workdir ~ "/" ~ desc.filename ~ ".tmp", progdata);
    write("! ");
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
        const auto radX = max(getJsonNumber(s["x1"]), getJsonNumber(s["x2"]))
                                        - min(getJsonNumber(s["x1"]), getJsonNumber(s["x2"]));
        const auto radY = max(getJsonNumber(s["y1"]), getJsonNumber(s["y2"]))
                                        - min(getJsonNumber(s["y1"]), getJsonNumber(s["y2"]));

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
        
    // Force precision mode (optional: "standard", "arbitrary", "gmp", "double", etc.)
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