module calc.iterate.dispatcher;

import std.stdio : write, writeln, stdout;
import std.parallelism : parallel;
import std.range : iota;
import core.atomic;

import types.iter_result;
import types.fractal;
import types.render;
import config.params : RenderParams;

import calc.iterate.double_iter : iterateDouble;
import calc.iterate.mpfr_iter : MPFRPixelConverter, iterateMPFR;
import calc.types.mpfr : GMPFloat;

alias ProgressCallback = void delegate(int percent);

void iterateAll(
    ref IterResult[][] iters,
    const ref RenderConfig cfg,
    const ref RenderParams desc,
    bool showProgress = true,
    ProgressCallback onProgress = null
) {
    if (cfg.precisionMode == PrecisionMode.arbitrary) {
        iterateMPFRMode(iters, cfg, desc, showProgress, onProgress);
    } else {
        iterateDoubleMode(iters, cfg, desc, showProgress, onProgress);
    }
}

private void iterateDoubleMode(
    ref IterResult[][] iters,
    const ref RenderConfig cfg,
    const ref RenderParams desc,
    bool showProgress,
    ProgressCallback onProgress
) {
    shared int completedColumns = 0;
    int totalColumns = desc.width;
    shared int lastMilestone = 0;
    
    if (showProgress) {
        write("Progress: 0%");
        stdout.flush();
    }
    
    auto wRange = iota(0, desc.width);
    foreach (i; parallel(wRange)) {
        for (int j = 0; j < desc.height; j++) {
            iters[i][j] = iterateDouble(i, j, cfg);
        }
        
        int completed = atomicOp!"+="(completedColumns, 1);
        int percent = cast(int)((cast(long)completed * 100) / totalColumns);
        int milestone = percent / 5 * 5;
        int oldMilestone = atomicLoad(lastMilestone);
        if (milestone > oldMilestone && milestone <= 100) {
            import core.atomic : cas;
            if (cas(&lastMilestone, oldMilestone, milestone)) {
                if (showProgress) {
                    write(" ", milestone, "%");
                    stdout.flush();
                }
                if (onProgress !is null) onProgress(milestone);
            }
        }
    }
    
    if (showProgress) writeln();
}

private void iterateMPFRMode(
    ref IterResult[][] iters,
    const ref RenderConfig cfg,
    const ref RenderParams desc,
    bool showProgress,
    ProgressCallback onProgress
) {
    import std.math : ceil;
    import std.algorithm : max;
    import utils.precision_auto : combinedPrecisionDigits, digitsPerPixel;
    
    uint baseDigits = combinedPrecisionDigits(
        desc.originXStr, desc.originYStr, desc.radiusStr, desc.radius
    );
    double perPixelDigits = digitsPerPixel(
        desc.radius, desc.width, desc.height, desc.radiusStr
    );
    uint perPixelRequired = perPixelDigits > 0
        ? cast(uint)ceil(perPixelDigits + 20.0)
        : 0;
    uint digits = max(baseDigits, perPixelRequired);
    
    GMPFloat.setPrecisionDigits(digits);
    
    auto gmpOptions = determineGMPFractalOptions(cfg.multibrotExp);
    
    if (showProgress) {
        if (cfg.fractalType == FractalType.multibrot) {
            if (cfg.multibrotExp < 0) {
                writeln("Using MPFR negative power for exponent ", cfg.multibrotExp);
            } else if (!gmpOptions.hasIntegerPower) {
                writeln("Using MPFR fractional power (De Moivre's formula) for exponent ", cfg.multibrotExp);
            }
        }
        writeln("Using ", digits, " digit precision for MPFR iteration");
        stdout.flush();
    }
    
    string originXStr = desc.originXStr;
    string originYStr = desc.originYStr;
    string radiusStr = desc.radiusStr;
    int width = desc.width;
    int height = desc.height;
    
    shared int completedColumns = 0;
    int totalColumns = width;
    shared int lastMilestone = 0;
    
    if (showProgress) {
        write("Progress: 0%");
        stdout.flush();
    }
    
    auto wRange = iota(0, desc.width);
    foreach (i; parallel(wRange)) {
        GMPFloat.setPrecisionDigits(digits);
        
        auto localConverter = MPFRPixelConverter(
            width, height,
            originXStr, originYStr, radiusStr
        );
        
        for (int j = 0; j < height; j++) {
            iters[i][j] = iterateMPFR(i, j, cfg, localConverter, gmpOptions);
        }
        
        int completed = atomicOp!"+="(completedColumns, 1);
        int percent = cast(int)((cast(long)completed * 100) / totalColumns);
        int milestone = percent / 5 * 5;
        int oldMilestone = atomicLoad(lastMilestone);
        if (milestone > oldMilestone && milestone <= 100) {
            import core.atomic : cas;
            if (cas(&lastMilestone, oldMilestone, milestone)) {
                if (showProgress) {
                    write(" ", milestone, "%");
                    stdout.flush();
                }
                if (onProgress !is null) onProgress(milestone);
            }
        }
    }
    
    if (showProgress) writeln();
}

