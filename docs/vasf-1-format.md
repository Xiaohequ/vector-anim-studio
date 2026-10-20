# VASF — Keyform Studio simple JSON format (v1 + extensions v2, v3, v4, v5, v6)

VASF is a compact, LLM-friendly JSON format for describing a complete 2D vector
animation (shapes, keyframes, optional skeleton rig) that the **Keyform Studio**
(Android / iOS) app can import directly. `VASF` keeps its original spelling
(*Vector Anim Studio Format*): it is the format identifier stored in the file,
not the app name.

Rules of thumb for generating a valid file:

- **Seconds** (double) for every time value. **Degrees** for every angle.
- Colors are strings `#RRGGBB` (or `#AARRGGBB`), or `"$alias"` resolved in the
  `theme` palette (VASF-2).
- A shape is **one primitive** by default; `"layers": [...]` (VASF-2) packs
  several primitives into one shape. Characters made of several parts = several
  shapes, each bound to its own bone.
- Draw order = order of the `shapes` array (first = background).
- Keyframes may be **partial**: a missing property is carried over from the
  previous keyframe (or from the base pose for the first keyframe). The same
  carry rule applies to the VASF-3 `color`/`colors` and `points`/`layerPoints`
  keyframe fields.
- The importer collects ALL problems and reports them in French — fix them and retry.
- Nested project instances are not representable in VASF-1 (ignored on export).
- The VASF-2 through VASF-6 extensions (below) are optional: a `version: 1`
  file stays valid. The importer accepts versions 1 to 6.

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
| version | int | required | `1`–`5`; choose the highest extension version used |
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
| cornerRadius | absent = historical auto | VASF-5: explicit common radius for rectangle corners; `0` makes square corners |
| roundTopLeft / roundTopRight / roundBottomRight / roundBottomLeft | true | VASF-5: independently enable/disable each rectangle corner |
| ref | optional | VASF-2: name of a `defs` entry used as geometry defaults (see below) |
| bone | optional | v0.17: binding shortcut — whole-shape binding to the named bone (same as one `skeleton.bind` entry; conflict with `bind` = error; requires a `skeleton` section) |
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
| bone.ik | false | enable IK on this bone = ROOT of an IK chain (dragging the chain end solves every bone of the chain; 2 bones = exact solver, more = CCD). A chain runs through unique-child bones only |
| bone.bend | 1 | elbow side for 2-bone IK: +1 or −1 (CCD chains may still flip) |
| bind | optional | map **shape name → bone name** |
| cycle | optional | VASF-2: `{"repeat": N}` repeats ALL bone keyframes (period = last − first time). v0.17: a bone-EMBEDDED `cycle` repeats THAT bone's own pattern and excludes it from the global cycle |
| keyframes | optional | bone animation (see below). v0.17: may instead be EMBEDDED in each bone object (`keyframes` and `cycle` directly on the bone — `bone` field implied) |

### Keyframe (bone)

```json
{"bone": "Bras", "t": 0.5, "angle": -30, "easing": "easeInOut", "opacity": 0.5, "stretch": 1.2, "squash": 1, "move": [10, -5]}
```

- `bone` = bone name (required), `t` seconds ≥ 0 (required).
- `angle` = **absolute WORLD angle in degrees** at that time (NOT a delta). The
  importer writes the internal delta = `angle − world rest angle` of the chain.
  Example: a child whose world rest angle is 90° given `angle: 30` rotates −60°.
- `opacity` (0–1), `stretch` (along the bone, 1 = neutral), `squash`
  (perpendicular, 1 = neutral) are optional per-keyframe bone properties.
