import SwiftUI

/// Guía para que la Concentración «Trabajo» del iPhone y Planaby trabajen juntas. Deja claro
/// quién hace qué: iOS es quien silencia las apps; Planaby solo ordena lo que le llega.
struct FocusModeGuideView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                row("iphone", "Lo que hace iOS",
                    "La Concentración Trabajo decide qué apps y personas pueden sonar. Es el único filtro real de notificaciones: Planaby no puede silenciar ni borrar las de otras apps.")
                row("tray.and.arrow.down", "Lo que recibe Planaby",
                    "Solo lo que tú le pasas: los mensajes por la automatización de Atajos y el correo por IMAP. No ve el resto de notificaciones del iPhone.")
                row("sparkles", "Lo que hace Planaby",
                    "Clasifica esa copia (urgente, importante, puede esperar, ruido), enseña lo importante de trabajo mientras te concentras y guarda lo demás para el descanso.")
            } header: {
                Text("Quién hace qué")
            }

            Section {
                step(1, "Abre Ajustes del iPhone › Concentración › Trabajo (si no existe, créala con «+»).")
                step(2, "En «Apps», elige «Permitir notificaciones de» y añade Teams, Outlook y Planaby.")
                step(3, "En «Personas», permite solo a quien de verdad pueda interrumpirte (o a nadie).")
                step(4, "Deja fuera las apps personales (WhatsApp, Instagram, juegos…): quedan silenciadas y las verás al salir de la Concentración.")
                step(5, "En «Filtros de modo de concentración» › «Añadir filtro» › Planaby, elige el plan Trabajo: al activar la Concentración, Planaby cambia de plan solo.")
                step(6, "Opcional: en «Programar», actívala en tu horario de trabajo o al abrir Planaby.")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Abrir Ajustes del iPhone", systemImage: "gear")
                }
            } header: {
                Text("Configurar la Concentración Trabajo")
            } footer: {
                Text("iOS no deja que una app abra directamente la pantalla de Concentración ni la configure por ti: el botón abre los ajustes de Planaby y desde ahí se vuelve atrás hasta «Concentración».")
            }

            Section {
                row("lock.shield", "Todo se queda en el iPhone",
                    "Los mensajes se clasifican en el dispositivo y no se envían a ningún servidor. La contraseña del correo se guarda en el Llavero.")
                row("eye.slash", "En la pantalla bloqueada",
                    "La Live Activity y los widgets solo dicen cuántos pendientes hay («Trabajo · 2 importantes»), nunca quién escribe ni qué dice.")
                row("trash", "Tú decides qué se guarda",
                    "Puedes vaciar la bandeja cuando quieras desde su menú, y quitar la automatización o la cuenta de correo en esta misma pantalla de ajustes.")
            } header: {
                Text("Privacidad")
            }
        }
        .navigationTitle("Concentración Trabajo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.orange)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Theme.orange, in: .circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
