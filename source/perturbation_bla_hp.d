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
import doubledouble : DDComplex, DoubleDouble;
import bigfloat : BigFloat, BigFloatComplex;
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
    
    // Create cRef in GMP first to get exact value
    GMPComplex cRefGMP = GMPComplex(cRealStr, cImagStr);
    
    // Convert to MultiDouble
    MultiDoubleComplex cRef = MultiDoubleComplex(
        numDoubles, cRefGMP.re.toString(), cRefGMP.im.toString()
    );
    
    MultiDoubleComplex z = MultiDoubleComplex(numDoubles, 0.0, 0.0);
    const double escapeRadius2 = 4.0;  // 2.0^2 = escape radius squared (standard Mandelbrot escape radius is 2.0)
    
    // Store initial Z_ref = 0
    zRefArray ~= MultiDoubleComplex(numDoubles, 0.0, 0.0);
    
    for (uint iter = 0; iter < maxIterations; iter++) {
        // Z = Z² + C
        z.squareAndAdd(cRef);
        
        // Store in full MultiDouble precision (no conversion to double!)
        zRefArray ~= MultiDoubleComplex(z.re, z.im);
        
        // Check escape - but continue computing even after escape
        // This is important for perturbation: we need the full reference orbit
        // even if it escapes, so we can accurately compute pixel variations
        double mag2 = z.magnitudeSquared();
        if (mag2 > escapeRadius2) {
            // Reference escaped, but continue to maxIterations
            // This ensures we have enough reference orbit points for all pixels
        }
    }
    
    return zRefArray;
}

/// Direct MultiDouble iteration (fallback when perturbation fails)
PerturbResult iterateDirectMultiDouble(
    MultiDoubleComplex c,
    uint maxIterations,
    uint numDoubles,
    double escapeRadius2
) {
    PerturbResult result;
    auto z = MultiDoubleComplex(numDoubles, 0.0, 0.0);
    for (uint iter = 0; iter < maxIterations; ++iter) {
        z.squareAndAdd(c);
        double mag2 = z.magnitudeSquared();
        if (!(mag2 == mag2) || mag2 == double.infinity || mag2 < 0.0) {
            double logZn = std.math.log(escapeRadius2 * 2.0) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = cast(int)iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
        if (mag2 > escapeRadius2) {
            double logZn = std.math.log(mag2) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = cast(int)iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }
    }
    result.iterations = cast(int)maxIterations;
    result.smoothed = cast(double)maxIterations;
    result.glitched = false;
    result.uncertain = false;
    return result;
}

/// High-precision perturbation iteration using MultiDoubleComplex
PerturbResult perturbIterateBLAMultiDouble(
    const MultiDoubleComplex[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    MultiDoubleComplex delta0,
    uint maxIterations,
    uint numDoubles
) {
    PerturbResult result;
    import std.process : environment;
    import std.stdio : writeln;
    bool tracePixel = "MANDEL_TRACE_PIXEL" in environment;
    bool disableBLA = "MANDEL_DISABLE_BLA" in environment;

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
    int escapeIter = -1;
    double lastEscapeMag2 = 0.0;

    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) break;
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }

        if (refIter < 0 || refIter >= cast(int)maxRefIter) break;

        const MultiDoubleComplex zRef = zRefArray[refIter];
        auto z = zRef + delta;
        double zMag2 = z.magnitudeSquared();
        double deltaMag2 = delta.magnitudeSquared();

        double deltaMag = sqrt(deltaMag2);
        if (tracePixel && iter % 64 == 0) {
            writeln("[md delta] iter=", iter, " |delta|=", deltaMag);
        }

        if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
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
            }
            continue;
        }
        double refMag2 = zRef.magnitudeSquared();
        bool refHasEscaped = (refMag2 > escapeRadius2);

        if (zMag2 > escapeRadius2) {
            if (escapeIter < 0) {
                escapeIter = iter;
            }
            lastEscapeMag2 = zMag2;
        } else if (zMag2 == double.infinity || zMag2 > 1e100) {
            double logZn = std.math.log(zMag2 > escapeRadius2 ? zMag2 : escapeRadius2 * 1.1) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }

        if (refHasEscaped && deltaMag2 < refMag2 * 1e-10) {
            if (escapeIter < 0) {
                escapeIter = iter;
                lastEscapeMag2 = zMag2;
            }
        }

        if (!refHasEscaped && deltaMag2 > escapeRadius2 * 0.1) {
            double refMag = sqrt(refMag2);
            double worstCaseMag2 = (refMag + deltaMag) * (refMag + deltaMag);
            if (worstCaseMag2 > escapeRadius2) {
                if (escapeIter < 0) {
                    escapeIter = iter;
                }
                lastEscapeMag2 = worstCaseMag2;
            }
        }

        if (!disableBLA && !usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, sqrt(deltaMag2));

            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                if (entry.hasMultiDouble) {
                    delta = entry.A_multiDouble * delta + entry.B_multiDouble * delta0;
                } else {
                    MultiDoubleComplex A = MultiDoubleComplex(numDoubles, entry.A.re, entry.A.im);
                    MultiDoubleComplex B = MultiDoubleComplex(numDoubles, entry.B.re, entry.B.im);
                    delta = A * delta + B * delta0;
                }
                iter += entry.skipCount;
                refIter += entry.skipCount;

                if (refIter >= cast(int)maxRefIter) {
                    refIter = cast(int)maxRefIter - 1;
                    usingLastRef = true;
                }

                const MultiDoubleComplex zBla = zRefArray[refIter] + delta;
                double zBlaMag2 = zBla.magnitudeSquared();
                if (!(zBlaMag2 == zBlaMag2) || zBlaMag2 == double.infinity || zBlaMag2 < 0.0) {
                    double logZn = std.math.log(escapeRadius2 * 2.0) * 0.5;
                    double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                    result.iterations = iter;
                    result.smoothed = 1 + cast(double)iter - nu;
                    result.glitched = false;
                    result.uncertain = false;
                    return result;
                }
                if (zBlaMag2 > escapeRadius2) {
                    if (escapeIter < 0) {
                        escapeIter = iter;
                    }
                    lastEscapeMag2 = zBlaMag2;
                }
                continue;
            }
        }

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
            lastEscapeMag2 = zMag2;
        }
    }

    if (escapeIter >= 0) {
        double mag = (lastEscapeMag2 > 0) ? lastEscapeMag2 : escapeRadius2 * 1.1;
        double logZn = std.math.log(mag) * 0.5;
        double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
        result.iterations = escapeIter;
        result.smoothed = 1 + cast(double)(escapeIter) - nu;
        result.glitched = false;
        result.uncertain = false;
        return result;
    }

    // Perturbation failed to detect escape - fall back to direct iteration
    MultiDoubleComplex cRef;
    if (zRefArray.length > 1) {
        MultiDouble reCopy = MultiDouble(numDoubles, 0.0);
        reCopy = zRefArray[1].re;
        MultiDouble imCopy = MultiDouble(numDoubles, 0.0);
        imCopy = zRefArray[1].im;
        cRef = MultiDoubleComplex(reCopy, imCopy);
    } else {
        cRef = MultiDoubleComplex(numDoubles, 0.0, 0.0);
    }
    auto cActual = cRef + delta0;
    return iterateDirectMultiDouble(cActual, maxIterations, numDoubles, escapeRadius2);
}

