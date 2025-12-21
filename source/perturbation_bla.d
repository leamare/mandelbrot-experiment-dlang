module perturbation_bla;

import std.stdio;
import std.math;
import std.conv;
import std.algorithm;
import std.range;
import std.complex;
import std.typecons;
import std.format;

import gmp_arb;
import precision_unified : PrecisionMethod;
import multidouble : MultiDoubleComplex, calculateNumDoubles;
import doubledouble : DDComplex, DoubleDouble;
import bigfloat : BigFloatComplex;

/**
 * Perturbation Theory with BLA (Bivariate Linear Approximation)
 * Based on: https://mathr.co.uk/web/deep-zoom.html
 * 
 * Strategy:
 * 1. Compute ONE high-precision reference orbit at image center (using GMP)
 * 2. For each pixel, iterate deltas using fast double precision
 * 3. Use BLA to skip many iterations when non-linear part is negligible
 * 4. Use rebasing to avoid glitches
 */

/// Reference orbit computed at high precision
struct ReferenceOrbit {
    /// Z_ref values at each iteration (stored as double for fast access)
    Complex!double[] zRef;
    
    /// High precision variants (optional)
    DDComplex[] zRefDoubleDouble;
    BigFloatComplex[] zRefBigFloat;
    MultiDoubleComplex[] zRefMultiDouble;
    GMPComplex[] zRefGMP;
    
    /// Reference point C (high precision, for exact computation)
    GMPComplex cRef;
    
    /// Number of iterations in reference orbit
    int refIterations;
    
    /// Whether reference escaped
    bool escaped;
    
    /// Escape radius squared
    double escapeRadius2 = (1 << 16);
    // double escapeRadius2 = 4.0;  // 2.0^2 = escape radius squared (standard Mandelbrot escape radius is 2.0)
    
    /// Method used for computation
    PrecisionMethod methodUsed = PrecisionMethod.double_;
    
    /// Multi-double component count (if applicable)
    uint multiDoubleComponents = 0;
}

/// BLA (Bivariate Linear Approximation) entry
/// Approximates l iterations: z_{n+l} = A * z_n + B * c
struct BLAEntry {
    int startIter;      // Starting iteration
    int skipCount;      // Number of iterations to skip
    Complex!double A;   // Linear coefficient for z
    Complex!double B;   // Linear coefficient for c
    double radius;      // Validity radius R: valid when |z| < R
    bool hasMultiDouble;              // High-precision coefficients available
    MultiDoubleComplex A_multiDouble; // MultiDouble coefficient for z
    MultiDoubleComplex B_multiDouble; // MultiDouble coefficient for c
}

