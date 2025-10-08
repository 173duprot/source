const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const r = @import("render.zig");
const shd = @import("shaders/cube.glsl.zig");
const input = @import("input.zig");
const physics = @import("physics.zig");
const bsp = @import("bsp.zig");

const App = struct {
    renderer: r.Renderer, camera: r.Camera3D, io: input.IO = .{}, physics: physics.Physics = .{},
    bsp_data: ?bsp.BSP = null, mesh_data: ?bsp.Mesh = null, a: std.mem.Allocator,

    fn init(a: std.mem.Allocator) !App {
        var self = App{ .renderer = undefined, .camera = r.Camera3D.init(Vec3.new(0, 1, 6), 0.0, 0.0, 60.0), .a = a };

        var data = try bsp.BSP.load(a, "src/maps/base.bsp");
        errdefer data.deinit();
        const mesh = try data.mesh(a);

        self.bsp_data = data; self.mesh_data = mesh;
        self.renderer = try r.Renderer.initFromBsp(a, &mesh, .{ 0.1, 0.1, 0.15, 1.0 }, .{ 0.7, 0.7, 0.8, 1.0 });

        if (data.spawn) |spawn| {
            const s = 0.03125;
            self.camera = r.Camera3D.init(Vec3.new(spawn.x() * s, spawn.z() * s, -spawn.y() * s), 0.0, 0.0, 60.0);
            std.debug.print("Spawned at: ({d:.2}, {d:.2}, {d:.2})\n", .{ spawn.x(), spawn.y(), spawn.z() });
        }

        std.debug.print("Loaded BSP: {} vertices, {} faces\n", .{ data.verts.len, data.faces.len });
        self.renderer.shader(shd.cubeShaderDesc(sokol.gfx.queryBackend()));
        return self;
    }

    fn update(self: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        const spd: f32 = 0.1 * dt * 60;
        const mv = self.io.vec2(.a, .d, .s, .w);

        if (mv.x != 0) self.camera.move(Vec3.new(self.camera.right().x(), 0, self.camera.right().z()).norm().scale(mv.x * spd));
        if (mv.y != 0) self.camera.move(Vec3.new(self.camera.forward().x(), 0, self.camera.forward().z()).norm().scale(mv.y * spd));

        self.physics.update(&self.camera.position, dt);
        if (self.io.justPressed(.space)) self.physics.jump(5.0);
        if (self.io.mouse.isLocked()) self.camera.look(self.io.mouse.dx * 0.002, -self.io.mouse.dy * 0.002);
        if (self.io.justPressed(.escape)) self.io.mouse.unlock();
        if (self.io.mouse.left and !self.io.mouse.isLocked()) self.io.mouse.lock();
    }

    fn render(self: *App) void {
        const mvp = Mat4.mul(Mat4.mul(
            self.camera.projectionMatrix(sapp.widthf() / sapp.heightf(), 0.1, 1000.0),
            self.camera.viewMatrix()
        ), Mat4.identity());
        self.renderer.draw(mvp);
    }

    fn deinit(self: *App) void {
        if (self.mesh_data) |m| { self.a.free(m.v); self.a.free(m.i); }
        if (self.bsp_data) |*b| b.deinit();
        self.renderer.deinit();
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var app: App = undefined;

export fn init() void { app = App.init(gpa.allocator()) catch unreachable; }
export fn frame() void { app.update(); app.render(); app.io.cleanInput(); }
export fn cleanup() void { app.deinit(); _ = gpa.deinit(); }
export fn event(ev: [*c]const sapp.Event) void { app.io.update(ev); }

pub fn main() void {
    sapp.run(.{
        .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .event_cb = event,
        .width = 800, .height = 600, .sample_count = 4, .icon = .{ .sokol_default = true },
        .window_title = "BSP Viewer", .logger = .{ .func = sokol.log.func },
    });
}
