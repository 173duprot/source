const std = @import("std");
const za = @import("zalgebra");
const Vec3 = za.Vec3;

pub const Physics = struct {
    vel: Vec3 = Vec3.zero(), gravity: f32 = 9.8, ground: f32 = 1.0, grounded: bool = true,

    pub fn jump(self: *Physics, force: f32) void {
        if (self.grounded) { self.vel.data[1] = force; self.grounded = false; }
    }

    pub fn accel(self: *Physics, wishdir: Vec3, speed: f32, dt: f32) void {
        self.vel = self.vel.add(wishdir.norm().scale(speed * dt));
    }

    fn grav(self: *Physics, dt: f32) void { self.vel.data[1] -= self.gravity * dt; }

    fn friction(self: *Physics, amount: f32, dt: f32) void {
        if (self.grounded) {
            const xz = Vec3.new(self.vel.x(), 0, self.vel.z());
            const damped = xz.scale(1.0 - amount * dt);
            self.vel.data[0] = damped.x(); self.vel.data[2] = damped.z();
        }
    }

    fn collide(self: *Physics, pos: *Vec3) void {
        if (pos.data[1] <= self.ground) {
            pos.data[1] = self.ground; self.vel.data[1] = 0; self.grounded = true;
        } else self.grounded = false;
    }

    pub fn update(self: *Physics, pos: *Vec3, dt: f32) void {
        self.grav(dt); self.friction(8.0, dt);
        pos.* = pos.add(self.vel.scale(dt));
        self.collide(pos);
    }
};
