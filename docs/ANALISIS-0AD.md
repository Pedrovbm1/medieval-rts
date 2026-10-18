# Análisis de 0 A.D. — Cómo funciona un RTS por dentro

> **Qué es esto**: análisis del código fuente real de **0 A.D.** (RTS histórico, libre, desarrollo desde ~2001) para extraer arquitectura y decisiones de diseño que alimenten el plan de REALM. Es el "ver cómo funciona" que necesita el proyecto — hecho de forma 100% legal, sobre código abierto.
> **Fuente analizada**: repo oficial `0ad/0ad` (mirror GitHub), commit `61a3b95`, checkout parcial de ~4 MB: `simulation/` (componentes JS + datos + IA), `globalscripts/` y `source/simulation2/helpers/` (pathfinding C++).
> **Herramientas**: REA CLI (`analyze-javascript-application`) sobre el árbol de simulación + lectura directa de fuentes. Revisa la sección 9 para métricas y límites del análisis REA.
> **Nota legal**: 0 A.D. es **GPL v2** (código) y CC-BY-SA (arte). De aquí se extraen **ideas, patrones y datos de diseño**; NO se copia código (una línea de GPL en nuestro proyecto contagiaría la licencia completa). Y cero relación con el AoE de Microsoft: esto es el análisis del equivalente abierto.

---

## 1. Arquitectura general

- **Entity-Component-System (ECS)**: cada entidad del juego (unidad, edificio, árbol) es un ID con componentes que se le enchufan: `Attack`, `Health`, `ResourceGatherer`, `UnitAI`, `Vision`, `Motion`... **82 componentes JS** solo en el mod público.
- **Templates XML con herencia múltiple**: los datos de unidades/edificios viven en XML y heredan en cadena. Ejemplo real: `units/athen/infantry_spearman_b.xml` hereda de `civ/athen|hoplite|template_unit_infantry_melee_spearman`. Los stats base (HP, costos, resistencia) viven en la plantilla abstracta; el archivo concreto solo pisa lo suyo (nombre, ícono, actor visual).
- **Niveles de unidad `_a / _b / _e`** (básico / avanzado / élite) — el mismo esqueleto de datos sirve para las 3 versiones.
- **Simulación por turnos discretos** (no por frame): el engine llama `Update(turnLength, commands)` con duración fija en ms y **comandos** en cola. La matemática de simulación usa **fixed-point** (`fixed`), no floats, para ser reproducible (clave de su multiplayer lockstep).
- **Data separada del código**: `simulation/data/` con **151 tecnologías en JSON**, civs, auras, damage_types, resources, settings.

**Lección para REALM**: nuestro diseño (componentes por rol, JSON para datos, tick de combate a 0.2 s) está alineado con un RTS que lleva 20 años funcionando. La simplificación es consciente: single-player en Godot → no necesitamos fixed-point ni lockstep.

---

## 2. Pathfinding — el hallazgo más importante

0 A.D. **no usa un solo pathfinder**: usa **dos niveles** con problemas distintos, y es la razón por la que puede mover cientos de unidades sin morir.

### 2.1 Long-range (A* sobre navigation grid) — `source/simulation2/helpers/Pathfinding.h`

- A* sobre una **navigation grid** (navcells) **más fina que los tiles del terreno** ("*Since units are much smaller than terrain tiles, the nav grid should be higher resolution than the tiles*"). En 0 A.D.: navcell = 1 m, tile de terreno = varios navcells.
- Conectividad **horizontal/vertical (sin diagonales)** en el path largo.
- Los obstáculos (árboles, edificios) se **rasterizan** sobre la grid y se expanden hacia afuera por el radio de la unidad (`CLEARANCE_EXTENSION_RADIUS`). La unidad nunca "raspa" las paredes.
- **Pass classes por bits**: pocas clases de pasabilidad ("infantry", "ship"), 1 bit por clase por celda (`NavcellData` = 16 bits). Infantería no camina por agua; barcos no caminan por tierra. Costo de memoria mínimo y check de un bit.
- Los pedidos son **objetos** con ticket y notificación (`LongPathRequest`/`ShortPathRequest`): cuando el path está listo, le avisan a la entidad. **No hay espera bloqueante.**

### 2.2 Short-range (grafo de vértices, local y asíncrono) — `VertexPathfinder.h`

- Cuando el path largo ya trajo a la unidad cerca del objetivo, entra el pathfinder corto: construye un grafo con los **vértices de las obstrucciones** cercanas (+ start/end), con **edges de colisión unidireccionales**, y corre A* solo dentro de un radio (`range`) alrededor.
- Se usa para el movimiento fino: esquivar las unidades/edificios que están **en medio del camino** en este momento (opción `avoidMovingUnits`).
- **Corre en threads paralelos**: "*There are several vertex pathfinders running asynchronously*". El cálculo de paths no bloquea el frame.

