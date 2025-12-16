/**
 * High-Precision Perturbation Iteration
 * 
 * Full perturbation iteration using high-precision types (MultiDouble, DDComplex, GMPComplex)
 * instead of converting to double. This preserves precision throughout the calculation.
 */

module perturbation_bla_hp;

import std.stdio;
import std.math;
import std.conv;
import std.complex;
import std.typecons;
import std.algorithm;

import gmp_arb : GMPComplex, GMPFloat;
import multidouble : MultiDoubleComplex, MultiDouble;
import bigfloat : DDComplex, DoubleDouble;
import precision_unified : PrecisionMethod;
import perturbation_bla : PerturbResult, BLAEntry, BLATable;

/// Compute reference orbit in MultiDouble precision
/// Returns array of MultiDoubleComplex values (not converted to double)
MultiDoubleComplex[] computeReferenceOrbitMultiDouble(
    string cRealStr, string cImagStr, uint maxIterations, uint numDoubles
) {
    import gmp_arb : GMPComplex;
    
    MultiDoubleComplex[] zRefArray;
    zRefArray.reserve(maxIterations + 1);
    
    GMPComplex cRefGMP = GMPComplex(cRealStr, cImagStr);
    
    MultiDoubleComplex cRef = MultiDoubleComplex(
        numDoubles, cRefGMP.re.toString(), cRefGMP.im.toString()
    );
    
    MultiDoubleComplex z = MultiDoubleComplex(numDoubles, 0.0, 0.0);
    const double escapeRadius2 = (1 << 16);
    
    // Store initial Z_ref = 0
    zRefArray ~= MultiDoubleComplex(numDoubles, 0.0, 0.0);
    
    for (uint iter = 0; iter < maxIterations; iter++) {
        // Z = Z² + C
        z.squareAndAdd(cRef);
        
        zRefArray ~= MultiDoubleComplex(z.re, z.im);
        
        double mag2 = z.magnitudeSquared();
        if (mag2 > escapeRadius2) {
            // Reference escaped, but continue to maxIterations
            // This ensures we have enough reference orbit points for all pixels
        }
    }
    
    return zRefArray;
}

