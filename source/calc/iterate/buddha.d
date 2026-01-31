/**
 * Buddhabrot Iteration
 */
module calc.iterate.buddha;

import std.stdio : write, writeln, stdout;
import std.parallelism : parallel, totalCPUs;
import std.range : iota;
import std.math : ceil;
import std.conv : to;
import std.algorithm : min, max;

import types.iter_result;
import types.fractal;
import types.render;
import config.params : RenderParams;

import calc.iterate.double_iter : iterateWithOrbit, complexToPixel;
import calc.iterate.mpfr_iter : MPFRPixelConverter, MPFROrbitResult, iterateMPFRWithOrbit;
import calc.types.mpfr : GMPFloat;
import calc.buddha : BuddhaAccumulator;
import utils.precision_auto : combinedPrecisionDigits, digitsPerPixel;

struct BuddhaResult {
    IterResult[][] iterations;
    BuddhaAccumulator accumulator;
    int maxHits;
}

BuddhaResult iterateBuddhabrot(
    ref IterResult[][] iters,
    const ref RenderConfig cfg,
    const ref RenderParams desc,
    int wfactor
) {
    BuddhaResult result;
    
    bool useMPFR = cfg.precisionMode == PrecisionMode.arbitrary;
    
    uint digits = 50;
    GMPFractalOptions gmpOptions;
    string originXStr, originYStr, radiusStr;
    
    if (useMPFR) {
        uint baseDigits = combinedPrecisionDigits(
            desc.originXStr, desc.originYStr, desc.radiusStr, desc.radius
        );
        double perPixelDigits = digitsPerPixel(
            desc.radius, desc.width, desc.height, desc.radiusStr
        );
        uint perPixelRequired = perPixelDigits > 0
            ? cast(uint)ceil(perPixelDigits + 20.0)
            : 0;
        digits = max(baseDigits, perPixelRequired);
        
        GMPFloat.setPrecisionDigits(digits);
        gmpOptions = determineGMPFractalOptions(cfg.multibrotExp);
        
        originXStr = desc.originXStr;
        originYStr = desc.originYStr;
        radiusStr = desc.radiusStr;
        
        writeln("Using MPFR precision (", digits, " digits) for Buddhabrot orbit tracking");
        stdout.flush();
    }
    
    result.accumulator = BuddhaAccumulator(desc.width, desc.height);
    
    auto numThreads = totalCPUs;
    int[][] localBuffers;
    localBuffers.length = numThreads;
    
    foreach (i; 0 .. numThreads) {
        localBuffers[i] = new int[](desc.width * desc.height);
        localBuffers[i][] = 0;
    }
    
    writeln("Using ", numThreads, " threads for Buddhabrot");
    
    int width = desc.width;
    int height = desc.height;
    
    auto wRange = iota(0, width);
    foreach (x; parallel(wRange)) {
        auto tid = x % numThreads;
        
        if (useMPFR) {
            GMPFloat.setPrecisionDigits(digits);
            
            auto localConverter = MPFRPixelConverter(
                width, height,
                originXStr, originYStr, radiusStr
            );
            
            for (int y = 0; y < height; y++) {
                auto orbitResult = iterateMPFRWithOrbit(x, y, cfg, localConverter, gmpOptions);
                iters[x][y] = orbitResult.iter;
                
                bool shouldAccumulate = (desc.buddha == BuddhaMode.antibuddha) || 
                                        (orbitResult.iter.iterations < cfg.maxIterations);
                
                if (shouldAccumulate) {
                    foreach (point; orbitResult.orbit) {
                        auto pixel = localConverter.complexToPixel(point[0], point[1]);
                        int px = pixel[0];
                        int py = pixel[1];
                        if (px >= 0 && px < width && py >= 0 && py < height) {
                            localBuffers[tid][px * height + py]++;
                        }
                    }
                }
            }
        } else {
            for (int y = 0; y < height; y++) {
                auto orbitResult = iterateWithOrbit(x, y, cfg);
                iters[x][y] = orbitResult.iter;
                
                bool shouldAccumulate = (desc.buddha == BuddhaMode.antibuddha) || 
                                        (orbitResult.iter.iterations < cfg.maxIterations);
                
                if (shouldAccumulate) {
                    foreach (point; orbitResult.orbit) {
                        auto pixel = complexToPixel(point[0], point[1], cfg);
                        int px = pixel[0];
                        int py = pixel[1];
                        if (px >= 0 && px < width && py >= 0 && py < height) {
                            localBuffers[tid][px * height + py]++;
                        }
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
        foreach (x; 0 .. width) {
            foreach (y; 0 .. height) {
                result.accumulator.data[x][y] += localBuffers[tid][x * height + y];
            }
        }
    }
    
    result.maxHits = result.accumulator.maxHits();
    result.iterations = iters;
    
    long totalHits = 0;
    int nonZeroPixels = 0;
    foreach (x; 0 .. width) {
        foreach (y; 0 .. height) {
            int hits = result.accumulator.data[x][y];
            totalHits += hits;
            if (hits > 0) nonZeroPixels++;
        }
    }
    
    writeln("Buddhabrot stats:");
    writeln("  Max hits per pixel: ", result.maxHits);
    writeln("  Total hits: ", totalHits);
    writeln("  Non-zero pixels: ", nonZeroPixels, " / ", width * height, 
            " (", cast(double)nonZeroPixels * 100.0 / (width * height), "%)");
    if (nonZeroPixels > 0) {
        writeln("  Avg hits per non-zero pixel: ", cast(double)totalHits / nonZeroPixels);
    }
    stdout.flush();
    
    return result;
}

