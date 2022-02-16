# @file		Makefile - Makefile for C-based utilities
# @author	Wes Garland, wes@kingsds.network
# @date		Apr 2020
#
# `make` to build everything
# `make clean` to erase everything

CFLAGS=-g
PROGS=range-find
OBJS=$(foreach PROG, $(PROGS), $(PROG).o)

# CFLAGS += -DSUPPORT_GETDATE

top: $(PROGS)

clean: 
	rm -f $(PROGS) $(OBJS)
