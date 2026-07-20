#import "DebugServer.h"
#import "utils.h"

#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <sys/param.h>
#import <dirent.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <errno.h>
#import <pthread.h>

// Note: this server uses raw BSD sockets, NOT Network.framework. iOS Local
// Network permission only gates NWBrowser/NWListener/Bonjour; raw socket()
// + bind() + listen() bypasses that permission entirely.

// Embedded HTML dashboard. Single page, vanilla JS, dark theme.
static NSString *const kHTML = @"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Amethyst Debug</title><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>"
"*{box-sizing:border-box;font-family:-apple-system,system-ui,monospace}"
"body{margin:0;background:#1a1d21;color:#e6e6e6;font-size:14px}"
"header{background:#0f1114;padding:10px 14px;border-bottom:1px solid #333;display:flex;align-items:center;gap:10px}"
"header h1{margin:0;font-size:15px;color:#9bd}header .url{color:#888;font-size:12px;margin-left:auto}"
".tabs{background:#16191d;padding:0 14px;border-bottom:1px solid #2a2e33;display:flex}"
".tab{padding:10px 14px;cursor:pointer;border-bottom:2px solid transparent;color:#aaa}"
".tab.active{color:#9bd;border-bottom-color:#9bd}"
".panel{display:none;padding:12px;height:calc(100vh - 86px);overflow:auto}"
".panel.active{display:block}"
"input,button,select,textarea{background:#222;color:#e6e6e6;border:1px solid #444;padding:6px 10px;border-radius:4px;font-family:inherit;font-size:13px}"
"button{cursor:pointer;background:#2a4060}button:hover{background:#395580}button.danger{background:#7a2a2a}button.danger:hover{background:#a03a3a}"
"textarea{width:100%;min-height:200px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;resize:vertical}"
".row{display:flex;gap:8px;align-items:center;margin-bottom:8px;flex-wrap:wrap}"
"pre{background:#0f1114;border:1px solid #2a2e33;padding:10px;border-radius:4px;overflow:auto;font-size:12px;line-height:1.4;white-space:pre-wrap;word-break:break-all}"
".file-row{padding:4px 8px;cursor:pointer;border-radius:3px;font-family:ui-monospace,Menlo,monospace;font-size:13px}"
".file-row:hover{background:#252a30}.file-row.dir{color:#9bd}.file-row.up{color:#888;font-style:italic}"
".path{font-family:ui-monospace,Menlo,monospace;color:#cc9}"
".log-line{font-family:ui-monospace,Menlo,monospace;font-size:11px;line-height:1.3;white-space:pre-wrap;word-break:break-all}"
"#tokenBox{position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.85);display:flex;align-items:center;justify-content:center;z-index:10}"
"#tokenBox .box{background:#1a1d21;border:1px solid #444;padding:24px;border-radius:8px;max-width:400px}"
"#tokenBox h2{margin:0 0 12px}#tokenBox p{color:#aaa;margin:0 0 12px}"
".kv{display:grid;grid-template-columns:max-content 1fr;gap:6px 14px;font-size:13px}"
".kv .k{color:#888}.kv .v{font-family:ui-monospace,Menlo,monospace;word-break:break-all}"
"</style></head><body>"
"<header><h1>Amethyst Debug</h1><span class=\"url\" id=\"hostUrl\"></span></header>"
"<div class=\"tabs\">"
"<div class=\"tab active\" data-panel=\"files\">Files</div>"
"<div class=\"tab\" data-panel=\"logs\">Logs</div>"
"<div class=\"tab\" data-panel=\"info\">Info</div>"
"<div class=\"tab\" data-panel=\"controls\">Controls</div>"
"</div>"
"<div class=\"panel active\" id=\"p-files\">"
"<div class=\"row\"><input id=\"path\" style=\"flex:1\" placeholder=\"/var/mobile/...\" /><button onclick=\"goPath()\">Open</button><button onclick=\"goHome()\">Home</button><button onclick=\"goPojav()\">POJAV</button></div>"
"<div id=\"fileList\"></div>"
"<div id=\"editor\" style=\"display:none;margin-top:12px\">"
"<div class=\"row\"><span class=\"path\" id=\"editPath\"></span><span style=\"flex:1\"></span><button onclick=\"saveFile()\">Save</button><button class=\"danger\" onclick=\"deleteFile()\">Delete</button><button onclick=\"closeEditor()\">Close</button></div>"
"<textarea id=\"editor-ta\"></textarea></div></div>"
"<div class=\"panel\" id=\"p-logs\">"
"<div class=\"row\"><label><input type=\"checkbox\" id=\"autotail\"/> Auto-refresh (1s)</label><select id=\"logFile\"><option value=\"latestlog.txt\">latestlog.txt</option><option value=\"latestlog.old.txt\">latestlog.old.txt</option></select><input id=\"logLines\" type=\"number\" value=\"500\" style=\"width:80px\"/><button onclick=\"refreshLog()\">Refresh</button></div>"
"<pre id=\"logContent\" style=\"height:calc(100vh - 200px)\"></pre></div>"
"<div class=\"panel\" id=\"p-info\">"
"<div class=\"row\"><button onclick=\"refreshInfo()\">Refresh</button><button onclick=\"loadDylibs()\">Dylibs</button><button onclick=\"loadCrashes()\">Crash reports</button></div>"
"<div id=\"infoContent\"></div></div>"
"<div class=\"panel\" id=\"p-controls\">"
"<div class=\"row\"><button class=\"danger\" onclick=\"if(confirm('Restart app?'))doRestart()\">Restart Minecraft</button></div>"
"<p style=\"color:#888;font-size:12px\">Restart kills the process — iOS will close the app and you'll need to relaunch from the home screen.</p>"
"<div class=\"row\"><button onclick=\"clearToken()\">Clear saved token</button></div></div>"
"<div id=\"tokenBox\"><div class=\"box\"><h2>Auth required</h2><p>Paste the token from the Amethyst settings page:</p><div class=\"row\"><input id=\"tokenIn\" style=\"flex:1\" type=\"text\" autocomplete=\"off\"/><button onclick=\"submitToken()\">Connect</button></div></div></div>"
"<script>"
"let token=localStorage.getItem('amethystToken')||'';"
"document.getElementById('hostUrl').textContent=location.host;"
"if(token){checkToken()}else{showTokenBox()}"
"function showTokenBox(){document.getElementById('tokenBox').style.display='flex'}"
"function hideTokenBox(){document.getElementById('tokenBox').style.display='none'}"
"function submitToken(){token=document.getElementById('tokenIn').value.trim();localStorage.setItem('amethystToken',token);checkToken()}"
"function clearToken(){localStorage.removeItem('amethystToken');location.reload()}"
"async function checkToken(){const r=await fetch('/api/info?token='+encodeURIComponent(token));if(r.status===401){showTokenBox();return}hideTokenBox();listFiles(localStorage.getItem('lastPath')||'/var/mobile')}"
"async function api(p,o){o=o||{};const sep=p.includes('?')?'&':'?';const r=await fetch(p+sep+'token='+encodeURIComponent(token),o);if(r.status===401){showTokenBox();throw new Error('auth')}return r}"
"document.querySelectorAll('.tab').forEach(t=>t.onclick=()=>{document.querySelectorAll('.tab,.panel').forEach(e=>e.classList.remove('active'));t.classList.add('active');document.getElementById('p-'+t.dataset.panel).classList.add('active');if(t.dataset.panel==='logs')refreshLog();if(t.dataset.panel==='info')refreshInfo()});"
"function goPath(){listFiles(document.getElementById('path').value)}"
"function goHome(){listFiles('/var/mobile')}"
"async function goPojav(){const i=await(await api('/api/info')).json();listFiles(i.pojavHome||'/var/mobile')}"
"async function listFiles(p){closeEditor();localStorage.setItem('lastPath',p);document.getElementById('path').value=p;const r=await api('/api/files?path='+encodeURIComponent(p));const j=await r.json();const list=document.getElementById('fileList');list.innerHTML='';if(j.error){list.innerHTML='<p style=\"color:#f88\">'+j.error+'</p>';return}const up=document.createElement('div');up.className='file-row up';up.textContent='\\u2191 ..';up.onclick=()=>listFiles(j.parent||'/');list.appendChild(up);for(const f of j.entries){const row=document.createElement('div');row.className='file-row '+(f.dir?'dir':'');row.textContent=(f.dir?'\\ud83d\\udcc1 ':'\\ud83d\\udcc4 ')+f.name+(f.dir?'/':'  ('+f.size+'B)');row.onclick=()=>{if(f.dir)listFiles(j.path+'/'+f.name);else openFile(j.path+'/'+f.name)};list.appendChild(row)}}"
"async function openFile(p){const r=await api('/api/file?path='+encodeURIComponent(p));const t=await r.text();document.getElementById('editor').style.display='block';document.getElementById('editPath').textContent=p;document.getElementById('editor-ta').value=t;document.getElementById('editor-ta').dataset.path=p}"
"async function saveFile(){const p=document.getElementById('editor-ta').dataset.path;const body=document.getElementById('editor-ta').value;const r=await api('/api/file?path='+encodeURIComponent(p),{method:'PUT',body:body});if(r.ok)alert('Saved');else alert('Save failed: '+r.status)}"
"async function deleteFile(){const p=document.getElementById('editor-ta').dataset.path;if(!confirm('Delete '+p+'?'))return;const r=await api('/api/file?path='+encodeURIComponent(p),{method:'DELETE'});if(r.ok){closeEditor();listFiles(localStorage.getItem('lastPath'))}else alert('Delete failed: '+r.status)}"
"function closeEditor(){document.getElementById('editor').style.display='none'}"
"let tailTimer=null;"
"document.getElementById('autotail').onchange=e=>{if(e.target.checked){tailTimer=setInterval(refreshLog,1000)}else{clearInterval(tailTimer);tailTimer=null}};"
"async function refreshLog(){const f=document.getElementById('logFile').value;const n=document.getElementById('logLines').value;const r=await api('/api/log?file='+encodeURIComponent(f)+'&n='+n);const t=await r.text();const el=document.getElementById('logContent');const wasBottom=el.scrollHeight-el.scrollTop-el.clientHeight<50;el.textContent=t;if(wasBottom)el.scrollTop=el.scrollHeight}"
"async function refreshInfo(){const r=await api('/api/info');const j=await r.json();const el=document.getElementById('infoContent');el.innerHTML='<div class=\"kv\">'+Object.entries(j).map(([k,v])=>'<div class=\"k\">'+k+'</div><div class=\"v\">'+(typeof v==='object'?JSON.stringify(v,null,2):v)+'</div>').join('')+'</div>'}"
"async function loadDylibs(){const r=await api('/api/dylibs');const j=await r.json();document.getElementById('infoContent').innerHTML='<pre>'+j.dylibs.join('\\n')+'</pre>'}"
"async function loadCrashes(){const r=await api('/api/crashes');const j=await r.json();document.getElementById('infoContent').innerHTML='<div>'+j.crashes.map(c=>'<div class=\"file-row\" onclick=\"openFile(\\''+c+'\\')\">'+c+'</div>').join('')+'</div>'}"
"async function doRestart(){await api('/api/restart',{method:'POST'});alert('Restart triggered. App will close.')}"
"</script></body></html>";

