#import "AuthWebViewController.h"
#import "Models.h"

// The fixed KCLS entry point. The url= parameter is the NewsBank landing page,
// percent-encoded as the redirector expects.
static NSString * const LNRedirectorURLString =
    @"https://go.openathens.net/redirector/kcls.org"
    @"?url=https%3A%2F%2Finfoweb.newsbank.com%2Fapps%2Fnews%2F%3Fp%3DNewsBank";

static const NSTimeInterval LNStepTimeoutSeconds = 60.0;
static const NSInteger LNMaxTotalSubmissions = 5;

// How many 1.5 s polls a NewsBank step waits for its page to appear before it
// gives up (a JS-rendered page gets several seconds; a blank page fails).
static const NSInteger LNNewsBankMaxAttempts = 8;

// The image edition of the Seattle Times, reached directly through the
// OpenAthens proxy. This is the "Format: Image" product in the Seattle Times
// Collection table (code STS2S-EEDT, 2018-Current); STIW is the text edition.
// Navigating here directly avoids depending on the intermediate pages.
static NSString * const LNImageEditionURLString =
    @"https://infoweb-newsbank-com.us1.proxy.openathens.net/apps/news/browse-pub"
    @"?p=NewsBank&t=pubname%3ASTS2S-EEDT%21Seattle%2BTimes%252C%2BThe%2B%2528WA%2529"
    @"&action=browse";

// What the flow is waiting for. Each step names the page that must appear
// next; the timeout applies per step.
typedef NS_ENUM(NSInteger, LNAuthStep) {
    LNAuthStepAwaitLoginForm,      // redirector loaded; looking for the login form
    LNAuthStepAwaitNewsBank,       // credentials submitted; waiting for NewsBank
    LNAuthStepAwaitImageEdition,   // NewsBank reached; open the image edition
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
// password step that appears in place), and SAML POST hand-off pages (hidden
// SAMLResponse/RelayState inputs that the page's own JS would auto-submit; on
// iOS 9 that JS does not run, so we submit the form ourselves). Returns:
//   NOFORM                                - nothing actionable on the page
//   NOSUBMIT                              - fields found but no way to submit
//   SUBMITTED:both|user|pass|saml:how     - form sent (which fields, and how)
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
        "var saml=document.querySelector('input[name=SAMLResponse]');"
        "if(saml){"
        "var sf=saml.form||document.querySelector('form');"
        "if(sf){sf.submit();return 'SUBMITTED:saml';}"
        "}"
        "}"
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
        "return 'CLICKED:'+(a.getAttribute('href')||'').substring(0,110);"
        "}"
        "}"
        "for(var k=0;k<links.length&&k<25;k++){"
        "var b=links[k];"
        "var bt=(b.textContent||'').replace(/\\s+/g,' ').substring(0,50);"
        "dump.push(bt+' => '+(b.getAttribute('href')||'').substring(0,90));"
        "}"
        "return 'NOTFOUND T:'+(document.title||'').substring(0,50)+' A:'+links.length+' X:'+((document.body&&document.body.innerText)||'').replace(/\\s+/g,' ').substring(0,120)+'\\n'+dump.join('\\n');"
        "})()",
        LNJavaScriptString([term lowercaseString])];
}

