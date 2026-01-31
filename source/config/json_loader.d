module config.json_loader;

import std.json;
import std.conv : to;
import std.string : toLower;
import std.math : abs, sqrt;
import std.algorithm : min, max, countUntil;
import std.format : format;

import config.params;
import config.filename : generateFileName;
import types.fractal;

double getJsonNumber(JSONValue v) {
    if (v.type == JSONType.integer) {
        return cast(double)v.integer;
    } else if (v.type == JSONType.uinteger) {
        return cast(double)v.uinteger;
    } else if (v.type == JSONType.float_) {
        return v.floating;
    }
    return 0.0;
}

int getJsonInt(JSONValue v) {
    if (v.type == JSONType.integer) {
        return cast(int)v.integer;
    } else if (v.type == JSONType.uinteger) {
        return cast(int)v.uinteger;
    } else if (v.type == JSONType.float_) {
        return cast(int)v.floating;
    }
    return 0;
}

bool isNonZeroNumber(JSONValue v) {
    if (v.type == JSONType.integer) return v.integer != 0;
    if (v.type == JSONType.uinteger) return v.uinteger != 0;
    if (v.type == JSONType.float_) return v.floating != 0;
    return false;
}

float getJsonFloat(JSONValue v) {
    if (v.type == JSONType.float_) {
        return cast(float)v.floating;
    } else if (v.type == JSONType.integer) {
        return cast(float)v.integer;
    } else if (v.type == JSONType.uinteger) {
        return cast(float)v.uinteger;
    }
    return 0.0f;
}

