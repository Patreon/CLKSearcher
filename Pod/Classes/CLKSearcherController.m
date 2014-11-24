#import "CLKSearcherController.h"
#import "CLKSearcher.h"
#import "FrameAccessor.h"

#define kReflexTime 0.15

@interface CLKSearcherController ()

@property (nonatomic, strong) CLKSearcher *searcher;
@property (nonatomic, assign) NSTimeInterval timeAtWhichToAllowRenderView;

@property (nonatomic, strong) NSTimer *searchingTimer;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, assign) BOOL hitSearchButton;
@property (nonatomic, copy) NSString *query;

@property (nonatomic, assign) CGFloat keyboardHeight;

@end

@implementation CLKSearcherController

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.selectedResults = [NSMutableArray array];
    }
    return self;
}

- (NSInteger)maxResultsSelectable
{
    return 1; // subclasses may override
}

- (void)dealloc
{
    [self stopSearching];

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(renderView)
                                               object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.field.delegate = self;
    self.field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.keyboardType = UIKeyboardTypeDefault;
    self.field.returnKeyType = UIReturnKeySearch;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self renderView];
}

#pragma mark - KVO
- (void)addObservers
{
    [self.searcher addObserver:self
                    forKeyPath:@"results"
                       options:0
                       context:nil];
    [self.searcher addObserver:self
                    forKeyPath:@"outstandingRequestCount"
                       options:0
                       context:nil];
}

- (void)removeObservers
{
    [self.searcher removeObserver:self
                       forKeyPath:@"results"
                          context:nil];
    [self.searcher removeObserver:self
                       forKeyPath:@"outstandingRequestCount"
                          context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    [self renderView];
}

- (void)renderView
{
    // TODO: maybe delete this perform selector stuff?

    // only render on the main thread
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(renderView)
                               withObject:nil
                            waitUntilDone:NO];
        return;
    }
    // don't render if they're still typing
    if (CACurrentMediaTime() < self.timeAtWhichToAllowRenderView) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(renderView)
                                                   object:nil];
        // check again once we think we'll be allowed to render
        [self performSelector:@selector(renderView)
                   withObject:nil
                   afterDelay:(self.timeAtWhichToAllowRenderView - CACurrentMediaTime()) + .001];
        return;
    }
    [self.table reloadData];
    self.noResultsView.hidden = (!self.isSearching || [self.table numberOfRowsInSection:0] != 0);
}

- (BOOL)waitingOnNetwork
{
    return self.searcher.outstandingRequestCount > 0;
}

- (BOOL)isSearching
{
    return self.query.length > 0;
}

- (NSUInteger)maxCharacters
{
    return 150;
}

#pragma mark - table delegate methods
- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
    if (section != 0) {
        return 0;
    }

    NSInteger rowCount = self.searcher.results.count;
    // show a loading cell at the bottom
    if ([self waitingOnNetwork]) {
        rowCount += 1;
    }
    return rowCount;
}

- (id)resultForIndexPath:(NSIndexPath *)indexPath
{
    id result = nil;
    // threading still seems to be an issue sometimes, so guard just in case :/
    @try {
        result = self.searcher.results[indexPath.row];
    } @catch (NSException *exception) {
        NSLog(@"bad access of search results array :(");
    } @finally {
        return result;
    }
}

- (NSIndexPath *)indexPathForResult:(id)result
{
    NSUInteger index = [self.searcher.results indexOfObject:result];
    if (index == NSNotFound) {
        return nil;
    }
    return [NSIndexPath indexPathForRow:index
                              inSection:0];
}

