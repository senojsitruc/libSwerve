//
//  CJTcpServerImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

internal class Connection: Hashable {
	
	var hashValue: Int { return name.hashValue }
	
	let name: String
	let connection: CJSocketConnection
	
	init(connection: CJSocketConnection) {
		self.name = connection.remoteAddr + ":\(connection.remotePort)"
		self.connection = connection
	}
	
}

internal func ==(lhs: Connection, rhs: Connection) -> Bool { return lhs.hashValue == rhs.hashValue }





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
	
	internal func startConnection(connection: Connection) {
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
