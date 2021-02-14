# Mandelbrot Dlang experiment

A test dlang app that generates image of Mandelbrot set of a given size and given section of coordinates.

Details blog: TBD

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
  - `-t | --type` - Fractal type (mandelbrot, multibrot, ship), **mandelbrot** by default
  - `-e | --exponent` - Multibrot exponent, **2.0** by default
- Coloring
  - `-p | --palettesize` - Palette size, Dwell number by default
  - `-c | --colorfunc` - Coloring function, **ultrafrac** by default
    Possible coloring functions are:
      * ultrafrac
      * hsv
      * gray
      * blue
      * red
      * oceanid
      * fire
      * seashore
      * cnfsso
      * acid
      * softhours
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
    // palette offset, float 0-1, percentage tby which palette should be shifted
    // only works with gradient-based palettes
    "paletteOffset": 0.5,
    // type: string with value "mandelbrot", "multibrot" or "ship"
    "type": "mandelbrot",
    // multibrot power
    "multibrotExp": 2.0,
    // colorfunc: string, value is one of the color function list from cli args
    "colorfunc": "cnfsso",
    // buddha and antibuddha, same rules as in cli
    "buddha": true,
    "antibuddha": false,
    // filename, .png is appended automatically, as well as working directory
    "filename": "cool_file_name",
  },
]
```

It's possible to describe two kinds of special jobs: animation and chunked image.

For anination you need to describe a job as follows:

```json
{
  // number of frames
  "animate": 420,
  // Object describing a srarting point job
  // non-animatable properties are copied from it
  "from": {...},
  // ending point job
  "to": {...}
}
```

Chunked image is an image generated in chunks.
To generate an image in chunks you should specify `chunks` parameter in the job descriptor object.
`chunks` is an integer, number of chunks in one line/row. Total number of chunks will be chunks^2.