# Galería 3D mínima

Galería de arte en primera persona. Lee las imágenes de la carpeta `cuadros` junto al ejecutable y cuelga un cuadro por imagen, a escala real si el nombre del archivo incluye las medidas. Las subcarpetas de `cuadros\colección\` se convierten en pasillos con cartel. Offline, sin dependencias.

> **Nota:** este repositorio no incluye las imágenes de las obras. Para usar la galería, copiá tus propios archivos en `cuadros/` siguiendo las reglas de nombres de este README. Ver `cuadros/README.md`.

## Requisitos

- Godot **4.3 estable** (o superior 4.x), versión estándar (no .NET): https://godotengine.org/download/archive/4.3-stable/
- Plantillas de exportación de la misma versión exacta.

## Abrir el proyecto

1. Abrir Godot → Importar → seleccionar `project.godot`.
2. Copiar imágenes en `cuadros/` (dentro del proyecto) y pulsar F5. En el editor se usa `res://cuadros`; la carpeta contiene un `.gdignore` para que Godot no importe los originales.

## Instalar las plantillas de exportación

Editor → Editor → Gestionar plantillas de exportación → Descargar e instalar.

## Compilar `Galeria.exe`

1. Proyecto → Exportar.
2. Si no aparece el preset "Windows Desktop" (el proyecto ya incluye uno): Añadir… → Windows Desktop.
3. Verificar que "Embed PCK" esté activado y la arquitectura sea x86_64.
4. En "Resources", dejar `cuadros/*` en el filtro de exclusión.
5. Pulsar "Exportar proyecto…", destino `build/Galeria.exe`, desactivar "Exportar con depuración".

## Estructura para distribuir

```
Galeria.exe
cuadros\
    sala_1__100x70.jpg               <- sala principal
    sala_2__60x90.jpg
    colección\
        Impresionismo\               <- un pasillo por carpeta
            obra1__90x60.jpg
            obra2__50x75.jpg
        Retratos del siglo XIX\
            retrato1__45x63.jpg
```

Copiar esa carpeta a cualquier PC con Windows 10/11 x86_64. No requiere instalar nada. Si `cuadros` no existe se crea al iniciar.

## Colecciones (pasillos)

