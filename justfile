# Local Variables:
# mode: makefile
# End:
# vim: set ft=make :
# description: build or run or lint
# https://github.com/casey/just

# build and run
run: build
  ./cet

# build
build:
  #!/usr/bin/env bash
  SRC=src/cet.cr
  TGT=./cet
  if [[ $SRC -nt $TGT ]]; then
    time crystal build src/cet.cr
  else
    echo Nothing to do. $TGT uptodate.
  fi

lint:
  ameba

log:
  most log.txt

install:
  time crystal build src/cet.cr --release
  cp cet ~/bin