ReferenceOrbit computeReferenceOrbit(string cRealStr, string cImagStr, uint maxIterations,
                                     PrecisionMethod precisionMethod = PrecisionMethod.auto_) {
    import std.datetime.stopwatch : StopWatch;
    
    debug(gmpdebug) {
        writeln("DEBUG: computeReferenceOrbit called");
        stdout.flush();
    }
    
    // Initialize result - use void and initialize fields manually
    ReferenceOrbit result = void;
    import std.conv : emplace;
    
    // Initialize arrays and other fields first
    result.zRef = [];  // Initialize array
    result.zRefDoubleDouble = [];
    result.zRefBigFloat = [];
    result.zRefMultiDouble = [];
    result.zRefGMP = [];
    result.refIterations = 0;
    result.escaped = false;
    result.methodUsed = precisionMethod;
    result.multiDoubleComponents = 0;
    
    // Construct cRef directly using emplace to avoid default construction
    debug(gmpdebug) {
        writeln("DEBUG: About to create GMPComplex cRef...");
        stdout.flush();
    }
    try {
        // Use emplace to construct cRef directly, avoiding default construction
        debug(gmpdebug) {
            writeln("DEBUG: Emplacing GMPComplex cRef...");
            stdout.flush();
        }
        emplace!GMPComplex(&result.cRef, cRealStr, cImagStr);
        debug(gmpdebug) {
            writeln("DEBUG: GMPComplex cRef created successfully");
            stdout.flush();
        }
    } catch (Exception e) {
        writeln("ERROR: Failed to create GMPComplex: ", e.msg);
        return result;
    }
    
    if (maxIterations == 0) {
        writeln("ERROR: maxIterations is 0");
        return result;
    }
    if (cRealStr.length == 0 || cImagStr.length == 0) {
        writeln("ERROR: Empty coordinate strings");
        return result;
    }
    
    debug(gmpdebug) {
        writeln("DEBUG: Reserving space for zRef array...");
        stdout.flush();
    }
    result.zRef.reserve(maxIterations + 1);
    debug(gmpdebug) {
        writeln("DEBUG: Space reserved, adding initial z=0...");
        stdout.flush();
    }
    result.zRef ~= Complex!double(0, 0);
    debug(gmpdebug) {
        writeln("DEBUG: Initial z added");
        stdout.flush();
    }
    result.refIterations = cast(int)maxIterations;
    const double escapeRadius2 = result.escapeRadius2;
    
    auto method = precisionMethod;
    if (method == PrecisionMethod.auto_) {
        method = PrecisionMethod.double_;
    }
    result.methodUsed = method;
    
    string methodName =
        method == PrecisionMethod.double_ ? "double" :
        method == PrecisionMethod.bigfloat ? "bigfloat" :
        method == PrecisionMethod.multidouble ? "multidouble" :
        method == PrecisionMethod.bigint ? "bigfloat (BigInt)" :
        method == PrecisionMethod.gmp ? "gmp" :
        "double";
    writeln("Computing reference orbit using precision method: ", methodName);
    writeln("  Iterations: ", maxIterations);
    write("Progress: [");
    stdout.flush();
    
    debug(gmpdebug) {
        writeln("DEBUG: About to start switch statement, method=", methodName);
        stdout.flush();
    }
    
    StopWatch timer;
    timer.start();
    int progressInterval = max(1, cast(int)maxIterations / 80);
    int lastPercent = -1;
    
    switch (method) {
        case PrecisionMethod.double_: {
            debug(gmpdebug) {
                writeln("DEBUG: Entering double_ case");
                stdout.flush();
            }
            double zr = 0.0;
            double zi = 0.0;
            debug(gmpdebug) {
                writeln("DEBUG: About to call result.cRef.re.toDouble()...");
                stdout.flush();
            }
            double cr = result.cRef.re.toDouble();
            debug(gmpdebug) {
                writeln("DEBUG: cr = ", cr);
                stdout.flush();
            }
            debug(gmpdebug) {
                writeln("DEBUG: About to call result.cRef.im.toDouble()...");
                stdout.flush();
            }
            double ci = result.cRef.im.toDouble();
            debug(gmpdebug) {
                writeln("DEBUG: ci = ", ci);
                stdout.flush();
            }
            for (uint iter = 0; iter < maxIterations; ++iter) {
                double zrTemp = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = zrTemp;
                result.zRef ~= Complex!double(zr, zi);
                double mag2 = zr * zr + zi * zi;
                if (!result.escaped && mag2 > escapeRadius2) {
                    result.escaped = true;
                    result.refIterations = cast(int)(iter + 1);
                }
                if (iter % progressInterval == 0 || iter == maxIterations - 1) {
                    int percent = cast(int)((iter + 1) * 100 / maxIterations);
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        if (percent % 10 == 0) {
                            write(percent);
                        } else {
                            write('.');
                        }
                        stdout.flush();
                    }
                }
            }
            break;
        }
        case PrecisionMethod.bigfloat: {
            DDComplex cDD = DDComplex(DoubleDouble(cRealStr), DoubleDouble(cImagStr));
            DDComplex zDD = DDComplex(0.0, 0.0);
            result.zRefDoubleDouble.reserve(maxIterations + 1);
            result.zRefDoubleDouble ~= zDD;
            for (uint iter = 0; iter < maxIterations; ++iter) {
                zDD = zDD.square() + cDD;
                result.zRefDoubleDouble ~= zDD;
                double zr = zDD.re.toDouble();
                double zi = zDD.im.toDouble();
                result.zRef ~= Complex!double(zr, zi);
                double mag2 = zr * zr + zi * zi;
                if (!result.escaped && mag2 > escapeRadius2) {
                    result.escaped = true;
                    result.refIterations = cast(int)(iter + 1);
                }
                if (iter % progressInterval == 0 || iter == maxIterations - 1) {
                    int percent = cast(int)((iter + 1) * 100 / maxIterations);
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        if (percent % 10 == 0) {
                            write(percent);
                        } else {
                            write('.');
                        }
                        stdout.flush();
                    }
                }
            }
            break;
        }
        case PrecisionMethod.multidouble: {
            debug(gmpdebug) {
                writeln("DEBUG: Entering multidouble case");
                stdout.flush();
            }
            auto coordLen = max(cRealStr.length, cImagStr.length);
            uint requiredDigits = cast(uint)max(50, coordLen + 20);
            debug(gmpdebug) {
                writeln("DEBUG: requiredDigits = ", requiredDigits);
                stdout.flush();
            }
            uint numDoubles = calculateNumDoubles(requiredDigits);
            debug(gmpdebug) {
                writeln("DEBUG: numDoubles = ", numDoubles);
                stdout.flush();
            }
            result.multiDoubleComponents = numDoubles;
            debug(gmpdebug) {
                writeln("DEBUG: About to create MultiDoubleComplex cMD...");
                stdout.flush();
            }
            auto cMD = MultiDoubleComplex(numDoubles, cRealStr, cImagStr);
            debug(gmpdebug) {
                writeln("DEBUG: MultiDoubleComplex cMD created");
                stdout.flush();
            }
            auto zMD = MultiDoubleComplex(numDoubles, 0.0, 0.0);
            result.zRefMultiDouble.reserve(maxIterations + 1);
            result.zRefMultiDouble ~= zMD;
            for (uint iter = 0; iter < maxIterations; ++iter) {
                zMD.squareAndAdd(cMD);
                result.zRefMultiDouble ~= zMD;
                double zr = zMD.re.toDouble();
                double zi = zMD.im.toDouble();
                result.zRef ~= Complex!double(zr, zi);
                double mag2 = zMD.magnitudeSquared();
                if (!result.escaped && mag2 > escapeRadius2) {
                    result.escaped = true;
                    result.refIterations = cast(int)(iter + 1);
                }
                if (iter % progressInterval == 0 || iter == maxIterations - 1) {
                    int percent = cast(int)((iter + 1) * 100 / maxIterations);
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        if (percent % 10 == 0) {
                            write(percent);
                        } else {
                            write('.');
                        }
                        stdout.flush();
                    }
                }
            }
            break;
        }
        case PrecisionMethod.bigint: {
            auto cBF = BigFloatComplex(cRealStr, cImagStr);
            auto zBF = BigFloatComplex("0", "0");
            result.zRefBigFloat.reserve(maxIterations + 1);
            result.zRefBigFloat ~= zBF;
            for (uint iter = 0; iter < maxIterations; ++iter) {
                zBF.squareAndAdd(cBF);
                result.zRefBigFloat ~= BigFloatComplex(zBF.re, zBF.im);
                double zr = zBF.re.toDouble();
                double zi = zBF.im.toDouble();
                result.zRef ~= Complex!double(zr, zi);
                double mag2 = zBF.magnitudeSquared().toDouble();
                if (!result.escaped && mag2 > escapeRadius2) {
                    result.escaped = true;
                    result.refIterations = cast(int)(iter + 1);
                }
                if (iter % progressInterval == 0 || iter == maxIterations - 1) {
                    int percent = cast(int)((iter + 1) * 100 / maxIterations);
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        if (percent % 10 == 0) {
                            write(percent);
                        } else {
                            write('.');
                        }
                        stdout.flush();
                    }
                }
            }
            break;
        }
        case PrecisionMethod.gmp: {
            debug(gmpdebug) {
                writeln("DEBUG: Creating GMPComplex cHigh...");
                stdout.flush();
            }
            auto cHigh = GMPComplex(cRealStr, cImagStr);
            debug(gmpdebug) {
                writeln("DEBUG: cHigh created successfully");
                stdout.flush();
            }
            
            debug(gmpdebug) {
                writeln("DEBUG: Creating initial z = 0...");
                stdout.flush();
            }
            GMPComplex z = GMPComplex(0.0, 0.0);
            debug(gmpdebug) {
                writeln("DEBUG: z created successfully");
                stdout.flush();
            }
            
            debug(gmpdebug) {
                writeln("DEBUG: Reserving space for ", maxIterations + 1, " orbit points...");
                stdout.flush();
            }
            result.zRefGMP.reserve(maxIterations + 1);
            debug(gmpdebug) {
                writeln("DEBUG: Space reserved");
                stdout.flush();
            }
            
            debug(gmpdebug) {
                writeln("DEBUG: Storing initial z = 0...");
                stdout.flush();
            }
            // Store initial z = 0 (use copy constructor)
            result.zRefGMP ~= GMPComplex(z);
            debug(gmpdebug) {
                writeln("DEBUG: Initial z stored, array length: ", result.zRefGMP.length);
                stdout.flush();
            }
            
            debug(gmpdebug) {
                writeln("DEBUG: Starting iteration loop...");
                stdout.flush();
            }
            for (uint iter = 0; iter < maxIterations; ++iter) {
                debug(gmpdebug) {
                    if (iter == 0) {
                        writeln("DEBUG: First iteration, calling squareAndAdd...");
                        stdout.flush();
                    }
                }
                z.squareAndAdd(cHigh);
                debug(gmpdebug) {
                    if (iter == 0) {
                        writeln("DEBUG: squareAndAdd completed, z.re=", z.re.toString()[0..min(30, z.re.toString().length)], "...");
                        stdout.flush();
                    }
                }
                
                debug(gmpdebug) {
                    if (iter == 0) {
                        writeln("DEBUG: Creating copy of z for array...");
                        stdout.flush();
                    }
                }
                // Use copy constructor to ensure proper copying
                result.zRefGMP ~= GMPComplex(z);
                debug(gmpdebug) {
                    if (iter == 0) {
                        writeln("DEBUG: Copy stored, array length: ", result.zRefGMP.length);
                        stdout.flush();
                    }
                }
                
                double zr = z.re.toDouble();
                double zi = z.im.toDouble();
                result.zRef ~= Complex!double(zr, zi);
                double mag2 = z.magnitudeSquaredDouble();
                if (!result.escaped && mag2 > escapeRadius2) {
                    result.escaped = true;
                    result.refIterations = cast(int)(iter + 1);
                }
                if (iter % progressInterval == 0 || iter == maxIterations - 1) {
                    int percent = cast(int)((iter + 1) * 100 / maxIterations);
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        if (percent % 10 == 0) {
                            write(percent);
                        } else {
                            write('.');
                        }
                        stdout.flush();
                    }
                }
                
                debug(gmpdebug) {
                    if (iter == 0) {
                        writeln("DEBUG: First iteration completed successfully");
                        stdout.flush();
                    }
                }
            }
            debug(gmpdebug) {
                writeln("DEBUG: Iteration loop completed, total iterations: ", maxIterations);
                stdout.flush();
            }
            break;
        }
        default: {
            double zr = 0.0;
            double zi = 0.0;
            double cr = result.cRef.re.toDouble();
            double ci = result.cRef.im.toDouble();
            for (uint iter = 0; iter < maxIterations; ++iter) {
                double zrTemp = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = zrTemp;
                result.zRef ~= Complex!double(zr, zi);
                double mag2 = zr * zr + zi * zi;
                if (!result.escaped && mag2 > escapeRadius2) {
                    result.escaped = true;
                    result.refIterations = cast(int)(iter + 1);
                }
                if (iter % progressInterval == 0 || iter == maxIterations - 1) {
                    int percent = cast(int)((iter + 1) * 100 / maxIterations);
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        if (percent % 10 == 0) {
                            write(percent);
                        } else {
                            write('.');
                        }
                        stdout.flush();
                    }
                }
            }
            break;
        }
    }
    
    writeln("] 100%");
    auto elapsed = timer.peek().total!"seconds";
    writeln("Reference orbit computed in ", format!"%.2f"(elapsed), " s (", 
            format!"%.1f"(cast(double)result.refIterations / elapsed), " iter/s)");
    return result;
}

