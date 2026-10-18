# Prompt maestro para Claude — REALM

> Uso: pegar el **Prompt maestro** al inicio de cada conversación con Claude.
> Después pegar el **prompt de la fase** que toca. Una fase = una conversación.
> Este brief describe un juego original. No se copian assets, nombres, datos ni código de terceros.

---

## 1. Objetivo general

Construir **REALM**, un RTS (real-time strategy) medieval 2D para Android:

- Single-player 1v1 contra IA, partidas de 20-30 minutos.
- 4 recursos: comida, madera, oro, piedra.
- 4 eras: Asentamientos, Fortalezas, Coronas, Imperio.
- Economía con aldeanos, drop-offs, granjas y casas.
- Base building con 14 edificios y ~100-150 de población.
- Combate con counters por clase, daño tipado, proyectiles y asedio.
- Tech tree de 16 techs en v1.0; 30-35 en v1.1.
- Fog of war, minimapa, scouting y build orders.
- Control táctil de primera clase: selección, caja, órdenes, cámara.
- Godot 4 + GDScript, renderer Compatibility, Android landscape.

**Pilares de diseño**

1. **Touch-first**: cada gesto se diseña para el pulgar, no para un mouse.
2. **Legibilidad**: el jugador entiende qué pasa en pantalla sin leer mucho.
3. **Tensión economía/ejército**: cada minuto invertido en uno es un minuto sin el otro.
4. **Data-driven**: todo el balance vive en JSON, no en scripts.
5. **Sesiones cortas**: 20-30 minutos, guardado y reanudación.
6. **Contenido original**: arte, nombres, datos y código propios.

---

## 2. Reglas no negociables

1. **Originalidad total.** Mecánicas de género sí; assets, nombres, tablas de balance, música, UI o código de juegos comerciales no.
2. **Nada de artefactos de terceros.** No se descargan, decompilan ni extraen archivos de juegos comerciales.
3. **Data-driven.** `game/data/units.json`, `buildings.json`, `techs.json`, `civs.json`, `maps/*.json`.
4. **GDScript tipado** en variables y funciones.
5. **Código y nombres en inglés**; textos de UI en español con i18n CSV desde F0.
6. **Mobile-first.** Base 1280x720 landscape, botones >= 64 px, texto >= 16 pt.
7. **Presupuesto de rendimiento:** 60 fps gama media, 150 unidades, <100 draw calls, <300 MB RAM, APK <60 MB, arranque <5 s.
8. **Una fase por conversación.** No avanzar sin cumplir criterios de aceptación y sin aprobación de Pedro.
9. **Cada fase termina con:** archivos creados/modificados, cómo probar en Android, criterios cumplidos, riesgos, commit.

---

## 3. Stack y arquitectura

- **Godot 4.x** (fijar versión exacta en `README.md` antes de F0; no actualizar a mitad de fase).
- **Renderer:** Compatibility (OpenGL ES 3.0).
- **Lenguaje:** GDScript tipado.
- **Pathfinding:** `AStarGrid2D`, celdas de 64 px, cola de paths amortizada, steering local, formación simple.
- **Datos:** JSON en `game/data/`.
- **Señales:** `EventBus` para recursos, muertes, UI y alertas.
- **Objetos:** pooling para proyectiles y unidades muertas.
- **Guardado:** JSON en `user://`, autosave cada 2 minutos.
- **Tests:** escenas de prueba y/o GUT; medir en device, no solo en editor.

```
game/
├─ project.godot
├─ autoload/          # game_state, data_loader, event_bus, save_manager
├─ scenes/
│  ├─ main/           # main, world, player, ai_controller
│  ├─ units/
│  ├─ buildings/
│  ├─ projectiles/
│  └─ ui/             # hud, minimap, context panel, menu
├─ systems/           # selection, pathfinding, economy, combat, construction, fog, ai
├─ data/              # units.json, buildings.json, techs.json, civs.json, maps/
├─ assets/            # placeholder/ -> art/ y audio/ en F9
└─ tests/
```

---

## 4. Hitos

