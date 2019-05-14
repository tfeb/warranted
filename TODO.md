# Things to do for `warranted`
## The whole command tree thing is bogus
It should be specified in terms of some kind of FSM so you might be able to say

```
(("/Users/tfb/lib/cron/run"
  (? "-t")
  (or "hourly"
      "nightly"
      "weekly"
      "monthly"
      "yearly"))
```

or something like that.

## Everything is awful
It just needs more thinking about.