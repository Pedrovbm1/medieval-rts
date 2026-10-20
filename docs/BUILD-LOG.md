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

---

## F5 — Combate core (2026-10-18, ~2 h)

**Qué se hizo**
- `Combat` (reglas puras): daño tipado con armadura por tipo, bonus por clase, mínimo 1; bonus de techs ya contemplados.
- `AttackTask`: perseguir, wind-up visible, golpe o disparo, cadencia; postura (perseguir, correa, quieta); siguiente objetivo al matar; reanuda el attack-move.
- `CombatSystem`: adquisición de objetivos por postura cada 0.25 s, respuesta al ser atacado, attack-move, flechas en pool con seguimiento, destello al recibir daño, cadáveres y reciclaje de unidades.
- Unidades: miliciano, lancero, arquero, caballero, ariete (+ aldeano, explorador, jabalí con datos de combate). Edificios: Galería de tiro, Establo, Taller de asedio. Posturas en `stances.json`.
- Edificios con armadura y clase "building"; destruirlos libera el terreno.
- Tocar un enemigo con militares seleccionados = atacar.

**Tests**: 192/192 headless. Counters del plan cumplidos con margen; 20v20 en 49 s; 216 muertes sin fugas. S10: 20v20 a 60 fps y 15 DC.

**Problemas**
- `target_alive` recibía edificios ya liberados con un tipo estricto → acepta cualquier valor.
- La batalla 20v20 se estancaba (ejércitos fuera de vista) → attack-move y reenganche cada 5 s en el test.
- Los tests de caza esperaban animales liberados; ahora se reciclan → se comprueba "ya no vive".

---

## F5.5 — Roster 10-12 (2026-10-18, ~1 h)

**Qué se hizo**
- 5 unidades nuevas con rol propio: escaramuzador, espadachín, monje, mangonel y camellero (unidad única de la facción).
- Mecánicas: `HealTask` (curación con búsqueda de heridos), daño de área con caída en el impacto del proyectil, rango mínimo de asedio (retrocede), unidades únicas por facción.
- Monasterio; trenes actualizados en Cuartel, Galería, Establo y Taller.
- `CombatSystem` registra daño por tipo de unidad y curación (para afinar y probar roles).
- Acuerdo de uso compartido del S10 con AppScanner y el juego de Mateo; `tools/device_guard.sh` aplicado a todos los scripts de device.

**Tests**: 205/205 headless. Duelos de rol: escaramuzadores, espadachines y camelleros ganan su enfrentamiento; un disparo de mangonel hiere a 6 arqueros agrupados; 2 monjes curan 84 HP y deciden una pelea pareja; las 12 unidades actúan en el ejército mixto.

**Problemas**
- Comandos bash muy largos con heredocs fallaban al parsear → los cambios grandes se aplican con scripts de Python en el scratchpad.

---

## F6 + F7 — IA, eras y tecnologías (2026-10-18, ~5 h, un solo commit)

Se cerraron juntas: la IA de F6 necesitaba eras y tecnologías (F7) para gastar su economía, y el balance de los gates de ambas se ajustó en conjunto (el código de la IA es el mismo archivo).

**F6 — Qué se hizo**
- `VisionGrid` + `VisionSystem` (3 estados por jugador, 4 veces por segundo, círculos precalculados).
- `AIController`: economía (aldeanos, casas, aserraderos escalables, campamento minero, granjas, reparto por recurso), edificios militares por fase, mezcla de ejército, explorador con barrido de puntos no explorados, defensa proporcional, hostigamiento, oleadas completas que crecen tras fallar, refuerzos solo a oleadas vivas, memoria de edificios enemigos.
- `MatchRules`: derrota sin edificios, estadísticas (recolectado, entrenados, bajas); pantalla de fin con Reintentar.

**F7 — Qué se hizo**
- `eras.json` (4 eras, costo, tiempo, requisito de 2 edificios de la era), `techs.json` (24 en economía/militar/defensa), Herrería, Universidad, Torre de vigía.
- `TechSystem`: disponibilidad con motivo, investigación en colas, efectos como modificadores, recalcula unidades y edificios existentes.
- Hooks: velocidad, vida, alcance, cadencia, visión, armadura y ataque por clase; torres que disparan.
- HUD: botón de avanzar de era, botones de tecnologías con descripción, era en la barra superior, aviso de nueva era, estadísticas de la unidad seleccionada (antes/después).
- IA: avanza de era (ahorro con ejército mínimo, pausa de aldeanos al subir), construye requisitos primero, investiga.

