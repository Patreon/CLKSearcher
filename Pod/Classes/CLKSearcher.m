#import "CLKSearcher.h"

/*
 * Upon being asked to search for a given query,
 * the Searcher spawns a thread to search the network and a thread to search locally.
 * 
 * Subclasses should override the actual local and network search methods
 * so as to customize the search strategy.
 * 
 * Any time a thread finishes, it asks to merge its results into the reported results list.
 * If this response is no older than the currently reported results from the same source source (local/remote)
 * (say, a new search has returned before this one finished)
 * we thread lock, merge in the new results (replacing old results of the same source), then sort.
 *
 * Observers should KVO on results to receive timely updates.
 */

@interface CLKSearcher ()

@property (nonatomic, strong) NSArray *remoteResults;
@property (nonatomic, strong) NSArray *localResults;
@property (atomic, strong) NSMutableArray *reportedResults;

@property (nonatomic, readonly) BOOL injectsPreferredResultsWhenEmpty;
@property (nonatomic, readonly) BOOL injectsPreferredResultsAlways;
@property (nonatomic, readonly) NSArray *preferredResults;

@property (nonatomic, assign) NSTimeInterval latestLocalRecomputeRequest;
@property (nonatomic, assign) NSTimeInterval latestRemoteRecomputeRequest;

@property (nonatomic, strong) NSRecursiveLock *reportedResultsLock;

// TODO: this may no longer be needed now that we use ARC.
// does an explicit setQuery:nil message ever get sent during dealloc, now?
@property (nonatomic, assign) BOOL isBeingDeallocated;

@end

@implementation CLKSearcher

#pragma mark - lifecycle
- (instancetype)initWithSearchMode:(CLKSearcherMode)searchMode
{
    self = [super init];
    if (self) {
        self.searchMode = searchMode;
        self.remoteResults = @[];
        self.localResults = @[];
        self.reportedResultsLock = [[NSRecursiveLock alloc] init];
    }
    return self;
}

- (void)dealloc
{
    self.isBeingDeallocated = YES;
}

#pragma mark - properties
- (NSArray *)results
{
    if (self.reportedResults) {
        return self.reportedResults;
    }

    [self.reportedResultsLock lock];
    [self recomputeResults];
    [self.reportedResultsLock unlock];

    return _reportedResults;
}

#pragma mark - initiating a search
- (NSString *)sanitizeQuery:(NSString *)query
{
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return query;
}

- (void)setQuery:(NSString *)query
{
    query = [self sanitizeQuery:query];
    if ([_query isEqualToString:query]) {
        return;
    }

    _query = [query copy];
    [self updateResultsForLatestQuery];
}

- (void)updateResultsForLatestQuery
{
    if (self.query.length == 0) {
        if (!self.isBeingDeallocated) {
            if (self.injectsPreferredResultsWhenEmpty || self.injectsPreferredResultsAlways) {
                [self performSelectorInBackground:@selector(injectPreferredResults)
                                       withObject:nil];
            }
            if (self.searchMode != CLKSearcherModeRemoteOnly && [self allowEmptyLocalSearch]) {
                [self performSelectorInBackground:@selector(performLocalSearch:)
                                       withObject:self.query];
            }
            if (self.searchMode != CLKSearcherModeRemoteOnly && [self allowEmptyLocalSearch]) {
                [self performBackgroundSelectorOnSelf:@selector(performLocalSearch:)
                                           withObject:query];
            }
            if (self.searchMode != CLKSearcherModeLocalOnly && [self allowEmptyRemoteSearch]) {
                [self performSelectorInBackground:@selector(performRemoteSearch:)
                                       withObject:self.query];
            } else {
                [self performSelectorInBackground:@selector(flushRemoteResults)
                                       withObject:nil];
            }
        }
        return;
    }

    if (self.injectsPreferredResultsWhenEmpty && !self.injectsPreferredResultsAlways) {
        [self performSelectorInBackground:@selector(flushPreferredResults)
                               withObject:nil];
    }
    if (self.searchMode != CLKSearcherModeRemoteOnly) {
        [self performSelectorInBackground:@selector(performLocalSearch:)
                               withObject:self.query];
    }
    if (self.searchMode != CLKSearcherModeLocalOnly) {
        [self performSelectorInBackground:@selector(performRemoteSearch:)
                               withObject:self.query];
    }
}

- (void)clearOldQuery
{
    _query = nil;
}

#pragma mark - preferred results
- (void)injectPreferredResults
{
    [self recomputeResultsWithLocalResults:[self localResultsWithPreferredResults:self.preferredResults]
                               atTimestamp:CACurrentMediaTime()];
}

- (void)flushPreferredResults
{
    [self recomputeResultsWithLocalResults:[self localResultsWithPreferredResults:@[]]
                               atTimestamp:CACurrentMediaTime()];
}

- (NSArray *)localResultsWithPreferredResults:(NSArray *)preferredResults
{
    if (self.injectsPreferredResultsAlways) {
        return [preferredResults arrayByAddingObjectsFromArray:self.localResults];
    }
    return preferredResults;
}

