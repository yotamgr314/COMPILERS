#include <stdio.h>   // printf
#include <string.h>  // strlen, memcpy

#include "runtime.h"

int dot_product(int* a, int* b, int size) {
    int sum = 0;
    for (int i = 0; i < size; ++i)
        sum += a[i] * b[i];
    return sum;
}

void vector_scalar_op(int* dst, int* src, int val, int size, char op) {
    for (int i = 0; i < size; ++i) {
        switch (op) {
            case '+': dst[i] = src[i] + val; break;
            case '-': dst[i] = src[i] - val; break;
            case '*': dst[i] = src[i] * val; break;
            case '/': dst[i] = val != 0 ? src[i] / val : 0; break;
        }
    }
}

void vector_vector_op(int* dst, int* a, int* b, int size, char op) {
    for (int i = 0; i < size; ++i) {
        switch (op) {
            case '+': dst[i] = a[i] + b[i]; break;
            case '-': dst[i] = a[i] - b[i]; break;
            case '*': dst[i] = a[i] * b[i]; break;
            case '/': dst[i] = b[i] != 0 ? a[i] / b[i] : 0; break;
        }
    }
}

void vector_index_by_vector(int* dst, int* vec, int* indices, int size) {
    for (int i = 0; i < size; ++i) {
        int idx = indices[i];
        dst[i] = (idx >= 0 && idx < size) ? vec[idx] : 0;
    }
}

void print_vector(const char* label, int* vec, int size) {
    if (label && strlen(label) > 0) {
        printf("%s: [", label);
    } else {
        printf("[");
    }

    for (int i = 0; i < size; ++i) {
        printf("%d", vec[i]);
        if (i < size - 1)
            printf(", ");
    }
    printf("]\n");
}
