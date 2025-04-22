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

int main(string[] args) {
	int amp = 50;
	int w = 0;
	int h = 0;

	BrotParams cli = BrotParams();

	bool buddha = false;
	bool antibuddha = false;

	string filename = "";
	string flowlist = "";
	
	BrotParams[] queue;

	auto helpInformation = getopt(
    args,
    "iterations|i", "Number of iterations to perform, "~to!string(cli.dwell)~" by default", &cli.dwell,
		"amp|a", "AMP of the image, used to calculate its size, "~to!string(amp)~" by default", &amp,
		"width|ws", "Width of the image, 16*amp by default", &w,
		"height|hs", "Height of the image, 16*amp by default", &h,
		"originx|x", "Center of origin real part (x), "~to!string(cli.originX)~" by default", &cli.originX,
		"originy|y", "Center of origin imaginary part (y), "~to!string(cli.originY)~" by default", &cli.originY,
		"radius|r", "Radius of calculated zone, "~to!string(radius)~" by default", &cli.radius,
		"buddha|b", "Calculate Buddhabrot, False by default", &buddha,
		"antibuddha|n", "Calculate Antibuddhabrot, False by default, disabled if -b", &antibuddha,
		"palettesize|p", "Pallete scale, MAX_ITER by default", &cli.palette,
		"output|o", "Output filename, generated based on parameters by default", &filename,
		"dir|d", "Output directory, `out` by default (created if does not exists)", &flow.workdir,
		"type|t", "Fractal type (mandelbrot, multibrot, ship), mandelbrot by default", &cli.type,
		"colorfunc|c", "Coloring function (ultrafrac, hsv, gray, blue, red), ultrafrac by default", &cli.colorfunc,
		"exponent|e", "Multibrot exponent, 2.0 by default", &cli.multibrotExp,
		"progress|s", "Save results to a separate file while working/import progress on load if foundn\n" ~
									"\t-1 for default block size (by percentage of lines), or any other int 1-50", &flow.saveProgress,
		"flowlist|f", "JSON list of things to generate", &flowlist,
		"skip|k", "Skip existing files instead of recalculating them", &flow.skipExisting,
  );

	if (helpInformation.helpWanted) {
    defaultGetoptPrinter("Some information about the program.",
      helpInformation.options);
		return 0;
  }

	// generate flow

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
			queue.length++;
			queue[$-1] = jsonList.createBrotDesc();
		} else {
			foreach (obj; jsonList.array) {
				//   if object has "animate" array - generate animation
				if ("animate" in obj && obj["animate"].integer && "from" in obj && "to" in obj) {
					flow.generateAnimateSequence(queue, obj);
					continue;
				}

				//   if object has "chunked" and >0 - generate sequence of chunks
				if ("chunks" in obj && obj["chunks"].integer) {
					flow.generateChunksSequence(queue, obj);
					continue;
				}
				
				queue.length++;
				queue[$-1] = obj.createBrotDesc();
			}
		}
	} else {
		cli.width = w ? w : 16*amp;
		cli.height = h ? h : 16*amp;

		if (!filename.length) {
			cli.filename = flow.generateFileName(cli);
		} else {
			cli.filename = filename;
		}

		if (buddha) cli.buddha = BuddhaState.buddha;
		else if (antibuddha) cli.buddha = BuddhaState.antibuddha;

		queue.length++;
		queue[] = cli;
	}

	if (!flow.workdir.exists) flow.workdir.mkdir;

	// to flow

	// queue
	// only one image per time
	foreach(request; queue) {
		request.brotFlow();
	}

	return 0;
}
