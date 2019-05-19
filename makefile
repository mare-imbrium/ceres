SRC=src/*.cr
PROG=cet

$(PROG): $(SRC)
	time crystal build src/${PROG}.cr
