//------------------------------------------------------------------------------
//  main.zig
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sapp = sokol.app;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const render = @import("render.zig");
const shd = @import("shaders/cube.glsl.zig");
const input = @import("input.zig");

const State = struct {
    renderer: render.Renderer,
    camera: render.Camera3D,
    angle: f32 = 0.0,
    io: input.IO = .{},
};

var state: State = undefined;

export fn init() void {
    state = .{
        .renderer = render.Renderer.init(render.Mesh.cube(), .{ 0.25, 0.5, 0.75, 1.0 }),
        .camera = render.Camera3D.init(Vec3.new(0, 2, 6), Vec3.new(0, 0, 0), 60.0),
    };
    state.renderer.shader(shd.cubeShaderDesc(sokol.gfx.queryBackend()));
}

export fn frame() void {
    const dt: f32 = @floatCast(sapp.frameDuration() * 60);
    state.angle += 1.0 * dt;

    // Camera movement with WASD
    const speed: f32 = 0.1 * dt;
    const move = state.io.vec2(.a, .d, .s, .w);
    if (move.x != 0) state.camera.translate(state.camera.right().scale(move.x * speed));
    if (move.y != 0) state.camera.translate(state.camera.forward().scale(move.y * speed));

    // Vertical movement with Space/Shift (use left_shift specifically)
    const vertical = state.io.axis(.left_shift, .space);
    if (vertical != 0) state.camera.translate(Vec3.up().scale(vertical * speed));

    // Mouse look when locked - read deltas directly (auto-cleared each frame)
    if (state.io.mouse.isLocked()) {
        const sensitivity: f32 = 0.002;
        state.camera.rotate(Vec3.up(), -state.io.mouse.dx * sensitivity, state.camera.position);
        state.camera.rotate(state.camera.right(), -state.io.mouse.dy * sensitivity, state.camera.position);
    }

    // Toggle mouse lock: Escape to unlock, Left-click to lock
    if (state.io.justPressed(.escape)) {
        state.io.mouse.unlock();
    }
    if (state.io.mouse.left and !state.io.mouse.isLocked()) {
        state.io.mouse.lock();
    }

    // Render scene
    const aspect = sapp.widthf() / sapp.heightf();
    const model = Mat4.fromRotation(state.angle, Vec3.new(0.5, 1, 0).norm());
    const view = state.camera.viewMatrix();
    const proj = state.camera.projectionMatrix(aspect, 0.1, 100.0);
    const mvp = Mat4.mul(Mat4.mul(proj, view), model);

    state.renderer.draw(mvp);

    // Clear per-frame input at end of frame, after all logic has read it
    state.io.cleanInput();
}

export fn cleanup() void {
    state.renderer.deinit();
}

export fn event(ev: [*c]const sapp.Event) void {
    state.io.update(ev);
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
        .window_title = "Camera3D Demo",
        .logger = .{ .func = sokol.log.func },
    });
}
