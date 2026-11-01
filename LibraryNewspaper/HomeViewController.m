#import "HomeViewController.h"
#import "IssueViewController.h"
#import "LoginViewController.h"
#import "AuthWebViewController.h"

static CGFloat const LHFooterHeight = 56.0;
static NSInteger const LHMaxPapers = 5;

@interface HomeViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *footerView;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIButton *dateButton;
@property (nonatomic, strong) UIButton *fetchButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) IssueViewController *issueVC;
@property (nonatomic, strong) UIViewController *authVC;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) UIDatePicker *activeDatePicker;

@end

@implementation HomeViewController

- (instancetype)initWithStore:(LibraryStore *)store {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _store = store;
        _selectedDate = [NSDate date];
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = @"yyyy-MM-dd";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];

    // Content area fills the space above the footer.
    _contentView = [[UIView alloc] init];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_contentView];

    // Footer bar.
    _footerView = [[UIView alloc] init];
    _footerView.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    _footerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_footerView];

    _settingsButton = [self footerButtonWithTitle:@"Settings" tag:0];
    _dateButton     = [self footerButtonWithTitle:@"Date"     tag:1];
    _fetchButton    = [self footerButtonWithTitle:@"Fetch paper" tag:2];

    [_footerView addSubview:_settingsButton];
    [_footerView addSubview:_dateButton];
    [_footerView addSubview:_fetchButton];

    [self addEmptyState];

    [NSLayoutConstraint activateConstraints:@[
        [_contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_contentView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:_footerView.topAnchor],

        [_footerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_footerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_footerView.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.topAnchor],
        [_footerView.heightAnchor constraintEqualToConstant:LHFooterHeight],

        [_settingsButton.leadingAnchor constraintEqualToAnchor:_footerView.leadingAnchor constant:12],
        [_settingsButton.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_settingsButton.widthAnchor constraintEqualToConstant:80],

        [_dateButton.leadingAnchor constraintEqualToAnchor:_settingsButton.trailingAnchor constant:12],
        [_dateButton.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_dateButton.widthAnchor constraintEqualToConstant:80],

        [_fetchButton.trailingAnchor constraintEqualToAnchor:_footerView.trailingAnchor constant:-12],
        [_fetchButton.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_fetchButton.widthAnchor constraintEqualToConstant:120],
    ]];
}

- (UIButton *)footerButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15];
    button.tag = tag;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:@selector(footerButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)addEmptyState {
    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.text = @"Paper not fetched yet";
    _emptyLabel.font = [UIFont boldSystemFontOfSize:20];
    _emptyLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:_emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:_contentView.centerYAnchor constant:-40],
    ]];
}

- (void)showPaperNotFetched {
    [self.issueVC willMoveToParentViewController:nil];
    [self.issueVC.view removeFromSuperview];
    [self.issueVC removeFromParentViewController];
    self.issueVC = nil;

    _emptyLabel.hidden = NO;
    self.title = @"News Reader";
}

- (void)showIssue:(LNIssue *)issue {
    self.currentIssue = issue;

    _emptyLabel.hidden = YES;

    if (self.issueVC != nil) {
        [self.issueVC willMoveToParentViewController:nil];
        [self.issueVC.view removeFromSuperview];
        [self.issueVC removeFromParentViewController];
    }

    self.issueVC = [[IssueViewController alloc] initWithStore:self.store
                                                      issue:issue
                                                  startPage:1];
    [self addChildViewController:self.issueVC];
    self.issueVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:self.issueVC.view];
    [self.issueVC didMoveToParentViewController:self];

    [NSLayoutConstraint activateConstraints:@[
        [self.issueVC.view.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor],
        [self.issueVC.view.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor],
        [self.issueVC.view.topAnchor constraintEqualToAnchor:_contentView.topAnchor],
        [self.issueVC.view.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor],
    ]];

    self.title = issue.title;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

#pragma mark - Footer actions

- (void)footerButtonTapped:(UIButton *)button {
    switch (button.tag) {
        case 0: [self settingsTapped]; break;
        case 1: [self dateTapped]; break;
        case 2: [self fetchTapped]; break;
    }
}

- (void)settingsTapped {
    LoginViewController *login = [[LoginViewController alloc] init];
    // Opened from Settings: just show the logon screen with pre-filled
    // credentials; do not auto-start the web flow.
    [self.navigationController pushViewController:login animated:YES];
}

- (void)dateTapped {
    // Present a simple date picker modal, defaulting to the selected date.
    UIViewController *picker = [[UIViewController alloc] initWithNibName:nil bundle:nil];
    picker.view.backgroundColor = [UIColor whiteColor];
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    picker.preferredContentSize = CGSizeMake(320, 260);

    UIDatePicker *datePicker = [[UIDatePicker alloc] init];
    datePicker.datePickerMode = UIDatePickerModeDate;
    datePicker.date = _selectedDate;
    datePicker.maximumDate = [NSDate date];
    datePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [picker.view addSubview:datePicker];
    self.activeDatePicker = datePicker;

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done addTarget:self action:@selector(datePickerDone:) forControlEvents:UIControlEventTouchUpInside];
    [picker.view addSubview:done];

    [NSLayoutConstraint activateConstraints:@[
        [datePicker.topAnchor constraintEqualToAnchor:picker.view.topAnchor constant:12],
        [datePicker.leadingAnchor constraintEqualToAnchor:picker.view.leadingAnchor constant:12],
        [datePicker.trailingAnchor constraintEqualToAnchor:picker.view.trailingAnchor constant:-12],

        [done.topAnchor constraintEqualToAnchor:datePicker.bottomAnchor constant:16],
        [done.centerXAnchor constraintEqualToAnchor:picker.view.centerXAnchor],
    ]];

    [self presentViewController:picker animated:YES completion:nil];
}

- (void)datePickerDone:(UIButton *)button {
    if (self.activeDatePicker != nil) {
        _selectedDate = self.activeDatePicker.date;
    }
    [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
    self.activeDatePicker = nil;
}

- (void)fetchTapped {
    NSString *username = nil;
    NSString *password = nil;
    if (![LoginViewController loadSavedCredentials:&username password:&password] ||
        username.length == 0 || password.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No credentials"
                                                                       message:@"Please open Settings and enter your KCLS username and password first."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString *dateString = [_dateFormatter stringFromDate:_selectedDate];

    AuthWebViewController *auth =
        [[AuthWebViewController alloc] initWithUsername:username password:password targetDate:dateString];
    auth.onComplete = ^(LNIssue *fetchedIssue, NSError *error) {
        if (error != nil) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Fetch failed"
                                                                           message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        // Pop the background webview controller and show the downloaded issue.
        [self.navigationController popViewControllerAnimated:YES];
        [self showIssue:fetchedIssue];
    };
    self.authVC = auth;
    [self.navigationController pushViewController:auth animated:YES];
}

@end
