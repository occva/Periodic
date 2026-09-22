import SwiftUI

private struct AppleIconCacheEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppleIconCache? = nil
}

extension EnvironmentValues {
    var appleIconCache: AppleIconCache? {
        get { self[AppleIconCacheEnvironmentKey.self] }
        set { self[AppleIconCacheEnvironmentKey.self] = newValue }
    }
}
