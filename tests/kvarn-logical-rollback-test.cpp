#include "llama-kv-cache-kvarn.h"
#include "llama-model.h"
#include "llama-batch.h"
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <numeric>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); std::abort(); } } while (0)

static void append(llama_kv_cache & cache, int begin, int count) {
    std::vector<llama_pos> pos(count);
    std::iota(pos.begin(), pos.end(), begin);
    std::vector<llama_token> tokens(count, 1);
    std::vector<int32_t> counts(count, 1);
    llama_seq_id id = 0;
    std::vector<llama_seq_id *> ids(count, &id);
    llama_ubatch ub{};
    ub.b_equal_seqs = 1;
    ub.n_tokens = ub.n_seq_tokens = count;
    ub.n_seqs = ub.n_seqs_unq = ub.n_pos = 1;
    ub.token = tokens.data(); ub.pos = ub.logical_pos = pos.data();
    ub.n_seq_id = counts.data(); ub.seq_id = ids.data(); ub.seq_id_unq = &id;
    auto slots = cache.find_slot(ub, false);
    CHECK(!slots.empty());
    for (int i = 0; i < count; ++i) CHECK(slots.idxs[0][i] == uint32_t(begin + i));
    cache.apply_ubatch(slots, ub);
}

int main() {
    std::unique_ptr<llama_model> model(llama_model_create(LLM_ARCH_LLAMA, llama_model_default_params()));
    // 不加载权重，直接验证真实缓存的 cell 分配和回滚状态机。
    model->hparams.n_layer_all = 0;
    auto params = llama_kvarn_default_params();
    params.type = llama_kvarn_type_from_name("kvarn_k4v4_g128");
    llama_kv_cache_kvarn cache(*model, model->hparams, params, false, true,
        1024, 1, 128, 128, 1, 0, LLAMA_SWA_TYPE_NONE, nullptr, nullptr);
    auto & meta = *cache.get_metadata_cache();
    append(meta, 0, 128);
    append(meta, 128, 4);
    CHECK(cache.seq_rm_logical(0, 130, -1));
    append(meta, 130, 2);
    // 反复拒绝部分草稿，物理位置不能随重试次数漂移。
    for (int i = 0; i < 10; ++i) {
        CHECK(cache.seq_rm_logical(0, 130, -1));
        append(meta, 130, 2);
    }
    CHECK(cache.seq_rm_logical(0, 128, -1));
    append(meta, 128, 128);
    append(meta, 256, 128);
    append(meta, 384, 4);
    // 查询回放必须先检查真实删除能力；拒绝后完整重算，不能把旧位置追加到新 cell。
    CHECK(!llama_memory_can_seq_rm(&cache, 0, 129, 388));
    CHECK(meta.seq_pos_max(0) == 387);
    CHECK(!llama_memory_seq_rm(&cache, 0, 129, 388));
    CHECK(meta.seq_pos_max(0) == 387);
    cache.clear(true);
    append(meta, 0, 128);
    append(meta, 128, 128);
    append(meta, 256, 128);
    append(meta, 384, 4);
    CHECK(llama_memory_can_seq_rm(&cache, 0, 386, 388));
    CHECK(llama_memory_seq_rm(&cache, 0, 386, 388));
    append(meta, 386, 2);
    CHECK(!cache.seq_rm_logical(0, 129, -1));
    CHECK(meta.seq_pos_max(0) == 387);
    CHECK(!cache.seq_rm_logical(0, 380, 385));
    CHECK(meta.seq_pos_max(0) == 387);
    CHECK(cache.seq_rm_logical(0, 1000, -1));
    CHECK(cache.seq_rm_logical(0, 0, -1));
    append(meta, 0, 4);
    CHECK(meta.seq_rm_logical(-1, 0, -1));
    append(meta, 0, 4);
    std::puts("logical rollback PASS");
}
