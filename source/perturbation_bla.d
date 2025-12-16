module perturbation_bla;

import std.stdio;
import std.math;
import std.conv;
import std.algorithm;
import std.range;
import std.complex;
import std.typecons;

import gmp_arb;
import precision_unified : PrecisionMethod;
import multidouble : MultiDoubleComplex, calculateNumDoubles;
import bigfloat : DDComplex;

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
    
    /// Reference point C (high precision, for exact computation)
    GMPComplex cRef;
    
    /// Number of iterations in reference orbit
    int refIterations;
    
    /// Whether reference escaped
    bool escaped;
    
    /// Escape radius squared
    double escapeRadius2 = (1 << 16);
}

/// BLA (Bivariate Linear Approximation) entry
/// Approximates l iterations: z_{n+l} = A * z_n + B * c
struct BLAEntry {
    int startIter;      // Starting iteration
    int skipCount;      // Number of iterations to skip
    Complex!double A;   // Linear coefficient for z
    Complex!double B;   // Linear coefficient for c
    double radius;      // Validity radius R: valid when |z| < R
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
            // Copy entry to avoid potential issues with parallel access
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

/// Compute reference orbit at high precision
/// Uses unified precision system - can use double, bigfloat, or GMP
/// This is done ONCE per image
ReferenceOrbit computeReferenceOrbit(string cRealStr, string cImagStr, uint maxIterations, 
                                     PrecisionMethod precisionMethod = PrecisionMethod.auto_) {
    import precision_unified : PrecisionMethod, UnifiedComplex, createUnifiedComplex, selectPrecisionMethod;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    
    ReferenceOrbit result;
    
    // Validate inputs
    if (maxIterations == 0) {
        writeln("ERROR: maxIterations is 0");
        return result;
    }
    
    if (cRealStr.length == 0 || cImagStr.length == 0) {
        writeln("ERROR: Empty coordinate strings");
        return result;
    }
    
    // Try to create GMPComplex - catch any errors
    try {
        result.cRef = GMPComplex(cRealStr, cImagStr);
    } catch (Exception e) {
        writeln("ERROR: Failed to create GMPComplex: ", e.msg);
        return result;
    }
    
    // Validate GMPComplex was created successfully
    try {
        double testRe = result.cRef.re.toDouble();
        double testIm = result.cRef.im.toDouble();
        // Debug output removed for production
    } catch (Exception e) {
        writeln("ERROR: Failed to convert GMPComplex to double: ", e.msg);
        return result;
    }
    
    result.zRef.reserve(maxIterations + 1);
    
    // Store initial Z_ref = 0
    result.zRef ~= Complex!double(0, 0);
    
    // Ensure we have at least one point
    if (result.zRef.length == 0) {
        writeln("ERROR: Failed to initialize reference orbit");
        return result;
    }
    
    const double escapeRadius2 = result.escapeRadius2;
    const double maxDoubleMag2 = 1e200;  // Switch to higher precision when values get this large
    
    // Determine required digits for multidouble if needed
    uint requiredDigits = 0;
    if (precisionMethod == PrecisionMethod.multidouble) {
        auto coordLen = max(cRealStr.length, cImagStr.length);
        requiredDigits = cast(uint)max(50, coordLen + 20);
    }
    
    // Initialize precision-specific variables
    double zr = 0.0;
    double zi = 0.0;
    double cr, ci;
    DDComplex zDD, cDD;
    MultiDoubleComplex zMD, cMD;
    bool usingBigFloat = (precisionMethod == PrecisionMethod.bigfloat);
    bool usingMultiDouble = (precisionMethod == PrecisionMethod.multidouble);
    
    if (usingBigFloat) {
        try {
            cr = result.cRef.re.toDouble();
            ci = result.cRef.im.toDouble();
            cDD = DDComplex(cr, ci);
            zDD = DDComplex(0.0, 0.0);
        } catch (Exception e) {
            writeln("ERROR: Failed to initialize bigfloat: ", e.msg);
            return result;
        }
    } else if (usingMultiDouble) {
        try {
            cr = result.cRef.re.toDouble();
            ci = result.cRef.im.toDouble();
            uint numDoubles = calculateNumDoubles(requiredDigits);
            cMD = MultiDoubleComplex(numDoubles, cr, ci);
            zMD = MultiDoubleComplex(numDoubles, 0.0, 0.0);
        } catch (Exception e) {
            writeln("ERROR: Failed to initialize multidouble: ", e.msg);
            return result;
        }
    } else {
        // Standard double precision
        try {
            cr = result.cRef.re.toDouble();
            ci = result.cRef.im.toDouble();
        } catch (Exception e) {
            writeln("ERROR: Failed to convert cRef to double: ", e.msg);
            return result;
        }
    }
    
    writeln("Computing reference orbit using precision method: ", 
            precisionMethod == PrecisionMethod.double_ ? "double" :
            precisionMethod == PrecisionMethod.bigfloat ? "bigfloat" :
            precisionMethod == PrecisionMethod.multidouble ? "multidouble" :
            precisionMethod == PrecisionMethod.gmp ? "gmp" : "auto");
    write("Progress: ");
    stdout.flush();
    
    int iter;
    int progressInterval = max(1, cast(int)maxIterations / 50);  // More frequent updates
    int lastPercent = -1;
    bool usingGMP = false;
    GMPComplex zGMP;
    StopWatch timer;
    timer.start();
    auto lastTime = timer.peek();
    
    // Synchronize progress output to prevent thread interference
    import core.sync.mutex : Mutex;
    static Mutex progressMutex;
    static shared bool mutexInitialized = false;
    synchronized {
        if (!mutexInitialized) {
            progressMutex = new Mutex();
            mutexInitialized = true;
        }
    }
    
    // Track if we've escaped to optimize post-escape computation
    bool hasEscaped = false;
    
    for (iter = 0; iter < maxIterations; iter++) {
        // Iterate using selected precision method
        if (usingBigFloat) {
            // BigFloat (double-double) iteration
            zDD = zDD.square() + cDD;
            double zrDD = zDD.re.toDouble();
            double ziDD = zDD.im.toDouble();
            double mag2 = zrDD * zrDD + ziDD * ziDD;
            result.zRef ~= Complex!double(zrDD, ziDD);
            
            if (mag2 > escapeRadius2 && !result.escaped) {
                result.escaped = true;
                result.refIterations = iter + 1;
                hasEscaped = true;
            }
            
            // Check if we need to switch to GMP (only if precisionMethod is gmp)
            bool shouldSwitch = mag2 > maxDoubleMag2 || (iter > 5000 && mag2 < escapeRadius2 && (maxIterations - iter) > 2000);
            if (shouldSwitch && precisionMethod == PrecisionMethod.gmp) {
                usingGMP = true;
                try {
                    zGMP = GMPComplex(zrDD, ziDD);
                    writeln("\nSwitching to GMP at iteration ", iter);
                    write("GMP Progress: ");
                    stdout.flush();
                } catch (Exception e) {
                    writeln("\nERROR: Failed to switch to GMP: ", e.msg);
                    usingGMP = false;
                }
            }
        } else if (usingMultiDouble) {
            // MultiDouble iteration
            zMD.squareAndAdd(cMD);
            double mag2 = zMD.magnitudeSquared();  // Use full precision magnitude squared
            double zrMD = zMD.re.toDouble();
            double ziMD = zMD.im.toDouble();
            result.zRef ~= Complex!double(zrMD, ziMD);
            
            if (mag2 > escapeRadius2 && !result.escaped) {
                result.escaped = true;
                result.refIterations = iter + 1;
                hasEscaped = true;
            }
            
            // Check if we need to switch to GMP (only if precisionMethod is gmp)
            bool shouldSwitch = mag2 > maxDoubleMag2 || (iter > 5000 && mag2 < escapeRadius2 && (maxIterations - iter) > 2000);
            if (shouldSwitch && precisionMethod == PrecisionMethod.gmp) {
                usingGMP = true;
                try {
                    zGMP = GMPComplex(zrMD, ziMD);
                    writeln("\nSwitching to GMP at iteration ", iter);
                    write("GMP Progress: ");
                    stdout.flush();
                } catch (Exception e) {
                    writeln("\nERROR: Failed to switch to GMP: ", e.msg);
                    usingGMP = false;
                }
            }
        } else if (!usingGMP) {
            // Fast double precision iteration
            double zrTemp = zr * zr - zi * zi + cr;
            zi = 2.0 * zr * zi + ci;
            zr = zrTemp;
            
            double mag2 = zr * zr + zi * zi;
            
            // Store as double
            result.zRef ~= Complex!double(zr, zi);
            
            // Check escape - but continue computing even after escape
            // This is important for perturbation: we need the full reference orbit
            // even if it escapes, so we can accurately compute pixel variations
            if (mag2 > escapeRadius2 && !result.escaped) {
                result.escaped = true;
                result.refIterations = iter + 1;
                hasEscaped = true;
                // Don't break - continue computing to maxIterations
                // This ensures we have the full reference orbit for perturbation
            }
            
            // Switch to higher precision if magnitude is huge or deep iteration
            // CRITICAL: Only switch to GMP if precisionMethod is explicitly GMP
            // If precisionMethod is bigfloat or double, NEVER switch to GMP (respect user's choice)
            bool shouldSwitch = mag2 > maxDoubleMag2 || (iter > 5000 && mag2 < escapeRadius2 && (maxIterations - iter) > 2000);
            
            // ONLY switch to GMP if precisionMethod is explicitly GMP (not bigfloat, not double, not auto that selected bigfloat)
            if (shouldSwitch && precisionMethod == PrecisionMethod.gmp) {
                usingGMP = true;
                try {
                    zGMP = GMPComplex(zr, zi);
                    writeln("\nSwitching to GMP at iteration ", iter);
                    write("GMP Progress: ");
                    stdout.flush();
                } catch (Exception e) {
                    writeln("\nERROR: Failed to switch to GMP at iteration ", iter, ": ", e.msg);
                    writeln("Continuing with double precision (may lose precision)");
                    usingGMP = false;
                }
            }
            // If precisionMethod is bigfloat or double, we NEVER switch - stay with double precision
            // This respects the user's forced precision choice
        } else {
            // GMP iteration (slower, but necessary for precision)
            // Note: If precisionMethod is bigfloat, we should use bigfloat here, but for now use GMP
            try {
                zGMP.squareAndAdd(result.cRef);
                
                // Store every point - we need the full orbit for perturbation
                // CRITICAL: After escape, we still need to store the actual values
                // because scaled delta iteration needs to check if reference has escaped
                double zrGMP, ziGMP;
                try {
                    zrGMP = zGMP.re.toDouble();
                    ziGMP = zGMP.im.toDouble();
                } catch (Exception e) {
                    writeln("\nERROR: Failed to convert GMP to double at iteration ", iter, ": ", e.msg);
                    break;
                }
                result.zRef ~= Complex!double(zrGMP, ziGMP);
            } catch (Exception e) {
                writeln("\nERROR: GMP iteration failed at iteration ", iter, ": ", e.msg);
                break;  // Can't continue
            }
            
            // AGGRESSIVE OPTIMIZATION: Check escape much less frequently after escape
            // Before escape: check every 10 iterations (need to know when it escapes)
            // After escape: check every 500 iterations (just to confirm, no action needed)
            int checkInterval = result.escaped ? 500 : 10;
            if (iter % checkInterval == 0 || iter == maxIterations - 1) {
                // Use a fast magnitude check that avoids toDouble() when possible
                // For escaped orbits, we can skip the check entirely
                if (!result.escaped) {
                    double mag2 = zGMP.magnitudeSquaredDouble();
                    if (mag2 > escapeRadius2) {
                        result.escaped = true;
                        result.refIterations = iter + 1;
                        hasEscaped = true;
                        writeln("\nReference escaped at iteration ", iter + 1, " (continuing to ", maxIterations, ")");
                        write("Progress: ");
                        stdout.flush();
                        // Don't break - continue to maxIterations
                    }
                }
            }
        }
        
        // Progress indication with time estimates (synchronized to prevent thread interference)
        if (iter % progressInterval == 0 || iter == maxIterations - 1) {
            // Use long to prevent integer overflow
            long percent = (cast(long)iter * 100L) / cast(long)maxIterations;
            synchronized (progressMutex) {
                // Check inside synchronized block to prevent race conditions
                if (percent != lastPercent && percent >= 0 && percent <= 100) {
                    auto currentTime = timer.peek();
                    auto elapsed = currentTime - lastTime;
                    
                    if (elapsed.total!"msecs" > 1000) {  // Only show time if > 1 second
                        write(cast(int)percent, "% ");
                        stdout.flush();
                        lastTime = currentTime;
                    } else {
                        write(cast(int)percent, "% ");
                        stdout.flush();
                    }
                    lastPercent = cast(int)percent;
                }
            }
        }
    }
    
    timer.stop();
    
    if (!result.escaped) {
        result.refIterations = cast(int)maxIterations;
    }
    
    // Validate that we have enough points for perturbation
    if (result.zRef.length < 2) {
        writeln("WARNING: Reference orbit has only ", result.zRef.length, " point(s), need at least 2");
    }
    
    writeln();  // New line after progress
    writeln("Reference orbit computed: ", result.refIterations, " iterations (", 
            result.zRef.length, " points) in ", timer.peek().total!"seconds", " seconds");
    
    return result;
}

/// Compute single-step BLA coefficients
/// For iteration n: z_{n+1} = A_{n,1} * z_n + B_{n,1} * c
/// Valid when |z_n| << |2 * Z_n|
BLAEntry computeSingleStepBLA(const ref ReferenceOrbit ref_, int n) {
    // Cache length for thread safety
    const size_t zRefLen = ref_.zRef.length;
    
    // Bounds check to prevent segfault
    if (n < 0 || n >= cast(int)zRefLen - 1) {
        // Can't compute BLA for invalid or last iteration
        BLAEntry entry;
        entry.startIter = n;
        entry.skipCount = 0;
        entry.A = Complex!double(1, 0);
        entry.B = Complex!double(0, 0);
        entry.radius = 0;
        return entry;
    }
    
    // A_{n,1} = 2 * Z_n
    // B_{n,1} = 1
    // Double-check bounds before access
    if (n >= 0 && n < cast(int)zRefLen) {
        auto Z_n = ref_.zRef[n];
        auto A = Z_n * 2.0;
        auto B = Complex!double(1, 0);
        
        // Validity radius: R = ε * |A| - |B| * |c| / |A|
        // Simplified: R = ε * |A| (assuming c is small)
        const double epsilon = 1e-10;  // Negligibility threshold
        double A_mag = sqrt(A.re * A.re + A.im * A.im);
        double radius = epsilon * A_mag;
        
        BLAEntry entry;
        entry.startIter = n;
        entry.skipCount = 1;
        entry.A = A;
        entry.B = B;
        entry.radius = radius;
        
        return entry;
    } else {
        // Fallback for safety
        BLAEntry entry;
        entry.startIter = n;
        entry.skipCount = 0;
        entry.A = Complex!double(1, 0);
        entry.B = Complex!double(0, 0);
        entry.radius = 0;
        return entry;
    }
}

/// Merge two BLA entries
/// If T_x skips l_x from m_x and T_y skips l_y from m_x + l_x,
/// then T_z = T_y ∘ T_x skips l_x + l_y from m_x
BLAEntry mergeBLA(const ref BLAEntry x, const ref BLAEntry y) {
    // A_z = A_y * A_x
    // B_z = A_y * B_x + B_y
    // R_z = min(R_x, (R_y - |B_x| * |c|) / |A_x|)
    
    auto A_z = y.A * x.A;
    auto B_z = y.A * x.B + y.B;
    
    // Simplified radius calculation (assuming c is small)
    double A_x_mag = sqrt(x.A.re * x.A.re + x.A.im * x.A.im);
    double radius_z = min(x.radius, y.radius / A_x_mag);
    radius_z = max(0.0, radius_z);  // Ensure non-negative
    
    BLAEntry entry;
    entry.startIter = x.startIter;
    entry.skipCount = x.skipCount + y.skipCount;
    entry.A = A_z;
    entry.B = B_z;
    entry.radius = radius_z;
    
    return entry;
}

/// Build BLA table from reference orbit
/// BLA (Bivariate Linear Approximation) creates linear approximations of the iteration function
/// that allow skipping many iterations during perturbation. This table is built once and reused
/// for all pixels, dramatically speeding up deep zoom rendering.
/// 
/// Creates O(M) entries using hierarchical merging:
/// - Step 1: Create M single-step BLAs in parallel (each is independent)
/// - Step 2: Hierarchically merge consecutive BLAs to create longer skip sequences
/// 
/// The merging step is sequential due to dependencies, which is why it can take a while
/// for very long reference orbits (millions of iterations).
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
        
