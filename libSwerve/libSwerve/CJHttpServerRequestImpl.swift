//
//  CJHttpServerRequestImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.19.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

internal class CJHttpServerRequestImpl: CJHttpServerRequest {
	
	var method: CJHttpMethod
	var path: String
	var query: String
	var version: String
	var headers = [String: CJHttpHeader]()
	var values: [String: AnyObject]?
	
	var contentHandler: ((AnyObject?, Bool) -> Void)?
	
	private var connection: CJHttpConnection?
	private var completionHandler: (() -> Void)?
	
	required init(methodName: String, path: String, version: String, connection: CJHttpConnection?, completionHandler: (() -> Void)?) {
		self.connection = connection
		self.completionHandler = completionHandler
		
		method = CJHttpMethod(rawValue: methodName ?? "") ?? .None
		
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
	
	func addHeader(header: CJHttpHeader) {
		guard var existingHeader = headers[header.name] else {
			headers[header.name] = header
			return
		}
		
		existingHeader.mergeHeader(header)
		headers[header.name] = existingHeader
	}
	
	///
	/// A connection is paused when the header is received and we need to the "user" to configure the
	/// request for receiving whatever data may follow. Thus, after configuring the request, the user
	/// will call resume(), and we'll telling the http connection to resume() which'll tell the under-
	/// lying tcp connection to resume.
	///
	func resume() {
		connection?.resume()
	}
	
	///
	/// called by the response when the response is complete
	///
	func cleanup() {
		completionHandler?()
		completionHandler = nil
		connection = nil
	}
	
}
