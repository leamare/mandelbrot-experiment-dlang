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
import calc.iterate.progress : iterateWithProgress;
import calc.iterate.buddha : iterateBuddhabrot, BuddhaResult;
import calc.buddha : BuddhaAccumulator;
import config.animation : generateAnimateSequence, generateChunksSequence;
import config.json_loader : createBrotDesc;
import types.fractal : GMPFractalOptions, determineGMPFractalOptions, FractalType, 
                       ColorFunc, BuddhaMode, PrecisionMode;
import types.render : RenderConfig;
import render.coloring : computeColor;
import config.params : RenderParams;
import config.filename : generateFileName;
import utils.dwell : estimateDwell;
import utils.precision_auto : combinedPrecisionDigits, digitsPerPixel, getZoomExponent;
import utils.color : estimatePalette;

// =============================================================================
// Module-level Configuration
// =============================================================================

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

    BuddhaResult buddhaResult;

    if (desc.buddha != BuddhaMode.none) {
        buddhaResult = iterateBuddhabrot(iters, cfg, desc, wfactor);
    } else if (saveProgress > 0 && saveProgress < 50) {
        iterateWithProgress(iters, cfg, desc, wfactor, saveProgress, workdir);
    } else {
        iterateAll(iters, cfg, desc, true, null);
    }
    
    displayIterationStats(iters, desc.width, desc.height, cfg.maxIterations);
    
    if (desc.buddha != BuddhaMode.none && buddhaResult.maxHits > 0) {
        SuperImage buddhaImg = image(desc.width, desc.height);
        
        double avgBackground = buddhaResult.accumulator.averageBackgroundHits();
        int backgroundLevel = cast(int)avgBackground;
        
        int minNonZero = buddhaResult.accumulator.minNonZeroHits();
        if (minNonZero > 0 && (backgroundLevel == 0 || minNonZero < backgroundLevel)) {
            backgroundLevel = minNonZero;
        }
        
        int maxLevel = buddhaResult.maxHits;
        
        writeln("\nGenerating Buddhabrot image");
        writeln("  Background level: ", backgroundLevel, " (avg: ", cast(int)avgBackground, 
                ", min: ", minNonZero, ")");
        writeln("  Max level: ", maxLevel);
        stdout.flush();
        
        foreach (x; 0 .. desc.width) {
            for (int y = 0; y < desc.height; y++) {
                buddhaImg[x, y] = computeBuddhaColor(
                    buddhaResult.accumulator.data[x][y], 
                    backgroundLevel,
                    maxLevel
                );
            }
            if (x % wfactor == 0) {
                write('.');
                stdout.flush();
            }
        }
        
        string buddhaPrefix = desc.buddha == BuddhaMode.buddha ? "buddha_" : "antibuddha_";
        writeln("\nSaving: " ~ workdir ~ "/" ~ buddhaPrefix ~ desc.filename ~ ".png");
        
        auto buddhaSaveTimer = StopWatch(AutoStart.yes);
        savePNG(buddhaImg, workdir ~ "/" ~ buddhaPrefix ~ desc.filename ~ ".png");
        buddhaSaveTimer.stop();
        writeln("Save time: ", formatDuration(buddhaSaveTimer.peek()));
    }
    
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
