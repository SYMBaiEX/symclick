#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <mach/mach_time.h>
#include <pthread.h>
#include <string>
#include <thread>

namespace {

constexpr double kDefaultCPS = 25.0;
constexpr double kMinimumCPS = 1.0;
constexpr double kMaximumCPS = 5000.0;
constexpr UInt32 kDefaultKeyCode = kVK_ANSI_C;
constexpr UInt32 kDefaultModifiers = controlKey | optionKey;
constexpr OSType kHotKeySignature = 0x54434C4B;  // "TCLK"
constexpr UInt32 kHotKeyID = 1;

NSString *const kCPSPreference = @"clicksPerSecond";
NSString *const kMouseButtonPreference = @"mouseButton";
NSString *const kHotKeyCodePreference = @"hotKeyCode";
NSString *const kHotKeyModifiersPreference = @"hotKeyModifiers";

double NormalizeCPS(double value) {
    if (!std::isfinite(value)) {
        return kDefaultCPS;
    }
    return std::clamp(std::round(value), kMinimumCPS, kMaximumCPS);
}

NSString *KeyName(UInt32 keyCode) {
    switch (keyCode) {
        case kVK_ANSI_A: return @"A";
        case kVK_ANSI_B: return @"B";
        case kVK_ANSI_C: return @"C";
        case kVK_ANSI_D: return @"D";
        case kVK_ANSI_E: return @"E";
        case kVK_ANSI_F: return @"F";
        case kVK_ANSI_G: return @"G";
        case kVK_ANSI_H: return @"H";
        case kVK_ANSI_I: return @"I";
        case kVK_ANSI_J: return @"J";
        case kVK_ANSI_K: return @"K";
        case kVK_ANSI_L: return @"L";
        case kVK_ANSI_M: return @"M";
        case kVK_ANSI_N: return @"N";
        case kVK_ANSI_O: return @"O";
        case kVK_ANSI_P: return @"P";
        case kVK_ANSI_Q: return @"Q";
        case kVK_ANSI_R: return @"R";
        case kVK_ANSI_S: return @"S";
        case kVK_ANSI_T: return @"T";
        case kVK_ANSI_U: return @"U";
        case kVK_ANSI_V: return @"V";
        case kVK_ANSI_W: return @"W";
        case kVK_ANSI_X: return @"X";
        case kVK_ANSI_Y: return @"Y";
        case kVK_ANSI_Z: return @"Z";
        case kVK_ANSI_0: return @"0";
        case kVK_ANSI_1: return @"1";
        case kVK_ANSI_2: return @"2";
        case kVK_ANSI_3: return @"3";
        case kVK_ANSI_4: return @"4";
        case kVK_ANSI_5: return @"5";
        case kVK_ANSI_6: return @"6";
        case kVK_ANSI_7: return @"7";
        case kVK_ANSI_8: return @"8";
        case kVK_ANSI_9: return @"9";
        case kVK_Space: return @"Space";
        case kVK_Return: return @"Return";
        case kVK_Tab: return @"Tab";
        case kVK_Delete: return @"Delete";
        case kVK_ForwardDelete: return @"Forward Delete";
        case kVK_Home: return @"Home";
        case kVK_End: return @"End";
        case kVK_PageUp: return @"Page Up";
        case kVK_PageDown: return @"Page Down";
        case kVK_LeftArrow: return @"←";
        case kVK_RightArrow: return @"→";
        case kVK_UpArrow: return @"↑";
        case kVK_DownArrow: return @"↓";
        case kVK_F1: return @"F1";
        case kVK_F2: return @"F2";
        case kVK_F3: return @"F3";
        case kVK_F4: return @"F4";
        case kVK_F5: return @"F5";
        case kVK_F6: return @"F6";
        case kVK_F7: return @"F7";
        case kVK_F8: return @"F8";
        case kVK_F9: return @"F9";
        case kVK_F10: return @"F10";
        case kVK_F11: return @"F11";
        case kVK_F12: return @"F12";
        case kVK_F13: return @"F13";
        case kVK_F14: return @"F14";
        case kVK_F15: return @"F15";
        case kVK_F16: return @"F16";
        case kVK_F17: return @"F17";
        case kVK_F18: return @"F18";
        case kVK_F19: return @"F19";
        case kVK_F20: return @"F20";
        case kVK_ANSI_Grave: return @"`";
        case kVK_ANSI_Minus: return @"-";
        case kVK_ANSI_Equal: return @"=";
        case kVK_ANSI_LeftBracket: return @"[";
        case kVK_ANSI_RightBracket: return @"]";
        case kVK_ANSI_Backslash: return @"\\";
        case kVK_ANSI_Semicolon: return @";";
        case kVK_ANSI_Quote: return @"'";
        case kVK_ANSI_Comma: return @",";
        case kVK_ANSI_Period: return @".";
        case kVK_ANSI_Slash: return @"/";
        default: return [NSString stringWithFormat:@"Key %u", keyCode];
    }
}

NSString *ShortcutDisplay(UInt32 keyCode, UInt32 modifiers) {
    NSMutableString *display = [NSMutableString string];
    if (modifiers & controlKey) [display appendString:@"⌃"];
    if (modifiers & optionKey) [display appendString:@"⌥"];
    if (modifiers & shiftKey) [display appendString:@"⇧"];
    if (modifiers & cmdKey) [display appendString:@"⌘"];
    [display appendString:KeyName(keyCode)];
    return display;
}

UInt32 CarbonModifiersFromEvent(NSEventModifierFlags flags) {
    UInt32 result = 0;
    if (flags & NSEventModifierFlagControl) result |= controlKey;
    if (flags & NSEventModifierFlagOption) result |= optionKey;
    if (flags & NSEventModifierFlagShift) result |= shiftKey;
    if (flags & NSEventModifierFlagCommand) result |= cmdKey;
    return result;
}

bool IsFunctionKey(UInt32 keyCode) {
    switch (keyCode) {
        case kVK_F1: case kVK_F2: case kVK_F3: case kVK_F4: case kVK_F5:
        case kVK_F6: case kVK_F7: case kVK_F8: case kVK_F9: case kVK_F10:
        case kVK_F11: case kVK_F12: case kVK_F13: case kVK_F14: case kVK_F15:
        case kVK_F16: case kVK_F17: case kVK_F18: case kVK_F19: case kVK_F20:
            return true;
        default:
            return false;
    }
}

class ClickEngine {
public:
    ~ClickEngine() { stop(); }

