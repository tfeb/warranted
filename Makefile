######################## -*- Mode: Makefile-Bsdmake -*- #######################
## File		    - Makefile
## Description	    - Makefile for command warranter
## Author	    - Tim Bradshaw (tfb at kingston.local)
## Created On	    - Thu May  2 19:14:17 2019
## Status	    - Unknown
##
## $Format:(@:%H)$
###############################################################################

SOURCES = warranted.rkt wct.rkt low.rkt
BINDIR = /usr/local/bin
LIBDIR = /usr/local/lib


.PHONY: clean install test

warranted: $(SOURCES) test
	raco exe warranted.rkt

distribution: warranted
	raco distribute $@ $^

install: distribution
	mkdir -p $(BINDIR) $(LIBDIR)
	install -C -v -m 555 distribution/bin/* $(BINDIR)
	(cd distribution/lib && tar -cf - * | tar -C $(LIBDIR) -xpof -)

test:
	raco test $(SOURCES)

clean:
	rm -f warranted
	rm -rf compiled
	rm -rf distribution
	rm -f *~
