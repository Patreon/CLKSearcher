#import <UIKit/UIKit.h>
#import "CLKSearcher.h"

@protocol CLKSearcherControllerDelegate<NSObject>

- (void)didSelectSearchResult:(id)result;

@optional

// The "Search" return key on the keyboard
- (void)hitSearchButton;

// when the field is resigned, for any reason.
// If the user hits the search button and the textDelegate didn't override textFieldShouldReturn with YES,
// then this will always be called after hitSearchButton
- (void)didStopSearching;

// For when users are allowed to select more than one result
- (void)didSelectFinalResult;
- (void)didDeselectSearchResult:(id)result;

@end

/*  CLKSearcherController is a highly performant, UX-optimized controller for turning user search queries into a list of results.
 *  It debounces user text entry to efficiently use the CLKSearcher,
 *  and avoids re-rendering the results while the user is still typing.
 */

@interface CLKSearcherController : UIViewController<UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource>

// assign your subclass of CLKSearcher here
@property (nonatomic, strong) CLKSearcher *searcher;


// assign your own views to these three properties
@property (nonatomic, strong) UITextField *field; // delegate and returnKeyType will be set automatically
@property (nonatomic, strong) UITableView *table; // delegate and dataSource will be set automatically
@property (nonatomic, strong) UIView *noResultsView;

// set query to perform a search (or just assign 'field')
@property (nonatomic, copy) NSString *query;

// hear about user selection of search results
@property (nonatomic, weak) id<CLKSearcherControllerDelegate> delegate;

// hear about interactions with the search field
// CLKSearcherController is the field's real UITextFieldDelegate,
// please use this instead of assigning yourself as the field's UITextFieldDelegate directly
@property (nonatomic, weak) id<UITextFieldDelegate> textDelegate;

// Users select results by tapping them.
// CLKSearcherDelegates hear about selections through the delegate protocol
@property (nonatomic, strong) NSMutableArray *selectedResults;

// defaults to only allowing selection of one result
@property (nonatomic, assign) NSInteger maxResultsSelectable;
@property (nonatomic, readonly) BOOL hasChosenMaximumNumberOfResults;
@property (nonatomic, assign) BOOL allowDeselection;

@property (nonatomic, readonly) BOOL hasNonemptyQuery;
@property (nonatomic, assign) NSUInteger maxCharacters;

// forcefully start searching the current .field's text.
// useful if you manually assigned the field's text property, as UITextFieldDelegates don't hear about that
// and therefore the text would not be searched by default.
- (void)forceSearchCurrentText;
// forcefully resign search field
- (void)stopSearching;
// forcefully deselect all selected results
- (void)clearUserSelection;
// forcefully clear the search field
- (void)clearQuery;

// By default, this class (acting as a UITableViewDataSource), will append a "LoadingCell" row
// to the table view's numRows. If you wish to style the cells yourself, use this method to know
// which indexPath is reserved as a LoadingCell row.
- (BOOL)isLoadingCellPath:(NSIndexPath *)indexPath
              ofTableView:(UITableView *)tableView;

// the below are called automatically, but clients/subclasses may want to call them manually some times
- (void)renderViewWhenAble;

- (void)selectResult:(id)result;
- (void)deselectResult:(id)result;

@end
