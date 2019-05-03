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


.PHONY: clean install test

warranted: $(SOURCES) test
	raco exe warranted.rkt

install: warranted
	install -C -v -m 555 $^ $(BINDIR)

test:
	raco test $(SOURCES)

clean:
	rm -f warranted
	rm -rf compiled
	rm -f *~
