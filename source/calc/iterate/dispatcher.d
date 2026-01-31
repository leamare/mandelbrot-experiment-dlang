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
import calc.iterate.mpfr_iter : MPFRPixelConverter, iterateMPFR, 
                                 computeReferenceOrbitMPFR, MPFRReferenceOrbit,
                                 iteratePerturbationMPFR, PerturbResult;
import calc.iterate.quaddouble_iter : iterateQuadDouble;
import calc.types.mpfr : GMPFloat, GMPComplex;
import precision.method : shouldUsePerturbation;

alias ProgressCallback = void delegate(int percent);

void iterateAll(
    ref IterResult[][] iters,
    const ref RenderConfig cfg,
    const ref RenderParams desc,
    bool showProgress = true,
    ProgressCallback onProgress = null
) {
    final switch (cfg.precisionMode) {
        case PrecisionMode.standard:
            iterateDoubleMode(iters, cfg, desc, showProgress, onProgress);
            break;
        case PrecisionMode.quaddouble:
            iterateQuadDoubleMode(iters, cfg, desc, showProgress, onProgress);
            break;
        case PrecisionMode.arbitrary:
            iterateMPFRMode(iters, cfg, desc, showProgress, onProgress);
            break;
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

private void iterateQuadDoubleMode(
    ref IterResult[][] iters,
    const ref RenderConfig cfg,
    const ref RenderParams desc,
    bool showProgress,
    ProgressCallback onProgress
) {
    if (showProgress) {
        writeln("Using QuadDouble precision (~62 digits)");
        stdout.flush();
    }
    
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
            iters[i][j] = iterateQuadDouble(i, j, cfg);
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

    auto perturbMode = desc.getPerturbationMode();
    bool usePerturbation = shouldUsePerturbation(
        perturbMode,
        cfg.maxIterations,
        digits,
        cfg.fractalType == FractalType.mandelbrot
    );
    
    if (showProgress) {
        if (cfg.fractalType == FractalType.multibrot) {
            if (cfg.multibrotExp < 0) {
                writeln("Using MPFR negative power for exponent ", cfg.multibrotExp);
            } else if (!gmpOptions.hasIntegerPower) {
                writeln("Using MPFR fractional power (De Moivre's formula) for exponent ", cfg.multibrotExp);
            }
        }
        writeln("Using ", digits, " digit precision for MPFR iteration");
        if (usePerturbation) {
            writeln("Using perturbation theory for acceleration");
        }
        stdout.flush();
    }
    
    string originXStr = desc.originXStr;
    string originYStr = desc.originYStr;
    string radiusStr = desc.radiusStr;
    int width = desc.width;
    int height = desc.height;

    MPFRReferenceOrbit refOrbit;
    if (usePerturbation) {
        if (showProgress) {
            writeln("Computing reference orbit at center...");
            stdout.flush();
        }
        
        refOrbit = computeReferenceOrbitMPFR(
            originXStr,
            originYStr,
            cfg.maxIterations,
            digits,
            cfg.escapeRadius * cfg.escapeRadius,
            true  // Store high precision for potential rebasing
        );
        
        if (showProgress) {
            writeln("Reference orbit: ", refOrbit.refIterations, " iterations, ",
                    refOrbit.escaped ? "escaped" : "in set");
            stdout.flush();
        }
    }
    
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
            if (usePerturbation) {
                auto c = GMPComplex.zero();
                localConverter.pixelToComplex(i, j, c);
                
                auto refCenter = GMPComplex(originXStr, originYStr);
                auto deltaC = GMPComplex.zero();
                deltaC.re = c.re - refCenter.re;
                deltaC.im = c.im - refCenter.im;
                
                auto pr = iteratePerturbationMPFR(deltaC, refOrbit, cfg.maxIterations, 
                                                   cfg.escapeRadius * cfg.escapeRadius);
                
                if (pr.needsRefinement) {
                    iters[i][j] = iterateMPFR(i, j, cfg, localConverter, gmpOptions);
                } else {
                    iters[i][j] = pr.result;
                }
            } else {
                iters[i][j] = iterateMPFR(i, j, cfg, localConverter, gmpOptions);
            }
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

