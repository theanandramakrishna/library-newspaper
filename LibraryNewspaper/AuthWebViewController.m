#import "AuthWebViewController.h"

// The fixed KCLS entry point. The url= parameter is the NewsBank landing page,
// percent-encoded as the redirector expects.
static NSString * const LNRedirectorURLString =
    @"https://go.openathens.net/redirector/kcls.org"
    @"?url=https%3A%2F%2Finfoweb.newsbank.com%2Fapps%2Fnews%2F%3Fp%3DNewsBank";

static const NSTimeInterval LNStepTimeoutSeconds = 60.0;
static const NSInteger LNMaxTotalSubmissions = 5;

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

// Handles modern login pages, including two-step ones (username first, then a
// password step that appears in place). Returns one of:
//   NOFORM                       - nothing actionable on the page
//   NOSUBMIT                     - fields found but no way to submit
//   SUBMITTED:both|user|pass:how - credentials sent (which fields, and how)
// It also looks inside same-origin iframes. Uses createEvent so it works on
// iOS 9's engine.
static NSString *LNCredentialProbeScript(NSString *username, NSString *password) {
    return [NSString stringWithFormat:
        @"(function(){"
        "var USER='%@';var PASS='%@';"
        "function setVal(el,v){"
        "if(el.focus)el.focus();"
        "el.value=v;"
        "var e1=document.createEvent('HTMLEvents');e1.initEvent('input',true,false);el.dispatchEvent(e1);"
        "var e2=document.createEvent('HTMLEvents');e2.initEvent('change',true,false);el.dispatchEvent(e2);"
        "}"
        "function howToSubmit(scope,form){"
        "var btn=scope.querySelector('input[type=submit],button[type=submit]');"
        "if(!btn){var bs=scope.querySelectorAll('button');"
        "for(var i=0;i<bs.length;i++){var bt=(bs[i].textContent||'').toLowerCase();"
        "if(bt.indexOf('next')>=0||bt.indexOf('sign')>=0||bt.indexOf('log')>=0||bt.indexOf('continue')>=0){btn=bs[i];break;}}}"
        "if(!btn){var is2=scope.querySelectorAll('input[type=button]');if(is2.length>0)btn=is2[0];}"
        "if(btn){btn.click();return 'button';}"
        "if(form&&form.submit){form.submit();return 'form';}"
        "return '';"
        "}"
        "function findIn(root){"
        "var pw=root.querySelector('input[type=password]');"
        "if(pw){"
        "var form=pw.form;"
        "var scope=form||root;"
        "var user=null;"
        "var inputs=scope.querySelectorAll('input');"
        "for(var i=0;i<inputs.length;i++){"
        "var el=inputs[i];"
        "if(el===pw)continue;"
        "var t=(el.getAttribute('type')||'text').toLowerCase();"
        "if(t==='hidden'||t==='checkbox'||t==='radio'||t==='submit')continue;"
        "if(t==='text'||t==='email'||t==='tel'||t==='username'||t===''){user=el;break;}"
        "}"
        "var how='';"
        "if(user){setVal(user,USER);setVal(pw,PASS);how=howToSubmit(scope,form);"
        "return how?('SUBMITTED:both:'+how):'NOSUBMIT';}"
        "setVal(pw,PASS);how=howToSubmit(scope,form);"
        "return how?('SUBMITTED:pass:'+how):'NOSUBMIT';"
        "}"
        "var cand=null;"
        "var inputs=root.querySelectorAll('input[type=text],input[type=email],input[type=tel],input:not([type])');"
        "for(var j=0;j<inputs.length;j++){"
        "var el2=inputs[j];"
        "var t2=(el2.getAttribute('type')||'text').toLowerCase();"
        "if(t2==='hidden'||t2==='submit')continue;"
        "var hint=((el2.name||'')+' '+(el2.id||'')+' '+(el2.placeholder||'')+' '+(el2.getAttribute('autocomplete')||'')).toLowerCase();"
        "if(hint.indexOf('search')>=0||hint.indexOf('query')>=0)continue;"
        "cand=el2;break;"
        "}"
        "if(!cand)return 'NOFORM';"
        "setVal(cand,USER);"
        "var how2=howToSubmit(cand.form||root,cand.form||root);"
        "return how2?('SUBMITTED:user:'+how2):'NOSUBMIT';"
        "}"
        "var r=findIn(document);"
        "if(r==='NOFORM'||r==='NOSUBMIT'){"
        "var fs=document.querySelectorAll('iframe');"
        "for(var k=0;k<fs.length;k++){"
        "try{var d=fs[k].contentDocument;"
        "if(d){var r2=findIn(d);if(r2!=='NOFORM'&&r2!=='NOSUBMIT')return r2;}}catch(e){}"
        "}"
        "}"
        "return r;"
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

// Dumps the structure of a page that keeps reporting NOFORM: title, inputs,
// buttons, and iframes (including whether each iframe is reachable).
static NSString * const LNDiagnoseScript =
    @"(function(){"
    "function describe(root){"
    "var out=[];"
    "var inputs=root.querySelectorAll('input');"
    "out.push('inputs='+inputs.length);"
    "for(var i=0;i<inputs.length&&i<8;i++){"
    "out.push(' input['+i+'] type='+(inputs[i].getAttribute('type')||'?')+' name='+(inputs[i].name||'')+' id='+(inputs[i].id||''));"
    "}"
    "var bs=root.querySelectorAll('button');"
    "out.push('buttons='+bs.length);"
    "for(var j=0;j<bs.length&&j<5;j++){"
    "out.push(' button['+j+'] '+(bs[j].textContent||'').replace(/\\s+/g,' ').substring(0,40));"
    "}"
    "return out;"
    "}"
    "var lines=[];"
    "lines.push('TITLE='+(document.title||'').substring(0,80));"
    "lines=lines.concat(describe(document));"
    "var fs=document.querySelectorAll('iframe');"
    "lines.push('iframes='+fs.length);"
    "for(var k=0;k<fs.length&&k<5;k++){"
    "lines.push(' iframe['+k+'] src='+(fs[k].getAttribute('src')||'').substring(0,100));"
    "try{var d=fs[k].contentDocument;"
    "if(d&&d.body){lines=lines.concat(describe(d).map(function(s){return ' IFRAME '+s;}));}"
    "else{lines.push(' iframe['+k+'] same-origin but empty');}}"
    "catch(e){lines.push(' iframe['+k+'] cross-origin');}"
    "}"
    "return lines.join(' | ');"
    "})()";

// Finds where an interstitial ("please wait while we transfer you…") page
// wants to send the browser next: a meta-refresh URL, or a link mentioning
// NewsBank / continue / click here. Returns an absolute URL or ''.
static NSString * const LNTransferTargetScript =
    @"(function(){"
    "function abs(u){var a=document.createElement('a');a.href=u;return a.href;}"
    "var m=document.querySelector('meta[http-equiv=refresh]');"
    "if(m){var c=(m.getAttribute('content')||'');"
    "var i=c.toLowerCase().indexOf('url=');"
    "if(i>=0)return abs(c.substring(i+4).replace(/['\"]/g,'').trim());}"
    "var links=document.querySelectorAll('a[href]');"
    "for(var i=0;i<links.length;i++){"
    "var l=(links[i].getAttribute('href')||'');"
    "var lt=((links[i].textContent||'')+' '+l).toLowerCase();"
    "if(l.indexOf('newsbank')>=0||lt.indexOf('newsbank')>=0||lt.indexOf('continue')>=0||lt.indexOf('click here')>=0){"
    "if(l.indexOf('javascript')!==0)return abs(l);"
    "}"
    "}"
    "return '';"
    "})()";

// Returns the src of the first iframe that looks like an embedded auth/login
// widget, or an empty string.
static NSString * const LNEmbeddedAuthFrameScript =
    @"(function(){"
    "var fs=document.querySelectorAll('iframe');"
    "for(var i=0;i<fs.length;i++){"
    "var s=(fs[i].getAttribute('src')||'');"
    "var l=s.toLowerCase();"
    "if(l.indexOf('http')===0&&(l.indexOf('auth')>=0||l.indexOf('login')>=0||l.indexOf('athens')>=0))return s;"
    "}"
    "return '';"
    "})()";

#pragma mark - Auth web view controller

@interface AuthWebViewController () <UIWebViewDelegate>

@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, assign) LNAuthStep step;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger submissionsThisPage;
@property (nonatomic, assign) NSInteger userSubmittedThisPage;
@property (nonatomic, assign) NSInteger noFormTicks;
@property (nonatomic, assign) NSInteger totalSubmissions;
@property (nonatomic, strong) NSString *lastFullSubmitHost;
@property (nonatomic, copy) NSString *lastProbeResult;
@property (nonatomic, assign) BOOL rescueNavigated;
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
    [_pollTimer invalidate];
    _webView.delegate = nil;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Leaving this screen (failure pop or manual back) stops the automation.
    [_timeoutTimer invalidate];
    [_pollTimer invalidate];
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
    // login page): fill and submit whatever login step it shows, polling as
    // SPA pages render their forms after load.
    if (_step == LNAuthStepAwaitLoginForm || _step == LNAuthStepAwaitNewsBank) {
        [self startLoginHandling];
    }
}

