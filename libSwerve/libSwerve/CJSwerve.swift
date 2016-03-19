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
	public static var httpConnectionType: CJHttpConnection.Type = CJHttpStringConnectionImpl.self
	public static var httpRequestType: CJHttpServerRequest.Type = CJHttpServerRequestImpl.self
	public static var httpResponseType: CJHttpServerResponse.Type = CJHttpServerResponseImpl.self
	
	public static var tlsTcpServerType: CJSocketServer.Type = CJTlsServerImpl.self
	public static var tcpServerType: CJSocketServer.Type = CJTcpServerImpl.self
	public static var tcpListenerType: CJSocketListener.Type = CJTcpListenerImpl.self
	public static var tcpConnectionType: CJSocketConnection.Type = CJTcpSocketConnectionImpl.self
	public static var tlsConnectionType: CJTlsSocketConnection.Type = CJTlsSocketConnectionImpl.self
	
}
