//
//  SharedConnection+Publisher.swift
//  Endel
//
//  Created by Maxim Smirnov on 07.07.2020.
//  Copyright © 2020 Endel Sound GmbH. All rights reserved.
//

import Combine

public extension AnyPublisher where Failure == Never {
    /// Shorthand method for creating a signal that emits values received from shared data.
    /// - parameter sharedConnectionService: Communication manager instance responsible for receiving data
    /// - parameter sharedDataKey: Key describing expected values.
    /// - parameter policy: Additional modificators applied to received data.
    /// - parameter transform: Closure to perform necessary transformations from shared communication DTO type to expected signal element.
    init<Key: SharedStateKeyProtocol>(
        _ sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        sharedDataFor key: Key,
        policy: Set<SharedConnectionPolicy.Receive> = [],
        transform: @escaping (Key.Value) -> Output)
    {
        self = Empty<Output, Never>(completeImmediately: false)
            .receiveSharedData(from: sharedConnectionService, key: key, policy: policy, transform: transform)
    }

    /// Shorthand method for creating a signal that emits values received from shared data.
    /// - parameter sharedConnectionService: Communication manager instance responsible for receiving data
    /// - parameter sharedDataKey: Key describing expected values.
    /// - parameter policy: Additional modificators applied to received data.
    init<Key: SharedStateKeyProtocol>(
        _ sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        sharedDataFor key: Key,
        policy: Set<SharedConnectionPolicy.Receive> = []) where Key.Value == Output
    {
        self.init(sharedConnectionService, sharedDataFor: key, policy: policy, transform: { $0 })
    }
}

public extension Publisher where Failure == Never {

    /// Observe shared data update for specified key.
    /// - parameter sharedConnectionService: Communication manager instance responsible for receiving data
    /// - parameter key: Key describing expected values.
    /// - parameter policy: Additional modificators applied to received data.
    /// - parameter transform: Closure to perform necessary transformations from shared communication DTO type to expected signal element.
    ///
    /// - returns: Combined signal of upstream elements merged with elements received from the counterpart app.
    func receiveSharedData<Key: SharedStateKeyProtocol>(
        from sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        key: Key,
        policy: Set<SharedConnectionPolicy.Receive> = [],
        transform: @escaping (Key.Value) -> Output) -> AnyPublisher<Output, Failure>
    {
        return sharedConnectionService
            .receiveSharedValues(for: key, policy: policy, transform: transform)
            .merge(with: self)
            .eraseToAnyPublisher()
    }

    /// Observe shared data update for specified key.
    /// - parameter sharedConnectionService: Communication manager instance responsible for receiving data
    /// - parameter key: Key describing expected values.
    /// - parameter policy: Additional modificators applied to received data.
    ///
    /// - returns: Combined signal of upstream elements merged with elements received from the counterpart app.
    func receiveSharedData<Key: SharedStateKeyProtocol>(
        from sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        key: Key,
        policy: Set<SharedConnectionPolicy.Receive> = []
    ) -> AnyPublisher<Output, Failure> where Key.Value == Output
    {
        return receiveSharedData(key: key, policy: policy, transform: { $0 })
    }
    
    /// Send shared data updates for specified key.
    /// - parameter sharedConnectionService: Communication manager instance responsible for sending data
    /// - parameter key: Key describing values being sent through the communication interface.
    /// - parameter origin: Determines wheter to send data depending on running platform.
    /// - parameter policy: Additional modificators applied to data to be sent.
    /// - parameter transform: Closure to perform necessary transformations from upstream signal element to shared communication DTO object.
    ///
    /// - returns: Unaltered upstream signal.
    func provideSharedData<Key: SharedStateKeyProtocol>(
        into sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        key: Key,
        origin: SharedConnectionPolicy.Provide.Origin,
        policy: Set<SharedConnectionPolicy.Provide> = [],
        transform: @escaping (Output) -> Key.Value) -> AnyPublisher<Output, Failure>
    {
        return sharedConnectionService.provideSharedData(key: key, signal: self, origin: origin,
                                                         policy: policy, transform: transform)
    }

    /// Send shared data updates for specified key.
    /// - parameter sharedConnectionService: Communication manager instance responsible for sending data
    /// - parameter key: Key describing values being sent through the communication interface.
    /// - parameter origin: Determines wheter to send data depending on running platform.
    /// - parameter policy: Additional modificators applied to data to be sent.
    ///
    /// - returns: Unaltered upstream signal.
    func provideSharedData<Key: SharedStateKeyProtocol>(
        into sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        key: Key,
        origin: SharedConnectionPolicy.Provide.Origin,
        policy: Set<SharedConnectionPolicy.Provide> = []) -> AnyPublisher<Output, Failure> where Output == Key.Value
    {
        return provideSharedData(key: key, origin: origin, policy: policy, transform: { $0 })
    }

    /// Sync shared data updates for specified key.
    /// - parameter sharedConnectionService: Communication manager instance responsible for sync data.
    /// - parameter key: Key describing values being sync through the communication interface.
    /// - parameter origin: Determines wheter to sync data depending on running platform.
    /// - parameter receivePolicy: Additional modificators applied to received data.
    /// - parameter providePolicy: Additional modificators applied to data to be sent.
    /// - parameter transform: Closure to perform necessary transformations from upstream signal element to shared communication DTO object.
    ///
    /// - returns: Received/provided values signal.
    func syncSharedData<Key: SharedStateKeyProtocol>(
        into sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        key: Key,
        origin: SharedConnectionPolicy.Provide.Origin,
        receivePolicy: Set<SharedConnectionPolicy.Receive> = [],
        providePolicy: Set<SharedConnectionPolicy.Provide> = [],
        transform: @escaping (Output) -> Key.Value) -> AnyPublisher<Key.Value, Failure>
    {
        return sharedConnectionService.syncSharedData(key: key,
                                                      signal: self,
                                                      origin: origin,
                                                      receivePolicy: receivePolicy,
                                                      providePolicy: providePolicy,
                                                      transform: transform)
    }
    
    /// Sync shared data updates for specified key.
    /// - parameter sharedConnectionService: Communication manager instance responsible for sync data.
    /// - parameter key: Key describing values being sync through the communication interface.
    /// - parameter origin: Determines wheter to sync data depending on running platform.
    /// - parameter receivePolicy: Additional modificators applied to received data.
    /// - parameter providePolicy: Additional modificators applied to data to be sent.
    ///
    /// - returns: Received/provided values signal.
    func syncSharedData<Key: SharedStateKeyProtocol>(
        into sharedConnectionService: SharedConnectionService = SharedConnectionManager.shared,
        key: Key,
        origin: SharedConnectionPolicy.Provide.Origin,
        receivePolicy: Set<SharedConnectionPolicy.Receive> = [],
        providePolicy: Set<SharedConnectionPolicy.Provide> = []) -> AnyPublisher<Key.Value, Failure> where Output == Key.Value
    {
        return syncSharedData(into: sharedConnectionService, key: key, origin: origin,
                              receivePolicy: receivePolicy, providePolicy: providePolicy,
                              transform: { $0 })
    }
}