- (BOOL)isLoadingCellPath:(NSIndexPath *)indexPath
              ofTableView:(UITableView *)tableView
{
    if (![self waitingOnNetwork]) {
        return NO;
    }

    NSInteger numRows = [self tableView:tableView
                  numberOfRowsInSection:indexPath.section];
    return indexPath.row == numRows - 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL isLoadingCell = [self isLoadingCellPath:indexPath
                                     ofTableView:tableView];

    NSString *dequeueID = isLoadingCell ? @"LoadingCell" : @"ResultsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:dequeueID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:dequeueID];
    }

    if (isLoadingCell) {
        cell.textLabel.text = @"Loading...";
    } else {
        id result = [self resultForIndexPath:indexPath];
        cell.textLabel.text = [self cellTextForResult:result];
    }

    return cell;
}

- (NSString *)cellTextForResult:(id)result
{
    return [result description]; // default
}

- (NSIndexPath *)tableView:(UITableView *)tableView
  willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isLoadingCellPath:indexPath ofTableView:tableView]) {
        return nil;
    }
    return indexPath;
}

- (void)      tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    id selectedResult = [self resultForIndexPath:indexPath];
    [self selectResult:selectedResult];
}

- (void)selectResult:(id)result
{
    if (!result) {
        return;
    }
    if ([self.selectedResults containsObject:result]) {
        if (!self.shouldReselectInsteadOfDeselect) {
            [self deselectResult:result];
            return;
        }
    }
    if (self.hasChosenAllResults && [self.selectedResults count] > 0) {
        id oldestSelection = [self.selectedResults lastObject];
        [self deselectResult:oldestSelection];
    }

    [self.selectedResults addObject:result];
    [self reloadRowForResult:result];
    [self.delegate didSelectSearchResult:result];
    [self stopSearchingAndInformDelegateIfAllResultsHaveBeenChosen];
}

- (void)deselectResult:(id)result
{
    if ([self.selectedResults indexOfObject:result] != NSNotFound) {
        [self.selectedResults removeObject:result];
        [self reloadRowForResult:result];
        [self.delegate didDeselectSearchResult:result];
    }
}

- (void)stopSearchingAndInformDelegateIfAllResultsHaveBeenChosen
{
    if (self.hasChosenAllResults) {
        [self stopSearching];

        if ([self.delegate respondsToSelector:@selector(didSelectFinalResult)]) {
            [self.delegate didSelectFinalResult];
        }
    }
}

- (BOOL)hasChosenAllResults
{
    return [self.selectedResults count] >= self.maxResultsSelectable;
}

- (void)reloadRowForResult:(id)result
{
    if (!result) {
        return;
    }
    NSIndexPath *selection = [self indexPathForResult:result];
    if (!selection) {
        return;
    }
    // Sometimes the table is trying renderView at the same time we're reloading this row.
    // If so, Cocoa throws an inconsistency exception because chances are our number of rows is going to change.
    // Luckily, we can just ask the table if the number of rows it has now is equal to the number of rows it will have
    // when reloadData gets called, and only do the quick and easy route if there's not going to be an inconsistency exception.
    if ([self.table numberOfRowsInSection:0] == [self tableView:self.table numberOfRowsInSection:0] && [self.table numberOfRowsInSection:0] != 0) {
        [self.table reloadRowsAtIndexPaths:@[selection]
                          withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.table reloadData];
    }
}

#pragma mark - Presentation
- (void)resign
{
    if (self.hasChosenAllResults) {
        // TODO: easier customization here
        id result = [self.selectedResults firstObject];
        self.field.text = [self cellTextForResult:result];
    }
    [self.field resignFirstResponder];
    [self dismiss];
}

- (void)clearResults
{
    for (id result in self.selectedResults) {
        [self.delegate didDeselectSearchResult:result];
    }
    self.selectedResults = [NSMutableArray array];
    [self.field resignFirstResponder];
    [self clearQuery];
}

- (void)clearQuery
{
    self.field.text = nil;
    self.query = nil;
    [self.table reloadData];
}

- (void)dismiss
{
    [self stopSearching];
    [self didDismiss];
}

- (void)didDismiss
{
    if ([self.delegate respondsToSelector:@selector(didDismissSearcher)]) {
        [self.delegate didDismissSearcher];
    }
}

