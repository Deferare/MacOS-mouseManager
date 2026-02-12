import Foundation

final class EventTapRunLoopHost {
    private let stateLock = NSLock()
    private let readySemaphore = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?
    private var keepAliveSource: CFRunLoopSource?
    private lazy var thread: Thread = {
        let thread = Thread { [weak self] in
            self?.threadMain()
        }
        thread.name = "mousemanager.eventtap.runloop"
        thread.qualityOfService = .userInteractive
        return thread
    }()

    init() {
        thread.start()
        readySemaphore.wait()
    }

    deinit {
        stop()
    }

    func addSource(_ source: CFRunLoopSource) {
        performOnRunLoop { runLoop in
            CFRunLoopAddSource(runLoop, source, .commonModes)
        }
    }

    func removeSource(_ source: CFRunLoopSource) {
        performOnRunLoop { runLoop in
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
    }

    private func stop() {
        performOnRunLoop { runLoop in
            CFRunLoopStop(runLoop)
        }
    }

    private func performOnRunLoop(_ block: @escaping (CFRunLoop) -> Void) {
        stateLock.lock()
        let currentRunLoop = runLoop
        stateLock.unlock()

        guard let currentRunLoop else { return }
        CFRunLoopPerformBlock(currentRunLoop, CFRunLoopMode.commonModes.rawValue) {
            block(currentRunLoop)
        }
        CFRunLoopWakeUp(currentRunLoop)
    }

    private func threadMain() {
        autoreleasepool {
            let currentRunLoop = CFRunLoopGetCurrent()

            var sourceContext = CFRunLoopSourceContext()
            sourceContext.version = 0
            let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext)
            if let keepAlive {
                keepAliveSource = keepAlive
                CFRunLoopAddSource(currentRunLoop, keepAlive, .commonModes)
            }

            stateLock.lock()
            runLoop = currentRunLoop
            stateLock.unlock()
            readySemaphore.signal()
            CFRunLoopRun()

            if let keepAliveSource {
                CFRunLoopRemoveSource(currentRunLoop, keepAliveSource, .commonModes)
            }
            keepAliveSource = nil

            stateLock.lock()
            runLoop = nil
            stateLock.unlock()
        }
    }
}
