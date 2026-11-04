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
| `com.alvaro.planaby.widgets` | Widgets (Concentración y Plan), Live Activity y Centro de Control |
| — | Libre |

## Estado

- [x] Hito 1: temporizador (Pomodoro, 52/17, Ultradiano, 112/26, 50/10, Flowtime y plantillas propias), notificaciones, historial y diseño minimalista.
- [x] Hito 2: Live Activity y Dynamic Island, widget para inicio/pantalla bloqueada/StandBy, control del Centro de Control, Siri y modo escritorio horizontal.
- [x] Rediseño: pestañas Enfoque, Progreso (objetivo diario, racha, gráfica de 7 días, métodos, historial) y Ajustes (métodos, objetivo, notificaciones, modo escritorio, atajos).
- [x] Hito 3: calendario propio con planes Trabajo y Normal, planificación con IA (chat y plantillas, siempre con confirmación) y recordatorios.
- [x] Secretaria personal: test de ritmo, adjuntos con estimación por IA, reorganizar por prioridad y tareas con checks en modo escritorio.
- [x] Hito 4: bloqueo con fricción mediante Atajos, estadísticas avanzadas, tareas y vista de mes.
- [x] Hito 5: filtro de mensajes con IA (iMessage/SMS con Atajos y correo por IMAP), avisos según la Concentración y música por fase (Spotify con enlaces). Spotify como mando con App Remote y la API web (carátula, controles y listas, también con cuenta gratuita).
- [x] Versión 1.0: widget «Plan» (lo que tienes ahora y lo siguiente, en inicio y pantalla bloqueada), Spotify como llave de paso, reproductor automático y dictado mejorado.

## Atajos útiles

- **Modo escritorio al cargar:** Atajos → Automatización → *Cargador* → *Está conectado* → acción **Abrir modo escritorio** (Planaby). Con el iPhone en horizontal, la pantalla no se apaga mientras carga.
- **Botón de Acción / Centro de Control:** añade el control **Concentración** de Planaby.
- **Bloqueo con fricción:** Ajustes › Bloqueo con fricción › **Elegir las apps**: marcas las que te distraen y Planaby te guía por Atajos (Automatización → *App* → tus apps → *Se abre* → *Ejecutar inmediatamente* → buscar «Bloquear» y tocar la acción, que ya lleva la app puesta: «Bloquear Instagram» o, para varias, «Bloquear la app que se abre»). Sin escribir nada; esa pantalla dice «Funciona» en cuanto llega el primer aviso. Se configura una vez; luego se enciende y apaga con el interruptor **Bloquear apps** de Ajustes. Planaby se abre, te pide respirar unos segundos y decides: «Volver a lo mío» o «Abrir igualmente N min» (durante ese rato no te vuelve a frenar). En Ajustes › Bloqueo con fricción eliges cuándo frenar (solo concentrándote, también en horario de Trabajo o siempre), cuánto respirar y la duración del pase. No usa Family Controls, que necesita una cuenta de pago.

- **Filtro de mensajes (iMessage y SMS):** Atajos → Automatización → *Mensaje* → remitentes → *Ejecutar inmediatamente* → acción **Filtrar mensaje** (Planaby) con la entrada del atajo y el remitente. Apple Intelligence lo clasifica en el iPhone (urgente, importante, puede esperar o ruido), se guarda en la bandeja de Enfoque y solo avisa de lo urgente (y de lo importante si no te estás concentrando; al terminar la sesión llega un resumen).
- **Correo cada hora con la app cerrada:** Atajos → Automatización → *Hora del día* → acción **Comprobar correo**.

## Filtro de mensajes y música

