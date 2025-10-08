const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

const rend = @import("render.zig");
const shade = @import("shaders/cube.glsl.zig");
const input = @import("input.zig");
const physics = @import("physics.zig");
const bsp = @import("bsp.zig");

const App = struct {
    renderer: rend.Renderer,
    camera: rend.Camera3D,
    io: input.IO = .{},
    physics: physics.Physics = .{},
    bsp_data: ?bsp.BSP = null,
    mesh_data: ?bsp.Mesh = null,
    a: std.mem.Allocator,

    fn init(a: std.mem.Allocator) !App {
        var self = App{
            .renderer = undefined,
            .camera = rend.Camera3D.init(Vec3.new(0, 1, 6), 0.0, 0.0, 60.0),
            .a = a,
        };

        var data = try bsp.BSP.load(a, @embedFile("maps/base.bsp"));
        std.log.info("BSP data size: {} bytes", .{@embedFile("maps/base.bsp").len});
        errdefer data.deinit();
        const mesh = try data.mesh(a);

        self.bsp_data = data;
        self.mesh_data = mesh;
        self.renderer = try rend.Renderer.initFromBsp(a, &mesh, .{ 0.1, 0.1, 0.15, 1.0 }, .{ 0.7, 0.7, 0.8, 1.0 });

        // Set spawn position AFTER creating renderer
        if (data.spawn) |spawn| {
            const scale = 0.03125;
            const spawn_x = spawn.x() * scale;
            const spawn_y = spawn.z() * scale;
            const spawn_z = -spawn.y() * scale;

            std.debug.print("Raw spawn: ({d:.2}, {d:.2}, {d:.2})\n", .{ spawn.x(), spawn.y(), spawn.z() });
            std.debug.print("Scaled spawn: ({d:.2}, {d:.2}, {d:.2})\n", .{ spawn_x, spawn_y, spawn_z });

            self.camera = rend.Camera3D.init(Vec3.new(spawn_x, spawn_y, spawn_z), 0.0, 0.0, 60.0);
            self.physics.grounded = true; // Prevent initial fall
        } else {
            std.debug.print("WARNING: No spawn point found in BSP!\n", .{});
        }

        std.debug.print("Loaded BSP: {} vertices, {} faces\n", .{ data.verts.len, data.faces.len });
        std.debug.print("Camera position: ({d:.2}, {d:.2}, {d:.2})\n", .{ self.camera.position.x(), self.camera.position.y(), self.camera.position.z() });

        self.renderer.shader(shade.cubeShaderDesc(sokol.gfx.queryBackend()));
        return self;
    }

    fn update(self: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        const spd: f32 = 0.1 * dt * 60;
        const mv = self.io.vec2(.a, .d, .s, .w);

        if (mv.x != 0) {
            const right = self.camera.right();
            const move_right = Vec3.new(right.x(), 0, right.z()).norm().scale(mv.x * spd);
            self.camera.move(move_right);
        }
        if (mv.y != 0) {
            const forward = self.camera.forward();
            const move_forward = Vec3.new(forward.x(), 0, forward.z()).norm().scale(mv.y * spd);
            self.camera.move(move_forward);
        }

        self.physics.update(&self.camera.position, dt);
        if (self.io.justPressed(.space)) self.physics.jump(5.0);
        if (self.io.mouse.isLocked()) self.camera.look(self.io.mouse.dx * 0.002, -self.io.mouse.dy * 0.002);
        if (self.io.justPressed(.escape)) self.io.mouse.unlock();
        if (self.io.mouse.left and !self.io.mouse.isLocked()) self.io.mouse.lock();
    }

    fn render(self: *App) void {
        const aspect = sapp.widthf() / sapp.heightf();
        const proj = self.camera.projectionMatrix(aspect, 0.1, 1000.0);
        const view = self.camera.viewMatrix();
        const mvp = Mat4.mul(Mat4.mul(proj, view), Mat4.identity());
        self.renderer.draw(mvp);
    }

    fn deinit(self: *App) void {
        if (self.mesh_data) |m| {
            self.a.free(m.v);
            self.a.free(m.i);
        }
        if (self.bsp_data) |*b| b.deinit();
        self.renderer.deinit();
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var app: App = undefined;

export fn init() void {
    app = App.init(gpa.allocator()) catch unreachable;
}

export fn frame() void {
    app.update();
    app.render();
    app.io.cleanInput();
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
