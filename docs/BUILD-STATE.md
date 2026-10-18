# BUILD-STATE — REALM

> Estado vivo del build autónomo. Se actualiza al cerrar cada fase.
> Una sesión nueva retoma desde aquí.

## Fase actual
**F3 — Economía + animales** (en curso)

## Completadas
| Fase | Commit | Fecha | Gate |
|---|---|---|---|
| F0 | 2007d99, 2638e05 | 2026-10-17 | Cumplido en Galaxy S10 (arranque 0.6-0.9 s, pan 60 fps, pinch probado por Pedro) |
| F1 | 4747fd7 | 2026-10-17 | 67/67 headless, 7/7 adb en S10, gate humano 10/10 aprobado por Pedro |
| F2 | 3784c4d | 2026-10-17 | Headless 96/96. S10: 150 unidades a 59.5-60 fps (peor frame en juego 28 ms; 149 ms solo en la carga), lake50 50/50 en 57 s. Draw calls 189-543 → se corrige en F3 con atlas |

## Siguiente
F3 → F4. El S10 se comparte con la sesión del juego de Mateo: pedir turno por mensaje antes de usarlo.

## Entorno
| Pieza | Valor |
|---|---|
| Godot | 4.7.2 stable (winget). Consola: `C:/Users/pedro/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe` |
| JDK para export | 17 (`C:\Users\pedro\AppData\Local\Programs\devtools\jdk-17.0.20.1+1`). `JAVA_HOME` del sistema apunta a 21: pasar JAVA_HOME=17 al exportar |
| Android SDK | `C:\Users\pedro\AppData\Local\Android\Sdk` |
| Device | Samsung Galaxy S10 (SM-G975U1), Android 12, 2280x1080, adb id R58M154WY9A |
| Paquete | `dev.pedro.realm`, actividad `com.godot.game.GodotAppLauncher` |

## Comandos
```bash
# variable de conveniencia (Git Bash)
G="C:/Users/pedro/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
# tests headless
"$G" --headless --path game tests/run_tests.tscn
# export APK debug
JAVA_HOME='C:\Users\pedro\AppData\Local\Programs\devtools\jdk-17.0.20.1+1' "$G" --headless --path game --export-debug "Android" ../build/realm-debug.apk
# prueba automática de gestos en el teléfono (F1)
bash tools/device_test_f1.sh
# benchmark de un escenario en el teléfono (perf + llegada), ej. 150 unidades
bash tools/device_bench.sh stress150 24
# instalar y abrir
adb install -r build/realm-debug.apk
adb shell am start -W -n dev.pedro.realm/com.godot.game.GodotAppLauncher
```

## Decisiones de producto y técnicas
| # | Fase | Decisión | Por qué |
|---|---|---|---|
| D1 | F0 | Tileset placeholder generado en runtime desde `terrain.json` (colores) | Cero assets binarios hasta F9 |
| D2 | F0 | Tests como escena (`tests/run_tests.tscn`), no `-s` | Con `-s` los autoloads no existen al compilar |
| D3 | F1 | Arrastre rápido de 1 dedo = pan; mantener 0.35 s quieto y arrastrar = caja de selección (con vibración). El plan decía "drag sin selección = caja" | Conserva el pan de 1 dedo de F0, que se usa mucho más que la caja; la presión larga es un gesto deliberado, difícil de hacer por accidente |
| D4 | F1 | `PointerManager` es el único dueño del touch (usa `_input`); la cámara ya no lee toques. Dedos que empiezan sobre el HUD se ignoran hasta soltarse | Un gesto nunca puede activar dos sistemas a la vez |
| D5 | F1 | `emulate_mouse_from_touch=true` para que los `Button` funcionen con el dedo; la cámara ignora mouse emulado | Los botones de Godot solo escuchan mouse |
| D6 | F1 | Unidades como `Node2D` con movimiento propio, no `CharacterBody2D` | 150 unidades sin costo de física; el steering propio llega en F2 |
| D7 | F1 | Autoload extra `Sfx` + `data/audio.json`. SFX placeholder sintetizados por `tools/gen_placeholder_sfx.py` (originales, sin licencia) | Cambiar sonidos en F9 sin tocar código |
| D8 | F1 | Doble tap en el suelo: si hay selección actúa como tap (mover); si no, centra la cámara ahí | El plan no definía el caso con selección |
| D9 | F1 | Tests en suites `tests/test_*.gd` (clase base `TestSuite`), orden alfabético de métodos | Escala por fase sin un archivo gigante |
| D10 | F2 | Navegación en celdas de 64 px (= tiles), A* de `AStarGrid2D` sin cortar esquinas; suavizado por línea de vista con margen de 10 px | Suficiente para 120x120; más fino solo si F3+ lo pide |
| D11 | F2 | Grupo = 1 A* compartido; cada unidad se une a la ruta si la ve (primeros 4 puntos) y sale a su lugar de formación; si no la ve, A* propio | Cumple "path compartido" sin meter unidades en el agua |
| D12 | F2 | Cola de rutas con dos topes: 8 rutas y ~2.5 ms por frame (`rules.json`) | Evita picos al ordenar a muchos grupos a la vez |
| D13 | F2 | Un solo `MovementSystem` mueve a todas las unidades (no `_physics_process` por unidad); separación con `SpatialHash` | Un loop, sin costo de física; base para combate (vecinos) |
| D14 | F2 | Escenarios en `data/scenarios.json`; en debug el teléfono lee `user://scenario.txt` (lo escribe `tools/device_bench.sh` con `run-as`) | Benchmarks reproducibles en device sin menús de debug |
| D15 | F2 | Mapas con `features` (círculo, rectángulo, línea) pintados sobre el ruido | Mapas de prueba exactos y, en F9, mapas curados |
| D16 | F2 | Las tablas de `DataLoader` se comparten: son de solo lectura (`duplicate()` antes de modificar) | Un test borró datos compartidos y rompió el siguiente |

## Blockers
- Ninguno. Nota: el S10 se comparte con otra sesión (juego de Mateo); turnarse por mensaje.

## Últimos tests
- F0: 22/22 headless. Device: arranque 0.6-0.9 s, 60 fps en pan.
- F2: 96/96 headless. Lake50: 50/50 llegan, ninguna pisa agua. Muro: re-planifica y 10/10 llegan; quitarlo re-planifica a todas. Stress150 (PC): movimiento 1.5-1.9 ms promedio, peor ~4-6 ms.
- F1: 67/67 headless (incluye 10/10 ciclos simulados y 100 taps con temblor). Device S10 por adb (`bash tools/device_test_f1.sh`): 7/7, incluye 10/10 ciclos selección + orden. 60 fps.