    void setClicksPerSecond(double cps) { cps_.store(NormalizeCPS(cps)); }
    void setMouseButton(int button) { mouseButton_.store(std::clamp(button, 0, 2)); }
    bool isRunning() const { return running_.load(); }

    void start() {
        bool expected = false;
        if (!running_.compare_exchange_strong(expected, true)) return;
        if (worker_.joinable()) worker_.join();
        worker_ = std::thread([this] { run(); });
    }

    void stop() {
        running_.store(false);
        if (worker_.joinable()) worker_.join();
    }

private:
    static uint64_t ticksForNanoseconds(double nanoseconds, const mach_timebase_info_data_t &timebase) {
        return static_cast<uint64_t>(nanoseconds * static_cast<double>(timebase.denom) /
                                     static_cast<double>(timebase.numer));
    }

    void postClick(CGEventSourceRef source) const {
        CGEventRef locationEvent = CGEventCreate(nullptr);
        if (!locationEvent) return;
        CGPoint location = CGEventGetLocation(locationEvent);
        CFRelease(locationEvent);

        CGMouseButton button = kCGMouseButtonLeft;
        CGEventType downType = kCGEventLeftMouseDown;
        CGEventType upType = kCGEventLeftMouseUp;
        switch (mouseButton_.load()) {
            case 1:
                button = kCGMouseButtonRight;
                downType = kCGEventRightMouseDown;
                upType = kCGEventRightMouseUp;
                break;
            case 2:
                button = kCGMouseButtonCenter;
                downType = kCGEventOtherMouseDown;
                upType = kCGEventOtherMouseUp;
                break;
            default:
                break;
        }

        CGEventRef down = CGEventCreateMouseEvent(source, downType, location, button);
        CGEventRef up = CGEventCreateMouseEvent(source, upType, location, button);
        if (down && up) {
            CGEventSetIntegerValueField(down, kCGMouseEventClickState, 1);
            CGEventSetIntegerValueField(up, kCGMouseEventClickState, 1);
            CGEventPost(kCGHIDEventTap, down);
            CGEventPost(kCGHIDEventTap, up);
        }
        if (down) CFRelease(down);
        if (up) CFRelease(up);
    }

