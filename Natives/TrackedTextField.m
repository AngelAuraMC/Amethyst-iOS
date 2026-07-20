#import "TrackedTextField.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#include "glfw_keycodes.h"

extern bool isUseStackQueueCall;

@interface UITextField(private)
- (NSRange)insertFilteredText:(NSString *)text;
- (id) replaceRangeWithTextWithoutClosingTyping:(UITextRange *)range replacementText:(NSString *)text;
@end

@interface TrackedTextField()
@property(nonatomic) int lastTextPos;
@property(nonatomic) CGFloat lastPointX;
@property(nonatomic) BOOL ignoreBridgeEvents; 
@end

@implementation TrackedTextField

- (void)sendMultiBackspaces:(int)times {
    // NSLog(@"[KeyboardDebug] sendMultiBackspaces called, times: %d", times);
    for (int i = 0; i < times; i++) {
        self.sendKey(GLFW_KEY_BACKSPACE, 0, 1, 0);
        self.sendKey(GLFW_KEY_BACKSPACE, 0, 0, 0);
    }
}

- (void)paste:(id)sender {
    // NSLog(@"[KeyboardDebug] Paste triggered. Text: '%@'", UIPasteboard.generalPasteboard.string);
    [super paste:sender];
    [self sendText:UIPasteboard.generalPasteboard.string];
}

- (void)sendText:(NSString *)text {
    // NSLog(@"[KeyboardDebug] sendText processing string: '%@' (length: %lu)", text, (unsigned long)text.length);
    for (int i = 0; i < text.length; i++) {
        unichar theChar = [text characterAtIndex:i];
        // NSLog(@"[KeyboardDebug] Sending character: '%C' (Unicode decimal: %d)", theChar, theChar);
        
        if (isUseStackQueueCall && self.sendCharMods != nil) {
            // NSLog(@"[KeyboardDebug] -> Routing to sendCharMods block");
            self.sendCharMods(theChar, 0);
        } else {
            // NSLog(@"[KeyboardDebug] -> Routing to sendChar block (isUseStackQueueCall: %d, sendCharMods present: %s)", 
            //       isUseStackQueueCall, self.sendCharMods != nil ? "YES" : "NO");
            self.sendChar(theChar);
        }
    }
}

- (void)beginFloatingCursorAtPoint:(CGPoint)point {
    [super beginFloatingCursorAtPoint:point];
    self.lastPointX = point.x;
}

- (void)updateFloatingCursorAtPoint:(CGPoint)point {
    [super updateFloatingCursorAtPoint:point];

    if (self.lastPointX == 0 || (self.lastTextPos > 0 && self.lastTextPos < self.text.length)) {
        return;
    }

    CGFloat diff = point.x - self.lastPointX;
    if (ABS(diff) < 8) {
        return;
    }
    self.lastPointX = point.x;

    int key = (diff > 0) ? GLFW_KEY_DPAD_RIGHT : GLFW_KEY_DPAD_LEFT;
    self.sendKey(key, 0, 1, 0);
    self.sendKey(key, 0, 0, 0);
}

- (void)endFloatingCursor {
    [super endFloatingCursor];
    self.lastPointX = 0;
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)point {
    UITextPosition *position = [super closestPositionToPoint:point];
    int start = [self offsetFromPosition:self.beginningOfDocument toPosition:position];
    if (start - self.lastTextPos != 0) {
        int key = (start - self.lastTextPos > 0) ? GLFW_KEY_DPAD_RIGHT : GLFW_KEY_DPAD_LEFT;
        self.sendKey(key, 0, 1, 0);
        self.sendKey(key, 0, 0, 0);
    }
    self.lastTextPos = start;
    return position;
}

- (void)deleteBackward {
    // NSLog(@"[KeyboardDebug] deleteBackward invoked (Backspace pressed)");
    if (self.text.length > 1) {
        [super deleteBackward];
    } else {
        self.text = @" ";
    }
    self.lastTextPos = [super offsetFromPosition:self.beginningOfDocument toPosition:self.selectedTextRange.start];

    [self sendMultiBackspaces:1];
}

