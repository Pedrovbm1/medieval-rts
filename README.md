# REALM — RTS medieval para Android

Juego RTS (real-time strategy) medieval original para Android, inspirado en los clásicos
del género. Construido en Godot 4 con GDScript.

**Nada en este proyecto usa assets, nombres, datos o código de juegos de terceros.**
Aquí no se analizan ni extraen artefactos de juegos propietarios. Mecánicas de género sí;
contenido propio, siempre.

## Estado
- [x] Investigación + plan de construcción → `docs/PLAN-CONSTRUCCION-RTS.md`
- [x] F0 — Setup + mundo mínimo (aprobada 2026-10-17; probada en Galaxy S10)
- [x] F1 — Selección y órdenes (gate humano aprobado 2026-10-17)
- [ ] F2 — Pathfinding
- [ ] F3 — Economía
- [ ] F4 — Construcción
- [ ] F5 — Combate
- [ ] F6 — IA enemiga
- [ ] F7 — Eras y tecnologías
- [ ] F8 — Fog of war + UX
- [ ] F9 — Arte y contenido
- [ ] F10 — Publicación

## Cómo trabajar
Una fase por conversación con Claude. El prompt base y los criterios de aceptación
de cada fase están en `docs/PROMPT-MAESTRO-CLAUDE.md` y `docs/PLAN-CONSTRUCCION-RTS.md`.

## Versión de Godot
**Godot 4.7.2 stable** (renderer Compatibility, GDScript). No actualizar a mitad de fase.

Requisitos para exportar a Android:
- Android SDK con `platform-tools`, `build-tools` 35+ y `platforms/android-35+`.
- JDK 17.
- Export templates 4.7.2 instalados (`Editor > Manage Export Templates`).

## Estructura
```
game/                 proyecto Godot (abrir esta carpeta en el editor)
├─ project.godot
├─ autoload/          EventBus, DataLoader, GameState, SaveManager
├─ scenes/main/       main.tscn, world.tscn, camera_controller.gd
├─ scenes/ui/         debug_overlay.gd (FPS / zoom en pantalla)
├─ systems/world/     map_generator.gd (ruido → terreno), placeholder_tileset.gd
├─ data/              terrain.json, civs.json, units/buildings/techs.json, maps/, i18n/ui.csv
├─ assets/placeholder/
└─ tests/run_tests.gd
```

## Correr en escritorio
```bash
godot --path game
```
El mouse emula un dedo (pan con clic izquierdo arrastrando); la rueda hace zoom.

## Tests (headless)
```bash
godot --headless --path game tests/run_tests.tscn
```
Estado detallado y decisiones: `docs/BUILD-STATE.md`. Bitácora por fase: `docs/BUILD-LOG.md`.
Sale con código 0 si todo pasa.

## Exportar e instalar en Android (debug)
1. Conectar el teléfono con depuración USB y verificar: `adb devices`.
2. Exportar: `godot --headless --path game --export-debug "Android" ../build/realm-debug.apk`
3. Instalar: `adb install -r build/realm-debug.apk`
4. Medir arranque: `adb shell am start -W -n dev.pedro.realm/com.godot.game.GodotApp`
   (`TotalTime` en ms debe ser < 5000).

## F0 — qué hay
- Mapa 120×120 tiles de 64 px generado con ruido (pasto / agua / bosque) desde `data/maps/skirmish_120.json`.
- Cámara táctil: pan con 1 dedo, pinch con 2 dedos (0.5×–1.5×), siempre dentro del mapa.
- Overlay con FPS y zoom para medir en el teléfono.
- Datos en JSON y textos en `data/i18n/ui.csv` (es/en).
