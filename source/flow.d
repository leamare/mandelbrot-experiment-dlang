module flow;

import std.stdio;
import std.file;
import std.conv;
import std.math;
import std.typecons;
import std.string;

import std.range;
import std.parallelism;
import cerealed;
import std.algorithm : min;

import dlib.image;

import mandel;

string workdir = "out";
int saveProgress = 0;

struct BrotParams {
  int width = 800;
  int height = 800;
  real originX = -0.5;
  real originY = 0.0;
  real radius  = 2.0;
  int palette = 0;
  uint dwell = 100;
  string filename;

  float multibrotExp = 2.0;

  FType type;
  ColorFunc colorfunc;
  BuddhaState buddha;
}

/* 
 * My initial plan was to split everything that happens in brotFlow
 * into small pieces and pass data from one function to another
 * while brotFlow() just combining it all together
 * but to be honest, every section is used only once per flow
 * and dividing it all could result in memory leaks 
 * (which can be fatal when working with bigger images)
 * so I left it as is instead
 */

void brotFlow(BrotParams desc) {
  if (desc.colorfunc != ColorFunc.init) mandel.setColorFunc(colorfunc);
	if (desc.type != FType.init) mandel.setType(type);

	mandel.initArr(desc.width, desc.height);
	mandel.setIter(desc.dwell);
	mandel.setOrigin(desc.originX, desc.originY, desc.radius);
	if (desc.type == FType.multibrot) mandel.setMultibrotBase(desc.multibrotExp);

	if (desc.buddha != BuddhaState.init) mandel.setBuddha(desc.buddha);

	if (desc.palette) mandel.setPaletteSize(desc.palette);

  const int wfactor = to!int( floor(to!double(desc.width) / 100.0) );

  // CLI description

  writeln("Iterations: ", desc.dwell);
	writeln("Image size: ", desc.width, " x ", desc.height);
	writeln("Origin: ", format!"%.17g"(desc.originX), (desc.originY < 0 ? " - " : " + "), 
    format!"%.17g"(desc.originY), "i");
	writeln("Viewpoint radius: ", format!"%.17g"(desc.radius));
	writeln("Palette size: ", desc.palette ? desc.palette : desc.dwell);
	writeln("Buddha: ", to!string(desc.buddha));

	writeln("Filename: ", desc.filename);

  // iterating

  Iters[][] iters;

	iters.length = desc.width;

	writeln("\nIterating");

  // progress aware iterations
	if (saveProgress > 0 && saveProgress < 50) {
		int loaded = 0;

    // looking for existing progress files
		if (exists(workdir ~ "/" ~ desc.filename ~ ".tmp")) {
			writeln("-- Progress data found --");
			auto progdata = cast(const(ubyte)[])read(workdir ~ "/" ~ desc.filename ~ ".tmp");
			iters = decerealise!(Iters[][])(progdata);
			if (iters.length == desc.width) {
				loaded = 0;
				foreach (line; iters) {
					if (line.length == desc.height) {
						loaded++;
						continue;
					} else {
						break;
					}
				}
				writeln("-- Data loaded, ", loaded, " lines --");
			} else {
				iters.length = desc.width;
			}

			if (desc.buddha != BuddhaState.none) {
				if (exists(workdir ~ "/" ~ (desc.buddha == BuddhaState.buddha ? "" : "anti") ~ "buddha_" ~ desc.filename ~ ".tmp")) {
					writeln("-- " ~ (desc.buddha == BuddhaState.buddha ? "Buddha" : "Antibuddha") ~ " data detected --");
					progdata = cast(const(ubyte)[])read(workdir ~ "/" ~ (desc.buddha == BuddhaState.buddha ? "" : "anti") ~ "buddha_" ~ desc.filename ~ ".tmp");

					int[][] tmpdata = decerealise!(int[][])(progdata);
					for(int i=0; i < desc.width; i++) {
						for(int j=0; j < desc.height; j++) {
							mandel.buddha_data[i][j] = tmpdata[i][j];
						}
					}
					writeln("-- " ~ (desc.buddha == BuddhaState.buddha ? "Buddha" : "Antibuddha") ~ " data loaded --");
				} else {
					writeln("!! WARNING no buddha data found! !!");
					writeln("-- if you want " ~ (desc.buddha == BuddhaState.buddha ? "buddha" : "antibuddha") ~ "brot please make a rerun --");
				}
			}
		}

    // working block size
    // save after block is done
		const int blockSize = saveProgress * wfactor;

		const endp = to!int( ceil( desc.width/to!double(blockSize) ) );
		for(int block = 0; block < endp; block++) {
			auto blockEnd = (block+1)*blockSize;
			auto wRange = iota(block*blockSize, min(blockEnd, desc.width));
			foreach (i; parallel(wRange)) {
				if (iters[i].length != desc.height) {
					iters[i].length = desc.height;
					for(int j = 0; j < desc.height; j++) {
						iters[i][j] = iterate(i, j, desc.width, desc.height);
					}
				} 
				if (i % wfactor == 0) {
					write ('.');
				}
			}
			write (' ');

      // escape if didn't finish the block yet
			if (loaded >= blockEnd || desc.width <= blockEnd)
				continue;

			auto progdata = iters.cerealise;
			std.file.write(workdir ~ "/" ~ desc.filename ~ ".tmp", progdata);

			if (desc.buddha != BuddhaState.none) {
        // need to copy data from shared int[][] to regular int[][] before serialization
				int[][] tmpdata;
				tmpdata.length = desc.width;
				for(int bi=0; bi < desc.width; bi++) {
					tmpdata[bi].length = desc.height;
					for(int bj=0; bj < desc.height; bj++) {
						tmpdata[bi][bj] = mandel.buddha_data[bi][bj];
					}
				}
				std.file.write(workdir ~ "/" ~ (desc.buddha == BuddhaState.buddha ? "" : "anti") ~ "buddha_" ~ desc.filename ~ ".tmp", tmpdata.cerealise);
			}
			write ("! ");
		}

    // remove progress files if done
		remove(workdir ~ "/" ~ desc.filename ~ ".tmp");
		if (exists(workdir ~ "/buddha_" ~ desc.filename ~ ".tmp"))
      remove(workdir ~ "/buddha_" ~ desc.filename ~ ".tmp");
		if (exists(workdir ~ "/antibuddha_" ~ desc.filename ~ ".tmp"))
      remove(workdir ~ "/antibuddha_" ~ desc.filename ~ ".tmp");
	} else {
    // simpler version, doesn't load progress
    // just runs through every line in parallel
		auto wRange = iota(0, desc.width);
		foreach (i; parallel(wRange)) {
			iters[i].length = desc.height;
			for(int j = 0; j < desc.height; j++) {
				iters[i][j] = iterate(i, j, desc.width, desc.height);
			}
			if (i % wfactor == 0) write ('.');
		}
	}

	auto wRange = iota(0, desc.width);

	SuperImage img = image(desc.width, desc.height);

	writeln("\nGenerating image");
	foreach (i; parallel(wRange)) {
		for(int j = 0; j < desc.height; j++) {
			img[i, j] = pixelcolor(iters[i][j].i, iters[i][j].d);
		}
		if (i % wfactor == 0) write ('.');
	}

	writeln("\nSaving: " ~ workdir ~ "/" ~ desc.filename ~ ".png");
	savePNG(img, workdir ~ "/" ~ desc.filename ~ ".png");

	if (desc.buddha != BuddhaState.none) {
		updateMaxBI();
		for(int i = 0; i < desc.width; i++) {
			if (i % wfactor == 0) write ('.');
			for(int j = 0; j < desc.height; j++) {
				img[i, j] = getBuddhabrotted(i, j);
			}
		}
		
		if (desc.buddha == BuddhaState.buddha) {
			writeln("\nSaving: " ~ workdir ~ "/buddha_" ~ desc.filename ~ ".png");
			savePNG(img, workdir ~ "/buddha_" ~ desc.filename ~ ".png");
		} else {
			writeln("\nSaving: " ~ workdir ~ "/antibuddha_" ~ desc.filename ~ ".png");
			savePNG(img, workdir ~ "/antibuddha_" ~ desc.filename ~ ".png");
		}
	}

	writeln("----------");
}

string generateFileName(BrotParams s) {
  return to!string(s.type) ~ 
    "_X=" ~ format!"%.17g"(s.originX) ~
    "_Y=" ~ format!"%.17g"(s.originY) ~
    "_R=" ~ format!"%.17g"(s.radius) ~
    "_W=" ~ to!string(s.width) ~
    "_H=" ~ to!string(s.height) ~
    "_I=" ~ to!string(s.dwell) ~ 
    "_P=" ~ to!string(s.palette ? s.palette : s.dwell) ~ 
    "_C=" ~ to!string(s.colorfunc) ~ 
    ( s.type == FType.multibrot ? "_E=" ~ to!string(s.multibrotExp) : "");
}

void generateAnimateSequence() {}
void generateChunksSequence() {}
