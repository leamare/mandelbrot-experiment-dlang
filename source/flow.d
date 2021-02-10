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


void brotFlow(BrotParams desc) {
}

string generateFileName(BrotParams s) {
}

void generateAnimateSequence() {}
void generateChunksSequence() {}