#pragma mark - Helpers

static NSString *currentLANIPv4(void) {
    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) != 0) return nil;
    NSString *result = nil;
    for (struct ifaddrs *ifa = ifap; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        char ip[INET_ADDRSTRLEN];
        struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
        inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof ip);
        NSString *s = @(ip);
        if ([s isEqualToString:@"127.0.0.1"]) continue;
        if ([s hasPrefix:@"169.254."]) continue;
        if ([s hasPrefix:@"192.168."] || [s hasPrefix:@"10."] ||
            ([s hasPrefix:@"172."] && (s.length > 4))) {
            result = s;
            break;
        }
    }
    freeifaddrs(ifap);
    return result;
}

static NSString *constantTimeCompare(NSString *a, NSString *b) {
    return ([a length] == [b length] && [a isEqualToString:b]) ? @"ok" : nil;
}

static NSString *contentTypeForPath(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([@[@"txt", @"log", @"properties", @"cfg", @"toml", @"yml", @"yaml", @"md"] containsObject:ext]) return @"text/plain; charset=utf-8";
    if ([ext isEqualToString:@"json"]) return @"application/json; charset=utf-8";
    if ([ext isEqualToString:@"html"]) return @"text/html; charset=utf-8";
    if ([ext isEqualToString:@"png"]) return @"image/png";
    if ([@[@"jpg", @"jpeg"] containsObject:ext]) return @"image/jpeg";
    return @"application/octet-stream";
}

