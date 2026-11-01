#import "LibraryStore.h"
#import <ImageIO/ImageIO.h>

static NSSet *LNImageExtensions(void) {
    static NSSet *extensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"heic", @"heif",
                                           @"tif", @"tiff"]];
    });
    return extensions;
}

/// Every image inside a folder, naturally sorted.
static NSArray<NSURL *> *LNImageFilesInDirectory(NSURL *directory) {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory.path
                                                                         error:NULL];
    if (names == nil) {
        return @[];
    }

    NSArray *sorted = [names sortedArrayUsingComparator:^NSComparisonResult(NSString *lhs,
                                                                           NSString *rhs) {
        return [lhs localizedStandardCompare:rhs];
    }];

    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in sorted) {
        if ([name hasPrefix:@"."]) {
            continue;
        }
        NSString *extension = name.pathExtension.lowercaseString;
        if (![LNImageExtensions() containsObject:extension]) {
            continue;
        }
        [result addObject:[directory URLByAppendingPathComponent:name]];
    }
    return result;
}

@interface LibraryStore ()
@property (nonatomic, strong, readwrite) NSURL *rootURL;
@property (nonatomic, strong) NSArray *issueCache;
@property (nonatomic, strong) NSMutableDictionary *articleCache;
@property (nonatomic, strong) NSMutableDictionary *ocrCache;
@end

@implementation LibraryStore

+ (instancetype)sharedStore {
    static LibraryStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[LibraryStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                 NSUserDomainMask,
                                                                 YES);
        NSString *documentsPath = documents.firstObject ?: NSTemporaryDirectory();
        _rootURL = [[NSURL fileURLWithPath:documentsPath] URLByAppendingPathComponent:@"NewsFiles"
                                                                         isDirectory:YES];
        _articleCache = [NSMutableDictionary dictionary];
        _ocrCache = [NSMutableDictionary dictionary];

        if (![[NSFileManager defaultManager] fileExistsAtPath:_rootURL.path]) {
            [[NSFileManager defaultManager] createDirectoryAtURL:_rootURL
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:NULL];
        }
    }
    return self;
}

#pragma mark - Issues

- (NSArray<LNIssue *> *)issues {
    if (self.issueCache != nil) {
        return self.issueCache;
    }
    NSArray *loaded = [self loadIssues];
    self.issueCache = loaded;
    return loaded;
}

- (void)reload {
    self.issueCache = nil;
    [self.articleCache removeAllObjects];
    [self.ocrCache removeAllObjects];
}

- (NSArray<LNIssue *> *)loadIssues {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.rootURL.path
                                                                         error:NULL];
    if (names == nil) {
        return @[];
    }

    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) {
            continue;
        }
        NSURL *directory = [self.rootURL URLByAppendingPathComponent:name isDirectory:YES];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory.path
                                                  isDirectory:&isDirectory] ||
            !isDirectory) {
            continue;
        }
        LNIssue *issue = [self loadIssueAtDirectory:directory fallbackID:name];
        if (issue != nil) {
            [result addObject:issue];
        }
    }

    [result sortUsingComparator:^NSComparisonResult(LNIssue *lhs, LNIssue *rhs) {
        NSDate *left = lhs.date ?: [NSDate distantPast];
        NSDate *right = rhs.date ?: [NSDate distantPast];
        if (![left isEqualToDate:right]) {
            return [right compare:left];
        }
        return [lhs.title localizedStandardCompare:rhs.title];
    }];
    return result;
}

