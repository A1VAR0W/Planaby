# Captura rápida

«Apúntalo ahora. Organízalo después. Sigue concentrado.»

Sirve para apuntar algo que se te pasa por la cabeza en mitad de un bloque sin salir de la sesión.
Funciona en el iPhone, sin conexión, con la firma gratuita actual (los mismos 2 App IDs, sin
extensiones nuevas) y sin Apple Intelligence.

## Dónde está

- **Enfoque**: el botón naranja con el lápiz, arriba a la derecha. Se ve:
  - concentrándote (aunque la barra de pestañas esté oculta);
  - en el descanso y en pausa;
  - sin sesión.
- **Modo escritorio**: en la barra inferior, junto al método. Si la barra se ha ocultado, un toque
  en la pantalla la vuelve a enseñar.
- **Gestos**:
  - tocar abre el panel con el teclado;
  - mantener pulsado ofrece «Escribir» o «Dictar»;
  - con VoiceOver, «Captura rápida» tiene la acción «Dictar».
- **Siri**: «Captura una tarea en Planaby», «Apunta algo en Planaby».
- **Centro de Control, pantalla bloqueada y botón de Acción**: el control **Captura rápida**.
- **Widget Concentración mediano**: el botón del lápiz.

## Qué hace (y qué no)

- **El panel**:
  - Es una hoja baja en vertical, o un panel flotando a la derecha en el modo escritorio, con la
    cifra a la vista.
  - Lleva el campo «¿Qué necesitas recordar?», el micrófono y Guardar.
  - No pide fecha, duración ni plan.
- **Guardar**:
  - Lo guarda en la base de datos al momento y confirma con «✓ Apuntado "…"».
  - Si la base de datos falla, no dice «Guardado»: enseña el error y el texto se queda en el panel.
- **Dictado**:
  - Usa el mismo reconocimiento de voz de Planaby (`SpeechCapture`).
  - Lo dictado aparece en el campo para corregirlo antes de guardar.
  - El micrófono se apaga al terminar la frase, al cerrar el panel o al salir de la app.
  - La música (Spotify) sigue sonando, más baja mientras escucha, y el audio vuelve a como estaba.
  - Sin permiso de micrófono, avisa y deja escribir.
- **No toca la sesión**: no pausa, no salta de fase, no cambia la tarea ni el método. Tampoco
  cambia la Live Activity ni el historial.
- **No inventa nada**: una captura no tiene fecha límite ni bloques en el calendario hasta que la
  planificas y confirmas.

## Por organizar

- **Dónde**: en Plan, la sección «Por organizar · N», con lo apuntado en los dos planes; cada
  captura lleva el suyo.
- **Cada captura enseña**:
  - la hora;
  - el plan (Trabajo o Normal);
  - si se apuntó en una sesión o en un descanso;
  - cómo se apuntó (escrita, dictada o con Siri);
  - si está sin revisar o pospuesta.
- **Acciones**:
  - Planificar (tocarla);
  - Editar;
  - Cambiar de plan;
  - Marcar como hecha;
  - Posponer la revisión (1 hora o mañana a las 9:00);
  - Eliminar.
- **Planificar**:
  - Usa el flujo de siempre: Apple Intelligence (`PlanningAssistant`) si está disponible, y si no,
    una propuesta sencilla que dice claramente que la fecha es una sugerencia.
  - Siempre se revisa y se confirma.
  - Al aceptar, la captura queda enlazada a la tarea creada (mismo identificador) y sale de
    «Por organizar», así que nunca se convierte dos veces.

## Descansos y fin de sesión

- **Al empezar el descanso**, la tarjeta de cambio de fase añade «Has apuntado 3 tareas ·
  Organizarlas», junto a las comunicaciones pendientes, en la misma tarjeta.
- **Al cerrarse la tarjeta**, en el descanso aparece «Mientras te concentrabas… Has apuntado 3
  tareas [Organizarlas] [Después]».
- **Al terminar la sesión**, Enfoque enseña «Has apuntado 4 tareas durante tu sesión [Organizar
  ahora] [Más tarde]».
- **Nunca hay dos hojas ni dos tarjetas a la vez**. El orden es:
  1. el cambio de fase;
  2. «Bienvenido de nuevo»;
  3. «Mientras estabas fuera»;
  4. lo apuntado;
  5. las sugerencias.
- **Durante la concentración no se reorganiza nada**: la IA solo propone cuando tú abres
  «Organizar».

## Siri y atajos

- **«Capturar tarea en Planaby»** guarda sin abrir la app, sin cambiar de pestaña y sin abrir el
  chat del plan.
  - Siri pregunta «¿Qué quieres apuntar?»: iOS no deja meter texto libre en la frase de un atajo
    de app.
  - Es el décimo atajo de app, el máximo de iOS.