// Called once per page load on a non-NewsBank page: probe immediately, then
// keep polling while the page may still be building its form (SPA two-step
// login: username first, password appears in place afterwards).
- (void)startLoginHandling {
    [_pollTimer invalidate];

    // If a page we already fully submitted comes back as a fresh load, the
    // credentials were rejected (e.g. the catalog login reappearing).
    NSString *host = _webView.request.mainDocumentURL.host.lowercaseString;
    if (_step == LNAuthStepAwaitNewsBank &&
        _lastFullSubmitHost != nil &&
        [host isEqualToString:_lastFullSubmitHost]) {
        [self failWithReason:@"The site did not accept the username or password."
                      detail:nil];
        return;
    }

    _submissionsThisPage = 0;
    _userSubmittedThisPage = 0;
    _noFormTicks = 0;
    _lastProbeResult = nil;

    // Schedule the poll BEFORE the immediate probe: the probe can complete a
    // login and invalidate the timer, which is only meaningful if it exists.
    if (_step == LNAuthStepAwaitLoginForm || _step == LNAuthStepAwaitNewsBank) {
        _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                      target:self
                                                    selector:@selector(loginProbeTick)
                                                    userInfo:nil
                                                     repeats:YES];
    }
    [self loginProbeTick];
}

- (void)loginProbeTick {
    if (_step != LNAuthStepAwaitLoginForm && _step != LNAuthStepAwaitNewsBank) {
        [_pollTimer invalidate];
        return;
    }
    if (_submissionsThisPage >= 2 || _userSubmittedThisPage >= 1) {
        return;  // done what this page allows; wait for navigation
    }

    NSString *result = [self runScript:LNCredentialProbeScript(_username, _password)] ?: @"";
    BOOL submitted = [result hasPrefix:@"SUBMITTED"];
    if (!submitted && [result isEqualToString:_lastProbeResult]) {
        [self handleQuietTick];
        return;  // page state unchanged
    }
    NSLog(@"[auth] form probe: %@", result);
    _lastProbeResult = result;

    if (submitted) {
        _submissionsThisPage++;

        NSArray *parts = [result componentsSeparatedByString:@":"];
        NSString *kind = parts.count > 2 ? parts[1] : @"";
        if ([kind isEqualToString:@"user"]) {
            // Two-step login: the password step should appear on this same
            // page shortly, so keep polling.
            _userSubmittedThisPage = 1;
        } else {
            // A full credential set was sent; stop until the next page.
            [_pollTimer invalidate];
            if ([kind isEqualToString:@"both"]) {
                _lastFullSubmitHost =
                    _webView.request.mainDocumentURL.host.lowercaseString;
            }
        }
        [self setStep:LNAuthStepAwaitNewsBank];

        _totalSubmissions++;
        if (_totalSubmissions >= LNMaxTotalSubmissions) {
            [self failWithReason:@"Too many sign-in attempts; giving up."
                          detail:nil];
        }
    } else {
        _noFormTicks = 0;
    }
}

