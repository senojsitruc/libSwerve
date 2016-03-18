//
//  CJTcpListenerImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

private func sockaddr_cast(p: UnsafePointer<sockaddr_in>) -> UnsafePointer<sockaddr> { return UnsafePointer<sockaddr>(p) }
private func sockaddr_castm(p: UnsafePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> { return UnsafeMutablePointer<sockaddr>(p) }

internal struct CJTcpListenerImpl: CJSocketListener {
	
	private let port: UInt16
	private let acceptHandler: CJSocketListenerAcceptHandler
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJTcpListenerImpl.queue", DISPATCH_QUEUE_SERIAL)
	
	private var sockfd: Int32 = 0
	private var soaddr: sockaddr_in?
	private var source: dispatch_source_t!
	
	init(port: UInt16, acceptHandler: CJSocketListenerAcceptHandler) {
		self.port = port
		self.acceptHandler = acceptHandler
	}
	
	mutating func start() throws {
		var status: Int32 = 0
		var reuse: Int32 = 1
		var nodelay: Int32 = 1
		var solinger = linger(l_onoff: 1, l_linger: 1)
		var soaddr = sockaddr_in()
		
		// create the socket
		let sockfd = socket(AF_INET, SOCK_STREAM, 0)
		if sockfd == -1 { throw NSError(description: cjstrerror()) }
		
		// make the socket reusable
		status = setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(sizeof(Int32)))
		if status == -1 { throw NSError(description: cjstrerror()) }
		
		// do not queue up outgoing data on the socket
		status = setsockopt(sockfd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(sizeof(Int32)))
		if status == -1 { throw NSError(description: cjstrerror()) }
		
		// configure the sockaddr
		soaddr.sin_family = sa_family_t(AF_INET)
		soaddr.sin_port = UInt16(port).bigEndian
		soaddr.sin_addr.s_addr = 0 // INADDR_ANY
		
		// bind to the local port
		status = bind(sockfd, sockaddr_cast(&soaddr), socklen_t(sizeof(sockaddr_in)))
		if status == -1 { throw NSError(description: cjstrerror()) }
		
		// listen
		status = listen(sockfd, 100)
		if status == -1 { throw NSError(description: cjstrerror()) }
		
		self.sockfd = sockfd
		self.soaddr = soaddr
		self.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(sockfd), 0, queue)
		
		dispatch_source_set_event_handler(source) {
			var addr = sockaddr_in()
			var alen = socklen_t(sizeof(sockaddr_in))
			let sock = accept(sockfd, sockaddr_castm(&addr), &alen)
			
			setsockopt(sock, SOL_SOCKET, SO_LINGER, &solinger, socklen_t(sizeof(linger)))
			
			if sock > 0 { self.acceptHandler(sock, addr) }
		}
		
		dispatch_resume(source)
		
		DLog("Started! [port = \(port)]")
	}
	
	mutating func stop() throws {
		dispatch_suspend(source)
		source = nil
		
		close(sockfd)
		
		DLog("Stopped!")
	}
	
}
