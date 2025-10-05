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
    renderer: r.Renderer,
    camera: r.Camera3D,
    io: input.IO = .{},
    angle: f32 = 0.0,
    physics: physics.Physics = .{},
    bsp_data: ?bsp.BspData = null,
    mesh_data: ?bsp.MeshData = null,
    allocator: std.mem.Allocator,

    fn init(a: std.mem.Allocator) !App {
        var self = App{ .renderer = undefined, .camera = r.Camera3D.init(Vec3.new(0, 1, 6), 0.0, 0.0, 60.0), .allocator = a };

        if (loadBsp(a, "src/maps/base.bsp")) |loaded| {
            self.bsp_data = loaded.bsp;
            self.mesh_data = loaded.mesh;
            self.renderer = try r.Renderer.initFromBsp(a, &self.mesh_data.?, .{ 0.1, 0.1, 0.15, 1.0 }, .{ 0.7, 0.7, 0.8, 1.0 });

            if (loaded.bsp.spawn_point) |spawn| {
                const s = 0.03125;
                self.camera = r.Camera3D.init(Vec3.new(spawn.origin.x() * s, spawn.origin.z() * s, -spawn.origin.y() * s), std.math.degreesToRadians(spawn.angle), 0.0, 60.0);
                std.debug.print("Spawned at: ({d:.2}, {d:.2}, {d:.2}) facing {d:.1}°\n", .{ spawn.origin.x(), spawn.origin.y(), spawn.origin.z(), spawn.angle });
            }
            std.debug.print("Loaded BSP: {} vertices, {} faces\n", .{ loaded.bsp.vertices.len, loaded.bsp.faces.len });
        } else |err| {
            std.debug.print("Failed to load BSP ({}), using cube\n", .{err});
            self.renderer = r.Renderer.init(r.Mesh.cube(), .{ 0.25, 0.5, 0.75, 1.0 });
        }

        self.renderer.shader(shd.cubeShaderDesc(sokol.gfx.queryBackend()));
        return self;
    }

    fn loadBsp(a: std.mem.Allocator, path: []const u8) !struct { bsp: bsp.BspData, mesh: bsp.MeshData } {
        var data = try bsp.loadBsp(a, path);
        errdefer data.deinit();
        return .{ .bsp = data, .mesh = try bsp.bspToMesh(a, &data) };
    }

    fn update(self: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        if (self.bsp_data == null) self.angle += dt * 60;

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
            self.camera.viewMatrix()),
            if (self.bsp_data != null) Mat4.identity() else Mat4.fromRotation(self.angle, Vec3.new(0.5, 1, 0).norm())
        );
        self.renderer.draw(mvp);
        self.io.cleanInput();
    }

    fn deinit(self: *App) void {
        if (self.mesh_data) |*m| m.deinit();
        if (self.bsp_data) |*b| b.deinit();
        self.renderer.deinit();
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var app: App = undefined;

export fn init() void {
    const a = gpa.allocator();
    app = App.init(a) catch |err| blk: {
        std.debug.print("Failed to initialize app: {}\n", .{err});
        var fallback = App{ .renderer = r.Renderer.init(r.Mesh.cube(), .{ 0.25, 0.5, 0.75, 1.0 }), .camera = r.Camera3D.init(Vec3.new(0, 1, 6), 0.0, 0.0, 60.0), .allocator = a };
        fallback.renderer.shader(shd.cubeShaderDesc(sokol.gfx.queryBackend()));
        break :blk fallback;
    };
}

export fn frame() void {
    app.update();
    app.render();
}

export fn cleanup() void {
    app.deinit();
    _ = gpa.deinit();
}

export fn event(ev: [*c]const sapp.Event) void {
    app.io.update(ev);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "BSP Viewer",
        .logger = .{ .func = sokol.log.func },
    });
}
