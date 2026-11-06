# Planificación con Apple Intelligence

Cómo entiende Planaby lo que le pides en el chat, qué comprueba antes de enseñarte una propuesta
y qué hay que probar en el iPhone. Las propuestas editables (versiones, deshacer, revisión) se
explican en [PROPUESTAS.md](PROPUESTAS.md).

## Qué fallaba

Con «Añade dos eventos, uno Subida PRE para el 25 de noviembre y otro Subida PRO para el 26 de
noviembre» salía un solo evento y, además, una «Comida» que nadie había pedido. Las causas:

1. Las instrucciones pedían omitir un evento si le faltaban datos, y el modelo debía dar siempre la
   hora de inicio. Como la petición no decía la hora, «Subida PRE» se descartaba.
2. Una regla antigua animaba a añadir la comida, y la agenda iba en el mensaje sin decir que ya
   existía. El modelo la copiaba o se inventaba rutinas, y nada lo filtraba después.
3. No se comprobaba cuántos elementos se pedían, ni se reintentaba si faltaba alguno.
4. Solo se podía editar lo que estaba en la propuesta: lo ya guardado no se podía cambiar ni borrar.
5. El texto se borraba del campo antes de enviar. Si fallaba no había reintento, ni forma de cancelar.
6. La tarjeta no tenía «Descartar», y las preguntas no tenían respuestas rápidas.

## Cómo funciona ahora

Cada petición pasa por los mismos pasos. La IA solo interpreta; todo lo demás es código
determinista y tiene tests.

1. **Intención.** El modelo dice primero si la petición es de planificación (`offTopic`) y cuántas
   cosas nuevas pide (`requestedCount`). Fuera de tema, contesta que está especializado en
   planificación y no toca nada.
2. **Extracción.** Un elemento por cosa pedida, aunque le falten datos. Lo que no se dice va vacío,
   nunca inventado.
3. **Comprobación con la petición** (`PlanRequest.swift`):
   - `RequestCheck` cuenta lo anunciado («dos eventos», «3 tareas», «una… y otra…»). Si falta
     alguno, se pide al modelo una vez más diciéndoselo. Si sigue faltando, la respuesta lo dice
     («Pediste 2 y solo he podido preparar 1»): nunca se presenta como completo.
   - `RequestGrounding` descarta lo que nadie mencionó y es una rutina (comida, cena, descanso…) o
     una copia de algo que ya está en la agenda. El título se copia tal como lo escribiste
     («Subida PRE», no «Subida pre»).
   - `RequestDates` lee las fechas escritas («25 de noviembre», «el día 24», «mañana», «el jueves»),
     y esas mandan sobre lo que diga el modelo. Sin año, se toma la próxima que no haya pasado.
4. **Lo que falta.** El día, la hora de inicio o la de fin que no dijiste quedan como
   provisionales (`unconfirmed`), y Planaby pregunta solo eso, con respuestas rápidas. Los
   eventos tienen inicio y fin; la duración sale de ahí (ver [HORAS.md](HORAS.md)).
   - Sin ninguna de las dos horas: «He preparado los dos eventos. ¿A qué hora quieres que
     comiencen y terminen «Subida PRE» y «Subida PRO»?», con 9:00–10:00 · 10:00–12:00 ·
     16:00–17:00 · Horario diferente para cada evento.
   - Si solo das una duración («2 h»), después pregunta a qué hora empiezan y calcula el fin.
     Si ya se sabe el inicio, pregunta solo a qué hora terminan.
   - Las respuestas cortas («de 9:00 a 11:30», «1 h», «a las 10», «hasta las 12», «5 de la
     tarde») se entienden sin la IA (`AnswerParsing`). «Diferente para cada evento» pregunta de
     uno en uno. Mientras pregunta no se pierde ningún elemento.
5. **Referencias.**
   - Lo que hay en la propuesta tiene los códigos E1, E2… (eventos) y T1, T2… (tareas).
   - Lo guardado tiene C1… (citas de los próximos 21 días) y P1… (tareas pendientes).
   - Los eventos de otros calendarios se enseñan sin código, como solo lectura.
   - `SavedResolver` busca primero por código, luego por nombre, y desempata por el día dicho.
   - Si dos cosas siguen empatadas, o el día no coincide, pregunta «¿Cuál?» con opciones. Nunca
     elige al azar.
   - «El duplicado» es el último de los que se llaman igual.
6. **Validación y conflictos.** Lo guardado que vas a cambiar o borrar entra en la propuesta sin
   cambios. Después se le aplican las mismas operaciones deterministas que a lo nuevo
   (`ProposalEditor`).
   - Un evento que se repite solo se toca si pides la serie entera («todas», «siempre»).
   - Los de otros calendarios nunca se tocan.
   - Las tareas se recolocan con `WorkloadPlanner`, respetando citas, franjas libres y fechas límite.
   - «Pásala al viernes» pone sus bloques solo ese día. Si su entrega era antes, la entrega pasa
     a ese día y la respuesta te lo dice.
