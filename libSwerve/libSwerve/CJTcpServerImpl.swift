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
	
	// wraps a call to the tlsReadCallback() member func in a block that can be passed as a c function
	// pointer to the ssl system
	var tlsReadHandler: SSLReadFunc { return { a, b, c in
		return Unmanaged<CJTlsSocketConnectionImpl>.fromOpaque(COpaquePointer(a)).takeUnretainedValue().tlsReadCallback(a, data: b, dataLength: c)
	}}
	
	// wraps a call to the tlsWriteCallback() member func in a block that can be passed as a c
	// function pointer to the ssl system
	var tlsWriteHandler: SSLWriteFunc { return { a, b, c in
		return Unmanaged<CJTlsSocketConnectionImpl>.fromOpaque(COpaquePointer(a)).takeUnretainedValue().tlsWriteCallback(a, data: b, dataLength: c)
	}}
	
	// CJConnection
	var context: Any?
	var readHandler: CJConnectionReadHandler?
	var closeHandler: ((CJConnection) -> Void)?
	
	// CJSocketConnection
	var remoteAddr: String { return connection.remoteAddr }
	var remotePort: UInt16 { return connection.remotePort }
	
	private var hasStartedTls = false
	private var tmpdata = dispatch_data_create(nil, 0, nil, nil)
	private let tmpdataQueue = dispatch_queue_create("us.curtisjones.libSwerve.CJSocketTlsConnectionImpl.tmpdataQueue", DISPATCH_QUEUE_SERIAL)
	private let connection: CJSocketConnection
	
	required init(sockfd: Int32, soaddr: sockaddr_in) {
		connection = CJSwerve.tcpConnectionType.init(sockfd: sockfd, soaddr: soaddr)
		connection.readHandler = { [weak self, connection, tmpdataQueue] buffer, size in
			guard let _self = self else { return }
			guard let tlsContext = _self.tlsContext else { return }
			
			/// append the new data to our buffer; this data is accessible to the ssl system via its read
			/// callback. since we're can't call the underlying socket object and ask for data, we have to
			/// to handle buffering here.
			dispatch_sync(tmpdataQueue) {
				_self.tmpdata = dispatch_data_create_concat(_self.tmpdata, dispatch_data_create(buffer, size, nil, nil))
			}
			
			/// continue with ssl handshake if we haven't finished that yet
			if _self.hasStartedTls == false {
				if _self.startTLS() == true {
					_self.hasStartedTls = true
				}
			}
			
			/// we're past the ssl handshake; pass data to the user's read handler
			else {
				// ask the ssl system to read some data
				var processed = 0
				let dbuffer = UnsafeMutablePointer<Void>.alloc(10000)
				let status = SSLRead(tlsContext, dbuffer, 10000, &processed)
				
				if status == errSSLClosedGraceful {
					DLog("SSL connection closed gracefully.")
					connection.closeConnection()
				}
				else if status == errSSLWouldBlock {
					DLog("Failed to SSLRead() because errSSLWouldBlock.")
					connection.closeConnection()
				}
				else if processed > 0 {
					_self.readHandler?(UnsafePointer<Void>(dbuffer), processed)
				}
			}
		}
	}
	
	func open() {
		connection.open()
	}
	
	func closeConnection() {
		connection.closeConnection()
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
			//DLog("totalBytes = \(totalBytes), size = \(size)")
			
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
		
		//DLog("Being asked for \(dataLength.memory) bytes")
		
		dispatch_sync(tmpdataQueue) { [tmpdata] in
			dispatch_data_apply(self.tmpdata) { region, offset, data2, size2 in
				memcpy(data, data2, min(size, size2))
				totalUsed = min(size, size2)
				return false
			}
			
			self.tmpdata = dispatch_data_create_subrange(tmpdata, totalUsed, dispatch_data_get_size(tmpdata) - totalUsed)
		}
		
		//DLog("Returning \(totalUsed) bytes. Remaining: \(dispatch_data_get_size(self.tmpdata))")
		
		dataLength.memory = totalUsed
		
		return 0
	}
	
	func tlsWriteCallback(connection: SSLConnectionRef, data: UnsafePointer<Void>, dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
		//let size = dataLength.memory
		self.connection.write(data, size: dataLength.memory) { success in /* DLog("Writing \(size) bytes succeeded!") */ }
		return 0
	}
	
}





internal class CJTcpSocketConnectionImpl: CJSocketConnection {
	
	var context: Any?
	var readHandler: CJConnectionReadHandler?
	var closeHandler: ((CJConnection) -> Void)?
	
	var channel: dispatch_io_t!
	let indata: dispatch_data_t
	
	var sockfd: Int32
	let soaddr: sockaddr_in
	let remoteAddr: String
	let remotePort: UInt16
	
	private var stop: Int32 = 0
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJTcpServerImpl.queue", DISPATCH_QUEUE_SERIAL)
	private let group = dispatch_group_create()
	private var bytesIn: size_t = 0
	private var bytesOut: size_t = 0
	
	required init(sockfd: Int32, soaddr: sockaddr_in) {
		self.sockfd = sockfd
		self.soaddr = soaddr
		self.remoteAddr = CJAddrToString(soaddr.sin_addr, family: soaddr.sin_family) ?? ""
		self.remotePort = soaddr.sin_port
		self.indata = dispatch_data_create(nil, 0, nil, nil)
		
		log("Incoming connection established.")
	}
	