// The page keeps reporting no usable form. After a few ticks, look for the
// interstitial's own redirect target and follow it (their hand-off JavaScript
// often cannot run on iOS 9), dump the page structure for diagnosis, and if
// the login form lives in a cross-origin iframe we cannot inject into,
// navigate the main frame there.
- (void)handleQuietTick {
    _noFormTicks++;
    if (_noFormTicks != 4) {
        return;
    }

    NSString *dump = [self runScript:LNDiagnoseScript] ?: @"";
    NSLog(@"[auth] login page diagnostics: %@", dump);

    if (_rescueNavigated) {
        return;
    }

    NSString *target = [self runScript:LNTransferTargetScript] ?: @"";
    if (target.length > 0) {
        NSURL *url = [NSURL URLWithString:target];
        if (url) {
            NSLog(@"[auth] interstitial redirect target, following: %@", target);
            _rescueNavigated = YES;
            [_webView loadRequest:[NSURLRequest requestWithURL:url]];
            return;
        }
    }

    NSString *src = [self runScript:LNEmbeddedAuthFrameScript] ?: @"";
    if (src.length == 0) {
        return;
    }
    NSURL *frameURL = [NSURL URLWithString:src];
    NSURL *current = _webView.request.mainDocumentURL;
    if (frameURL && current &&
        ![frameURL.host.lowercaseString isEqualToString:current.host.lowercaseString]) {
        NSLog(@"[auth] login form seems to be an embedded frame; opening it directly");
        _rescueNavigated = YES;
        [_webView loadRequest:[NSURLRequest requestWithURL:frameURL]];
    }
}

- (void)handleNewsBankPage {
    NSString *result = nil;
    NSLog(@"[auth] NewsBank page at step %ld", (long)_step);
    [_pollTimer invalidate];

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
            [_pollTimer invalidate];
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
    [_pollTimer invalidate];

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
