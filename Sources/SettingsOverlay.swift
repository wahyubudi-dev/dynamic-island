import SwiftUI

struct SettingsOverlay: View {
    @ObservedObject var state: IslandState
    let actions: IslandActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dynamic Island")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Now playing · Clock · Drop zone")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                GlassIconButton(systemName: "xmark", size: 9, help: "Close") {
                    state.showSettings = false
                }
            }

            Toggle(isOn: $state.pinned) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep expanded")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Stay open when the pointer leaves")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack(spacing: 8) {
                Label("Scroll horizontally to switch features", systemImage: "arrow.left.and.right")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Button(action: actions.quit) {
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.1)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16 + state.notchInset)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.045, green: 0.045, blue: 0.052))
        .contentShape(Rectangle())
    }
}
