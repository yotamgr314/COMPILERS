%{
/* -------------------------------------------------------------------------- */
/*  Prologue – headers, helpers & symbol table                                */
/* -------------------------------------------------------------------------- */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

FILE *out;
void yyerror(const char *s);
int  yylex();

/* ---------------- symbol table ---------------- */
char current_vec_name[64] = "";
int  current_vec_size     = 0;
int temp_id_counter = 0;
struct {
    char name[64];
    int  is_vector;
    int  size;
} symbols[100];
int symbol_count = 0;

int  is_vector_var(const char *n){
    for(int i=0;i<symbol_count;++i)
        if(strcmp(symbols[i].name,n)==0) return symbols[i].is_vector;
    return 0;
}
bool is_temp_vector_expr(const char *n){
    return strncmp(n,"temp_vec_expr_",14)==0 ||
           strncmp(n,"temp_index_",11)   ==0;
}

static const char *strip_parens(const char *s) {
    size_t len = strlen(s);
    if (len >= 2 && s[0] == '(' && s[len - 1] == ')') {
        char *tmp = strdup(s + 1);          /* copy without first '(' */
        tmp[len - 2] = '\0';                /* kill last ')'          */
        return tmp;                         /* caller frees if needed */
    }
    return s;
}

int is_vector_expr(const char *s) {
    const char *t = strip_parens(s);     /* NEW */
    int res = is_vector_var(t) || is_temp_vector_expr(t);
    if (t != s) free((char *)t);         /* only free if we duped */
    return res;
}

void register_var(const char *n,int vec,int sz){
    strcpy(symbols[symbol_count].name,n);
    symbols[symbol_count].is_vector = vec;
    symbols[symbol_count].size      = sz;
    ++symbol_count;
    if(vec){ strcpy(current_vec_name,n); current_vec_size=sz; }
}
int  get_vector_size(const char *n){
    for(int i=0;i<symbol_count;++i)
        if(strcmp(symbols[i].name,n)==0) return symbols[i].size;
    return current_vec_size;
}
/*  concat two C snippets  */
static char *cat2(const char *a,const char *b){
    char *r = malloc(strlen(a)+strlen(b)+1);
    strcpy(r,a); strcat(r,b); return r;
}
%}

/* -------------------------------------------------------------------------- */
/*  Bison declarations                                                        */
/* -------------------------------------------------------------------------- */
%union{
    int    ival;
    char  *sval;
    struct{
        char *setup;          /* C stmts that must run first */
        char *code;           /* the C expression itself    */
        char *left,*right;    /* raw operands (analysis)    */
        char  op;             /* '+','-','*','/','@',0      */
    } expr;
    struct{
        char *setup;          /* setup for print list */
        char *code;           /* comma‑separated args */
        int   count;          /* number of args       */
    } plist;
    char *blockcode;          /* generated C for stmt/block */
}

%token <ival> INT
%token <sval> ID STRING
%token SCL VEC LOOP IF PRINT
%token LBRACE RBRACE LPAREN RPAREN LBRACK RBRACK
%token COLON SEMICOLON COMMA ASSIGN
%token PLUS MINUS TIMES DIVIDE DOTPROD
%token UNKNOWN
%token EQ NE LT LE GT GE
/* ---------- operator precedence & associativity ---------- */
%left PLUS MINUS           /* '+' and '-' left‑associative      */
%left TIMES DIVIDE         /* '*' and '/' at a higher precedence */
%left DOTPROD  
%type <expr>    expression indexed_expr
%type <sval>    int_list
%type <plist>   print_list
%type <blockcode> program block statement_list statement
%type <blockcode> if_statement loop_statement assignment print_statement

%start program

%%  /* ===============================  grammar  ============================== */

/* ---------------- program & blocks ---------------- */
program
    : block                         { fprintf(out,"%s",$1); free($1); }
    ;

block
    : LBRACE statement_list RBRACE  { $$ = $2; }
    ;

