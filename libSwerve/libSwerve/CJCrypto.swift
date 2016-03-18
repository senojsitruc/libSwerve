//
//  CJCrypto.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.17.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation
import Security

public final class CJCrypto {
	
	internal var identity: SecIdentity?
	
	///
	/// Generates a new key pair. If permanent, the key pair is stored in the default keychain. To
	/// use this keypair in a TLS context, the specified label can be used in a call to [some func].
	///
	internal class func generateKeyPair(keySize: Int = 4096, label: String, permanent: Bool = true) -> (SecKey, SecKey)? {
		var publicKey, privateKey: SecKey?
		var params = [String: AnyObject]()
		var status: OSStatus = 0
		
		params[String(kSecAttrLabel)] = label
		params[String(kSecAttrKeyType)] = kSecAttrKeyTypeRSA
		params[String(kSecAttrIsPermanent)] = permanent
		params[String(kSecAttrKeySizeInBits)] = keySize
		params[String(kSecAttrApplicationTag)] = NSData(base64EncodedString: label, options: NSDataBase64DecodingOptions(rawValue: 0))
//	params[String(kSecPublicKeyAttrs)] = [String(kSecAttrIsPermanent): true, String(kSecAttrApplicationTag): label]
//	params[String(kSecPrivateKeyAttrs)] = [String(kSecAttrIsPermanent): true, String(kSecAttrApplicationTag): label]
		
		status = SecKeyGeneratePair(params, &publicKey, &privateKey)
		
		if status != 0 {
			DLog("Failed to SecKeyGeneratePair(), \(status)")
			return nil
		}
		
		if publicKey == nil || privateKey == nil {
			DLog("Failed to generate key pair.")
			return nil
		}
		
		return (publicKey!, privateKey!)
	}
	
	///
	/// Returns the idetnity matching the specified label (from the keychain).
	///
	internal class func identityWithLabel(label: String) -> SecIdentity? {
		var query = [String: AnyObject]()
		var result: AnyObject?
		var status: OSStatus = 0
		
		query[String(kSecReturnRef)] = true
		query[String(kSecClass)] = kSecClassIdentity
		query[String(kSecAttrLabel)] = label
		query[String(kSecMatchLimit)] = kSecMatchLimitAll
//	query[String(kSecAttrApplicationTag)] = NSData(base64EncodedString: label, options: NSDataBase64DecodingOptions(rawValue: 0))
		
		status = SecItemCopyMatching(query, &result)
		
		if status != 0 || result == nil {
			DLog("Failed to SecItemCopyMatching(), \(status)")
			return nil
		}
		
		// enumerate the returned identities and find the one with the appropriate common name, because
		// the keychain api is severely screwed up and doesn't actually filter on its own.
		for identity in (result as! [SecIdentity]) {
			if SecIdentityGetTypeID() == CFGetTypeID(identity) {
//			DLog("commonName = \(identity.commonName)")
				if identity.commonName == label {
					return identity
				}
			}
		}
		
		return nil
	}
	
	///
	/// Returns the identity for the given pkcs12 file.
	///
	internal class func identityFromFile(pkcs12FilePath filePath: String, passphrase: String) -> SecIdentity? {
		guard let keyData = NSData(contentsOfFile: filePath) where keyData.length > 0 else {
			DLog("Failed to read file [filePath = \(filePath)]")
			return nil
		}
		
		var options = [String: AnyObject]()
		var items: CFArray?
		var status: OSStatus = 0
		
		options[kSecImportExportPassphrase as String] = passphrase
		
		status = SecPKCS12Import(keyData, options, &items)
		
		if status != 0 {
			DLog("Failed to SecPKCS12Import(), \(status)")
			return nil
		}
		
		if items == nil {
			DLog("SecPKCS12Import() succeeded, but we didn't get any data!")
			return nil
		}
		
		let dict = CFArrayGetValueAtIndex(items, 0) as! CFDictionary
		let identity = CFDictionaryGetValue(dict, "identity") as! SecIdentity
		
		return identity
	}
	