    void run() {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
        if (!source) {
            running_.store(false);
            return;
        }
        CGEventSourceSetLocalEventsSuppressionInterval(source, 0.0);

        mach_timebase_info_data_t timebase{};
        mach_timebase_info(&timebase);
        uint64_t nextDeadline = mach_absolute_time();
        const uint64_t maximumStopLatency = ticksForNanoseconds(5'000'000.0, timebase);

        while (running_.load()) {
            postClick(source);

            const double cps = cps_.load();
            const uint64_t interval = std::max<uint64_t>(
                1, ticksForNanoseconds(1'000'000'000.0 / cps, timebase));
            nextDeadline += interval;

            uint64_t now = mach_absolute_time();
            if (now > nextDeadline + interval * 2) {
                nextDeadline = now;
                continue;
            }

            while (running_.load() && now < nextDeadline) {
                mach_wait_until(std::min(nextDeadline, now + maximumStopLatency));
                now = mach_absolute_time();
            }
        }

        CFRelease(source);
    }

    std::atomic<bool> running_{false};
    std::atomic<double> cps_{kDefaultCPS};
    std::atomic<int> mouseButton_{0};
    std::thread worker_;
};

NSTextField *Label(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

}  // namespace

@class AppDelegate;

@interface HotKeyRecorderButton : NSButton
@property(nonatomic, weak) AppDelegate *recorderDelegate;
@property(nonatomic) BOOL recording;
- (void)beginRecording;
- (void)finishRecording;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, NSTextFieldDelegate>
- (void)recorderDidCaptureKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers;
- (void)recorderDidCancel;
@end

@implementation HotKeyRecorderButton

- (BOOL)acceptsFirstResponder { return YES; }

- (void)beginRecording {
    self.recording = YES;
    self.title = @"Press a shortcut…";
    [self.window makeFirstResponder:self];
}

- (void)finishRecording {
    self.recording = NO;
}

- (void)keyDown:(NSEvent *)event {
    if (!self.recording) {
        [super keyDown:event];
        return;
    }
    if (event.keyCode == kVK_Escape) {
        [self.recorderDelegate recorderDidCancel];
        return;
    }

    const UInt32 modifiers = CarbonModifiersFromEvent(
        event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
    if (modifiers == 0 && !IsFunctionKey(event.keyCode)) {
        NSBeep();
        self.title = @"Add ⌃, ⌥, ⇧, or ⌘";
        return;
    }
    [self.recorderDelegate recorderDidCaptureKeyCode:event.keyCode modifiers:modifiers];
}

@end

@implementation AppDelegate {
    ClickEngine _engine;
    EventHotKeyRef _hotKey;
    EventHandlerRef _hotKeyHandler;
    UInt32 _hotKeyCode;
    UInt32 _hotKeyModifiers;
    double _cps;
    int _mouseButton;

    NSStatusItem *_statusItem;
    NSMenu *_menu;
    NSMenuItem *_statusMenuItem;
    NSMenuItem *_toggleMenuItem;
    NSMenuItem *_speedMenuItem;
    NSMenu *_speedMenu;
    NSMenu *_mouseMenu;

    NSWindow *_preferencesWindow;
    HotKeyRecorderButton *_recorderButton;
    NSTextField *_speedField;
    NSStepper *_speedStepper;
    NSPopUpButton *_mousePopup;
    NSTextField *_permissionLabel;
}

static OSStatus HandleGlobalHotKey(EventHandlerCallRef, EventRef event, void *userData) {
    EventHotKeyID hotKeyID{};
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, nullptr,
                          sizeof(hotKeyID), nullptr, &hotKeyID) == noErr &&
        hotKeyID.signature == kHotKeySignature && hotKeyID.id == kHotKeyID) {
        AppDelegate *delegate = (__bridge AppDelegate *)userData;
        [delegate performSelectorOnMainThread:@selector(toggleClicking:) withObject:nil waitUntilDone:NO];
    }
    return noErr;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults registerDefaults:@{
        kCPSPreference: @(kDefaultCPS),
        kMouseButtonPreference: @0,
        kHotKeyCodePreference: @(kDefaultKeyCode),
        kHotKeyModifiersPreference: @(kDefaultModifiers),
    }];

