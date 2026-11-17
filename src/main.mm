// SPDX-License-Identifier: MIT
// Copyright (c) 2026 SYMBaiEX

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <mach/mach_time.h>
#include <limits>
#include <pthread.h>
#include <random>
#include <string>
#include <thread>
#include <sys/utsname.h>
#include <vector>

namespace {

constexpr double kDefaultCPS = 25.0;
constexpr double kMinimumCPS = 1.0;
constexpr double kMaximumCPS = 5000.0;
constexpr uint64_t kMaximumClickLimit = 10'000'000;
constexpr double kMaximumDurationSeconds = 86'400.0;
constexpr double kMaximumJitterPixels = 20.0;
constexpr double kDefaultStartDelaySeconds = 0.0;
constexpr double kMaximumStartDelaySeconds = 10.0;
constexpr UInt32 kDefaultKeyCode = kVK_ANSI_C;
constexpr UInt32 kDefaultModifiers = controlKey | optionKey;
constexpr OSType kHotKeySignature = 0x53594D43;  // "SYMC"
constexpr UInt32 kHotKeyID = 1;

NSString *const kCPSPreference = @"clicksPerSecond";
NSString *const kMouseButtonPreference = @"mouseButton";
NSString *const kHotKeyCodePreference = @"hotKeyCode";
NSString *const kHotKeyModifiersPreference = @"hotKeyModifiers";
NSString *const kLocationModePreference = @"locationMode";
NSString *const kFixedXPreference = @"fixedX";
NSString *const kFixedYPreference = @"fixedY";
NSString *const kFixedLocationCapturedPreference = @"fixedLocationCaptured";
NSString *const kLimitModePreference = @"limitMode";
NSString *const kClickLimitPreference = @"clickLimit";
NSString *const kDurationSecondsPreference = @"durationSeconds";
NSString *const kClickPatternPreference = @"clickPattern";
NSString *const kJitterPixelsPreference = @"jitterPixels";
NSString *const kStartDelayPreference = @"startDelaySeconds";

double NormalizeCPS(double value) {
    if (!std::isfinite(value)) {
        return kDefaultCPS;
    }
    return std::clamp(std::round(value), kMinimumCPS, kMaximumCPS);
}

uint64_t NormalizeClickLimit(double value) {
    if (!std::isfinite(value)) return 1;
    if (value <= 1.0) return 1;
    if (value >= static_cast<double>(kMaximumClickLimit)) return kMaximumClickLimit;
    return static_cast<uint64_t>(std::round(value));
}

double NormalizeDuration(double value) {
    if (!std::isfinite(value)) return 60.0;
    return std::clamp(std::round(value), 1.0, kMaximumDurationSeconds);
}

double NormalizeJitter(double value) {
    if (!std::isfinite(value)) return 0.0;
    return std::clamp(std::round(value), 0.0, kMaximumJitterPixels);
}

double NormalizeStartDelay(double value) {
    if (!std::isfinite(value)) return kDefaultStartDelaySeconds;
    return std::clamp(std::round(value), 0.0, kMaximumStartDelaySeconds);
}

constexpr double kDefaultAgentStartDelaySeconds = 1.0;
constexpr double kMaximumAgentCoordinate = 100'000.0;

struct AgentOptions {
    double cps = kDefaultCPS;
    double x = 0.0;
    double y = 0.0;
    double jitter = 0.0;
    double startDelay = kDefaultAgentStartDelaySeconds;
    uint64_t clicks = 0;
    double duration = 0.0;
    int button = 0;
    int pattern = 0;
    bool hasX = false;
    bool hasY = false;
    bool hasClicks = false;
    bool hasDuration = false;
    bool confirmed = false;
};

bool ParseAgentDouble(const std::string &text, double *value) {
    if (text.empty()) return false;
    char *end = nullptr;
    errno = 0;
    const double parsed = std::strtod(text.c_str(), &end);
    if (errno == ERANGE || end == text.c_str() || *end != '\0' || !std::isfinite(parsed)) {
        return false;
    }
    *value = parsed;
    return true;
}

bool ParseAgentUInt64(const std::string &text, uint64_t *value) {
    if (text.empty() || text.front() == '-') return false;
    char *end = nullptr;
    errno = 0;
    const unsigned long long parsed = std::strtoull(text.c_str(), &end, 10);
    if (errno == ERANGE || end == text.c_str() || *end != '\0') return false;
    *value = static_cast<uint64_t>(parsed);
    return true;
}

bool NextAgentValue(int argc, const char *argv[], int *index, std::string *value,
                    std::string *error) {
    if (*index + 1 >= argc) {
        *error = std::string("missing value for ") + argv[*index];
        return false;
    }
    *value = argv[++(*index)];
    return true;
}

bool ParseAgentOptions(int argc, const char *argv[], AgentOptions *options,
                       bool requireConfirmation, std::string *error) {
    for (int index = 2; index < argc; ++index) {
        const std::string argument = argv[index];
        std::string value;
        if (argument == "--confirm") {
            options->confirmed = true;
        } else if (argument == "--cps" || argument == "--x" || argument == "--y" ||
                   argument == "--jitter" || argument == "--delay" || argument == "--clicks" ||
                   argument == "--duration" || argument == "--button" || argument == "--pattern") {
            if (!NextAgentValue(argc, argv, &index, &value, error)) return false;
            if (argument == "--cps" && !ParseAgentDouble(value, &options->cps)) {
                *error = "--cps must be a finite number";
                return false;
            }
            if (argument == "--x" && !(options->hasX = ParseAgentDouble(value, &options->x))) {
                *error = "--x must be a finite number";
                return false;
            }
            if (argument == "--y" && !(options->hasY = ParseAgentDouble(value, &options->y))) {
                *error = "--y must be a finite number";
                return false;
            }
            if (argument == "--jitter" && !ParseAgentDouble(value, &options->jitter)) {
                *error = "--jitter must be a finite number";
                return false;
            }
            if (argument == "--delay" && !ParseAgentDouble(value, &options->startDelay)) {
                *error = "--delay must be a finite number";
                return false;
            }
            if (argument == "--clicks") {
                if (options->hasClicks || !ParseAgentUInt64(value, &options->clicks)) {
                    *error = "--clicks must be a positive integer and may appear once";
                    return false;
                }
                options->hasClicks = true;
            }
            if (argument == "--duration") {
                if (options->hasDuration || !ParseAgentDouble(value, &options->duration)) {
                    *error = "--duration must be a finite number and may appear once";
                    return false;
                }
                options->hasDuration = true;
            }
            if (argument == "--button") {
                if (value == "left") options->button = 0;
                else if (value == "right") options->button = 1;
                else if (value == "middle") options->button = 2;
                else {
                    *error = "--button must be left, right, or middle";
                    return false;
                }
            }
            if (argument == "--pattern") {
                if (value == "single") options->pattern = 0;
                else if (value == "double") options->pattern = 1;
                else {
                    *error = "--pattern must be single or double";
                    return false;
                }
            }
        } else {
            *error = "unknown agent option: " + argument;
            return false;
        }
    }

    if (!options->hasX || !options->hasY) {
        *error = "--x and --y are required; agent runs always use a fixed target";
        return false;
    }
    if (!options->hasClicks && !options->hasDuration) {
        *error = "provide exactly one finite bound: --clicks or --duration";
        return false;
    }
    if (options->hasClicks && options->hasDuration) {
        *error = "provide exactly one finite bound: --clicks or --duration, not both";
        return false;
    }
    if (requireConfirmation && !options->confirmed) {
        *error = "--confirm is required for a real click run; use --agent-validate for a dry run";
        return false;
    }
    if (options->cps < kMinimumCPS || options->cps > kMaximumCPS ||
        options->jitter < 0.0 || options->jitter > kMaximumJitterPixels ||
        options->startDelay < 0.0 || options->startDelay > kMaximumStartDelaySeconds ||
        options->x < -kMaximumAgentCoordinate || options->x > kMaximumAgentCoordinate ||
        options->y < -kMaximumAgentCoordinate || options->y > kMaximumAgentCoordinate) {
        *error = "agent values are outside the documented safety bounds";
        return false;
    }
    if (options->hasClicks && (options->clicks < 1 || options->clicks > kMaximumClickLimit)) {
        *error = "--clicks must be between 1 and 10000000";
        return false;
    }
    if (options->hasDuration && (options->duration < 1.0 || options->duration > kMaximumDurationSeconds)) {
        *error = "--duration must be between 1 and 86400 seconds";
        return false;
    }
    options->cps = NormalizeCPS(options->cps);
    options->jitter = NormalizeJitter(options->jitter);
    options->startDelay = NormalizeStartDelay(options->startDelay);
    return true;
}

std::string EscapeJson(const std::string &value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (const char character : value) {
        switch (character) {
            case '\\': escaped += "\\\\"; break;
            case '"': escaped += "\\\""; break;
            case '\n': escaped += "\\n"; break;
            case '\r': escaped += "\\r"; break;
            case '\t': escaped += "\\t"; break;
            default: escaped += character; break;
        }
    }
    return escaped;
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
    void setLocationMode(int mode) { locationMode_.store(std::clamp(mode, 0, 1)); }
    void setFixedLocation(CGPoint location) {
        fixedX_.store(location.x);
        fixedY_.store(location.y);
    }
    void setLimitMode(int mode) { limitMode_.store(std::clamp(mode, 0, 2)); }
    void setClickLimit(uint64_t limit) { clickLimit_.store(std::clamp<uint64_t>(limit, 1, kMaximumClickLimit)); }
    void setDurationSeconds(double seconds) { durationSeconds_.store(NormalizeDuration(seconds)); }
    void setClickPattern(int pattern) { clickPattern_.store(std::clamp(pattern, 0, 1)); }
    void setJitterPixels(double pixels) { jitterPixels_.store(NormalizeJitter(pixels)); }
    void setStartDelaySeconds(double seconds) { startDelaySeconds_.store(NormalizeStartDelay(seconds)); }
    bool isRunning() const { return running_.load(); }
    bool isArming() const { return arming_.load(); }
    uint64_t clickCount() const { return clickCount_.load(); }

    void start() {
        bool expected = false;
        if (!running_.compare_exchange_strong(expected, true)) return;
        if (worker_.joinable()) worker_.join();
        clickCount_.store(0);
        arming_.store(true);
        worker_ = std::thread([this] { run(); });
    }

    void stop() {
        running_.store(false);
        arming_.store(false);
        if (worker_.joinable()) worker_.join();
    }

private:
    static uint64_t ticksForNanoseconds(double nanoseconds, const mach_timebase_info_data_t &timebase) {
        return static_cast<uint64_t>(nanoseconds * static_cast<double>(timebase.denom) /
                                     static_cast<double>(timebase.numer));
    }

    CGPoint clickLocation() const {
        if (locationMode_.load() == 1) {
            return CGPointMake(fixedX_.load(), fixedY_.load());
        }
        CGEventRef locationEvent = CGEventCreate(nullptr);
        if (!locationEvent) return CGPointZero;
        CGPoint location = CGEventGetLocation(locationEvent);
        CFRelease(locationEvent);
        return location;
    }

    void postClick(CGEventSourceRef source, CGPoint location, int clickState) const {
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
            CGEventSetIntegerValueField(down, kCGMouseEventClickState, clickState);
            CGEventSetIntegerValueField(up, kCGMouseEventClickState, clickState);
            CGEventPost(kCGHIDEventTap, down);
            CGEventPost(kCGHIDEventTap, up);
        }
        if (down) CFRelease(down);
        if (up) CFRelease(up);
    }

