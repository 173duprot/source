//------------------------------------------------------------------------------
//  render.zig - Minimalist 3D Rendering Engine
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;

const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

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
};

pub const Renderer = struct {
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    pass: sg.PassAction,
    count: u32,

    pub fn init(mesh: Mesh, clear: [4]f32) Renderer {
        sg.setup(.{ .environment = sglue.environment(), .logger = .{ .func = sokol.log.func } });

        var r: Renderer = undefined;
        r.bind = .{};
        r.bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(mesh.verts) });
        r.bind.index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(mesh.indices) });
        r.pass = .{};
        r.pass.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = clear[0], .g = clear[1], .b = clear[2], .a = clear[3] } };
        r.count = @intCast(mesh.indices.len);
        return r;
    }

    pub fn shader(self: *Renderer, desc: sg.ShaderDesc) void {
        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;

        self.pip = sg.makePipeline(.{
            .shader = sg.makeShader(desc),
            .layout = layout,
            .index_type = .UINT16,
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

    pub fn deinit(_: Renderer) void {
        sg.shutdown();
    }
};
