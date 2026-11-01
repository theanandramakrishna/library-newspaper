#import "LoginViewController.h"
#import "AuthWebViewController.h"
#import <Security/Security.h>

#pragma mark - Keychain helpers

static NSString * const LNKeychainService = @"com.anand.librarynewspaper";

static BOOL LNKeychainSaveCredentials(NSString *username, NSString *password) {
    NSDictionary *query = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : LNKeychainService,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSDictionary *attributes = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : LNKeychainService,
        (__bridge id)kSecAttrAccount : username ?: @"",
        (__bridge id)kSecValueData : [password dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data],
        (__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
    };
    return SecItemAdd((__bridge CFDictionaryRef)attributes, NULL) == errSecSuccess;
}

static BOOL LNKeychainLoadCredentials(NSString **username, NSString **password) {
    NSDictionary *query = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : LNKeychainService,
        (__bridge id)kSecReturnAttributes : @YES,
        (__bridge id)kSecReturnData : @YES,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) {
        return NO;
    }
    NSDictionary *item = CFBridgingRelease(result);
    NSString *account = item[(__bridge id)kSecAttrAccount];
    NSData *data = item[(__bridge id)kSecValueData];
    if (account.length == 0 || data.length == 0) {
        return NO;
    }
    if (username) {
        *username = account;
    }
    if (password) {
        *password = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return YES;
}

#pragma mark - Login view controller

@interface LoginViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *logonButton;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, assign) BOOL autoStartDone;

@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.title = @"News Reader";

    [self buildSubviews];
    [self loadSavedCredentials];
}

