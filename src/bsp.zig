const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;

const Lump = extern struct { ofs: i32, len: i32 };
const Header = extern struct { ver: i32, lumps: [15]Lump };

pub const Vertex = extern struct { x: f32, y: f32, z: f32 };
pub const Edge = extern struct { v: [2]u16 };
pub const Face = extern struct {
    plane: u16, side: u16, edge0: i32, nedges: i16,
    tex: i16, styles: [4]u8, light: i32,
};
pub const Plane = extern struct { n: [3]f32, d: f32, type: i32 };
pub const Node = extern struct { plane: i32, kids: [2]u16, min: [3]i16, max: [3]i16, face0: u16, nfaces: u16 };
pub const Model = extern struct { min: [3]f32, max: [3]f32, org: [3]f32, nodes: [4]i32, nleafs: i32, face0: i32, nfaces: i32 };

pub const Mesh = struct { v: []f32, i: []u32 };

pub const BSP = struct {
    verts: []Vertex, edges: []Edge, sedges: []i32, faces: []Face,
    planes: []Plane, nodes: []Node, models: []Model, spawn: ?Vec3, a: std.mem.Allocator,

    pub fn deinit(self: *BSP) void {
        inline for (.{ self.verts, self.edges, self.sedges, self.faces, self.planes, self.nodes, self.models }) |d|
            self.a.free(d);
    }

    pub fn load(a: std.mem.Allocator, path: []const u8) !BSP {
        const f = try std.fs.cwd().openFile(path, .{});
        defer f.close();

        var h: Header = undefined;
        _ = try f.read(std.mem.asBytes(&h));
        if (h.ver != 29) return error.BadVer;

        return .{
            .verts = try rd(Vertex, a, f, h.lumps[3]),
            .edges = try rd(Edge, a, f, h.lumps[12]),
            .sedges = try rd(i32, a, f, h.lumps[13]),
            .faces = try rd(Face, a, f, h.lumps[7]),
            .planes = try rd(Plane, a, f, h.lumps[1]),
            .nodes = try rd(Node, a, f, h.lumps[5]),
            .models = try rd(Model, a, f, h.lumps[14]),
            .spawn = try getSpawn(a, f, h.lumps[0]),
            .a = a,
        };
    }

    pub fn mesh(self: *const BSP, a: std.mem.Allocator) !Mesh {
        var v = std.ArrayListUnmanaged(f32){};
        var idx = std.ArrayListUnmanaged(u32){};
        var m = std.AutoHashMap(u16, u32).init(a);
        defer m.deinit();

        for (self.faces) |face| {
            var fv = std.ArrayListUnmanaged(u16){};
            defer fv.deinit(a);

            var j: i32 = 0;
            while (j < face.nedges) : (j += 1) {
                const se = self.sedges[@intCast(face.edge0 + j)];
                const e = self.edges[@intCast(@abs(se))];
                try fv.append(a, if (se > 0) e.v[0] else e.v[1]);
            }

            if (fv.items.len >= 3) {
                const v0 = fv.items[0];
                for (fv.items[1..fv.items.len - 1], 0..) |v1, k| {
                    const v2 = fv.items[k + 2];
                    for ([_]u16{ v0, v1, v2 }) |vi| {
                        if (!m.contains(vi)) {
                            try m.put(vi, @intCast(m.count()));
                            const vx = self.verts[vi];
                            try v.appendSlice(a, &[_]f32{ vx.x * 0.03125, vx.z * 0.03125, -vx.y * 0.03125 });
                        }
                    }
                    try idx.appendSlice(a, &[_]u32{ m.get(v0).?, m.get(v1).?, m.get(v2).? });
                }
            }
        }
        return .{ .v = try v.toOwnedSlice(a), .i = try idx.toOwnedSlice(a) };
    }
};

fn rd(comptime T: type, a: std.mem.Allocator, f: std.fs.File, l: Lump) ![]T {
    if (l.len == 0) return &[_]T{};
    const d = try a.alloc(T, @intCast(@divExact(l.len, @sizeOf(T))));
    try f.seekTo(@intCast(l.ofs));
    if (try f.read(std.mem.sliceAsBytes(d)) != l.len) return error.Read;
    return d;
}

fn getSpawn(a: std.mem.Allocator, f: std.fs.File, l: Lump) !?Vec3 {
    if (l.len == 0) return null;
    const d = try a.alloc(u8, @intCast(l.len));
    defer a.free(d);
    try f.seekTo(@intCast(l.ofs));
    _ = try f.read(d);

    var in = false;
    var it = std.mem.splitScalar(u8, d, '\n');
    while (it.next()) |ln| {
        const t = std.mem.trim(u8, ln, " \t\r");
        if (std.mem.indexOf(u8, t, "\"classname\" \"info_player_start\"") != null) in = true
        else if (in and std.mem.indexOf(u8, t, "\"origin\"") != null) {
            if (std.mem.indexOf(u8, t, "\"")) |q1|
                if (std.mem.indexOfPos(u8, t, q1 + 1, "\"")) |q2|
                    if (std.mem.indexOfPos(u8, t, q2 + 1, "\"")) |q3| {
                        var p = std.mem.splitScalar(u8, t[q2 + 1..q3], ' ');
                        const x = std.fmt.parseFloat(f32, p.next() orelse continue) catch continue;
                        const y = std.fmt.parseFloat(f32, p.next() orelse continue) catch continue;
                        const z = std.fmt.parseFloat(f32, p.next() orelse continue) catch continue;
                        return Vec3.new(x, y, z);
                    };
        }
    }
    return null;
}
