# VASF-1 — Vector Anim Studio simple JSON format

VASF-1 is a compact, LLM-friendly JSON format for describing a complete 2D vector
animation (shapes, keyframes, optional skeleton rig) that the **Vector Anim Studio**
Android app can import directly.

Rules of thumb for generating a valid file:

- **Seconds** (double) for every time value. **Degrees** for every angle.
- Colors are strings `#RRGGBB` (or `#AARRGGBB`).
- A shape is **one primitive**. Characters made of several parts = several shapes,
  each bound to its own bone.
- Draw order = order of the `shapes` array (first = background).
- Keyframes may be **partial**: a missing property is carried over from the
  previous keyframe (or from the base pose for the first keyframe).
- The importer collects ALL problems and reports them in French — fix them and retry.
- Nested project instances are not representable in VASF-1 (ignored on export).

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
| version | int | required | must be `1` |
| name | string | "Animation importée" | project name |
| canvas.width / height | number | 720 / 1280 | 16…4096 |
| canvas.fps | int | 25 | 5…60 (export fps) |
| canvas.background | string | `#14161C` | scene background |
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
| opacity | 1 | 0–1 |
| keyframes | optional | see below |

### Keyframe (shape)

```json
{"t": 0.0, "x": 180, "y": 320, "rotation": 0, "scale": 1, "opacity": 1, "strokeWidth": 1, "easing": "easeInOut"}
```

- `t` (seconds, ≥ 0, sorted automatically) — a keyframe beyond `end` extends it.
- `easing` = curve of the segment ARRIVING at this keyframe: `linear, easeIn,
  easeOut, easeInOut, step` (default `easeInOut`).
- Any of `x, y, rotation, scale, opacity, strokeWidth` may be omitted (carried
  over). `rotation` is in degrees. `strokeWidth` here animates the stroke
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

See `docs/vasf-1-examples.json` for a skeleton example (character waving an arm).

# Limitations (v1)

- One primitive per shape (no multi-layer shapes).
- No nested project instances.
- Layer bindings (single layer bound to a bone) are ignored on export.
- Layers stay locally neutral: a shape's pose is its entire geometry.
