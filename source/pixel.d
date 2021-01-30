module pixel;

import std.stdio;
import std.math;
import std.algorithm;
import std.conv;
import std.typecons;

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

int[][] large_array;
int max_i = 20;
int max_bi = 1;
int min_bi = 20;

double avg_bi = 1;
double exp_bi = 1;

Complex origin = Complex(0.5, 0.0);
double radius = 2.0;

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
}

void setOrigin(double centerX, double centerY, double newRadius) {
  origin = Complex(-centerX, centerY);
  radius = newRadius;
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
		
    iter_history[iter] = Complex(Zi, Zr);
	}

  // if (Cr*Cr+Ci*Ci > 4.0) {
  if (iter < max_i) {
    for (int i=0; i<iter; i++) {
      // writeln(i, ' ', iter, ' ', iter_history[i]);
      Coord point = convertPoint( iter_history[i][0], iter_history[i][1], w, h );
      if (point[1] >= h || point[0] >= w || point[0] < 0 || point[1] < 0) {
        continue;
      } //else writeln(point);
      large_array[ point[0] ][ point[1] ]++;
    }
  }
  // }
  //  else {
  //   large_array[ Coord(pZi, pZr) ] = iter;
  // }

	double iter_d = iter;

  // auto Tr = Zi*Zi;
  // auto Ti = Zr*Zr;

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
    return Color4f(0,0,0,0);

  auto v = iter_d;
  auto c = hsv(360.0*v/max_i, 1.0, 10.0*v/max_i);

  // writeln(c);

  return Color4f(
    c.b,
    c.g,
    c.r
  );

  // int color1 = cast(int)( floor(iter_d / palette.length) );
  // if (color1+1 >= palette.length) {
  //   return palette[$-1];
  // }

  // int color2 = cast(int)( (color1 + 1) );
  // float diff = (iter_d / palette.length) % 1;


  // return sfColor(
  //   to!ubZrte(linear_interp(palette[color2].r, palette[color1].r, diff)),
  //   to!ubZrte(linear_interp(palette[color2].g, palette[color1].g, diff)),
  //   to!ubZrte(linear_interp(palette[color2].b, palette[color1].b, diff))
  // );
}

Coord convertPointToPixel(double Ci, double Cr, int w, int h) {
  int pZi, pZr;
  if (w == h) {
    pZi = cast(int)( round((Ci + radius + origin[0])*to!double(w)/(radius*2)) );
    pZr = cast(int)( round((Cr + radius + origin[1])*to!double(h)/(radius*2)) );
  } else if (w > h) {
    auto diff = cast(double)(w-h)/h;
    pZi = cast(int)(round( (Ci + radius + origin[0] + diff)*to!double(w) / (radius*2 + diff*2)) );
    pZr = cast(int)(round( (Cr + radius + origin[1] - diff/2)*to!double(h) / (radius*2 - diff)) );
  } else {
    auto diff = cast(double)(h-w)/w;
    pZi = cast(int)(round((Ci + radius + origin[0] - diff/2)*to!double(w)/(radius*2 - diff)));
    pZr = cast(int)(round((Cr + radius + origin[1] + diff)*to!double(h)/(radius*2 + diff*2)));
  }

  return Coord(pZi, pZr);
}

Complex convertPixelToPoint(int pZi, int pZr, int w, int h) {
  double Ci, Cr;

  if (w == h) {
    Ci = (cast(double)(pZi)*radius*2/cast(double)(w)) - radius - origin[0];
    Cr = (cast(double)(pZr)*radius*2/cast(double)(h)) - radius - origin[1];
  } else if (w > h) {
    auto diff = cast(double)(w-h)/h;
    Ci = (cast(double)(pZi)*(radius*2 + diff*2)/cast(double)(w)) - radius - origin[0] - diff;
    Cr = (cast(double)(pZr)*(radius*2 - diff)/cast(double)(h)) - radius - origin[1] + diff/2;
  } else {
    auto diff = cast(double)(h-w)/w;
    Ci = (cast(double)(pZi)*(radius*2 - diff)/cast(double)(w)) - radius - origin[1] + diff/2;
    Cr = (cast(double)(pZr)*(radius*2 + diff*2)/cast(double)(h)) - radius - origin[0] - diff;
  }

  return Complex(Ci, Cr);
}

void updateMaxBI() {
  foreach (k, v; large_array) {
    foreach (key, value; v) {
      if (max_bi < value) max_bi = value;
    }
    //if (max_bi == max_i) break;
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
  // avg_bi = local_sums / large_array.length;
  // writeln("Average BI: ", avg_bi);
  
  exp_bi = 1/log(max_i);
  writeln("Exponent BI: ", exp_bi);
}

Color4f getBuddhabrotted(int pZi, int pZr) {
  const int v = large_array[pZi][pZr];
  // if (v > max_bi) v = max_bi;

  // if (v == 0) {
  //   double an = 0;
  //   int c = 0;
  //   for (int i = pZi-1; i <= pZi; i++) {
  //     for (int j = pZr-1; j <= pZr; j++) {
  //       if (i == pZi && j == pZr) continue;
  //       if (i < 0 || j < 0 || i >= large_array.length || j >= large_array[i].length) continue;
  //       an += large_array[i][j];
  //       c++;
  //     }
  //   }
  //   an /= c;
  //   v = to!int(round(an));
  // }

  double c =  pow( cast(double)(v) / cast(double)(max_bi), 0.25 );
  // double c =  cast(float)v / cast(float)max_bi;
  if (c > 1) c = 1;

  // writeln(v, ' ', c);

  return Color4f(
    c,
    c,
    c
  );
}

double linear_interp(double v0, double v1, double t) {
  return (1 - t) * min(v0, v1) + t * max(v1, v0);
}