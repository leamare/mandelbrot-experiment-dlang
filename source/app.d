module main;

import std.stdio;
import std.getopt;
import std.conv;
import std.string;
import std.file;
import std.json;
import std.math;
import std.typecons;

import std.range;
import std.parallelism;

import dlib.image;
// import daffodil.bmp;

import pixel;

alias Coord = Tuple!(int, int);

int main(string[] args) {
	int amp = 50;
	int w = 0;
	int h = 0;
	int iter = 100;

	double originX = -0.5;
	double originY = 0.0;
	double radius = 2.0;
	float multibrotExp = 2.0;

	int paletteSize = 0;
	bool buddha = false;
	FType type;
	ColorFunc colorfunc;

	string filename = "";
	string dir = "out";

	auto helpInformation = getopt(
    args,
    "iterations|i", "Number of iterations to perform, "~to!string(iter)~" by default", &iter,
		"amp|a", "AMP of the image, used to calculate its size, "~to!string(amp)~" by default", &amp,
		"width|ws", "Width of the image, 16*amp by default", &w,
		"height|hs", "Height of the image, 16*amp by default", &h,
		"originx|x", "Center of origin real part (x), "~to!string(originX)~" by default", &originX,
		"originy|y", "Center of origin imaginary part (y), "~to!string(originY)~" by default", &originY,
		"radius|r", "Radius of calculated zone, "~to!string(radius)~" by default", &radius,
		"buddha|b", "Calculate Buddhabrot, False by default", &buddha,
		"palletesize|p", "Pallete scale, MAX_ITER by default", &paletteSize,
		"output|o", "Output filename, generated based on parameters by default", &filename,
		"dir|d", "Output directory, `out` by default (created if does not exists)", &dir,
		"type|t", "Fractal type (mandelbrot, multibrot, ship), mandelbrot by default", &type,
		"colorfunc|c", "Coloring function (ultrafrac, hsv, gray, blue, red), ultrafrac by default", &colorfunc,
		"exponent|e", "Multibrot exponent, 2.0 by default", &multibrotExp,
  );

	if (helpInformation.helpWanted) {
    defaultGetoptPrinter("Some information about the program.",
      helpInformation.options);
		return 0;
  }

	if (!w) w = 16*amp;
	if (!h) h = 16*amp;

	const int wfactor = to!int( floor(to!double(w) / 100.0) );

	if (!filename.length) {
		filename = to!string(type) ~ 
			"_X=" ~ format!"%.17g"(originX) ~
			"_Y=" ~ format!"%.17g"(originY) ~
			"_R=" ~ format!"%.17g"(radius) ~
			"_W=" ~ to!string(w) ~
			"_H=" ~ to!string(h) ~
			"_I=" ~ to!string(iter) ~ 
			"_P=" ~ to!string(paletteSize) ~ 
			"_C=" ~ to!string(colorfunc) ~ 
			( type == FType.multibrot ? "_E=" ~ to!string(multibrotExp) : "") ~
		".png";
	}

	writeln("Iterations: ", iter);
	writeln("Image size: ", w, " x ", h);
	writeln("Origin: ", format!"%.17g"(originX), (originY < 0 ? " - " : " + "), format!"%.17g"(originY), "i");
	writeln("Viewpoint radius: ", format!"%.17g"(radius));
	writeln("Palette size: ", paletteSize ? paletteSize : iter);
	writeln("Buddha: ", to!string(buddha));

	writeln("Filename postfix: ", filename);

	if (!dir.exists) dir.mkdir;

	if (colorfunc != ColorFunc.init) setColorFunc(colorfunc);
	if (type != FType.init) setType(type);

	initArr(w, h);
	setIter(iter);
	setOrigin(originX, originY, radius);
	if (type == FType.multibrot) setMultibrotBase(multibrotExp);

	if (buddha) enableBuddha();
	if (paletteSize) setPaletteSize(paletteSize);
	// if (colorfunc == ColorFunc.ultrafrac) setPaletteSize(to!int(paletteSize*0.35));
	// setOrigin(0.0, 0.0, 1.0);
	// setOrigin(-1.15, 0.1, 0.125);
	// setOrigin(-1.25275, -0.343, 0.0025);

	SuperImage img = image(w, h);

	auto wRange = iota(0, w);
	//for(int i = 0; i < w; i++) {
	foreach (i; parallel(wRange)) {
		if (i % wfactor == 0) write ('.');
		for(int j = 0; j < h; j++) {
			img[i, j] = pixelcolor(i, j, w, h);
		}
	}

	writeln("\nMain set");
	savePNG(img, dir ~ "/" ~ filename);

	if (buddha) {
		updateMaxBI();
		for(int i = 0; i < w; i++) {
			// writeln(i);
			if (i % wfactor == 0) write ('.');
			for(int j = 0; j < h; j++) {
				img[i, j] = getBuddhabrotted(i, j);
			}
		}
		
		writeln("\nBuddha");
		savePNG(img, dir ~ "/buddha_" ~ filename);
	}

	return 0;
}
