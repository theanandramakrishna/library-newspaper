#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// One replica page image.
@interface LNPage : NSObject
@property (nonatomic) NSInteger number;          // 1-based
@property (nonatomic, strong) NSURL *imageURL;
@property (nonatomic) NSInteger pixelWidth;      // 0 if unknown
@property (nonatomic) NSInteger pixelHeight;     // 0 if unknown
@end

/// A clickable region on a page plus its reading text.
@interface LNArticle : NSObject
@property (nonatomic, copy) NSString *articleID;
@property (nonatomic) NSInteger pageNumber;      // 1-based
@property (nonatomic, copy) NSString *headline;
@property (nonatomic) CGRect bounds;             // page pixel coordinates
@property (nonatomic, copy) NSString *text;
@end

/// One imported issue (a single publication on a single day).
@interface LNIssue : NSObject
@property (nonatomic, copy) NSString *issueID;
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *dateText;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) NSArray<LNPage *> *pages;

- (NSInteger)pageCount;
- (NSString *)displayDate;
@end

/// One search result.
@interface LNSearchHit : NSObject
@property (nonatomic, strong) LNIssue *issue;
@property (nonatomic) NSInteger pageNumber;
@property (nonatomic, copy) NSString *headline;
@property (nonatomic, copy) NSString *snippet;
@end

/// Forgiving JSON helpers for loosely-authored manifest files.
FOUNDATION_EXPORT NSDictionary *LNDictionary(id value);
FOUNDATION_EXPORT NSArray *LNArray(id value);
FOUNDATION_EXPORT NSString *LNString(id value);
FOUNDATION_EXPORT NSNumber *LNNumber(id value);
FOUNDATION_EXPORT NSInteger LNInteger(id value, NSInteger fallback);

/// Accepts {x,y,width,height}, {x,y,w,h}, {left,top,width,height} or [x,y,w,h].
FOUNDATION_EXPORT BOOL LNRect(id value, CGRect *outRect);

/// Parses yyyy-MM-dd, MM/dd/yyyy, ISO timestamps, or a date embedded in a
/// folder name such as "seattle-times-2026-10-17".
FOUNDATION_EXPORT NSDate *LNParseDate(NSString *text);
