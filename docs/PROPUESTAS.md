# Propuestas editables con IA

Una propuesta del chat se puede corregir tantas veces como quieras antes de aceptarla. No se
duplica nada, no se pierde nada entre mensajes y nunca se empieza de cero. Nada se guarda en el
calendario hasta «Aceptar propuesta».

## Cómo funciona

- **Una sola propuesta activa.** Cada mensaje la modifica y la anterior queda como «Versión
  anterior (sustituida)», sin botones: no se puede aceptar.
- **Identificadores estables.** Cada cita y cada tarea tiene un `id` que no cambia aunque cambien
  el título, el día, la hora, la duración, el plan o la prioridad. La IA ve códigos cortos
  (`E1`, `T1`); los identificadores reales quedan dentro de Planaby.
- **La IA solo interpreta.** Devuelve qué quiere cambiar la persona (`ParsedEdit`,
  `ParsedCondition`). Cómo cambia la propuesta lo decide código determinista y probado
  (`Shared/Planning/ProposalEditing.swift`):
  - `ProposalEditor.resolve`: busca el elemento por código; si no, por título; si hay varios,
    pregunta «¿Cuál quieres mover?» y la propuesta no cambia.
  - `ProposalEditor.apply`: aplica todas las operaciones o ninguna.
  - Si la IA repite como nueva una cita que ya está (mismo título), se trata como un cambio de
    esa cita, salvo que digas «otra reunión».
- **Recalcular solo lo necesario** (`ProposalPlacement`, con el `WorkloadPlanner` de siempre):
  - se recolocan los bloques de las tareas cambiadas y los que ya no encajan (pisan una cita,
    se salen de una condición o pasan la fecha límite);
  - los demás bloques se quedan donde estaban, también los movidos a mano;
  - se respetan tu horario, tu energía, el tope diario, el calendario guardado y Outlook/Teams;
  - si no cabe, lo dice y no inventa huecos.
- **Lo guardado no se toca** hasta aceptar. Si una cita nueva pisa bloques guardados, esa tarea
  entra en la propuesta para moverlos; si la quitas de la propuesta, sus bloques se conservan.

## Qué se puede pedir

- Citas: título, día, hora de inicio y de fin, duración, repetición, plan, aviso, quitar.
- Tareas: título, fecha límite, tiempo total, prioridad, dificultad, plan, ponerla primero, quitar.
- Condiciones: «deja libre el viernes por la tarde», «nada después de las 17», «no antes de las
  10», «menos intenso», «lo difícil por la mañana», «primero lo urgente», «reorganiza todo».
- «Deshaz lo último», «rehaz», y «guarda el plan» (enseña «Aceptar propuesta» para confirmar).
  Estas tres se entienden sin IA.
- «Que dure menos» sin decir cuánto: pregunta cuánto. La respuesta («1 hora») completa el cambio.

## Interfaz

- Tarjeta «Tu propuesta está lista» (o «Propuesta actualizada») con tareas, citas, bloques y
  avisos; [Revisar propuesta], [Modificar con IA], deshacer y rehacer.
- «Modificar con IA» deja la propuesta y lleva al campo «¿Qué quieres cambiar?», con atajos
  según la propuesta: Cambiar horario, Ajustar duración, Priorizar, Quitar, Añadir algo, Deshacer.
- Tras cada cambio: «He actualizado tu planificación» y la lista de cambios. Verde = nuevo,
  naranja = cambiado, gris tachado = quitado; siempre con icono y palabra, no solo color.
- Revisión: editar citas (título, día, hora, duración, repetición, plan, aviso, quitar) y tareas
  (título, entrega, horas, prioridad, dificultad, plan, notas, bloques, quitar), y «Pedir cambios
  a la IA». Los cambios a mano son una versión más: se pueden deshacer y la IA parte de ellos.

## Versiones y datos

- `ProposalHistory`: hasta 20 versiones, aparte de la conversación. Al aceptar se borran, así que
  deshacer nunca recupera algo ya aceptado.
- La propuesta activa se guarda en `Application Support/proposal.json` y sigue ahí al cerrar
  Planaby. Al abrir el chat se comprueba: lo borrado desde entonces se olvida y los bloques que ya
  han pasado se recolocan.
- `chat.json` gana campos opcionales (id, estado, cambios): los historiales antiguos se siguen
  leyendo. No hay cambios en SwiftData ni en las copias de seguridad.

## Pruebas

**Automáticas**: `Tests/ProposalEditingTests.swift`, en el CI.

**Solo en el iPhone** (Apple Intelligence no corre en el CI):

1. «Añade una reunión con Jonatan el jueves a las 10 y organiza 4 horas para terminar el informe
   el viernes» → tarjeta con 1 tarea, 1 cita y sus bloques.
2. «Mejor la reunión el miércoles a las 12» → una sola reunión, miércoles 12:00.
3. «El informe me llevará 2 horas» → 4 h → 2 h, bloques recolocados.
4. «Pon el informe primero» → «primero».
5. «Quita la reunión» → quitada (tachada); el informe conserva sus cambios.
6. «Deshaz lo último» → vuelve la reunión, miércoles 12:00.
7. «Ahora sí, guarda el plan» → «Aceptar propuesta» → solo esa versión llega al calendario.
8. Revisar → cambia algo a mano → vuelve → pide otro cambio: el tuyo se mantiene.
9. Cierra Planaby desde el selector de apps con una propuesta abierta y vuelve al chat.
10. Con dos reuniones, «mueve la reunión a las 16» → pregunta cuál.

## Límites conocidos

- Que la IA entienda bien cada frase depende de Apple Intelligence; si no entiende, la propuesta
  sigue igual y puedes editarla a mano.
- Una cita nueva que coincide con otra cita (propia o de Outlook/Teams) solo avisa; no se mueve.
- Las tareas guardadas que entran en una propuesta reciben al aceptar lo que se cambió de ellas.
