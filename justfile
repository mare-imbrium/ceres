# Local Variables:
# mode: makefile
# End:
# vim: set ft=make :
# description: build or run or lint
# https://github.com/casey/just

prog = "cet"
src  = "src/" + prog + ".cr"

# build and run
run: build
  ./{{prog}}

# build
build:
  #!/usr/bin/env bash
  if [[ -f makefile ]]; then
    make
  else
    time crystal build {{src}}
  fi

lint:
  ameba

log:
  most log.txt

install:
  time crystal build {{src}} --release
  cp {{prog}} ~/bin
