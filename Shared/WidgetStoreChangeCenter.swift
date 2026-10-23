import Foundation

private func widgetStoreDidChange(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    let box = Unmanaged<WidgetStoreChangeObserver>.fromOpaque(observer).takeUnretainedValue()
    box.deliver()
}

/// Darwin notification so a widget edit reaches an app process that is still alive.
enum WidgetStoreChangeCenter {
    static let notificationName = "com.queueapp.queue.storeDidChange"

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

final class WidgetStoreChangeObserver {
    var onChange: () -> Void
    private var pointer: UnsafeMutableRawPointer?
    // AddObserver still takes CFString. PostNotification takes CFNotificationName.
    private let name = WidgetStoreChangeCenter.notificationName as CFString

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard pointer == nil else { return }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        self.pointer = pointer
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            widgetStoreDidChange,
            name,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        guard let pointer else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            nil,
            nil
        )
    }

    fileprivate func deliver() {
        DispatchQueue.main.async { [weak self] in
            self?.onChange()
        }
    }
}
