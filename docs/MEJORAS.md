# Planaby como asistente de concentración

Qué se ha añadido para que Planaby ayude a concentrarse incluso sin ganas, reduzca las
distracciones y ayude a terminar tareas **sin pedir atención de más**. Todo funciona en el iPhone,
sin servidores, cuentas ni APIs de pago, con la firma gratuita actual (los mismos 2 App IDs, sin
extensiones nuevas ni entitlements de pago).

## Qué hay nuevo

### Estabilidad y datos
- **Pases por app:** «Abrir igualmente» solo da pase a la app que se abre. Antes, un aviso de Atajos
  sin nombre de app creaba un pase global que desbloqueaba todas. Los pases caducan por fecha
  (`Shared/Engine/PassBook.swift`) y siguen leyendo el formato guardado por versiones anteriores.
- **Sesiones con identidad:** cada tarea tiene un identificador estable (`PlanTask.uid`) y cada
  sesión guarda tarea, plan (Trabajo o Normal), método, minutos planificados, si se dejó a medias,
  pausas, salidas de la app, tiempo fuera y descansos saltados. Las tareas y sesiones antiguas se
  enlazan una vez por el título al abrir la app (`PlanabyStore.backfillIdentifiers`).
- **Estadísticas corregidas:** el mapa de calor reparte el tiempo concentrado por las horas reales
  de la sesión (antes sumaba todo a la hora de inicio); las pausas conscientes y las salidas de
  Planaby van por separado; hay tasa de sesiones completadas, interrupciones por sesión,
  comparación de métodos y tareas terminadas.
- **Migración segura:** todos los campos nuevos de SwiftData tienen valor por defecto y los del
  estado del temporizador son opcionales, así que las versiones anteriores se leen sin borrar nada.
  Las copias de seguridad incluyen los campos nuevos (opcionales al restaurar copias antiguas).

### Avisos de fase
- Seis sonidos propios, sintetizados con `tools/make_sounds.py` (campana suave, madera y cristal;
  uno para empezar el descanso y otro para volver), o el del sistema.
- Ajustes › Notificaciones › **Avisos de concentración**: cuándo avisar (al empezar el descanso, al
  volver), estilo (sonido y vibración, solo vibración, solo visual), juego de sonidos, tarjeta en
  la app y «No sonar si hay música».
- Con Planaby delante no llega la notificación (para no avisar dos veces): aparece una tarjeta con
  el siguiente paso, sonido con sesión de audio `ambient` (respeta el modo silencio y se mezcla con
  la música) y vibración. Al reprogramar, se quitan los avisos ya entregados de la sesión.

### Atención
- **Sin ganas: empezar 5 minutos** («Empezar ahora»): la tarea principal (la del bloque en curso o
  la más prioritaria del plan actual), un primer paso pequeño (el guardado, el primero de las notas
  o uno propuesto por Apple Intelligence) y un método de 5 minutos. Al terminar, la tarjeta pregunta
  si seguir con un bloque del método habitual, descansar o terminar.
- **Contexto de la sesión:** objetivo, siguiente paso, notas y lo que falta. El siguiente paso se ve
  bajo el temporizador y en el aviso de vuelta del descanso.
- **Me he atascado:** intentarlo 10 minutos con un paso más pequeño, o aparcar la tarea (queda
  marcada como atascada con la nota) y cambiar a otra sin cortar la sesión.
- **Bienvenido de nuevo:** al volver tras salir de Planaby en mitad de un bloque, recuerda la tarea y
  el siguiente paso; si estuviste fuera más de 10 minutos, propone retomar con un bloque corto.
- **Bloqueo adaptativo** (con la automatización de Atajos, opcional): intensidad suave, equilibrada
  o estricta; pase y aperturas libres al día por app (solo fuera de la concentración); la pausa
  crece si insistes con la misma app en media hora; en los descansos frena con más suavidad; motivos
  rápidos (aburrimiento, costumbre, tarea difícil, cansancio…), obligatorios en modo estricto.
- Valoración opcional al terminar sesiones de 10 minutos o más («disperso, normal, muy centrado»).

### Personalización
- `AttentionProfileEngine` (reglas deterministas en `Shared/Engine/AttentionEngine.swift`):
  - no propone nada con menos de 5 sesiones del plan;
  - solo mira los últimos 45 días (30 sesiones como mucho);
  - Trabajo y Normal se aprenden por separado;
  - acorta como mucho un 30 % de golpe y alarga de 5 en 5 minutos;
  - una sesión larga no cuenta como buena si se interrumpe mucho o se valora como dispersa.
- Propone: bloques más cortos o más largos, descansos más cortos o más largos, volver a un método
  que funciona mejor y la franja horaria en la que mejor terminas. Cada propuesta explica sus cifras.
- `AdaptiveFocusCoordinator`: una sola sugerencia a la vez en Enfoque. «Probar» crea o actualiza el
  método «Adaptado · Trabajo/Normal» (o elige el método propuesto); «Ahora no» la calla 14 días; «No
  sugerir más» lo desactiva. Nada cambia sin aceptarlo.
- Ajustes › Tu ritmo › **Lo aprendido**: sesiones analizadas, mejores horas, hora con más
  distracciones, métodos y sugerencias por plan; interruptores y **Reiniciar lo aprendido** (no borra
  el historial). El test de ritmo sigue siendo opcional.

### IA
- `AIProvider`: acceso único a Apple Intelligence (Foundation Models, en el dispositivo). Todo el
  contenido externo (mensajes, correos, adjuntos, notas) va entre `<datos>…</datos>` y las
  instrucciones dicen que nunca se sigan órdenes que aparezcan dentro. Lo usan el chat del plan, la
  estimación de tareas, el filtro de mensajes, el primer paso y el resumen del día.
