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
}





private struct Request: CJHttpServerRequest {
	
}





private struct Response: CJHttpServerResponse {
	
}





private protocol Handler {
	
	func matches(request: Request) -> Bool
	
}

private struct PathEqualsHandler: Handler {
	
	let method: CJHttpMethod
	let path: String
	let handler: CJHttpServerRequestPathEqualsHandler
	
	func matches(request: Request) -> Bool {
		return false
	}
	
}

private struct PathLikeHandler: Handler {
	
	let method: CJHttpMethod
	let path: String
	let handler: CJHttpServerRequestPathLikeHandler
	
	func matches(request: Request) -> Bool {
		return false
	}
	
}





internal class CJHttpConnectionImpl: CJHttpConnection {
	
	private var connection: CJConnection
	private let requestHandler: CJHttpConnectionRequestHandler
	private var connectionState: ConnectionState = .None
	
	private var tmpdata = ""
	private var method = ""
	private var path = ""
	private var version = ""
	private var headers = [CJHttpHeader]()
	
	required init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler) {
		self.requestHandler = requestHandler
		self.connection = connection
		self.connection.readHandler = { [weak self] data, leng in
			guard let _self = self else { return 0 }
			
			// concatenate any buffered data with this new data
			_self.tmpdata += String(CString: UnsafePointer<CChar>(data), encoding: NSUTF8StringEncoding) ?? ""
			
			// we'll update this index as we run through the string instead of repeatedly substring()'ing
			var startIndex = _self.tmpdata.startIndex
			
			while (true) {
				///
				/// Preface | GET /test.php HTTP/1.1\r\n
				///
				if _self.connectionState == .None {
					// get the next newline (if any); return if we can't find one
					guard let nlrange = _self.tmpdata.rangeOfString("\r\n", options: NSStringCompareOptions(rawValue: 0), range: Range<String.Index>(startIndex..<_self.tmpdata.endIndex), locale: nil) else { break }
					
					// get the first line
					let line = _self.tmpdata.substringWithRange(Range<String.Index>(startIndex..<nlrange.startIndex))
					
					// the parts are separated by a single space each
					let parts = line.componentsSeparatedByCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
					
					// there should be precisely three parts (method, path and version)
					if parts.count != 3 {
						DLog("Unsupported 1st line; expected 3 parts: \(line)")
						connection.close()
						break
					}
					
					// grab the method, path and version
					_self.method = parts[0]
					_self.path = parts[1]
					_self.version = parts[2]
					
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
					guard let nlrange = _self.tmpdata.rangeOfString("\r\n", options: NSStringCompareOptions(rawValue: 0), range: Range<String.Index>(startIndex..<_self.tmpdata.endIndex), locale: nil) else { break }
					
					// get the first line
					let line = _self.tmpdata.substringWithRange(Range<String.Index>(startIndex..<nlrange.startIndex))
					
					// save the header without parsing it further
					_self.headers.append(CJHttpHeader(headerString: line))
					
					// trim the line from the buffer (including the newline characters)
					startIndex = nlrange.endIndex
					
					// we got a blank line; advance to the body (if any)
					if line.isEmpty == true { _self.connectionState = .Body }
				}
				
				///
				/// Body |
				///
				else if _self.connectionState == .Body {
					break
				}
			}
			
			_self.tmpdata = _self.tmpdata.substringFromIndex(startIndex)
			
			return leng
		}
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
			
			let requestHandler: CJHttpConnectionRequestHandler = { connection, request in
				
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
	
	func addHandler(method: CJHttpMethod, pathLike path: String, handler: CJHttpServerRequestPathLikeHandler) {
		handlers.append(PathLikeHandler(method: method, path: path, handler: handler))
	}
	
}