// Clicks the "Image" format edition in the Seattle Times Collection table.
// Finds the absolute URL of the Seattle Times image edition on the collection
// page. The collection page is a table (Source | Dates | Location | Type |
// Format | Language) with two rows both named "Seattle Times, The (WA)" — the
// image edition is the one whose href carries the STS2S-EEDT code (the other,
// STIW, is the text edition), or whose Format cell says "Image". Returns
// 'URL:<absolute>' on success, else 'NOTFOUND' plus a diagnostic dump.
static NSString * const LNImageEditionURLScript =
    @"(function(){"
    "function abs(p){var x=document.createElement('a');x.href=p;return x.href;}"
    "var links=document.querySelectorAll('a[href*=browse-pub]');"
    "for(var k=0;k<links.length;k++){"
    "var h=links[k].getAttribute('href')||'';"
    "if(h.indexOf('STS2S-EEDT')>=0)return 'URL:'+abs(h);"
    "}"
    "var rows=document.querySelectorAll('tr');"
    "for(var i=0;i<rows.length;i++){"
    "var a=rows[i].querySelector('a[href*=\"browse-pub\"]');"
    "if(!a)continue;"
    "var cells=rows[i].querySelectorAll('td');"
    "for(var j=0;j<cells.length;j++){"
    "var c=(cells[j].textContent||'').replace(/\\s+/g,' ').trim().toLowerCase();"
    "if(c==='image')return 'URL:'+abs(a.getAttribute('href')||'');"
    "}"
    "}"
    "var dump=[];"
    "var all=document.querySelectorAll('a[href]');"
    "for(var m=0;m<all.length&&m<25;m++){"
    "dump.push(((all[m].textContent||'').replace(/\\s+/g,' ').substring(0,40))+' => '+((all[m].getAttribute('href')||'').substring(0,80)));"
    "}"
    "return 'NOTFOUND T:'+(document.title||'').substring(0,50)+' A:'+all.length+' X:'+((document.body&&document.body.innerText)||'').replace(/\\s+/g,' ').substring(0,200)+'\\n'+dump.join('\\n');"
    "})()";

// Finds the absolute URL of the issue on the publication page's "View Recent
// Issues" list whose text matches the target date (yyyy-MM-dd). Links point at
// issue-browse with a mody:MMDD parameter and format=image. Only links whose
// text is a full date count. Returns 'URL:<absolute>' or 'NOTFOUND'+dump.
static NSString *LNPickIssueURLScriptForDate(NSString *targetDate) {
    return [NSString stringWithFormat:
        @"(function(){"
        "function abs(p){var x=document.createElement('a');x.href=p;return x.href;}"
        "var target='%@';"
        "var monthNames={jan:0,feb:1,mar:2,apr:3,may:4,jun:5,jul:6,aug:7,sep:8,oct:9,nov:10,dec:11};"
        "var tp=target.split('-');"
        "var ty=parseInt(tp[0],10),tm=parseInt(tp[1],10),td=parseInt(tp[2],10);"
        "var links=document.querySelectorAll('a[href*=issue-browse]');"
        "var dump=[];"
        "for(var i=0;i<links.length;i++){"
        "var a=links[i];"
        "var raw=a.getAttribute('href')||'';"
        "var href=decodeURIComponent(raw);"
        "if(href.indexOf('format=image')<0)continue;"
        "var txt=(a.textContent||'').replace(/\\s+/g,' ').trim();"
        "var dm=txt.match(/([a-z]+)\\s+(\\d{1,2}),?\\s+(\\d{4})/i);"
        "if(!dm)continue;"
        "dump.push(txt.substring(0,40)+' => '+raw.substring(0,90));"
        "var mn=dm[1].toLowerCase().substring(0,3);"
        "var d=parseInt(dm[2],10),y=parseInt(dm[3],10);"
        "if(monthNames[mn]===undefined)continue;"
        "if(y===ty&&monthNames[mn]+1===tm&&d===td)return 'URL:'+abs(raw);"
        "}"
        "return 'NOTFOUND T:'+(document.title||'').substring(0,50)+' A:'+document.querySelectorAll('a').length+' X:'+((document.body&&document.body.innerText)||'').replace(/\\s+/g,' ').substring(0,180)+'\\n'+dump.slice(0,25).join('\\n');"
        "})()",
        LNJavaScriptString(targetDate)];
}

// Picks the most recent issue from the publication page's "View Recent Issues"
// list (no target date). Returns 'URL:<absolute>' or 'NOTFOUND'+dump.
static NSString *LNPickIssueURLScriptLatest(void) {
    return [NSString stringWithFormat:
        @"(function(){"
        "function abs(p){var x=document.createElement('a');x.href=p;return x.href;}"
        "var links=document.querySelectorAll('a[href*=issue-browse]');"
        "var best=null;"
        "var bestMody=-1;"
        "var dateRe=/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.? \\d{1,2},? \\d{4}/i;"
        "var dump=[];"
        "for(var i=0;i<links.length;i++){"
        "var a=links[i];"
        "var raw=a.getAttribute('href')||'';"
        "var href=decodeURIComponent(raw);"
        "if(href.indexOf('format=image')<0)continue;"
        "var m=href.match(/mody:(\\d{4})/);"
        "if(!m)continue;"
        "var txt=(a.textContent||'').replace(/\\s+/g,' ').trim();"
        "dump.push(txt.substring(0,40)+' => '+raw.substring(0,90));"
        "if(!dateRe.test(txt))continue;"
        "var mody=parseInt(m[1],10);"
        "if(mody>bestMody){bestMody=mody;best=raw;}"
        "}"
        "if(!best)return 'NOTFOUND T:'+(document.title||'').substring(0,50)+' A:'+document.querySelectorAll('a').length+' X:'+((document.body&&document.body.innerText)||'').replace(/\\s+/g,' ').substring(0,180)+'\\n'+dump.slice(0,25).join('\\n');"
        "return 'URL:'+abs(best);"
        "})()"];
}

