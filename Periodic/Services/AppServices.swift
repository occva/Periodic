import Observation

/// App-wide dependencies. Window selection and presentation state stay in views.
@MainActor
@Observable
final class AppServices {
    let persistence: PersistenceController

    init(persistence: PersistenceController = PersistenceController()) {
        self.persistence = persistence
    }
}
