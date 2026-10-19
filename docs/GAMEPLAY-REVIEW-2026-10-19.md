# Revisión de jugabilidad — REALM vs. el RTS clásico del género (2026-10-19)

Referencia: las mecánicas que hicieron memorable al RTS medieval clásico de los
90 (economía que crece, edades, murallas y torres, contadores, mapa). Solo se
comparan **mecánicas y sensaciones**: REALM no copia nombres, arte ni datos.

Lo que dijo Pedro tras ganarle a Fácil: "casi no ataco", "no te da tiempo de
hacer nada cuando ya te están atacando", "si te apuras apenas subes de nivel",
"se podían poner murallas y torres", "los monos y gráficos más parecidos".

## 1. Pilares del género y cómo está REALM

| Pilar | En el clásico | En REALM hoy | Hueco |
|---|---|---|---|
| **Economía que crece** | Aldeanos, campamentos, granjas, mercado; "boom" como estrategia | Igual (D3-D23, D65) | — |
| **Edades como hitos** | 4 edades; subir cambia unidades, edificios y el aspecto | 4 eras, 24 techs; sube el nombre y los botones | Subir de era no se **ve** (mismos sprites, misma música) |
| **Defensa que se construye** | Empalizada, muralla de piedra, puerta, torres, castillo; el Centro Urbano dispara | Solo torre de vigía (Era II, 125 piedra) | **Sin murallas ni puertas; el Centro Urbano no dispara** |
| **Ventana de paz** | ~10 min sin ataques serios; rush temprano es cosa de expertos | Normal hostiga en el min 12 y empuja en el 17; Fácil en 17/24 | Correcto en números, pero **sin defensa posible** se siente injusto |
| **Contadores** | Lanceros > caballería > arqueros > infantería; asedio > edificios | Igual (F5) | — |
| **Control del mapa** | Oro y piedra lejos, caza, reliquias | Oro/piedra extra lejos, caza | Sin reliquias ni motivos para pelear el centro (salvo Tierras Doradas) |
| **Feedback** | Sonido por todo, alertas, campana de ociosos | Igual (F8, F9) | Falta "edificio completado" visible, cola con íconos |
| **Victoria** | Conquista, maravilla, reliquias | Conquista + rendición | Solo una forma de ganar |
| **Aspecto** | Sprites isométricos con 8 direcciones, árboles individuales, orilla de agua, caminos | Sprites vista 3/4 de 2 direcciones, bosque de bolitas, agua lisa | **Árboles, orillas y unidades se ven pobres** |

## 2. Diagnóstico de lo que sintió Pedro

1. **"No da tiempo"**: no es el reloj, es que al min 12 no hay **nada** que
   construir para frenar: ni empalizada, ni torre temprana, ni Centro Urbano
   que dispare. En el clásico un rush se frena con el Centro Urbano y una
   empalizada barata.
2. **"Apenas subes de nivel"**: Era II cuesta 350 de comida (+60 s) y pide 2
   edificios; con el ritmo nuevo (D70) ya es más suave, pero la **presión
   llega a la vez** que la era. La paz debe depender de la dificultad.
3. **"Casi no ataco"**: ganó por economía; la IA Fácil es pasiva por diseño
   (D71). Correcto para Fácil; en Normal sí va a tener que atacar.

## 3. Plan de ajustes (esta noche)

### A. Defensa construible
- **Empalizada** (Era I, 5 madera por tramo, 1x1, 250 HP) y **muralla de
  piedra** (Era II, 5 piedra por tramo, 900 HP): se trazan **arrastrando**
  (una línea de tramos), con costo por tramo y vista previa verde/roja.
- **Puerta** (Era I, 30 madera, 1x1): se abre sola para unidades propias y se
  **cierra cuando hay enemigos cerca** (bloquea el paso y hay que tirarla).
- **Centro Urbano dispara flechas** (débiles, alcance medio): frena un
  hostigamiento de 6 milicianos, no un empuje de 20.
- La IA también construye **1-2 torres** desde la fase de hostigamiento y
  sabe **romper murallas** (ataca lo que le estorba; los arietes ya tienen
  bono contra edificios).

