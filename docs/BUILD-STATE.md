# BUILD-STATE — REALM

> Estado vivo del build autónomo. Se actualiza al cerrar cada fase.
> Una sesión nueva retoma desde aquí.

## Fase actual
**F2 — Pathfinding y movimiento de grupo** (en curso)

## Completadas
| Fase | Commit | Fecha | Gate |
|---|---|---|---|
| F0 | 2007d99, 2638e05 | 2026-10-17 | Cumplido en Galaxy S10 (arranque 0.6-0.9 s, pan 60 fps, pinch probado por Pedro) |
| F1 | 4747fd7 | 2026-10-17 | 67/67 headless, 7/7 adb en S10, gate humano 10/10 aprobado por Pedro |

## Siguiente
F2 → F3.

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

## Blockers
Ninguno.

## Últimos tests
- F0: 22/22 headless. Device: arranque 0.6-0.9 s, 60 fps en pan.
- F1: 67/67 headless (incluye 10/10 ciclos simulados y 100 taps con temblor). Device S10 por adb (`bash tools/device_test_f1.sh`): 7/7, incluye 10/10 ciclos selección + orden. 60 fps.
