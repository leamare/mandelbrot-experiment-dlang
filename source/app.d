module main;

import std.stdio;
import std.getopt;
import std.conv;
import std.string;
import std.file;
import std.math;
import std.json;

import mandel;
import flow;
import config.params : RenderParams;
import config.filename : generateFileName;

int main(string[] args) {
    int amp = 50;
    int w = 0;
    int h = 0;

    RenderParams cli;

    bool buddha = false;
    bool antibuddha = false;

    string filename = "";
    string flowlist = "";
    
    RenderParams[] queue;
    
    // String versions for high precision input
    string originXArg = "";
    string originYArg = "";
    string radiusArg = "";

    auto helpInformation = getopt(
        args,
        "iterations|i", "Number of iterations to perform, " ~ to!string(cli.dwell) ~ " by default", &cli.dwell,
        "amp|a", "AMP of the image, used to calculate its size, " ~ to!string(amp) ~ " by default", &amp,
        "width|ws", "Width of the image, 16*amp by default", &w,
        "height|hs", "Height of the image, 16*amp by default", &h,
        "originx|x", "Center of origin real part (x), " ~ to!string(cli.originX) ~ " by default (use string for high precision)", &originXArg,
        "originy|y", "Center of origin imaginary part (y), " ~ to!string(cli.originY) ~ " by default", &originYArg,
        "radius|r", "Radius of calculated zone, " ~ to!string(cli.radius) ~ " by default", &radiusArg,
        "buddha|b", "Calculate Buddhabrot, False by default", &buddha,
        "antibuddha|n", "Calculate Antibuddhabrot, False by default, disabled if -b", &antibuddha,
        "palettesize|p", "Palette scale, MAX_ITER by default", &cli.palette,
        "output|o", "Output filename, generated based on parameters by default", &filename,
        "dir|d", "Output directory, `out` by default (created if does not exist)", &flow.workdir,
        "type|t", "Fractal type (mandelbrot, multibrot, ship, mandelbar), mandelbrot by default", &cli.fractalType,
        "colorfunc|c", "Coloring function (ultrafrac, hsv, gray, blue, red, seashore, fire, oceanid, cnfsso, acid, softhours), ultrafrac by default", &cli.colorfunc,
        "exponent|e", "Multibrot exponent, 2.0 by default", &cli.multibrotExp,
        "progress|s", "Save results to a separate file while working/import progress on load if found\n" ~
                                    "\t-1 for default block size (by percentage of lines), or any other int 1-50", &flow.saveProgress,
        "flowlist|f", "JSON list of things to generate", &flowlist,
        "skip|k", "Skip existing files instead of recalculating them", &flow.skipExisting,
    );

    if (helpInformation.helpWanted) {
        defaultGetoptPrinter(
            "Mandelbrot Set Renderer with Arbitrary Precision Support\n\n" ~
            "Features:\n" ~
            "  - Automatic precision detection for deep zooms\n" ~
            "  - Efficient parallel rendering\n" ~
            "  - Multiple coloring schemes\n" ~
            "  - Buddhabrot/Antibuddhabrot support\n" ~
            "  - Animation and chunking modes\n\n" ~
            "Options:",
            helpInformation.options
        );
        return 0;
  }

    // Parse coordinate arguments (support both numeric and string input)
    if (originXArg.length > 0) {
        cli.originXStr = originXArg;
        try { cli.originX = to!real(originXArg); } catch (Exception) {}
    }
    if (originYArg.length > 0) {
        cli.originYStr = originYArg;
        try { cli.originY = to!real(originYArg); } catch (Exception) {}
    }
    if (radiusArg.length > 0) {
        cli.radiusStr = radiusArg;
        try { cli.radius = to!real(radiusArg); } catch (Exception) {}
    }
    
    // Generate flow from JSON list
    if (flowlist != "" && flowlist.exists()) {
        JSONValue jsonList;

        writeln("\nLoading " ~ flowlist ~ "\n");

        try {
            jsonList = flowlist.readText.parseJSON;
            if (jsonList.type != JSONType.object && jsonList.type != JSONType.array)
                throw new Exception("Invalid object");
        } catch (Exception e) {
            jsonList = "[{}]".parseJSON;
        }

        if (jsonList.type == JSONType.object) {
            queue ~= jsonList.createBrotDesc();
        } else {
            foreach (obj; jsonList.array) {
                // Handle animation sequences
                if ("animate" in obj && obj["animate"].integer && "from" in obj && "to" in obj) {
                    flow.generateAnimateSequence(queue, obj);
                    continue;
                }

                // Handle chunked rendering
                if ("chunks" in obj && obj["chunks"].integer) {
                    flow.generateChunksSequence(queue, obj);
                    continue;
                }
                
                queue ~= obj.createBrotDesc();
            }
        }
    } else {
        cli.width = w ? w : 16 * amp;
        cli.height = h ? h : 16 * amp;

        if (!filename.length) {
            cli.filename = generateFileName(cli);
        } else {
            cli.filename = filename;
        }

        if (buddha) cli.buddha = BuddhaMode.buddha;
        else if (antibuddha) cli.buddha = BuddhaMode.antibuddha;

        queue ~= cli;
    }

    if (!flow.workdir.exists) flow.workdir.mkdir;

    writeln("Processing ", queue.length, " render(s)...\n");
    
    foreach (idx, request; queue) {
        if (queue.length > 1) {
            writeln("=== Render ", idx + 1, " of ", queue.length, " ===");
        }
        request.brotFlow();
    }

    writeln("All renders complete!");
    return 0;
}
