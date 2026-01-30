/**
 * Reference Orbit Computation
 */
module calc.perturbation.reference;

import std.complex : Complex;
import calc.types.mpfr : GMPFloat, GMPComplex;
import precision.constants;

struct ReferenceOrbit {
    Complex!double[] zRef;
    GMPComplex[] zRefHP;
    string cRealStr;
    string cImagStr;

    int refIterations;
    
    bool escaped;
    double escapeRadius2 = 4.0;
    uint precisionDigits;
}

ReferenceOrbit computeReferenceOrbit(
    string cRealStr,
    string cImagStr,
    uint maxIterations,
    uint precisionDigits,
    bool storeHighPrecision = false
) {
    import std.stdio : writeln, stdout;
    
    ReferenceOrbit result;
    result.cRealStr = cRealStr;
    result.cImagStr = cImagStr;
    result.precisionDigits = precisionDigits;
    result.escapeRadius2 = 4.0;
    
    GMPFloat.setPrecisionDigits(precisionDigits);
    
    auto c = GMPComplex(cRealStr, cImagStr);
    auto z = GMPComplex.zero();
    
    result.zRef = new Complex!double[](maxIterations + 1);
    if (storeHighPrecision) {
        result.zRefHP.reserve(maxIterations + 1);
    }
    
    result.zRef[0] = Complex!double(0.0, 0.0);
    
    for (uint iter = 0; iter < maxIterations; iter++) {
        z.squareAndAdd(c);
        
        double zr = z.re.toDouble();
        double zi = z.im.toDouble();
        result.zRef[iter + 1] = Complex!double(zr, zi);
        
        double mag2 = zr * zr + zi * zi;
        if (mag2 > result.escapeRadius2) {
            result.escaped = true;
            result.refIterations = iter + 1;
            
            result.zRef = result.zRef[0 .. iter + 2];
            return result;
        }
    }
    
    result.escaped = false;
    result.refIterations = maxIterations;
    return result;
}

Complex!double getZRef(const ref ReferenceOrbit orbit, int n) {
    if (n < 0 || n >= orbit.zRef.length) {
        return Complex!double(0.0, 0.0);
    }
    return orbit.zRef[n];
}

