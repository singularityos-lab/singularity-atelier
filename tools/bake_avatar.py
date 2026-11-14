#!/usr/bin/env python3
import json
import os
import struct
import sys

import numpy as np

RENDER_GROUPS = ("body", "helper-l-eye", "helper-r-eye")
MUSCLE = ("minmuscle", "averagemuscle", "maxmuscle")
WEIGHT = ("minweight", "averageweight", "maxweight")
RACES = ("african", "asian", "caucasian")


def read_obj(path):
    verts, faces, group = [], {}, None
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                verts.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("g "):
                group = line.split()[1]
            elif line.startswith("f "):
                faces.setdefault(group, []).append([int(t.split("/")[0]) - 1 for t in line.split()[1:]])
    return np.array(verts, dtype=np.float64), faces


def read_target(path, count):
    d = np.zeros((count, 3), dtype=np.float64)
    with open(path) as f:
        for line in f:
            if not line or line[0] == "#" or not line.strip():
                continue
            p = line.split()
            d[int(p[0])] = (float(p[1]), float(p[2]), float(p[3]))
    return d


PROXIES = ("hair/afro01", "hair/bob01", "hair/bob02", "hair/braid01", "hair/long01", "hair/ponytail01", "hair/short01", "hair/short02", "hair/short03", "hair/short04")
BROWS = "eyebrows/eyebrow001"


def read_proxy(assets, rel):
    folder = os.path.join(assets, rel)
    name = os.path.basename(rel)
    verts, scales, in_verts = [], {}, False
    with open(os.path.join(folder, name + ".mhclo"), errors="replace") as f:
        for line in f:
            p = line.split()
            if not p or p[0].startswith("#"):
                continue
            if p[0] in ("x_scale", "y_scale", "z_scale"):
                scales[p[0][0]] = (int(p[1]), int(p[2]), float(p[3]))
            elif p[0] == "verts":
                in_verts = True
            elif in_verts and len(p) == 9:
                verts.append(([int(p[0]), int(p[1]), int(p[2])], [float(x) for x in p[3:6]], [float(x) for x in p[6:9]]))
            elif in_verts and len(p) == 1 and p[0].isdigit():
                verts.append(([int(p[0])] * 3, [1.0, 0.0, 0.0], [0.0, 0.0, 0.0]))
    tris = []
    with open(os.path.join(folder, name + ".obj"), errors="replace") as f:
        for line in f:
            if line.startswith("f "):
                ids = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
                for k in range(1, len(ids) - 1):
                    tris.append((ids[0], ids[k], ids[k + 1]))
    return name, verts, scales, tris


def proxy_points(base, verts, scales):
    out = np.zeros((len(verts), 3))
    factor = [abs(base[scales[a][0]][i] - base[scales[a][1]][i]) / scales[a][2] if a in scales else 1.0 for i, a in enumerate("xyz")]
    for k, (ids, w, off) in enumerate(verts):
        out[k] = sum(base[ids[j]] * w[j] for j in range(3)) + np.array(off) * factor
    return out


def name_bytes(s):
    b = s.encode()
    return struct.pack("<B", len(b)) + b