**Tests**: suite normal F0-F5.5 sin cambios + F2 29/29, F6 17/17, F7 21/21 corridas solas; Difícil vs Normal: NO cumplido: 3 duelos de 45 min terminaron en empate tras 3 rondas de ajustes (ver Blockers).

**Problemas**
- Balance IA: con costos de era altos la IA no podía tener ejército y avanzar a tiempo → costos bajados (D44) y reglas de ahorro (D45).
- Duelo IA vs IA se estancaba (refuerzos sueltos contra la defensa) → oleadas completas que crecen, refuerzos solo a oleadas vivas, más asedio.
- `MatchRules` declaraba victoria instantánea sin rival (encontrado en el S10).
- Un script de device tocó otro dispositivo conectado por red al desconectarse el S10 → serial fijo y aborto si falta.

---

## F8 — Niebla, minimapa, UX y guardado (2026-10-18)

**Qué se hizo**
- Niebla de guerra por jugador: `FogLayer` es una sola textura con 1 texel por celda (negro / explorado / visible), escalada con filtro; los enemigos fuera de vista se ocultan.
- Minimapa (toque = mover cámara, alertas rojas de ataque), grupos de control 1-5 (tocar recupera, mantener asigna), menú de pausa (Continuar, Guardar, Salir), menú principal (Continuar, Nueva partida, Tutorial).
- `SaveGame` + `SaveManager`: guardar y cargar la partida completa (unidades, edificios, recursos, techs, IA); autoguardado cada 120 s.
- Sonido de alerta "¡Te atacan!" con espera entre avisos.

**Tests**: `test_f8_ux` 24/24 (cargar = mismo estado). Gate lento `test_f8_slow_full_match`: Difícil vs Fácil con niebla y autoguardado termina en 28.4 min, gana Difícil, 0 errores de script.

**Problemas**
- La comparación de guardar/cargar se hacía después de avanzar frames → se compara justo tras cargar.
- Las primeras 3 corridas de la partida completa terminaron en empate a los 50 min. Con registros cada 5 min se vio que Fácil era casi igual a Normal, que Difícil no convertía su economía en ejército y que sus oleadas morían golpeando edificios. Se arregló en F9 (D50, D51).

---

## F9 — Arte, audio y contenido (2026-10-18, en curso)

**Qué se hizo**
- Arte por código: `Raster` (primitivas con borde y sombra), `UnitPainter` (12 unidades + animales, 6 poses: quieto, 2 de caminar, 2 de golpe, caído), `BuildingPainter` (13 edificios con techo, puerta y estandarte del jugador), `NaturePainter` (3 variantes de pasto/agua/bosque, minas, arbustos, carne, íconos). Todo se hornea en un atlas de 2048x1024 al arrancar.
- Animación: la unidad elige pose según lo que hace (camina, golpea, trabaja con la herramienta al talar/minar/construir) y se voltea hacia donde va. El cadáver usa la pose caída.
- Audio: `tools/gen_audio.py` sintetiza 47 efectos (UI, trabajo, combate, eventos, fanfarrias) y 3 temas (menú con arpa, paz con laúd y flauta, batalla con tambores y metales). `Sfx` con variantes, espacio mínimo por sonido y filtro "solo si se ve"; `Music` con fundidos y cambio a batalla al ver combate. Botón "Sonido: Sí/No" en la pausa.
- Contenido: tutorial de 5 misiones (`tutorial.json` + `TutorialDirector`, panel, flecha, Saltar); 3 mapas curados simétricos (Valle del Río, Bosque Cerrado, Tierras Doradas) y selector de mapa en Nueva partida.
- Balance: unidades que golpean un edificio se voltean contra soldados enemigos (D50); dificultades con perillas reales (D51).
- Documentos: `docs/LICENSES.md` (inventario), `docs/PLAYTEST-F9.md` (gate humano para Pedro).

**Medido en PC (render real 1280x720)**: stress150 60 fps, 32 draw calls; battle20 60 fps, 33-35 draw calls; APK debug 29.9 MB.

