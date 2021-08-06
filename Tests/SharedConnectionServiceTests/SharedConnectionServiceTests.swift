import XCTest
import Combine
@testable import SharedConnectionService

final class SharedConnectionServiceTests: XCTestCase {

    var manager: SharedConnectionService!

    var isCounterpartReachable: CurrentValueSubject<Bool, Never>!
    var receivedMessage: PassthroughSubject<SharedData, Never>!
    var sentMessage: PassthroughSubject<SharedData, Never>!

    let key = SharedStateKey<Bool>(identifier: "test")
    var cancellables: Set<AnyCancellable> = []

    var sentMessages: [Bool] = []

    var signal: PassthroughSubject<Bool, Never>!

    override func setUp() {
        cancellables = []
        isCounterpartReachable = .init(true)
        receivedMessage = .init()
        sentMessage = .init()
        signal = .init()
        sentMessages = []

        let session = MockSharedConnectionSession(isCounterpartReachable: isCounterpartReachable,
                                                  receivedMessage: receivedMessage,
                                                  sentMessage: sentMessage)
        manager = SharedConnectionManager(sharedSession: session)

        sentMessage
            .compactMap { [key] in key.value(from: $0) }
            .sink(receiveValue: { [weak self] in
                self?.sentMessages.append($0)
            })
            .store(in: &cancellables)
    }

    // MARK: Provide

    func testProvidePolicyRemoveDuplicates() {
        manager.provideSharedData(key: key, signal: signal, origin: .both,
                                  policy: [.removeDuplicates], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        // Send same value multiple times
        signal.send(true)
        signal.send(true)

        // Only one message should be sent
        XCTAssertEqual(sentMessages, [true])
    }

    func testProvideReachability() {
        // Disable connection
        isCounterpartReachable.send(false)

        manager.provideSharedData(key: key, signal: signal, origin: .both,
                                  policy: [], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        signal.send(false)
        signal.send(true)

        // Don't send messages when reachbility disabled
        XCTAssertEqual(sentMessages, [])

        // Enable connection
        isCounterpartReachable.send(true)

        // Try to send latest value
        XCTAssertEqual(sentMessages, [true])
    }

    func testProvidePolicyIgnoreReachability() {
        // Disable connection
        isCounterpartReachable.send(false)

        manager.provideSharedData(key: key, signal: signal, origin: .both,
                                  policy: [.ignoreReachability], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        signal.send(true)

        // Enable connection
        isCounterpartReachable.send(true)

        // Sent values must be ignored
        XCTAssertEqual(sentMessages, [])
    }

    func testProvidePassSent() {
        var passMessages: [Bool] = []

        manager.provideSharedData(key: key, signal: signal, origin: .both,
                                  policy: [], transform: { $0 })
            .sink { passMessages.append($0) }
            .store(in: &cancellables)

        signal.send(true)
        signal.send(false)

        XCTAssertEqual(passMessages, [true, false])
    }

    func testProvidePolicyBlockSent() {
        var passMessages: [Bool] = []

        manager.provideSharedData(key: key, signal: signal, origin: .both,
                                  policy: [.blockSent], transform: { $0 })
            .sink { passMessages.append($0) }
            .store(in: &cancellables)

        signal.send(true)
        signal.send(false)

        XCTAssertEqual(passMessages, [])
    }

    func testProvidePolicyDropFirst() {
        manager.provideSharedData(key: key, signal: signal, origin: .both,
                                  policy: [.dropFirstOnPhone], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        // Send first value
        signal.send(false)

        // Reachability recovered
        isCounterpartReachable.send(false)
        isCounterpartReachable.send(true)

        // All values above should be ignored
        XCTAssertEqual(sentMessages, [])

        // Send second value
        signal.send(false)

        // Second value should be sent
        XCTAssertEqual(sentMessages, [false])
    }

    func testOriginShouldPass() {
        #if os(watchOS)
        let origin: SharedConnectionPolicy.Provide.Origin = .watch
        #else
        let origin: SharedConnectionPolicy.Provide.Origin = .phone
        #endif

        manager.provideSharedData(key: key, signal: signal, origin: origin,
                                  policy: [], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        signal.send(true)

        // Messages should be pass by origin policy
        XCTAssertEqual(sentMessages, [true])
    }

    func testOriginShouldBlocked() {
        #if os(watchOS)
        let origin: SharedConnectionPolicy.Provide.Origin = .phone
        #else
        let origin: SharedConnectionPolicy.Provide.Origin = .watch
        #endif

        manager.provideSharedData(key: key, signal: signal, origin: origin,
                                  policy: [], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        signal.send(true)

        // Messages should be blocked by origin policy
        XCTAssertEqual(sentMessages, [])
    }

    // MARK: Receive

    func testReceive() {
        var receivedMessages: [Bool] = []

        manager.receiveSharedValues(for: key, policy: [], transform: { $0 })
            .sink { receivedMessages.append($0) }
            .store(in: &cancellables)

        receivedMessage.send(SharedValue(key: key, value: false)!.sharedData)
        receivedMessage.send(SharedValue(key: key, value: true)!.sharedData)

        XCTAssertEqual(receivedMessages, [false, true])
    }

    // MARK: Sync

    func testSync() {
        manager.syncSharedData(key: key, signal: signal, origin: .both,
                               receivePolicy: [], providePolicy: [.blockSent], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        // Simulate value received from companion
        receivedMessage.send(SharedValue(key: key, value: false)!.sharedData)
        // Pass same value locally
        signal.send(false)

        // Don't send received value back
        XCTAssertEqual(sentMessages, [])
    }

    func testSyncReachability() {
        // Disable connection
        isCounterpartReachable.send(false)

        manager.syncSharedData(key: key, signal: signal, origin: .both,
                               receivePolicy: [], providePolicy: [], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        signal.send(false)
        signal.send(true)

        // Don't send messages when reachbility disabled
        XCTAssertEqual(sentMessages, [])

        // Enable connection
        isCounterpartReachable.send(true)

        // Try to send latest value
        XCTAssertEqual(sentMessages, [true])
    }

    func testSyncPolicyDropFirst() {
        manager.syncSharedData(key: key, signal: signal, origin: .both, receivePolicy: [],
                               providePolicy: [.dropFirstOnPhone], transform: { $0 })
            .sink { _ in }
            .store(in: &cancellables)

        // Send first value
        signal.send(false)

        // Reachability recovered
        isCounterpartReachable.send(false)
        isCounterpartReachable.send(true)

        // Reachability recovered
        isCounterpartReachable.send(false)
        isCounterpartReachable.send(true)

        // Value should be ignored
        XCTAssertEqual(sentMessages, [])

        // Simulate value received from companion
        receivedMessage.send(SharedValue(key: key, value: true)!.sharedData)

        // Send first value duplicate
        signal.send(false)

        // Value should be sent
        XCTAssertEqual(sentMessages, [false])
    }
}

private extension SharedStateKey {
    func value(from sharedData: SharedData) -> Value? {
        guard
            sharedData.identifier == self.identifier,
            let data = sharedData.data
        else { return nil }

        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