/// High-precision perturbation iteration using BigFloatComplex
PerturbResult perturbIterateBLABigFloat(
    const BigFloatComplex[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    BigFloatComplex delta0,
    uint maxIterations
) {
    PerturbResult result;
    import std.process : environment;
    import std.stdio : writeln;
    bool disableBLA = "MANDEL_DISABLE_BLA" in environment;

    const size_t zRefLength = zRefArray.length;
    const size_t blaEntriesLength = blaEntriesArray.length;

    if (zRefLength < 2) {
        result.iterations = cast(int)maxIterations;
        result.smoothed = cast(double)maxIterations;
        result.glitched = true;
        result.uncertain = false;
        return result;
    }

    const double rebaseThreshold = 1e-12;

    auto delta = delta0;
    int iter = 0;
    int refIter = 0;
    size_t maxRefIter = zRefLength;
    bool usingLastRef = false;

    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) break;
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }

        if (refIter < 0 || refIter >= cast(int)maxRefIter) break;

        const BigFloatComplex zRef = zRefArray[refIter];
        auto z = zRef + delta;
        double zMag2 = z.magnitudeSquared().toDouble();
        double deltaMag2 = delta.magnitudeSquared().toDouble();

        if (!std.math.isFinite(zMag2) || zMag2 < 0.0) {
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
            if (refIter >= 0 && refIter < cast(int)maxRefIter) {
                auto zNew = zRefArray[refIter] + delta;
                zMag2 = zNew.magnitudeSquared().toDouble();
            }
        }

        if (zMag2 > escapeRadius2) {
            double logZn = std.math.log(zMag2) * 0.5;
            double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
            result.iterations = iter;
            result.smoothed = 1 + cast(double)iter - nu;
            result.glitched = false;
            result.uncertain = false;
            return result;
        }

        if (!disableBLA && !usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            double deltaMag = std.math.sqrt(deltaMag2);
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, deltaMag);
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                auto A = BigFloatComplex(BigFloat(entry.A.re), BigFloat(entry.A.im));
                auto B = BigFloatComplex(BigFloat(entry.B.re), BigFloat(entry.B.im));
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

        auto two = BigFloat("2");
        auto twoZ = BigFloatComplex(zRef.re * two, zRef.im * two);
        delta = (twoZ + delta) * delta + delta0;
        iter++;
        if (!usingLastRef) {
            refIter++;
            if (refIter >= cast(int)maxRefIter) {
                refIter = cast(int)maxRefIter - 1;
                usingLastRef = true;
            }
        }
    }

    result.iterations = iter;
    result.smoothed = cast(double)iter;
    result.glitched = false;
    result.uncertain = false;
    return result;
}

