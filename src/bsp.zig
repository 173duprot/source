const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;

const Lump = extern struct { ofs: i32, len: i32 };
const Header = extern struct { ver: i32, lumps: [15]Lump };
pub const Vertex = extern struct { x: f32, y: f32, z: f32 };
pub const Edge = extern struct { v: [2]u16 };
pub const Face = extern struct { plane: u16, side: u16, edge0: i32, nedges: i16, tex: i16, styles: [4]u8, light: i32 };
pub const Plane = extern struct { n: [3]f32, d: f32, type: i32 };
pub const Node = extern struct { plane: i32, kids: [2]u16, min: [3]i16, max: [3]i16, face0: u16, nfaces: u16 };
pub const Model = extern struct { min: [3]f32, max: [3]f32, org: [3]f32, nodes: [4]i32, nleafs: i32, face0: i32, nfaces: i32 };
pub const ClipNode = extern struct { plane: i32, kids: [2]i16 };
pub const Leaf = extern struct { ty: i32, vis: i32, min: [3]i16, max: [3]i16, mark0: u16, nmarks: u16, ambient: [4]u8 };
pub const Mesh = struct { v: []f32, i: []u32 };
pub const Trace = struct { frac: f32 = 1, n: Vec3 = Vec3.zero(), solid: bool = false, hit: bool = false };
pub const Box = struct { min: Vec3, max: Vec3 };

fn rd(comptime T: type, a: std.mem.Allocator, f: std.fs.File, l: Lump) ![]T {
    if (l.len == 0) return &[_]T{};
    const d = try a.alloc(T, @intCast(@divExact(l.len, @sizeOf(T)))); try f.seekTo(@intCast(l.ofs));
    return if (try f.read(std.mem.sliceAsBytes(d)) == l.len) d else error.Read;
}

fn spawn(a: std.mem.Allocator, f: std.fs.File, l: Lump) !?Vec3 {
    if (l.len == 0) return null;
    const d = try a.alloc(u8, @intCast(l.len)); defer a.free(d); try f.seekTo(@intCast(l.ofs)); _ = try f.read(d);
    var it = std.mem.splitScalar(u8, d, '\n'); var o: ?Vec3 = null;
    while (it.next()) |ln| {
        const t = std.mem.trim(u8, ln, " \t\r");
        if (std.mem.indexOf(u8, t, "{") != null) o = null;
        if (std.mem.indexOf(u8, t, "\"origin\"")) |_| if (std.mem.indexOf(u8, t, "\"")) |q1| if (std.mem.indexOfPos(u8, t, q1 + 1, "\"")) |q2| if (std.mem.indexOfPos(u8, t, q2 + 1, "\"")) |q3| if (std.mem.indexOfPos(u8, t, q3 + 1, "\"")) |q4| {
            var p = std.mem.splitScalar(u8, t[q3 + 1 .. q4], ' ');
            o = Vec3.new(std.fmt.parseFloat(f32, p.next() orelse continue) catch continue, std.fmt.parseFloat(f32, p.next() orelse continue) catch continue, std.fmt.parseFloat(f32, p.next() orelse continue) catch continue);
        };
        if (o != null and (std.mem.indexOf(u8, t, "\"info_player_start\"") != null or std.mem.indexOf(u8, t, "\"info_player_deathmatch\"") != null)) return o;
    }
    return null;
}