**En el S10**: F8 por toques 5/5; stress150 60 fps / 32 DC / 60 MB; battle20 60 fps; tutorial 60 fps / 42 DC.

**Problemas**
- El script de device borraba el log justo después de volver al menú y ya no encontraba el botón Continuar → se limpia antes de salir.
- Dos textos del tutorial tenían comas sin comillas en el CSV y se cortaban en el teléfono → CSV reescrito con comillas y test que revisa las 3 columnas de cada fila.
- El panel del tutorial no crecía con el texto y tapaba la barra de recursos → se ajusta al texto y baja a y=92.
- Duelo Difícil vs Normal: empates por (1) soldados golpeando muros, (2) oleadas paradas junto a objetivos destruidos, (3) bases sin aldeanos que tardaban 15 min en demolerse, (4) el mapa de ruido favorece una esquina. Con D50, D57-D59: 4 de 4 en Tierras Doradas.

**Primer playtest de Pedro (tutorial)** y arreglos:
1. "Los círculos se desplazan de los aldeanos": al caminar a la izquierda el sprite se dibujaba 48 px a la derecha (Godot voltea un rect de ancho negativo sin moverlo) → origen corregido; anillo como elipse a los pies.
2. "A aldeanos, casas y edificios les falta diseño" → arte v2 (D60).
3. "Todo cuesta C y no sé qué es C" → costos con íconos (D61).

---

## F9 noche — Jugabilidad "como el clásico" (2026-10-19)

Pedro ganó a Fácil y pidió comparar con el RTS clásico y revisar: "no da tiempo", "faltan murallas y torres", "mejores gráficos". Se escribió `docs/GAMEPLAY-REVIEW-2026-10-19.md`, se pasó por `/plan-ceo-review` (autónomo, decisiones recomendadas anotadas) y se implementó lo aceptado: murallas en línea, puertas automáticas, Centro Urbano con flechas, rutas parciales, ventana de paz por dificultad, aviso de ejército, torres y mercado para la IA, techo del CU por era, misión 6 del tutorial, arte v3 (unidades tres cuartos con escudos, árboles, orilla, agua). Diferido a `TODOS.md`: 4 direcciones, reliquias, maravilla, guarnición.

**Problemas**: la IA Difícil no llegaba a Era IV por falta de oro al final (minas secas) → vende en el mercado al ahorrar (D84); el precio mínimo 20 era un pozo sin fondo → 30 con recuperación más rápida. El jugador pasivo cae en 20-23 min con el CU disparando → gate 15-22 (D85). La prueba de rendimiento de PC varía 5x según la carga de la máquina: solo cuenta el S10.

---

## IDEAS-AOE2 — Lotes 1 y 2a (noche 2026-10-20)

Pedro pidió implementar `docs/IDEAS-AOE2.md` (análisis de mecánicas del clásico escrito por otra sesión) trabajando toda la noche sin preguntar. Lote 1 (D93-D99): guarnición + campana, reparar, carnero en Era III con embestida y muralla de 1,200 con grietas y brecha, alertas en 3 niveles con íconos en el minimapa y flecha en pantalla, informe "por qué gané/perdí", IA justa por defecto con tarjeta de bonos en el menú. Lote 2a (D100-D102): granjas finitas con resiembra automática, segundo Centro Urbano en Era III, veta de oro y canteras en el centro de cada mapa, compra en el mercado.

**Problemas**: con la guarnición, tocar el CU con aldeanos ya no lo seleccionaba (prueba de F4) → solo guarece si hay peligro (D99). La alerta de aldeanos atacados reemplaza a "¡Te atacan!" y el minimapa guarda una marca por lugar (la más específica). Los recursos nuevos (vetas, canteras) cambian la huella del atlas → `bake_art` de nuevo y campo `art` para pintarlos como las minas.

---

## F9 — Segundo playtest de Pedro (2026-10-19)

Pedro ganó a Fácil y pidió: victoria al destruir el edificio principal, edificios que caigan más rápido y se reconozcan, razón cuando no puede subir de era, descripciones de edificios y unidades, y un nivel de daño por tropa. Hecho en D87-D92. De paso se encontró y arregló una persecución infinita contra un objetivo inalcanzable (D92).
