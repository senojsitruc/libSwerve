//
//  CJTlsServerImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.19.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

internal class CJTlsServerImpl: CJTcpServerImpl {
	
	private var tlsIdentity: SecIdentity?
	private var tlsContext: SSLContext?
	
	override func start() throws {
		tlsIdentity = CJCrypto.identity
		DLog("tlsIdentity = \(tlsIdentity) | \(tlsIdentity?.commonName)")
		
		try super.start()
	}
	
	internal override func startConnection(connection: Connection) {
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
