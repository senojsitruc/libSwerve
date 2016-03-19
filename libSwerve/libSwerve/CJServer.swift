//
//  CJServer.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation
import Security

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
	var readHandler2: CJConnectionReadHandler2? { get set }
	var closeHandler: ((CJConnection) -> Void)? { get set }
	
	func open()
	func close()
	func pause()
	func resume()
	
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

public protocol CJTlsConnection: CJConnection {
	
	var tlsIdentity: SecIdentity? { get set }
	var tlsContext: SSLContext? { get set }
	
	var tlsObject: AnyObject { get }
	var tlsReadHandler: SSLReadFunc { get }
	var tlsWriteHandler: SSLWriteFunc { get }
	
	mutating func setupTLS() -> Bool
	mutating func startTLS() -> Bool
	
	func tlsReadCallback(connection: SSLConnectionRef, data: UnsafeMutablePointer<Void>, dataLength: UnsafeMutablePointer<Int>) -> OSStatus
	func tlsWriteCallback(connection: SSLConnectionRef, data: UnsafePointer<Void>, dataLength: UnsafeMutablePointer<Int>) -> OSStatus
	
}

extension CJTlsConnection {
	
	mutating func setupTLS() -> Bool {
		var status: OSStatus = 0
		
		guard let tlsIdentity = self.tlsIdentity else {
			DLog("self.tlsIdentity must be configured before setupTLS() is called.")
			return false
		}
		
		// create the new ssl context
		guard let tlsContext = SSLCreateContext(nil, .ServerSide, .StreamType) else {
			DLog("Failed to SSLCreateContext!")
			return false
		}
		
		// configure our callback functions
		status = SSLSetIOFuncs(tlsContext, tlsReadHandler, tlsWriteHandler)
		if status != errSecSuccess { DLog("Failed to SSLSetIOFuncs(), \(status)"); return false }
		
		// disable unsecure protocol versions
		status = SSLSetProtocolVersionMin(tlsContext, .TLSProtocol11)
		if status != errSecSuccess { DLog("Failed to SSLSetProtocolVersionMin(), \(status)"); return false }
		
		// set the context object
		status = SSLSetConnection(tlsContext, UnsafePointer<Void>(Unmanaged.passUnretained(tlsObject).toOpaque()))
		if status != errSecSuccess { DLog("Failed to SSLSetConnection(), \(status)"); return false }
		
		// disable certificate authentication
		status = SSLSetSessionOption(tlsContext, .BreakOnServerAuth, true)
		if status != errSecSuccess { DLog("Failed to SSLSetSessionOption(.BreakOnServerAuth), \(status)"); return false }
		
		// configure the server certificate
		status = SSLSetCertificate(tlsContext, [tlsIdentity] as CFArray)
		if status != errSecSuccess { DLog("Failed to SSLSetCertificate(), \(status)"); return false }
		
//		// enable resumable ssl connections
//		status = SSLSetPeerID(tlsContext, <#T##peerID: UnsafePointer<Void>##UnsafePointer<Void>#>, <#T##peerIDLen: Int##Int#>)
//		if status != errSecSuccess { DLog("Failed to SSLSetPeerID(), \(status)"); return false }
		
		self.tlsIdentity = tlsIdentity
		self.tlsContext = tlsContext
		
		return true
	}
	
	func startTLS() -> Bool {
		var status: OSStatus = 0
		
		guard let tlsContext = self.tlsContext else {
			DLog("You may not call startTLS() until after you call setupTLS().")
			return false
		}
		
		status = SSLHandshake(tlsContext)
		
		// this'll happen every time if our server certificate is not "authentic" (ie, paid for with
		// the moneyz); we'll make it work either way though
		if status == errSSLPeerAuthCompleted {
			var peerTrust: SecTrust?
			var trustResult: SecTrustResultType = 0
			
			// get the peer trust
			status = SSLCopyPeerTrust(tlsContext, &peerTrust)
			if status != errSecSuccess || peerTrust == nil { DLog("Failed to SSLCopyPeerTrust(), \(status)"); return false }
			
			// we'll allow expired certs
			status = SecTrustSetOptions(peerTrust!, .AllowExpired)
			if status != errSecSuccess { DLog("Failed to SecTrustSetOption(.AllowExpired), \(status)"); return false }
			
			// evaluate trust for the certificate
			status = SecTrustEvaluate(peerTrust!, &trustResult)
			if status != errSecSuccess { DLog("Failed to SecTrustEvaluate(), \(status)"); return false }
			
			// explicitly trusted (eg, user clicked always trust) or otherwise valid due to ca
			if trustResult == UInt32(kSecTrustResultProceed) || trustResult == UInt32(kSecTrustResultUnspecified) {
				status = SSLHandshake(tlsContext)
				//DLog("SSLHandshake() = \(status)")
			}
				
			// not trusted for reason other than expiration
			else if trustResult == UInt32(kSecTrustResultRecoverableTrustFailure) {
				DLog("Bad cert [1]")
				return false
			}
			else {
				DLog("Bad cert [1]")
				return false
			}
		}
		
		return status == noErr
	}
	
}

public protocol CJTlsSocketConnection: CJTlsConnection, CJSocketConnection {
	
}

public typealias CJConnectionReadHandler = (UnsafePointer<Void>, Int) -> Void
public typealias CJConnectionReadHandler2 = (dispatch_data_t, Int) -> Void

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
