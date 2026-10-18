# BUILD-STATE — REALM

> Estado vivo del build autónomo. Se actualiza al cerrar cada fase.
> Una sesión nueva retoma desde aquí.

## Fase actual
**F9 — Arte, audio y contenido** (en curso; F8 cerrada)

## Completadas
| Fase | Commit | Fecha | Gate |
|---|---|---|---|
| F0 | 2007d99, 2638e05 | 2026-10-17 | Cumplido en Galaxy S10 (arranque 0.6-0.9 s, pan 60 fps, pinch probado por Pedro) |
| F1 | 4747fd7 | 2026-10-17 | 67/67 headless, 7/7 adb en S10, gate humano 10/10 aprobado por Pedro |
| F2 | 3784c4d | 2026-10-17 | Headless 96/96. S10: 150 unidades a 59.5-60 fps (peor frame en juego 28 ms; 149 ms solo en la carga), lake50 50/50 en 57 s. Draw calls 189-543 → se corrigió en F3 con atlas (15) |
| F3 | ver BUILD-LOG | 2026-10-17 | 132/132 headless (12 aldeanos 10 min sin trabarse ni perder carga; campana; tasas JSON + modificadores; oveja/ciervo/jabalí con lure). S10: 150 unidades 60 fps con 15 draw calls; eco12 60 fps 15-32 DC; F1 adb 7/7 |
| F4 | ver BUILD-LOG | 2026-10-18 | 168/168 headless: base completa (2 casas, granja, aserradero, cuartel) en 64 s de juego con toques simulados; no construir sobre recursos/árboles/unidades; cancelar devuelve 50%. S10: flujo real Construir→Casa→✓ y entrenar aldeano por adb 5/5, F1 7/7, 60 fps 25-41 DC |
| F5 | ver BUILD-LOG | 2026-10-18 | 192/192 headless: 10 lanceros vencen a 10 caballeros perdiendo 37% HP; 10 arqueros vencen a 10 lanceros sin bajas; 20v20 mixto termina en 49 s; 216 muertes sin fugas (24 nodos creados, huérfanos = pool). S10: batalla 20v20 a 60 fps con 15 DC |
| F5.5 | ver BUILD-LOG | 2026-10-18 | 205/205 headless. Roster de 12: aldeano, explorador, miliciano, lancero, espadachín, arquero, escaramuzador, caballero, camellero (única de Northvale), ariete, mangonel, monje; cada nueva gana su duelo de rol y las 12 actúan en el ejército mixto |
| F6 | ver BUILD-LOG | 2026-10-18 | Pasivo pierde vs IA Normal en ~19.8 min; IA sin map hack (0 ataques sin explorar; ataca al ver la base); pantalla de fin. Difícil vs Normal: NO cumplido: 3 duelos de 45 min terminaron en empate tras 3 rondas de ajustes (ver Blockers) |
| F7 | ver BUILD-LOG | 2026-10-18 | 4 eras con requisito de 2 edificios; 24 techs en 3 ramas sin huérfanas, cada una cambia un número visible; IA Difícil llega a Era IV en ~22-24 min; torres |
| F8 | ver BUILD-LOG | 2026-10-18 | Niebla por jugador (textura de 1 texel por celda), minimapa con alertas, grupos de control, menú de pausa, guardar/cargar (cargar = mismo estado, 24/24), autoguardado 120 s, menú principal. Partida completa Difícil vs Fácil con niebla y autoguardado: termina en 28-29 min, gana Difícil, 0 errores (tras arreglar F9-D50). Medición en S10 pendiente (teléfono ocupado por Pedro/AppScanner) |

## Siguiente
F9 en curso. Hecho: arte por código integrado (atlas, poses, terreno con variantes, íconos), audio (47 SFX + 3 temas, música de batalla), tutorial de 5 misiones, 3 mapas curados simétricos con selector, inventario de licencias, playtest humano documentado (`docs/PLAYTEST-F9.md`), IA con dificultades reales. Falta: revisar el duelo Difícil vs Normal (gate F6) con los arreglos nuevos, medir F8/F9 en el S10 cuando Pedro lo suelte (`tools/device_test_f8.sh`, `device_bench.sh stress150`), gate humano de F9 (Pedro). Después F10 (necesita cuenta de Play Console de Pedro).

