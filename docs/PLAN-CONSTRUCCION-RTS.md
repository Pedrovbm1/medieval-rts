# Project REALM — RTS medieval para Android
## Investigación + plan de construcción completo

> **Qué es esto**: el plan maestro para construir un juego RTS (real-time strategy / estrategia en tiempo real) medieval para Android, inspirado en los clásicos del género (Age of Empires II como referencia de diseño). Es un juego **original**: mecánicas de género (ideas, no protegidas), con arte, nombres, datos y código 100% propios.
> **Cómo usarlo**: cada fase (F0–F10) se trabaja por separado con Claude. Copia la fase + el prompt del Apéndice A. No avances de fase sin cumplir sus criterios de aceptación.
> **Codename**: REALM (nombre final pendiente — elige Pedro).

---

## 0. Resumen ejecutivo

| Pregunta | Respuesta |
|---|---|
| ¿Es viable? | Sí. Un RTS 2D de un solo jugador contra IA, con ~100-150 unidades en pantalla, es un proyecto realista para un builder-operator asistido por IA, en Godot 4, para Android. |
| ¿Por qué ahora? | Godot 4 tiene pipeline 2D nativo, `AStarGrid2D` para pathfinding en grid y export Android directo. Builds ~25-40 MB vs ~35-80 MB de Unity, con mejor rendimiento 2D en benchmarks. |
| ¿Hay mercado? | El "Age of Empires Mobile" oficial (Microsoft/TiMi, oct 2024) es un city-builder con gacha de héroes, **no un RTS clásico**. Reviews recurrentes: "it's just a city builder". El RTS clásico táctil real está desatendido en móvil. |
| ¿Es legal? | Sí, si se respetan las reglas de originalidad (sección 2). Las mecánicas del género no están protegidas. Los assets, nombres de facciones, música y código de Microsoft sí — se usan cero. |
| Esfuerzo honesto | MVP jugable (F0–F8): semanas de trabajo enfocado, no un fin de semana. Contenido completo (F9–F10): meses. El plan por fases reduce el riesgo de morir a mitad de camino. |
| Riesgo #1 | El control táctil. Un RTS vive o muere por cómo se siente seleccionar y mandar unidades con el dedo. Por eso la fase F1 se prueba en teléfono físico antes de construir nada más. |

---

## 1. Metodología y reglas del proyecto

### 1.1 Cómo se investigó
- Fuentes públicas: documentación oficial de Godot, wikis del género RTS, sitios de datos de AoE II (aoedb, fandom), reviews y fichas de tienda del AoE Mobile oficial, foros de Godot y gamedev sobre controles táctiles y rendimiento.
- Sin análisis de binarios ni extracción de archivos del juego original. Para este proyecto no hace falta: las mecánicas están documentadas públicamente y las decisiones de diseño se toman propias.
- Cada afirmación técnica de este documento se contrastó con: documentación de Godot 4.x, reportes de desarrolladores con RTS en Godot, y datos de rendimiento 2D/Android.

### 1.2 Reglas de originalidad (NO negociables)
✅ **SÍ se puede**:
- Usar mecánicas y estructuras del género: recursos, eras, aldeanos, counters, tech tree, fog of war.
- Usar términos históricos y genéricos: lancero, arquero, caballero, muralla, castillo.
- Inspirarse en el "feel" del juego (ritmo, sonidos de confirmación, feedback).

❌ **NO se puede**:
- Copiar sprites, animaciones, música, SFX, voces, UI art o logos del juego original.
- Usar el nombre "Age of Empires" ni ningún nombre/civ de Microsoft (Britons, Teutons, etc.) ni el nombre "AoE".
- Extraer/descompilar archivos del juego original (.dat, .slp, art) ni portar su código.
- Copiar tablas de balance completas tal cual. Nuestros números se diseñan propios y se iteran con playtest.

### 1.3 Assets
Todo el arte empieza como **placeholders** (formas de colores) y se reemplaza en F9 con arte original (pixel art propio, generado con IA, o packs CC0 con licencia verificada — Kenney, OpenGameArt). Música/SFX igual: CC0 o generados.

---

## 2. Análisis del género (benchmark: AoE II)

### 2.1 El loop central
```
Explorar → Recolectar recursos → Construir economía → Avanzar de era
   → Producir ejército → Atacar → Destruir al enemigo (o aguantar y vencer)
```
La tensión del género: cada minuto de economía es un minuto sin ejército, y viceversa. El jugador balancea macro (economía) y micro (combate) en tiempo real.

### 2.2 Recursos (4 clásicos)
| Recurso | De dónde se obtiene | Para qué se usa |
|---|---|---|
| Comida | Arbustos, caza, granjas | Aldeanos, infantería, avanzar de era |
| Madera | Árboles | Edificios, arqueros, granjas |
| Oro | Minas de oro | Unidades avanzadas, tecnologías |
| Piedra | Minas de piedra | Torres, murallas, castillos |

