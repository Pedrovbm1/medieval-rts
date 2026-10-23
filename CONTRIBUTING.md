# Cómo ayudar con REALM

Bienvenido. REALM es un RTS medieval 2D para Android hecho en **Godot 4.7.2** con
**GDScript tipado**. Esta guía te deja listo para correr el juego, entender cómo
está armado y mandar cambios sin romper nada.

> Lee primero el [README](README.md) (qué es y estado). Para el detalle vivo de
> decisiones y fases: [`docs/BUILD-STATE.md`](docs/BUILD-STATE.md) y
> [`docs/BUILD-LOG.md`](docs/BUILD-LOG.md).

---

## 1. Probar el juego sin instalar nada

Descarga el APK más reciente desde la página
**[Releases](../../releases/latest)** e instálalo en un Android (permite
"instalar apps de origen desconocido"). Funciona en teléfonos de gama media
(probado en Galaxy S10 y S24, 60 fps).

Para jugar **multijugador por Wi-Fi**: los dos teléfonos en la misma red, uno
en *Multijugador → Crear partida* (muestra su IP) y el otro en *Unirse con IP*.

---

## 2. Preparar tu computadora

| Necesitas | Versión | Para qué |
|---|---|---|
| [Godot](https://godotengine.org/download/archive/4.7.2-stable/) | **4.7.2 stable**, exacta | Editor y motor |
| Python | 3.10+ | Solo si regeneras el audio (`tools/gen_audio.py`) |
| Android SDK + JDK 17 | `platform-tools`, `build-tools` 35+ | Solo para exportar el APK |
| Export templates de Godot 4.7.2 | `Editor > Manage Export Templates` | Solo para exportar |

No subas de versión de Godot por tu cuenta: el proyecto está fijado a 4.7.2.

```bash
git clone <url-del-repo>
cd medieval-rts
godot --path game          # abre el juego
godot -e --path game       # abre el editor
```

En escritorio el mouse hace de dedo: clic arrastrando mueve la cámara, la rueda
hace zoom, mantener el clic arma la selección en caja.

La primera vez Godot importa los recursos (tarda un poco). Si ves texturas raras
después de cambiar el arte, corre `godot --headless --path game --import`.

---

## 3. Cómo está armado

```
game/
├─ project.godot
├─ autoload/        EventBus (señales globales), DataLoader (JSON), GameState,
│                   SaveManager, Sfx, Music, NetSession (red)
├─ data/            TODO el balance vive aquí: units, buildings, techs, eras,
│                   ai, rules, resources, scenarios, tutorial (JSON),
│                   maps/*.json y i18n/ui.csv (textos es/en)
├─ scenes/main/     main.gd arma la partida; world.gd tiene unidades,
│                   edificios, recursos y el NavGrid
├─ scenes/ui/       menú, HUD, minimapa
├─ systems/
│  ├─ selection/    toques → órdenes (selection_controller), formaciones
│  ├─ pathfinding/  NavGrid (A*), cola de rutas, movimiento con separación
│  ├─ economy/      recolección, granjas, mercado; tareas por unidad (UnitTask)
│  ├─ construction/ colocar, construir, reparar, entrenar
│  ├─ combat/       daño tipado + bonos (counters), proyectiles, guarnición
│  ├─ ai/           AIController (dificultades) y MatchRules (victoria)
│  ├─ tech/         eras y tecnologías
│  ├─ net/          capa de órdenes + lockstep para multijugador
│  ├─ render/       el ARTE se pinta por código y se hornea a un atlas
│  ├─ fog/ save/ tutorial/ world/
├─ assets/          atlas horneado (art/) y audio generado (audio/)
└─ tests/           run_tests.tscn + test_f*.gd
tools/              gen_audio.py y scripts adb para probar en teléfono
docs/               plan, estado, bitácora, ideas y análisis
```

Ideas clave para no perderte:

- **Data-driven.** Para cambiar costos, vida, daño, tiempos o la IA, toca el
  JSON en `game/data/`, no el código.
- **Todo pasa por órdenes.** Lo que hace el jugador (mover, construir,
  entrenar…) se vuelve un diccionario que aplica `systems/net/command_bus.gd`.
  Así funciona igual en una partida normal y en red. Si agregas una acción
  nueva, agrégala ahí.
- **Determinismo (por el multijugador).** Dentro de la simulación no uses
  `randf()` ni el reloj real: usa `world.rng` y `world.sim_time`. Si no, los dos
  teléfonos se desincronizan. Detalle en
  [`docs/MULTIPLAYER-PLAN.md`](docs/MULTIPLAYER-PLAN.md).
- **Arte por código.** No hay PNG dibujados a mano: `systems/render/*_painter.gd`
  pinta cada sprite. Si cambias un pintor, sube `ART_VERSION` en
  `placeholder_art.gd`, hornea con
  `godot --headless --path game tests/tools/bake_art.tscn` y luego
  `godot --headless --path game --import`.
- **Textos.** Nada de texto fijo en el código: agrega la clave en
  `game/data/i18n/ui.csv` (columnas `keys,es,en`; usa comillas si el texto lleva
  comas) y usa `tr("CLAVE")`.

---

## 4. Reglas del proyecto

1. **100 % contenido original.** Mecánicas del género sí; nunca copies sprites,
   sonidos, música, nombres, textos, mapas ni datos de otros juegos.
   Inventario en [`docs/LICENSES.md`](docs/LICENSES.md).
2. **GDScript con tipos** en todo (`var x: int`, `func f() -> void`).
3. **Móvil primero.** Pantalla base 1280×720, botones de al menos 64 px.
4. **Presupuestos:** 60 fps con 150 unidades, < 100 draw calls, < 300 MB de RAM,
   APK < 60 MB. Mídelo en un teléfono real si tocas render o rutas.
5. **Interfaz en español** (inglés como segunda columna del CSV).
6. Código, nombres y commits en **inglés**; documentos en español.

---

## 5. Pruebas

Las pruebas son una escena (así existen los autoloads):

```bash
godot --headless --path game tests/run_tests.tscn                    # todas (~15 min)
godot --headless --path game tests/run_tests.tscn -- suite=f9_ideas1 # una suite
godot --headless --path game tests/run_tests.tscn -- slow            # + partidas IA vs IA largas
```

Salen con código 0 si todo pasa. Antes de mandar un cambio corre al menos las
suites que tocan tu área y, si puedes, la completa.

Notas que ahorran tiempo:
- Las suites de IA y rendimiento dependen de la carga de tu CPU; el número real
  de rendimiento es el del teléfono.
- No edites scripts mientras corre la suite completa.
- Las funciones anónimas de GDScript copian las variables locales: asignar
  dentro de una lambda no cambia la variable de afuera.

---

## 6. Exportar el APK

```bash
JAVA_HOME=<ruta a JDK 17> godot --headless --path game --export-debug "Android" ../build/realm-debug.apk
adb install -r build/realm-debug.apk
```

El APK de depuración se firma con la llave debug de tu Android SDK. Las llaves
de publicación nunca van al repositorio (`.gitignore` ya las excluye).

---

## 7. Flujo de trabajo

1. Crea una rama: `git checkout -b feat/lo-que-haces`.
2. Haz el cambio con su prueba (en `game/tests/`).
3. Corre las pruebas.
4. Commit en inglés con prefijo: `feat(...)`, `fix(...)`, `docs(...)`.
5. Abre un Pull Request contra `main` explicando qué cambia y cómo lo probaste.
   Pedro revisa y lo junta.

¿Por dónde empezar? Mira [`TODOS.md`](TODOS.md) (pendientes) y la sección
"Siguiente" de [`docs/BUILD-STATE.md`](docs/BUILD-STATE.md). Ideas de diseño en
[`docs/IDEAS-AOE2.md`](docs/IDEAS-AOE2.md) y plan del multijugador por internet en
[`docs/MULTIPLAYER-PLAN.md`](docs/MULTIPLAYER-PLAN.md).
