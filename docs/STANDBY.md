# Comunicación inteligente, bandeja contextual y StandBy

Qué hace esta parte de Planaby, cómo está montada y qué no puede hacer iOS. Todo funciona en el
iPhone, con la firma gratuita actual (los mismos 2 App IDs, sin extensiones ni entitlements nuevos)
y sin servidores.

## Comunicaciones

- **«Filtrar notificación»** (App Intent) para el disparador «Notificación» de Atajos de iOS 27.
  Recibe, si Atajos los da: app, identificador de la app, remitente, título, subtítulo, texto y
  fecha. Todos son opcionales: cada app rellena la notificación a su manera, puede venir recortada
  (o sin texto si la vista previa está oculta) y no todas las notificaciones disparan el atajo.
  - Reconoce WhatsApp, Instagram, Teams, Outlook, Gmail, Mensajes y Correo por el identificador o
    por el nombre (`Shared/Engine/CommApps.swift`).
  - En los chats el título suele ser el remitente; en el correo, el subtítulo es el asunto.
  - Una huella evita guardar dos veces el mismo aviso.
- **Clasificación:** la misma de siempre (`MessageTriage` + `TriageRules` + Apple Intelligence):
  Urgente, Importante, Puede esperar e Irrelevante, y aparte **«espera respuesta»**. Con IA lo
  decide el modelo, que nunca lo da por bueno en lo irrelevante; sin IA, una regla de preguntas y
  peticiones directas (`CommPolicy.needsReply`). Se mantienen los remitentes prioritarios y las
  correcciones aprendidas.
- **Política** (`Shared/Engine/CommPolicy.swift`, con tests):
  - Concentrándose solo se ve lo urgente e importante de las **apps de trabajo** (por defecto Teams
    y Outlook; Ajustes › Filtro de mensajes › Apps de trabajo y excepciones).
  - Lo personal espera al descanso salvo las excepciones elegidas y, opcionalmente, lo urgente de un
    remitente prioritario.
  - Cuenta como concentración una sesión de Planaby en marcha o, sin sesión, la Concentración del
    iPhone con el filtro de Planaby. El plan Trabajo elegido a mano dentro de Planaby **no** cuenta.
  - Al apagarse esa Concentración, lo personal vuelve a las reglas normales. Planaby no se cierra
    ni se vuelve a abrir.
- **Avisos:** lo que llega por una notificación ya lo ha avisado su app, así que Planaby solo
  repite lo urgente. Concentrándose, solo si es visible según la política.

## Bandeja contextual

- **Enfoque, concentrándose:** «Trabajo · 2 importantes», una línea discreta encima de la tarea que
  no compite con el temporizador. Al tocarla enseña hasta dos líneas, por ejemplo
  «Teams — Jonatan necesita revisar un documento.»
- **Descanso:**
  - La tarjeta de cambio de fase incluye «Mientras te concentrabas: 4 pendientes», con el recuento
    por app.
  - Al cerrarse la tarjeta, Enfoque enseña «Tienes 4 comunicaciones pendientes».
- **Bandeja:** «Pendientes / Todo», «Resumir lo pendiente», y en cada comunicación: revisado,
  respondido (a mano: Planaby no puede saber si contestaste), posponer, al plan como tarea, abrir la
  app (solo la abre; iOS no deja ir a un mensaje concreto) y mover de categoría.
- **«Mientras estabas fuera»:** al volver a Planaby con comunicaciones nuevas y relevantes que no se
  han enseñado.
  - Se basa en la fecha de llegada, en lo ya presentado y en el estado de la app. No detecta si el
    iPhone estuvo bloqueado: no hay API pública para eso.
  - Concentrándose: la línea de trabajo con un punto naranja que late una vez.
  - En el descanso o sin sesión: una tarjeta con el punto naranja, el título y las comunicaciones
    entrando una tras otra.
  - Si a la vez aparece «Bienvenido de nuevo», va dentro de esa hoja. Nunca hay dos hojas a la
    vez, y nada se superpone a la tarjeta de cambio de fase.
  - Con «Reducir movimiento» no hay movimiento, y ninguna animación es continua.