Puntos clave del diseño original:
- Los aldeanos cargan ~10 unidades por viaje y las depositan en un **drop-off** (punto de entrega): Centro urbano (todo) y campamentos especializados (madera/minería).
- Las granjas dan comida infinita a cambio de madera → mecanismo económico clásico.
- **Tiempo idle del aldeano = la mayor pérdida de eficiencia** (dato citado en guías del género). El HUD debe mostrar aldeanos desocupados.

### 2.3 Eras
El género clásico tiene 4 edades (Dark → Feudal → Castle → Imperial), cada una con:
- Costo creciente en comida (+oro en las últimas).
- Requisitos de edificios (ej. 2 edificios para la era II).
- Desbloqueo de unidades, edificios y tecnologías.

**Nuestro diseño (original)**: 4 eras con nombres propios: **I. Asentamientos → II. Fortalezas → III. Coronas → IV. Imperio**, con costos propios y partidas objetivo de 20-30 min (más cortas que el PC clásico, porque móvil pide partidas rápidas).

### 2.4 Edificios (por rol)
- **Economía**: Centro urbano (todo en uno + produce aldeanos), Casa (+pop), Granja, Aserradero (drop-off madera), Campamento minero (drop-off oro/piedra), Mercado (fase 2).
- **Militar**: Cuartel (infantería), Galería de tiro (arqueros), Establo (caballería), Taller de asedio (fase 2).
- **Tecnología**: Herrería (ataque/armadura), Universidad (fase 2).
- **Defensa**: Torre de vigía, Muralla + puerta, Castillo (fase 2).
- **Victoria alternativa**: Maravilla (Wonder) — construirla y defenderla N segundos.

### 2.5 Unidades y counter system
Cuatro clases: **infantería, arqueros, caballería, asedio**. El triángulo clásico (soft counters por multiplicadores de daño):

```
    Lancero ──pega──▶ Caballería ──pega──▶ Arquero ──pega──▶ Lancero
       ▲                                        │
       └──────────── Miliciano (generalista) ◀──┘
```

- El daño se calcula: `daño = max(1, ataque + bonus_vs_clase − armadura)` con cadencia por unidad.
- Esto da profundidad estratégica con pocas unidades: nunca existe "la mejor unidad".

### 2.6 Tech tree
El clásico tiene 70+ tecnologías por civilización. Para nuestro MVP: ~14-16 techs propias en 3 ramas (economía, militar, defensa), investigadas en edificios (Centro, Herrería, Universidad) con costo y tiempo real.

### 2.7 Niebla de guerra y mapa
- **Fog of war**: lo explorado queda "recordado" pero opaco; lo visible se actualiza con unidades/edificios. Es el corazón del scouting.
- **Mapa**: simétrico para justicia, con recursos repartidos (bosques, minas, arbustos). Empezamos con 3 mapas fijos curados; generador por seed después.

### 2.8 Condiciones de victoria/derrota
- Victoria: destruir todos los edificios enemigos / Maravilla defendida / Rendición de la IA.
- Derrota: perder todo tu territorio.

### 2.9 UI clásica (que replicamos con toque)
- Barra de recursos + población + aldeanos idle + era actual.
- Panel contextual: unidad seleccionada → sus stats y acciones; edificio → cola de producción/techs.
- Minimapa con alertas (ataque, edificio listo, idle villager).
- Órdenes: mover, atacar, **attack-move**, stop, hold, grupos de control.

---

## 3. El hueco de mercado (por qué este juego)

- **AoE Mobile oficial** (Microsoft/TiMi, octubre 2024): 4X city-builder con gacha de héroes y ~70 héroes de colección. Review típica en tienda: *"It's just a city builder. It has no Age of Empires gameplay."* Está diseñado para monetización de colección, no para RTS.
- **El hueco**: un RTS clásico real — economía, eras, construcción, combate táctico — con controles pensados para touch, sin gacha, jugable offline, partidas de 20-30 minutos.
- **Posicionamiento**: "el RTS clásico que puedes jugar con el pulgar en el camión". Nicho fiel: jugadores de 25-45 que crecieron con el género y no tienen PC a la mano.
- **Monetización potencial** (fase futura, no MVP): pago único en tienda o demo + compra completa. Sin energía, sin timers, sin loot boxes.

---

## 4. Diseño del juego (MVP)

### 4.1 Facciones
MVP: **1 facción jugable** (los "Reinos del Alba") + **1 IA espejo con paleta distinta**. Fase 9: 2ª facción asimétrica ligera (bonuses distintos, mismas unidades base).
> Regla anti-copia: ninguno de los nombres ni bonuses se parece a las civs de Microsoft; los nuestros nacen del lore propio del juego.

### 4.2 Recursos y tasas base (diseño propio, ajustable)
| Recurso | Fuente | Tasa base | Capacidad de viaje |
|---|---|---|---|
| Comida | Arbustos 120 u., caza, Granja | 0.55/s | 10 |
| Madera | Árbol 100 u. | 0.50/s | 10 |
| Oro | Mina 800 u. | 0.45/s | 10 |
| Piedra | Mina 500 u. | 0.40/s | 10 |

Techs suben tasas y capacidad. Partida empieza: **1 Plaza Mayor + 4 aldeanos + 1 explorador ligero**.