	///
	/// Returns an identity for the given key pair.
	///
	internal class func identityWithKeyPair(publicKey: SecKey, privateKey: SecKey) -> SecIdentity? {
		var query = [String: AnyObject]()
		var result: AnyObject?
		var status: OSStatus = 0
		
		query[String(kSecReturnRef)] = true
		query[String(kSecClass)] = kSecClassIdentity
		query[String(kSecMatchItemList)] = [publicKey, privateKey]
		
		status = SecItemCopyMatching(query, &result)
		
		if status != 0 || result == nil {
			DLog("Failed to SecItemCopyMatching(), \(status)")
			return nil
		}
		
		return result as! SecIdentity?
	}
	
	
	
	
	
	///
	///
	///
	internal class func keyData(key: SecKey) -> NSData? {
		var query = [String: AnyObject]()
		var result: AnyObject?
		var status: OSStatus = 0
		
		query[String(kSecReturnData)] = true
		query[String(kSecClass)] = kSecClassKey
//	query[String(kSecAttrLabel)] = label
//	query[String(kSecAttrApplicationTag)] = NSData(base64EncodedString: label, options: NSDataBase64DecodingOptions(rawValue: 0))
		query[String(kSecMatchItemList)] = [key]
		
		status = SecItemCopyMatching(query, &result)
		
		if status != 0 || result == nil {
			DLog("Failed to SecItemCopyMatching(), \(status)")
			return nil
		}
		
		return result as! NSData?
	}
	
	
	
	
	
	///
	/// Setup TLS using the given public / private key pair.
	///
	final func setupTLS(publicKey: SecKey, privateKey: SecKey) -> Bool {
		guard let identity = CJCrypto.identityWithKeyPair(publicKey, privateKey: privateKey) else {
			DLog("Could not create identity for the given key pair.")
			return false
		}
		
		self.identity = identity
		
		return true
	}
	
	///
	/// Setup TLS using a certificate in the keychain with the given label.
	///
	final func setupTLS(label: String) -> Bool {
		guard let identity = CJCrypto.identityWithLabel(label) else {
			DLog("Could not find identity [label = \(label)]")
			return false
		}
		
		self.identity = identity
		
		return true
	}
	
	///
	/// Setup TLS using a certificate in the given PKCS12 file.
	///
	final func setupTLS(pkcs12FilePath filePath: String, passphrase: String) -> Bool {
		guard let identity = CJCrypto.identityFromFile(pkcs12FilePath: filePath, passphrase: passphrase) else {
			DLog("Could not get identity [filePath = \(filePath)]")
			return false
		}
		
		self.identity = identity
		
		return true
	}
	
}





