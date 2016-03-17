//
//  CJTcpServerImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation
import Security

internal class CJTlsSocketConnectionImpl: CJTlsSocketConnection {
	
	// CJTlsConnection
	var tlsIdentity: SecIdentity?
	var tlsContext: SSLContext?
	var tlsObject: AnyObject { return self }
	
	var tlsReadHandler: SSLReadFunc { return { a, b, c in
		return Unmanaged<CJTlsSocketConnectionImpl>.fromOpaque(COpaquePointer(a)).takeUnretainedValue().tlsReadCallback(a, data: b, dataLength: c)
	}}
	
	var tlsWriteHandler: SSLWriteFunc { return { a, b, c in
		return Unmanaged<CJTlsSocketConnectionImpl>.fromOpaque(COpaquePointer(a)).takeUnretainedValue().tlsWriteCallback(a, data: b, dataLength: c)
	}}
	
	// CJConnection
	var context: Any?
	var readHandler: CJConnectionReadHandler?
	
	/// CJSocketConnection
	var remoteAddr: String { return connection.remoteAddr }
	var remotePort: UInt16 { return connection.remotePort }
	
	private var hasStartedTls = false
	private var tmpdata = dispatch_data_create(nil, 0, nil, nil)
	private let tmpdataQueue = dispatch_queue_create("us.curtisjones.libSwerve.CJTcpServerImpl.CJSocketTlsConnectionImpl.tmpdataQueue", DISPATCH_QUEUE_SERIAL)
	private let connection: CJSocketConnection
	
	required init(sockfd: Int32, soaddr: sockaddr_in, queue: dispatch_queue_t) {
		connection = CJSwerve.tcpConnectionType.init(sockfd: sockfd, soaddr: soaddr, queue: queue)
		connection.readHandler = { [weak self, connection, tmpdataQueue] buffer, size in
			DLog("We got \(size) bytes from the underlying socket.")
			
			guard let _self = self else { return size }
			guard let tlsContext = _self.tlsContext else { return size }
			
			let dbuffer = UnsafeMutablePointer<Void>.alloc(10000)
			var processed = 0, processed2 = 0
			
			dispatch_sync(tmpdataQueue) {
				_self.tmpdata = dispatch_data_create_concat(_self.tmpdata, dispatch_data_create(buffer, size, nil, nil))
			}
			
			DLog("Total buffered data is \(dispatch_data_get_size(_self.tmpdata))")
			
			if _self.hasStartedTls == false {
				if _self.startTLS() == true {
					_self.hasStartedTls = true
					DLog("Secure connection established!")
				}
				return size
			}
			
			let status = SSLRead(tlsContext, dbuffer, 10000, &processed)
			
			if status == errSSLClosedGraceful {
				DLog("SSL connection closed gracefully.")
				connection.closeConnection()
			}
			else if status == errSSLWouldBlock {
				DLog("Failed to SSLRead() because errSSLWouldBlock.")
				connection.closeConnection()
			}
			else if processed == 0 {
				return size
			}
			else {
				
				processed2 = _self.readHandler?(UnsafePointer<Void>(dbuffer), processed) ?? 0
				
				if processed2 != processed {
					DLog("We didn't use all of the data! [processed = \(processed), processed2 = \(processed2)]")
				}
			}
			
			return size
		}
	}
	
	func open() {
		connection.open()
	}
	
	func closeConnection() {
		connection.closeConnection()
	}
	
	func pause() {
		connection.pause()
	}
	
	func resume(waitForWrites waitForWrites: Bool) {
		connection.resume(waitForWrites: waitForWrites)
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int, completionHandler: ((Bool) -> Void)?) {
		
		// TODO: an internal serial queue?
		
		guard let tlsContext = self.tlsContext else {
			DLog("Cannot write until startTLS() has been called!")
			completionHandler?(false)
			return
		}
		
		var totalBytes = 0
		var success = true
		
		repeat {
			DLog("totalBytes = \(totalBytes), size = \(size)")
			
			var processed = 0
			let status = SSLWrite(tlsContext, bytes.advancedBy(totalBytes), size, &processed)
			
			if status == errSSLWouldBlock {
				DLog("SSL would block. [processed = \(processed)]")
				sleep(1)
			}
			else if status != noErr {
				DLog("SSL error [status = \(status)]")
				success = false
				break
			}
			
			totalBytes += processed
			
		} while totalBytes < size
		
		completionHandler?(success)
	}
	
