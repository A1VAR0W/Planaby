# Modo horizontal, avisos y Live Activity

Guía de las mejoras del modo escritorio (iPhone en horizontal), de los avisos de fase con música,
de la navegación durante una sesión y del nuevo diseño de la Dynamic Island y la Live Activity.

## Volumen vertical

- En la barra del escritorio, en el borde derecho, hay un botón circular de cristal oscuro con un
  borde fino y el altavoz. Un arco naranja alrededor enseña el nivel (gris si no hay sonido) y el
  icono cambia: silenciado, bajo, medio o alto.
- Al tocarlo, el botón se hunde un poco, el icono hace un pequeño salto y una cápsula vertical
  (60 × 216 pt) nace del botón y crece hacia arriba. Lleva:
  - el porcentaje arriba, discreto (o «Sin sonido»), que aparece un instante después;
  - la pista gruesa con el relleno naranja desde abajo y un tirador blanco (en gris si está silenciado);
  - el altavoz abajo.
- Se cierra de tres maneras: otro toque en el botón, tocar fuera, o abrir la captura rápida.
  - La animación es la misma al revés, más rápida.
  - Con «Reducir movimiento» solo hay un fundido.
  - Mientras está abierta, la barra no se esconde.
- Iconos, textos y umbral de silencio están en `VolumeLevel` (con tests); iOS no ofrece un
  «silenciar» público, así que silenciado es volumen por debajo del 1 %.
- **Es el volumen real del iPhone**, el de los botones laterales. Se usa `MPVolumeView`, el control
  público de Apple, girado −90° con una transformación de UIKit.
  - Su pista se centra con `volumeSliderRect(forBounds:)`, un método público pensado para subclases.
  - No hay ningún slider de mentira ni API privadas.
  - El icono lee `AVAudioSession.outputVolume` por KVO y nunca escribe en él.
- **Spotify:** su SDK (App Remote) no ofrece cambiar el volumen. Por eso se controla el volumen de
  salida del sistema, que es el que oyes en el altavoz, los auriculares o AirPlay.
  - Si Spotify suena en otro dispositivo con Spotify Connect, el volumen de ese aparato se cambia
    desde Spotify.
- En vertical, «Ahora suena» conserva la barra horizontal clásica.
- En el simulador `MPVolumeView` no se ve. Hay que probarlo en el iPhone.

## Música y tareas a la vez

- Con las dos activadas, el escritorio se reparte en dos mitades iguales: música a la izquierda y
  tareas a la derecha. El reparto lo calcula `DeskPanels.halfWidth`, que tiene tests.
- **Mitad de música:** la fase y la cifra grandes arriba (el temporizador sigue mandando), la
  carátula, la canción, el artista, el progreso y los controles.
- **Mitad de tareas:**
  - la tarea de la sesión arriba, marcada como «Ahora · en esta sesión»;
  - las pendientes y las hechas hoy, con desplazamiento vertical;
  - el círculo para completarlas y el «+» para añadir.
- Si solo hay una de las dos, ocupa el sitio libre. Sin música, la lista es una columna de 320 pt
  que nunca pasa de la mitad. Los anchos los calcula `DeskPanels.widths` (con tests).
- Cambiar de disposición nunca reinicia el reproductor ni la sesión: la composición es siempre la
  misma (panel principal + lista) y solo cambian los anchos. La lista sigue montada aunque esté
  cerrada, así que al volver conserva su desplazamiento.
- **Animación:** al abrir, el panel se abre con un muelle suave y su contenido entra escalonado
  (cabecera, «Por organizar» y filas); la carátula y los controles se recolocan sin cortes. Al
  cerrar, todo se va a la vez y más rápido. Con «Reducir movimiento», solo un fundido corto.

## Sistema de movimiento

Las animaciones de toda la app salen de los mismos tokens: `MotionTiming` (tiempos, con tests) y
`Motion` (curvas, transiciones y el estilo de botón `.pressable`).

- Pulsación 0,16 s · rápida 0,22 s · normal 0,32 s · destacada 0,42 s · panel 0,5 s.
- Las salidas duran el 60 % de la entrada. El escalonado avanza 0,04 s por elemento, como mucho 8.
- Con «Reducir movimiento», cualquier animación pasa a un fundido de 0,18 s.
- Los widgets y la Live Activity no tienen animaciones continuas.

