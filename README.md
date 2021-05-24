# [Warranted commands](https://github.com/tfeb/warranted)
\[**This documentation, and the utility itself, are currently in a fairly rudimentary state: *caveat emptor*.**]

This is a primitive utility which allows you to 'warrant' certain commands using one or more configuration files.  It's like a tiny version of `sudo` except without the implication of SUID or most of the complexity, and probably without most of the security either.

So what's it useful for?  MacOS has recently developed a complicated layer of privacy controls which mean that programs (not just applications with GUIs: anything) which want to access data such as contacts &c need permission to do so.  This access control is completely orthogonal to the Unix filesystem permissions.

This is fine ... unless you want to run periodic background jobs which run scripts or other programs in order to, for instance, make backups: if you try to run anything which walks over your home directory then it will either fail altogether or pop up dialogue boxes at odd times, which is not the behaviour you want from cron jobs.

There is a solution to this: you can grant specified programs 'full disk access' which allows them to bypass all this.  There is some mechanism I don't understand which decides which program needs to have that access: for instance if you sit in a terminal window and type

```
$ find ~ -type f -print > /dev/null
```

Then the dialogue which pops up will ask you whether you want to grant access to `Terminal` (or `iTerm` if you are sensible and use that), not `/usr/bin/find`.  It seems to be doing some magic which allows it to walk up the process tree and find the closest thing with a GUI to ask about (and in fact it may be able to do some hairy thing to find the appropriate thing even if it's not an ancestor of the process which actually needs access).

In the case of programs where there is no GUI component such as cron jobs, it does seem to be enough to grant permission to something up the process tree.  So one solution would be to 'bless' (allow full disk access to) `/usr/sbin/cron`.  But that's tantamount to blessing *all* commands, as you can put anything in a `crontab`.  And, worse, you might not even be using `cron`: I use `launchd`, and I *really* don't want to bless that, since almost everything uses it to run things.

So you need a wrapper of some kind which you can bless.  One obvious approach would be to bless `sudo`, but I didn't want to do that as it would mean I would need to maintain a `sudoers` file which might or might not get unilaterally overwritten by the system's one, and also there might be other things in it which I *don't* want to be blessed.

Enter `warranted`: this reads one or more sources of command descriptions, and checks a command line against these descriptions, running it if it matches.  If you install it in `/usr/local/bin`, then you can bless it (remember 'CMD-shift-.' to let the Finder see all files), and use it to run commands you are interested in.

## Configuration sources
All configuration syntax is standard [Racket](https://racket-lang.org/) syntax: everything is read with [`read`](https://docs.racket-lang.org/reference/Reading.html) wrapped with `call-with-default-reading-parameterization` and with the `read-accept-lang` and `read-accept-reader` parameters false.  There is exactly one form in any source (you can add others, but only the first will be read).

There are three sets of files:

- meta files tell it the sources of command specifications to read;
- command specification files contain command specifications which tell it what commands it can run;
- command specification commands are programs which *print* command specifications.

**Meta files** are searched for in a fixed set of locations in a fixed order and the first one found is read, only.  The fixed set of places is, in order:

1. `/etc/warranted/meta.rktd`;
2. `/usr/local/etc/warranted/meta.rktd`;
3. `~/etc/warranted/meta.rktd` (`~` meaning 'user's home directory' in the usual way).

If any of these files is found it should contain a single list.  Each entry in this list specifies a source of command specifications.  An entry may be either;

- a filename, which specifies a command specification file to read;
- a list of the form `(run <command> <argument> ...)`, which is a command to run with its arguments, which should print a set of command specifications to its standard output.

To make `warranted` be really fussy install a meta file in `/etc/warranted/meta.rktd` and put in that a single file or files which can be carefully controlled.  For instance the contents of `/etc/warranted/meta.rktd` might be

```
("/etc/warranted/commands.rktd")
```

which will cause `warranted` to look *only* at `/etc/warranted/commands.rktd` for command specifications.

**Command specification sources** can therefore either be files containing command specifications, or commands which print command specifications  The syntax of command specifications is the same in either case.

**Command specification files** are looked for either wherever the meta file tells it to look or in a set of standard places if no meta file is found.

1. `/etc/warranted/commands.rktd`;
2. `/usr/local/etc/warranted/commands.rktd`;
3. `~/etc/warranted/commands.rktd`.

All the files which are found are read, and they are combined into a single specification specifying what can be read.

**Command specification commands** are only looked for if there is a meta file which specifies them, as for instance

```
(run "/usr/local/sbin/get-warranted-commands"
     "-s" "ldap")
```

In this case:

1. if `/usr/local/sbin/get-warranted-commands` doesn't exist nothing happens;
2. if it does exist it must be executable (it is an error if not, and `warranted` will exit) and it will be run with the specified arguments (not via the shell, so no globbing, environment variable substitution or other terrors);
3. its exit code and standard output (and standard error in fact, for error reporting) will be captured;
4. if it exits with a nonzero exit code then `warranted` will exit reporting that error (with a nonzero exit code in turn);
5. otherwise, if it produces *no* output it is ignored;
6. otherwise its standard output should contain a well-formed command specification list, just as a file would contain.

The purpose of command specification commands is so that `warranted` can acquire command specifications from sources it does not understand, such as name services, without having to understand them: the command does that for it.

## The regrettable history of command specifications
In the first reasonable version, command specifications were lists of elements where nested lists were disjunctions which could in turn have command specifications inside them.  This meant you had to know the nesting level to know what you were looing at meant.  So in something like

```
["/Users/tfb/lib/cron/run"
  (/ "-t" ["-l" "-r"])
  ("hourly" "nightly" "weekly"
   "monthly" "yearly")]
```

You need to know that the outer thing is a command specification, the thing inside it is a disjunction, and inside *that* is another partial command specification.  This is OK so long as you are consistent in using `[...]` and `(...)`, but nothing forces that.

So I thought it would be nice to express these things explicitly: a command specification would be `(and ...)`, meaning 'all these mus match' and a disjunction would be `(or ...)` meaning 'one of these must match'.  And that means you can also compose things: `(and "ls" (and "-l" *))` is `(and "ls" "-l" *)`.  So now the above specificatioun would be

```
[and "/Users/tfb/lib/cron/run"
     (or / "-t" [and "-l" "-r"])
  (or "hourly" "nightly" "weekly"
      "monthly" "yearly")]
```

And that would be better.

Except, is it really?  And, even worse, I didn't want to disenfranchise the old nesting-level-based one, so that's all still there, and you can combine them.  Something needs to be done about this, but I am not sure what.

## Command specifications
Each command specification file contains a single form, which is a list of command specifications.

* A *command specification* is either `(and element ...)` (`and` is a literal) or a list of elements.
* An *element* is either:
	* a string;
	* a regexp, using Racket's `#rx` or `#px` syntaxes for regexps;
	* a *disjunction*, which is either `(or disjunct ...)` (again, `or` is a literal) or a list of disjuncts, where a *disjunct* is a command specification, a command specification element (both may be in a single list) or a disjunction in the explicit `(or disjunct ...)` form.
	* one of the symbols `*`, `**`, `/`;
	* a command specification in the explicit `(and element ...)` form.

A command line matches a command specification if all its elements match.

* Elements which are strings match corresponding command line elements.  The first element in the command line (the command in other words) is looked up along `PATH` and this is what is matched.  So, for instance `cat` is turned into `/bin/cat` and this must be what is in the command specification.
* Elements which are regexps also match corresponding command line elements.  The regexp must match the whole of the element: this means you don't need to anchor the pattern, and also makes it harder to make mistakes I hope.
* The element `*` matches any single entry in the command line.
* The element `**` matches zero or more entries in the command line.
* The element `/` matches no elements in the command line (see below for why this is useful).
* An element which is a disjunction matches if one of its entries matches:
	* if the entry is an element it must match element-wise;
	* if the entry is a command-specification it must match as a specification;
	* if the entry is a disjunction it is essentially spliced into the current disjunction: `(or "x" (or "y" "z"))` is the same as `(or "x" "y" "z")`.
* An element which is a command specification is spliced into the current specification: `(and "ls" (and "-l") *)` is equivalent to `(and "ls" "-l" *)`.

## Example command specifications
These examples are of single command specifications: remember that a specification file contains a list of command specifications.  Note that not all of the command specifications below make any sense, or are safe: they're just here as examples.

`("/bin/ls")` will match `ls` with no arguments only (assuming that `type -p ls` is `/bin/ls` which it is by default).

`("/bin/ls" "/etc/motd")` will match `ls /etc/motd` only.  This is equivalent to `(and "/bin/ls" "/etc/motd")`: the same is true for the following.

`("/bin/ls" *)` will match `ls` with any single argument.  Note that `warranted` has no idea whether an argument is a switch or not.

`("/bin/ls" "-l" *)` will match `ls -l` and any other single argument.

`("/bin/ls" #rx"-[ld]" *)` will match `ls -l` and any other single argument, or `ls -d` and any other single argument.

`("/bin/ls" **)` will match `ls` with any number of arguments, including zero.

`("/bin/ls" ** "/etc/motd")` would match `ls` with any number of arguments so long as the last one is `/etc/motd`.

`("/bin/ls" ("/etc/motd" "/etc/hostname"))` will match `ls /etc/motd` or `ls /etc/hostname`, only.

`("/bin/ls" (/ "-l") "/etc/motd")` matches `ls /etc/motd` and `ls -l /etc/motd`.  This works because the disjunction either matches `-l` or matches nothing with `/`: this is what `/` is useful for.

`("/bin/ls" (/ ("-l" "-r")) "/etc/motd")` matches either `ls /etc/motd` or `ls -l -r /etc/motd`, which it does because the disjunction contains a nested command specification.  This might be more clearly expressed as `(and "/bin/ls" (or / (and "-l" "-r")) "/etc/motd")`.

`("/bin/ls" (/ #rx"-[lr]") "/etc/motd")` matches one of `ls /etc/motd`, `ls -l /etc/motd` or `ls -r /etc/motd`.  This can be expressed without using a regexp as `("/bin/ls" (/ (("-l" "-r"))) "/etc/motd")`: In this case `(/ ...)` is a disjunction which contains a command sequence of one element which contains another disjunction.  That case again would probably be much clearer as `(and "/bin/ls" (or / (and (or "-l" "-r"))) "/etc/motd")` or something like that, although both are less clear than the regexp version I think.

Finally here is the content of my `~/etc/warranted/commands.rktd` file:

```
(["/Users/tfb/lib/cron/run"
  ;; My cron commands
  (/ "-t")
  ("hourly" "nightly" "weekly"
   "monthly" "yearly")])
```

Note that I've used `[...]` which Racket allows, and that this warrants, for instance `/Users/tfb/lib/cron/run hourly` and `/Users/tfb/lib/cron/run -t yearly` but not `/Users/tfb/lib/cron/run -x annually`.  Note also that this is an old-style specification.

Regexps are new in command specifications and obviously allow some additional flexibility.  There is a saying about regexps which should never be forgotten:

> Some people, when confronted with a problem, think "I know,
I'll use regular expressions."  Now they have two problems.
> -- jwz, 1997.

Note that you can freely nest things: `(and (and ...))` is fine, as is `(and ... (or (or ...)))`.  Both are effectively flattened (and in fact actually flattened) to a single layer structure.

## Usage
There are various options not described here (but `warranted -h` will give you some hints).  The basic usage is

```
$ warranted command [arg ...]
```

which, if the executable corresponding to `command` is warranted with the given arguments, will run it & return its exit code.  If it's not warranted, then `warranted` returns an exit code of `1`.

So, I have `cron` (really `launchd`) jobs which run

```
/usr/local/bin/warranted $HOME/lib/cron/run hourly
```

for instance.

One option which is useful is `-n`: `warranted -n ...` will tell you whether it would run the specified command but not actually run it:

```
$ warranted -n ls
unwarranted command line ("/bin/ls") (from ("ls"))
$ warranted -n ~/lib/cron/run hourly
[would run ("/Users/tfb/lib/cron/run" "hourly")]
$ echo $?
0
$ warranted -n ~/lib/cron/run annually
unwarranted command line ("/Users/tfb/lib/cron/run" "annually") (from ("/Users/tfb/lib/cron/run" "annually"))
$ echo $?
1
```

## Notes on security
The main purpose of the thing is to evade the MacOS privacy controls without just giving up completely: it's not intended as a comprehensive solution to anything and in particular

> **I make no promise at all that `warranted` is even slightly secure: you use it entirely at your own risk.** – tfb

Specific security notes.

- `warranted` is only as secure as the Racket reader, which is probably not very secure.
- The default configuration will let it read a file controlled by the user running it: it needs to be tied down with a meta file to stop that.
- It knows nothing of file permissions, and in particular does no checking that, for instance `/usr/local/etc/warranted/meta.rktd` can't be written or replaced by the user running `warranted`.
- *It's just a hack*: I wrote it in a few hours so I could make my cron jobs work, and that's all it's good for.

If you care about security, read the code: it's not very big.

## Building
`warranted` is written in [Racket](https://racket-lang.org/), and has been built with Racket 7.2 & 7.3.  You will need a Racket installation with `raco` in your `PATH`, & a working `make` (the Xcode one is fine).  The `Makefile` uses `raco exe` to make a binary and then `raco distribute` to make a distribution which should not depend on the installed Racket.  The default target just makes the binary, `make distrubution` will make the distribution directory, and `make install` will try to install the distribution.  Installing is fiddly in the usual way if the user who can run `raco` is not the one who can write into the install directory.

## Other notes
Although this is not apparent from the GUI, it seems to be the case that when you bless a locally-built executable, such as `warranted`, you are blessing the specific file: presumably it works out whether the file is blessed or not by computing some signature of it and comparing it with what it knows.  This means that if you rebuild & reinstall it it will stop being blessed, although the GUI will show that it still is.  So each time you reinstall `warranted` you have to do a little dance to remove the old one from the list and then bless the new one.  The answer to this is probably code signing, but I have no idea how that works: I suspect the answer is [here](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Introduction/Introduction.html).

The `(and ...)` and `(or ...)` forms were meant to make complex nested command specifications easier to read: I'm not sure they actually do.

---

## Copyright & Licence
Copyright 2019-2021 Tim Bradshaw

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.