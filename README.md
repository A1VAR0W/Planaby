# Planaby

App de concentración para iPhone (iOS 26+): temporizador con varias metodologías, modo escritorio en StandBy,
bloqueo con fricción de apps de distracción y filtrado de mensajes con IA on-device.

## Compilar

El proyecto se genera con [XcodeGen](https://github.com/yonaskolb/XcodeGen) desde `project.yml` y se compila en GitHub Actions
(`.github/workflows/build.yml`), sin necesidad de Mac:

1. Sube el repo a GitHub (rama `main`).
2. Cada push genera `Planaby.ipa` sin firmar: como artifact del workflow y como pre-release `build-N`.
3. En el iPhone, descarga el IPA y ábrelo con **SideStore** (`+` → elegir archivo). SideStore lo firma con tu Apple ID.

Recuerda refrescar la app en SideStore cada 7 días.

## App IDs (cuenta gratuita, máximo 3)

| App ID | Uso |
|---|---|
| `com.alvaro.planaby` | App |
| `com.alvaro.planaby.widgets` | Widgets, Live Activity y Centro de Control (hito 2) |
| — | Libre |

## Estado

- [x] Hito 1: temporizador (Pomodoro, 52/17, Ultradiano, 112/26, 50/10, Flowtime y plantillas propias), notificaciones, historial y diseño minimalista.
- [x] Hito 2: Live Activity y Dynamic Island, widget para inicio/pantalla bloqueada/StandBy, control del Centro de Control, Siri y modo escritorio horizontal.
- [x] Rediseño: pestañas Enfoque, Progreso (objetivo diario, racha, gráfica de 7 días, métodos, historial) y Ajustes (métodos, objetivo, notificaciones, modo escritorio, atajos).
- [x] Hito 3: calendario propio con planes Trabajo y Normal, planificación con IA (chat y plantillas, siempre con confirmación) y recordatorios.
- [x] Secretaria personal: test de ritmo, adjuntos con estimación por IA, reorganizar por prioridad y tareas con checks en modo escritorio.
- [ ] Hito 4: bloqueo con fricción mediante Atajos, estadísticas avanzadas y tareas.
- [ ] Hito 5: triage con IA de iMessage/SMS e IMAP, filtro de Concentración y Spotify.

## Atajos útiles

- **Modo escritorio al cargar:** Atajos → Automatización → *Cargador* → *Está conectado* → acción **Abrir modo escritorio** (Planaby). Con el iPhone en horizontal, la pantalla no se apaga mientras carga.
- **Botón de Acción / Centro de Control:** añade el control **Concentración** de Planaby.

## Tus datos

- **Nada se pierde al cerrar o actualizar:** todo vive en la base de datos de la app (SwiftData), que SideStore conserva al actualizar. Al pasar a segundo plano se guarda lo pendiente, y la conversación con la IA también se guarda.
- **Antes de cada versión nueva** se copian los archivos de la base de datos (las 3 últimas). Si alguna vez no se pudiera abrir, no se borra: se aparta y Ajustes avisa para restaurar una copia.
- **Copias de seguridad:** cada día que usas la app, una copia completa en JSON (tareas, calendario, adjuntos, sesiones, ajustes y conversación) en Archivos › En mi iPhone › Planaby › Copias de seguridad (las 14 últimas). En Ajustes › Copias de seguridad: hacer una ahora, exportarla a iCloud Drive y restaurar. Si vas a borrar la app, exporta antes una copia.
- **Plan Normal en el Calendario de iOS (opcional):** Ajustes › Tus datos. Copia solo el plan Normal a un calendario «Planaby» (en iCloud si lo hay), de ayer a dos meses vista, y lo actualiza con cada cambio. El plan de Trabajo nunca sale de Planaby. Es de un solo sentido: los cambios hechos en el Calendario de iOS se sobrescriben.

## Interfaz

| Pestaña | Contenido |
|---|---|
| **Enfoque** | La cifra, el método y un solo botón principal. Con la sesión en marcha se oculta la barra de pestañas (vuelve al pausar). En horizontal pasa a modo escritorio: solo la cifra y, al tocar, una barra inferior con método, controles, tareas y atenuar. Con las tareas activadas aparece a la derecha una lista con checks (las hechas hoy quedan tachadas con papelera). |
| **Plan** | Selector Trabajo/Normal, semana, agenda del día y tareas pendientes. «+» abre las plantillas (evento, tarea con fecha límite, hábito), ⇅ reorganiza por prioridad y «Planificar con IA» el chat. Al tocar una tarea se abre su ficha (material, bloques, estimar, replanificar). Toda propuesta se revisa (incluir, quitar o mover bloques) antes de guardarse. |
| **Progreso** | Hoy frente al objetivo, racha, media por sesión, últimos 7 días, métodos de la semana e historial con borrado confirmado. |
| **Ajustes** | Tu ritmo (test y lo aprendido), métodos y plantillas, objetivo diario, notificaciones, modo escritorio (pantalla encendida, atenuar, franja nocturna), atajos y Siri. |

### Plan y modos

- **Modo Normal:** solo se ve y avisa el plan personal; los recordatorios de Trabajo quedan en silencio.
- **Modo Trabajo:** se ven y suenan los dos planes.
- **Cambiar de modo:** en la pestaña Plan, en Ajustes, con Siri («Cambia de modo en Planaby») o con un filtro de Concentración: Ajustes de iOS › Concentración › Trabajo › Filtros › Planaby › Modo Trabajo. Al desactivar esa Concentración, Planaby vuelve a Normal.
- **IA:** Apple Intelligence en el dispositivo interpreta el texto; `WorkloadPlanner` reparte las tareas en los huecos del horario de cada modo (Ajustes › Plan), primero la fecha límite más cercana. Sin Apple Intelligence quedan las plantillas.

### Secretaria personal

- **Tu ritmo:** al abrir la app por primera vez (o en Ajustes › Tu ritmo) un test de cinco preguntas: mejores y peores franjas, cuánto aguantas concentrado (fija la duración máxima de bloque y el método), si empiezas por lo difícil y tu horario. Con el uso se mezcla con tus sesiones reales de los últimos 30 días.
- **Reparto personalizado:** lo exigente (dificultad 4–5 o prioridad alta) va a tus horas de más energía; lo ligero, fuera de ellas si prefieres empezar por lo difícil.
- **Estimaciones que aprenden:** las sesiones empezadas desde un bloque quedan ligadas a su tarea; si sueles tardar más (o menos) de lo previsto, las nuevas estimaciones se corrigen y la propuesta lo explica.
- **Material:** capturas, fotos, PDF y textos en la tarea o en el chat. Se leen en el iPhone (Vision y PDFKit) y «Estimar con IA» propone tiempo, dificultad y pasos.
- **Reorganizar:** ordena las tareas pendientes arrastrando y, si ha surgido algo, escríbelo («Me han pedido el presupuesto para mañana, unas 3 horas»). Los bloques que aún no han empezado se recolocan con ese orden. Si una tarea nueva no cabe, la revisión ofrece «Hacer hueco moviendo otros bloques».
- **Por voz:** el micrófono de Plan, de Enfoque (sin sesión en marcha) y de la barra del modo escritorio. Dicta «Preparar la presentación para el viernes, unas 3 horas» o «Reunión con Marta el jueves a las 10»: el reconocimiento de voz del iPhone (en el dispositivo si se puede) lo pasa a texto, Apple Intelligence lo interpreta y sale una tarjeta para confirmar con «Añadir» (en vertical también «Revisar»). Sin Apple Intelligence se apunta como tarea para mañana de 30 min. Deja de escuchar sola tras un silencio.
- **Hecha:** marcar una tarea como hecha libera sus bloques futuros.
- **Horarios por día:** en Ajustes › Horario de Trabajo/Normal, «Días con otro horario» (p. ej. los viernes de 8:00 a 15:00).
- **Outlook y Teams (solo en Planaby):** en outlook.office.com › Configuración › Calendario › Calendarios compartidos › Publicar un calendario, copia el enlace ICS y pégalo en Ajustes › Calendarios externos › Añadir calendario de Outlook. Planaby lo descarga directamente (sin pasar por el Calendario de iOS) al abrirse como mucho cada 15 minutos o al deslizar hacia abajo en Plan, y guarda una copia para usarla sin conexión. Sus eventos (también los de Teams) se ven en la agenda y la revisión, y el planificador no pone bloques encima. Solo lectura; los eventos «libres» y cancelados no cuentan. `ICSCalendar` entiende las zonas horarias de Windows de Outlook, las repeticiones, las excepciones y las reuniones movidas, y tiene tests en CI.
- **Calendarios del iPhone (opcional):** en la misma pantalla se pueden usar también calendarios que ya estén en el Calendario de iOS.
- **Recordatorios:** hasta 40 avisos de los próximos 14 días, que se reprograman al abrir la app, al editar y al cambiar de modo. Los de bloques y hábitos traen «Empezar a concentrarme» y «Posponer 10 min».
- En LiveContainer no funcionan el filtro de Concentración ni Siri; instala desde SideStore.