/// Hybrid perturbation: use MultiDouble for delta only, with double reference orbit.
PerturbResult perturbIterateBLAMultiDoubleDelta(
    const Complex!double[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    MultiDoubleComplex delta0,
    uint maxIterations,
    uint numDoubles
) {
    PerturbResult result;
    import std.process : environment;
    import std.stdio : writeln;
    bool tracePixel = "MANDEL_TRACE_PIXEL" in environment;
    bool disableBLA = "MANDEL_DISABLE_BLA" in environment;
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

    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) break;
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        if (refIter < 0 || refIter >= cast(int)maxRefIter) break;

        Complex!double zRef = zRefArray[refIter];
        auto z = MultiDoubleComplex(numDoubles, zRef.re, zRef.im) + delta;
        double zMag2 = z.magnitudeSquared();
        double deltaMag2 = delta.magnitudeSquared();

        double deltaMag = sqrt(deltaMag2);
        if (tracePixel && iter % 64 == 0) {
            writeln("[md delta] iter=", iter, " |delta|=", deltaMag);
        }

        if (zMag2 > escapeRadius2) {
            double logZn = std.math.log(zMag2) * 0.5;
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
            continue;
        }

        // (Growth-based rebase removed to avoid infinite rebasing loops)

        bool usedBLA = false;
        if (!disableBLA && !usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, sqrt(deltaMag2));
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                if (entry.skipCount <= 32) {
                    double radius = entry.radius;
                    if (radius > 0 && deltaMag2 < radius * radius) {
                        auto nextDelta = entry.A_multiDouble * delta + entry.B_multiDouble * delta0;
                        double nextMag2 = nextDelta.magnitudeSquared();
                        if (nextMag2 == nextMag2 && nextMag2 != double.infinity && nextMag2 < radius * radius * 16) {
                            delta = nextDelta;
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
            Complex!double twoZref = zRef * 2.0;
            auto deltaSq = delta;
            deltaSq.square(); // δ^2
            delta = MultiDoubleComplex(numDoubles, twoZref.re, twoZref.im) * delta + deltaSq + delta0;
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
    result.glitched = false;
    result.uncertain = true; // mark for higher precision if needed
    return result;
}

/// High-precision perturbation iteration using DDComplex (bigfloat)
PerturbResult perturbIterateBLADDComplex(
    const DDComplex[] zRefArray,
    const double escapeRadius2,
    const BLAEntry[] blaEntriesArray,
    DDComplex delta0,  // Initial delta in DDComplex precision
    uint maxIterations
) {
    PerturbResult result;
    import std.process : environment;
    bool disableBLA = "MANDEL_DISABLE_BLA" in environment;
    
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
        
        DDComplex zRef = zRefArray[refIter];
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
        if (!disableBLA && !usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
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
    const GMPComplex[] zRefArray,
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
    
    // Ensure escapeRadius2 is valid - if it's NaN or wrong value, use the correct value
    // Standard Mandelbrot escape radius is 2.0, so escapeRadius2 should be 4.0
    // Some code paths may pass (1 << 16) = 65536, which is wrong - override it
    double validEscapeRadius2 = escapeRadius2;
    if (!(validEscapeRadius2 == validEscapeRadius2) || validEscapeRadius2 <= 0 || validEscapeRadius2 > 100.0) {
        validEscapeRadius2 = 4.0;  // 2.0^2 = standard Mandelbrot escape radius squared
    }
    // Force to 4.0 always for now to debug
    validEscapeRadius2 = 4.0;
    GMPFloat escapeRadius2GMP = GMPFloat(validEscapeRadius2);
    
    // Debug: print escape radius
    import std.stdio;
    static bool escapeRadiusPrinted = false;
    if (!escapeRadiusPrinted) {
        stderr.writeln("[DEBUG] escapeRadius2 param=", escapeRadius2, " validEscapeRadius2=", validEscapeRadius2);
        stderr.flush();
        escapeRadiusPrinted = true;
    }
    
    // Debug: check initial delta0 magnitude and first few iterations
    import std.stdio;
    static int debugPixelCount = 0;
    if (debugPixelCount < 3) {
        auto delta0Mag2 = delta0.magnitudeSquared();
        double delta0Mag2Double = delta0Mag2.toDouble();
        double delta0Mag = sqrt(delta0Mag2Double);
        stderr.writeln("[DEBUG pixel ", debugPixelCount, "] Initial delta0 magnitude: ", delta0Mag, " (squared: ", delta0Mag2Double, ")");
        stderr.writeln("[DEBUG] Escape radius: ", sqrt(validEscapeRadius2), " (squared: ", validEscapeRadius2, ")");
        stderr.writeln("[DEBUG] delta0 would escape at iter 0: ", delta0Mag2Double > validEscapeRadius2);
        stderr.flush();
        debugPixelCount++;
    }
    
    while (iter < maxIterations) {
        if (refIter >= cast(int)maxRefIter) {
            if (maxRefIter == 0) break;
            refIter = cast(int)maxRefIter - 1;
            usingLastRef = true;
        }
        
        if (refIter < 0 || refIter >= cast(int)maxRefIter) break;
        
        // Use reference orbit directly (avoid unnecessary string conversion)
        // zRefArray elements are already GMPComplex, so we can use them directly
        const GMPComplex zRef = zRefArray[refIter];
        auto z = zRef + delta;
        
        // Skip escape check at iteration 0 - z = zRef[0] + delta0 = 0 + delta0 = delta0
        // For deep zooms, delta0 is tiny and shouldn't escape, but we haven't iterated yet
        // Check escape after we've done at least one iteration
        if (iter > 0) {
            // Use GMP magnitude calculation and compare in GMP precision for accuracy
            // This is critical - double conversion can lose precision for very large values
            auto zMag2GMP = z.magnitudeSquared();
            
            // Compare in GMP precision first - this is the accurate check
            bool escapedGMP = (zMag2GMP > escapeRadius2GMP);
            
            // Convert to double for fallback and logging
            double zMag2 = zMag2GMP.toDouble();
        
            debug(gmpdebug) {
                import std.stdio;
                static int debugCount = 0;
                if (debugCount < 50 && iter < 20) {
                    stderr.writeln("[ESCAPE DEBUG iter=", iter, "] zMag2GMP=", zMag2GMP.toString(), 
                                  " escapeRadius2GMP=", escapeRadius2GMP.toString(),
                                  " escapedGMP=", escapedGMP, " zMag2=", zMag2, 
                                  " escapeRadius2=", escapeRadius2);
                    stderr.flush();
                    debugCount++;
                }
            }
            
            // Check for NaN or infinity
            if (!(zMag2 == zMag2) || zMag2 == double.infinity || zMag2 < 0.0) {
                // Value is too large or invalid - consider it escaped
                debug(gmpdebug) {
                    import std.stdio;
                    stderr.writeln("[ESCAPE] NaN/Inf detected at iter=", iter, ", treating as escaped");
                    stderr.flush();
                }
                double logZn = std.math.log(validEscapeRadius2 * 2.0) * 0.5;
                double nu = std.math.log(logZn / std.math.log(2.0)) / std.math.log(2.0);
                result.iterations = iter;
                result.smoothed = 1 + cast(double)iter - nu;
                result.glitched = false;
                result.uncertain = false;
                return result;
            }
            
            // Check escape - use GMP comparison result, with double fallback for safety
            // Use validEscapeRadius2 for the double comparison too
            if (escapedGMP || zMag2 > validEscapeRadius2) {
                // Temporary debug: print first few escapes to see what's happening
                static int escapeCount = 0;
                if (escapeCount < 10) {
                    auto zRefMag2 = zRef.magnitudeSquared().toDouble();
                    auto deltaMag2 = delta.magnitudeSquared().toDouble();
                    stderr.writeln("[ESCAPE ", escapeCount, "] iter=", iter, " zMag2=", zMag2, 
                                  " validEscapeRadius2=", validEscapeRadius2, " escapedGMP=", escapedGMP,
                                  " zRefMag2=", zRefMag2, " deltaMag2=", deltaMag2,
                                  " zMag2GMP=", zMag2GMP.toString());
                    stderr.flush();
                    escapeCount++;
                }
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
        }
        
        // Try BLA
        double deltaMag2 = delta.magnitudeSquaredDouble();
        if (!usingLastRef && refIter + 1 < cast(int)maxRefIter && blaEntriesLength > 0) {
            int blaIdx = BLATable.findBestInEntries(blaEntriesArray, refIter, sqrt(deltaMag2));
            
            if (blaIdx >= 0 && blaIdx < cast(int)blaEntriesLength) {
                const BLAEntry entry = blaEntriesArray[blaIdx];
                
                // Apply BLA: delta_new = A * delta + B * delta0
                // Convert double to GMPComplex (double precision is sufficient for BLA coefficients)
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