7. **Propuesta.** La tarjeta enseña lo que de verdad hay:
   - cifras: nuevos, cambios, bloques, lo que se borrará y lo pendiente de confirmar;
   - los avisos y la lista de cambios («Se borrará: …», «Se conserva: …»);
   - los botones Revisar, Modificar con IA, Aceptar y Descartar.
8. **Confirmación.** Nada se escribe hasta pulsar «Aceptar propuesta». Descartar pide confirmación.
   En la revisión, lo que se va a borrar tiene su propia sección, «Se borrará al aceptar», con
   «Conservar» en cada elemento.
9. **Guardado** (`PlanBuilder.accept`). Un evento guardado que se cambia se modifica en su sitio,
   sin crear otro. Lo borrado se elimina con sus adjuntos y bloques. Si algo ya no existe, se
   salta sin romper nada.

## Contexto de la conversación

- Hay una sola propuesta activa, con versiones. Cada mensaje la modifica y solo cambia lo pedido:
  con «cambia la Subida PRE al día 24 y deja la Subida PRO el 26», la PRO no se toca.
- Los identificadores son estables, así que nada se duplica: el código E1 sigue siendo el mismo
  elemento aunque cambie de nombre o de día.
- Cada petición abre una sesión nueva del modelo, con la propuesta, lo guardado y los últimos
  cuatro mensajes. Así una conversación larga no llena la memoria del modelo del iPhone.
- La propuesta y la pregunta pendiente se guardan en el iPhone. Al volver a abrir Planaby se
  recuperan, y se olvida lo que ya no existe en la base de datos.

## Errores

- Si la IA no está disponible, falla o devuelve algo no válido, la propuesta no cambia y no se
  guarda nada a medias. El texto vuelve al campo y aparece «Reintentar».
- «Cancelar» detiene la petición en curso: «Cancelado. Tu propuesta sigue igual.»
- Nunca se dice que algo está hecho si no lo está. Las acciones que Planaby no puede hacer
  (invitar, enviar mensajes) se dicen, no se simulan.

## Límites

- Los números sueltos se entienden como horas hasta 8 («2» son 2 horas) y como minutos a partir
  de ahí. Una hora de 1 a 7 sin «de la mañana» se entiende de la tarde.
- La IA ve como mucho 15 citas de los próximos 21 días, 10 tareas pendientes y 8 eventos de otros
  calendarios. Para algo más lejano, di su día o su nombre exacto.
- Un evento que se repite no se puede cambiar en una sola fecha: solo la serie entera.
- La calidad depende del modelo de Apple en el dispositivo. El código vigila que no falte ni
  sobre nada, pero puede tener que preguntarte más a menudo.

## Tests

`Tests/PlanRequestTests.swift` simula lo que devolvería la IA y comprueba qué hace Planaby con
ello:

- el caso PRE/PRO: dos eventos, nombres exactos, 25 y 26 de noviembre, fuera la «Comida», y la
  pregunta del inicio y el fin con sus opciones;
- `Tests/EventTimesTests.swift`: inicio y fin (solo el fin, solo el inicio, conservar el fin,
  varios días, medianoche, cambio de hora), franjas escritas, cambios de la IA, franjas de
  tareas y compatibilidad con lo guardado;
- las respuestas cortas;
- elegir el elemento guardado correcto (día, código, duplicado, ambigüedad);
- borrar frente a quitar de la propuesta;
- el cambio parcial;
- editar un evento guardado sin duplicarlo;
- el día de trabajo de una tarea y las franjas libres;
- abrir propuestas guardadas por versiones anteriores;
- los tiempos de animación, el volumen y los anchos de los paneles.

## Pruebas en el iPhone 18 Pro

Con Apple Intelligence activado:

1. Escribe la petición de PRE/PRO. Deben salir los dos eventos con su fecha y una sola pregunta,
   a qué hora comienzan y terminan. Escribe «de 9:00 a 11:30»: los dos quedan de 9:00 a 11:30.
2. «Está bien, pero cambia la Subida PRE al día 24 y deja la Subida PRO el 26»: solo cambia la PRE.
3. Acepta. Después escribe «Borra la Subida PRO»: la tarjeta dice «1 elemento guardado se borrará».
   Revísala, pulsa «Conservar» y luego vuelve a pedirlo y acepta.
4. «Borra la tarea de revisar documentación del jueves», con dos tareas así en días distintos:
   debe elegir la del jueves.
5. «Mueve las tareas menos importantes al viernes y deja dos horas libres por la tarde»: sus
   bloques van al viernes y la franja queda libre.
6. «Añade una reunión el lunes y otra el martes y borra el duplicado de X»: lo nuevo y el borrado
   en la misma propuesta.
7. Pregunta algo que no sea de planificar: debe contestar que está especializado en planificación.
8. Activa el modo avión o desactiva Apple Intelligence a mitad de una petición: el texto vuelve al
   campo y aparece «Reintentar». Prueba también «Cancelar».
9. Cierra Planaby del todo con una propuesta a medias y vuelve a abrirla: sigue ahí, con su pregunta.
10. Intenta borrar un evento de Outlook o del Calendario de iOS: debe decir que es solo lectura.