statement_list
    : statement_list statement      { $$ = cat2($1,$2); free($1); free($2); }
    | statement                     { $$ = $1; }
    ;

statement
    : declaration                   { $$ = strdup(""); }
    | assignment                    { $$ = $1; }
    | if_statement                  { $$ = $1; }
    | loop_statement                { $$ = $1; }
    | print_statement               { $$ = $1; }
    ;

/* ---------------- declarations ---------------- */
declaration
    : SCL ID SEMICOLON
        { fprintf(out,"int %s = 0;\n",$2); register_var($2,0,1); }
    | VEC ID LBRACE INT RBRACE SEMICOLON
        { fprintf(out,"int %s[%d] = {0};\n",$2,$4); register_var($2,1,$4); }
    ;

/* ---------------- assignments ---------------- */
assignment
    : ID ASSIGN LBRACK int_list RBRACK SEMICOLON      /* vector literal */
        {
            static int t=0; char tmp[64]; sprintf(tmp,"temp_vec_%d",t++);
            char buf[256+strlen($4)];
            sprintf(buf,
                "int %s[] = {%s};\n"
                "memcpy(%s,%s,sizeof(int)*%d);\n",
                tmp,$4,$1,tmp,current_vec_size);
            $$ = strdup(buf); free($4);
        }

      /* ---------------- v / scl assignment ---------------- */
    | ID ASSIGN expression SEMICOLON
        {
            /*  run any setup statements produced while parsing the RHS  */
            char *buf = cat2($3.setup, "");

            /* 1. RHS is a **temporary** vector we built earlier */
            if (is_temp_vector_expr($3.code)) {
                char rhs[128];
                sprintf(rhs,
                        "memcpy(%s, %s, sizeof(int)*%d);\n",
                        $1, $3.code, current_vec_size);
                buf = cat2(buf, rhs);
            }

            /* 2. destination is **scalar** → simple scalar assignment   */
            else if (!is_vector_var($1)) {
                char rhs[128];
                sprintf(rhs, "%s = %s;\n", $1, $3.code);
                buf = cat2(buf, rhs);
            }

            /* 3. pattern  v = v2 : v1   (vector‑by‑vector indexing)     */
            else if ($3.left && $3.right &&
                     is_vector_expr($3.left) &&
                     is_vector_expr($3.right) &&
                     $3.op == 0)
            {
                char rhs[160];
                sprintf(rhs,
                        "vector_index_by_vector(%s, %s, %s, %d);\n",
                        $1, $3.left, $3.right, current_vec_size);
                buf = cat2(buf, rhs);
            }

            /* 4. **new branch**  simple vector‑to‑vector copy: y = x;   */
            else if (is_vector_expr($3.code) &&     /* RHS is a vector  */
                     $3.right == NULL &&            /* not an op result */
                     $3.op == 0)
            {
                char rhs[128];
                sprintf(rhs,
                        "memcpy(%s, %s, sizeof(int)*%d);\n",
                        $1, $3.code, current_vec_size);
                buf = cat2(buf, rhs);
            }

            /* 5. broadcast of scalar / literal into vector             */
            else if ($3.op == 0) {
                char rhs[160];
                sprintf(rhs,
                        "for(int i=0; i<%d; ++i) %s[i] = %s;\n",
                        current_vec_size, $1, $3.code);
                buf = cat2(buf, rhs);
            }

            /* 6. vector‑scalar & vector‑vector arithmetic               */
            else {
                int l = is_vector_expr($3.left);
                int r = is_vector_expr($3.right);
                char rhs[192];

                if (!l && !r)                                   /* s op s */
                    sprintf(rhs,
                        "for(int i=0; i<%d; ++i) %s[i] = %s;\n",
                        current_vec_size, $1, $3.code);
                else if (l && !r)                               /* v op s */
                    sprintf(rhs,
                        "vector_scalar_op(%s, %s, %s, %d, '%c');\n",
                        $1, $3.left,  $3.right,
                        current_vec_size, $3.op);
                else if (!l && r)                               /* s op v */
                    sprintf(rhs,
                        "vector_scalar_op(%s, %s, %s, %d, '%c');\n",
                        $1, $3.right, $3.left,
                        current_vec_size, $3.op);
                else                                            /* v op v */
                    sprintf(rhs,
                        "vector_vector_op(%s, %s, %s, %d, '%c');\n",
                        $1, $3.left, $3.right,
                        current_vec_size, $3.op);

                buf = cat2(buf, rhs);
            }

            $$ = buf;
            free($3.code);
            free($3.setup);
        }


    | ID COLON INT ASSIGN expression SEMICOLON
        {
            char *buf = cat2($5.setup,"");
            char rhs[160];
            sprintf(rhs,"%s[%d] = %s;\n",$1,$3,$5.code);
            buf = cat2(buf,rhs); $$ = buf;
            free($5.code); free($5.setup);
        }

    | ID COLON expression ASSIGN expression SEMICOLON
        {
            char *buf = cat2($3.setup,$5.setup);
            char rhs[192];
            sprintf(rhs,"%s[(int)(%s)] = %s;\n",$1,$3.code,$5.code);
            buf = cat2(buf,rhs); $$ = buf;
            free($3.code); free($3.setup);
            free($5.code); free($5.setup);
        }
    ;

