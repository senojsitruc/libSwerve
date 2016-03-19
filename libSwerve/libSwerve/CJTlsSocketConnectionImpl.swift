//
//  CJTlsSocketConnectionImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.19.
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
	var readHandler2: CJConnectionReadHandler2?
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
					connection.close()
				}
				else if status == errSSLWouldBlock {
					DLog("Failed to SSLRead() because errSSLWouldBlock.")
					connection.close()
				}
				else if processed > 0 {
					if let handler = _self.readHandler {
						handler(UnsafePointer<Void>(dbuffer), processed)
					}
					else if let handler = _self.readHandler2 {
						handler(dispatch_data_create(UnsafePointer<Void>(dbuffer), processed, nil, nil), processed)
					}
				}
			}
		}
	}
	
	func open() {
		connection.open()
	}
	
	func close() {
		connection.close()
	}
	
	func pause() {
		connection.pause()
	}
	
	func resume() {
		connection.resume()
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
	
	///
	/// Called (indirectly via tlsReadHandler) by the SSL system when it wants to read data.
	///
	func tlsReadCallback(connection: SSLConnectionRef, data: UnsafeMutablePointer<Void>, dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
		let size = dataLength.memory
		var totalUsed = 0
		
		dispatch_sync(tmpdataQueue) { [tmpdata] in
			dispatch_data_apply(self.tmpdata) { region, offset, data2, size2 in
				memcpy(data, data2, min(size, size2))
				totalUsed = min(size, size2)
				return false
			}
			
			self.tmpdata = dispatch_data_create_subrange(tmpdata, totalUsed, dispatch_data_get_size(tmpdata) - totalUsed)
		}
		
		dataLength.memory = totalUsed
		
		return 0
	}
	
	///
	/// Called (indirectly via tlsWriteHandler) by the SSL system when it wants to write data.
	///
	func tlsWriteCallback(connection: SSLConnectionRef, data: UnsafePointer<Void>, dataLength: UnsafeMutablePointer<Int>) -> OSStatus {
		self.connection.write(data, size: dataLength.memory) { success in /* DLog("Writing \(size) bytes succeeded!") */ }
		return 0
	}
	
}
