#import <UIKit/UIKit.h>

@protocol CLKSearcherDelegate<NSObject>

- (void)didSelectSearchResult:(id)result;

@optional
- (void)prepareToShowKeyboardOfHeight:(CGFloat)keyboardHeight;

- (void)didDismissSearcher;

- (void)didStopSearching;

- (void)hitSearchButton;

- (void)didSelectFinalResult;
- (void)didDeselectSearchResult:(id)result;

@end

// TODO: figure out how this should relate to UISearchDisplayController? Probably subclass it..

/*  CLKSearcherController is a highly performant, UX-optimized controller for turning user search queries into a list of results.
 *  It debounces user text entry to efficiently use the CLKSearcher,
 *  and avoids re-rendering the results while the user is still typing.
 */

@interface CLKSearcherController : UIViewController<UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, weak) id<CLKSearcherDelegate> delegate;
@property (nonatomic, weak) id<UITextFieldDelegate> textDelegate;

@property (nonatomic, assign) NSInteger maxResultsSelectable;
@property (nonatomic, strong) NSMutableArray *selectedResults;
@property (nonatomic, readonly) BOOL hasChosenAllResults;

@property (nonatomic, strong) IBOutlet UITableView *table;
@property (nonatomic, strong) IBOutlet UIView *noResultsView;
@property (nonatomic, assign) BOOL isShowing;
@property (nonatomic, readonly) BOOL isSearching;
@property (nonatomic, assign) BOOL shouldReselectInsteadOfDeselect;
@property (nonatomic, assign) NSUInteger maxCharacters;

- (void)startSearching;
- (void)stopSearching;

- (void)dismiss;
- (void)resign;
- (void)clearResults;
- (void)clearQuery;
- (void)renderView;

- (void)selectResult:(id)result;
- (void)deselectResult:(id)result;

- (BOOL)isLoadingCellPath:(NSIndexPath *)indexPath
              ofTableView:(UITableView *)tableView;

@end