- VASF-3: `move` = optional `[dx, dy]` **world translation** (project coords)
  of the bone's joint, relative to its rest position at that time. The joint
  slides, children and bound pieces follow rigidly; the rest pose is untouched.
  Internally stored in the parent's rest frame — the export round-trips it to
  world. A keyframe may combine `angle` and `move`.
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
`x` / `y` (offset from the shape center), `rotation`, `scale`, `opacity`,
and (VASF-4) the content mirror flags `flipH` / `flipV`, and (VASF-5) the
rectangle corner fields `cornerRadius` and `roundTopLeft` / `roundTopRight` /
`roundBottomRight` / `roundBottomLeft` (see the relevant sections).
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

# VASF-3 extensions (optional — `version: 3`, engine features)

Heavy engine features, delivered in v0.15. All fields are optional; a file
that uses none of them exports as v1/v2. Mixing v2 and v3 fields in one file
is fine. The importer accepts versions 1 to 5; the exporter uses the highest
extension version present, so later v4/v5 features take precedence.

## Animated color — `color` / `colors` in a shape keyframe

A shape keyframe may carry a color for each layer; the app interpolates it
between color keyframes (hold outside the posed range, same easing as the
numeric properties):

- **Single-layer shape** (flat file): keyframes carry a scalar `color`:

  ```json
  {"t": 0, "color": "#5B8DEF"}, {"t": 2, "easing": "linear", "color": "#FF5C5C"}
  ```

- **layers[] shape**: keyframes carry a map keyed by LAYER NAME:

  ```json
  {"t": 0, "colors": {"Langue": "#FF5C5C"}}, {"t": 2, "colors": {"Langue": "#F2C94C"}}
  ```

- A missing `color`/`colors` in a later keyframe keeps the last posed color
  (carry), exactly like the numeric properties; the first keyframe of the
  shape defines the starting color (put the base color at `t: 0`).
- `color` is rejected on a layers[] shape, and `colors` on a flat shape —
  explicit error, use the right one.
- Colors accept `"$alias"` palette references like everywhere else.
- In-app: the shape's ⚙ sheet shows one color row per layer (palette swatches
  + a diamond that poses/removes the color of the pose at the playhead).

## Point morph — `points` / `layerPoints` in a shape keyframe

A `path` layer's points can be keyframed (faces, expressions, flames): each
keyframe may redefine the full point list, and the app interpolates the path
point by point. If the two clouds have different counts, the shorter one is
padded by repeating its last point (new segments grow out of it).

- **Single-layer shape** (flat file): keyframes carry `points` (same
  convention as the shape's own `points`: any canvas coords, the importer
  converts them).
- **layers[] shape**: keyframes carry `"layerPoints": {"Langue": [[x, y], ...]}`
  keyed by LAYER NAME.
- **Coordinate frame (important)**: the morph keyframes share the frame of
  the BASE `points` list — i.e. the same canvas coords the shape was drawn
  with (the importer uses the base cloud's bbox center, not each keyframe's).
  A keyframe that translates every point by +[200, 0] visibly slides the
  whole path by 200 units.
- As for colors, the FIRST keyframe must define the starting cloud (put the
  base `points` copy at `t: 0`), and a missing `points` in a later keyframe
  carries the last posed cloud — before the first posed cloud the app shows
  the BASE points.
- In-app: since v0.16 the shape editor edits morph clouds directly (point
  handles, editor time cursor, auto-key morph, add/remove points) — agents
  still author the whole morph in the JSON.

## Bone translation — `move` in a bone keyframe

```json
{"bone": "Poignet", "t": 1, "angle": -90, "move": [0, -20]}
```

- `move` = `[dx, dy]` in WORLD (project) coordinates: the joint's offset from
  its rest position at that time. Children and bound pieces follow rigidly;
  the rest pose stays untouched (a bone with keyframes animates — a bone
  without keyframes keeps its rest-offset behavior when dragged).
- Combines freely with `angle` on the same keyframe; interpolated with the
  keyframe's easing, held outside the posed range like every other property.
- In-app: drag the ✥ handle of an ANIMATED bone → writes the translation at
  the playhead (auto-key). On an unanimated bone the ✥ drag keeps the
  historical rest-move behavior.

