//
//  CJHttpServerResponseImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.19.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

internal class CJHttpServerResponseImpl: CJHttpServerResponse {
	
	var headers = [String: CJHttpHeader]()
	
	private var firstWrite = true
	private let connection: CJHttpConnection
	private var request: CJHttpServerRequest
	
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
		
		guard request.headers["Connection"]?.value?.lowercaseString == "keep-alive" else {
			connection.close()
			return
		}
	}
	
	func close() {
		connection.close()
	}
	
	private final func writeHeaders() {
		var headerString = "HTTP/1.1 200 OK\r\n"
		headers.forEach { _, header in headerString += header.makeHeaderString() }
		headerString += "\r\n"
		connection.write(headerString)
	}
	
}
