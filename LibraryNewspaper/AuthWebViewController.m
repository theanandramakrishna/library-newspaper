#import "AuthWebViewController.h"

// The fixed KCLS entry point. The url= parameter is the NewsBank landing page,
// percent-encoded as the redirector expects.
static NSString * const LNRedirectorURLString =
    @"https://go.openathens.net/redirector/kcls.org"
    @"?url=https%3A%2F%2Finfoweb.newsbank.com%2Fapps%2Fnews%2F%3Fp%3DNewsBank";

static const NSTimeInterval LNStepTimeoutSeconds = 60.0;
static const NSInteger LNMaxLoginAttempts = 2;

// What the flow is waiting for. Each step names the page that must appear
// next; the timeout applies per step.
typedef NS_ENUM(NSInteger, LNAuthStep) {
    LNAuthStepAwaitLoginForm,      // redirector loaded; looking for the login form
    LNAuthStepAwaitNewsBank,       // credentials submitted; waiting for NewsBank
    LNAuthStepAwaitCollectionClick, // NewsBank landing; open Seattle Times Collection
    LNAuthStepAwaitImageFormatClick,// collection page; open the image format
    LNAuthStepAwaitIssueClick,     // edition page; open the most recent issue
    LNAuthStepDone                 // reading; no further automation
};

#pragma mark - JavaScript helpers

// Escapes a value for embedding in a single-quoted JS string literal.
static NSString *LNJavaScriptString(NSString *value) {
    if (value == nil) {
        return @"";
    }
    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\"
                                options:0
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"'" withString:@"\\'"
                                options:0
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\n" withString:@"\\n"
                                options:0
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r" withString:@""
                                options:0
                                  range:NSMakeRange(0, escaped.length)];
    return escaped;
}

// Finds a form containing a password field, fills in the credentials, and
// submits it. Returns one of:
//   NOPASSWORDFIELD / NOFORM / NOUSERFIELD  - page not recognized; keep waiting
//   SUBMITTED:button / SUBMITTED:form       - credentials sent
// Uses createEvent (not the Event constructor) so it works on iOS 9's engine.
static NSString *LNLoginFillScript(NSString *username, NSString *password) {
    return [NSString stringWithFormat:
        @"(function(){"
        "var pw=document.querySelector('input[type=password]');"
        "if(!pw)return 'NOPASSWORDFIELD';"
        "var form=pw.form;"
        "if(!form)return 'NOFORM';"
        "var user=null;"
        "var inputs=form.getElementsByTagName('input');"
        "for(var i=0;i<inputs.length;i++){"
        "var el=inputs[i];"
        "if(el===pw)continue;"
        "var t=(el.getAttribute('type')||'text').toLowerCase();"
        "if(t==='text'||t==='email'||t==='tel'||t==='username'||t===''){user=el;break;}"
        "}"
        "if(!user)return 'NOUSERFIELD';"
        "function setVal(el,v){"
        "el.value=v;"
        "var e1=document.createEvent('HTMLEvents');e1.initEvent('input',true,false);el.dispatchEvent(e1);"
        "var e2=document.createEvent('HTMLEvents');e2.initEvent('change',true,false);el.dispatchEvent(e2);"
        "}"
        "setVal(user,'%@');"
        "setVal(pw,'%@');"
        "var btn=form.querySelector('input[type=submit],button[type=submit]');"
        "if(!btn){var bs=form.getElementsByTagName('button');if(bs.length>0)btn=bs[0];}"
        "if(btn){btn.click();return 'SUBMITTED:button';}"
        "if(form.submit){form.submit();return 'SUBMITTED:form';}"
        "return 'NOSUBMIT';"
        "})()",
        LNJavaScriptString(username), LNJavaScriptString(password)];
}

// Clicks the first link whose visible text (or title/aria-label) contains the
// given term. On failure returns NOTFOUND plus a dump of the page's links so
// failures are diagnosable from the alert.
static NSString *LNClickLinkScript(NSString *term) {
    return [NSString stringWithFormat:
        @"(function(){"
        "var term='%@';"
        "var links=document.querySelectorAll('a[href]');"
        "var dump=[];"
        "for(var i=0;i<links.length;i++){"
        "var a=links[i];"
        "var txt=((a.textContent||'')+' '+(a.getAttribute('title')||'')+' '+(a.getAttribute('aria-label')||''));"
        "txt=txt.replace(/\\s+/g,' ').toLowerCase();"
        "if(txt.indexOf(term)>=0){"
        "if(a.target==='_blank')a.target='';"
        "a.click();"
        "return 'CLICKED';"
        "}"
        "}"
        "for(var k=0;k<links.length&&k<25;k++){"
        "var b=links[k];"
        "var bt=(b.textContent||'').replace(/\\s+/g,' ').substring(0,50);"
        "dump.push(bt+' => '+(b.getAttribute('href')||'').substring(0,90));"
        "}"
        "return 'NOTFOUND\\n'+dump.join('\\n');"
        "})()",
        LNJavaScriptString([term lowercaseString])];
}