// On the document-view viewer page, extracts the page-1 image URL and the
// "Next Page" link so the app can download pages one at a time. Returns a JSON
// object: {"image":"<url>","nextPage":"<url>"}.
static NSString * const LNDownloadPageScript =
    @"(function(){"
    "var result={image:'',nextPage:''};"
    "var imgs=document.querySelectorAll('img');"
    "for(var i=0;i<imgs.length;i++){"
    "var src=imgs[i].src||'';"
    "var w=imgs[i].width||0;"
    "var h=imgs[i].height||0;"
    "if(w>200&&h>200&&src.indexOf('document-view')<0){result.image=src;break;}"
    "}"
    "if(!result.image){"
    "for(var i=0;i<imgs.length;i++){"
    "var src=imgs[i].src||'';"
    "if(src.indexOf('document-view')>=0){result.image=src;break;}"
    "}"
    "}"
    "var links=document.querySelectorAll('a');"
    "for(var i=0;i<links.length;i++){"
    "var text=(links[i].textContent||'').toLowerCase();"
    "var href=links[i].href||'';"
    "if((text.indexOf('next page')>=0||text==='next page')&&href.length>0){"
    "result.nextPage=href;break;"
    "}"
    "}"
    "return JSON.stringify(result);"
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
@property (nonatomic, copy) NSString *lastHandledURLString;
@property (nonatomic, assign) NSInteger attempts;
@property (nonatomic, assign) BOOL navigationPending;
@property (nonatomic, assign) BOOL rescueNavigated;
@property (nonatomic, assign) BOOL started;

@end

@implementation AuthWebViewController

- (instancetype)initWithUsername:(NSString *)username
                        password:(NSString *)password
                       targetDate:(NSString *)targetDate {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _username = [username copy];
        _password = [password copy];
        _targetDate = [targetDate copy];
        _step = LNAuthStepAwaitLoginForm;
        _pageImageURLs = [NSMutableArray array];
        _downloadSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
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
    // Run the auth + download flow in the background; the user never sees it.
    _webView.hidden = YES;
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
        case LNAuthStepAwaitImageEdition:
            return @"Opening the Seattle Times image edition…";
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
    // UIWebView fires didFinishLoad for subframes too; the step machine must
    // only run once per main-document page. A duplicate event for a page we
    // already handled is skipped unless a click/submit started a navigation.
    NSString *currentURL = _webView.request.mainDocumentURL.absoluteString ?: @"";
    if (!_navigationPending && [_lastHandledURLString isEqualToString:currentURL]) {
        return;
    }
    _navigationPending = NO;
    _lastHandledURLString = [currentURL copy];

    // While downloading pages, route page loads to the download handler.
    if (_downloadActive) {
        [self downloadTick];
        return;
    }

    if (_step == LNAuthStepDone) {
        return;
    }
    [self resetTimeout];
    _attempts = 0;

    NSString *host = _webView.request.mainDocumentURL.host.lowercaseString;
    NSLog(@"[auth] page loaded (step %ld): %@", (long)_step, currentURL);

    // Authenticated NewsBank pages are served through the OpenAthens proxy
    // domain (infoweb-newsbank-com.us1.proxy.openathens.net), so match on
    // "newsbank" rather than "newsbank.com".
    BOOL isNewsBank = [host containsString:@"newsbank"];

    if (isNewsBank) {
        if (_step == LNAuthStepAwaitLoginForm || _step == LNAuthStepAwaitNewsBank) {
            [self setStep:LNAuthStepAwaitImageEdition];
        }
        if (_step == LNAuthStepAwaitIssueClick &&
            [self isImageViewerURL:currentURL]) {
            NSLog(@"[auth] image viewer reached; automation complete");
            [self setStep:LNAuthStepDone];
            [_timeoutTimer invalidate];
            [_pollTimer invalidate];
            return;
        }
        [self startStepPolling];
        return;
    }

    // Any other host (OpenAthens redirector, OpenAthens login, a library-hosted
    // login page): fill and submit whatever login step it shows, polling as
    // SPA pages render their forms after load.
    if (_step == LNAuthStepAwaitLoginForm || _step == LNAuthStepAwaitNewsBank) {
        [self startLoginHandling];
    }
}