### 4.3 Edades (propias)
| Era | Costo | Requisito | Desbloquea |
|---|---|---|---|
| I. Asentamientos | — | — | Aldeano, Miliciano, Cuartel, Casa, Granja, Aserradero, Campamento, Torre |
| II. Fortalezas | 400 Comida | 2 edificios era I | Lancero, Arquero, Galería, Muralla, Puerta, Herrería |
| III. Coronas | 700 Comida + 250 Oro | 2 edificios era II | Caballero, Establo, Castillo, Universidad, techs nivel 2 |
| IV. Imperio | 900 Comida + 700 Oro | 2 edificios era III | Carnero, techs nivel 3, Maravilla |

### 4.4 Unidades MVP (stats propios — versión 0.1, todo editable en JSON)
| Unidad | Costo | HP | ATK | Arm. c/u | Alcance | Velocidad | Rol |
|---|---|---|---|---|---|---|---|
| Aldeano | 50 C | 40 | 3 | 0/0 | melee | 0.9 | Economía, construye, repara |
| Explorador | 80 C | 75 | 5 | 0/1 | melee | 1.6 | Scouting rápido |
| Miliciano | 60 C 20 O | 60 | 7 | 0/1 | melee | 1.0 | Infantería generalista |
| Lancero | 35 C 25 M | 55 | 6 (+12 vs caballería) | 0/1 | melee | 1.0 | Anti-caballería |
| Arquero | 25 M 45 O | 45 | 5 | 0/0 | 5 tiles | 1.0 | Daño a distancia |
| Caballero | 60 C 75 O | 100 | 10 | 2/2 | melee | 1.5 | Caballería de choque |
| Carnero (era IV) | 160 M | 175 | 2 (+75 vs edificios) | 0/0 | melee | 0.7 | Asedio |

Costo repetido = cola por unidad con tiempo de producción. Counters por multiplicador, nunca por inmunidad. **Actualización recomendada tras el análisis de 0 A.D.**: daño tipado (corte/perforante/impacto) con resistencias por tipo, en vez de armadura melee/ranged — ver `docs/ANALISIS-0AD.md` §5; separar además wind-up (anticipación visible) de cadencia.

### 4.5 Edificios MVP (stats propios v0.1)
| Edificio | Costo | HP | Función |
|---|---|---|---|
| Plaza Mayor (centro) | 275 M 100 P | 2400 | Produce aldeanos/explorador; drop-off universal; avanza era |
| Casa | 30 M | 550 | +5 población |
| Granja | 60 M | 300 | Comida infinita |
| Aserradero | 100 M | 600 | Drop-off madera |
| Campamento minero | 100 M | 600 | Drop-off oro/piedra |
| Cuartel | 150 M | 1500 | Miliciano, Lancero (era II) |
| Galería de tiro | 175 M | 1500 | Arquero |
| Establo | 175 M | 1500 | Caballero |
| Herrería | 150 M | 1500 | Techs militares |
| Torre de vigía | 125 P | 850 | Ataque a distancia, visión amplia |
| Muralla (segmento) | 5 P | 250 | Bloquea paso |
| Puerta | 30 M | 300 | Abre/cierra |
| Castillo | 650 P | 4800 | Defensa fuerte, produce unidad élite (fase 2) |
| Maravilla | 1000 M/C/O/P | 4800 | Victoria alternativa (defender 180s) |

Población máxima MVP: **100** (casas +5 c/u; límite duro 100).

### 4.6 Tecnologías MVP (~16)
- **Economía (Plaza Mayor)**: Hoces (+10% comida), Hacha afilada (+10% madera), Pico (+10% minería), Carretilla (+15% velocidad aldeano, +5 capacidad), Arado (granjas +15%).
- **Militar (Herrería)**: Forja (+1 ATK infantería), Flechas reforzadas (+1 ATK arqueros), Estribos (caballería +10% velocidad), Arneses (armaduras +1/+1 infantería), Monturas (caballería +1 armadura), Ballesta (+2 ATK arqueros).
- **Defensa (Universidad)**: Muralla reforzada (+30% HP muralla), Almenas (torres +2 ATK y +1 alcance), Torre de vigilancia (visión +30%), Carcaj (más munición → +10% cadencia arqueros).

### 4.7 Mapas MVP
- 3 mapas fijos curados (tamaño 120×120 tiles de 64 px): "Valle del Río" (río central, vados), "Bosque Cerrado" (poca visibilidad, madera abundante), "Tierras Doradas" (oro central disputado).
- Simetría espejo para justicia. Recursos calculados para partidas de 20-30 min.
- Generador procedural por seed: fase 9.

### 4.8 IA enemiga (FSM por fases)
| Fase | Cuándo | Comportamiento |
|---|---|---|
| Apertura | 0-4 min | Build order rígido: aldeanos a comida/madera, casa, granja, subir a era II |
| Desarrollo | 4-12 min | Balancea eco, 2 cuarteles, ejército de 10-20 |
| Hostigamiento | 12-18 min | Grupos de 5-8 atacan aldeanos y edificios periféricos |
| Push final | 18+ min | Ataque con todo; repite oleadas si falla |