/* ---------------- helpers ---------------- */
int_list
    : INT            { char tmp[32]; sprintf(tmp,"%d",$1); $$=strdup(tmp); }
    | int_list COMMA INT
        { char *b=malloc(strlen($1)+32); sprintf(b,"%s,%d",$1,$3); free($1); $$=b; }
    ;

/* ---------------- expressions ---------------- */
expression
    : INT
        {
            char tmp[32]; sprintf(tmp,"%d",$1);
            $$.setup=strdup(""); $$.code=strdup(tmp);
            $$.left=$$.code; $$.right=NULL; $$.op=0;
        }
    | ID
        { $$.setup=strdup(""); $$.code=strdup($1);
          $$.left=$$.code; $$.right=NULL; $$.op=0; }

  /* --------------- arithmetic '+' ---------------- */
    | expression PLUS expression
        {
            $$.setup = cat2($1.setup, $3.setup);
            int l = is_vector_expr($1.code);
            int r = is_vector_expr($3.code);

            if (l && r) {                                   /* v + v */
                char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
                char buf[256];
                sprintf(buf,
                    "int %s[%d];\n"
                    "vector_vector_op(%s, %s, %s, %d, '+');\n",
                    tmp, current_vec_size, tmp, $1.code, $3.code, current_vec_size);
                $$.setup = cat2($$.setup, buf);
                $$.code  = strdup(tmp);
            } else if (l || r) {                            /* v + s | s + v */
                char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
                char buf[256];
                const char *vec = l ? $1.code : $3.code;
                const char *scl = l ? $3.code : $1.code;
                sprintf(buf,
                    "int %s[%d];\n"
                    "vector_scalar_op(%s, %s, %s, %d, '+');\n",
                    tmp, current_vec_size, tmp, vec, scl, current_vec_size);
                $$.setup = cat2($$.setup, buf);
                $$.code  = strdup(tmp);
            } else {                                        /* s + s */
                char *code = malloc(strlen($1.code)+strlen($3.code)+4);
                sprintf(code,"%s + %s",$1.code,$3.code);
                $$.code = code;
            }
            $$.left = $1.code; $$.right = $3.code; $$.op = '+';
        }