    void postLogicalClick(CGEventSourceRef source, std::mt19937 &random) const {
        CGPoint location = clickLocation();
        const double jitter = jitterPixels_.load();
        if (jitter > 0.0) {
            std::uniform_real_distribution<double> distribution(-jitter, jitter);
            location.x += distribution(random);
            location.y += distribution(random);
        }
        postClick(source, location, 1);
        if (clickPattern_.load() == 1) {
            postClick(source, location, 2);
        }
    }

    void run() {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
        if (!source) {
            running_.store(false);
            arming_.store(false);
            return;
        }
        CGEventSourceSetLocalEventsSuppressionInterval(source, 0.0);

        mach_timebase_info_data_t timebase{};
        mach_timebase_info(&timebase);
        uint64_t nextDeadline = mach_absolute_time();
        const uint64_t maximumStopLatency = ticksForNanoseconds(5'000'000.0, timebase);
        std::mt19937 random(std::random_device{}());
        uint64_t completedClicks = 0;

        const uint64_t armingDeadline = nextDeadline + ticksForNanoseconds(
            startDelaySeconds_.load() * 1'000'000'000.0, timebase);
        while (running_.load() && nextDeadline < armingDeadline) {
            mach_wait_until(std::min(armingDeadline, nextDeadline + maximumStopLatency));
            nextDeadline = mach_absolute_time();
        }
        arming_.store(false);
        if (!running_.load()) {
            CFRelease(source);
            return;
        }

        nextDeadline = mach_absolute_time();
        const uint64_t runStarted = nextDeadline;

        while (running_.load()) {
            const int limitMode = limitMode_.load();
            if (limitMode == 1 && completedClicks >= clickLimit_.load()) break;
            if (limitMode == 2) {
                const uint64_t durationTicks = ticksForNanoseconds(
                    durationSeconds_.load() * 1'000'000'000.0, timebase);
                if (mach_absolute_time() >= runStarted + durationTicks) break;
            }

            postLogicalClick(source, random);
            ++completedClicks;
            clickCount_.store(completedClicks);

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
        running_.store(false);
    }

    std::atomic<bool> running_{false};
    std::atomic<double> cps_{kDefaultCPS};
    std::atomic<int> mouseButton_{0};
    std::atomic<int> locationMode_{0};
    std::atomic<double> fixedX_{0.0};
    std::atomic<double> fixedY_{0.0};
    std::atomic<int> limitMode_{0};
    std::atomic<uint64_t> clickLimit_{1'000};
    std::atomic<double> durationSeconds_{60.0};
    std::atomic<int> clickPattern_{0};
    std::atomic<double> jitterPixels_{0.0};
    std::atomic<double> startDelaySeconds_{kDefaultStartDelaySeconds};
    std::atomic<bool> arming_{false};
    std::atomic<uint64_t> clickCount_{0};
    std::thread worker_;
};

NSTextField *Label(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

CGPoint CurrentPointerLocation() {
    CGEventRef event = CGEventCreate(nullptr);
    if (!event) return CGPointZero;
    CGPoint location = CGEventGetLocation(event);
    CFRelease(event);
    return location;
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
    int _locationMode;
    CGPoint _fixedLocation;
    bool _hasFixedLocation;
    int _limitMode;
    uint64_t _clickLimit;
    double _durationSeconds;
    int _clickPattern;
    double _jitterPixels;
    double _startDelaySeconds;

    NSStatusItem *_statusItem;
    NSMenu *_menu;
    NSMenuItem *_statusMenuItem;
    NSMenuItem *_toggleMenuItem;
    NSMenuItem *_speedMenuItem;
    NSMenu *_speedMenu;
    NSMenu *_mouseMenu;
    NSMenu *_patternMenu;
    NSMenu *_locationMenu;
    NSMenu *_limitMenu;

    NSWindow *_preferencesWindow;
    HotKeyRecorderButton *_recorderButton;
    NSTextField *_speedField;
    NSStepper *_speedStepper;
    NSPopUpButton *_mousePopup;
    NSPopUpButton *_patternPopup;
    NSPopUpButton *_locationPopup;
    NSPopUpButton *_limitPopup;
    NSButton *_captureButton;
    NSTextField *_limitField;
    NSStepper *_limitStepper;
    NSTextField *_limitUnitLabel;
    NSStepper *_jitterStepper;
    NSTextField *_jitterValueLabel;
    NSStepper *_startDelayStepper;
    NSTextField *_startDelayValueLabel;
    NSTextField *_fixedLocationLabel;
    NSTextField *_permissionLabel;
    NSTimer *_statusTimer;
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
        kLocationModePreference: @0,
        kFixedXPreference: @0.0,
        kFixedYPreference: @0.0,
        kFixedLocationCapturedPreference: @NO,
        kLimitModePreference: @0,
        kClickLimitPreference: @1'000,
        kDurationSecondsPreference: @60.0,
        kClickPatternPreference: @0,
        kJitterPixelsPreference: @0.0,
        kStartDelayPreference: @(kDefaultStartDelaySeconds),
    }];

    _cps = NormalizeCPS([defaults doubleForKey:kCPSPreference]);
    _mouseButton = std::clamp((int)[defaults integerForKey:kMouseButtonPreference], 0, 2);
    _hotKeyCode = (UInt32)[defaults integerForKey:kHotKeyCodePreference];
    _hotKeyModifiers = (UInt32)[defaults integerForKey:kHotKeyModifiersPreference];
    _locationMode = std::clamp((int)[defaults integerForKey:kLocationModePreference], 0, 1);
    _fixedLocation = CGPointMake([defaults doubleForKey:kFixedXPreference],
                                 [defaults doubleForKey:kFixedYPreference]);
    _hasFixedLocation = [defaults boolForKey:kFixedLocationCapturedPreference] ||
        _fixedLocation.x != 0.0 || _fixedLocation.y != 0.0;
    _limitMode = std::clamp((int)[defaults integerForKey:kLimitModePreference], 0, 2);
    _clickLimit = NormalizeClickLimit([defaults doubleForKey:kClickLimitPreference]);
    _durationSeconds = NormalizeDuration([defaults doubleForKey:kDurationSecondsPreference]);
    _clickPattern = std::clamp((int)[defaults integerForKey:kClickPatternPreference], 0, 1);
    _jitterPixels = NormalizeJitter([defaults doubleForKey:kJitterPixelsPreference]);
    _startDelaySeconds = NormalizeStartDelay([defaults doubleForKey:kStartDelayPreference]);
    _engine.setClicksPerSecond(_cps);
    _engine.setMouseButton(_mouseButton);
    _engine.setLocationMode(_locationMode);
    _engine.setFixedLocation(_fixedLocation);
    _engine.setLimitMode(_limitMode);
    _engine.setClickLimit(_clickLimit);
    _engine.setDurationSeconds(_durationSeconds);
    _engine.setClickPattern(_clickPattern);
    _engine.setJitterPixels(_jitterPixels);
    _engine.setStartDelaySeconds(_startDelaySeconds);

    [self buildMenu];
    [self installHotKeyHandler];
    if (![self registerHotKeyCode:_hotKeyCode modifiers:_hotKeyModifiers]) {
        _hotKeyCode = kDefaultKeyCode;
        _hotKeyModifiers = kDefaultModifiers;
        [self registerHotKeyCode:_hotKeyCode modifiers:_hotKeyModifiers];
    }
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                     target:self
                                                   selector:@selector(pollEngine:)
                                                   userInfo:nil
                                                    repeats:YES];
    [self updateUI];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    _engine.stop();
    if (_hotKey) UnregisterEventHotKey(_hotKey);
    if (_hotKeyHandler) RemoveEventHandler(_hotKeyHandler);
    [_statusTimer invalidate];
}

- (void)buildMenu {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _statusItem.button.toolTip = @"SymClick";

    _menu = [[NSMenu alloc] initWithTitle:@"SymClick"];
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

    NSMenuItem *patternMenuItem = [[NSMenuItem alloc] initWithTitle:@"Click Pattern" action:nil keyEquivalent:@""];
    _patternMenu = [[NSMenu alloc] initWithTitle:@"Click Pattern"];
    NSArray<NSString *> *patternNames = @[@"Single click", @"Double click"];
    for (NSInteger pattern = 0; pattern < 2; ++pattern) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:patternNames[pattern]
                                                       action:@selector(selectClickPattern:)
                                                keyEquivalent:@""];
        item.target = self;
        item.tag = pattern;
        [_patternMenu addItem:item];
    }
    patternMenuItem.submenu = _patternMenu;
    [_menu addItem:patternMenuItem];

