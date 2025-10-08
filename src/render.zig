const std = @import("std");
const sokol = @import("sokol");
    const sg = sokol.gfx;
    const sglue = sokol.glue;
const za = @import("zalgebra");
    const Vec3 = za.Vec3;
    const Mat4 = za.Mat4;
const map = @import("map.zig");

pub const Camera3D = struct {
    position: Vec3, yaw: f32, pitch: f32, fov: f32,

    pub fn init(position: Vec3, yaw: f32, pitch: f32, fov: f32) Camera3D {
        return .{ .position = position, .yaw = yaw, .pitch = pitch, .fov = fov };
    }

    pub fn forward(self: Camera3D) Vec3 {
        return Vec3.new(@cos(self.pitch) * @cos(self.yaw), @sin(self.pitch), @cos(self.pitch) * @sin(self.yaw));
    }

    pub fn right(self: Camera3D) Vec3 { return self.forward().cross(Vec3.up()).norm(); }
    pub fn move(self: *Camera3D, offset: Vec3) void { self.position = self.position.add(offset); }

    pub fn look(self: *Camera3D, dyaw: f32, dpitch: f32) void {
        self.yaw += dyaw;
        self.pitch = std.math.clamp(self.pitch + dpitch, -std.math.pi / 2.0 + 0.01, std.math.pi / 2.0 - 0.01);
    }

    pub fn viewMatrix(self: Camera3D) Mat4 {
        return za.lookAt(self.position, self.position.add(self.forward()), Vec3.up());
    }

    pub fn projectionMatrix(self: Camera3D, aspect: f32, near: f32, far: f32) Mat4 {
        return za.perspective(self.fov, aspect, near, far);
    }
};

pub const Vertex = extern struct { pos: [3]f32, col: [4]f32 };

pub const Renderer = struct {
    pip: sg.Pipeline = .{}, bind: sg.Bindings = .{}, pass: sg.PassAction, count: u32, itype: sg.IndexType,

    pub fn init(v: []const Vertex, i: []const u16, clr: [4]f32) Renderer {
        sg.setup(.{ .environment = sglue.environment(), .logger = .{ .func = sokol.log.func } });
        return .{
            .bind = .{
                .vertex_buffers = .{ sg.makeBuffer(.{ .data = sg.asRange(v) }), .{}, .{}, .{}, .{}, .{}, .{}, .{} },
                .index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(i) }),
            },
            .pass = .{ .colors = .{ .{ .load_action = .CLEAR, .clear_value = .{ .r = clr[0], .g = clr[1], .b = clr[2], .a = clr[3] } }, .{}, .{}, .{}, .{}, .{}, .{}, .{} } },
            .count = @intCast(i.len),
            .itype = .UINT16,
        };
    }

    pub fn initFromBsp(a: std.mem.Allocator, md: *const map.Mesh, clr: [4]f32, col: [4]f32) !Renderer {
        sg.setup(.{ .environment = sglue.environment(), .logger = .{ .func = sokol.log.func } });
        const v = try a.alloc(Vertex, md.v.len / 3); defer a.free(v);
        for (v, 0..) |*vx, i| vx.* = .{ .pos = .{ md.v[i * 3], md.v[i * 3 + 1], md.v[i * 3 + 2] }, .col = col };
        return .{
            .bind = .{
                .vertex_buffers = .{ sg.makeBuffer(.{ .data = sg.asRange(v) }), .{}, .{}, .{}, .{}, .{}, .{}, .{} },
                .index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(md.i) }),
            },
            .pass = .{ .colors = .{ .{ .load_action = .CLEAR, .clear_value = .{ .r = clr[0], .g = clr[1], .b = clr[2], .a = clr[3] } }, .{}, .{}, .{}, .{}, .{}, .{}, .{} } },
            .count = @intCast(md.i.len),
            .itype = .UINT32,
        };
    }

    pub fn shader(self: *Renderer, desc: sg.ShaderDesc) void {
        var l = sg.VertexLayoutState{};
        l.attrs[0].format = .FLOAT3; l.attrs[1].format = .FLOAT4;
        self.pip = sg.makePipeline(.{ .shader = sg.makeShader(desc), .layout = l, .index_type = self.itype, .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true }, .cull_mode = .BACK });
    }

    pub fn draw(self: Renderer, mvp: Mat4) void {
        sg.beginPass(.{ .action = self.pass, .swapchain = sglue.swapchain() });
        sg.applyPipeline(self.pip); sg.applyBindings(self.bind);
        sg.applyUniforms(0, sg.asRange(&mvp));
        sg.draw(0, self.count, 1);
        sg.endPass(); sg.commit();
    }

    pub fn deinit(self: Renderer) void {
        if (self.bind.vertex_buffers[0].id != 0) sg.destroyBuffer(self.bind.vertex_buffers[0]);
        if (self.bind.index_buffer.id != 0) sg.destroyBuffer(self.bind.index_buffer);
        if (self.pip.id != 0) sg.destroyPipeline(self.pip);
        sg.shutdown();
    }
};
