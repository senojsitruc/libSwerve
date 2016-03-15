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
	public static let None = CJHttpMethod(rawValue: 0)
	public static let Get  = CJHttpMethod(rawValue: 1 << 0)
	public static let Post = CJHttpMethod(rawValue: 1 << 1)
}

public typealias CJHttpServerResponseHandler = (CJHttpServerResponse) -> Void
public typealias CJHttpServerRequestPathEqualsHandler = (CJHttpServerRequest, CJHttpServerResponseHandler) -> Void
public typealias CJHttpServerRequestPathLikeHandler = ([String], CJHttpServerRequest, CJHttpServerResponseHandler) -> Void

public protocol CJHttpServerRequest {
	
}

public protocol CJHttpServerResponse {
	
}

public protocol CJHttpServer: CJServer {
	
	init(port: Int16)
	
	mutating func addHandler(method: CJHttpMethod, pathEqual: String, handler: CJHttpServerRequestPathEqualsHandler)
	mutating func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler)
	
}
