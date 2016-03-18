//
//  CJHttpServer1.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

private enum ConnectionState {
	case None
	case Header
	case Body
	case Done
}





internal struct CJHttpServerRequestImpl: CJHttpServerRequest {
	
	var method: CJHttpMethod
	var path: String
	var query: String
	var version: String
	var headers = [String: CJHttpHeader]()
	
	private let completionHandler: (() -> Void)?
	
	init(methodName: String, path: String, version: String, completionHandler: (() -> Void)?) {
		self.completionHandler = completionHandler
		
		if methodName == "GET" {
			method = .Get
		}
		else if methodName == "POST" {
			method = .Post
		}
		else {
			method = .None
		}
		
		// separate the path from the query (if any)
		do {
			if let qrange = path.rangeOfString("?") {
				self.path = path.substringToIndex(qrange.startIndex)
				self.query = path.substringFromIndex(qrange.startIndex)
			}
			else {
				self.path = path
				self.query = ""
			}
		}
		
		self.version = version
	}
	
	mutating func addHeader(header: CJHttpHeader) {
		guard var existingHeader = headers[header.name] else {
			headers[header.name] = header
			return
		}
		
		existingHeader.mergeHeader(header)
		headers[header.name] = existingHeader
	}
	
	///
	/// called by the response when the response is complete
	///
	func cleanup() {
		completionHandler?()
	}
}





internal class CJHttpServerResponseImpl: CJHttpServerResponse {
	
	var headers = [String: CJHttpHeader]()
	
	private var firstWrite = true
	private let connection: CJHttpConnection
	private let request: CJHttpServerRequest
	
	required init(connection: CJHttpConnection, request: CJHttpServerRequest) {
		self.connection = connection
		self.request = request
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int) {
		if firstWrite == true {
			firstWrite = false
			writeHeaders()
		}
		
		connection.write(bytes, size: size)
	}
	
	func finish() {
		request.cleanup()
		
		guard request.headers["Connection"]?.value == "keep-alive" else {
			connection.close()
			return
		}
	}
	
	func close() {
		connection.close()
	}
	
	private final func writeHeaders() {
//		connection.write("HTTP/1.1 200 OK\r\n")
		
		var headerString = "HTTP/1.1 200 OK\r\n"
		headers.forEach { _, header in headerString += header.makeHeaderString() }
		headerString += "\r\n"
		connection.write(headerString)
		
//		headers.forEach { _, header in
//			connection.write(header.makeHeaderString())
//		}
//		
//		connection.write("\r\n")
	}
	
}





private protocol Handler {
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> Bool
	
}

private struct PathEqualsHandler: Handler {
	
	let method: CJHttpMethod
	let path: String
	let handler: CJHttpServerRequestPathEqualsHandler
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> Bool {
		if request.path == path {
			handler(request, response)
			return true
		}
		else {
			return false
		}
	}
	
}

private struct PathLikeHandler: Handler {
	
	let method: CJHttpMethod
	let regex: NSRegularExpression
	let handler: CJHttpServerRequestPathLikeHandler
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> Bool {
		let path = request.path
		var values = [String]()
		
		guard let result = regex.firstMatchInString(path, options: NSMatchingOptions(rawValue: 0), range: NSMakeRange(0, request.path.characters.count)) else { return false }
		
		for index in 0..<result.numberOfRanges {
			guard let range = path.rangeFromNSRange(result.rangeAtIndex(index)) else { continue }
			values.append(path.substringWithRange(range))
		}
		
		handler(values, request, response)
		
		return true
	}
	
}





internal class CJHttpConnectionImpl: CJHttpConnection {
	
	private var connection: CJConnection
	private let requestHandler: CJHttpConnectionRequestHandler
	private var connectionState: ConnectionState = .None
	
	private var tmpdata = ""
	private var request: CJHttpServerRequest?
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJHttpConnectionImpl.queue", DISPATCH_QUEUE_SERIAL)
	private let group = dispatch_group_create()
	
