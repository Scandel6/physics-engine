const std = @import("std");
const builtin = @import("builtin");
const ballistic = @import("ballistic_system.zig");
const render = @import("render");
const cyclone = @import("physics-engine");
const rl = render.rl;

const v3 = cyclone.core.vec3(f32);

extern fn emscripten_set_main_loop(
    func: *const fn () callconv(.c) void,
    fps: c_int,
    simulate_infinite_loop: c_int,
) void;

const MAX_HEIGHT = 600;
const MAX_WIDTH = 800;

// Globals for emscripten callback
var system: ballistic.AmmoRoundSystem = undefined;
var camera: rl.Camera3D = undefined;
var currentShot = ballistic.ShotType.LASER;

fn updateDrawFrame() callconv(.c) void {
    // Timing
    const dt: f32 = rl.GetFrameTime();
    const now: u32 = @as(u32, @intFromFloat(rl.GetTime() * 1000));

    // Input
    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
        system.fire(currentShot, now);
    }
    if (rl.IsKeyPressed(rl.KEY_ONE)) currentShot = .PISTOL;
    if (rl.IsKeyPressed(rl.KEY_TWO)) currentShot = .ARTILLERY;
    if (rl.IsKeyPressed(rl.KEY_THREE)) currentShot = .FIREBALL;
    if (rl.IsKeyPressed(rl.KEY_FOUR)) currentShot = .LASER;

    // Physics
    system.update(dt, now) catch {};

    // Render
    rl.BeginDrawing();
    defer rl.EndDrawing();

    rl.ClearBackground(rl.RAYWHITE);

    rl.BeginMode3D(camera);

    // Lines in floor

    var i: f32 = 0;
    while (i <= 200) : (i += 10) {
        rl.DrawLine3D(
            .{ .x = -5, .y = 0, .z = i },
            .{ .x = 5, .y = 0, .z = i },
            rl.GRAY,
        );
    }

    // Punto de disparo
    rl.DrawSphere(.{ .x = 0, .y = 1.5, .z = 0 }, 0.1, rl.BLACK);

    // Rounds activos
    const ammo_slice = system.ammoRound.slice();
    const shot_types = ammo_slice.items(.shotType);
    const positions_x = system.particles.data.slice().items(.position_x);
    const positions_y = system.particles.data.slice().items(.position_y);
    const positions_z = system.particles.data.slice().items(.position_z);
    for (0..ballistic.AmmoRoundSystem.CAPACITY) |j| {
        if (shot_types[j] == .UNUSED) continue;
        rl.DrawSphere(render.toRl(v3.init(positions_x[j], positions_y[j], positions_z[j])), 0.3, rl.BLACK);
    }
    rl.EndMode3D();

    // --- HUD ---
    rl.DrawText("Click: Fire", 10, 10, 20, rl.BLACK);
    rl.DrawText("1-4: Select Ammo", 10, 34, 20, rl.BLACK);
    const ammo_text = switch (currentShot) {
        .PISTOL => "Current Ammo: Pistol",
        .ARTILLERY => "Current Ammo: Artillery",
        .FIREBALL => "Current Ammo: Fireball",
        .LASER => "Current Ammo: Laser",
        .UNUSED => unreachable,
    };
    rl.DrawText(ammo_text, 10, 58, 20, rl.BLACK);
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    system = try ballistic.AmmoRoundSystem.init(allocator);

    camera = .{
        .position = .{ .x = -25, .y = 8, .z = 5 },
        .target = .{ .x = 0, .y = 5, .z = 22 },
        .up = .{ .x = 0, .y = 1, .z = 0 },
        .fovy = 60,
        .projection = rl.CAMERA_PERSPECTIVE,
    };

    rl.InitWindow(MAX_WIDTH, MAX_HEIGHT, "physics-engine - ballistic");

    rl.SetTargetFPS(60);

    // Known in comptime
    const is_web = builtin.os.tag == .emscripten;

    if (is_web) {
        // Browser closes and returns so deinit is not called
        emscripten_set_main_loop(updateDrawFrame, 0, 0);
    } else {
        while (!rl.WindowShouldClose()) updateDrawFrame();
        system.deinit();
        rl.CloseWindow();
    }
}
