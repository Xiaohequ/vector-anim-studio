# VASF — Vector Anim Studio simple JSON format (v1 + extensions v2)

VASF is a compact, LLM-friendly JSON format for describing a complete 2D vector
animation (shapes, keyframes, optional skeleton rig) that the **Vector Anim Studio**
Android app can import directly.

Rules of thumb for generating a valid file:

- **Seconds** (double) for every time value. **Degrees** for every angle.
- Colors are strings `#RRGGBB` (or `#AARRGGBB`), or `"$alias"` resolved in the
  `theme` palette (VASF-2).
- A shape is **one primitive** by default; `"layers": [...]` (VASF-2) packs
  several primitives into one shape. Characters made of several parts = several
  shapes, each bound to its own bone.
- Draw order = order of the `shapes` array (first = background).
- Keyframes may be **partial**: a missing property is carried over from the
  previous keyframe (or from the base pose for the first keyframe).
- The importer collects ALL problems and reports them in French — fix them and retry.
- Nested project instances are not representable in VASF-1 (ignored on export).
- The VASF-2 extensions (below) are optional: a `version: 1` file stays valid.

# Top level

```json
{
  "version": 1,
  "name": "My animation",
  "canvas": {"width": 720, "height": 1280, "fps": 25, "background": "#14161C"},
  "shapes": [ ... ],
  "skeleton": { ... }
}
```

| field | type | default | notes |
|---|---|---|---|
| version | int | required | `1`, or `2` when using the VASF-2 extensions below |
| name | string | "Animation importée" | project name |
| canvas.width / height | number | 720 / 1280 | 16…4096 |
| canvas.fps | int | 25 | 5…60 (export fps) |
| canvas.background | string | `#14161C` | scene background (or `"$alias"`) |
| theme | object | optional | VASF-2 color palette: `{"peau": "#FFE3C2", …}` |
| defs | object | optional | VASF-2 reusable primitive definitions |
| shapes | array | required, ≥ 1 | draw order = array order |
| skeleton | object | optional | presence switches the project to **skeleton type** |

Coordinates: origin = top-left of the canvas, x → right, y → **down** (screen
convention). Positive degrees = clockwise on screen.

# Shape

```json
{
  "name": "Bloc",
  "type": "rect",
  "color": "#FF5C5C",
  "filled": true,
  "strokeWidth": 4,
  "width": 110,
  "height": 110,
  "points": [[0,0], [50,25]],
  "start": 0.0,
  "end": 2.0,
  "x": 180, "y": 320, "rotation": 0, "scale": 1, "opacity": 1,
  "keyframes": [ ... ]
}
```

| field | default | notes |
|---|---|---|
| name | "Forme" | must be unique (duplicates are auto-renamed "X 2") |
| type | "rect" | one of `rect, circle, line, path, triangle, star, hexagon, cross, heart, arrow` |
| color | `#5B8DEF` | fill/stroke color of the primitive |
| filled | true | `false` = outline only (stroke) |
| strokeWidth | 4 | outline thickness in scene units (used when `filled=false`, always for `line`) |
| width / height | 110 / 110 | primitive size in scene units (ignored for `path`: derived from points) |
| points | — | `path` only: `[x, y]` pairs **around the shape center** (≥ 2 points, auto-closed) |
| start / end | 0 / latest other end, else 4.0 | visibility window in seconds; `end` must be > `start` |
| x / y | canvas center | base position of the shape center |
| rotation | 0 | base rotation, degrees |
| scale | 1 | base scale (0.05–4 recommended) |
| scaleX / scaleY | 1 | VASF-2: base axis factors — effective scale = `scale` × factor (see below) |
| pivot | `[0, 0]` | VASF-2: `[dx, dy]` offset from the shape center, in shape units — rotation & scale turn around it (STATIC, see below) |
| opacity | 1 | 0–1 |
| layers | optional | VASF-2: array of primitive objects (see below) — overrides `type/color/filled/strokeWidth/width/height/points` |
| ref | optional | VASF-2: name of a `defs` entry used as geometry defaults (see below) |
| cycle | optional | VASF-2: `{"repeat": N}` repeats the keyframe pattern (see below) |
| keyframes | optional | see below |

