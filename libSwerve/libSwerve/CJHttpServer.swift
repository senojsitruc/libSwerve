//
//  CJHttpServer.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

public struct CJHttpMethod: OptionSetType {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }
	public static let None = CJHttpMethod(rawValue:      0)
	public static let Get  = CJHttpMethod(rawValue: 1 << 0)
	public static let Post = CJHttpMethod(rawValue: 1 << 1)
}

public typealias CJHttpServerResponseHandler = (CJHttpServerResponse) -> Void
public typealias CJHttpServerResponseDataSourceHandler = (inout Bool) -> NSData?
public typealias CJHttpServerRequestPathEqualsHandler = (CJHttpServerRequest, CJHttpServerResponse) -> Void
public typealias CJHttpServerRequestPathLikeHandler = ([String], CJHttpServerRequest, CJHttpServerResponse) -> Void
public typealias CJHttpConnectionRequestHandler = (CJHttpConnection, CJHttpServerRequest) -> Void

public struct CJHttpHeader {
	var name: String
	var values = [String]()
	var value: String? {
		get {
			return values.first
		}
		set {
			values.removeAll()
			if let x = newValue { values.append(x) }
		}
	}
	
	init(headerString: String) {
		guard let csrange = headerString.rangeOfString(": ") else {
			self.name = headerString
			return
		}
		
		self.name = headerString.substringToIndex(csrange.startIndex)
		self.values.append(headerString.substringFromIndex(csrange.endIndex))
	}
	
	init(name: String, value: String?) {
		self.name = name
		self.value = value
	}
	
	mutating func mergeHeader(header: CJHttpHeader) { values += header.values }
	
	func makeHeaderString() -> String {
		var string = name + ": "
		
		for (index, value) in values.enumerate() {
			string += value
			
			if index < values.endIndex.predecessor() {
				string += "; "
			}
		}
		
		string += "\r\n"
		
		return string
	}
	
}

public protocol CJHttpConnection {
	
	init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler)
	
	func close()
	func resume()
	func resumeAfterWrites()
	
	func write(bytes: UnsafePointer<Void>, size: Int)
	func write(data: NSData)
	func write(string: String)
	
}

extension CJHttpConnection {
	
	func write(data: NSData) {
		write(data.bytes, size: data.length)
	}
	
	func write(string: String) {
		if let data = string.dataUsingEncoding(NSUTF8StringEncoding) {
			write(data)
		}
	}
	
}

public protocol CJHttpServerRequest {
	
//	func readJsonObject() -> AnyObject?
//	func readXmlObject() -> AnyObject?
//	func readDataObject() -> AnyObject?
//	func readStringObject() -> AnyObject?
	
	var method: CJHttpMethod { get set }
	var path: String { get set }
//var query: [String: String]()
	var query: String { get set }
	var version: String { get set }
	var headers: [String: CJHttpHeader] { get set }
	
	var contentLength: Int? { get set }
	
	init(methodName: String, path: String, version: String)
	
	mutating func addHeader(header: CJHttpHeader)
	
}

extension CJHttpServerRequest {
	
	var contentLength: Int? {
		get { return self.headerIntValue("Content-Length") }
		set { self.setHeaderValue("Content-Length", value: newValue) }
	}
	
	func headerIntValue(name: String) -> Int? { return Int(headers[name]?.value ?? "") }
	
	mutating func setHeaderValue(name: String, value: AnyObject?) {
		guard let value = value else {
			headers.removeValueForKey(name)
			return
		}
		
		guard var header = headers[name] else {
			headers[name] = CJHttpHeader(name: name, value: "\(value)")
			return
		}
		
		header.value = "\(value)"
	}
	
}

public protocol CJHttpServerResponse {
	
	var headers: [String: CJHttpHeader] { get set }
	
	init(connection: CJHttpConnection)
	
	mutating func addHeader(header: CJHttpHeader)
	mutating func addHeader(name: String, value: AnyObject)
	
	func write(bytes: UnsafePointer<Void>, size: Int)
	func write(data: NSData)
	func write(string: String)
	
	func finish()
	func close()
	
}

extension CJHttpServerResponse {
	
	mutating func addHeader(header: CJHttpHeader) {
		guard var existingHeader = headers[header.name] else {
			headers[header.name] = header
			return
		}
		
		existingHeader.mergeHeader(header)
		headers[header.name] = existingHeader
	}
	
	mutating func addHeader(name: String, value: AnyObject) {
		addHeader(CJHttpHeader(name: name, value: "\(value)"))
	}
	
	func write(data: NSData) {
		write(data.bytes, size: data.length)
	}
	
	func write(string: String) {
		if let data = string.dataUsingEncoding(NSUTF8StringEncoding) {
			write(data)
		}
	}
	
}

public protocol CJHttpServer {
	
	init(server: CJServer)
	
	mutating func start(completionHandler: (Bool, NSError?) -> Void)
	mutating func stop(completionHandler: (Bool, NSError?) -> Void)
	
	mutating func addHandler(method: CJHttpMethod, pathEquals: String, handler: CJHttpServerRequestPathEqualsHandler)
	mutating func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler)
	
	func addFileModule(localPath localPath: String, webPath: String, recurses: Bool)
	
}
