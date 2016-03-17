//
//  CJTcpServerImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

internal class CJTcpConnectionImpl: CJSocketConnection {
	
	var context: Any?
	var readHandler: CJConnectionReadHandler?
	
	let channel: dispatch_io_t
	let indata: dispatch_data_t
	
	let sockfd: Int32
	let soaddr: sockaddr_in
	let queue: dispatch_queue_t
	let writeGroup = dispatch_group_create()
	let remoteAddr: String
	let remotePort: UInt16
	
	private var stop = false
	private var paused = false
	private var tmpdata: dispatch_data_t = dispatch_data_create(nil, 0, nil, nil)
	private let tmpdataQueue = dispatch_queue_create("us.curtisjones.libSwerve.CJTcpServerImpl.tmpdataQueue", DISPATCH_QUEUE_SERIAL)
	private var bytesIn: size_t = 0
	
	required init(sockfd: Int32, soaddr: sockaddr_in, queue: dispatch_queue_t) {
		self.sockfd = sockfd
		self.soaddr = soaddr
		self.queue = queue
		self.remoteAddr = CJAddrToString(soaddr.sin_addr, family: soaddr.sin_family) ?? ""
		self.remotePort = soaddr.sin_port
		self.indata = dispatch_data_create(nil, 0, nil, nil)
		
		self.channel = dispatch_io_create(DISPATCH_IO_STREAM, dispatch_fd_t(sockfd), queue) { error in
			
		}
		
		DLog("\(remoteAddr):\(remotePort) :: Incoming connection established.")
	}
	
	func open() {
		dispatch_io_set_low_water(channel, 1)
		
		dispatch_io_set_interval(channel, 10000000000, DISPATCH_IO_STRICT_INTERVAL)
		
		dispatch_io_read(channel, 0, Int.max, queue) { [weak self, remoteAddr, remotePort, tmpdataQueue] done, data, error in
			let size = dispatch_data_get_size(data)
			
			DLog("\(remoteAddr):\(remotePort) :: read bytes = \(dispatch_data_get_size(data))")
			
			if size == 0 { return }
			
			guard let _self = self else { return }
			
			// check for a stop signal
			if _self.stop == true { return }
			
			// enumerate the memory regions of the data buffer. the handler will tell us how many bytes it
			// has consumed and we'll subrange() them off the front when we're done
			if let data = data {
				_self.bytesIn += size
				dispatch_sync(tmpdataQueue) {
					_self.tmpdata = dispatch_data_create_concat(_self.tmpdata, data)
				}
				_self.applyData()
			}
		}
	}
	
	func closeConnection() {
		stop = true
		dispatch_io_close(channel, 0)
		close(sockfd)
	}
	
	///
	/// the read handler will not be called until after resume() is called
	///
	func pause() {
		paused = true
	}
	
	func resume(waitForWrites waitForWrites: Bool = false) {
		if stop == true {
			DLog("Cannot resume a closed connection.")
			return
		}
		
		if waitForWrites == true {
			dispatch_group_async(writeGroup, queue) { self.paused = false; self.applyData() }
		}
		else {
			paused = false
			dispatch_async(queue) { self.applyData() }
		}
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int, completionHandler: ((Bool) -> Void)?) {
		DLog("writing bytes = \(size)")
		
		if stop == true {
			DLog("Cannot write to a closed connection.")
			completionHandler?(false)
			return
		}
		
		dispatch_group_enter(writeGroup)
		dispatch_io_write(channel, 0, dispatch_data_create(bytes, size, nil, nil), queue) { [writeGroup] done, data, error in
			if done == true {
				DLog("DONE!")
				completionHandler?(error == 0)
				dispatch_group_leave(writeGroup)
			}
		}
	}
	
	///
	/// calls the read handler with segments of data (if the connection is not paused)
	///
	private final func applyData() {
		if paused == true { return }
		
		guard let handler = readHandler else { return }
		
		var totalUsed = 0
		
		dispatch_sync(tmpdataQueue) {
			dispatch_data_apply(self.tmpdata) { region, offset, buffer, size in
				let used = handler(buffer, size)
				totalUsed += used
				return used == size
			}
			
			self.tmpdata = dispatch_data_create_subrange(self.tmpdata, totalUsed, dispatch_data_get_size(self.tmpdata) - totalUsed)
		}
	}
	
}





private class Connection: Hashable {
	
	var hashValue: Int { return name.hashValue }
	
	let name: String
	let connection: CJSocketConnection
	
	init(connection: CJSocketConnection) {
		self.name = connection.remoteAddr + "\(connection.remotePort)"
		self.connection = connection
	}
	
}

private func ==(lhs: Connection, rhs: Connection) -> Bool { return lhs.hashValue == rhs.hashValue }





internal class CJTcpServerImpl: CJSocketServer {
	
	var serverStatus: CJServerStatus = .None
	var acceptHandler: CJServerAcceptHandler?
	
	private let serverPort: UInt16
	private var connections = Set<Connection>()
	
	private var listener: CJSocketListener?
	private let socketQueue = dispatch_queue_create("us.curtisjones.libSwerve.CJHttpServerImpl.socketQueue", DISPATCH_QUEUE_CONCURRENT)
	
	required init(port: UInt16) {
		serverPort = port
	}
	
	func start() throws {
		let acceptHandler: CJSocketListenerAcceptHandler = { [weak self, socketQueue] sockfd, soaddr in
			let tcpConnection = CJSwerve.tcpConnectionType.init(sockfd: sockfd, soaddr: soaddr, queue: socketQueue)
			let connection = Connection(connection: tcpConnection)
			self?.connections.insert(connection)
			self?.acceptHandler?(tcpConnection)
			tcpConnection.open()
		}
		
		var listener = CJSwerve.tcpListenerType.init(port: serverPort, acceptHandler: acceptHandler)
			
		try listener.start()
		self.listener = listener
	}
	
	func stop() throws {
		try listener?.stop()
		listener = nil
		
		connections.forEach() { $0.connection.closeConnection() }
		connections.removeAll()
	}
	
}
