//
//  CJHttpServerRequestImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.19.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

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
