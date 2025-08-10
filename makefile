LEX     = flex
YACC    = bison
CC      = gcc
CFLAGS  = -Wall -std=c11 -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200809L

all: vlang.exe

vlang.exe: parser.tab.c lex.yy.c
	$(CC) $(CFLAGS) -o $@ $^

parser.tab.c parser.tab.h: parser.y
	$(YACC) -d $<

lex.yy.c: lexer.l
	$(LEX) $<

generate: vlang.exe example.vlang
	./vlang.exe < example.vlang
	@echo "✓ generated output.c"

compile-c: generate runtime.c
	$(CC) $(CFLAGS) -o program.exe output.c runtime.c
	@echo "✓ compiled program.exe"

run-c: compile-c
	./program.exe

test: run-c
clean:
	cmd /C "del /Q lex.yy.c parser.tab.c parser.tab.h vlang.exe output.c program.exe 2>nul || exit 0"