        if (zMag2 < deltaMag2 * rebaseThreshold) {
            // Rebase: replace delta with Z_ref + delta, reset refIter to 0
            delta = z;
            refIter = 0;
            usingLastRef = false;  // Reset flag after rebasing
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
        
        // Check escape
        if (zMag2 > escapeRadius2) {
            double logZn = log(zMag2) * 0.5;
            double nu = log(logZn / log(2.0)) / log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            return result;
        }
        
        // Try to use BLA to skip iterations (only if we have more reference data and not using last ref)
        bool useBLA = true;  // Re-enable BLA now that we've fixed the threading issue
        if (useBLA && !usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            double deltaMag = sqrt(deltaMag2);
            // Create local BLATable wrapper for findBest
            BLATable localBLATable;
            localBLATable.entries = blaEntries.dup;  // Duplicate to avoid const issue
            int blaIdx = localBLATable.findBest(refIter, deltaMag);
            
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
    result.glitched = false;
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
        
        if (zMag2 < deltaMag2 * rebaseThreshold) {
            delta = z;
            refIter = 0;
            usingLastRef = false;
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
        
        if (zMag2 > escapeRadius2) {
            double logZn = log(zMag2) * 0.5;
            double nu = log(logZn / log(2.0)) / log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            return result;
        }
        
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            double deltaMag = sqrt(deltaMag2);
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, deltaMag);
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                
                delta = entry.A * delta + entry.B * delta0;
                
                iter += entry.skipCount;
                refIter += entry.skipCount;
                
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
            } else {
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
        } else {
            if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                break;
            }
            Complex!double currentZRef = zRefArray[refIter];
            auto twoZref = currentZRef * 2.0;
            delta = (twoZref + delta) * delta + delta0;
            
            iter++;
        }
    }
    
    result.iterations = iter;
    result.smoothed = cast(double)iter;
    result.glitched = false;
    return result;
}

