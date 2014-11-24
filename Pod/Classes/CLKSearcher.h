#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CLKSearcherMode)
{
    CLKSearcherModeLocalOnly,
    CLKSearcherModeRemoteOnly,
    CLKSearcherModeLocalAndRemote,
};

@interface CLKSearcher : NSObject

@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) NSInteger outstandingRequestCount;
@property (weak, nonatomic, readonly) NSArray *results;

@property (nonatomic, assign) CLKSearcherMode searchMode;

- (instancetype)initWithSearchMode:(CLKSearcherMode)searchMode;

- (void)clearOldQuery;

@end
