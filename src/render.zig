//------------------------------------------------------------------------------
//  render.zig - Minimalist 3D Rendering Engine with BSP Support
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;

const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

const bsp = @import("bsp.zig");

pub const Camera3D = @import("camera.zig").Camera3D;

pub const Vertex = extern struct { pos: [3]f32, col: [4]f32 };

pub const Mesh = struct {
    verts: []const Vertex,
    indices: []const u16,

    pub fn cube() Mesh {
        const v = [_]Vertex{
            .{ .pos = .{-1,-1,-1}, .col = .{1,0,0,1} }, .{ .pos = .{ 1,-1,-1}, .col = .{1,0,0,1} },
            .{ .pos = .{ 1, 1,-1}, .col = .{1,0,0,1} }, .{ .pos = .{-1, 1,-1}, .col = .{1,0,0,1} },
            .{ .pos = .{-1,-1, 1}, .col = .{0,1,0,1} }, .{ .pos = .{ 1,-1, 1}, .col = .{0,1,0,1} },
            .{ .pos = .{ 1, 1, 1}, .col = .{0,1,0,1} }, .{ .pos = .{-1, 1, 1}, .col = .{0,1,0,1} },
        };
        const i = [_]u16{ 0,1,2, 0,2,3, 6,5,4, 7,6,4, 0,3,7, 0,7,4, 1,5,6, 1,6,2, 3,2,6, 3,6,7, 0,4,5, 0,5,1 };
        return .{ .verts = &v, .indices = &i };
    }

    /// Create a mesh from BSP MeshData
    pub fn fromBspMesh(allocator: std.mem.Allocator, mesh_data: *const bsp.MeshData, color: [4]f32) !Mesh {
        const num_verts = mesh_data.vertices.len / 3;
        var verts = try allocator.alloc(Vertex, num_verts);

        var i: usize = 0;
        while (i < num_verts) : (i += 1) {
            verts[i] = .{
                .pos = .{
                    mesh_data.vertices[i*3],
                    mesh_data.vertices[i*3+1],
                    mesh_data.vertices[i*3+2]
                },
                .col = color,
            };
        }

        var indices_u16 = try allocator.alloc(u16, mesh_data.indices.len);
        for (mesh_data.indices, 0..) |idx, j| {
            indices_u16[j] = @intCast(idx);
        }

        return .{ .verts = verts, .indices = indices_u16 };
    }
};

pub const Renderer = struct {
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    pass: sg.PassAction,
    count: u32,
    index_type: sg.IndexType = .UINT16,

    pub fn init(mesh: Mesh, clear: [4]f32) Renderer {
        sg.setup(.{ .environment = sglue.environment(), .logger = .{ .func = sokol.log.func } });

        var r: Renderer = undefined;
        r.bind = .{};
        r.bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(mesh.verts) });
        r.bind.index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(mesh.indices) });
        r.pass = .{};
        r.pass.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = clear[0], .g = clear[1], .b = clear[2], .a = clear[3] } };
        r.count = @intCast(mesh.indices.len);
        r.index_type = .UINT16;
        return r;
    }

    /// Initialize renderer from BSP MeshData with u32 indices
    pub fn initFromBspMesh(mesh_data: *const bsp.MeshData, clear: [4]f32, color: [4]f32) !Renderer {
        sg.setup(.{ .environment = sglue.environment(), .logger = .{ .func = sokol.log.func } });

        const num_verts = mesh_data.vertices.len / 3;
        var verts = try mesh_data.allocator.alloc(Vertex, num_verts);
        defer mesh_data.allocator.free(verts);

        var i: usize = 0;
        while (i < num_verts) : (i += 1) {
            verts[i] = .{
                .pos = .{
                    mesh_data.vertices[i*3],
                    mesh_data.vertices[i*3+1],
                    mesh_data.vertices[i*3+2]
                },
                .col = color,
            };
        }

        var r: Renderer = undefined;
        r.bind = .{};
        r.bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(verts) });
        r.bind.index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(mesh_data.indices) });
        r.pass = .{};
        r.pass.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = clear[0], .g = clear[1], .b = clear[2], .a = clear[3] } };
        r.count = @intCast(mesh_data.indices.len);
        r.index_type = .UINT32;

        return r;
    }

    pub fn shader(self: *Renderer, desc: sg.ShaderDesc) void {
        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;

        self.pip = sg.makePipeline(.{
            .shader = sg.makeShader(desc),
            .layout = layout,
            .index_type = self.index_type,
            .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
            .cull_mode = .BACK,
        });
    }

    pub fn draw(self: Renderer, mvp: Mat4) void {
        sg.beginPass(.{ .action = self.pass, .swapchain = sglue.swapchain() });
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(0, sg.asRange(&mvp));
        sg.draw(0, self.count, 1);
        sg.endPass();
        sg.commit();
    }

    pub fn deinit(self: Renderer) void {
        if (self.bind.vertex_buffers[0].id != 0) {
            sg.destroyBuffer(self.bind.vertex_buffers[0]);
        }
        if (self.bind.index_buffer.id != 0) {
            sg.destroyBuffer(self.bind.index_buffer);
        }
        if (self.pip.id != 0) {
            sg.destroyPipeline(self.pip);
        }
        sg.shutdown();
    }
};
