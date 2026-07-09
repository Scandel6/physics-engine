const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});

const MAX_HEIGHT = 600;
const MAX_WIDTH = 800;

pub fn main() void {
    rl.InitWindow(MAX_WIDTH, MAX_HEIGHT, "physics-engine - ballistic");
    defer rl.CloseWindow();

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.RAYWHITE);
        rl.DrawText("physics-engine ballistic demo", 20, 20, 20, rl.BLACK);
    }
}
