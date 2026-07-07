//! By convention, root.zig is the root source file when making a library.
//! Having the public stuff of the module.
const cyclone = @import("cyclone/cyclone.zig");

pub const Vector3 = cyclone.Vector3;
pub const Particle = cyclone.Particle;
pub const ParticleSystem = cyclone.ParticleSystem;

test {
    _ = @import("cyclone/core.zig");
    _ = @import("cyclone/particle.zig");
}
