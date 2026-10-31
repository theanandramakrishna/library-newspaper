#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Models.h"

/// Scans the app's Documents/NewsFiles folder and exposes issues, article
/// rectangles, OCR text and search.
@interface LibraryStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, strong, readonly) NSURL *rootURL;

- (NSArray<LNIssue *> *)issues;
- (void)reload;
- (NSArray<LNArticle *> *)articlesForIssue:(LNIssue *)issue;
- (NSString *)ocrTextForIssue:(LNIssue *)issue page:(LNPage *)page;
- (NSArray<LNSearchHit *> *)search:(NSString *)query limit:(NSInteger)limit;

@end

/// Decodes and caches page images at a bounded size so large scanned pages do
/// not blow up memory.
@interface ImageLoader : NSObject

+ (instancetype)sharedLoader;

- (UIImage *)cachedImageForURL:(NSURL *)url;
- (void)loadImageForURL:(NSURL *)url
           maxPixelSize:(CGFloat)maxPixelSize
             completion:(void (^)(UIImage *image))completion;

@end