string jsonToString(JSONValue v) {
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

RenderParams createBrotDesc(JSONValue s) {
    RenderParams ret;
    
    if (s.type != JSONType.object) return ret;

    if ("width" in s && isNonZeroNumber(s["width"])) ret.width = getJsonInt(s["width"]);
    if ("height" in s && isNonZeroNumber(s["height"])) ret.height = getJsonInt(s["height"]);
    
    if ("amp" in s && isNonZeroNumber(s["amp"])) {
        ret.width = 16 * getJsonInt(s["amp"]);
        ret.height = 16 * getJsonInt(s["amp"]);
    }
    
    if ("x1" in s && "x2" in s && "y1" in s && "y2" in s) {
        const auto x = (getJsonNumber(s["x1"]) + getJsonNumber(s["x2"])) / 2;
        const auto y = (getJsonNumber(s["y1"]) + getJsonNumber(s["y2"])) / 2;
        const auto radX = max(getJsonNumber(s["x1"]), getJsonNumber(s["x2"])) - 
                         min(getJsonNumber(s["x1"]), getJsonNumber(s["x2"]));
        const auto radY = max(getJsonNumber(s["y1"]), getJsonNumber(s["y2"])) - 
                         min(getJsonNumber(s["y1"]), getJsonNumber(s["y2"]));

        ret.originX = x;
        ret.originY = y;
        ret.radius = max(radX, radY);
        
        ret.originXStr = format!"%.20g"(x);
        ret.originYStr = format!"%.20g"(y);
        ret.radiusStr = format!"%.20g"(ret.radius);
    }

    if ("x" in s) {
        if (s["x"].type == JSONType.string) {
            ret.originXStr = s["x"].str;
            try { ret.originX = to!real(s["x"].str); } catch (Exception) {}
        } else {
            ret.originX = getJsonNumber(s["x"]);
            ret.originXStr = format!"%.20g"(ret.originX);
        }
    }
    if ("y" in s) {
        if (s["y"].type == JSONType.string) {
            ret.originYStr = s["y"].str;
            try { ret.originY = to!real(s["y"].str); } catch (Exception) {}
        } else {
            ret.originY = getJsonNumber(s["y"]);
            ret.originYStr = format!"%.20g"(ret.originY);
        }
    }
    if ("radius" in s) {
        if (s["radius"].type == JSONType.string) {
            ret.radiusStr = s["radius"].str;
            try { ret.radius = to!real(s["radius"].str); } catch (Exception) {}
        } else {
            ret.radius = getJsonNumber(s["radius"]);
            ret.radiusStr = format!"%.20g"(ret.radius);
        }
    }
    
    if ("precision" in s && s["precision"].type == JSONType.string) {
        ret.forcePrecision = s["precision"].str;
    } else if ("precisionMode" in s && s["precisionMode"].type == JSONType.string) {
        ret.forcePrecision = s["precisionMode"].str;
    }
    
    if ("arbitrary_precision_method" in s && s["arbitrary_precision_method"].type == JSONType.string) {
        ret.arbitraryPrecisionMethod = s["arbitrary_precision_method"].str;
    } else if ("arbitraryPrecisionMethod" in s && s["arbitraryPrecisionMethod"].type == JSONType.string) {
        ret.arbitraryPrecisionMethod = s["arbitraryPrecisionMethod"].str;
    }
    
    if ("zoom" in s) {
        string zoomStr;
        if (s["zoom"].type == JSONType.string) {
            zoomStr = s["zoom"].str;
        } else {
            zoomStr = format!"%.20g"(getJsonNumber(s["zoom"]));
        }
        
        auto ePos = zoomStr.countUntil!(c => c == 'e' || c == 'E')();
        if (ePos >= 0) {
            string mantissa = zoomStr[0..ePos];
            int exp = to!int(zoomStr[ePos + 1 .. $]);
            double mant = to!double(mantissa);
            double invMant = 1.0 / mant;
            int newExp = -exp;
            ret.radiusStr = format!"%.10ge%d"(invMant, newExp);
            try { ret.radius = to!real(ret.radiusStr); } catch (Exception) {}
        } else {
            double zoom = to!double(zoomStr);
            ret.radius = 1.0 / zoom;
            ret.radiusStr = format!"%.20g"(ret.radius);
        }
    }
    
    if ("dwell" in s && isNonZeroNumber(s["dwell"])) ret.dwell = getJsonInt(s["dwell"]);
    if ("iterations" in s && isNonZeroNumber(s["iterations"])) ret.dwell = getJsonInt(s["iterations"]);
    if ("palette" in s) ret.palette = getJsonInt(s["palette"]);
    if ("paletteOffset" in s) ret.paletteOffset = cast(float)getJsonNumber(s["paletteOffset"]);
    if ("palette_offset" in s) ret.paletteOffset = cast(float)getJsonNumber(s["palette_offset"]);
    if ("palette_reverse" in s && s["palette_reverse"].type == JSONType.true_) {
        ret.paletteReverse = true;
    } else if ("paletteReverse" in s && s["paletteReverse"].type == JSONType.true_) {
        ret.paletteReverse = true;
    }
    if ("paletteFile" in s && s["paletteFile"].type == JSONType.string) {
        ret.paletteFile = s["paletteFile"].str;
    } else if ("palette_file" in s && s["palette_file"].type == JSONType.string) {
        ret.paletteFile = s["palette_file"].str;
    }
    
    if ("multibrotExp" in s) ret.multibrotExp = cast(float)getJsonNumber(s["multibrotExp"]);
    if ("exponent" in s) ret.multibrotExp = cast(float)getJsonNumber(s["exponent"]);
    
    if ("type" in s && s["type"].type == JSONType.string) {
        string typeStr = s["type"].str.toLower();
        switch (typeStr) {
            case "mandelbrot": ret.fractalType = FractalType.mandelbrot; break;
            case "multibrot": ret.fractalType = FractalType.multibrot; break;
            case "ship": ret.fractalType = FractalType.ship; break;
            case "mandelbar": ret.fractalType = FractalType.mandelbar; break;
            default: break;
        }
    }
    
    if ("colorfunc" in s && s["colorfunc"].type == JSONType.string) {
        string cfStr = s["colorfunc"].str.toLower();
        bool isBuiltin = true;
        switch (cfStr) {
            case "ultrafrac": ret.colorfunc = ColorFunc.ultrafrac; break;
            case "hsv": ret.colorfunc = ColorFunc.hsv; break;
            case "gray": ret.colorfunc = ColorFunc.gray; break;
            case "blue": ret.colorfunc = ColorFunc.blue; break;
            case "red": ret.colorfunc = ColorFunc.red; break;
            case "base": ret.colorfunc = ColorFunc.base; break;
            case "seashore": ret.colorfunc = ColorFunc.seashore; break;
            case "fire": ret.colorfunc = ColorFunc.fire; break;
            case "oceanid": ret.colorfunc = ColorFunc.oceanid; break;
            case "cnfsso": ret.colorfunc = ColorFunc.cnfsso; break;
            case "acid": ret.colorfunc = ColorFunc.acid; break;
            case "softhours": ret.colorfunc = ColorFunc.softhours; break;
            default: 
                isBuiltin = false;
                ret.colorfunc = ColorFunc.ultrafrac;
                if (cfStr.length > 5 && cfStr[$-5..$] == ".json") {
                    ret.paletteFile = cfStr;
                } else {
                    ret.paletteFile = cfStr ~ ".json";
                }
                break;
        }
    }

    if ("buddha" in s && s["buddha"].type == JSONType.true_) {
        ret.buddha = BuddhaMode.buddha;
    } else if ("antibuddha" in s && s["antibuddha"].type == JSONType.true_) {
        ret.buddha = BuddhaMode.antibuddha;
    }
    
    if ("autoDwell" in s && s["autoDwell"].type == JSONType.true_) {
        ret.autoDwell = true;
    } else if ("auto_dwell" in s && s["auto_dwell"].type == JSONType.true_) {
        ret.autoDwell = true;
    }
    
    if ("perturbations" in s && s["perturbations"].type == JSONType.string) {
        ret.perturbations = s["perturbations"].str;
    }
    
    if ("x_px_offset" in s) {
        ret.x_px_offset = getJsonInt(s["x_px_offset"]);
    }
    if ("y_px_offset" in s) {
        ret.y_px_offset = getJsonInt(s["y_px_offset"]);
    }
    
    if ("filename" in s && s["filename"].type == JSONType.string) {
        ret.filename = s["filename"].str;
    } else {
        ret.filename = generateFileName(ret);
    }
    
    return ret;
}
