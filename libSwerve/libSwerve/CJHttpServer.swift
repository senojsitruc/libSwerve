//
//  CJHttpServer.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

public struct CJHttpMethod: OptionSetType {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }
	public static let None = CJHttpMethod(rawValue: 0)
	public static let Get  = CJHttpMethod(rawValue: 1 << 0)
	public static let Post = CJHttpMethod(rawValue: 1 << 1)
}

public typealias CJHttpServerResponseHandler = (CJHttpServerResponse) -> Void
public typealias CJHttpServerRequestPathEqualsHandler = (CJHttpServerRequest, CJHttpServerResponseHandler) -> Void
public typealias CJHttpServerRequestPathLikeHandler = ([String], CJHttpServerRequest, CJHttpServerResponseHandler) -> Void

//public protocol CJHttpConnection {
//	
//	init(sockfd: Int32, soaddr: sockaddr_in, queue: dispatch_queue_t)
//	
//}

//public class CJHttpConnection: Hashable {
//	
//	public var hashValue: Int { return (remoteAddr + ":\(remotePort)").hashValue }
//	
//	let sockfd: Int32
//	let soaddr: sockaddr_in
//	let remoteAddr: String
//	let remotePort: UInt16
//	
//	init(sockfd: Int32, soaddr: sockaddr_in, queue: dispatch_queue_t) {
//		self.sockfd = sockfd
//		self.soaddr = soaddr
//		self.remoteAddr = CJAddrToString(soaddr.sin_addr, family: soaddr.sin_family) ?? ""
//		self.remotePort = soaddr.sin_port
//	}
//	
//}
//
//public func ==(lhs: CJHttpConnection, rhs: CJHttpConnection) -> Bool { return lhs.hashValue == rhs.hashValue }

//public class CJHttpConnection {
//	
//	let connection: CJConnection
//	
//	init(connection: CJConnection) {
//		self.connection = connection
//	}
//	
//}

public typealias CJHttpConnectionRequestHandler = (CJHttpConnection, CJHttpServerRequest) -> Void

public protocol CJHttpConnection {
	
	init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler)
	
//	var connection: CJConnection { get }
//	var requestHandler: ((CJHttpRequest) -> Void) { get set }
	
}

//public struct CJHttpConnection: CJHttpConnectionProtocol {
//	
//	public var hashValue: Int = 0
//	
//	public init(sockfd: Int32, soaddr: sockaddr_in, queue: dispatch_queue_t) { }
//	
//}
//
//public func ==(lhs: CJHttpConnection, rhs: CJHttpConnection) -> Bool { return lhs.hashValue == rhs.hashValue }

public protocol CJHttpServerRequest {
	
}

public protocol CJHttpServerResponse {
	
}

public protocol CJHttpServer {
	
	init(server: CJServer)
	
	mutating func start(completionHandler: (Bool, NSError?) -> Void)
	mutating func stop(completionHandler: (Bool, NSError?) -> Void)
	
	mutating func addHandler(method: CJHttpMethod, pathEquals: String, handler: CJHttpServerRequestPathEqualsHandler)
	mutating func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler)
	
}