	func open() {
		self.channel = dispatch_io_create(DISPATCH_IO_STREAM, dispatch_fd_t(sockfd), queue) { [weak self, sockfd] error in
			if error != 0 {
				self?.log("Channel open failed. [sockfd = \(sockfd), error = (\(error)) \(cjstrerror(error))")
				self?.channel = nil
				self?.closeConnection()
			}
			else {
				self?.log("Channel closed. [sockfd = \(sockfd)")
			}
		}
		
		guard let channel = self.channel else { return }
		
		dispatch_io_set_low_water(channel, 1)
		dispatch_io_set_interval(channel, 10000000000, DISPATCH_IO_STRICT_INTERVAL)
		dispatch_io_read(channel, 0, Int.max, queue) { [weak self, group] done, data, error in
			if self?.stop != 0 {
				return
			}
			
			dispatch_group_enter(group)
			
			if data != nil && dispatch_data_get_size(data) != 0 {
				self?.handleIncoming(done: done, data: data, error: error)
			}
			
			if done == true || error != 0 {
				self?.closeConnection()
				self?.log("Error while reading. \(error) = \(cjstrerror(error))")
			}
			
			dispatch_group_leave(group)
		}
	}
	
	func closeConnection() {
		if OSAtomicCompareAndSwap32(0, 1, &stop) == false { return }
		
		dispatch_group_notify(group, queue) { [sockfd] in
			self.readHandler = nil
			self.sockfd = 0
			
			if let channel = self.channel {
				dispatch_io_close(channel, DISPATCH_IO_STOP)
			}
			close(sockfd)
			
			self.closeHandler?(self)
			
			self.closeHandler = nil
			self.context = nil
			
			self.log("Connection closed. [bytesIn = \(self.bytesIn); bytesOut = \(self.bytesOut)]")
		}
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int, completionHandler: ((Bool) -> Void)?) {
		//log("Writing \(size) bytes.")
		
		if stop != 0 {
			log("Cannot write to a closed connection.")
			completionHandler?(false)
			return
		}
		
		bytesOut += size
		
		dispatch_group_enter(group)
		dispatch_io_write(channel, 0, dispatch_data_create(bytes, size, nil, nil), queue) { [group] done, data, error in
			if done == true {
				completionHandler?(error == 0)
				
				if error != 0 {
					self.closeConnection()
					self.log("Writing. [error = [\(error)] \(cjstrerror(error))]")
				}
				
				dispatch_group_leave(group)
			}
			else if error != 0 {
				self.log("Writing. [error = [\(error)] \(cjstrerror(error))]")
				dispatch_group_leave(group)
			}
		}
	}
	
	private final func handleIncoming(done done: Bool, data: dispatch_data_t, error: Int32) {
		guard let handler = readHandler else { return }
		
		let size = dispatch_data_get_size(data)
		
		if size == 0 { return }
		
		// check for a stop signal
		if stop != 0 { return }
		
		bytesIn += size
		
		dispatch_data_apply(data) { region, offset, buffer, size in handler(buffer, size); return true }
	}
	
	private final func log(string: String) {
//		print("\(remoteAddr):\(remotePort) [sockfd = \(sockfd)] :: " + string)
	}
}





private class Connection: Hashable {
	
	var hashValue: Int { return name.hashValue }
	
	let name: String
	let connection: CJSocketConnection
	
	init(connection: CJSocketConnection) {
		self.name = connection.remoteAddr + ":\(connection.remotePort)"
		self.connection = connection
	}
	
}

private func ==(lhs: Connection, rhs: Connection) -> Bool { return lhs.hashValue == rhs.hashValue }





internal class CJTlsServerImpl: CJTcpServerImpl {
	
	private var tlsIdentity: SecIdentity?
	private var tlsContext: SSLContext?
	
	override func start() throws {
		tlsIdentity = CJCrypto.identity
		DLog("tlsIdentity = \(tlsIdentity) | \(tlsIdentity?.commonName)")
		
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
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJTcpServerImpl.queue", DISPATCH_QUEUE_SERIAL)
	
	private var listener: CJSocketListener?
	private var portMapper: PGPortMapperBonjour?
	
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
		
		dispatch_sync(queue) {
			self.connections.forEach() { $0.connection.closeConnection() }
			self.connections.removeAll()
		}
	}
	
	func accept(sockfd: Int32, soaddr: sockaddr_in) {
		var tcpConnection = self.connectionType().init(sockfd: sockfd, soaddr: soaddr)
		let connection = Connection(connection: tcpConnection)
		tcpConnection.closeHandler = { [weak self, weak connection] _ in self?.closeConnection(connection) }
		startConnection(connection)
	}
	
	private func startConnection(connection: Connection) {
		dispatch_sync(queue) {
			self.connections.insert(connection)
		}
		acceptHandler?(connection.connection)
		connection.connection.open()
	}
	
	private func closeConnection(connection: Connection?) {
		dispatch_sync(queue) {
			if let connection = connection {
				self.connections.remove(connection)
			}
		}
	}
	
	func enablePortMapping(externalPort port: UInt16) {
		if portMapper != nil {
			DLog("Port mapping is already enabled.")
			return
		}
		
		portMapper = PGPortMapperBonjour(privatePort: serverPort, publicPort: port) { portMapper in
			DLog("Port Mapper | publicAddress = \(portMapper.publicAddress), publicPort: \(portMapper.publicPort), isMapped = \(portMapper.isMapped), error = \(portMapper.error)")
		}
		
		portMapper?.open()
	}
	
	func disablePortMapping() {
		portMapper?.close()
		portMapper = nil
	}
	
	func connectionType() -> CJSocketConnection.Type { return CJSwerve.tcpConnectionType }
	
}
