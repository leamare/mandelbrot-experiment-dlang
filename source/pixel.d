module pixel;

import std.stdio;
import std.math;
import std.algorithm;
import std.conv;

import dlib.image.hsv;

// palette:
// - black
// - yellow
// - red-ish
// - blue

const auto logBase = 1.0 / log(2.0);
const auto logHalfBase = log(0.5)*logBase;

struct sfColor {
  ubyte r;
  ubyte g;
  ubyte b;
  ubyte a;
  this(ubyte cr, ubyte cg, ubyte cb, ubyte ca = to!ubyte(255)) {
    r = cr;
    g = cg;
    b = cb;
    a = ca;
  }
}

sfColor[] palette = [
  sfColor(0, 0, 0),
  sfColor(255, 255, 255),
  // sfColor(0, 255, 255),
  // sfColor(0, 0, 255),
  // sfColor(255, 255, 0),
  sfColor(0, 0, 0),
];

sfColor pixelcolor(int px, int py, int w, int h) {
  double x0, y0;

  if (w == h) {
    x0 = (cast(double)(px)*4.0/cast(double)(w)) - 2.5;
    y0 = (cast(double)(py)*4.0/cast(double)(h)) - 2.0;
  } else if (w > h) {
    auto diff = cast(double)(w-h)/h;
    x0 = (cast(double)(px)*(4.0+diff*2)/cast(double)(w)) - 2.5 - diff;
    y0 = (cast(double)(py)*(4.0-diff)/cast(double)(h)) - 2.0 + diff/2;
  } else {
    auto diff = cast(double)(h-w)/w;
    x0 = (cast(double)(px)*(4.0-diff)/cast(double)(w)) - 2.5 + diff/2;
    y0 = (cast(double)(py)*(4.0+diff*2)/cast(double)(h)) - 2.0 - diff;
  }

	double x = 0;
	double y = 0;
	int iter = 0;
	const int max_i = 392;
	double x_temp = 0;

	// Here N = 2^8 is chosen as a reasonable bailout radius.
  //  <= (1 << 16)
	while (x*x + y*y <= (1 << 16) && iter < max_i) {
		x_temp = x*x - y*y + x0;
		y = 2*x*y + y0;
		x = x_temp;
		iter++;
	}

	double iter_d = iter;

  // auto Tr = x*x;
  // auto Ti = y*y;

	if (iter < max_i) {
		const double log_zn = log(x*x + y*y) / 2;
		const double nu = log( log_zn / log(2) ) / log(2);

		// Rearranging the potential function.
		// Dividing log_zn by log(2) instead of log(N = 1<<8)
		// because we want the entire palette to range from the
		// center to radius 2, NOT our bailout radius.
		// iter_d = 5 + iter - logHalfBase - log(log(Tr+Ti))*logBase;
    iter_d = 1 + to!double(iter) - nu;
	}

  //grayscale

  // if ( iter == max_i ) { // converged?
  //   auto c = 255 - floor(255.0*sqrt(Tr+Ti)) % 255;
  //   if ( c < 0 ) c = 0;
  //   if ( c > 255 ) c = 255;
  //   return sfColor(
  //     to!ubyte(c),
  //     to!ubyte(c),
  //     to!ubyte(c)
  //   );
  // }

  // auto v = iter_d;
  // v = floor(512.0*v/max_i);
  // if ( v > 255 ) v = 255;
  // return sfColor(
  //   to!ubyte(v),
  //   to!ubyte(v),
  //   to!ubyte(v)
  // );

  // blue

  if ( iter == max_i ) // converged?
    return palette[$-1];

  auto v = iter_d;
  auto c = hsv(360.0*v/max_i, 1.0, 10.0*v/max_i);

  // writeln(c);

  return sfColor(
    to!ubyte(c.b < 1.0 ? 255*c.b : 255),
    to!ubyte(c.g < 1.0 ? 255*c.g : 255),
    to!ubyte(c.r < 1.0 ? 255*c.r : 255)
  );

  // int color1 = cast(int)( floor(iter_d / palette.length) );
  // if (color1+1 >= palette.length) {
  //   return palette[$-1];
  // }

  // int color2 = cast(int)( (color1 + 1) );
  // float diff = (iter_d / palette.length) % 1;


  // return sfColor(
  //   to!ubyte(linear_interp(palette[color2].r, palette[color1].r, diff)),
  //   to!ubyte(linear_interp(palette[color2].g, palette[color1].g, diff)),
  //   to!ubyte(linear_interp(palette[color2].b, palette[color1].b, diff))
  // );
}

double linear_interp(double v0, double v1, double t) {
  return (1 - t) * min(v0, v1) + t * max(v1, v0);
}