#import "AuthWebViewController.h"
#import "Models.h"
#import <math.h>

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

// Reads the viewer page's own PDF settings. The site builds its "Download PDF"
// request from Drupal.settings.nbcore_pdf (template_params + options), which
// contains the exact metadata/title/openurl the server expects for this page,
// and from Drupal.settings.nbbase (docref, baseUrl, authToken). The TOC
// settings hold the page list URL and the viewer URL template used to page
// through the issue. Returning these values lets the app make the same requests
// the browser makes (see newsbank.har, entries 479 / 508 / 509).
static NSString * const LNSettingsScript =
    @"(function(){"
    "try{"
    "if(typeof Drupal==='undefined'||!Drupal.settings)return '{\"error\":\"no Drupal.settings\"}';"
    "var st=Drupal.settings;"
    "var nb=st.nbbase||{};"
    "var pdfs=st.nbcore_pdf||{};"
    "var inst=null;"
    "for(var k in pdfs){var v=pdfs[k];if(v&&v.template_params){inst=v;break;}}"
    "if(!inst)return '{\"error\":\"no nbcore_pdf settings\"}';"
    "var toc=null;"
    "for(var t in st){if(t.indexOf('tocSelect__')===0){toc=st[t];break;}}"
    "return JSON.stringify({"
    "ok:true,"
    "baseUrl:nb.baseUrl||'',"
    "docref:nb.docref||'',"
    "authToken:nb.authToken||'',"
    "sitelinksREM:nb.sitelinksREM||'nbnews_drupal',"
    "theme:inst.theme||'',"
    "templateParams:inst.template_params||{},"
    "options:inst.options||{},"
    "tocUrl:(toc&&toc.tocUrl)?toc.tocUrl:'',"
    "destinationTemplate:(toc&&toc.destinationUrlTemplate)?toc.destinationUrlTemplate:'',"
    "metadataJSON:(inst.template_params&&inst.template_params.metadata)?JSON.stringify(inst.template_params.metadata):''"
    "});"
    "}catch(e){return JSON.stringify({error:String(e)});}"
    "})()";

#pragma mark - NewsBank XML helpers

// Parses <page docref="..." label="..."/> entries out of the image-viewer
// table of contents (nb-sitelinks/imageviewer/toc/index.xml), which lists every
// page of the issue.
@interface LNTOCParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pages;
@property (nonatomic, copy) NSString *issueID;
@end

@implementation LNTOCParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _pages = [NSMutableArray array];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)elementName
      namespaceURI:(NSString *)namespaceURI
     qualifiedName:(NSString *)qName
        attributes:(NSDictionary *)attributeDict {
    if ([elementName isEqualToString:@"toc"]) {
        NSString *issueID = attributeDict[@"source_id"];
        if (issueID.length > 0) {
            self.issueID = issueID;
        }
        return;
    }
    if (![elementName isEqualToString:@"page"]) {
        return;
    }
    NSString *docref = attributeDict[@"docref"];
    if (docref.length == 0) {
        return;
    }
    [self.pages addObject:@{ @"docref": docref,
                             @"label": attributeDict[@"label"] ?: @"" }];
}

@end

// Parses the printer-friendly image info from
// SiteLinks/imageviewer/print/index.xml: the <img> element carries the
// base64-encoded x-large image URL (encoded_src, i.e. the form's
// image_url_encoded) plus the pixel size used to compute the PDF page box.
@interface LNImageInfoParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, copy) NSString *encodedSrc;
@property (nonatomic) NSInteger imageWidth;
@property (nonatomic) NSInteger imageHeight;
@end

@implementation LNImageInfoParser

- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)elementName
      namespaceURI:(NSString *)namespaceURI
     qualifiedName:(NSString *)qName
        attributes:(NSDictionary *)attributeDict {
    if (![elementName isEqualToString:@"img"]) {
        return;
    }
    if (self.encodedSrc.length > 0) {
        return;
    }
    NSString *encoded = attributeDict[@"encoded_src"];
    if (encoded.length == 0) {
        return;
    }
    self.encodedSrc = encoded;
    self.imageWidth = [attributeDict[@"width"] integerValue];
    self.imageHeight = [attributeDict[@"height"] integerValue];
}

@end

