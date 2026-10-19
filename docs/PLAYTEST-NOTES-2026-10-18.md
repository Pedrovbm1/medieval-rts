# Notas del playtest de Pedro — 2026-10-18 (S10)

Observado por adb sin tocar el teléfono: registros del juego `[REALM]` y una
captura de pantalla por minuto. Versión instalada: build de las 19:16
(commit 214fb61, **sin** el arte v2, los íconos de costo ni el arreglo del
volteo, que están en 7ba0bd9).

## Línea de tiempo
| Hora | Qué pasó |
|---|---|
| 19:17-19:21 | Tutorial: construyó una casa (19:18) y peleó en la misión 5 (19:20). |
| 19:21-19:37 | Partida 1 en Valle del Río. La IA hostiga en el min 11 y empuja con 19 soldados en el min 14.5; Pedro **no había construido cuartel**. Sale al menú en el min ~15.5. |
| 19:37 | Partida 2 en Valle del Río. |
| 19:52 | Pedro llega a Era II (min 15). Construye galería de tiro (19:53) y otra (19:57). |
| 19:55 / 20:01 | La IA llega a Era III (min 18.8) y Era IV (min 24.6). |
| 20:05 | Pedro llega a Era III (min 28) y construye establo. |
| 20:11 | Primer ataque de Pedro: 17 unidades a la base enemiga. |
| 20:17-20:20 | Pedro busca oro lejos (campamentos mineros en (38,61) y (81,45), este último ya en la mitad de la IA) y pone una torre. **Pedro: "ya no hay oro de donde cavar"** (min ~41). |
| 20:27-20:28 | Pedro construye casas y 2 torres cerca del centro del mapa ((72,55), (57,62), (61,61)). |
| 20:28 | **Primer ataque de la IA en el min 51.5 con 55 soldados**, directo a las torres del centro. Pedro llega a Era IV al mismo tiempo. |
| 20:41-20:46 | Batalla grande en el centro (57 unidades de Pedro contra el ejército de la IA). La IA manda refuerzos a la base de Pedro ((2208,1824)) por primera vez. |
| 20:47 | Pedro sale al menú tras ~70 min **sin ganador**. |
| 20:07 | Min 30: Pedro tiene 44/55 de población, 15 casas, economía sana y casi sin soldados. **La IA no ha atacado ni una vez.** |

## Lo que vio Pedro (dicho por él)
1. Círculos de selección separados de los aldeanos → **arreglado** en 7ba0bd9.
2. A aldeanos, casas y edificios les falta diseño → **arte v2** en 7ba0bd9.
3. "Todo cuesta C, no sé qué es C" → **íconos** en 7ba0bd9.
4. "Mientras no estoy viendo, no hacen nada" → pendiente aclarar.

