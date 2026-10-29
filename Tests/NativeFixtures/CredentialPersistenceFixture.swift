// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import Foundation

/// Synthetic-only persistence check, run under two different signing identities.
@main enum CredentialPersistenceFixture {
    static func main() throws {
        guard CommandLine.arguments.count==3 else {throw Failure.arguments}
        let operation=CommandLine.arguments[1],service=CommandLine.arguments[2]
        guard service.hasPrefix("dev.upsided.antille.credential-migration-check."),
              !SilentCredentialPolicy.memoryOnly,
              SilentCredentialPolicy.enforceNoInteraction() else {throw Failure.arguments}
        let account="synthetic-only",value="synthetic-constant"
        switch operation {
        case "write":
            try LocalCredentialStore.save(value,service:service,account:account)
            guard LocalCredentialStore.read(service:service,account:account)==value else {throw Failure.restore}
        case "read":
            guard LocalCredentialStore.read(service:service,account:account)==value else {throw Failure.restore}
        case "delete":
            LocalCredentialStore.delete(service:service,account:account)
            guard LocalCredentialStore.read(service:service,account:account)==nil else {throw Failure.restore}
        default:throw Failure.arguments
        }
    }
    enum Failure:Error {case arguments,restore}
}