// Percent-encodes a docref the way the site does (RFC 3986 unreserved set,
// everything else escaped: image%2Fv2%3A...%400).
static NSString *LNPercentEncode(NSString *value) {
    static NSCharacterSet *allowed = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

// The OpenURL fields carry the docref percent-encoded once, then their % signs
// escaped a second time (document_id%3Aimage%252Fv2%253A...).
static NSString *LNDoubleEncodedDocref(NSString *docref) {
    return [LNPercentEncode(docref) stringByReplacingOccurrencesOfString:@"%"
                                                              withString:@"%25"];
}

static NSString *LNBase64Encode(NSString *string) {
    return [[string dataUsingEncoding:NSUTF8StringEncoding]
               base64EncodedStringWithOptions:0] ?: @"";
}

static NSString *LNBase64Decode(NSString *base64) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (data == nil) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

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
@property (nonatomic, strong) NSDictionary *pdfSettings;
@property (nonatomic, strong) NSArray<NSDictionary *> *tocPages;
@property (nonatomic, assign) NSInteger pdfPageIndex;
@property (nonatomic, assign) NSInteger pdfPageAttempts;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL downloadFinished;

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

    // The web view is hidden, so show what the background flow is doing.
    _spinner = [[UIActivityIndicatorView alloc]
                   initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_spinner startAnimating];
    [self.view addSubview:_spinner];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont systemFontOfSize:15];
    _statusLabel.textColor = [UIColor darkGrayColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-24],

        [_statusLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:16],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];
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
    if (_statusLabel != nil) {
        _statusLabel.text = [self titleForStep:step];
    }
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

    // While downloading, the web view is no longer navigated — all page
    // fetches run through NSURLSession — so page loads are ignored here.
    if (_downloadActive) {
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
        // If we're downloading a specific date's paper, don't stop at the
        // viewer page — let newsbankTick start the download. Otherwise (browse
        // mode) stop automation here.
        if (_step == LNAuthStepAwaitIssueClick &&
            [self isImageViewerURL:currentURL] &&
            _targetDate == nil) {
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
        // Navigate directly to the image-edition (browse-pub) URL. This avoids
        // loading the intermediate collection page and clicking the
        // "Seattle Times Collection" link — we already know the URL from the
        // HAR / verified page scrape.
        target = LNImageEditionURLString;
        NSLog(@"[auth] navigating directly to image edition: %@", target);
        [self setStep:LNAuthStepAwaitIssueClick];
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
// The page itself tells us everything NewsBank's own "Download PDF" button
// sends: template_params (metadata, title, openurl, copyright…), the page
// options, and the TOC endpoint that lists every page of the issue.
- (void)startDownload {
    _downloadActive = YES;
    [_pollTimer invalidate];
    [_timeoutTimer invalidate];
    [_downloadRetryTimer invalidate];

    _currentDocumentViewURL = _webView.request.mainDocumentURL.absoluteString ?: @"";

    NSString *settingsJSON = [self runScript:LNSettingsScript] ?: @"";
    NSData *settingsData = [settingsJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *settings = nil;
    if (settingsData.length > 0) {
        id parsed = [NSJSONSerialization JSONObjectWithData:settingsData options:0 error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            settings = parsed;
        }
    }
    NSLog(@"[auth] page PDF settings: %@", settingsJSON.length > 1200
          ? [settingsJSON substringToIndex:1200] : settingsJSON);

    if (settings == nil || ![settings[@"ok"] boolValue]) {
        [self abortDownloadWithReason:@"Could not read the NewsBank PDF settings from the page."];
        return;
    }

    _pdfSettings = settings;
    _pdfPageIndex = 0;
    _pdfPageAttempts = 0;
    _nextDownloadPage = 1;
    _downloadFinished = NO;
    // A retry starts the issue over; don't mix in pages from a failed attempt.
    _pageImageURLs = [NSMutableArray array];

    NSDictionary *params = settings[@"templateParams"];
    if (![params isKindOfClass:[NSDictionary class]]) params = @{};
    NSDictionary *meta = params[@"metadata"];
    if (![meta isKindOfClass:[NSDictionary class]]) meta = @{};

    _issueTitle = LNString(meta[@"publication"]);
    if (_issueTitle.length == 0) _issueTitle = @"Seattle Times, The (WA)";

    NSDate *issueDate = nil;
    NSString *dateDisplay = LNString(meta[@"date_display"]);
    if (dateDisplay.length > 0) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        df.dateFormat = @"MMMM d, yyyy";
        issueDate = [df dateFromString:dateDisplay];
    }
    if (issueDate == nil && _targetDate.length > 0) {
        issueDate = LNParseDate(_targetDate);
    }
    if (issueDate == nil) {
        issueDate = [NSDate date];
    }

    NSDateFormatter *iso = [[NSDateFormatter alloc] init];
    iso.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    iso.dateFormat = @"yyyy-MM-dd";
    _issueDateText = [iso stringFromDate:issueDate];
    _issueIDString = [NSString stringWithFormat:@"STS2S-EEDT-%@", _issueDateText];

    NSLog(@"[auth] download starting for issue %@ (base %@)", _issueIDString,
          LNString(settings[@"baseUrl"]));

    _statusLabel.text = @"Loading the paper's page list…";
    [self fetchTableOfContents];
}

#pragma mark - Page list

// The page's validated PDF dictionaries (never NSNull).
- (NSDictionary *)pdfTemplateParams {
    NSDictionary *params = _pdfSettings[@"templateParams"];
    return [params isKindOfClass:[NSDictionary class]] ? params : @{};
}

- (NSDictionary *)pdfOptions {
    NSDictionary *options = _pdfSettings[@"options"];
    return [options isKindOfClass:[NSDictionary class]] ? options : @{};
}

- (NSString *)issueIDFromDocref:(NSString *)docref {
    // image/v2:<pbi>@NewsBank-<issueID>@<ibd>-<page>@<seq>
    NSRange marker = [docref rangeOfString:@"@NewsBank-"];
    if (marker.location == NSNotFound) {
        return @"";
    }
    NSString *rest = [docref substringFromIndex:marker.location + marker.length];
    NSRange at = [rest rangeOfString:@"@"];
    return at.location == NSNotFound ? rest : [rest substringToIndex:at.location];
}

// The TOC lists docrefs as "v2:…" while every other request uses the
// "image/"-prefixed form from Drupal.settings.nbbase.docref.
- (NSString *)fullDocrefForTOCDocref:(NSString *)tocDocref {
    if ([tocDocref hasPrefix:@"image/"]) {
        return tocDocref;
    }
    NSString *live = LNString(_pdfSettings[@"docref"]);
    NSRange v2 = [live rangeOfString:@"v2:"];
    NSString *prefix = (v2.location != NSNotFound)
        ? [live substringToIndex:v2.location] : @"image/";
    return [prefix stringByAppendingString:tocDocref];
}

// The viewer's TOC endpoint lists every page of the issue (HAR entry 479).
- (void)fetchTableOfContents {
    NSURL *base = [NSURL URLWithString:LNString(_pdfSettings[@"baseUrl"])];
    if (base.scheme.length == 0 || base.host.length == 0) {
        [self abortDownloadWithReason:@"The viewer page did not report its NewsBank host."];
        return;
    }

    NSString *tocPath = LNString(_pdfSettings[@"tocUrl"]);
    if (tocPath.length == 0) {
        NSString *docref = LNString(_pdfSettings[@"docref"]);
        NSString *auth = LNString(_pdfSettings[@"authToken"]);
        NSString *product = LNString([self pdfTemplateParams][@"p"]);
        if (product.length == 0) product = @"NewsBank";
        tocPath = [NSString stringWithFormat:
            @"/apps/news/nb-sitelinks/imageviewer/toc/index.xml"
            @"?product=%@&issueid=%@&url=%@&query=&auth=%@",
            product, [self issueIDFromDocref:docref], LNPercentEncode(docref), auth];
    }

    NSString *absolute = tocPath;
    if ([absolute hasPrefix:@"/"]) {
        absolute = [NSString stringWithFormat:@"%@://%@%@", base.scheme, base.host, absolute];
    }

    NSLog(@"[auth] page list: %@", absolute);

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:absolute]];
    request.timeoutInterval = 30.0;
    [self addAuthHeadersToRequest:request];
    [request setValue:@"application/xml, text/xml, */*; q=0.01" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    [request setValue:_currentDocumentViewURL forHTTPHeaderField:@"Referer"];

    NSURLSessionDataTask *task =
        [_downloadSession dataTaskWithRequest:request
                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error != nil || data.length == 0) {
            NSInteger status = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                status = [(NSHTTPURLResponse *)response statusCode];
            }
            NSLog(@"[auth] page list failed: status=%ld error=%@", (long)status, error ?: @"no data");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self abortDownloadWithReason:@"Could not load the paper's page list."];
            });
            return;
        }

        LNTOCParser *parser = [[LNTOCParser alloc] init];
        NSXMLParser *xml = [[NSXMLParser alloc] initWithData:data];
        xml.delegate = parser;
        [xml parse];
        NSLog(@"[auth] page list: %lu pages (issue %@)", (unsigned long)parser.pages.count,
              parser.issueID ?: @"?");

        dispatch_async(dispatch_get_main_queue(), ^{
            if (parser.pages.count == 0) {
                [self abortDownloadWithReason:@"The paper's page list was empty."];
                return;
            }
            self.tocPages = parser.pages;
            [self downloadNextPage];
        });
    }];
    [task resume];
}

