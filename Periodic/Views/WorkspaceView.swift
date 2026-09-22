import SwiftUI

struct WorkspaceView: View {
    var body: some View {
        ContentUnavailableView("暂无内容", systemImage: "square.grid.2x2")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("workspace-placeholder")
    }
}
