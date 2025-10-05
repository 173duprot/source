const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;

pub const Physics = struct {
    velocity: Vec3 = Vec3.zero(),
    gravity: f32 = 9.8,
    ground_level: f32 = 1.0,
    on_ground: bool = true,

    pub fn applyGravity(self: *Physics, dt: f32) void {
        self.velocity.data[1] -= self.gravity * dt;
    }

    pub fn applyVelocity(self: *Physics, position: *Vec3, dt: f32) void {
        position.* = position.add(self.velocity.scale(dt));
    }

    pub fn checkGroundCollision(self: *Physics, position: *Vec3) void {
        if (position.data[1] <= self.ground_level) {
            position.data[1] = self.ground_level;
            self.velocity.data[1] = 0;
            self.on_ground = true;
        } else {
            self.on_ground = false;
        }
    }

    pub fn jump(self: *Physics, force: f32) void {
        if (self.on_ground) {
            self.velocity.data[1] = force;
            self.on_ground = false;
        }
    }

    pub fn addForce(self: *Physics, force: Vec3) void {
        self.velocity = self.velocity.add(force);
    }

    pub fn setVelocity(self: *Physics, vel: Vec3) void {
        self.velocity = vel;
    }

    pub fn update(self: *Physics, position: *Vec3, dt: f32) void {
        self.applyGravity(dt);
        self.applyVelocity(position, dt);
        self.checkGroundCollision(position);
    }
};
