module flow;

import std.stdio;
import std.file;
import std.conv;
import std.math;
import std.typecons;
import std.string;
import std.json;

import std.range;
import std.parallelism;
import cerealed;
import std.algorithm : min, max;

import dlib.image;

import mandel;

string workdir = "out";
int saveProgress = 0;
bool skipExisting = false;

struct BrotParams {
  int width = 800;
  int height = 800;
  real originX = -0.5;
  real originY = 0.0;
  real radius  = 2.0;
  int palette = 0;
	float paletteOffset = 0;
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
	if (skipExisting && exists(workdir ~ "/" ~ desc.filename ~ ".png")) {
		writeln("File `" ~ desc.filename ~ "` exists, skipping...\n");
		return;
	}

  mandel.setColorFunc(desc.colorfunc);
	mandel.setType(desc.type);

	mandel.initArr(desc.width, desc.height);
	mandel.setIter(desc.dwell);
	mandel.setOrigin(desc.originX, desc.originY, desc.radius);
	if (desc.type == FType.multibrot) mandel.setMultibrotBase(desc.multibrotExp);

	mandel.setBuddha(desc.buddha);

	//if (desc.palette) 
	mandel.setPaletteSize(desc.palette, desc.paletteOffset);

  const int wfactor = to!int( floor(to!double(desc.width) / 100.0) );

  // CLI description

  writeln("Iterations: ", desc.dwell);
	writeln("Image size: ", desc.width, " x ", desc.height);
	writeln("Origin: ", format!"%.17g"(desc.originX), (desc.originY < 0 ? " - " : " + "), 
    format!"%.17g"(desc.originY), "i");
	writeln("Viewpoint radius: ", format!"%.17g"(desc.radius));
	writeln("Palette size: ", desc.palette ? desc.palette : desc.dwell, " + ", desc.paletteOffset);
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
				if (exists(workdir ~ "/" ~ (desc.buddha == BuddhaState.buddha ? "" : "anti") ~ "buddha_" ~ desc.filename ~ ".tmp")){
					writeln("-- " ~ (desc.buddha == BuddhaState.buddha ? "Buddha" : "Antibuddha") ~ " data detected --");
					progdata = cast(const(ubyte)[])read(workdir ~ "/" ~ 
						(desc.buddha == BuddhaState.buddha ? "" : "anti") ~ "buddha_" ~ desc.filename ~ ".tmp");

					int[][] tmpdata = decerealise!(int[][])(progdata);
					for(int i=0; i < desc.width; i++) {
						for(int j=0; j < desc.height; j++) {
							mandel.buddha_data[i][j] = tmpdata[i][j];
						}
					}
					writeln("-- " ~ (desc.buddha == BuddhaState.buddha ? "Buddha" : "Antibuddha") ~ " data loaded --");
				} else {
					writeln("!! WARNING no buddha data found! !!");
					writeln("-- if you want " ~ 
						(desc.buddha == BuddhaState.buddha ? "buddha" : "antibuddha") ~ "brot please make a rerun --");
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
				std.file.write(workdir ~ "/" ~ 
					(desc.buddha == BuddhaState.buddha ? "" : "anti") ~ "buddha_" ~ desc.filename ~ ".tmp", tmpdata.cerealise);
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

		clearBuddhaData();
	}