/// BLA table: collection of approximations
struct BLATable {
    BLAEntry[] entries;
    
    /// Find best BLA entry starting from iteration m
    /// Returns index of entry with largest skip satisfying |z| < R, or -1 if none
    int findBest(int m, double zMag) const {
        return findBestInEntries(entries, m, zMag);
    }
    
    /// Static version that takes entries array directly (thread-safe)
    static int findBestInEntries(const BLAEntry[] entriesArray, int m, double zMag) {
        int bestIdx = -1;
        int bestSkip = 0;
        
        // Cache length locally for thread safety
        const size_t entriesLen = entriesArray.length;
        
        // Iterate with explicit bounds checking
        for (size_t i = 0; i < entriesLen; i++) {
            const BLAEntry entry = entriesArray[i];
            if (entry.startIter == m && zMag < entry.radius) {
                if (entry.skipCount > bestSkip) {
                    bestSkip = entry.skipCount;
                    bestIdx = cast(int)i;
                }
            }
        }
        return bestIdx;
    }
}

/// Compute single-step BLA coefficients
/// For iteration n: z_{n+1} = A_{n,1} * z_n + B_{n,1} * c
/// Valid when |z_n| << |2 * Z_n|
BLAEntry computeSingleStepBLA(const ref ReferenceOrbit ref_, int n) {
    const size_t zRefLen = ref_.zRef.length;
    if (n < 0 || n >= cast(int)zRefLen - 1) {
        BLAEntry entry;
        entry.startIter = n;
        entry.skipCount = 0;
        entry.A = Complex!double(1, 0);
        entry.B = Complex!double(0, 0);
        entry.radius = 0;
        entry.hasMultiDouble = false;
        return entry;
    }
    
    if (n >= 0 && n < cast(int)zRefLen) {
        auto Z_n = ref_.zRef[n];
        auto A = Z_n * 2.0;
        auto B = Complex!double(1, 0);
        
        const double epsilon = 1e-10;
        double A_mag = sqrt(A.re * A.re + A.im * A.im);
        double radius = epsilon * A_mag;
        
        BLAEntry entry;
        entry.startIter = n;
        entry.skipCount = 1;
        entry.A = A;
        entry.B = B;
        entry.radius = radius;
        entry.hasMultiDouble = false;
        if (ref_.zRefMultiDouble.length > n && ref_.multiDoubleComponents > 0) {
            auto Z_md = ref_.zRefMultiDouble[n];
            auto twoMD = MultiDoubleComplex(ref_.multiDoubleComponents, 2.0, 0.0);
            entry.A_multiDouble = Z_md * twoMD;
            entry.B_multiDouble = MultiDoubleComplex(ref_.multiDoubleComponents, 1.0, 0.0);
            entry.hasMultiDouble = true;
        }
        return entry;
    } else {
        BLAEntry entry;
        entry.startIter = n;
        entry.skipCount = 0;
        entry.A = Complex!double(1, 0);
        entry.B = Complex!double(0, 0);
        entry.radius = 0;
        entry.hasMultiDouble = false;
        return entry;
    }
}