- **Dificultades**: Fácil (decisiones lentas, ejército ×0.7, sin bonus), Normal (sin bonus, x1.0), Difícil (bonus de recursos +20%, ejército ×1.3, scouting agresivo, ataca mientras se defiende).
- **Sin cheats de visión**: la IA no ve lo que no exploró. Nada de "map hacks" (eso es lo que hace sentir tramposo a un RTS móvil).
- Implementación: máquina de estados + "director" de recursos; los números viven en JSON, no en código.

### 4.9 Victoria/derrota y modos MVP
- Modo: **Skirmish 1v1 vs IA** (elige mapa + dificultad).
- Victoria: destruir todos los edificios enemigos, o completar Maravilla (defender 180s), o la IA se rinde (perdió 80%+ de evaluación de fuerza).
- Derrota: equivalente.
- Guardado: partida completa serializable a JSON en `user://` (una ranura + autosave). Sin nube en MVP.

---

## 5. Stack técnico y arquitectura

### 5.1 Motor: Godot 4.x (versión estable más reciente, ej. 4.5/4.6+)
**Por qué**:
- Pipeline 2D nativo (no 3D adaptado como Unity): benchmarks independientes lo ponen hasta 15-27% arriba en sprites y ~50% menos memoria RAM en builds Android 2D.
- `AStarGrid2D` viene integrado: pathfinding en grid con `set_point_solid()` para obstáculos y `update()` al cambiar el mapa.
- Export Android en el editor, sin ecosistema pesado. Instalador ~120 MB vs ~21 GB de Unity.
- Gratis (MIT) sin regalías ni cambios de licencia.

**Renderer**: **Compatibility** (OpenGL ES 3.0) — es el correcto para móvil de gama media y 2D.

**Alternativas consideradas y descartadas**:
| Opción | Por qué no |
|---|---|
| Unity | Más pesado (builds +40%), con historial de cambios de licencia (Runtime Fee). Su 2D va dentro del pipeline 3D. |
| libGDX | Viable, pero más ensamblaje manual (UI, escenas) y menos asistencia de IA entrenada en el ecosistema. |
| Web + Capacitor | Rendimiento inferior en móvil para cientos de sprites y multitouch; híbrido innecesario. |

### 5.2 Lenguaje y estilo
- **GDScript** para todo el juego (está tipado estáticamente si se usa `: int`, `: float` — usarlo siempre).
- Comentarios y nombres de código en inglés. UI y textos de cara al jugador en español (i18n con CSV de traducciones desde el día 1).
- Data-driven: unidades, edificios, techs, civs y mapas viven en **JSON** dentro de `game/data/`. Nada de stats hardcodeadas en scripts.

### 5.3 Estructura del proyecto
```
medieval-rts/
├─ game/                          # proyecto Godot
│  ├─ project.godot
│  ├─ autoload/                   # singletons
│  │  ├─ game_state.gd            # recursos, era, pop, victoria
│  │  ├─ data_loader.gd           # lee JSON de data/
│  │  ├─ event_bus.gd             # señales globales (unit_died, resource_changed...)
│  │  └─ save_manager.gd
│  ├─ scenes/
│  │  ├─ main/ (main.tscn, world.tscn, player.tscn, ai_controller.tscn)
│  │  ├─ units/ (unit.tscn, villager.tscn, military.tscn)
│  │  ├─ buildings/ (building.tscn + variantes)
│  │  ├─ projectiles/ (arrow.tscn)
│  │  └─ ui/ (hud.tscn, minimap.tscn, panel_context.tscn, menu*.tscn)
│  ├─ systems/                    # lógica pura, sin nodos si se puede
│  │  ├─ selection/               # input táctil, caja de selección
│  │  ├─ pathfinding/             # wrapper AStarGrid2D + colas
│  │  ├─ economy/                 # gather, drop-off, rates
│  │  ├─ combat/                  # damage, counters, aggro
│  │  ├─ construction/            # placement, build progress
│  │  ├─ fog/                     # visibilidad por grid
│  │  └─ ai/                      # FSM enemiga
│  ├─ data/ (units.json, buildings.json, techs.json, civs.json, maps/)
│  ├─ assets/ (placeholder/ → art/ y audio/ en F9)
│  └─ tests/ (GUT o escenas de prueba)
├─ docs/ (este plan)
└─ README.md
```

### 5.4 Sistemas clave (decisiones técnicas)

**Selección y input (el mayor riesgo)**
- Manejar el gesto completo en **pointer-up**, no en pointer-down: si el dedo se movió < ~30 px fue *tap*; si se movió más, fue *drag* (caja de selección). Este es el patrón estándar probado en RTS táctiles.
- `PointerManager` propio: diccionario de pointers por ID (multitouch real, soporta pan+zoom+selección sin trabarse).
- Doble tap en una unidad = seleccionar todas las del mismo tipo visibles en pantalla (patrón clásico del género).

