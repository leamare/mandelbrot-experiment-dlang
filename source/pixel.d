module pixel;

import std.stdio;
import std.math;
import std.algorithm;
import std.conv;
import std.typecons;

import core.atomic;

import dlib.image.color;
import dlib.image.hsv;

// I don't really want to use it but I won't be able to calculate 
// negative multibrots otherwise so yes, it's only used in ONE specific place
// and in every other I'm doing in an old-fashioned way
// I could've implement it myself, but I don't have any idea how to
// import std.complex;

const auto logBase = 1.0 / log(2.0);
const auto logHalfBase = log(0.5)*logBase;

alias Complex = Tuple!(double, double);
alias Coord = Tuple!(int, int);
enum FType { mandelbrot, multibrot, ship }
enum ColorFunc { ultrafrac, hsv, gray, blue, red, base }

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

shared float multibrotExp = 2.0;

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

void setMultibrotBase(float value = 2.0) {
  multibrotExp = value;
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

  const Complex convertedPoint = convertPixelToPoint(pZr, pZi, w, h);
  const double Cr = convertedPoint[0];
  const double Ci = convertedPoint[1];

	double Zr = 0;
	double Zi = 0;
	int iter;
	double Zr_temp = 0;

  if (type == FType.multibrot && multibrotExp != 2.0) {
    double r;

    // using std.complex it would be easier
    // but it wouldn't be interesting enough
    // here's the code
    //
    // auto Zn = complex(Zr, Zi);

    // for (iter = 0; Zr*Zr + Zi*Zi <= (1 << 16) && iter < max_i; iter++) {
    //   Zn = pow(Zn, multibrotExp);
    //   Zr = Zn.re + Cr;
    //   Zi = Zn.im + Ci;
    //   Zn = complex(Zr, Zi);

    //   if (buddha)
    //     iter_history[iter] = Complex(Zr, Zi);
    // }

    if (multibrotExp > 0) {
      for (iter = 0; Zr*Zr + Zi*Zi <= (1 << 16) && iter < max_i; iter++) {
        r = pow(Zr*Zr + Zi*Zi, multibrotExp/2);
        Zr_temp = r * cos(multibrotExp * atan2(Zi, Zr)) + Cr;
        Zi = r * sin(multibrotExp * atan2(Zi, Zr)) + Ci;
        Zr = Zr_temp;
        
        if (buddha)
          iter_history[iter] = Complex(Zr, Zi);
      }
    } else if (multibrotExp < 0) {
      auto m = -multibrotExp;
      for (iter = 0; Zr*Zr + Zi*Zi <= (1 << 16) && iter < max_i; iter++) {
        r = pow(Zr*Zr + Zi*Zi, m/2);
        Zr_temp = r * cos(m * atan2(Zi, Zr));
        Zi = r * sin(m * atan2(Zi, Zr));
        Zr = Zr_temp;

        // dividing (1 + 0i) / z
        r = (Zr*Zr + Zi*Zi);
        if (r == 0) {
          Zr = Cr;
          Zi = Ci;
        } else {
          Zr_temp = Zr / r + Cr;
          Zi = -Zi / r + Ci;
          Zr = Zr_temp;
        }
        
        if (buddha)
          iter_history[iter] = Complex(Zr, Zi);
      }
    } else {
      for (iter = 0; Zr*Zr + Zi*Zi <= (1 << 16) && iter < max_i; iter++) {
        Zr_temp = 1 + Cr;
        Zi = 0 + Ci;
        Zr = Zr_temp;

        if (buddha)
          iter_history[iter] = Complex(Zr, Zi);
      }
    }
  } else if (type == FType.ship) {
    for (iter = 0; Zr*Zr + Zi*Zi <= (1 << 16) && iter < max_i; iter++) {
      Zr_temp = Zr*Zr - Zi*Zi + Cr;
      Zi = abs(2*Zr*Zi) + Ci;
      Zr = Zr_temp;
      
      if (buddha)
        iter_history[iter] = Complex(Zi, Zr);
    }
  } else {
    for (iter = 0; Zr*Zr + Zi*Zi <= (1 << 16) && iter < max_i; iter++) {
      Zr_temp = Zr*Zr - Zi*Zi + Cr;
      Zi = 2*Zr*Zi + Ci;
      Zr = Zr_temp;
      
      if (buddha)
        iter_history[iter] = Complex(Zr, Zi);
    }
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

  if (type == FType.multibrot && multibrotExp <= 1) {
    iter = max_i - iter;
  }

	if (iter < max_i) {
		const double log_zn = log(Zr*Zr + Zi*Zi) * 0.5;
		const double nu = log( log_zn * logBase ) * logBase;

    iter_d = 1 + to!double(iter) - nu;
	}

  // coloring

  if ( iter == max_i ) return Color4f(0,0,0);

  if (colorfunc == ColorFunc.ultrafrac) {
    ubyte c1, c2;

    auto paletteBlock = to!float(paletteSize)/palette.length;

    c1 = cast(ubyte)( floor(abs(iter_d)/paletteBlock) % palette.length );
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
  } else if (colorfunc == ColorFunc.base) {
    if (iter_d > 0) return Color4f(1.0, 1.0, 1.0);
    return Color4f(0, 0, 0);
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

Coord convertPointToPixel(double Cr, double Ci, int w, int h) {
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

  pZi = cast(int)( round( (Cr + radius + origin[0] + di) * to!double(w)/(radius*2 + di*2) ) );
  pZr = cast(int)( round( (Ci + radius + origin[1] + dr) * to!double(h)/(radius*2 + dr*2) ) );


  return Coord(pZi, pZr);
}

Complex convertPixelToPoint(int pZr, int pZi, int w, int h) {
  double Cr, Ci;
  double di, dr;

  if (w == h) {
    di = 0;
    dr = 0;
  } else {
    double diff = cast(double)( max(w, h)-min(w, h) )/min(w, h);
    di = w > h ? diff : -diff/2;
    dr = w > h ? -diff/2 : diff;
  }

  Cr = (to!double(pZi)*(radius*2 + di*2)/to!double(w)) - radius - origin[0] - di;
  Ci = (to!double(pZr)*(radius*2 + dr*2)/to!double(h)) - radius - origin[1] - dr;

  return Complex(Cr, Ci);
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

Color4f getBuddhabrotted(int pZr, int pZi) {
  const int v = large_array[pZr][pZi];

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