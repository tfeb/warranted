# Things to do for `warranted`
## Patterns should be more explicit
You can now say `(and "ls" (or "-l" "-r") ...)`.  It still needs to deal properly with things like `(and ... (and ...))`, which should compile to `(and ... ...)`.
## Should `/` be `?`
I prefer `/`, but, well, perhaps `(? ...)` reads better as a disjunction?
## What else is needed for specifications?
What's there now seems OK.  Perhaps negation would be useful (but how to fit that).  I should look at `sudo` and remember what it does (although it is problematic).
## Code signing
I suppose I need to understand this.
## Everything is awful
It just needs more thinking about.