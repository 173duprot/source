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
    allocator: std.mem.Allocator,
    bsp_data: ?bsp.BspData = null,
    mesh_data: ?bsp.MeshData = null,
    is_bsp_mode: bool = false,

    fn init(allocator: std.mem.Allocator) App {
        var self = App{
            .renderer = r.Renderer.init(r.Mesh.cube(), .{ 0.25, 0.5, 0.75, 1.0 }),
            .camera = r.Camera3D.init(Vec3.new(0, 1, 6), 0.0, 0.0, 60.0),
            .allocator = allocator,
        };
        self.renderer.shader(shd.cubeShaderDesc(sokol.gfx.queryBackend()));
        return self;
    }

    fn loadBsp(self: *App, filepath: []const u8) !void {
        // Clean up previous BSP data
        if (self.bsp_data) |*data| {
            data.deinit();
            self.bsp_data = null;
        }
        if (self.mesh_data) |*data| {
            data.deinit();
            self.mesh_data = null;
        }

        // Load BSP file
        std.debug.print("Loading BSP file: {s}\n", .{filepath});
        var bsp_data = try bsp.loadBsp(self.allocator, filepath);
        errdefer bsp_data.deinit();

        std.debug.print("BSP loaded: {} vertices, {} faces, {} models\n", .{
            bsp_data.vertices.len,
            bsp_data.faces.len,
            bsp_data.models.len,
        });

        // Convert BSP to renderable mesh
        var mesh_data = try bsp.bspToMesh(self.allocator, &bsp_data);
        errdefer mesh_data.deinit();

        std.debug.print("Mesh created: {} vertices, {} indices ({} triangles)\n", .{
            mesh_data.vertices.len / 3,
            mesh_data.indices.len,
            mesh_data.indices.len / 3,
        });

        // Destroy old renderer
        self.renderer.deinit();

        // Create new renderer from BSP MeshData
        self.renderer = try r.Renderer.initFromBspMesh(
            &mesh_data,
            .{ 0.1, 0.1, 0.15, 1.0 }, // Darker clear color for BSP levels
            .{ 0.8, 0.8, 0.8, 1.0 }   // Light gray for BSP geometry
        );
        self.renderer.shader(shd.cubeShaderDesc(sokol.gfx.queryBackend()));

        // Store BSP data
        self.bsp_data = bsp_data;
        self.mesh_data = mesh_data;
        self.is_bsp_mode = true;

        // Reposition camera for BSP viewing
        if (bsp_data.models.len > 0) {
            const model = bsp_data.models[0];
            const center_x = (model.bound_min[0] + model.bound_max[0]) / 2.0;
            const center_y = (model.bound_min[1] + model.bound_max[1]) / 2.0;
            const center_z = (model.bound_min[2] + model.bound_max[2]) / 2.0;

            // Position camera at center, slightly above and back
            self.camera = r.Camera3D.init(
                Vec3.new(center_x, center_y + 100, center_z + 200),
                0.0,
                0.0,
                60.0
            );

            std.debug.print("Camera positioned at BSP center: ({d:.1}, {d:.1}, {d:.1})\n", .{
                center_x, center_y + 100, center_z + 200
            });
        } else {
            self.camera = r.Camera3D.init(Vec3.new(0, 50, 200), 0.0, 0.0, 60.0);
        }

        std.debug.print("BSP loaded successfully!\n", .{});
    }

    fn update(self: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());

        // Rotate cube in non-BSP mode
        if (!self.is_bsp_mode) {
            self.angle += dt * 60;
        }

        // Camera movement - faster in BSP mode
        const base_speed: f32 = if (self.is_bsp_mode) 200.0 else 0.1;
        const speed: f32 = base_speed * dt * 60;
        const move = self.io.vec2(.a, .d, .s, .w);

        if (move.x != 0) {
            const right = self.camera.right();
            const offset = Vec3.new(right.x(), 0, right.z()).norm().scale(move.x * speed);
            self.camera.move(offset);
        }
        if (move.y != 0) {
            const forward = self.camera.forward();
            const offset = Vec3.new(forward.x(), 0, forward.z()).norm().scale(move.y * speed);
            self.camera.move(offset);
        }

        // Vertical movement (Q/E keys for up/down in BSP mode)
        if (self.is_bsp_mode) {
            const vertical_move = self.io.vec2(.q, .e, .space, .space);
            if (vertical_move.x < 0) { // Q key
                self.camera.move(Vec3.new(0, -speed, 0));
            }
            if (vertical_move.x > 0) { // E key
                self.camera.move(Vec3.new(0, speed, 0));
            }
        } else {
            // Physics update for cube mode
            self.physics.update(&self.camera.position, dt);
            if (self.io.justPressed(.space)) {
                self.physics.jump(5.0);
            }
        }

        // Mouse look
        if (self.io.mouse.isLocked()) {
            self.camera.look(self.io.mouse.dx * 0.002, -self.io.mouse.dy * 0.002);
        }

        if (self.io.justPressed(.escape)) self.io.mouse.unlock();
        if (self.io.mouse.left and !self.io.mouse.isLocked()) self.io.mouse.lock();
    }

    fn render(self: *App) void {
        const aspect = sapp.widthf() / sapp.heightf();

        // Use different far plane for BSP (much larger levels)
        const far_plane: f32 = if (self.is_bsp_mode) 10000.0 else 100.0;

        const model = if (self.is_bsp_mode)
            Mat4.identity()
        else
            Mat4.fromRotation(self.angle, Vec3.new(0.5, 1, 0).norm());

        const mvp = Mat4.mul(
            Mat4.mul(
                self.camera.projectionMatrix(aspect, 0.1, far_plane),
                self.camera.viewMatrix()
            ),
            model
        );

        self.renderer.draw(mvp);
        self.io.cleanInput();
    }

    fn deinit(self: *App) void {
        self.renderer.deinit();
        if (self.bsp_data) |*data| data.deinit();
        if (self.mesh_data) |*data| data.deinit();
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var app: App = undefined;

export fn init() void {
    const allocator = gpa.allocator();
    app = App.init(allocator);

    // Example: Load a BSP file
    // Uncomment and provide path to your BSP file:
    app.loadBsp("src/maps/close.bsp") catch |err| {
        std.debug.print("Failed to load BSP: {}\n", .{err});
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
        .window_title = "Camera3D + BSP Demo",
        .logger = .{ .func = sokol.log.func },
    });
}
