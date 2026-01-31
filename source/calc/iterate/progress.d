/**
 * Progress-Aware Iteration
 */
module calc.iterate.progress;

import std.stdio : write, writeln, stdout;
import std.file : exists, read, remove;
import std.file : write_ = write;
import std.parallelism : parallel;
import std.range : iota;
import std.math : ceil;
import std.conv : to;
import std.algorithm : min, max;

import cerealed : cerealise, decerealise;

import types.iter_result;
import types.fractal;
import types.render;
import config.params : RenderParams;

import calc.iterate.double_iter : iterateDouble;
import calc.iterate.mpfr_iter : MPFRPixelConverter, iterateMPFR;
import calc.types.mpfr : GMPFloat;
import utils.precision_auto : combinedPrecisionDigits, digitsPerPixel;

void iterateWithProgress(
    ref IterResult[][] iters,
    const ref RenderConfig cfg,
    const ref RenderParams desc,
    int wfactor,
    int saveProgressInterval,
    string workdir
) {
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
        
        writeln("Using ", digits, " digit precision for MPFR iteration");
        stdout.flush();
    }
    
    int loaded = 0;
    string progressFile = workdir ~ "/" ~ desc.filename ~ ".tmp";

    if (exists(progressFile)) {
        writeln("-- Progress data found --");
        auto progdata = cast(const(ubyte)[])read(progressFile);
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
    
    const int blockSize = saveProgressInterval * wfactor;
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
        write_(progressFile, progdata);
        write("! ");
    }
    
    if (exists(progressFile)) {
        remove(progressFile);
    }
}
