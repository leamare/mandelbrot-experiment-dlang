/**
 * Unified Precision System
 * 
 * Provides a common interface for different precision types with automatic switching:
 * - double: Standard double precision (~15 decimal digits) - FASTEST
 * - bigfloat: Double-double precision (~31 decimal digits) - FAST
 * - bigint: Arbitrary precision using BigInt (~unlimited) - SLOW
 * - gmp: Arbitrary precision using GMP (~unlimited) - MEDIUM (optimized C library)
 * 
 * Automatically selects the fastest method that provides sufficient precision.
 */

module precision_unified;

import std.conv;
import std.string;
import std.math;
import std.algorithm;
import std.typecons;

// Import precision implementations
import bigfloat : DoubleDouble, DDComplex;
import multidouble : MultiDouble, MultiDoubleComplex, calculateNumDoubles;
import gmp_arb : GMPFloat, GMPComplex;  // GMP is a dependency, always available

// Complex number as tuple (matching mandel.d)
alias Complex = Tuple!(real, real);

/// Precision method selection
enum PrecisionMethod {
    auto_,      // Auto-select based on requirements (default)
    double_,    // Standard double precision
    bigfloat,   // Double-double precision (DoubleDouble)
    multidouble, // Multi-double precision (3-12 doubles)
    bigint,     // BigInt-based arbitrary precision (not yet implemented)
    gmp         // GMP-based arbitrary precision
}

/// Parse precision method from string
PrecisionMethod parsePrecisionMethod(string method) {
    string m = method.toLower().strip();
    if (m == "auto" || m == "auto_") return PrecisionMethod.auto_;
    if (m == "double" || m == "double_") return PrecisionMethod.double_;
    if (m == "bigfloat" || m == "dd" || m == "doubledouble") return PrecisionMethod.bigfloat;
    if (m == "multidouble" || m == "md") return PrecisionMethod.multidouble;
    if (m == "bigint" || m == "arbitrary") return PrecisionMethod.bigint;
    if (m == "gmp" || m == "arbitrary_gmp") return PrecisionMethod.gmp;
    return PrecisionMethod.auto_;  // Default to auto
}

/// Select appropriate precision method based on required decimal digits
/// Uses gradual progression: double -> bigfloat -> multidouble -> GMP/bigint
/// 
/// Parameters:
///   requiredDigits: Number of decimal digits required
///   arbitraryMethod: Which arbitrary precision method to use for very high precision
///                    (PrecisionMethod.gmp or PrecisionMethod.bigint)
/// 
/// Thresholds (can be overridden by importing flow.d constants):
///   - 0-15 digits: double
///   - 16-50 digits: bigfloat (double-double) - Theoretical: ~31 digits, Practical: ~50 digits
///   - 51-240 digits: multidouble (3-12 doubles) - Theoretical: ~180 digits (12 doubles), Practical: ~240 digits
///   - 241+ digits: GMP/bigint
PrecisionMethod selectPrecisionMethod(uint requiredDigits, PrecisionMethod arbitraryMethod = PrecisionMethod.gmp) {
    // Import thresholds from flow.d if available, otherwise use defaults
    version (HaveFlowConstants) {
        import flow : PRECISION_THRESHOLD_DOUBLE, PRECISION_THRESHOLD_BIGFLOAT, 
                      PRECISION_THRESHOLD_MULTIDOUBLE, PRECISION_THRESHOLD_GMP;
        enum uint THRESHOLD_DOUBLE = PRECISION_THRESHOLD_DOUBLE;
        enum uint THRESHOLD_BIGFLOAT = PRECISION_THRESHOLD_BIGFLOAT;
        enum uint THRESHOLD_MULTIDOUBLE = PRECISION_THRESHOLD_MULTIDOUBLE;
        enum uint THRESHOLD_GMP = PRECISION_THRESHOLD_GMP;
    } else {
        enum uint THRESHOLD_DOUBLE = 15;
        enum uint THRESHOLD_BIGFLOAT = 32;
        enum uint THRESHOLD_MULTIDOUBLE = 240;
        enum uint THRESHOLD_GMP = 241;
    }
    
    if (requiredDigits <= THRESHOLD_DOUBLE) {
        return PrecisionMethod.double_;  // Fastest for low precision
    } else if (requiredDigits <= THRESHOLD_BIGFLOAT) {
        return PrecisionMethod.bigfloat;  // Double-double precision (~31 digits)
    } else if (requiredDigits <= THRESHOLD_MULTIDOUBLE) {
        return PrecisionMethod.multidouble;  // Multi-double precision (3-12 doubles, ~33-180 digits)
    } else {
        // For very high precision (>THRESHOLD_MULTIDOUBLE digits), use specified arbitrary precision method
        // Default is GMP (faster), but can be set to bigint if preferred
        return arbitraryMethod;
    }
}

