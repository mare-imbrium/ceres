SRC=src/*.cr
PROG=ceres

$(PROG): $(SRC)
	time crystal build src/${PROG}.cr
