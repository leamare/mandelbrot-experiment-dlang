module main;

import std.stdio;
import std.getopt;
import std.conv;
import std.string;
import std.file;
import std.json;
import std.math;
import std.typecons;

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
	bool buddha = false;
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
  );

	if (helpInformation.helpWanted) {
    defaultGetoptPrinter("Some information about the program.",
      helpInformation.options);
		return 0;
  }

	if (!w) w = 16*amp;
	if (!h) h = 16*amp;

	const int wfactor = to!int( floor(to!double(w) / 100.0) );

	writeln("Iterations: ", iter);

	initArr(w, h);
	setIter(iter);
	setOrigin(originX, originY, radius);

	if (buddha) enableBuddha();
	SuperImage img = image(w, h);

	for(int i = 0; i < w; i++) {
		if (i % wfactor == 0) writeln (i / wfactor, '%');
		for(int j = 0; j < h; j++) {
			img[i, j] = pixelcolor(i, j, w, h);
		}
	}

	writeln("Main set");
	savePNG(img, "out_mandel"~
		"_X"~to!string(originX)~
		"_Y"~to!string(originY)~
		"_R"~to!string(radius)~
		"_W"~to!string(w)~
		"_H"~to!string(h)~
		"_I"~to!string(iter)~".png"
	);

	if (buddha) {
	updateMaxBI();
	for(int i = 0; i < w; i++) {
		// writeln(i);
		if (i % wfactor == 0) writeln (i / wfactor, '%');
		for(int j = 0; j < h; j++) {
			img[i, j] = getBuddhabrotted(i, j);
		}
	}

	writeln("Buddha");
		savePNG(img, "out_buddha_"~
				"_X"~to!string(originX)~
			"_Y"~to!string(originY)~
			"_R"~to!string(radius)~
			"_W"~to!string(w)~
			"_H"~to!string(h)~
			"_I"~to!string(iter)~".png"
		);
	}

	return 0;
}
