const std = @import("std");
const cyclone = @import("physics-engine");
const testing = std.testing;

const Vec3 = cyclone.Vector3(f32);
const ParticleSystem = cyclone.ParticleSystem(f32);
const Particle = cyclone.Particle(f32);
const defaultParticle = cyclone.defaultParticle;

pub const ShotType = enum(u8) {
    UNUSED = 0,
    PISTOL = 1,
    ARTILLERY = 2,
    FIREBALL = 3,
    LASER = 4,
};

const AmmoRound = struct {
    shotType: ShotType,
    startTime: u32,
};

pub const AmmoRoundSystem = struct {
    pub const CAPACITY: usize = 16;
    particles: ParticleSystem,
    ammoRound: std.MultiArrayList(AmmoRound),
    count: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !@This() {
        // No alloc in running time
        var ammo = std.MultiArrayList(AmmoRound){};
        try ammo.ensureTotalCapacity(alloc, CAPACITY);
        var particles = ParticleSystem.init(alloc);
        try particles.ensureTotalCapacity(CAPACITY);

        for (0..CAPACITY) |_| {
            const i = ammo.addOneAssumeCapacity();
            ammo.items(.shotType)[i] = ShotType.UNUSED;
            ammo.items(.startTime)[i] = 0;
            try particles.addParticle(defaultParticle(f32));
        }

        return .{
            .ammoRound = ammo,
            .allocator = alloc,
            .particles = particles,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.particles.deinit();
        self.ammoRound.deinit(self.allocator);
    }

    test "init/deinit" {
        var system = try AmmoRoundSystem.init(testing.allocator);
        defer system.deinit();
    }

    //  busca primer UNUSED, escribe campos del particle in-site según shot (valores de cyclone),
    //  setea shotType/startTime, limpia forceAccum. count++. Si no hay slot, no hace nada.
    pub fn fire(self: *@This(), shot: ShotType, now: u32) void {
        const slice = self.ammoRound.slice();
        const shotTypes = slice.items(.shotType);

        for (0..slice.len) |i| {
            if (shotTypes[i] == ShotType.UNUSED) {
                self.ammoRound.set(i, .{
                    .shotType = shot,
                    .startTime = now,
                });
                self.count += 1;
                self.setParticle(i, shot);
                break;
            }
        }
    }

    fn setParticle(self: *@This(), index: usize, shot: ShotType) void {
        var particle = defaultParticle(f32);
        switch (shot) {
            .PISTOL => {
                particle.inverseMass = 0.5; // mass = 2kg
                particle.velocity = Vec3{ .x = 0, .y = 0, .z = 35 };
                particle.acceleration = Vec3{ .x = 0, .y = -1, .z = 0 };
                particle.damping = 0.99;
            },
            .ARTILLERY => {
                particle.inverseMass = 0.005; // mass = 200kg
                particle.velocity = Vec3{ .x = 0, .y = 30, .z = 40 };
                particle.acceleration = Vec3{ .x = 0, .y = -20, .z = 0 };
                particle.damping = 0.99;
            },
            .FIREBALL => {
                particle.inverseMass = 1; // mass = 1kg
                particle.velocity = Vec3{ .x = 0, .y = 0, .z = 10 };
                particle.acceleration = Vec3{ .x = 0, .y = 0.6, .z = 0 };
                particle.damping = 0.9;
            },
            .LASER => {
                particle.inverseMass = 10; // mass = 0.1kg
                particle.velocity = Vec3{ .x = 0, .y = 0, .z = 100 };
                particle.acceleration = Vec3{ .x = 0, .y = 0, .z = 0 };
                particle.damping = 0.99;
            },
            .UNUSED => unreachable,
        }

        particle.position = Vec3{ .x = 0, .y = 1.5, .z = 0 };
        particle.forceAccum = Vec3.zero();

        self.particles.data.set(index, particle);
    }

    test "fire" {
        var system = try AmmoRoundSystem.init(testing.allocator);
        defer system.deinit();
        system.fire(ShotType.ARTILLERY, 1);
        system.fire(ShotType.FIREBALL, 2);
        system.fire(ShotType.LASER, 3);
        system.fire(ShotType.PISTOL, 4);
    }

    /// Updates physics and culls expired/out-of-bounds rounds.
    /// dt: frame duration in seconds. now: current timestamp in ms.
    pub fn update(self: *@This(), dt: f32, now: u32) !void {
        if (dt <= 0) return;

        // Integrate all particles once (handles all CAPACITY slots,
        // including UNUSED - must change in the future).
        try self.particles.integrateAll(dt);

        // Cull: mark UNUSED any round that hit ground, expired, or flew past z=200.
        const ammo_slice = self.ammoRound.slice();
        const shotTypes = ammo_slice.items(.shotType);
        const startTimes = ammo_slice.items(.startTime);

        const positions = self.particles.data.slice().items(.position);

        for (0..CAPACITY) |i| {
            if (shotTypes[i] == ShotType.UNUSED) continue;

            if (positions[i].y < 0 or now - startTimes[i] > 5000 or positions[i].z > 200) {
                shotTypes[i] = ShotType.UNUSED;
                self.count -= 1;
            }
        }
    }
};

test {
    _ = AmmoRoundSystem;
}
