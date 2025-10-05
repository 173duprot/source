const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;

// BSP version constant
const BSP_VERSION = 29; // 0x1D for Quake 1

// Lump indices
const LUMP_ENTITIES = 0;
const LUMP_PLANES = 1;
const LUMP_TEXTURES = 2;
const LUMP_VERTICES = 3;
const LUMP_VISIBILITY = 4;
const LUMP_NODES = 5;
const LUMP_TEXINFO = 6;
const LUMP_FACES = 7;
const LUMP_LIGHTING = 8;
const LUMP_CLIPNODES = 9;
const LUMP_LEAVES = 10;
const LUMP_MARKSURFACES = 11;
const LUMP_EDGES = 12;
const LUMP_SURFEDGES = 13;
const LUMP_MODELS = 14;
const HEADER_LUMPS = 15;

pub const BspHeader = extern struct {
    version: i32,
};

pub const BspLump = extern struct {
    offset: i32,
    length: i32,
};

pub const BspVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn toVec3(self: BspVertex) Vec3 {
        return Vec3.new(self.x, self.y, self.z);
    }
};

pub const BspEdge = extern struct {
    v: [2]u16,
};

pub const BspPlane = extern struct {
    normal: [3]f32,
    dist: f32,
    type: i32,
};

pub const BspFace = extern struct {
    plane_id: u16,
    side: u16,
    first_edge: i32,
    num_edges: i16,
    texinfo_id: i16,
    typelight: u8,
    baselight: u8,
    light: [2]u8,
    lightmap: i32,
};

pub const BspNode = extern struct {
    plane_id: i32,
    children: [2]i16, // negative means leaf index
    min: [3]i16,
    max: [3]i16,
    face_id: u16,
    face_num: u16,
};

pub const BspLeaf = extern struct {
    type: i32,
    vislist: i32,
    min: [3]i16,
    max: [3]i16,
    lface_id: u16,
    lface_num: u16,
    sndwater: u8,
    sndsky: u8,
    sndslime: u8,
    sndlava: u8,
};

pub const BspModel = extern struct {
    bound_min: [3]f32,
    bound_max: [3]f32,
    origin: [3]f32,
    node_id0: i32,
    node_id1: i32,
    node_id2: i32,
    node_id3: i32,
    numleafs: i32,
    face_id: i32,
    face_num: i32,
};

pub const BspData = struct {
    vertices: []BspVertex,
    edges: []BspEdge,
    surfedges: []i32,
    faces: []BspFace,
    planes: []BspPlane,
    nodes: []BspNode,
    leaves: []BspLeaf,
    models: []BspModel,
    marksurfaces: []u16,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BspData) void {
        self.allocator.free(self.vertices);
        self.allocator.free(self.edges);
        self.allocator.free(self.surfedges);
        self.allocator.free(self.faces);
        self.allocator.free(self.planes);
        self.allocator.free(self.nodes);
        self.allocator.free(self.leaves);
        self.allocator.free(self.models);
        self.allocator.free(self.marksurfaces);
    }
};

pub const MeshData = struct {
    vertices: []f32,
    indices: []u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MeshData) void {
        self.allocator.free(self.vertices);
        self.allocator.free(self.indices);
    }
};

pub fn loadBsp(allocator: std.mem.Allocator, filepath: []const u8) !BspData {
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var header: BspHeader = undefined;
    _ = try file.read(std.mem.asBytes(&header));

    if (header.version != BSP_VERSION) {
        return error.InvalidBspVersion;
    }

    var lumps: [HEADER_LUMPS]BspLump = undefined;
    _ = try file.read(std.mem.sliceAsBytes(&lumps));

    const vertices = try loadLump(BspVertex, allocator, file, lumps[LUMP_VERTICES]);
    errdefer allocator.free(vertices);

    const edges = try loadLump(BspEdge, allocator, file, lumps[LUMP_EDGES]);
    errdefer allocator.free(edges);

    const surfedges = try loadLump(i32, allocator, file, lumps[LUMP_SURFEDGES]);
    errdefer allocator.free(surfedges);

    const faces = try loadLump(BspFace, allocator, file, lumps[LUMP_FACES]);
    errdefer allocator.free(faces);

    const planes = try loadLump(BspPlane, allocator, file, lumps[LUMP_PLANES]);
    errdefer allocator.free(planes);

    const nodes = try loadLump(BspNode, allocator, file, lumps[LUMP_NODES]);
    errdefer allocator.free(nodes);

    const leaves = try loadLump(BspLeaf, allocator, file, lumps[LUMP_LEAVES]);
    errdefer allocator.free(leaves);

    const models = try loadLump(BspModel, allocator, file, lumps[LUMP_MODELS]);
    errdefer allocator.free(models);

    const marksurfaces = try loadLump(u16, allocator, file, lumps[LUMP_MARKSURFACES]);
    errdefer allocator.free(marksurfaces);

    return BspData{
        .vertices = vertices,
        .edges = edges,
        .surfedges = surfedges,
        .faces = faces,
        .planes = planes,
        .nodes = nodes,
        .leaves = leaves,
        .models = models,
        .marksurfaces = marksurfaces,
        .allocator = allocator,
    };
}

