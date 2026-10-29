// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
public enum IslandMagnet {
    public static func arcPoint(from:CGPoint,to:CGPoint,progress:Double,height:Double)->CGPoint {
        let t=max(0,min(1,progress))
        return CGPoint(x:from.x+(to.x-from.x)*t,y:from.y+(to.y-from.y)*t+4*max(0,height)*t*(1-t))
    }
    public static func dragOrigin(window:CGPoint,startPointer:CGPoint,pointer:CGPoint)->CGPoint {
        CGPoint(x:window.x+pointer.x-startPointer.x,y:window.y+pointer.y-startPointer.y)
    }
    public static func strength(pointer:CGPoint,target:CGRect)->Double {
        let distance=hypot(pointer.x-target.midX,pointer.y-(target.maxY-38))
        return max(0,min(1,1-distance/190))
    }
    public static func shouldDock(pointer:CGPoint,velocity:CGPoint,target:CGRect)->Bool {
        if target.contains(pointer) {return true}
        guard velocity.y>450 else{return false}
        let t=(target.midY-pointer.y)/velocity.y
        guard (0...0.28).contains(t) else{return false}
        let x=pointer.x+velocity.x*t
        return x>=target.minX-20 && x<=target.maxX+20
    }
}
