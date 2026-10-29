// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import Foundation

@main struct AntilleCommand {
    static func main() {
        do { try run() } catch {
            FileHandle.standardError.write(Data(("antille: \(error.localizedDescription)\n").utf8)); exit(1)
        }
    }
    static func run() throws {
        let args=Array(CommandLine.arguments.dropFirst())
        guard let command=args.first,command != "--help" else { print(help); return }
        func flag(_ name: String) -> String? {
            guard let index=args.firstIndex(of:name),index+1<args.count else { return nil }
            return args[index+1]
        }
        let producer=flag("--producer") ?? "local.cli"
        if command=="asset" {
            guard args.count>1 else { throw IslandError.invalid("Usage: antille asset FILE") }
            let source=URL(fileURLWithPath:args[1])
            let values=try source.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
            guard values.isRegularFile==true,(values.fileSize ?? Int.max)<4_194_304 else { throw IslandError.invalid("Choose a regular image smaller than 4 MiB.") }
            let folder=IslandPaths.directory.appending(path:"assets")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let target=folder.appending(path:UUID().uuidString+"."+source.pathExtension)
            try FileManager.default.copyItem(at:source,to:target)
            print(target.path); return
        }
        if command=="pair" {
            let nonce=IslandCredential.read("pending::"+producer) ?? UUID().uuidString
            try IslandCredential.save(nonce,producer:"pending::"+producer)
            var response=try IslandLocalClient.send(IslandRequest(operation:"pair",producerID:producer,requestID:nonce))
            if let token=response.token { try IslandCredential.save(token,producer:producer); response.token=nil; IslandCredential.delete("pending::"+producer) }
            print(try text(response));if !response.ok {exit(2)};return
        }
        let token=IslandCredential.read(producer)
        var request=IslandRequest(operation:command,producerID:producer,token:token)
        switch command {
        case "ping": break
        case "list": request.operation="snapshot"
        case "publish","update":
            let activity:IslandActivity
            if let file=flag("--file") { activity=try IslandWire.decoder().decode(IslandActivity.self,from:Data(contentsOf:URL(fileURLWithPath:file))) }
            else {
                activity=IslandActivity(producerID:producer,activityID:flag("--id") ?? "default",
                    generation:flag("--generation") ?? "cli",revision:Int(flag("--revision") ?? "") ?? Int(Date.now.timeIntervalSince1970*1000),
                    title:flag("--title") ?? "Activity",detail:flag("--detail") ?? "",state:flag("--state") ?? "running",
                    attention:IslandAttention(rawValue:flag("--attention") ?? "") ?? .none,
                    progress:flag("--progress").flatMap(Double.init),symbol:flag("--symbol") ?? "sparkle",
                    imagePath:flag("--image"),actions:flag("--action").map{[IslandAction(id:$0,title:flag("--action-title") ?? $0)]} ?? [])
            }
            request.operation="upsert"; request.activity=activity; request.generation=activity.generation
        case "clear": request.operation="remove"; request.activityID=flag("--id") ?? "default"
        case "actions": request.operation="actions"
        case "ack": request.operation="ack"; request.actionID=flag("--id"); request.result=flag("--result") ?? "Done"
        default: throw IslandError.invalid(help)
        }
        let response=try IslandLocalClient.send(request)
        print(try text(response))
        if !response.ok { exit(2) }
    }
    static func text(_ response:IslandResponse) throws -> String {
        let encoder=IslandWire.encoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        return String(decoding:try encoder.encode(response),as:UTF8.self)
    }
    static let help="""
    Antille — publish to your Mac island
    antille pair --producer ID              Request pairing; approve in Antille, then repeat
    antille publish --producer ID --id ID --title TEXT [--detail TEXT] [--progress 0...1]
                    [--state TEXT] [--attention none|information|needsAttention|error]
                    [--symbol SF_SYMBOL] [--image IMPORTED_PATH] [--action ID --action-title TEXT]
    antille publish --producer ID --file ACTIVITY.json
    antille list --producer ID
    antille clear --producer ID --id ID
    antille actions --producer ID
    antille ack --producer ID --id ACTION_EVENT_ID [--result TEXT]
    antille asset FILE                      Import an image and print its safe local path
    antille ping
    """
}
