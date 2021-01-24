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
	const int w = 5120;
	const int h = 2880;

	SuperImage img = image(w, h);
	// writeln(img.pixelFormat());
	sfColor[Coord] points;

	for(int i = 0; i < w; i++) {
		for(int j = 0; j < h; j++) {
			if (!(Coord(i, j) in points)) {
				points[ Coord(i, j) ] = pixelcolor(i, j, w, h);
			}
			// img.setPixel(
			// 	Color4(points[ Coord(i, j) ].r, points[ Coord(i, j) ].g, points[ Coord(i, j) ].b, 255),
			// 	i,
			// 	j
			// );
			img[i, j] = Color4f(
				cast(float)(points[ Coord(i, j) ].r) / 255,
				cast(float)(points[ Coord(i, j) ].g) / 255,
				cast(float)(points[ Coord(i, j) ].b) / 255,
				1.0f
			);
		}
	}

	saveBMP(img, "out.bmp");

	return 0;
}