- **Correo (IMAP):** Ajustes › Filtro de mensajes › Correo: Gmail, iCloud, Outlook/Hotmail, Yahoo u otro servidor, con una contraseña de aplicación (se guarda en el Llavero). Planaby lee los correos sin abrir de los dos últimos días sin marcarlos como leídos, al abrirse (como mucho cada 10 minutos), al deslizar en la bandeja o con «Comprobar correo». Las cuentas de Microsoft 365 del trabajo suelen tener IMAP bloqueado.
- **Bandeja:** el botón de bandeja de Enfoque (con el número de urgentes e importantes sin leer). Tocar marca leído; deslizar a la derecha manda el mensaje al chat del plan («Al plan»); a la izquierda, borrar; mantener pulsado, moverlo de categoría. Es una copia: los mensajes de verdad siguen en sus apps.
- **Que no interrumpan:** en Ajustes de iOS › Concentración (p. ej. Trabajo) silencia Mensajes y Correo y permite Planaby; Planaby avisará solo de lo que importa.
- **Spotify como mando:** Ajustes › Música › Spotify. Una sola vez: en developer.spotify.com/dashboard, «Create app» con la Redirect URI `planaby-spotify://callback`, «Web API» e «iOS» (el Bundle ID real, que SideStore termina con tu Team ID, p. ej. `com.alvaro.planaby.XXXXXXXXXX`; Ajustes lo muestra y lo copia), y pega el Client ID en Planaby. Se conecta con PKCE (sin secreto; la sesión va al Llavero) y no usa ningún App ID de Apple. Enfoque muestra lo que suena (carátula, canción, reproducir/pausar) y al tocarlo, el reproductor completo con progreso, anterior/siguiente, aleatorio y tus listas. En el modo escritorio, el botón ♪ pone la carátula a pantalla completa con los controles y el temporizador en pequeño (de noche, en rojo como StandBy). Los controles van por **App Remote** (SDK de Spotify para iOS): Planaby manda las órdenes a la app de Spotify instalada, así que funcionan también con cuenta gratuita y con apps de Spotify modificadas (p. ej. SpotC++/EeveeSpotify), que se abren por el esquema `spotify:` aunque estén re-firmadas. Si Spotify estaba cerrado se abre un instante para despertarlo y vuelve a Planaby; si App Remote no conecta, se usa la API web (que con cuenta gratuita solo permite ver lo que suena). También se puede pulsar «Conectar solo con la app de Spotify» y prescindir de la API web: Spotify se abre una sola vez para dar permiso y Planaby guarda una sesión renovable (el SDK de Spotify con PKCE); después hace de llave de paso y manda las órdenes sin abrirlo. Solo lo abre si está dormido (nada sonando un rato) y pulsas reproducir. Sin API web no se ve lo que suena en otro dispositivo. Si conectaste antes de la versión 0.1.28, desconecta y vuelve a conectar para conceder el permiso `app-remote-control`.
- **Música:** Ajustes › Música: un enlace de lista para concentrarte y otro para descansar (Spotify, Apple Music o YouTube Music). Los de Spotify se abren en su app. Con «Reproducir al empezar cada fase», al empezar una sesión o un descanso con Planaby abierta suena su lista; con Spotify conectado y sin lista, al concentrarte reanuda lo que tenías y al terminar la sesión lo pausa. En el modo escritorio la carátula aparece sola cuando empieza a sonar Spotify, como en StandBy (Ajustes › Modo escritorio › Carátula al sonar música).

## Tus datos

- **Nada se pierde al cerrar o actualizar:** todo vive en la base de datos de la app (SwiftData), que SideStore conserva al actualizar. Al pasar a segundo plano se guarda lo pendiente, y la conversación con la IA también se guarda.
- **Antes de cada versión nueva** se copian los archivos de la base de datos (las 3 últimas). Si alguna vez no se pudiera abrir, no se borra: se aparta y Ajustes avisa para restaurar una copia.
- **Copias de seguridad:** cada día que usas la app, una copia completa en JSON (tareas, calendario, adjuntos, sesiones, ajustes y conversación) en Archivos › En mi iPhone › Planaby › Copias de seguridad (las 14 últimas). En Ajustes › Copias de seguridad: hacer una ahora, exportarla a iCloud Drive y restaurar. Si vas a borrar la app, exporta antes una copia.
- **Sincronizar con el Calendario de iOS (opcional):** Ajustes › Tus datos. Al activarlo, los eventos de los calendarios del iPhone aparecen en Planaby en el plan Normal (se eligen en Calendarios externos; los cumpleaños no) y el planificador no pone bloques encima. Además copia solo el plan Normal a un calendario «Planaby» (en iCloud si lo hay), de ayer a dos meses vista, y lo actualiza con cada cambio. El plan de Trabajo nunca sale de Planaby. Es de un solo sentido: los cambios hechos en el Calendario de iOS se sobrescriben.

## Interfaz

| Pestaña | Contenido |
|---|---|
| **Enfoque** | La cifra, el método y un solo botón principal. Con la sesión en marcha se oculta la barra de pestañas (vuelve al pausar). En horizontal pasa a modo escritorio: solo la cifra y, al tocar, una barra inferior con método, controles, tareas y atenuar. Con las tareas activadas aparece a la derecha una lista con checks (las hechas hoy quedan tachadas con papelera). |
| **Plan** | Selector Trabajo/Normal, semana o mes entero (toca el nombre del mes; las flechas o deslizar cambian de semana o de mes; puntos de color por plan y calendario), agenda del día y tareas pendientes. «+» abre las plantillas (evento, tarea con fecha límite, hábito), ⇅ reorganiza por prioridad y el botón naranja «Planificar con IA» abre el chat (o, con su micrófono, dicta por voz). Al tocar una tarea se abre su ficha (material, bloques, estimar, replanificar). Toda propuesta se revisa (incluir, quitar o mover bloques) antes de guardarse. |
| **Progreso** | Hoy frente al objetivo, racha, media por sesión, últimos 7 días, métodos de la semana e historial con borrado confirmado. Debajo, el **Análisis** de 7 días, 30 días o 3 meses: mapa de calor por día y hora con tu mejor franja, plan cumplido (bloques con sesión), desvío de tus estimaciones, reparto Trabajo/Normal, distracciones frenadas y entregas a tiempo. |
| **Ajustes** | Bloqueo con fricción, música, filtro de mensajes, sincronización con el Calendario de iOS, copias de seguridad, tu ritmo (test y lo aprendido), métodos y plantillas, objetivo diario, notificaciones, modo escritorio (pantalla encendida, atenuar, franja nocturna), atajos y Siri. |

