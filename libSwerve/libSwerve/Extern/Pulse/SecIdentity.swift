import Security

extension SecIdentity {
	
	private class func identitySearchDict(keychainAttribute : String) -> [String:AnyObject] {
		let identitySearchDict: [String:AnyObject] = [
			kSecClass as String: kSecClassIdentity,
			kSecAttrLabel as String: keychainAttribute,
			kSecReturnRef as String: true]
		return identitySearchDict
	}
	
//	private class func keychainAttr() -> String {
//		let keychainAttr = "us.curtisjones.libSwerve.001"
//		return keychainAttr
//	}
//	
//	public class func myIdentity() -> SecIdentity? {
//		let attr = keychainAttr()
//		let storedIdentity : SecIdentity? = getStoredIdentity(attr)
//		if let myId = storedIdentity {
//			return myId
//		}
//		else {
//			var error : NSError? = nil
//			let newId : SecIdentity? = create(error:&error)
//			if let myId = newId {
//				if (storeIdentity(myId, attr)) {
//					return myId
//				}
//			}
//		}
//		return nil
//	}
//	
//	public class func deleteMyIdentity() {
//		let dict = identitySearchDict(keychainAttr())
//		SecItemDelete(dict)
//	}
	
	public class func getStoredIdentity(keychainAttribute : String) -> SecIdentity? {
		let dict = identitySearchDict(keychainAttribute)
		var out: AnyObject? = nil
		let resultCode = SecItemCopyMatching(dict, &out)
		if errSecSuccess != resultCode {
			return nil
		}
		return out as! SecIdentity?
	}
	
	public class func storeIdentity(identity : SecIdentity, _ keychainAttribute : String) -> Bool {
		let addDict: [String:AnyObject] = [kSecAttrLabel as String: keychainAttribute,
		                                   kSecValueRef as String: identity]
		let resultCode = SecItemAdd(addDict, nil)
		return errSecSuccess == resultCode
	}
	
	public class func create(numberOfBits bits: UInt = 4096, label: String, password: String, error: NSErrorPointer) -> SecIdentity? {
//	let pass = "pwd"
		let pkcs12Data : NSData
		do {
			pkcs12Data = try createPKCS12BlobUsingOpenSSL(password, bits: bits, label: label)
		}
		catch {
			return nil
		}
		
		let key: NSString = kSecImportExportPassphrase as NSString
		let options: NSDictionary = [key: password]
		var items: CFArray?
		let status = SecPKCS12Import(pkcs12Data, options, &items);
		if (errSecSuccess != status) {
			if error != nil {
//			error.memory = NSError(domain:PulseError.domain, code:PulseError.pkcs12ImportError, userInfo:nil)
				return nil
			}
			return nil
		}
		
		let its: NSArray = items! as NSArray
		let objects = its[0] as! NSDictionary
		let k2 = kSecImportItemIdentity as NSString
		return objects[k2] as! SecIdentityRef?
	}
	
	public var certificate: SecCertificate? {
		var uCert: SecCertificateRef?
		let status = SecIdentityCopyCertificate(self, &uCert)
		if (status != errSecSuccess) {
			return nil
		}
		return uCert
	}
	
	public var commonName: String? {
		guard let certificate = self.certificate else { return nil }
		let namePtr = UnsafeMutablePointer<CFString?>.alloc(1)
		SecCertificateCopyCommonName(certificate, namePtr)
		return namePtr.memory as String?
	}
	
	public var deviceId: DeviceId? {
		return self.certificate?.deviceId
	}
	
	class func randomSerial() -> Int32 {
		var randomSerial : Int32  = 0
		withUnsafeMutablePointer(&randomSerial, { (ptr) -> Void in
			let uint8ptr : UnsafeMutablePointer<UInt8> = unsafeBitCast(ptr, UnsafeMutablePointer<UInt8>.self)
			let r = SecRandomCopyBytes(kSecRandomDefault, Int(sizeof(Int32)), uint8ptr)
			if r != errSecSuccess {
				randomSerial = Int32(arc4random())
			}
			else {
				// Use only the last 31 bits of the random number so that the number is
				// positive but the random distribution still uniform
				randomSerial = randomSerial & (0x7FFFFFFF)
			}
		})
		
		return randomSerial
	}
	
	class func createPKCS12BlobUsingOpenSSL(pass: String, bits: UInt, label: String) throws -> NSData {
		let cal = NSCalendar.currentCalendar()
		let components = NSDateComponents()
		components.year = 2049
		components.month = 12
		components.day = 31
		components.hour = 23
		components.minute = 23
		components.second = 59
		let endDate = cal.dateFromComponents(components)
		
		let cert:OpenSSLCertificate! = OpenSSLCertificate(endDate: endDate, bits: bits, label: label, serial: CLong(randomSerial()))
		do {
			try cert.tryCreateSelfSignedCertificate()
			return try cert.createPKCS12BlobWithPassword(pass)
		}
	}
}
