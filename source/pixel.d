module pixel;

import std.stdio;
import std.math;

struct sfColor {
  byte r;
  byte g;
  byte b;
  byte a;
  this(byte cr, byte cg, byte cb, byte ca) {
    r = cr;
    g = cg;
    b = cb;
    a = ca;
  }
}

sfColor pixelcolor(int px, int py, int w, int h) {
  double x0, y0;

  if (w == h) {
    x0 = (cast(double)(px)*4.0/cast(double)(w)) - 2.5;
    y0 = (cast(double)(py)*4.0/cast(double)(h)) - 2.0;
  } else if (w > h) {
    auto diff = cast(double)(w-h)/h;
    x0 = (cast(double)(px)*(4.0+diff*2)/cast(double)(w)) - 2.5 - diff;
    y0 = (cast(double)(py)*4.0/cast(double)(h)) - 2.0;
  } else {
    auto diff = cast(double)(h-w)/w;
    x0 = (cast(double)(px)*4.0/cast(double)(w)) - 2.5;
    y0 = (cast(double)(py)*(4.0+diff)/cast(double)(h)) - 2.0 - diff/2;
  }

	double x = 0;
	double y = 0;
	int iter = 0;
	const int max_i = 1000;
	double x_temp = 0;

  bool outside = false;

	// Here N = 2^8 is chosen as a reasonable bailout radius.
  //  <= (1 << 16)
	while (x*x + y*y <= (1 << 16) && iter < max_i) {
		x_temp = x*x - y*y + x0;
		y = 2*x*y + y0;
		x = x_temp;
		iter++;
	}

	double iter_d = iter;

	if (iter < max_i) {
		const double log_zn = log(x*x + y*y) / 2;
		const double nu = log( log_zn / log(2) ) / log(2);
		// Rearranging the potential function.
		// Dividing log_zn by log(2) instead of log(N = 1<<8)
		// because we want the entire palette to range from the
		// center to radius 2, NOT our bailout radius.
		iter_d = iter + 1 - nu;
	}

  // nu = nu / max_i * colors;

  byte colorR, colorG, colorB;

  // auto h2 = 1.5;
  // auto angle = 45;
  // auto = exp()

  colorR = cast(byte)(floor(iter_d) % 255);
  colorG = cast(byte)(floor(iter_d/255) % 255);
  colorB = cast(byte)(floor(iter_d % 1 * 255));

  // writeln(iter);

  // int clr1 = (int)mu;
  // double t2 = mu - clr1;
  // double t1 = 1 - t2;
  // clr1 = clr1 % colors;
  // int clr2 = (clr1 + 1) % colors;

  // byte colorR = (byte)(Colors[clr1].R * t1 + Colors[clr2].R * t2);

  // writeln(x0, ' ', px, ' ', y0, ' ', py, ' ', iter, ' ', colorR);

	return sfColor(
		colorR, 
		colorG, 
		colorB,
    127
	);
}

// double linear_interp(double color_1, double color_2, double iter) {
//   return (1 - t) * v0 + t * v1;
// }