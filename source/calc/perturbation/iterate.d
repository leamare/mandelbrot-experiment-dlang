/**
 * Perturbation Iteration
 * 
 * Per-pixel iteration using perturbation theory with rebasing.
 * 
 * https://mathr.co.uk/blog/2021-05-14_deep_zoom_theory_and_practice.html
 */
module calc.perturbation.iterate;

import std.math : sqrt, log, log2, abs, isNaN, isInfinity;
import std.complex : Complex;

import calc.perturbation.reference;
import types.iter_result;
import precision.constants;

struct PerturbResult {
    IterResult result;
    bool needsRefinement;
    int rebaseCount;
}

PerturbResult iteratePerturbation(
    Complex!double delta_c,
    const ref ReferenceOrbit orbit,
    uint maxIterations
) {
    PerturbResult pr;
    pr.needsRefinement = false;
    pr.rebaseCount = 0;
    
    Complex!double delta = Complex!double(0.0, 0.0);
    
    int iter = 0;
    int refIter = 0;
    
    double escapeRadius2 = orbit.escapeRadius2;
    
    enum double REBASE_THRESHOLD = 1e-3;
    
    while (iter < maxIterations && refIter < orbit.refIterations) {
        auto Z_ref = getZRef(orbit, refIter);
        
        auto z = Z_ref + delta;
        double z_mag2 = z.re * z.re + z.im * z.im;
        
        if (z_mag2 > escapeRadius2) {
            double logZn = log(z_mag2) / 2.0;
            double nu = log(logZn / log(2.0)) / log(2.0);
            pr.result = IterResult(iter, iter + 1.0 - nu);
            return pr;
        }
        
        if (isNaN(delta.re) || isNaN(delta.im) || 
            isInfinity(delta.re) || isInfinity(delta.im)) {
            pr.needsRefinement = true;
            pr.result = IterResult(iter, cast(double)iter);
            return pr;
        }
        
        // Perturbation formula
        auto twoZ = Z_ref * 2.0;
        auto delta_sq = delta * delta;
        delta = twoZ * delta + delta_sq + delta_c;
        
        double delta_mag = sqrt(delta.re * delta.re + delta.im * delta.im);
        double Z_mag = sqrt(Z_ref.re * Z_ref.re + Z_ref.im * Z_ref.im);
        
        if (Z_mag > 0 && delta_mag / Z_mag > REBASE_THRESHOLD) {
            if (delta_mag > 1e10) {
                pr.needsRefinement = true;
            }
        }
        
        iter++;
        refIter++;
    }
    
    if (refIter >= orbit.refIterations && !orbit.escaped) {
        pr.result = IterResult(maxIterations, cast(double)maxIterations);
        return pr;
    }
    
    if (iter < maxIterations) {
        pr.needsRefinement = true;
    }
    
    pr.result = IterResult(iter, cast(double)iter);
    return pr;
}

void iterateRowPerturbation(
    ref IterResult[] results,
    int row,
    int width,
    const ref ReferenceOrbit orbit,
    double pixelSize,
    double originX,
    double originY,
    string refCenterXStr,
    string refCenterYStr,
    uint maxIterations
) {
    import gmp_arb : GMPFloat;
    
    double refX = 0, refY = 0;
    try {
        GMPFloat.setPrecisionDigits(orbit.precisionDigits);
        auto refXGMP = GMPFloat(refCenterXStr);
        auto refYGMP = GMPFloat(refCenterYStr);
        refX = refXGMP.toDouble();
        refY = refYGMP.toDouble();
    } catch (Exception) {
    }
    
    foreach (col; 0 .. width) {
        double px = originX + col * pixelSize;
        double py = originY + row * pixelSize;
        
        Complex!double delta_c = Complex!double(px - refX, py - refY);
        
        auto pr = iteratePerturbation(delta_c, orbit, maxIterations);
        
        if (pr.needsRefinement) {
            results[col] = pr.result;
            results[col].iterations = -1;
        } else {
            results[col] = pr.result;
        }
    }
}

bool shouldUsePerturbation(
    uint iterations,
    uint precisionDigits,
    bool isMandelbrot
) {
    if (!isMandelbrot) {
        return false;
    }
    
    if (iterations < PERTURBATION_ITERATION_THRESHOLD) {
        return false;
    }
    
    if (precisionDigits < PERTURBATION_MIN_DEPTH_DIGITS) {
        return false;
    }
    
    return true;
}

