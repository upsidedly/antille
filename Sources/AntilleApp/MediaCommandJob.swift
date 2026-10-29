// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Darwin

enum MediaCommandFailure:LocalizedError,Sendable {
    case failed,timedOut,tooLarge
    var errorDescription:String? {
        switch self {case .failed:"The player did not complete the command.";case .timedOut:"The player took too long to respond.";case .tooLarge:"The player returned too much information."}
    }
}

/// One fixed AppleScript job. A lock owns completion; dedicated readers drain
/// both pipes. Cancellation/timeout terminate the child and bound the fallback.
final class MediaCommandJob:@unchecked Sendable {
    private let lock=NSLock(),process=Process(),outputPipe=Pipe(),errorPipe=Pipe()
    private var continuation:CheckedContinuation<Data,Error>?
    private var output=Data(),errorBytes=0
    private var outDone=false,errDone=false,finished=false,cancelled=false
    private var status:Int32?
    private var failure:Error?
    private var timer:Task<Void,Never>?
    func run(_ script:String,timeout:Duration = .seconds(5)) async throws ->Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished,!cancelled else {lock.unlock();continuation.resume(throwing:CancellationError());return}
                self.continuation=continuation
                process.executableURL=URL(fileURLWithPath:"/usr/bin/osascript");process.arguments=["-e",script]
                process.standardInput=FileHandle.nullDevice;process.standardOutput=outputPipe;process.standardError=errorPipe
                process.terminationHandler={ [self] child in
                    lock.lock();status=child.terminationStatus;lock.unlock();complete()
                }
                do {try process.run();lock.unlock()}
                catch {lock.unlock();finish(.failure(error));return}
                Thread.detachNewThread { [self] in drain(outputPipe.fileHandleForReading,standardOutput:true) }
                Thread.detachNewThread { [self] in drain(errorPipe.fileHandleForReading,standardOutput:false) }
                lock.lock()
                if !finished {timer=Task { [weak self] in do {try await Task.sleep(for:timeout)} catch{return};self?.stop(MediaCommandFailure.timedOut)}}
                lock.unlock()
            }
        } onCancel:{self.stop(CancellationError())}
    }
    private func drain(_ handle:FileHandle,standardOutput:Bool) {
        do {
            while let bytes=try handle.read(upToCount:4096),!bytes.isEmpty {
                lock.lock();if standardOutput {output.append(bytes)} else {errorBytes+=bytes.count}
                let tooLarge=output.count>131072 || errorBytes>16384;lock.unlock()
                if tooLarge {stop(MediaCommandFailure.tooLarge);break}
            }
        } catch {lock.lock();failure=failure ?? error;lock.unlock()}
        lock.lock();if standardOutput {outDone=true} else {errDone=true};lock.unlock();complete()
    }
    private func complete() {
        lock.lock()
        guard outDone,errDone,let status else {lock.unlock();return}
        let result:Result<Data,Error> = failure.map{.failure($0)} ?? (status==0 ? .success(output):.failure(MediaCommandFailure.failed))
        lock.unlock();finish(result)
    }
    private func finish(_ result:Result<Data,Error>) {
        lock.lock();guard !finished else {lock.unlock();return}
        finished=true;let continuation=self.continuation;self.continuation=nil;let timer=timer;self.timer=nil
        lock.unlock();timer?.cancel();continuation?.resume(with:result)
    }
    private func stop(_ reason:Error) {
        lock.lock();guard !finished else {lock.unlock();return}
        cancelled=true;failure=reason;let running=process.isRunning;lock.unlock()
        if running {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+0.4) { [self] in if process.isRunning {kill(process.processIdentifier,SIGKILL)} }
        } else {finish(.failure(reason))}
    }
}
