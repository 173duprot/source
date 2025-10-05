const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;

const BSP_VERSION = 29;
const HEADER_LUMPS = 15;

pub const Lump = extern struct { offset: i32, length: i32 };
pub const Header = extern struct { version: i32, lumps: [HEADER_LUMPS]Lump };

pub const Vertex = extern struct {
    x: f32, y: f32, z: f32,
    pub fn toVec3(self: Vertex) Vec3 { return Vec3.new(self.x, self.y, self.z); }
};

pub const Edge = extern struct { v: [2]u16 };
pub const Face = extern struct {
    plane_id: u16, side: u16, first_edge: i32, num_edges: i16,
    texinfo_id: i16, styles: [4]u8, lightmap_offset: i32,
};
pub const Plane = extern struct { normal: [3]f32, dist: f32, type: i32 };
pub const Node = extern struct {
    plane_id: i32, front: u16, back: u16,
    bbox_min: [3]i16, bbox_max: [3]i16, face_id: u16, face_num: u16,
};
pub const Leaf = extern struct {
    type: i32, vislist: i32, bbox_min: [3]i16, bbox_max: [3]i16,
    lface_id: u16, lface_num: u16, snd_water: u8, snd_sky: u8, snd_slime: u8, snd_lava: u8,
};
pub const Model = extern struct {
    bbox_min: [3]f32, bbox_max: [3]f32, origin: [3]f32,
    node_id0: i32, node_id1: i32, node_id2: i32, node_id3: i32,
    numleafs: i32, face_id: i32, face_num: i32,
};

pub const SpawnPoint = struct { origin: Vec3, angle: f32 };

pub const BspData = struct {
    vertices: []Vertex, edges: []Edge, surfedges: []i32, faces: []Face,
    planes: []Plane, nodes: []Node, leaves: []Leaf, marksurfaces: []u16,
    models: []Model, spawn_point: ?SpawnPoint, allocator: std.mem.Allocator,

    pub fn deinit(self: *BspData) void {
        inline for (.{ self.vertices, self.edges, self.surfedges, self.faces,
                      self.planes, self.nodes, self.leaves, self.marksurfaces, self.models }) |data| {
            self.allocator.free(data);
        }
    }
};

pub const MeshData = struct {
    vertices: []f32, indices: []u32, allocator: std.mem.Allocator,
    pub fn deinit(self: *MeshData) void {
        self.allocator.free(self.vertices);
        self.allocator.free(self.indices);
    }
};

fn loadLump(comptime T: type, allocator: std.mem.Allocator, file: std.fs.File, lump: Lump) ![]T {
    if (lump.length == 0) return &[_]T{};
    const data = try allocator.alloc(T, @intCast(@divExact(lump.length, @sizeOf(T))));
    try file.seekTo(@intCast(lump.offset));
    if (try file.read(std.mem.sliceAsBytes(data)) != lump.length) return error.IncompleteRead;
    return data;
}

pub fn loadBsp(allocator: std.mem.Allocator, filepath: []const u8) !BspData {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var header: Header = undefined;
    _ = try file.read(std.mem.asBytes(&header));
    if (header.version != BSP_VERSION) return error.InvalidVersion;

    return .{
        .vertices = try loadLump(Vertex, allocator, file, header.lumps[3]),
        .edges = try loadLump(Edge, allocator, file, header.lumps[12]),
        .surfedges = try loadLump(i32, allocator, file, header.lumps[13]),
        .faces = try loadLump(Face, allocator, file, header.lumps[7]),
        .planes = try loadLump(Plane, allocator, file, header.lumps[1]),
        .nodes = try loadLump(Node, allocator, file, header.lumps[5]),
        .leaves = try loadLump(Leaf, allocator, file, header.lumps[10]),
        .marksurfaces = try loadLump(u16, allocator, file, header.lumps[11]),
        .models = try loadLump(Model, allocator, file, header.lumps[14]),
        .spawn_point = try parseSpawnPoint(allocator, file, header.lumps[0]),
        .allocator = allocator,
    };
}