### v1.0 — MVP+

| Hito | Objetivo | Criterio de aceptación |
|---|---|---|
| **F0** | Setup + mundo mínimo | APK abre en <5 s; pan/pinch 60 fps; cámara clamped; commit limpio |
| **F1** | Selección y órdenes | Tap, doble tap, caja, órdenes y cámara sin gestos accidentales; 10/10 intentos |
| **F2** | Pathfinding y grupos | 50 unidades rodean un lago y llegan; 150 unidades >=40 fps; obstáculos dinámicos |
| **F3** | Economía + animales | 12 aldeanos 10 min sin trabarse; idle bell; tasas desde JSON; ovejas/jabalí/ciervo |
| **F4** | Construcción y producción | Base completa en <4 min con el dedo; no construir sobre recursos; cancelar devuelve 50% |
| **F5** | Combate core | 20v20 legible en <60 s; counters correctos; sin fugas tras 200 muertes |
| **F5.5** | Roster 10-12 | Skirmisher, espadachín, monje, manganela, camello/unidad única; roles distintos |
| **F6** | IA 2.0 | Jugador pasivo pierde en 15-20 min; IA sin map hack; Difícil gana a Normal 3/4 |
| **F7** | Eras y 24 techs | Era IV en 25 min; techs visibles y funcionales; sin techs huérfanas |
| **F8** | Fog, minimapa, UX, save | Fog <0.5 s; guardar/cargar idéntico; partida completa sin crash |
| **F9** | Arte, audio, tutorial, mapas | Desconocido completa tutorial; 5 playtests sin "no entendía"; licencias documentadas |
| **F10** | Publicación | AAB aprobado; 3 devices; crash rate <1% |

### v1.1 — 90% del feel

- Roster 12-14 unidades.
- 30-35 techs.
- 2.ª facción asimétrica.
- Formaciones (línea/caja), guarnición, monjes/reliquias, mercado.
- 6-9 mapas, generador por seed, victoria por Maravilla/reliquias.
- Campaña tutorial de 5-8 misiones.
- Pulido de audio/visual.
- 150 de población y rendimiento estable.

### v2

- Multijugador 1v1 online, replays, ranked.
- 3.ª facción, más campañas, editor de mapas.

---

## 5. Prompt maestro (copiar y pegar al inicio de cada sesión)

```text
Eres el ingeniero principal de REALM, un RTS medieval 2D original para Android.
Trabajas en el repo C:\Users\pedro\dev\medieval-rts.

Antes de escribir código, lee completos:
- README.md
- docs/PROMPT-MAESTRO-CLAUDE.md (este documento)

Para F0 no necesitas otros documentos. Cuando lleguemos a fases que requieran
más detalle de diseño, Pedro te pasará el prompt específico de esa fase.

OBJETIVO
Construir un RTS 2D single-player contra IA, para Android, en Godot 4 + GDScript.
Partidas de 20-30 minutos, 4 recursos, 4 eras, economía, base building,
counters, tech tree, fog of war y control táctil de primera clase.
El juego es 100% original: arte, nombres, datos y código propios.
No se copian assets, nombres, tablas de balance ni código de juegos comerciales.

REGLAS
1. Originalidad total. Mecánicas de género sí; contenido de terceros no.
2. Data-driven: stats en game/data/*.json, nunca hardcodeadas.
3. GDScript con tipos estáticos en variables y funciones.
4. Código y nombres en inglés; UI en español con i18n CSV.
5. Mobile-first: landscape 1280x720, botones >= 64 px, texto >= 16 pt.
6. Presupuesto: 60 fps gama media, 150 unidades, <100 draw calls,
   <300 MB RAM, APK <60 MB, arranque <5 s.
7. Una fase por conversación. No avances sin cumplir los criterios
   de aceptación y sin que Pedro lo pida.
8. Al terminar: lista de archivos, cómo probar en Android, criterios
   cumplidos, riesgos y commit.

STACK
Godot 4.x (fijar versión exacta en README antes de F0), renderer Compatibility,
GDScript tipado, AStarGrid2D, cola de paths amortizada, steering local,
EventBus, pooling, JSON, guardado en user://.

ARQUITECTURA
game/
  project.godot
  autoload/ (game_state, data_loader, event_bus, save_manager)
  scenes/ (main, units, buildings, projectiles, ui)
  systems/ (selection, pathfinding, economy, combat, construction, fog, ai)
  data/ (units.json, buildings.json, techs.json, civs.json, maps/)
  assets/ (placeholder/ -> art/ y audio/ en F9)
  tests/

FASE ACTUAL: [pegar aquí la fase]
Objetivo: [pegar objetivo]
Entregable: [pegar entregable]
Criterios de aceptación: [pegar checklist]
No implementes fases futuras. Al terminar, reporta y espera aprobación.
```