    NSMenuItem *locationMenuItem = [[NSMenuItem alloc] initWithTitle:@"Click Location" action:nil keyEquivalent:@""];
    _locationMenu = [[NSMenu alloc] initWithTitle:@"Click Location"];
    NSArray<NSString *> *locationNames = @[@"Follow pointer", @"Fixed location"];
    for (NSInteger mode = 0; mode < 2; ++mode) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:locationNames[mode]
                                                       action:@selector(selectLocationMode:)
                                                keyEquivalent:@""];
        item.target = self;
        item.tag = mode;
        [_locationMenu addItem:item];
    }
    [_locationMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *captureLocation = [[NSMenuItem alloc] initWithTitle:@"Capture current pointer location"
                                                               action:@selector(captureCurrentLocation:)
                                                        keyEquivalent:@""];
    captureLocation.target = self;
    [_locationMenu addItem:captureLocation];
    locationMenuItem.submenu = _locationMenu;
    [_menu addItem:locationMenuItem];

    NSMenuItem *limitMenuItem = [[NSMenuItem alloc] initWithTitle:@"Run Mode" action:nil keyEquivalent:@""];
    _limitMenu = [[NSMenu alloc] initWithTitle:@"Run Mode"];
    NSArray<NSString *> *limitNames = @[@"Repeat until stopped", @"Stop after click count…", @"Stop after duration…"];
    for (NSInteger mode = 0; mode < 3; ++mode) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:limitNames[mode]
                                                       action:@selector(selectLimitMode:)
                                                keyEquivalent:@""];
        item.target = self;
        item.tag = mode;
        [_limitMenu addItem:item];
    }
    limitMenuItem.submenu = _limitMenu;
    [_menu addItem:limitMenuItem];
    [_menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *preferences = [[NSMenuItem alloc] initWithTitle:@"Preferences…" action:@selector(showPreferences:) keyEquivalent:@","];
    preferences.target = self;
    [_menu addItem:preferences];

    NSMenuItem *accessibility = [[NSMenuItem alloc] initWithTitle:@"Accessibility Settings…" action:@selector(openAccessibilitySettings:) keyEquivalent:@""];
    accessibility.target = self;
    [_menu addItem:accessibility];

    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About SymClick" action:@selector(showAbout:) keyEquivalent:@""];
    about.target = self;
    [_menu addItem:about];
    [_menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit SymClick" action:@selector(terminate:) keyEquivalent:@"q"];
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
            alert.informativeText = @"SymClick needs permission to send mouse clicks to other apps. Enable SymClick in Privacy & Security → Accessibility, then try again.";
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

- (void)selectClickPattern:(NSMenuItem *)sender {
    [self applyClickPattern:(int)sender.tag];
}

- (void)applyClickPattern:(int)pattern {
    _clickPattern = std::clamp(pattern, 0, 1);
    _engine.setClickPattern(_clickPattern);
    [NSUserDefaults.standardUserDefaults setInteger:_clickPattern forKey:kClickPatternPreference];
    if (_patternPopup) [_patternPopup selectItemAtIndex:_clickPattern];
    [self updateUI];
}

- (void)applyLocationMode:(int)mode {
    _locationMode = std::clamp(mode, 0, 1);
    _engine.setLocationMode(_locationMode);
    [NSUserDefaults.standardUserDefaults setInteger:_locationMode forKey:kLocationModePreference];
    if (_locationPopup) [_locationPopup selectItemAtIndex:_locationMode];
    [self refreshPreferencesControls];
    [self updateUI];
}

- (void)selectLocationMode:(NSMenuItem *)sender {
    [self applyLocationMode:(int)sender.tag];
    if (sender.tag == 1 && !_hasFixedLocation) {
        [self captureCurrentLocation:nil];
    }
}

- (void)captureCurrentLocation:(id)sender {
    (void)sender;
    _fixedLocation = CurrentPointerLocation();
    _engine.setFixedLocation(_fixedLocation);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:_fixedLocation.x forKey:kFixedXPreference];
    [defaults setDouble:_fixedLocation.y forKey:kFixedYPreference];
    [defaults setBool:YES forKey:kFixedLocationCapturedPreference];
    _hasFixedLocation = YES;
    [self refreshPreferencesControls];
    [self updateUI];
}

- (void)applyLimitMode:(int)mode {
    _limitMode = std::clamp(mode, 0, 2);
    _engine.setLimitMode(_limitMode);
    [NSUserDefaults.standardUserDefaults setInteger:_limitMode forKey:kLimitModePreference];
    [self refreshPreferencesControls];
    [self updateUI];
}

- (void)selectLimitMode:(NSMenuItem *)sender {
    [self applyLimitMode:(int)sender.tag];
    if (sender.tag != 0) [self showPreferences:nil];
}

- (void)applyClickLimit:(double)value {
    _clickLimit = NormalizeClickLimit(value);
    _engine.setClickLimit(_clickLimit);
    [NSUserDefaults.standardUserDefaults setDouble:(double)_clickLimit forKey:kClickLimitPreference];
    [self refreshPreferencesControls];
    [self updateUI];
}

- (void)applyDuration:(double)value {
    _durationSeconds = NormalizeDuration(value);
    _engine.setDurationSeconds(_durationSeconds);
    [NSUserDefaults.standardUserDefaults setDouble:_durationSeconds forKey:kDurationSecondsPreference];
    [self refreshPreferencesControls];
    [self updateUI];
}

- (void)applyJitter:(double)value {
    _jitterPixels = NormalizeJitter(value);
    _engine.setJitterPixels(_jitterPixels);
    [NSUserDefaults.standardUserDefaults setDouble:_jitterPixels forKey:kJitterPixelsPreference];
    [self refreshPreferencesControls];
    [self updateUI];
}

- (void)applyStartDelay:(double)value {
    _startDelaySeconds = NormalizeStartDelay(value);
    _engine.setStartDelaySeconds(_startDelaySeconds);
    [NSUserDefaults.standardUserDefaults setDouble:_startDelaySeconds forKey:kStartDelayPreference];
    [self refreshPreferencesControls];
    [self updateUI];
}

- (void)pollEngine:(NSTimer *)timer {
    (void)timer;
    [self updateUI];
}

- (void)updateUI {
    const BOOL running = _engine.isRunning();
    const BOOL arming = _engine.isArming();
    NSString *speed = _cps >= kMaximumCPS ? @"Maximum · 5,000 CPS" :
        [NSString stringWithFormat:@"%.0f CPS", _cps];
    NSString *count = [NSString stringWithFormat:@"%llu clicks", static_cast<unsigned long long>(_engine.clickCount())];
    NSString *runMode = _limitMode == 1 ? [NSString stringWithFormat:@" · %llu max", static_cast<unsigned long long>(_clickLimit)] :
        (_limitMode == 2 ? [NSString stringWithFormat:@" · %.0fs max", _durationSeconds] : @"");
    _statusMenuItem.title = arming ? [NSString stringWithFormat:@"◐ Starting · %.0fs delay · %@", _startDelaySeconds, ShortcutDisplay(_hotKeyCode, _hotKeyModifiers)] :
        (running ? [NSString stringWithFormat:@"● Clicking · %@ · %@%@", speed, count, runMode] :
                   [NSString stringWithFormat:@"○ Idle · %@ · %@%@", speed, count, runMode]);
    _toggleMenuItem.title = [NSString stringWithFormat:@"%@ Clicking (%@)",
        arming ? @"Cancel" : (running ? @"Stop" : @"Start"), ShortcutDisplay(_hotKeyCode, _hotKeyModifiers)];
    _speedMenuItem.title = [NSString stringWithFormat:@"Speed: %@", speed];

    for (NSMenuItem *item in _speedMenu.itemArray) {
        item.state = item.tag > 0 && std::fabs(_cps - item.tag) < 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in _mouseMenu.itemArray) {
        item.state = item.tag == _mouseButton ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in _patternMenu.itemArray) {
        item.state = item.tag == _clickPattern ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in _locationMenu.itemArray) {
        item.state = item.tag < 2 && item.tag == _locationMode ? NSControlStateValueOn : NSControlStateValueOff;
    }
    for (NSMenuItem *item in _limitMenu.itemArray) {
        item.state = item.tag <= 2 && item.tag == _limitMode ? NSControlStateValueOn : NSControlStateValueOff;
    }

    NSString *symbol = running ? @"bolt.circle.fill" : @"cursorarrow.click.2";
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"SymClick"];
    if (!image) image = [NSImage imageWithSystemSymbolName:@"cursorarrow.click" accessibilityDescription:@"SymClick"];
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

- (void)refreshPreferencesControls {
    if (!_preferencesWindow) return;
    [_patternPopup selectItemAtIndex:_clickPattern];
    [_locationPopup selectItemAtIndex:_locationMode];
    [_limitPopup selectItemAtIndex:_limitMode];
    _captureButton.enabled = YES;

    const double limitMaximum = _limitMode == 1 ? static_cast<double>(kMaximumClickLimit) : kMaximumDurationSeconds;
    _limitStepper.maxValue = limitMaximum;
    if (NSNumberFormatter *formatter = (NSNumberFormatter *)_limitField.formatter) {
        formatter.maximum = @(limitMaximum);
    }
    if (_limitMode == 1) {
        _limitField.doubleValue = (double)_clickLimit;
        _limitStepper.doubleValue = (double)_clickLimit;
        _limitUnitLabel.stringValue = @"clicks";
        _limitField.enabled = YES;
        _limitStepper.enabled = YES;
    } else if (_limitMode == 2) {
        _limitField.doubleValue = _durationSeconds;
        _limitStepper.doubleValue = _durationSeconds;
        _limitUnitLabel.stringValue = @"seconds";
        _limitField.enabled = YES;
        _limitStepper.enabled = YES;
    } else {
        _limitField.stringValue = @"—";
        _limitStepper.doubleValue = 1;
        _limitUnitLabel.stringValue = @"off";
        _limitField.enabled = NO;
        _limitStepper.enabled = NO;
    }
    _jitterStepper.doubleValue = _jitterPixels;
    _jitterValueLabel.stringValue = [NSString stringWithFormat:@"%.0f px", _jitterPixels];
    _startDelayStepper.doubleValue = _startDelaySeconds;
    _startDelayValueLabel.stringValue = _startDelaySeconds == 0.0 ? @"instant" :
        [NSString stringWithFormat:@"%.0f sec", _startDelaySeconds];
    _fixedLocationLabel.stringValue = _hasFixedLocation ?
        [NSString stringWithFormat:@"Fixed: (%.0f, %.0f)", _fixedLocation.x, _fixedLocation.y] :
        @"Fixed: (not captured)";
}

- (void)showPreferences:(id)sender {
    (void)sender;
    if (!_preferencesWindow) [self buildPreferencesWindow];
    _speedField.doubleValue = _cps;
    _speedStepper.doubleValue = _cps;
    [_mousePopup selectItemAtIndex:_mouseButton];
    _recorderButton.title = ShortcutDisplay(_hotKeyCode, _hotKeyModifiers);
    [self refreshPreferencesControls];
    [self updateUI];
    [NSApp activateIgnoringOtherApps:YES];
    [_preferencesWindow center];
    [_preferencesWindow makeKeyAndOrderFront:nil];
}

- (void)buildPreferencesWindow {
    _preferencesWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 560, 550)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _preferencesWindow.title = @"SymClick Preferences";
    _preferencesWindow.releasedWhenClosed = NO;
    _preferencesWindow.delegate = self;

    NSTextField *intro = Label(@"Fast, native clicking with predictable limits and target control.");
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

    NSTextField *patternLabel = Label(@"Click pattern:");
    _patternPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _patternPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_patternPopup addItemsWithTitles:@[@"Single click", @"Double click"]];
    _patternPopup.target = self;
    _patternPopup.action = @selector(patternPopupChanged:);
    [_patternPopup.widthAnchor constraintGreaterThanOrEqualToConstant:175].active = YES;

    NSTextField *locationLabel = Label(@"Click location:");
    _locationPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _locationPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_locationPopup addItemsWithTitles:@[@"Follow pointer", @"Fixed location"]];
    _locationPopup.target = self;
    _locationPopup.action = @selector(locationPopupChanged:);
    [_locationPopup.widthAnchor constraintGreaterThanOrEqualToConstant:175].active = YES;
    _captureButton = [NSButton buttonWithTitle:@"Capture pointer" target:self action:@selector(captureCurrentLocation:)];
    _captureButton.translatesAutoresizingMaskIntoConstraints = NO;
    _fixedLocationLabel = Label(@"Fixed: (not captured)");
    _fixedLocationLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _fixedLocationLabel.textColor = NSColor.secondaryLabelColor;
    NSStackView *locationControls = [NSStackView stackViewWithViews:@[_locationPopup, _captureButton, _fixedLocationLabel]];
    locationControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    locationControls.spacing = 8;

    NSTextField *runModeLabel = Label(@"Run mode:");
    _limitPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _limitPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_limitPopup addItemsWithTitles:@[@"Repeat until stopped", @"Stop after click count", @"Stop after duration"]];
    _limitPopup.target = self;
    _limitPopup.action = @selector(limitPopupChanged:);
    [_limitPopup.widthAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;

    NSTextField *limitLabel = Label(@"Stop after:");
    _limitField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _limitField.translatesAutoresizingMaskIntoConstraints = NO;
    _limitField.alignment = NSTextAlignmentRight;
    _limitField.delegate = self;
    _limitField.target = self;
    _limitField.action = @selector(limitFieldChanged:);
    NSNumberFormatter *limitFormatter = [[NSNumberFormatter alloc] init];
    limitFormatter.allowsFloats = NO;
    limitFormatter.minimum = @1;
    limitFormatter.maximum = @(kMaximumClickLimit);
    _limitField.formatter = limitFormatter;
    [_limitField.widthAnchor constraintEqualToConstant:110].active = YES;
    _limitStepper = [NSStepper new];
    _limitStepper.translatesAutoresizingMaskIntoConstraints = NO;
    _limitStepper.minValue = 1;
    _limitStepper.maxValue = kMaximumClickLimit;
    _limitStepper.increment = 1;
    _limitStepper.target = self;
    _limitStepper.action = @selector(limitStepperChanged:);
    _limitUnitLabel = Label(@"clicks");
    _limitUnitLabel.textColor = NSColor.secondaryLabelColor;
    NSStackView *limitControls = [NSStackView stackViewWithViews:@[_limitField, _limitStepper, _limitUnitLabel]];
    limitControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    limitControls.spacing = 6;

    NSTextField *jitterLabel = Label(@"Pointer jitter:");
    _jitterStepper = [NSStepper new];
    _jitterStepper.translatesAutoresizingMaskIntoConstraints = NO;
    _jitterStepper.minValue = 0;
    _jitterStepper.maxValue = kMaximumJitterPixels;
    _jitterStepper.increment = 1;
    _jitterStepper.target = self;
    _jitterStepper.action = @selector(jitterStepperChanged:);
    _jitterValueLabel = Label(@"0 px");
    _jitterValueLabel.textColor = NSColor.secondaryLabelColor;
    NSStackView *jitterControls = [NSStackView stackViewWithViews:@[_jitterStepper, _jitterValueLabel]];
    jitterControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    jitterControls.spacing = 8;

    NSTextField *startDelayLabel = Label(@"Start delay:");
    _startDelayStepper = [NSStepper new];
    _startDelayStepper.translatesAutoresizingMaskIntoConstraints = NO;
    _startDelayStepper.minValue = 0;
    _startDelayStepper.maxValue = kMaximumStartDelaySeconds;
    _startDelayStepper.increment = 1;
    _startDelayStepper.target = self;
    _startDelayStepper.action = @selector(startDelayStepperChanged:);
    _startDelayValueLabel = Label(@"instant");
    _startDelayValueLabel.textColor = NSColor.secondaryLabelColor;
    NSStackView *startDelayControls = [NSStackView stackViewWithViews:@[_startDelayStepper, _startDelayValueLabel]];
    startDelayControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    startDelayControls.spacing = 8;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[shortcutLabel, _recorderButton],
        @[speedLabel, speedControls],
        @[mouseLabel, _mousePopup],
        @[patternLabel, _patternPopup],
        @[locationLabel, locationControls],
        @[runModeLabel, _limitPopup],
        @[limitLabel, limitControls],
        @[jitterLabel, jitterControls],
        @[startDelayLabel, startDelayControls],
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 12;
    grid.columnSpacing = 16;
    grid.xPlacement = NSGridCellPlacementLeading;
    grid.yPlacement = NSGridCellPlacementCenter;

    NSTextField *speedHint = Label(@"1–5,000 CPS. Changes apply immediately. Start delay gives you time to move to the target; limits stop cleanly.");
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

    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset Defaults" target:self action:@selector(resetPreferences:)];
    NSButton *doneButton = [NSButton buttonWithTitle:@"Done" target:self action:@selector(closePreferences:)];
    doneButton.keyEquivalent = @"\r";
    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[resetButton, [NSView new], doneButton]];
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
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:_preferencesWindow.contentView.bottomAnchor constant:-22],
        [permissionRow.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [buttonRow.widthAnchor constraintEqualToAnchor:root.widthAnchor],
    ]];
    [self refreshPreferencesControls];
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

