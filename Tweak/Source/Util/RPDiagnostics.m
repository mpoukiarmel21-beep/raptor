#import "RPDiagnostics.h"
#import "RPPaths.h"

@implementation RPDiagnostics {
    NSLock *_lock;
    NSString *_path;
}
+ (instancetype)shared { static RPDiagnostics *s; static dispatch_once_t t; dispatch_once(&t,^{ s=[[self alloc] init]; }); return s; }
- (instancetype)init { self=[super init]; if(self){ _lock=[[NSLock alloc] init]; NSString *dir=[RPPaths logDirectory]; [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]; _path=[dir stringByAppendingPathComponent:@"raptor.log"]; } return self; }
- (void)log:(NSString *)msg {
    if (!msg.length) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSLog(@"[Raptor] %@", msg);
    [_lock lock];
    @try {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:_path];
        if (!fh) { [line writeToFile:_path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
        else { @try{ [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; } @catch(NSException *e){} }
    } @finally { [_lock unlock]; }
}
@end