#pragma mark - searching
- (void)setQuery:(NSString *)query
{
    if (query.length > self.maxCharacters) {
        query = [query substringToIndex:self.maxCharacters];
    }

    if (query != _query) {
        _query = [(query ? query : @"") copy];
    }

    // save off when we should allow rendering,
    // we dont want to render while they're typing
    self.timeAtWhichToAllowRenderView = CACurrentMediaTime() + kReflexTime;

    // we should start the searching poller if we havent searched yet
    [self debounceSearchExecution];
}

- (void)debounceSearchExecution
{
    if (self.searchingTimer) {
        return;
    }
    NSDate *fireDate = [[NSDate date] dateByAddingTimeInterval:(kReflexTime * 3)];
    self.searchingTimer = [[NSTimer alloc] initWithFireDate:fireDate
                                                   interval:(kReflexTime * 5)
                                                     target:self
                                                   selector:@selector(setSearcherQuery)
                                                   userInfo:nil
                                                    repeats:YES];
    NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
    [runLoop addTimer:self.searchingTimer
              forMode:NSDefaultRunLoopMode];
}

- (void)setSearcherQuery
{
    self.searcher.query = self.query;
}

- (void)startSearching
{
    // run the side-effects of the setter
    self.query = self.query ? self.query : @"";
}

- (void)stopSearching
{
    [self.searchingTimer invalidate];
    self.searchingTimer = nil;
}

#pragma mark - Text Field Delegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    if ([self.textDelegate respondsToSelector:@selector(textFieldShouldBeginEditing:)]) {
        [self.textDelegate textFieldShouldBeginEditing:textField];
    }
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    [self startSearching];
    self.field.text = self.query;
    if ([self.textDelegate respondsToSelector:@selector(textFieldDidBeginEditing:)]) {
        [self.textDelegate textFieldDidBeginEditing:textField];
    }
    if ([self.delegate respondsToSelector:@selector(prepareToShowKeyboardOfHeight:)]) {
        [self.delegate prepareToShowKeyboardOfHeight:self.keyboardHeight];
    }
}

- (BOOL)            textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
            replacementString:(NSString *)string
{
    SEL selector = @selector(textField:shouldChangeCharactersInRange:replacementString:);
    if ([self.textDelegate respondsToSelector:selector]) {
        BOOL delegateApproves = [self.textDelegate textField:textField
                               shouldChangeCharactersInRange:range
                                           replacementString:string];
        if (!delegateApproves) {
            return NO;
        }
    }

    NSString *newString = [textField.text stringByReplacingCharactersInRange:range
                                                                  withString:string];

    if (newString.length <= self.maxCharacters) {
        self.query = newString;
        return YES;
    }

    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    self.hitSearchButton = YES;
    [self.field resignFirstResponder];
    self.hitSearchButton = NO;
    if ([self.textDelegate respondsToSelector:@selector(textFieldShouldReturn:)]) {
        [self.textDelegate textFieldShouldReturn:textField];
    }

    return NO;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    if ([self.textDelegate respondsToSelector:@selector(textFieldShouldEndEditing:)]) {
        [self.textDelegate textFieldShouldEndEditing:textField];
    }
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (self.hitSearchButton && [self.delegate respondsToSelector:@selector(hitSearchButton)]) {
        [self.delegate hitSearchButton];
    } else if (NO == self.hitSearchButton && [self.delegate respondsToSelector:@selector(didStopSearching)]) {
        [self.delegate didStopSearching];
    }

    if ([self.textDelegate respondsToSelector:@selector(textFieldDidEndEditing:)]) {
        [self.textDelegate textFieldDidEndEditing:textField];
    }
}

- (void)setKeyboardHeight:(CGFloat)keyboardHeight
{
    _keyboardHeight = keyboardHeight;
    if ([self.delegate respondsToSelector:@selector(prepareToShowKeyboardOfHeight:)]) {
        [self.delegate prepareToShowKeyboardOfHeight:self.keyboardHeight];
    }
}

@end