- (void)patternPopupChanged:(NSPopUpButton *)sender {
    _clickPattern = std::clamp((int)sender.indexOfSelectedItem, 0, 1);
    _engine.setClickPattern(_clickPattern);
    [NSUserDefaults.standardUserDefaults setInteger:_clickPattern forKey:kClickPatternPreference];
    [self updateUI];
}

- (void)locationPopupChanged:(NSPopUpButton *)sender {
    [self applyLocationMode:(int)sender.indexOfSelectedItem];
    if (_locationMode == 1 && !_hasFixedLocation) {
        [self captureCurrentLocation:nil];
    }
}

- (void)limitPopupChanged:(NSPopUpButton *)sender {
    [self applyLimitMode:(int)sender.indexOfSelectedItem];
}

- (void)limitFieldChanged:(id)sender {
    (void)sender;
    if (_limitMode == 1) [self applyClickLimit:_limitField.doubleValue];
    if (_limitMode == 2) [self applyDuration:_limitField.doubleValue];
}

- (void)limitStepperChanged:(NSStepper *)sender {
    if (_limitMode == 1) [self applyClickLimit:sender.doubleValue];
    if (_limitMode == 2) [self applyDuration:sender.doubleValue];
}

- (void)jitterStepperChanged:(NSStepper *)sender {
    [self applyJitter:sender.doubleValue];
}