	func tlsReadCallback(connection: SSLConnectionRef, data: UnsafeMutablePointer<Void>, dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
		let size = dataLength.memory
		var totalUsed = 0
		
		DLog("Being asked for \(dataLength.memory) bytes")
		
		dispatch_sync(tmpdataQueue) { [tmpdata] in
			dispatch_data_apply(self.tmpdata) { region, offset, data2, size2 in
				memcpy(data, data2, min(size, size2))
				totalUsed = min(size, size2)
				return false
			}
			
			self.tmpdata = dispatch_data_create_subrange(tmpdata, totalUsed, dispatch_data_get_size(tmpdata) - totalUsed)
		}
		
		DLog("Returning \(totalUsed) bytes. Remaining: \(dispatch_data_get_size(self.tmpdata))")
		
		dataLength.memory = totalUsed
		
		return 0
	}
	
	func tlsWriteCallback(connection: SSLConnectionRef, data: UnsafePointer<Void>, dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
		let size = dataLength.memory
		self.connection.write(data, size: dataLength.memory) { success in DLog("Writing \(size) bytes succeeded!") }
		return 0
	}
	
}

internal class CJTcpSocketConnectionImpl: CJSocketConnection {
	
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
	private var tmpdata = dispatch_data_create(nil, 0, nil, nil)
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
			
			if size == 0 { return }
			
			guard let _self = self else { return }
			
			DLog("\(remoteAddr):\(remotePort) :: read bytes = \(dispatch_data_get_size(data)), buffered bytes = \(dispatch_data_get_size(_self.tmpdata))")
			
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
	internal func applyData() {
		if paused == true { return }
		
		guard let handler = readHandler else { return }
		
		dispatch_sync(tmpdataQueue) {
			var lastUsed = 0
			
			while (true) {
				var totalUsed = 0
				let totalSize = dispatch_data_get_size(self.tmpdata)
				
				dispatch_data_apply(self.tmpdata) { region, offset, buffer, size in
					lastUsed = handler(buffer, size)
					totalUsed += lastUsed
					DLog("totalSize = \(totalSize), totalUsed = \(totalUsed), lastUsed = \(lastUsed)")
					return lastUsed == size
				}
				
				self.tmpdata = dispatch_data_create_subrange(self.tmpdata, totalUsed, dispatch_data_get_size(self.tmpdata) - totalUsed)
				
				if lastUsed == 0 || totalUsed == totalSize {
					DLog("Used: \(totalUsed); Remaining: \(dispatch_data_get_size(self.tmpdata))")
					break
				}
			}
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





internal class CJTlsServerImpl: CJTcpServerImpl {
	
	private var tlsIdentity: SecIdentity?
	private var tlsContext: SSLContext?
	
	override func start() throws {
		tlsIdentity = CJCrypto.identityWithLabel("us.curtisjones.libSwerve.tlsKey-001")
		DLog("tlsIdentity = \(tlsIdentity)")
		try super.start()
	}
	
	private override func startConnection(connection: Connection) {
		guard var tlsConnection = connection.connection as? CJTlsSocketConnection else {
			super.startConnection(connection)
			return
		}
		
		tlsConnection.tlsIdentity = tlsIdentity
		tlsConnection.setupTLS()
		
		super.startConnection(connection)
	}
	
	override func connectionType() -> CJSocketConnection.Type { return CJSwerve.tlsConnectionType }
	
}





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
		var listener = CJSwerve.tcpListenerType.init(port: serverPort) { [weak self] in self?.accept($0, soaddr: $1) }
		try listener.start()
		self.listener = listener
	}
	
	func stop() throws {
		try listener?.stop()
		listener = nil
		
		connections.forEach() { $0.connection.closeConnection() }
		connections.removeAll()
	}
	
	func accept(sockfd: Int32, soaddr: sockaddr_in) {
		let tcpConnection = self.connectionType().init(sockfd: sockfd, soaddr: soaddr, queue: socketQueue)
		let connection = Connection(connection: tcpConnection)
		connections.insert(connection)
		startConnection(connection)
	}
	
	private func startConnection(connection: Connection) {
		acceptHandler?(connection.connection)
		connection.connection.open()
	}
	
	func connectionType() -> CJSocketConnection.Type { return CJSwerve.tcpConnectionType }
	
}
