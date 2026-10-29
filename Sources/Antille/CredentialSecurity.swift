// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Security
import LocalAuthentication
import Darwin

/// macOS legacy Keychain ACLs can present UI even with a noninteractive LAContext.
/// Every persistent operation first disables legacy interaction for this process.
/// The public, deprecated C entry points are weak-linked here because the modern
/// LAContext policy alone does not cover legacy items (see the SDK SecItem.h).
public enum SilentCredentialPolicy {
    public static var memoryOnly:Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".fixture")==true ||
        ProcessInfo.processInfo.arguments.contains("--fixture") ||
        ProcessInfo.processInfo.arguments.first?.hasSuffix("antille-fixture")==true ||
        ProcessInfo.processInfo.environment["ANTILLE_CREDENTIAL_MODE"]=="memory"
    }
    public static func enforceNoInteraction()->Bool {
        // RTLD_DEFAULT's public dlfcn.h macro is ((void *) -2); Swift cannot import it.
        guard let symbols=UnsafeMutableRawPointer(bitPattern:-2),
              let setSymbol=dlsym(symbols,"SecKeychainSetUserInteractionAllowed"),
              let getSymbol=dlsym(symbols,"SecKeychainGetUserInteractionAllowed") else {return false}
        typealias SetInteraction = @convention(c) (UInt8)->Int32
        typealias GetInteraction = @convention(c) (UnsafeMutablePointer<UInt8>)->Int32
        let set=unsafeBitCast(setSymbol,to:SetInteraction.self)
        let get=unsafeBitCast(getSymbol,to:GetInteraction.self)
        var allowed:UInt8=1
        return set(0)==errSecSuccess && get(&allowed)==errSecSuccess && allowed==0
    }
}

/// A test-only RAM store. The lock protects all reads and writes across the CLI,
/// main actor, and local-server queue. No credential file or fallback is written.
private final class TransientCredentials:@unchecked Sendable {
    private let lock=NSLock()
    private var values:[String:String]=[:]
    func read(_ key:String)->String? {lock.lock();defer{lock.unlock()};return values[key]}
    func save(_ value:String,key:String) {lock.lock();defer{lock.unlock()};values[key]=value}
    func delete(_ key:String) {lock.lock();defer{lock.unlock()};values.removeValue(forKey:key)}
}
public enum LocalCredentialStore {
    private static let transient=TransientCredentials()
    private static let ownerNamespace:String? = {
        var current:SecCode?,code:SecStaticCode?,information:CFDictionary?
        guard SecCodeCopySelf([],&current)==errSecSuccess,let current,
              SecCodeCopyStaticCode(current,[],&code)==errSecSuccess,let code,
              SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&information)==errSecSuccess,
              let values=information as? [String:Any],let identity=values[kSecCodeInfoUnique as String] as? Data,
              !identity.isEmpty else {return nil}
        return identity.map{String(format:"%02x",$0)}.joined()
    }()
    private static func query(service:String,account:String)->[String:Any]? {
        // A development update cannot silently change an older build's Keychain
        // ACL. Reconnect creates a separately protected item for this signature;
        // an unchanged installed build finds that same item on every relaunch.
        guard let ownerNamespace else {return nil}
        let context=LAContext();context.interactionNotAllowed=true
        return [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
                kSecAttrAccount as String:account+"::"+ownerNamespace,kSecUseAuthenticationContext as String:context]
    }
    public static func read(service:String,account:String)->String? {
        if SilentCredentialPolicy.memoryOnly {return transient.read(service+"::"+account)}
        guard SilentCredentialPolicy.enforceNoInteraction(),var record=query(service:service,account:account) else{return nil}
        record[kSecReturnData as String]=true;record[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?
        guard SecItemCopyMatching(record as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil}
        return String(data:data,encoding:.utf8)
    }
    public static func save(_ value:String,service:String,account:String) throws {
        if SilentCredentialPolicy.memoryOnly {transient.save(value,key:service+"::"+account);return}
        guard SilentCredentialPolicy.enforceNoInteraction(),let record=query(service:service,account:account) else {throw unavailable}
        let status=SecItemUpdate(record as CFDictionary,[kSecValueData as String:Data(value.utf8)] as CFDictionary)
        if status==errSecItemNotFound {
            var add=record;add[kSecValueData as String]=Data(value.utf8)
            guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else {throw unavailable}
        } else if status != errSecSuccess {throw unavailable}
        guard read(service:service,account:account)==value else {throw unavailable}
    }
    public static func delete(service:String,account:String) {
        if SilentCredentialPolicy.memoryOnly {transient.delete(service+"::"+account);return}
        guard SilentCredentialPolicy.enforceNoInteraction(),let record=query(service:service,account:account) else{return}
        SecItemDelete(record as CFDictionary)
    }
    private static var unavailable:IslandError {.unavailable("Saved access is unavailable without interaction. Reconnect when convenient.")}
}