/* --------------- arithmetic '-' ---------------- */
    | expression MINUS expression
        {
            $$.setup = cat2($1.setup, $3.setup);
            int l = is_vector_expr($1.code);
            int r = is_vector_expr($3.code);

            if (l && r) {                                   /* v - v */
                char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
                char buf[256];
                sprintf(buf,
                    "int %s[%d];\n"
                    "vector_vector_op(%s, %s, %s, %d, '-');\n",
                    tmp, current_vec_size, tmp, $1.code, $3.code, current_vec_size);
                $$.setup = cat2($$.setup, buf);
                $$.code  = strdup(tmp);
            } else if (l || r) {                            /* v - s | s - v */
                char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
                char buf[256];
                const char *vec = l ? $1.code : $3.code;
                const char *scl = l ? $3.code : $1.code;
                /* order matters for scalar‑vector vs vector‑scalar */
                if (l) /* v - s */
                    sprintf(buf,
                        "int %s[%d];\n"
                        "vector_scalar_op(%s, %s, %s, %d, '-');\n",
                        tmp, current_vec_size, tmp, vec, scl, current_vec_size);
                else   /* s - v */
                    sprintf(buf,
                        "int %s[%d];\n"
                        "vector_scalar_op(%s, %s, %s, %d, '-');\n",
                        tmp, current_vec_size, tmp, scl, vec, current_vec_size);
                $$.setup = cat2($$.setup, buf);
                $$.code  = strdup(tmp);
            } else {                                        /* s - s */
                char *code = malloc(strlen($1.code)+strlen($3.code)+4);
                sprintf(code,"%s - %s",$1.code,$3.code);
                $$.code = code;
            }
            $$.left = $1.code; $$.right = $3.code; $$.op = '-';
        }

/* --------------- arithmetic '*' ---------------- */
    | expression TIMES expression
        {
            $$.setup = cat2($1.setup, $3.setup);
            int l = is_vector_expr($1.code);
            int r = is_vector_expr($3.code);

            if (l && r) {                                   /* v * v */
                char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
                char buf[256];
                sprintf(buf,
                    "int %s[%d];\n"
                    "vector_vector_op(%s, %s, %s, %d, '*');\n",
                    tmp, current_vec_size, tmp, $1.code, $3.code, current_vec_size);
                $$.setup = cat2($$.setup, buf);
                $$.code  = strdup(tmp);
            } else if (l || r) {                            /* v * s | s * v */
                char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
                char buf[256];
                const char *vec = l ? $1.code : $3.code;
                const char *scl = l ? $3.code : $1.code;
                sprintf(buf,
                    "int %s[%d];\n"
                    "vector_scalar_op(%s, %s, %s, %d, '*');\n",
                    tmp, current_vec_size, tmp, vec, scl, current_vec_size);
                $$.setup = cat2($$.setup, buf);
                $$.code  = strdup(tmp);
            } else {                                        /* s * s */
                char *code = malloc(strlen($1.code)+strlen($3.code)+4);
                sprintf(code,"%s * %s",$1.code,$3.code);
                $$.code = code;
            }
            $$.left = $1.code; $$.right = $3.code; $$.op = '*';
        }