## Entorno
| Pieza | Valor |
|---|---|
| Godot | 4.7.2 stable (winget). Consola: `C:/Users/pedro/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe` |
| JDK para export | 17 (`C:\Users\pedro\AppData\Local\Programs\devtools\jdk-17.0.20.1+1`). `JAVA_HOME` del sistema apunta a 21: pasar JAVA_HOME=17 al exportar |
| Android SDK | `C:\Users\pedro\AppData\Local\Android\Sdk` |
| Device | Samsung Galaxy S10 (SM-G975U1), Android 12, 2280x1080, adb id R58M154WY9A |
| Paquete | `dev.pedro.realm`, actividad `com.godot.game.GodotAppLauncher` |
| Teléfono compartido | Con AppScanner (`com.pedro.escaner`, sesión "F6 PDF multipágina") y el juego de Mateo (`mx.mateo.misioncolima`, sesión "Revisión videojuego"). Reglas: no tocar pantalla ni `am start` si otra app está al frente (`dumpsys activity activities` → `mResumedActivity`); `adb install -r` siempre se vale; al terminar `am force-stop` + launcher; avisar "tomo el S10" / "S10 libre". Los scripts lo hacen con `tools/device_guard.sh` |

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
# prueba real de construir y entrenar en el teléfono (F4)
bash tools/device_test_f4.sh
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
| D17 | F3 | Árboles = datos por celda (no nodos); al agotarse la celda pasa a pasto y se libera en NavGrid | ~2000 árboles sin costo de dibujo |
| D18 | F3 | Todo el arte placeholder en UN atlas generado en runtime (`PlaceholderArt` + fuente de píxeles propia `PixelFont`) | De 189-543 a 15 draw calls con 150 unidades |
| D19 | F3 | Tareas por unidad (`UnitTask`: `GatherTask`, `HuntTask`) avanzadas por `BehaviorSystem` en un loop | Base para BuildTask (F4) y AttackTask (F5) |
| D20 | F3 | Tasas por subtipo (bayas, carne, granja, madera, oro, piedra) en `units.json` × multiplicador por jugador (`GameState.multipliers`, para techs F7) | Lección de 0 A.D.: cachear modificadores |
| D21 | F3 | Ciervo huye solo al recibir daño; oveja se une al primer jugador cerca; jabalí pelea y el cazador lo "lurea" a la Plaza, donde ayudan aldeanos cercanos | "Lure simple" del plan sin micro obligatorio |
| D22 | F3 | Granja infinita (1 trabajador); cambiar de recurso tira la carga | Plan 4.5; regla del género |
| D24 | F4 | Construir: botón en el panel de aldeanos → menú → fantasma que se mueve con tap o arrastrándolo desde encima (si el arrastre empieza fuera, mueve la cámara) → ✓ o doble tap | Spec 6.3 sin perder el pan |
| D25 | F4 | El costo se paga al confirmar; cancelar una obra devuelve 50% (`rules.json`); quitar de la cola devuelve 100% | Plan F4 |
| D26 | F4 | Primer constructor a velocidad 1.0, cada extra a 0.6 | Más manos ayudan sin volverse instantáneo |
| D27 | F4 | Tocar un edificio propio con selección: ayuda a construir si es obra, siembra si es granja, entrega si cargan y aplica; si no, selecciona el edificio | En F4 tocar la Plaza con aldeanos los movía ahí |
| D28 | F4 | Al terminar: constructores de granja la siembran; de aserradero/campamento recolectan cerca; casa/cuartel → ociosos | Comportamiento clásico, menos micro |
| D29 | F4 | Punto de reunión: con un edificio productor seleccionado, tocar el mapa lo fija; aldeanos que salen hacia un recurso empiezan a recolectarlo | Plan HUD 6.2 |
| D30 | F4 | El jabalí tiene correa de 1600 px y el cazador no ataca mientras lo "lurea" | Con 900 px se rendía antes de llegar a la Plaza |
| D31 | F5 | Daño tipado (corte/perforante/impacto) con armadura por tipo y bonus planos por clase: `max(1, Σ max(0, daño_t - armadura_t) + Σ bonus[clase])` | Fórmula del plan + recomendación de 0 A.D. |
| D32 | F5 | Wind-up visible (`prepare_s`) separado de la cadencia (`repeat_s`), con trazo de "golpe que viene" | Legibilidad del combate |
| D33 | F5 | Posturas como flags en `data/stances.json` (agresiva, defensiva, quieta, pasiva); aldeanos pasivos por defecto | 0 A.D. §3.2; cero código por postura |
| D34 | F5 | Attack-move (`CombatSystem.attack_move`): caminar peleando con lo que aparezca y luego seguir. Disponible en código; botón en HUD queda para F8 | Sin él, ejércitos que se cruzan quedan fuera de vista |
| D35 | F5 | Unidades muertas: cadáver 0.8 s y luego al pool de `World` por tipo (fuera del árbol, señales desconectadas); flechas en pool de `CombatSystem` | Gate "sin fugas tras 200 muertes" |
| D36 | F5 | Eras de unidades/edificios ya en datos (lancero/arquero II, caballero III, ariete IV); se activan en F7 | Datos listos para F7 |
| D37 | F5.5 | Roster de 12 con roles: escaramuzador (anti-arquero, armadura perforante), espadachín (infantería pesada era III), camellero (anti-caballería, única de Northvale vía `unique_to`), mangonel (área 56 px con caída 100→50%, rango mínimo, sin fuego amigo), monje (cura 3 HP/s, sin ataque) | Plan F5.5 |
| D38 | F5.5 | Monasterio (era III) entrena monjes; Taller de asedio pasa a era III (mangonel) | Ubicar cada unidad en su edificio |
| D39 | F6 | IA = FSM por fases (apertura/desarrollo/hostigamiento/empuje) que piensa cada 1.5-3 s; números en `data/ai.json`; 3 dificultades (Difícil: +20% recolección, ejército x1.3, fases 15% antes) | Plan 4.8 |
| D40 | F6 | Visión honesta: `VisionGrid` por jugador (sin ver / explorado / visible); la IA recuerda edificios enemigos vistos y solo ataca posiciones exploradas | "Sin map hack" |
| D41 | F6 | Derrota = sin edificios; solo compiten jugadores que empezaron con edificios (sandbox/pruebas nunca terminan) | Bug encontrado en el S10: victoria instantánea en demos |
| D42 | F6 | Suites lentas (`*_slow*`, IA vs IA) solo con `-- slow` | La suite normal no debe tardar 30 min |
| D43 | F7 | Investigación en las colas de edificios como ítems `#tech` / `#eraN`; efectos = modificadores por jugador ya leídos por los sistemas (`TechSystem.CONSUMED_KEYS`) | Cero código por tecnología |
| D44 | F7 | Costos de era bajados (II 350C; III 600C+200O; IV 800C+500O) | Con los originales la IA no podía tener ejército y llegar a Era IV en 25 min (partidas de 20-30 min) |
| D45 | F7 | IA: ahorra para la era manteniendo un ejército mínimo por fase; pausa aldeanos al "subir" (18/26/34); turno de investigación (la más barata) | Equilibra "pasivo pierde en 15-20" y "Era IV en 25" |
| D46 | F7 | Torre de vigía con flechas propias; Almenas/Química la mejoran | Plan 2.4 (defensa) |
| D47 | F8 | Niebla configurable por escenario (`"fog": false` en pruebas/demos); `VisionSystem` oculta enemigos no visibles | Las pruebas de rendimiento no miden la niebla por accidente |
| D48 | F8 | Menú principal como escena inicial; la partida se lanza con `GameState.launch` (escenario, IA, mapa o slot a cargar); autoguardado cada 120 s solo con IA; grupos 1-5: tocar = recuperar, mantener 0.5 s = asignar | Patrón móvil: un toque hace lo común, mantener hace lo raro |
| D49 | F8 | `SaveGame` guarda unidades/edificios/recursos/techs/IA y regenera el terreno desde la semilla del mapa + celdas cortadas | Guardados chicos (KB) y deterministas |
| D50 | F9 | Unidades que eligieron un edificio por su cuenta lo sueltan si llega un soldado enemigo (las órdenes explícitas se respetan) | Causa real de los empates IA vs IA: los atacantes golpeaban muros mientras los mataban |
| D51 | F9 | Dificultades con perillas reales en `ai.json`: aldeanos (×0.6/×1.0), era máxima (Fácil III), probabilidad de investigar, tope de ejército (Fácil 18), multiplicador de producción (Difícil ×1.5) y +1 edificio militar por cada 1200 recursos acumulados | Antes Fácil ≈ Normal y Difícil no convertía economía en ejército |
| D52 | F9 | Arte 100% por código (`systems/render/*_painter.gd`) horneado en un atlas de 2048x1024 al arrancar; 6 poses por unidad; espejo con ancho negativo; 3 variantes de terreno por celda con hash estable | Original, sin archivos binarios, 32-35 draw calls con HUD |
| D53 | F9 | Audio sintetizado por `tools/gen_audio.py` (stdlib), WAV importado como QOA; sonidos del mundo solo si se ven en pantalla, con espacio mínimo por id; música cambia a batalla al ver combate entre jugadores (no caza) | Original y sin licencias; sin ruido en batallas grandes |
| D54 | F9 | Mapas curados con simetría puntual (`"symmetry": "point"`): se genera y puebla la mitad y se refleja | Justicia exacta entre las dos bases |
| D55 | F9 | Tutorial data-driven (`tutorial.json`) con metas que escuchan señales existentes del EventBus; no se guarda | Cero rutas especiales en los sistemas que enseña |
| D56 | F9 | IA reparte de nuevo a los recolectores: si ahorra para una era (o un recurso baja de 150) mueve hasta 2 aldeanos por turno del recurso que sobra (≥600) al que falta | Solo se asignaban aldeanos ociosos: sobraban 2000 de madera y faltaba oro para la Era IV |
| D23 | F3 | Recursos alrededor de cada inicio desde `start_layout` del mapa (grupos que se tocan para bayas/oro) | Inicio justo y data-driven |

