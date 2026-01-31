/**
 * Palette Loader
 * 
 * JSON Format:
 * {
 *   "format": "rgb" or "float",  // Optional: "rgb" for 0-255, "float" for 0-1
 *   "colors": [                   // Or just an array at root level
 *     {"r": 255, "g": 0, "b": 0},
 *     ...
 *   ]
 * }
 */

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

enum PaletteFormat {
    auto_,
    rgb,
    float_
}

struct PalettePoint {
    float r, g, b;
    float position;
}

public struct PaletteMetadata {
    float rOffset = 0.0;
    float gOffset = 0.0;
    float bOffset = 0.0;
    float rMultiplier = 1.0;
    float gMultiplier = 1.0;
    float bMultiplier = 1.0;
    float rBase = 0.5;
    float gBase = 0.5;
    float bBase = 0.5;
    float rRange = 0.5;
    float gRange = 0.5;
    float bRange = 0.5;
    bool useSineWave = false;
}

Color4f[] loadPaletteFromFile(string filename) {
    auto result = loadPaletteImpl(filename, false);
    return result is null ? null : result.colors;
}

Color4f[] loadPaletteFromFileSilent(string filename) {
    auto result = loadPaletteImpl(filename, true);
    return result is null ? null : result.colors;
}

private struct PaletteLoadResult {
    Color4f[] colors;
    PaletteMetadata metadata;
}

public struct PaletteInfo {
    Color4f[] colors;
    PaletteMetadata metadata;
}

private PaletteLoadResult* loadPaletteImpl(string filename, bool silent) {
    string paletteDir = "palettes";
    string filePath = buildPath(paletteDir, filename);
    
    if (!exists(filePath)) {
        return null;
    }
    
    try {
        string content = readText(filePath);
        JSONValue json = parseJSON(content);
        
        JSONValue colorsJson;
        PaletteFormat format = PaletteFormat.auto_;
        
        if (json.type == JSONType.object) {
            // Check for format field
            if ("format" in json && json["format"].type == JSONType.string) {
                string formatStr = json["format"].str.toLower();
                if (formatStr == "rgb" || formatStr == "rgb255" || formatStr == "255") {
                    format = PaletteFormat.rgb;
                } else if (formatStr == "float" || formatStr == "fraction" || formatStr == "normalized") {
                    format = PaletteFormat.float_;
                }
            }
            
            // Get colors array
            if ("colors" in json && json["colors"].type == JSONType.array) {
                colorsJson = json["colors"];
            } else {
                writeln("ERROR: Palette object must have 'colors' array");
                return null;
            }
        } else if (json.type == JSONType.array) {
            colorsJson = json;
        } else {
            writeln("ERROR: Palette file '", filePath, "' must contain a JSON array or object");
            return null;
        }
        
        Color4f[] palette;
        PalettePoint[] points;
        bool hasPosition = false;
        
        foreach (pointJson; colorsJson.array) {
            if (pointJson.type != JSONType.object) {
                writeln("WARNING: Skipping invalid palette point (not an object)");
                continue;
            }
            
            PalettePoint point;
            
            if ("r" in pointJson && "g" in pointJson && "b" in pointJson) {
                auto rVal = pointJson["r"];
                auto gVal = pointJson["g"];
                auto bVal = pointJson["b"];
                
                PaletteFormat useFormat = format;
                
                if (useFormat == PaletteFormat.auto_) {
                    double maxVal = max(getJsonNumber(rVal), max(getJsonNumber(gVal), getJsonNumber(bVal)));
                    if (maxVal > 1.0) {
                        useFormat = PaletteFormat.rgb;
                    } else {
                        useFormat = PaletteFormat.float_;
                    }
                }
                
                if (useFormat == PaletteFormat.rgb) {
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

        PaletteMetadata metadata;
        if (json.type == JSONType.object) {
            if ("metadata" in json && json["metadata"].type == JSONType.object) {
                auto metaJson = json["metadata"];
                if ("rOffset" in metaJson) metadata.rOffset = cast(float)getJsonNumber(metaJson["rOffset"]);
                if ("gOffset" in metaJson) metadata.gOffset = cast(float)getJsonNumber(metaJson["gOffset"]);
                if ("bOffset" in metaJson) metadata.bOffset = cast(float)getJsonNumber(metaJson["bOffset"]);
                if ("rMultiplier" in metaJson) metadata.rMultiplier = cast(float)getJsonNumber(metaJson["rMultiplier"]);
                if ("gMultiplier" in metaJson) metadata.gMultiplier = cast(float)getJsonNumber(metaJson["gMultiplier"]);
                if ("bMultiplier" in metaJson) metadata.bMultiplier = cast(float)getJsonNumber(metaJson["bMultiplier"]);
                if ("rBase" in metaJson) metadata.rBase = cast(float)getJsonNumber(metaJson["rBase"]);
                if ("gBase" in metaJson) metadata.gBase = cast(float)getJsonNumber(metaJson["gBase"]);
                if ("bBase" in metaJson) metadata.bBase = cast(float)getJsonNumber(metaJson["bBase"]);
                if ("rRange" in metaJson) metadata.rRange = cast(float)getJsonNumber(metaJson["rRange"]);
                if ("gRange" in metaJson) metadata.gRange = cast(float)getJsonNumber(metaJson["gRange"]);
                if ("bRange" in metaJson) metadata.bRange = cast(float)getJsonNumber(metaJson["bRange"]);
                if ("useSineWave" in metaJson && metaJson["useSineWave"].type == JSONType.true_) {
                    metadata.useSineWave = true;
                }
            }
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
        
        PaletteLoadResult* result = new PaletteLoadResult;
        result.colors = palette;
        result.metadata = metadata;
        return result;
    } catch (Exception e) {
        if (!silent) {
            writeln("ERROR: Failed to load palette from '", filePath, "': ", e.msg);
        }
        return null;
    }
}

public PaletteInfo* getPaletteInfo(string filename, bool reverse) {
    import std.path : buildPath;
    import std.file : exists;
    
    if (filename.length == 0) return null;
    
    string paletteDir = "palettes";
    string filePath = buildPath(paletteDir, filename);
    
    if (!exists(filePath)) return null;
    
    auto result = loadPaletteImpl(filename, true);
    if (result is null) return null;
    
    PaletteInfo* info = new PaletteInfo;
    info.colors = result.colors;
    if (reverse) {
        info.colors = reversePalette(result.colors);
    }
    info.metadata = result.metadata;
    return info;
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

bool paletteFileExists(string filename) {
    import std.file : exists;
    string paletteDir = "palettes";
    string filePath = buildPath(paletteDir, filename);
    return exists(filePath);
}
