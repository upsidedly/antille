// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille
import Foundation

enum CheckError:Error { case failed(String) }
func expect(_ condition: @autoclosure () -> Bool,_ message:String) throws {
    if !condition() { throw CheckError.failed(message) }
}
@main struct AntilleChecks {
    @MainActor static func main() async {
        do {
            if CommandLine.arguments.contains("--interaction-checks") {try await runInteractionChecks();return}
            try expect(SilentCredentialPolicy.enforceNoInteraction(),"legacy Keychain interaction is disabled without accessing records")
            if SilentCredentialPolicy.memoryOnly {
                try expect(IslandPaths.directory.lastPathComponent=="AntilleFixture","isolated fixture socket/support")
                let fixtureDirectory=await IslandDiskStore().directory
                try expect(fixtureDirectory==IslandPaths.directory,"isolated fixture profile defaults")
                try LocalCredentialStore.save("fixture-value",service:"fixture",account:"only-in-memory")
                try expect(LocalCredentialStore.read(service:"fixture",account:"only-in-memory")=="fixture-value","RAM credential fixture")
                LocalCredentialStore.delete(service:"fixture",account:"only-in-memory")
            }
            let store=IslandStore()
            var item=IslandActivity(producerID:"test",activityID:"one",revision:2,title:"Newest")
            let encoded=try IslandWire.encoder().encode(IslandRequest(operation:"upsert",activity:item))
            let decoded=try IslandWire.decoder().decode(IslandRequest.self,from:encoded)
            try expect(decoded.activity?.id==item.id,"portable ISO date wire round trip")
            let first=try store.upsert(item);try expect(first,"first update")
            item.revision=1;item.title="Old"
            let old=try store.upsert(item);try expect(!old,"reject late updates")
            try expect(store.activities.first?.title=="Newest","retain newest value")
            store.beginGeneration(producerID:"test",generation:"new")
            do { try store.upsert(item);throw CheckError.failed("old epoch accepted") }
            catch is IslandError {}
            store.markStale(producerID:"test")
            try expect(store.activities.first?.state=="running","stale is not finished")
            try expect(store.activities.first?.stale==true,"stale marker")
            try store.upsert(IslandActivity(producerID:"other",activityID:"one",title:"Other",attention:.needsAttention))
            try expect(store.visibleActivities.first?.producerID=="other","attention ordering")
            store.remove(producerID:"other",activityID:"one")
            try expect(store.activities.count==1,"producer scoped removal")
            store.beginGeneration(producerID:"handoff",generation:"session")
            var handoff=IslandActivity(producerID:"handoff",activityID:"head",generation:"session",revision:8,title:"Moving")
            try store.upsert(handoff)
            store.remove(producerID:"handoff",activityID:"head",revision:11)
            handoff.revision=10
            let late=try store.upsert(handoff)
            try expect(!late && !store.activities.contains(where:{$0.id==handoff.id}),"late publish cannot resurrect an extracted head")
            handoff.revision=12
            let restoredHead=try store.upsert(handoff)
            try expect(restoredHead,"a newer explicit docking can restore the head")
            store.remove(producerID:"handoff",activityID:"head",revision:11)
            try expect(store.activities.contains(where:{$0.id==handoff.id}),"late detach acknowledgment cannot remove a newer docking")
            let geometry=IslandGeometry(screen:CGRect(x:1440,y:80,width:1280,height:900),cutoutWidth:210,topInset:32)
            let frame=geometry.frame(profile:IslandProfile(),expanded:true)
            try expect(frame.midX==2080 && frame.maxY==980 && frame.minX>=1440,"display coordinates")
            var crowded=IslandProfile();crowded.wingWidth=36;crowded.compactLimit=8
            let packed=geometry.frame(profile:crowded,expanded:false,activityCount:8)
            try expect((packed.width-geometry.cutoutWidth)/2>=127+22,"eight heads fit outside physical cutout")
            let overflow=geometry.frame(profile:crowded,expanded:false,activityCount:12)
            try expect(overflow.width>packed.width,"overflow label has space")
            for limit in 1...8 {
                crowded.compactLimit=limit
                for count in 1...12 {
                    let bounds=geometry.frame(profile:crowded,expanded:false,activityCount:count)
                    var seen=Set<Double>()
                    for index in 0..<count {
                        guard let slot=geometry.landingSlot(index:index,profile:crowded,activityCount:count) else {throw CheckError.failed("missing landing slot")}
                        try expect(abs(slot.x-geometry.screen.midX)>geometry.cutoutWidth/2+12,"landing avoids physical notch")
                        try expect(slot.x-12>=bounds.minX && slot.x+12<=bounds.maxX,"landing fits island wing")
                        if index<limit {try expect(seen.insert(slot.x).inserted,"compact landing slots are distinct")}
                    }
                }
            }
            var profile=IslandProfile();profile.expandedWidth = .nan;profile.compactLimit=100
            profile.componentOrder=["content","content","invalid"];profile.normalize()
            try expect(profile.expandedWidth==420 && profile.compactLimit==8,"profile bounds")
            try expect(profile.componentOrder==["content"],"unique content identity")
            do {
                try IslandActivity(producerID:"bad",activityID:"one",title:"Bad",priority:Int.min,progress:1.8).validate()
                throw CheckError.failed("invalid payload accepted")
            } catch is IslandError {}
            let drag=IslandMagnet.dragOrigin(window:CGPoint(x:100,y:200),startPointer:CGPoint(x:130,y:240),pointer:CGPoint(x:330,y:440))
            try expect(drag==CGPoint(x:300,y:400),"screen-coordinate dragging")
            let catchRect=CGRect(x:500,y:800,width:300,height:120)
            try expect(IslandMagnet.shouldDock(pointer:CGPoint(x:650,y:700),velocity:CGPoint(x:0,y:1000),target:catchRect),"upward toss capture")
            try expect(!IslandMagnet.shouldDock(pointer:CGPoint(x:100,y:700),velocity:CGPoint(x:0,y:1000),target:catchRect),"reject off-target toss")
            let a=CGPoint(x:0,y:0),b=CGPoint(x:100,y:0)
            try expect(IslandMagnet.arcPoint(from:a,to:b,progress:0,height:40)==a,"jump starts at head")
            try expect(IslandMagnet.arcPoint(from:a,to:b,progress:1,height:40)==b,"jump lands at island")
            try expect(IslandMagnet.arcPoint(from:a,to:b,progress:0.5,height:40).y==40,"jump arcs above straight path")
            let directory=FileManager.default.temporaryDirectory.appending(path:"antille-check-\(UUID().uuidString)")
            let disk=IslandDiskStore(directory:directory)
            try await disk.saveProfiles([profile])
            let restored=try await disk.loadProfiles()
            try expect(restored==[profile],"versioned atomic profile round trip")
            let socket="/tmp/antille-\(UUID().uuidString.prefix(8)).sock"
            let server=IslandLocalServer(path:socket) { request in
                try? await Task.sleep(for:.milliseconds(8))
                return IslandResponse(message:request.operation,activities:request.activity.map{[$0]})
            }
            try await server.start()
            try await withThrowingTaskGroup(of:Void.self) { group in
                for _ in 0..<8 {
                    group.addTask {
                        for _ in 0..<15 {
                            let result=try IslandLocalClient.send(IslandRequest(operation:"ping"),socketPath:socket)
                            try expect(result.ok && result.message=="ping","socket round trip")
                        }
                    }
                }
                try await group.waitForAll()
            }
            var large=IslandActivity(producerID:"sprite",activityID:"head",title:"Large sprite payload")
            large.spriteFrames=(0..<120).map{"/Applications/"+String(repeating:"x",count:180)+"/\($0).png"}
            let fixture=large
            try await withThrowingTaskGroup(of:Void.self) { group in
                for _ in 0..<6 {
                    group.addTask {
                        for _ in 0..<10 {
                            let result=try IslandLocalClient.send(IslandRequest(operation:"upsert",activity:fixture),socketPath:socket)
                            try expect(result.activities?.first?.spriteFrames==fixture.spriteFrames,"large sprite round trip")
                        }
                    }
                }
                try await group.waitForAll()
            }
            server.stop()
            try await Task.sleep(for:.milliseconds(50))
            try expect(!FileManager.default.fileExists(atPath:socket),"socket cleanup")
            try FileManager.default.removeItem(at:directory)
            print("PASS: silent credential policy (no record reads), fixture isolation, ordering/epochs/stale state, 1–12 heads with 1–8 slots and overflow, drag/toss/arc geometry, validation, atomic profiles, 120 small and 60 large concurrent transport round trips.")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8));exit(1)
        }
    }
}