## Modo escritorio, StandBy, widgets y Live Activity

- **Un solo modelo** (`Shared/Engine/DeskPresentation.swift`):
  - Calculado del único `TimerState` (no hay otro temporizador) y de un recuento sin textos
    (`CommsSnapshot` en el App Group).
  - Lo usan el modo escritorio de la app, el widget Concentración y la Live Activity.
  - Tres disposiciones: concentración, descanso y sin sesión.
- **Modo escritorio** (la pantalla de Planaby en horizontal):
  - cifra grande, la tarea, lo que viene después y lo siguiente del plan;
  - el recuento de comunicaciones, que al tocarlo abre la bandeja;
  - de noche, rojo;
  - el halo solo respira en los descansos y nunca de noche (pantalla OLED encendida mucho rato).
- **StandBy de iOS:** es del sistema y Planaby no puede sustituirlo. Ahí solo aparecen los
  widgets y la Live Activity.
  - El widget Concentración tiene una disposición propia para StandBy: cifra de 76 pt, estado y
    una línea (comunicaciones, tarea o lo siguiente).
  - No lleva botones ni animaciones. De noche iOS lo tiñe de rojo.
- **Privacidad:** widgets, Live Activity y StandBy solo enseñan recuentos («2 comunicaciones
  laborales importantes», «Mientras trabajabas: 3 pendientes», «3 pendientes»), nunca el texto de
  un mensaje.
- **Volver a Planaby:** tocar un widget o la Live Activity abre `planaby://desk` (Enfoque; en
  horizontal, el modo escritorio).
- **Rendimiento:**
  - Los widgets solo tienen entradas en los cambios de fase; los contadores son del sistema.
  - Los widgets se recargan al cambiar los recuentos, no con cada mensaje.
  - Sin procesos en segundo plano.

## Abrir Planaby al cargar en horizontal

**«Abrir escritorio si toca»** (App Intent) abre el modo escritorio solo si se cumplen a la vez
las tres condiciones:

- la Concentración elegida (por defecto «Trabajo») está activa;
- el iPhone está cargando;
- el iPhone está en horizontal.

| Concentración | Cargando | Horizontal | Resultado |
|---|---|---|---|
| sí | sí | sí | Abre el modo escritorio |
| sí | sí | no | No abre (no hay disparador al girarlo: widget, Live Activity o acción) |
| sí | no | – | No abre |
| no | – | – | No abre, aunque el plan Trabajo de Planaby esté activo |
| se desactiva | – | – | Nada: ni reabre ni cierra Planaby |

Cómo comprueba cada condición:

- **Concentración:** el filtro de Concentración de Planaby (`PlanModeFocusFilter`, con «Abrir
  escritorio al cargar en horizontal») o el nombre que pase «Obtener concentración actual».
  Trabajo y Work cuentan igual.
- **Carga:** `UIDevice.batteryState`.
- **Orientación:** la gravedad de Core Motion, para medir el iPhone aunque la interfaz no haya
  rotado.

Si todo se cumple, la acción abre Planaby con `continueInForeground`. Cada ejecución queda apuntada
(`IntentLog`) para el tutorial. La acción antigua «Abrir modo escritorio» sigue igual.

**Ajustes › Modo escritorio › Configurar StandBy** guía los seis pasos con su estado. Los que
Planaby puede comprobar solo cuentan como hechos cuando se han ejecutado de verdad (abrir Atajos no
basta):

- el filtro de Concentración;
- la automatización del cargador;
- la automatización de la Concentración.

## Configuración en un iPhone 18 Pro (iOS 27)