// Picks the most recent issue from the edition browse page. Preference order:
// links whose text looks like a date, then links mentioning issue/edition,
// then any link into /apps/news/. Returns CLICKED or NOTFOUND plus a dump.
static NSString * const LNPickIssueScript =
    @"(function(){"
    "var links=document.querySelectorAll('a[href]');"
    "var here=location.href;"
    "var dateRe=/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.? \\d{1,2},? \\d{4}|\\d{1,2}\\/\\d{1,2}\\/\\d{2,4}|\\d{4}-\\d{2}-\\d{2}/i;"
    "var dump=[];"
    "var cands=[];"
    "for(var i=0;i<links.length;i++){"
    "var a=links[i];"
    "var href=a.getAttribute('href')||'';"
    "if(!href||href.charAt(0)==='#'||href.indexOf('javascript:')===0)continue;"
    "var txt=(a.textContent||'').replace(/\\s+/g,' ').trim();"
    "dump.push(txt.substring(0,50)+' => '+href.substring(0,90));"
    "var s=-1;"
    "if(dateRe.test(txt))s=3;"
    "else if(href.indexOf('issue')>=0||href.indexOf('edition')>=0)s=2;"
    "else if(href.indexOf('/apps/news/')>=0&&href!==here)s=1;"
    "if(s>0)cands.push({a:a,s:s,i:i});"
    "}"
    "if(cands.length===0)return 'NOTFOUND\\n'+dump.slice(0,25).join('\\n');"
    "cands.sort(function(x,y){return (y.s-x.s)||(x.i-y.i);});"
    "var p=cands[0].a;"
    "if(p.target==='_blank')p.target='';"
    "p.click();"
    "return 'CLICKED';"
    "})()";

#pragma mark - Auth web view controller

@interface AuthWebViewController () <UIWebViewDelegate>

@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, assign) LNAuthStep step;
@property (nonatomic, assign) NSInteger loginAttempts;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, assign) BOOL started;

@end

@implementation AuthWebViewController

- (instancetype)initWithUsername:(NSString *)username
                        password:(NSString *)password {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _username = [username copy];
        _password = [password copy];
        _step = LNAuthStepAwaitLoginForm;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];

    _webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _webView.scalesPageToFit = YES;
    _webView.delegate = self;
    [self.view addSubview:_webView];
}

- (void)dealloc {
    [_timeoutTimer invalidate];
    _webView.delegate = nil;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Leaving this screen (failure pop or manual back) stops the automation.
    [_timeoutTimer invalidate];
}

// start is triggered from viewDidAppear so the flow always begins once the
// controller is on screen, regardless of who pushed it.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_started) {
        return;
    }
    _started = YES;
    [self start];
}

#pragma mark - Flow

- (void)start {
    self.title = [self titleForStep:_step];
    [self resetTimeout];

    NSLog(@"[auth] loading redirector");
    NSURLRequest *request =
        [NSURLRequest requestWithURL:[NSURL URLWithString:LNRedirectorURLString]];
    [_webView loadRequest:request];
}

- (NSString *)titleForStep:(LNAuthStep)step {
    switch (step) {
        case LNAuthStepAwaitLoginForm:
        case LNAuthStepAwaitNewsBank:
            return @"Signing in…";
        case LNAuthStepAwaitCollectionClick:
            return @"Opening Seattle Times Collection…";
        case LNAuthStepAwaitImageFormatClick:
            return @"Opening image format…";
        case LNAuthStepAwaitIssueClick:
            return @"Opening the latest issue…";
        case LNAuthStepDone:
            return @"Seattle Times";
    }
}

- (void)setStep:(LNAuthStep)step {
    _step = step;
    self.title = [self titleForStep:step];
}

- (void)resetTimeout {
    [_timeoutTimer invalidate];
    _timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:LNStepTimeoutSeconds
                                                     target:self
                                                   selector:@selector(timeoutFired)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)timeoutFired {
    if (_step == LNAuthStepDone) {
        return;
    }
    [self failWithReason:@"Timed out waiting for the next page."
                  detail:nil];
}