// The image-edition viewer is the issue-browse or document-view URL with
// format=image (the site renders issue-browse as document-view).
- (BOOL)isImageViewerURL:(NSString *)urlString {
    NSString *lower = urlString.lowercaseString;
    return [lower containsString:@"format=image"] &&
           ([lower containsString:@"document-view"] || [lower containsString:@"issue-browse"]);
}

- (void)loadAbsoluteURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        [self failWithReason:@"The site returned a link the app could not open."
                      detail:urlString];
        return;
    }
    [_webView loadRequest:[NSURLRequest requestWithURL:url]];
}

// Called once per page load on a non-NewsBank page: probe immediately, then
// keep polling while the page may still be building its form (SPA two-step
// login: username first, password appears in place afterwards).
- (void)startLoginHandling {
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
    [self startStepPolling];
}

// (Re)starts the 1.5 s poll that drives the current step, then probes once
// immediately. The timer is scheduled before the immediate probe so that a
// probe which finishes the step can invalidate a timer that actually exists.
- (void)startStepPolling {
    [_pollTimer invalidate];
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                  target:self
                                                selector:@selector(probeTick)
                                                userInfo:nil
                                                 repeats:YES];
    [self probeTick];
}

- (void)probeTick {
    switch (_step) {
        case LNAuthStepAwaitLoginForm:
        case LNAuthStepAwaitNewsBank:
            [self loginTick];
            break;
        case LNAuthStepAwaitImageEdition:
        case LNAuthStepAwaitIssueClick:
            [self newsbankTick];
            break;
        case LNAuthStepDone:
            [_pollTimer invalidate];
            break;
    }
}

- (void)loginTick {
    if (_step != LNAuthStepAwaitLoginForm && _step != LNAuthStepAwaitNewsBank) {
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
        _navigationPending = YES;

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
            _navigationPending = YES;
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
        _navigationPending = YES;
        [_webView loadRequest:[NSURLRequest requestWithURL:frameURL]];
    }
}

// Drives the NewsBank steps. Runs every 1.5 s (and once when a page loads), so
// a page whose content appears late still works, and a page that never shows
// the expected content fails with a diagnostic dump instead of hanging.
- (void)newsbankTick {
    if (_navigationPending) {
        return;  // a navigation is in flight; wait for it to land
    }

    NSString *urlString = _webView.request.mainDocumentURL.absoluteString ?: @"";
    if ([self isImageViewerURL:urlString] && !_downloadActive) {
        NSLog(@"[auth] image viewer reached; starting download");
        [self startDownload];
        return;
    }

    NSString *result = @"";
    NSString *target = nil;

    if (_step == LNAuthStepAwaitImageEdition) {
        // Prefer the collection page: read the image-edition URL straight from
        // it and navigate there directly (no reliance on clicking).
        result = [self runScript:LNImageEditionURLScript] ?: @"";
        if ([result hasPrefix:@"URL:"]) {
            target = [result substringFromIndex:4];
            NSLog(@"[auth] image edition URL: %@", target);
            [self setStep:LNAuthStepAwaitIssueClick];
        } else {
            // Not on the collection page yet: on the NewsBank landing page the
            // way in is the "Seattle Times Collection" link.
            NSString *click = [self runScript:LNClickLinkScript(@"seattle times")] ?: @"";
            if ([click hasPrefix:@"CLICKED"]) {
                NSLog(@"[auth] clicked Seattle Times Collection: %@", click);
                _navigationPending = YES;
                _attempts = 0;
                return;  // wait for the collection page
            }
            // Blank or unrecognised page: after a few tries, fall back to the
            // known image-edition URL.
            _attempts++;
            if (_attempts >= 3) {
                NSLog(@"[auth] falling back to direct image-edition URL");
                target = LNImageEditionURLString;
                [self setStep:LNAuthStepAwaitIssueClick];
            } else {
                return;
            }
        }
    } else {  // LNAuthStepAwaitIssueClick
        // Pick the issue matching the target date, or the most recent if no
        // date was specified.
        NSString *pickScript;
        if (_targetDate != nil) {
            pickScript = LNPickIssueURLScriptForDate(_targetDate);
        } else {
            pickScript = LNPickIssueURLScriptLatest();
        }
        result = [self runScript:pickScript] ?: @"";
        if ([result hasPrefix:@"URL:"]) {
            target = [result substringFromIndex:4];
            NSLog(@"[auth] issue URL: %@", target);
        } else {
            _attempts++;
            if (_attempts >= LNNewsBankMaxAttempts) {
                [self failWithReason:_targetDate != nil
                              ? [NSString stringWithFormat:@"Could not find the issue for %@.", _targetDate]
                              : @"Could not find the latest issue link."
                              detail:result];
            }
            return;
        }
    }

    if (target.length > 0) {
        _navigationPending = YES;
        _attempts = 0;
        [self loadAbsoluteURL:target];
    }
}

