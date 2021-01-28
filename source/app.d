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
	const int amp = 2000;
	const int w = 4*4*amp;
	const int h = 4*4*amp;
	const int iter = to!int(args[1]);

	const int wfactor = to!int( floor(to!double(w) / 100.0) );

	writeln("Iterations: ", iter);

	initArr(w, h);
	setIter(iter);

	SuperImage img = image(w, h);

	for(int i = 0; i < w; i++) {
		if (i % wfactor == 0) writeln (i / wfactor, '%');
		for(int j = 0; j < h; j++) {
			img[i, j] = pixelcolor(i, j, w, h);
		}
	}

	writeln("Main set");
	savePNG(img, "out_mandel_"~to!string(w)~"x"~to!string(h)~"_"~to!string(iter)~".png");

	updateMaxBI();
	for(int i = 0; i < w; i++) {
		// writeln(i);
		if (i % wfactor == 0) writeln (i / wfactor, '%');
		for(int j = 0; j < h; j++) {
			img[i, j] = getBuddhabrotted(i, j);
		}
	}

	writeln("Buddha");
	savePNG(img, "out_buddha_"~to!string(w)~"x"~to!string(h)~"_"~to!string(iter)~".png");

	return 0;
}
