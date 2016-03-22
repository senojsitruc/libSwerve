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
	case Error
}

internal class CJHttpBinaryConnectionImpl: CJHttpConnection {
	
	private var connection: CJConnection
	private let requestHandler: CJHttpConnectionRequestHandler
	private var connectionState: ConnectionState = .None
	
	private var tmpdata = dispatch_data_create(nil, 0, nil, nil)
	private var request: CJHttpServerRequest?
	private var requests = [CJHttpServerRequest]()
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJHttpBinaryConnectionImpl.queue", DISPATCH_QUEUE_SERIAL)
	private let group = dispatch_group_create()
	
	private var startIndex = 0
	private var contentLengthRemaining = 0
	
	required init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler) {
		self.requestHandler = requestHandler
		self.connection = connection
		self.connection.readHandler2 = { [weak self] data, leng in self?.parseData(data, leng) }
	}
	
	func close() {
		connection.close()
	}
	
	func resume() {
		parseData(nil, 0)
		connection.resume()
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int) {
		connection.write(bytes, size: size, completionHandler: nil)
	}
	
	private final func parseData(data: dispatch_data_t?, _ leng: Int) {
		// concatenate any buffered data with this new data
		if let data = data {
			tmpdata = tmpdata + data
		}
		
		// we'll update this index as we run through the string instead of repeatedly substring()'ing
		startIndex = 0
		
		// parse a single request, up to the limits of our buffered data, but stop short of parsing
		// the body all in one go, since that's dependent on the caller first being able to determine
		// how to best handle the body data.
		while (startIndex < tmpdata.length) {
			if connectionState == .None {
				parsePrologue()
			}
			else if connectionState == .Header {
				parseHeader()
				if connectionState == .Body { break }
			}
			else if connectionState == .Body {
				parseBody()
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
		// finished, the completion handler will update the group. we do not allow requests to
		// process concurrently, but we do queue them up so they don't sit on the socket
		request = CJSwerve.httpRequestType.init(methodName: parts[0], path: parts[1], version: parts[2], connection: self) { [group] in
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
		
		// add the header to the request
		if line.isEmpty == false {
			request?.addHeader(CJHttpHeader(headerString: line))
		}
		// we got a blank line. this is the end of the header.
		else {
			let request = self.request!
			
			// if there's a body to be read and parsed, set the connection state accordingly and pause()
			// further reads. the handler for this request will need to resume() when it is ready.
			if request.contentLength > 0 {
				connectionState = .Body
				connection.pause()
				contentLengthRemaining = request.contentLength!
			}
			// there is no body to this request, so we're done here.
			else {
				connectionState = .None
				self.request = nil
			}
			
			handleRequest(request)
		}
	}
	
	///
	/// Body
	///
	private final func parseBody() {
		if request?.contentType == CJHttpContentType.UrlForm.rawValue {
			parseBodyUrlForm()
		}
		else {
			DLog("Unsupported content type: \(request?.contentType)")
		}
		
		// self.request = nil
		
	}
	
	private final func parseBodyUrlForm() {
		var values = [String: AnyObject]()
		var consumed = 0
		
		// given a data that spans just a `name=value` segment, find the `=`, split it into two strings,
		// decode the strings and add them to the values dictionary.
		let handlePair = { (pairData: dispatch_data_t) in
			if let equRange = pairData.rangeOfByte(0x3D) {
				let k = pairData.stringWithRange(NSMakeRange(0, equRange.location))
				let v = pairData.stringWithRange(NSMakeRange(equRange.location + 1, pairData.length - equRange.location - 1))
				if let k = k?.stringByRemovingPercentEncoding, v = v?.stringByRemovingPercentEncoding {
					values[k] = v
					DLog(" | \(k) = \(v)")
				}
			}
		}
		
		// while we still have data to read, look for name=value pairs separated by ampersands (except
		// for the last one)
		while consumed < contentLengthRemaining {
			if let ampRange = tmpdata.rangeOfByte(0x26, after: startIndex + consumed, maxLength: contentLengthRemaining - consumed) {
				handlePair(tmpdata.subrangeFromIndex(startIndex + consumed, length: ampRange.location - startIndex - consumed))
				consumed += ampRange.location - startIndex - consumed + 1
			}
			else if tmpdata.length - startIndex - consumed >= contentLengthRemaining - consumed {
				handlePair(tmpdata.subrangeFromIndex(startIndex + consumed, length: contentLengthRemaining - consumed))
				consumed = contentLengthRemaining
			}
			else {
				break
			}
		}
		
		// update our read offset. the calling function will trim the data when we return.
		startIndex += consumed
		contentLengthRemaining -= consumed
		
		// update the handler with our newly parsed content (if any). if we've read all of the content,
		// also notify the caller and clear out this request so we can start on the next request.
		if values.isEmpty == false {
			if contentLengthRemaining == 0 {
				request?.contentHandler?(values, true)
				connectionState = .None
				self.request = nil
			}
			else {
				request?.contentHandler?(values, false)
			}
		}
	}
	
	private final func handleRequest(request: CJHttpServerRequest? = nil) {
		dispatch_async(queue) { [group, queue, requestHandler] in
			if let request = request {
				self.requests.append(request)
			}
			
			if self.requests.count == 1 {
				let request = self.requests[0]
				self.requests.removeFirst()
				dispatch_group_enter(group)
				dispatch_group_notify(group, queue) { [weak self] in self?.handleRequest() }
				self.log(request.method.rawValue + " " + request.path)
				requestHandler(self, request)
			}
		}
	}
	
	private final func log(string: String) {
		connection.log(string)
	}
	
}
