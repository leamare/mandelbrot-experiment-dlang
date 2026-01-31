/**
 * Animation and Chunking
 */
module config.animation;

import std.json;
import std.conv : to;
import std.format : format;
import std.math : log, exp, pow;
import std.algorithm : min, max;
import std.file : exists, mkdir;

import config.params;
import config.json_loader : createBrotDesc;
import config.filename;
import types.fractal;
import calc.types.mpfr : GMPFloat;
import utils.precision_auto : combinedPrecisionDigits;

void generateAnimateSequence(ref RenderParams[] queue, JSONValue animate, string workdir) {
    const int frames = to!int(animate["animate"].integer);
    const int skip = "skip" in animate ? to!int(animate["skip"].integer) : 0;
    const RenderParams fromParams = createBrotDesc(animate["from"]);
    const RenderParams toParams = createBrotDesc(animate["to"]);
    const int w = fromParams.width;
    const int h = fromParams.height;

    const string fpath = "animate_FRAMES=" ~ to!string(frames) ~ 
        "_W=" ~ to!string(w) ~ "_H=" ~ to!string(h) ~
        "_X0=" ~ format!"%.17g"(fromParams.originX) ~ "_Y0=" ~ 
        format!"%.17g"(fromParams.originY) ~ "_Rn=" ~ format!"%.17g"(toParams.radius) ~ "/";

    if (!(workdir ~ "/" ~ fpath).exists) (workdir ~ "/" ~ fpath).mkdir;

    bool needsHighPrecision = (fromParams.determinePrecisionMode() == PrecisionMode.arbitrary) ||
                              (toParams.determinePrecisionMode() == PrecisionMode.arbitrary);
    
    if (needsHighPrecision) {
        uint fromDigits = combinedPrecisionDigits(
            fromParams.originXStr, fromParams.originYStr, fromParams.radiusStr, fromParams.radius
        );
        uint toDigits = combinedPrecisionDigits(
            toParams.originXStr, toParams.originYStr, toParams.radiusStr, toParams.radius
        );
        uint digits = max(fromDigits, toDigits);
        GMPFloat.setPrecisionDigits(digits + 20);
        
        auto fromX = GMPFloat(fromParams.originXStr);
        auto fromY = GMPFloat(fromParams.originYStr);
        auto toX = GMPFloat(toParams.originXStr);
        auto toY = GMPFloat(toParams.originYStr);
        auto framesGMP = GMPFloat(cast(double)frames);
        
        auto deltaX = (toX - fromX) / framesGMP;
        auto deltaY = (toY - fromY) / framesGMP;
        
        double logFromR = log(fromParams.radius);
        double logToR = log(toParams.radius);
        double deltaLogR = (logToR - logFromR) / cast(double)frames;
        
        float deltaDwell = (log(cast(double)toParams.dwell) - log(cast(double)fromParams.dwell)) / cast(double)frames;
        float deltaPalette = (log(cast(double)(toParams.palette ? toParams.palette : toParams.dwell)) - 
            log(cast(double)(fromParams.palette ? fromParams.palette : fromParams.dwell))) / cast(double)frames;
        float deltaExp = (toParams.multibrotExp - fromParams.multibrotExp) / cast(double)frames;
        
        for (int i = 0; i <= frames; i++) {
            if (i < skip) continue;
            
            RenderParams ret;
            ret.width = w;
            ret.height = h;
            
            auto iGMP = GMPFloat(cast(double)i);
            auto currentX = fromX + deltaX * iGMP;
            auto currentY = fromY + deltaY * iGMP;
            
            ret.originXStr = currentX.toString();
            ret.originYStr = currentY.toString();
            ret.radius = exp(logFromR + deltaLogR * i);
            ret.radiusStr = format!"%.20g"(ret.radius);
            
            try {
                ret.originX = to!real(ret.originXStr);
                ret.originY = to!real(ret.originYStr);
            } catch (Exception) {
                ret.originX = currentX.toDouble();
                ret.originY = currentY.toDouble();
            }
            
            ret.dwell = cast(uint)exp(log(cast(double)fromParams.dwell) + deltaDwell * i);
            ret.palette = cast(int)exp(log(cast(double)fromParams.palette) + deltaPalette * i);
            ret.multibrotExp = fromParams.multibrotExp + (deltaExp * i);
            
            ret.fractalType = fromParams.fractalType;
            ret.colorfunc = fromParams.colorfunc;
            ret.buddha = fromParams.buddha;
            ret.filename = fpath ~ "frame_" ~ format!"%06d"(i);

            queue ~= ret;
        }
    } else {
        double deltaX = (toParams.originX - fromParams.originX) / cast(double)frames;
        double deltaY = (toParams.originY - fromParams.originY) / cast(double)frames;
        double deltaRadius = (log(toParams.radius) - log(fromParams.radius)) / cast(double)frames;
        float deltaDwell = (log(cast(double)toParams.dwell) - log(cast(double)fromParams.dwell)) / cast(double)frames;
        float deltaPalette = (log(cast(double)(toParams.palette ? toParams.palette : toParams.dwell)) - 
            log(cast(double)(fromParams.palette ? fromParams.palette : fromParams.dwell))) / cast(double)frames;
        float deltaExp = (toParams.multibrotExp - fromParams.multibrotExp) / cast(double)frames;
        
        for (int i = 0; i <= frames; i++) {
            if (i < skip) continue;
            
            RenderParams ret;
            ret.width = w;
            ret.height = h;
            ret.originX = fromParams.originX + deltaX * i;
            ret.originY = fromParams.originY + deltaY * i;
            ret.radius = exp(log(fromParams.radius) + deltaRadius * i);
            
            ret.originXStr = format!"%.20g"(ret.originX);
            ret.originYStr = format!"%.20g"(ret.originY);
            ret.radiusStr = format!"%.20g"(ret.radius);
            
            ret.dwell = cast(uint)exp(log(cast(double)fromParams.dwell) + deltaDwell * i);
            ret.palette = cast(int)exp(log(cast(double)fromParams.palette) + deltaPalette * i);
            ret.multibrotExp = fromParams.multibrotExp + (deltaExp * i);
            
            ret.fractalType = fromParams.fractalType;
            ret.colorfunc = fromParams.colorfunc;
            ret.buddha = fromParams.buddha;
            ret.filename = fpath ~ "frame_" ~ format!"%06d"(i);

            queue ~= ret;
        }
    }
}