#pragma mark - Per-connection handler

@interface DebugConnection : NSObject
@property (nonatomic) int fd;
@property (nonatomic, weak) DebugServer *server;
@property (nonatomic) NSMutableData *buffer;
@property (nonatomic) NSUInteger expectedBodyLength;
@property (nonatomic) NSUInteger headerEndOffset;
- (instancetype)initWithFd:(int)fd server:(DebugServer *)server;
- (void)run;
@end

#pragma mark - DebugServer

@interface DebugServer ()
@property (nonatomic) int listenFd;
@property (nonatomic) dispatch_queue_t acceptQueue;
@property (nonatomic) dispatch_queue_t connQueue;
@property (nonatomic, copy) NSString *expectedToken;
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) uint16_t boundPort;
- (void)acceptLoop;
@end

@implementation DebugServer

+ (instancetype)shared {
    static DebugServer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [DebugServer new]; });
    return s;
}

+ (NSString *)generateToken {
    uint8_t bytes[24];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof bytes, bytes) != errSecSuccess) {
        for (int i = 0; i < (int)sizeof bytes; i++) bytes[i] = (uint8_t)arc4random_uniform(256);
    }
    NSMutableString *s = [NSMutableString stringWithCapacity:48];
    for (int i = 0; i < (int)sizeof bytes; i++) [s appendFormat:@"%02x", bytes[i]];
    return s;
}