#pragma mark - Page download

- (void)downloadNextPage {
    if (!_downloadActive) {
        return;
    }
    if (_pdfPageIndex >= (NSInteger)_tocPages.count) {
        [self finishDownload];
        return;
    }

    NSString *docref = [self fullDocrefForTOCDocref:
                        LNString(_tocPages[(NSUInteger)_pdfPageIndex][@"docref"])];
    NSString *label = LNString(_tocPages[(NSUInteger)_pdfPageIndex][@"label"]);
    NSInteger pageNumber = _pdfPageIndex + 1;

    _nextDownloadPage = pageNumber;
    _statusLabel.text = [NSString stringWithFormat:@"Downloading page %ld of %lu…",
                         (long)pageNumber, (unsigned long)_tocPages.count];

    NSLog(@"[auth] page %ld/%lu docref=%@", (long)pageNumber,
          (unsigned long)_tocPages.count, docref);

    [self fetchImageInfoForDocref:docref label:label pageNumber:pageNumber];
}

// Ask the site for the x-large page image: the response's encoded_src is the
// exact image_url_encoded the PDF endpoint expects, and width/height drive the
// page box (SiteLinks/imageviewer/print/index.xml in the HAR, entry 508).
- (void)fetchImageInfoForDocref:(NSString *)docref
                          label:(NSString *)label
                     pageNumber:(NSInteger)pageNumber {
    NSDictionary *options = _pdfSettings[@"options"];
    if (![options isKindOfClass:[NSDictionary class]]) options = @{};
    NSDictionary *imageOptions = options[@"image"];
    if (![imageOptions isKindOfClass:[NSDictionary class]]) imageOptions = @{};

    NSInteger widthOffset = LNInteger(imageOptions[@"widthOffset"], 50);
    NSInteger heightOffset = LNInteger(imageOptions[@"heightOffset"], 175);
    NSInteger maxWidth = LNInteger(imageOptions[@"maxWidth"], 900);
    NSString *rem = LNString(_pdfSettings[@"sitelinksREM"]);
    if (rem.length == 0) rem = @"nbnews_drupal";

    long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    NSString *urlString = [NSString stringWithFormat:
        @"%@/SiteLinks/imageviewer/print/index.xml"
        @"?ssl=true&url=%@&rem=%@&image=x-large&max_width=2600"
        @"&widthOffset=%ld&heightOffset=%ld&maxWidth=%ld&_=%lld",
        LNString(_pdfSettings[@"baseUrl"]), LNPercentEncode(docref), rem,
        (long)widthOffset, (long)heightOffset, (long)maxWidth, timestamp];

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.timeoutInterval = 60.0;
    [self addAuthHeadersToRequest:request];
    [request setValue:@"application/xml, text/xml, */*; q=0.01" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    [request setValue:[self documentViewURLForDocref:docref] forHTTPHeaderField:@"Referer"];

    NSURLSessionDataTask *task =
        [_downloadSession dataTaskWithRequest:request
                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        LNImageInfoParser *info = [[LNImageInfoParser alloc] init];
        if (error == nil && data.length > 0) {
            NSXMLParser *xml = [[NSXMLParser alloc] initWithData:data];
            xml.delegate = info;
            [xml parse];
        }

        if (info.encodedSrc.length == 0 || info.imageWidth <= 0 || info.imageHeight <= 0) {
            NSInteger status = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                status = [(NSHTTPURLResponse *)response statusCode];
            }
            NSLog(@"[auth] page %ld: image info failed (status=%ld error=%@ bytes=%lu)",
                  (long)pageNumber, (long)status, error ?: @"none", (unsigned long)data.length);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self retryOrAbortPage:pageNumber
                                reason:@"Could not read the page image details."];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.downloadActive) {
                return;
            }
            [self postPDFForPage:pageNumber
                           label:label
                          docref:docref
                       imageInfo:info
                     widthOffset:widthOffset
                    heightOffset:heightOffset];
        });
    }];
    [task resume];
}

