const sokol = @import("sokol");
const sapp = sokol.app;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const r = @import("render.zig");
const shd = @import("shaders/cube.glsl.zig");
const input = @import("input.zig");
const physics = @import("physics.zig");

const App = struct {
    renderer: r.Renderer,
    camera: r.Camera3D,
    io: input.IO = .{},
    angle: f32 = 0.0,
    physics: physics.Physics = .{},

    fn init() App {
        var self = App{
            .renderer = r.Renderer.init(r.Mesh.cube(), .{ 0.25, 0.5, 0.75, 1.0 }),
            .camera = r.Camera3D.init(Vec3.new(0, 1, 6), Vec3.new(0, 1, 0), 60.0),
        };
        self.renderer.shader(shd.cubeShaderDesc(sokol.gfx.queryBackend()));
        return self;
    }

    fn update(self: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        self.angle += dt * 60;

        // Camera movement - horizontal only (don't affect Y)
        const speed: f32 = 0.1 * dt * 60;
        const move = self.io.vec2(.a, .d, .s, .w);

        if (move.x != 0) {
            const right = self.camera.right();
            const offset = Vec3.new(right.x(), 0, right.z()).norm().scale(move.x * speed);
            self.camera.translate(offset);
        }
        if (move.y != 0) {
            const forward = self.camera.forward();
            const offset = Vec3.new(forward.x(), 0, forward.z()).norm().scale(move.y * speed);
            self.camera.translate(offset);
        }

        // Physics update
        self.physics.update(&self.camera.position, dt);

        // Jump input
        if (self.io.justPressed(.space)) {
            self.physics.jump(20.0);
        }

        // Mouse look
        if (self.io.mouse.isLocked()) {
            self.camera.rotate(Vec3.up(), -self.io.mouse.dx * 0.002, self.camera.position);
            self.camera.rotate(self.camera.right(), -self.io.mouse.dy * 0.002, self.camera.position);
        }

        if (self.io.justPressed(.escape)) self.io.mouse.unlock();
        if (self.io.mouse.left and !self.io.mouse.isLocked()) self.io.mouse.lock();
    }

    fn render(self: *App) void {
        const aspect = sapp.widthf() / sapp.heightf();
        const mvp = Mat4.mul(Mat4.mul(
            self.camera.projectionMatrix(aspect, 0.1, 100.0),
            self.camera.viewMatrix()),
            Mat4.fromRotation(self.angle, Vec3.new(0.5, 1, 0).norm())
        );
        self.renderer.draw(mvp);
        self.io.cleanInput();
    }

    fn deinit(self: *App) void {
        self.renderer.deinit();
    }
};

var app: App = undefined;

export fn init() void { app = App.init(); }
export fn frame() void { app.update(); app.render(); }
export fn cleanup() void { app.deinit(); }
export fn event(ev: [*c]const sapp.Event) void { app.io.update(ev); }

pub fn main() void {
    sapp.run(.{
        .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .event_cb = event,
        .width = 800, .height = 600, .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "Camera3D Demo",
        .logger = .{ .func = sokol.log.func },
    });
}