- (void)startDelayStepperChanged:(NSStepper *)sender {
    [self applyStartDelay:sender.doubleValue];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == _speedField) [self applySpeed:_speedField.doubleValue];
    if (notification.object == _limitField) [self limitFieldChanged:_limitField];
}

- (void)resetPreferences:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Reset SymClick preferences?";
    alert.informativeText = @"This restores the default shortcut and all click settings.";
    [alert addButtonWithTitle:@"Reset Defaults"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [self applySpeed:kDefaultCPS];
    [self applyMouseButton:0];
    [self applyLocationMode:0];
    [self applyLimitMode:0];
    [self applyClickLimit:1'000];
    [self applyDuration:60.0];
    [self applyClickPattern:0];
    [self applyJitter:0.0];
    [self applyStartDelay:kDefaultStartDelaySeconds];
    _fixedLocation = CGPointZero;
    _hasFixedLocation = false;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:0.0 forKey:kFixedXPreference];
    [defaults setDouble:0.0 forKey:kFixedYPreference];
    [defaults setBool:NO forKey:kFixedLocationCapturedPreference];

    if ([self registerHotKeyCode:kDefaultKeyCode modifiers:kDefaultModifiers]) {
        _hotKeyCode = kDefaultKeyCode;
        _hotKeyModifiers = kDefaultModifiers;
        [defaults setInteger:_hotKeyCode forKey:kHotKeyCodePreference];
        [defaults setInteger:_hotKeyModifiers forKey:kHotKeyModifiersPreference];
    }
    [self refreshPreferencesControls];
    [self updateUI];
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
    id bundledVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *version = [bundledVersion isKindOfClass:NSString.class] ? bundledVersion : @"development";
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        NSAboutPanelOptionApplicationName: @"SymClick",
        NSAboutPanelOptionApplicationVersion: version,
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
        if (NormalizeClickLimit(-1) != 1 || NormalizeClickLimit(10'000'001) != 10'000'000 ||
            NormalizeClickLimit(24.6) != 25) return 2;
        if (NormalizeDuration(0) != 1 || NormalizeDuration(100'000) != 86'400 || NormalizeDuration(24.6) != 25) return 3;
        if (NormalizeJitter(-1) != 0 || NormalizeJitter(100) != 20 || NormalizeJitter(4.6) != 5) return 4;
        if (NormalizeStartDelay(-1) != 0 || NormalizeStartDelay(100) != 10 || NormalizeStartDelay(2.6) != 3) return 5;
        if (![ShortcutDisplay(kVK_ANSI_C, controlKey | optionKey) isEqualToString:@"⌃⌥C"]) return 6;
        if (![ShortcutDisplay(kVK_F6, 0) isEqualToString:@"F6"]) return 7;
        if (CarbonModifiersFromEvent(NSEventModifierFlagCommand | NSEventModifierFlagShift) !=
            (cmdKey | shiftKey)) return 8;
        {
            const char *arguments[] = {"SymClick", "--agent-validate", "--x", "100", "--y", "200",
                                       "--clicks", "3", "--cps", "100"};
            AgentOptions options;
            std::string error;
            if (!ParseAgentOptions(static_cast<int>(std::size(arguments)), arguments, &options, false, &error)) return 9;
            if (!options.hasX || !options.hasY || !options.hasClicks || options.clicks != 3 || options.cps != 100) return 10;
        }
        {
            const char *arguments[] = {"SymClick", "--agent-run", "--x", "100", "--y", "200",
                                       "--clicks", "3"};
            AgentOptions options;
            std::string error;
            if (ParseAgentOptions(static_cast<int>(std::size(arguments)), arguments, &options, true, &error)) return 11;
        }
        {
            const char *arguments[] = {"SymClick", "--agent-run", "--x", "100", "--y", "200",
                                       "--clicks", "3", "--duration", "5", "--confirm"};
            AgentOptions options;
            std::string error;
            if (ParseAgentOptions(static_cast<int>(std::size(arguments)), arguments, &options, true, &error)) return 12;
        }
        NSLog(@"SymClick self-test passed");
    }
    return 0;
}