### 2.3 Objetivos con radio

El objetivo de un path es un `PathGoal` (puede ser "llegar a esta zona", no solo "a este punto exacto"). Evita fallos cuando el destino exacto está ocupado.

**Traducción a REALM (fases F2–F3)**:
- `AStarGrid2D` es nuestro long-range (misma idea, ya integrado en Godot con `set_point_solid`).
- La "separación/short-range" local se hace con steering simple por unidad.
- Usar `allow_partial_path` y destinos con radio (la unidad "llega cerca").
- **Reconsiderar**: celdas de grid de 64 px → para 150 unidades en mapas 120×120 alcanza; si F2 muestra tirones, subdividir la grid de pathfinding (2 navcells por tile) como hace 0 A.D.
- Optimización disponible si hace falta: mover el cálculo de A* a un hilo (Godot `Thread`), como los vertex pathfinders asíncronos.

---

## 3. UnitAI — la máquina de estados (6,530 líneas)

### 3.1 FSM jerárquica

`UnitAI.js` define los estados en un **spec data-driven** (`UnitFsmSpec`, línea 194) sobre un motor FSM genérico (`globalscripts/FSM.js`). Dos modos raíz:

- `INDIVIDUAL.*` — la unidad hace su vida (IDLE, WALKING, GATHER, ATTACK, CHASING, FLEEING...).
- `FORMATIONMEMBER.*` — la unidad obedece a su controlador de formación (ej. `FORMATIONMEMBER.WALKING`).

Los estados reaccionan a **eventos por mensaje**: `MovementUpdate`, `Attacked`, `LosRangeUpdate` (enemigos que entran a visión), `ConstructionFinished`, y órdenes (`Order.FormationWalk`...). Es una FSM por eventos (event-driven), no un `if` gigante por frame.

### 3.2 Stances (posturas) — data-driven con flags

En vez de programar comportamientos por unidad, cada **stance** es una combinación de flags (línea 80):

| Stance | targetVisibleEnemies | respondFlee | respondChase | respondHoldGround | ... |
|---|---|---|---|---|---|
| violent | ✅ | ❌ | ✅ (sin límite) | ❌ | ataca todo lo que ve |
| aggressive | ✅ | ❌ | ✅ (hasta visión) | ❌ | persigue lo visible |
| defensive | ✅ | ❌ | ❌ | ✅ | defiende posición |
| standground | ✅ | ❌ | ❌ | (no se mueve) | solo ataca a rango |
| passive | ❌ | ✅ (huye) | ❌ | ❌ | no inicia peleas |
| skittish | ❌ | ✅ (al ver) | ❌ | ❌ | huye al ver enemigo |

**Lección para REALM (F5)**: adoptar el modelo de flags — nosotros con 3-4 stances en JSON (agresivo / defensivo / quieto / pasivo), cada una = combinación de flags. Cero código nuevo por stance.

### 3.3 Formaciones (13 tipos)

`Scatter, Box, ColumnClosed, LineClosed, ColumnOpen, LineOpen, Flank, Skirmish, Wedge, Testudo, Phalanx, Syntagma, BattleLine` — cada unidad declara en su template cuáles puede usar. Para REALM: fuera del MVP; nuestro "grid de formación simple" (3×3/4×4) es suficiente hasta F9.

---

## 4. Economía — `ResourceGatherer.js`

- **Rates por subtipo de recurso** (no por recurso genérico): `food.fruit` 0.5, `food.grain` 0.25 (granjas), `food.meat` 1 (caza), `wood.tree` 0.75, `stone.rock` 0.5, `metal.ore` 0.5 — multiplicados por un `BaseSpeed` de la unidad. (0 A.D. usa *metal* donde AoE usa *oro*; mismo esquema.)
- **Capacidad de carga** por recurso (10 base) y `MaxDistance` 2.0 (qué tan lejos puede recolectar del nodo).
- Recolección **entera por llamadas** (`GATHER_AMOUNT = 1`, intervalo según rate) — simple y determinista.
- **Optimización clave**: los rates se **recálculan y cachean** cuando cambia una tecnología (`RecalculateGatherRates` + `ApplyValueModificationsToEntity`), no se consultan por frame. Comentario del código: "*this code is very performance critical*".
- El aldeano **recuerda el último subtipo** recolectado (para animación/íconos).

**Lección para REALM (F3)**: nuestro JSON ya tiene `gather_rate` por recurso; añadir el patrón **"recalcular al investigar tech, cachear el multiplicador"** (una función, cero polling). Y guardar `last_gathered_type` por aldeano para el feedback visual/sonoro.

---

## 5. Combate — daño tipado + bonuses por clase

Del template real del lancero (`template_unit_infantry_melee_spearman.xml`):

