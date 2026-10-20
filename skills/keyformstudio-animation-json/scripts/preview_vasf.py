#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Aperçu headless d'un JSON vasf (v1/2/3) — rendu fidèle à l'appli, sans Docker.

Usage :
    python3 preview_vasf.py fichier.json [t1 t2 ...] [--out DIR] [--scale 0.28]
                            [--pick CLE] [--bones]

Sans instants : 5 échantillons équirépartis sur la durée du contenu. Écrit
planche.png (côte à côte, cellules réduites --scale) + frame_t*.png (pleine
résolution, pour les mesures pixel) dans le dossier de sortie
(défaut : tmp/vasf_preview/<nom-du-fichier>/).

Collections (recueil d'exemples) : `--pick cle` choisit l'objet ; un recueil
à UN SEUL candidat est pris automatiquement.

Fidélité : mêmes formules que scene_painter.dart / skeleton.dart — géométrie
des primitives (rect arrondi, ellipse, ligne, path polyline fermé, triangle,
star 5 branches 0.45, hexagone, croix, cœur, flèche), chaînes de pose
(pivot ancré visuellement, scaleX/scaleY), poses partielles portées,
easing nommé + cubic-bezier, couleur animée et morph de points (vasf-3),
cycles (forme / squelette global / par os — v0.17), FK exacte (angles MONDE,
move, stretch/squash, opacité d'os, z), liaisons forme et couche.

LIMITES : validation PERMISSIVE — le validateur reste la porte stricte ;
fenêtres start/end ACTIVES (une forme n'est rendue que sur [start, end]) ;
alpha #AARRGGBB REMPLACÉ par l'opacité calculée (comme l'app) ; chaque
keyframe d'os porte sa propre pose (pas de carry) ; IK non simulée
(champ ignoré — l'IK ne s'applique qu'au glisser in-app). Vérification EXACTE
au pixel : harnais officiel `VASF_PREVIEW_INPUT=... vector_anim_studio/
scripts/flutter_docker.sh test test/vasf_preview_test.dart`.
"""
import argparse
import json
import math
import os
import re
import sys

import cairo

PRIMS = ("rect", "circle", "line", "path", "triangle", "star", "hexagon",
         "cross", "heart", "arrow")
DEF_KEYS = ("type", "color", "filled", "strokeWidth", "width", "height",
            "points", "flipH", "flipV", "cornerRadius", "roundTopLeft",
            "roundTopRight", "roundBottomRight", "roundBottomLeft")
DEFAULT_COLOR = "#5B8DEF"
DEFAULT_BG = "#14161C"
DEFAULT_SIZE = 110.0
DEFAULT_SW = 4.0
# Propriétés de pose de forme (thickness = facteur d'épaisseur de trait)
SHAPE_PROPS = ("x", "y", "rotation", "scale", "scaleX", "scaleY", "opacity",
               "thickness")


# ---------------------------------------------------------------- couleurs

def resolve_color(value, palette, fallback=DEFAULT_COLOR):
    """'#RRGGBB' / '#AARRGGBB' / alias '$nom' → (r, g, b, a) floats 0-1."""
    if value is None:
        value = fallback
    if isinstance(value, str):
        v = value.strip()
        if v.startswith("$"):
            return resolve_color(palette.get(v[1:]), {}, fallback)
        value = v
    if not isinstance(value, str):
        return None
    hexs = value.lstrip("#")
    try:
        if len(hexs) == 8:
            a = int(hexs[:2], 16) / 255.0
            r, g, b = (int(hexs[2:4], 16), int(hexs[4:6], 16),
                       int(hexs[6:8], 16))
        elif len(hexs) == 6:
            a = 1.0
            r, g, b = int(hexs[:2], 16), int(hexs[2:4], 16), int(hexs[4:6], 16)
        else:
            return None
    except ValueError:
        return None
    return (r / 255.0, g / 255.0, b / 255.0, a)


def lerp_color(c1, c2, f):
    """Mélange canal par canal — arrondi EXACT de l'appli (`lerpArgb` :
    `(a + (b - a) * u).round()` demi-supérieur sur des canaux 0..255 ;
    sans cet arrondi, les couleurs interpolées décalent de 1/255 en
    plein segment et le fond entier diffère)."""
    out = []
    for i in range(4):
        a, b = c1[i] * 255.0, c2[i] * 255.0
        out.append(math.floor(a + (b - a) * f + 0.5) / 255.0)
    return tuple(out)


# ----------------------------------------------------------------- easings

def _parse_bezier(s):
    parts = [p.strip() for p in s[len("cubic-bezier("):-1].split(",")]
    if len(parts) != 4:
        return None
    try:
        vals = [float(p) for p in parts]
    except ValueError:
        return None
    if not (0 <= vals[0] <= 1 and 0 <= vals[2] <= 1):
        return None
    return vals


def bezier_progress(b, x):
    """Progression y d'une cubic-bezier CSS (x1, y1, x2, y2) à l'abscisse x."""
    x1, y1, x2, y2 = b
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    px = lambda t: 3 * t * (1 - t) ** 2 * x1 + 3 * t * t * (1 - t) * x2 + t ** 3
    py = lambda t: 3 * t * (1 - t) ** 2 * y1 + 3 * t * t * (1 - t) * y2 + t ** 3
    lo, hi, t = 0.0, 1.0, x
    for _ in range(60):
        v = px(t) - x
        if abs(v) < 1e-9:
            break
        if v > 0:
            hi = t
        else:
            lo = t
        t = (lo + hi) / 2
    return py(t)


def ease(kind, u):
    if isinstance(kind, (list, tuple)):
        return bezier_progress(kind, u)
    if kind == "linear":
        return u
    if kind == "step":
        return 0.0 if u < 1 else 1.0
    if kind == "easeIn":
        return u * u * u
    if kind == "easeOut":
        return 1 - (1 - u) ** 3
    return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2  # easeInOut


def easing_of(raw):
    """'easeInOut' | 'cubic-bezier(...)' → (kind, erreur éventuelle)."""
    if raw is None:
        return None, None
    if not isinstance(raw, str):
        return None, "easing doit être une chaîne (défaut easeInOut)"
    s = raw.strip()
    if s.startswith("cubic-bezier(") and s.endswith(")"):
        b = _parse_bezier(s)
        if b is None:
            return None, "cubic-bezier invalide (défaut easeInOut)"
        return b, None
    if s in ("linear", "easeIn", "easeOut", "easeInOut", "step"):
        return s, None
    return None, "easing « %s » inconnu (défaut easeInOut)" % s


# ------------------------------------------------------------ utilitaires

def num_or(v, fallback, errors, path):
    if v is None:
        return float(fallback)
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return float(v)
    errors.append(path + " : nombre attendu")
    return float(fallback)


def bbox_center(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return ((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0)


def rot2(x, y, rad):
    """Rotation écran : degrés positifs = horaire (y vers le bas)."""
    c, s = math.cos(rad), math.sin(rad)
    return (x * c - y * s, x * s + y * c)


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def fmt_fr(x):
    return ("%.2f" % x).replace(".", ",")


def parse_cloud(raw, errors, path):
    """Liste json de points → [(x, y)…] (≥ 2) ou None."""
    if not isinstance(raw, list) or len(raw) < 2:
        errors.append(path + " : au moins 2 points [x, y] attendus")
        return None
    pts = []
    for i, p in enumerate(raw):
        if (isinstance(p, (list, tuple)) and len(p) >= 2 and
                all(isinstance(v, (int, float)) and not isinstance(v, bool)
                    for v in p[:2])):
            pts.append((float(p[0]), float(p[1])))
        else:
            errors.append("%s[%d] : [x, y] attendu" % (path, i))
    return pts if len(pts) >= 2 else None


def lerp_clouds(a, b, f):
    """Interpolation point par point, nuage court bourré (dernier point)."""
    n = max(len(a), len(b))
    out = []
    for i in range(n):
        p1 = a[i] if i < len(a) else a[-1]
        p2 = b[i] if i < len(b) else b[-1]
        out.append((p1[0] + (p2[0] - p1[0]) * f, p1[1] + (p2[1] - p1[1]) * f))
    return out


# --------------------------------------------- keyframes (formes et os)

def parse_keyframes(raw, errors, path):
    """Keys brutes → triées, _easing parsé (temps en secondes)."""
    keys = []
    if raw is None:
        return keys
    if not isinstance(raw, list):
        errors.append(path + " : doit être un tableau de keyframes")
        return keys
    for j, kf in enumerate(raw):
        kpath = "%s[%d]" % (path, j)
        if not isinstance(kf, dict):
            errors.append(kpath + " : doit être un objet")
            continue
        t = kf.get("t")
        if not isinstance(t, (int, float)) or isinstance(t, bool) or t < 0:
            errors.append(kpath + ".t : temps en secondes ≥ 0 requis")
            continue
        k = dict(kf)
        k["t"] = float(t)
        e, msg = easing_of(kf.get("easing"))
        if msg:
            errors.append(kpath + ".easing : " + msg)
        k["_easing"] = e
        keys.append(k)
    keys.sort(key=lambda k: k["t"])
    return keys


def expand_cycle(keys, repeat, errors, path):
    """cycle.repeat : répète le motif N fois de plus (raccord sauté)."""
    if repeat is None or len(keys) < 2:
        return keys
    if not isinstance(repeat, int) or isinstance(repeat, bool) or repeat < 1:
        errors.append(path + ".repeat : entier ≥ 1 attendu")
        return keys
    period = keys[-1]["t"] - keys[0]["t"]
    if period <= 0:
        return keys
    out = list(keys)
    count = len(keys)
    for r in range(1, repeat + 1):
        for i in range(1, count):
            k = dict(keys[i])
            k["t"] = round(keys[i]["t"] + r * period, 6)
            out.append(k)
    out.sort(key=lambda k: k["t"])
    return out


# ---------------------------------------------------------- parsing : formes

def parse_layer(lj, lpath, errors, is_local):
    """Couche = primitive. Mode layers[] : pose locale en plus."""
    kind = lj.get("type")
    if kind not in PRIMS:
        if kind is not None:
            errors.append("%s.type : type inconnu « %s » (valeurs : %s)" %
                          (lpath, kind, ", ".join(PRIMS)))
        kind = "rect"
    layer = {
        "name": (lj.get("name") if is_local and isinstance(lj.get("name"), str)
                 and lj["name"].strip() else "Couche"),
        "kind": kind,
        "color": lj.get("color", DEFAULT_COLOR),
        "filled": lj["filled"] if isinstance(lj.get("filled"), bool) else True,
        "sw": num_or(lj.get("strokeWidth"), DEFAULT_SW, errors,
                     lpath + ".strokeWidth"),
        "x": num_or(lj.get("x"), 0, errors, lpath + ".x") if is_local else 0.0,
        "y": num_or(lj.get("y"), 0, errors, lpath + ".y") if is_local else 0.0,
        "rot": (num_or(lj.get("rotation"), 0, errors, lpath + ".rotation")
                if is_local else 0.0),
        "scale": (num_or(lj.get("scale"), 1, errors, lpath + ".scale")
                  if is_local else 1.0),
        "opacity": (num_or(lj.get("opacity"), 1, errors, lpath + ".opacity")
                    if is_local else 1.0),
        "flipH": lj["flipH"] if isinstance(lj.get("flipH"), bool) else False,
        "flipV": lj["flipV"] if isinstance(lj.get("flipV"), bool) else False,
        "cornerRadius": num_or(lj.get("cornerRadius"), -1, errors,
                                lpath + ".cornerRadius"),
        "roundTopLeft": lj.get("roundTopLeft", True),
        "roundTopRight": lj.get("roundTopRight", True),
        "roundBottomRight": lj.get("roundBottomRight", True),
        "roundBottomLeft": lj.get("roundBottomLeft", True),
    }
    if kind == "path":
        cloud = parse_cloud(lj.get("points"), errors, lpath + ".points")
        if cloud is None:
            layer["cloud"] = []
            layer["w"] = DEFAULT_SIZE
            layer["h"] = DEFAULT_SIZE
        else:
            cx, cy = bbox_center(cloud)
            layer["bcx"], layer["bcy"] = cx, cy
            layer["cloud"] = [(x - cx, y - cy) for x, y in cloud]
            layer["w"] = max(1.0, max(p[0] for p in cloud) - min(p[0] for p in cloud))
            layer["h"] = max(1.0, max(p[1] for p in cloud) - min(p[1] for p in cloud))
    else:
        layer["cloud"] = []
        layer["w"] = max(1.0, num_or(lj.get("width"), DEFAULT_SIZE, errors,
                                     lpath + ".width"))
        layer["h"] = max(1.0, num_or(lj.get("height"), DEFAULT_SIZE, errors,
                                     lpath + ".height"))
    return layer


def parse_groups(raw, errors, warnings):
    """Groupes d'éléments (v6) : nom → {name, color, visible, collapsed,
    x, y, rotation, scaleX, scaleY}. Le groupe ne porte ni keyframes ni os ;
    sa visibilité s'applique à ses formes (le rendu l'applique)."""
    groups = {}
    if raw is None:
        return groups
    if not isinstance(raw, list):
        errors.append("groups : doit être un tableau de groupes")
        return groups
    for i, g in enumerate(raw):
        path = "groups[%d]" % i
        if not isinstance(g, dict):
            errors.append(path + " : doit être un objet")
            continue
        name = g.get("name")
        if not isinstance(name, str) or not name.strip():
            errors.append(path + ".name : nom de groupe non vide requis")
            continue
        if name in groups:
            errors.append(path + ".name : groupe « %s » déjà défini "
                          "(noms uniques)" % name)
            continue
        groups[name] = {
            "name": name,
            "color": g.get("color"),
            "visible": g.get("visible", True) is not False,
            "collapsed": g.get("collapsed", False) is True,
            "x": num_or(g.get("x"), 0, errors, path + ".x"),
            "y": num_or(g.get("y"), 0, errors, path + ".y"),
            "rotation": num_or(g.get("rotation"), 0, errors,
                               path + ".rotation"),
            "scaleX": num_or(g.get("scaleX"), 1, errors, path + ".scaleX"),
            "scaleY": num_or(g.get("scaleY"), 1, errors, path + ".scaleY"),
        }
    return groups


def parse_shape(sj, index, palette, defs, errors, warnings,
                cx0=360.0, cy0=640.0):
    path = "shapes[%d]" % index
    effective = sj
    ref = sj.get("ref")
    if ref is not None:
        if isinstance(ref, str) and ref.strip():
            d = defs.get(ref.strip())
            if d is None:
                errors.append(path + ".ref : définition « %s » inconnue" % ref)
            else:
                base = {k: d[k] for k in DEF_KEYS if k in d}
                base.update(sj)
                effective = base
        else:
            errors.append(path + ".ref : nom de définition attendu")

    raw_layers = effective.get("layers")
    multi = raw_layers is not None
    layers = []
    if multi:
        if isinstance(raw_layers, list) and raw_layers:
            for j, lj in enumerate(raw_layers):
                lpath = "%s.layers[%d]" % (path, j)
                if isinstance(lj, dict):
                    layers.append(parse_layer(lj, lpath, errors, True))
                else:
                    errors.append(lpath + " : doit être un objet")
        else:
            errors.append(path + ".layers : au moins une couche requise")
    else:
        layers.append(parse_layer(effective, path, errors, False))

    shape = {
        "name": sj.get("name") if isinstance(sj.get("name"), str) else "Forme",
        "layers": layers,
        "zIndex": num_or(sj.get("zIndex"), 0, errors, path + ".zIndex"),
        "multi": multi,
        "x": num_or(sj.get("x"), cx0, errors, path + ".x"),
        "y": num_or(sj.get("y"), cy0, errors, path + ".y"),
        "rotation": num_or(sj.get("rotation"), 0, errors, path + ".rotation"),
        "scale": num_or(sj.get("scale"), 1, errors, path + ".scale"),
        "scaleX": num_or(sj.get("scaleX"), 1, errors, path + ".scaleX"),
        "scaleY": num_or(sj.get("scaleY"), 1, errors, path + ".scaleY"),
        "opacity": num_or(sj.get("opacity"), 1, errors, path + ".opacity"),
        "sw": num_or(sj.get("strokeWidth"), DEFAULT_SW, errors,
                     path + ".strokeWidth"),
        "groupId": (sj["groupId"].strip()
                    if isinstance(sj.get("groupId"), str)
                    and sj["groupId"].strip() else None),
        "start": num_or(sj.get("start"), 0, errors, path + ".start"),
        "end": num_or(sj.get("end"), 0, errors, path + ".end"),
        "end_explicit": "end" in sj,
        "pivot_x": 0.0,
        "pivot_y": 0.0,
        "bone_shortcut": (sj["bone"].strip()
                          if isinstance(sj.get("bone"), str) and sj["bone"].strip()
                          else None),
        "raw_keyframes": sj.get("keyframes"),
        "cycle_repeat": (sj["cycle"].get("repeat")
                         if isinstance(sj.get("cycle"), dict) else None),
        "keyframes": None,
    }
    if not multi and layers:
        layers[0]["sw"] = shape["sw"]  # la forme à plat porte son strokeWidth
    pivot = sj.get("pivot")
    if pivot is not None:
        if (isinstance(pivot, (list, tuple)) and len(pivot) >= 2 and
                all(isinstance(v, (int, float)) and not isinstance(v, bool)
                    for v in pivot[:2])):
            shape["pivot_x"], shape["pivot_y"] = float(pivot[0]), float(pivot[1])
        else:
            errors.append(path + ".pivot : paire [dx, dy] attendue")
    return shape


def normalize_shape_keys(shape, errors, warnings, palette):
    """Parse + cycle + poses complètes portées + couleurs/morph résolus."""
    name = shape["name"]
    keys = parse_keyframes(shape.pop("raw_keyframes"), errors,
                           "shapes[%s].keyframes" % name)
    keys = expand_cycle(keys, shape.pop("cycle_repeat"), errors,
                        "shapes[%s].cycle" % name)
    shape["keyframes"] = keys
    if not keys:
        return

    layer_names = [l["name"] for l in shape["layers"]]
    base = {"x": shape["x"], "y": shape["y"], "rotation": shape["rotation"],
            "scale": shape["scale"], "scaleX": shape["scaleX"],
            "scaleY": shape["scaleY"], "opacity": shape["opacity"],
            "thickness": 1.0}
    base_colors = {l["name"]: l["color"] for l in shape["layers"]}
    base_clouds = {}
    base_center = {}
    for l in shape["layers"]:
        if l["kind"] == "path" and l["cloud"]:
            base_clouds[l["name"]] = tuple(l["cloud"])
            base_center[l["name"]] = (l["bcx"], l["bcy"])

    carried = dict(base)
    color_carry = dict(base_colors)
    points_carry = dict(base_clouds)
    for k in keys:
        kpath = "shapes[%s].keyframes[t=%s]" % (name, fmt_fr(k["t"]))
        for prop in SHAPE_PROPS:
            field = "strokeWidth" if prop == "thickness" else prop
            if field in k:
                v = k[field]
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    carried[prop] = float(v)
                else:
                    errors.append("%s.%s : nombre attendu" % (kpath, field))
        k["pose"] = dict(carried)

        # Couleur animée (v3) : `color` à plat / `colors` {NomCouche: hex}
        posed_colors = {}
        if shape["multi"]:
            if isinstance(k.get("colors"), dict):
                for lname, cval in k["colors"].items():
                    if lname not in layer_names:
                        errors.append("%s.colors[« %s »] : couche inconnue"
                                      % (kpath, lname))
                    elif isinstance(cval, str):
                        posed_colors[lname] = cval
                    else:
                        errors.append("%s.colors[« %s »] : couleur attendue"
                                      % (kpath, lname))
            if "color" in k:
                errors.append("%s.color : refusé sur une forme layers[] — "
                              "utilisez « colors »" % kpath)
        else:
            if isinstance(k.get("color"), str):
                posed_colors[layer_names[0]] = k["color"]
            if "colors" in k:
                errors.append("%s.colors : refusé sur une forme à plat — "
                              "utilisez « color »" % kpath)
        color_carry.update(posed_colors)
        k["colors_resolved"] = dict(color_carry)

        # Morph de points (v3) : `points` à plat / `layerPoints` {nom: nuage}
        posed_points = {}
        if shape["multi"]:
            if isinstance(k.get("layerPoints"), dict):
                for lname, cloud in k["layerPoints"].items():
                    if lname not in base_clouds:
                        errors.append(
                            "%s.layerPoints[« %s »] : aucune couche path "
                            "« %s » (base points vide ou absente)"
                            % (kpath, lname, lname))
                    else:
                        c = parse_cloud(cloud, errors,
                                        "%s.layerPoints[« %s »]" % (kpath, lname))
                        if c is not None:
                            bx, by = base_center[lname]
                            posed_points[lname] = tuple((x - bx, y - by)
                                                        for x, y in c)
            if "points" in k:
                errors.append("%s.points : refusé sur une forme layers[] — "
                              "utilisez « layerPoints »" % kpath)
        else:
            if "points" in k:
                c = parse_cloud(k["points"], errors, kpath + ".points")
                if c is not None:
                    bx, by = base_center[layer_names[0]]
                    posed_points[layer_names[0]] = tuple((x - bx, y - by)
                                                         for x, y in c)
            if "layerPoints" in k:
                errors.append("%s.layerPoints : refusé sur une forme à plat — "
                              "utilisez « points »" % kpath)
        points_carry.update(posed_points)
        k["points_resolved"] = dict(points_carry)

    # Une keyframe au-delà de la fin du segment PROLONGE la fenêtre.
    if keys:
        shape["end"] = max(shape["end"], max(k["t"] for k in keys))


def apply_window_defaults(shapes, errors, warnings):
    """Fenêtre d'affichage ACTIVE : une forme n'est rendue que sur
    [start, end]. `end` absent (≤ 0) = la fin la plus tardive des AUTRES
    formes, sinon 4 s ; une keyframe au-delà de `end` PROLONGE `end`
    (fait dans normalize_shape_keys, une fois les keyframes parsées)."""
    for s in shapes:
        if s["start"] < 0:
            errors.append("shapes[%s].start : ≥ 0 attendu (%s s)" %
                          (s["name"], fmt_fr(s["start"])))
        if s["end"] < 0:
            errors.append("shapes[%s].end : ≥ 0 attendu (%s s)" %
                          (s["name"], fmt_fr(s["end"])))
        if s["end"] <= 0:
            others = [o["end"] for o in shapes
                      if o is not s and o["end"] > 0]
            s["end"] = max(others) if others else 4.0
        if s["end"] <= s["start"]:
            errors.append("shapes[%s].end : fin > début attendue (%s ≤ %s)" %
                          (s["name"], fmt_fr(s["end"]),
                           fmt_fr(s["start"])))


# ------------------------------------------------------ parsing : squelette

def materialize_bone_key(rig, bone, kj, kpath, errors):
    """Keyframe d'os → valeurs SPARSE : une propriété absente reste None et
    vaut le défaut neutre au rendu (1/1/1/0) — chaque keyframe d'os porte sa
    propre pose, sans carry entre poses."""
    rest_deg = bone["angle"]
    angle_deg = num_or(kj.get("angle"), rest_deg, errors, kpath + ".angle")

    def opt_num(v, path):
        if v is None:
            return None
        return num_or(v, 1.0, errors, path)

    opacity = opt_num(kj.get("opacity"), kpath + ".opacity")
    stretch = opt_num(kj.get("stretch"), kpath + ".stretch")
    squash = opt_num(kj.get("squash"), kpath + ".squash")
    tx, ty = None, None
    mv = kj.get("move")
    if mv is not None:
        if (isinstance(mv, (list, tuple)) and len(mv) >= 2 and
                all(isinstance(v, (int, float)) and not isinstance(v, bool)
                    for v in mv[:2])):
            # move MONDE → repère de repos du PARENT (comme l'importeur)
            base_ang = 0.0
            if bone["parent"]:
                base_ang = math.radians(rig["by_name"][bone["parent"]]["angle"])
            tx, ty = rot2(float(mv[0]), float(mv[1]), -base_ang)
        else:
            errors.append(kpath + ".move : paire [dx, dy] attendue")
    return {"t": float(kj["t"]), "_easing": kj.get("_easing"),
            "d": angle_deg - rest_deg, "op": opacity, "st": stretch,
            "sq": squash, "tx": tx, "ty": ty}


def merge_bone_keys(rig, errors):
    """Fusionne les doublons (os, t) — upsertKeyframe exact : une valeur
    ABSENTE (None) ne surcharge pas celle déjà posée (défaut neutre sinon) ;
    un move posé gagne (la paire arrive entière depuis l'import)."""
    for bone in rig["bones"]:
        merged = {}
        for k in bone["keys"]:
            prev = merged.get(k["t"])
            if prev is None:
                merged[k["t"]] = k
                continue
            for field in ("d", "op", "st", "sq"):
                if k[field] is not None:
                    prev[field] = k[field]
            if k["tx"] is not None or k["ty"] is not None:
                prev["tx"], prev["ty"] = k["tx"], k["ty"]
        keys = sorted(merged.values(), key=lambda k: k["t"])
        bone["keys"] = keys


def apply_bone_cycles(rig, errors):
    """Cycle PAR OS (embarqué) puis cycle GLOBAL (os sans cycle propre)."""
    own = set()
    for bone in rig["bones"]:
        if bone["own_repeat"] is None or len(bone["keys"]) < 2:
            continue
        bone["keys"] = expand_cycle(bone["keys"], bone["own_repeat"], errors,
                                    "skeleton.bones[%s].cycle" % bone["name"])
        own.add(bone["name"])
    subset = [b for b in rig["bones"]
              if b["name"] not in own and b["keys"]]
    if len(subset) < 1:
        return
    ts = [k["t"] for b in subset for k in b["keys"]]
    period = max(ts) - min(ts)
    if period <= 0:
        return
    g_repeat = rig["global_repeat"]
    for bone in subset:
        bone["keys"] = expand_cycle(bone["keys"], g_repeat, errors,
                                    "skeleton.cycle")


def parse_skeleton(sk, shapes, errors, warnings):
    """Rig : os parents-d'abord, keyframes niveau squelette + embarquées."""
    rig = {"name": sk.get("name") if isinstance(sk.get("name"), str)
           else "Squelette",
           "bones": [], "by_name": {}, "bindings": [], "duration": 0.0,
           "global_repeat": None}
    raw_bones = sk.get("bones")
    if not isinstance(raw_bones, list) or not raw_bones:
        errors.append("skeleton.bones : au moins 1 os requis")
        return rig
    names = []
    for i, bj in enumerate(raw_bones):
        path = "skeleton.bones[%d]" % i
        if not isinstance(bj, dict):
            errors.append(path + " : doit être un objet")
            continue
        name = bj.get("name") if isinstance(bj.get("name"), str) else "Os"
        if name in names:
            errors.append(path + ".name : os « %s » en double" % name)
            continue
        bone = {"name": name, "parent": None, "joint": (0.0, 0.0),
                "angle": 0.0, "length": 80.0, "z": 0, "keys": [],
                "own_repeat": None, "offset": (0.0, 0.0), "rest_rel": 0.0}
        pj = bj.get("parent")
        if pj is not None:
            if isinstance(pj, str) and pj.strip():
                if pj.strip() in names:
                    bone["parent"] = pj.strip()
                else:
                    errors.append(
                        "%s.parent : os « %s » inconnu — les parents doivent "
                        "être déclarés AVANT leurs enfants" % (path, pj))
            else:
                errors.append(path + ".parent : nom d'os attendu")
        j = bj.get("joint")
        if (isinstance(j, (list, tuple)) and len(j) >= 2 and
                all(isinstance(v, (int, float)) and not isinstance(v, bool)
                    for v in j[:2])):
            bone["joint"] = (float(j[0]), float(j[1]))
        else:
            errors.append(path + ".joint : paire [x, y] requise")
        bone["angle"] = num_or(bj.get("angle"), 0, errors, path + ".angle")
        bone["length"] = num_or(bj.get("length"), 80, errors, path + ".length")
        if bone["length"] <= 0:
            errors.append(path + ".length : doit être > 0")
            bone["length"] = 80.0
        z = bj.get("z", 0)
        bone["z"] = int(z) if isinstance(z, (int, float)) and \
            not isinstance(z, bool) else 0
        cyc = bj.get("cycle")
        if isinstance(cyc, dict):
            bone["own_repeat"] = cyc.get("repeat")
        # Keyframes EMBARQUÉES dans l'os (v0.17) — champ `bone` implicite.
        if bj.get("keyframes") is not None:
            keys = parse_keyframes(bj["keyframes"], errors, path + ".keyframes")
            for k in keys:
                bone["keys"].append(materialize_bone_key(
                    rig, bone, k, path + ".keyframes", errors))
        rig["bones"].append(bone)
        rig["by_name"][name] = bone
        names.append(name)

    # Keyframes niveau squelette : champ `bone` requis.
    if sk.get("keyframes") is not None:
        keys = parse_keyframes(sk.get("keyframes"), errors, "skeleton.keyframes")
        for k in keys:
            kpath = "skeleton.keyframes[t=%s]" % fmt_fr(k["t"])
            bone = rig["by_name"].get(k.get("bone"))
            if bone is None:
                errors.append("%s.bone : os « %s » inconnu"
                              % (kpath, k.get("bone")))
                continue
            bone["keys"].append(materialize_bone_key(
                rig, bone, k, kpath, errors))
    merge_bone_keys(rig, errors)
    rig["global_repeat"] = (sk.get("cycle", {}).get("repeat")
                            if isinstance(sk.get("cycle"), dict) else None)
    apply_bone_cycles(rig, errors)
    for b in rig["bones"]:
        for k in b["keys"]:
            k.pop("posed_move", None)
        if b["keys"]:
            rig["duration"] = max(rig["duration"], b["keys"][-1]["t"])

    # Repères de repos : offset enfant dans le repère de repos du parent.
    for bone in rig["bones"]:
        par = rig["by_name"].get(bone["parent"]) if bone["parent"] else None
        if par is None:
            bone["rest_rel"] = 0.0
            bone["offset"] = bone["joint"]
        else:
            bone["rest_rel"] = bone["angle"] - par["angle"]
            dx = bone["joint"][0] - par["joint"][0]
            dy = bone["joint"][1] - par["joint"][1]
            bone["offset"] = rot2(dx, dy, -math.radians(par["angle"]))

    # Liaisons : skeleton.bind + raccourcis « bone » des formes.
    bind = sk.get("bind")
    if bind is not None:
        if not isinstance(bind, dict):
            errors.append("skeleton.bind : doit être un objet {forme → os}")
        else:
            for s_field, b_field in bind.items():
                if "/" in s_field:
                    s_name, l_name = s_field.split("/", 1)
                else:
                    s_name, l_name = s_field, None
                if not _shape_exists(shapes, s_name, l_name, s_field):
                    continue
                if not _bone_exists(rig, b_field, s_field):
                    continue
                rig["bindings"].append((s_name, l_name, b_field))
    for shape in shapes:
        if shape["bone_shortcut"]:
            s_name = shape["name"]
            bound = {b for (s, l, b) in rig["bindings"]
                     if s == s_name and l is None}
            if bound and bound != {shape["bone_shortcut"]}:
                errors.append(
                    "shapes[%s].bone : conflit — aussi liée à « %s » par "
                    "skeleton.bind" % (s_name, ", ".join(sorted(bound))))
            elif not bound:
                if shape["bone_shortcut"] in rig["by_name"]:
                    rig["bindings"].append((s_name, None,
                                            shape["bone_shortcut"]))
                else:
                    errors.append(
                        "shapes[%s].bone : aucun os ne s'appelle « %s »"
                        % (s_name, shape["bone_shortcut"]))

    # Os porteur par forme / par couche (précalcul pour le rendu).
    for shape in shapes:
        whole = next((b for (s, l, b) in rig["bindings"]
                      if s == shape["name"] and l is None), None)
        shape["bone"] = whole
        shape["layer_bones"] = {l: b for (s, l, b) in rig["bindings"]
                                if s == shape["name"] and l is not None}
    return rig


def _shape_exists(shapes, s_name, l_name, label):
    shape = next((s for s in shapes if s["name"] == s_name), None)
    if shape is None:
        errors.append("skeleton.bind[\"%s\"] : forme « %s » inconnue"
                      % (label, s_name))
        return False
    if l_name is not None and not any(
            l["name"] == l_name for l in shape["layers"]):
        errors.append("skeleton.bind[\"%s\"] : couche « %s » inconnue"
                      % (label, l_name))
        return False
    return True


def _bone_exists(rig, b_name, label):
    if b_name in rig["by_name"]:
        return True
    errors.append("skeleton.bind[\"%s\"] : aucun os ne s'appelle « %s »"
                  % (label, b_name))
    return False


# ------------------------------------------------------- FK squelette exacte

def _bone_num_at(bone, t, field, base=1.0):
    """Sampler exact `_numAt` : chaque keyframe d'os porte sa PROPRE valeur
    (une propriété omise vaut le défaut neutre — PAS de carry entre poses
    d'os), interpolation entre les clés encadrantes avec l'easing
    d'ARRIVÉE, tenue avant la 1re / après la dernière. Piste vide → base."""
    keys = bone["keys"]
    if not keys:
        return base
    resolved = [base if k[field] is None else k[field] for k in keys]
    if t <= keys[0]["t"]:
        return resolved[0]
    if t >= keys[-1]["t"]:
        return resolved[-1]
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / (b["t"] - a["t"]) if b["t"] > a["t"] else 1.0
            f = ease(b["_easing"], u)
            return resolved[i] + (resolved[i + 1] - resolved[i]) * f
    return resolved[-1]


def angle_delta_at(bone, t):
    """Delta d'angle (radians) — 0 sans piste (repos)."""
    keys = bone["keys"]
    if not keys:
        return 0.0
    if t <= keys[0]["t"]:
        return keys[0]["d"]
    if t >= keys[-1]["t"]:
        return keys[-1]["d"]
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / (b["t"] - a["t"]) if b["t"] > a["t"] else 1.0
            f = ease(b["_easing"], u)
            return a["d"] + (b["d"] - a["d"]) * f
    return keys[-1]["d"]


def translation_at(bone, t):
    """Translation animée du joint (tx, ty) — (0, 0) sans piste. Chaque
    keyframe porte sa PROPRE translation (une clé sans `move` vaut 0, PAS de
    carry), interpolation avec l'easing d'ARRIVÉE, tenue hors plage."""
    keys = bone["keys"]
    if not keys:
        return (0.0, 0.0)
    resolved = [(0.0 if k["tx"] is None else k["tx"],
                 0.0 if k["ty"] is None else k["ty"]) for k in keys]
    if t <= keys[0]["t"]:
        return resolved[0]
    if t >= keys[-1]["t"]:
        return resolved[-1]
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / (b["t"] - a["t"]) if b["t"] > a["t"] else 1.0
            f = ease(b["_easing"], u)
            return (resolved[i][0] + (resolved[i + 1][0] - resolved[i][0]) * f,
                    resolved[i][1] + (resolved[i + 1][1] - resolved[i][1]) * f)
    return resolved[-1]


def evaluate_rig(rig, t):
    """FK exacte : réplique de SkeletonPose.evaluate (skeleton.dart).

    Parents d'abord (garanti par la déclaration) ; jointRest/angleRest =
    pose de repos MONDE ; l'animation du parent (delta d'angle + déplacement
    du joint + stretch) se propage aux enfants via leur offset, qui est
    multiplié par le stretch du parent puis tourné selon son angle courant.
    """
    frames = {}
    for bone in rig["bones"]:
        par = rig["by_name"].get(bone["parent"]) if bone["parent"] else None
        pf = frames.get(par["name"]) if par else None
        if pf is None:
            joint_rest = bone["joint"]
            angle_rest = bone["angle"]
        else:
            ox, oy = rot2(bone["offset"][0], bone["offset"][1],
                          math.radians(pf["angle_rest"]))
            joint_rest = (pf["joint_rest"][0] + ox, pf["joint_rest"][1] + oy)
            angle_rest = pf["angle_rest"] + bone["rest_rel"]
        tx, ty = translation_at(bone, t)
        if pf is None:
            joint = (bone["joint"][0] + tx, bone["joint"][1] + ty)
        else:
            dx = (bone["offset"][0] + tx) * pf["stretch_x"]
            dy = (bone["offset"][1] + ty) * pf["stretch_y"]
            rx, ry = rot2(dx, dy, math.radians(pf["world_angle"]))
            joint = (pf["joint"][0] + rx, pf["joint"][1] + ry)
        parent_delta = (pf["world_angle"] - pf["angle_rest"]) if pf else 0.0
        world_angle = angle_rest + parent_delta + angle_delta_at(bone, t)
        frames[bone["name"]] = {
            "joint_rest": joint_rest, "angle_rest": angle_rest,
            "joint": joint, "world_angle": world_angle,
            "length": bone["length"],
            "stretch_x": _bone_num_at(bone, t, "st"),
            "stretch_y": _bone_num_at(bone, t, "sq"),
            "opacity": _bone_num_at(bone, t, "op"),
        }
    return frames


def shape_pose_at(shape, t):
    """Pose interpolée de la forme (valueAt exact : tenue hors plage,
    easing de la keyframe d'arrivée)."""
    keys = shape["keyframes"]
    base = {"x": shape["x"], "y": shape["y"], "rotation": shape["rotation"],
            "scale": shape["scale"], "scaleX": shape["scaleX"],
            "scaleY": shape["scaleY"], "opacity": shape["opacity"],
            "thickness": 1.0}
    if not keys:
        return base
    if t <= keys[0]["t"]:
        return keys[0]["pose"]
    if t >= keys[-1]["t"]:
        return keys[-1]["pose"]
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / (b["t"] - a["t"]) if b["t"] > a["t"] else 1.0
            f = ease(b["_easing"], u)
            return {p: a["pose"][p] + (b["pose"][p] - a["pose"][p]) * f
                    for p in SHAPE_PROPS}
    return keys[-1]["pose"]


def color_at(shape, layer, t, palette):
    """Couleur RENDUE de la couche à t (colorAtLayer exact) : valeur
    résolue par pose (son entrée, sinon carry, sinon la couleur de base),
    interpolation entre les poses encadrantes avec l'easing d'arrivée."""
    base = resolve_color(layer["color"], palette)
    if base is None:
        base = resolve_color(DEFAULT_COLOR, {})
    keys = shape["keyframes"]
    if not keys:
        return base

    def to_rgba(raw):
        if raw is None:
            return base
        c = resolve_color(raw, palette)
        return c if c is not None else base

    def resolved(i):
        return to_rgba(keys[i]["colors_resolved"].get(layer["name"]))

    if t <= keys[0]["t"]:
        return resolved(0)
    if t >= keys[-1]["t"]:
        return resolved(len(keys) - 1)
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / (b["t"] - a["t"]) if b["t"] > a["t"] else 1.0
            f = ease(b["_easing"], u)
            return lerp_color(resolved(i), resolved(i + 1), f)
    return resolved(len(keys) - 1)


def points_at(shape, layer, t):
    """Nuage de points RENDU de la couche à t (pointsAtLayer exact), en
    coordonnées de rendu locales — repère commun = centre bbox de la liste
    `points` de BASE (les morphs dériveraient sinon)."""
    if layer["kind"] != "path" or not layer["cloud"]:
        return []
    keys = shape["keyframes"]
    if not keys:
        return list(layer["cloud"])

    def resolved(i):
        return keys[i]["points_resolved"].get(layer["name"]) or layer["cloud"]

    if t <= keys[0]["t"]:
        return list(resolved(0))
    if t >= keys[-1]["t"]:
        return list(resolved(len(keys) - 1))
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / (b["t"] - a["t"]) if b["t"] > a["t"] else 1.0
            f = ease(b["_easing"], u)
            return lerp_clouds(resolved(i), resolved(i + 1), f)
    return list(resolved(len(keys) - 1))


# ------------------------------------------------------------ rendu cairo

def apply_bone_delta(ctx, frame):
    """translate(joint_t) · rotate(worldAngle_t) · scale(S) · rotate(−rest)
    · translate(−jointRest) — identité au repos (scene_painter.dart)."""
    ctx.translate(frame["joint"][0], frame["joint"][1])
    ctx.rotate(math.radians(frame["world_angle"]))
    ctx.scale(frame["stretch_x"], frame["stretch_y"])
    ctx.rotate(math.radians(-frame["angle_rest"]))
    ctx.translate(-frame["joint_rest"][0], -frame["joint_rest"][1])


def apply_shape_pose(ctx, pose, shape):
    """translate(x,y) · translate(S·pivot) · rotate · scale(eff) ·
    translate(−pivot) — gond ancré à sa position VISUELLE."""
    cx = pose["scaleX"] if pose["scaleX"] > 0 else 0.0001
    cy = pose["scaleY"] if pose["scaleY"] > 0 else 0.0001
    px, py = shape["pivot_x"], shape["pivot_y"]
    ctx.translate(pose["x"], pose["y"])
    ctx.translate(cx * px, cy * py)
    ctx.rotate(math.radians(pose["rotation"]))
    ctx.scale(cx, cy)
    ctx.translate(-px, -py)


def apply_layer_pose(ctx, layer):
    """Pose locale de couche (statique) : translate · rotate · scale.

    v0.19 : réflexion du contenu (flipH/flipV) autour de l'origine de la
    couche, après l'échelle — même chaîne que scene_painter._paintLayer.
    """
    ctx.translate(layer["x"], layer["y"])
    ctx.rotate(math.radians(layer["rot"]))
    s = layer["scale"] if layer["scale"] > 0 else 0.0001
    ctx.scale(s, s)
    if layer.get("flipH") or layer.get("flipV"):
        ctx.scale(-1.0 if layer.get("flipH") else 1.0,
                  -1.0 if layer.get("flipV") else 1.0)


def _poly(ctx, pts):
    for i, (x, y) in enumerate(pts):
        if i == 0:
            ctx.move_to(x, y)
        else:
            ctx.line_to(x, y)
    ctx.close_path()


def _rounded_rect(ctx, w, h, radius=-1, corners=(True, True, True, True)):
    """Rectangle à rayon commun, avec rayons indépendants par coin."""
    r = min(24.0, min(w, h) * 0.15) if radius < 0 else radius
    r = min(max(0.0, r), w / 2.0, h / 2.0)
    hw, hh = w / 2.0, h / 2.0
    tl, tr, br, bl = (r if enabled else 0.0 for enabled in corners)
    ctx.new_sub_path()
    ctx.move_to(-hw + tl, -hh)
    ctx.line_to(hw - tr, -hh)
    if tr:
        ctx.arc(hw - tr, -hh + tr, tr, -math.pi / 2, 0.0)
    else:
        ctx.line_to(hw, -hh)
    ctx.line_to(hw, hh - br)
    if br:
        ctx.arc(hw - br, hh - br, br, 0.0, math.pi / 2)
    else:
        ctx.line_to(hw, hh)
    ctx.line_to(-hw + bl, hh)
    if bl:
        ctx.arc(-hw + bl, hh - bl, bl, math.pi / 2, math.pi)
    else:
        ctx.line_to(-hw, hh)
    ctx.line_to(-hw, -hh + tl)
    if tl:
        ctx.arc(-hw + tl, -hh + tl, tl, math.pi, 3 * math.pi / 2)
    else:
        ctx.line_to(-hw, -hh)
    ctx.close_path()


def build_geometry(ctx, layer, cloud):
    """Géométrie exacte de _kindPath / _paintLayer (scene_painter.dart)."""
    kind, w, h = layer["kind"], layer["w"], layer["h"]
    if kind == "rect":
        _rounded_rect(
            ctx, w, h, layer.get("cornerRadius", -1),
            (layer.get("roundTopLeft", True),
             layer.get("roundTopRight", True),
             layer.get("roundBottomRight", True),
             layer.get("roundBottomLeft", True)),
        )
    elif kind == "circle":
        ctx.save()
        ctx.scale(w / 2.0, h / 2.0)
        ctx.arc(0.0, 0.0, 1.0, 0.0, 2 * math.pi)
        ctx.close_path()
        ctx.restore()
    elif kind == "line":
        ctx.move_to(-w / 2.0, 0.0)
        ctx.line_to(w / 2.0, 0.0)
    elif kind == "path":
        if cloud:
            ctx.move_to(cloud[0][0], cloud[0][1])
            for p in cloud[1:]:
                ctx.line_to(p[0], p[1])
            ctx.close_path()
        else:
            ctx.rectangle(-w / 2.0, -h / 2.0, w, h)
    elif kind == "triangle":
        _poly(ctx, [(0.0, -h / 2.0), (w / 2.0, h / 2.0), (-w / 2.0, h / 2.0)])
    elif kind == "star":
        pts = []
        for i in range(10):
            ang = -math.pi / 2 + i * math.pi / 5
            radius = 1.0 if i % 2 == 0 else 0.45
            pts.append((math.cos(ang) * (w / 2) * radius,
                        math.sin(ang) * (h / 2) * radius))
        _poly(ctx, pts)
    elif kind == "hexagon":
        pts = [(math.cos(-math.pi / 2 + i * math.pi / 3) * w / 2,
                math.sin(-math.pi / 2 + i * math.pi / 3) * h / 2)
               for i in range(6)]
        _poly(ctx, pts)
    elif kind == "cross":
        a, b, tx, ty = w / 2.0, h / 2.0, w / 6.0, h / 6.0
        _poly(ctx, [(-tx, -b), (tx, -b), (tx, -ty), (a, -ty), (a, ty),
                    (tx, ty), (tx, b), (-tx, b), (-tx, ty), (-a, ty),
                    (-a, -ty), (-tx, -ty)])
    elif kind == "heart":
        cw, ch = w / 2.0, h / 2.0
        ctx.move_to(0.0, ch)
        ctx.curve_to(-cw, ch * 0.25, -cw * 0.55, -ch, 0.0, -ch * 0.35)
        ctx.curve_to(cw * 0.55, -ch, cw, ch * 0.25, 0.0, ch)
        ctx.close_path()
    elif kind == "arrow":
        a, b = w / 2.0, h / 2.0
        _poly(ctx, [(-a, -h * 0.2), (w * 0.05, -h * 0.2), (w * 0.05, -b),
                    (a, 0.0), (w * 0.05, b), (w * 0.05, h * 0.2), (-a, h * 0.2)])
    else:
        ctx.rectangle(-w / 2.0, -h / 2.0, w, h)


def draw_primitive(ctx, layer, cloud, rgba, opacity, stroke_factor):
    """Alpha de la couleur REMPLACÉ par l'opacité calculée (comportement de
    l'app : `Color(colorValue).withValues(alpha: opacity)` — l'alpha propre
    d'un `#AARRGGBB` n'est PAS appliqué) ; trait = strokeWidth × facteur de
    pose, caps/joints arrondis."""
    opacity = clamp(opacity, 0.0, 1.0)
    if opacity <= 0:
        return
    stroke = max(0.0, layer["sw"] * stroke_factor)
    ctx.set_source_rgba(rgba[0], rgba[1], rgba[2], opacity)
    ctx.set_line_width(stroke)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.new_path()
    build_geometry(ctx, layer, cloud)
    if layer["filled"] and layer["kind"] != "line":
        ctx.fill()
    else:
        ctx.stroke()


def z_for_shape(rig, shape):
    """z de dessin d'une forme : os porteur (liaison entière), sinon MIN
    du z des os portant ses couches, sinon 0 (zForShape exact)."""
    if shape["bone"]:
        return rig["by_name"][shape["bone"]]["z"]
    bones = [rig["by_name"][b] for b in shape["layer_bones"].values()]
    return min(b["z"] for b in bones) if bones else 0


def z_of_layer(rig, shape, layer):
    b = shape["layer_bones"].get(layer["name"])
    return rig["by_name"][b]["z"] if b else None


def draw_rig_overlay(ctx, rig, frames):
    for bone in rig["bones"]:
        f = frames[bone["name"]]
        tx, ty = rot2(bone["length"] * f["stretch_x"], 0.0,
                      math.radians(f["world_angle"]))
        tip = (f["joint"][0] + tx, f["joint"][1] + ty)
        ctx.set_source_rgba(1.0, 0.72, 0.25, 0.85)
        ctx.set_line_width(3.0)
        ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        ctx.move_to(f["joint"][0], f["joint"][1])
        ctx.line_to(tip[0], tip[1])
        ctx.stroke()
        ctx.set_source_rgba(1.0, 0.45, 0.1, 0.95)
        ctx.new_path()
        ctx.arc(f["joint"][0], f["joint"][1], 6.0, 0.0, 2 * math.pi)
        ctx.fill()


def group_center_of(doc, group):
    """Centre visuel d'un groupe : moyenne des positions de repos (x/y de
    base) de ses fils — même pivot que le painter de l'app."""
    if group is None:
        return None
    xs, ys = [], []
    for s in doc["shapes"]:
        if s["groupId"] == group["name"]:
            xs.append(s["x"])
            ys.append(s["y"])
    if not xs:
        return None
    return (sum(xs) / len(xs), sum(ys) / len(ys))


def apply_group_transform(ctx, group, center):
    """Transformation STATIQUE du groupe (v6) : décalage, rotation et échelle
    d'axe autour du centre visuel — identité quand tout est neutre."""
    ctx.translate(center[0] + group["x"], center[1] + group["y"])
    ctx.rotate(math.radians(group["rotation"]))
    ctx.scale(group["scaleX"], group["scaleY"])
    ctx.translate(-center[0], -center[1])


def render_frame(doc, t, draw_bones=False):
    """Une frame = fond + formes (z en projet squelette) + rig optionnel.

    Couche : BoneDelta ∘ PoseForme(t) ∘ PoseCouche, avec os porteur = os de
    couche (prioritaire) sinon os de la forme entière ; opacité forme × os
    de porteur × couche ; couleur animée + morph par couche (vasf-3).
    """
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32,
                                 doc["width"], doc["height"])
    ctx = cairo.Context(surface)
    ctx.set_source_rgba(*doc["bg"])
    ctx.paint()
    rig = doc["skeleton"]
    rig_frames = evaluate_rig(rig, t) if rig else None
    shapes = doc["shapes"]
    if rig:
        order = sorted(
            range(len(shapes)),
            key=lambda i: (shapes[i]["zIndex"], z_for_shape(rig, shapes[i]), i),
        )
    else:
        order = sorted(range(len(shapes)), key=lambda i: (shapes[i]["zIndex"], i))
    for i in order:
        shape = shapes[i]
        # Fenêtre d'affichage : la forme n'est rendue que sur [start, end]
        # (l'œil `visible` n'existe pas en vasf).
        if not (shape["start"] <= t <= shape["end"]):
            continue
        # Groupe d'éléments (v6) : un groupe masqué cache ses formes.
        group = doc["groups"].get(shape["groupId"]) \
            if shape["groupId"] else None
        if group is not None and not group["visible"]:
            continue
        # Transformation statique du groupe : autour de son centre visuel.
        group_center = group_center_of(doc, group) if group else None
        pose = shape_pose_at(shape, t)
        carrier = rig_frames.get(shape["bone"]) \
            if (rig and shape["bone"]) else None
        layers = shape["layers"]
        if rig:
            layer_order = sorted(
                range(len(layers)),
                key=lambda j: (z_of_layer(rig, shape, layers[j]) or 0, j))
        else:
            layer_order = range(len(layers))
        for j in layer_order:
            layer = layers[j]
            bone_name = shape["layer_bones"].get(layer["name"]) if rig else None
            frame = rig_frames.get(bone_name) if (rig and bone_name) \
                else carrier
            bone_op = frame["opacity"] if frame else 1.0
            opacity = (clamp(pose["opacity"] * bone_op, 0.0, 1.0) *
                       clamp(layer["opacity"], 0.0, 1.0))
            rgba = color_at(shape, layer, t, doc["palette"])
            cloud = points_at(shape, layer, t)
            ctx.save()
            if group is not None and group_center is not None:
                apply_group_transform(ctx, group, group_center)
            if frame:
                apply_bone_delta(ctx, frame)
            apply_shape_pose(ctx, pose, shape)
            apply_layer_pose(ctx, layer)
            draw_primitive(ctx, layer, cloud, rgba, opacity, pose["thickness"])
            ctx.restore()
    if draw_bones and rig:
        draw_rig_overlay(ctx, rig, rig_frames)
    return surface


# ---------------------------------------------------------------- planche

def compose_planche(surfaces, times, cell_scale):
    """Planche côte à côte, cellules réduites (--scale), label temps sous
    chaque cellule (décimales à la française)."""
    n = len(surfaces)
    w0, h0 = surfaces[0].get_width(), surfaces[0].get_height()
    cw, ch = max(1, int(w0 * cell_scale)), max(1, int(h0 * cell_scale))
    margin, gap, label_h = 12, 10, 30
    width = margin * 2 + n * cw + (n - 1) * gap
    height = margin + ch + label_h + margin
    out = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(out)
    ctx.set_source_rgba(0.10, 0.11, 0.13, 1.0)
    ctx.paint()
    ctx.select_font_face("DejaVu Sans", cairo.FONT_SLANT_NORMAL,
                         cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(15)
    for i, (surf, t) in enumerate(zip(surfaces, times)):
        x = margin + i * (cw + gap)
        ctx.save()
        ctx.translate(x, margin)
        ctx.scale(cw / w0, ch / h0)
        ctx.set_source_surface(surf, 0, 0)
        ctx.paint()
        ctx.restore()
        ctx.set_source_rgba(1.0, 1.0, 1.0, 0.18)
        ctx.set_line_width(1.0)
        ctx.rectangle(x + 0.5, margin + 0.5, cw - 1, ch - 1)
        ctx.stroke()
        ctx.set_source_rgba(1.0, 1.0, 1.0, 0.92)
        ctx.move_to(x, margin + ch + label_h - 9)
        ctx.show_text("t = %s s" % fmt_fr(t))
    return out


def uniquify_names(shapes, warnings):
    seen = set()
    for s in shapes:
        name = s["name"]
        if name in seen:
            k = 2
            while "%s %d" % (name, k) in seen:
                k += 1
            warnings.append("shapes[%s] : nom dupliqué → renommé « %s %d »"
                            % (name, name, k))
            s["name"] = "%s %d" % (name, k)
        seen.add(s["name"])


# ------------------------------------------------------- document complet

def parse_document(dj):
    errors, warnings = [], []
    canvas = dj.get("canvas") if isinstance(dj.get("canvas"), dict) else {}
    width = int(num_or(canvas.get("width"), 720, errors, "canvas.width"))
    height = int(num_or(canvas.get("height"), 1280, errors, "canvas.height"))
    theme = dj.get("theme")
    palette = {}
    if theme is not None:
        if isinstance(theme, dict):
            for alias, cval in theme.items():
                if resolve_color(cval, {}) is None:
                    errors.append(
                        "theme[« %s »] : couleur littérale #RRGGBB attendue"
                        % alias)
                else:
                    palette[alias] = cval
        else:
            errors.append("theme : doit être un objet {alias → couleur}")
    bg = resolve_color(canvas.get("background"), palette, DEFAULT_BG)
    if bg is None:
        errors.append("canvas.background : couleur invalide")
        bg = resolve_color(DEFAULT_BG, {})
    raw_defs = dj.get("defs")
    defs = raw_defs if isinstance(raw_defs, dict) else {}
    if raw_defs is not None and not isinstance(raw_defs, dict):
        errors.append("defs : doit être un objet {nom → définition}")
    groups = parse_groups(dj.get("groups"), errors, warnings)
    raw_shapes = dj.get("shapes")
    shapes = []
    if isinstance(raw_shapes, list) and raw_shapes:
        for i, sj in enumerate(raw_shapes):
            if isinstance(sj, dict):
                shapes.append(parse_shape(sj, i, palette, defs, errors,
                                          warnings, width / 2.0, height / 2.0))
            else:
                errors.append("shapes[%d] : doit être un objet" % i)
    else:
        errors.append("shapes : tableau de ≥ 1 forme requis")
    uniquify_names(shapes, warnings)
    apply_window_defaults(shapes, errors, warnings)
    for shape in shapes:
        normalize_shape_keys(shape, errors, warnings, palette)
    rig = None
    if dj.get("skeleton") is not None:
        if isinstance(dj.get("skeleton"), dict):
            rig = parse_skeleton(dj["skeleton"], shapes, errors, warnings)
        else:
            errors.append("skeleton : doit être un objet")
    return {
        "name": dj.get("name") if isinstance(dj.get("name"), str)
        else "Animation importée",
        "width": width, "height": height, "bg": bg,
        "palette": palette, "shapes": shapes, "skeleton": rig,
        "groups": groups,
        "errors": errors, "warnings": warnings,
    }


def document_duration(doc):
    """Durée du projet : la fin la plus tardive des segments de formes
    (fenêtres start/end, keyframes au-delà comprises) ; les keyframes d'os
    s'ajoutent avec un plancher de 4 s dès qu'un rig ou une forme existe."""
    span = 0.0
    for s in doc["shapes"]:
        span = max(span, s["end"])
    if doc["skeleton"]:
        span = max(span, doc["skeleton"]["duration"], 4.0)
    return span if span > 0 else 4.0


def pick_document(data, pick, fatal):
    """Un seul objet vasf à la racine (l'appli importe UN objet par import)."""
    def is_doc(d):
        return isinstance(d, dict) and isinstance(d.get("shapes"), list)

    if is_doc(data):
        return data
    if isinstance(data, list):
        docs = [(str(i), d) for i, d in enumerate(data) if is_doc(d)]
    elif isinstance(data, dict):
        docs = [(k, v) for k, v in data.items() if is_doc(v)]
    else:
        docs = []
    if not docs:
        fatal("aucun objet vasf (champ « shapes ») trouvé")
    if pick is not None:
        for k, d in docs:
            if k == pick:
                return d
        fatal("--pick %s : aucune clé candidate (%s)"
              % (pick, ", ".join(k for k, _ in docs)))
    if len(docs) == 1:
        return docs[0][1]
    fatal("recueil de %d objets — précisez --pick parmi : %s"
          % (len(docs), ", ".join(k for k, _ in docs)))


# -------------------------------------------------------------------- CLI

def main():
    ap = argparse.ArgumentParser(
        description="Aperçu headless d'un JSON vasf (Vector Anim Studio).")
    ap.add_argument("fichier", help="fichier .json vasf (ou recueil)")
    ap.add_argument("times", nargs="*", type=float,
                    help="instants rendus (secondes)")
    ap.add_argument("--out", default=None,
                    help="dossier de sortie (défaut tmp/vasf_preview/<nom>/)")
    ap.add_argument("--scale", type=float, default=0.28,
                    help="échelle des cellules de la planche")
    ap.add_argument("--pick", default=None,
                    help="clé de l'objet dans un recueil d'exemples")
    ap.add_argument("--bones", action="store_true",
                    help="superposer le rig (os + articulations)")
    args = ap.parse_args()

    def fatal(msg):
        sys.stderr.write("✗ %s\n" % msg)
        sys.exit(2)

    try:
        with open(args.fichier, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError as exc:
        fatal("fichier illisible : %s" % exc)
    except json.JSONDecodeError as exc:
        fatal("JSON invalide : %s" % exc)

    dj = pick_document(data, args.pick, fatal)
    doc = parse_document(dj)
    if not doc["shapes"]:
        fatal("aucune forme valide — rien à rendre")

    duration = document_duration(doc)
    times = sorted(set(round(t, 3) for t in args.times)) if args.times \
        else [duration * i / 4.0 for i in range(5)]

    stem = re.sub(r"[^A-Za-z0-9_-]+", "_",
                  os.path.splitext(os.path.basename(args.fichier))[0])
    out_dir = args.out or os.path.join("tmp", "vasf_preview", stem)
    os.makedirs(out_dir, exist_ok=True)

    surfaces, frame_paths = [], []
    for t in times:
        surf = render_frame(doc, t, args.bones)
        path = os.path.join(out_dir, "frame_t%.2f.png" % t)
        surf.write_to_png(path)
        surfaces.append(surf)
        frame_paths.append(path)
    planche = compose_planche(surfaces, times, args.scale)
    planche_path = os.path.join(out_dir, "planche.png")
    planche.write_to_png(planche_path)

    print("VASF preview — %s" % doc["name"])
    print("  durée du contenu : %s s · instants : %s"
          % (fmt_fr(duration), " / ".join(fmt_fr(t) for t in times)))
    print("  planche : %s" % planche_path)
    print("  frames  : %s … (%d)" % (frame_paths[0], len(frame_paths)))
    if doc["errors"]:
        print("✗ %d erreur(s) — à corriger avant livraison :" % len(doc["errors"]))
        for e in doc["errors"]:
            print("   - %s" % e)
    if doc["warnings"]:
        print("⚠ %d avertissement(s) :" % len(doc["warnings"]))
        for w in doc["warnings"]:
            print("   - %s" % w)
    sys.exit(1 if doc["errors"] else 0)


if __name__ == "__main__":
    main()