# v0.17 app — strict import, `bone` shortcut, embedded & per-bone cycles

Accepted by the v0.17 importer and the Python validator. The exporter never
emits them (cycles are developed into plain keyframes on export).

## Mirror — `flipH` / `flipV` (VASF-4)

A layer may carry `"flipH": true` and/or `"flipV": true`: the painter reflects
the layer CONTENT (primitive or path, base points like morph clouds) around
the layer origin. On a single-layer shape the flags may be set at shape level
(flat format — same meaning). The mirror action in the app (buttons Miroir H /
Miroir V of the shape sheet) also negates each layer's `x` (H) or `y` (V) and
rotation, mirroring the whole group around the shape center while it stays in
place; keyframes are untouched. The app exports `flipH`/`flipV` only when true
and bumps the file to `version: 4`.

```json
{
  "version": 4,
  "name": "Flipped arrow",
  "shapes": [
    {"name": "Flèche", "type": "arrow", "flipH": true, "x": 360, "y": 640, "end": 2}
  ]
}
```

## Unknown fields are REJECTED

The importer refuses any unknown field at every level (document root,
`canvas`, shapes, bones) with a French error naming the field and its path.
Previously unknown fields were silently ignored — which could drop a binding
or freeze an animation without any warning. Check spellings against the field
tables of this document.

## Shape `bone` — binding shortcut

A shape may carry `"bone": "OsName"` as a whole-shape binding shortcut
(equivalent to one `skeleton.bind` entry). The bone must exist; a conflict
with a `skeleton.bind` entry for the same shape (different bone) is an error;
`bone` without a `skeleton` section is an error. Per-layer bindings keep
using the `"Forme/Couche"` keys of `skeleton.bind`.

## Keyframes & cycle embedded in a bone

A bone object may carry its own `"keyframes": [...]` and `"cycle":
{"repeat": N}`. Semantics are identical to `skeleton.keyframes` (world
absolute angles, partial poses, `move`, easing) — the `bone` field is
implied and must be omitted. This lets each bone repeat ITS OWN pattern,
e.g. walk bones: a 5-key pattern over 1.2 s with `{"repeat": 9}` → a full
12 s walk (41 keyframes after expansion), while a root bone carries its own
12 s linear rotation with NO cycle.

## Per-bone cycle — different periods on different bones

`skeleton.cycle.repeat` (vasf-2) repeats ONE pattern for ALL bones. A bone
with its own embedded `cycle` repeats its own pattern (period = last − first
time of its keyframes) and is EXCLUDED from the global `skeleton.cycle`,
which still applies to every bone without its own cycle (period computed
over those bones only). A bone cycle with fewer than 2 keyframes (or a zero
period) is ignored; `repeat` must be an integer ≥ 1. End the pattern with
the pose it started with for a clean loop.

# VASF-5 extensions — rectangle corners

VASF-5 adds a shared corner radius and independent corner switches for
rectangles, on a flat shape or on a primitive inside `layers[]`:

```json
{
  "version": 5,
  "name": "Rounded cards",
  "shapes": [
    {"name": "Card", "type": "rect", "width": 300, "height": 180,
     "cornerRadius": 28, "roundTopLeft": false, "roundBottomRight": false},
    {"name": "Square", "type": "rect", "width": 160, "height": 100,
     "cornerRadius": 0}
  ]
}
```

- `cornerRadius` must be a number ≥ 0. It is clamped at render time to half the
  smaller rectangle dimension. Explicit `0` produces square corners.
- If `cornerRadius` is absent, the historical automatic radius remains in use:
  `min(24, 0.15 × min(width, height))`. This preserves existing projects.
- The four `round…` fields are booleans, each defaulting to `true`; `false`
  squares only that corner. They are ignored by non-rectangle primitives.
