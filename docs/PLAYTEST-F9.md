# Playtest humano — F9 (arte, audio, contenido)

Estas cosas no se pueden medir con tests automáticos: necesitan ojos, oídos y
manos. Pedro, juega en el Galaxy S10 con audífonos o bocina y marca cada punto.
Anota cualquier cosa rara con la hora aproximada de la partida.

Instalar la versión de prueba:
```bash
adb -s R58M154WY9A install -r build/realm-debug.apk
```

## 1. Tutorial (10 min)
Menú principal → **Tutorial**.
- [ ] Las 5 misiones se entienden solo leyendo el panel (sin ayuda).
- [ ] La flecha amarilla siempre apunta a algo útil.
- [ ] Al terminar sale "¡Tutorial completado!" y **Volver al menú** funciona.
- [ ] **Saltar** a mitad del tutorial regresa al menú sin errores.

## 2. Arte (5 min, partida en Valle del Río)
- [ ] Distingues aldeano, miliciano, arquero, caballero y ariete sin seleccionarlos.
- [ ] Distingues tus unidades (azul) de las enemigas (rojo) de un vistazo.
- [ ] Las unidades caminan (piernas), golpean y voltean hacia donde van.
- [ ] Los aldeanos "trabajan" (balancean la herramienta) al talar, minar y construir.
- [ ] Los edificios se reconocen: Centro Urbano, casa, cuartel, granja, torre.
- [ ] El terreno no se ve como cuadrícula repetida.

## 3. Audio (10 min)
- [ ] La música del menú suena y no corta feo al entrar a la partida.
- [ ] En la partida suena el tema tranquilo; al ver una pelea cambia al de batalla
      y ~25 s después de que termina vuelve al tranquilo.
- [ ] Los sonidos de talar, minar, construir, espadas y flechas suenan solo cuando
      lo ves en pantalla, y no saturan en una batalla grande.
- [ ] Volumen: la música no tapa los efectos; nada lastima los oídos.
- [ ] ≡ → **Sonido: No** silencia todo y **Sonido: Sí** lo regresa.

## 4. Mapas (3 partidas cortas)
Nueva partida → Fácil → cada mapa.
- [ ] **Valle del Río**: el río separa las bases y los vados se encuentran.
- [ ] **Bosque Cerrado**: los caminos entre el bosque llevan al centro y al rival.
- [ ] **Tierras Doradas**: hay más oro y el centro vale la pena pelearlo.
- [ ] En los tres, sientes que tu inicio es igual de bueno que el del rival.

## 5. Dificultad (2 partidas completas)
- [ ] **Fácil**: le ganas sin mucha presión (si nunca juegas RTS, igual se puede).
- [ ] **Difícil**: te ataca con fuerza y se siente injusto ganarle rápido.

## 6. Rendimiento (lo mido yo por adb, tú solo avisa si algo se siente lento)
- [ ] Nada se traba en batallas grandes ni al abrir menús.

Cuando termines, dime "playtest F9" con lo que marcaste y lo que no.

## 7. Defensa (nuevo, 2026-10-19)
- [ ] Construir → Empalizada: el primer toque fija el inicio, cada toque mueve el fin, ✓ construye. ¿Se entiende sin explicación?
- [ ] Una Puerta en la muralla se abre para tus aldeanos y se cierra cuando llega el enemigo.
- [ ] El Centro Urbano dispara a los primeros hostigadores.
- [ ] En Normal, la primera presión llega después del minuto 11: ¿ahora sí da tiempo de prepararse?
- [ ] Suena y se ve "¡Se acerca un ejército!" antes de que lleguen.
- [ ] Al subir de era cambia el techo del Centro Urbano.
