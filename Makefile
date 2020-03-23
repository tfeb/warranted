######################## -*- Mode: Makefile-Bsdmake -*- #######################
## File		    - Makefile
## Description	    - Makefile for command warranter
## Author	    - Tim Bradshaw (tfb at kingston.local)
## Created On	    - Thu May  2 19:14:17 2019
## Status	    - Unknown
##
## $Format:(@:%H)$
###############################################################################

SOURCES	= warranted.rkt low.rkt fsm.rkt wcf.rkt
BINDIR = /usr/local/bin
LIBDIR = /usr/local/lib
TESTF = .TESTF

.PHONY: clean install test

warranted: $(SOURCES) $(TESTF)
	raco exe warranted.rkt

$(TESTF): $(SOURCES)
	raco test -t $(SOURCES)
	touch $@

distribution: warranted
	raco distribute $@ $^

install: distribution
	mkdir -p $(BINDIR) $(LIBDIR)
	install -C -v -m 555 distribution/bin/* $(BINDIR)
	if [ -d distribution/lib ]; then \
            (cd distribution/lib && tar -cf - * | tar -C $(LIBDIR) -xpof -); \
        fi

test:	$(TESTF)

clean:
	rm -f warranted
	rm -f $(TESTF)
	rm -rf compiled
	rm -rf distribution
	rm -f *~
