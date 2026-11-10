# Planificación con IA en el iPhone

Cómo entiende Planaby lo que le pides en el chat (con la IA local o con Apple Intelligence), qué
comprueba antes de enseñarte una propuesta y qué hay que probar en el iPhone. Las propuestas editables (versiones, deshacer, revisión) se
explican en [PROPUESTAS.md](PROPUESTAS.md).

## IA local en el iPhone (Qwen3.5)

El modelo de Apple Intelligence es pequeño (unos 3.000 millones de parámetros y poco contexto): con
peticiones largas, varias cosas a la vez o mucho guardado, entiende mal o se deja cosas. Por eso
Planaby puede usar además un modelo abierto más capaz que corre **en el propio iPhone**:

- **Qwen3.5 4B** (recomendado, 3,1 GB) o **Qwen3.5 2B** (1,8 GB, más ligero), de Alibaba, con
  licencia Apache 2.0, en la versión cuantizada a 4 bits de `mlx-community` en Hugging Face.
- Corre con **MLX**, la librería de Apple para la GPU (paquete `mlx-swift-lm`). No hay servidores,
  cuentas ni claves: se descarga una vez y después funciona sin conexión. Nada de lo que escribes
  sale del iPhone.
- Se activa en **Ajustes › Plan › IA de planificación**: elegir el modelo, «Descargar» (con
  progreso; si se corta, sigue donde iba), el interruptor «Usar la IA local» y «Borrar». Los
  archivos van a Application Support/Modelos y no entran en las copias de iCloud.

Cómo se usa:

1. Con la IA local activada, cada petición va en **una sola llamada** con todo el contexto (la
   propuesta, hasta 40 elementos guardados relevantes, la conversación reciente y el material) y
   con ejemplos resueltos (`LocalPlanningPrompt`). Contesta en JSON y `PlanReading.parse` lo lee
   con tolerancia (texto alrededor, comillas de código, números entre comillas, comas sobrantes).
2. Si no se puede leer, se pide otra vez solo el JSON. Si faltan elementos de los que se pidieron,
   se le repite la petición diciéndole cuáles faltan.
3. Lo que devuelve pasa por **las mismas comprobaciones** que lo de Apple (`convert`): nombres y
   fechas exactos de la petición, nada inventado, preguntas por lo que falta y nada se guarda sin
   confirmar.
4. Si el modelo local falla, se usa Apple Intelligence (si está) y se avisa en la respuesta. Sin
   ninguno de los dos, quedan las plantillas.

Memoria y batería: el modelo ocupa varios GB de RAM mientras está cargado, pero solo gasta
cuando piensa. Por eso:

- **No se carga al abrir el chat**, sino al escribir el primer carácter (en el chat o en
  Reorganizar), al adjuntar algo o al empezar a dictar. Mientras terminas la petición se va
  cargando, y al enviar ya está listo. Si envías antes de que termine, la petición espera a esa
  misma carga (nunca se carga dos veces).
- **Se suelta** tras 3 minutos sin usarlo, al empezar una sesión de concentración, al pasar
  Planaby a segundo plano o si iOS avisa de poca memoria. Al cerrar el chat no se suelta en el
  acto: si vuelves al rato, sigue listo.
- Si Planaby se cierra mientras carga o piensa (casi siempre por falta de memoria), al volver a
  abrirla la IA local queda desactivada y Ajustes lo explica, sugiriendo el 2B.

«Estimar con IA» sigue usando Apple Intelligence.

Animación: mientras la IA trabaja se ve el atardecer del icono (`SunsetLoader`, con las cuentas en
`SunsetMotion`). Cargando, el sol amanece y se pone; pensando, respira, el reflejo ondula como el
agua y un destello recorre el horizonte; en la descarga, el sol sube con el progreso. Va a 30
fotogramas por segundo y, con «Reducir movimiento», se queda quieta como el icono.

## Repaso de lo que devuelve la IA

Los modelos pequeños se equivocan siempre de las mismas maneras. Con «Planifica en normal para el
día 28 de noviembre "Actuación Natalia", ponle que empieza a las 18 pero tenemos que estar antes,
acabará como a las 20» devolvieron dos eventos y dos tareas con el mismo nombre, de 16:00 a 22:00
y en el plan de Trabajo; y al corregir («solo quiero un único evento, de 17:45 a 20:00, nada
más») crearon dos eventos más, una tarea «Entregar informe» copiada de los ejemplos y un cambio
sobre «P1», un código que no existía.

Por eso todo lo que devuelve la IA (la local o la de Apple) pasa primero por
`PlanReadingCheck.clean`, que son reglas fijas y se prueban sin el modelo:

1. **Una cosa pedida es un solo elemento.** Se quitan los repetidos y la tarea que se llama igual
   que un evento. Varios siguen siendo varios si la petición lo dice: «dos reuniones», «una el
   lunes y otra el martes», «el lunes y el miércoles».