**Pathfinding**
- `AStarGrid2D` con celdas de 64 px, `diagonal_mode` sin cortar esquinas, `set_point_solid()` para árboles/edificios/agua.
- **Amortización**: cola de solicitudes de path; máximo N (ej. 8) paths calculados por frame. Con 150 unidades esto evita el colapso que sufren los que usan un NavigationAgent por unidad.
- Los grupos comparten un path de referencia y cada unidad toma un offset de formación (grid 3×3/4×4). Steering local simple (separación) para no encimarse.
- Re-path solo si la ruta quedó bloqueada por un edificio nuevo.
- **Inspiración validada (0 A.D.)**: 0 A.D. usa exactamente este esquema de dos niveles (A* global sobre navcells + pathfinder de vértices corto, asíncrono). Ver `docs/ANALISIS-0AD.md` §2. Si F2 lo pide: navcells más finos que los tiles, o A* corriendo en un `Thread`.

**Unidades (FSM)**
Cada unidad es un `CharacterBody2D` con FSM: `idle → moving → gathering → returning → building → attacking → dying`. Los estados viven en un script por rol; los stats, en JSON.

**Economía**
- Nodos recolectables (árbol/mina/arbusto) con cantidad restante; al agotarse, liberan el tile de pathfinding y el aldeano va a por el siguiente recurso del mismo tipo en radio.
- `resource_changed` se emite por señal (EventBus) → el HUD reacciona. Cero polling por frame.

**Combate**
- Tick de combate cada 0.2 s por unidad en estado `attacking` (no por frame): `daño = max(1, atk + bonus − armadura)`.
- Proyectiles (flechas) como `Area2D` con velocidad; el daño se aplica al impactar.
- Agresividad: unidades militares atacan automáticamente lo que entra en su rango *si están en stance agresivo*; en el resto de casos ignoran (así el jugador no pierde el control).
- Muerte: animación → liberar al pool. Sin borrar nodos constantemente (object pooling).

**Niebla de guerra**
- Grid de 3 estados por tile (0 = nunca visto, 1 = visto pero no visible, 2 = visible) por jugador.
- Recómputo cada 0.25 s en un radio por unidad/edificio (cheap, sin raycasts).
- Render MVP: `TileMapLayer` encima con modulación (negro/parcial); shader bonito en F9.
- La IA usa *su propia* grilla de visibilidad — sin trampas.

**IA enemiga**
- Un `AIController` con la FSM de la sección 4.8. Evalúa cada 2 s (no por frame). Decisiones en función de: recursos propios, era, tamaño de ejército, estado de la guerra.

**Rendimiento (presupuesto)**
| Métrica | Objetivo |
|---|---|
| FPS | 60 en gama media (30 mínimo aceptable) |
| Unidades simultáneas | 150 MVP (diseño hasta 200) |
| Draw calls | < 100 (sprites en atlas, batching) |
| RAM | < 300 MB |
| Tamaño APK/AAB | < 60 MB con arte final |
| Arranque en frío | < 5 s |

**Guardado**: serializar estado (unidades, edificios, recursos, techs, fog, seed) a dict → JSON → `user://save_1.json`. Autosave cada 2 min.

**Multijugador: FUERA del MVP.** Un RTS online exige simulación determinista y *lockstep* (todos los clientes calculan lo mismo exactamente, o se desincronizan) — es el sistema más complejo del género. Si algún día se hace: paso de simulación fijo, RNG con seed compartida, y solo órdenes por red (nunca posiciones).

**i18n**: CSV de Godot con claves (`UNIT_VILLAGER_NAME`) desde F0; español primero, inglés después (el género es global).

---

## 6. UX táctil (especificación completa)

### 6.1 Gestos
| Gesto | Acción |
|---|---|
| Tap en unidad | Seleccionar |
| Doble tap en unidad | Seleccionar todas del mismo tipo visibles |
| Tap en edificio | Seleccionar (abre panel de producción) |
| Tap en el suelo (con selección) | Mover / ir a recolectar / construir |
| Tap en enemigo (con selección) | Atacar |
| Drag 1 dedo (sin selección) | Caja de selección |
| Drag 1 dedo (con selección) — largo (>0.5s) | Mover cámara (pan) |
| Pinch 2 dedos | Zoom (rango 0.5×–1.5×) |
| Tap doble en el suelo | Pan rápido centrado ahí |

> Los conflictos gesto/orden se resuelven con el patrón pointer-up + umbral (~30 px): nada se dispara mientras el dedo está abajo salvo el feedback visual (línea de destino, caja de selección).

### 6.2 HUD
- **Arriba**: recursos (4) con íconos grandes + población `48/75` + campana de idle villagers + era actual.
- **Abajo-izquierda**: minimapa táctil (tap = mover cámara; alertas pulsantes).
- **Abajo-derecha**: panel contextual:
  - Unidad seleccionada → stats + botones grandes (Mover, Atacar, Stop, Hold). Máx. 4-5 botones, ≥ 64 px.
  - Edificio → cola de producción con tiempos, techs con costo.
  - Aldeanos → botones de construir (grid de íconos de edificios).
- **Feedback obligatorio**: cada orden confirmada con SFX + animación de la unidad + línea de destino momentánea (sin esto el RTS táctil se siente roto).
- Todo botón ≥ 64×64 px, con área táctil ampliada; texto mínimo 16 pt.

