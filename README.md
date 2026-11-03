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
- [ ] Hito 3: calendario propio con planes Trabajo y Normal, planificación con IA (chat y plantillas, siempre con confirmación) y recordatorios.
- [ ] Hito 4: bloqueo con fricción mediante Atajos, estadísticas avanzadas y tareas.
- [ ] Hito 5: triage con IA de iMessage/SMS e IMAP, filtro de Concentración y Spotify.

## Atajos útiles

- **Modo escritorio al cargar:** Atajos → Automatización → *Cargador* → *Está conectado* → acción **Abrir modo escritorio** (Planaby). Con el iPhone en horizontal, la pantalla no se apaga mientras carga.
- **Botón de Acción / Centro de Control:** añade el control **Concentración** de Planaby.

## Interfaz

| Pestaña | Contenido |
|---|---|
| **Enfoque** | La cifra, el método y un solo botón principal. Con la sesión en marcha se oculta la barra de pestañas (vuelve al pausar). En horizontal pasa a modo escritorio: solo la cifra y, al tocar, una barra inferior con método, controles y atenuar. |
| **Progreso** | Hoy frente al objetivo, racha, media por sesión, últimos 7 días, métodos de la semana e historial con borrado confirmado. |
| **Ajustes** | Métodos y plantillas, objetivo diario, notificaciones, modo escritorio (pantalla encendida, atenuar, franja nocturna), atajos y Siri. |

El hito 3 añadirá la pestaña **Plan** (calendario y planificación) entre Enfoque y Progreso; los siguientes hitos añaden su sección en Ajustes.