/// Merge two BLA entries
/// If T_x skips l_x from m_x and T_y skips l_y from m_x + l_x,
/// then T_z = T_y ∘ T_x skips l_x + l_y from m_x
BLAEntry mergeBLA(const ref BLAEntry x, const ref BLAEntry y) {
    auto A_z = y.A * x.A;
    auto B_z = y.A * x.B + y.B;
    double A_x_mag = sqrt(x.A.re * x.A.re + x.A.im * x.A.im);
    double radius_z = min(x.radius, y.radius / max(A_x_mag, 1e-12));
    radius_z = max(0.0, radius_z);
    
    BLAEntry entry;
    entry.startIter = x.startIter;
    entry.skipCount = x.skipCount + y.skipCount;
    entry.A = A_z;
    entry.B = B_z;
    entry.radius = radius_z;
    entry.hasMultiDouble = x.hasMultiDouble && y.hasMultiDouble;
    if (entry.hasMultiDouble) {
        entry.A_multiDouble = y.A_multiDouble * x.A_multiDouble;
        entry.B_multiDouble = y.A_multiDouble * x.B_multiDouble + y.B_multiDouble;
    }
    return entry;
}

/// Compute reference orbit at high precision
/// Uses unified precision system - can use double, bigfloat, or GMP
/// This is done ONCE per image
BLATable buildBLATable(const ref ReferenceOrbit ref_) {
    import std.parallelism;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    import core.sync.mutex : Mutex;
    
    writeln("Building BLA table...");
    StopWatch timer;
    timer.start();
    
    BLATable table;
    
    if (ref_.zRef.length < 2) {
        return table;  // Need at least 2 points
    }
    
    // Start from iteration 1 (iteration 0 is always non-linear as Z=0)
    // Cache length to avoid repeated access
    const size_t zRefLength = ref_.zRef.length;
    if (zRefLength < 2) {
        writeln("  Skipping BLA table (reference orbit too short)");
        return table;
    }
    
    const int startIter = 1;
    const int M = cast(int)zRefLength - 1;
    
    // Create BLAs for all iterations
    const int numBLAs = M;
    const int stepSize = 1;
    
    writeln("  Creating ", numBLAs, " single-step BLAs...");
    
    // Step 1: Create sampled single-step BLAs in chunks to avoid memory issues
    BLAEntry[] singleSteps;
    
    // Process in chunks to avoid large allocations
    enum int CHUNK_SIZE = 10_000;  // Process 10K at a time
    int numChunks = (numBLAs + CHUNK_SIZE - 1) / CHUNK_SIZE;
    
    // Progress tracking
    import core.sync.mutex : Mutex;
    static Mutex progressMutex;
    static shared bool mutexInitialized = false;
    synchronized {
        if (!mutexInitialized) {
            progressMutex = new Mutex();
            mutexInitialized = true;
        }
    }
    int completed = 0;  // No longer shared since we're sequential
    int lastProgressPercent = -1;
    
    // Build BLAs chunk by chunk
    for (int chunk = 0; chunk < numChunks; chunk++) {
        int chunkStart = chunk * CHUNK_SIZE;
        int chunkEnd = min(chunkStart + CHUNK_SIZE, numBLAs);
        int chunkSize = chunkEnd - chunkStart;
        
        // Allocate chunk
        BLAEntry[] chunkBLAs = new BLAEntry[chunkSize];
        
        // Process chunk sequentially to avoid threading issues
        // Cache zRefLength for safety
        const size_t cachedZRefLength = zRefLength;
        for (int idx = chunkStart; idx < chunkEnd; idx++) {
            int i = startIter + idx * stepSize;
            // Bounds check using cached length
            if (i >= 0 && i < cast(int)cachedZRefLength - 1) {
                chunkBLAs[idx - chunkStart] = computeSingleStepBLA(ref_, i);
            } else {
                // Invalid index - create empty entry
                BLAEntry empty;
                empty.startIter = i;
                empty.skipCount = 0;
                empty.A = Complex!double(1, 0);
                empty.B = Complex!double(0, 0);
                empty.radius = 0;
                chunkBLAs[idx - chunkStart] = empty;
            }
            
            // Update progress
            completed++;
            long percent = (cast(long)completed * 100L) / cast(long)numBLAs;
            
            if (percent != lastProgressPercent && percent >= 0 && percent <= 100 && 
                (completed % max(1, numBLAs / 20) == 0 || completed == numBLAs)) {
                write("  ", cast(int)percent, "%... ");
                stdout.flush();
                lastProgressPercent = cast(int)percent;
            }
        }
        
        // Append chunk to singleSteps
        singleSteps ~= chunkBLAs;
    }
    writeln();
    
    writeln("  Merging BLAs hierarchically...");
    // Step 2: Hierarchical merging (sequential - dependencies between merges)
    // Only store merged entries in the table (not all single steps) to save memory
    BLAEntry[] current = singleSteps;
    // Don't store all single steps - only store merged entries
    // table.entries will be populated during merging
    
    int mergeLevel = 0;
    while (current.length > 1) {
        mergeLevel++;
        BLAEntry[] next;
        next.reserve((current.length + 1) / 2);
        
        // Merge pairs
        for (int i = 0; i < current.length - 1; i += 2) {
            // Check if entries can be merged (consecutive or within stepSize)
            int gap = current[i+1].startIter - (current[i].startIter + current[i].skipCount);
            if (gap >= 0 && gap <= stepSize) {
                // Can merge (consecutive or close enough)
                auto merged = mergeBLA(current[i], current[i+1]);
                next ~= merged;
                table.entries ~= merged;  // Store merged entry
            } else {
                // Can't merge, keep both
                next ~= current[i];
                next ~= current[i+1];
            }
        }
        
        // Handle odd element
        if (current.length % 2 == 1) {
            next ~= current[$ - 1];
        }
        
        if (mergeLevel % 10 == 0 || current.length <= 2) {
            write("  Level ", mergeLevel, " (", current.length, " entries)... ");
            stdout.flush();
        }
        
        current = next;
    }
    writeln();
    
    timer.stop();
    writeln("BLA table built: ", table.entries.length, " entries in ", 
            timer.peek().total!"msecs", " ms");
    
    return table;
}