void generateChunksSequence(ref RenderParams[] queue, JSONValue source, string workdir) {
    const int chunks = to!int(source["chunks"].integer);
    const RenderParams s = createBrotDesc(source);

    const string fpath = "CHUNKED=" ~ to!string(chunks) ~ "_" ~ s.filename ~ "/";

    if (!(workdir ~ "/" ~ fpath).exists) (workdir ~ "/" ~ fpath).mkdir;

    if (s.buddha != BuddhaMode.none) {
        if (!(workdir ~ "/" ~ to!string(s.buddha) ~ "_" ~ fpath).exists) 
            (workdir ~ "/" ~ to!string(s.buddha) ~ "_" ~ fpath).mkdir;
    }

    const int w = cast(int)(s.width / to!double(chunks));
    const int h = cast(int)(s.height / to!double(chunks));
    
    bool needsHighPrecision = s.determinePrecisionMode() == PrecisionMode.arbitrary;
    
    if (needsHighPrecision) {
        uint digits = combinedPrecisionDigits(s.originXStr, s.originYStr, s.radiusStr, s.radius);
        GMPFloat.setPrecisionDigits(digits + 20);
        
        auto originX = GMPFloat(s.originXStr);
        auto originY = GMPFloat(s.originYStr);
        auto radius = GMPFloat(s.radiusStr);
        
        auto diff = GMPFloat(cast(double)(min(w, h)) / max(w, h));
        auto chunksGMP = GMPFloat(cast(double)chunks);
        
        auto radiusX = (w > h) ? radius / chunksGMP : radius * diff / chunksGMP;
        auto radiusY = (w < h) ? radius / chunksGMP : radius * diff / chunksGMP;
        
        auto half = GMPFloat(cast(double)(chunks / 2 + 2));
        auto x1 = originX - radiusX * half;
        auto y1 = originY + radiusY * half;
        auto two = GMPFloat(2.0);
        
        for (int i = 0; i < chunks; i++) {
            for (int j = 0; j < chunks; j++) {
                RenderParams ret;
                ret.width = w;
                ret.height = h;
                
                auto jGMP = GMPFloat(cast(double)j + 0.5);
                auto iGMP = GMPFloat(cast(double)i + 0.5);
                auto chunkX = x1 + radiusX * two * jGMP;
                auto chunkY = y1 - radiusY * two * iGMP;
                
                ret.originXStr = chunkX.toString();
                ret.originYStr = chunkY.toString();
                
                auto chunkRadius = (radiusX.toDouble() < radiusY.toDouble()) ? radiusX : radiusY;
                ret.radiusStr = chunkRadius.toString();
                
                try {
                    ret.originX = to!real(ret.originXStr);
                    ret.originY = to!real(ret.originYStr);
                    ret.radius = to!real(ret.radiusStr);
                } catch (Exception) {
                    ret.originX = chunkX.toDouble();
                    ret.originY = chunkY.toDouble();
                    ret.radius = chunkRadius.toDouble();
                }
                
                ret.dwell = s.dwell;
                ret.palette = s.palette;
                ret.multibrotExp = s.multibrotExp;
                ret.fractalType = s.fractalType;
                ret.colorfunc = s.colorfunc;
                ret.buddha = s.buddha;
                ret.filename = fpath ~ "chunk_" ~ format!"%06d"(i * chunks + j);

                queue ~= ret;
            }
        }
    } else {
        double diff = cast(double)(min(w, h)) / max(w, h);
        double radiusX = s.radius * (w > h ? 1 : diff) / cast(double)chunks;
        double radiusY = s.radius * (w < h ? 1 : diff) / cast(double)chunks;

        double x1 = s.originX - (s.radius * (w > h ? 1 : diff) / cast(double)chunks) * (chunks / 2 + 2);
        double y1 = s.originY + (s.radius * (w < h ? 1 : diff) / cast(double)chunks) * (chunks / 2 + 2);
        
        for (int i = 0; i < chunks; i++) {
            for (int j = 0; j < chunks; j++) {
                RenderParams ret;
                ret.width = w;
                ret.height = h;
                ret.originX = x1 + radiusX * 2 * (j + 0.5);
                ret.originY = y1 - radiusY * 2 * (i + 0.5);
                ret.radius = min(radiusX, radiusY);
                
                ret.originXStr = format!"%.20g"(ret.originX);
                ret.originYStr = format!"%.20g"(ret.originY);
                ret.radiusStr = format!"%.20g"(ret.radius);

                ret.dwell = s.dwell;
                ret.palette = s.palette;
                ret.multibrotExp = s.multibrotExp;
                ret.fractalType = s.fractalType;
                ret.colorfunc = s.colorfunc;
                ret.buddha = s.buddha;
                ret.filename = fpath ~ "chunk_" ~ format!"%06d"(i * chunks + j);

                queue ~= ret;
            }
        }
    }
}
