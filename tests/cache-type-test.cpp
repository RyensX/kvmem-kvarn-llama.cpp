#include "kvmem-spec.h"

#include <cstdio>

static int failures = 0;

#define CHECK(expr) do { \
    if (!(expr)) { \
        std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); \
        ++failures; \
    } \
} while (0)

int main() {
    ggml_type backing = GGML_TYPE_COUNT;
    int32_t bits = -1;
    CHECK(kvmem_parse_target_cache_type("kvarn4", backing, bits));
    CHECK(bits == 4);
    CHECK(backing == GGML_TYPE_Q4_0);

    llama_kvarn_params kvarn = llama_kvarn_default_params();
    CHECK(kvmem_cache_config(backing, backing, 4, 4, kvarn));
    CHECK(kvarn.type == llama_kvarn_type_from_name("kvarn_k4v4_g128"));
    CHECK(!kvmem_cache_config(backing, backing, 4, 0, kvarn));
    CHECK(!kvmem_parse_target_cache_type("kvarn7", backing, bits));

    if (failures != 0) {
        return 1;
    }
    std::puts("OK");
    return 0;
}