/// High-precision perturbation iteration using MultiDoubleComplex
PerturbResult perturbIterateBLAMultiDouble(
    const MultiDoubleComplex[] zRefArray,  // Reference orbit in full MultiDouble precision
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    MultiDoubleComplex delta0,  // Initial delta in MultiDouble precision
    uint maxIterations,
    uint numDoubles
) {
    PerturbResult result;
    
    const size_t zRefLength = zRefArray.length;
    const size_t blaEntriesLength = blaEntriesArray.length;
    
    if (zRefLength < 2) {
        result.iterations = cast(int)maxIterations;
        result.smoothed = cast(double)maxIterations;
        result.glitched = true;
        result.uncertain = false;
        return result;
    }
    
    const double rebaseThreshold = 1e-10;
    
    auto delta = delta0;
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;
    int escapeIter = -1;  // Track escape iteration per pixel
    
    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) break;
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        
        if (refIter < 0 || refIter >= cast(int)maxRefIter) break;
        
        // Reference orbit is now in full MultiDouble precision (no conversion loss!)
        const MultiDoubleComplex zRef = zRefArray[refIter];
        
        // Compute Z = Z_ref + delta in MultiDouble precision
        // Even though zRef lost precision, delta is in full precision
        // So z = zRef + delta still benefits from high-precision delta
        auto z = zRef + delta;
        
        // Check for rebasing first (matches regular perturbation order)
        double zMag2 = z.magnitudeSquared();
        double deltaMag2 = delta.magnitudeSquared();
        
        if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
            // Magnitude calculation failed - assume escape for safety
            double logZn = std.math.log(escapeRadius2 * 2.0) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        
        if (zMag2 < deltaMag2 * rebaseThreshold) {
            delta = z;
            refIter = 0;
            usingLastRef = false;
            // Recompute z after rebasing
            if (refIter >= 0 && refIter < cast(int)maxRefIter) {
                z = zRefArray[refIter] + delta;
                zMag2 = z.magnitudeSquared();
                // Check for NaN/Inf after rebasing
                if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
                    double logZn = std.math.log(escapeRadius2 * 2.0) * 0.5;
                    double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                    result.iterations = iter;
                    result.smoothed = 1 + cast(double)iter - nu;
                    result.glitched = false;
                    result.uncertain = false;
                    return result;
                }
            }
        }
        
        double refMag2 = zRef.magnitudeSquared();
        bool refHasEscaped = (refMag2 > escapeRadius2);
        
        static int debugIterCount = 0;
        if (debugIterCount < 20 && iter < 20) {
            double deltaMag = sqrt(deltaMag2);
            double refMag = sqrt(refMag2);
            double zMag = sqrt(zMag2);
            writeln("\n[ESCAPE DEBUG iter=", iter, "] zMag2=", zMag2, " refMag2=", refMag2, 
                    " deltaMag2=", deltaMag2, " escapeRadius2=", escapeRadius2);
            writeln("  zMag=", zMag, " refMag=", refMag, " deltaMag=", deltaMag);
            writeln("  delta/reference ratio: ", (deltaMag > 0 && refMag > 0) ? deltaMag/refMag : 0.0);
            if (iter == 19) debugIterCount = 20;
        }
        
        if (zMag2 > escapeRadius2) {
            if (escapeIter < 0) {
                escapeIter = iter;
            }
        } else if (zMag2 == double.infinity || zMag2 > 1e100) {
            double logZn = std.math.log(zMag2 > escapeRadius2 ? zMag2 : escapeRadius2 * 1.1) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        
        if (refHasEscaped) {
            if (deltaMag2 < refMag2 * 1e-10) {
                if (escapeIter < 0) {
                    escapeIter = iter;
                }
            }
        }
        
        if (!refHasEscaped && deltaMag2 > escapeRadius2 * 0.1) {
            // Delta has grown very large - recompute z more carefully
            // Use worst-case: |z| ≤ |zRef| + |delta|
            double refMag = sqrt(refMag2);
            double deltaMag = sqrt(deltaMag2);
            double worstCaseMag2 = (refMag + deltaMag) * (refMag + deltaMag);
            if (worstCaseMag2 > escapeRadius2) {
                if (escapeIter < 0) {
                    escapeIter = iter;
                }
            }
        }
        
        // Try BLA
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, sqrt(deltaMag2));
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                
                // Apply BLA: delta_new = A * delta + B * delta0
                // Convert BLA coefficients to MultiDouble
                MultiDoubleComplex A = MultiDoubleComplex(numDoubles, entry.A.re, entry.A.im);
                MultiDoubleComplex B = MultiDoubleComplex(numDoubles, entry.B.re, entry.B.im);
                
                delta = A * delta + B * delta0;
                iter += entry.skipCount;
                refIter += entry.skipCount;
                
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
                
                if (refIter >= 0 && refIter < cast(int)maxRefIter) {
                    z = zRefArray[refIter] + delta;
                    zMag2 = z.magnitudeSquared();
                    if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
                        double logZn = std.math.log(escapeRadius2 * 2.0) * 0.5;
                        double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                        result.iterations = iter;
                        result.smoothed = 1 + cast(double)iter - nu;
                        result.glitched = false;
                        result.uncertain = false;
                        return result;
                    }
                    if (zMag2 > escapeRadius2) {
                        if (escapeIter < 0) {
                            escapeIter = iter;
                        }
                    } else if (zMag2 > 1e100) {
                        double logZn = std.math.log(zMag2 > escapeRadius2 ? zMag2 : escapeRadius2 * 1.1) * 0.5;
                        double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                        result.iterations = iter;
                        result.smoothed = 1 + cast(double)iter - nu;
                        result.glitched = false;
                        result.uncertain = false;
                        return result;
                    }
                }
                continue;
            }
        }
        
        // Regular perturbation step: δ_{n+1} = 2·Z_ref·δ_n + δ_n² + δ_0

        MultiDoubleComplex twoZref = zRef * MultiDoubleComplex(numDoubles, 2.0, 0.0);
        MultiDoubleComplex deltaSq = delta.square();
        delta = twoZref * delta + deltaSq + delta0;
        
        iter++;
        
        if (!usingLastRef) {
            refIter++;
            if (refIter >= cast(int)maxRefIter) {
                refIter = cast(int)maxRefIter - 1;
                usingLastRef = true;
            }
        }
        
        const MultiDoubleComplex zRefForEscape = zRefArray[refIter];
        
        z = zRefForEscape + delta;
        zMag2 = z.magnitudeSquared();
        
        if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
            double logZn = std.math.log(escapeRadius2 * 2.0) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        
        if (zMag2 > escapeRadius2) {
            if (escapeIter < 0) {
                escapeIter = iter;
            }
            
            if (iter >= cast(int)maxIterations - 10) {
                double logZn = std.math.log(zMag2) * 0.5;
                double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                result.iterations = escapeIter;
                result.smoothed = 1.0 + cast(double)iter - nu;
                result.glitched = false;
                result.uncertain = false;
                return result;
            }
        }
        
        if (!usingLastRef) {
            refIter++;
            if (refIter >= cast(int)maxRefIter) {
                refIter = cast(int)maxRefIter - 1;
                usingLastRef = true;
            }
        }
    }
    
    // Didn't escape
    result.iterations = cast(int)maxIterations;
    result.smoothed = cast(double)maxIterations;
    result.glitched = false;
    result.uncertain = false;
    return result;
}

