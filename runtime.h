// runtime.h

#ifndef RUNTIME_H
#define RUNTIME_H

void vector_scalar_op(int* dst, int* src, int val, int size, char op);
void vector_vector_op(int* dst, int* a, int* b, int size, char op);
int dot_product(int* a, int* b, int size); // for future support
void vector_index_by_vector(int* dst, int* vec, int* indices, int size);
void print_vector(const char* label, int* vec, int size);
#endif
