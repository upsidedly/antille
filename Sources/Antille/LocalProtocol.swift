// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Darwin
import Security
import LocalAuthentication

public enum IslandWire {
    public static func encoder()->JSONEncoder {
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    public static func decoder()->JSONDecoder {
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct IslandRequest: Codable, Sendable {
    public var version: Int = 1
    public var operation: String
    public var producerID: String?
    public var generation: String?
    public var token: String?
    public var activity: IslandActivity?
    public var activityID: String?
    public var requestID: String?
    public var actionID: String?
    public var result: String?
    public var value:Double?
    public var revision:Int?
    public var position:IslandPoint?
    public var excludingActionIDs:[String]?
    public init(operation: String, producerID: String? = nil, generation: String? = nil, token: String? = nil,
                activity: IslandActivity? = nil, activityID: String? = nil, requestID: String? = nil,
                actionID: String? = nil, result: String? = nil,value:Double?=nil,revision:Int?=nil,position:IslandPoint?=nil,excludingActionIDs:[String]?=nil) {
        self.operation=operation; self.producerID=producerID; self.generation=generation; self.token=token
        self.activity=activity; self.activityID=activityID; self.requestID=requestID; self.actionID=actionID; self.result=result;self.value=value
        self.revision=revision
        self.position=position;self.excludingActionIDs=excludingActionIDs
    }
}
public struct IslandActionEvent: Codable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var producerID: String
    public var activityID: String
    public var actionID: String
    public var createdAt: Date = .now
    public var position:IslandPoint?
    public var fields:[String:String]?
    public init(producerID: String, activityID: String, actionID: String,position:IslandPoint?=nil,fields:[String:String]?=nil) {
        self.producerID=producerID; self.activityID=activityID; self.actionID=actionID
        self.position=position;self.fields=fields
    }
}
public struct IslandResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String?
    public var token: String?
    public var activities: [IslandActivity]?
    public var actions: [IslandActionEvent]?
    public var position:IslandPoint?
    public var target:IslandBounds?
    public init(ok: Bool = true, message: String? = nil, token: String? = nil,
                activities: [IslandActivity]? = nil, actions: [IslandActionEvent]? = nil,position:IslandPoint?=nil,target:IslandBounds?=nil) {
        self.ok=ok; self.message=message; self.token=token; self.activities=activities; self.actions=actions
        self.position=position;self.target=target
    }
}
public enum IslandPaths {
    public static var directory: URL { URL.applicationSupportDirectory.appending(path:SilentCredentialPolicy.memoryOnly ? "AntilleFixture":"Antille") }
    // macOS sockaddr_un is limited to 104 bytes. The user-specific support path stays below this.
    public static var socket: String { directory.appending(path:"host.sock").path }
}
public enum IslandCredential {
    public static func read(_ producer: String) -> String? {
        LocalCredentialStore.read(service:"dev.upsided.antille.producer",account:producer)
    }
    public static func delete(_ producer: String) {
        LocalCredentialStore.delete(service:"dev.upsided.antille.producer",account:producer)
    }
    public static func save(_ token: String, producer: String) throws {
        try LocalCredentialStore.save(token,service:"dev.upsided.antille.producer",account:producer)
    }
}
private func socketAddress(_ path: String) throws -> sockaddr_un {
    var address=sockaddr_un()
    address.sun_family=sa_family_t(AF_UNIX)
    let bytes=Array(path.utf8)+[0]
    guard bytes.count<=MemoryLayout.size(ofValue:address.sun_path) else { throw IslandError.invalid("Socket path is too long.") }
    withUnsafeMutableBytes(of:&address.sun_path) { raw in raw.copyBytes(from:bytes) }
    address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
    return address
}
public enum IslandLocalClient {
    public static func send(_ request: IslandRequest, socketPath: String = IslandPaths.socket) throws -> IslandResponse {
        let fd=Darwin.socket(AF_UNIX,SOCK_STREAM,0)
        guard fd>=0 else { throw IslandError.unavailable("Could not create a local connection.") }
        defer { Darwin.close(fd) }
        var noSignal:Int32=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout.size(ofValue:noSignal)))
        var timeout=timeval(tv_sec:3,tv_usec:0)
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        var address=try socketAddress(socketPath)
        let connected=withUnsafePointer(to:&address) {
            $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected==0 else { throw IslandError.unavailable("Antille is not running. Open Antille.app first.") }
        var data=try IslandWire.encoder().encode(request); data.append(10)
        try data.withUnsafeBytes { raw in
            guard let base=raw.baseAddress else { return }
            var count=0
            while count<data.count {
                let sent=Darwin.send(fd,base.advanced(by:count),data.count-count,0)
                guard sent>0 else { throw IslandError.unavailable("The local connection closed while sending.") }
                count+=sent
            }
        }
        var result=Data(); var buffer=[UInt8](repeating:0,count:8192)
        while result.count<1_048_576 {
            let count=Darwin.recv(fd,&buffer,buffer.count,0)
            guard count>0 else { throw IslandError.unavailable("The host did not return a complete response.") }
            result.append(contentsOf:buffer.prefix(count))
            if let end=result.firstIndex(of:10) {
                return try IslandWire.decoder().decode(IslandResponse.self,from:result.prefix(upTo:end))
            }
        }
        throw IslandError.invalid("Host response exceeded the size limit.")
    }
}

