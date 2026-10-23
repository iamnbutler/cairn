#include <lean/lean.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
extern lean_object* initialize_Deep(uint8_t builtin);
extern void lean_initialize_thread(void);
extern void lean_initialize_runtime_module(void);
extern void lean_finalize_thread(void);
extern size_t deep_wide(size_t);
static size_t N;
static void* run(void* _) { lean_initialize_thread(); printf("n=%zu -> %zu\n", N, deep_wide(N)); fflush(stdout); lean_finalize_thread(); return 0; }
int main(int argc, char** argv) {
  N = strtoull(argv[1], 0, 10); size_t stack = strtoull(argv[2], 0, 10);
  lean_initialize_runtime_module();
  lean_object* r = initialize_Deep(1); lean_dec_ref(r);
  lean_io_mark_end_initialization();
  pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, stack);
  pthread_t t; pthread_create(&t, &a, run, 0); pthread_join(t, 0); return 0;
}
