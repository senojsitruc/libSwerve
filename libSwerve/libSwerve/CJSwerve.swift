//
//  CJSwerve.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

public struct CJSwerve {
	
	private static let httpServerType = CJHttpServerImpl.self
	private static let tcpListenerType = CJTcpListenerImpl.self
	
	public init() {
	}
	
	public static func httpServer(port: Int16) -> CJHttpServer {
		return httpServerType.init(port: port)
	}
	
	internal static func tcpListener(port port: Int16, acceptHandler: CJTcpListenerAcceptHandler) -> CJTcpListener {
		return tcpListenerType.init(port: port, acceptHandler: acceptHandler)
	}
	
}
