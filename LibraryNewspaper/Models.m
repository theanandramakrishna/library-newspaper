#import "Models.h"

@implementation LNPage
@end

@implementation LNArticle
@end

@implementation LNIssue

- (NSInteger)pageCount {
    return (NSInteger)self.pages.count;
}

- (NSString *)displayDate {
    if (self.dateText.length > 0) {
        return self.dateText;
    }
    if (self.date == nil) {
        return @"";
    }
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    });
    return [formatter stringFromDate:self.date];
}

@end

@implementation LNSearchHit
@end

NSDictionary *LNDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

NSArray *LNArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

NSString *LNString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return nil;
}

NSNumber *LNNumber(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSString class]]) {
        return @([value doubleValue]);
    }
    return nil;
}

NSInteger LNInteger(id value, NSInteger fallback) {
    NSNumber *number = LNNumber(value);
    return number != nil ? number.integerValue : fallback;
}

BOOL LNRect(id value, CGRect *outRect) {
    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = value;
        if (array.count == 4) {
            CGRect rect = CGRectMake([LNNumber(array[0]) doubleValue],
                                     [LNNumber(array[1]) doubleValue],
                                     [LNNumber(array[2]) doubleValue],
                                     [LNNumber(array[3]) doubleValue]);
            if (outRect != NULL) { *outRect = rect; }
            return YES;
        }
        return NO;
    }

    NSDictionary *dictionary = LNDictionary(value);
    if (dictionary.count == 0) {
        return NO;
    }

    CGFloat x = [LNNumber(dictionary[@"x"]) doubleValue];
    if (dictionary[@"x"] == nil) {
        x = [LNNumber(dictionary[@"left"]) doubleValue];
    }
    CGFloat y = [LNNumber(dictionary[@"y"]) doubleValue];
    if (dictionary[@"y"] == nil) {
        y = [LNNumber(dictionary[@"top"]) doubleValue];
    }

    NSNumber *width = LNNumber(dictionary[@"width"]) ?: LNNumber(dictionary[@"w"]);
    NSNumber *height = LNNumber(dictionary[@"height"]) ?: LNNumber(dictionary[@"h"]);
    if (width == nil || height == nil) {
        return NO;
    }

    if (outRect != NULL) {
        *outRect = CGRectMake(x, y, width.doubleValue, height.doubleValue);
    }
    return YES;
}

NSDate *LNParseDate(NSString *text) {
    if (text.length == 0) {
        return nil;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    for (NSString *format in @[@"yyyy-MM-dd", @"yyyy/MM/dd", @"MM/dd/yyyy",
                               @"yyyyMMdd", @"yyyy-MM-dd'T'HH:mm:ssZ"]) {
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:text];
        if (date != nil) {
            return date;
        }
    }

    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"(\\d{4})-(\\d{2})-(\\d{2})"
                                                  options:0
                                                    error:NULL];
    NSTextCheckingResult *match =
        [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match != nil) {
        NSString *year = [text substringWithRange:[match rangeAtIndex:1]];
        NSString *month = [text substringWithRange:[match rangeAtIndex:2]];
        NSString *day = [text substringWithRange:[match rangeAtIndex:3]];
        formatter.dateFormat = @"yyyy-MM-dd";
        return [formatter dateFromString:[NSString stringWithFormat:@"%@-%@-%@",
                                          year, month, day]];
    }
    return nil;
}