### B. Ventana de paz por dificultad
- `first_attack_min` en `ai.json`: Fácil 16, Normal 11, Difícil 8. Antes de
  ese minuto la IA no hostiga ni empuja (sí defiende).
- Aviso suave en el HUD cuando la IA sale a atacar por primera vez: ya existe
  "¡Te atacan!"; se agrega "Se acerca un ejército" cuando el enemigo es visto
  a mitad de camino (torres/explorador).

### C. Que subir de era se note
- Al subir de era: fanfarria (existe), **cambia el techo del Centro Urbano**
  (madera → piedra → teja → oro) y las unidades de Era III+ llevan más metal.

### D. Gráficos v3 (originales, estilo "sprite detallado")
- **Árboles individuales** con tronco, copa con luz y sombra proyectada.
- **Orilla**: pasto con arena donde toca agua; agua con brillo.
- **Unidades**: cuerpo con más volumen, escudos con el color del jugador,
  plumas/yelmos distintos, capas en caballería; vista **frontal y trasera**
  además de izquierda/derecha (4 direcciones) para que no "patinen" al
  subir/bajar.
- **Edificios**: pared lateral visible (3/4 real), más detalles por tipo.

### E. Más adelante (no esta noche)
- Reliquias o un "pozo de oro" central que dé ingreso: motivo para pelear.
- Segunda condición de victoria (maravilla).
- Garrison en el Centro Urbano.

## 4. Cómo se mide
- Tests: murallas bloquean el paso y se destruyen; puerta abre/cierra; CU
  dispara; IA no ataca antes de `first_attack_min`; IA rompe murallas.
- Gates que ya existían deben seguir: Difícil 3/4 vs Normal; pasivo pierde
  contra Normal en 15-20 (se recalibra si el CU que dispara lo mueve).
- En el S24: 60 fps con murallas largas (cada tramo es un edificio: vigilar
  draw calls y nodos), tutorial y una partida corta con captura.

## GSTACK REVIEW REPORT

