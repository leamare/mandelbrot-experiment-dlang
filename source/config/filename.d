
module config.filename;

import std.format : format;
import std.conv : to;

import config.params;
import types.fractal;

string generateFileName(const ref RenderParams desc) {
    string name = "mandelbrot";
    
    if (desc.fractalType != FractalType.mandelbrot) {
        final switch (desc.fractalType) {
            case FractalType.mandelbrot: break;
            case FractalType.multibrot: name = format!"multibrot_e%.2f"(desc.multibrotExp); break;
            case FractalType.ship: name = "burning_ship"; break;
            case FractalType.mandelbar: name = "mandelbar"; break;
        }
    }
    
    if (desc.buddha != BuddhaMode.none) {
        string buddhaPrefix = desc.buddha == BuddhaMode.buddha ? "buddha_" : "antibuddha_";
        name = buddhaPrefix ~ name;
    }
    
    string xStr = desc.originX >= 0 ? format!"%.15g"(desc.originX) : format!"%.15g"(desc.originX);
    string yStr = format!"%.15g"(desc.originY);
    
    name ~= format!"_X=%s_Y=%s"(xStr, yStr);
    
    name ~= format!"_R=%s"(desc.radiusStr.length > 0 ? truncateStr(desc.radiusStr, 10) : format!"%.6g"(desc.radius));
    
    name ~= format!"_W=%d_H=%d"(desc.width, desc.height);
    
    name ~= format!"_I=%d_P=%d"(desc.dwell, desc.palette > 0 ? desc.palette : desc.dwell);
    
    name ~= format!"_C=%s"(to!string(desc.colorfunc));
    
    return name;
}

private string truncateStr(string s, size_t maxLen) {
    if (s.length <= maxLen) return s;
    return s[0 .. maxLen];
}

