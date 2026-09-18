#include "kvmem-output-limit.h"
#include <cstdio>
#include <cstdlib>

#define CHECK(x) do { if (!(x)) { std::fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); std::abort(); } } while (0)

int main() {
    const int resident = kvmem_generation_limit(131072, true, 2048, true);
    const int standard = kvmem_generation_limit(131072, true, 2048, false);
    CHECK(resident == 131072 && standard == 2048);
    CHECK(kvmem_generation_limit(131072, false, 2048, false) == 131072);
    CHECK(kvmem_generation_limit(1024, true, 2048, false) == 1024);
    CHECK(kvmem_generation_limit(1024, true, UINT32_MAX, false) == 1024);
    CHECK(kvmem_generation_limit(1024, true, 0, false) == 1024);
    for (const char * key : {"max_tokens", "max_completion_tokens"}) {
        int value = 512;
        std::string error;
        CHECK(kvmem_output_limit({{key, 8192}}, resident, value, error) && value == 8192);
        CHECK(!kvmem_output_limit({{key, 8192}}, standard, value, error));
        CHECK(!kvmem_output_limit({{key, 131073}}, resident, value, error));
        CHECK(!kvmem_output_limit({{key, 0}}, resident, value, error));
        CHECK(!kvmem_output_limit({{key, 2.5}}, resident, value, error));
        value = 4096;
        CHECK(kvmem_output_limit({{key, -1}}, resident, value, error) && value == 4096);
    }
    std::puts("output limits PASS");
}
