const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

pub const Camera3D = struct {
    position: Vec3,
    target: Vec3,
    up: Vec3,
    fov: f32,

    pub fn init(position: Vec3, target: Vec3, fov: f32) Camera3D {
        return .{
            .position = position,
            .target = target,
            .up = Vec3.up(),
            .fov = fov,
        };
    }

    pub fn forward(self: Camera3D) Vec3 {
        return self.target.sub(self.position).norm();
    }

    pub fn right(self: Camera3D) Vec3 {
        return self.forward().cross(self.up).norm();
    }

    pub fn translate(self: *Camera3D, offset: Vec3) void {
        self.position = self.position.add(offset);
        self.target = self.target.add(offset);
    }

    pub fn rotate(self: *Camera3D, axis: Vec3, angle: f32, pivot: Vec3) void {
        self.position = rotateAround(self.position, pivot, axis, angle);
        self.target = rotateAround(self.target, pivot, axis, angle);
        self.up = rotateByAxis(self.up, axis, angle);
    }

    pub fn viewMatrix(self: Camera3D) Mat4 {
        return za.lookAt(self.position, self.target, self.up);
    }

    pub fn projectionMatrix(self: Camera3D, aspect: f32, near: f32, far: f32) Mat4 {
        return za.perspective(self.fov, aspect, near, far);
    }
};

fn rotateByAxis(v: Vec3, axis: Vec3, angle: f32) Vec3 {
    const c = @cos(angle);
    const s = @sin(angle);
    const t = 1.0 - c;
    const ax = axis.x();
    const ay = axis.y();
    const az = axis.z();

    return Vec3.new(
        v.x() * (c + ax * ax * t) + v.y() * (ax * ay * t - az * s) + v.z() * (ax * az * t + ay * s),
        v.x() * (ay * ax * t + az * s) + v.y() * (c + ay * ay * t) + v.z() * (ay * az * t - ax * s),
        v.x() * (az * ax * t - ay * s) + v.y() * (az * ay * t + ax * s) + v.z() * (c + az * az * t),
    );
}

fn rotateAround(point: Vec3, pivot: Vec3, axis: Vec3, angle: f32) Vec3 {
    const relative = point.sub(pivot);
    const rotated = rotateByAxis(relative, axis, angle);
    return pivot.add(rotated);
}