## Observaciones (registros y capturas)
- **Órdenes repetidas:** en el tutorial tocó los arbustos de bayas 9 veces en 30 s, y en la partida repite "recolectar" sobre el mismo punto 2-4 veces seguidas. Señal de que **falta confirmación visible** de la orden (un marcador o un destello en el recurso, además del sonido).
- **Primera partida sin ejército:** a los 14.5 min la IA llegó con 19 soldados y no había cuartel. Falta que el juego **enseñe o avise** que hay que defenderse (el tutorial muestra milicia regalada, no cómo entrenarla).
- **Zoom 0.5x:** juega muy alejado; a esa distancia las unidades de 48 px miden ~24 px en pantalla.
- **Comida en 15** con 21 aldeanos y 4 granjas (min ~14 de la partida 2): la comida frena el crecimiento.
- **Cola con letras:** "Cola: I 1%" en el Centro Urbano y "Cola: Q Q Q Q Q 42%" en el establo. Las letras no dicen qué se entrena; deben ser íconos de la unidad.
- **Nombre del edificio:** el juego dice "Plaza Mayor", el tutorial dice "Centro Urbano". Hay que usar uno solo.
- **Rendimiento:** 60 fps y 47-51 draw calls durante la partida.
- **Aldeanos ociosos después de construir:** Pedro usó el botón Ociosos 28 veces en 33 min, a veces 3-5 veces seguidas al mismo aldeano. Causa en el código: al terminar una casa o un edificio militar el aldeano se queda sin tarea (solo los campamentos y granjas lo ponen a trabajar). Esto puede ser lo que Pedro describió como "mientras no estoy viendo, no hacen nada". Mejora propuesta: que el aldeano **regrese a lo que estaba recolectando** antes de construir.
- **La IA no atacó en 30 min** (partida 2), aunque en la partida 1, en el mismo mapa, atacó en el min 14.5. En una simulación en PC (Valle del Río, Normal contra un jugador pasivo) la IA encuentra la base en el min 6 y ataca en el min 12.7 y 18. **Confirmado:** la IA solo atacó (min 51.5, 55 soldados) cuando Pedro construyó torres cerca del centro; nunca había visto su base. Sin conocerla, acumula un ejército enorme y no ataca. Mejora propuesta: si la IA no conoce ninguna base enemiga, debe mandar otro explorador o un grupo a explorar. Además se agrega un registro de su estado cada minuto para el próximo playtest.
- **Abreviaturas en estadísticas:** "ATQ 3 ARM 1/1 VEL 86" es tan críptico como la "C" de los costos.
- **Bug de volteo confirmado en el teléfono:** un anillo verde aparece junto al aldeano y no debajo (ya arreglado en 7ba0bd9).
- **Se acaba el oro (min ~41):** en Valle del Río cada jugador tiene 4 minas de 800 = 3200 de oro. Eras (700) + arqueros/caballeros + técnicas lo agotan antes de que la partida se decida. Opciones: más oro por mina (p. ej. 1200), más minas por mapa, o un **mercado** para cambiar madera/piedra por oro (lo que hace el género cuando se acaba el oro).
- **Recursos desbalanceados al final (min ~44):** 2985 de comida y 1411 de madera sin uso, 115 de oro. Refuerza la idea del **mercado**.
- **Pedro pregunta "¿cómo consigo más oro?"** (min ~60): el juego no lo explica. En Valle del Río sus otras 2 minas están en la orilla izquierda a media altura, sin ninguna pista en pantalla; el campamento que puso quedó a ~18 casillas de ellas. Ideas: aviso "esta mina se agotó" + señalar en el minimapa minas ya exploradas; el mercado.
- **Rendimiento:** a las 20:37 bajó a 44.6 fps (peor frame 70 ms) con 400 nodos (batalla grande contra los 55 soldados de la IA). Medir en el S10 una batalla de ~100 unidades.
- **Draw calls hasta 270 con 57 unidades seleccionadas** (20:41, 54 fps). Causa: el anillo de selección se dibuja con `draw_arc` (sin la textura del atlas), lo que corta el batching: cada unidad seleccionada cuesta 2+ draw calls. Arreglo: hornear el anillo en el atlas y dibujarlo con la misma textura.
- **Plurales en el panel:** "25 Escaramuzador, 10 Camellero, 10 Lancero" → debería decir "25 escaramuzadores", etc.
- **Ejército final de Pedro (min ~64):** 57 unidades (25 escaramuzadores, 10 lanceros, 10 camelleros, 6 arqueros, 5 caballeros, 1 espadachín), población 94/100, 5875 de comida sin usar, 39 de oro.

## Resumen y prioridades

**Arreglar primero (bloquean la diversión o el rendimiento)**
1. **La IA debe encontrar al jugador:** si no conoce ninguna base enemiga, explorar otra vez (nuevo explorador o grupo). Sin esto la partida 2 tuvo 50 min sin un ataque y luego 55 soldados de golpe.
2. **Aldeanos que vuelven a trabajar** después de construir (regresan a lo que recolectaban). Es lo más probable detrás de "mientras no estoy viendo no hacen nada" (28 usos del botón Ociosos).
3. **Más oro / mercado:** el oro se acaba en el min ~40 y la partida se traba con miles de comida y madera sin uso.
4. **Anillo de selección en el atlas:** con 57 unidades seleccionadas los draw calls llegan a 270 (presupuesto < 100).

**Claridad (Pedro no entendía)**
5. Colas con íconos en lugar de letras ("Q Q Q Q Q").
6. Estadísticas sin abreviaturas ("ATQ / ARM / VEL").
7. Confirmación visible al dar una orden (marcador en el destino o destello en el recurso).
8. Enseñar a entrenar soldados y defenderse (en la partida 1 llegó al primer ataque sin cuartel).
9. Un solo nombre para el edificio principal ("Plaza Mayor" contra "Centro Urbano") y plurales en el panel.

**Ya hecho después de esta versión (7ba0bd9):** círculo de selección pegado a la unidad, arte v2, costos con íconos.

## Arreglado después del playtest
- Prioridades 1-4: D63 (aldeanos vuelven a trabajar), D64 (la IA busca al jugador), D65 (mercado), D66 (anillo en el atlas). Ver `docs/BUILD-STATE.md`.