/// High-precision perturbation iteration using DDComplex (bigfloat)
PerturbResult perturbIterateBLADDComplex(
    const Complex!double[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    DDComplex delta0,  // Initial delta in DDComplex precision
    uint maxIterations
) {
    PerturbResult result;
    
    const size_t zRefLength = zRefArray.length;
    const size_t blaEntriesLength = blaEntriesArray.length;
    
    if (zRefLength < 2) {
        result.iterations = cast(int)maxIterations;
        result.smoothed = cast(double)maxIterations;
        result.glitched = true;
        result.uncertain = false;
        return result;
    }
    
    const double rebaseThreshold = 1e-10;
    
    auto delta = delta0;
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;
    int escapeIter = -1;  // Track escape iteration per pixel
    
    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) break;
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        
        if (refIter < 0 || refIter >= cast(int)maxRefIter) break;
        
        // Convert reference orbit value to DDComplex
        Complex!double zRefDouble = zRefArray[refIter];
        DDComplex zRef = DDComplex(zRefDouble.re, zRefDouble.im);
        
        // Compute Z = Z_ref + delta in DDComplex precision
        auto z = zRef + delta;
        double zMag2 = z.magnitudeSquared().toDouble();
        
        // Check escape
        if (zMag2 > escapeRadius2) {
            double logZn = std.math.log(zMag2) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        
        // Check for rebasing
        double deltaMag2 = delta.magnitudeSquared().toDouble();
        if (zMag2 < deltaMag2 * rebaseThreshold) {
            delta = z;
            refIter = 0;
            usingLastRef = false;
            continue;
        }
        
        // Try BLA
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, sqrt(deltaMag2));
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                
                // Apply BLA: delta_new = A * delta + B * delta0
                DDComplex A = DDComplex(entry.A.re, entry.A.im);
                DDComplex B = DDComplex(entry.B.re, entry.B.im);
                
                delta = A * delta + B * delta0;
                iter += entry.skipCount;
                refIter += entry.skipCount;
                
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
                continue;
            }
        }
        
        // Regular perturbation step: δ_{n+1} = 2·Z_ref·δ_n + δ_n² + δ_0
        auto twoZref = zRef * DDComplex(2.0, 0.0);
        auto deltaSq = delta.square();
        delta = twoZref * delta + deltaSq + delta0;
        
        iter++;
        if (!usingLastRef) {
            refIter++;
            if (refIter >= cast(int)maxRefIter) {
                refIter = cast(int)maxRefIter - 1;
                usingLastRef = true;
            }
        }
    }
    
    // Didn't escape
    result.iterations = cast(int)maxIterations;
    result.smoothed = cast(double)maxIterations;
    result.glitched = false;
    result.uncertain = false;
    return result;
}

/// High-precision perturbation iteration using GMPComplex
PerturbResult perturbIterateBLAGMP(
    const Complex!double[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    GMPComplex delta0,  // Initial delta in GMPComplex precision
    uint maxIterations
) {
    PerturbResult result;
    
    const size_t zRefLength = zRefArray.length;
    const size_t blaEntriesLength = blaEntriesArray.length;
    
    if (zRefLength < 2) {
        result.iterations = cast(int)maxIterations;
        result.smoothed = cast(double)maxIterations;
        result.glitched = true;
        result.uncertain = false;
        return result;
    }
    
    const double rebaseThreshold = 1e-10;
    
    auto delta = delta0;
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;
    int escapeIter = -1;  // Track escape iteration per pixel
    
    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) break;
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        
        if (refIter < 0 || refIter >= cast(int)maxRefIter) break;
        
        // Convert reference orbit value to GMPComplex
        Complex!double zRefDouble = zRefArray[refIter];
        GMPComplex zRef = GMPComplex(zRefDouble.re, zRefDouble.im);
        
        // Compute Z = Z_ref + delta in GMPComplex precision
        auto z = zRef + delta;
        double zMag2 = z.magnitudeSquaredDouble();
        
        // Check escape
        if (zMag2 > escapeRadius2) {
            double logZn = std.math.log(zMag2) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        
        // Check for rebasing
        double deltaMag2 = delta.magnitudeSquaredDouble();
        if (zMag2 < deltaMag2 * rebaseThreshold) {
            delta = z;
            refIter = 0;
            usingLastRef = false;
            continue;
        }
        
        // Try BLA
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, sqrt(deltaMag2));
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                
                // Apply BLA: delta_new = A * delta + B * delta0
                GMPComplex A = GMPComplex(entry.A.re, entry.A.im);
                GMPComplex B = GMPComplex(entry.B.re, entry.B.im);
                
                delta = A * delta + B * delta0;
                iter += entry.skipCount;
                refIter += entry.skipCount;
                
                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }
                continue;
            }
        }
        
        // Regular perturbation step: δ_{n+1} = 2·Z_ref·δ_n + δ_n² + δ_0
        auto twoZref = zRef * GMPComplex(2.0, 0.0);
        auto deltaSq = delta.square();
        delta = twoZref * delta + deltaSq + delta0;
        
        iter++;
        if (!usingLastRef) {
            refIter++;
            if (refIter >= cast(int)maxRefIter) {
                refIter = cast(int)maxRefIter - 1;
                usingLastRef = true;
            }
        }
    }
    
    // Didn't escape
    result.iterations = cast(int)maxIterations;
    result.smoothed = cast(double)maxIterations;
    result.glitched = false;
    result.uncertain = false;
    return result;
}

