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


PROXIES = ("hair/afro01", "hair/bob01", "hair/bob02", "hair/braid01", "hair/long01", "hair/ponytail01", "hair/short01", "hair/short02", "hair/short03", "hair/short04", "clothes/shoes01", "clothes/fedora01")
BROWS = "eyebrows/eyebrow001"


def read_proxy(assets, rel):
    folder = os.path.join(assets, rel)
    name = os.path.basename(rel)
    verts, scales, in_verts, hidden, in_hidden = [], {}, False, [], False
    obj_name = name + ".obj"
    with open(os.path.join(folder, name + ".mhclo"), errors="replace") as f:
        for line in f:
            p = line.split()
            if not p or p[0].startswith("#"):
                continue
            if p[0] == "obj_file":
                obj_name = p[1]
                continue
            if p[0] == "delete_verts":
                in_hidden, in_verts = True, False
                continue
            if in_hidden:
                if not (p[0].isdigit() or p[0] == "-"):
                    in_hidden = False
                else:
                    k = 0
                    while k < len(p):
                        if k + 2 < len(p) and p[k + 1] == "-":
                            hidden.extend(range(int(p[k]), int(p[k + 2]) + 1))
                            k += 3
                        else:
                            hidden.append(int(p[k]))
                            k += 1
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
    with open(os.path.join(folder, obj_name), errors="replace") as f:
        for line in f:
            if line.startswith("f "):
                ids = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
                for k in range(1, len(ids) - 1):
                    tris.append((ids[0], ids[k], ids[k + 1]))
    return name, verts, scales, tris, hidden


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
    for _, pv, sc, _, _ in proxies:
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
    for kid, g in (("girl", "female"), ("boy", "male")):
        shape = base.copy()
        for r in RACES:
            shape += target("macrodetails", "%s-%s-child.target" % (r, g)) / 3.0
        center = target("macrodetails", "universal-%s-child-averagemuscle-averageweight.target" % g)
        dense.append((kid, shape + center, True))
        for w in ("minweight", "maxweight"):
            d = target("macrodetails", "universal-%s-child-averagemuscle-%s.target" % (g, w)) - center
            dense.append(("%s:averagemuscle-%s" % (kid, w), d, False))
        for h in ("minheight", "maxheight"):
            dense.append(("%s:%s" % (kid, h), target("macrodetails", "height", "%s-child-averagemuscle-averageweight-%s.target" % (g, h)), False))
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
    out += struct.pack("<7I", 6, nv, len(used), len(quads), len(order), len(joint_names), len(dense))
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
    for name, pv, sc, tris, hidden in proxies:
        out += name_bytes(name)
        out += struct.pack("<II", len(pv), len(tris))
        for a in "xyz":
            ra, rb, den = sc.get(a, (keep[0], keep[0], 1.0))
            out += struct.pack("<HHf", remap[ra], remap[rb], den if a in sc else 0.0)
        for ids, w, off in pv:
            out += struct.pack("<3H6f", remap[ids[0]], remap[ids[1]], remap[ids[2]], *w, *off)
        out += np.array(tris, dtype="<u2").tobytes()
        gone = [remap[i] for i in hidden if i in remap and remap[i] < len(used)]
        out += struct.pack("<I", len(gone)) + np.array(gone, dtype="<u2").tobytes()
    brow_amount = np.zeros(len(used))
    if brows:
        pts = proxy_points(verts, brows[1], brows[2])
        folder = os.path.join(assets, BROWS)
        uvs, faces = [], []
        with open(os.path.join(folder, "eyebrow001.obj"), errors="replace") as f:
            for line in f:
                p = line.split()
                if p and p[0] == "vt":
                    uvs.append((float(p[1]), float(p[2])))
                elif p and p[0] == "f":
                    c = [(int(t.split("/")[0]) - 1, int(t.split("/")[1]) - 1) for t in p[1:]]
                    for k in range(1, len(c) - 1):
                        faces.append((c[0], c[k], c[k + 1]))
        from PIL import Image
        alpha = np.array(Image.open(os.path.join(folder, "eyebrow001.png")).convert("RGBA"))[:, :, 3] / 255.0
        samples = []
        for a, b, c in faces:
            for u in np.linspace(0, 1, 14):
                for v in np.linspace(0, 1 - u, 14):
                    w = 1 - u - v
                    tu = uvs[a[1]][0] * w + uvs[b[1]][0] * u + uvs[c[1]][0] * v
                    tv = uvs[a[1]][1] * w + uvs[b[1]][1] * u + uvs[c[1]][1] * v
                    px = min(alpha.shape[1] - 1, max(0, int(tu * alpha.shape[1])))
                    py = min(alpha.shape[0] - 1, max(0, int((1 - tv) * alpha.shape[0])))
                    if alpha[py, px] > 0.45:
                        samples.append(pts[a[0]] * w + pts[b[0]] * u + pts[c[0]] * v)
        samples = np.array(samples)
        body = verts[np.array(used)]
        near = np.nonzero(np.linalg.norm(body - samples.mean(axis=0), axis=1) < 1.2)[0]
        for i in near:
            dist = np.linalg.norm(samples - body[i], axis=1).min()
            brow_amount[i] = max(0.0, 1.0 - dist / 0.045)
    mask = np.nonzero(brow_amount > 0.02)[0]
    out += struct.pack("<I", len(mask))
    for i in mask:
        out += struct.pack("<HB", int(i), int(round(brow_amount[i] * 255)))
    amount = np.zeros(len(used))
    for name in ("mouth-upperlip-volume-incr", "mouth-lowerlip-volume-incr"):
        d = np.linalg.norm(target("mouth", name + ".target")[: len(used)], axis=1)
        amount = np.maximum(amount, d / d.max())
    lips = np.nonzero(amount > 0.02)[0]
    out += struct.pack("<I", len(lips))
    for i in lips:
        out += struct.pack("<HB", int(i), int(round(amount[i] * 255)))
    with open(out_path, "wb") as f:
        f.write(out)
    print("vertices %d (render %d) quads %d bones %d joints %d dense %d sparse %d proxies %d brow %d lips %d bytes %d" % (nv, len(used), len(quads), len(order), len(joint_names), len(dense), len(sparse), len(proxies), len(mask), len(lips), len(out)))


if __name__ == "__main__":
    main()
