//
//  CJHttpServer1.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

private struct Request: CJHttpServerRequest {
	
}





private struct Response: CJHttpServerResponse {
	
}





private struct Connection: Hashable {
	
	var hashValue: Int { return (remoteAddr + ":\(remotePort)").hashValue }
	
	let socket: Int
	let remoteAddr: String
	let remotePort: Int16
	
}

private func ==(lhs: Connection, rhs: Connection) -> Bool { return lhs.hashValue == rhs.hashValue }





private protocol Handler {
	
	func matches(request: Request) -> Bool
	
}

private struct PathEqualsHandler {
	
	let path: String
	let handler: CJHttpServerRequestPathEqualsHandler
	
	func matches(request: Request) -> Bool {
		return false
	}
	
}

private struct PathLikeHandler {
	
	let path: String
	let handler: CJHttpServerRequestPathLikeHandler
	
	func matches(request: Request) -> Bool {
		return false
	}
	
}





internal struct CJHttpServerImpl: CJHttpServer {
	
	var serverStatus = CJServerStatus.None
	
	private let serverPort: Int16
	private let acceptHandler: CJTcpListenerAcceptHandler
	private var connections = Set<Connection>()
	private var handlers = [Handler]()
	
	private var listener: CJTcpListener?
	private let socketQueue = dispatch_queue_create("us.curtisjones.libSwerve.CJHttpServerImpl.socketQueue", DISPATCH_QUEUE_CONCURRENT)
	
	init(port: Int16) {
		serverPort = port
		
		acceptHandler = { sockfd, soaddr in
			DLog("")
		}
	}
	
	mutating func start(completionHandler: (Bool, NSError?) -> Void) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { [serverPort, acceptHandler] in
			var success = true
			var error: NSError?
			var listener = CJSwerve.tcpListener(port: serverPort, acceptHandler: acceptHandler)
			
			defer {
				completionHandler(success, error)
			}
			
			do {
				try listener.start()
				self.listener = listener
			}
			catch let e as NSError {
				error = e
			}
			catch {
				DLog("Failed for an unknown reason!")
			}
		}
		
	}
	
	func stop(completionHandler: (Bool, NSError?) -> Void) {
		
	}
	
	func addHandler(method: CJHttpMethod, pathEqual: String, handler: CJHttpServerRequestPathEqualsHandler) {
		
	}
	
	func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler) {
		
	}
	
}
