//
//  HostAppConnectManager.swift
//  EndelWatch Extension
//
//  Created by Vyacheslav Dubovitsky on 16/05/2018.
//  Copyright © 2018 Endel. All rights reserved.
//

import Foundation
import Combine

/// Type-erased data to share.
public struct SharedData: Codable, Equatable {
    /// Value identifier.
    let identifier: String
    /// Data to share.
    let data: Data?
}

struct SharedValue<Key: SharedStateKeyProtocol>: Codable, Equatable {

    /// Materialized value.
    let value: Key.Value
    /// Encoded value ready to be passed down into WatchConnect.
    let sharedData: SharedData

    /// Initialize with known value, preparing it to be sent into WatchConnect.
    init?(key: Key, value: Key.Value) {
        guard let data = try? JSONEncoder().encode(value) else {
            print("SharedConnection: failed to encode \(value)")
            return nil
        }

        self.value = value
        self.sharedData = .init(identifier: key.identifier, data: data)
    }

    // Initialize with data received from WatchConnect and try to reconstruct required value type.
    init?(key: Key, data: Data?) {
        guard let data = data else { return nil }

        guard let value = try? JSONDecoder().decode(Key.Value.self, from: data) else {
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            print("SharedConnection: failed to decode \(Key.Value.self) from \(jsonString)")
            return nil
        }

        self.value = value
        self.sharedData = .init(identifier: key.identifier, data: data)
    }
}

/// Manages connection between watch and host apps iOS app.
public final class SharedConnectionManager: SharedConnectionService {

    public static let shared = SharedConnectionManager()

    private let sharedSession: SharedConnectionSession

    #if os(iOS)
    public var isPaired: Bool? {
        sharedSession.isPaired
    }
    #endif

    public init(sharedSession: SharedConnectionSession = WatchConnectivitySession.shared) {
        self.sharedSession = sharedSession
    }
}

extension SharedConnectionManager {

    public func receiveSharedValues<Key: SharedStateKeyProtocol, Element>(
        for key: Key,
        policy: Set<SharedConnectionPolicy.Receive>,
        transform: @escaping (Key.Value) -> Element
    ) -> AnyPublisher<Element, Never>
    {
        // If Session is not supported, don't receive any values
        guard sharedSession.isSupported else { return Empty(completeImmediately: false).eraseToAnyPublisher() }

        return sharedSession.receivedMessage
            // Decode message into intermediate representation
            .compactMap { sharedData -> SharedValue<Key>? in
                guard sharedData.identifier == key.identifier else { return nil }
                return SharedValue(key: key, data: sharedData.data)
            }
            // Transform into desired type
            .map { transform($0.value) }
//            .print("%%% received shared data for key \(key.identifier)")
            .eraseToAnyPublisher()
    }

    public func provideSharedData<Key: SharedStateKeyProtocol, Element, Signal: Publisher>(
        key: Key,
        signal: Signal,
        origin: SharedConnectionPolicy.Provide.Origin,
        policy: Set<SharedConnectionPolicy.Provide>,
        transform: @escaping (Element) -> Key.Value
    ) -> AnyPublisher<Element, Never> where Signal.Output == Element, Signal.Failure == Never
    {
        var bag: Set<AnyCancellable> = []

        if
            // If Session is not supported, don't try to send any values
            sharedSession.isSupported,
            // Handle origin policy
            origin.shouldProvideValue
        {
            signal
                // Transform  into intermediate representation
                .map(transform)
                // Apply `dropFirstOnWatch/OnPhone` policy
                .dropFirst(with: policy)
                // Apply `removeDuplicates` policy
                .removeDuplicates(by: { (old, new) -> Bool in
                    guard policy.contains(.removeDuplicates) else { return false }
                    return old == new
                })
                // Handle reachable state
                .map { [weak self] newValue -> AnyPublisher<Key.Value, Never> in
                    guard
                        let self = self,
                        !policy.contains(.ignoreReachability)
                    else { return Just(newValue).eraseToAnyPublisher() }

                    // Replay latest value when watch reachability is established after a break
                    return self.watchDidBecomeReachable
                        .map { _ in newValue }
                        .prepend(newValue)
                        .eraseToAnyPublisher()
                }
                .switchToLatest()
                // Don't send values if counterpart is not reachable right now
                .filter { [weak self] _ in self?.sharedSession.isCounterpartReachable.value == true }
    //            .print("%%% sending shared data for key \(key.identifier)")
                // Encode for WatchConnect transmission and perform send
                .compactMap { SharedValue(key: key, value: $0) }
                .sink(receiveValue: { [weak self] value in
                    guard let self = self else { return }

                    // Send state update into WCSession
                    self.sharedSession.send(sharedData: value.sharedData)
                })
                .store(in: &bag)
        }

        return signal
            // Apply `blockSent` policy
            .map { value -> AnyPublisher<Element, Never> in
                if policy.contains(.blockSent) { return Empty(completeImmediately: false).eraseToAnyPublisher() }

                return Just(value).eraseToAnyPublisher()
            }
            .switchToLatest()
            // Stop providing values after original signal cancelled
            .handleEvents(receiveCancel: {
                bag = []
            })
            .eraseToAnyPublisher()
    }
    