## Añadir tareas en horizontal

- El «+» de la lista, o el lápiz de la barra, abre una tarjeta ancha arriba. Así el teclado ocupa
  la mitad de abajo sin tapar nada.
- La tarjeta tiene el campo «¿Qué necesitas recordar?» (con el cursor ya dentro), el micrófono,
  Cancelar y Guardar.
- **Detalles es opcional.** Abre una sola fila con plan, prioridad, fecha, duración y notas.
  - **Sin detalles:** la tarea va a «Por organizar», como siempre.
  - **Con detalles:** se crea directamente la tarea y aparece al momento en la lista.
    - Vence a las 20:00 del día elegido.
    - Si ese día es hoy y ya han pasado las 20:00, vence a las 23:59.
- Al guardar aparece «Tarea apuntada» abajo y la tarjeta se cierra.
- Tocar fuera cierra sin borrar lo escrito.
- El temporizador, la fase y la música no se tocan.

## Avisos de fase con música

- **Sonido con Planaby delante:**
  - La sesión de audio es `.ambient`, que **respeta el modo silencio**: es una regla de iOS y no se
    salta.
  - Si suena música de otra app, se añade la opción `.duckOthers`: iOS baja esa música mientras
    suena el aviso.
  - Al acabar, Planaby desactiva su sesión con `notifyOthersOnDeactivation`, y la música vuelve
    sola a su volumen.
  - Nunca se pausa la música ni se cambia el volumen del iPhone.
  - Si llega un segundo aviso mientras la música sigue baja, ese aviso se encarga de devolverla.
- **Ajustes › Avisos de concentración › Con Planaby abierta:**
  - «Sonar aunque haya música» está activado por defecto.
  - «Bajar la música mientras suena» está activado por defecto.
- **Nunca suena dos veces.** Con la app delante, la notificación del sistema llega sin sonido, y
  un cambio de fase de hace más de 5 s no vuelve a avisar.
- **Tarjeta:** el texto es, por ejemplo, «¡Sesión completada! Has trabajado durante 25 minutos.
  Comienza tu descanso de 5 minutos.».
  - En el escritorio va arriba a la izquierda, encima del panel de música. No lo reconstruye y deja
    libre la lista de tareas.
  - Tiene borde del color de la fase y se va sola a los 8 s.
  - Si la captura rápida está abierta, la tarjeta espera a que se cierre. El sonido sí suena en el
    momento.
- **Con la app cerrada o el iPhone bloqueado** avisa la notificación programada, con el sonido
  elegido.
  - iOS decide cómo convive con la música: no se puede pedir que la baje.
  - El modo silencio, la Concentración de iOS y los permisos de notificación mandan.
  - «Si no suena», en Ajustes, distingue entre permiso denegado, opción de Planaby e iOS.

## Plan, Progreso y Ajustes durante la sesión

- El botón de cuadrícula abre un menú con Plan, Progreso y Ajustes. Está en Enfoque mientras corre
  la sesión, y en la barra del escritorio.
- Solo cambia de pestaña:
  - el temporizador, la Live Activity y la Dynamic Island siguen igual;
  - no hay un segundo motor de tiempo.
- Para volver, la pestaña Enfoque. En horizontal, vuelve al escritorio.

## Dynamic Island y Live Activity: nuevo diseño

La isla y la pantalla bloqueada son dos tamaños del mismo diseño que el escritorio:

- fondo negro;
- la fase como etiqueta pequeña en el color de la fase, con su símbolo;
- la cifra fina y grande;
- la tarea debajo;
- una línea de progreso;
- los mismos botones redondos: terminar, pausa destacada en color y saltar.

| Superficie | Qué enseña |
|---|---|
| Isla compacta | Anillo de progreso en el color de la fase · cifra en ese color |
| Isla mínima | El anillo |
| Isla expandida | ☀ PLANABY · «hasta 18:42»<br>Fase y cifra con los tres botones<br>Tarea<br>Línea de progreso y «Luego: Descanso» |
| Pantalla bloqueada | Fase, cifra grande y tarea, con los botones a la derecha<br>Línea de progreso<br>«Luego: …», recuento de comunicaciones y «hasta 18:42»<br>Halo quieto del color de la fase |

