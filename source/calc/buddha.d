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
    
    ref int[][] data() { return globalData; }
}

