//
//  CJListener.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

typealias CJTcpListenerAcceptHandler = (Int32, sockaddr_in) -> Void

protocol CJListener { }

protocol CJTcpListener: CJListener {
	
	init(port: Int16, acceptHandler: CJTcpListenerAcceptHandler)
	
	mutating func start() throws
	mutating func stop() throws
	
}

protocol CJUdpListener: CJListener { }