- (void)buildSubviews {
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"News Reader";
    _titleLabel.font = [UIFont boldSystemFontOfSize:32];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.text = @"The Seattle Times via your KCLS account";
    _subtitleLabel.font = [UIFont systemFontOfSize:15];
    _subtitleLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_subtitleLabel];

    _usernameField = [[UITextField alloc] init];
    _usernameField.placeholder = @"Username or library card";
    _usernameField.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    _usernameField.textColor = [UIColor whiteColor];
    _usernameField.tintColor = [UIColor whiteColor];
    _usernameField.font = [UIFont systemFontOfSize:17];
    _usernameField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:_usernameField.placeholder
                                        attributes:@{NSForegroundColorAttributeName:
                                                         [UIColor colorWithWhite:0.55 alpha:1.0]}];
    _usernameField.autocorrectionType = UITextAutocorrectionTypeNo;
    _usernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _usernameField.keyboardType = UIKeyboardTypeASCIICapable;
    _usernameField.returnKeyType = UIReturnKeyNext;
    _usernameField.delegate = self;
    _usernameField.layer.cornerRadius = 6.0;
    _usernameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_usernameField];

    _passwordField = [[UITextField alloc] init];
    _passwordField.placeholder = @"Password or PIN";
    _passwordField.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    _passwordField.textColor = [UIColor whiteColor];
    _passwordField.tintColor = [UIColor whiteColor];
    _passwordField.font = [UIFont systemFontOfSize:17];
    _passwordField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:_passwordField.placeholder
                                        attributes:@{NSForegroundColorAttributeName:
                                                         [UIColor colorWithWhite:0.55 alpha:1.0]}];
    _passwordField.secureTextEntry = YES;
    _passwordField.autocorrectionType = UITextAutocorrectionTypeNo;
    _passwordField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _passwordField.returnKeyType = UIReturnKeyDone;
    _passwordField.delegate = self;
    _passwordField.layer.cornerRadius = 6.0;
    _passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_passwordField];

    _logonButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_logonButton setTitle:@"Logon" forState:UIControlStateNormal];
    _logonButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [_logonButton setTitleColor:[UIColor colorWithWhite:0.08 alpha:1.0] forState:UIControlStateNormal];
    _logonButton.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    _logonButton.layer.cornerRadius = 6.0;
    _logonButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_logonButton addTarget:self action:@selector(logonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_logonButton];

    _errorLabel = [[UILabel alloc] init];
    _errorLabel.font = [UIFont systemFontOfSize:13];
    _errorLabel.textColor = [UIColor colorWithRed:1.0 green:0.45 blue:0.40 alpha:1.0];
    _errorLabel.textAlignment = NSTextAlignmentCenter;
    _errorLabel.numberOfLines = 0;
    _errorLabel.hidden = YES;
    _errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_errorLabel];

    NSLayoutConstraint *usernameWidth = [_usernameField.widthAnchor constraintEqualToConstant:360];
    usernameWidth.priority = 999;
    NSLayoutConstraint *passwordWidth = [_passwordField.widthAnchor constraintEqualToConstant:360];
    passwordWidth.priority = 999;
    NSLayoutConstraint *buttonWidth = [_logonButton.widthAnchor constraintEqualToConstant:360];
    buttonWidth.priority = 999;

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:72],

        [_subtitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8],

        [_usernameField.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_usernameField.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:36],
        usernameWidth,
        [_usernameField.widthAnchor constraintLessThanOrEqualToConstant:360],
        [_usernameField.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [_usernameField.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
        [_usernameField.heightAnchor constraintEqualToConstant:44],

        [_passwordField.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_passwordField.topAnchor constraintEqualToAnchor:_usernameField.bottomAnchor constant:12],
        passwordWidth,
        [_passwordField.widthAnchor constraintLessThanOrEqualToConstant:360],
        [_passwordField.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [_passwordField.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
        [_passwordField.heightAnchor constraintEqualToConstant:44],

        [_logonButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_logonButton.topAnchor constraintEqualToAnchor:_passwordField.bottomAnchor constant:28],
        buttonWidth,
        [_logonButton.widthAnchor constraintLessThanOrEqualToConstant:360],
        [_logonButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [_logonButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
        [_logonButton.heightAnchor constraintEqualToConstant:44],

        [_errorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_errorLabel.topAnchor constraintEqualToAnchor:_logonButton.bottomAnchor constant:16],
        [_errorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [_errorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32]
    ]];
}

- (void)loadSavedCredentials {
    NSString *username = nil;
    NSString *password = nil;
    if (LNKeychainLoadCredentials(&username, &password)) {
        NSLog(@"[login] keychain load: OK");
        _usernameField.text = username;
        _passwordField.text = password;
    } else {
        NSLog(@"[login] keychain load: no saved credentials");
    }
}

#pragma mark - Actions

- (void)logonTapped {
    NSString *username = [_usernameField.text stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = _passwordField.text;

    if (username.length == 0 || password.length == 0) {
        [self showError:@"Enter your username and password."];
        return;
    }

    [self clearError];
    BOOL saved = LNKeychainSaveCredentials(username, password);
    NSLog(@"[login] keychain save: %@", saved ? @"OK" : @"FAILED");

    [self startAuthenticationWithUsername:username password:password];
}

- (void)startAuthenticationWithUsername:(NSString *)username password:(NSString *)password {
    [self.view endEditing:YES];
    [self clearError];

    AuthWebViewController *auth =
        [[AuthWebViewController alloc] initWithUsername:username password:password];
    [self.navigationController pushViewController:auth animated:YES];
}

- (void)showError:(NSString *)message {
    _errorLabel.text = message;
    _errorLabel.hidden = NO;
}

- (void)clearError {
    _errorLabel.text = nil;
    _errorLabel.hidden = YES;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _usernameField) {
        [_passwordField becomeFirstResponder];
    } else if (textField == _passwordField) {
        [self logonTapped];
    }
    return YES;
}

#pragma mark - Returning users

// Returning users with saved credentials go straight into the web flow. If
// that flow fails it pops back here; autoStartDone makes sure we do not push
// the web view again automatically (the user can tap Logon to retry).
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (_autoStartDone) {
        return;
    }

    NSString *username = nil;
    NSString *password = nil;
    if (LNKeychainLoadCredentials(&username, &password) &&
        username.length > 0 && password.length > 0) {
        _autoStartDone = YES;
        _usernameField.text = username;
        _passwordField.text = password;
        [self startAuthenticationWithUsername:username password:password];
    }
}

@end
