# BUILD-LOG — REALM

Una entrada por fase: qué se hizo, archivos, tests, problemas y tiempo aproximado.

---

## F0 — Setup + mundo mínimo (2026-10-17, ~1 h)

**Qué se hizo**
- Proyecto Godot 4.7.2: renderer Compatibility, 1280x720 landscape, stretch `canvas_items`/`expand`.
- Autoloads: EventBus, DataLoader, GameState, SaveManager.
- Mapa 120x120 de tiles 64 px con ruido (pasto/agua/bosque) y semilla fija.
- Cámara táctil: pan 1 dedo, pinch 0.5x-1.5x, siempre dentro del mapa.
- Overlay de FPS/zoom/mapa. Preset de export Android (arm64-v8a).

**Archivos clave**: `game/project.godot`, `game/autoload/*`, `game/scenes/main/*`, `game/systems/world/*`, `game/data/*`, `game/tests/*`.

**Tests**: 22/22 headless. En Galaxy S10: arranque en frío 0.6-0.9 s, pan a 60 fps, pinch probado por Pedro.

**Problemas**
- Los tests con `-s` no ven autoloads → se movieron a una escena.
- El `.tpz` de templates es zip, no tar.
- El overlay perdía la señal `map_generated` (suscriptor tardío) → lee el estado al arrancar.

---

## F1 — Selección y órdenes (2026-10-17, ~1.5 h)

**Qué se hizo**
- `GestureClassifier` puro (tap, doble tap, pan, caja con presión larga, pinch, cancelaciones) con tiempo explícito → testeable sin device.
- `PointerManager`: único dueño del touch; rutea gestos a cámara y selección; ignora dedos que empiezan en el HUD; vibra al armar la caja.
- `SelectionController`: tap selecciona, doble tap = mismo tipo en pantalla, caja, tap en suelo = mover en formación (slots en espiral, asignación greedy), Detener/Mantener/Soltar.
- `Unit` placeholder (disco de color + letra + anillo de selección), 3 milicianos + 2 aldeanos de prueba en pasto.
- Feedback: `OrderMarker` (línea + anillo que se cierra) y SFX sintetizados (`Sfx` autoload, `data/audio.json`).
- HUD con panel de selección en español y botones de 120x72.
- Reglas de input/movimiento en `data/rules.json`.

**Archivos clave**: `game/systems/selection/*`, `game/scenes/units/*`, `game/scenes/ui/hud.*`, `game/scenes/ui/order_marker.gd`, `game/autoload/sfx.gd`, `game/data/rules.json`, `game/data/audio.json`, `tools/gen_placeholder_sfx.py`, `tools/device_test_f1.sh`, `game/tests/test_f1_*.gd`.

**Tests**: 67/67 headless. S10 por adb: 7/7 (tap, caja, orden, Detener, HUD sin fuga, swipe no selecciona, 10/10 ciclos). 60 fps.

**Problemas**
- Una presión de 500 ms sin frames intermedios contaba como tap (el dedo se borraba antes de revisar el tiempo). Corregido y cubierto por test.
- El script de device leía la posición del botón después de limpiar el log. Corregido.

**Pendiente**: gate humano (Pedro, 10/10 con los dedos).