### 6.3 Construcción con el dedo
1. Tap en aldeano → botón Construir → elige edificio.
2. El edificio "fantasma" sigue el drag del dedo sobre el mapa con validación en vivo (verde = válido, rojo = inválido: terreno, overlap, recursos).
3. Confirmar con botón ✓ o doble tap; cancelar con ✕ o tap en el botón de cancelar.
4. Los aldeanos reciben automáticamente la orden de ir a construir.

### 6.4 Tutorial y onboarding
- 5 misiones guionadas al arrancar (feature-campaign): "recolecta", "construye una casa", "produce un militar", "vence un explorador", "avanza de era"). Cada una con tip y flecha. Skip disponible.

---

## 7. Fases de construcción (trabajar con Claude)

> Regla general para cada fase: **una fase = una conversación con Claude**. Al terminar, correr los criterios de aceptación, probar en Android físico, commit, y cerrar la conversación.

### F0 — Setup + mundo mínimo (fundacional)
**Objetivo**: proyecto Godot creado, corriendo en el teléfono con grid y cámara.
**Entregable**: repositorio con proyecto Godot 4.x; escena `World` con `TileMapLayer` de pasto/agua/bosque (placeholders); cámara con pan/pinch-zoom táctil (zoom 0.5×–1.5×, clamped a bordes del mapa); APK debug corriendo en teléfono físico.
**Tareas**:
1. `git init`, estructura de carpetas (sección 5.3), `.gitignore` de Godot.
2. `project.godot`: renderer Compatibility, resolución base 1280×720 estirada, orientación landscape.
3. Generar tile grid placeholder 120×120 (64 px) con ruido simple (agua/pasto/bosque).
4. `CameraController` con pan 1 dedo + pinch.
5. Export Android: keystore debug, AAB debug, instalar en device.
**Criterios de aceptación (testables)**:
- [ ] El APK abre en el teléfono en < 5 s y muestra el mapa.
- [ ] Pan fluido a 60 fps; zoom con pinch fluido entre 0.5× y 1.5×, sin salir del mapa.
- [ ] `git status` limpio después del commit.

### F1 — Selección y órdenes (el "feel")
**Objetivo**: validar el riesgo #1 (control táctil) antes de invertir en nada más.
**Entregable**: PointerManager; tap/doble tap/drag-box; unidad placeholder que se mueve a un punto con feedback (línea de destino + SFX).
**Tareas**:
1. `PointerManager` (IDs de pointer, detección tap vs drag en pointer-up, umbral 30 px).
2. Highlight de selección (círculo verde) + click en el suelo con orden de mover.
3. Caja de selección táctil (rectángulo dibujado, selección múltiple).
4. 5 unidades de prueba con movimiento directo (sin pathfinding aún).
**Criterios de aceptación**:
- [ ] En teléfono: se puede seleccionar 1 unidad, 3 con caja, y ordenar movimiento a varios puntos sin que un gesto robe al otro.
- [ ] 10 intentos seguidos sin un solo un-gesto-no-previsto. *(Si esto no se siente bien, iterar AQUÍ antes de F2.)*

### F2 — Pathfinding y movimiento de grupo
**Entregable**: integración `AStarGrid2D`; órdenes de grupo con path compartido y formación; amortización de paths; obstáculos dinámicos (poner/quitar "solid" al construir/destruir).
**Criterios de aceptación**:
- [ ] 50 unidades al mismo destino rodean un lago y llegan todas (sin atasco permanente).
- [ ] 150 unidades en marcha: fps ≥ 40 en gama media, sin picos > 100 ms por frame.
- [ ] Quitar/poner un obstáculo recalculan rutas correctamente.

### F3 — Economía: aldeanos y recursos
**Entregable**: nodos de recursos (árbol/mina/arbusto), aldeanos con FSM de recolección, drop-offs (Plaza Mayor funciona como universal; campamentos), HUD con recursos/población/idle, árbol se agota y libera pathfinding.
**Criterios de aceptación**:
- [ ] Partida de 10 min: 12 aldeanos trabajando en 3 recursos sin que ninguno se quede trabado ni pierda carga.
- [ ] Los ids de idle villager (campana) funcionan y llevan la cámara al aldeano.
- [ ] Tasas del JSON visibles/balanceables sin tocar código.

### F4 — Construcción
**Entregable**: modo construcción (fantasma con validación), aldeanos constructores, progreso visual, cancelación con devolución del 50%, cola de producción de la Plaza Mayor (aldeanos, explorador), casas suben pop cap.
**Criterios de aceptación**:
- [ ] Construir una base completa (2 casas, granja, aserradero, cuartel) en < 4 min de juego, todo con el dedo.
- [ ] No se puede construir sobre recursos/unidades; el fantasma lo indica en vivo.
- [ ] Cancelar en cualquier momento devuelve recursos correctamente.