### Keyframe (shape)

```json
{"t": 0.0, "x": 180, "y": 320, "rotation": 0, "scale": 1, "opacity": 1, "strokeWidth": 1, "easing": "easeInOut"}
```

- `t` (seconds, ≥ 0, sorted automatically) — a keyframe beyond `end` extends it.
- `easing` = curve of the segment ARRIVING at this keyframe: `linear, easeIn,
  easeOut, easeInOut, step` (default `easeInOut`). VASF-2 also accepts a CSS
  chain: `"cubic-bezier(x1, y1, x2, y2)"` (x1/x2 within [0, 1], see below).
- Any of `x, y, rotation, scale, opacity, strokeWidth` may be omitted (carried
  over). VASF-2 adds `scaleX` / `scaleY` (animatable axis factors, see below).
  `rotation` is in degrees. `strokeWidth` here animates the stroke
  **factor** (visible stroke = `strokeWidth` × factor).
- Keyframes are poses: the app interpolates each property independently.

# Skeleton (optional)

```json
{
  "name": "Rat",
  "bones": [
    {"name": "Bras",      "joint": [100, 320], "angle": 0,  "length": 100},
    {"name": "Avant-bras", "parent": "Bras", "joint": [200, 420], "angle": 90, "length": 80,
     "z": 0, "ik": false, "bend": 1}
  ],
  "bind": {"Bloc": "Bras"},
  "keyframes": [
    {"bone": "Bras", "t": 0.5, "angle": -30, "easing": "easeInOut",
     "opacity": 0.5, "stretch": 1.2, "squash": 1}
  ]
}
```

| field | default | notes |
|---|---|---|
| name | "Squelette" | rig name |
| bones | required, ≥ 1 | **parents must be listed before their children** |
| bone.name | required | unique |
| bone.joint | required `[x, y]` | anchor (joint) position **in world canvas coords**, at rest |
| bone.angle | 0 | **world** rest angle, degrees (the importer converts to the internal parent-relative form) |
| bone.length | 80 | bone length in scene units (> 0) |
| bone.parent | none | parent bone NAME |
| bone.z | 0 | draw order for the pieces carried by this bone (−10…10) |
| bone.ik | false | enable 2-bone IK (needs exactly one child) |
| bone.bend | 1 | elbow side for IK: +1 or −1 |
| bind | optional | map **shape name → bone name** |
| cycle | optional | VASF-2: `{"repeat": N}` repeats ALL bone keyframes (period = last − first time) |
| keyframes | optional | bone animation (see below) |

### Keyframe (bone)

```json
{"bone": "Bras", "t": 0.5, "angle": -30, "easing": "easeInOut", "opacity": 0.5, "stretch": 1.2, "squash": 1}
```

- `bone` = bone name (required), `t` seconds ≥ 0 (required).
- `angle` = **absolute WORLD angle in degrees** at that time (NOT a delta). The
  importer writes the internal delta = `angle − world rest angle` of the chain.
  Example: a child whose world rest angle is 90° given `angle: 30` rotates −60°.
- `opacity` (0–1), `stretch` (along the bone, 1 = neutral), `squash`
  (perpendicular, 1 = neutral) are optional per-keyframe bone properties.
- VASF-2: `easing` also accepts the CSS chain `"cubic-bezier(x1, y1, x2, y2)"`
  on bone keyframes.

# Worked example (bouncing ball)

```json
{
  "version": 1,
  "name": "Balle rebondissante",
  "canvas": {"width": 720, "height": 1280, "fps": 25, "background": "#14161C"},
  "shapes": [
    {
      "name": "Balle",
      "type": "circle",
      "color": "#FF5C5C",
      "width": 120, "height": 120,
      "end": 1.6,
      "x": 360, "y": 400,
      "keyframes": [
        {"t": 0.0, "x": 360, "y": 300},
        {"t": 0.4, "x": 360, "y": 1040, "easing": "easeIn"},
        {"t": 0.8, "x": 360, "y": 300, "easing": "easeOut"},
        {"t": 1.2, "x": 360, "y": 1040, "easing": "easeIn"},
        {"t": 1.6, "x": 360, "y": 300, "easing": "easeOut"}
      ]
    }
  ]
}
```