	writeln("--------------------\n");
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

BrotParams createBrotDesc(JSONValue s) {
	BrotParams ret = BrotParams();
	
	if (s.type != JSONType.object) return ret;

	if ("width" in s && s["width"].integer) ret.width = to!int(s["width"].integer);
	if ("height" in s && s["height"].integer) ret.height = to!int(s["height"].integer);

	if ("amp" in s && s["amp"].integer) {
		ret.width = 16 * to!int(s["amp"].integer);
		ret.height = 16 * to!int(s["amp"].integer);
	}

	if ("x1" in s && "x2" in s && "y1" in s && "y2" in s) {
		const auto x = ( s["x1"].floating + s["x2"].floating ) / 2;
		const auto y = ( s["y1"].floating + s["y2"].floating ) / 2;
		const auto radX = max(s["x1"].floating, s["x2"].floating) - min(s["x1"].floating, s["x2"].floating);
		const auto radY = max(s["y1"].floating, s["y2"].floating) - min(s["y1"].floating, s["y2"].floating);

		ret.originX = x;
		ret.originY = y;
		ret.radius = max(radX, radY);
	}

	if ("x" in s) ret.originX = s["x"].floating;
	if ("y" in s) ret.originY = s["y"].floating;
	if ("radius" in s) ret.radius = s["radius"].floating;

	if ("dwell" in s && s["dwell"].integer) ret.dwell = to!int(s["dwell"].integer);
	if ("palette" in s && s["palette"].integer >= 0) ret.palette = to!int(s["palette"].integer);
	if ("paletteOffset" in s) ret.paletteOffset = to!float(s["paletteOffset"].floating);

	if ("multibrotExp" in s) ret.multibrotExp = s["multibrotExp"].floating;

	if ("type" in s) ret.type = to!FType(s["type"].str);
	if ("colorfunc" in s) ret.colorfunc = to!ColorFunc(s["colorfunc"].str);

	if ("buddha" in s && s["buddha"].boolean) {
		ret.buddha = BuddhaState.buddha;
	} else if ("antibuddha" in s && s["antibuddha"].boolean) {
		ret.buddha = BuddhaState.antibuddha;
	}

	if ("filename" in s) {
		ret.filename = s["filename"].str;
	} else {
		ret.filename = ret.generateFileName();
	}

	return ret;
}

void generateAnimateSequence(ref BrotParams[] queue, JSONValue animate) {
	const int frames = to!int(animate["animate"].integer);
	const BrotParams from = createBrotDesc(animate["from"]);
	const BrotParams endp = createBrotDesc(animate["to"]);
	//const string fpath = from.filename ~ "++" ~ endp.filename ~ "_FRAMES=" ~ to!string(frames) ~ "/";
	const string fpath = "animate_FRAMES=" ~ to!string(frames) ~ "_X0=" ~ format!"%.17g"(from.originX) ~ "_Y0=" ~ 
		format!"%.17g"(from.originY) ~ "_Rn=" ~ format!"%.17g"(endp.radius) ~ "/";

	if (!(workdir ~ "/" ~ fpath).exists) (workdir ~ "/" ~ fpath).mkdir;

	const double deltaX = (endp.originX - from.originX) / to!double(frames);
	const double deltaY = (endp.originY - from.originY) / to!double(frames);
	const double deltaRadius = (log(endp.radius) - log(from.radius)) / to!double(frames);
	const float deltaDwell = (log(endp.dwell) - log(from.dwell)) / to!double(frames);
	const float deltaPalette = ( log(endp.palette ? endp.palette : endp.dwell) - 
		log(from.palette ? from.palette : from.dwell) ) / to!double(frames);
	const float deltaExp = (endp.multibrotExp - from.multibrotExp) / to!double(frames);

	const int w = from.width;
	const int h = from.height;

	for(int i=0; i <= frames; i++) {
		auto ret = BrotParams();

		ret.width = w;
		ret.height = h;
		ret.originX = from.originX + deltaX * i;
		ret.originY = from.originY + deltaY * i;
		ret.radius = exp(log(from.radius) + deltaRadius * i);

		ret.dwell = cast(int)exp( log(from.dwell) + deltaDwell * i);
		ret.palette = cast(int)exp( log(from.palette) + deltaPalette * i);

		ret.multibrotExp = from.multibrotExp + (deltaExp * i);

		ret.type = from.type;
		ret.colorfunc = from.colorfunc;
		ret.buddha = from.buddha;

		ret.filename = fpath ~ "frame_" ~ format!"%06d"(i);

		queue.length++;
		queue[$-1] = ret;
	}
}
void generateChunksSequence(ref BrotParams[] queue, JSONValue source) {
	const int chunks = to!int(source["chunks"].integer);
	const BrotParams s = createBrotDesc(source);

	const string fpath = "CHUNKED=" ~ to!string(chunks) ~ "_" ~ s.filename ~ "/";

	if (!(workdir ~ "/" ~ fpath).exists) (workdir ~ "/" ~ fpath).mkdir;

	if (s.buddha != BuddhaState.none) {
		if (!(workdir ~ "/" ~ to!string(s.buddha) ~ "_" ~ fpath).exists) 
			(workdir ~ "/" ~ to!string(s.buddha) ~ "_" ~ fpath).mkdir;
	}

	const int w = cast(int)( s.width / to!double(chunks) );
	const int h = cast(int)( s.height / to!double(chunks) );

  const double diff = cast(double)( min(w, h) )/max(w, h);
  const double radiusX = s.radius * (w > h ? 1 : diff) / to!double(chunks);
  const double radiusY = s.radius * (w < h ? 1 : diff) / to!double(chunks);

	const double x1 = s.originX - (s.radius * (w > h ? 1 : diff) / to!double(chunks))*(chunks/2 + 2);
	const double y1 = s.originY + (s.radius * (w < h ? 1 : diff) / to!double(chunks))*(chunks/2 + 2);

	for(int i=0; i < chunks; i++) {
		for(int j=0; j < chunks; j++) {
			auto ret = BrotParams();

			ret.width = w;
			ret.height = h;
			ret.originX = x1 + radiusX * 2 * (j + 0.5);
			ret.originY = y1 - radiusY * 2 * (i + 0.5);
			ret.radius = min(radiusX, radiusY);

			ret.dwell = s.dwell;
			ret.palette = s.palette;

			ret.multibrotExp = s.multibrotExp;

			ret.type = s.type;
			ret.colorfunc = s.colorfunc;
			ret.buddha = s.buddha;

			ret.filename = fpath ~ "chunk_" ~ format!"%06d"(i*chunks+j);

			queue.length++;
			queue[$-1] = ret;
		}
	}
}