///
/// https://github.com/henrinormak/Heimdall
///
/*
private extension NSData {
	
	convenience init(modulus: NSData, exponent: NSData) {
		// Make sure neither the modulus nor the exponent start with a null byte
		var modulusBytes = [CUnsignedChar](UnsafeBufferPointer<CUnsignedChar>(start: UnsafePointer<CUnsignedChar>(modulus.bytes), count: modulus.length / sizeof(CUnsignedChar)))
		let exponentBytes = [CUnsignedChar](UnsafeBufferPointer<CUnsignedChar>(start: UnsafePointer<CUnsignedChar>(exponent.bytes), count: exponent.length / sizeof(CUnsignedChar)))
		
		// Make sure modulus starts with a 0x00
		if let prefix = modulusBytes.first where prefix != 0x00 {
			modulusBytes.insert(0x00, atIndex: 0)
		}
		
		// Lengths
		let modulusLengthOctets = modulusBytes.count.encodedOctets()
		let exponentLengthOctets = exponentBytes.count.encodedOctets()
		
		// Total length is the sum of components + types
		let totalLengthOctets = (modulusLengthOctets.count + modulusBytes.count + exponentLengthOctets.count + exponentBytes.count + 2).encodedOctets()
		
		// Combine the two sets of data into a single container
		var builder: [CUnsignedChar] = []
		let data = NSMutableData()
		
		// Container type and size
		builder.append(0x30)
		builder.appendContentsOf(totalLengthOctets)
		data.appendBytes(builder, length: builder.count)
		builder.removeAll(keepCapacity: false)
		
		// Modulus
		builder.append(0x02)
		builder.appendContentsOf(modulusLengthOctets)
		data.appendBytes(builder, length: builder.count)
		builder.removeAll(keepCapacity: false)
		data.appendBytes(modulusBytes, length: modulusBytes.count)
		
		// Exponent
		builder.append(0x02)
		builder.appendContentsOf(exponentLengthOctets)
		data.appendBytes(builder, length: builder.count)
		data.appendBytes(exponentBytes, length: exponentBytes.count)
		
		self.init(data: data)
	}
	
	func splitIntoComponents() -> (modulus: NSData, exponent: NSData)? {
		// Get the bytes from the keyData
		let pointer = UnsafePointer<CUnsignedChar>(self.bytes)
		let keyBytes = [CUnsignedChar](UnsafeBufferPointer<CUnsignedChar>(start:pointer, count:self.length / sizeof(CUnsignedChar)))
		
		// Assumption is that the data is in DER encoding
		// If we can parse it, then return successfully
		var i: NSInteger = 0
		
		// First there should be an ASN.1 SEQUENCE
		if keyBytes[0] != 0x30 {
			return nil
		} else {
			i += 1
		}
		
		// Total length of the container
		if let _ = NSInteger(octetBytes: keyBytes, startIdx: &i) {
			// First component is the modulus
			if keyBytes[i++] == 0x02, let modulusLength = NSInteger(octetBytes: keyBytes, startIdx: &i) {
				let modulus = self.subdataWithRange(NSMakeRange(i, modulusLength))
				i += modulusLength
				
				// Second should be the exponent
				if keyBytes[i++] == 0x02, let exponentLength = NSInteger(octetBytes: keyBytes, startIdx: &i) {
					let exponent = self.subdataWithRange(NSMakeRange(i, exponentLength))
					i += exponentLength
					
					return (modulus, exponent)
				}
			}
		}
		
		return nil
	}
	
	func dataByPrependingX509Header() -> NSData {
		let result = NSMutableData()
		
		let encodingLength: Int = (self.length + 1).encodedOctets().count
		let OID: [CUnsignedChar] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
		                            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
		
		var builder: [CUnsignedChar] = []
		
		// ASN.1 SEQUENCE
		builder.append(0x30)
		
		// Overall size, made of OID + bitstring encoding + actual key
		let size = OID.count + 2 + encodingLength + self.length
		let encodedSize = size.encodedOctets()
		builder.appendContentsOf(encodedSize)
		result.appendBytes(builder, length: builder.count)
		result.appendBytes(OID, length: OID.count)
		builder.removeAll(keepCapacity: false)
		
		builder.append(0x03)
		builder.appendContentsOf((self.length + 1).encodedOctets())
		builder.append(0x00)
		result.appendBytes(builder, length: builder.count)
		
		// Actual key bytes
		result.appendData(self)
		
		return result as NSData
	}
	
	func dataByStrippingX509Header() -> NSData {
		var bytes = [CUnsignedChar](count: self.length, repeatedValue: 0)
		self.getBytes(&bytes, length:self.length)
		
		var range = NSRange(location: 0, length: self.length)
		var offset = 0
		
		// ASN.1 Sequence
		if bytes[offset++] == 0x30 {
			// Skip over length
			let _ = NSInteger(octetBytes: bytes, startIdx: &offset)
			
			let OID: [CUnsignedChar] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
			                            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
			let slice: [CUnsignedChar] = Array(bytes[offset..<(offset + OID.count)])
			
			if slice == OID {
				offset += OID.count
				
				// Type
				if bytes[offset++] != 0x03 {
					return self
				}
				
				// Skip over the contents length field
				let _ = NSInteger(octetBytes: bytes, startIdx: &offset)
				
				// Contents should be separated by a null from the header
				if bytes[offset++] != 0x00 {
					return self
				}
				
				range.location += offset
				range.length -= offset
			} else {
				return self
			}
		}
		
		return self.subdataWithRange(range)
	}
	
}
*/
