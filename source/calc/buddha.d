module calc.buddha;

struct BuddhaAccumulator {
    private int[][] globalData;
    private int width, height;
    
    this(int w, int h) {
        width = w;
        height = h;
        globalData = new int[][](w, h);
        foreach (ref row; globalData) {
            row[] = 0;
        }
    }
    
    int[][] createLocalBuffer() {
        auto local = new int[][](width, height);
        foreach (ref row; local) {
            row[] = 0;
        }
        return local;
    }
    
    void mergeLocal(int[][] local) {
        foreach (x; 0 .. width) {
            foreach (y; 0 .. height) {
                globalData[x][y] += local[x][y];
            }
        }
    }
    
    static void recordHit(ref int[][] buffer, int x, int y, int width, int height) {
        if (x >= 0 && x < width && y >= 0 && y < height) {
            buffer[x][y]++;
        }
    }
    
    int maxHits() {
        int maxVal = 0;
        foreach (row; globalData) {
            foreach (val; row) {
                if (val > maxVal) maxVal = val;
            }
        }
        return maxVal;
    }

    int percentileHits(double percentile) {
        import std.algorithm : sort;
        import std.array : array;
        
        int[] hits;
        foreach (row; globalData) {
            foreach (val; row) {
                if (val > 0) {
                    hits ~= val;
                }
            }
        }
        
        if (hits.length == 0) return 0;
        
        hits.sort();
        
        size_t idx = cast(size_t)((hits.length - 1) * percentile);
        if (idx >= hits.length) idx = hits.length - 1;
        
        return hits[idx];
    }
    
    double averageBackgroundHits() {
        long totalHits = 0;
        int nonZeroCount = 0;
        
        foreach (row; globalData) {
            foreach (val; row) {
                if (val > 0) {
                    totalHits += val;
                    nonZeroCount++;
                }
            }
        }
        
        if (nonZeroCount == 0) return 0.0;
        return cast(double)totalHits / nonZeroCount;
    }
    
    int minNonZeroHits() {
        int minVal = int.max;
        bool found = false;
        
        foreach (row; globalData) {
            foreach (val; row) {
                if (val > 0) {
                    if (val < minVal) minVal = val;
                    found = true;
                }
            }
        }
        
        return found ? minVal : 0;
    }
    
    ref int[][] data() { return globalData; }
}