| expression DIVIDE expression
{
    $$.setup = cat2($1.setup, $3.setup);
    int l = is_vector_expr($1.code);
    int r = is_vector_expr($3.code);

    if (l && r) {
        char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
        char buf[256];
        sprintf(buf,
            "int %s[%d];\n"
            "vector_vector_op(%s, %s, %s, %d, '/');\n",
            tmp, current_vec_size, tmp, $1.code, $3.code, current_vec_size);
        $$.setup = cat2($$.setup, buf);
        $$.code = strdup(tmp);
    } else if (l || r) {
        char tmp[64]; sprintf(tmp,"temp_vec_expr_%d", temp_id_counter++);
        char buf[256];
        const char *vec = l ? $1.code : $3.code;
        const char *scl = l ? $3.code : $1.code;
        sprintf(buf,
            "int %s[%d];\n"
            "vector_scalar_op(%s, %s, %s, %d, '/');\n",
            tmp, current_vec_size, tmp, vec, scl, current_vec_size);
        $$.setup = cat2($$.setup, buf);
        $$.code = strdup(tmp);
    } else {
        char *code = malloc(strlen($1.code)+strlen($3.code)+4);
        sprintf(code,"%s / %s",$1.code,$3.code);
        $$.code = code;
    }

    $$.left = $1.code;
    $$.right = $3.code;
    $$.op = '/';
}



    | LPAREN expression RPAREN
        {
            char *code = malloc(strlen($2.code)+3);
            sprintf(code,"(%s)",$2.code);
            $$.setup=$2.setup; $$.code=code;
            $$.left=$2.left; $$.right=$2.right; $$.op=$2.op;
        }

    | indexed_expr                 { $$=$1; }

   | expression COLON expression
{
    char *setup = cat2($1.setup, $3.setup);

    if (!is_vector_expr($3.code)) {
        // scalar index
        char buf[512];
        sprintf(buf, "%s[(int)(%s)]", $1.code, $3.code);
        $$.setup = setup;
        $$.code = strdup(buf);
        $$.left = strdup($1.code);
        $$.right = strdup($3.code);
        $$.op = 0;
    } else {
        // vector index
       char tmp[64]; sprintf(tmp,"temp_index_%d",temp_id_counter++);
        char prep[256];
        sprintf(prep,
            "int %s[%d];\n"
            "vector_index_by_vector(%s,%s,%s,%d);\n",
            tmp, current_vec_size, tmp, $1.code, $3.code, current_vec_size);
        setup = cat2(setup, prep);
        $$.setup = setup;
        $$.code = strdup(tmp);
        $$.left = strdup($1.code);
        $$.right = strdup($3.code);
        $$.op = 0;
    }
}


  | expression DOTPROD expression
{
    if (!is_vector_expr($1.code) || !is_vector_expr($3.code)) {
        yyerror("dot product '@' requires both operands to be vectors");
        YYABORT;
    }

    char *setup = cat2($1.setup,$3.setup);
    int sz = current_vec_size;
    if ($1.left) sz = get_vector_size($1.left);

    char *code = malloc(strlen($1.code)+strlen($3.code)+32);
    sprintf(code,"dot_product(%s,%s,%d)",$1.code,$3.code,sz);

    $$.setup = setup; $$.code = code;
    $$.left = $1.code; $$.right = $3.code; $$.op = '@';
}


   | LBRACK int_list RBRACK       /* literal vector */
    {
        char tmp[64]; sprintf(tmp,"temp_vec_expr_%d",temp_id_counter++);

            char prep[256+strlen($2)];
            sprintf(prep,"int %s[] = {%s};\n",tmp,$2);
            $$.setup=strdup(prep); $$.code=strdup(tmp);
            $$.left=$$.code; $$.right=NULL; $$.op=0; free($2);
        }
        | expression EQ expression
    {
        $$.setup = cat2($1.setup, $3.setup);
        char *code = malloc(strlen($1.code)+strlen($3.code)+6);
        sprintf(code, "%s == %s", $1.code, $3.code);
        $$.code = code;
        $$.left = $1.code; $$.right = $3.code; $$.op = 0;
    }

| expression NE expression
    {
        $$.setup = cat2($1.setup, $3.setup);
        char *code = malloc(strlen($1.code)+strlen($3.code)+6);
        sprintf(code, "%s != %s", $1.code, $3.code);
        $$.code = code;
        $$.left = $1.code; $$.right = $3.code; $$.op = 0;
    }

    ;

/* ---------------- indexed_expr ---------------- */
indexed_expr
    : ID COLON INT
        {
            char buf[256]; sprintf(buf,"%s[%d]",$1,$3);
            $$.setup=strdup(""); $$.code=strdup(buf);
            $$.left=strdup($1);
            char idx[32]; sprintf(idx,"%d",$3);
            $$.right=strdup(idx); $$.op=0;
        }
    | ID COLON expression
        {
            char *setup = $3.setup;
            if(is_vector_expr($3.code)){
                static int t=0; char tmp[64]; sprintf(tmp,"temp_index_%d",t++);
                char prep[256];
                sprintf(prep,
                    "int %s[%d];\n"
                    "vector_index_by_vector(%s,%s,%s,%d);\n",
                    tmp,current_vec_size,tmp,$1,$3.code,current_vec_size);
                setup = cat2(setup,prep);
                $$.code=strdup(tmp);
            }else{
                char buf[512]; sprintf(buf,"%s[(int)(%s)]",$1,$3.code);
                $$.code=strdup(buf);
            }
            $$.setup=setup; $$.left=strdup($1); $$.right=strdup($3.code); $$.op=0;
            free($3.code);
        }
    ;

