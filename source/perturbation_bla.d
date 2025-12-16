module perturbation_bla;

import std.stdio;
import std.math;
import std.conv;
import std.algorithm;
import std.range;
import std.complex;
import std.typecons;

import gmp_arb;

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
    /// Z_ref values at each iteration
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
        int bestIdx = -1;
        int bestSkip = 0;
        
        foreach (i, ref entry; entries) {
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

/// Compute reference orbit at high precision using GMP
/// Uses hybrid approach: start with double, switch to GMP when needed
/// This is done ONCE per image
ReferenceOrbit computeReferenceOrbit(string cRealStr, string cImagStr, uint maxIterations) {
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
    const double maxDoubleMag2 = 1e200;  // Switch to GMP when values get this large
    
    // Start with fast double precision
    double zr = 0.0;
    double zi = 0.0;
    double cr, ci;
    
    try {
        cr = result.cRef.re.toDouble();
        ci = result.cRef.im.toDouble();
    } catch (Exception e) {
        writeln("ERROR: Failed to convert cRef to double: ", e.msg);
        return result;
    }
    
    writeln("Computing reference orbit (this may take a while)...");
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
    
    for (iter = 0; iter < maxIterations; iter++) {
        // Fast double precision iteration
        if (!usingGMP) {
            double zrTemp = zr * zr - zi * zi + cr;
            zi = 2.0 * zr * zi + ci;
            zr = zrTemp;
            
            double mag2 = zr * zr + zi * zi;
            
            // Store as double
            result.zRef ~= Complex!double(zr, zi);
            
            // Check escape
            if (mag2 > escapeRadius2) {
                result.escaped = true;
                result.refIterations = iter + 1;
                break;
            }
            
            // Switch to GMP if magnitude is huge or deep iteration
            if (mag2 > maxDoubleMag2 || (iter > 3000 && mag2 < escapeRadius2 && (maxIterations - iter) > 1000)) {
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
        } else {
            // GMP iteration (slower, but necessary for precision)
            try {
                zGMP.squareAndAdd(result.cRef);
                
                // Store as double
                double zrGMP, ziGMP;
                try {
                    zrGMP = zGMP.re.toDouble();
                    ziGMP = zGMP.im.toDouble();
                } catch (Exception e) {
                    writeln("\nERROR: Failed to convert GMP to double at iteration ", iter, ": ", e.msg);
                    break;  // Can't continue
                }
                result.zRef ~= Complex!double(zrGMP, ziGMP);
            } catch (Exception e) {
                writeln("\nERROR: GMP iteration failed at iteration ", iter, ": ", e.msg);
                break;  // Can't continue
            }
            
            // Check escape less frequently for GMP
            if (iter % 10 == 0 || iter == maxIterations - 1) {
                double mag2 = zGMP.magnitudeSquaredDouble();
                if (mag2 > escapeRadius2) {
                    result.escaped = true;
                    result.refIterations = iter + 1;
                    break;
                }
            }
        }
        
        // Progress indication with time estimates
        if (iter % progressInterval == 0 || iter == maxIterations - 1) {
            int percent = (iter * 100) / cast(int)maxIterations;
            if (percent != lastPercent) {
                auto currentTime = timer.peek();
                auto elapsed = currentTime - lastTime;
                
                if (elapsed.total!"msecs" > 1000) {  // Only show time if > 1 second
                    write(percent, "% ");
                    stdout.flush();
                    lastTime = currentTime;
                } else {
                    write(percent, "% ");
                    stdout.flush();
                }
                lastPercent = percent;
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
    
    writeln("100% - Reference orbit computed: ", result.refIterations, " iterations (", 
            result.zRef.length, " points) in ", timer.peek().total!"seconds", " seconds");
    
    return result;
}

/// Compute single-step BLA coefficients
/// For iteration n: z_{n+1} = A_{n,1} * z_n + B_{n,1} * c
/// Valid when |z_n| << |2 * Z_n|
BLAEntry computeSingleStepBLA(const ref ReferenceOrbit ref_, int n) {
    if (n >= ref_.zRef.length - 1) {
        // Can't compute BLA for last iteration
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
/// Creates O(M) entries using hierarchical merging
/// Can be parallelized since each single-step BLA is independent
BLATable buildBLATable(const ref ReferenceOrbit ref_) {
    import std.parallelism;
    import std.datetime.stopwatch : StopWatch, AutoStart;
    
    writeln("Building BLA table...");
    StopWatch timer;
    timer.start();
    
    BLATable table;
    
    if (ref_.zRef.length < 2) {
        return table;  // Need at least 2 points
    }
    
    // Start from iteration 1 (iteration 0 is always non-linear as Z=0)
    const int startIter = 1;
    const int M = cast(int)ref_.zRef.length - 1;
    
    // Step 1: Create M single-step BLAs in parallel (each is independent!)
    BLAEntry[] singleSteps;
    singleSteps.length = M;
    
    auto iterRange = iota(startIter, startIter + M);
    foreach (i; parallel(iterRange)) {
        singleSteps[i - startIter] = computeSingleStepBLA(ref_, i);
    }
    
    // Step 2: Hierarchical merging (sequential - dependencies between merges)
    BLAEntry[] current = singleSteps;
    table.entries ~= singleSteps;  // Keep all single steps
    
    while (current.length > 1) {
        BLAEntry[] next;
        next.reserve((current.length + 1) / 2);
        
        // Merge pairs
        for (int i = 0; i < current.length - 1; i += 2) {
            // Check if entries can be merged (consecutive)
            if (current[i].startIter + current[i].skipCount == current[i+1].startIter) {
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
        
        current = next;
    }
    
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
}

/// Perform perturbation iteration with BLA
/// Uses reference orbit and BLA table to iterate pixel deltas efficiently
PerturbResult perturbIterateBLA(
    const ref ReferenceOrbit ref_,
    const ref BLATable blaTable,
    Complex!double delta0,  // Initial delta (pixel offset from reference)
    uint maxIterations
) {
    PerturbResult result;
    
    // Validate inputs
    if (ref_.zRef.length < 2) {
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
    size_t maxRefIter = ref_.zRef.length;
    bool usingLastRef = false;  // Track if we're using the last reference point
    
    while (iter < maxIterations) {
        // Bounds check before accessing zRef
        if (refIter >= cast(int)maxRefIter) {
            // Ran out of reference orbit - use last point and continue
            if (maxRefIter > 0) {
                refIter = cast(int)maxRefIter - 1;
                usingLastRef = true;
            } else {
                break;  // No reference data at all
            }
        }
        
        auto zRef = ref_.zRef[refIter];
        
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
            // Get new reference after rebasing
            auto newZRef = ref_.zRef[refIter];
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
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter) {
            double deltaMag = sqrt(deltaMag2);
            int blaIdx = blaTable.findBest(refIter, deltaMag);
            
            if (blaIdx >= 0) {
                // Use BLA to skip iterations
                const ref entry = blaTable.entries[blaIdx];
                
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
                auto currentZRef = ref_.zRef[refIter];
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
            auto currentZRef = ref_.zRef[refIter];
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