- (LNIssue *)loadIssueAtDirectory:(NSURL *)directory fallbackID:(NSString *)fallbackID {
    NSFileManager *manager = [NSFileManager defaultManager];

    NSDictionary *manifest = nil;
    for (NSString *name in @[@"issue.json", @"metadata.json"]) {
        NSURL *url = [directory URLByAppendingPathComponent:name];
        if ([manager fileExistsAtPath:url.path]) {
            NSData *data = [NSData dataWithContentsOfURL:url];
            if (data != nil) {
                manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if ([manifest isKindOfClass:[NSDictionary class]]) {
                    break;
                }
                manifest = nil;
            }
        }
    }
    if (manifest == nil) {
        manifest = @{};
    }

    NSMutableArray<LNPage *> *pages = [NSMutableArray array];

    // Preferred: explicit page list in the manifest.
    for (id entry in LNArray(manifest[@"pages"])) {
        NSString *relativePath = nil;
        NSInteger width = 0;
        NSInteger height = 0;

        if ([entry isKindOfClass:[NSString class]]) {
            relativePath = entry;
        } else {
            NSDictionary *page = LNDictionary(entry);
            relativePath = LNString(page[@"image"]) ?: LNString(page[@"file"])
                         ?: LNString(page[@"path"]);
            width = LNInteger(page[@"width"], 0);
            height = LNInteger(page[@"height"], 0);
        }

        if (relativePath == nil) {
            continue;
        }
        NSURL *url = [directory URLByAppendingPathComponent:relativePath];
        if (![manager fileExistsAtPath:url.path]) {
            continue;
        }

        LNPage *page = [[LNPage alloc] init];
        page.number = pages.count + 1;
        page.imageURL = url;
        page.pixelWidth = width;
        page.pixelHeight = height;
        [pages addObject:page];
    }

    // Fallback: every image inside the pages folder, sorted naturally.
    if (pages.count == 0) {
        NSArray<NSURL *> *files =
            LNImageFilesInDirectory([directory URLByAppendingPathComponent:@"pages"
                                                               isDirectory:YES]);
        if (files.count == 0) {
            return nil;
        }
        [files enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger index, BOOL *stop) {
            LNPage *page = [[LNPage alloc] init];
            page.number = (NSInteger)index + 1;
            page.imageURL = url;
            page.pixelWidth = 0;
            page.pixelHeight = 0;
            [pages addObject:page];
        }];
    }

    LNIssue *issue = [[LNIssue alloc] init];
    issue.issueID = LNString(manifest[@"id"]) ?: fallbackID;
    issue.directory = directory;
    issue.title = LNString(manifest[@"title"]) ?: LNString(manifest[@"publication"])
                ?: fallbackID;
    issue.subtitle = LNString(manifest[@"subtitle"]) ?: LNString(manifest[@"edition"]) ?: @"";
    issue.dateText = LNString(manifest[@"date"]) ?: LNString(manifest[@"dateText"]) ?: @"";
    issue.date = LNParseDate(issue.dateText) ?: LNParseDate(fallbackID);
    issue.pages = pages;
    return issue;
}

#pragma mark - Articles

