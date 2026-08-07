import SwiftUI

struct AddServerView: View {
    @Environment(ServerStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var isChecking = false
    @State private var errorMessage: String?

    private var normalized: String {
        ServerStore.normalize(host)
    }

    private var isValidFormat: Bool {
        normalized.range(of: "^([a-z0-9-]+\\.)+[a-z]{2,}$", options: .regularExpression) != nil
    }

    private var alreadyExists: Bool {
        servers.contains(host: normalized)
    }

    private var canAdd: Bool {
        isValidFormat && !alreadyExists && !isChecking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("example.com", text: $host)
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .onSubmit {
                            if canAdd { Task { await addServer() } }
                        }
                } footer: {
                    footerView
                }
            }
            .navigationTitle("Add Server")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
#if os(macOS)
            .formStyle(.grouped)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task { await addServer() }
                        }
                        .disabled(!canAdd)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if alreadyExists {
                Text("This server is already in your list.")
                    .foregroundStyle(.orange)
            } else {
                Text("Enter a booru domain. We'll verify it supports a known API (Moebooru, Danbooru, or Gelbooru) before adding it.")
            }
        }
        .font(.footnote)
    }

    private func addServer() async {
        guard canAdd else { return }
        errorMessage = nil
        isChecking = true
        defer { isChecking = false }

        do {
            let flavor = try await BooruServerProbe.detectFlavor(host: normalized)
            servers.add(host: normalized, flavor: flavor)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddServerView()
        .environment(ServerStore.shared)
}