- The exporter writes `version: 5` when any rectangle has an explicit radius or
  a non-default corner selection. `zIndex` is app-internal and does not alter
  the existing VASF array draw order.

# VASF-6 extensions — element groups

VASF-6 adds named element groups. A group organises shapes in the timeline
(name, track colour, collapse state, visibility) and carries a static
transform. Shapes reference their group **by name**:

```json
{
  "version": 6,
  "name": "Grouped face",
  "groups": [
    {"name": "Tête", "color": "#FF8800", "visible": true,
     "collapsed": false, "x": 0, "y": 0, "rotation": 0,
     "scaleX": 1, "scaleY": 1}
  ],
  "shapes": [
    {"name": "Oeil gauche", "type": "circle", "width": 40, "height": 40,
     "x": 150, "y": 300, "end": 2, "groupId": "Tête"},
    {"name": "Oeil droit", "type": "circle", "width": 40, "height": 40,
     "x": 210, "y": 300, "end": 2, "groupId": "Tête"}
  ]
}
```

| group field | type | default | notes |
|---|---|---|---|
| name | string | required | unique; shapes reference it through `groupId` |
| color | string | `#2DD4BF` | timeline track colour (alias `"$nom"` allowed) |
| visible | bool | true | `false` hides every shape of the group |
| collapsed | bool | false | timeline fold state (editor only) |
| x / y | number | 0 | static group offset |
| rotation | number | 0 | static group rotation, degrees |
| scaleX / scaleY | number | 1 | static group axis factors |

- `groupId` on a shape is the group **NAME**, not an id: the importer resolves
  it after creating the groups, so the JSON key order does not matter. An
  unknown name is a collected error.
- A group holds no keyframes and no bones: its time span is DERIVED from its
  children (earliest start, latest end). Group visibility multiplies the
  shape's own visibility.
- The static group transform (`x`/`y`/`rotation`/`scaleX`/`scaleY`) IS applied
  by the renderer: it wraps the pose of every shape of the group and turns
  around the group's VISUAL CENTRE — the mean of its children's rest positions
  (`x`/`y` base values), not the canvas origin. A neutral group (all defaults)
  renders exactly like ungrouped shapes.
- Groups are flat: no nested groups, and a shape belongs to at most one group.
- The exporter writes `version: 6` as soon as a shape carries a `groupId`, and
  only exports groups that actually hold at least one shape (an empty group is
  dropped). Default-valued group fields are omitted.

# Limitations

- VASF-2 layer pose is static: a layer's x/y/rotation/scale/opacity cannot be
  keyframed — the group pose animates, and (v3) so do layer COLORS and layer
  POINT morphs (layer-level x/y animation is still planned).
- No nested project instances.
- `pivot` is static (not keyframable); `scaleX`/`scaleY` ARE animatable.
- Layer bindings ARE supported (`"Forme/Couche"` keys, vasf-2).
- VASF-3 morphs a full point LIST only: no per-point keys, no bezier handles
  in the morph (straight polyline interpolation between clouds); morphs are
  authored in imports or edited in-app since v0.16 (point editor).
- VASF-3 bone `move` ignores the parent's stretch/squash when converting the
  world delta (tiny drift on stretched parents — the drag-✥ path converts
  against the parent's CURRENT world angle, not its stretch).
- VASF-3 chains of ≥ 3 bones solve with CCD: the end effector lands on the
  target but the elbow side is not guaranteed (`bend` only controls the
  2-bone analytic solver).
- The export writes `version: 6` when a shape belongs to a group, otherwise
  `version: 5` when VASF-5 rectangle-corner settings are used, otherwise
  `version: 4` for content mirroring, `version: 3` for shape keyframe
  colors/morph or bone `move`, and `version: 2` for the other v2 extensions
  (several layers, axis factor ≠ 1, pivot ≠ 0, `cubic-bezier`, layer
  binding). Single-layer shapes without extensions export flat (v1);
  palette/defs are never exported (colors are expanded).
