//
//  CJSwerve.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

public struct CJSwerve {
	
	public static var httpServerType: CJHttpServer.Type = CJHttpServerImpl.self
	public static var httpConnectionType: CJHttpConnection.Type = CJHttpConnectionImpl.self
	
	public static var tcpServerType: CJSocketServer.Type = CJTcpServerImpl.self
	public static var tcpListenerType: CJSocketListener.Type = CJTcpListenerImpl.self
	public static var tcpConnectionType: CJSocketConnection.Type = CJTcpConnectionImpl.self
	
}