/// Unified complex number wrapper
/// Automatically uses the fastest precision method that meets requirements
struct UnifiedComplex {
    private Complex _double;
    private DDComplex _bigfloat;
    private MultiDoubleComplex _multidouble;
    private GMPComplex _gmp;
    private PrecisionMethod _method;
    private bool _isDouble;
    private bool _isBigFloat;
    private bool _isMultiDouble;
    private bool _isGMP;
    
    /// Create from method and strings
    this(PrecisionMethod method, string realStr, string imagStr) {
        _method = method;
        _isDouble = false;
        _isBigFloat = false;
        _isMultiDouble = false;
        _isGMP = false;
        
        final switch (method) {
            case PrecisionMethod.double_:
                _double = Complex(to!double(realStr), to!double(imagStr));
                _isDouble = true;
                break;
            case PrecisionMethod.bigfloat:
                _bigfloat = DDComplex(DoubleDouble(realStr), DoubleDouble(imagStr));
                _isBigFloat = true;
                break;
            case PrecisionMethod.multidouble:
                uint numDoubles = calculateNumDoubles(cast(uint)max(realStr.length, imagStr.length));
                _multidouble = MultiDoubleComplex(numDoubles, realStr, imagStr);
                _isMultiDouble = true;
                break;
            case PrecisionMethod.gmp:
                _gmp = GMPComplex(realStr, imagStr);
                _isGMP = true;
                break;
            case PrecisionMethod.bigint:
                // BigInt not yet implemented, fall back to GMP
                _gmp = GMPComplex(realStr, imagStr);
                _method = PrecisionMethod.gmp;
                _isGMP = true;
                break;
            case PrecisionMethod.auto_:
                // Should not reach here - auto should be resolved before construction
                _double = Complex(to!double(realStr), to!double(imagStr));
                _method = PrecisionMethod.double_;
                _isDouble = true;
                break;
        }
    }
    
    /// Create from method and doubles (with optional required digits for multidouble)
    this(PrecisionMethod method, double realVal, double imagVal, uint requiredDigits = 0) {
        _method = method;
        _isDouble = false;
        _isBigFloat = false;
        _isMultiDouble = false;
        _isGMP = false;
        
        final switch (method) {
            case PrecisionMethod.double_:
                _double = Complex(realVal, imagVal);
                _isDouble = true;
                break;
            case PrecisionMethod.bigfloat:
                _bigfloat = DDComplex(DoubleDouble(realVal), DoubleDouble(imagVal));
                _isBigFloat = true;
                break;
            case PrecisionMethod.multidouble:
                uint numDoubles = requiredDigits > 0 ? calculateNumDoubles(requiredDigits) : 3;
                _multidouble = MultiDoubleComplex(numDoubles, realVal, imagVal);
                _isMultiDouble = true;
                break;
            case PrecisionMethod.gmp:
                _gmp = GMPComplex(realVal, imagVal);
                _isGMP = true;
                break;
            case PrecisionMethod.bigint:
                _gmp = GMPComplex(realVal, imagVal);
                _method = PrecisionMethod.gmp;
                _isGMP = true;
                break;
            case PrecisionMethod.auto_:
                _double = Complex(realVal, imagVal);
                _method = PrecisionMethod.double_;
                _isDouble = true;
                break;
        }
    }
    
    /// Get current method
    PrecisionMethod method() const {
        return _method;
    }
    
    /// Convert to double complex (may lose precision)
    Complex toDoubleComplex() const {
        if (_isDouble) {
            return _double;
        } else if (_isBigFloat) {
            return Complex(_bigfloat.re.toDouble(), _bigfloat.im.toDouble());
        } else if (_isMultiDouble) {
            return _multidouble.toDoubleComplex();
        } else if (_isGMP) {
            return Complex(_gmp.re.toDouble(), _gmp.im.toDouble());
        } else {
            return _double;  // Fallback
        }
    }
    