- (NSArray<LNArticle *> *)articlesForIssue:(LNIssue *)issue {
    NSArray *cached = self.articleCache[issue.issueID];
    if (cached != nil) {
        return cached;
    }

    NSMutableArray *result = [NSMutableArray array];
    NSURL *articlesDirectory = [issue.directory URLByAppendingPathComponent:@"articles"
                                                                isDirectory:YES];

    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:articlesDirectory.path
                                                                         error:NULL];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if (![name.lowercaseString hasSuffix:@".json"]) {
            continue;
        }
        NSData *data = [NSData dataWithContentsOfURL:
                            [articlesDirectory URLByAppendingPathComponent:name]];
        if (data == nil) {
            continue;
        }
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        LNArticle *article = [LibraryStore articleFromObject:LNDictionary(object) issue:issue];
        if (article != nil) {
            [result addObject:article];
        }
    }

    NSData *combinedData = [NSData dataWithContentsOfURL:
                               [issue.directory URLByAppendingPathComponent:@"articles.json"]];
    if (combinedData != nil) {
        id combined = [NSJSONSerialization JSONObjectWithData:combinedData options:0 error:NULL];
        for (id entry in LNArray(LNDictionary(combined)[@"articles"])) {
            LNArticle *article = [LibraryStore articleFromObject:LNDictionary(entry) issue:issue];
            if (article != nil) {
                [result addObject:article];
            }
        }
    }

    [result sortUsingComparator:^NSComparisonResult(LNArticle *lhs, LNArticle *rhs) {
        if (lhs.pageNumber != rhs.pageNumber) {
            return lhs.pageNumber < rhs.pageNumber ? NSOrderedAscending : NSOrderedDescending;
        }
        if (lhs.bounds.origin.y != rhs.bounds.origin.y) {
            return lhs.bounds.origin.y < rhs.bounds.origin.y ? NSOrderedAscending
                                                            : NSOrderedDescending;
        }
        if (lhs.bounds.origin.x != rhs.bounds.origin.x) {
            return lhs.bounds.origin.x < rhs.bounds.origin.x ? NSOrderedAscending
                                                            : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    self.articleCache[issue.issueID] = result;
    return result;
}

+ (LNArticle *)articleFromObject:(NSDictionary *)object issue:(LNIssue *)issue {
    if (object.count == 0) {
        return nil;
    }

    NSInteger page = LNInteger(object[@"page"],
                               LNInteger(object[@"pageNumber"], 1));
    if (page < 1 || page > issue.pageCount) {
        return nil;
    }

    CGRect bounds = CGRectZero;
    id rectValue = object[@"bounds"] ?: object[@"rect"];
    if (!LNRect(rectValue, &bounds)) {
        return nil;
    }

    LNArticle *article = [[LNArticle alloc] init];
    article.articleID = LNString(object[@"id"]) ?: LNString(object[@"headline"]) ?: @"article";
    article.pageNumber = page;
    article.headline = LNString(object[@"headline"]) ?: LNString(object[@"title"]) ?: @"Untitled";
    article.bounds = bounds;

    NSString *text = LNString(object[@"text"]) ?: @"";
    if (text.length == 0) {
        NSString *file = LNString(object[@"textFile"]);
        if (file.length > 0) {
            NSURL *url = [[issue.directory URLByAppendingPathComponent:@"ocr"]
                             URLByAppendingPathComponent:file];
            text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL] ?: @"";
        }
    }
    article.text = [text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return article;
}

#pragma mark - OCR

- (NSString *)ocrTextForIssue:(LNIssue *)issue page:(LNPage *)page {
    NSString *key = [NSString stringWithFormat:@"%@|%ld", issue.issueID, (long)page.number];
    NSString *cached = self.ocrCache[key];
    if (cached != nil) {
        return cached;
    }
    NSString *text = [self loadOCRTextForIssue:issue page:page] ?: @"";
    self.ocrCache[key] = text;
    return text;
}

- (NSString *)loadOCRTextForIssue:(LNIssue *)issue page:(LNPage *)page {
    NSURL *directory = [issue.directory URLByAppendingPathComponent:@"ocr" isDirectory:YES];
    NSString *baseName = page.imageURL.URLByDeletingPathExtension.lastPathComponent ?: @"";

    NSArray *candidates = @[
        [NSString stringWithFormat:@"%ld.json", (long)page.number],
        [NSString stringWithFormat:@"%03ld.json", (long)page.number],
        [baseName stringByAppendingPathExtension:@"json"] ?: @"",
        [NSString stringWithFormat:@"%ld.txt", (long)page.number],
        [baseName stringByAppendingPathExtension:@"txt"] ?: @""
    ];

    for (NSString *name in candidates) {
        if (name.length == 0) {
            continue;
        }
        NSURL *url = [directory URLByAppendingPathComponent:name];
        if ([url.pathExtension.lowercaseString isEqualToString:@"txt"]) {
            NSString *text = [NSString stringWithContentsOfURL:url
                                                       encoding:NSUTF8StringEncoding
                                                          error:NULL];
            text = [text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (text.length > 0) {
                return text;
            }
        } else {
            NSData *data = [NSData dataWithContentsOfURL:url];
            if (data == nil) {
                continue;
            }
            NSDictionary *object =
                [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (![object isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *text = LNString(object[@"text"]);
            if (text.length > 0) {
                return text;
            }

            NSMutableArray *lines = [NSMutableArray array];
            for (id entry in LNArray(object[@"lines"])) {
                NSString *line = LNString(LNDictionary(entry)[@"text"]);
                if (line != nil) {
                    [lines addObject:line];
                }
            }
            if (lines.count > 0) {
                return [lines componentsJoinedByString:@" "];
            }
        }
    }
    return @"";
}

#pragma mark - Search

- (NSArray<LNSearchHit *> *)search:(NSString *)query limit:(NSInteger)limit {
    NSString *trimmed =
        [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 2) {
        return @[];
    }

    NSMutableArray *hits = [NSMutableArray array];
    for (LNIssue *issue in [self issues]) {
        NSArray<LNArticle *> *articles = [self articlesForIssue:issue];
        for (LNPage *page in issue.pages) {
            NSString *text = [self ocrTextForIssue:issue page:page];
            if (text.length == 0) {
                continue;
            }

            NSRange range = [text rangeOfString:trimmed
                                        options:NSCaseInsensitiveSearch];
            if (range.location == NSNotFound) {
                continue;
            }

            NSString *headline = nil;
            for (LNArticle *article in articles) {
                if (article.pageNumber != page.number) {
                    continue;
                }
                if ([article.text rangeOfString:trimmed
                                        options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    headline = article.headline;
                    break;
                }
            }
            if (headline == nil) {
                headline = [NSString stringWithFormat:@"Page %ld", (long)page.number];
            }

            LNSearchHit *hit = [[LNSearchHit alloc] init];
            hit.issue = issue;
            hit.pageNumber = page.number;
            hit.headline = headline;
            hit.snippet = [LibraryStore snippetInText:text aroundRange:range radius:90];
            [hits addObject:hit];

            if (limit > 0 && (NSInteger)hits.count >= limit) {
                return hits;
            }
        }
    }
    return hits;
}

+ (NSString *)snippetInText:(NSString *)text aroundRange:(NSRange)range radius:(NSInteger)radius {
    NSInteger location = (NSInteger)range.location - radius;
    if (location < 0) {
        location = 0;
    }
    NSInteger end = (NSInteger)(range.location + range.length) + radius;
    if (end > (NSInteger)text.length) {
        end = (NSInteger)text.length;
    }

    NSString *snippet = [text substringWithRange:NSMakeRange((NSUInteger)location,
                                                             (NSUInteger)(end - location))];
    snippet = [snippet stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    snippet = [snippet stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    snippet = [snippet stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (location > 0) {
        snippet = [@"…" stringByAppendingString:snippet];
    }
    if (end < (NSInteger)text.length) {
        snippet = [snippet stringByAppendingString:@"…"];
    }
    return snippet;
}

@end

#pragma mark - ImageLoader

@interface ImageLoader ()
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation ImageLoader

+ (instancetype)sharedLoader {
    static ImageLoader *loader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loader = [[ImageLoader alloc] init];
    });
    return loader;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 3;
        _queue = dispatch_queue_create("news.image-loader", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (NSString *)keyForURL:(NSURL *)url maxPixelSize:(CGFloat)maxPixelSize {
    return [NSString stringWithFormat:@"%@|%ld", url.path, (long)maxPixelSize];
}

- (UIImage *)cachedImageForURL:(NSURL *)url {
    return [self.cache objectForKey:[self keyForURL:url maxPixelSize:3200]];
}

- (void)loadImageForURL:(NSURL *)url
           maxPixelSize:(CGFloat)maxPixelSize
             completion:(void (^)(UIImage *))completion {
    NSString *key = [self keyForURL:url maxPixelSize:maxPixelSize];
    UIImage *cached = [self.cache objectForKey:key];
    if (cached != nil) {
        completion(cached);
        return;
    }

    dispatch_async(self.queue, ^{
        UIImage *image = [ImageLoader downsampleURL:url maxPixelSize:maxPixelSize];
        if (image != nil) {
            [self.cache setObject:image forKey:key];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image);
        });
    });
}

+ (UIImage *)downsampleURL:(NSURL *)url maxPixelSize:(CGFloat)maxPixelSize {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        NSLog(@"[auth] ImageLoader: CGImageSourceCreateWithURL returned NULL for %@", url.path);
        return nil;
    }

    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize)
    };

    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0,
                                                               (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (thumbnail == NULL) {
        NSLog(@"[auth] ImageLoader: CGImageSourceCreateThumbnailAtIndex returned NULL for %@", url.path);
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:thumbnail];
    CGImageRelease(thumbnail);
    return image;
}

@end