int RunDiagnostics() {
    @autoreleasepool {
        struct utsname systemInfo{};
        uname(&systemInfo);
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (![version isKindOfClass:NSString.class]) version = @"development";
        std::printf("SymClick diagnostics\nversion=%s\nmachine=%s\naccessibility=%s\n",
                    version.UTF8String,
                    systemInfo.machine,
                    CGPreflightPostEventAccess() ? "granted" : "not-granted");
    }
    return 0;
}

int RunSmokeTest() {
    @autoreleasepool {
        if (CGMainDisplayID() == 0) {
            std::fprintf(stderr, "SymClick smoke test skipped: no interactive display session\n");
            return 0;
        }
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [AppDelegate new];
        application.delegate = delegate;
        [application finishLaunching];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [application terminate:nil]; });
        [application run];
    }
    return 0;
}

const char *AgentBundleVersion() {
    id bundledVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([bundledVersion isKindOfClass:NSString.class]) return [bundledVersion UTF8String];
    return "development";
}

void PrintAgentError(const std::string &error, int exitCode) {
    std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"error\",\"code\":\"invalid_request\",\"message\":\"%s\"}\n",
                EscapeJson(error).c_str());
    (void)exitCode;
}

void PrintAgentConfig(const AgentOptions &options, const char *eventName) {
    const char *button = options.button == 1 ? "right" : options.button == 2 ? "middle" : "left";
    const char *pattern = options.pattern == 1 ? "double" : "single";
    if (options.hasClicks) {
        std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"%s\",\"valid\":true,"
                    "\"target\":{\"x\":%.3f,\"y\":%.3f},\"cps\":%.0f,\"button\":\"%s\","
                    "\"pattern\":\"%s\",\"jitter\":%.0f,\"start_delay_seconds\":%.0f,"
                    "\"bound\":{\"type\":\"clicks\",\"value\":%llu}}\n",
                    eventName, options.x, options.y, options.cps, button, pattern, options.jitter,
                    options.startDelay, static_cast<unsigned long long>(options.clicks));
    } else {
        std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"%s\",\"valid\":true,"
                    "\"target\":{\"x\":%.3f,\"y\":%.3f},\"cps\":%.0f,\"button\":\"%s\","
                    "\"pattern\":\"%s\",\"jitter\":%.0f,\"start_delay_seconds\":%.0f,"
                    "\"bound\":{\"type\":\"duration_seconds\",\"value\":%.0f}}\n",
                    eventName, options.x, options.y, options.cps, button, pattern, options.jitter,
                    options.startDelay, options.duration);
    }
}