    _cps = NormalizeCPS([defaults doubleForKey:kCPSPreference]);
    _mouseButton = std::clamp((int)[defaults integerForKey:kMouseButtonPreference], 0, 2);
    _hotKeyCode = (UInt32)[defaults integerForKey:kHotKeyCodePreference];
    _hotKeyModifiers = (UInt32)[defaults integerForKey:kHotKeyModifiersPreference];
    _engine.setClicksPerSecond(_cps);
    _engine.setMouseButton(_mouseButton);

    [self buildMenu];
    [self installHotKeyHandler];
    if (![self registerHotKeyCode:_hotKeyCode modifiers:_hotKeyModifiers]) {
        _hotKeyCode = kDefaultKeyCode;
        _hotKeyModifiers = kDefaultModifiers;
        [self registerHotKeyCode:_hotKeyCode modifiers:_hotKeyModifiers];
    }
    [self updateUI];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    _engine.stop();
    if (_hotKey) UnregisterEventHotKey(_hotKey);
    if (_hotKeyHandler) RemoveEventHandler(_hotKeyHandler);
}

- (void)buildMenu {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _statusItem.button.toolTip = @"TurboClick";

    _menu = [[NSMenu alloc] initWithTitle:@"TurboClick"];
    _menu.delegate = self;
    _menu.autoenablesItems = NO;

    _statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"Idle" action:nil keyEquivalent:@""];
    _statusMenuItem.enabled = NO;
    [_menu addItem:_statusMenuItem];

    _toggleMenuItem = [[NSMenuItem alloc] initWithTitle:@"Start Clicking" action:@selector(toggleClicking:) keyEquivalent:@""];
    _toggleMenuItem.target = self;
    [_menu addItem:_toggleMenuItem];
    [_menu addItem:NSMenuItem.separatorItem];

    _speedMenuItem = [[NSMenuItem alloc] initWithTitle:@"Speed" action:nil keyEquivalent:@""];
    _speedMenu = [[NSMenu alloc] initWithTitle:@"Speed"];
    const int presets[] = {1, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000};
    for (int preset : presets) {
        NSString *title = preset == 5000 ? @"Maximum (5,000 CPS)" :
            [NSString stringWithFormat:@"%d CPS", preset];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(selectSpeed:) keyEquivalent:@""];
        item.target = self;
        item.tag = preset;
        [_speedMenu addItem:item];
    }
    [_speedMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *customSpeed = [[NSMenuItem alloc] initWithTitle:@"Custom…" action:@selector(showPreferences:) keyEquivalent:@""];
    customSpeed.target = self;
    [_speedMenu addItem:customSpeed];
    _speedMenuItem.submenu = _speedMenu;
    [_menu addItem:_speedMenuItem];

    NSMenuItem *mouseMenuItem = [[NSMenuItem alloc] initWithTitle:@"Mouse Button" action:nil keyEquivalent:@""];
    _mouseMenu = [[NSMenu alloc] initWithTitle:@"Mouse Button"];
    for (NSInteger button = 0; button < 3; ++button) {
        NSArray<NSString *> *names = @[@"Left", @"Right", @"Middle"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:names[button] action:@selector(selectMouseButton:) keyEquivalent:@""];
        item.target = self;
        item.tag = button;
        [_mouseMenu addItem:item];
    }
    mouseMenuItem.submenu = _mouseMenu;
    [_menu addItem:mouseMenuItem];
    [_menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *preferences = [[NSMenuItem alloc] initWithTitle:@"Preferences…" action:@selector(showPreferences:) keyEquivalent:@","];
    preferences.target = self;
    [_menu addItem:preferences];

    NSMenuItem *accessibility = [[NSMenuItem alloc] initWithTitle:@"Accessibility Settings…" action:@selector(openAccessibilitySettings:) keyEquivalent:@""];
    accessibility.target = self;
    [_menu addItem:accessibility];

    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About TurboClick" action:@selector(showAbout:) keyEquivalent:@""];
    about.target = self;
    [_menu addItem:about];
    [_menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit TurboClick" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [_menu addItem:quit];

    _statusItem.menu = _menu;
}

- (void)installHotKeyHandler {
    EventTypeSpec type{ kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&HandleGlobalHotKey, 1, &type, (__bridge void *)self, &_hotKeyHandler);
}

- (BOOL)registerHotKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
    if (_hotKey && keyCode == _hotKeyCode && modifiers == _hotKeyModifiers) return YES;

    EventHotKeyRef newHotKey = nullptr;
    EventHotKeyID identifier{ kHotKeySignature, kHotKeyID };
    const OSStatus status = RegisterEventHotKey(keyCode, modifiers, identifier,
                                                GetApplicationEventTarget(), 0, &newHotKey);
    if (status != noErr) return NO;
    if (_hotKey) UnregisterEventHotKey(_hotKey);
    _hotKey = newHotKey;
    return YES;
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    [self updateUI];
}

- (void)toggleClicking:(id)sender {
    (void)sender;
    if (_engine.isRunning()) {
        _engine.stop();
        [self updateUI];
        return;
    }

    if (!CGPreflightPostEventAccess()) {
        const bool granted = CGRequestPostEventAccess();
        if (!granted) {
            [self updateUI];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Accessibility permission is required";
            alert.informativeText = @"TurboClick needs permission to send mouse clicks to other apps. Enable TurboClick in Privacy & Security → Accessibility, then try again.";
            [alert addButtonWithTitle:@"Open Settings"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] == NSAlertFirstButtonReturn) [self openAccessibilitySettings:nil];
            return;
        }
    }

    _engine.start();
    [self updateUI];
}