def main():
    data, out_path = sys.argv[1], sys.argv[2]
    assets = sys.argv[3] if len(sys.argv) > 3 else None
    verts, faces = read_obj(os.path.join(data, "3dobjs", "base.obj"))
    total = len(verts)
    skel = json.load(open(os.path.join(data, "rigs", "default.mhskel")))
    weights = json.load(open(os.path.join(data, "rigs", "default_weights.mhw")))["weights"]

    quads = [q for g in RENDER_GROUPS for q in faces[g]]
    used = sorted({i for q in quads for i in q})
    joint_names = sorted(skel["joints"])
    joint_verts = sorted({i for n in joint_names for i in skel["joints"][n]})
    proxies = [read_proxy(assets, rel) for rel in PROXIES] if assets else []
    brows = read_proxy(assets, BROWS) if assets else None
    extra = set()
    for _, pv, sc, _ in proxies:
        for ids, _, _ in pv:
            extra.update(ids)
        for a, b, _ in sc.values():
            extra.update((a, b))
    taken = set(used)
    keep = used + [i for i in joint_verts if i not in taken]
    taken.update(joint_verts)
    keep += sorted(i for i in extra if i not in taken)
    remap = {old: new for new, old in enumerate(keep)}
    nv = len(keep)
    assert nv < 65536
    keep_idx = np.array(keep)

    def target(*parts):
        return read_target(os.path.join(data, "targets", *parts), total)[keep_idx]

    base = verts[keep_idx]
    dense, sparse = [], []
    for g in ("female", "male"):
        shape = base.copy()
        for r in RACES:
            shape += target("macrodetails", "%s-%s-young.target" % (r, g)) / 3.0
        center = target("macrodetails", "universal-%s-young-averagemuscle-averageweight.target" % g)
        dense.append((g, shape + center, True))
        for m in MUSCLE:
            for w in WEIGHT:
                if m == "averagemuscle" and w == "averageweight":
                    continue
                d = target("macrodetails", "universal-%s-young-%s-%s.target" % (g, m, w)) - center
                dense.append(("%s:%s-%s" % (g, m, w), d, False))
        for h in ("minheight", "maxheight"):
            dense.append(("%s:%s" % (g, h), target("macrodetails", "height", "%s-young-averagemuscle-averageweight-%s.target" % (g, h)), False))
    for c in ("mincup", "maxcup"):
        dense.append(("female:%s" % c, target("breast", "female-young-averagemuscle-averageweight-%s-averagefirmness.target" % c), False))
    mdir = os.path.join(data, "targets", "measure")
    for fn in sorted(os.listdir(mdir)):
        if fn.endswith(".target"):
            d = target("measure", fn)
            idx = np.nonzero(np.abs(d).sum(axis=1) > 1e-7)[0]
            sparse.append((fn[len("measure-"):-len(".target")], idx, d[idx]))

    for name in ("breast-point-decr", "breast-point-incr"):
        d = target("breast", name + ".target")
        idx = np.nonzero(np.abs(d).sum(axis=1) > 1e-7)[0]
        sparse.append((name, idx, d[idx]))

    bones = list(skel["bones"])
    order, placed = [], set()
    while len(order) < len(bones):
        for b in bones:
            p = skel["bones"][b]["parent"]
            if b not in placed and (p is None or p in placed):
                order.append(b)
                placed.add(b)
    bone_index = {b: i for i, b in enumerate(order)}
    joint_index = {n: i for i, n in enumerate(joint_names)}

    wsum = np.zeros((nv, len(order)), dtype=np.float32)
    for b, pairs in weights.items():
        if b not in bone_index:
            continue
        for i, w in pairs:
            if i in remap:
                wsum[remap[i], bone_index[b]] += w
    top = np.argsort(-wsum, axis=1)[:, :4]
    topw = np.take_along_axis(wsum, top, axis=1)
    s = topw.sum(axis=1, keepdims=True)
    s[s == 0] = 1
    topw = np.round(topw / s * 255).astype(np.int32)
    topw[:, 0] += 255 - topw.sum(axis=1)

    out = bytearray()
    out += b"ATAV"
    out += struct.pack("<7I", 2, nv, len(used), len(quads), len(order), len(joint_names), len(dense))
    out += struct.pack("<I", len(sparse))
    out += np.array([[remap[i] for i in q] for q in quads], dtype="<u2").tobytes()
    for b in order:
        info = skel["bones"][b]
        out += name_bytes(b)
        out += struct.pack("<hHH", -1 if info["parent"] is None else bone_index[info["parent"]], joint_index[info["head"]], joint_index[info["tail"]])
    for n in joint_names:
        ids = [remap[i] for i in skel["joints"][n]]
        out += struct.pack("<B", len(ids)) + np.array(ids, dtype="<u2").tobytes()
    out += top.astype("u1").tobytes()
    out += topw.astype("u1").tobytes()
    for name, arr, absolute in dense:
        out += name_bytes(name)
        mm = arr * 100.0
        if absolute:
            out += struct.pack("<Bf", 1, 1.0) + mm.astype("<f4").tobytes()
        else:
            scale = max(1e-9, float(np.abs(mm).max())) / 32767.0
            out += struct.pack("<Bf", 0, scale) + np.round(mm / scale).astype("<i2").tobytes()
    for name, idx, d in sparse:
        out += name_bytes(name)
        mm = d * 100.0
        scale = max(1e-9, float(np.abs(mm).max())) / 32767.0
        out += struct.pack("<If", len(idx), scale)
        out += idx.astype("<u2").tobytes()
        out += np.round(mm / scale).astype("<i2").tobytes()
    out += struct.pack("<I", len(proxies))
    for name, pv, sc, tris in proxies:
        out += name_bytes(name)
        out += struct.pack("<II", len(pv), len(tris))
        for a in "xyz":
            ra, rb, den = sc.get(a, (keep[0], keep[0], 1.0))
            out += struct.pack("<HHf", remap[ra], remap[rb], den if a in sc else 0.0)
        for ids, w, off in pv:
            out += struct.pack("<3H6f", remap[ids[0]], remap[ids[1]], remap[ids[2]], *w, *off)
        out += np.array(tris, dtype="<u2").tobytes()
    mask = []
    if brows:
        pts = proxy_points(verts, brows[1], brows[2])
        body = verts[np.array(used)]
        near = np.zeros(len(used), dtype=bool)
        for q in pts:
            near |= np.linalg.norm(body - q, axis=1) < 0.03
        mask = np.nonzero(near)[0]
    out += struct.pack("<I", len(mask))
    out += np.array(mask, dtype="<u2").tobytes()
    with open(out_path, "wb") as f:
        f.write(out)
    print("vertices %d (render %d) quads %d bones %d joints %d dense %d sparse %d proxies %d brow %d bytes %d" % (nv, len(used), len(quads), len(order), len(joint_names), len(dense), len(sparse), len(proxies), len(mask), len(out)))


if __name__ == "__main__":
    main()
