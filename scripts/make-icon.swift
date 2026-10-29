// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import AppKit

@main enum AntilleIconGenerator {
    @MainActor static func main() throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let iconset=output.appending(path:"Antille.iconset")
        try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
        for size in [16,32,128,256,512] {
            for scale in [1,2] {
                let pixels=size*scale
                guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                      let context=NSGraphicsContext(bitmapImageRep:bitmap) else {throw NSError(domain:"AntilleIcon",code:1)}
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
                let transform=NSAffineTransform();transform.scale(by:CGFloat(pixels)/1024);transform.concat()
                NSColor(calibratedWhite:0.94,alpha:1).setFill()
                NSBezierPath(roundedRect:CGRect(x:60,y:60,width:904,height:904),xRadius:205,yRadius:205).fill()
                // A top edge flowing into a hanging, liquid island.
                let island=NSBezierPath()
                island.move(to:CGPoint(x:242,y:686));island.line(to:CGPoint(x:782,y:686))
                island.curve(to:CGPoint(x:744,y:588),controlPoint1:CGPoint(x:746,y:686),controlPoint2:CGPoint(x:744,y:630))
                island.line(to:CGPoint(x:744,y:484))
                island.curve(to:CGPoint(x:652,y:410),controlPoint1:CGPoint(x:744,y:426),controlPoint2:CGPoint(x:717,y:410))
                island.curve(to:CGPoint(x:512,y:362),controlPoint1:CGPoint(x:586,y:410),controlPoint2:CGPoint(x:583,y:362))
                island.curve(to:CGPoint(x:372,y:410),controlPoint1:CGPoint(x:441,y:362),controlPoint2:CGPoint(x:438,y:410))
                island.curve(to:CGPoint(x:280,y:484),controlPoint1:CGPoint(x:307,y:410),controlPoint2:CGPoint(x:280,y:426))
                island.line(to:CGPoint(x:280,y:588))
                island.curve(to:CGPoint(x:242,y:686),controlPoint1:CGPoint(x:280,y:630),controlPoint2:CGPoint(x:278,y:686))
                island.close();NSColor(calibratedWhite:0.16,alpha:1).setFill();island.fill()
                NSGraphicsContext.restoreGraphicsState()
                guard let data=bitmap.representation(using:.png,properties:[:]) else {throw NSError(domain:"AntilleIcon",code:2)}
                let suffix=scale==2 ? "@2x":""
                try data.write(to:iconset.appending(path:"icon_\(size)x\(size)\(suffix).png"))
            }
        }
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil")
        process.arguments=["-c","icns",iconset.path,"-o",output.appending(path:"AppIcon.icns").path]
        try process.run();process.waitUntilExit()
        guard process.terminationStatus==0 else {throw NSError(domain:"AntilleIcon",code:Int(process.terminationStatus))}
    }
}
