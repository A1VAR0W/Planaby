# Hora de inicio y hora de fin

Los eventos se crean y se editan con **fecha, hora de inicio y hora de fin**. La duración ya no
se escribe: se calcula y se enseña debajo («Duración 2 h 30 min»).

## Dónde

- **Nuevo evento y editar evento** (pestaña Plan; es el mismo formulario en vertical y en
  horizontal): Fecha, Inicio y Fin
  con los selectores nativos, y «Termina otro día» para eventos de noche o de varios días.
  «Otros días» crea copias con el mismo inicio y fin.
- **Revisión de la propuesta:** el editor de un evento y el de un bloque de trabajo usan los
  mismos campos. «Listo» aplica el cambio solo si las horas valen.
- **Agenda del día y de la semana:** cada fila dice «09:00–11:30» o, si acaba otro día,
  «hasta jue 26 01:00».
- **Tareas:** siguen teniendo un tiempo estimado (es trabajo que se reparte, no una cita). Sus
  bloques se ven con inicio y fin, y se les puede pedir una franja fija («el viernes de 9:00 a
  11:00»).

## Reglas (`Shared/Planning/EventSchedule.swift`)

- El fin tiene que ser posterior al inicio. Si no, se dice debajo del campo y no se puede guardar.
- La medianoche solo se cruza si se pide: «Termina otro día», el botón «Termina al día
  siguiente» o «del día siguiente» / «de madrugada» en el chat.
- **Cambiar el día** conserva las horas de reloj y los días que dura (22:00–01:00 sigue
  terminando al día siguiente).
- **Cambiar el inicio** en el formulario deja el fin donde estaba mientras siga siendo
  posterior. Si no, el fin se mueve con él y se conserva la duración.
- **Cambiar el fin** nunca toca el inicio.
- Todo se calcula con el calendario y la zona horaria del iPhone, con horas de reloj. En un
  cambio de hora, un evento de 1:00 a 4:00 sigue siendo de 1:00 a 4:00, aunque ese día dure
  dos horas reales. Una hora que no existe (2:30 el día que se adelanta el reloj) pasa a la
  siguiente que sí.
- Máximo 14 días por evento.
- **Coincidencias:** debajo de las horas aparece «Coincide con «Comité» · jueves 10:00–11:00»,
  con las citas guardadas, las de otros calendarios y el resto de la propuesta. Avisa, pero no
  impide guardar. La propuesta también lo dice en sus avisos.

## Con la IA

| Lo que escribes | Lo que pasa |
|---|---|
| «Añade una reunión mañana de 10:00 a 12:00» | Un evento de 10:00 a 12:00 |
| «Cambia la hora de fin de Subida PRE a las 14:30» | Solo cambia el fin |
| «Adelanta el comienzo media hora, pero conserva la hora de fin» | Empieza 30 min antes y termina igual |
| «Haz que Subida PRO termine a las 17:00» | Solo cambia el fin |
| «Mueve la reunión a las 10» | Se mueve entera, con la misma duración |
| «Mueve esta tarea al viernes de 9:00 a 11:00» | La tarea se trabaja el viernes de 9:00 a 11:00; si no cabe entera, lo dice |
| «Añade Subida PRE el 25 de noviembre y Subida PRO el 26» | Los dos eventos y la pregunta «¿A qué hora quieres que comiencen y terminen…?» |

- Lo que entiende el modelo se comprueba con lo escrito (`TimeGrounding`). Una franja, «adelanta
  el comienzo» o «que termine a las…» escritos mandan sobre lo que haya devuelto la IA.
- Si solo das una duración, Planaby pregunta a qué hora empieza y calcula el fin.
- Una hora de fin que queda antes del inicio no se aplica. La respuesta lo dice y pregunta si
  termina al día siguiente.
- Cada cambio solo toca el elemento nombrado. Los demás eventos no se mueven.

## Compatibilidad

No hay migración. `CalendarEvent` ya guardaba `start` y `end`, así que los eventos existentes
conservan sus horas. Los campos nuevos de propuestas y cambios (`workFrom`, `workTo`,
`startDeltaMinutes`, `keepEnd`, `endsNextDay`) son opcionales, y las propuestas guardadas por
versiones anteriores se siguen abriendo.

## Pruebas en el iPhone 18 Pro

Nada de esto se ha comprobado todavía en el dispositivo.

1. En Plan, crea un evento: elige 25 nov, inicio 9:00 y fin 11:30. Debe poner «Duración 2 h 30 min».
   Guarda y comprueba la agenda.
2. Cambia el fin a 8:00: aparece el aviso y «Guardar» se desactiva. Pulsa «Termina al día
   siguiente»: vuelve a valer.
3. Crea otro evento que se solape con el anterior: aparece «Coincide con…».
4. Cambia la fecha de un evento de 22:00 a 01:00: sigue terminando al día siguiente.
5. En el chat, prueba las frases de la tabla y revisa cada propuesta antes de aceptar.
6. En horizontal, crea un evento desde Plan y repite el paso 1.
7. Abre una propuesta guardada antes de esta versión: debe abrirse igual que antes.