fn parseSpawnPoint(allocator: std.mem.Allocator, file: std.fs.File, lump: Lump) !?SpawnPoint {
    if (lump.length == 0) return null;
    const data = try allocator.alloc(u8, @intCast(lump.length));
    defer allocator.free(data);
    try file.seekTo(@intCast(lump.offset));
    _ = try file.read(data);

    var origin: ?Vec3 = null;
    var angle: f32 = 0.0;
    var in_spawn = false;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.indexOf(u8, t, "\"classname\" \"info_player_start\"") != null) in_spawn = true
        else if (in_spawn and std.mem.indexOf(u8, t, "\"origin\"") != null) origin = parseValue(t, parseOrigin)
        else if (in_spawn and std.mem.indexOf(u8, t, "\"angle\"") != null) angle = parseValue(t, parseFloat) orelse 0.0
        else if (std.mem.eql(u8, t, "}") and in_spawn and origin != null) return .{ .origin = origin.?, .angle = angle };
    }
    return null;
}

fn parseValue(line: []const u8, comptime parseFn: anytype) @TypeOf(parseFn("")) {
    if (std.mem.indexOf(u8, line, "\"")) |q1|
        if (std.mem.indexOfPos(u8, line, q1 + 1, "\"")) |q2|
            if (std.mem.indexOfPos(u8, line, q2 + 1, "\"")) |q3|
                return parseFn(line[q2 + 1..q3]);
    return null;
}


fn parseFloat(s: []const u8) ?f32 { return std.fmt.parseFloat(f32, s) catch null; }

fn parseOrigin(coords: []const u8) ?Vec3 {
    var parts = std.mem.splitScalar(u8, coords, ' ');
    const x = std.fmt.parseFloat(f32, parts.next() orelse return null) catch return null;
    const y = std.fmt.parseFloat(f32, parts.next() orelse return null) catch return null;
    const z = std.fmt.parseFloat(f32, parts.next() orelse return null) catch return null;
    return Vec3.new(x, y, z);
}

pub fn bspToMesh(allocator: std.mem.Allocator, bsp: *const BspData) !MeshData {
    var verts = std.ArrayListUnmanaged(f32){};
    var indices = std.ArrayListUnmanaged(u32){};
    var vmap = std.AutoHashMap(u16, u32).init(allocator);
    defer vmap.deinit();

    const scale: f32 = 0.03125;

    for (bsp.faces) |face| {
        var face_verts = std.ArrayListUnmanaged(u16){};
        defer face_verts.deinit(allocator);

        var i: i32 = 0;
        while (i < face.num_edges) : (i += 1) {
            const se = bsp.surfedges[@intCast(face.first_edge + i)];
            const edge = bsp.edges[@intCast(@abs(se))];
            try face_verts.append(allocator, if (se > 0) edge.v[0] else edge.v[1]);
        }

        if (face_verts.items.len >= 3) {
            const v0 = face_verts.items[0];
            for (face_verts.items[1..face_verts.items.len - 1], 0..) |v1, j| {
                const v2 = face_verts.items[j + 2];
                for ([_]u16{ v0, v1, v2 }) |vi| {
                    if (!vmap.contains(vi)) {
                        try vmap.put(vi, @intCast(vmap.count()));
                        const v = bsp.vertices[vi];
                        try verts.appendSlice(allocator, &[_]f32{ v.x * scale, v.z * scale, -v.y * scale });
                    }
                }
                try indices.appendSlice(allocator, &[_]u32{ vmap.get(v0).?, vmap.get(v1).?, vmap.get(v2).? });
            }
        }
    }

    return .{ .vertices = try verts.toOwnedSlice(allocator), .indices = try indices.toOwnedSlice(allocator), .allocator = allocator };
}