- (NSString *)metadataJSONForPage:(NSString *)label {
    // The page already gave us the metadata serialized exactly as the server
    // expects (same key order as the HAR body); only the page label changes.
    NSString *serialized = LNString(_pdfSettings[@"metadataJSON"]);
    if (serialized.length > 0 && label.length > 0) {
        NSString *escaped = [label stringByReplacingOccurrencesOfString:@"\""
                                                             withString:@"\\\""];
        NSRegularExpression *regex =
            [NSRegularExpression regularExpressionWithPattern:@"\"page\"\\s*:\\s*\"[^\"]*\""
                                                      options:0
                                                        error:NULL];
        NSRange range = NSMakeRange(0, serialized.length);
        NSTextCheckingResult *match =
            [regex firstMatchInString:serialized options:0 range:range];
        NSString *replacement = [NSString stringWithFormat:@"\"page\":\"%@\"", escaped];
        if (match != nil) {
            return [serialized stringByReplacingCharactersInRange:match.range
                                                      withString:replacement];
        }
        return serialized;
    }

    id meta = [self pdfTemplateParams][@"metadata"];
    if ([meta isKindOfClass:[NSString class]]) {
        return meta;
    }
    NSMutableDictionary *dict = [meta isKindOfClass:[NSDictionary class]]
        ? [meta mutableCopy] : [NSMutableDictionary dictionary];
    if (label.length > 0) {
        dict[@"page"] = label;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

- (NSString *)titleForPage:(NSInteger)pageNumber {
    NSString *title = LNString([self pdfTemplateParams][@"title"]);
    NSString *pageText = [NSString stringWithFormat:@"page %ld", (long)pageNumber];
    if (title.length == 0) {
        return [NSString stringWithFormat:@"News Article - %@ - %@",
                _issueTitle ?: @"", pageText];
    }
    // NewsBank titles end with "- page N"; only that part changes per page.
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"page\\s+\\d+\\s*$"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:NULL];
    NSTextCheckingResult *match =
        [regex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
    if (match != nil) {
        return [title stringByReplacingCharactersInRange:match.range withString:pageText];
    }
    return [title stringByAppendingFormat:@" - %@", pageText];
}

- (NSString *)openURLForDocref:(NSString *)docref {
    NSString *marker = @"rft_dat=document_id%3A";
    NSString *live = LNString([self pdfTemplateParams][@"openurl"]);
    NSString *value = [marker stringByAppendingFormat:@"%@/hlterms%%3A",
                       LNDoubleEncodedDocref(docref)];
    NSRange range = [live rangeOfString:marker];
    if (range.location == NSNotFound) {
        return live ?: @"";
    }
    return [[live substringToIndex:range.location] stringByAppendingString:value];
}

// openurl_encoded is the same OpenURL against the direct NewsBank host. The
// page gives us the whole string base64-encoded, so only the docref changes.
- (NSString *)openURLEncodedForDocref:(NSString *)docref fallback:(NSString *)openURL {
    NSString *marker = @"rft_dat=document_id%3A";
    NSString *value = [marker stringByAppendingFormat:@"%@/hlterms%%3A",
                       LNDoubleEncodedDocref(docref)];
    NSString *liveEncoded = LNString([self pdfTemplateParams][@"openurl_encoded"]);
    NSString *decoded = LNBase64Decode(liveEncoded);
    if (decoded != nil) {
        NSRange range = [decoded rangeOfString:marker];
        if (range.location != NSNotFound) {
            return LNBase64Encode([[decoded substringToIndex:range.location]
                                   stringByAppendingString:value]);
        }
    }
    NSString *direct = openURL ?: @"";
    NSURL *base = [NSURL URLWithString:LNString(_pdfSettings[@"baseUrl"])];
    if (base.host.length > 0) {
        direct = [direct stringByReplacingOccurrencesOfString:base.host
                                                   withString:@"infoweb.newsbank.com"];
    }
    return LNBase64Encode(direct);
}

- (NSString *)documentViewURLForDocref:(NSString *)docref {
    NSString *template = LNString(_pdfSettings[@"destinationTemplate"]);
    if (template.length == 0) {
        return _currentDocumentViewURL ?: @"";
    }
    NSString *path = [template stringByReplacingOccurrencesOfString:@"__DOCREF__"
                                                        withString:LNPercentEncode(docref)];
    if (![path hasPrefix:@"/"]) {
        return path;
    }
    NSURL *base = [NSURL URLWithString:LNString(_pdfSettings[@"baseUrl"])];
    return [NSString stringWithFormat:@"%@://%@%@", base.scheme, base.host, path];
}

// Posts the same multipart form the browser sends (newsbank.har entry 509).
// Field order matches the HAR body exactly.
- (void)postPDFForPage:(NSInteger)pageNumber
                 label:(NSString *)label
                docref:(NSString *)docref
             imageInfo:(LNImageInfoParser *)imageInfo
           widthOffset:(NSInteger)widthOffset
          heightOffset:(NSInteger)heightOffset {
    NSDictionary *params = _pdfSettings[@"templateParams"];
    if (![params isKindOfClass:[NSDictionary class]]) params = @{};
    NSDictionary *options = _pdfSettings[@"options"];
    if (![options isKindOfClass:[NSDictionary class]]) options = @{};

    // Page geometry, exactly as getImageParams() in nbcore_pdf.js computes it:
    // millimetres at 96 dpi plus the metadata offsets, floored at 8.5x11in.
    double imageWidthMM = imageInfo.imageWidth * 25.4 / 96.0;
    double imageHeightMM = imageInfo.imageHeight * 25.4 / 96.0;
    NSInteger pdfWidth = (NSInteger)ceil(MAX(215.9, imageWidthMM + widthOffset));
    NSInteger pdfHeight = (NSInteger)ceil(MAX(279.4, imageHeightMM + heightOffset));
    NSInteger pdfWidthImage = (NSInteger)ceil(imageWidthMM);
    NSInteger pdfHeightImage = (NSInteger)ceil(imageHeightMM);

    NSString *openURL = [self openURLForDocref:docref];
    NSString *openURLEncoded = [self openURLEncodedForDocref:docref fallback:openURL];

    NSDictionary *pageOptions = options[@"page"];
    NSString *pageJSON = @"{\"orientation\":\"portrait\",\"size\":\"letter\"}";
    if ([pageOptions isKindOfClass:[NSDictionary class]]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:pageOptions options:0 error:NULL];
        if (data != nil) {
            pageJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }

    NSString *theme = LNString(params[@"theme"]);
    if (theme.length == 0) theme = LNString(_pdfSettings[@"theme"]);
    if (theme.length == 0) theme = @"gnus_pdf_print_template";

    NSString *product = LNString(params[@"p"]);
    if (product.length == 0) product = @"NewsBank";

    NSString *themePath = LNString(params[@"theme_path"]);
    if (themePath.length == 0) themePath = @"sites/all/themes/nb_gnus";

    NSString *mediaType = LNString(params[@"media_type"]);
    if (mediaType.length == 0) mediaType = @"image";

    NSArray<NSArray *> *fields = @[
        @[@"action", @"download"],
        @[@"__debugPDF", @"false"],
        @[@"__debugPDFHTML", @"false"],
        @[@"p", product],
        @[@"theme", theme],
        @[@"metadata", [self metadataJSONForPage:label]],
        @[@"body", LNString(params[@"body"]) ?: @""],
        @[@"title", [self titleForPage:pageNumber]],
        @[@"openurl", openURL],
        @[@"openurl_encoded", openURLEncoded],
        @[@"theme_path", themePath],
        @[@"copyright", LNString(params[@"copyright"]) ?: @""],
        @[@"media_type", mediaType],
        @[@"citation", @"false"],
        @[@"page", pageJSON],
        @[@"width", [NSString stringWithFormat:@"%ld", (long)pdfWidth]],
        @[@"height", [NSString stringWithFormat:@"%ld", (long)pdfHeight]],
        @[@"widthImage", [NSString stringWithFormat:@"%ld", (long)pdfWidthImage]],
        @[@"heightImage", [NSString stringWithFormat:@"%ld", (long)pdfHeightImage]],
        @[@"image_url_encoded", imageInfo.encodedSrc],
    ];

    NSString *boundary = @"----LibraryNewspaperPDFBoundary";
    NSMutableData *body = [NSMutableData data];
    for (NSArray *field in fields) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:
                           @"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", field[0]]
                          dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[(NSString *)field[1] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary]
                      dataUsingEncoding:NSUTF8StringEncoding]];

    NSString *endpoint = [NSString stringWithFormat:@"%@/nb-pdf/download",
                          LNString(_pdfSettings[@"baseUrl"])];
    NSURL *base = [NSURL URLWithString:LNString(_pdfSettings[@"baseUrl"])];

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 120.0;
    [self addAuthHeadersToRequest:request];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
   forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length]
   forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"%@://%@", base.scheme, base.host]
   forHTTPHeaderField:@"Origin"];
    [request setValue:[self documentViewURLForDocref:docref] forHTTPHeaderField:@"Referer"];
    request.HTTPBody = body;

    NSLog(@"[auth] POST PDF page %ld: %ldx%ldpt image %ldx%ldpx, body %lu bytes",
          (long)pageNumber, (long)pdfWidth, (long)pdfHeight,
          (long)imageInfo.imageWidth, (long)imageInfo.imageHeight,
          (unsigned long)body.length);

    NSURLSessionDataTask *task =
        [_downloadSession dataTaskWithRequest:request
                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = 0;
        NSString *mime = @"";
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            status = [(NSHTTPURLResponse *)response statusCode];
            mime = [(NSHTTPURLResponse *)response allHeaderFields][@"Content-Type"] ?: @"";
        }
        BOOL isPDF = (data.length >= 5 && data.bytes != NULL &&
                      memcmp(data.bytes, "%PDF-", 5) == 0);
        NSLog(@"[auth] page %ld PDF: status=%ld mime=%@ bytes=%lu valid=%d",
              (long)pageNumber, (long)status, mime, (unsigned long)data.length, (int)isPDF);

        if (error != nil || !isPDF) {
            NSLog(@"[auth] page %ld: PDF download failed: %@", (long)pageNumber,
                  error ?: @"response was not a PDF");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self retryOrAbortPage:pageNumber
                                reason:@"The PDF download did not return a PDF."];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self saveDownloadedPage:data pageNumber:pageNumber];
        });
    }];
    [task resume];
}

