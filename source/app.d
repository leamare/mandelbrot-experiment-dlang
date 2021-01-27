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
	const int w = 16*100;
	const int h = 9*100;
	const int iter = 50000;
	const int max_bi = 1000;

	initArr(w, h);
	setIter(iter);

	SuperImage img = image(w, h);

	for(int i = 0; i < w; i++) {
		writeln(i);
		for(int j = 0; j < h; j++) {
			img[i, j] = pixelcolor(i, j, w, h);
		}
	}

	writeln("Main set");
	savePNG(img, "out_mandel_"~to!string(w)~"x"~to!string(h)~"_"~to!string(iter)~".png");

	updateMaxBI();
	for(int i = 0; i < w; i++) {
		// writeln(i);
		for(int j = 0; j < h; j++) {
			img[i, j] = getBuddhabrotted(i, j);
		}
	}

	writeln("Buddha");
	savePNG(img, "out_buddha_"~to!string(w)~"x"~to!string(h)~"_"~to!string(iter)~".png");

	return 0;
}
