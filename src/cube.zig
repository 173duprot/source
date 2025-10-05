const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const za = @import("zalgebra");
const Camera3D = @import("camera.zig").Camera3D;
const shd = @import("shaders/cube.glsl.zig");

var a: f32 = 0;
var p: sg.Pipeline = .{};
var b: sg.Bindings = .{};
var c: Camera3D = undefined;

const v = [_]f32{ -1, -1, -1, 1, 0, 0, 1, 1, -1, -1, 1, 0, 0, 1, 1, 1, -1, 1, 0, 0, 1, -1, 1, -1, 1, 0, 0, 1, -1, -1, 1, 0, 1, 0, 1, 1, -1, 1, 0, 1, 0, 1, 1, 1, 1, 0, 1, 0, 1, -1, 1, 1, 0, 1, 0, 1, -1, -1, -1, 0, 0, 1, 1, -1, 1, -1, 0, 0, 1, 1, -1, 1, 1, 0, 0, 1, 1, -1, -1, 1, 0, 0, 1, 1, 1, -1, -1, 1, .5, 0, 1, 1, 1, -1, 1, .5, 0, 1, 1, 1, 1, 1, .5, 0, 1, 1, -1, 1, 1, .5, 0, 1, -1, -1, -1, 0, .5, 1, 1, -1, -1, 1, 0, .5, 1, 1, 1, -1, 1, 0, .5, 1, 1, 1, -1, -1, 0, .5, 1, 1, -1, 1, -1, 1, 0, .5, 1, -1, 1, 1, 1, 0, .5, 1, 1, 1, 1, 1, 0, .5, 1, 1, 1, -1, 1, 0, .5, 1 };
const i = [_]u16{ 0, 1, 2, 0, 2, 3, 6, 5, 4, 7, 6, 4, 8, 9, 10, 8, 10, 11, 14, 13, 12, 15, 14, 12, 16, 17, 18, 16, 18, 19, 22, 21, 20, 23, 22, 20 };

export fn init() void {
    sg.setup(.{ .environment = sglue.environment(), .logger = .{ .func = sokol.log.func } });
    cam = Camera3D.init(za.Vec3.new(0, 2, 6), za.Vec3.new(0, 0, -1), 60);
    bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(&v) });
    bind.index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(&i) });
    pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.cubeShaderDesc(sg.queryBackend())),
        .layout = .{ .attrs = .{ shd.ATTR_cube_position = .{ .format = .FLOAT3 }, shd.ATTR_cube_color0 = .{ .format = .FLOAT4 } } },
        .index_type = .UINT16,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
        .cull_mode = .BACK,
    });
}

export fn frame() void {
    angle += @floatCast(sapp.frameDuration() * 60);
    cam.aspect = sapp.widthf() / sapp.heightf();
    const m = za.Mat4.fromRotation(angle, za.Vec3.new(.5, 1, 0).norm());
    sg.beginPass(.{ .action = .{ .colors = .{.{ .load_action = .CLEAR, .clear_value = .{ .r = .25, .g = .5, .b = .75, .a = 1 } }} }, .swapchain = sglue.swapchain() });
    sg.applyPipeline(pip);
    sg.applyBindings(bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&shd.VsParams{ .mvp = za.Mat4.mul(cam.matrix(), m) }));
    sg.draw(0, 36, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{ .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .width = 800, .height = 600, .sample_count = 4, .icon = .{ .sokol_default = true }, .window_title = "Camera3D", .logger = .{ .func = sokol.log.func } });
}
