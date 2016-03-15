//
//  CJHttpServer.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

struct CJHttpMethod : OptionSetType {
	let rawValue: Int
	static let None = CJHttpMethod(rawValue: 0)
	static let Get  = CJHttpMethod(rawValue: 1 << 0)
	static let Post = CJHttpMethod(rawValue: 1 << 1)
}

typealias CJHttpServerResponseHandler = (CJHttpServerResponse) -> Void
typealias CJHttpServerRequestPathEqualsHandler = (CJHttpServerRequest, CJHttpServerResponseHandler) -> Void
typealias CJHttpServerRequestPathLikeHandler = ([String], CJHttpServerRequest, CJHttpServerResponseHandler) -> Void

protocol CJHttpServerRequest {
	
}

protocol CJHttpServerResponse {
	
}

protocol CJHttpServer: CJServer {
	
	func addHandler(method: CJHttpMethod, pathEqual: String, handler: CJHttpServerRequestPathEqualsHandler)
	func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler)
	
}
