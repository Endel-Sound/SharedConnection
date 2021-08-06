//
//  SharedConnectionService.swift
//  EndelWatch Extension
//
//  Created by Vyacheslav Dubovitsky on 20/05/2018.
//  Copyright © 2018 Endel. All rights reserved.
//

import Combine

#if canImport(WatchConnectivity)

/// Additional options for shared data communication.
public enum SharedConnectionPolicy {
    /// Options to apply to data to be sent.
    public enum Provide {
        /// Disable duplicate values to be sent via WatchConnect session.
        ///
        /// By default duplicate values are allowed, so if two upstream values result in the same shared data update, every instance will be sent.
        /// Set this policy if only first value need to be sent.
        case removeDuplicates
        
        /// Disable automatic resend latest provided value when reachability changed to active.
        case ignoreReachability

        /// Block sent value locally.
        case blockSent

        /// Ignore first value on watch origin.
        case dropFirstOnWatch

        /// Ignore first value on phone origin.
        case dropFirstOnPhone
    }

    /// Options to apply when new shared data is received.
    public enum Receive: Hashable {
    }
}

extension SharedConnectionPolicy.Provide {
    /// Policy to control communication direction.
    /// Depending on current platform `provideSharedData` operator will either send data to the counterpart app or work as passthrough.
    public enum Origin {
        /// Only send data when running watch app.
        case watch
        /// Only send data when running ios app.
        case phone
        /// Send data in both directions.
        case both

        /// For unified managers, decide whether to send updates to shared state or not, depending on current platform.
        public var shouldProvideValue: Bool {
            switch self {
            case .watch:
                #if os(watchOS)
                return true
                #else
                return false
                #endif
            case .phone:
                #if os(watchOS)
                return false
                #else
                return true
                #endif
            case .both:
                return true
            }
        }
    }
}

/// Protocol describing key for shared state communication.
/// Key should define an associated value type and provide a string for serialization.
public protocol SharedStateKeyProtocol {
    /// The associated type representing the data type of the key's value.
    associatedtype Value: Codable & Equatable

    /// String value of the key itself used for serialization.
    var identifier: String { get }
}

/// Default implementation of `SharedStateKeyProtocol`.
public struct SharedStateKey<T: Codable & Equatable>: SharedStateKeyProtocol {
    /// The associated type representing the data type of the key's value.
    public typealias Value = T
    /// String value of the key itself used for serialization.
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}

public protocol SharedConnectionService {
    #if os(iOS)
    /// I whether the current iPhone is paired to an Apple Watch
    var isPaired: Bool? { get }
    #endif

    /// Receive updates whenever new update for shared value occurs.
    /// - parameter key: Type of key describing expected values.
    /// - parameter policy: Additional modificators applied to received data.
    /// - parameter transform: Closure to perform necessary transformations from shared communication DTO type to expected signal element.
    ///
    /// - returns: Signal emitting values received through WatchConnect interface.
    func receiveSharedValues<Key: SharedStateKeyProtocol, Element>(
        for key: Key,
        policy: Set<SharedConnectionPolicy.Receive>,
        transform: @escaping (Key.Value) -> Element
    ) -> AnyPublisher<Element, Never>

    /// Send shared data updates for specified key.
    /// - parameter key: Type of key describing values being sent through the communication interface.
    /// - parameter signal: Stream of elements that need to be sent through the watch connect interface.
    /// - parameter origin: Determines wheter to send data depending on running platform.
    /// - parameter policy: Additional modificators applied to data to be sent.
    /// - parameter transform: Closure to perform necessary transformations from upstream signal element to shared communication DTO object.
    ///
    /// - returns: Unaltered upstream signal.
    func provideSharedData<Key: SharedStateKeyProtocol, Element, Signal: Publisher>(
        key: Key,
        signal: Signal,
        origin: SharedConnectionPolicy.Provide.Origin,
        policy: Set<SharedConnectionPolicy.Provide>,
        transform: @escaping (Element) -> Key.Value
    ) -> AnyPublisher<Element, Never> where Signal.Output == Element, Signal.Failure == Never
    
    /// Sync shared data updates for specified key.
    /// - parameter key: Type of key describing values being sync through the communication interface.
    /// - parameter signal: Stream of elements that need to be sync through the watch connect interface.
    /// - parameter receivePolicy: Additional modificators applied to received data.
    /// - parameter providePolicy: Additional modificators applied to data to be sent.
    /// - parameter transform: Closure to perform necessary transformations from upstream signal element to shared communication DTO object.
    ///
    /// - returns: Signal emitting values received/provided through WatchConnect interface.
    func syncSharedData<Key: SharedStateKeyProtocol, Element, Signal: Publisher>(
        key: Key,
        signal: Signal,
        origin: SharedConnectionPolicy.Provide.Origin,
        receivePolicy: Set<SharedConnectionPolicy.Receive>,
        providePolicy: Set<SharedConnectionPolicy.Provide>,
        transform: @escaping (Element) -> Key.Value
    ) -> AnyPublisher<Key.Value, Never> where Signal.Output == Element, Signal.Failure == Never
}

#endif