Revisor: `/plan-ceo-review` (gstack 1.89), modo **SELECTIVE EXPANSION**, corrido
en modo autónomo por instrucción de Pedro ("trabaja toda la noche mientras
duermo"): en cada decisión se tomó la opción recomendada y queda anotada aquí
para que Pedro la confirme o la revierta. No se cambió configuración de gstack
(upgrade y routing quedaron pendientes para una sesión interactiva).

### 0A Premisa
Problema real: el jugador nuevo **no tiene forma de defenderse** cuando llega
la primera presión, así que la partida se siente injusta aunque los tiempos
sean los normales del género. El plan ataca la causa (defensa construible +
paz por dificultad), no el síntoma (retrasar a la IA sin más).

### 0B Código reutilizable
- Torres ya disparan (`CombatSystem._towers`): el Centro Urbano con flechas es
  **solo datos** (`combat` en `buildings.json`).
- Murallas = `Building` 1x1 normal (bloquea `NavGrid`, HP, armadura, arte en el
  atlas). Lo nuevo es el **trazo en línea** en `PlacementController` y el cobro
  por tramo en `ConstructionSystem`.
- Puerta = muralla que alterna `nav.set_blocked` según enemigos cercanos; los
  repaths ya existen (`MovementSystem._handle_nav_changes`).
- Rutas parciales: `AStarGrid2D.get_point_path(..., allow_partial_path=true)`
  hace que un ejército llegue hasta la muralla en vez de rendirse sin ruta.
- Fases de IA por dificultad: `phase_scale` ya existe; `first_attack_min` es
  un piso explícito en `ai.json`.

### 0C Estado soñado (12 meses)
```
HOY                         ESTA NOCHE                       IDEAL 12 MESES
Economía + 12 unidades  --> + murallas, puertas, CU que   --> + reliquias/maravilla,
+ eras + IA que gana        dispara, paz por dificultad,       guarnición, campañas,
sin forma de defenderse     eras visibles, arte v3             multijugador local
```

### 0G Cherry-pick (efecto / esfuerzo humano / CC)
| # | Propuesta | Esfuerzo | Decisión (auto, recomendada) |
|---|---|---|---|
| 1 | Empalizada + muralla de piedra con trazo por línea | M (humano 2 d / CC 1 h) | **ACEPTADA** |
| 2 | Puerta que se cierra con enemigos cerca | M | **ACEPTADA** (sin puerta, amurallar encierra a tus propios aldeanos) |
| 3 | Centro Urbano dispara flechas débiles | S | **ACEPTADA** |
| 4 | `first_attack_min` por dificultad + aviso "se acerca un ejército" | S | **ACEPTADA** |
| 5 | IA construye torres y rompe murallas (rutas parciales + arietes) | S | **ACEPTADA** (sin esto, amurallar = ganar gratis) |
| 6 | Techo del CU cambia por era | S | **ACEPTADA** |
| 7 | Misión 6 del tutorial: "amuralla y pon una torre" | S | **ACEPTADA** |
| 8 | Arte v3: árboles individuales, orilla, agua, unidades con más volumen | L | **ACEPTADA** (lo pidió Pedro) |
| 9 | Unidades con 4 direcciones | L | **DIFERIDA** a TODOS: duplica el atlas y el pintado; primero validar el estilo con Pedro |
| 10 | Reliquias / pozo de oro central | M | **DIFERIDA** |
| 11 | Maravilla (segunda victoria) | M | **DIFERIDA** |
| 12 | Guarnición en el CU | M | **DIFERIDA** |

### Secciones 1-11 (resumen de hallazgos y remedios aplicados)
1. **Arquitectura**: murallas como edificios normales evitan un sistema nuevo; el
   trazo por línea vive en `PlacementController` (modo `line`). Riesgo: 60
   tramos = 60 nodos `Building` con `_draw` cada uno; aceptable (<300 edificios)
   y todos comparten el atlas (un draw call por lote).
2. **Errores**: sin madera a mitad de línea → se construyen los tramos que
   alcanzan y suena `error`; celda ocupada/agua → se salta y se pinta roja;
   puerta sobre muralla propia → reemplaza y devuelve el costo del tramo; sin
   ruta (base cerrada) → ruta parcial hasta la muralla, nunca "sin ruta".
3. **Seguridad**: sin red ni datos personales; nada nuevo.
4. **Flujo de datos / estados**: puerta `open/closed` con histéresis (cierra
   con enemigo a 5 celdas, abre sin enemigos a 6 celdas durante 1 s) para no
   oscilar `set_blocked` cada frame. Guardado: `is_open` en `SaveGame`.
5. **Calidad**: costo por tramo y lista de tipos de muralla en JSON; nada
   codificado a mano.
6. **Tests**: murallas bloquean y se destruyen; puerta abre/cierra por
   enemigos; CU dispara y mata hostigadores pero no un empuje; IA no ataca
   antes de `first_attack_min`; ejército con base amurallada llega a la muralla
   y la rompe; techo del CU cambia por era; tutorial 6/6; guardar/cargar con
   murallas y puertas. Gates previos se repiten (duelo, pasivo, Era IV).
7. **Rendimiento**: medir en el S24 con 80 tramos de muralla + 100 unidades.
8. **Observabilidad**: `[REALM] wall placed n=… cost=…`, `[REALM] gate open/closed`,
   `[REALM] ai … explore/push` ya existen.
9. **Rollout**: todo en datos (`buildings.json`, `ai.json`, `rules.json`); se
   puede apagar la puerta automática con `rules.gates.auto` sin tocar código.
10. **Largo plazo**: la puerta por bloqueo global del NavGrid es un atajo
    aceptable hasta tener navegación por jugador (TODOS).
11. **UX**: botón "Muralla" en Construir → modo línea: primer toque fija el
    inicio, cada toque mueve el fin, ✓ construye; costo total visible en el
    panel mientras se traza.

### Veredicto
| Corridas | Estado | Hallazgos |
|---|---|---|
| 1 (autónoma) | APROBADO con decisiones auto-tomadas | 8 aceptadas, 4 diferidas |

VERDICT: implementar A-D esta noche; E a TODOS.

NO UNRESOLVED DECISIONS
