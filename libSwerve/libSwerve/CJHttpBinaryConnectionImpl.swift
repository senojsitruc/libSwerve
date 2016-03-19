//
//  CJHttpBinaryConnectionImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.19.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

private enum ConnectionState: Int {
	case None
	case Header
	case Body
	case Done
}

internal class CJHttpBinaryConnectionImpl: CJHttpConnection {
	
	private var connection: CJConnection
	private let requestHandler: CJHttpConnectionRequestHandler
	private var connectionState: ConnectionState = .None
	
	private var tmpdata = dispatch_data_create(nil, 0, nil, nil)
	private var request: CJHttpServerRequest?
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJHttpBinaryConnectionImpl.queue", DISPATCH_QUEUE_SERIAL)
	private let group = dispatch_group_create()
	
	required init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler) {
		self.requestHandler = requestHandler
		self.connection = connection
		self.connection.readHandler2 = { [weak self, queue, group] data, leng in
			guard let _self = self else { return }
			
			// concatenate any buffered data with this new data
			_self.tmpdata = _self.tmpdata + data
			
			// we'll update this index as we run through the string instead of repeatedly substring()'ing
			var startIndex = 0
			
			// parse a single request, up to the limits of our buffered data
			while (startIndex < _self.tmpdata.length) {
				///
				/// Preface | GET /test.php HTTP/1.1\r\n
				///
				if _self.connectionState == .None {
					// get the next newline (if any); return if we can't find one
					guard let (line, range) = _self.tmpdata.readLine(after: startIndex) else { break }
					
					// the parts are separated by a single space each
					let parts = line.componentsSeparatedByCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
					
					// there should be precisely three parts (method, path and version)
					if parts.count != 3 {
						DLog("Unsupported 1st line; expected 3 parts: \(line)")
						connection.closeConnection()
						break
					}
					
					// create a new request object with the 1st line of the request. when the request is
					// finished, the completion handler were update the group. we do not allow requests to
					// process concurrently, but we do queue them up so they don't sit on the socket
					_self.request = CJSwerve.httpRequestType.init(methodName: parts[0], path: parts[1], version: parts[2]) {
						dispatch_group_leave(group)
					}
					
					// update our offset with the length of the current line
					startIndex += range.length
					
					// we got the 1st line; let's move on to the header
					_self.connectionState = .Header
				}
					
				///
				/// Headers | Host: 127.0.0.1:8080\r\nUser-Agent: curl/7.43.0\r\nAccept: */*\r\n\r\n
				///
				else if _self.connectionState == .Header {
					// get the next newline (if any); return if we can't find one
					guard let (line, range) = _self.tmpdata.readLine(after: startIndex) else { break }
					
					// update our offset with the length of the current line
					startIndex += range.length
					
					// we got a blank line; advance to the body (if any)
					if line.isEmpty == true {
						_self.connectionState = .Done
						break
					}
					
					// save the header without parsing it further
					_self.request?.addHeader(CJHttpHeader(headerString: line))
				}
					
				///
				/// Body |
				///
				else if _self.connectionState == .Body {
					break
				}
			}
			
			///
			/// Done |
			///
			if _self.connectionState == .Done {
				let request = _self.request!
				
				_self.connectionState = .None
				_self.request = nil
				
				dispatch_async(queue) {
					dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
					dispatch_group_enter(group)
					requestHandler(_self, request)
				}
			}
		
			_self.tmpdata = _self.tmpdata.subrangeFromIndex(startIndex)
		}
	}
	
	func close() {
		connection.closeConnection()
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int) {
		connection.write(bytes, size: size, completionHandler: nil)
	}
	
}
