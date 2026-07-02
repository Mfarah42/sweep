import SwiftUI
import WidgetKit

@main
struct SweepWidgetBundle: WidgetBundle {
    var body: some Widget {
        SweepWidget()
        SweepLiveActivity()
    }
}
