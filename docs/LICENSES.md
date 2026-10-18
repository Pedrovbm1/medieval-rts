# REALM — Inventario de licencias y contenido

Última revisión: 2026-10-18 (F9).

Regla del proyecto: **100 % contenido original**. Nada de sprites, sonidos,
música, nombres o textos de juegos existentes. Todo lo que el jugador ve u
oye se genera con código de este repositorio.

## 1. Contenido del juego (nuestro)

| Qué | Cómo se hace | Dónde | Licencia |
|---|---|---|---|
| Sprites de unidades (12 + animales, 6 poses, colores de jugador) | Pintados por código al arrancar | `game/systems/render/unit_painter.gd`, `raster.gd` | Propio |
| Edificios (13 tipos) | Pintados por código | `game/systems/render/building_painter.gd` | Propio |
| Terreno (3 variantes por tipo), recursos, íconos del HUD | Pintados por código | `game/systems/render/nature_painter.gd`, `game/systems/world/placeholder_tileset.gd` | Propio |
| Atlas único (1 textura, ~15 draw calls) | Empaquetado en runtime | `game/systems/render/placeholder_art.gd` | Propio |
| Fuente pixel del overlay de depuración | Glifos definidos en código | `game/systems/render/pixel_font.gd` | Propio |
| 47 efectos de sonido | Síntesis (senos, ruido, Karplus-Strong, filtros) | `tools/gen_audio.py` → `game/assets/audio/sfx/` | Propio |
| 3 temas musicales (menú, paz, batalla) | Composición procedural con semilla fija | `tools/gen_audio.py` → `game/assets/audio/music/` | Propio |
| Mapas (escaramuza + 3 curados simétricos) | JSON + ruido con semilla | `game/data/maps/` | Propio |
| Textos de interfaz (es/en) | Escritos a mano | `game/data/i18n/ui.csv` | Propio |
| Nombres (REALM, Northvale, unidades genéricas) | Propios o genéricos del medievo | `game/data/` | Propio |

Los archivos `.wav` se pueden regenerar idénticos con `python tools/gen_audio.py`
(determinista, sin dependencias externas).

## 2. Software de terceros incluido en el APK/AAB

| Componente | Licencia | Obligación |
|---|---|---|
| Godot Engine 4.7.2 (motor y plantillas de exportación) | MIT | Incluir el aviso de copyright y la licencia MIT en el juego |
| Bibliotecas que Godot compila dentro del motor (FreeType, HarfBuzz, ICU, mbedTLS, zlib, libpng, etc.) | Varias permisivas (FTL/BSD/MIT/zlib/Apache-2.0/Unicode) | Incluir el texto de `COPYRIGHT.txt` de Godot |
| Fuente por defecto del tema de Godot (usada en los `Label`/`Button`) | Incluida con el motor, licencia abierta (ver `COPYRIGHT.txt` de Godot) | Igual que arriba |

**Pendiente F10:** pantalla "Créditos y licencias" en el menú principal que
muestre el aviso MIT de Godot y el texto de terceros
(`Engine.get_license_text()` y `Engine.get_copyright_info()` lo dan en runtime).
Verificar en F10 el nombre exacto y la licencia de la fuente por defecto en
`COPYRIGHT.txt` de la versión 4.7.2.

## 3. Herramientas de compilación (NO van dentro del juego)

| Herramienta | Uso | Licencia |
|---|---|---|
| Android SDK / platform-tools / build-tools | Exportar e instalar | Términos del Android SDK |
| OpenJDK 17 (Temurin) | Firmar y empaquetar | GPLv2 + Classpath Exception |
| Python 3 (stdlib) | Generar audio | PSF |

Ninguna se distribuye con el juego.

## 4. Lo que NO usamos

- Ningún asset descargado (ni CC0, ni de tiendas): no hay atribuciones que cumplir.
- Ningún SDK de anuncios, analítica ni servicios de terceros.
- Ningún contenido de otros juegos del género.
