# Mata Zancudos

Juego sencillo hecho en **Godot 4.7**: los zancudos se posan en una ventana y hay
que aplastarlos con el clic (PC/web) o el toque (móvil). Si dejas que se acumulen
hasta cubrir más del **70 %** de la pantalla, pierdes.

El top 5 de puntajes se guarda en línea en Firebase Realtime Database.

## Cómo se juega

- **Menú**: título, botón COMENZAR y la tabla de mejores puntajes.
- **Partida**: los zancudos entran volando y **se quedan** en la ventana hasta que
  los aplastas. La barra `PANTALLA` muestra cuánto llevan ocupado.
- **Puntos**: aplastar rápido paga más (hasta 4 puntos), y tres aplastamientos
  seguidos dan **combo x2**. Los zancudos grandes valen el doble.
- **Fin**: al pasar del 70 % de ocupación. Escribes tu nombre, se sube el puntaje
  y aparece el top 5 con tu entrada resaltada.

## Estructura

```
scenes/     escenas (menú, partida, zancudo, HUD, panel de puntajes)
scripts/    lógica del juego y autoloads (GameData, Sfx)
assets/     sprites y sonido, generados por tools/
tools/      generadores de assets y pruebas (no se exportan, ver tools/.gdignore)
build/web/  build web lista para publicar, con Docker
addons/     plugin del editor (MCP de Godot); no forma parte del juego
```

## Ejecutar

Abre el proyecto en Godot 4.7 y pulsa **F5**, o desde consola:

```bash
godot --path .
```

## Regenerar los assets

Los sprites y el sonido son **generados por código**, sin dependencias externas ni
licencias de terceros:

```bash
node tools/make-assets.mjs    # zancudo (4 frames), mancha y ventana -> assets/sprites
node tools/make-sounds.mjs    # sonido de aplastamiento -> assets/audio
```

## Pruebas

Se ejecutan con el motor en modo headless, indicando la escena de prueba como
escena principal:

```bash
# Reglas del juego, sonido, ocupación, guardado y nube
godot --headless --path . --quit-after 20000 res://tools/smoke_test.tscn

# Clics reales en los botones de fin de partida (necesita ventana, no headless)
godot --path . --quit-after 20000 res://tools/button_test.tscn
```

`smoke_test` sube un puntaje de prueba a Firebase y **lo borra al terminar**, así
que no ensucia la tabla real.

## Build web

Está en `build/web/` (compilada sin hilos, para que funcione en cualquier
hosting). Para levantarla:

```bash
cd build/web
docker compose up -d --build     # http://localhost:8080
```

Ver `build/web/LEEME.txt` para los tipos MIME que necesita el servidor y el resto
de detalles. Para recompilarla desde el código:

```bash
godot --headless --path . --export-release "Web" build/web/index.html
```

## Puntajes en línea

Firebase Realtime Database, configurada en `scripts/game_data.gd`
(constante `BASE_URL`). La tabla se lee completa y se ordena en el cliente porque
la base no tiene `.indexOn` para `points`; si algún día lo agregas, puedes pasar a
una consulta ordenada del servidor.

El juego funciona sin conexión: si la nube no responde, muestra la última tabla
conocida y avisa al guardar.

## Contadores de jugadores

`scripts/analytics.gd` (autoload `Analytics`) mantiene dos números que el menú y
la pantalla final muestran:

| Contador | Nodo | Cómo se mantiene |
|---|---|---|
| En línea ahora | `presence/` | Cada sesión escribe su entrada y arma un borrado en el servidor (`onDisconnect`); un latido cada 45 s la refresca y las entradas de más de 150 s no se cuentan |
| Jugadores en total | `stats/players` | Se suma uno al empezar cada partida |

El incremento atómico que documenta Firebase **no funciona en esta base**: se
comprobó escribiendo `10` y luego `2` en un nodo nuevo, y quedó `2`. Por eso la
suma se hace leyendo y escribiendo el valor siguiente, con el riesgo de perder
una cuenta si dos partidas empiezan en el mismo instante. El único lugar a
cambiar si la base llegara a soportarlo es `_count_player()` en
`scripts/analytics.gd`.

Prueba relacionada: `tools/counters_test.tscn` verifica que ambos contadores
llegan a la interfaz del menú y del fin de partida.

