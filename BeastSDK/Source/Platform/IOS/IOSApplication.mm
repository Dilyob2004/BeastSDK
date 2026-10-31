// iOS host: UIKit scene lifecycle, a CAMetalLayer-backed view and a CADisplayLink frame loop.
// Compiled only for iOS (IOS/ directory) with ARC. Everything runs on the main thread, which is
// the Application's Run thread on this platform.
#if defined(__APPLE__)
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "Core/Application.h"
#include <crt_externs.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <exception>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>

namespace
{
    struct Host
    {
        Beast::Application* application = nullptr;
        bool started = false, surface = false, foreground = false, active = false, failed = false;
        CFTimeInterval previousFrame = 0;
        std::unordered_map<const void*, int> touches; // UITouch* -> stable pointer id while it lasts.
        int nextTouch = 1;
    };
    Host host;

    void Fail(const char* message)
    {
        if (host.failed) return;
        host.failed = true;
        Beast::Log(message ? message : "Unhandled exception in the iOS host.");
        // Like a failed Android/Windows loop: stop the process; the simulator and Xcode keep the log.
        std::exit(1);
    }
    template<class Function> void Guard(const char* where, Function&& function)
    {
        if (host.failed || !host.application) return;
        try { function(); }
        catch (const std::exception& error) { Fail(error.what()); }
        catch (...) { Fail(where); }
    }
    void Dispatch(Beast::EventType type)
    {
        Guard("Unhandled exception in an iOS lifecycle event.", [&] {
            Beast::Event event{};
            event.type = type;
            host.application->Dispatch(event);
        });
    }
    int Pixels(CGFloat points, CGFloat scale) { return std::max(0, static_cast<int>(std::lround(points * scale))); }

    // System pasteboard; the SDK protocol is UTF-16 like NSString.
    class IOSClipboard final : public Beast::Clipboard
    {
    public:
        std::optional<std::u16string> ReadClipboard() override
        {
            NSString* text = UIPasteboard.generalPasteboard.string;
            if (!text) return {};
            std::u16string result(text.length, u'\0');
            [text getCharacters:reinterpret_cast<unichar*>(result.data()) range:NSMakeRange(0, text.length)];
            return result;
        }
        bool WriteClipboard(const std::u16string& text) override
        {
            UIPasteboard.generalPasteboard.string = [NSString stringWithCharacters:reinterpret_cast<const unichar*>(text.data()) length:text.size()];
            return true;
        }
    };

    Beast::Key TranslateKey(long usage)
    {
        if (usage >= 0x04 && usage <= 0x1D) return static_cast<Beast::Key>(static_cast<unsigned>(Beast::Key::A) + (usage - 0x04));
        if (usage >= 0x1E && usage <= 0x26) return static_cast<Beast::Key>(static_cast<unsigned>(Beast::Key::D1) + (usage - 0x1E));
        switch (usage)
        {
        case 0x27: return Beast::Key::D0;
        case 0x28: case 0x58: return Beast::Key::Enter;
        case 0x29: return Beast::Key::Escape;
        case 0x2A: return Beast::Key::Backspace;
        case 0x2B: return Beast::Key::Tab;
        case 0x2C: return Beast::Key::Space;
        case 0x4A: return Beast::Key::Home;
        case 0x4C: return Beast::Key::Delete;
        case 0x4D: return Beast::Key::End;
        case 0x4F: return Beast::Key::Right;
        case 0x50: return Beast::Key::Left;
        case 0x51: return Beast::Key::Down;
        case 0x52: return Beast::Key::Up;
        case 0xE1: case 0xE5: return Beast::Key::Shift;
        // Command acts as Control so that the SDK's Ctrl+C/X/V/Z shortcuts follow Apple conventions.
        case 0xE0: case 0xE4: case 0xE3: case 0xE7: return Beast::Key::Control;
        case 0xE2: case 0xE6: return Beast::Key::Alt;
        default: return Beast::Key::Unknown;
        }
    }
}

@interface BeastMetalView : UIView
@end

@implementation BeastMetalView
+ (Class)layerClass { return [CAMetalLayer class]; }

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        self.multipleTouchEnabled = YES;
        self.opaque = YES;
        self.backgroundColor = UIColor.blackColor;
        auto* layer = (CAMetalLayer*)self.layer;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = YES;
        layer.opaque = YES;
    }
    return self;
}

- (CGFloat)displayScale
{
    const CGFloat scale = self.traitCollection.displayScale;
    return scale > 0 ? scale : (self.window ? self.window.screen.scale : UIScreen.mainScreen.scale);
}