- `PersonalContextService`: el contexto personal mínimo para la IA (plan actual, mejores horas,
  método habitual); nunca mensajes ni adjuntos.
- Resumen del día en Progreso: con cifras y sin IA; con Apple Intelligence, redactado con una
  sugerencia para mañana (a la IA solo le llegan cifras).
- Filtro de mensajes (`Shared/Engine/TriageRules.swift`):
  - remitentes prioritarios, que nunca acaban en «Puede esperar» ni en «Ruido»;
  - lo que mueves a mano en la bandeja se aprende por remitente;
  - «urgente» sin motivo ni plazo de horas se queda en «Importante».

## Decisiones de arquitectura
- **Lógica pura y probada aparte de la interfaz:** pases, política de bloqueo, motor de atención,
  reparto por horas, reglas de mensajes y estado del temporizador no dependen de SwiftUI ni
  SwiftData, y entran en el target de tests.
- **Las reglas deciden; la IA redacta.** Las recomendaciones salen de reglas deterministas
  explicables; la IA solo propone primeros pasos, clasifica mensajes (corregida por las reglas) y
  redacta resúmenes. Si no hay Apple Intelligence, todo tiene alternativa.
- **Una cosa cada vez:** una sola sugerencia, una tarjeta al cambiar de fase que se cierra sola y
  ninguna notificación nueva que compita por la atención.

## Limitaciones de iOS con la firma gratuita
- **Sin Family Controls** (necesita cuenta de pago): Planaby no puede bloquear apps de verdad ni
  saber qué app se abre. Lo que sí hace: avisar al salir de Planaby concentrándose (y, en modo
  estricto, no contar ese rato) y, con la automatización opcional de Atajos, frenar con la pausa
  consciente.
- **Sin notificaciones críticas ni urgentes** (necesitan entitlements): los avisos son normales y
  respetan las Concentraciones del iPhone.
- Con «Solo vibración», las notificaciones con la app cerrada llegan sin sonido ni vibración, porque
  iOS solo vibra con los avisos que suenan. Dentro de la app sí vibra.
- Un aviso de Atajos «al abrir cualquiera de estas apps» no dice cuál se abrió. Por eso en ese caso
  se elige la app al pulsar «Abrir igualmente»; con una automatización por app, el pase es exacto.
- Sin audio en segundo plano: los sonidos en la app solo suenan con Planaby delante.

## Alternativas de IA gratuitas evaluadas

| Opción | Coste | Privacidad | Encaje | Decisión |
|---|---|---|---|---|
| **Foundation Models (Apple Intelligence)** | Gratis | En el iPhone | Ya integrado, salida estructurada | **Se usa** |
| Core ML con un modelo propio | Gratis | En el iPhone | Bueno para clasificar mensajes, pero hay que entrenar y mantener el modelo | No por ahora: las reglas más la IA de Apple bastan |
| MLX Swift con un LLM pequeño (p. ej. 1–3B) | Gratis | En el iPhone | Funciona sin Apple Intelligence, pero añade cientos de MB, más batería y una dependencia nueva | No: no se justifica para este uso |
| Ollama en el PC o servidor propio | Gratis | En casa, por red | Necesita el ordenador encendido y la red; expone datos fuera del iPhone | No |
| APIs de pago (OpenAI, Anthropic, Gemini…) | De pago | Fuera del dispositivo | Lo descarta el requisito | No |

Si algún día el iPhone no tuviera Apple Intelligence, la alternativa con más sentido sería MLX con
un modelo pequeño solo para el primer paso y el resumen; todo lo demás ya funciona sin IA.

## Configuración manual en el iPhone
1. **Nada obligatorio.** El aviso al salir de Planaby, «Empezar ahora», los avisos de fase y las
   sugerencias funcionan nada más instalar.
2. *Opcional:* Ajustes › Bloqueo › Frenar apps → elegir apps y crear la automatización de Atajos
   (una vez). Ahí mismo, intensidad y reglas por app.
3. *Opcional:* Ajustes › Notificaciones › Avisos de concentración → sonido y estilo.
4. *Opcional:* Ajustes › Filtro de mensajes › Remitentes prioritarios.
5. Apple Intelligence activado en Ajustes de iOS, para el primer paso propuesto, el resumen
   redactado y el filtro de mensajes con IA (sin él se usan las alternativas sin IA).

## Pruebas
Tests automáticos con Swift Testing (`Tests/`), en el CI:
- pases por app, sin nombre y caducidad;
- pausa consciente: fuera de horario, pase, escalada, descansos y aperturas libres;
- temporizador: pausas, descansos saltados, salidas, sesiones a medias, bloque corto, cambio de
  método, avisos con la sesión en pausa y lectura de estados antiguos;
- reparto por horas;
- recomendaciones: pocas muestras, separación por plan, ventana de 45 días, más corto y más largo,
  sesiones largas pero interrumpidas, valoraciones bajas, descansos, cambio de método, método libre,
  franjas y hora de más distracciones;
- reglas de mensajes: remitentes, correcciones, «urgente» sin motivo y texto con órdenes.

Lo que necesita el iPhone real (interfaz, sonidos, avisos, Atajos y Apple Intelligence) no tiene
tests automáticos y hay que comprobarlo a mano.

## Recomendaciones futuras
- Probar en el iPhone durante una o dos semanas y ajustar los umbrales del motor (40 % de
  abandonos, 80 % de sesiones completadas…).
- Tests de interfaz con XCUITest para «Empezar ahora» y «Bienvenido de nuevo».
- Si Apple abre Family Controls a cuentas gratuitas, sustituir la fricción de Atajos por un bloqueo
  real.
