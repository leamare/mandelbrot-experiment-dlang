# Mandelbrot Dlang experiment

A test dlang app that generates image of Mandelbrot set of a given size and given section of coordinates.

Details in blog with demos and stuff: [English](https://medium.com/@leamare/experiment-with-mandelbrot-set-and-d-language-fdda4606ce9b) [Russian](https://log.ileamare.ru/2021/02/d.html)

Buddhabrot is calculated using naive method.

## Build

1. Install DUB
2. Run `dub build`
3. Enjoy

## Usage

The app can access parameters from command line or from JSON file.
It's not ready to handle unreasonable JSON values and cli args, so be careful with it.

### Supported CLI arguments

- `-h | --help` - List of CLI arguments
- Calculations definitions
  - `-i | --iterations` - Maximum dwell number, **100** by default
  - `-x | --originx` - Real part (x) of the center point, **-0.5** by default
  - `-y | --originy` - Imaginary part (y) of the center point, **0.0** by default
  - `-r | --radius` - Camera radius (smallest side), **2.0** by default
  - `-a | --amp` - Image size amplification, used to calculate size for square images, multiplying it by 16, **50** by default
  - `-ws | --width` - Image width, **16\*amp** by default
  - `-hs | --height` - Image height, **16\*amp** by default
- Additional plotting/calculating settings
  - `-b | --buddha` - Create Buddhabrot, false by default
  - `-n | --antibuddha` - Create Anti Buddhabrot, false by default
  - **NOTE:** Only one of -b and -n can be active at a time (-b has priority)
  - `-t | --type` - Fractal type (mandelbrot, multibrot, ship, mandelbar), **mandelbrot** by default
  - `-e | --exponent` - Multibrot exponent, **2.0** by default
  - `-v | --legacyiteration` - Legacy iteration mode (old-style negative exponent multibrot + inverted coloring), **false** by default
  - `-q | --escaperadius` - Escape radius threshold (|z|² > escapeRadius²), **4.0** by default
- Coloring
  - `-p | --palettesize` - Palette size, Dwell number by default
  - `-c | --colorfunc` - Color palette or function, **ultrafrac** by default
    Can be a built-in name or a custom palette filename (without .json):
      * Built-in algorithmic: hsv, gray, blue, red, base
      * Built-in palettes (from palettes/): ultrafrac, seashore, fire, oceanid, cnfsso, acid, softhours
      * Custom palette: any filename in palettes/ directory (e.g., "mypalette" loads "palettes/mypalette.json")
- Additional helpers
  - `-o | --output` - Output filename, generated based on parameters by default
  - `-d | --dir` - Output directory, `out` by default (created if does not exists)
  - `-s | --progress` - Save results to a separate file while working/import progress on load if found
    -1 for default block size (by percentage of lines), or any other int 1-50
  - `-k | --skip` - Skip existing files instead of recalculating them
- `-f | --flowlist` - Path to JSON file with a list of jobs

### JSON Syntax

Flowlist is a JSON file that has array of objects, describing jobs to execute.

Empty object (more accurately, any object's missing setting) is using default values from above (cli args).

Floating point variables should be **clearly defined as floating point**

Example of a JSON file with one fully described job:

```json
[
  {
    // width and height parameters
    "width": 1600,
    "height": 900,
    // amp parameter, same as cli, overrides width and height
    "amp": 512,

    // coordinates
    // can be defined in two ways: as a rectangle...
    "x1": -1.8609034765390223754525,
    "x2": -1.8609034764471059071895,
    "y1": 0.0008002498531361310295,
    "y2": 0.0008002499220734822265,
    // ...or as origin-radius
    "x": -1.7487156281015155,
    "y": 0.00044824588968512592,
    "radius": 1.6331380692236053e-13,
    // dwell and palette size
    "dwell": 2500,
    "palette": 350,
    // palette offset, float 0-1, percentage by which palette should be shifted
    // only works with gradient-based palettes
    "paletteOffset": 0.5,
    // type: string with value "mandelbrot", "multibrot", "mandelbar" or "ship"
    "type": "mandelbrot",
    // multibrot power
    "multibrotExp": 2.0,
    // legacyIteration: boolean, legacy iteration mode (matches old code behavior)
    //   When true:
    //     - Uses old-style negative exponent multibrot iteration
    //     - Inverts coloring: points in set get colored, escaping points are black
    //   This creates a gradient background effect instead of pure black background
    //   Works for all fractal types, false by default
    "legacyIteration": false,
    // escapeRadius: float, escape radius threshold (|z|² > escapeRadius²), 4.0 by default
    //   Lower values detect escape earlier, higher values allow deeper exploration
    "escapeRadius": 4.0,
    // colorfunc: string, value is one of the color function list from cli args
    "colorfunc": "cnfsso",
    // buddha and antibuddha, same rules as in cli
    "buddha": true,
    "antibuddha": false,
    // filename, .png is appended automatically, as well as working directory
    "filename": "cool_file_name",
    
    // Precision control parameters
    // precision: string, controls precision mode
    //   Values: "auto", "double", "quaddouble", "mpfr"
    //   "auto" (default): Automatically selects based on zoom depth
    //   "double" or "standard": Standard double precision (~15 decimal digits) - FASTEST
    //   "quaddouble" or "qd": Quad-double precision (~60 decimal digits) - FAST
    //   "mpfr" or "gmp": MPFR arbitrary precision (unlimited) - MEDIUM speed
    "precision": "auto",
    
    // Perturbation mode - controls use of perturbation theory for optimization
    // perturbations: string, controls perturbation optimization
    //   Values: "auto" (default), "enabled", "disabled"
    //   "auto": Use perturbation when beneficial (high iterations + deep zoom on Mandelbrot)
    //   "enabled": Always use perturbation when supported (Mandelbrot only)
    //   "disabled": Never use perturbation, always use direct iteration
    "perturbations": "auto",
    
    // Pixel offset parameters (shift viewport center)
    // x_px_offset: integer, number of pixels to offset center horizontally
    //   Positive values shift center right (point at +x_px_offset becomes new center)
    // y_px_offset: integer, number of pixels to offset center vertically
    //   Positive values shift center down (point at +y_px_offset becomes new center)
    //   Note: Origin coordinates in filename will reflect the adjusted center
    "x_px_offset": 0,
    "y_px_offset": 0,
    
    // Palette options
    // palette_reverse: boolean, reverses the color palette order
    //   Works with both external palettes and built-in palettes
    "palette_reverse": false,
    // NOTE: Custom palettes are now specified via "colorfunc" parameter:
    //   Use "colorfunc": "mypalette" to load "palettes/mypalette.json"
  },
]
```

It's possible to describe two kinds of special jobs: animation and chunked image.

For animation you need to describe a job as follows:

```json
{
  // number of frames
  "animate": 420,
  // Object describing a starting point job
  // non-animatable properties are copied from it
  "from": {...},
  // ending point job
  "to": {...}
}
```

Chunked image is an image generated in chunks.
To generate an image in chunks you should specify `chunks` parameter in the job descriptor object.
`chunks` is an integer, number of chunks in one line/row. Total number of chunks will be chunks^2.