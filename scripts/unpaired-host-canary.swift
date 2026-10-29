// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Antille

/// Headless, fixture-only regression host. It cannot approve sources, show an
/// island, issue credentials or handle commands. It exits after 90 seconds.
@main struct UnpairedHostCanary {
    static func main() async throws {
        guard SilentCredentialPolicy.memoryOnly else {throw IslandError.invalid("Run with --fixture.")}
        let server=IslandLocalServer {request in IslandResponse(ok:request.operation=="ping",message:request.operation=="ping" ? nil:"Fixture source is deliberately unpaired.")}
        try await server.start()
        defer {server.stop()}
        FileHandle.standardOutput.write(Data("READY: headless unpaired fixture host, 90 seconds.\n".utf8))
        try await Task.sleep(for:.seconds(90))
        FileHandle.standardOutput.write(Data("STOPPED: headless fixture host.\n".utf8))
    }
}