int RunAgentHelp() {
    std::printf(
        "{\n"
        "  \"protocol\": \"symclick-agent/v1\",\n"
        "  \"name\": \"SymClick\",\n"
        "  \"version\": \"%s\",\n"
        "  \"commands\": {\n"
        "    \"status\": \"SymClick --agent-status\",\n"
        "    \"inspect\": \"SymClick --agent-inspect (read-only)\",\n"
        "    \"validate\": \"SymClick --agent-validate --x <px> --y <px> --clicks <n> --cps <n>\",\n"
        "    \"run\": \"SymClick --agent-run --confirm --x <px> --y <px> --clicks <n> --cps <n>\"\n"
        "  },\n"
        "  \"safety\": {\n"
        "    \"requires_confirmation\": true,\n"
        "    \"requires_fixed_target\": true,\n"
        "    \"requires_finite_bound\": true,\n"
        "    \"default_start_delay_seconds\": 1,\n"
        "    \"max_cps\": 5000,\n"
        "    \"max_clicks\": 10000000,\n"
        "    \"max_duration_seconds\": 86400\n"
        "  },\n"
        "  \"events\": [\"ready\", \"started\", \"completed\", \"error\"]\n"
        "}\n",
        AgentBundleVersion());
    return 0;
}

int RunAgentStatus() {
    @autoreleasepool {
        struct utsname systemInfo{};
        uname(&systemInfo);
        std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"status\","
                    "\"version\":\"%s\",\"machine\":\"%s\",\"accessibility\":\"%s\","
                    "\"local_only\":true,\"capabilities\":[\"inspect\",\"validate\",\"run\"]}\n",
                    AgentBundleVersion(), systemInfo.machine,
                    CGPreflightPostEventAccess() ? "granted" : "not-granted");
    }
    return 0;
}