- (BOOL)startWithPort:(uint16_t)port localhostOnly:(BOOL)localhostOnly token:(NSString *)token {
    if (self.running) [self stop];
    if (token.length < 8) {
        NSLog(@"[DebugServer] Refusing to start: token too short");
        return NO;
    }
    self.expectedToken = [token copy];

    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) {
        NSLog(@"[DebugServer] socket() failed: %s", strerror(errno));
        return NO;
    }
    int yes = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = localhostOnly ? htonl(INADDR_LOOPBACK) : INADDR_ANY;

    if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"[DebugServer] bind(:%u) failed: %s", port, strerror(errno));
        close(s);
        return NO;
    }
    if (listen(s, 16) < 0) {
        NSLog(@"[DebugServer] listen() failed: %s", strerror(errno));
        close(s);
        return NO;
    }

    self.listenFd = s;
    self.boundPort = port;
    self.running = YES;
    self.acceptQueue = dispatch_queue_create("amethyst.debug.accept", DISPATCH_QUEUE_SERIAL);
    self.connQueue = dispatch_queue_create("amethyst.debug.conn", DISPATCH_QUEUE_CONCURRENT);

    dispatch_async(self.acceptQueue, ^{ [self acceptLoop]; });

    NSLog(@"[DebugServer] Listening on %@", [self displayURL]);
    return YES;
}

- (void)acceptLoop {
    while (self.running) {
        int client = accept(self.listenFd, NULL, NULL);
        if (client < 0) {
            if (!self.running) break;
            usleep(50000);
            continue;
        }
        dispatch_async(self.connQueue, ^{
            DebugConnection *c = [[DebugConnection alloc] initWithFd:client server:self];
            [c run];
        });
    }
}