- **Con el iPhone bloqueado**:
  - Funciona si se ha desbloqueado al menos una vez desde que se encendió, porque la base de datos
    está protegida hasta entonces.
  - Solo guarda lo dicho y no enseña nada del plan.
- **El control «Captura rápida»** abre Planaby con el panel. Con el iPhone bloqueado, iOS pide Face
  ID o el código antes.

## Por qué no hay botón en la Live Activity ni en StandBy

- **Live Activity**: ya lleva la cifra, la fase, la tarea, las comunicaciones y los controles. Un
  botón más quitaría sitio a la cifra.
- **StandBy**: no admite campos de texto, y el widget en StandBy no lleva botones.
- **Desde la pantalla bloqueada o StandBy**: usa el control del Centro de Control o Siri.

## Datos y copias

- **El modelo**: `CapturedTask` (SwiftData), en `Shared/Models/CapturedTask.swift`.
  - Una entidad nueva, añadida al esquema con todos los campos con valor por defecto: migración
    ligera, sin borrar nada.
- **Campos**:
  - identificador estable;
  - texto, fecha, plan y estado (por organizar, en el plan, hecha);
  - cómo se apuntó;
  - inicio de la sesión y fase de origen;
  - revisada, convertida, tarea enlazada, pospuesta hasta, y resumen ya enseñado.
- **Copias de seguridad**:
  - Las copias incluyen las capturas (`captures`, opcional).
  - Al restaurar una copia anterior a esta función, no se borran las capturas actuales.
- **Lógica pura con tests**: `Shared/Engine/QuickCapture.swift` (`CaptureRules`).

## Pruebas

**Automáticas**: `Tests/QuickCaptureTests.swift` (27 pruebas), en el CI con el simulador.

- limpieza del texto: vacío, solo puntuación, espacios, mayúscula inicial, «iPhone» y texto largo;
- sesión y fase de origen, y que el estado del temporizador no cambia;
- por organizar y pospuestas, por sesión, el resumen sin repetir y sus textos;
- convertir una sola vez, también si era una cita;
- valores por defecto y valores desconocidos;
- copia de seguridad de ida y vuelta, y copias antiguas sin capturas;
- persistencia al cerrar y reabrir la base de datos;
- peticiones del control: una sola vez, caducadas y directas a la app.

**Solo en el iPhone** (no se pueden dar por comprobadas sin probarlas a mano):

- que el teclado sube y el panel cabe, en vertical y en horizontal;
- el dictado con Spotify sonando: debe bajar el volumen y no pararse;
- el permiso de micrófono denegado;
- Siri con el iPhone bloqueado y desbloqueado;
- el control del Centro de Control y el botón del widget;
- la tarjeta del descanso y el resumen al terminar;
- VoiceOver, «Reducir movimiento» y la vibración al guardar.

## Probar en un iPhone 18 Pro

1. **Captura durante la concentración**:
   - Empieza una sesión en Enfoque y toca el lápiz.
   - Escribe «Llamar a Marta» y pulsa Guardar.
   - Debe salir «✓ Apuntado "Llamar a Marta"», y la cifra, la fase y la Live Activity siguen igual.
2. **Dictado con música**:
   - Pon Spotify y mantén pulsado el lápiz › Dictar.
   - Di algo: la música baja sin pararse y vuelve al terminar.
   - Corrige el texto y guarda.
3. **Varias seguidas**: guarda tres seguidas. Cada confirmación sustituye a la anterior.
4. **Modo escritorio**:
   - Gira el iPhone, toca la pantalla y toca el lápiz.
   - El panel sale a la derecha con la cifra a la vista.
   - Con la lista de tareas abierta, aparece «N por organizar».
5. **Descanso**: deja que acabe el bloque. La tarjeta dice «Has apuntado N tareas», y al cerrarla
   queda la línea con «Organizarlas» y «Después».
6. **Fin de sesión**: termina la sesión. En Enfoque aparece «Has apuntado N tareas durante tu
   sesión».
7. **Organizar**:
   - En Plan › Por organizar, toca una captura y revisa la propuesta.
   - Pulsa Añadir: sale de la lista y aparece en Tareas.
8. **Persistencia**: apunta algo, cierra Planaby desde el selector de apps y ábrela. Sigue en «Por
   organizar».
9. **Siri**:
   - Di «Captura una tarea en Planaby», luego «comprar pilas».
   - Prueba también con el iPhone bloqueado (tras haberlo desbloqueado una vez).
10. **Control**:
    - Centro de Control › + › Planaby › Captura rápida.
    - Tócalo: se abre Planaby con el panel y la sesión no cambia.
11. **Copia**: Ajustes › Copias de seguridad › hacer una y restaurarla. Las capturas siguen ahí.