See `docs/vasf-1-examples.json` for a skeleton example (character waving an arm)
and a VASF-2 example (multi-layer character with theme, defs and cycle).

# VASF-2 extensions (optional — `version: 2`)

Everything below is optional; a `version: 1` file stays importable unchanged.
The importer EXPANDS all of it at import time — the animation engine is
unchanged, so the app renders exactly what it always rendered. Ready-to-import
single-object examples live in `docs/vasf-2-example.json` (multi-couches +
theme + defs + cycle) and `docs/vasf-2-g2-example.json` (scaleX/scaleY animées
+ pivot + cubic-bezier + liaison de couche).

## Theme (color palette)

```json
{"theme": {"peau": "#FFE3C2", "encre": "#14161C"}}
```

Any color field (canvas background, shape color, layer color, def color) may
reference an alias: `"color": "$peau"`. Change the palette once, everything
follows. An unknown alias is a collected error. Theme values must be literal
`#RRGGBB`/`#AARRGGBB` colors (no `$` of alias of alias).

## Layers — several primitives in one shape

```json
{
  "name": "Visage",
  "x": 360, "y": 640, "end": 2,
  "layers": [
    {"name": "Peau", "type": "circle", "color": "$peau", "width": 170, "height": 170},
    {"name": "Œil", "type": "circle", "color": "$encre", "width": 26, "height": 26, "x": -34, "y": -22},
    {"name": "Sourire", "type": "path", "filled": false, "strokeWidth": 5,
     "points": [[-38, 28], [38, 28], [0, 58]], "y": 43}
  ],
  "keyframes": [ {"t": 0, "y": 640}, {"t": 0.5, "y": 620}, {"t": 1, "y": 640} ]
}
```

Each layer accepts: `name` ("Couche"), `type`, `color` (alias OK), `filled`,
`strokeWidth`, `width` / `height`, `points` (path), plus a LOCAL pose
`x` / `y` (offset from the shape center), `rotation`, `scale`, `opacity`.
Draw order = array order (last = front). When `layers` is present, the
shape-level `type/color/filled/strokeWidth/width/height/points` are ignored;
`x/y/rotation/scale/opacity/keyframes` remain the GROUP pose (the whole face
moves as one).

IMPORTANT for paths: `points` are re-centered on the layer origin, so place a
path with the layer's `x`/`y` (the smile above sits at y = 43, the bbox center
of its points).

## Cycle — repeat the keyframe pattern

`"cycle": {"repeat": N}` on a shape (or on `skeleton`, for ALL bones) repeats
the keyframe pattern N MORE times after the last keyframe. Period = last
keyframe time − first keyframe time. At each seam, the repeated first keyframe
is skipped when it lands on a time already present — end the pattern with the
pose it started with for a clean loop.

Example: keys at 0 / 0.5 / 1.0 with `repeat: 3` → keys at 0, 0.5, 1.0, 1.5,
2.0, 2.5, 3.0, 3.5, 4.0. A keyframe beyond `end` extends the window as usual.
`repeat` must be an integer ≥ 1; without keyframes, `cycle` is ignored.

## Defs — reusable primitive definitions

```json
{
  "defs": {"oeil": {"type": "circle", "color": "$encre", "width": 26, "height": 26}},
  "shapes": [
    {"name": "Œil gauche", "ref": "oeil", "x": 326, "y": 618, "end": 2},
    {"name": "Œil droit", "ref": "oeil", "x": 394, "y": 618, "end": 2, "color": "#FF5C5C"}
  ]
}
```

A def holds geometry only: `type`, `color`, `filled`, `strokeWidth`,
`width` / `height`, `points` (anything else is ignored). A shape with
`"ref": "oeil"` inherits those as defaults and may override any of them (the
example turns the right eye red). Name / start / end / pose / keyframes always
come from the shape itself. No nested refs; `ref` works at shape level only
(not inside `layers[]`).

