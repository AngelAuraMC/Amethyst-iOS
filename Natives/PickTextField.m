#import "PickTextField.h"
#import "UIKit+hook.h"
#import "utils.h"

@interface PickViewController : UIViewController
@property(nonatomic, assign) UITextField *textField;
@end

@implementation PickViewController
- (void)loadView {
    [super loadView];
    if(self.textField.inputAccessoryView) [self.view addSubview:self.textField.inputAccessoryView];
    [self.view addSubview:self.textField.inputView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CGRect frame = CGRectMake(
        self.view.safeAreaInsets.left,
        self.view.safeAreaInsets.top,
        MIN(self.view.frame.size.width - self.view.safeAreaInsets.right, self.preferredContentSize.width),
        MIN(self.view.frame.size.height - self.view.safeAreaInsets.bottom, self.preferredContentSize.height));
    CGRect accessoryFrame = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, self.textField.inputAccessoryView.frame.size.height);
    self.textField.inputAccessoryView.frame = accessoryFrame;
    self.textField.inputView.frame = CGRectMake(frame.origin.x, CGRectGetMaxY(accessoryFrame), frame.size.width, frame.size.height - CGRectGetMaxY(self.inputAccessoryView.frame));
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.textField.delegate textFieldDidEndEditing:self.textField];
}
@end

@interface PickTextField()
@property(nonatomic) PickViewController *vc;
@property(nonatomic) UIButton *doneButton;
@end

@implementation PickTextField

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return NO;
}

- (CGRect)caretRectForPosition:(UITextPosition*) position {
    return CGRectNull;
}

- (NSArray *)selectionRectsForRange:(UITextRange *)range {
    return nil;
}

- (BOOL)prefersPopoverPresentation {
    BOOL hasLiquidGlass = _UISolariumEnabled && _UISolariumEnabled();
    return hasLiquidGlass || NSProcessInfo.processInfo.isMacCatalystApp;
}

- (void)setupDoneButtonWithTarget:(id)target action:(SEL)action {
    if (self.prefersPopoverPresentation) return;
    UIToolbar *toolbar = (id)self.inputAccessoryView;
    if (!toolbar) {
        UIBarButtonItem *btnFlexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0, 0.0, self.frame.size.width, 44.0)];
        toolbar.items = @[btnFlexibleSpace];
        self.inputAccessoryView = toolbar;
    }
    UIBarButtonItem *editDoneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:target action:action];
    toolbar.items = [toolbar.items arrayByAddingObject:editDoneButton];
}

- (BOOL)becomeFirstResponder {
    // iOS 26 uses popover aswell
    if (!self.prefersPopoverPresentation) {
        return [super becomeFirstResponder];
    }

    self.vc = [[PickViewController alloc] init];
    self.vc.modalPresentationStyle = UIModalPresentationPopover;
    CGFloat width = MIN(400, MIN(self.window.frame.size.width, self.window.frame.size.height));
    self.vc.preferredContentSize = CGSizeMake(width, 250);
    self.vc.textField = self;

    UIPopoverPresentationController *popoverController = [self.vc popoverPresentationController];
    popoverController.sourceView = self;
    popoverController.sourceRect = self.frame;

    UIViewController *showingVC = (id)self.nextResponder;
    while (![showingVC isKindOfClass:UIViewController.class]) {
        showingVC = (id)showingVC.nextResponder;
    }
    [showingVC presentViewController:self.vc animated:YES completion:nil];
    if([self.delegate respondsToSelector:@selector(textFieldDidBeginEditing:)]) {
        [self.delegate textFieldDidBeginEditing:self];
    }

    return YES;
}

- (BOOL)endEditing:(BOOL)force {
    if (!NSProcessInfo.processInfo.isMacCatalystApp) {
        return [super endEditing:force];
    }

    [self.vc dismissViewControllerAnimated:YES completion:NULL];
    if([self.delegate respondsToSelector:@selector(textFieldDidEndEditing:)]) {
        [self.delegate textFieldDidEndEditing:self];
    }
    self.vc = nil;
    return YES;
}

@end