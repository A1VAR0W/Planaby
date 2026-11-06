import SwiftUI
import WidgetKit

@main
struct PlanabyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusWidget()
        AgendaWidget()
        FocusLiveActivity()
        FocusControl()
        CaptureControl()
    }
}