- (void)selectSpeed:(NSMenuItem *)sender {
    [self applySpeed:sender.tag];
}

- (void)applySpeed:(double)cps {
    _cps = NormalizeCPS(cps);
    _engine.setClicksPerSecond(_cps);
    [NSUserDefaults.standardUserDefaults setDouble:_cps forKey:kCPSPreference];
    if (_speedField) _speedField.doubleValue = _cps;
    if (_speedStepper) _speedStepper.doubleValue = _cps;
    [self updateUI];
}

- (void)selectMouseButton:(NSMenuItem *)sender {
    [self applyMouseButton:(int)sender.tag];
}

- (void)applyMouseButton:(int)button {
    _mouseButton = std::clamp(button, 0, 2);
    _engine.setMouseButton(_mouseButton);
    [NSUserDefaults.standardUserDefaults setInteger:_mouseButton forKey:kMouseButtonPreference];
    if (_mousePopup) [_mousePopup selectItemAtIndex:_mouseButton];
    [self updateUI];
}

- (void)updateUI {
    const BOOL running = _engine.isRunning();
    NSString *speed = _cps >= kMaximumCPS ? @"Maximum · 5,000 CPS" :
        [NSString stringWithFormat:@"%.0f CPS", _cps];
    _statusMenuItem.title = running ? [NSString stringWithFormat:@"● Clicking · %@", speed] :
                                          [NSString stringWithFormat:@"○ Idle · %@", speed];
    _toggleMenuItem.title = [NSString stringWithFormat:@"%@ Clicking (%@)",
        running ? @"Stop" : @"Start", ShortcutDisplay(_hotKeyCode, _hotKeyModifiers)];
    _speedMenuItem.title = [NSString stringWithFormat:@"Speed: %@", speed];

    for (NSMenuItem *item in _speedMenu.itemArray) {
        item.state = item.tag > 0 && std::fabs(_cps - item.tag) < 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in _mouseMenu.itemArray) {
        item.state = item.tag == _mouseButton ? NSControlStateValueOn : NSControlStateValueOff;
    }

    NSString *symbol = running ? @"bolt.circle.fill" : @"cursorarrow.click.2";
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"TurboClick"];
    if (!image) image = [NSImage imageWithSystemSymbolName:@"cursorarrow.click" accessibilityDescription:@"TurboClick"];
    [image setTemplate:YES];
    _statusItem.button.image = image;
    _statusItem.button.title = image ? @"" : (running ? @"●" : @"TC");

    if (_recorderButton && !_recorderButton.recording) {
        _recorderButton.title = ShortcutDisplay(_hotKeyCode, _hotKeyModifiers);
    }
    if (_permissionLabel) {
        _permissionLabel.stringValue = CGPreflightPostEventAccess() ?
            @"Accessibility permission granted" : @"Accessibility permission not granted";
        _permissionLabel.textColor = CGPreflightPostEventAccess() ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
    }
}

