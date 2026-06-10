import SwiftUI

struct ContentView: View {
    @StateObject private var conn = KnepConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            StreamView(decoder: conn.videoDecoder)
                .ignoresSafeArea()
                .opacity(conn.isConnected ? 1 : 0)

            if !conn.isConnected {
                VStack(spacing: 18) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 56))
                        .foregroundColor(.white.opacity(0.3))

                    Text("knep")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text(conn.statusMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))

                    Text("Run knep on your Mac, then connect\nvia USB-C with iPhone Hotspot (USB)\nor on the same Wi-Fi network")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            conn.start()
            // A second monitor should never auto-lock mid-use.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: conn.pause()
            case .active: conn.resume()
            default: break
            }
        }
    }
}
