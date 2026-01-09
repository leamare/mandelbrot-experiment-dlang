module types.iter_result;

struct IterResult {
    int iterations;
    double smoothed;
    
    this(int i, double s) {
        iterations = i;
        smoothed = s;
    }
}