- (void)retryOrAbortPage:(NSInteger)pageNumber reason:(NSString *)reason {
    if (!_downloadActive) {
        return;
    }
    _pdfPageAttempts++;
    if (_pdfPageAttempts < 4) {
        NSLog(@"[auth] page %ld: retry %ld (%@)", (long)pageNumber,
              (long)_pdfPageAttempts, reason);
        _statusLabel.text = [NSString stringWithFormat:@"Retrying page %ld…", (long)pageNumber];
        __weak AuthWebViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AuthWebViewController *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf.downloadActive) {
                [strongSelf downloadNextPage];
            }
        });
        return;
    }
    [self abortDownloadWithReason:
        [NSString stringWithFormat:@"Page %ld failed: %@", (long)pageNumber, reason]];
}

- (void)saveDownloadedPage:(NSData *)data pageNumber:(NSInteger)pageNumber {
    if (![self savePageData:data pageNumber:pageNumber extension:@"pdf"]) {
        [self abortDownloadWithReason:@"Could not save the downloaded PDF."];
        return;
    }

    NSLog(@"[auth] saved page %ld (%lu bytes)", (long)pageNumber, (unsigned long)data.length);

    // Hand every page to the reader as it arrives: page 1 opens the reader, and
    // each later page extends the issue so the reader can page forward while the
    // rest of the paper keeps downloading in the background.
    if (_onComplete) {
        _onComplete([self buildIssueWithPageCount:(NSInteger)_pageImageURLs.count], nil);
    }

    _pdfPageIndex = pageNumber;
    _pdfPageAttempts = 0;
    [self downloadNextPage];
}