	required init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler) {
		self.requestHandler = requestHandler
		self.connection = connection
		self.connection.readHandler = { [weak self, queue, group] data, leng in
			guard let _self = self else { return }
			
			//hexdump(UnsafePointer<UInt8>(data), Int32(leng))
			
			// concatenate any buffered data with this new data
			_self.tmpdata += String(data: NSData(bytes: data, length: leng), encoding: NSUTF8StringEncoding) ?? ""
//		_self.tmpdata += String(CString: UnsafePointer<CChar>(data), encoding: NSUTF8StringEncoding) ?? ""
			
			//DLog("tmpdata [\(_self.tmpdata.characters.count)] = \(_self.tmpdata)")
			
			// we'll update this index as we run through the string instead of repeatedly substring()'ing
			var startIndex = _self.tmpdata.startIndex
			
			// parse a single request, up to the limits of our buffered data
			while (startIndex < _self.tmpdata.endIndex) {
				///
				/// Preface | GET /test.php HTTP/1.1\r\n
				///
				if _self.connectionState == .None {
					// get the next newline (if any); return if we can't find one
					guard let nlrange = _self.tmpdata.rangeOfString("\r\n", options: NSStringCompareOptions(rawValue: 0), range: Range<String.Index>(startIndex..<_self.tmpdata.endIndex), locale: nil) else {
						break
					}
					
					// get the first line
					let line = _self.tmpdata.substringWithRange(Range<String.Index>(startIndex..<nlrange.startIndex))
					
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
					
					// trim the line from the buffer (including the newline characters)
					startIndex = nlrange.endIndex
					
					// we got the 1st line; let's move on to the header
					_self.connectionState = .Header
				}
					
				///
				/// Headers | Host: 127.0.0.1:8080\r\nUser-Agent: curl/7.43.0\r\nAccept: */*\r\n\r\n
				///
				else if _self.connectionState == .Header {
					// get the next newline (if any); return if we can't find one
					guard let nlrange = _self.tmpdata.rangeOfString("\r\n", options: NSStringCompareOptions(rawValue: 0), range: Range<String.Index>(startIndex..<_self.tmpdata.endIndex), locale: nil) else {
						break
					}
					
					// get the first line
					let line = _self.tmpdata.substringWithRange(Range<String.Index>(startIndex..<nlrange.startIndex))
					
					// trim the line from the buffer (including the newline characters)
					startIndex = nlrange.endIndex
					
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
		
			_self.tmpdata = _self.tmpdata.substringFromIndex(startIndex)
		}
	}
	
	func close() {
		connection.closeConnection()
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int) {
		connection.write(bytes, size: size, completionHandler: nil)
	}
	
}





internal class CJHttpServerImpl: CJHttpServer {
	
	private var handlers = [Handler]()
	private var server: CJServer!
	
	required init(server: CJServer) {
		self.server = server
	}
	
	func start(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() {
			var success = false
			var nserror: NSError?
			
			defer { CJDispatchMain() { completionHandler(success, nserror) } }
			
			let requestHandler: CJHttpConnectionRequestHandler = { [weak self] connection, request in
				var matched = false
				let response = CJSwerve.httpResponseType.init(connection: connection, request: request)
				
				for handler in self?.handlers ?? [] {
					if handler.matches(connection, request, response) == true { matched = true; break }
				}
				
				if matched == false {
					DLog("No handler match found; closing connection [\(request)]")
					connection.close()
				}
			}
			
			// link new connections to http connection objects
			self.server.acceptHandler = { connection in
				var c = connection
				c.context = CJSwerve.httpConnectionType.init(connection: connection, requestHandler: requestHandler)
			}
			
			do {
				try self.server.start()
				success = true
			}
			catch let e as NSError {
				nserror = e
			}
			catch {
				nserror = NSError(description: "Start failed for an unknown reason.")
			}
		}
	}
	
	func stop(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() {
			var success = false
			var nserror: NSError?
			
			defer {
				self.server = nil
				CJDispatchMain() { completionHandler(success, nserror) }
			}
			
			do {
				try self.server.stop()
				success = true
			}
			catch let e as NSError {
				nserror = e
			}
			catch {
				nserror = NSError(description: "Failed for an unknown reason!")
			}
		}
	}
	
	func addHandler(method: CJHttpMethod, pathEquals path: String, handler: CJHttpServerRequestPathEqualsHandler) {
		handlers.append(PathEqualsHandler(method: method, path: path, handler: handler))
	}
	
	func addHandler(method: CJHttpMethod, pathLike pattern: String, handler: CJHttpServerRequestPathLikeHandler) {
		do {
			let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpressionOptions(rawValue: 0))
			handlers.append(PathLikeHandler(method: method, regex: regex, handler: handler))
		}
		catch {
			DLog("Failed to install handler because of invalid regex pattern: \(pattern)")
		}
	}
	
	func addFileModule(localPath _lp: String, webPath _wp: String, recurses: Bool) {
		let localPath = _lp.hasSuffix("/") ? _lp : (_lp + "/")
		let webPath = _wp.hasSuffix("/") ? _wp.substringToIndex(_wp.endIndex.predecessor()) : _wp
		let fileManager = NSFileManager()
		
		self.addHandler(.Get, pathLike: "^\(webPath)/(.*)$") { values, request, response in
			// DLog("values = \(values)")
			
			let path = values.count == 2 ? values[1] : ""
			
			// prevent the user from escaping the base directory
			if path.rangeOfString("..") != nil {
				response.finish()
				response.close()
				return
			}
			
			CJDispatchBackground() {
				var response = response
				
				// assemble the file path
				let fileName = path
				let fileType = (fileName as NSString).pathExtension.lowercaseString
				let filePath = localPath + fileName
				
				//DLog("filePath = \(filePath)")
				
				var isdir: ObjCBool = false
				let exists = fileManager.fileExistsAtPath(filePath, isDirectory: &isdir)
				
				if exists == false {
					response.finish()
					response.close()
					return
				}
				
				if Bool(isdir) == true {
					do {
						var page = "<html><body>"
						
						for fileName in try fileManager.contentsOfDirectoryAtPath(filePath) {
							if fileName.hasPrefix(".") == false {
								page += "<a href=\"\(fileName.stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet()) ?? "")\">\(fileName)</a><br>"
							}
						}
						
						page += "</body></html>"
						
						guard let fileData = page.dataUsingEncoding(NSUTF8StringEncoding) else {
							response.finish()
							response.close()
							return
						}
						
						// configure and send the response
						response.addHeader("Content-Type", value: "text/html")
						response.addHeader("Content-Length", value: fileData.length)
						response.addHeader("Connection", value: "keep-alive")
						response.write(fileData)
					}
					catch {
						DLog("Failed to read directory contents [filePath = \(filePath)]")
					}
				}
				else {
					// close the connection if the target file doesn't exist
					guard let fileData = NSData(contentsOfFile: filePath) else {
						response.finish()
						response.close()
						return
					}
					
					// configure and send the response
					response.addHeader("Content-Type", value: CJMimeTypeForExtension(fileType) ?? "content/octet-stream")
					response.addHeader("Content-Length", value: fileData.length)
					response.addHeader("Connection", value: "keep-alive")
					response.write(fileData)
				}
				
				response.finish()
			}
		}
	}
	
}
