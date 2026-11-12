# Carpeta de imágenes

Esta carpeta está vacía en el repositorio a propósito: las fotos de las obras no se versionan por derechos de autor y para mantener el repositorio liviano.

Para usar la galería, copiá acá tus imágenes con este formato:

- `nombre__ANCHOxALTO.ext` (por ejemplo `paisaje__80x60.jpg`), con las medidas en centímetros.
- Sin medidas: `nombre.jpg` usa el tamaño por defecto (120 cm de lado mayor).
- Dentro de `colección/`, una carpeta por colección; el nombre de la carpeta se muestra en el cartel del pasillo.

Ejemplo:

```text
cuadros/
    sala_1__100x70.jpg
    colección/
        Impresionismo/
            obra1__90x60.jpg
            obra2__50x75.jpg
```

Formatos admitidos: jpg, jpeg, png, webp, bmp y tga.

El archivo `.gdignore` evita que Godot importe estas imágenes en el editor. No lo borres.