- Dentro de `cuadros\` se crea la carpeta `colección` (también se aceptan `coleccion`, `colecciones` y cualquier combinación de mayúsculas). Dentro de ella, **una carpeta por colección**; el nombre de la carpeta es el título de la colección.
- Las imágenes sueltas en `cuadros\` forman la **sala principal**. Las de cada carpeta de colección van en su propio pasillo.
- Cada colección es un pasillo que sale de la sala principal por una puerta, con un **cartel con el título** sobre la puerta. Los nombres largos reducen el tamaño del texto para entrar en el cartel.
- Las colecciones se ordenan alfabéticamente (natural) y se reparten alternadas entre la pared norte y la pared sur de la sala (la primera al norte, la segunda al sur, etc.). La sala se ensancha lo necesario para que quepan todas las puertas.
- Dentro del pasillo, los cuadros se cuelgan en ambas paredes, alternando izquierda y derecha en el orden alfabético de los archivos. El largo del pasillo se ajusta a la cantidad y el tamaño de las obras.
- Valen las mismas reglas de nombres y medidas (`nombre__ANCHOxALTO.ext`), el zoom Z y la vista ampliada con E.
- Carpetas de colección vacías, o sin imágenes legibles, se omiten (se registra una advertencia). Las imágenes que estén sueltas dentro de `colección\` (fuera de una subcarpeta) se ignoran.
- Las subcarpetas de las colecciones no se exploran: solo se lee un nivel.
- La altura de la galería se calcula con la obra más alta de todas; los pasillos tienen la misma altura que la sala.

## Medidas reales en el nombre del archivo

Formato: `nombre__ANCHOxALTO.ext`, en centímetros, con dos guiones bajos antes de las medidas.

| Archivo | Resultado |
|---|---|
| `paisaje__80x60.jpg` | Cuadro de 80 × 60 cm. Se muestra como "paisaje" |
| `retrato__42,5x30cm.png` | 42,5 × 30 cm (coma o punto decimal; `cm` opcional; `x` o `X`) |
| `vista.jpg` | Sin medidas: lado mayor de `DEFAULT_SIDE_CM` (120 cm) |

Reglas:

- Las medidas son de la imagen visible; el marco se agrega por fuera.
- La imagen nunca se deforma. Si las medidas no coinciden con la proporción real del archivo (tolerancia 2 %), se usa el ancho y el alto se calcula desde la imagen. Si vienen invertidas (ancho y alto cambiados) se corrigen solas.
- Lado mayor admitido: de 5 a 600 cm; fuera de ese rango se ajusta.
- El marco y la separación entre cuadros son proporcionales al tamaño de la obra.
- Las obras altas se cuelgan más arriba si hace falta (borde inferior ≥ 10 cm del piso) y la galería crece en altura para contenerlas.
- Las advertencias (medidas inconsistentes o fuera de rango) se registran en la consola de Godot; en el `.exe` no se muestran.

## Controles

| Acción | Tecla |
|---|---|
| Moverse | WASD o flechas |
| Correr | Mantener Shift (2,5 → 4,0 m/s) |
| Agacharse | Mantener Ctrl (1,2 m/s; la cámara baja a 0,95 m) |
| Mirar | Mouse |
| Zoom de cámara | Z: normal → 2× → 4× → 8× → normal |
| Ver cuadro ampliado (a ≤ 2,5 m, apuntándolo) | E (E o Esc para cerrar) |
| Pausa / salir | Esc / Q en pausa |
| Pantalla completa | F11 |

Agacharse tiene prioridad sobre correr si se mantienen ambas teclas. Al soltar Ctrl el jugador se levanta; no hay obstáculos bajos en la galería, así que siempre puede hacerlo.

### Zoom (Z) y detalle

- Cada pulsación de Z pasa al siguiente nivel; después del tercero vuelve al zoom normal. Se muestra "Zoom N×" arriba.
- Con zoom activo, el giro del mouse se reduce proporcionalmente para apuntar con precisión.
- Al apuntar con zoom a un cuadro cuyo original supera `MAX_TEX_SIZE` (2048 px), se carga el original en segundo plano (hasta `HIRES_TEX_SIZE`, 4096 px) y reemplaza a la textura de pared. Mientras carga se muestra "(cargando detalle)".
- Solo un original en memoria a la vez: se libera al pasar a otro cuadro o al volver al zoom normal. La vista ampliada con E también usa el detalle si ya está cargado.
- Cuadros con original de 2048 px o menos no cargan detalle adicional.
- Ni la tecla E ni el zoom atraviesan paredes: un cuadro de otro pasillo no se puede seleccionar desde afuera.

## Constantes ajustables

En `main.gd`:

| Constante | Valor | Descripción |
|---|---|---|
| `MAX_TEX_SIZE` | 2048 | Lado mayor máximo de la textura de pared (px) |
| `HIRES_TEX_SIZE` | 4096 | Lado mayor máximo del detalle con zoom (px) |
| `HIRES_DISTANCE` | 8.0 | Distancia máxima para cargar el detalle (m) |
| `DEFAULT_SIDE_CM` | 120 | Lado mayor de imágenes sin medidas (cm) |
| `MIN_SIDE_CM` / `MAX_SIDE_CM` | 5 / 600 | Rango admitido del lado mayor (cm) |
| `ASPECT_TOLERANCE` | 0.02 | Tolerancia entre medidas e imagen |
| `HANG_HEIGHT` | 1.55 | Altura del centro del cuadro (m) |
| `GAP_FACTOR`, `GAP_MIN`, `GAP_MAX` | 0.625, 0.3, 1.0 | Separación entre marcos (m) |
| `CORNER_MARGIN` | 0.6 | Distancia mínima a esquinas y puertas (m) |
| `ROOM_HEIGHT` | 3.2 | Altura mínima de la galería (m) |
| `ROOM_RATIO` | 1.5 | Largo / ancho de la sala principal |
| `FRAME_THICKNESS`, `FRAME_DEPTH` | 0.04, 0.05 | Máximos del marco (m) |
| `VIEW_DISTANCE` | 2.5 | Distancia máxima para ampliar con E (m) |
| `COLLECTION_FOLDERS` | coleccion, colecciones | Nombres aceptados para la carpeta de colecciones |
| `CORRIDOR_WIDTH` | 3.2 | Ancho de pasillos y puertas (m) |
| `DOOR_HEIGHT` | 2.3 | Altura de las puertas (m) |
| `CORRIDOR_ENTRY_MARGIN`, `CORRIDOR_END_MARGIN` | 1.2, 1.2 | Distancia de la entrada al primer cuadro y del último al fondo (m) |
| `CORRIDOR_MIN_LENGTH` | 6.0 | Largo mínimo de un pasillo (m) |
| `SIGN_HEIGHT`, `SIGN_TEXT_HEIGHT` | 0.6, 0.34 | Alto del cartel y del texto (m) |
| `COLOR_*` | — | Colores de pared, piso, techo, marco y cartel |

En `player.gd`: `WALK_SPEED` (2,5), `RUN_SPEED` (4,0), `CROUCH_SPEED` (1,2), `EYE_HEIGHT` (1,6), `CROUCH_EYE_HEIGHT` (0,95), `CROUCH_HEIGHT` (1,1), `MOUSE_SENSITIVITY` (0,0025), `FOV` (65), `ZOOM_LEVELS` (2, 4, 8).

## Detalles técnicos

- Renderer Compatibility (OpenGL), VSync activo, 60 FPS máximo, filtro anisotrópico 4x.
- Las imágenes (de la sala y de todas las colecciones) se cargan en un hilo, se reducen a `MAX_TEX_SIZE` con mipmaps y se descartan de memoria tras crear la textura. Los originales no se modifican.
- Una textura por archivo, compartida entre la pared y la vista ampliada.
- Todos los marcos se dibujan con un único MultiMesh. Draw calls aproximados: cantidad de imágenes + 8 + 7 por colección (5 piezas del pasillo, cartel y texto).
- Iluminación: luz ambiente + una luz direccional sin sombras. Se usó luz direccional en lugar de varias OmniLight3D porque el renderer Compatibility limita las luces por objeto y las paredes largas parpadearían.
- Distribución de la sala: secuencial por los tramos de pared libres de puertas, grupo centrado en cada tramo, ningún cuadro cruza una esquina ni una puerta. La sala crece para que todo quepa.
- Pasillos: salen hacia afuera de las paredes norte y sur, contiguos entre sí (separados por sus propias paredes), por lo que no pueden superponerse entre sí ni con la sala.
- El texto del cartel usa la fuente por defecto de Godot (cubre tildes y Ñ).
- FOV vertical de 65° (en lugar de 75°) para que los tamaños se perciban más cercanos a la escala real.
- Autoprueba: `godot --headless --path . -- --selftest` verifica medidas, distribución, que los pasillos no se superpongan, que la puerta se pueda cruzar caminando, que la selección no atraviese paredes, el zoom con carga y liberación del detalle, y las velocidades de correr y agacharse (incluyendo altura de cámara y cápsula).

## Limitaciones conocidas

- Formatos: jpg, jpeg, png, webp, bmp, tga. Otros archivos se ignoran.
- La orientación EXIF no se aplica: una foto guardada con rotación EXIF puede verse girada.
- PNG con transparencia: se conserva el alfa, pero el cuadro no se mezcla con la pared.
- Si se renombra un archivo, hay que mantener el sufijo `__ANCHOxALTO`; sin él pasa al tamaño por defecto.
- Memoria: textura de 2048×1536 RGB con mipmaps ≈ 12,6 MB; 100 imágenes ≈ 1,3 GB, contando sala y colecciones. El detalle con zoom suma hasta ≈ 50 MB por un cuadro a la vez. Bajar `MAX_TEX_SIZE` a 1536 reduce el uso casi a la mitad.
- Una obra de más de ~4 m de ancho se ve blanda de cerca aun con detalle de 4096 px.
- Los pasillos salen solo de las paredes norte y sur. Con muchísimas colecciones (decenas) la sala se vuelve muy ancha.
- Un solo nivel de colecciones: no hay subcolecciones.
- La carpeta se lee solo al iniciar; para agregar imágenes o colecciones hay que reiniciar.
