module config.json_loader;

import std.json;
import std.conv : to;
import std.string : toLower;
import std.math : abs, sqrt;
import std.algorithm : min;

import config.params;
import types.fractal;

RenderParams createBrotDesc(JSONValue obj) {
    RenderParams desc;
    
    if ("width" in obj) desc.width = to!int(obj["width"].integer);
    if ("height" in obj) desc.height = to!int(obj["height"].integer);
    if ("amp" in obj) {
        int amp = to!int(obj["amp"].integer);
        desc.width = 16 * amp;
        desc.height = 16 * amp;
    }
    
    if ("x" in obj) {
        desc.originXStr = jsonToString(obj["x"]);
        try { desc.originX = to!real(desc.originXStr); } catch (Exception) {}
    }
    if ("y" in obj) {
        desc.originYStr = jsonToString(obj["y"]);
        try { desc.originY = to!real(desc.originYStr); } catch (Exception) {}
    }
    if ("radius" in obj) {
        desc.radiusStr = jsonToString(obj["radius"]);
        try { desc.radius = to!real(desc.radiusStr); } catch (Exception) {}
    }
    
    if ("x1" in obj && "x2" in obj && "y1" in obj && "y2" in obj) {
        real x1, x2, y1, y2;
        string x1Str = jsonToString(obj["x1"]);
        string x2Str = jsonToString(obj["x2"]);
        string y1Str = jsonToString(obj["y1"]);
        string y2Str = jsonToString(obj["y2"]);
        
        try {
            x1 = to!real(x1Str);
            x2 = to!real(x2Str);
            y1 = to!real(y1Str);
            y2 = to!real(y2Str);
            
            desc.originX = (x1 + x2) / 2.0;
            desc.originY = (y1 + y2) / 2.0;
            desc.radius = min(abs(x2 - x1), abs(y2 - y1)) / 2.0;
            
            import std.format : format;
            desc.originXStr = format!"%.20g"(desc.originX);
            desc.originYStr = format!"%.20g"(desc.originY);
            desc.radiusStr = format!"%.20g"(desc.radius);
        } catch (Exception) {}
    }
    
    if ("dwell" in obj) desc.dwell = to!uint(obj["dwell"].integer);
    if ("iterations" in obj) desc.dwell = to!uint(obj["iterations"].integer);
    if ("palette" in obj) desc.palette = to!int(obj["palette"].integer);
    if ("paletteOffset" in obj || "palette_offset" in obj) {
        auto key = "paletteOffset" in obj ? "paletteOffset" : "palette_offset";
        desc.paletteOffset = getJsonFloat(obj[key]);
    }
    if ("paletteReverse" in obj || "palette_reverse" in obj) {
        auto key = "paletteReverse" in obj ? "paletteReverse" : "palette_reverse";
        desc.paletteReverse = obj[key].type == JSONType.true_;
    }
    if ("paletteFile" in obj || "palette_file" in obj) {
        auto key = "paletteFile" in obj ? "paletteFile" : "palette_file";
        if (obj[key].type == JSONType.string) {
            desc.paletteFile = obj[key].str;
        }
    }
    
    if ("type" in obj) {
        string typeStr = obj["type"].str.toLower();
        switch (typeStr) {
            case "mandelbrot": desc.fractalType = FractalType.mandelbrot; break;
            case "multibrot": desc.fractalType = FractalType.multibrot; break;
            case "ship": desc.fractalType = FractalType.ship; break;
            case "mandelbar": desc.fractalType = FractalType.mandelbar; break;
            default: break;
        }
    }
    
    if ("colorfunc" in obj) {
        string cfStr = obj["colorfunc"].str.toLower();
        switch (cfStr) {
            case "ultrafrac": desc.colorfunc = ColorFunc.ultrafrac; break;
            case "hsv": desc.colorfunc = ColorFunc.hsv; break;
            case "gray": desc.colorfunc = ColorFunc.gray; break;
            case "blue": desc.colorfunc = ColorFunc.blue; break;
            case "red": desc.colorfunc = ColorFunc.red; break;
            case "seashore": desc.colorfunc = ColorFunc.seashore; break;
            case "fire": desc.colorfunc = ColorFunc.fire; break;
            case "oceanid": desc.colorfunc = ColorFunc.oceanid; break;
            case "cnfsso": desc.colorfunc = ColorFunc.cnfsso; break;
            case "acid": desc.colorfunc = ColorFunc.acid; break;
            case "softhours": desc.colorfunc = ColorFunc.softhours; break;
            default: break;
        }
    }
    
    if ("multibrotExp" in obj || "exponent" in obj) {
        auto key = "multibrotExp" in obj ? "multibrotExp" : "exponent";
        desc.multibrotExp = getJsonFloat(obj[key]);
    }
    
    if ("buddha" in obj && obj["buddha"].type == JSONType.true_) {
        desc.buddha = BuddhaMode.buddha;
    }
    if ("antibuddha" in obj && obj["antibuddha"].type == JSONType.true_) {
        if (desc.buddha != BuddhaMode.buddha) {
            desc.buddha = BuddhaMode.antibuddha;
        }
    }
    
    if ("autoDwell" in obj || "auto_dwell" in obj) {
        auto key = "autoDwell" in obj ? "autoDwell" : "auto_dwell";
        desc.autoDwell = obj[key].type == JSONType.true_;
    }
    
    if ("precision" in obj && obj["precision"].type == JSONType.string) {
        desc.forcePrecision = obj["precision"].str;
    }
    if ("arbitrary_precision_method" in obj && obj["arbitrary_precision_method"].type == JSONType.string) {
        desc.arbitraryPrecisionMethod = obj["arbitrary_precision_method"].str;
    }
    
    if ("perturbations" in obj && obj["perturbations"].type == JSONType.string) {
        desc.perturbations = obj["perturbations"].str;
    }
    
    if ("x_px_offset" in obj) desc.x_px_offset = to!int(obj["x_px_offset"].integer);
    if ("y_px_offset" in obj) desc.y_px_offset = to!int(obj["y_px_offset"].integer);
    
    if ("filename" in obj && obj["filename"].type == JSONType.string) {
        desc.filename = obj["filename"].str;
    }
    
    if (desc.filename.length == 0) {
        import config.filename : generateFileName;
        desc.filename = generateFileName(desc);
    }
    
    return desc;
}

private string jsonToString(JSONValue v) {
    import std.format : format;
    
    if (v.type == JSONType.string) {
        return v.str;
    } else if (v.type == JSONType.integer) {
        return to!string(v.integer);
    } else if (v.type == JSONType.uinteger) {
        return to!string(v.uinteger);
    } else if (v.type == JSONType.float_) {
        return format!"%.20g"(v.floating);
    }
    return "";
}

private float getJsonFloat(JSONValue v) {
    if (v.type == JSONType.float_) {
        return cast(float)v.floating;
    } else if (v.type == JSONType.integer) {
        return cast(float)v.integer;
    } else if (v.type == JSONType.uinteger) {
        return cast(float)v.uinteger;
    }
    return 0.0f;
}

