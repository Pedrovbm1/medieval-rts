# MULTIPLAYER-PLAN — REALM (F10-mp)

> Arquitectura elegida para el multijugador de REALM y por qué. Primer objetivo:
> 1v1 entre dos teléfonos en la misma Wi-Fi (LAN con ENet de Godot), con camino
> a partidas por internet después. Escrito 2026-10-20.

## 1. Las dos opciones

Un RTS tiene cientos de unidades moviéndose a la vez. Hay dos maneras clásicas
de que dos teléfonos vean la misma partida:

### A. Lockstep determinista ("todos simulan, solo se mandan órdenes")

Cada teléfono corre la simulación completa (economía, rutas, combate). Por la
red **solo viajan las órdenes del jugador** ("mueve las unidades 12, 13 y 14 a
(3200, 1800)"), nunca el estado del mundo. Para que los dos mundos sean
idénticos, cada orden se aplica en el **mismo tick** de simulación en los dos
lados: la partida avanza en "turnos" cortos (100 ms) y una orden dada en el
turno T se ejecuta en el turno T+2. Si al llegar al turno T+2 no han llegado
las órdenes del rival, el juego espera (se congela) hasta que lleguen.

- **Ancho de banda**: minúsculo (unas decenas de bytes por turno). Da igual que
  haya 10 o 300 unidades.
- **Requisito duro**: la simulación tiene que ser **determinista**: mismas
  entradas → mismos bits de salida, en los dos teléfonos. Cualquier
  `randf()`, cualquier lectura del reloj real, cualquier "hago lo que me dé
  tiempo en este frame" rompe la igualdad y los mundos se separan
  (*desync*, desincronía) sin que nadie lo note hasta que un soldado está vivo
  en un teléfono y muerto en el otro.
- **Trampas**: imposible "inventar" recursos (el otro teléfono simula lo mismo
  y no coincide), pero sí se puede ver a través de la niebla con un cliente
  modificado (*maphack*), porque cada lado tiene el mundo entero.
- **Latencia**: la orden tarda 2-3 turnos en aplicarse (200-300 ms). En RTS es
  normal (Age of Empires y StarCraft funcionan así) y en Wi-Fi local ni se nota.
- **Online**: el mismo diseño sirve tal cual; solo cambia el transporte (relay
  o NAT punch) y el retraso de turnos sube a 4-6 con mala conexión.

### B. Host autoritativo con sincronía de estado

Un teléfono (el *host*, anfitrión) es el único que simula. El otro (el
*client*, cliente) le manda sus toques y recibe de vuelta la posición, vida y
estado de cada unidad varias veces por segundo, y dibuja lo que le dicen.

- **Determinismo**: no hace falta. Puede quedarse el código tal como está.
- **Ancho de banda**: con 300 unidades hay que mandar ~300 posiciones × 10-20
  veces por segundo = 50-150 KB/s hacia el cliente, más deltas, más
  interpolación para que no se vea a saltos. En Wi-Fi aguanta; por internet
  móvil ya es un problema y hay que comprimir e interpolar mucho.
- **Justicia**: el host juega con latencia cero y el cliente con el doble de
  ping (sus órdenes van y el estado vuelve). En 1v1 competitivo se siente.
- **Trabajo**: hay que escribir serialización de todo el estado (unidades,
  edificios, colas, tareas, niebla), reconciliación en el cliente, predicción
  de movimiento y un "HUD remoto" que pide al host cada dato (recursos,
  población, colas). Es el doble de código y toca cada sistema.
- **Online**: funciona igual, pero el host carga con todo el tráfico.

## 2. Decisión: lockstep determinista

Para REALM elegimos **A, lockstep**, por estas razones:

1. **Es un juego de muchas unidades y pocos clics.** Lockstep manda solo clics;
   la opción B escala con las unidades, que es justo lo que crece en un RTS.
2. **Las pruebas ya simulan el mundo entero en headless.** Lockstep reutiliza
   la simulación tal cual; B obliga a partir el juego en "simulación" y
   "vista" y a escribir una vista remota.
3. **Las repeticiones (replays) y "guardar partida" salen gratis.** Una partida
   es la semilla más la lista de órdenes con su tick: se puede reproducir
   entera en una prueba, que es exactamente la prueba (a) de la suite.
4. **El costo del determinismo es acotado y conocido** (sección 3): son seis
   puntos concretos del código, no un rediseño.
5. **Camino a online idéntico.** Solo cambia el transporte y el número de
   turnos de retraso.

Lo que aceptamos a cambio: cualquier bug de determinismo se ve como desync, así
que necesitamos (a) detectarlo pronto con un **hash de estado** periódico y (b)
una prueba automática que simule dos mundos con las mismas órdenes.

### Limitación honesta: PC contra teléfono

Dos teléfonos con el **mismo APK** (ambos ARM64, misma versión de Godot) dan
los mismos bits en coma flotante. PC (x86-64) contra teléfono (ARM64) **puede**
divergir: el compilador de ARM fusiona multiplicación y suma (`fma`) en el
código C++ de Godot (`Vector2.length()`, `dot`, etc.) y `sin/cos/atan2` vienen
de distintas libm. El primer objetivo son dos teléfonos (o dos instancias en
el mismo PC); PC↔teléfono sirve para probar el lobby y el protocolo, y la
pantalla de desync dirá si diverge. Si algún día importa, la salida es
aritmética en enteros/punto fijo en la simulación (trabajo grande, no para F10).

## 3. Qué parte del juego hoy NO es determinista y cómo se arregla

| # | Dónde | Problema | Arreglo |
|---|---|---|---|
| 1 | `World.eject()` | `randf_range` global para dispersar al salir de un edificio | RNG propio del mundo (`World.rng`) sembrado con la semilla de la partida (`match_seed`). Es el único `randf` global en la simulación; los demás (`Sfx`, `Rubble`) son solo visuales/sonido |
| 2 | `PathQueue.process()` | Tope de **tiempo real** (`path_budget_usec`): en un teléfono lento se calculan 2 rutas en el tick, en el rápido 8 → las unidades arrancan en ticks distintos | `PathQueue.deterministic = true` en partidas en red (y en las pruebas de determinismo): se calculan exactamente `paths_per_frame` rutas por tick, sin mirar el reloj. En solitario se conserva el tope de tiempo (rendimiento en el teléfono) |
| 3 | `MovementSystem._separation()` | Desempate con `get_instance_id()` cuando dos unidades están en el mismo punto: los ids de instancia cambian entre procesos | Desempate con `unit.sim_id` (id de simulación, contador del mundo, igual en ambos lados) |
| 4 | `Building.take_damage / recently_hit`, `ConstructionSystem._tick_gates` | `Time.get_ticks_msec()` (reloj real) para "golpeado hace < 20 s" y el retraso de las puertas | Reloj de simulación: `World.sim_time` (segundos acumulados por tick de física). Las puertas y `recently_hit` leen ese reloj. *(`_tick_gates` está en el archivo que edita la otra sesión; se deja anotado y se cambia cuando termine)* |
| 5 | `AIController` | RNG propio (`rng.seed = ai_seed`) — ya es determinista si los dos lados usan la misma semilla; y `elapsed` va por delta de física | Nada que arreglar: el lobby manda la semilla. En 1v1 humano no hay IA; si se añade una, corre igual en los dos teléfonos |
| 6 | Diccionarios | En Godot 4 los `Dictionary` **conservan el orden de inserción**, así que iterarlos es determinista mientras las inserciones sean iguales (lo son: mismas órdenes, mismos ticks). Las claves por objeto (`room[b]`) se insertan en el orden de `world.buildings`, también igual | Nada; se documenta para no asustarse |
| 7 | `Engine.time_scale` (botón x1/x2/x3) | Escala el `delta` de cada tick de física; si un lado va a x2, su mundo avanza el doble por tick | En red el botón de velocidad se desactiva y `time_scale` se fija en 1 |
| 8 | `_process` vs `_physics_process` | Todo lo que cambia el estado de juego debe ir en el tick de física. Hoy ya es así (movimiento, tareas, combate, construcción, visión, reglas); `_process` solo dibuja (minimapa, colocación fantasma, puntero) | Se comprueba con la prueba (a): dos mundos secuenciales con las mismas órdenes dan el mismo hash tick a tick |
| 9 | Ids de entidades en las órdenes | Las órdenes de red no pueden llevar referencias a nodos | Cada unidad, edificio y nodo de recurso recibe un `sim_id` al crearse (contador único del mundo); las órdenes llevan ids y el mundo los resuelve con `World.by_sim_id()` |

Lo que **no** rompe el determinismo aunque parezca: `Time.get_ticks_usec` para
medir rendimiento (`last_step_usec`), `Sfx`/`Music`, el HUD, la cámara, los
`Timer` de la interfaz (refresco de ociosos), `sort_custom` (no es estable
pero sí determinista para la misma entrada).

## 4. Diseño

### 4.1 Capa de órdenes (`game/systems/net/command_bus.gd`)

Toda acción del jugador que cambia el mundo pasa por **una sola función**:

```
CommandBus.submit({"type": "order", "player": 0, "units": [12, 13], "target": {"kind": "node", "id": 40}, "pos": [3200.0, 1800.0], "formation": "line", "attack_move": false})
```

Tipos: `order` (mover/atacar/recolectar/construir-en-cimiento/reparar/cazar/
entregar/guarecer/reliquia/comerciar, lo decide el objetivo como hoy en
`SelectionController._task_for`), `attack_move`, `stop`, `hold`, `build`,
`build_line` (murallas), `train` (unidad o `#tech`), `dequeue`,
`cancel_construction`, `sell`, `buy`, `bell`, `eject`, `rally`, `gate`,
`resign`. El diccionario solo lleva tipos planos (int, float, String, Array),
así se manda por ENet y se puede guardar en JSON para repeticiones.

- `CommandBus.apply(cmd)` es el **único ejecutor**: resuelve los `sim_id` y
  llama a los sistemas (`behavior.assign`, `movement.command_move`,
  `construction.enqueue`, etc.). La lógica de "qué tarea toca según el
  objetivo" vive en `OrderResolver` (estático), compartida por la selección
  (para el color del marcador y soltar a los aldeanos) y por `apply`.
- **Partida local**: `submit` aplica en el acto. Es equivalente a "al inicio
  del próximo tick" porque la entrada se procesa entre ticks de física, y así
  las pruebas que hacen `issue_order` y comprueban `unit.task` en la misma
  línea siguen pasando. Cada orden se anota con su tick en `history`
  (repeticiones y la prueba (a)).
- **Partida en red**: `submit` encola la orden para el turno `T + delay` y la
  manda al rival; `apply` corre en ese turno en los dos lados.

### 4.2 Lockstep (`game/systems/net/lockstep.gd`, nodo `Lockstep` en main)

- `turn_ticks = 6` (100 ms a 60 Hz), `delay_turns = 2`, `hash_every_turns = 20`
  (2 s). Todo en `rules.json` sección `net`.
- Al final de cada turno T se manda al rival un paquete fiable
  `{"turn": T + delay, "cmds": [...], "hash_turn": t, "hash": h}` (vacío si no
  hubo órdenes: el paquete vacío es lo que deja avanzar al otro).
- Al **inicio** del turno T: si falta el paquete del rival para T, el nodo
  pone `process_mode = DISABLED` en `World`, `MatchRules` y las IA → la
  simulación no avanza ni un tick (la interfaz sigue viva y muestra
  "Esperando al rival…" tras 0.5 s). Cuando llega, se aplican las órdenes de
  todos los jugadores en orden fijo (jugador 0, luego 1; dentro de cada uno en
  orden de envío) y se vuelve a habilitar el proceso.
- El nodo corre con `process_priority = -100` para decidir antes de que
  `World` procese ese mismo tick.
- Arranque sincronizado: los dos cargan `main` con la misma semilla y mapa;
  cada uno manda `ready`; la simulación arranca (turno 0) cuando los dos están
  listos.

### 4.3 Hash de estado (`World.state_hash()`)

Un número que resume el mundo: tick, recursos de cada jugador, y por cada
unidad/edificio/nodo (en el orden de sus arrays) `sim_id`, dueño, posición
exacta (bits), HP, tarea y carga. Se calcula al inicio del turno cada
`hash_every_turns` y viaja con el paquete; el que lo recibe lo compara con el
suyo del mismo turno. Si difiere: señal `desync(turn)`, banner rojo
"Desincronización en el turno N" y la partida sigue (para poder mirar); la
prueba (a) usa la misma función tick a tick.

### 4.4 Lobby LAN (`game/autoload/net_session.gd` + menú)

- Menú → **Multijugador** → *Crear partida* (muestra la IP local, deja elegir
  mapa, espera al rival, botón *Iniciar*) / *Unirse con IP* (campo de IP +
  *Conectar*). Puerto 7777 (`rules.json net.port`).
- `NetSession` (autoload) guarda el peer de ENet, el rol (host/cliente), el
  mapa, la semilla y `local_player` (host = 0, cliente = 1). Al iniciar, el
  host manda `start_match(map, seed)` por RPC; los dos cambian a `main`.
- En red: sin IA, sin autoguardado, sin botón de velocidad, la cámara arranca
  en el inicio del jugador local, el HUD y la niebla usan `local_player`
  (`GameState.PLAYER_HUMAN` pasa de constante a variable con el mismo nombre
  para no tocar 40 sitios).

### 4.5 Pruebas (`game/tests/test_f10_multiplayer.gd`)

- (a) **Determinismo**: mundo A con semilla S y una lista de órdenes en ticks
  fijos (mover, recolectar, construir, entrenar, atacar) → se guarda el hash
  cada 30 ticks durante N ticks; se cierra; mundo B con lo mismo → hashes
  iguales en cada punto. Se corre dos veces sobre el **mismo proceso** porque
  `GameState` es un autoload compartido (dos mundos a la vez se pisarían los
  recursos).
- (b) **Lobby y turnos**: dos ramas del árbol con su propio `MultiplayerAPI`
  (host en `localhost:7777`, cliente conectado), dos nodos `Lockstep`
  intercambian paquetes de turno; se comprueba que el turno no avanza sin el
  paquete del rival, que avanza al llegar, que las órdenes se aplican en el
  mismo turno en los dos lados y que un hash distinto dispara `desync`.

## 5. Camino a online (después de F10)

1. Mismo protocolo; `delay_turns` adaptativo (2 en LAN, 4-6 por internet) a
   partir del RTT medido con los propios paquetes de turno.
2. Transporte: relay (un servidor pequeño que reenvía paquetes ENet, o
   WebRTC con `WebRTCMultiplayerPeer`) para atravesar NAT; el lobby pasa a un
   servicio de salas (código de sala en vez de IP).
3. Reconexión: el que se cae pide al otro un `SaveGame.snapshot()` (ya
   existe) y se reengancha desde ese turno.
4. Anti-maphack: solo si hay ranking; implicaría un servidor que simule.

## 6. Glosario para Pedro

- **Lockstep**: los dos teléfonos avanzan "al mismo paso": nadie da el
  siguiente paso hasta tener las órdenes del otro para ese paso. Como dos
  panaderos siguiendo la misma receta al mismo ritmo: si cada uno echa los
  mismos ingredientes en el mismo orden, salen dos panes iguales.
- **Determinismo**: con las mismas entradas sale exactamente lo mismo, bit a
  bit. Un dado (`randf`), un reloj de pared o "hago lo que me dé tiempo" lo
  rompen.
- **Hash de estado**: una "huella digital" numérica del mundo entero. Si las
  huellas de los dos teléfonos coinciden, los mundos son iguales; si no, hubo
  desync y sabemos en qué turno empezó.
- **Tick**: un paso de simulación (1/60 s). **Turno**: 6 ticks (100 ms), la
  unidad en que se intercambian órdenes.
