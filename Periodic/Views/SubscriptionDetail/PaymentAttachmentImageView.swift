import AppKit
import SwiftUI

struct PaymentAttachmentImageView: View {
    @Environment(AppServices.self) private var services

    let reference: String
    let maximumSize: CGSize?

    @State private var image: NSImage?
    @State private var didFail = false

    init(reference: String, maximumSize: CGSize? = nil) {
        self.reference = reference
        self.maximumSize = maximumSize
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: fittedSize(for: image)?.width,
                        height: fittedSize(for: image)?.height
                    )
            } else if didFail {
                Text("无法显示截图")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: reference) {
            image = nil
            didFail = false
            do {
                let data = try await services.paymentAttachmentStore.data(for: reference)
                guard let loadedImage = NSImage(data: data) else {
                    didFail = true
                    return
                }
                image = loadedImage
            } catch {
                didFail = true
            }
        }
    }

    private func fittedSize(for image: NSImage) -> CGSize? {
        guard let maximumSize,
              image.size.width > 0,
              image.size.height > 0 else { return nil }
        let scale = min(
            maximumSize.width / image.size.width,
            maximumSize.height / image.size.height
        )
        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }
}