#pragma mark - Failure

- (void)failWithReason:(NSString *)reason detail:(NSString *)detail {
    // Do not pop back to the logon screen on failure. Stay in the web view so
    // the user can see what happened and either retry the current step or
    // dismiss the alert and remain where they are.
    if (_step == LNAuthStepDone) {
        return;
    }
    NSString *failURL = _webView.request.mainDocumentURL.absoluteString ?: @"(nil)";
    NSLog(@"[auth] FAILED (step %ld): %@ | url: %@ | detail: %@",
          (long)_step, reason, failURL, detail ?: @"(none)");
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
        [UIAlertController alertControllerWithTitle:@"Flow stopped"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Retry"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self retryCurrentStep];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Re-arm the current step and poll again instead of giving up.
- (void)retryCurrentStep {
    _attempts = 0;
    [self resetTimeout];
    [self startStepPolling];
}

#pragma mark - Download pipeline

// Called when the image viewer (document-view with format=image) is reached.
// Starts downloading page images one at a time.
- (void)startDownload {
    _downloadActive = YES;
    [_pollTimer invalidate];
    [_timeoutTimer invalidate];

    // Extract issue info from the viewer URL.
    NSString *urlString = _webView.request.mainDocumentURL.absoluteString ?: @"";
    _issueTitle = @"Seattle Times, The (WA)";
    _issueDateText = _targetDate ?: @"";
    NSDate *issueDate = nil;
    if (_issueDateText.length > 0) {
        issueDate = LNParseDate(_issueDateText);
    }
    if (issueDate == nil) {
        issueDate = [NSDate date];
    }

    // Build issue ID: STS2S-EEDT-YYYY-MM-DD
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd";
    _issueIDString = [NSString stringWithFormat:@"STS2S-EEDT-%@", [df stringFromDate:issueDate]];
    _nextDownloadPage = 1;
    _downloadRetries = 0;

    NSLog(@"[auth] download starting for issue %@", _issueIDString);

    [self downloadTick];
}

// Called when a page finishes loading during the download phase. Extracts the
// page image and next-page link, downloads the image, and either navigates to
// the next page or finishes.
- (void)downloadTick {
    NSString *result = [self runScript:LNDownloadPageScript] ?: @"";
    NSLog(@"[auth] download page extract: %@", result);

    NSData *jsonData = [result dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
    if (![info isKindOfClass:[NSDictionary class]]) {
        info = @{};
    }

    NSString *imageURL = info[@"image"] ?: @"";
    NSString *nextPage = info[@"nextPage"] ?: @"";

    if (imageURL.length > 0 && nextPage.length > 0) {
        // Found both page image and next-page link: download image, advance.
        _downloadRetries = 0;
        [self downloadImageAtURLString:imageURL];
        NSURL *url = [NSURL URLWithString:nextPage];
        if (url) {
            _navigationPending = YES;
            [_webView loadRequest:[NSURLRequest requestWithURL:url]];
            return;
        }
        // No next page link but we have the image: last page.
        [self finishDownload];
        return;
    }

    if (imageURL.length > 0) {
        // Found image but no next-page link: last page.
        _downloadRetries = 0;
        [self downloadImageAtURLString:imageURL];
        [self finishDownload];
        return;
    }

    if (nextPage.length > 0) {
        // Found next-page link but image not rendered yet: retry before
        // advancing, so we don't skip a page.
        _downloadRetries++;
        if (_downloadRetries < 4) {
            NSLog(@"[auth] download: next page found, waiting for image (retry %ld)", (long)_downloadRetries);
            [self startDownloadRetryTimer];
            return;
        }
        // Retries exhausted: advance without this page's image.
        _downloadRetries = 0;
        NSURL *url = [NSURL URLWithString:nextPage];
        if (url) {
            _navigationPending = YES;
            [_webView loadRequest:[NSURLRequest requestWithURL:url]];
            return;
        }
        [self finishDownload];
        return;
    }

    // Nothing found at all: retry.
    _downloadRetries++;
    if (_downloadRetries < 4) {
        NSLog(@"[auth] download: nothing usable yet (retry %ld)", (long)_downloadRetries);
        [self startDownloadRetryTimer];
        return;
    }

    // No more pages (or retries exhausted): save the issue to disk.
    [self finishDownload];
}

// Schedules a re-check of the current page after a short delay, in case the
// page image or next-page link is still rendering.
- (void)startDownloadRetryTimer {
    [_downloadRetryTimer invalidate];
    _downloadRetryTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           target:self
                                                         selector:@selector(downloadRetryTick)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)downloadRetryTick {
    [self downloadTick];
}

// Downloads a single page image from the given URL string.
- (void)downloadImageAtURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        NSLog(@"[auth] download: invalid image URL: %@", urlString);
        [self finishDownload];
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSInteger pageNumber = _nextDownloadPage++;
    NSURLSessionDataTask *task = [_downloadSession dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error != nil || data == nil) {
            NSLog(@"[auth] download image failed for page %ld: %@", (long)pageNumber, error ?: @"no data");
            return;
        }

        // Determine file extension from MIME type or URL.
        NSString *extension = @"jpg";
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSString *mime = [(NSHTTPURLResponse *)response allHeaderFields][@"Content-Type"] ?: @"";
            if ([mime hasPrefix:@"image/png"]) extension = @"png";
            else if ([mime hasPrefix:@"image/jpeg"]) extension = @"jpg";
            else if ([mime hasPrefix:@"image/tiff"]) extension = @"tiff";
        }

        NSString *fileName = [NSString stringWithFormat:@"%03ld.%@", (long)pageNumber, extension];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsPath = paths.firstObject;
        NSString *issueDir = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"NewsFiles/%@", _issueIDString]];
        NSString *pagesDir = [issueDir stringByAppendingPathComponent:@"pages"];
        NSString *filePath = [pagesDir stringByAppendingPathComponent:fileName];

        // Create directories if needed.
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:pagesDir withIntermediateDirectories:YES attributes:nil error:NULL];

        if ([data writeToFile:filePath atomically:YES]) {
            NSURL *fileURL = [NSURL fileURLWithPath:filePath];
            dispatch_async(dispatch_get_main_queue(), ^{
                [_pageImageURLs addObject:fileURL];
                NSLog(@"[auth] downloaded page %ld -> %@", (long)pageNumber, filePath);
            });
        } else {
            NSLog(@"[auth] failed to write page image: %@", filePath);
        }
    }];
    [task resume];
}

