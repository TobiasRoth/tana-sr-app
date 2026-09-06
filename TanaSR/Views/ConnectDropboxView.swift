import SwiftUI

/// Einmaliger Setup-Schritt: Refresh-Token aus authorize_dropbox.py (Mac) einfuegen.
/// Kein In-App-OAuth-Flow -- der Token wird einmal auf dem Mac erzeugt und hier
/// nur eingefuegt, analog zu save_tana_token.py auf der Mac-Seite.
struct ConnectDropboxView: View {
    let client: DropboxClient
    let onConnected: () -> Void

    @State private var tokenInput = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Mit Dropbox verbinden")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Refresh-Token von deinem Mac einfügen (aus authorize_dropbox.py, gespeichert unter ~/.tana-sr/dropbox_credentials.json).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("Refresh-Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await connect() }
            } label: {
                if isValidating {
                    ProgressView()
                } else {
                    Text("Verbinden")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(tokenInput.isEmpty || isValidating)
        }
        .padding()
    }

    private func connect() async {
        isValidating = true
        errorMessage = nil
        await client.connect(refreshToken: tokenInput)
        do {
            _ = try await client.download(path: "/cards.json")
            onConnected()
        } catch {
            errorMessage = "Verbindung fehlgeschlagen: \(error.localizedDescription)"
            await client.disconnect()
        }
        isValidating = false
    }
}