/// Perturbation iteration result
struct PerturbResult {
    int iterations;
    double smoothed;
    bool glitched;
    bool uncertain;  // True if pixel needs higher precision (delta too small, near boundary, etc.)
}

/// Thread-safe local reference orbit structure
struct LocalReferenceOrbit {
    Complex!double[] zRef;
    double escapeRadius2;
    int refIterations;
}

/// Perform perturbation iteration with BLA (thread-safe version)
/// Uses local copies of reference orbit and BLA entries for thread safety
PerturbResult perturbIterateBLASafe(
    LocalReferenceOrbit ref_,  // Pass by value for thread safety
    const BLAEntry[] blaEntries,
    Complex!double delta0,  // Initial delta (pixel offset from reference)
    uint maxIterations
) {
    PerturbResult result;
    
    // Validate inputs and cache lengths for thread safety
    const Complex!double[] zRefArray = ref_.zRef;  // Already a local copy
    const size_t zRefLength = zRefArray.length;
    const size_t blaEntriesLength = blaEntries.length;
    
    if (zRefLength < 2) {
        // Not enough reference data - return max iterations
        result.iterations = cast(int)maxIterations;
        result.smoothed = cast(double)maxIterations;
        result.glitched = true;  // Mark as glitched since we can't compute properly
        return result;
    }
    
    const double escapeRadius2 = ref_.escapeRadius2;
    const double rebaseThreshold = 1e-10;  // Threshold for rebasing
    int rebaseCount = 0;
    bool glitchDetected = false;
    double delta0Mag2 = delta0.re * delta0.re + delta0.im * delta0.im;
    bool deltaTooSmall = delta0Mag2 < 1e-30;
    
    auto delta = delta0;
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;  // Track if we're using the last reference point
    
    // Now that reference orbit computation continues even after escape,
    // we should have the full reference orbit up to maxIterations.
    // However, if we still run out (shouldn't happen), use last point.
    
    while (iter < maxIterations) {
        // Bounds check before accessing zRef
        if (refIter >= cast(int)maxRefIter) {
            // Ran out of reference orbit - shouldn't happen if computation is correct
            if (maxRefIter == 0) {
                break;  // No reference data at all
            }
            // Use last point and continue
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        
        // Bounds check before accessing zRef
        if (refIter < 0 || refIter >= cast(int)maxRefIter) {
            break;  // Invalid index
        }
        auto zRef = zRefArray[refIter];  // Use local copy
        
        // Check for rebasing: if |Z_ref + delta| < |delta|, rebase
        auto z = zRef + delta;
        double zMag2 = z.re * z.re + z.im * z.im;
        double deltaMag2 = delta.re * delta.re + delta.im * delta.im;

        if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
            result.iterations = iter;
            result.smoothed = cast(double)iter;
            result.glitched = true;
            result.uncertain = true;
            return result;
        }
        
        if (zMag2 < deltaMag2 * rebaseThreshold) {
            // Rebase: replace delta with Z_ref + delta, reset refIter to 0
            delta = z;
            refIter = 0;
            usingLastRef = false;  // Reset flag after rebasing
            rebaseCount++;
            if (rebaseCount > 8) {
                glitchDetected = true;
                break;
            }
            // Bounds check after rebasing
            if (refIter >= cast(int)maxRefIter) {
                break;
            }
            // Get new reference after rebasing (with bounds check)
            if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                break;
            }
            auto newZRef = zRefArray[refIter];  // Use local copy
            z = newZRef + delta;
            zMag2 = z.re * z.re + z.im * z.im;
        }

        if (deltaMag2 > escapeRadius2 * 1e6) {
            glitchDetected = true;
            break;
        }
        
        // Check escape
        if (zMag2 > escapeRadius2) {
            double logZn = log(zMag2) * 0.5;
            double nu = log(logZn / log(2.0)) / log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        
        // Try to use BLA to skip iterations (only if we have more reference data and not using last ref)
        bool useBLA = true;  // Re-enable BLA now that we've fixed the threading issue
        if (useBLA && !usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            double deltaMag = sqrt(deltaMag2);
            int blaIdx = BLATable.findBestInEntries(blaEntries, refIter, deltaMag);
            
            // Double-check bounds before accessing
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                // Use BLA to skip iterations (with bounds check)
                // Cache entry to avoid repeated array access
                const BLAEntry entry = blaEntries[blaIdx];  // Use local copy
                
                // Apply BLA: delta_new = A * delta + B * delta0
                delta = entry.A * delta + entry.B * delta0;
                
                // Advance iterations
                iter += entry.skipCount;
                refIter += entry.skipCount;
                
                // Clamp refIter to valid range
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
            } else {
                // No valid BLA, do regular perturbation step
                // δ_{n+1} = 2·Z_ref_n·δ_n + δ_n² + δ_0
                if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                    break;
                }
                auto currentZRef = zRefArray[refIter];  // Use local copy
                auto twoZref = currentZRef * 2.0;
                delta = (twoZref + delta) * delta + delta0;
                
                iter++;
                if (!usingLastRef) {
                    refIter++;
                    if (refIter >= cast(int)maxRefIter) {
                        refIter = cast(int)maxRefIter - 1;
                        usingLastRef = true;
                    }
                }
            }
        } else {
            // Using last reference point or no more reference data - continue with regular perturbation
            // δ_{n+1} = 2·Z_ref_n·δ_n + δ_n² + δ_0
            if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                break;
            }
            auto currentZRef = zRefArray[refIter];  // Use local copy
            auto twoZref = currentZRef * 2.0;
            delta = (twoZref + delta) * delta + delta0;
            
            iter++;
            // refIter stays at maxRefIter - 1 (usingLastRef = true)
        }
    }
    
    // Didn't escape
    result.iterations = iter;
    result.smoothed = cast(double)iter;
    result.glitched = glitchDetected;
    result.uncertain = glitchDetected || deltaTooSmall || usingLastRef;
    return result;
}

