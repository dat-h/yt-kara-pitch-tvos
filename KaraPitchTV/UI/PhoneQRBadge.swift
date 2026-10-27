import SwiftUI

/// A small QR code for the phone page with "ADD SONGS" under it, at the right end of the ticker, so
/// phones can open the queue page mid-song. The address itself isn't shown, leaving the ticker room
/// to scroll. Says "No network" while the TV has no address.
struct PhoneQRBadge: View {
    @State private var phoneURL = LocalAddress.phoneURL()
    /// Made only when the address changes, not on every redraw of the player screen.
    @State private var qr = LocalAddress.phoneURL().flatMap(QRCode.image(for:))

    var body: some View {
        VStack(spacing: 6) {
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("QR code for \(phoneURL ?? "")")
            } else {
                Text("No network").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.orange)
            }
            Text("ADD SONGS").font(.system(size: 18, weight: .bold)).kerning(2).foregroundStyle(Theme.pink)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: IdleView.addressRefresh)
                let url = LocalAddress.phoneURL()
                if url != phoneURL {
                    phoneURL = url
                    qr = url.flatMap(QRCode.image(for:))
                }
            }
        }
    }
}
