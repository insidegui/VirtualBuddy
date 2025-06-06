import SwiftUI
import VirtualCore
import BuddyKit

struct BlurHashFullBleedBackground: View {
    var blurHash: BlurHashToken?

    init(_ blurHash: BlurHashToken?) {
        self.blurHash = blurHash
    }

    init(_ blurHashValue: String?) {
        self.blurHash = blurHashValue.flatMap { BlurHashToken(value: $0) }
    }

    var body: some View {
        if let blurHash {
            Image(blurHash: blurHash)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 22, opaque: true)
                .saturation(1.3)
                .contrast(0.8)
                .brightness(-0.1)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.linear(duration: 2.5), value: blurHash)
                .drawingGroup(opaque: true)
        }
    }
}

#if DEBUG
extension BlurHashToken {
    static let previewSequoia = BlurHashToken(value: "eN86q8M1Hbyya7t-g$MpnTx,b;k9X8Vgr?osbHenWEeYoGj@aNaPah")
    static let previewSonoma = BlurHashToken(value: "ec8rzYaIWBj?a}iqosaxj?fkRFa2axayj[t%ofV[ayf6V]pGkBf5fi")
    static let previewVentura = BlurHashToken(value: "enHk%=ocoeW:Nb-8xEODaya#1fWWJAWExDEjR-jGazoJWCagw^s-Wp")

}
@available(macOS 14.0, *)
#Preview {
    @Previewable @State var token = BlurHashToken.previewSequoia

    BlurHashFullBleedBackground(token)
        .task {
            let enableCycle = false

            guard enableCycle else { return }

            func cycle() async {
                let delay = 3

                try? await Task.sleep(for: .seconds(delay))

                token = .previewSequoia

                try? await Task.sleep(for: .seconds(delay))

                token = .previewSonoma

                try? await Task.sleep(for: .seconds(delay))

                token = .previewVentura

                try? await Task.sleep(for: .seconds(delay))

                token = .virtualBuddyBackground

                await cycle()
            }

            await cycle()
        }
        .frame(width: 1024, height: 1024)
}
#endif