- (void)abortDownloadWithReason:(NSString *)reason {
    NSLog(@"[auth] download aborted: %@", reason);
    BOOL hadPages = (_pageImageURLs.count > 0);
    _downloadActive = NO;
    [_pollTimer invalidate];
    [_timeoutTimer invalidate];
    [_downloadRetryTimer invalidate];

    if (hadPages) {
        // Keep what already arrived and record the manifest.
        [self finishDownload];
        return;
    }
    if (_onComplete) {
        NSError *error =
            [NSError errorWithDomain:@"LibraryNewspaper"
                               code:3
                           userInfo:@{NSLocalizedDescriptionKey: reason ?: @"Fetch failed."}];
        _onComplete(nil, error);
    }
}

#pragma mark - Saving

// Saves one downloaded page into Documents/NewsFiles/<issue>/pages.
- (BOOL)savePageData:(NSData *)data
          pageNumber:(NSInteger)pageNumber
           extension:(NSString *)extension {
    NSString *fileName = [NSString stringWithFormat:@"%03ld.%@", (long)pageNumber, extension];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = paths.firstObject;
    NSString *issueDir = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"NewsFiles/%@", _issueIDString]];
    NSString *pagesDir = [issueDir stringByAppendingPathComponent:@"pages"];
    NSString *filePath = [pagesDir stringByAppendingPathComponent:fileName];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:pagesDir withIntermediateDirectories:YES attributes:nil error:NULL];

    if (![data writeToFile:filePath atomically:YES]) {
        NSLog(@"[auth] failed to write page: %@", filePath);
        return NO;
    }
    [_pageImageURLs addObject:[NSURL fileURLWithPath:filePath]];
    NSLog(@"[auth] page %ld -> %@ (%lu bytes)", (long)pageNumber, filePath,
          (unsigned long)data.length);
    return YES;
}