/// Mutable descriptors, buffers, and tasks are confined to the serial queue.
/// The only cross-queue entry points enqueue work; the async handler uses Sendable values.
public final class IslandLocalServer: @unchecked Sendable {
    private let queue=DispatchQueue(label:"dev.upsided.antille.ipc",qos:.utility)
    private var listener: DispatchSourceRead?
    private var clients: [Int32:DispatchSourceRead] = [:]
    private var buffers: [Int32:Data] = [:]
    private var tasks: [Int32:Task<Void,Never>] = [:]
    private var epochs: [Int32:UUID] = [:]
    private var writes: [Int32:(data:Data,offset:Int)] = [:]
    private var writeSources: [Int32:DispatchSourceWrite] = [:]
    private var suspendedReads:Set<Int32>=[]
    private let handler: @Sendable (IslandRequest) async -> IslandResponse
    private let path: String
    public init(path: String = IslandPaths.socket, handler: @escaping @Sendable (IslandRequest) async -> IslandResponse) {
        self.path=path; self.handler=handler
    }
    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            queue.async { [self] in
                do { try startOnQueue(); continuation.resume() } catch { continuation.resume(throwing:error) }
            }
        }
    }
    private func startOnQueue() throws {
        guard listener==nil else { return }
        let directory=URL(fileURLWithPath:path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        // Never unlink a live socket belonging to another Antille instance.
        if FileManager.default.fileExists(atPath:path) {
            if (try? IslandLocalClient.send(IslandRequest(operation:"ping"),socketPath:path)) != nil {
                throw IslandError.unavailable("Another Antille host is already running.")
            }
            try FileManager.default.removeItem(atPath:path)
        }
        let fd=Darwin.socket(AF_UNIX,SOCK_STREAM,0)
        guard fd>=0 else { throw IslandError.unavailable("Could not create the host socket.") }
        var address=try socketAddress(path)
        let bound=withUnsafePointer(to:&address) {
            $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound==0, Darwin.listen(fd,16)==0 else { Darwin.close(fd); throw IslandError.unavailable("Could not bind the local host socket.") }
        guard chmod(path,0o600)==0,fcntl(fd,F_SETFL,O_NONBLOCK)>=0 else { Darwin.close(fd); throw IslandError.unavailable("Could not secure the local socket.") }
        let source=DispatchSource.makeReadSource(fileDescriptor:fd,queue:queue)
        source.setEventHandler { [weak self] in self?.acceptConnections(fd) }
        source.setCancelHandler { Darwin.close(fd) }
        listener=source; source.resume()
    }
    private func acceptConnections(_ fd: Int32) {
        while true {
            let client=Darwin.accept(fd,nil,nil)
            guard client>=0 else { return }
            var uid:uid_t=0; var gid:gid_t=0
            guard clients.count<16,getpeereid(client,&uid,&gid)==0,uid==getuid() else { Darwin.close(client); continue }
            guard fcntl(client,F_SETFL,O_NONBLOCK)>=0 else { Darwin.close(client); continue }
            var noSignal:Int32=1; setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout.size(ofValue:noSignal)))
            let source=DispatchSource.makeReadSource(fileDescriptor:client,queue:queue)
            let epoch=UUID(); epochs[client]=epoch
            buffers[client]=Data(); clients[client]=source
            source.setEventHandler { [weak self] in self?.read(client,epoch:epoch) }
            source.setCancelHandler { Darwin.close(client) }
            source.resume()
            queue.asyncAfter(deadline:.now()+5) { [weak self] in
                guard self?.epochs[client]==epoch else { return }; self?.finish(client)
            }
        }
    }
    private func read(_ fd: Int32,epoch:UUID) {
        guard epochs[fd]==epoch else { return }
        guard var accumulated=buffers[fd] else {return}
        var bytes=[UInt8](repeating:0,count:8192)
        let count=Darwin.recv(fd,&bytes,bytes.count,0)
        if count<=0 { if count==0 || errno != EAGAIN { finish(fd) }; return }
        accumulated.append(contentsOf:bytes.prefix(count))
        guard accumulated.count<=524_288 else { respond(IslandResponse(ok:false,message:"Message exceeds 512 KiB."),to:fd); return }
        buffers[fd]=accumulated
        guard let end=accumulated.firstIndex(of:10) else { return }
        clients[fd]?.suspend();suspendedReads.insert(fd)
        buffers.removeValue(forKey:fd)
        do {
            let request=try IslandWire.decoder().decode(IslandRequest.self,from:accumulated.prefix(upTo:end))
            tasks[fd]=Task { [weak self,handler] in
                let response=await handler(request)
                guard !Task.isCancelled else { return }
                self?.queue.async { [weak self] in self?.respond(response,to:fd,epoch:epoch) }
            }
        } catch { respond(IslandResponse(ok:false,message:"Invalid request: \(error.localizedDescription)"),to:fd) }
    }
    private func respond(_ response: IslandResponse,to fd: Int32,epoch:UUID?=nil) {
        guard clients[fd] != nil,epoch==nil || epochs[fd]==epoch else { return }
        do {
            var data=try IslandWire.encoder().encode(response); data.append(10)
            guard data.count<=1_048_576 else { finish(fd); return }
            writes[fd]=(data,0)
            drainWrite(fd)
            if writes[fd] != nil {
                let source=DispatchSource.makeWriteSource(fileDescriptor:fd,queue:queue)
                let expected=epochs[fd]
                source.setEventHandler { [weak self] in
                    guard self?.epochs[fd]==expected else { return }; self?.drainWrite(fd)
                }
                writeSources[fd]=source;source.resume()
            }
        } catch { finish(fd) }
    }
    private func drainWrite(_ fd:Int32) {
        guard var pending=writes[fd] else { return }
        var failed=false
        let bytes=pending.data
        var offset=pending.offset
        bytes.withUnsafeBytes { raw in
            guard let base=raw.baseAddress else { return }
            while offset<bytes.count {
                let count=Darwin.send(fd,base.advanced(by:offset),bytes.count-offset,0)
                if count<0 && (errno==EAGAIN || errno==EWOULDBLOCK) { break }
                if count<=0 { failed=true;break }
                offset+=count
            }
        }
        pending.offset=offset
        if failed || offset==bytes.count { finish(fd) }
        else { writes[fd]=pending }
    }
    private func finish(_ fd: Int32) {
        epochs.removeValue(forKey:fd)
        writes.removeValue(forKey:fd)
        writeSources.removeValue(forKey:fd)?.cancel()
        tasks.removeValue(forKey:fd)?.cancel()
        buffers.removeValue(forKey:fd)
        if let client=clients.removeValue(forKey:fd) {
            if suspendedReads.remove(fd) != nil {client.resume()}
            client.cancel()
        }
    }
    public func stop() {
        queue.async { [self] in
            for fd in Array(clients.keys) { finish(fd) }
            listener?.cancel(); listener=nil
            try? FileManager.default.removeItem(atPath:path)
        }
    }
}
