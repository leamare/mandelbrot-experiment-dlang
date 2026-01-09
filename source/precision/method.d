/**
 * Precision Methods
 */
module precision.method;

import std.string : toLower, strip;
import precision.constants;

enum PrecisionMethod {
    auto_,
    double_,
    quaddouble,
    mpfr
}

enum PerturbationMode {
    auto_,
    enabled,
    disabled
}

PrecisionMethod parsePrecisionMethod(string method) {
    string m = method.toLower().strip();
    switch (m) {
        case "auto":
        case "auto_":
            return PrecisionMethod.auto_;
        case "double":
        case "double_":
        case "standard":
            return PrecisionMethod.double_;
        case "quaddouble":
        case "qd":
        case "quad":
        case "bigfloat":
        case "dd":
        case "doubledouble":
            return PrecisionMethod.quaddouble;
        case "mpfr":
        case "gmp":
        case "arbitrary":
        case "bigint":
            return PrecisionMethod.mpfr;
        default:
            return PrecisionMethod.auto_;
    }
}

PerturbationMode parsePerturbationMode(string mode) {
    string m = mode.toLower().strip();
    switch (m) {
        case "auto":
        case "auto_":
            return PerturbationMode.auto_;
        case "enabled":
        case "on":
        case "true":
        case "yes":
            return PerturbationMode.enabled;
        case "disabled":
        case "off":
        case "false":
        case "no":
            return PerturbationMode.disabled;
        default:
            return PerturbationMode.auto_;
    }
}

PrecisionMethod selectPrecisionMethod(uint requiredDigits) {
    if (requiredDigits <= PRECISION_THRESHOLD_DOUBLE) {
        return PrecisionMethod.double_;
    } else if (requiredDigits <= PRECISION_THRESHOLD_QUADDOUBLE) {
        return PrecisionMethod.quaddouble;
    } else {
        return PrecisionMethod.mpfr;
    }
}

bool shouldUsePerturbation(
    PerturbationMode mode,
    uint iterations,
    uint depthDigits,
    bool supportedFractal = true
) {
    if (!supportedFractal) {
        return false;
    }
    
    final switch (mode) {
        case PerturbationMode.enabled:
            return true;
        case PerturbationMode.disabled:
            return false;
        case PerturbationMode.auto_:
            // Use perturbation if:
            // 1. Iterations are high enough to benefit from skipping
            // 2. Zoom is deep enough that we need high precision anyway
            return iterations >= PERTURBATION_ITERATION_THRESHOLD &&
                   depthDigits >= PERTURBATION_MIN_DEPTH_DIGITS;
    }
}

string precisionMethodName(PrecisionMethod method) {
    final switch (method) {
        case PrecisionMethod.auto_:
            return "auto";
        case PrecisionMethod.double_:
            return "double";
        case PrecisionMethod.quaddouble:
            return "quaddouble";
        case PrecisionMethod.mpfr:
            return "mpfr";
    }
}

