import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let size = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(size)/128); transform.concat()
        let shape = NSBezierPath(roundedRect:NSRect(x:6,y:6,width:116,height:116),xRadius:26,yRadius:26)
        NSGradient(starting:NSColor(srgbRed:0.10,green:0.45,blue:0.40,alpha:1),ending:NSColor(srgbRed:0.035,green:0.22,blue:0.21,alpha:1))!.draw(in:shape,angle:270)
        NSColor(srgbRed:0.94,green:0.96,blue:0.82,alpha:1).setFill()
        for (i,h) in [20,40,68,48,30,16].enumerated() {
            NSBezierPath(roundedRect:NSRect(x:28+13*i,y:64-h/2,width:8,height:h),xRadius:4,yRadius:4).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
    }
}
