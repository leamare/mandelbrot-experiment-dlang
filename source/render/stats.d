module render.stats;

import std.stdio : writeln, stdout;
import std.format : format;
import types.iter_result;

void displayIterationStats(const ref IterResult[][] iters, int width, int height, uint maxIterations) {
    int minIter = int.max;
    int maxIter = int.min;
    long totalIter = 0;
    long pixelCount = 0;
    long maxIterCount = 0;
    
    foreach (i; 0 .. width) {
        foreach (j; 0 .. height) {
            int iter = iters[i][j].iterations;
            if (iter < minIter) minIter = iter;
            if (iter > maxIter) maxIter = iter;
            totalIter += iter;
            pixelCount++;
            if (iter >= maxIterations) maxIterCount++;
        }
    }
    
    if (pixelCount == 0) {
        writeln("\nIteration stats: No pixels computed");
        return;
    }
    
    if (minIter == int.max) minIter = 0;
    if (maxIter == int.min) maxIter = 0;
    
    double avgIter = cast(double)totalIter / cast(double)pixelCount;
    double inSetPercent = 100.0 * cast(double)maxIterCount / cast(double)pixelCount;
    
    writeln("\nIteration stats:");
    writeln("  Min iterations: ", minIter);
    writeln("  Max iterations: ", maxIter);
    writeln("  Avg iterations: ", format!"%.1f"(avgIter));
    writeln("  Pixels in set:  ", maxIterCount, " / ", pixelCount, 
            " (", format!"%.1f"(inSetPercent), "%)");
    stdout.flush();
}