/// Thread-safe version that takes arrays directly (for parallel access)
/// This avoids accessing struct members through references in parallel contexts
/// Arrays should be copies (using .dup) to ensure thread safety
PerturbResult perturbIterateBLAArrays(
    const Complex!double[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    Complex!double delta0,
    uint maxIterations
) {
    PerturbResult result;
    
    const size_t zRefLength = zRefArray.length;
    const size_t blaEntriesLength = blaEntriesArray.length;
    
    if (zRefLength < 2) {
        result.iterations = cast(int)maxIterations;
        result.smoothed = cast(double)maxIterations;
        result.glitched = true;
        result.uncertain = true;  // Mark as uncertain if we don't have enough reference data
        return result;
    }
    
    const double rebaseThreshold = 1e-10;
    int rebaseCount = 0;
    bool glitchDetected = false;
    
    // Check if delta0 is too small - this indicates precision issues
    double delta0Mag2 = delta0.re * delta0.re + delta0.im * delta0.im;
    bool deltaTooSmall = delta0Mag2 < 1e-30;  // Very small delta indicates precision loss
    
    auto delta = delta0;
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;
    
    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) {
                break;
            }
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        
        if (refIter < 0 || refIter >= cast(int)maxRefIter) {
            break;
        }
        Complex!double zRef = zRefArray[refIter];
        
        auto z = zRef + delta;
        double zMag2 = z.re * z.re + z.im * z.im;
        double deltaMag2 = delta.re * delta.re + delta.im * delta.im;
        
        if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
            result.iterations = iter;
            result.smoothed = cast(double)iter;
            result.glitched = true;
            result.uncertain = true;
            return result;
        }
        
        if (zMag2 < deltaMag2 * rebaseThreshold) {
            delta = z;
            refIter = 0;
            usingLastRef = false;
            rebaseCount++;
            if (rebaseCount > 8) {
                glitchDetected = true;
                break;
            }
            if (refIter >= cast(int)maxRefIter) {
                break;
            }
            if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                break;
            }
            Complex!double newZRef = zRefArray[refIter];
            z = newZRef + delta;
            zMag2 = z.re * z.re + z.im * z.im;
        }
        
        if (deltaMag2 > escapeRadius2 * 1e6) {
            glitchDetected = true;
            break;
        }
        
        if (zMag2 > escapeRadius2) {
            double logZn = log(zMag2) * 0.5;
            double nu = log(logZn / log(2.0)) / log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        
        bool usedBLA = false;
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            double deltaMag = sqrt(deltaMag2);
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, deltaMag);
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                double radius = entry.radius;
                if (radius > 0 && deltaMag < radius) {
                    auto nextDelta = entry.A * delta + entry.B * delta0;
                    double nextMag2 = nextDelta.re * nextDelta.re + nextDelta.im * nextDelta.im;
                    if (nextMag2 == nextMag2 && nextMag2 != double.infinity &&
                        nextMag2 < radius * radius * 4) {
                        delta = nextDelta;
                        iter += entry.skipCount;
                        refIter += entry.skipCount;
                        if (refIter >= cast(int)maxRefIter) {
                            refIter = cast(int)maxRefIter - 1;
                            usingLastRef = true;
                        }
                        usedBLA = true;
                    }
                }
            }
        }

        if (!usedBLA) {
            if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                break;
            }
            Complex!double currentZRef = zRefArray[refIter];
            auto twoZref = currentZRef * 2.0;
            delta = (twoZref + delta) * delta + delta0;
            
            iter++;
            if (!usingLastRef) {
                refIter++;
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
            }
        }
    }
    
    result.iterations = iter;
    result.smoothed = cast(double)iter;
    result.glitched = glitchDetected;
    result.uncertain = glitchDetected || deltaTooSmall || usingLastRef;
    return result;
}