/* ---------------- control flow ---------------- */
if_statement
    : IF expression block
        {
            char *buf = cat2($2.setup,"");
            char head[64+strlen($2.code)];
            sprintf(head,"if(%s){\n",$2.code);
            buf = cat2(buf,head); buf = cat2(buf,$3); buf = cat2(buf,"}\n");
            $$ = buf; free($2.code); free($2.setup); free($3);
        }
    ;

loop_statement
    : LOOP expression block
        {
            char *buf = cat2($2.setup,"");
            char head[80+strlen($2.code)];
            sprintf(head,"for(int __i=0;__i<%s;++__i){\n",$2.code);
            buf = cat2(buf,head); buf = cat2(buf,$3); buf = cat2(buf,"}\n");
            $$ = buf; free($2.code); free($2.setup); free($3);
        }
    ;

/* ---------------- print_list ---------------- */
print_list
    : expression
        {                       /* first item                          */
            $$.setup = $1.setup;
            $$.code  = strdup($1.code);     /* no separator yet         */
            $$.count = 1;
        }
    | print_list COMMA expression
        {                       /* append item, join with ‘|’          */
            $$.setup = cat2($1.setup, $3.setup);

            size_t len = strlen($1.code) + strlen($3.code) + 2; /* '|' + NUL */
            char *code = malloc(len);
            sprintf(code, "%s|%s", $1.code, $3.code);

            free($1.code);
            $$.code  = code;
            $$.count = $1.count + 1;
        }
    ;

/* ---------------- print_statement ---------------- */
print_statement
    : PRINT STRING COLON print_list SEMICOLON
    {
        /* 1. emit all setup code from sub‑expressions */
        char *buf  = cat2($4.setup, "");
        char *line = malloc(1024);

        /* 2. heading — prints the label and a colon (no newline) */
        sprintf(line, "printf(\"%s: \");\n", $2);
        buf = cat2(buf, line);

        /* 3. iterate over the saved expressions, split on ‘|’          */
        /*    we know how many there are from $4.count                   */
        char *list_copy = strdup($4.code);          /* strtok mutates    */
        char *token     = strtok(list_copy, "|");
        int   idx       = 0;                        /* 1‑based position  */

        while (token) {
            ++idx;
            /* trim leading blanks the user may have typed after ','     */
            while (*token == ' ') ++token;

            bool last = (idx == $4.count);          /* last expression?  */

            if (is_vector_expr(token)) {
                /* vector: we want newline at the end no matter what     */
                sprintf(line,
                        "print_vector(\"\", %s, %d);\n",
                        token, current_vec_size);
            } else {
                /* scalar: newline only if this is the last item         */
                if (last)
                    sprintf(line, "printf(\"%%d\\n\", %s);\n", token);
                else
                    sprintf(line, "printf(\"%%d \", %s);\n",  token);
            }
            buf = cat2(buf, line);
            token = strtok(NULL, "|");
        }

        $$ = buf;

        free(list_copy);
        free($4.code);
        free($4.setup);
    }
;


%% /* ============================  driver  ============================ */

void yyerror(const char *s){ fprintf(stderr,"Parse error: %s\n",s); }

int main(){
    out=fopen("output.c","w");
    if(!out){ perror("output.c"); return 1; }
    fprintf(out,
        "#include <stdio.h>\n"
        "#include <string.h>\n"
        "#include \"runtime.h\"\n"
        "int main(){\n");
    yyparse();
    fprintf(out,"return 0;\n}\n");
    fclose(out);
    return 0;
}
