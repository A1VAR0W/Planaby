import SwiftUI

/// «Ya tienes algo a esa hora»: avisa antes de guardar algo que coincide con otra cosa, pero
/// deja guardarlo igualmente (tener dos cosas a la vez está permitido; es para organizarse).
private struct OverlapAlert: ViewModifier {
    @Binding var clashes: [OverlapNotice.Clash]
    let confirm: String
    let cancel: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            OverlapNotice.alertTitle,
            isPresented: Binding(get: { !clashes.isEmpty }, set: { if !$0 { clashes = [] } })
        ) {
            Button(confirm, action: onConfirm)
            Button(cancel, role: .cancel) {}
        } message: {
            Text(OverlapNotice.alertMessage(clashes))
        }
    }
}

extension View {
    /// Enseña la alerta mientras `clashes` tenga algo; «confirmar» guarda igualmente.
    func overlapAlert(
        _ clashes: Binding<[OverlapNotice.Clash]>, confirm: String = "Guardar igualmente",
        cancel: String = "Cambiar", onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(OverlapAlert(clashes: clashes, confirm: confirm, cancel: cancel, onConfirm: onConfirm))
    }
}