```xml
<Attack><Melee>
  <Damage><Hack>3</Hack><Pierce>2.5</Pierce></Damage>
  <MaxRange>4</MaxRange>
  <PrepareTime>500</PrepareTime>     <!-- 0.5 s de anticipación -->
  <RepeatTime>1000</RepeatTime>     <!-- 1 ataque por segundo -->
  <Bonuses><BonusCavMelee>
      <Classes>Cavalry</Classes>
      <Multiplier>3.0</Multiplier>   <!-- ×3 vs caballería -->
  </BonusCavMelee></Bonuses>
</Melee></Attack>
```

- **3 tipos de daño**: `Hack` (corte), `Pierce` (perforante), `Crush` (contundente). Cada unidad tiene **resistencias por tipo** (`Resistance: Hack 5, Pierce 5...`), separadas para entidad viva vs *foundation* (edificio en construcción).
- **Counters por multiplicador de clase**: ≠×3 vs Cavalry. El tooltip del juego lo dice explícito: "*Counters: 3× vs Cavalry*". Nunca inmunidad.
- **Clases vs clases visibles**: `Classes` (tags internos para bonuses: Cavalry, Human, Domestic...) y `VisibleClasses` (las que ve el jugador). Un bonus dice contra qué tag pega.
- **PrepareTime/RepeatTime** separados: el wind-up (anticipación) es visible — legibilidad del combate.
- Unidades con **XP y promoción** (`RequiredXp 100`), `Loot` al morir, `Capture` (capturar en vez de destruir edificios) y `Slaughter` (matar ganado). Sistemas fuera del MVP.
- **Sonido por evento**: cada orden tiene su SoundGroup (`order_walk`, `order_gather`, `gather_tree`, `select`, `death`...). El feedback sonoro es de primera clase.

**Lección para REALM (F5)**:
- Upgrade de diseño: pasar de armadura melee/ranged a **daño tipado por resistencias** (nuestros 3 tipos: corte/perforante/impacto). Es igual de fácil de implementar y da profundidad sin más unidades.
- Separar `prepare_time` (wind-up) y `repeat_time` — para la legibilidad del combate en pantalla de celular.
- Tooltip con el counter explícito ("×3 vs caballería") en F7.
- Checklist de SFX por evento ya está; 0 A.D. confirma el nivel de granularidad esperado.

---

## 6. Tecnologías — JSON declarativo (151 en el juego)

Formato real (`gather_capacity_wheelbarrow.json`):

```json
{
  "genericName": "Wheelbarrow",
  "cost": { "food": 400, "wood": 400 },
  "supersedes": "gather_capacity_basket",
  "requirements": { "tech": "phase_town" },
  "researchTime": 50,
  "modifications": [
    { "value": "ResourceGatherer/Capacities/food", "add": 5 },
    { "value": "ResourceGatherer/Capacities/wood", "add": 5 },
    { "value": "ResourceGatherer/Capacities/stone", "add": 5 },
    { "value": "ResourceGatherer/Capacities/metal", "add": 5 }
  ],
  "affects": ["Worker"]
}
```

- Una tech = **deltas declarativos** sobre rutas de valores del componente ("añade 5 a `Capacities/food` de quien sea Worker").
- `requirements` (era/edificio/tech previa), `supersedes` (reemplaza a otra tech), `affects` (a qué clase de entidades aplica).
- Los componentes aplican los modificadores con `ApplyValueModificationsToEntity` al consultar el valor (cacheado).

**Lección para REALM (F7)**: nuestro esquema planeado (`effects: [{stat, class, add}]`) es una versión simplificada del mismo patrón. Adoptar también `supersedes` (evita techs redundantes) y aplicar los efectos **al consultar el stat con caché**, no reescribiendo valores.

---

## 7. IA enemiga — Petra

- **Arquitectura de managers** (27 archivos en `simulation/ai/petra/`): `economy...` repartidos en `worker.js`, `buildManager`, `baseManager/basesManager` (expansión de bases), `attackManager` + `attackPlan`, `defenseManager` + `defenseArmy`, `garrisonManager`, `emergencyManager`, `researchManager`, `queueManager` (colas de producción/train), `startingStrategy`, `mapModule` (scouting), `diplomacyManager`, `navalManager`, `victoryManager`. Un `headquarters.js` hace de "hub" que los coordina.
- **Config 100% data-driven** (`config.js`) con valores concretos y legibles:

| Parámetro | Valor | Significado |
|---|---|---|
| dificultades | 0–5 | Sandbox, VeryEasy... VeryHard |
| `popPhase2` | 38 | no avanza de fase hasta tener ~38 "unidades" de trabajo |
| `workPhase3` / `workPhase4` | 65 / 80 | trabajadores antes de fase 3 / 4 |
| `targetNumWorkers` | 40 | objetivo de aldeanos |
| `popForBarracks1` | 25 | su primer cuartel lo construye a ese umbral de población |
| `towerLapseTime` | 90 s | tiempo mínimo entre torres (no spam) |
| `defenseRatio` | ally 1.4 / neutral 1.8 / own 2.0 | cuántos defensores por atacante según dónde |
| `armyCompactSize` | 2000 (²) | distancias al cuadrado para agrupar ejércitos |

