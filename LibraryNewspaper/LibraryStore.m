#import "LibraryStore.h"
#import <ImageIO/ImageIO.h>

static NSSet *LNImageExtensions(void) {
    static NSSet *extensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"heic", @"heif",
                                           @"tif", @"tiff", @"pdf"]];
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
        } else {
            NSLog(@"[auth] ImageLoader: downsampleURL returned NIL for %@ (maxPixelSize=%.0f)",
                  url.path, maxPixelSize);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image);
        });
    });
}

+ (UIImage *)downsampleURL:(NSURL *)url maxPixelSize:(CGFloat)maxPixelSize {
    // PDF rendering via Core Graphics (PDFKit not available on iOS 9).
    if ([[url pathExtension] isEqualToString:@"pdf"]) {
        return [ImageLoader renderPDFPageAtURL:url maxPixelSize:maxPixelSize];
    }

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
    NSLog(@"[auth] ImageLoader: rendered image %@ -> %dx%d", url.lastPathComponent,
          (NSInteger)image.size.width, (NSInteger)image.size.height);
    return image;
}

// Returns the part of the page box that actually has ink on it. NewsBank's
// generated PDFs use a page box much larger than the artwork: page 1's box is
// 2092x4524, the template paints a white panel over 2035x3313 of it, and the
// newspaper itself only occupies 1674x3314 of that panel. Drawing the whole
// box shows a blank 26% strip along the bottom and a ~390 pt white gutter down
// the right-hand side, so the rendered page is cropped to the ink instead.
+ (CGRect)contentRectForPDFPage:(CGPDFPageRef)page pageRect:(CGRect)pageRect {
    // Probe tall enough that a one-point rule still spans a couple of pixels;
    // below ~600 the anti-aliased right-hand edge of the artwork fades into the
    // white template panel and the measured box jumps around by 150 pt.
    const CGFloat probeMax = 800.0;
    CGFloat pageWidth = pageRect.size.width;
    CGFloat pageHeight = pageRect.size.height;
    CGFloat maxDim = MAX(pageWidth, pageHeight);
    if (maxDim <= 0) {
        return pageRect;
    }

    CGFloat scale = probeMax / maxDim;
    size_t width = (size_t)ceil(pageWidth * scale);
    size_t height = (size_t)ceil(pageHeight * scale);
    if (width == 0 || height == 0) {
        return pageRect;
    }

    size_t bytesPerRow = width * 4;
    unsigned char *data = calloc(height, bytesPerRow);
    if (data == NULL) {
        return pageRect;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, bytesPerRow,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        free(data);
        return pageRect;
    }

    // Start from white paper so the test below measures ink on paper rather
    // than "did the PDF paint here". NewsBank's template paints a white panel
    // wider than the artwork, so an alpha test keeps that blank panel: page 1's
    // artwork ends at x=1702 but the panel runs on to x=2063, leaving a 390 pt
    // empty gutter down the right-hand side.
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));

    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, -pageRect.origin.x, -pageRect.origin.y);
    CGContextDrawPDFPage(context, page);

    size_t minRow = height, maxRow = 0, minCol = width, maxCol = 0;
    BOOL found = NO;
    // Two passes: one mark per column/row is not enough (a single stray
    // anti-aliasing pixel at the panel edge must not define the box), so count
    // hits first and then keep only axis positions carrying real ink.
    unsigned int *columnInk = calloc(width, sizeof(unsigned int));
    unsigned int *rowInk = calloc(height, sizeof(unsigned int));
    if (columnInk == NULL || rowInk == NULL) {
        free(columnInk);
        free(rowInk);
        CGContextRelease(context);
        free(data);
        return pageRect;
    }
    for (size_t row = 0; row < height; row++) {
        const unsigned char *pixels = data + row * bytesPerRow;
        for (size_t col = 0; col < width; col++) {
            const unsigned char *pixel = pixels + col * 4;
            unsigned char r = pixel[0], g = pixel[1], b = pixel[2];
            if (r < 240 || g < 240 || b < 240) {  // anything darker than paper
                columnInk[col]++;
                rowInk[row]++;
            }
        }
    }

    const unsigned int minCount = 2;
    for (size_t col = 0; col < width; col++) {
        if (columnInk[col] >= minCount) {
            found = YES;
            if (col < minCol) minCol = col;
            if (col > maxCol) maxCol = col;
        }
    }
    for (size_t row = 0; row < height; row++) {
        if (rowInk[row] >= minCount) {
            found = YES;
            if (row < minRow) minRow = row;
            if (row > maxRow) maxRow = row;
        }
    }

    free(columnInk);
    free(rowInk);
    CGContextRelease(context);
    free(data);

    if (!found) {
        return pageRect;
    }

    // Bitmap row 0 is the top of the page; PDF coordinates have y pointing up.
    CGFloat x0 = minCol / scale;
    CGFloat x1 = (maxCol + 1) / scale;
    CGFloat y0 = (height - 1 - maxRow) / scale;
    CGFloat y1 = (height - minRow) / scale;

    CGRect content = CGRectMake(x0, y0, x1 - x0, y1 - y0);
    content = CGRectIntersection(content, pageRect);
    if (CGRectIsNull(content) || content.size.width <= 0 || content.size.height <= 0) {
        return pageRect;
    }
    // Sanity guard: if the ink box collapses to a fraction of the page (an
    // almost-blank page, or a scan whose ink the threshold missed) fall back to
    // the whole page box rather than upscaling a sliver of it.
    if (content.size.width < pageWidth * 0.4 || content.size.height < pageHeight * 0.4) {
        return pageRect;
    }
    return content;
}