- (BOOL)allowEmptyRemoteSearch
{
    return NO;
}

- (BOOL)allowEmptyLocalSearch
{
    return YES;
}

- (BOOL)injectsPreferredResultsWhenEmpty
{
    return NO;
}

- (BOOL)injectsPreferredResultsAlways
{
    return NO;
}

- (NSArray *)preferredResults
{
    return @[];
}

#pragma mark local
- (void)performLocalSearch:(NSString *)query
{
    if (!self.readyForLocalSearch) {
        return;
    }

    NSTimeInterval timestamp = CACurrentMediaTime();
    NSArray *localResults = [self getLocalResults:query];
    [self recomputeResultsWithLocalResults:localResults
                               atTimestamp:timestamp];
}

- (BOOL)readyForLocalSearch
{
    return YES;
}

- (NSArray *)getLocalResults:(NSString *)query
{
    // subclasses can implement
    return @[];
}


#pragma mark remote
- (void)performRemoteSearch:(NSString *)query
{
    if (![self allowEmptyRemoteSearch] && query.length == 0) {
        self.latestRemoteRecomputeRequest = CACurrentMediaTime();
        [self recomputeResultsWithRemoteResults:@[]
                                    atTimestamp:self.latestRemoteRecomputeRequest];
        return;
    }

    if (self.shouldMakeRemoteRequest) {
        [self makeRemoteSearchRequest:query];
        self.outstandingRequestCount++;
    }
}

- (BOOL)shouldMakeRemoteRequest
{
    return YES;
}

- (void)makeRemoteSearchRequest:(NSString *)query
{
    // subclasses may implement
}

- (void)resultsReceived:(NSDictionary *)response
{
    self.outstandingRequestCount--;

    if (![self responseDidSucceed:response]) {
        return;
    }

    if (![self isMostRecentRemoteResponse:response]) {
        return;
    }

    NSTimeInterval latestRemoteRequestTime = self.latestRemoteRequestTime;
    self.latestRemoteRecomputeRequest = latestRemoteRequestTime;
    NSMutableArray *remoteResults = [self parseRemoteResults:response];
    [self recomputeResultsWithRemoteResults:remoteResults
                                atTimestamp:latestRemoteRequestTime];
}

- (BOOL)responseDidSucceed:(NSDictionary *)response
{
    // subclasses should implement
    return YES;
}

- (BOOL)isMostRecentRemoteResponse:(NSDictionary *)response
{
    // subclasses should implement
    return YES;
}

- (NSTimeInterval)latestRemoteRequestTime
{
    // subclasses should implement
    return 0;
}

- (NSMutableArray *)parseRemoteResults:(NSDictionary *)response
{
    // subclasses should implement
    return [NSMutableArray array];
}

- (void)flushRemoteResults
{
    [self recomputeResultsWithRemoteResults:@[]
                                atTimestamp:CACurrentMediaTime()];
}

#pragma mark - merging results
- (void)recomputeResultsWithLocalResults:(NSArray *)localResults
                             atTimestamp:(NSTimeInterval)timestamp
{
    if (timestamp < self.latestLocalRecomputeRequest) {
        return;
    }
    self.latestLocalRecomputeRequest = timestamp;

    [self.reportedResultsLock lock];
    self.localResults = localResults;
    [self recomputeResults];
    [self.reportedResultsLock unlock];
}

- (void)recomputeResultsWithRemoteResults:(NSArray *)remoteResults
                              atTimestamp:(NSTimeInterval)timestamp
{
    if (timestamp < self.latestRemoteRecomputeRequest) {
        return;
    }
    self.latestRemoteRecomputeRequest = timestamp;

    [self.reportedResultsLock lock];
    self.remoteResults = remoteResults;
    [self recomputeResults];
    [self.reportedResultsLock unlock];
}

- (void)recomputeResults
{
    [self.reportedResultsLock lock];
    [self willChangeValueForKey:@"results"];

    [self mergeRemoteIntoLocalWithoutDuplication];
    [self sortMergedResults];
    [self dedupeMergedResults];

    [self didChangeValueForKey:@"results"];
    [self.reportedResultsLock unlock];
}

- (void)mergeRemoteIntoLocalWithoutDuplication
{
    if (self.localResults) {
        self.reportedResults = self.localResults.mutableCopy;
    } else {
        self.reportedResults = [NSMutableArray array];
    }

    for (NSObject *object in self.remoteResults) {
        NSUInteger index = [self.reportedResults indexOfObject:object]; // matches phone #
        if (index == NSNotFound) {
            [self.reportedResults addObject:object];
        } else {
            [self mergeRemoteResult:object
                    withLocalResult:self.reportedResults[index]];
        }
    }
}

- (void)mergeRemoteResult:(NSObject *)remoteResult
          withLocalResult:(NSObject *)localResult
{
    // Override in subclass
}

- (void)sortMergedResults
{
    // Override in subclass
}

- (void)dedupeMergedResults
{
    // Override in subclass
}

@end
