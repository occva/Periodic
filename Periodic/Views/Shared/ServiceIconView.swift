import AppKit
import SwiftUI

struct ServiceIconView: View {
    @Environment(\.appleIconCache) private var iconCache

    let iconResourceName: String?
    let iconURLString: String?
    let fallbackSeed: String
    let size: CGFloat

    @State private var remoteImage: NSImage?
    @State private var isLoadingRemoteImage = false

    var body: some View {
        Group {
            if let iconResourceName {
                if let image = bundledImage(named: iconResourceName) {
                    rendered(image)
                } else {
                    unavailableIcon
                }
            } else if iconURLString != nil {
                if let remoteImage {
                    rendered(remoteImage)
                } else if isLoadingRemoteImage {
                    ProgressView().controlSize(.small)
                } else {
                    unavailableIcon
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.22))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
        .task(id: iconURLString) {
            remoteImage = nil
            isLoadingRemoteImage = false
            guard iconResourceName == nil,
                  let iconURLString,
                  let iconCache else { return }
            isLoadingRemoteImage = true
            defer { isLoadingRemoteImage = false }
            guard let data = try? await iconCache.data(for: iconURLString) else { return }
            remoteImage = NSImage(data: data)
        }
    }

    private func rendered(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
    }

    private var placeholderIcon: some View {
        Image(systemName: PlaceholderSymbolResolver.symbol(for: fallbackSeed))
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundStyle(.secondary)
    }

    private var unavailableIcon: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                Text("?")
                    .font(.system(size: size * 0.46, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
    }

    private func bundledImage(named resourceName: String) -> NSImage? {
        let resource = resourceName as NSString
        let basename = resource.deletingPathExtension
        let fileExtension = resource.pathExtension
        let url = Bundle.main.url(
            forResource: basename,
            withExtension: fileExtension,
            subdirectory: "BuiltinTemplateIcons"
        ) ?? Bundle.main.url(forResource: basename, withExtension: fileExtension)
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}

enum PlaceholderSymbolResolver {
    private static let symbols = [
        "circle.grid.2x2.fill",
        "sparkles",
        "shippingbox.fill",
        "bolt.fill",
        "bookmark.fill",
        "leaf.fill",
        "star.fill",
        "square.stack.3d.up.fill",
        "hexagon.fill",
        "paperplane.fill"
    ]

    static func symbol(for seed: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return symbols[Int(hash % UInt64(symbols.count))]
    }
}