2. **Nada copiado de los ejemplos.** Un título que la persona no ha nombrado y que sale de los
   ejemplos del modelo se descarta.
3. **Solo códigos que existen.** Un cambio sobre un código que no está en la propuesta ni en lo
   guardado se descarta, y nunca se enseña un código en un mensaje. Si un cambio no se encuentra,
   se hacen los demás y se dice cuál no.
4. **Lo que ya está en la propuesta no se crea otra vez:** se convierte en un cambio de eso, solo
   con el día y las horas que diga la petición. «Otra reunión» sí crea una nueva.
5. **«Solo quiero un único evento»** deja uno (el que se cambia, el que se nombra o, si todos se
   llaman igual, el primero) y quita los demás que creó la propuesta; con «nada más», también
   las tareas. Lo guardado no se toca.
6. **«Pon primero»** solo si la petición habla de orden o de prisa, y solo para tareas.

Y con un solo evento nuevo, lo escrito manda sobre lo que diga la IA (`EventGrounding`):

- **Las horas:** una franja («de 17:45 a 20:00»), «empieza a las 18» y «acabará como a las 20»
  son esas horas exactas. Si la IA da un inicio que nadie escribió, vale la hora escrita.
- **El día,** si la petición nombra uno solo, esté donde esté en la frase.
- **El plan:** «planifica en normal», «en el plan de trabajo». No se pregunta «¿Trabajo o
  Normal?» si ya se ha dicho.

Las instrucciones de los dos modelos dicen lo mismo con ejemplos (un evento con inicio y fin
dichos de palabra, y una corrección con «solo quiero un único evento»), pero la garantía es el
repaso, no el modelo.

## Qué fallaba con Apple Intelligence

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

1. **Intención.** Un primer paso muy corto (`ParsedIntent`) dice qué pide: crear, cambiar,
   condiciones, reorganizar o nada de planificar (`offTopic`). Las palabras de la petición se
   suman por si al modelo se le escapa algo (`RequestIntent.hints`). Si este paso falla, bastan
   las palabras. Fuera de tema, contesta que está especializado en planificación y no toca nada.
2. **Extracción, por partes.** Cada parte va en una sesión nueva, con su formato pequeño y solo
   el contexto que necesita (ver «Por qué por pasos»):
   - crear (`ParsedCreation`): la fecha, el material (hasta 1.500 caracteres) y la petición.
     Devuelve un elemento por cosa pedida, aunque le falten datos. Lo que no se dice va vacío,
     nunca inventado;
   - cambiar (`ParsedChanges`): la propuesta (hasta 1.600 caracteres) y solo lo guardado que
     nombra la petición, más lo más próximo (12 líneas como mucho). En cada cambio solo se
     escriben los campos que cambian;
   - condiciones (`ParsedConditions`): solo la fecha y la petición. Si solo falla esta parte, lo
     demás sigue y la respuesta dice qué no entendió.
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

## Por qué por pasos

El modelo de Apple Intelligence del iPhone es pequeño (unos 3.000 millones de parámetros). En
unos 4.000 tokens tienen que caber las instrucciones, el formato de respuesta, el contexto y la
propia respuesta. Antes todo iba en una sola petición: unas 25 reglas, un formato con unos 45
campos (19 por cada cambio, que el modelo rellenaba siempre), 33 líneas del calendario, la
propuesta, la conversación y hasta 3.000 caracteres de adjuntos. A menudo no cabía, la respuesta
salía cortada y no se podía leer: era el «La IA no ha dado una respuesta válida».

Ahora:

- cada paso tiene instrucciones cortas y un formato pequeño;
- los campos de un cambio son opcionales, así que la respuesta solo lleva lo que cambia;
- el calendario se recorta a lo que nombra la petición, y la propuesta y la conversación tienen
  un límite (`ContextBudget`);
- si una respuesta no cabe o sale mal formada, se repite una vez con el contexto aún más
  recortado. Si la IA está ocupada, se espera un segundo y medio y se vuelve a intentar;
- cada error dice su causa: demasiado texto, respuesta mal formada, bloqueo de seguridad, IA
  ocupada, modelo descargándose o idioma no admitido. El detalle técnico queda en el registro
  del sistema (subsistema `com.alvaro.Planaby`, categoría `IA`), que se ve con la app Consola
  de un Mac.

Una petición tarda algo más, porque son dos o tres pasos seguidos. A cambio falla mucho menos.

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
- Con Apple Intelligence, la calidad depende de su modelo en el dispositivo. El código vigila que no falte ni
  sobre nada, pero puede tener que preguntarte más a menudo.

## Tests

`Tests/PlanRequestTests.swift` simula lo que devolvería la IA y comprueba qué hace Planaby con
ello:

