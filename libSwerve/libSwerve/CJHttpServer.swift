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
public typealias CJHttpServerRequestPathEqualsHandler = (CJHttpServerRequest, CJHttpServerResponseHandler) -> Void
public typealias CJHttpServerRequestPathLikeHandler = ([String], CJHttpServerRequest, CJHttpServerResponseHandler) -> Void
public typealias CJHttpConnectionRequestHandler = (CJHttpConnection, CJHttpServerRequest) -> Void

public struct CJHttpHeader {
	var name: String
	var values = [String]()
	var value: String? { return values.first }
	
	init(headerString: String) {
		name = ""
		
		// TODO: parse header string
		
	}
}

public protocol CJHttpConnection {
	
	init(connection: CJConnection, requestHandler: CJHttpConnectionRequestHandler)
	
}

public protocol CJHttpServerRequest {
	
//	func readJsonObject() -> AnyObject?
//	func readXmlObject() -> AnyObject?
//	func readDataObject() -> AnyObject?
//	func readStringObject() -> AnyObject?
	
}

public protocol CJHttpServerResponse {
	
}

public protocol CJHttpServer {
	
	init(server: CJServer)
	
	mutating func start(completionHandler: (Bool, NSError?) -> Void)
	mutating func stop(completionHandler: (Bool, NSError?) -> Void)
	
	mutating func addHandler(method: CJHttpMethod, pathEquals: String, handler: CJHttpServerRequestPathEqualsHandler)
	mutating func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler)
	
}
