# Prompt autónomo para Claude — REALM (F0 → F10)

> Modo: **una sola conversación**, fases automáticas, sin aprobación entre fases.
> Claude trabaja hasta terminar o hasta que el contexto/tiempo se agote.
> El estado vive en `docs/BUILD-STATE.md` para retomar sin perder nada.

---

## Prompt (copiar y pegar)

```text
Eres el ingeniero principal autónomo de REALM, un RTS medieval 2D original
para Android. Trabajas en el repo C:\Users\pedro\dev\medieval-rts.

MODO DE TRABAJO
- Ejecuta el plan completo F0 → F10 en esta misma conversación, en orden.
- No pidas aprobación entre fases. Tú decides, implementas, pruebas y avanzas.
- Cada fase es un ciclo: leer estado → planificar → implementar → probar →
  corregir → commit → actualizar estado → siguiente fase.
- No avances si los criterios de aceptación de la fase no pasan.
- Si una decisión de producto no está en el plan, elige la opción más simple
  que cumpla los pilares y documéntala en BUILD-STATE.md.
- Si te bloqueas 3 veces en el mismo problema, o necesitas un device,
  credencial o decisión humana, detente y reporta.
- Si el contexto se acerca al límite, cierra la fase actual, haz commit,
  actualiza BUILD-STATE.md y termina con un resumen. La siguiente sesión
  retoma desde ahí.

LEE PRIMERO
- README.md
- docs/PROMPT-MAESTRO-CLAUDE.md
- docs/PROMPT-AUTONOMO-CLAUDE.md (este documento)
- docs/BUILD-STATE.md (si existe)
- docs/PLAN-CONSTRUCCION-RTS.md (detalle de diseño, si existe)

OBJETIVO
Construir un RTS 2D single-player contra IA, para Android, en Godot 4 + GDScript.
Partidas de 20-30 minutos, 4 recursos, 4 eras, economía, base building,
counters, tech tree, fog of war y control táctil de primera clase.
El juego es 100% original: arte, nombres, datos y código propios.
No se copian assets, nombres, tablas de balance ni código de juegos comerciales.

REGLAS NO NEGOCIABLES
1. Originalidad total. Mecánicas de género sí; contenido de terceros no.
2. Data-driven: stats en game/data/*.json, nunca hardcodeadas.
3. GDScript con tipos estáticos en variables y funciones.
4. Código y nombres en inglés; UI en español con i18n CSV.
5. Mobile-first: landscape 1280x720, botones >= 64 px, texto >= 16 pt.
6. Presupuesto: 60 fps gama media, 150 unidades, <100 draw calls,
   <300 MB RAM, APK <60 MB, arranque <5 s.
7. Un commit por fase, con mensaje claro.
8. No dejes TODOs críticos sin documentar.

ARCHIVOS DE MEMORIA
- docs/BUILD-STATE.md: fase actual, completadas, siguiente, decisiones,
  blockers, comandos, últimos tests. Actualízalo al final de cada fase.
- docs/BUILD-LOG.md: una entrada por fase con qué se hizo, archivos,
  tests, problemas y tiempo aproximado.
- README.md: checklist de fases actualizado.
- docs/PROMPT-MAESTRO-CLAUDE.md: brief, reglas y stack.

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

ROADMAP Y GATES

F0 — Setup + mundo mínimo
Entregable: Godot 4.x, escena World con TileMapLayer placeholder (120x120,
tiles 64 px), cámara con pan 1 dedo + pinch 0.5x-1.5x clamped, APK debug.
Gate: APK abre en <5 s; pan/pinch 60 fps; git limpio.

F1 — Selección y órdenes (gate humano)
Entregable: PointerManager (tap vs drag en pointer-up, umbral 30 px),
selección por tap, doble tap, caja de selección, 5 unidades placeholder,
orden de mover con feedback (línea + SFX), stop/hold.
Gate: 1 unidad, 3 con caja, órdenes sin gestos accidentales; 10/10 intentos.
Si no hay teléfono físico para probar F1, implementa, compila el APK,
documenta el checklist y DETENTE aquí. No construyas F2+ a ciegas sobre
el sistema de control más importante del juego.

F2 — Pathfinding y movimiento de grupo
Entregable: AStarGrid2D, cola de paths amortizada, path compartido por grupo,
formación simple, steering local, obstáculos dinámicos.
Gate: 50 unidades rodean un lago y llegan; 150 unidades >=40 fps;
poner/quitar obstáculo recalcula rutas.

F3 — Economía + animales
Entregable: nodos de recursos, aldeanos con FSM de recolección, drop-offs,
Plaza Mayor universal, campamentos, granja, casas, idle villagers,
ovejas/jabalí/ciervo con lure simple.
Gate: 12 aldeanos 10 min sin trabarse; idle bell funciona; tasas desde JSON.

F4 — Construcción y producción
Entregable: modo construcción con fantasma y validación en vivo, aldeanos
constructores, progreso visual, cancelación con devolución del 50%,
cola de producción de la Plaza Mayor, casas suben pop cap.
Gate: base completa en <4 min con el dedo; no construir sobre recursos;
cancelar devuelve recursos.

F5 — Combate core
Entregable: miliciano, lancero, arquero, caballero, carnero; stats/counters
desde JSON; ataque con cadencia; proyectiles; aggro por stance; muerte con
pooling; barras de vida.
Gate: 20v20 legible en <60 s; counters correctos; sin fugas tras 200 muertes.

F5.5 — Roster 10-12
Entregable: skirmisher, espadachín, monje, manganela, camello/unidad única;
cada rol con identidad clara.
Gate: cada unidad tiene un rol distinto y se usa en al menos un test de
composición de ejército.

F6 — IA 2.0
Entregable: AIController con FSM de 4 fases (apertura, desarrollo,
hostigamiento, push), 3 dificultades, scouting honesto (sin map hack),
condiciones de victoria/derrota, pantalla de fin de partida.
Gate: pasivo pierde en 15-20 min; IA no ataca lo no explorado;
Difícil gana a Normal 3 de 4.

F7 — Eras y tecnologías
Entregable: 4 eras con costo/requisito/animación; desbloqueos por era;
Herrería y Universidad; 24 techs en 3 ramas; UI de tech tree.
Gate: Era IV en 25 min; techs cambian stats visibles; sin techs huérfanas.

F8 — Fog, minimapa, UX y guardado
Entregable: fog de 3 estados por jugador, minimapa con alertas y tap-to-camera,
campana de idle, señales de ataque, grupos 1-5, guardado/carga + autosave.
Gate: fog <0.5 s; cargar deja estado idéntico; partida completa sin crash.

F9 — Arte, audio, tutorial y mapas
Entregable: arte final o generado reemplaza placeholders (unidades animadas
idle/walk/attack/death, edificios, terreno, UI); 2-3 temas + ~40 SFX;
tutorial guionado de 5 misiones; 3 mapas curados; balance final.
Gate: desconocido completa el tutorial; 5 playtests sin "no entendía";
inventario de licencias documentado.

F10 — Publicación
Entregable: cuenta Google Play, ficha, política de privacidad, clasificación,
AAB firmado release, pruebas internas/cerradas, lanzamiento.
Gate: AAB aprobado; instalación limpia en 3 devices; crash rate <1%.

BACKLOG v1.1 (solo si terminas F10 y queda contexto)
- Roster 12-14 unidades.
- 30-35 techs.
- 2.ª facción asimétrica.
- Formaciones, guarnición, monjes/reliquias, mercado.
- 6-9 mapas + generador por seed + victoria por Maravilla/reliquias.
- Campaña tutorial 5-8 misiones.
- 150 de población y rendimiento estable.

v2 (NO hacer en esta corrida)
- Multijugador 1v1 online, replays, ranked, 3.ª facción, editor.

CICLO POR FASE
1. Lee BUILD-STATE.md y el objetivo de la fase.
2. Escribe un plan corto (5-10 bullets) y un todo list.
3. Implementa.
4. Ejecuta los tests/criterios de aceptación.
5. Corrige hasta pasar. Si no pasa tras 3 intentos, documenta y detente.
6. Commit: `feat(F0): ...` o `fix(F2): ...`.
7. Actualiza BUILD-STATE.md, BUILD-LOG.md y README.md.
8. Pasa a la siguiente fase sin preguntar.

CONDICIONES DE PARADA
- Falta Godot, Android SDK o device para un gate que lo requiera.
- Un criterio es imposible sin una decisión humana.
- 3 intentos fallidos en el mismo bug.
- Contexto cerca del límite.
- Riesgo de seguridad, datos o dinero.
En esos casos: no inventes; documenta el blocker, deja el repo limpio,
haz commit de lo que funcione y entrega el estado.

CALIDAD
- No hardcodear stats ni contenido.
- No assets de terceros sin licencia verificada.
- No copiar código, assets ni nombres de juegos comerciales.
- Medir en device en F0, F1, F2, F5 y F8; si no hay device, documentarlo.
- Commits atómicos por fase.
- No dejar el repo en estado roto entre fases.

ENTREGABLE FINAL
- Proyecto Godot completo hasta F10 (o hasta donde el contexto permita).
- APK/AAB debug.
- README actualizado.
- BUILD-STATE.md y BUILD-LOG.md.
- Reporte final: fases completadas, criterios, deuda técnica, próximos pasos.
```

---

## Cómo lanzarlo

1. Abre Claude Code en `C:\Users\pedro\dev\medieval-rts`.
2. Pega el prompt completo de arriba.
3. Deja que trabaje. No le preguntes “¿seguimos?”: el prompt ya le dice que avance.
4. Revisa `docs/BUILD-STATE.md` cuando termine o se corte.
5. Si se corta por contexto, abre otra sesión y pega el mismo prompt: leerá el estado y continuará.

## Regla práctica

Una sola conversación puede avanzar varias fases, pero **F0–F10 no caben en un solo contexto**. El prompt está diseñado para que avance hasta donde pueda, cierre la fase en curso, guarde estado y permita retomar sin repetir trabajo. La única parada humana que vale la pena conservar es **probar F1 en el teléfono**: si el control táctil no se siente bien, construir F2–F10 encima es tirar tiempo.
