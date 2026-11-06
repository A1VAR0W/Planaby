import SwiftUI

/// Ajustes › Modo escritorio › Configurar StandBy: «Usar Planaby al cargar el iPhone».
///
/// Seis pasos con su estado. Los que Planaby puede comprobar (el filtro de Concentración y las dos
/// automatizaciones) solo cuentan como hechos cuando se han ejecutado de verdad, no por abrir
/// Atajos. Los que dependen de Ajustes de iOS (StandBy y los widgets) los marca la persona.
struct StandBySetupView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("standBySetup.standBy") private var standByDone = false
    @AppStorage("standBySetup.widgets") private var widgetsDone = false
    @State private var autoOpen = SystemFocusState.autoOpenEnabled()
    @State private var focusName = SystemFocusState.focusName()
    @State private var testing = false
    @State private var check: DeskLauncher.Check?
    @State private var expanded: Int? = nil
    /// Se relee al volver de Atajos o de Ajustes.
    @State private var refresh = 0
    @Environment(\.scenePhase) private var scenePhase

    private struct SetupStep: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let detail: String
        let instructions: [String]
        /// Hecho según Planaby (una ejecución real) o según la persona.
        let status: Status
        var opensShortcuts = false
        var opensSettings = false
    }

    private enum Status: Equatable {
        case pending
        case confirmedByUser
        case verified(Date, String)

        var isDone: Bool { self != .pending }
    }

    private var steps: [SetupStep] {
        _ = refresh
        let filter = IntentLog.last(.focusFilter)
        let charger = IntentLog.last(.deskCharger)
        let focus = IntentLog.last(.deskFocus)
        return [
            SetupStep(
                id: 1, symbol: "platter.filled.bottom.iphone", title: "Activa StandBy",
                detail: "StandBy aparece al cargar el iPhone en horizontal y quieto, con la pantalla bloqueada.",
                instructions: [
                    "Ajustes de iOS › StandBy › activa StandBy.",
                    "Opcional: «Modo noche» para que de noche todo pase a rojo.",
                ],
                status: standByDone ? .confirmedByUser : .pending, opensSettings: true
            ),
            SetupStep(
                id: 2, symbol: "moon.fill", title: "Concentración \(focusName) con Planaby",
                detail: "El filtro de Planaby avisa a la app de que la Concentración del iPhone está activa. Es distinto del plan Trabajo que eliges dentro de Planaby.",
                instructions: [
                    "Ajustes de iOS › Concentración › \(focusName) (créala si no existe).",
                    "Filtros de concentración › Añadir filtro › Planaby.",
                    "Modo: Trabajo. Deja activado «Abrir escritorio al cargar en horizontal».",
                    "Actívala y desactívala una vez para que Planaby lo compruebe.",
                ],
                status: filter.map { Status.verified($0.date, $0.result) } ?? .pending, opensSettings: true
            ),
            SetupStep(
                id: 3, symbol: "bolt.fill", title: "Automatización al conectar el cargador",
                detail: "Cada vez que conectes el cargador, Planaby mira si toca abrir el escritorio. Si no toca, no hace nada.",
                instructions: [
                    "Atajos › Automatización › + › Cargador › «Está conectado».",
                    "Elige «Ejecutar inmediatamente» (si no, iOS pregunta cada vez).",
                    "Opcional: añade «Obtener concentración actual».",
                    "Añade «Abrir escritorio si toca» de Planaby. Cuándo: «Al conectar el cargador». Si añadiste el paso anterior, pon su resultado en «Concentración actual».",
                ],
                status: charger.map { Status.verified($0.date, $0.result) } ?? .pending, opensShortcuts: true
            ),
            SetupStep(
                id: 4, symbol: "person.crop.circle.badge.moon", title: "Automatización al activar la Concentración",
                detail: "Para cuando el iPhone ya está cargando en horizontal y activas la Concentración después.",
                instructions: [
                    "Atajos › Automatización › + › Concentración › \(focusName) › «Al activarse».",
                    "Elige «Ejecutar inmediatamente».",
                    "Añade «Abrir escritorio si toca». Cuándo: «Al activar la Concentración».",
                ],
                status: focus.map { Status.verified($0.date, $0.result) } ?? .pending, opensShortcuts: true
            ),
            SetupStep(
                id: 5, symbol: "square.stack.fill", title: "Widgets de Planaby en StandBy",
                detail: "Así StandBy enseña el temporizador y el plan aunque Planaby no se abra.",
                instructions: [
                    "Con el iPhone en StandBy, mantén pulsada una pila de widgets › + › Planaby (Concentración y Plan).",
                    "Pon el de Concentración arriba de la pila.",
                    "En la pila, desactiva «Rotación inteligente» y «Sugerencias de widgets» para que no cambie solo.",
                    "iOS no permite ocultar los widgets según la Concentración: también se verán con otras.",
                ],
                status: widgetsDone ? .confirmedByUser : .pending
            ),
            SetupStep(
                id: 6, symbol: "checkmark.seal.fill", title: "Prueba la configuración",
                detail: "Con la Concentración activa, el cargador conectado y el iPhone en horizontal, pulsa «Probar configuración».",
                instructions: [],
                status: check?.decision == .open ? .verified(check?.date ?? .now, "Todo listo") : .pending
            ),
        ]
    }

    var body: some View {
        let steps = steps
        let done = steps.filter(\.status.isDone).count
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Usar Planaby al cargar el iPhone")
                        .font(.title2.weight(.semibold))
                    Text("Configura Planaby para que se abra cuando coloques el iPhone horizontalmente mientras tienes activada la Concentración \(focusName).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    ProgressView(value: Double(done), total: Double(steps.count)) {
                        Text("\(done) de \(steps.count) pasos")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(Theme.orange)
                    .padding(.top, Space.xs)
                }
                .padding(.vertical, Space.xs)
            }

            Section {
                ForEach(steps) { step in
                    stepCard(step)
                }
            }

            Section {
                Button {
                    runTest()
                } label: {
                    Label(testing ? "Comprobando…" : "Probar configuración", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.orange)
                .disabled(testing)
                .listRowBackground(Color.clear)
                if let check {
                    testResult(check)
                }
            } footer: {
                Text("La prueba mira lo mismo que las automatizaciones: la Concentración (según el filtro de Planaby), si carga y la orientación. No abre nada ni cambia ajustes.")
            }

            Section {
                Toggle("Abrir al cargar en horizontal", isOn: $autoOpen)
                    .onChange(of: autoOpen) { _, value in SystemFocusState.setAutoOpen(value) }
                LabeledContent("Concentración") {
                    TextField("Trabajo", text: $focusName)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { SystemFocusState.setFocusName(focusName) }
                }
            } header: {
                Text("Preferencias")
            } footer: {
                Text("El nombre solo se compara con el que pasa «Obtener concentración actual» (Trabajo y Work cuentan igual). Sin ese paso, vale cualquier Concentración que tenga el filtro de Planaby con «Abrir escritorio» activado.")
            }

            Section {
                limit("No hay disparador al girar el iPhone ni al entrar en StandBy. Si lo conectas en vertical y lo giras después, no se abrirá solo: toca el widget de Planaby o la Live Activity, o usa la acción «Modo escritorio».", symbol: "rotate.right")
                limit("Con el iPhone bloqueado, iOS pide Face ID o el código para abrir Planaby. Ningún atajo puede desbloquearlo; si iOS no la abre, el iPhone sigue en StandBy.", symbol: "lock.fill")
                limit("Planaby no puede saber si el iPhone está en StandBy o bloqueado, ni sustituir la pantalla de StandBy: ahí solo aparecen sus widgets y la Live Activity.", symbol: "eye.slash")
                limit("Al desactivar la Concentración, Planaby no se cierra ni se vuelve a abrir: solo deja de guardar lo personal para el descanso.", symbol: "moon.zzz")
                limit("Los widgets fijados en StandBy siguen apareciendo con otras Concentraciones: iOS no permite ocultarlos según la Concentración.", symbol: "square.stack")
            } header: {
                Text("Límites de iOS")
            }

            Section {
                Button("Abrir Atajos", systemImage: "square.2.layers.3d") { open("shortcuts://") }
                Button("Abrir Ajustes de iOS", systemImage: "gear") { open(UIApplication.openSettingsURLString) }
            } header: {
                Text("Ayuda")
            } footer: {
                Text("Si una automatización no se ejecuta, revisa que tenga «Ejecutar inmediatamente» y que la acción sea de Planaby. Aquí verás la última vez que se ejecutó cada una.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Configurar StandBy")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
        .onDisappear { SystemFocusState.setFocusName(focusName) }
    }

    // MARK: Piezas

    private func stepCard(_ step: SetupStep) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                withAnimation(Motion.quick) { expanded = expanded == step.id ? nil : step.id }
            } label: {
                HStack(alignment: .top, spacing: Space.m) {
                    ZStack {
                        Circle()
                            .fill(step.status.isDone ? Theme.orange : Theme.surface)
                            .frame(width: 36, height: 36)
                        Image(systemName: step.status.isDone ? "checkmark" : step.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(step.status.isDone ? .black : Theme.orange)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(step.id). \(step.title)")
                            .font(.subheadline.weight(.semibold))
                        Text(statusText(step.status))
                            .font(.caption)
                            .foregroundStyle(step.status.isDone ? Theme.orange : Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded == step.id ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(statusText(step.status))

            if expanded == step.id {
                Text(step.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                ForEach(Array(step.instructions.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: Space.s) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.orange)
                            .frame(width: 16)
                        Text(line)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: Space.s) {
                    if step.opensShortcuts {
                        Button("Abrir Atajos") { open("shortcuts://") }
                    }
                    if step.opensSettings {
                        Button("Abrir Ajustes") { open(UIApplication.openSettingsURLString) }
                    }
                    if step.id == 1 || step.id == 5 {
                        Button(step.status.isDone ? "Marcar pendiente" : "Ya lo he hecho") {
                            if step.id == 1 { standByDone.toggle() } else { widgetsDone.toggle() }
                        }
                    }
                }
                .buttonStyle(.glass)
                .font(.footnote.weight(.semibold))
                .padding(.top, Space.xs)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func statusText(_ status: Status) -> String {
        switch status {
        case .pending: "Pendiente"
        case .confirmedByUser: "Hecho (lo has marcado tú)"
        case .verified(let date, let result): "Comprobado \(date.formatted(.relative(presentation: .named))) · \(result)"
        }
    }

    private func testResult(_ check: DeskLauncher.Check) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            row("Concentración \(focusName)", ok: check.focusActive, detail: check.focusActive ? "Activa" : "No activa (o el filtro de Planaby no ha avisado)")
            row("Cargando", ok: check.charging == true, detail: check.charging.map { $0 ? "Sí" : "No" } ?? "iOS no lo sabe")
            row("En horizontal", ok: check.landscape == true, detail: check.landscape.map { $0 ? "Sí" : "No, está en vertical" } ?? "No se pudo medir (¿plano?)")
            Divider()
            switch check.decision {
            case .open:
                Label("Todo listo: la automatización abriría el modo escritorio.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.orange)
            case .skip(let reason):
                Label(reason.text, systemImage: "info.circle")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.footnote)
    }

    private func row(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Theme.orange : Theme.secondaryText)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: Space.s)
            Text(detail)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func limit(_ text: String, symbol: String) -> some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.orange)
        }
    }

    private func runTest() {
        SystemFocusState.setFocusName(focusName)
        testing = true
        Task {
            check = await DeskLauncher.shared.evaluate(trigger: .manual, focusName: nil)
            testing = false
            refresh += 1
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { openURL(url) }
    }
}