### F5 — Combate
**Entregable**: unidades militares (miliciano, lancero, arquero, caballero), stats/counters desde JSON, ataque con cadencia, proyectiles, aggro por stance, muerte con pooling, barras de vida.
**Criterios de aceptación**:
- [ ] Una batalla 20v20 es legible y termina en < 60 s.
- [ ] El counter funciona: 10 lanceros vencen a 10 caballeros gastando < 50% de HP; 10 arqueros vencen a 10 lanceros sin perder más de 4.
- [ ] Sin fugas de memoria tras 200 muertes (monitorear nodos activos).

### F6 — IA enemiga + condiciones de victoria
**Entregable**: AIController con FSM (apertura/desarrollo/hostigamiento/push), 3 dificultades, scouting honesto (sin map hack), victoria/derrota, pantalla de fin de partida con stats.
**Criterios de aceptación**:
- [ ] En Normal, un jugador pasivo pierde en 15-20 min; un jugador con build order básico gana.
- [ ] La IA no ataca lo que no ha explorado (test con fog visual del debug).
- [ ] Difícil gana contra Normal simulando IA vs IA en 3 de 4 corridas.

### F7 — Eras y tecnologías
**Entregable**: avance de era con costo/requisito/animación; desbloqueos por era; Herrería y Universidad con techs de las 3 ramas; árbol de techs consultable en UI.
**Criterios de aceptación**:
- [ ] Se puede llegar a Era IV en una partida de 25 min y las unidades nuevas aparecen en las colas.
- [ ] Una tech investigada cambia stats visibles (tooltip de antes/después).
- [ ] No hay techs huérfanas (todas se pueden investigar y todas tienen efecto).

### F8 — Fog of war, minimapa y pulido de UX
**Entregable**: fog de 3 estados por jugador, minimapa funcional con alertas y tap-to-camera, campana de idle villagers, señales de ataque, groups de control (botones 1-5), guardado/carga + autosave.
**Criterios de aceptación**:
- [ ] La niebla se actualiza en < 0.5 s al explorar; edificios enemigos no visibles no se renderizan.
- [ ] Cargar una partida guardada deja el estado idéntico (mismo frame de simulación aproximado).
- [ ] Partida completa vs IA de principio a fin, sin tocar el teclado ni un solo crash.

### F9 — Contenido, arte y audio
**Entregable**: arte final (o IA generado) reemplaza placeholders: unidades animadas (idle/walk/attack/death), edificios, terreno, UI; música 2-3 temas + ~40 SFX; tutorial guionado (sección 6.4); 3 mapas curados; 2ª facción; generador por seed; balance pasada final.
**Criterios de aceptación**:
- [ ] Un desconocido completa el tutorial sin ayuda.
- [ ] 5 playtests externos: nadie reporta "no entendía qué hacer" ni "se sentía roto".
- [ ] Sin assets con licencia dudosa (inventario de licencias en docs/).

### F10 — Publicación
**Entregable**: cuenta Google Play ($25 único), ficha (íconos, capturas, video, descripción), política de privacidad (si aplica), clasificación de contenido, AAB firmado release, pruebas internas/cerradas, lanzamiento.
**Criterios de aceptación**:
- [ ] AAB pasa la revisión de Play sin warnings.
- [ ] Instalación limpia en 3 dispositivos distintos (gama baja/media/alta).
- [ ] Crash rate < 1% en las primeras 100 sesiones (Play Console).

---

## 8. Riesgos y mitigaciones

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Control táctil se siente incómodo | Alta | Fatal | F1 completo antes de lo demás; playtest en device; iterar |
| Scope creep (el género es gigante) | Alta | Alto | MVP estricto (esta lista); todo lo demás a un backlog "v2" |
| Rendimiento con muchas unidades | Media | Alto | Presupuesto 150 unidades; pooling; amortización; medir en device cada fase |
| Balance imposible | Media | Medio | Data-driven (JSON); simulador IA vs IA para probar rápido |
| Arte final caro/lento | Media | Medio | Placeholders hasta F9; IA + packs CC0 verificados |
| Decompilar el juego original por costumbre | Baja | Fatal | Regla dura: este proyecto no analiza artefactos de Microsoft. Cero. |
| Cambios de Godot rompen cosas | Baja | Bajo | Fijar versión de Godot en README; actualizar solo entre fases con changelog leído |

---

## 9. Apéndice A — Prompts de arranque por fase para Claude

> Pegar en una conversación nueva de Claude (con acceso al repo). Sustituir `[FASE]` y adjuntar/indicar `docs/PLAN-CONSTRUCCION-RTS.md`.

**Prompt base (copiar antes de cada fase):**
```
Vamos a trabajar en el proyecto REALM, un RTS medieval original para Android
en Godot 4, definido en docs/PLAN-CONSTRUCCION-RTS.md (léelo completo primero).

Reglas del proyecto:
- Juego 100% original: nada de assets, nombres ni datos del Age of Empires de
  Microsoft. Mecánicas de género sí; su contenido no.
- Código y nombres en inglés; comentarios solo donde aporten.
- Data-driven: stats en game/data/*.json, no hardcodeadas.
- GDScript tipado estáticamente (usar tipos en variables y funciones).
- Presupuesto de rendimiento: 60 fps gama media, 150 unidades, < 100 draw calls.
- Al terminar: lista de archivos creados/modificados y cómo probarlo en Android.

Fase a trabajar: [FASE]
Objetivo: [copiar el objetivo de la fase]
Entregable: [copiar el entregable]
Criterios de aceptación: [copiar la checklist]
```