- (void)showPreferences:(id)sender {
    (void)sender;
    if (!_preferencesWindow) [self buildPreferencesWindow];
    _speedField.doubleValue = _cps;
    _speedStepper.doubleValue = _cps;
    [_mousePopup selectItemAtIndex:_mouseButton];
    _recorderButton.title = ShortcutDisplay(_hotKeyCode, _hotKeyModifiers);
    [self updateUI];
    [NSApp activateIgnoringOtherApps:YES];
    [_preferencesWindow center];
    [_preferencesWindow makeKeyAndOrderFront:nil];
}

- (void)buildPreferencesWindow {
    _preferencesWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 460, 285)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _preferencesWindow.title = @"TurboClick Preferences";
    _preferencesWindow.releasedWhenClosed = NO;
    _preferencesWindow.delegate = self;

    NSTextField *intro = Label(@"Fast, native clicking at the current pointer location.");
    intro.font = [NSFont systemFontOfSize:13];

    NSTextField *shortcutLabel = Label(@"Start / stop shortcut:");
    _recorderButton = [HotKeyRecorderButton buttonWithTitle:ShortcutDisplay(_hotKeyCode, _hotKeyModifiers)
                                                    target:self
                                                    action:@selector(beginShortcutRecording:)];
    _recorderButton.translatesAutoresizingMaskIntoConstraints = NO;
    _recorderButton.recorderDelegate = self;
    [_recorderButton.widthAnchor constraintGreaterThanOrEqualToConstant:175].active = YES;

    NSTextField *speedLabel = Label(@"Clicks per second:");
    _speedField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _speedField.translatesAutoresizingMaskIntoConstraints = NO;
    _speedField.alignment = NSTextAlignmentRight;
    _speedField.delegate = self;
    _speedField.target = self;
    _speedField.action = @selector(speedFieldChanged:);
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.allowsFloats = NO;
    formatter.minimum = @(kMinimumCPS);
    formatter.maximum = @(kMaximumCPS);
    _speedField.formatter = formatter;
    [_speedField.widthAnchor constraintEqualToConstant:92].active = YES;

    _speedStepper = [NSStepper new];
    _speedStepper.translatesAutoresizingMaskIntoConstraints = NO;
    _speedStepper.minValue = kMinimumCPS;
    _speedStepper.maxValue = kMaximumCPS;
    _speedStepper.increment = 1;
    _speedStepper.target = self;
    _speedStepper.action = @selector(speedStepperChanged:);
    NSStackView *speedControls = [NSStackView stackViewWithViews:@[_speedField, _speedStepper]];
    speedControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    speedControls.spacing = 6;

    NSTextField *mouseLabel = Label(@"Mouse button:");
    _mousePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _mousePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_mousePopup addItemsWithTitles:@[@"Left", @"Right", @"Middle"]];
    _mousePopup.target = self;
    _mousePopup.action = @selector(mousePopupChanged:);
    [_mousePopup.widthAnchor constraintGreaterThanOrEqualToConstant:175].active = YES;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[shortcutLabel, _recorderButton],
        @[speedLabel, speedControls],
        @[mouseLabel, _mousePopup],
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 12;
    grid.columnSpacing = 16;
    grid.xPlacement = NSGridCellPlacementLeading;
    grid.yPlacement = NSGridCellPlacementCenter;

    NSTextField *speedHint = Label(@"1–5,000 CPS. Changes apply immediately while clicking.");
    speedHint.font = [NSFont systemFontOfSize:11];
    speedHint.textColor = NSColor.secondaryLabelColor;

    _permissionLabel = Label(@"");
    _permissionLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    NSButton *settingsButton = [NSButton buttonWithTitle:@"Open Accessibility Settings"
                                                  target:self
                                                  action:@selector(openAccessibilitySettings:)];
    NSStackView *permissionRow = [NSStackView stackViewWithViews:@[_permissionLabel, settingsButton]];
    permissionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    permissionRow.distribution = NSStackViewDistributionFillProportionally;
    permissionRow.spacing = 10;

    NSButton *doneButton = [NSButton buttonWithTitle:@"Done" target:self action:@selector(closePreferences:)];
    doneButton.keyEquivalent = @"\r";
    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[[NSView new], doneButton]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.distribution = NSStackViewDistributionFill;

    NSStackView *root = [NSStackView stackViewWithViews:@[
        intro, grid, speedHint, permissionRow, buttonRow,
    ]];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 14;
    [_preferencesWindow.contentView addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:_preferencesWindow.contentView.leadingAnchor constant:24],
        [root.trailingAnchor constraintEqualToAnchor:_preferencesWindow.contentView.trailingAnchor constant:-24],
        [root.topAnchor constraintEqualToAnchor:_preferencesWindow.contentView.topAnchor constant:22],
        [permissionRow.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [buttonRow.widthAnchor constraintEqualToAnchor:root.widthAnchor],
    ]];
}