- el caso PRE/PRO: dos eventos, nombres exactos, 25 y 26 de noviembre, fuera la «Comida», y la
  pregunta del inicio y el fin con sus opciones;
- `Tests/RequestIntentTests.swift`: qué pide cada petición sin el modelo, y los recortes de
  contexto;
- `Tests/PlanReadingTests.swift`: el JSON del modelo local (los ejemplos que se le enseñan se
  leen bien, solo cambia lo que viene, valores fuera de rango, texto alrededor y respuestas que
  no son JSON);
- `Tests/PlanReadingCheckTests.swift`: el caso «Actuación Natalia» tal como falló en el iPhone
  (un solo evento de una cosa pedida, las horas y el plan escritos, la corrección que deja uno y
  quita el resto, los códigos que no existen, los títulos copiados de los ejemplos) y que lo que
  sí son varias cosas siga siéndolo;
- `Tests/OverlapNoticeTests.swift`: dos cosas a la vez (qué se avisa y cómo, cada pareja una
  vez, bordes que se tocan, lo que se repite, el texto de la alerta y la marca de la agenda);
- `Tests/SunsetMotionTests.swift`: la animación del atardecer (el sol no se sale de su sitio, la
  descarga lo hace subir, el reflejo y el destello, y la imagen quieta igual que el icono);
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
11. Con 20 o más citas guardadas y una propuesta abierta, escribe «Mueve la Subida PRO al jueves
    y añade una llamada el lunes»: los dos cambios en la misma respuesta, sin «respuesta no
    válida».
12. Adjunta un documento largo y pide «Organiza esto»: debe salir la propuesta o, si no cabe, un
    aviso que diga la causa.
13. Si aparece algún error, anota el mensaje exacto: ahora cada causa tiene el suyo.

Con la IA local (nada de esto está comprobado todavía en un iPhone):

14. Ajustes › Plan › IA de planificación › «Descargar Qwen3.5 4B» con Wi-Fi y Planaby abierta: la
    barra avanza hasta el final y el interruptor se activa solo. Corta la red a mitad y vuelve a
    pulsar: sigue donde iba.
15. Repite las pruebas 1 a 6 y 11 con la IA local. Anota cuánto tarda la primera petición (carga
    el modelo) y las siguientes.
16. Una petición larga con varias cosas a la vez («Añade dos eventos…, mueve…, y nada después de
    las 17:00»): debe salir todo en la misma propuesta.
17. Si Planaby se cierra al pensar: vuelve a abrirla. En Ajustes debe salir el aviso y la IA local
    desactivada. Prueba entonces el 2B.
18. Activa el modo avión: la IA local debe seguir funcionando.
19. Pasa Planaby a segundo plano y vuelve: la siguiente petición vuelve a cargar el modelo y
    funciona.
20. Abre el chat sin escribir: no debe aparecer «Preparando la IA local». Escribe una letra:
    aparece el atardecer pequeño sobre el campo y, al terminar de cargar, se va. Envía: la
    respuesta llega sin la espera de la carga.
21. Envía nada más empezar a escribir: el atardecer del chat dice «Preparando la IA local…» y
    luego «Organizando…», sin cargar dos veces.
22. Deja el chat 3 minutos sin usarlo y mira Ajustes › Plan › IA de planificación: ya no dice
    «Ahora está cargado». Lo mismo al empezar una sesión de concentración.
23. Dicta por voz: el atardecer grande sale mientras organiza (también en el modo escritorio, con
    su color de noche). Con «Reducir movimiento», queda quieto como el icono.
24. Descarga el 2B: el sol sube a medida que avanza la descarga.

El caso que falló (con la IA local y con la de Apple):

25. «Planifica en normal para el día 28 de noviembre "Actuación Natalia", ponle que empieza a las
    18 pero tenemos que estar antes, acabará como a las 20»: un solo evento, el 28 de noviembre,
    de 18:00 a 20:00, en el plan Normal, sin tareas y sin preguntar «¿Trabajo o Normal?».
26. Después, «Solo quiero un único evento, de 17:45 a 20:00, nada más»: la propuesta se queda con
    un evento de 17:45 a 20:00 y sin avisos de «coincide con».
27. Con esa propuesta abierta, «Añade otra actuación el domingo a las 12»: aparece un segundo
    evento (aquí sí se pide otro).
28. Si en algún momento sale un título que no has dicho o un código (E1, P1) en un mensaje,
    anota la petición exacta.
29. Con un evento guardado el sábado de 19:00 a 21:00, pide «Pon ensayo el sábado de 18 a 20»:
    la IA deja 18:00–20:00 (no lo mueve), la propuesta avisa de que coincide y «Aceptar
    propuesta» enseña «Ya tienes algo a esa hora». «Aceptar igualmente» guarda los dos.
