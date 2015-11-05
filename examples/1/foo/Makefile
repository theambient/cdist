PREFIX ?= /usr/local
INCLUDE = $(subst //,/,$(DESTDIR)/$(PREFIX)/include)
LIB = $(subst //,/,$(DESTDIR)/$(PREFIX)/lib)

CXX ?= cc

build: src/foo.cpp 
	mkdir -p dist/
	$(CXX) -c -o dist/libfoo.a src/foo.cpp

install: 
	@echo "INSTALL $(INCLUDE)"
	@install -d $(INCLUDE)
	@install -m 644 include/* $(INCLUDE)/

	@echo "INSTALL $(LIB)"
	@install -d $(LIB)
	@install -m 644 dist/libfoo.a $(LIB)/