---

## 6. Prompt F0 — Setup + mundo mínimo

```text
FASE F0 — Setup + mundo mínimo.

Objetivo: proyecto Godot creado, corriendo en el teléfono con grid y cámara.

Entregable:
- Repositorio con proyecto Godot 4.x.
- Escena World con TileMapLayer de pasto/agua/bosque (placeholders).
- Cámara con pan de 1 dedo y pinch-zoom táctil (0.5x-1.5x, clamped a bordes).
- APK debug instalado y corriendo en un teléfono físico.

Tareas:
1. git init si hace falta; estructura de carpetas; .gitignore de Godot.
2. project.godot: renderer Compatibility, resolución base 1280x720,
   orientación landscape, nombre REALM.
3. Generar grid placeholder de 120x120 tiles de 64 px con ruido simple
   (agua/pasto/bosque). Sin arte final.
4. CameraController con pan de 1 dedo y pinch de 2 dedos, zoom 0.5x-1.5x,
   límites del mapa.
5. Export Android debug: keystore debug, APK/AAB debug, instalar en device.

Criterios de aceptación:
- [ ] El APK abre en el teléfono en <5 s y muestra el mapa.
- [ ] Pan fluido a 60 fps; pinch fluido entre 0.5x y 1.5x sin salir del mapa.
- [ ] git status limpio después del commit.

No implementes selección, unidades, economía ni combate todavía.
Al terminar, reporta archivos, cómo probar y criterios cumplidos.
```

---

## 7. Prompt F1 — Selección y órdenes

> No usar hasta cerrar F0 y aprobarlo.

```text
FASE F1 — Selección y órdenes (el "feel" táctil).

Objetivo: validar el riesgo #1 (control táctil) antes de invertir en nada más.

Entregable:
- PointerManager con detección tap vs drag en pointer-up (umbral 30 px).
- Selección por tap, doble tap (mismo tipo visible), caja de selección por drag.
- 5 unidades placeholder que se mueven a un punto con feedback:
  línea de destino + SFX placeholder.
- Cámara que no roba gestos de selección.

Tareas:
1. PointerManager con IDs de pointer y multitouch real.
2. Highlight de selección (círculo verde) y orden de mover al tocar el suelo.
3. Caja de selección táctil con rectángulo visible.
4. 5 unidades de prueba con movimiento directo (sin pathfinding aún).
5. Botón de stop/hold y feedback de orden confirmada.

Criterios de aceptación:
- [ ] En teléfono: seleccionar 1 unidad, 3 con caja, y ordenar movimiento
      a varios puntos sin que un gesto robe al otro.
- [ ] 10 intentos seguidos sin un gesto no previsto.
- [ ] Si no se siente bien, iterar AQUÍ antes de F2.

No implementes pathfinding, economía ni combate todavía.
Al terminar, reporta archivos, cómo probar y criterios cumplidos.
```

---

## 8. Checklist de cierre por fase

- [ ] Criterios de aceptación cumplidos y probados en teléfono físico.
- [ ] Sin errores en consola ni warnings nuevos.
- [ ] Sin assets de terceros sin licencia.
- [ ] `README.md` actualizado con el estado de la fase.
- [ ] Commit con mensaje claro.
- [ ] Reporte: archivos, cómo probar, qué falta, riesgos.
