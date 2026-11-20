import SwiftUI

/// Closes Mencal's menu, e.g. before handing off to Calendar.app.
/// StatusItemController supplies it through the environment.
struct DismissMenuAction {
    let run: () -> Void

    func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry var dismissMenu = DismissMenuAction(run: {})
}