- (void)stop {
    self.running = NO;
    if (self.listenFd > 0) {
        close(self.listenFd);
        self.listenFd = 0;
    }
}

- (NSString *)displayURL {
    NSString *ip = currentLANIPv4() ?: @"127.0.0.1";
    return [NSString stringWithFormat:@"http://%@:%u", ip, self.boundPort];
}

@end

#pragma mark - DebugConnection

@implementation DebugConnection

- (instancetype)initWithFd:(int)fd server:(DebugServer *)server {
    if ((self = [super init])) {
        _fd = fd;
        _server = server;
        _buffer = [NSMutableData dataWithCapacity:8192];
        _expectedBodyLength = NSUIntegerMax;
        _headerEndOffset = NSNotFound;
    }
    return self;
}

- (void)run {
    char chunk[8192];
    while (self.fd > 0) {
        ssize_t n = read(self.fd, chunk, sizeof(chunk));
        if (n <= 0) break;
        [self.buffer appendBytes:chunk length:(NSUInteger)n];
        [self tryDispatch];
        if (self.buffer.length > 32 * 1024 * 1024) break;
    }
    if (self.fd > 0) {
        close(self.fd);
        self.fd = 0;
    }
}

- (void)tryDispatch {
    if (self.headerEndOffset == NSNotFound) {
        const char *bytes = self.buffer.bytes;
        for (NSUInteger i = 0; i + 3 < self.buffer.length; i++) {
            if (bytes[i] == '\r' && bytes[i+1] == '\n' && bytes[i+2] == '\r' && bytes[i+3] == '\n') {
                self.headerEndOffset = i + 4;
                break;
            }
        }
        if (self.headerEndOffset == NSNotFound) {
            if (self.buffer.length > 16*1024) {
                [self respond:413 contentType:@"text/plain" body:[@"Headers too large" dataUsingEncoding:NSUTF8StringEncoding]];
            }
            return;
        }
        NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, self.headerEndOffset - 4)];
        NSString *headers = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
        for (NSString *line in [headers componentsSeparatedByString:@"\r\n"]) {
            NSRange c = [line rangeOfString:@":"];
            if (c.location == NSNotFound) continue;
            NSString *k = [[line substringToIndex:c.location] lowercaseString];
            NSString *v = [[line substringFromIndex:c.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if ([k isEqualToString:@"content-length"]) {
                self.expectedBodyLength = (NSUInteger)v.integerValue;
                break;
            }
        }
        if (self.expectedBodyLength == NSUIntegerMax) self.expectedBodyLength = 0;
    }
    NSUInteger needed = self.headerEndOffset + self.expectedBodyLength;
    if (self.buffer.length < needed) return;
    [self handleRequest];
}

- (void)handleRequest {
    NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, self.headerEndOffset - 4)];
    NSString *headers = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
    NSArray<NSString *> *lines = [headers componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) { [self respond:400 contentType:@"text/plain" body:nil]; return; }
    NSArray<NSString *> *requestLine = [lines[0] componentsSeparatedByString:@" "];
    if (requestLine.count < 2) { [self respond:400 contentType:@"text/plain" body:nil]; return; }
    NSString *method = requestLine[0];
    NSString *target = requestLine[1];

    NSString *path = target;
    NSString *query = @"";
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        path = [target substringToIndex:q.location];
        query = [target substringFromIndex:q.location + 1];
    }

    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    for (NSString *kv in [query componentsSeparatedByString:@"&"]) {
        NSRange e = [kv rangeOfString:@"="];
        if (e.location == NSNotFound) continue;
        NSString *k = [[kv substringToIndex:e.location] stringByRemovingPercentEncoding] ?: @"";
        NSString *v = [[kv substringFromIndex:e.location + 1] stringByRemovingPercentEncoding] ?: @"";
        params[k] = v;
    }

    NSString *authHeader = nil;
    for (NSString *line in lines) {
        if ([[line lowercaseString] hasPrefix:@"authorization:"]) {
            authHeader = [line substringFromIndex:14];
            authHeader = [authHeader stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if ([authHeader hasPrefix:@"Bearer "]) authHeader = [authHeader substringFromIndex:7];
            break;
        }
    }
    NSString *suppliedToken = params[@"token"] ?: authHeader ?: @"";

    NSData *body = self.expectedBodyLength > 0
        ? [self.buffer subdataWithRange:NSMakeRange(self.headerEndOffset, self.expectedBodyLength)]
        : nil;

    [self route:method path:path params:params token:suppliedToken body:body];
}