// Logs all cookies in shared storage for debugging download 503s.
- (void)logCookies {
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [storage cookies];
    NSLog(@"[auth] %ld cookies in shared storage:", cookies ? (long)cookies.count : -1);
    if (cookies) {
        for (NSHTTPCookie *cookie in cookies) {
            // Names/domains only — never log session cookie values.
            NSLog(@"[auth]   cookie: domain=%@ path=%@ name=%@",
                  cookie.domain, cookie.path, cookie.name);
        }
    }
}

// Adds the OpenAthens/NewsBank session cookies and browser-like headers to a
// request. NewsBank's download endpoint is behind AWS WAF which requires the
// cookies that the UIWebView set during the login flow (session + WAF telemetry).
- (void)addAuthHeadersToRequest:(NSMutableURLRequest *)request {
    // Add cookies from shared storage (UIWebView writes session cookies here
    // during the login flow; defaultSessionConfiguration should send them
    // automatically, but we set them explicitly to be safe on iOS 9).
    NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
    if (cookies.count > 0) {
        NSDictionary *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        for (NSString *key in cookieHeaders) {
            [request setValue:cookieHeaders[key] forHTTPHeaderField:key];
        }
    } else if (_capturedCookies && _capturedCookies.length > 0) {
        // Fallback: use Cookie header captured from UIWebView requests if
        // shared storage has no cookies (possible on iOS 9 where UIWebView
        // may not persist cookies to NSHTTPCookieStorage).
        [request setValue:_capturedCookies forHTTPHeaderField:@"Cookie"];
        NSLog(@"[auth] using captured Cookie header (%ld bytes) for download request",
              (long)_capturedCookies.length);
    }

    // Browser-like headers that NewsBank's WAF expects.
    [request setValue:@"Mozilla/5.0 (iPad; CPU OS 9_3_5 like Mac OS X) AppleWebKit/601.1 (KHTML, like Gecko) Mobile/13G36" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" forHTTPHeaderField:@"Accept"];
    [request setValue:@"en-US,en;q=0.9" forHTTPHeaderField:@"Accept-Language"];
}

// Builds an LNIssue from the downloaded pages (up to pageCount pages). Used to
// show the first page immediately while the rest continue downloading.
- (LNIssue *)buildIssueWithPageCount:(NSInteger)pageCount {
    NSMutableArray *pages = [NSMutableArray array];
    NSInteger count = MIN(pageCount, (NSInteger)_pageImageURLs.count);
    for (NSInteger i = 0; i < count; i++) {
        LNPage *page = [[LNPage alloc] init];
        page.number = i + 1;
        page.imageURL = _pageImageURLs[i];
        page.pixelWidth = 0;
        page.pixelHeight = 0;
        [pages addObject:page];
    }

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = paths.firstObject;
    NSString *issueDir = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"NewsFiles/%@", _issueIDString]];

    LNIssue *issue = [[LNIssue alloc] init];
    issue.issueID = _issueIDString;
    issue.directory = [NSURL fileURLWithPath:issueDir isDirectory:YES];
    issue.title = _issueTitle ?: @"Seattle Times, The (WA)";
    issue.subtitle = @"Image Edition";
    issue.dateText = _issueDateText ?: @"";
    issue.date = LNParseDate(_issueDateText) ?: [NSDate date];
    issue.pages = pages;
    return issue;
}