// Saves the issue metadata (issue.json) and finishes the download.
- (void)finishDownload {
    _downloadActive = NO;
    [_downloadRetryTimer invalidate];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = paths.firstObject;
    NSString *issueDir = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"NewsFiles/%@", _issueIDString]];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:issueDir withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:[issueDir stringByAppendingPathComponent:@"articles"] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:[issueDir stringByAppendingPathComponent:@"ocr"] withIntermediateDirectories:YES attributes:nil error:NULL];

    // Build page entries.
    NSMutableArray *pageEntries = [NSMutableArray array];
    for (NSInteger i = 0; i < _pageImageURLs.count; i++) {
        NSURL *url = _pageImageURLs[i];
        [pageEntries addObject:[NSString stringWithFormat:@"pages/%03ld.%@", (long)(i + 1), url.pathExtension]];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd";

    NSDictionary *manifest = @{
        @"id": _issueIDString,
        @"title": _issueTitle ?: @"Seattle Times, The (WA)",
        @"subtitle": @"Image Edition",
        @"date": _issueDateText ?: [df stringFromDate:[NSDate date]],
        @"pages": pageEntries
    };

    NSError *writeError = nil;
    NSData *jsonData = [NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] options:0 error:nil];
    if (jsonData) {
        NSString *manifestPath = [issueDir stringByAppendingPathComponent:@"issue.json"];
        if (![jsonData writeToFile:manifestPath atomically:YES]) {
            writeError = [NSError errorWithDomain:@"LibraryNewspaper" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write issue.json"}];
        }
    } else {
        writeError = [NSError errorWithDomain:@"LibraryNewspaper" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize issue.json"}];
    }

    if (writeError != nil) {
        _downloadActive = NO;
        if (_onComplete) {
            _onComplete(nil, writeError);
        }
        return;
    }

    // Enforce max 5 papers: delete oldest issues beyond the limit.
    [self enforceMaxPapers];

    // Build an LNIssue for the completion callback.
    LNIssue *issue = [[LNIssue alloc] init];
    issue.issueID = _issueIDString;
    issue.directory = [NSURL fileURLWithPath:issueDir isDirectory:YES];
    issue.title = _issueTitle ?: @"Seattle Times, The (WA)";
    issue.subtitle = @"Image Edition";
    issue.dateText = _issueDateText ?: @"";
    issue.date = LNParseDate(_issueDateText) ?: [NSDate date];

    NSMutableArray *pages = [NSMutableArray array];
    for (NSInteger i = 0; i < _pageImageURLs.count; i++) {
        LNPage *page = [[LNPage alloc] init];
        page.number = i + 1;
        page.imageURL = _pageImageURLs[i];
        page.pixelWidth = 0;
        page.pixelHeight = 0;
        [pages addObject:page];
    }
    issue.pages = pages;

    NSLog(@"[auth] download complete: %ld pages saved", (long)_pageImageURLs.count);

    if (_onComplete) {
        _onComplete(issue, nil);
    }
}

// Deletes the oldest issues so that at most LHMaxPapers (5) remain on disk.
- (void)enforceMaxPapers {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = paths.firstObject;
    NSString *newsFilesDir = [documentsPath stringByAppendingPathComponent:@"NewsFiles"];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:newsFilesDir error:NULL];
    if (names == nil || names.count <= 5) {
        return;
    }

    // Load issues with their dates, sort oldest first.
    NSMutableArray *issueInfos = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *dirPath = [newsFilesDir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dirPath isDirectory:&isDir] || !isDir) continue;

        NSString *manifestPath = [dirPath stringByAppendingPathComponent:@"issue.json"];
        NSData *data = [NSData dataWithContentsOfFile:manifestPath];
        if (data == nil) continue;

        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![object isKindOfClass:[NSDictionary class]]) continue;

        NSString *dateText = object[@"date"] ?: @"";
        NSDate *date = LNParseDate(dateText) ?: [NSDate distantPast];
        [issueInfos addObject:@{@"name": name, @"date": date, @"path": dirPath}];
    }

    // Sort by date descending (newest first), keep first 5, delete the rest.
    [issueInfos sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSDate *d1 = obj1[@"date"];
        NSDate *d2 = obj2[@"date"];
        return [d2 compare:d1];
    }];

    for (NSInteger i = 5; i < issueInfos.count; i++) {
        NSString *dirPath = issueInfos[i][@"path"];
        NSError *delError = nil;
        [fm removeItemAtPath:dirPath error:&delError];
        if (delError) {
            NSLog(@"[auth] failed to delete old issue %@: %@", dirPath, delError.localizedDescription);
        } else {
            NSLog(@"[auth] deleted old issue to maintain max 5: %@", dirPath);
        }
    }
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
