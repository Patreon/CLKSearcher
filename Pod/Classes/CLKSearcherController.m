#import "CLKSearcherController.h"
#import "FrameAccessor.h"

#define kReflexTime 0.15

@interface CLKSearcherController ()

@property (nonatomic, assign) NSTimeInterval timeAtWhichToAllowRenderView;

@property (nonatomic, strong) NSTimer *searchingTimer;
@property (nonatomic, assign) BOOL hitSearchButton;

@end

@implementation CLKSearcherController

- (instancetype)init
{
  self = [super init];
  if (self) {
    self.selectedResults = [NSMutableArray array];
    self.maxResultsSelectable = 1;
    self.maxCharacters = NSIntegerMax;
  }
  return self;
}

- (void)dealloc
{
  if (_searcher) {
    [self removeObservers];
  }
  [self stopSearching];

  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(renderViewWhenAble)
                                             object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  [self renderViewWhenAble];
}

#pragma mark - properties

- (void)setField:(UITextField *)field {
  _field = field;

  self.field.delegate = self;
  self.field.returnKeyType = UIReturnKeySearch;
}

- (void)setSearcher:(CLKSearcher *)searcher {
  if (_searcher == searcher) {
    return;
  }
  if (_searcher) {
    [self removeObservers];
  }
  _searcher = searcher;
  if (_searcher) {
    [self addObservers];
  }
}

- (void)setTable:(UITableView *)table {
  if (_table == table) {
    return;
  }
  _table = table;
  if (_table) {
    _table.delegate = self;
    _table.dataSource = self;
  }
}

- (BOOL)showLoadingCell
{
  return self.searcher.outstandingRequestCount > 0;
}

- (BOOL)hasNonemptyQuery
{
  return self.query.length > 0;
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
  if ([keyPath isEqualToString:@"results"]
      || [keyPath isEqualToString:@"outstandingRequestCount"])
  {
    [self renderViewWhenAble];
  }
}

- (void)renderViewWhenAble
{
  // only render on the main thread
  if (![NSThread isMainThread]) {
    [self performSelectorOnMainThread:@selector(renderViewWhenAble)
                           withObject:nil
                        waitUntilDone:NO];
    return;
  }
  // don't render if they're still typing
  if (CACurrentMediaTime() < self.timeAtWhichToAllowRenderView) {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(renderViewWhenAble)
                                               object:nil];
    // check again once we think we'll be allowed to render
    [self performSelector:@selector(renderViewWhenAble)
               withObject:nil
               afterDelay:(self.timeAtWhichToAllowRenderView - CACurrentMediaTime()) + .001];
    return;
  }
  [self.table reloadData];
  self.noResultsView.hidden = (!self.hasNonemptyQuery || [self.table numberOfRowsInSection:0] != 0);
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
  if (section != 0) {
    return 0;
  }

  NSInteger rowCount = self.searcher.results.count;
  // show a loading cell at the bottom
  if ([self showLoadingCell]) {
    rowCount += 1;
  }
  return rowCount;
}

// default styling
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
  return [result description];
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
  if (![self showLoadingCell]) {
    return NO;
  }

  NSInteger numRows = [self tableView:tableView
                numberOfRowsInSection:indexPath.section];
  return indexPath.row == numRows - 1;
}

#pragma mark - UITableViewDelegate

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
    if (self.allowDeselection) {
      [self deselectResult:result];
      return;
    }
  }
  if (self.hasChosenMaximumNumberOfResults && [self.selectedResults count] > 0) {
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
    if ([self.delegate respondsToSelector:@selector(didDeselectSearchResult:)]) {
      [self.delegate didDeselectSearchResult:result];
    }
  }
}

- (void)stopSearchingAndInformDelegateIfAllResultsHaveBeenChosen
{
  if (self.hasChosenMaximumNumberOfResults) {
    [self stopSearching];

    if ([self.delegate respondsToSelector:@selector(didSelectFinalResult)]) {
      [self.delegate didSelectFinalResult];
    }
  }
}

- (BOOL)hasChosenMaximumNumberOfResults
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
  // Sometimes the table is trying renderViewWhenAble at the same time we're reloading this row.
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

- (void)clearUserSelection
{
  if ([self.delegate respondsToSelector:@selector(didDeselectSearchResult:)]) {
    for (id result in self.selectedResults) {
      [self.delegate didDeselectSearchResult:result];
    }
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

#pragma mark - Searching

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

- (void)forceSearchCurrentText
{
  if (self.field) {
    self.query = self.field.text;
  }
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
  [self forceSearchCurrentText];
  self.field.text = self.query;
  if ([self.textDelegate respondsToSelector:@selector(textFieldDidBeginEditing:)]) {
    [self.textDelegate textFieldDidBeginEditing:textField];
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
    return [self.textDelegate textFieldShouldReturn:textField];
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
  }
  if ([self.delegate respondsToSelector:@selector(didStopSearching)]) {
    [self.delegate didStopSearching];
  }

  if ([self.textDelegate respondsToSelector:@selector(textFieldDidEndEditing:)]) {
    [self.textDelegate textFieldDidEndEditing:textField];
  }
}

@end
