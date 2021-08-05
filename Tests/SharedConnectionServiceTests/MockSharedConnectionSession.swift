//
//  MockSharedConnectionSession.swift
//  EndelWatch Extension
//
//  Created by Igor Skovorodkin on 27.07.2021.
//  Copyright © 2021 Endel. All rights reserved.
//

import Foundation
import Combine
import SharedConnectionService

class MockSharedConnectionSession: SharedConnectionSession {
    var isPaired: Bool? { true }

    var isSupported: Bool { true }

    let isCounterpartReachable: CurrentValueSubject<Bool, Never>
    let receivedMessage: PassthroughSubject<SharedData, Never>
    let sentMessage: PassthroughSubject<SharedData, Never>

    init(isCounterpartReachable: CurrentValueSubject<Bool, Never>,
         receivedMessage: PassthroughSubject<SharedData, Never>,
         sentMessage: PassthroughSubject<SharedData, Never>)
    {
        self.isCounterpartReachable = isCounterpartReachable
        self.receivedMessage = receivedMessage
        self.sentMessage = sentMessage
    }

    func send(sharedData: SharedData) {
        sentMessage.send(sharedData)
    }
}