- (void)beginShortcutRecording:(id)sender {
    (void)sender;
    [_recorderButton beginRecording];
}

- (void)recorderDidCaptureKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers {
    if (keyCode == _hotKeyCode && modifiers == _hotKeyModifiers) {
        [_recorderButton finishRecording];
        [self updateUI];
        return;
    }

    if (![self registerHotKeyCode:keyCode modifiers:modifiers]) {
        NSBeep();
        _recorderButton.title = @"Shortcut unavailable — try another";
        return;
    }

    _hotKeyCode = keyCode;
    _hotKeyModifiers = modifiers;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:_hotKeyCode forKey:kHotKeyCodePreference];
    [defaults setInteger:_hotKeyModifiers forKey:kHotKeyModifiersPreference];
    [_recorderButton finishRecording];
    [_preferencesWindow makeFirstResponder:_speedField];
    [self updateUI];
}

- (void)recorderDidCancel {
    [_recorderButton finishRecording];
    [_preferencesWindow makeFirstResponder:_speedField];
    [self updateUI];
}

- (void)speedFieldChanged:(id)sender {
    (void)sender;
    [self applySpeed:_speedField.doubleValue];
}

- (void)speedStepperChanged:(NSStepper *)sender {
    [self applySpeed:sender.doubleValue];
}

- (void)mousePopupChanged:(NSPopUpButton *)sender {
    [self applyMouseButton:(int)sender.indexOfSelectedItem];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == _speedField) [self applySpeed:_speedField.doubleValue];
}

- (void)closePreferences:(id)sender {
    (void)sender;
    [self recorderDidCancel];
    [_preferencesWindow close];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == _preferencesWindow) [self recorderDidCancel];
}

- (void)openAccessibilitySettings:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)showAbout:(id)sender {
    (void)sender;
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        NSAboutPanelOptionApplicationName: @"TurboClick",
        NSAboutPanelOptionApplicationVersion: @"1.0.0",
        NSAboutPanelOptionVersion: @"Native Objective-C++ menu-bar autoclicker",
        NSAboutPanelOptionCredits: [[NSAttributedString alloc] initWithString:
            @"A lean Core Graphics click engine for macOS."],
    }];
    [NSApp activateIgnoringOtherApps:YES];
}

@end

int RunSelfTests() {
    @autoreleasepool {
        if (NormalizeCPS(-10) != 1 || NormalizeCPS(10000) != 5000 || NormalizeCPS(24.6) != 25) return 1;
        if (![ShortcutDisplay(kVK_ANSI_C, controlKey | optionKey) isEqualToString:@"⌃⌥C"]) return 2;
        if (![ShortcutDisplay(kVK_F6, 0) isEqualToString:@"F6"]) return 3;
        if (CarbonModifiersFromEvent(NSEventModifierFlagCommand | NSEventModifierFlagShift) !=
            (cmdKey | shiftKey)) return 4;
        NSLog(@"TurboClick self-test passed");
    }
    return 0;
}

int main(int argc, const char *argv[]) {
    if (argc > 1 && std::string(argv[1]) == "--self-test") return RunSelfTests();
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