- (NSString *)runScript:(NSString *)script {
    return [_webView stringByEvaluatingJavaScriptFromString:script];
}

- (void)handlePageLoad {
    if (_step == LNAuthStepDone) {
        return;
    }
    [self resetTimeout];

    NSString *host = _webView.request.mainDocumentURL.host.lowercaseString;
    NSLog(@"[auth] page loaded (step %ld): %@", (long)_step, host ?: @"(nil)");

    BOOL isNewsBank = [host containsString:@"newsbank.com"];

    if (isNewsBank) {
        [self handleNewsBankPage];
        return;
    }

    // Any other host (OpenAthens redirector, OpenAthens login, a library-hosted
    // login page): if it shows a login form, fill and submit it.
    if (_step == LNAuthStepAwaitLoginForm || _step == LNAuthStepAwaitNewsBank) {
        [self tryLoginForm];
    }
}

- (void)tryLoginForm {
    NSString *result = [self runScript:LNLoginFillScript(_username, _password)] ?: @"";
    NSLog(@"[auth] login form probe: %@", result);

    if ([result hasPrefix:@"SUBMITTED"]) {
        _loginAttempts++;
        if (_loginAttempts >= LNMaxLoginAttempts) {
            // The login page came back after a submission: rejected credentials.
            [self failWithReason:@"The site did not accept the username or password."
                          detail:nil];
            return;
        }
        [self setStep:LNAuthStepAwaitNewsBank];
    }
    // NOPASSWORDFIELD / NOFORM / NOUSERFIELD: an intermediate page. Keep
    // waiting; the step timeout reports failure if nothing arrives.
}

- (void)handleNewsBankPage {
    NSString *result = nil;
    NSLog(@"[auth] NewsBank page at step %ld", (long)_step);

    switch (_step) {
        case LNAuthStepAwaitLoginForm:
        case LNAuthStepAwaitNewsBank:
            // An already-authenticated session can land straight on NewsBank.
            [self setStep:LNAuthStepAwaitCollectionClick];
            // fall through

        case LNAuthStepAwaitCollectionClick:
            result = [self runScript:LNClickLinkScript(@"seattle times")] ?: @"";
            if (![result hasPrefix:@"CLICKED"]) {
                [self failWithReason:@"Could not find the Seattle Times Collection link."
                              detail:result];
                return;
            }
            NSLog(@"[auth] clicked Seattle Times Collection");
            [self setStep:LNAuthStepAwaitImageFormatClick];
            return;

        case LNAuthStepAwaitImageFormatClick:
            result = [self runScript:LNClickLinkScript(@"image")] ?: @"";
            if (![result hasPrefix:@"CLICKED"]) {
                [self failWithReason:@"Could not find the image format link."
                              detail:result];
                return;
            }
            NSLog(@"[auth] clicked image format");
            [self setStep:LNAuthStepAwaitIssueClick];
            return;

        case LNAuthStepAwaitIssueClick:
            result = [self runScript:LNPickIssueScript] ?: @"";
            if (![result hasPrefix:@"CLICKED"]) {
                [self failWithReason:@"Could not find the latest issue link."
                              detail:result];
                return;
            }
            NSLog(@"[auth] clicked latest issue; automation complete");
            [self setStep:LNAuthStepDone];
            [_timeoutTimer invalidate];
            return;

        case LNAuthStepDone:
            return;
    }
}

#pragma mark - Failure

- (void)failWithReason:(NSString *)reason detail:(NSString *)detail {
    if (_step == LNAuthStepDone) {
        return;
    }
    NSLog(@"[auth] FAILED (step %ld): %@ | detail: %@", (long)_step, reason, detail ?: @"(none)");
    _step = LNAuthStepDone;
    [_timeoutTimer invalidate];

    NSMutableString *message = [NSMutableString stringWithString:reason];
    NSString *url = _webView.request.mainDocumentURL.absoluteString;
    if (url.length > 0) {
        [message appendFormat:@"\n\n%@", url];
    }
    if (detail.length > 0) {
        NSString *trimmed = detail;
        if (trimmed.length > 600) {
            trimmed = [trimmed substringToIndex:600];
        }
        [message appendFormat:@"\n\n%@", trimmed];
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Sign-in failed"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self handlePageLoad];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (_step == LNAuthStepDone) {
        return;
    }
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    NSURL *failingURL = error.userInfo[NSURLErrorFailingURLErrorKey]
                        ?: _webView.request.mainDocumentURL;
    [self failWithReason:
              [NSString stringWithFormat:@"A page failed to load (%@).",
                                         error.localizedDescription]
              detail:failingURL.absoluteString];
}

@end