// Saves the issue metadata (issue.json) and finishes the download.
- (void)finishDownload {
    if (_downloadFinished) {
        return;
    }
    _downloadFinished = YES;
    _downloadActive = NO;
    [_downloadRetryTimer invalidate];
    [_pollTimer invalidate];
    [_timeoutTimer invalidate];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = paths.firstObject;
    NSString *issueDir = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"NewsFiles/%@", _issueIDString]];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:issueDir withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:[issueDir stringByAppendingPathComponent:@"articles"] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtPath:[issueDir stringByAppendingPathComponent:@"ocr"] withIntermediateDirectories:YES attributes:nil error:NULL];

    // Build page entries using actual filenames from downloaded URLs.
    NSMutableArray *pageEntries = [NSMutableArray array];
    for (NSURL *url in _pageImageURLs) {
        [pageEntries addObject:[NSString stringWithFormat:@"pages/%@", url.lastPathComponent]];
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

    // Build an LNIssue for the completion callback (all downloaded pages).
    LNIssue *issue = [self buildIssueWithPageCount:NSIntegerMax];

    NSLog(@"[auth] download complete: %ld pages saved", (long)_pageImageURLs.count);
    _statusLabel.text = [NSString stringWithFormat:@"Saved %ld pages.", (long)_pageImageURLs.count];
    [_spinner stopAnimating];

    // Report the full issue so the UI can update the page count and toolbar.
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

// Intercepts UIWebView requests to capture the Cookie header. NewsBank's WAF
// requires session + telemetry cookies that UIWebView sets during the login
// flow. If NSHTTPCookieStorage.sharedHTTPCookieStorage isn't populated by
// UIWebView on iOS 9, we extract cookies from outgoing requests here and
// reuse them in NSURLSession download requests.
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    NSURL *url = request.URL;
    if (url && [url.host containsString:@"newsbank"]) {
        NSString *cookieHeader = [request valueForHTTPHeaderField:@"Cookie"];
        if (cookieHeader && cookieHeader.length > 0) {
            if (!_capturedCookies) {
                _capturedCookies = [NSMutableString string];
            }
            if (![_capturedCookies isEqualToString:cookieHeader]) {
                _capturedCookies = [cookieHeader mutableCopy];
                NSLog(@"[auth] captured Cookie header (%ld bytes) from %@",
                      (long)cookieHeader.length, url.host);
            }
        }
    }
    return YES; // allow the navigation to proceed normally
}

@end
