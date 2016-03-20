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
	case Error
}

internal class CJHttpBinaryConnectionImpl: CJHttpConnection {
	
	private var connection: CJConnection
	private let requestHandler: CJHttpConnectionRequestHandler
	private var connectionState: ConnectionState = .None
	
	private var tmpdata = dispatch_data_create(nil, 0, nil, nil)
	private var request: CJHttpServerRequest?
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJHttpBinaryConnectionImpl.queue", DISPATCH_QUEUE_SERIAL)
	private let group = dispatch_group_create()
	
	private var startIndex = 0
	
	required init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler) {
		self.requestHandler = requestHandler
		self.connection = connection
		self.connection.readHandler2 = { [weak self] data, leng in self?.parseData(data, leng) }
	}
	
	func close() {
		connection.close()
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int) {
		connection.write(bytes, size: size, completionHandler: nil)
	}
	
	private final func parseData(data: dispatch_data_t, _ leng: Int) {
		// concatenate any buffered data with this new data
		tmpdata = tmpdata + data
		
		// we'll update this index as we run through the string instead of repeatedly substring()'ing
		startIndex = 0
		
		// parse a single request, up to the limits of our buffered data
		while (startIndex < tmpdata.length) {
			if connectionState == .None {
				parsePrologue()
			}
			else if connectionState == .Header {
				parseHeader()
			}
			else if connectionState == .Body {
				parseBody()
			}
		}
		
		if connectionState == .Done {
			let request = self.request!
			
			self.connectionState = .None
			self.request = nil
			
			DLog(request.method.rawValue + " " + request.path)
			
			dispatch_async(queue) { [group, requestHandler] in
				dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
				dispatch_group_enter(group)
				requestHandler(self, request)
			}
		}
		
		tmpdata = tmpdata.subrangeFromIndex(startIndex)
	}

	///
	/// Prologue | GET /test.php?foo=bar&you=me HTTP/1.1\r\n
	///
	private final func parsePrologue() {
		// get the next newline (if any); return if we can't find one
		guard let (line, range) = tmpdata.readLine(after: startIndex) else { return }
		
		// the parts are separated by a single space each
		let parts = line.componentsSeparatedByCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
		
		// there should be precisely three parts (method, path and version)
		if parts.count != 3 {
			DLog("Unsupported 1st line; expected 3 parts: \(line)")
			connectionState = .Error
			connection.close()
			return
		}
		
		// create a new request object with the 1st line of the request. when the request is
		// finished, the completion handler were update the group. we do not allow requests to
		// process concurrently, but we do queue them up so they don't sit on the socket
		request = CJSwerve.httpRequestType.init(methodName: parts[0], path: parts[1], version: parts[2]) { [group] in
			dispatch_group_leave(group)
		}
		
		// update our offset with the length of the current line
		startIndex += range.length
		
		// we got the 1st line; let's move on to the header
		connectionState = .Header
	}
	
	///
	/// Headers | Host: 127.0.0.1:8080\r\nUser-Agent: curl/7.43.0\r\nAccept: */*\r\n\r\n
	///
	private final func parseHeader() {
		// get the next newline (if any); return if we can't find one
		guard let (line, range) = tmpdata.readLine(after: startIndex) else { return }
		
		// update our offset with the length of the current line
		startIndex += range.length
		
		// we got a blank line; advance to the body (if any)
		if line.isEmpty == true {
			connectionState = request?.contentLength > 0 ? .Body : .Done
			return
		}
		
		// save the header without parsing it further
		request?.addHeader(CJHttpHeader(headerString: line))
	}
	
	///
	/// Body
	///
	private final func parseBody() {
		
	}
	
}