fn loadLump(comptime T: type, allocator: std.mem.Allocator, file: std.fs.File, lump: BspLump) ![]T {
    if (lump.length == 0) return &[_]T{};

    const count = @divExact(lump.length, @sizeOf(T));
    const data = try allocator.alloc(T, @intCast(count));

    try file.seekTo(@intCast(lump.offset));
    const bytes_read = try file.read(std.mem.sliceAsBytes(data));

    if (bytes_read != lump.length) {
        allocator.free(data);
        return error.IncompleteRead;
    }

    return data;
}

pub fn bspToMesh(allocator: std.mem.Allocator, bsp: *const BspData) !MeshData {
    var verts = try std.ArrayList(f32).initCapacity(allocator, bsp.vertices.len * 3);
    defer verts.deinit(allocator);
    var indices = try std.ArrayList(u32).initCapacity(allocator, bsp.faces.len * 3);
    defer indices.deinit(allocator);

    var vmap = std.AutoHashMap(u16, u32).init(allocator);
    defer vmap.deinit();

    for (bsp.faces) |face| {
        var fv = try std.ArrayList(u16).initCapacity(allocator, @intCast(face.num_edges));
        defer fv.deinit(allocator);

        var i: i32 = 0;
        while (i < face.num_edges) : (i += 1) {
            const se = bsp.surfedges[@intCast(face.first_edge + i)];
            const ei: usize = @intCast(@abs(se));
            const edge = bsp.edges[ei];
            const vi = if (se > 0) edge.v[0] else edge.v[1];
            try fv.append(allocator, vi);
        }

        if (fv.items.len >= 3) {
            const v0 = fv.items[0];
            var j: usize = 1;
            while (j < fv.items.len - 1) : (j += 1) {
                const v1 = fv.items[j];
                const v2 = fv.items[j + 1];

                for ([_]u16{ v0, v1, v2 }) |vi| {
                    if (!vmap.contains(vi)) {
                        const idx: u32 = @intCast(vmap.count());
                        try vmap.put(vi, idx);
                        const v = bsp.vertices[vi];
                        try verts.append(allocator, v.x);
                        try verts.append(allocator, v.y);
                        try verts.append(allocator, v.z);
                    }
                }

                try indices.append(allocator, vmap.get(v0).?);
                try indices.append(allocator, vmap.get(v1).?);
                try indices.append(allocator, vmap.get(v2).?);
            }
        }
    }

    return MeshData{
        .vertices = try verts.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// Traversal helper
pub fn findLeaf(bsp: *const BspData, point: Vec3) ?*const BspLeaf {
    if (bsp.models.len == 0) return null;

    var node_idx = bsp.models[0].node_id0;

    while (node_idx >= 0) {
        const node = &bsp.nodes[@intCast(node_idx)];
        const plane = &bsp.planes[@intCast(node.plane_id)];

        const dist = point.x() * plane.normal[0] +
            point.y() * plane.normal[1] +
            point.z() * plane.normal[2] - plane.dist;

        node_idx = node.children[if (dist >= 0) 0 else 1];
    }

    const leaf_idx: usize = @intCast(~node_idx);
    if (leaf_idx < bsp.leaves.len) {
        return &bsp.leaves[leaf_idx];
    }
    return null;
}
