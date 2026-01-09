module config.animation;

import std.json;
import std.conv : to;
import std.format : format;
import std.math : pow, abs;

import config.params;
import config.json_loader;
import config.filename;

void generateAnimateSequence(ref RenderParams[] queue, JSONValue obj) {
    int frames = to!int(obj["animate"].integer);
    if (frames <= 0) return;
    
    JSONValue fromObj = obj["from"];
    JSONValue toObj = obj["to"];
    
    RenderParams fromDesc = createBrotDesc(fromObj);
    RenderParams toDesc = createBrotDesc(toObj);
    
    for (int f = 0; f < frames; f++) {
        double t = cast(double)f / cast(double)(frames - 1);
        
        RenderParams frameDesc = fromDesc;
        
        frameDesc.originX = interpolate(fromDesc.originX, toDesc.originX, t);
        frameDesc.originY = interpolate(fromDesc.originY, toDesc.originY, t);
        
        double logFrom = log10Safe(fromDesc.radius);
        double logTo = log10Safe(toDesc.radius);
        double logRadius = interpolate(logFrom, logTo, t);
        frameDesc.radius = pow(10.0, logRadius);
        
        frameDesc.originXStr = format!"%.20g"(frameDesc.originX);
        frameDesc.originYStr = format!"%.20g"(frameDesc.originY);
        frameDesc.radiusStr = format!"%.20g"(frameDesc.radius);
        
        if (fromDesc.dwell != toDesc.dwell) {
            frameDesc.dwell = cast(uint)interpolate(
                cast(double)fromDesc.dwell, 
                cast(double)toDesc.dwell, 
                t
            );
        }
        
        frameDesc.filename = format!"frame_%05d"(f);
        
        queue ~= frameDesc;
    }
}

void generateChunksSequence(ref RenderParams[] queue, JSONValue obj) {
    int chunks = to!int(obj["chunks"].integer);
    if (chunks <= 0) return;
    
    RenderParams baseDesc = createBrotDesc(obj);
    
    int totalWidth = baseDesc.width;
    int totalHeight = baseDesc.height;
    int chunkWidth = totalWidth / chunks;
    int chunkHeight = totalHeight / chunks;
    
    for (int cy = 0; cy < chunks; cy++) {
        for (int cx = 0; cx < chunks; cx++) {
            RenderParams chunkDesc = baseDesc;
            
            int offsetX = cx * chunkWidth - totalWidth / 2 + chunkWidth / 2;
            int offsetY = cy * chunkHeight - totalHeight / 2 + chunkHeight / 2;
            
            chunkDesc.width = chunkWidth;
            chunkDesc.height = chunkHeight;
            chunkDesc.x_px_offset = offsetX;
            chunkDesc.y_px_offset = offsetY;
            
            chunkDesc.filename = format!"%s_chunk_%d_%d"(
                baseDesc.filename.length > 0 ? baseDesc.filename : "render",
                cx, cy
            );
            
            queue ~= chunkDesc;
        }
    }
}

private T interpolate(T)(T a, T b, double t) {
    return cast(T)(a + (b - a) * t);
}

private double log10Safe(real x) {
    import std.math : log10;
    if (x <= 0) return -300;
    return log10(cast(double)abs(x));
}

