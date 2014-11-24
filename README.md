# CLKSearcher

CLKSearcher is the best way to allow your users to keyword search over remote and local content

Subclasses can define how to perform remote and local searches for a particular query string, and CLKSearcher handles threading, merging of local and remote results, and re-requesting at regular intervals as the user types.

CLKSearcherController manages the text input control that calls into CLKSearcher, as well as display of the results back to the user in a table view.