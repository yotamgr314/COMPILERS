# Makefile for Vlang Compiler on Windows
LEX     = flex
YACC    = bison
CC      = gcc
CFLAGS  = -Wall -std=c11

all: vlang.exe

vlang.exe: parser.tab.c lex.yy.c
	$(CC) $(CFLAGS) -o $@ $^

parser.tab.c parser.tab.h: parser.y
	$(YACC) -d $<

lex.yy.c: lexer.l
	$(LEX) $<

# 1) הפעלת המהדר -> output.c
generate: vlang.exe example.vlang
	./vlang.exe < example.vlang
	@echo "✓ generated output.c"

# 2) קומפילציית C -> program.exe (שימו לב ל‑runtime.c)
compile-c: generate runtime.c
	$(CC) $(CFLAGS) -o program.exe output.c runtime.c
	@echo "✓ compiled program.exe"

# 3) הרצה
run-c: compile-c
	./program.exe

# שרשור נוח
test: run-c
clean:
	cmd /C "del /Q lex.yy.c parser.tab.c parser.tab.h vlang.exe output.c program.exe 2>nul || exit 0"
