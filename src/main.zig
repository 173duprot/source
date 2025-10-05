//------------------------------------------------------------------------------
//  camera_demo.zig
//
//  Rotating cube using Camera3D
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;
const Camera3D = @import("camera.zig").Camera3D;
const shd = @import("shaders/cube.glsl.zig");

const state = struct {
    var angle: f32 = 0.0;
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var pass_action: sg.PassAction = .{};
    var camera: Camera3D = undefined;
    var keys = struct {
        w: bool = false,
        a: bool = false,
        s: bool = false,
        d: bool = false,
        space: bool = false,
        shift: bool = false,
    }{};
    var mouse_locked: bool = false;
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // initialize camera
    state.camera = Camera3D.init(
        Vec3.new(0, 2, 6),      // position
        Vec3.new(0, 0, 0),      // target (looking at origin)
        60.0,                   // fov
    );

    // cube vertex buffer
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            -1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
            1.0,  -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,
            -1.0, 1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,
            -1.0, -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
            1.0,  -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
            1.0,  1.0,  1.0,  0.0, 1.0, 0.0, 1.0,
            -1.0, 1.0,  1.0,  0.0, 1.0, 0.0, 1.0,
            -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0,
            -1.0, 1.0,  -1.0, 0.0, 0.0, 1.0, 1.0,
            -1.0, 1.0,  1.0,  0.0, 0.0, 1.0, 1.0,
            -1.0, -1.0, 1.0,  0.0, 0.0, 1.0, 1.0,
            1.0,  -1.0, -1.0, 1.0, 0.5, 0.0, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.5, 0.0, 1.0,
            1.0,  1.0,  1.0,  1.0, 0.5, 0.0, 1.0,
            1.0,  -1.0, 1.0,  1.0, 0.5, 0.0, 1.0,
            -1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,
            -1.0, -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
            1.0,  -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
            1.0,  -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,
            -1.0, 1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
            -1.0, 1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
            1.0,  1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
        }),
    });

    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            0,  1,  2,  0,  2,  3,
            6,  5,  4,  7,  6,  4,
            8,  9,  10, 8,  10, 11,
            14, 13, 12, 15, 14, 12,
            16, 17, 18, 16, 18, 19,
            22, 21, 20, 23, 22, 20,
        }),
    });

    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.cubeShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_cube_position].format = .FLOAT3;
            l.attrs[shd.ATTR_cube_color0].format = .FLOAT4;
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
        .cull_mode = .BACK,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.5, .b = 0.75, .a = 1 },
    };
}

export fn frame() void {
    const dt: f32 = @floatCast(sapp.frameDuration() * 60);
    state.angle += 1.0 * dt;

    // camera movement
    const move_speed: f32 = 0.1;
    if (state.keys.w) state.camera.translate(state.camera.forward().scale(move_speed));
    if (state.keys.s) state.camera.translate(state.camera.forward().scale(-move_speed));
    if (state.keys.a) state.camera.translate(state.camera.right().scale(-move_speed));
    if (state.keys.d) state.camera.translate(state.camera.right().scale(move_speed));
    if (state.keys.space) state.camera.translate(Vec3.up().scale(move_speed));
    if (state.keys.shift) state.camera.translate(Vec3.up().scale(-move_speed));

    // compute aspect ratio
    const aspect = sapp.widthf() / sapp.heightf();

    // compute MVP using camera
    const model = Mat4.fromRotation(state.angle, Vec3.new(0.5, 1, 0).norm());
    const view = state.camera.viewMatrix();
    const proj = state.camera.projectionMatrix(aspect, 0.1, 100.0);
    const vp = Mat4.mul(proj, view);
    const mvp = Mat4.mul(vp, model);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&shd.VsParams{ .mvp = mvp }));
    sg.draw(0, 36, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    const e = ev.*;
    switch (e.type) {
        .KEY_DOWN => {
            switch (e.key_code) {
                .W => state.keys.w = true,
                .A => state.keys.a = true,
                .S => state.keys.s = true,
                .D => state.keys.d = true,
                .SPACE => state.keys.space = true,
                .LEFT_SHIFT => state.keys.shift = true,
                .ESCAPE => {
                    if (state.mouse_locked) {
                        sapp.lockMouse(false);
                    }
                },
                else => {},
            }
        },
        .KEY_UP => {
            switch (e.key_code) {
                .W => state.keys.w = false,
                .A => state.keys.a = false,
                .S => state.keys.s = false,
                .D => state.keys.d = false,
                .SPACE => state.keys.space = false,
                .LEFT_SHIFT => state.keys.shift = false,
                else => {},
            }
        },
        .MOUSE_DOWN => {
            if (e.mouse_button == .LEFT and !state.mouse_locked) {
                sapp.lockMouse(true);
                state.mouse_locked = true;
            }
        },
        .MOUSE_MOVE => {
            if (state.mouse_locked) {
                const sensitivity: f32 = 0.002;
                const dx = e.mouse_dx * sensitivity;
                const dy = e.mouse_dy * sensitivity;

                // Yaw (left/right) - rotate around world up
                state.camera.rotate(Vec3.up(), -dx, state.camera.position);

                // Pitch (up/down) - rotate around camera right
                state.camera.rotate(state.camera.right(), -dy, state.camera.position);
            }
        },
        else => {},
    }
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
        .logger = .{ .func = slog.func },
    });
}
