# USO DE CALLBACK SIN VARIABLES GLOBALES

Al usar emscripten_set_main_loop, ¿cómo le paso la instancia de mi motor de físicas (world) a la función callback sin convertirla en una variable global en Zig?

## RESPUESTA

Para lograr esto sin ensuciar tu código con variables globales, la clave está en usar una función hermana de la API de Emscripten diseñada específicamente para inyectar contexto: **`emscripten_set_main_loop_arg`**.

Esta función acepta un argumento adicional (`void *arg` en C, que en Zig se traduce como `?*anyopaque`). Este puntero opaco actuará como el "vehículo" para transportar la instancia de tu motor de físicas directamente a las entrañas del *callback*.

Aquí tienes la arquitectura idónea para estructurar esto en Zig, manteniendo el diseño Data-Oriented y limpio:

### 1. Agrupar el estado de la demo

En lugar de inicializar tu `World` suelto en `main`, encapsúlalo dentro de un *struct* que represente el estado completo de la demo.

### 2. El código de la implementación

```zig
const std = @import("std");
const phys = @import("fisicas");
const rl = @cImport({ @cInclude("raylib.h"); });

// Importamos Emscripten de forma condicional para que compile en escritorio
const is_web = @import("builtin").os.tag == .emscripten;
const emscripten = if (is_web) @cImport({ @cInclude("emscripten.h"); }) else struct {};

// 1. Definimos el estado de la demo
const DemoState = struct {
    world: phys.World,
    allocator: std.mem.Allocator,
    // Aquí puedes añadir la cámara, texturas u otros recursos

    pub fn init(allocator: std.mem.Allocator) !*DemoState {
        // MUY IMPORTANTE: Alojamos el estado en el Heap, no en el Stack.
        const state = try allocator.create(DemoState);
        state.* = .{
            .world = phys.World.init(allocator),
            .allocator = allocator,
        };
        return state;
    }

    pub fn updateDraw(self: *DemoState) void {
        // Físicas
        self.world.step(rl.GetFrameTime());

        // Renderizado
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        
        // Renderizamos usando self.world...
    }
};

// 2. El puente C-ABI (El Callback)
// Tiene que usar callconv(.C) para que Emscripten/C lo entienda.
fn emscriptenCallback(arg: ?*anyopaque) callconv(.C) void {
    // Restauramos el puntero opaco a nuestro tipo real
    const state: *DemoState = @ptrCast(@alignCast(arg.?));
    state.updateDraw();
}

pub fn main() !void {
    rl.InitWindow(800, 600, "Demo Balística con Callback");
    defer rl.CloseWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Instanciamos el estado en el heap
    const state = try DemoState.init(allocator);

    if (is_web) {
        // La magia ocurre aquí: 
        // 1. Pasamos nuestra función callback
        // 2. Pasamos el puntero a 'state'
        // 3. 0 = Dejar que el navegador controle los FPS (requestAnimationFrame)
        // 4. 1 = Simular bucle infinito (evita que main libere la memoria al terminar)
        emscripten.emscripten_set_main_loop_arg(emscriptenCallback, state, 0, 1);
    } else {
        // Bucle nativo tradicional para escritorio
        rl.SetTargetFPS(60);
        while (!rl.WindowShouldClose()) {
            state.updateDraw();
        }
    }
}

```

### El detalle crítico: ¿Por qué alojar en el Heap? (`allocator.create`)

Fíjate que en la función `init` utilizamos `allocator.create(DemoState)` para reservar la memoria del estado dinámicamente, en lugar de instanciarlo localmente en `main` como `var state = DemoState{...}`.

Si lo instancias localmente en el *stack* de `main` y pasas una referencia (`&state`), ocurre un desastre:
Cuando llamas a `emscripten_set_main_loop_arg` (con el último parámetro a `1`), Emscripten lanza una excepción controlada de JavaScript bajo el capó para pausar la ejecución de Zig y devolver el control al navegador. Conceptualmente, el marco de pila (*stack frame*) de `main` se desvanece o queda inestable. Si el *callback* intenta leer ese puntero del *stack* en el siguiente *frame*, leerá memoria corrupta (basura).

Al usar memoria del *heap*, garantizas que los datos de tu motor de físicas (`World`) sobrevivan intactos frame a frame en la memoria lineal de WebAssembly, sin violar las convenciones de limpieza de Zig ni usar variables globales.
