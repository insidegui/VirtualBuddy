import SwiftUI
import BuddyKit

struct VirtualBuddyMonoIcon: View {
    var size: Double = 90
    var style: VirtualBuddyMonoStyle = .default

    var resource: ImageResource {
        switch style {
        case .default: .virtualBuddyMono
        case .success: .virtualBuddyMonoHappy
        case .failure: .virtualBuddyMonoSad
        }
    }

    var body: some View {
        Image(resource)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