/// Scaled delta iteration with BLA support for extreme zooms
/// Handles deltas that are too small to represent in double precision
PerturbResult perturbIterateBLAScaledArrays(
    const Complex!double[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    Complex!double delta0Normalized,  // Normalized delta (in range [-2, 2])
    double delta0LogScale,  // log10 of the actual scale factor (e.g., -20 for 1e-20)
    uint maxIterations,
    int refEscapeIteration = -1  // Iteration at which reference escaped (-1 if didn't escape)
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
    
    // Check if we're in scaled mode - this indicates extreme precision issues
    // If logScale is very negative, we're dealing with extremely tiny deltas
    bool deltaTooSmall = delta0LogScale < -20;  // Very negative log scale indicates precision loss
    
    // Work with scaled coordinates: actual_delta = delta_normalized * 10^logScale
    auto delta = delta0Normalized;
    auto delta0 = delta0Normalized;
    double currentLogScale = delta0LogScale;
    
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;
    
    // Convert escape iteration from 1-indexed to 0-indexed
    // refEscapeIteration is 1-indexed (iter + 1), but refIter is 0-indexed
    int refEscapeIndex = refEscapeIteration >= 0 ? refEscapeIteration - 1 : -1;
    
    while (iter < maxIterations) {
        // Don't automatically mark pixels as escaped just because reference escaped
        // At extreme zooms, delta can be significant enough to keep pixels in the set
        // We'll compute the actual pixel value and check escape based on that
        
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
        
        // Check reference magnitude - but DON'T automatically mark pixel as escaped
        // At extreme zooms, even if reference escapes, delta might be significant enough
        // to keep some pixels in the set. We need to compute the actual pixel value.
        double refMag2 = zRef.re * zRef.re + zRef.im * zRef.im;
        
        // Check if scaled delta has grown to significant size
        double deltaMag = sqrt(delta.re * delta.re + delta.im * delta.im);
        double logActualMag = std.math.log10(max(deltaMag, 1e-300)) + currentLogScale;
        
        // Compute Z = Z_ref + δ_actual for escape check
        double zMag2;
        if (logActualMag > -10 && currentLogScale < 0) {
            // Delta is significant enough to affect Z directly
            // Only use scaled computation if we're actually in scaled mode (logScale < 0)
            double actualScale = (currentLogScale > -300) ? std.math.pow(10.0, currentLogScale) : 0;
            
            if (actualScale == 0 || actualScale < 1e-300) {
                // Scale underflows but delta is significant - use approximation
                // refMag2 is already computed above
                double refMag = sqrt(refMag2);
                double deltaContrib = std.math.pow(10.0, logActualMag);
                double worstCaseMag = refMag + deltaContrib;
                zMag2 = worstCaseMag * worstCaseMag;
            } else {
                auto z = zRef + Complex!double(delta.re * actualScale, delta.im * actualScale);
                zMag2 = z.re * z.re + z.im * z.im;
            }
        } else {
            // Delta still too tiny OR not in scaled mode
            if (currentLogScale >= 0) {
                // Not in scaled mode - use regular delta
                auto z = zRef + delta;
                zMag2 = z.re * z.re + z.im * z.im;
            } else {
                // In scaled mode but delta too tiny to affect Z directly
                // When delta is extremely small, we need to be very careful
                // Even tiny deltas can affect escape detection at extreme zooms
                // Try to compute actual Z = Z_ref + delta, even if delta is tiny
                double actualScale = (currentLogScale > -300) ? std.math.pow(10.0, currentLogScale) : 0;
                if (actualScale > 0 && actualScale >= 1e-300) {
                    // Can compute actual Z even with tiny scale
                    auto z = zRef + Complex!double(delta.re * actualScale, delta.im * actualScale);
                    zMag2 = z.re * z.re + z.im * z.im;
                } else {
                    // Scale is too tiny - use reference magnitude as approximation
                    // But be conservative: if reference hasn't escaped, pixel might not either
                    // If reference has escaped, pixel should also escape (delta can't prevent it)
                    zMag2 = refMag2;
                    
                    // Only auto-escape if reference is well past escape (10x escape radius)
                    // This ensures we don't miss pixels that should be in the set
                    if (refMag2 > escapeRadius2 * 10.0) {
                        double logZn = std.math.log(refMag2) * 0.5;
                        double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                        result.iterations = iter;
                        result.smoothed = 1 + cast(double)iter - nu;
                        result.glitched = false;
                        return result;
                    }
                }
            }
        }
        
        // Check escape based on computed pixel value (Z_ref + delta)
        // Don't use reference magnitude alone - we need the actual pixel value
        if (zMag2 > escapeRadius2) {
            double logZn = std.math.log(zMag2) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;  // Escaped pixels are certain
            return result;
        }
        
        // Try to use BLA to skip iterations
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, deltaMag);
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                
                // Don't automatically escape if BLA skip takes us past escape iteration
                // We need to compute the actual pixel value to determine escape
                
                // Apply BLA: delta_new = A * delta + B * delta0
                // For scaled deltas, BLA coefficients work the same way
                delta = entry.A * delta + entry.B * delta0;
                
                iter += entry.skipCount;
                refIter += entry.skipCount;
                
                // Don't automatically escape after BLA skip
                // We'll check escape based on computed pixel value in the main loop
                
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
            } else {
                // No valid BLA, do regular perturbation step
                if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                    break;
                }
                Complex!double currentZRef = zRefArray[refIter];
                auto twoZref = currentZRef * 2.0;
                
                // Iterate: δ_s_{n+1} = 2·Z_ref·δ_s + δ_s²·10^logScale + δ_s_0
                double logQuadContrib = 2.0 * std.math.log10(deltaMag) + currentLogScale;
                
                if (logQuadContrib > -300) {
                    // Can include quadratic term
                    double scaleFactor = std.math.pow(10.0, currentLogScale);
                    auto deltaSq = Complex!double(
                        delta.re * delta.re - delta.im * delta.im,
                        2.0 * delta.re * delta.im
                    ) * scaleFactor;
                    delta = twoZref * delta + deltaSq + delta0;
                } else {
                    // Linear approximation (quadratic term underflows)
                    delta = twoZref * delta + delta0;
                }
                
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
            // No BLA available, do regular step
            if (refIter < 0 || refIter >= cast(int)maxRefIter) {
                break;
            }
            Complex!double currentZRef = zRefArray[refIter];
            
            // Don't automatically escape - compute actual pixel value to determine escape
            
            auto twoZref = currentZRef * 2.0;
            
            double logQuadContrib = 2.0 * std.math.log10(deltaMag) + currentLogScale;
            
            if (logQuadContrib > -300) {
                double scaleFactor = std.math.pow(10.0, currentLogScale);
                auto deltaSq = Complex!double(
                    delta.re * delta.re - delta.im * delta.im,
                    2.0 * delta.re * delta.im
                ) * scaleFactor;
                delta = twoZref * delta + deltaSq + delta0;
            } else {
                delta = twoZref * delta + delta0;
            }
            
            iter++;
            // Don't automatically escape after incrementing - escape will be checked in main loop
        }
        
        // Rescale if delta grows too large (prevents overflow)
        deltaMag = sqrt(delta.re * delta.re + delta.im * delta.im);
        if (deltaMag > 1e100) {
            delta = Complex!double(delta.re * 1e-100, delta.im * 1e-100);
            currentLogScale += 100;
        }
    }
    
    result.iterations = iter;
    result.smoothed = cast(double)iter;
    result.glitched = false;
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

