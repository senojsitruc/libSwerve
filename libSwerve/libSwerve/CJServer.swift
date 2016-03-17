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

public protocol CJConnection {
	
	var context: Any? { get set }
	var readHandler: CJConnectionReadHandler? { get set }
	
	func open()
	func closeConnection()
	func pause()
	func resume(waitForWrites waitForWrites: Bool)
	
	func write(bytes: UnsafePointer<Void>, size: Int, completionHandler: ((Bool) -> Void)?)
	func write(data: NSData, completionHandler: ((Bool) -> Void)?)
	func write(string: String, completionHandler: ((Bool) -> Void)?)
	
}

extension CJConnection {
	
	func write(data: NSData, completionHandler: ((Bool) -> Void)?) {
		write(data.bytes, size: data.length, completionHandler: completionHandler)
	}
	
	func write(string: String, completionHandler: ((Bool) -> Void)?) {
		if let data = string.dataUsingEncoding(NSUTF8StringEncoding) {
			write(data, completionHandler: completionHandler)
		}
	}
	
}
public typealias CJConnectionReadHandler = (UnsafePointer<Void>, Int) -> Int

public typealias CJServerAcceptHandler = (CJConnection) -> Void

public protocol CJServer {
	
	var serverStatus: CJServerStatus { get }
	var acceptHandler: CJServerAcceptHandler? { get set }
	
	mutating func start() throws
	mutating func stop() throws
	
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
