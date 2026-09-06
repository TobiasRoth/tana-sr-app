import SwiftUI

struct RootView: View {
    private let client = DropboxClient()
    @State private var isConnected: Bool?

    var body: some View {
        Group {
            switch isConnected {
            case .none:
                ProgressView()
            case .some(false):
                ConnectDropboxView(client: client) {
                    isConnected = true
                }
            case .some(true):
                StudySessionView(store: DropboxCardStore(client: client))
            }
        }
        .task {
            isConnected = await client.isAuthenticated
        }
    }
}

#Preview {
    RootView()
}
