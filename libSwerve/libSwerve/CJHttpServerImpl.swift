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
	
	let channel: dispatch_io_t
	let indata: dispatch_data_t
	
	let sockfd: Int
	let soaddr: sockaddr_in
	let remoteAddr: String
	let remotePort: UInt16
	
	init(sockfd: Int, soaddr: sockaddr_in, queue: dispatch_queue_t) {
		self.sockfd = sockfd
		self.soaddr = soaddr
		self.remoteAddr = CJAddrToString(soaddr.sin_addr, family: soaddr.sin_family) ?? ""
		self.remotePort = soaddr.sin_port
		self.indata = dispatch_data_create(nil, 0, nil, nil)
		self.channel = dispatch_io_create(DISPATCH_IO_STREAM, dispatch_fd_t(sockfd), queue) { error in
			
		}
		
		dispatch_io_set_low_water(channel, 1)
		dispatch_io_set_interval(channel, 10000000000, DISPATCH_IO_STRICT_INTERVAL)
		
		dispatch_io_read(channel, 0, Int.max, queue) { done, data, error in
			
		}
	}
	
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
			
			// create connection object
			
			//   which creates a source
			
		}
	}
	
	mutating func start(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() { [serverPort, acceptHandler] in
			var success = true
			var error: NSError?
			var listener = CJSwerve.tcpListener(port: serverPort, acceptHandler: acceptHandler)
			
			defer { CJDispatchMain() { completionHandler(success, error) } }
			
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
	
	mutating func stop(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() {
			var success = true
			var error: NSError?
			
			defer { CJDispatchMain() { completionHandler(success, error) } }
			
			do {
				try self.listener?.stop()
			}
			catch let e as NSError {
				error = e
			}
			catch {
				DLog("Failed for an unknown reason!")
			}
		}
	}
	
	func addHandler(method: CJHttpMethod, pathEqual: String, handler: CJHttpServerRequestPathEqualsHandler) {
		
	}
	
	func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler) {
		
	}
	
}