private double pow10Clamped(double logVal) {
    // Clamp exponent to the finite range of double precision. Use zeros for
    // extreme underflow and the maximum finite value for overflow so the caller
    // can detect unusable scales.
    enum double MIN_LOG10 = -308.0;
    enum double MAX_LOG10 = 308.0;
    if (logVal < MIN_LOG10) {
        return 0.0;
    }
    if (logVal > MAX_LOG10) {
        return double.max;
    }
    return pow(10.0, logVal);
}

private void renormalizeScaledDelta(ref Complex!double delta,
                                    ref double currentLogScale,
                                    ref double currentScale) {
    // Keep the normalized delta in a numerically stable range by tracking the
    // implicit scale separately. This mirrors the rescale trick from the deep
    // zoom perturbation write-ups: we nudge the mantissa back toward 1 while
    // adjusting the log scale in powers of 10^100.
    enum double SCALE_STEP = 100.0;
    enum double MAX_NORM = 1e100;
    enum double MIN_NORM = 1e-100;
    enum double MAX_NORM2 = MAX_NORM * MAX_NORM;
    enum double MIN_NORM2 = MIN_NORM * MIN_NORM;

    double mag2 = delta.re * delta.re + delta.im * delta.im;

    while (mag2 > MAX_NORM2 && mag2 == mag2 && mag2 != double.infinity) {
        delta = Complex!double(delta.re * MIN_NORM, delta.im * MIN_NORM);
        currentLogScale += SCALE_STEP;
        currentScale = pow10Clamped(currentLogScale);
        mag2 = delta.re * delta.re + delta.im * delta.im;
    }

    while (mag2 > 0.0 && mag2 < MIN_NORM2) {
        delta = Complex!double(delta.re * MAX_NORM, delta.im * MAX_NORM);
        currentLogScale -= SCALE_STEP;
        currentScale = pow10Clamped(currentLogScale);
        mag2 = delta.re * delta.re + delta.im * delta.im;
    }
}

private void addScaledTerm(ref Complex!double accum,
                           ref double accumLogScale,
                           ref double accumScale,
                           Complex!double value,
                           double valueLogScale) {
    // Combine two scaled complex values while keeping their mantissas in a
    // stable range. We bound the log-difference so we never request pow10 with
    // exponents that under/overflow, and fall back to the dominant term when
    // magnitudes differ wildly.
    enum double MAX_LOG_DIFF = 256.0;
    double diff = valueLogScale - accumLogScale;
    if (diff > MAX_LOG_DIFF) {
        accum = value;
        accumLogScale = valueLogScale;
        accumScale = pow10Clamped(accumLogScale);
        renormalizeScaledDelta(accum, accumLogScale, accumScale);
        return;
    }
    if (diff < -MAX_LOG_DIFF) {
        return; // value is negligible compared to accum
    }
    double factor = pow10Clamped(diff);
    if (factor == 0.0) {
        return;
    }
    accum = Complex!double(
        accum.re + value.re * factor,
        accum.im + value.im * factor
    );
    renormalizeScaledDelta(accum, accumLogScale, accumScale);
}

