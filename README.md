# Warranted commands
\[**This documentation and the utility itself are currently in a rudimentary state: *caveat emptor*.**]

This is a primitive utility which allows you to 'warrant' certain commands using one or more configuration files.  It's like a tiny version of `sudo` except without the implication of SUID or most of the complexity, and probably without most of the security either.


So what's it useful for?  MacOS has recently developed a complicated layer of privacy controls which mean that programs (not just applications with GUIs: anything) which want to access data such as contacts &c need permission to do so.  This access control is completely orthogonal to the Unix filesystem permissions.

This is fine ... unless you want to run cron jobs which, say, run scripts or other programs in order to, for instance, make backups: if you try to run anything which walks over your home directory then it will fail.

There is a solution to this: you can grant specified programs 'full disk access' which allows them to bypass all this.  There is some mechanism I don't understand which decides which program needs to have that access: for instance if you sit in a terminal window and type

```
$ find ~ -type f -print > /dev/null
```

Then the dialogue which pops up will ask you whether you want to grant access to `Terminal` (or `iTerm` if you are sensible and use that), not `/usr/bin/find`.  It seems to be doing some magic which allows it to walk up the process tree and find the closest thing with a GUI to ask about (and in fact it may be able to do some hairy thing to find the appropriate thing even if it's not an ancestor of the process which actually needs access).

In the case of programs where there is no GUI component such as cron jobs, it does seem to be enough to grant permission to something up the process tree.  So one solution would be to 'bless' `/usr/sbin/cron`.  But that's tantamount to blessing all commands, as you can put anything in a `crontab`.  And, worse, you might not even be using `cron`: I use `launchd`, and I *really* don't want to bless that, since almost everything uses it to run things.

So you need a wrapper of some kind which you can bless.  One obvious approach would be to bless `sudo`, but I didn't want to do that as it would mean I would need to maintain a `sudoers` file which might or might not get unilaterally overwritten by the system's one, and also there might be other things in it which I *don't* want to be blessed.

Enter `warranted`: this reads one or more files with command descriptions in them, and checks a command line against it, running it if it matches.  If you install it in `/usr/local/bin`, then you can bless it (remember 'CMD-shift-.' to let the Finder see all files), and use it to run commands you are interested in.

## Configuration files
**This is subject to change**: the current thing is deficient and I'm going to write a better one in due course: see [the TODO list](TODO.md).

All configuration file syntax is standard [Racket](https://racket-lang.org/) syntax: everything is read with [`read`](https://docs.racket-lang.org/reference/Reading.html) wrapped with `call-with-default-reading-parameterization`.  There is exactly one form in any file (you can add others, but only the first will be read).

There are two sets of files:

- meta files tell it which files of command specifications to read;
- command specification files tell it what commands it can run.

It looks in a fixed set of places for meta files, and reads the first one it finds, only.  The standard set of places is:

1. `/etc/warranted/meta.rktd`;
2. `/usr/local/etc/warranted/meta.rktd`;
3. `~/etc/warranted/meta.rktd` (`~` meaning 'user's home directory' un the usual way).

If any of these files is found it should contain a single list of filenames: these are the command specification files to read.  So to make `warranted` be really fussy install a meta file in `/etc/warranted/meta.rktd` and put in that a single file or files which can be carefully controlled.

Command specification files are looked for either wherever the meta file tells it to look or in a set of standard places:

1. `/etc/warranted/commands.rktd`;
2. `/usr/local/etc/warranted/commands.rktd`;
3. `~/etc/warranted/commands.rktd`.

All the files which are found are read, and they are combined into a single tree specifying what can be read.

## Usage
There are various options not described here (but `warranted -h` will give you some hints).  The basic usage is

```
$ warranted command [arg ...]
```

which, if the executable corresponding to `command` is warranted with the given arguments, will run it & return its exit code.

So, I have `cron` (really `launchd`) jobs which run

```
/usr/local/bin/warranted $HOME/lib/cron/run hourly
```

for instance.

## Configuration syntax
**Note this is both subject to change and incomplete**: I'm only giving the most simple case here as the current syntax is all going to change at some point.

Each configuration file contains a single form which should be a list of lists.  Each sublist specifies a command which is allowed with its arguments.  Commands must be matched as full pathnames: you need to say `"/bin/cat"`, not `"cat"`.

There are two wildcard characters:

- `*` means 'any single argument';
- `**` means 'any number of arguments, incluing zero'.

So, for instance the following configuration file

```
(("/Users/tfb/lib/cron/run" *))
```

Will allow the command `/Users/tfb/lib/cron/run` to be run with any single argument, while

```
(("/Users/tfb/lib/cron/run" "hourly")
 ("/Users/tfb/lib/cron/run" "nightly"))
```

Will allow the same command to be run with arguments of `hourly` or `nightly`.

You can put as many commands as you like (and, yes, there's a way of specifying a single command with various combinations of arguments in a better way, but this is what is subject to change, so I'm not going to describe it).

## Notes on security
The main purpose of the thing is to evade the MacOS privacy controls without just giving up completely: it's not intended as a comprehensive solution to anything and in particular

> **I make no promise at all that `warranted` is even slightly secure: you use it entirely at your own risk.**

Specific notes.

- `warranted` is as secure as the Racket reader, which is probably not very secure.
- The default configuration will let it read a file controlled by the user running it: it needs to be tied down with a meta file to stop that.
- *It's just a hack*: I wrote it in a few hours so I could make my cron jobs work, and that's all it's good for.

## Building
You will need a [Racket](https://racket-lang.org/) installation with `raco` in your `PATH`, & a working `make` (the Xcode one is fine).  Then `make` should be enough.  The binary is huge because it includes the whole Racket runtime.

## Copyright & Licence
Copyright 2019 Tim Bradshaw

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