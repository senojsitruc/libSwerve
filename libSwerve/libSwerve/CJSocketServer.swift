//
//  CJTcpServer.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

public protocol CJSocketConnection: CJConnection {
	
	var remoteAddr: String { get }
	var remotePort: UInt16 { get }
	
	init(sockfd: Int32, soaddr: sockaddr_in)

}

public protocol CJSocketServer: CJServer {
	
	init(port: UInt16)
	
}

public typealias CJSocketListenerAcceptHandler = (Int32, sockaddr_in) -> Void

public protocol CJSocketListener {
	
	init(port: UInt16, acceptHandler: CJSocketListenerAcceptHandler)
	
	mutating func start() throws
	mutating func stop() throws
	
}