- `DamageTypeImportance` (Hack 0.085, Pierce 0.075...) — la IA **le da peso a cada tipo de daño** al evaluar ejércitos enemigos. Evalúa counters.

**Lección para REALM (F6)**: mantener nuestra FSM de 4 fases, pero gobernada por **umbrales explícitos en JSON** (estilo `popForBarracks`, `workersForAgeUp`, `defendersPerAttacker`) en vez de ifs dispersos. Los multiplicadores de dificultad ya están en el plan — 0 A.D. valida que la IA se define por *parámetros*, no por código distinto.

---

## 8. Qué adopta REALM (resumen ejecutable)

| Hallazgo en 0 A.D. | Acción en REALM | Fase |
|---|---|---|
| Pathfinding de 2 niveles (A* grid + vertex corto) | Mantener AStarGrid2D + steering local; opción de navcells más finos y thread si F2 lo pide | F2 |
| Objetivos con radio / path parcial | `allow_partial_path` + destinos con radio | F2 |
| Pedidos de path como cola con notificación | Ya planeado (amortización); confirmar el patrón ticket→notify | F2 |
| Stances = flags data-driven | Implementar stances como combinación de flags en JSON | F5 |
| Counters ×3 con tooltip explícito | Subir bonus a ×2.5–3 si el playtest lo pide; tooltip "×N vs clase" | F5/F7 |
| Damage types (Hack/Pierce/Crush) vs resistencias | Cambiar diseño a 3 tipos de daño con resistencias por tipo | F5 |
| PrepareTime (wind-up) separado de RepeatTime | Añadir wind-up visible de 0.3–0.5 s en ataques | F5 |
| Techs como deltas por ruta de valor + supersedes | Adoptar `supersedes` y aplicar efectos con caché al consultar | F7 |
| IA por umbrales poblacionales en config | Umbrales de IA a JSON (barracks, age-up, defensa) | F6 |
| Sonido por evento de orden | Usar como checklist de SFX (walk, gather_tree, select, death...) | F9 |
| Templates con herencia + niveles _a/_b/_e | MVP: JSON plano; F9 (2ª facción): evaluar herencia simple | F9 |
| Sim por turnos con fixed-point | No se adopta (single-player); mantener delta fijo de Godot + tick de combate 0.2 s | — |

---

## 9. Corrida de REA (evidencia y límites)

Se corrió el CLI de REA sobre `binaries/data/mods/public/simulation` (635 archivos relevantes; 2.38 MB de texto; 267 archivos JS parseados; 288,320 nodos AST visitados; 164 findings; **0 fallos de parse**). El Evidence resultante (311 MB con grafo completo) registra:

- `summary`: 0 ventanas de browser, 0 IPC — confirma que **no es una app empaquetada** (no Electron/Webpack), que es el perfil para el que ese analizador está optimizado. El grafo marca ~81,310 referencias `jsrg_unknown`: este código se inyecta en un runtime de juego custom (SpiderMonkey con API `Engine.*`), no se resuelve como app web.
- Las limitaciones que el propio Evidence declara (cita textual): *"Static paths and relationships may remain unresolved when expressions are dynamic or obfuscated"* y *"JavaScript and HTML were parsed as inert text; bundle bootstrap code was never executed"*.
- Conclusión honesta: para **un repo de código fuente completo**, la herramienta correcta es la lectura directa de fuentes — y así se hizo (secciones 1–7). REA aportó inventario, parseo y confirmación del tipo de artefacto. Los falsos "endpoint candidates" (ej. leyó `get("Attack")` como posible llamada de red) se descartan con la propia limitation del Evidence ("*only a candidate*").

---

## 10. Límites de este análisis

- Se analizó la capa de **simulación** (JS + helpers C++ de pathfinding). No se analizó el render (C++), el netcode, ni el editor de mapas — fuera del alcance de REALM.
- Los datos citados son del commit `61a3b95`; 0 A.D. sigue en desarrollo y puede haber cambiado detalles.
- **GPL**: nada de este análisis se traduce en código copiado. Se copian *ideas* (licencia libre de ideas), no *expresión* (código/assets con licencia). Si algún día se quisiera reutilizar código de 0 A.D. directamente, el archivo debería estar GPL — decisión que este proyecto no toma.

---

*El clon local de referencia (solo código de simulación, 4 MB) quedó en `%TEMP%\opencode\0ad-src` para consultas durante la construcción. Documento vivo: se amplía si alguna fase necesita más detalle de 0 A.D.*
