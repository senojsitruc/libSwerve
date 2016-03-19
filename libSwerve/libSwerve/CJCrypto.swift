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
	
	internal static var identity: SecIdentity?
	
	///
	/// Generates a self-signed certificate.
	///
	public class func generateIdentity(keySizeInBits bits: UInt, label: String, password: String = "drowssap") -> SecIdentity? {
		return SecIdentity.create(numberOfBits: bits, label: label, password: password, error: nil)
	}
	
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
	public class func identityWithLabel(label: String) -> SecIdentity? {
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
	public class func setupTLS(publicKey: SecKey, privateKey: SecKey) -> Bool {
		guard let identity = CJCrypto.identityWithKeyPair(publicKey, privateKey: privateKey) else {
			DLog("Could not create identity for the given key pair.")
			return false
		}
		
		CJCrypto.identity = identity
		
		return true
	}
	
	///
	/// Setup TLS using a certificate in the keychain with the given label.
	///
	public class func setupTLS(label: String) -> Bool {
		guard let identity = CJCrypto.identityWithLabel(label) else {
			DLog("Could not find identity [label = \(label)]")
			return false
		}
		
		CJCrypto.identity = identity
		
		return true
	}
	
	///
	/// Setup TLS using a certificate in the given PKCS12 file.
	///
	public class func setupTLS(pkcs12FilePath filePath: String, passphrase: String) -> Bool {
		guard let identity = CJCrypto.identityFromFile(pkcs12FilePath: filePath, passphrase: passphrase) else {
			DLog("Could not get identity [filePath = \(filePath)]")
			return false
		}
		
		CJCrypto.identity = identity
		
		return true
	}
	
	///
	///
	///
	public class func setupTLS(identity: SecIdentity) {
		CJCrypto.identity = identity
	}
	
}