1. **StandBy:** Ajustes › StandBy › activar. Opcional: «Modo noche».
2. **Concentración Trabajo con Planaby:**
   - Ajustes › Concentración › Trabajo (créala si no existe) › Filtros de concentración › Añadir
     filtro › Planaby.
   - Modo **Trabajo**, con «Abrir escritorio al cargar en horizontal» activado.
   - En «Personas» y «Apps», silencia lo que no quieras y permite Planaby.
   - Actívala y desactívala una vez. En Configurar StandBy, el paso 2 pasa a «Comprobado».
3. **Automatización A, el cargador:**
   - Atajos › Automatización › + › Cargador › «Está conectado» › «Ejecutar inmediatamente».
   - Opcional: añade «Obtener concentración actual».
   - Añade «Abrir escritorio si toca» con Cuándo «Al conectar el cargador». Si añadiste el paso
     anterior, pon su resultado en «Concentración actual».
4. **Automatización B, la Concentración:**
   - Atajos › Automatización › + › Concentración › Trabajo › «Al activarse» › «Ejecutar
     inmediatamente».
   - Añade «Abrir escritorio si toca» con Cuándo «Al activar la Concentración».
5. **Widgets en StandBy:**
   - Conecta el cargador con el iPhone en horizontal y quieto, y deja que entre en StandBy.
   - Mantén pulsada una pila › + › Planaby › Concentración (y Plan, si quieres).
   - En la pila, desactiva «Rotación inteligente» y «Sugerencias de widgets».
   - iOS no deja ocultarlos según la Concentración, así que también se verán con otras.
6. **Probar:**
   - Con la Concentración Trabajo activa, el cargador conectado y el iPhone en horizontal, abre
     Ajustes › Modo escritorio › Configurar StandBy y pulsa **Probar configuración**.
   - Dice qué falta, si falta algo.
   - Después, desconecta y vuelve a conectar el cargador: la automatización A debe abrir Planaby.
   - Con el iPhone bloqueado, iOS pide Face ID primero.

### Si no se abre sola

- **Conectado en vertical y girado después:** iOS no tiene disparador de orientación ni de StandBy.
  Toca el widget o la Live Activity en StandBy (pide Face ID) o di «Modo escritorio en Planaby».
- **Con el iPhone bloqueado:** ningún atajo puede desbloquearlo. iOS pide Face ID o el código; si
  no, el iPhone sigue en StandBy.
- **Si la automatización pregunta antes de ejecutarse:** falta «Ejecutar inmediatamente».

## Pruebas

Automáticas (Swift Testing, en el CI: `Tests/CommsTests.swift` y `Tests/DeskTests.swift`):

- reconocimiento de apps;
- notificaciones sin campos, chat y correo, y la huella para no repetir;
- «espera respuesta»;
- política en concentración, descanso y excepciones;
- revisado, respondido y pospuesto;
- orden de la bandeja;
- «Mientras estabas fuera»;
- texto de cada línea;
- recuentos por momento;
- privacidad: el recuento compartido no lleva remitentes ni textos;
- la tabla de decisión completa, el plan Trabajo frente a la Concentración, los nombres de
  Concentración y la orientación por gravedad;
- estado de la Concentración y registro de ejecuciones;
- las tres disposiciones del modelo común, con la pausa congelada.

Necesitan el iPhone real y no se pueden dar por comprobadas sin probarlas a mano:

- el disparador «Notificación» de iOS 27 y qué datos pasa cada app;
- el filtro de Concentración al activar y desactivar;
- las automatizaciones del cargador y de la Concentración;
- la apertura con `continueInForeground` con el iPhone bloqueado o en StandBy;
- la orientación con Core Motion en segundo plano;
- el aspecto de los widgets y la Live Activity en StandBy, de día y de noche (rojo);
- las animaciones con «Reducir movimiento»;
- abrir las apps de origen por su esquema;
- Apple Intelligence para «espera respuesta» y «Resumir lo pendiente».