// Window size, scale and safe area in physical pixels; creates the surface on the first real size.
- (void)updateGeometry
{
    if (!host.application || host.failed) return;
    const CGFloat scale = [self displayScale];
    self.contentScaleFactor = scale;
    auto* layer = (CAMetalLayer*)self.layer;
    layer.contentsScale = scale;
    auto& window = host.application->PlatformWindow();
    const int width = Pixels(self.bounds.size.width, scale), height = Pixels(self.bounds.size.height, scale);
    if (width > 0 && height > 0) layer.drawableSize = CGSizeMake(width, height);
    const UIEdgeInsets insets = self.safeAreaInsets;
    const int left = std::min(width, Pixels(insets.left, scale)), top = std::min(height, Pixels(insets.top, scale));
    const bool changed = window.width != width || window.height != height || window.scale != float(scale) ||
        window.contentX != left || window.contentY != top;
    window.width = width; window.height = height; window.scale = float(scale);
    window.contentX = left; window.contentY = top;
    window.contentWidth = std::max(0, width - left - Pixels(insets.right, scale));
    window.contentHeight = std::max(0, height - top - Pixels(insets.bottom, scale));
    window.imeBottom = 0;
    if (!host.surface)
    {
        if (width <= 0 || height <= 0) return;
        window.nativeHandle = (__bridge void*)layer;
        window.visible = host.foreground;
        host.surface = true;
        Dispatch(Beast::EventType::SurfaceCreated);
    }
    else if (!changed) return;
    Guard("Unhandled exception in an iOS resize event.", [&] {
        Beast::Event event{};
        event.type = Beast::EventType::Resized;
        event.width = width; event.height = height;
        host.application->Dispatch(event);
    });
}

- (void)layoutSubviews { [super layoutSubviews]; [self updateGeometry]; }
- (void)safeAreaInsetsDidChange { [super safeAreaInsetsDidChange]; [self updateGeometry]; }
- (void)traitCollectionDidChange:(UITraitCollection*)previous { [super traitCollectionDidChange:previous]; [self updateGeometry]; }

- (void)sendTouches:(NSSet<UITouch*>*)touches type:(Beast::EventType)type
{
    const CGFloat scale = [self displayScale];
    for (UITouch* touch in touches)
    {
        const void* key = (__bridge const void*)touch;
        auto found = host.touches.find(key);
        if (type == Beast::EventType::TouchDown && found == host.touches.end())
            found = host.touches.emplace(key, host.nextTouch++).first;
        if (found == host.touches.end()) continue;
        const CGPoint point = [touch locationInView:self];
        Beast::Event event{};
        event.type = type;
        event.pointerId = found->second;
        event.x = float(point.x * scale);
        event.y = float(point.y * scale);
        event.timestamp = touch.timestamp; // Seconds since boot: the CADisplayLink time domain.
        if (type == Beast::EventType::TouchUp || type == Beast::EventType::TouchCancel) host.touches.erase(found);
        Guard("Unhandled exception in an iOS touch event.", [&] { host.application->Dispatch(event); });
    }
}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self sendTouches:touches type:Beast::EventType::TouchDown]; }
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self sendTouches:touches type:Beast::EventType::TouchMove]; }
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self sendTouches:touches type:Beast::EventType::TouchUp]; }
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self sendTouches:touches type:Beast::EventType::TouchCancel]; }

- (void)cancelAllTouches
{
    for (const auto& [touch, id] : host.touches)
    {
        Beast::Event event{};
        event.type = Beast::EventType::TouchCancel;
        event.pointerId = id;
        if (const auto* state = host.application ? &host.application->GetInput() : nullptr)
            for (const auto& item : state->GetTouches()) if (item.first == id) { event.x = item.second.x; event.y = item.second.y; }
        Guard("Unhandled exception in an iOS touch event.", [&] { host.application->Dispatch(event); });
    }
    host.touches.clear();
}

// Hardware keyboard (iPad keyboards, the simulator's Mac keyboard). The on-screen keyboard and IME
// are a separate text input service (UITextInput), not emulated here.
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)sendPresses:(NSSet<UIPress*>*)presses down:(BOOL)down
{
    BOOL handled = NO;
    for (UIPress* press in presses)
    {
        UIKey* key = press.key;
        if (!key) continue;
        Beast::Event event{};
        event.type = down ? Beast::EventType::KeyDown : Beast::EventType::KeyUp;
        event.key = TranslateKey(long(key.keyCode));
        event.timestamp = press.timestamp;
        Guard("Unhandled exception in an iOS key event.", [&] { host.application->Dispatch(event); });
        handled |= event.key != Beast::Key::Unknown;
        if (!down || (key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierControl))) continue;
        NSString* text = key.characters;
        for (NSUInteger index = 0; index < text.length;)
        {
            const NSRange range = [text rangeOfComposedCharacterSequenceAtIndex:index];
            UTF32Char character = 0;
            [text getBytes:&character maxLength:sizeof(character) usedLength:nullptr encoding:NSUTF32LittleEndianStringEncoding
                   options:0 range:NSMakeRange(range.location, range.length) remainingRange:nullptr];
            index = range.location + range.length;
            // Control characters and Apple's private-use function key codes (arrows, F-keys).
            if (character < 0x20 || character == 0x7F || (character >= 0xF700 && character <= 0xF8FF) || character > 0x10FFFF) continue;
            event.type = Beast::EventType::TextInput;
            event.character = char32_t(character);
            Guard("Unhandled exception in an iOS text event.", [&] { host.application->Dispatch(event); });
            handled = YES;
        }
    }
    return handled;
}
- (void)pressesBegan:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{ if (![self sendPresses:presses down:YES]) [super pressesBegan:presses withEvent:event]; }
- (void)pressesEnded:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{ if (![self sendPresses:presses down:NO]) [super pressesEnded:presses withEvent:event]; }
- (void)pressesCancelled:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{ if (![self sendPresses:presses down:NO]) [super pressesCancelled:presses withEvent:event]; }
@end

