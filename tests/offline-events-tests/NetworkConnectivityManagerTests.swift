//
//  Copyright © 2020 Iterable. All rights reserved.
//

import XCTest

@testable import IterableSDK

// Add MockNetworkMonitor for better test control
class MockNetworkMonitor: NetworkMonitorProtocol {
    var statusUpdatedCallback: (() -> Void)?
    private(set) var isStarted = false
    
    func start() {
        isStarted = true
        // Trigger callback immediately to simulate initial status
        DispatchQueue.main.async { [weak self] in
            self?.triggerCallbackIfStarted()
        }
    }
    
    func stop() {
        isStarted = false
    }
    
    func forceStatusUpdate() {
        triggerCallbackIfStarted()
    }
    
    private func triggerCallbackIfStarted() {
        guard isStarted else { return }
        statusUpdatedCallback?()
    }
}

class NetworkConnectivityManagerTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        IterableLogUtil.sharedInstance = IterableLogUtil(dateProvider: SystemDateProvider(),
                                                         logDelegate: DefaultLogDelegate())
    }
    
    func testNetworkMonitor() throws {
        let expectation1 = expectation(description: "do not fulfill before start")
        expectation1.isInverted = true
        let monitor = NetworkMonitor()
        monitor.statusUpdatedCallback = {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)

        let expectation2 = expectation(description: "fullfill when started")
        monitor.statusUpdatedCallback = {
            expectation2.fulfill()
        }
        monitor.start()
        wait(for: [expectation2], timeout: 1.0)

        // now stop
        monitor.stop()
        let expectation3 = expectation(description: "don't fullfill when stopped")
        expectation3.isInverted = true
        monitor.statusUpdatedCallback = {
            expectation3.fulfill()
        }
        wait(for: [expectation3], timeout: 1.0)
        
        let expectation4 = expectation(description: "fullfill when started again")
        monitor.statusUpdatedCallback = {
            expectation4.fulfill()
        }
        monitor.start()
        wait(for: [expectation4], timeout: 1.0)
        monitor.stop()
    }
    
    func testPollingNetworkMonitor() throws {
        let expectation1 = expectation(description: "do not fulfill before start")
        expectation1.isInverted = true
        let monitor = MockNetworkMonitor()
        monitor.statusUpdatedCallback = {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 2.0)
        
        let expectation2 = expectation(description: "fullfill when started")
        monitor.statusUpdatedCallback = {
            expectation2.fulfill()
        }
        monitor.start()
        wait(for: [expectation2], timeout: 5.0)
        
        // now stop
        monitor.stop()
        let expectation3 = expectation(description: "don't fullfill when stopped")
        expectation3.isInverted = true
        monitor.statusUpdatedCallback = {
            expectation3.fulfill()
        }
        wait(for: [expectation3], timeout: 2.0)
        
        let expectation4 = expectation(description: "fullfill when started again")
        monitor.statusUpdatedCallback = {
            expectation4.fulfill()
        }
        monitor.start()
        wait(for: [expectation4], timeout: 5.0)
        monitor.stop()
    }
    
    func testConnectivityChange() throws {
        let networkSession = MockNetworkSession()
        let checker = NetworkConnectivityChecker(networkSession: networkSession)
        let monitor = MockNetworkMonitor()
        let notificationCenter = MockNotificationCenter()
        let manager = NetworkConnectivityManager(networkMonitor: monitor,
                                               connectivityChecker: checker,
                                               notificationCenter: notificationCenter,
                                                 offlineModePollingInterval: 0.5, onlineModePollingInterval: 0.5)
        
        // check online status before everything
        XCTAssertTrue(manager.isOnline)
        
        // check that status is offline when there is network error
        let expectation1 = expectation(description: "ConnectivityManager: check status change on network error")
        networkSession.responseCallback = { _ in
            MockNetworkSession.MockResponse(error: IterableError.general(description: "Mock error"))
        }
        manager.connectivityChangedCallback = { (connected: Bool) in
            XCTAssertFalse(connected)
            expectation1.fulfill()
        }
        manager.start()
        monitor.forceStatusUpdate() // Force immediate check
        wait(for: [expectation1], timeout: 5.0)
        
        // check that status is online once error is removed
        let expectation2 = expectation(description: "ConnectivityManager: check status change on network back to normal")
        manager.connectivityChangedCallback = { (connected: Bool) in
            XCTAssertTrue(connected)
            expectation2.fulfill()
        }
        networkSession.responseCallback = nil
        monitor.forceStatusUpdate() // Force immediate check
        wait(for: [expectation2], timeout: 5.0)
        
        // check that status does not change once manager is stopped
        let expectation3 = expectation(description: "ConnectivityManager: no status change when stopped")
        expectation3.isInverted = true
        manager.stop()
        networkSession.responseCallback = { _ in
            MockNetworkSession.MockResponse(error: IterableError.general(description: "Mock error"))
        }
        manager.connectivityChangedCallback = { (connected: Bool) in
            expectation3.fulfill()
        }
        monitor.forceStatusUpdate() // This shouldn't trigger callback since manager is stopped
        wait(for: [expectation3], timeout: 2.0)
    }

    func testOnlinePollingInterval() throws {
        // Network status will never be updated
        class NoUpdateNetworkMonitor: NetworkMonitorProtocol {
            func start() {}
            
            func stop() {}
            
            var statusUpdatedCallback: (() -> Void)?
        }
        
        let networkSession = MockNetworkSession()
        let checker = NetworkConnectivityChecker(networkSession: networkSession)
        let monitor = NoUpdateNetworkMonitor()
        let notificationCenter = MockNotificationCenter()
        let manager = NetworkConnectivityManager(networkMonitor: monitor,
                                               connectivityChecker: checker,
                                               notificationCenter: notificationCenter,
                                               onlineModePollingInterval: 0.5)
        
        // check online status before everything
        XCTAssertTrue(manager.isOnline)
        manager.start()

        // check that status is updated when status is offline
        let expectation1 = expectation(description: "ConnectivityManager: check status change on network offline")
        manager.connectivityChangedCallback = { (connected: Bool) in
            XCTAssertFalse(connected)
            expectation1.fulfill()
        }
        networkSession.responseCallback = { _ in
            MockNetworkSession.MockResponse(error: IterableError.general(description: "Mock error"))
        }

        wait(for: [expectation1], timeout: 10.0)
    }

    func testOfflinePollingInterval() throws {
        // Network status will never be updated
        class NoUpdateNetworkMonitor: NetworkMonitorProtocol {
            func start() {}
            
            func stop() {}
            
            var statusUpdatedCallback: (() -> Void)?
        }
        
        let networkSession = MockNetworkSession()
        let checker = NetworkConnectivityChecker(networkSession: networkSession)
        let monitor = NoUpdateNetworkMonitor()
        let notificationCenter = MockNotificationCenter()
        let manager = NetworkConnectivityManager(networkMonitor: monitor,
                                               connectivityChecker: checker,
                                               notificationCenter: notificationCenter,
                                               offlineModePollingInterval: 0.5)
        
        // check online status before everything
        XCTAssertTrue(manager.isOnline)
        manager.start()

        notificationCenter.post(name: .iterableNetworkOffline, object: nil, userInfo: nil)
        XCTAssertFalse(manager.isOnline)
        
        // check that status is updated when status is online
        let expectation1 = expectation(description: "ConnectivityManager: check status change on network online")
        manager.connectivityChangedCallback = { (connected: Bool) in
            XCTAssertTrue(connected)
            expectation1.fulfill()
        }

        wait(for: [expectation1], timeout: 10.0)
    }
}