#pragma mark - Routing

- (void)route:(NSString *)method path:(NSString *)path params:(NSDictionary *)params token:(NSString *)token body:(NSData *)body {
    if ([path isEqualToString:@"/"] && [method isEqualToString:@"GET"]) {
        [self respond:200 contentType:@"text/html; charset=utf-8" body:[kHTML dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    if ([path isEqualToString:@"/api/health"]) {
        [self respond:200 contentType:@"application/json" body:[@"{\"ok\":true}" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    if (!constantTimeCompare(token, self.server.expectedToken)) {
        [self respond:401 contentType:@"application/json" body:[@"{\"error\":\"unauthorized\"}" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    if ([path isEqualToString:@"/api/info"]) { [self handleInfo]; return; }
    if ([path isEqualToString:@"/api/log"]) { [self handleLog:params]; return; }
    if ([path isEqualToString:@"/api/files"]) { [self handleFiles:params]; return; }
    if ([path isEqualToString:@"/api/file"]) { [self handleFile:method params:params body:body]; return; }
    if ([path isEqualToString:@"/api/restart"] && [method isEqualToString:@"POST"]) { [self handleRestart]; return; }
    if ([path isEqualToString:@"/api/dylibs"]) { [self handleDylibs]; return; }
    if ([path isEqualToString:@"/api/crashes"]) { [self handleCrashes]; return; }

    [self respond:404 contentType:@"text/plain" body:[@"not found" dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - Endpoints

- (void)handleInfo {
    UIDevice *dev = UIDevice.currentDevice;
    NSProcessInfo *pi = NSProcessInfo.processInfo;
    NSDictionary *bundle = NSBundle.mainBundle.infoDictionary;
    const char *home = getenv("POJAV_HOME") ?: "";
    const char *gameDir = getenv("POJAV_GAME_DIR") ?: "";
    const char *renderer = getenv("AMETHYST_RENDERER") ?: "";

    struct statfs st;
    statfs("/var/mobile", &st);
    uint64_t freeBytes = (uint64_t)st.f_bavail * st.f_bsize;
    uint64_t totalBytes = (uint64_t)st.f_blocks * st.f_bsize;

    NSDictionary *info = @{
        @"appName": bundle[@"CFBundleName"] ?: @"",
        @"appVersion": bundle[@"CFBundleShortVersionString"] ?: @"",
        @"appBuild": bundle[@"CFBundleVersion"] ?: @"",
        @"bundleId": bundle[@"CFBundleIdentifier"] ?: @"",
        @"iosVersion": dev.systemVersion,
        @"deviceModel": dev.model,
        @"deviceName": dev.name,
        @"pid": @(getpid()),
        @"physicalMemoryMB": @(pi.physicalMemory / 1048576),
        @"processorCount": @(pi.processorCount),
        @"thermalState": @(pi.thermalState),
        @"pojavHome": @(home),
        @"pojavGameDir": @(gameDir),
        @"pojavRenderer": @(renderer),
        @"diskFreeMB": @(freeBytes / 1048576),
        @"diskTotalMB": @(totalBytes / 1048576),
        @"sandboxRoot": NSHomeDirectory(),
        @"isJailbroken": @(isJailbroken),
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:info options:NSJSONWritingPrettyPrinted error:nil];
    [self respond:200 contentType:@"application/json" body:json];
}

- (void)handleLog:(NSDictionary *)params {
    const char *home = getenv("POJAV_HOME");
    if (!home) { [self respond:500 contentType:@"text/plain" body:[@"POJAV_HOME unset" dataUsingEncoding:NSUTF8StringEncoding]]; return; }
    NSString *file = params[@"file"] ?: @"latestlog.txt";
    if ([file containsString:@"/"] || [file containsString:@".."]) {
        [self respond:400 contentType:@"text/plain" body:[@"invalid file" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    NSString *path = [NSString stringWithFormat:@"%s/%@", home, file];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        [self respond:404 contentType:@"text/plain" body:[@"log not found" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    NSInteger n = [params[@"n"] integerValue];
    if (n > 0) {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        NSInteger start = MAX(0, (NSInteger)lines.count - n);
        NSArray *tail = [lines subarrayWithRange:NSMakeRange(start, lines.count - start)];
        data = [[tail componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    }
    [self respond:200 contentType:@"text/plain; charset=utf-8" body:data];
}

- (NSString *)resolveSafePath:(NSString *)inputPath allowOutsideSandbox:(BOOL)allow {
    NSString *resolved = [inputPath stringByResolvingSymlinksInPath];
    if (!resolved.length) return nil;
    if ([resolved containsString:@"/.."]) return nil;
    if (allow) return resolved;
    NSString *sandbox = NSHomeDirectory();
    if (![resolved hasPrefix:sandbox]) return nil;
    return resolved;
}

- (void)handleFiles:(NSDictionary *)params {
    NSString *path = params[@"path"] ?: NSHomeDirectory();
    NSString *resolved = [self resolveSafePath:path allowOutsideSandbox:YES];
    if (!resolved) { [self respond:400 contentType:@"application/json" body:[@"{\"error\":\"invalid path\"}" dataUsingEncoding:NSUTF8StringEncoding]]; return; }

    NSError *err = nil;
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:resolved error:&err];
    if (!names) {
        NSDictionary *r = @{ @"error": err.localizedDescription ?: @"unreadable", @"path": resolved };
        NSData *j = [NSJSONSerialization dataWithJSONObject:r options:0 error:nil];
        [self respond:200 contentType:@"application/json" body:j];
        return;
    }
    names = [names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:names.count];
    NSUInteger limit = MIN(names.count, 1000);
    for (NSUInteger i = 0; i < limit; i++) {
        NSString *name = names[i];
        NSString *full = [resolved stringByAppendingPathComponent:name];
        NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:full error:nil];
        BOOL isDir = [attr[NSFileType] isEqualToString:NSFileTypeDirectory];
        [entries addObject:@{
            @"name": name,
            @"dir": @(isDir),
            @"size": attr[NSFileSize] ?: @0,
        }];
    }
    NSDictionary *r = @{ @"path": resolved, @"parent": [resolved stringByDeletingLastPathComponent] ?: @"/", @"entries": entries };
    NSData *j = [NSJSONSerialization dataWithJSONObject:r options:0 error:nil];
    [self respond:200 contentType:@"application/json" body:j];
}

- (void)handleFile:(NSString *)method params:(NSDictionary *)params body:(NSData *)body {
    NSString *path = params[@"path"];
    if (!path.length) { [self respond:400 contentType:@"text/plain" body:[@"missing path" dataUsingEncoding:NSUTF8StringEncoding]]; return; }
    NSString *resolved = [self resolveSafePath:path allowOutsideSandbox:YES];
    if (!resolved) { [self respond:400 contentType:@"text/plain" body:[@"invalid path" dataUsingEncoding:NSUTF8StringEncoding]]; return; }

    if ([method isEqualToString:@"GET"]) {
        NSData *data = [NSData dataWithContentsOfFile:resolved];
        if (!data) { [self respond:404 contentType:@"text/plain" body:[@"not found" dataUsingEncoding:NSUTF8StringEncoding]]; return; }
        if (data.length > 16*1024*1024) {
            data = [data subdataWithRange:NSMakeRange(0, 16*1024*1024)];
        }
        [self respond:200 contentType:contentTypeForPath(resolved) body:data];
        return;
    }

    if ([method isEqualToString:@"PUT"]) {
        NSError *err = nil;
        BOOL ok = [body writeToFile:resolved options:NSDataWritingAtomic error:&err];
        if (!ok) {
            NSString *msg = [NSString stringWithFormat:@"{\"error\":\"%@\"}", err.localizedDescription ?: @"write failed"];
            [self respond:500 contentType:@"application/json" body:[msg dataUsingEncoding:NSUTF8StringEncoding]];
            return;
        }
        [self respond:200 contentType:@"application/json" body:[@"{\"ok\":true}" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    if ([method isEqualToString:@"DELETE"]) {
        NSError *err = nil;
        BOOL ok = [NSFileManager.defaultManager removeItemAtPath:resolved error:&err];
        if (!ok) {
            NSString *msg = [NSString stringWithFormat:@"{\"error\":\"%@\"}", err.localizedDescription ?: @"delete failed"];
            [self respond:500 contentType:@"application/json" body:[msg dataUsingEncoding:NSUTF8StringEncoding]];
            return;
        }
        [self respond:200 contentType:@"application/json" body:[@"{\"ok\":true}" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    [self respond:405 contentType:@"text/plain" body:[@"method not allowed" dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)handleRestart {
    [self respond:200 contentType:@"application/json" body:[@"{\"ok\":true}" dataUsingEncoding:NSUTF8StringEncoding]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

- (void)handleDylibs {
    uint32_t count = _dyld_image_count();
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        const char *n = _dyld_get_image_name(i);
        if (n) [names addObject:@(n)];
    }
    NSDictionary *r = @{ @"dylibs": names, @"count": @(count) };
    NSData *j = [NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil];
    [self respond:200 contentType:@"application/json" body:j];
}

- (void)handleCrashes {
    NSMutableArray *crashes = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    NSArray *roots = @[
        [home stringByAppendingPathComponent:@"Documents/crash-reports"],
        [home stringByAppendingPathComponent:@"Documents/.minecraft/crash-reports"],
        [NSString stringWithFormat:@"%s/crash-reports", getenv("POJAV_HOME") ?: ""],
    ];
    for (NSString *root in roots) {
        NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil];
        for (NSString *f in files) {
            [crashes addObject:[root stringByAppendingPathComponent:f]];
        }
    }
    NSDictionary *r = @{ @"crashes": crashes };
    NSData *j = [NSJSONSerialization dataWithJSONObject:r options:0 error:nil];
    [self respond:200 contentType:@"application/json" body:j];
}

#pragma mark - Response

- (void)respond:(int)status contentType:(NSString *)contentType body:(NSData *)body {
    static NSDictionary *codes = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        codes = @{ @200: @"OK", @201: @"Created", @204: @"No Content", @400: @"Bad Request",
                   @401: @"Unauthorized", @404: @"Not Found", @405: @"Method Not Allowed",
                   @413: @"Payload Too Large", @500: @"Internal Server Error" };
    });
    NSString *reason = codes[@(status)] ?: @"OK";
    NSUInteger len = body.length;
    NSMutableString *headers = [NSMutableString stringWithFormat:
        @"HTTP/1.1 %d %@\r\n"
        @"Content-Type: %@\r\n"
        @"Content-Length: %lu\r\n"
        @"Connection: close\r\n"
        @"Cache-Control: no-store\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"\r\n",
        status, reason, contentType, (unsigned long)len];
    NSMutableData *out = [NSMutableData dataWithData:[headers dataUsingEncoding:NSUTF8StringEncoding]];
    if (body) [out appendData:body];

    if (self.fd <= 0) return;
    const uint8_t *p = out.bytes;
    size_t remaining = out.length;
    while (remaining > 0) {
        ssize_t w = write(self.fd, p, remaining);
        if (w <= 0) break;
        p += w;
        remaining -= (size_t)w;
    }
    close(self.fd);
    self.fd = 0;
}

@end