@interface BeastViewController : UIViewController
@end

@implementation BeastViewController
- (void)loadView { self.view = [[BeastMetalView alloc] initWithFrame:UIScreen.mainScreen.bounds]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self.view becomeFirstResponder]; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
@end

@interface BeastSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow* window;
@property (strong, nonatomic) CADisplayLink* displayLink;
@end

@implementation BeastSceneDelegate
- (BeastMetalView*)metalView { return (BeastMetalView*)self.window.rootViewController.view; }

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options
{
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
    self.window.rootViewController = [BeastViewController new];
    [self.window makeKeyAndVisible];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    self.displayLink.paused = YES;
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)frame:(CADisplayLink*)link
{
    if (!host.application || host.failed) return;
    if (host.application->IsExitRequested())
    {
        // iOS has no "close window"; an explicit exit request ends the process like on other platforms.
        link.paused = YES;
        Guard("Unhandled exception stopping the iOS application.", [&] { host.application->OnStop(); });
        std::exit(0);
    }
    if (!host.foreground || !host.active || !host.surface) return;
    const CFTimeInterval now = link.timestamp;
    const double delta = host.previousFrame > 0 && now > host.previousFrame ? std::min(now - host.previousFrame, 0.1) : 0;
    host.previousFrame = now;
    host.application->PlatformWindow().frameTimeSeconds = now;
    Guard("Unhandled exception updating the iOS application.", [&] { host.application->OnUpdate(delta); });
    host.application->BeginFrame(); // Preserve input edges until an actual frame consumes them.
}

- (void)sceneWillEnterForeground:(UIScene*)scene
{
    host.foreground = true;
    if (host.application) host.application->PlatformWindow().visible = host.surface;
    Dispatch(Beast::EventType::Resumed);
}
- (void)sceneDidBecomeActive:(UIScene*)scene
{
    host.active = true;
    host.previousFrame = 0;
    Dispatch(Beast::EventType::FocusGained);
    self.displayLink.paused = NO;
}
- (void)sceneWillResignActive:(UIScene*)scene
{
    host.active = false;
    self.displayLink.paused = YES;
    [[self metalView] cancelAllTouches];
    Dispatch(Beast::EventType::FocusLost);
}
- (void)sceneDidEnterBackground:(UIScene*)scene
{
    // No GPU work is allowed in the background; the display link is already paused.
    host.foreground = false;
    if (host.application) host.application->PlatformWindow().visible = false;
    Dispatch(Beast::EventType::Suspended);
}
- (void)sceneDidDisconnect:(UIScene*)scene
{
    [self.displayLink invalidate];
    self.displayLink = nil;
    if (host.surface && host.application)
    {
        // Delivered while the layer is still alive, like Android's TERM_WINDOW.
        Dispatch(Beast::EventType::SurfaceDestroyed);
        host.application->PlatformWindow().nativeHandle = nullptr;
        host.application->PlatformWindow().visible = false;
    }
    host.surface = false;
}
@end

@interface BeastAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation BeastAppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options
{
    // The scene delegate creates the window: since iOS 27 UIKit stops apps that create it here.
    Guard("Unhandled exception starting the iOS application.", [&] {
        const auto definition = host.application->Configure();
        Beast::Log(definition.title.c_str());
        host.application->OnStart();
        host.started = true;
        host.application->BeginFrame();
    });
    return YES;
}
- (UISceneConfiguration*)application:(UIApplication*)application configurationForConnectingSceneSession:(UISceneSession*)session
                             options:(UISceneConnectionOptions*)options
{
    UISceneConfiguration* configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    configuration.delegateClass = [BeastSceneDelegate class];
    return configuration;
}
- (void)applicationWillTerminate:(UIApplication*)application
{
    if (!host.started) return;
    host.started = false;
    Guard("Unhandled exception stopping the iOS application.", [&] { host.application->OnStop(); });
}
@end

namespace Beast
{
    // UIApplicationMain owns the main thread's run loop and does not return; the application
    // object lives in main()'s frame (BEAST_APPLICATION) for the whole process.
    int Run(Application& application, void*)
    {
        host.application = &application;
        application.PlatformWindow().clipboard = std::make_shared<IOSClipboard>();
        @autoreleasepool
        {
            return UIApplicationMain(*_NSGetArgc(), *_NSGetArgv(), nil, NSStringFromClass([BeastAppDelegate class]));
        }
    }
}
#endif