**Ejemplo F1 ya armado:**
```
[Prompt base con FASE = F1 — Selección y órdenes]
Implementa el PointerManager con detección tap vs drag en pointer-up (umbral
30 px), selección por tap, doble tap (seleccionar mismo tipo visible), caja de
selección por drag y órdenes de movimiento con feedback (línea de destino +
sonido placeholder). Incluye una escena de prueba con 5 unidades placeholder.
No implementes todavía pathfinding ni economía.
```

**Ejemplo F6 ya armado:**
```
[Prompt base con FASE = F6 — IA enemiga]
Implementa el AIController con la FSM de 4 fases descrita en el plan (apertura,
desarrollo, hostigamiento, push final), con las 3 dificultades y sus
multiplicadores en JSON. Usa la grilla de visibilidad real (sin map hack).
Añade condiciones de victoria/derrota y pantalla de fin de partida. Incluye un
modo debug que muestre el estado de la FSM en pantalla.
```

---

## 10. Apéndice B — Esquema de datos (JSON)

**units.json** (ejemplo de una entrada):
```json
{
  "spearman": {
    "name_key": "UNIT_SPEARMAN_NAME",
    "cost": { "food": 35, "wood": 25 },
    "hp": 55,
    "attack": 6,
    "bonus": { "cavalry": 12 },
    "armor": { "melee": 0, "ranged": 1 },
    "range_tiles": 0,
    "speed": 1.0,
    "attack_speed": 1.4,
    "train_time": 22,
    "era": 2,
    "produced_at": "barracks",
    "class": "infantry"
  }
}
```

**buildings.json** (ejemplo):
```json
{
  "house": {
    "name_key": "BLDG_HOUSE_NAME",
    "cost": { "wood": 30 },
    "hp": 550,
    "footprint": [2, 2],
    "pop_bonus": 5,
    "era": 1,
    "build_time": 18
  }
}
```

**techs.json** (ejemplo):
```json
{
  "forge": {
    "name_key": "TECH_FORGE_NAME",
    "cost": { "food": 150 },
    "research_time": 40,
    "era": 2,
    "researched_at": "blacksmith",
    "effects": [ { "stat": "attack", "class": "infantry", "add": 1 } ]
  }
}
```

---

## 11. Apéndice C — Fuentes consultadas

- Mecánicas del género: `ageofempires.com/learn-to-play` (recursos, UI, control), `aoedb.net/aoe2` (edades, tech tree, mecánicas para principiantes), `ageofempires.fandom.com/wiki/Counter` (sistema de counters).
- Estado del mercado móvil: fichas oficiales de "Age of Empires Mobile" (Microsoft Store, App Store, Google Play) + reviews de tienda y prensa (Pocket Tactics, TheGamer).
- Godot: `docs.godotengine.org` (AStarGrid2D, TileSets/TileMapLayer, export Android), KidsCanCode (recetas de pathfinding en grid), foro Godot (optimización de unidades 2D en RTS, rendimiento Android).
- Comparativa de motores: benchmarks públicos Godot 4.4/4.5+ vs Unity 6 (sprites 2D, tamaño de build, memoria Android).
- UX táctil: devlog de RTS táctil (Construct.net, "input and gestures"), módulo de controles móviles de RTS Engine (Unity), guías de diseño táctil para pulgares.
- Análisis del código de 0 A.D. (RTS libre, GPL): `docs/ANALISIS-0AD.md` — pathfinding de dos niveles, stances data-driven, damage types vs resistencias, IA por umbrales.

---

## 12. Apéndice D — Glosario rápido

| Término | Significado |
|---|---|
| **RTS** | Real-Time Strategy: estrategia en tiempo real (el género, ej. los Age of Empires clásicos). |
| **Skirmish** | Partida suelta 1v1 contra IA (sin campaña). |
| **Drop-off** | Punto de entrega: donde el aldeano deposita lo recolectado. |
| **Pop cap** | Límite de población; lo suben las casas. |
| **Tech tree** | Árbol de tecnologías: qué mejoras puedes investigar y cuándo. |
| **Counter** | Unidad que le gana a una clase específica (lancero → caballería). |
| **Fog of war** | Niebla de guerra: solo ves lo que tus unidades exploran. |
| **Stance** | Actitud de una unidad en combate (agresivo, defensivo, quieto). |
| **Placeholder** | Recurso temporal (p. ej. cuadrado de color) que se reemplaza después. |
| **Milestone / Fase** | Bloque de trabajo con entregable y criterios de aceptación. |
| **Lockstep** | Técnica de red para RTS: todos los clientes simulan lo mismo al mismo tiempo. Fuera de MVP. |
| **Pooling** | Reusar objetos (balas, muertos) en vez de crearlos/destruirlos. |
| **x1.0 / ×0.7** | Notación de multiplicadores de dificultad de la IA. |

---

*Documento vivo. Última actualización: 2026-10-16. Se actualiza al cerrar cada fase.*