/// Scaled delta iteration with BLA support for extreme zooms
/// Handles deltas that are too small to represent in double precision
PerturbResult perturbIterateBLAScaledArrays(
    const Complex!double[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    Complex!double delta0Normalized,
    double delta0LogScale,
    Complex!double delta0Actual,
    uint maxIterations
) {
    PerturbResult result;
    bool forcedApproximation = false;
    enum int MAX_SCALED_BLA_SKIP = 32;
    import std.process : environment;
    import std.string : format;
    bool tracePixel = "MANDEL_TRACE_PIXEL" in environment;
    const size_t zRefLength = zRefArray.length;
    const size_t blaEntriesLength = blaEntriesArray.length;
    
    if (zRefLength < 2) {
        result.iterations = cast(int)maxIterations;
        result.smoothed = cast(double)maxIterations;
        result.glitched = true;
        result.uncertain = true;  // Mark as uncertain if we don't have enough reference data
        return result;
    }
    
    const double rebaseThreshold = 1e-10;
    const double logRebaseThreshold = std.math.log10(rebaseThreshold);
    auto delta = delta0Normalized;
    const Complex!double delta0Norm = delta0Normalized;
    const Complex!double delta0Exact = delta0Actual;
    double currentLogScale = delta0LogScale;
    double currentScale = pow10Clamped(currentLogScale);
    renormalizeScaledDelta(delta, currentLogScale, currentScale);
    int lastRebaseIter = -1000000;
    
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;
    
    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) {
                break;
            }
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        
        if (refIter < 0 || refIter >= cast(int)maxRefIter) {
            break;
        }
        Complex!double zRef = zRefArray[refIter];
        double refMag2 = zRef.re * zRef.re + zRef.im * zRef.im;

        renormalizeScaledDelta(delta, currentLogScale, currentScale);
        bool haveScale = currentScale != 0.0 && currentScale == currentScale && currentScale != double.max;
        bool scaleUsable = haveScale && currentScale > 0.0;
        Complex!double deltaActual = scaleUsable
            ? Complex!double(delta.re * currentScale, delta.im * currentScale)
            : Complex!double(0.0, 0.0);
        double deltaMag2Actual = scaleUsable
            ? deltaActual.re * deltaActual.re + deltaActual.im * deltaActual.im
            : 0.0;
        double logDeltaMag2Actual = scaleUsable
            ? std.math.log10(max(deltaMag2Actual, 1e-300))
            : -double.infinity;
        if (!scaleUsable) forcedApproximation = true;
        
        auto z = scaleUsable ? (zRef + deltaActual) : zRef;
        double zMag2 = scaleUsable ? (z.re * z.re + z.im * z.im) : refMag2;
        
        if (tracePixel && iter % 128 == 0) {
            import std.stdio : writeln;
            writeln("[scaled] iter=", iter,
                    " logScale=", currentLogScale,
                    " |deltaActual|=", sqrt(deltaMag2Actual));
        }

        if (zMag2 > escapeRadius2) {
            double logZn = std.math.log(zMag2) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;  // Escaped pixels are certain
            return result;
        }
        
        bool shouldRebase = false;
        if (!scaleUsable || deltaMag2Actual == 0 || deltaMag2Actual != deltaMag2Actual) {
            shouldRebase = true;
        } else if (zMag2 < deltaMag2Actual * rebaseThreshold) {
            shouldRebase = true;
        } else {
            double growthOrders = (logDeltaMag2Actual * 0.5) - delta0LogScale;
            if (growthOrders > 10.0 && iter - lastRebaseIter > 4) { // ~1e10 relative growth
                shouldRebase = true;
            }
        }
        if (shouldRebase) {
            if (scaleUsable && currentScale != 0.0) {
                delta = Complex!double(deltaActual.re / currentScale, deltaActual.im / currentScale);
            } else {
                delta = Complex!double(0.0, 0.0);
                currentLogScale = delta0LogScale;
                currentScale = pow10Clamped(currentLogScale);
            }
            renormalizeScaledDelta(delta, currentLogScale, currentScale);
            refIter = 0;
            usingLastRef = false;
            lastRebaseIter = iter;
            continue;
        }
        // If perturbation is blowing up, rebase instead of bailing out early
        if (deltaMag2Actual > escapeRadius2 * 1e4) {
            if (iter - lastRebaseIter > 2) {
                lastRebaseIter = iter;
                delta = Complex!double(deltaActual.re / currentScale, deltaActual.im / currentScale);
                renormalizeScaledDelta(delta, currentLogScale, currentScale);
                refIter = 0;
                usingLastRef = false;
                continue;
            }
        }
        
        double deltaMagActual = sqrt(deltaMag2Actual);
        
        // Disable BLA when we're in deep scaled territory; it tends to skip over
        // the region where we need rebasing the most.
        bool usedBLA = false;
        bool allowBLA = scaleUsable && currentLogScale > -12.0;
        if (allowBLA &&
            !usingLastRef && refIter + 1 < cast(int)maxRefIter &&
            blaEntriesLength > 0 && deltaMagActual > 0) {
            int blaIdx = BLATable.findBestInEntries(
                blaEntriesArray, refIter, deltaMagActual
            );
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];

                if (entry.skipCount <= MAX_SCALED_BLA_SKIP) {
                    double radius = entry.radius;
                    if (radius > 0 && deltaMagActual < radius) {
                        auto nextDeltaActual = entry.A * deltaActual + entry.B * delta0Exact;
                        double nextMagActual = hypot(nextDeltaActual.re, nextDeltaActual.im);
                        if (nextMagActual == nextMagActual &&
                            nextMagActual != double.infinity &&
                            nextMagActual < radius * 4) {
                            delta = Complex!double(
                                nextDeltaActual.re / currentScale,
                                nextDeltaActual.im / currentScale
                            );
                            renormalizeScaledDelta(delta, currentLogScale, currentScale);
                            iter += entry.skipCount;
                            refIter += entry.skipCount;
                            if (refIter >= cast(int)maxRefIter) {
                                refIter = cast(int)maxRefIter - 1;
                                usingLastRef = true;
                            }
                            usedBLA = true;
                            continue;
                        }

                    }
                }
            }
        }
        
        if (!usedBLA) {
            if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                break;
            }
            Complex!double currentZRef = zRefArray[refIter];
            auto twoZref = currentZRef * 2.0;
            
            // Use scaled accumulation to avoid underflow of the quadratic term:
            // δ_{n+1} = 2 Z_ref δ + δ^2 + δ0, but δ and δ0 may be extremely small.
            // Represent all terms as mantissa + logScale and add them safely.
            Complex!double accum = Complex!double(
                (twoZref.re * deltaActual.re - twoZref.im * deltaActual.im) / currentScale,
                (twoZref.re * deltaActual.im + twoZref.im * deltaActual.re) / currentScale
            );
            double accumLogScale = currentLogScale;
            double accumScale = currentScale;

            // Quadratic term uses normalized delta with doubled scale.
            auto deltaSqNorm = Complex!double(
                delta.re * delta.re - delta.im * delta.im,
                2.0 * delta.re * delta.im
            );
            addScaledTerm(accum, accumLogScale, accumScale, deltaSqNorm, currentLogScale * 2.0);

            // Add delta0 in the same scaled units as accum
            auto delta0Scaled = Complex!double(delta0Exact.re / currentScale, delta0Exact.im / currentScale);
            addScaledTerm(accum, accumLogScale, accumScale, delta0Scaled, currentLogScale);

            delta = accum;
            currentLogScale = accumLogScale;
            currentScale = pow10Clamped(currentLogScale);
            renormalizeScaledDelta(delta, currentLogScale, currentScale);


            iter++;
            if (!usingLastRef) {
                refIter++;
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
            }
        }
    }
    
    result.iterations = iter;
    result.smoothed = cast(double)iter;
    result.glitched = true;
    result.uncertain = true;
    return result;
}

/// Perform perturbation iteration with BLA (wrapper for compatibility)
/// Uses reference orbit and BLA table to iterate pixel deltas efficiently
PerturbResult perturbIterateBLA(
    const ref ReferenceOrbit ref_,
    const ref BLATable blaTable,
    Complex!double delta0,  // Initial delta (pixel offset from reference)
    uint maxIterations
) {
    // Extract arrays and call thread-safe version
    return perturbIterateBLAArrays(
        ref_.zRef, ref_.escapeRadius2, blaTable.entries, delta0, maxIterations
    );
}
