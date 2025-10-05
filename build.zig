const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = target,
        .optimize = optimize,
    });
    const shdc_dep = b.dependency("shdc", .{});

    // Compile shader
    const sokol_shdc = @import("shdc");
    const shader_step = try sokol_shdc.createSourceFile(b, .{
        .shdc_dep = shdc_dep,
        .input = "src/shaders/cube.glsl",
        .output = "src/shaders/cube.glsl.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .metal_macos = true,
            .hlsl5 = true,
            .wgsl = true,
        },
        .reflection = true,
    });

    // Build executable
    const exe = b.addExecutable(.{
        .name = "camera_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sokol", .module = sokol_dep.module("sokol") },
                .{ .name = "zalgebra", .module = zalgebra_dep.module("zalgebra") },
            },
        }),
    });

    exe.step.dependOn(shader_step);
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the camera demo");
    run_step.dependOn(&run_cmd.step);
}
