# REALM — RTS medieval para Android

Juego RTS (real-time strategy) medieval original para Android, inspirado en los clásicos
del género. Construido en Godot 4 con GDScript.

**Nada en este proyecto usa assets, nombres, datos o código de juegos de terceros.**
Aquí no se analizan ni extraen artefactos de juegos propietarios. Mecánicas de género sí;
contenido propio, siempre.

## Descargar y jugar

**[⬇ Descargar el APK más reciente](https://github.com/Pedrovbm1/medieval-rts/releases/latest)**
(en el teléfono Android permite "instalar apps de origen desconocido").

- **Un jugador:** Nueva partida → dificultad (Fácil / Normal / Difícil) → mapa.
- **Multijugador por Wi-Fi:** los dos teléfonos en la misma red; uno entra a
  *Multijugador → Crear partida* (muestra su IP) y el otro a *Unirse con IP*.
- **Tutorial:** 7 misiones cortas que enseñan lo básico.

¿Quieres ayudar a desarrollarlo? Lee **[CONTRIBUTING.md](CONTRIBUTING.md)**.

## Qué tiene hoy
- 4 eras, 13 unidades con counters (lancero > caballo > arquero > infantería), 24 tecnologías.
- Economía con 4 recursos, granjas que se resiembran, mercado de compra/venta y caravanas.
- Murallas trazadas en línea, puertas que solo dejan pasar a tu bando, torres,
  guarnición con campana, reparar, carnero con embestida.
- IA en 3 dificultades (justa por defecto, sin bonos ocultos), niebla de guerra,
  minimapa con alertas, guardado y autoguardado.
- Tres formas de ganar: destruir el Centro Urbano rival, guardar todas las reliquias
  3 minutos, o mantener una maravilla en pie 3 minutos.
- Multijugador 1v1 por Wi-Fi (lockstep determinista).
- Arte, música y sonidos 100 % generados por código de este repo.

## Estado
- [x] Investigación + plan de construcción → `docs/PLAN-CONSTRUCCION-RTS.md`
- [x] F0 — Setup + mundo mínimo (aprobada 2026-10-17; probada en Galaxy S10)
- [x] F1 — Selección y órdenes (gate humano aprobado 2026-10-17)
- [x] F2 — Pathfinding (S10: 150 unidades a 60 fps, 50/50 rodean el lago)
- [x] F3 — Economía (12 aldeanos 10 min sin trabarse; 60 fps y 15 draw calls en S10)
- [x] F4 — Construcción (base completa en 64 s de juego; probado con toques reales en S10)
- [x] F5 — Combate (counters del plan; 20v20 en 49 s; sin fugas; 60 fps en S10)
- [x] F5.5 — Roster de 12 unidades con roles
- [x] F6 — IA enemiga (pasivo pierde en ~20 min; sin map hack)
- [x] F7 — Eras y 24 tecnologías
- [x] F8 — Fog of war + UX (niebla, minimapa, guardado; Difícil gana a Fácil en ~29 min)
- [ ] F9 — Arte y contenido (arte v3, audio, tutorial de 7 misiones, 3 mapas, murallas/puertas/torres, mercado; falta el playtest final de Pedro)
- [ ] IDEAS-AOE2 — mecánicas del clásico (`docs/IDEAS-AOE2.md`): hechos guarnición + campana, reparar, carnero/brecha, alertas, informe de fin, IA justa, granjas finitas, segundo CU, vetas centrales, compra en el mercado, reliquias, formaciones + attack-move, maravilla, caravana; falta la campaña
- [x] F10-mp — Multijugador LAN (lockstep; primera partida real teléfono↔teléfono 2026-10-20: 22 min, 0 desincronizaciones)
- [ ] F10 — Publicación en Play Store

## Cómo trabajar
Guía para colaboradores: **[CONTRIBUTING.md](CONTRIBUTING.md)**. El juego se construyó por
fases con Claude; el prompt base y los criterios de aceptación de cada fase están en
`docs/PROMPT-MAESTRO-CLAUDE.md` y `docs/PLAN-CONSTRUCCION-RTS.md`.

## Versión de Godot
**Godot 4.7.2 stable** (renderer Compatibility, GDScript). No actualizar a mitad de fase.

Requisitos para exportar a Android:
- Android SDK con `platform-tools`, `build-tools` 35+ y `platforms/android-35+`.
- JDK 17.
- Export templates 4.7.2 instalados (`Editor > Manage Export Templates`).

## Estructura
```
game/
├─ project.godot
├─ autoload/          EventBus, DataLoader, GameState, SaveManager, Sfx, Music, NetSession
├─ scenes/main/       main (partida), world, scenario_runner, cámara
├─ scenes/ui/         main_menu, hud, minimap
├─ systems/           selection, pathfinding, economy, construction, combat,
│                     ai, fog, tech, save, tutorial, net (multijugador), world (mapas),
│                     render (arte por código)
├─ data/              units/buildings/techs/eras/ai/audio/tutorial.json, maps/, i18n/ui.csv
├─ assets/audio/      sfx/ y music/ generados por tools/gen_audio.py
└─ tests/             run_tests.tscn + test_f*.gd (suites lentas: *_slow*)
tools/                gen_audio.py, scripts adb para el S10 (device_*.sh)
docs/                 BUILD-STATE, BUILD-LOG, LICENSES, plan y prompts
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
