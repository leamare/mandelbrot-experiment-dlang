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
import calc.types.mpfr;
import calc.types.quaddouble;
import calc.iterate;
import calc.iterate.double_iter : pixelToComplex, complexToPixel, iterateWithOrbit, 
                                  OrbitResult, ComplexD, Coord;
import calc.iterate.dispatcher : iterateAll;
import calc.buddha : BuddhaAccumulator;
import types.fractal : GMPFractalOptions, determineGMPFractalOptions, FractalType, 
                       ColorFunc, BuddhaMode, PrecisionMode;
import types.render : RenderConfig;
import render.coloring : computeColor;
import config.params : RenderParams;
import utils.dwell : estimateDwell;
import utils.precision_auto : combinedPrecisionDigits, digitsPerPixel, getZoomExponent;

import precision.constants;

string workdir = "out";
int saveProgress = 0;
bool skipExisting = false;

uint combinedPrecisionDigitsForParams(const ref RenderParams desc) {
    return combinedPrecisionDigits(desc.originXStr, desc.originYStr, desc.radiusStr, desc.radius);
}

double digitsPerPixelForParams(const ref RenderParams desc) {
    return digitsPerPixel(desc.radius, desc.width, desc.height, desc.radiusStr);
}

int estimatePalette(uint dwell) {
    import utils.color : estimatePalette;
    return cast(int)estimatePalette(dwell);
}

// =============================================================================
// Iteration Statistics
// =============================================================================

private void displayIterationStats(const ref IterResult[][] iters, int width, int height, uint maxIterations) {
    int minIter = int.max;
    int maxIter = int.min;
    long totalIter = 0;
    long pixelCount = 0;
    long maxIterCount = 0;
    
    foreach (i; 0 .. width) {
        foreach (j; 0 .. height) {
            int iter = iters[i][j].iterations;
            if (iter < minIter) minIter = iter;
            if (iter > maxIter) maxIter = iter;
            totalIter += iter;
            pixelCount++;
            if (iter >= maxIterations) maxIterCount++;
        }
    }
    
    if (pixelCount == 0) {
        writeln("\nIteration stats: No pixels computed");
        return;
    }
    
    if (minIter == int.max) minIter = 0;
    if (maxIter == int.min) maxIter = 0;
    
    double avgIter = cast(double)totalIter / cast(double)pixelCount;
    double inSetPercent = 100.0 * cast(double)maxIterCount / cast(double)pixelCount;
    
    writeln("\nIteration stats:");
    writeln("  Min iterations: ", minIter);
    writeln("  Max iterations: ", maxIter);
    writeln("  Avg iterations: ", format!"%.1f"(avgIter));
    writeln("  Pixels in set:  ", maxIterCount, " / ", pixelCount, 
            " (", format!"%.1f"(inSetPercent), "%)");
    stdout.flush();
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
    stdout.flush();

    IterResult[][] iters = new IterResult[][](desc.width, desc.height);

	writeln("\nIterating");
    stdout.flush();

    if (desc.buddha != BuddhaMode.none) {
        iterateBuddhabrot(iters, cfg, desc, wfactor);
    } else if (saveProgress > 0 && saveProgress < 50) {
        iterateWithProgress(iters, cfg, desc, wfactor);
    } else {
        iterateAll(iters, cfg, desc, true, null);
    }
    
    displayIterationStats(iters, desc.width, desc.height, cfg.maxIterations);
    
    SuperImage img = image(desc.width, desc.height);
    
    writeln("\nGenerating image");
    stdout.flush();
    
    {
        import core.atomic;
        shared int completedColumns = 0;
        int totalColumns = desc.width;
        shared int lastMilestone = 0;
        
        write("Progress: 0%");
        stdout.flush();
        
        auto wRange = iota(0, desc.width);
        foreach (i; parallel(wRange)) {
            for (int j = 0; j < desc.height; j++) {
                img[i, j] = computeColor(iters[i][j], cfg);
            }
            
            int completed = atomicOp!"+="(completedColumns, 1);
            int percent = cast(int)((cast(long)completed * 100) / totalColumns);
            int milestone = percent / 5 * 5;
            int oldMilestone = atomicLoad(lastMilestone);
            if (milestone > oldMilestone && milestone <= 100) {
                import core.atomic : cas;
                if (cas(&lastMilestone, oldMilestone, milestone)) {
                    write(" ", milestone, "%");
                    stdout.flush();
                }
            }
        }
        writeln();
    }
    
    writeln("Saving: " ~ workdir ~ "/" ~ desc.filename ~ ".png");
    stdout.flush();
    savePNG(img, workdir ~ "/" ~ desc.filename ~ ".png");
    
    writeln("--------------------\n");
    stdout.flush();
}

private void iterateWithProgress(ref IterResult[][] iters, const ref RenderConfig cfg,
                                 const ref RenderParams desc, int wfactor) {
    import calc.iterate.double_iter : iterateDouble;
    import calc.iterate.mpfr_iter : MPFRPixelConverter, iterateMPFR;
    import std.math : ceil;
    
    bool useMPFR = cfg.precisionMode == PrecisionMode.arbitrary;
    
    uint digits = 50;
    GMPFractalOptions gmpOptions;
    string originXStr, originYStr, radiusStr;
    
    if (useMPFR) {
        uint baseDigits = combinedPrecisionDigitsForParams(desc);
        double perPixelDigits = digitsPerPixelForParams(desc);
        uint perPixelRequired = perPixelDigits > 0
            ? cast(uint)ceil(perPixelDigits + 20.0)
            : 0;
        digits = max(baseDigits, perPixelRequired);
        
        GMPFloat.setPrecisionDigits(digits);
        gmpOptions = determineGMPFractalOptions(cfg.multibrotExp);
        
        originXStr = desc.originXStr;
        originYStr = desc.originYStr;
        radiusStr = desc.radiusStr;
        
        writeln("Using ", digits, " digit precision for MPFR iteration");
        stdout.flush();
    }
    
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
    int width = desc.width;
    int height = desc.height;
    
    for (int block = 0; block < endp; block++) {
        auto blockEnd = (block + 1) * blockSize;
        auto wRange = iota(block * blockSize, min(blockEnd, desc.width));

        foreach (i; parallel(wRange)) {
            if (iters[i].length != height || i >= loaded) {
                if (useMPFR) {
                    GMPFloat.setPrecisionDigits(digits);
                    auto localConverter = MPFRPixelConverter(
                        width, height,
                        originXStr, originYStr, radiusStr
                    );
                    for (int j = 0; j < height; j++) {
                        iters[i][j] = iterateMPFR(i, j, cfg, localConverter, gmpOptions);
                    }
                } else {
                    for (int j = 0; j < height; j++) {
                        iters[i][j] = iterateDouble(i, j, cfg);
                    }
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
    if (cfg.precisionMode == PrecisionMode.arbitrary) {
        writeln("Warning: Buddhabrot mode requires orbit tracking which is only available");
        writeln("  in double precision. Using double precision for Buddhabrot rendering.");
        writeln("  For deep zooms with Buddhabrot, consider using smaller regions.");
        stdout.flush();
    }
    
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