    /// Magnitude squared (as double, for escape checks)
    double magnitudeSquaredDouble() const {
        if (_isDouble) {
            return _double[0] * _double[0] + _double[1] * _double[1];
        } else if (_isBigFloat) {
            return _bigfloat.magnitudeSquared().toDouble();
        } else if (_isMultiDouble) {
            return _multidouble.magnitudeSquared();
        } else if (_isGMP) {
            return _gmp.magnitudeSquaredDouble();
        } else {
            return _double[0] * _double[0] + _double[1] * _double[1];  // Fallback
        }
    }
    
    /// In-place square and add: z = z² + c (optimized)
    void squareAndAdd(UnifiedComplex c) {
        // Both must use same method
        if (_method != c._method) {
            // Convert c to this method (expensive, but necessary)
            auto cDouble = c.toDoubleComplex();
            if (_isDouble) {
                _double = Complex(
                    _double[0] * _double[0] - _double[1] * _double[1] + cDouble[0],
                    2.0 * _double[0] * _double[1] + cDouble[1]
                );
            } else if (_isBigFloat) {
                _bigfloat = _bigfloat.square() + DDComplex(DoubleDouble(cDouble[0]), DoubleDouble(cDouble[1]));
            } else if (_isMultiDouble) {
                _multidouble.squareAndAdd(MultiDoubleComplex(_multidouble.re.numComponents(), cDouble[0], cDouble[1]));
            } else if (_isGMP) {
                _gmp.squareAndAdd(GMPComplex(cDouble[0], cDouble[1]));
            }
            return;
        }
        
        // Same method - use optimized path
        if (_isDouble) {
            _double = Complex(
                _double[0] * _double[0] - _double[1] * _double[1] + c._double[0],
                2.0 * _double[0] * _double[1] + c._double[1]
            );
        } else if (_isBigFloat) {
            _bigfloat = _bigfloat.square() + c._bigfloat;
        } else if (_isMultiDouble) {
            _multidouble.squareAndAdd(c._multidouble);
        } else if (_isGMP) {
            _gmp.squareAndAdd(c._gmp);
        }
    }
    
    /// Zero complex
    static UnifiedComplex zero(PrecisionMethod method, uint requiredDigits = 0) {
        switch (method) {
            case PrecisionMethod.double_:
                return UnifiedComplex(method, 0.0, 0.0);
            case PrecisionMethod.bigfloat:
                return UnifiedComplex(method, 0.0, 0.0);
            case PrecisionMethod.multidouble:
                return UnifiedComplex(method, 0.0, 0.0, requiredDigits);
            case PrecisionMethod.gmp:
                return UnifiedComplex(method, 0.0, 0.0);
            case PrecisionMethod.bigint:
                return UnifiedComplex(PrecisionMethod.gmp, 0.0, 0.0);
            default:
                return UnifiedComplex(PrecisionMethod.double_, 0.0, 0.0);
        }
    }
}

/// Factory: Create unified complex with auto-selection
UnifiedComplex createUnifiedComplex(
    string realStr,
    string imagStr,
    uint requiredDigits = 0,
    PrecisionMethod overrideMethod = PrecisionMethod.auto_
) {
    PrecisionMethod method = overrideMethod;
    
    // Auto-select if needed
    if (method == PrecisionMethod.auto_) {
        if (requiredDigits == 0) {
            // Estimate from string precision
            requiredDigits = estimatePrecisionFromString(realStr, imagStr);
        }
        method = selectPrecisionMethod(requiredDigits);
    }
    
    return UnifiedComplex(method, realStr, imagStr);
}

/// Estimate required precision from coordinate strings
uint estimatePrecisionFromString(string realStr, string imagStr) {
    // Count significant digits
    uint maxDigits = 0;
    
    foreach (str; [realStr, imagStr]) {
        str = str.strip();
        if (str.length == 0) continue;
        
        // Find decimal point
        auto dotPos = str.indexOf('.');
        if (dotPos >= 0) {
            // Count digits after decimal point
            uint digits = 0;
            for (size_t i = dotPos + 1; i < str.length; i++) {
                if (str[i] >= '0' && str[i] <= '9') {
                    digits++;
                } else if (str[i] == 'e' || str[i] == 'E') {
                    break;
                }
            }
            maxDigits = max(maxDigits, digits);
        }
        
        // Check for scientific notation
        auto ePos = str.countUntil!(c => c == 'e' || c == 'E')();
        if (ePos >= 0) {
            try {
                int exp = to!int(str[ePos + 1 .. $]);
                if (exp < 0) {
                    // Very small number - need high precision
                    maxDigits = max(maxDigits, cast(uint)(-exp + 15));
                }
            } catch (Exception) {}
        }
    }
    
    return maxDigits;
}

