module config.palette;

import std.stdio;
import std.json;
import std.conv;
import std.string;
import std.file;
import std.path;
import std.algorithm;
import std.math;
import dlib.image.color;

struct PalettePoint {
    float r, g, b;
    float position;
}

Color4f[] loadPaletteFromFile(string filename) {
    string paletteDir = "palettes";
    string filePath = buildPath(paletteDir, filename);
    
    if (!exists(filePath)) {
        return null;
    }
    
    try {
        string content = readText(filePath);
        JSONValue json = parseJSON(content);
        
        if (json.type != JSONType.array) {
            writeln("ERROR: Palette file '", filePath, "' must contain a JSON array");
            return null;
        }
        
        Color4f[] palette;
        PalettePoint[] points;
        bool hasPosition = false;
        
        foreach (pointJson; json.array) {
            if (pointJson.type != JSONType.object) {
                writeln("WARNING: Skipping invalid palette point (not an object)");
                continue;
            }
            
            PalettePoint point;
            
            if ("r" in pointJson && "g" in pointJson && "b" in pointJson) {
                auto rVal = pointJson["r"];
                auto gVal = pointJson["g"];
                auto bVal = pointJson["b"];
                
                bool isRGB = false;
                if (rVal.type == JSONType.integer && rVal.integer > 1) {
                    isRGB = true;
                } else if (gVal.type == JSONType.integer && gVal.integer > 1) {
                    isRGB = true;
                } else if (bVal.type == JSONType.integer && bVal.integer > 1) {
                    isRGB = true;
                } else if (rVal.type == JSONType.integer && rVal.integer >= 0 && 
                          gVal.type == JSONType.integer && gVal.integer >= 0 &&
                          bVal.type == JSONType.integer && bVal.integer >= 0) {
                    long maxVal = max(rVal.integer, max(gVal.integer, bVal.integer));
                    if (maxVal > 1) {
                        isRGB = true;
                    }
                }
                
                if (isRGB) {
                    point.r = cast(float)getJsonNumber(rVal) / 255.0f;
                    point.g = cast(float)getJsonNumber(gVal) / 255.0f;
                    point.b = cast(float)getJsonNumber(bVal) / 255.0f;
                } else {
                    point.r = cast(float)getJsonNumber(rVal);
                    point.g = cast(float)getJsonNumber(gVal);
                    point.b = cast(float)getJsonNumber(bVal);
                }
            } else {
                writeln("WARNING: Palette point missing r, g, b values");
                continue;
            }
            
            if ("position" in pointJson) {
                point.position = cast(float)getJsonNumber(pointJson["position"]);
                if (!hasPosition) hasPosition = true;
            } else {
                point.position = cast(float)points.length;
            }
            
            points ~= point;
        }
        
        if (points.length == 0) {
            writeln("ERROR: No valid color points found in palette file '", filePath, "'");
            return null;
        }
        
        if (hasPosition) {
            points.sort!((a, b) => a.position < b.position);
            
            const int paletteSize = 256;
            palette.length = paletteSize;
            
            for (int i = 0; i < paletteSize; i++) {
                float pos = cast(float)i / (paletteSize - 1);
                
                int idx = 0;
                for (int j = 0; j < cast(int)(points.length - 1); j++) {
                    if (pos >= points[j].position && pos <= points[j+1].position) {
                        idx = j;
                        break;
                    }
                }
                if (pos > points[$-1].position) {
                    idx = cast(int)(points.length - 2);
                }
                
                float t = 0.0f;
                if (points[idx+1].position != points[idx].position) {
                    t = (pos - points[idx].position) / (points[idx+1].position - points[idx].position);
                }
                
                palette[i] = Color4f(
                    points[idx].r + (points[idx+1].r - points[idx].r) * t,
                    points[idx].g + (points[idx+1].g - points[idx].g) * t,
                    points[idx].b + (points[idx+1].b - points[idx].b) * t
                );
            }
        } else {
            foreach (point; points) {
                palette ~= Color4f(point.r, point.g, point.b);
            }
        }
        
        writeln("Loaded palette from '", filePath, "' with ", palette.length, " colors");
        return palette;
        
    } catch (Exception e) {
        writeln("ERROR: Failed to load palette from '", filePath, "': ", e.msg);
        return null;
    }
}

private double getJsonNumber(JSONValue v) {
    if (v.type == JSONType.integer) {
        return cast(double)v.integer;
    } else if (v.type == JSONType.uinteger) {
        return cast(double)v.uinteger;
    } else if (v.type == JSONType.float_) {
        return v.floating;
    }
    return 0.0;
}

Color4f[] reversePalette(Color4f[] palette) {
    Color4f[] reversed;
    reversed.length = palette.length;
    for (size_t i = 0; i < palette.length; i++) {
        reversed[i] = palette[palette.length - 1 - i];
    }
    return reversed;
}