int RunAgentInspect(int argc) {
    @autoreleasepool {
        if (argc != 2) {
            PrintAgentError("--agent-inspect takes no arguments", 2);
            return 2;
        }
        uint32_t count = 0;
        if (CGGetActiveDisplayList(0, nullptr, &count) != kCGErrorSuccess || count == 0) {
            std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"error\",\"code\":\"display_unavailable\"}\n");
            return 3;
        }
        std::vector<CGDirectDisplayID> displays(count);
        if (CGGetActiveDisplayList(count, displays.data(), &count) != kCGErrorSuccess) {
            std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"error\",\"code\":\"display_unavailable\"}\n");
            return 3;
        }
        CGEventRef event = CGEventCreate(nullptr);
        if (!event) {
            std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"error\",\"code\":\"pointer_unavailable\"}\n");
            return 3;
        }
        CGPoint point = CGEventGetLocation(event);
        CFRelease(event);
        NSMutableArray *items = [NSMutableArray array];
        for (uint32_t i = 0; i < count; ++i) {
            CGDirectDisplayID display = displays[i];
            CGRect bounds = CGDisplayBounds(display);
            id scale = NSNull.null;
            for (NSScreen *screen in NSScreen.screens) {
                NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
                if (number.unsignedIntValue == display) {
                    scale = @(screen.backingScaleFactor);
                    break;
                }
            }
            [items addObject:@{@"id": @(display), @"bounds": @{@"x": @(bounds.origin.x),
                @"y": @(bounds.origin.y), @"width": @(bounds.size.width), @"height": @(bounds.size.height)},
                @"scale": scale}];
        }
        NSDictionary *snapshot = @{@"protocol": @"symclick-agent/v1", @"event": @"inspection",
            @"read_only": @YES, @"coordinate_space": @"core_graphics_global_points",
            @"pointer": @{@"x": @(point.x), @"y": @(point.y)}, @"displays": items};
        NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        if (!json) return 3;
        std::printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}

int RunAgentCommand(int argc, const char *argv[], bool execute) {
    @autoreleasepool {
        AgentOptions options;
        std::string error;
        if (!ParseAgentOptions(argc, argv, &options, execute, &error)) {
            PrintAgentError(error, 2);
            return 2;
        }
        if (!execute) {
            PrintAgentConfig(options, "validated");
            return 0;
        }
        if (!CGPreflightPostEventAccess()) {
            std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"error\","
                        "\"code\":\"accessibility_required\",\"message\":\"Enable SymClick in Privacy & Security > Accessibility\"}\n");
            return 3;
        }

        ClickEngine engine;
        engine.setClicksPerSecond(options.cps);
        engine.setMouseButton(options.button);
        engine.setLocationMode(1);
        engine.setFixedLocation(CGPointMake(options.x, options.y));
        engine.setClickPattern(options.pattern);
        engine.setJitterPixels(options.jitter);
        engine.setStartDelaySeconds(options.startDelay);
        if (options.hasClicks) {
            engine.setLimitMode(1);
            engine.setClickLimit(options.clicks);
        } else {
            engine.setLimitMode(2);
            engine.setDurationSeconds(options.duration);
        }

        PrintAgentConfig(options, "ready");
        engine.start();
        std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"started\"}\n");
        std::fflush(stdout);
        while (engine.isRunning()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        engine.stop();
        const char *reason = options.hasClicks ? "click-limit" : "duration-limit";
        std::printf("{\"protocol\":\"symclick-agent/v1\",\"event\":\"completed\","
                    "\"clicks\":%llu,\"reason\":\"%s\"}\n",
                    static_cast<unsigned long long>(engine.clickCount()), reason);
    }
    return 0;
}

int main(int argc, const char *argv[]) {
    if (argc > 1 && std::string(argv[1]) == "--self-test") return RunSelfTests();
    if (argc > 1 && std::string(argv[1]) == "--diagnose") return RunDiagnostics();
    if (argc > 1 && std::string(argv[1]) == "--smoke-test") return RunSmokeTest();
    if (argc > 1 && std::string(argv[1]) == "--agent-help") return RunAgentHelp();
    if (argc > 1 && std::string(argv[1]) == "--agent-status") return RunAgentStatus();
    if (argc > 1 && std::string(argv[1]) == "--agent-inspect") return RunAgentInspect(argc);
    if (argc > 1 && std::string(argv[1]) == "--agent-validate") return RunAgentCommand(argc, argv, false);
    if (argc > 1 && std::string(argv[1]) == "--agent-run") return RunAgentCommand(argc, argv, true);
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
