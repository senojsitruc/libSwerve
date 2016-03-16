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





private protocol Handler {
	
	func matches(request: Request) -> Bool
	
}

private struct PathEqualsHandler: Handler {
	
	let method: CJHttpMethod
	let path: String
	let handler: CJHttpServerRequestPathEqualsHandler
	
	func matches(request: Request) -> Bool {
		return false
	}
	
}

private struct PathLikeHandler: Handler {
	
	let method: CJHttpMethod
	let path: String
	let handler: CJHttpServerRequestPathLikeHandler
	
	func matches(request: Request) -> Bool {
		return false
	}
	
}





internal class CJHttpConnectionImpl: CJHttpConnection {
	
	private var connection: CJConnection
	private let requestHandler: CJHttpConnectionRequestHandler
	
	required init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler) {
		self.connection = connection
		self.connection.readHandler = { }
		self.requestHandler = requestHandler
	}
	
}





internal class CJHttpServerImpl: CJHttpServer {
	
	private var handlers = [Handler]()
	private var server: CJServer!
	
	required init(server: CJServer) {
		self.server = server
	}
	
	func start(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() {
			var success = false
			var nserror: NSError?
			
			defer { CJDispatchMain() { completionHandler(success, nserror) } }
			
			let requestHandler: CJHttpConnectionRequestHandler = { connection, request in
				
			}
			
			// link new connections to http connection objects
			self.server.acceptHandler = { connection in
				var c = connection
				c.context = CJSwerve.httpConnectionType.init(connection: connection, requestHandler: requestHandler)
			}
			
			do {
				try self.server.start()
				success = true
			}
			catch let e as NSError {
				nserror = e
			}
			catch {
				nserror = NSError(description: "Start failed for an unknown reason.")
			}
		}
	}
	
	func stop(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() {
			var success = false
			var nserror: NSError?
			
			defer {
				self.server = nil
				CJDispatchMain() { completionHandler(success, nserror) }
			}
			
			do {
				try self.server.stop()
				success = true
			}
			catch let e as NSError {
				nserror = e
			}
			catch {
				nserror = NSError(description: "Failed for an unknown reason!")
			}
		}
	}
	
	func addHandler(method: CJHttpMethod, pathEquals path: String, handler: CJHttpServerRequestPathEqualsHandler) {
		handlers.append(PathEqualsHandler(method: method, path: path, handler: handler))
	}
	
	func addHandler(method: CJHttpMethod, pathLike path: String, handler: CJHttpServerRequestPathLikeHandler) {
		handlers.append(PathLikeHandler(method: method, path: path, handler: handler))
	}
	
}