- (BOOL)hasText {
    self.lastTextPos = MAX(self.lastTextPos, 1);
    return YES;
}

- (void)insertText:(NSString *)text {
    // NSLog(@"[KeyboardDebug] UIKeyInput insertText received raw input from iOS: '%@'", text);
    if (self.ignoreBridgeEvents) {
        // NSLog(@"[KeyboardDebug] insertText bypassed (ignoreBridgeEvents is active)");
        [super insertText:text];
        return;
    }
    self.ignoreBridgeEvents = YES;

    int cursorPos = [super offsetFromPosition:self.beginningOfDocument toPosition:self.selectedTextRange.start];
    int off = self.lastTextPos - cursorPos;
    if (off > 0) {
        [self sendMultiBackspaces:off];
    }

    self.lastTextPos = cursorPos + text.length;
    [self sendText:text];

    [super insertText:text];
    self.ignoreBridgeEvents = NO;
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    // NSLog(@"[KeyboardDebug] replaceRange:withText: caught auto-correction/replacement: '%@'", text);
    if (self.ignoreBridgeEvents) {
        [super replaceRange:range withText:text];
        return;
    }
    self.ignoreBridgeEvents = YES;

    int oldLength = [super offsetFromPosition:range.start toPosition:range.end];
    [self sendMultiBackspaces:oldLength];
    [self sendText:text];
    self.lastTextPos += text.length - oldLength;

    [super replaceRange:range withText:text];
    self.ignoreBridgeEvents = NO;
}

- (NSRange)insertFilteredText:(NSString *)text {
    // NSLog(@"[KeyboardDebug] Private insertFilteredText called: '%@'", text);
    if (self.ignoreBridgeEvents) {
        return [super insertFilteredText:text];
    }
    self.ignoreBridgeEvents = YES;

    int cursorPos = [super offsetFromPosition:self.beginningOfDocument toPosition:self.selectedTextRange.start];
    int off = self.lastTextPos - cursorPos;
    if (off > 0) {
        [self sendMultiBackspaces:off];
    }

    self.lastTextPos = cursorPos + text.length;
    [self sendText:text];

    NSRange range = [super insertFilteredText:text];
    self.ignoreBridgeEvents = NO;
    return range;
}

- (id)replaceRangeWithTextWithoutClosingTyping:(UITextRange *)range replacementText:(NSString *)text
{
    // NSLog(@"[KeyboardDebug] replaceRangeWithTextWithoutClosingTyping called: '%@'", text);
    if (self.ignoreBridgeEvents) {
        return [super replaceRangeWithTextWithoutClosingTyping:range replacementText:text];
    }
    self.ignoreBridgeEvents = YES;

    int oldLength = [super offsetFromPosition:range.start toPosition:range.end];
    [self sendMultiBackspaces:oldLength];
    [self sendText:text];
    self.lastTextPos += text.length - oldLength;

    id result = [super replaceRangeWithTextWithoutClosingTyping:range replacementText:text];
    self.ignoreBridgeEvents = NO;
    return result;
}

- (void)setAttributedMarkedText:(NSAttributedString *)markedText selectedRange:(NSRange)selectedRange {
    // NSLog(@"[KeyboardDebug] setAttributedMarkedText (marked text update): '%@'", markedText.string);
    if (self.ignoreBridgeEvents) {
        [super setAttributedMarkedText:markedText selectedRange:selectedRange];
        return;
    }
    self.ignoreBridgeEvents = YES;

    NSInteger markedLength = [self offsetFromPosition:self.markedTextRange.start toPosition:self.markedTextRange.end];
    [self sendMultiBackspaces:markedLength];

    [super setAttributedMarkedText:markedText selectedRange:selectedRange];
    [self sendText:markedText.string];
    self.ignoreBridgeEvents = NO;
}

- (void)setText:(NSString *)text {
    [super setText:text];
    self.lastTextPos = text.length;
}

@end