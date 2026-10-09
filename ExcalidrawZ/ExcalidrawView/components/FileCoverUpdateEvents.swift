import Combine
import Foundation

/// Route global preview notifications once, then deliver only to that file's
/// covers. The weak channels disappear when their views release the publisher.
@MainActor
final class FileCoverUpdateEvents {
    enum Event: Equatable {
        case refreshRequested
        case imageUpdated
    }

    static let shared = FileCoverUpdateEvents()

    private typealias Channel = PassthroughSubject<Event, Never>
    private let channels = NSMapTable<NSString, Channel>(
        keyOptions: .strongMemory,
        valueOptions: .weakMemory
    )
    private var subscriptions: Set<AnyCancellable> = []

    init(notificationCenter: NotificationCenter = .default) {
        observe(.filePreviewShouldRefresh, event: .refreshRequested, in: notificationCenter)
        observe(.filePreviewDidUpdate, event: .imageUpdated, in: notificationCenter)
    }

    func publisher(for fileID: String) -> AnyPublisher<Event, Never> {
        let key = fileID as NSString
        if let channel = channels.object(forKey: key) {
            return channel.eraseToAnyPublisher()
        }
        let channel = Channel()
        channels.setObject(channel, forKey: key)
        return channel.eraseToAnyPublisher()
    }

    private func observe(
        _ name: Notification.Name,
        event: Event,
        in notificationCenter: NotificationCenter
    ) {
        notificationCenter.publisher(for: name)
            .sink { [weak self] notification in
                guard let fileID = notification.object as? String else { return }
                Task { @MainActor [weak self] in
                    self?.channels.object(forKey: fileID as NSString)?.send(event)
                }
            }
            .store(in: &subscriptions)
    }
}
