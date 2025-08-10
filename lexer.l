%{
#include "parser.tab.h"
#include <string.h>
#include <stdlib.h>
%}

digit     [0-9]
id        [a-zA-Z_][a-zA-Z0-9_]*
ws        [ \t\r\n]+

%%

"{"             { return LBRACE; }
"}"             { return RBRACE; }
"("             { return LPAREN; }
")"             { return RPAREN; }
"["             { return LBRACK; }
"]"             { return RBRACK; }
":"             { return COLON; }
";"             { return SEMICOLON; }
","             { return COMMA; }

"=="            { return EQ; }
"!="            { return NE; }
"<="            { return LE; }
">="            { return GE; }
"<"             { return LT; }
">"             { return GT; }

"="             { return ASSIGN; }
"+"             { return PLUS; }
"-"             { return MINUS; }
"*"             { return TIMES; }
"/"             { return DIVIDE; }
"@"             { return DOTPROD; }

"scl"           { return SCL; }
"vec"           { return VEC; }
"loop"          { return LOOP; }
"if"            { return IF; }
"print"         { return PRINT; }

{digit}+        { yylval.ival = atoi(yytext); return INT; }
{id}            { yylval.sval = strdup(yytext); return ID; }

\"[^"]*\"       {
    yylval.sval = strdup(yytext + 1);
    yylval.sval[strlen(yylval.sval) - 1] = '\0';
    return STRING;
}

"//".*                        { /* ignore single-line comment */ }
"/*"([^*]|\*+[^*/])*\*+"/"    { /* ignore multi-line comment */ }

{ws}            { /* skip whitespace */ }

.               { printf("Unknown character: %s\n", yytext); return UNKNOWN; }

%%

int yywrap() {
    return 1;
}
