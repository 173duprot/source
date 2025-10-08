const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

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
