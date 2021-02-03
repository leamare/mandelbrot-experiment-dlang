module pixel;

import std.stdio;
import std.math;
import std.algorithm;
import std.conv;
import std.typecons;

import core.atomic;

import dlib.image.color;
import dlib.image.hsv;

// palette:
// - black
// - Zrellow
// - red-ish
// - blue

const auto logBase = 1.0 / log(2.0);
const auto logHalfBase = log(0.5)*logBase;

alias Complex = Tuple!(double, double);
alias Coord = Tuple!(int, int);

shared int[][] large_array;
shared int max_i = 20;
shared int max_bi = 1;
shared int min_bi = 20;

shared double avg_bi = 1;
shared double exp_bi = 1;

shared Complex origin = Complex(0.5, 0.0);
shared double radius = 2.0;

shared bool buddha = false;
shared int paletteSize = 20;

void initArr(int w, int h) {
  large_array.length = w;
  for(int i=0; i < w; i++) {
    large_array[i].length = h;
    for (int j=0; j<h; j++)
      large_array[i][j] = 0;
  }
}

void setIter(int i) {
  max_i = i;
  min_bi = i;
  paletteSize = i;
}

void setOrigin(double centerX, double centerY, double newRadius) {
  origin[0] = -centerX;
  origin[1] = centerY;
  // origin = Complex(-centerX, centerY);
  radius = newRadius;
}

void enableBuddha(bool state = true) {
  buddha = state;
}

void setPaletteSize(int psz = 0) {
  if (psz)
    paletteSize = psz;
  else 
    paletteSize = max_i;
}

Color4f pixelcolor(int pZi, int pZr, int w, int h) {
  Complex[] iter_history;
  if (buddha)
    iter_history.length = max_i+1;

  const Complex convertedPoint = convertPixelToPoint(pZi, pZr, w, h);
  const double Ci = convertedPoint[0];
  const double Cr = convertedPoint[1];

	double Zi = 0;
	double Zr = 0;
	int iter;
	double Zi_temp = 0;

	// Here N = 2^8 is chosen as a reasonable bailout radius.
  //  <= (1 << 16)
	for (iter = 0; Zi*Zi + Zr*Zr <= (1 << 16) && iter < max_i; iter++) {
		Zi_temp = Zi*Zi - Zr*Zr + Ci;
		Zr = 2*Zi*Zr + Cr;
		Zi = Zi_temp;
		
    if (buddha)
      iter_history[iter] = Complex(Zi, Zr);
	}

  if (buddha) {
    if (iter < max_i) {
      for (int i=0; i<iter; i++) {
        // writeln(i, ' ', iter, ' ', iter_history[i]);
        Coord point = convertPointToPixel( iter_history[i][0], iter_history[i][1], w, h );
        if (point[1] >= h || point[0] >= w || point[0] < 0 || point[1] < 0) {
          continue;
        } //else writeln(point);
        // large_array[ point[0] ][ point[1] ]++;
        atomicOp!"+="(large_array[ point[0] ][ point[1] ], 1);
      }
    }
  }

	double iter_d = iter;

	if (iter < max_i) {
		const double log_zn = log(Zi*Zi + Zr*Zr) / 2;
		const double nu = log( log_zn / log(2) ) / log(2);

		// Rearranging the potential function.
		// Dividing log_zn by log(2) instead of log(N = 1<<8)
		// because we want the entire palette to range from the
		// center to radius 2, NOT our bailout radius.
		// iter_d = 5 + iter - logHalfBase - log(log(Tr+Ti))*logBase;
    iter_d = 1 + to!double(iter) - nu;
	}

  //grayscale

  // auto Tr = Zi*Zi;
  // auto Ti = Zr*Zr;

  // if ( iter == max_i ) return Color4f(0,0,0);

  // auto v = iter_d/paletteSize % 1;
  // // if (v > 1) v = 1.;
  // return Color4f(v, v, v);

  // HSV

  if ( iter == max_i ) return Color4f(0,0,0);

  auto v = iter_d/paletteSize % 1;
  auto c = hsv(360.0*v, 1.0, 10.0*v);

  return Color4f(c.b, c.g, c.r);
}

Coord convertPointToPixel(double Ci, double Cr, int w, int h) {
  int pZi, pZr;
  double di, dr;

  if (w == h) {
    di = 0;
    dr = 0;
  } else {
    double diff = cast(double)( max(w, h)-min(w, h) )/min(w, h);
    di = w > h ? diff : -diff/2;
    dr = w > h ? -diff/2 : diff;
  }

  pZi = cast(int)( round( (Ci + radius + origin[0] + di) * to!double(w)/(radius*2 + di*2) ) );
  pZr = cast(int)( round( (Cr + radius + origin[1] + dr) * to!double(h)/(radius*2 + dr*2) ) );


  return Coord(pZi, pZr);
}

Complex convertPixelToPoint(int pZi, int pZr, int w, int h) {
  double Ci, Cr;
  double di, dr;

  if (w == h) {
    di = 0;
    dr = 0;
  } else {
    double diff = cast(double)( max(w, h)-min(w, h) )/min(w, h);
    di = w > h ? diff : -diff/2;
    dr = w > h ? -diff/2 : diff;
  }

  Ci = (to!double(pZi)*(radius*2 + di*2)/to!double(w)) - radius - origin[0] - di;
  Cr = (to!double(pZr)*(radius*2 + dr*2)/to!double(h)) - radius - origin[1] - dr;

  return Complex(Ci, Cr);
}

void updateMaxBI() {
  foreach (k, v; large_array) {
    foreach (key, value; v) {
      if (max_bi < value) max_bi = value;
    }
  }
  writeln("Max buddha: ", max_bi);

  double local_sums = 0;
  foreach (k, v; large_array) {
    long sum = 0;
    foreach (key, value; v) {
      sum += value;
    }
    local_sums += sum / v.length;
  }
}

Color4f getBuddhabrotted(int pZi, int pZr) {
  const int v = large_array[pZi][pZr];

  double c =  pow( cast(double)(v) / cast(double)(max_bi), 0.25 );
  
  if (c > 1) c = 1;

  return Color4f(c, c, c);
}


  return Color4f(
    c,
    c,
    c
  );
}

double linear_interp(double v0, double v1, double t) {
  return (1 - t) * min(v0, v1) + t * max(v1, v0);
}