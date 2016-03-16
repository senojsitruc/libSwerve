//
//  CJServer.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

public struct CJServerStatus: OptionSetType {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }
	static let None     = CJServerStatus(rawValue:      0)
	static let Starting = CJServerStatus(rawValue: 1 << 0)
	static let Running  = CJServerStatus(rawValue: 2 << 0)
	static let Stopping = CJServerStatus(rawValue: 3 << 0)
	static let Stopped  = CJServerStatus(rawValue: 4 << 0)
}

public protocol CJServer {
	
	var serverStatus: CJServerStatus { get }
	
	mutating func start(completionHandler: (Bool, NSError?) -> Void)
	mutating func stop(completionHandler: (Bool, NSError?) -> Void)
	
}

///
/// http://codereview.stackexchange.com/questions/71861/pure-swift-solution-for-socket-programming
///
internal func CJAddrToString(addr: in_addr, family: sa_family_t) -> String? {
	var addrstr = [CChar](count:Int(INET_ADDRSTRLEN), repeatedValue: 0)
	var addr = addr
	
	inet_ntop(Int32(family), &addr, &addrstr, socklen_t(INET6_ADDRSTRLEN))
	
	return String.fromCString(addrstr)
}
