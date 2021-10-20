//
//  SharedConnectionSession.swift
//  EndelWatch Extension
//
//  Created by Igor Skovorodkin on 27.07.2021.
//  Copyright © 2021 Endel. All rights reserved.
//

import Foundation
import Combine

public protocol SharedConnectionSession {
    #if os(iOS)
    var isPaired: Bool? { get }
    #endif

    var isSupported: Bool { get }

    var isCounterpartReachable: CurrentValueSubject<Bool, Never> { get }

    var receivedMessage: PassthroughSubject<SharedData, Never> { get }

    func send(sharedData: SharedData)
}

#if canImport(WatchConnectivity)

import WatchConnectivity

public class WatchConnectivitySession: NSObject, SharedConnectionSession {

    public static let shared = WatchConnectivitySession()
    
    /// Message Payload size limit in bytes.
    static let messagePayloadSizeLimit = 65000

    private(set) var session: WCSession?

    /// Timer that should check an actual reachabilty state of the associated WCSession and sync it with `_isReachable` property.
    /// - note: Session delegate with its events is simultaneously used for the same purpose but unfortunately it's a bit buggy so we may not receive all reachablity change events.
    private var sessionReachabilityCheckTimer: Timer?
    private var cancellabes: Set<AnyCancellable> = []
    private let fileManager: FileManager
    private let configuration: Configuration

    public let isCounterpartReachable: CurrentValueSubject<Bool, Never>
    public let receivedMessage: PassthroughSubject<SharedData, Never>

    #if os(iOS)
    public var isPaired: Bool? {
        session?.activationState == .activated ? session?.isPaired : nil
    }
    #endif

    public var isSupported: Bool {
        WCSession.isSupported()
    }

    public init(configuration: Configuration = .init(),
                fileManager: FileManager = .default)
    {
        self.configuration = configuration
        self.fileManager = fileManager
        self.isCounterpartReachable = .init(false)
        self.receivedMessage = .init()

        super.init()

        // Try to assign activate WCSession
        guard WCSession.isSupported() else {
            print("SharedConnectionManager is running on unsupported device.")
            isCounterpartReachable.value = false
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()

        isCounterpartReachable.value = session?.isReachable ?? false

        // Setup session reachability check timer
        sessionReachabilityCheckTimer = Timer.scheduledTimer(withTimeInterval: configuration.sessionReachabilityCheckInterval,
                                                             repeats: true)
        { _ in
            // Only if local and session's isReachable property are not synced and session's value is true
            guard !self.isCounterpartReachable.value, self.session?.isReachable ?? false else { return }
            self.isCounterpartReachable.value = self.session?.isReachable ?? false
        }

        // MARK: Bindings

        // Activate session when a counterpart becomes reachable if needed
        isCounterpartReachable
            .removeDuplicates()
            .filter { $0 }
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }

                if self.session?.activationState != .activated {
                    self.session?.activate()
                }
            })
            .store(in: &cancellabes)
    }

    func activate() {
        if session?.activationState != .activated {
            session?.activate()
        }
    }
}

// MARK: WCSessionDelegate

extension WatchConnectivitySession: WCSessionDelegate {
    // These methods can be implemented only on iOS
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        print("SharedConnectionManager: WCSession sessionDidBecomeInactive")
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // Begin the activation process for the new Apple Watch
        self.session?.activate()
        print("SharedConnectionManager: WCSession sessionDidDeactivate")
    }
    #endif

    public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?)
    {
        print("SharedConnectionManager: WCSession activation state:", activationState.rawValue)
        if let error = error { print("SharedConnectionManager: WCSession activationDidCompleteWith error: ", error.localizedDescription) }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        isCounterpartReachable.value = session.isReachable
    }

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let sharedData = try? JSONDecoder().decode(SharedData.self, from: messageData) else {
            print("SharedConnection Message Received: Can't create shared data")
            return
        }
//        print("%%% SharedConnectionService didReceiveMessage for key \(sharedData.identifier)")
        receivedMessage.send(sharedData)
    }

    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error { print("SharedConnection File Transfer: \(error.localizedDescription)") }

        let fileUrl = fileTransfer.file.fileURL
        // Delete cached files after transfer
        guard fileUrl.path.contains(configuration.cachedFileNamePrefix) else { return }
        do {
            try fileManager.removeItem(at: fileTransfer.file.fileURL)
        } catch {
            print(error.localizedDescription)
        }
    }

    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.fileURL.path.contains(configuration.cachedFileNamePrefix) else { return }

        do {
            let data = try Data(contentsOf: file.fileURL)
            guard let sharedData = try? JSONDecoder().decode(SharedData.self, from: data) else {
                print("SharedConnection File Received: Can't create shared data")
                return
            }
            receivedMessage.send(sharedData)
        } catch {
            print("SharedConnection File Received: \(error.localizedDescription)")
        }
    }
}

public extension WatchConnectivitySession {
    /// Send given shared data to the counterpart.
    func send(sharedData: SharedData) {
        guard let data = try? JSONEncoder().encode(sharedData) else {
            print("Shared Connection Manager: Can't create data to Send Message/File")
            return
        }
        let size = data.count
        // Send message if payload fits into size limit, otherwise create and send file

        if size < Self.messagePayloadSizeLimit {
            self.session?.sendMessageData(data, replyHandler: nil) { error in
                print("Shared Connection Manager: Send Message error: \(error.localizedDescription)")
            }
        } else {
            do {
                let cachesDir = try self.fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let fileName = "\(configuration.cachedFileNamePrefix)\(sharedData.identifier).json"
                let fileUrl = cachesDir.appendingPathComponent(fileName)
                try data.write(to: fileUrl)
                self.session?.transferFile(fileUrl, metadata: nil)
            } catch {
                print("Shared Connection Manager: Send file error: \(error.localizedDescription)")
            }
        }
    }
}

public extension WatchConnectivitySession {
    /// Shared connection manager configuration.
    struct Configuration {
        /// An interval to check the WCSession reachability.
        let sessionReachabilityCheckInterval: Double
        /// Prefix for shared values cached as files.
        let cachedFileNamePrefix: String

        public init(sessionReachabilityCheckInterval: Double = 3.0,
                    cachedFileNamePrefix: String = "shared-cache-")
        {
            self.sessionReachabilityCheckInterval = sessionReachabilityCheckInterval
            self.cachedFileNamePrefix = cachedFileNamePrefix
        }
    }
}

#endif

/// Shared Connection session without actual implementation.
public class StabSharedConnectionSession: SharedConnectionSession {
    #if os(iOS)
    public var isPaired: Bool? = false
    #endif
    
    public var isSupported: Bool = false
    public var isCounterpartReachable: CurrentValueSubject<Bool, Never> = .init(false)
    public var receivedMessage: PassthroughSubject<SharedData, Never> = .init()
    
    public func send(sharedData: SharedData) { return }
}
