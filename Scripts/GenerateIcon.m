#import <AppKit/AppKit.h>
int main(int argc, const char *argv[]) { @autoreleasepool {
 NSString *out = @(argv[1]);
 [[NSFileManager defaultManager] createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
 int sizes[] = {16,32,128,256,512};
 for(int i=0;i<5;i++) for(int scale=1;scale<=2;scale++) {
 int n=sizes[i]*scale;
 NSBitmapImageRep *b=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:n pixelsHigh:n bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
 [NSGraphicsContext saveGraphicsState];
 [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:b]];
 CGContextScaleCTM(NSGraphicsContext.currentContext.CGContext,n/1024.0,n/1024.0);
 NSBezierPath *tile=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(84,84,856,856) xRadius:192 yRadius:192];
 NSGradient *g=[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:.12 green:.21 blue:.32 alpha:1] endingColor:[NSColor colorWithCalibratedRed:.025 green:.055 blue:.105 alpha:1]];
 [g drawInBezierPath:tile angle:-90];
 [[NSColor colorWithWhite:1 alpha:.15] setStroke]; tile.lineWidth=3; [tile stroke];
 NSBezierPath *p=[NSBezierPath bezierPath];
 [p moveToPoint:NSMakePoint(225,497)];
 NSPoint points[]={ {354,497},{416,650},{509,340},{597,713},{670,497},{799,497} };
 for(int k=0;k<6;k++) [p lineToPoint:points[k]];
 p.lineCapStyle=NSLineCapStyleRound; p.lineJoinStyle=NSLineJoinStyleRound;
 [NSGraphicsContext saveGraphicsState];
 NSShadow *s=[NSShadow new]; s.shadowColor=[[NSColor cyanColor] colorWithAlphaComponent:.5]; s.shadowBlurRadius=32; s.shadowOffset=NSZeroSize; [s set];
 [[NSColor colorWithCalibratedRed:.22 green:.87 blue:.98 alpha:1] setStroke]; p.lineWidth=53; [p stroke];
 [NSGraphicsContext restoreGraphicsState];
 [[NSColor colorWithCalibratedRed:.65 green:.98 blue:1 alpha:1] setStroke]; p.lineWidth=27; [p stroke];
 [NSGraphicsContext restoreGraphicsState];
 NSString *name=[NSString stringWithFormat:@"icon_%dx%d%@.png",sizes[i],sizes[i],scale==2?@"@2x":@""];
 [[b representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[out stringByAppendingPathComponent:name] atomically:YES];
 }
 } return 0; }