### Plan y modos

- **Modo Normal:** solo se ve y avisa el plan personal; los recordatorios de Trabajo quedan en silencio.
- **Modo Trabajo:** se ven y suenan los dos planes.
- **Cambiar de modo:** en la pestaña Plan, en Ajustes, con Siri («Cambia de modo en Planaby») o con un filtro de Concentración: Ajustes de iOS › Concentración › Trabajo › Filtros › Planaby › Modo Trabajo. Al desactivar esa Concentración, Planaby vuelve a Normal.
- **IA:** Apple Intelligence en el dispositivo interpreta el texto. Si no está claro si algo es de Trabajo o del plan Normal, pregunta («¿«Llamar a Juan» va en tu plan de Trabajo o en el Normal?») con dos botones, en el chat, por voz y en Reorganizar; `WorkloadPlanner` reparte las tareas en los huecos del horario de cada modo (Ajustes › Plan), primero la fecha límite más cercana. Sin Apple Intelligence quedan las plantillas.

### Secretaria personal

- **Tu ritmo:** al abrir la app por primera vez (o en Ajustes › Tu ritmo) un test de cinco preguntas: mejores y peores franjas, cuánto aguantas concentrado (fija la duración máxima de bloque y el método), si empiezas por lo difícil y tu horario. Con el uso se mezcla con tus sesiones reales de los últimos 30 días.
- **Reparto personalizado:** lo exigente (dificultad 4–5 o prioridad alta) va a tus horas de más energía; lo ligero, fuera de ellas si prefieres empezar por lo difícil.
- **Estimaciones que aprenden:** las sesiones empezadas desde un bloque quedan ligadas a su tarea; si sueles tardar más (o menos) de lo previsto, las nuevas estimaciones se corrigen y la propuesta lo explica.
- **Material:** capturas, fotos, PDF y textos en la tarea o en el chat. Se leen en el iPhone (Vision y PDFKit) y «Estimar con IA» propone tiempo, dificultad y pasos.
- **Reorganizar:** ordena las tareas pendientes arrastrando y, si ha surgido algo, escríbelo («Me han pedido el presupuesto para mañana, unas 3 horas»). Los bloques que aún no han empezado se recolocan con ese orden. Si una tarea nueva no cabe, la revisión ofrece «Hacer hueco moviendo otros bloques».
- **Por voz:** el micrófono de Plan, de Enfoque (sin sesión en marcha) y de la barra del modo escritorio. Dicta «Preparar la presentación para el viernes, unas 3 horas» o «Reunión con Marta el jueves a las 10»: el reconocimiento de voz del iPhone (en el dispositivo si se puede) lo pasa a texto, Apple Intelligence lo interpreta y sale una tarjeta para confirmar con «Añadir» (en vertical también «Revisar»). Sin Apple Intelligence se apunta como tarea para mañana de 30 min, preguntando antes si es de Trabajo o Normal. Deja de escuchar sola tras un silencio.
- **Hecha:** marcar una tarea como hecha libera sus bloques futuros.
- **Horarios por día:** en Ajustes › Horario de Trabajo/Normal, «Días con otro horario» (p. ej. los viernes de 8:00 a 15:00).
- **Outlook y Teams (solo en Planaby):** en outlook.office.com › Configuración › Calendario › Calendarios compartidos › Publicar un calendario, copia el enlace ICS y pégalo en Ajustes › Calendarios externos › Añadir calendario de Outlook. Planaby lo descarga directamente (sin pasar por el Calendario de iOS) al abrirse como mucho cada 15 minutos o al deslizar hacia abajo en Plan, y guarda una copia para usarla sin conexión. Sus eventos (también los de Teams) se ven en la agenda y la revisión, y el planificador no pone bloques encima. Solo lectura; los eventos «libres» y cancelados no cuentan. `ICSCalendar` entiende las zonas horarias de Windows de Outlook, las repeticiones, las excepciones y las reuniones movidas, y tiene tests en CI.
- **Calendarios del iPhone (opcional):** en la misma pantalla se pueden usar también calendarios que ya estén en el Calendario de iOS.
- **Recordatorios:** hasta 40 avisos de los próximos 14 días, que se reprograman al abrir la app, al editar y al cambiar de modo. Los de bloques y hábitos traen «Empezar a concentrarme» y «Posponer 10 min».
- En LiveContainer no funcionan el filtro de Concentración ni Siri; instala desde SideStore.