| Estado | Cómo se ve |
|---|---|
| Concentración | Naranja, con la tarea (o el método) |
| Descanso | Color del descanso, halo más vivo y «Levántate, respira y mira lejos» |
| En pausa | «EN PAUSA · 40 %», cifra atenuada y botón de reanudar |
| Fase completada (sin la app delante) | «FASE COMPLETADA», 00:00 y «Continuar» |
| Sesión terminada | «SESIÓN TERMINADA», «Hecho» y «Abrir»<br>Se ve 5 minutos; empezar otra sesión la quita al momento, así nunca hay dos |

- La cifra y el progreso avanzan solos con los contadores del sistema (`Text(timerInterval:)` y
  `ProgressView(timerInterval:)`). No hay actualizaciones cada segundo.
- El porcentaje solo aparece en pausa, porque un texto de porcentaje no puede avanzar solo sin push.
- En la pantalla siempre activa, iOS atenúa todo y el halo desaparece.
- De las comunicaciones solo se enseña el recuento, nunca un mensaje.
- Los botones son los intents reales del motor de la app. Tocar la actividad abre el escritorio.

## Icono

- `App/Assets.xcassets/AppIcon.appiconset/icon.png` y `distribution/icon.png` son la imagen
  adjunta, idéntica byte a byte: 1024 × 1024, RGB y sin transparencia.
- `Contents.json` sigue con una sola entrada universal de 1024. El identificador de la app no
  cambia.
- El icono anterior está en `docs/icons/planaby-icon-anterior.png`.
- La fuente de SideStore recoge `distribution/icon.png` de la última release.

## Pruebas en el iPhone 18 Pro

1. **Escritorio y paneles**
   1. Gira el iPhone en Enfoque con una sesión en marcha y Spotify sonando.
   2. Activa música y tareas: deben verse dos mitades iguales sin nada cortado.
   3. Abre y cierra las tareas varias veces: la canción no se corta ni vuelve a empezar, y la
      lista conserva dónde estabas. Con «Reducir movimiento» activado, solo hay fundidos.
2. **Volumen**
   1. Toca el altavoz: la cápsula sube desde el botón y el arco naranja coincide con el nivel.
   2. Arrastra: el volumen del iPhone cambia (mira el indicador del sistema).
   3. Usa los botones laterales: la cápsula y el arco se mueven solos.
   4. Baja hasta el final: el icono pasa a silenciado y el texto, a «Sin sonido».
   5. Toca fuera o vuelve a tocar el botón: se cierra.
3. **Captura en horizontal**
   1. Toca «+» y escribe con el teclado abierto: Guardar sigue a la vista.
   2. Abre Detalles, elige Trabajo, Alta, mañana y 45 min, y guarda.
   3. La tarea aparece en la lista y el temporizador no ha cambiado.
4. **Aviso con música**
   1. Pon una fase de 1 minuto con Spotify al 60 %.
   2. Al terminar, la música baja, suena el aviso y vuelve a su volumen.
   3. La tarjeta sale encima de la música y se va sola.
   4. Comprueba que no hay dos sonidos.
   5. Repite con el modo silencio: no debe sonar, solo vibrar.
5. **Navegación**
   1. Durante la sesión, abre la cuadrícula › Plan, luego Progreso, luego Ajustes.
   2. Vuelve a Enfoque: el tiempo sigue y la Live Activity no se ha reiniciado.
6. **Live Activity**
   1. Bloquea el iPhone: comprueba concentración, pausa (desde el botón), descanso y fase
      completada (deja acabar una fase con la app cerrada y toca «Continuar»).
   2. Termina la sesión: «Sesión terminada» se ve unos minutos.
   3. Empieza otra: solo hay una actividad.
7. **Dynamic Island**
   1. Compacta: anillo y cifra sin cortes.
   2. Mantén pulsada para expandirla y usa pausa y saltar.
   3. Revisa StandBy y la pantalla siempre activa.
8. **Icono:** el sol naranja en la pantalla de inicio, tras instalar desde SideStore.