    public func syncSharedData<Key: SharedStateKeyProtocol, Element, Signal: Publisher>(
        key: Key,
        signal: Signal,
        origin: SharedConnectionPolicy.Provide.Origin,
        receivePolicy: Set<SharedConnectionPolicy.Receive>,
        providePolicy: Set<SharedConnectionPolicy.Provide>,
        transform: @escaping (Element) -> Key.Value
    ) -> AnyPublisher<Key.Value, Never> where Signal.Output == Element, Signal.Failure == Never
    {
        // Handle received values
        
        let receiveSignal = receiveSharedValues(for: key,
                                                policy: receivePolicy,
                                                transform: { $0 })
            .share()

        guard origin.shouldProvideValue else { return receiveSignal.eraseToAnyPublisher() }

        var bag: Set<AnyCancellable> = []

        // Handle provided values

        let latestProvidedValue: CurrentValueSubject<Key.Value?, Never> = .init(nil)

        let lastValue: CurrentValueSubject<Key.Value?, Never> = .init(nil)

        receiveSignal
            .map { Optional($0) }
            .merge(with: latestProvidedValue)
            .prepend(nil)
            .sink(receiveValue: {
                lastValue.send($0)
            })
            .store(in: &bag)

        // On reachability restore we need to send last value (can be received or provided)
        // Can't be used restore logic from `provide` method because of this (which resend only latest provided value)
        let lastValueOnReachable: AnyPublisher<Key.Value, Never> = watchDidBecomeReachable
            .map { lastValue.first().eraseToAnyPublisher() }
            .switchToLatest()
            .compactMap { $0 }
            .eraseToAnyPublisher()

        let provideChangedDataSignal = signal
            .map { transform($0) }
            // Apply `dropFirstOnWatch/OnPhone` policy
            .dropFirst(with: providePolicy)
            .flatMap { newValue in
                lastValue.first()
                    .map { (newValue, $0) }
                    .eraseToAnyPublisher()
            }
            .compactMap { (newValue, oldValue) -> Key.Value? in
                // Don't send back received value
                newValue != oldValue ? newValue : nil
            }
            .handleEvents(receiveOutput: {
                latestProvidedValue.send(Optional($0))
            })
            // Force provide last value on reachability changed
            .map { newValue -> AnyPublisher<Key.Value, Never>  in
                lastValueOnReachable
                    .prepend(newValue)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .share()
            .eraseToAnyPublisher()

        let provideSignal = provideSharedData(key: key,
                          signal: provideChangedDataSignal,
                          origin: origin,
                          policy: providePolicy
                            // Use `.ignoreReachability` - because resend values already handled in `provideChangedDataSignal`
                            .union([.ignoreReachability])
                            // Disable `dropFirst` policy because already handled in `provideChangedDataSignal`
                            .subtracting([.dropFirstOnPhone, .dropFirstOnWatch]),
                          transform: { $0 })
            .eraseToAnyPublisher()

        // Return received and provides values

        return receiveSignal
            .merge(with: provideSignal)
            .handleEvents(receiveCancel: {
                bag = []
            })
            .eraseToAnyPublisher()
    }
}

private extension SharedConnectionManager {
    /// Signal that emits when shared connection reachability established after it was lost.
    /// On iOS it is used to resend last state after watch reconnect. On watchOS it does nothing.
    var watchDidBecomeReachable: AnyPublisher<Void, Never> {
        #if os(iOS)
        return sharedSession.isCounterpartReachable
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .map { _ in () }
            .eraseToAnyPublisher()
        #else
        return Empty(completeImmediately: false).eraseToAnyPublisher()
        #endif
    }
}

private extension Publisher {
    /// Apply `dropFirstOnWatch/OnPhone` policy.
    func dropFirst(with policy: Set<SharedConnectionPolicy.Provide>) -> Publishers.Drop<Self> {
        // Compute drop count for `dropFirstOnWatch/OnPhone` policy
        #if os(watchOS)
        let dropFirstCount = policy.contains(.dropFirstOnWatch) ? 1 : 0
        #else
        let dropFirstCount = policy.contains(.dropFirstOnPhone) ? 1 : 0
        #endif

        return self.dropFirst(dropFirstCount)
    }
}