pub const BSP = struct {
    verts: []Vertex, edges: []Edge, sedges: []i32, faces: []Face, planes: []Plane, nodes: []Node, models: []Model, clips: []ClipNode, leafs: []Leaf, spawn: ?Vec3, a: std.mem.Allocator,

    pub fn deinit(self: *BSP) void {
        inline for (.{ self.verts, self.edges, self.sedges, self.faces, self.planes, self.nodes, self.models, self.clips, self.leafs }) |d| self.a.free(d);
    }

    pub fn load(a: std.mem.Allocator, path: []const u8) !BSP {
        const f = try std.fs.cwd().openFile(path, .{}); defer f.close(); var h: Header = undefined; _ = try f.read(std.mem.asBytes(&h));
        if (h.ver != 29) return error.BadVer;
        return .{ .verts = try rd(Vertex, a, f, h.lumps[3]), .edges = try rd(Edge, a, f, h.lumps[12]), .sedges = try rd(i32, a, f, h.lumps[13]), .faces = try rd(Face, a, f, h.lumps[7]), .planes = try rd(Plane, a, f, h.lumps[1]), .nodes = try rd(Node, a, f, h.lumps[5]), .models = try rd(Model, a, f, h.lumps[14]), .clips = try rd(ClipNode, a, f, h.lumps[9]), .leafs = try rd(Leaf, a, f, h.lumps[10]), .spawn = try spawn(a, f, h.lumps[0]), .a = a };
    }

    pub fn mesh(self: *const BSP, a: std.mem.Allocator) !Mesh {
        var v = std.ArrayListUnmanaged(f32){}; var idx = std.ArrayListUnmanaged(u32){}; var m = std.AutoHashMap(u16, u32).init(a); defer m.deinit();
        for (self.faces) |face| {
            var fv = std.ArrayListUnmanaged(u16){}; defer fv.deinit(a); var j: i32 = 0;
            while (j < face.nedges) : (j += 1) try fv.append(a, if (self.sedges[@intCast(face.edge0 + j)] > 0) self.edges[@intCast(self.sedges[@intCast(face.edge0 + j)])].v[0] else self.edges[@intCast(-self.sedges[@intCast(face.edge0 + j)])].v[1]);
            if (fv.items.len >= 3) for (fv.items[1 .. fv.items.len - 1], 0..) |v1, k| {
                for ([_]u16{ fv.items[0], v1, fv.items[k + 2] }) |vi| if (!m.contains(vi)) {
                    try m.put(vi, @intCast(m.count())); const vx = self.verts[vi]; try v.appendSlice(a, &[_]f32{ vx.x * 0.03125, vx.z * 0.03125, -vx.y * 0.03125 });
                };
                try idx.appendSlice(a, &[_]u32{ m.get(fv.items[0]).?, m.get(v1).?, m.get(fv.items[k + 2]).? });
            };
        }
        return .{ .v = try v.toOwnedSlice(a), .i = try idx.toOwnedSlice(a) };
    }

    pub fn trace(self: *const BSP, s: Vec3, e: Vec3, b: Box) Trace {
        var t = Trace{}; if (self.clips.len == 0) return t;
        const ext = Vec3.new((b.max.x() - b.min.x()) * 0.5, (b.max.y() - b.min.y()) * 0.5, (b.max.z() - b.min.z()) * 0.5);
        self.traceR(0, 0, 1, s, e, ext, &t); return t;
    }

    fn traceR(self: *const BSP, i: i32, sf: f32, ef: f32, s: Vec3, e: Vec3, ext: Vec3, t: *Trace) void {
        if (i < 0) { if (i != -1 and self.leafs.len > 0 and self.leafs[@intCast(-(i + 1))].ty == -2) t.solid = true; return; }
        const n = self.clips[@intCast(i)]; const p = self.planes[@intCast(n.plane)]; const off = @abs(ext.x() * p.n[0]) + @abs(ext.y() * p.n[1]) + @abs(ext.z() * p.n[2]);
        const ds = s.x() * p.n[0] + s.y() * p.n[1] + s.z() * p.n[2] - p.d; const de = e.x() * p.n[0] + e.y() * p.n[1] + e.z() * p.n[2] - p.d;
        if (ds >= off and de >= off) return self.traceR(n.kids[0], sf, ef, s, e, ext, t);
        if (ds < -off and de < -off) return self.traceR(n.kids[1], sf, ef, s, e, ext, t);
        const side: usize = if (ds < 0) 1 else 0; const d1 = if (ds >= 0) ds - off else ds + off; const d2 = if (de >= 0) de - off else de + off;
        var mf = sf; var m = s; if (d1 != d2 and (d1 >= 0) != (d2 >= 0)) { const f = d1 / (d1 - d2); mf = sf + (ef - sf) * f; m = s.add(e.sub(s).scale(f)); }
        self.traceR(n.kids[side], sf, mf, s, m, ext, t); if (t.solid) return;
        self.traceR(n.kids[1 - side], mf, ef, m, e, ext, t);
        if (t.solid and side == 0 and mf < t.frac) { t.frac = mf; t.n = Vec3.new(p.n[0], p.n[1], p.n[2]); t.hit = true; }
    }

    pub fn slide(self: *const BSP, p: Vec3, v: Vec3, dt: f32, b: Box) Vec3 {
        var pos = p; var vel = v; var t = dt;
        for (0..4) |_| {
            const d = pos.add(vel.scale(t)); const tr = self.trace(pos, d, b);
            if (tr.frac >= 1) return d; if (tr.solid and !tr.hit) return pos;
            pos = pos.add(d.sub(pos).scale(tr.frac));
            if (tr.hit) { const bk = vel.dot(tr.n); vel = Vec3.new(vel.x() - tr.n.x() * bk, vel.y() - tr.n.y() * bk, vel.z() - tr.n.z() * bk); }
            t *= 1 - tr.frac; if (t < 0.001) break;
        }
        return pos;
    }
};