// Renders the first page of a PDF to a UIImage using Core Graphics.
// PDFKit is not available on iOS 9, so we draw the PDF page into a bitmap
// context manually. This gives full-resolution vector-quality rendering.
+ (UIImage *)renderPDFPageAtURL:(NSURL *)url maxPixelSize:(CGFloat)maxPixelSize {
    NSLog(@"[auth] ImageLoader: renderPDFPageAtURL start for %@", url.path);

    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
    if (!pdf) {
        NSLog(@"[auth] ImageLoader: CGPDFDocumentCreateWithURL returned NULL for %@", url.path);
        return nil;
    }
    NSLog(@"[auth] ImageLoader: CGPDFDocumentCreateWithURL OK, page count=%ld",
          (long)CGPDFDocumentGetNumberOfPages(pdf));

    CGPDFPageRef page = CGPDFDocumentGetPage(pdf, 1);
    if (!page) {
        NSLog(@"[auth] ImageLoader: CGPDFDocumentGetPage(page 1) returned NULL for %@", url.path);
        CGPDFDocumentRelease(pdf);
        return nil;
    }
    NSLog(@"[auth] ImageLoader: CGPDFDocumentGetPage OK");

    CGRect pageRect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    CGRect contentRect = [self contentRectForPDFPage:page pageRect:pageRect];
    CGFloat pageWidth = contentRect.size.width;
    CGFloat pageHeight = contentRect.size.height;
    CGFloat maxDim = MAX(pageWidth, pageHeight);
    NSLog(@"[auth] ImageLoader: page box %.0fx%.0f, ink %.0fx%.0f at (%.0f,%.0f)",
          pageRect.size.width, pageRect.size.height, pageWidth, pageHeight,
          contentRect.origin.x, contentRect.origin.y);
    if (maxDim <= 0) {
        CGPDFDocumentRelease(pdf);
        return nil;
    }

    // Scale to fit within maxPixelSize.
    CGFloat scale = maxPixelSize / maxDim;
    CGFloat renderWidth = pageWidth * scale;
    CGFloat renderHeight = pageHeight * scale;
    NSLog(@"[auth] ImageLoader: scale=%.3f, render %.0fx%.0f", scale, renderWidth, renderHeight);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, renderWidth, renderHeight, 8, 0,
                                                 colorSpace, kCGImageAlphaPremultipliedLast);
    if (!context) {
        NSLog(@"[auth] ImageLoader: CGBitmapContextCreate returned NULL for %@", url.path);
        CGColorSpaceRelease(colorSpace);
        CGPDFDocumentRelease(pdf);
        return nil;
    }

    // Start from white paper: parts of the PDF that were never painted would
    // otherwise come out black (the bitmap starts out transparent).
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, renderWidth, renderHeight));

    // CGBitmapContext and PDF pages both use a bottom-left origin with y up,
    // so the page draws straight in once scaled. (Applying a flip here renders
    // NewsBank's PDFs upside down.) The translation crops away the unpainted
    // part of the page box.
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, -contentRect.origin.x, -contentRect.origin.y);
    CGContextDrawPDFPage(context, page);

    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    if (!imageRef) {
        NSLog(@"[auth] ImageLoader: CGBitmapContextCreateImage returned NULL for %@", url.path);
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        CGPDFDocumentRelease(pdf);
        return nil;
    }
    UIImage *image = [UIImage imageWithCGImage:imageRef];

    CGImageRelease(imageRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGPDFDocumentRelease(pdf);

    NSLog(@"[auth] ImageLoader: rendered PDF %@ -> %dx%d", url.lastPathComponent,
          (NSInteger)image.size.width, (NSInteger)image.size.height);
    return image;
}

@end
