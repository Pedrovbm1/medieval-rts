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

**Gate humano**: aprobado por Pedro en el teléfono (10/10).

---

## F2 — Pathfinding y movimiento de grupo (2026-10-17, ~2 h)

**Qué se hizo**
- `NavGrid`: `AStarGrid2D` 120x120 (celdas de 64 px), sin cortar esquinas, contador de bloqueos por celda para obstáculos dinámicos, vecino caminable más cercano, línea de vista con margen (recorrido de celdas Amanatides-Woo) y suavizado de rutas.
- `PathQueue`: máximo 8 rutas y ~2.5 ms por frame; una petición nueva del mismo dueño reemplaza la vieja.
- `MovementSystem`: un loop para todas las unidades; rutas compartidas por grupo; lugares de formación solo en celdas caminables; separación con `SpatialHash`; deslizamiento contra paredes; detección de atasco (llegó entre la multitud / re-planifica / se rinde); re-planifica si un obstáculo corta la ruta o si se libera camino.
- Mapas con `features` y dos mapas de prueba (`test_lake`, `test_open`).
- `ScenarioRunner` + `data/scenarios.json` (sandbox, lake50, stress150) y `tools/device_bench.sh`.
- Overlay con draw calls y log `[REALM] perf` cada 2 s.

**Archivos clave**: `game/systems/pathfinding/*`, `game/scenes/main/scenario_runner.gd`, `game/data/scenarios.json`, `game/data/maps/test_*.json`, `game/tests/test_f2_pathfinding.gd`, `tools/device_bench.sh`.

**Tests**: 96/96 headless. 50 unidades rodean el lago y llegan todas sin pisar agua. Un muro a media ruta las re-planifica y llegan 10/10; quitarlo re-planifica a todas. 150 unidades: 1.5-1.9 ms por paso en PC.

**Problemas**
- El suavizado era cuadrático en rutas largas (picos de 20 ms en la cola): búsqueda exponencial + binaria del punto visible más lejano y tope de tiempo por frame → picos de ~4 ms.
- Un test modificó la tabla de escenarios compartida → el runner ahora copia los datos.
- El S10 se desconectó de adb a mitad del benchmark: medición de device pendiente.

---

## F3 — Economía + animales (2026-10-17, ~3 h)

**Qué se hizo**
- `Building` (huella, bloquea NavGrid salvo granja, drop-off, población) y `ResourceNode` (minas, arbustos, cadáveres con decaimiento).
- Árboles como datos por celda: talar libera el camino.
- `EconomySystem`: drop-off más cercano, entregas con estadísticas, población usada/tope, aldeanos ociosos, tasas con modificadores.
- `GatherTask` (recolectar → depositar → volver, re-objetivo cercano, granjas con 1 trabajador) y `HuntTask` (caza a distancia, lure del jabalí); `BehaviorSystem` corre tareas y cerebros de animales.
- `MapPopulator`: inicios y recursos por inicio desde el JSON del mapa; escenarios `skirmish` y `eco12`.
- Órdenes inteligentes (árbol, mina, granja, animal, entregar, mover) y selección de edificios.
- HUD: barra de recursos y población, campana de ociosos (selecciona y centra la cámara), panel de edificio.
- Atlas único de arte placeholder con fuente de píxeles propia: 15 draw calls con 150 unidades.

**Tests**: 132/132 headless. S10: 60 fps con 150 unidades y 15 draw calls; eco12 60 fps; F1 adb 7/7.

**Problemas**
- Los grupos de bayas/oro solo ponían 1 recurso (el anillo libre chocaba con el vecino) → los aldeanos quedaban ociosos al agotarse. Corregido: los miembros de un grupo pueden tocarse.
- Restos de 0.9999 por suma de flotantes no se entregaban → épsilon al entregar.
- `time_scale` no da más pasos de física: los tests leen el reloj del escenario.
- El runner de tests se colgaba si una suite no compilaba → ahora la reporta como falla.

---

## F4 — Construcción y producción (2026-10-18, ~2 h)

**Qué se hizo**
- `ConstructionSystem`: validación con motivo (ocupado / costo / era / tipo), pago al confirmar, cimientos que bloquean el paso, cancelar con 50% de reembolso, colas de producción (máx. 5, pago al encolar, reembolso al quitar), población que bloquea la cola, punto de reunión.
- `BuildTask`: constructores con velocidad decreciente por constructor extra; al terminar siembran, recolectan o quedan ociosos.
- `PlacementController`: fantasma verde/rojo validado en vivo, se mueve con tap o arrastre, ✓ / doble tap / ✕.
- HUD dinámico: panel de aldeanos con Construir, menú de edificios con costos, barra ✓/✕ con motivo, panel de edificio con botones de entrenar, cola y Cancelar obra; el panel se ajusta a su contenido.
- Cuartel (entrena miliciano); costos y tiempos de entrenamiento en `units.json`; recursos iniciales por escenario.
- Tocar un edificio propio con selección: ayudar/sembrar/entregar o seleccionarlo.

**Archivos clave**: `game/systems/construction/*`, `game/scenes/ui/hud.*`, `game/scenes/buildings/building.gd`, `game/tests/test_f4_construction.gd`, `tools/device_test_f4.sh`.

**Tests**: 168/168 headless. Base completa en 64 s de juego. S10: construir una casa y entrenar con toques reales 5/5; F1 7/7.

**Problemas**
- Con aldeanos seleccionados no se podía seleccionar la Plaza (los movía) → regla D27.
- El panel no crecía cuando los botones pasaban a otra fila → se mide tras el acomodo y se ancla abajo a la derecha.
- El test del jabalí dependía de la posición de los aldeanos y de la correa de 900 px; el cazador mataba al jabalí durante el lure → correa 1600 px, no ataca mientras lurea, muestreo cada 0.1 s.
- La sesión programada de las 2:05 quedó esperando un permiso sin hacer cambios; se continuó en la sesión original.