## Blockers
- **Gate F6 "Difícil gana a Normal 3 de 4"**: Pedro decidió seguir ("Si avanza,") y revisarlo en F9. En F9 se encontró la causa (D50) y se dieron perillas reales a las dificultades (D51): Difícil ya gana a Fácil en 28 min. Falta volver a correr el duelo Difícil vs Normal (`-- suite=test_f6_slow`).
- S10 ocupado por Pedro probando AppScanner (aviso de la sesión "F6 PDF multipágina", 2026-10-18): no tomarlo hasta que lo suelte. Mediciones F8/F9 en device pendientes.
- 2026-10-18: el S10 se desconectó de adb; el script de F7 alcanzó otro dispositivo por red (192.168.100.10:5555, Fire TV de otra sesión): mandó 1 toque, 1 captura y Home. Ya corregido: todos los scripts fijan `ANDROID_SERIAL=R58M154WY9A` y abortan si no está.
- Riesgo visto 1 vez: el S10 cerró la app ~1 s después de arrancar (Samsung Game Optimizing Service, "KILL_YOURSELF"); no se repitió.

## Últimos tests
- F9 (parcial): suite normal F0-F9 318/318 (F6 y F7 re-corridas solas tras el ajuste de IA), 0 errores de script. F9 art+audio 19/19, mapas+tutorial 29/29, balance 3/3. Gate F8 lento: Difícil gana a Fácil en 28.4 y 29.3 min. PC 1280x720: stress150 60 fps / 32 DC; battle20 60 fps / 33-35 DC; APK debug 29.9 MB.
- F0: 22/22 headless. Device: arranque 0.6-0.9 s, 60 fps en pan.
- F6+F7: suite normal F0-F5.5 sin cambios + F2 29/29, F6 17/17, F7 21/21 corridas solas. Nota: tiempos y economía de la IA dependen de la carga de CPU (la cola de rutas tiene tope de tiempo real); correr las suites de IA sin otras corridas en paralelo.
- F5.5: 205/205 headless (~8 min).
- F5: 192/192 headless (~6 min). S10: `bash tools/device_bench.sh battle20 40` → 60 fps, 15 DC, 44 MB.
- F4: 168/168 headless (~4 min). S10 por adb: `tools/device_test_f4.sh` 5/5 (caja, Construir, Casa, ✓, entrenar en Plaza), F1 7/7. Nota: tiempos de PC varían 2x con la carga; el umbral de PC es solo alarma (6 ms), el presupuesto real se mide en el S10.
- F3: 132/132 headless (~2 min). 10 min de economía: comida 750, madera 879, oro 770, piedra 360; peor aldeano quieto 5 s; extraído = entregado + cargado + tirado. S10: stress150 60 fps / 15 DC / 43 MB; eco12 60 fps; F1 adb 7/7.
- F2: 96/96 headless. Lake50: 50/50 llegan, ninguna pisa agua. Muro: re-planifica y 10/10 llegan; quitarlo re-planifica a todas. Stress150 (PC): movimiento 1.5-1.9 ms promedio, peor ~4-6 ms.
- F1: 67/67 headless (incluye 10/10 ciclos simulados y 100 taps con temblor). Device S10 por adb (`bash tools/device_test_f1.sh`): 7/7, incluye 10/10 ciclos selección + orden. 60 fps.
