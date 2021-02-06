module pixel;

import std.stdio;
import std.math;
import std.algorithm;
import std.conv;
import std.typecons;

import core.atomic;

import dlib.image.color;
import dlib.image.hsv;



const auto logBase = 1.0 / log(2.0);
const auto logHalfBase = log(0.5)*logBase;

alias Complex = Tuple!(double, double);
alias Coord = Tuple!(int, int);
enum FType { mandelbrot, multibrot, ship }
enum ColorFunc { ultrafrac, hsv, gray, blue, red }

shared int[][] large_array;
shared int max_i = 20;
shared int max_bi = 1;
shared int min_bi = 20;

shared Complex origin = Complex(0.5, 0.0);
shared double radius = 2.0;

shared bool buddha = false;
shared int paletteSize = 20;

shared FType type;
shared ColorFunc colorfunc;

const Color4f[] palette = [
  RGBtoColor4f(66, 30, 15),
  RGBtoColor4f(25, 7, 26),
  RGBtoColor4f(9, 1, 47),
  RGBtoColor4f(4, 4, 73),
  RGBtoColor4f(0, 7, 100),
  RGBtoColor4f(12, 44, 138),
  RGBtoColor4f(24, 82, 177),
  RGBtoColor4f(57, 125, 209),
  RGBtoColor4f(134, 181, 229),
  RGBtoColor4f(211, 236, 248),
  RGBtoColor4f(241, 233, 191),
  RGBtoColor4f(248, 201, 95),
  RGBtoColor4f(255, 170, 0),
  RGBtoColor4f(204, 128, 0),
  RGBtoColor4f(153, 87, 0),
  RGBtoColor4f(106, 52, 3),
];

// preset functions

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
  paletteSize = cast(int)(i*0.3);
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

void setColorFunc(ColorFunc value = ColorFunc.init) {
  colorfunc = value;
}

void setType(FType value = FType.init) {
  type = value;
}

void setPaletteSize(int psz = 0) {
  if (psz)
    paletteSize = psz;
  else 
    paletteSize = max_i;
}

// calculators

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
        Coord point = convertPointToPixel( iter_history[i][0], iter_history[i][1], w, h );
        if (point[1] >= h || point[0] >= w || point[0] < 0 || point[1] < 0) {
          continue;
        }
        atomicOp!"+="(large_array[ point[0] ][ point[1] ], 1);
      }
    }
  }

	double iter_d = iter;
  // auto Tr = Zi*Zi;
  // auto Ti = Zr*Zr;

	if (iter < max_i) {
		const double log_zn = log(Zi*Zi + Zr*Zr) * 0.5;
		const double nu = log( log_zn * logBase ) * logBase;

		// Rearranging the potential function.
		// Dividing log_zn by log(2) instead of log(N = 1<<8)
		// because we want the entire palette to range from the
		// center to radius 2, NOT our bailout radius.
    iter_d = 1 + to!double(iter) - nu;
	}

  // coloring

  if ( iter == max_i ) return Color4f(0,0,0);

  if (colorfunc == ColorFunc.ultrafrac) {
    ubyte c1, c2;

    auto paletteBlock = to!float(paletteSize)/palette.length;

    c1 = cast(ubyte)( floor(iter_d/paletteBlock) % palette.length );
    c2 = iter + paletteBlock >= max_i ? 4 : to!ubyte( (c1 + 1) % palette.length );

    const float vd = (iter_d % paletteBlock) / paletteBlock;
    
    return Color4f(
      palette[c1].r + (palette[c2].r - palette[c1].r) * vd,
      palette[c1].g + (palette[c2].g - palette[c1].g) * vd,
      palette[c1].b + (palette[c2].b - palette[c1].b) * vd,
    );
  } else if (colorfunc == ColorFunc.hsv) {
    auto v = (iter_d/paletteSize % 1);
    auto c = hsv(360.0*v, 1.0, 10.0*v);
    return Color4f(c.b, c.g, c.r);
  } else {
    auto v = iter_d/paletteSize % 1;
    // if (v > 1) v = 1.;
    if (colorfunc == ColorFunc.blue)
      return Color4f(0, v*v, v);
    
    if (colorfunc == ColorFunc.red)
      return Color4f(v, v*v, 0);

    return Color4f(v, v, v);
  }
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

// service 

Color4f RGBtoColor4f(ubyte r, ubyte g, ubyte b) {
  return Color4f(
    to!float(r)/255.,
    to!float(g)/255.,
    to!float(b)/255.
  );
}