## Axis scale — `scaleX` / `scaleY`

VASF-2 adds two axis factors usable at BASE level (on the shape) and per
KEYFRAME (same names — the keyframe carries the factor):

```json
{
  "name": "Balle", "scaleX": 1.4, "scaleY": 0.6, "end": 1.5,
  "keyframes": [
    {"t": 0, "scaleX": 1.2, "scaleY": 0.8},
    {"t": 0.5, "scaleX": 0.9, "scaleY": 1.15, "easing": "easeOut"}
  ]
}
```

- The effective scale along an axis = `scale` × `scaleX` (same on Y). The
  shape-level factor is the base, keyframes carry FACTORS — a keyframe
  `scaleX: 1` shows the shape × `scale` wide, it does NOT restore the base
  factor; end the bounce pattern back at the shape-level value for a clean
  loop.
- Independent factors = squash & stretch without a rotation trick: impact
  squash is `scaleX > 1` with `scaleY < 1`.
- Keep factors within 0.05–4 (the pinch gesture clamps there).

## Pivot — rotation & scale around a point

`"pivot": [dx, dy]` = offset from the shape CENTER, in shape units, where
rotation and scale turn (a door hinges on its edge, not its middle). The
pivot is anchored at its VISUAL position `center + S·pivot` — under a
non-uniform scale it stays glued to the visual edge of the shape. STATIC:
`pivot` cannot be keyframed. Default `[0, 0]` = center (classic behavior).

```json
{"name": "Porte", "type": "rect", "width": 240, "height": 420,
 "pivot": [-120, 0], "keyframes": [{"t": 0, "rotation": 0}, {"t": 1.2, "rotation": 70}]}
```

Shape-level only: put `pivot` on the SHAPE, never inside a `layers[]` entry —
a `pivot` found in a layer is REJECTED at import (it would otherwise be
silently ignored and the shape would rotate around its center as before).

## Custom easing — `cubic-bezier(...)`

`easing` accepts the CSS chain form on shape AND bone keyframes:

```json
{"t": 0.5, "x": 500, "easing": "cubic-bezier(0.34, 1.56, 0.64, 1.0)"}
```

- 4 numbers `x1, y1, x2, y2` — control points of the timing curve; `x1` and
  `x2` MUST be within `[0, 1]` (monotone progress). `y1`/`y2` may overshoot
  past 0–1 for an elastic/bounce feel.
- Named easings remain available. Exact identity (linear) =
  `cubic-bezier(0.333, 0.333, 0.667, 0.667)` — NOT `(0, 0, 1, 1)` (that one
  is a smoothstep).
- Keyframe-bound: the curve applies to the segment ARRIVING at that keyframe,
  exactly like named easings.

## Layer bindings — `bind` a single layer

VASF-2 extends `skeleton.bind` keys: `"Forme/Couche"` binds ONE named layer
of a shape to a bone; a plain key keeps binding the whole shape.

```json
"bind": {"Corps": "Torse", "Visage/Chapeau": "Tête"}
```

- The layer must exist on the shape (unknown layer = collected error);
  a bound layer follows ITS bone and takes precedence over the whole-shape
  binding.
- On export, a shape with a layer binding is emitted with `layers[]` even at
  a single layer (so the layer name survives the round-trip).

# Limitations

- VASF-2 layer pose is static: a layer's x/y/rotation/scale/opacity cannot be
  keyframed — only the group pose animates (layer-level animation is planned).
- No nested project instances.
- `pivot` is static (not keyframable); `scaleX`/`scaleY` ARE animatable.
- Layer bindings ARE supported (`"Forme/Couche"` keys, vasf-2).
- The export writes `version: 2` when a shape has several layers OR uses an
  axis factor ≠ 1, a pivot ≠ 0, a `cubic-bezier` easing, or a layer binding;
  single-layer shapes without those export flat (v1), and the palette/defs
  are never exported (colors are expanded).
