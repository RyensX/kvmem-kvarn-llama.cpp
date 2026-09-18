#!/usr/bin/env python3
"""检查无 GPU 测试难以执行的 server 默认路由及异常恢复顺序。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
server = (ROOT / 'tools/llama-kvmem-server.cpp').read_text()
multimodal = (ROOT / 'tools/kvmem-multimodal-server.h').read_text()


def body(source, signature):
    start = source.index('{', source.index(signature))
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


assert 'bool query_policy_user = true;' in server
route = body(server, 'static bool run_prefill_retrieval(')
assert 'if (st.vision || st.query_policy_user) return run_prefill_multimodal' in route
restore = body(multimodal, 'static void multimodal_restore(')
mutation = restore.index('llama_state_seq_set_data_ext(')
for context in ('st.ctx', 'st.spec.ctx_dft'):
    assert restore.index(f'llama_kvmem_can_restore_logical({context}, checkpoint.row)') < mutation
assert restore.count('throw multimodal_rebuild_required(') == 3
prefill = body(multimodal, 'static bool run_prefill_multimodal(')
assert 'if (replay && !allow_replay)' in prefill
assert prefill.index('replay = false;', prefill.index('if (replay && !allow_replay)')) < prefill.index('multimodal_restore(st, query_checkpoint, false)')
retry = prefill[prefill.index('catch (const multimodal_rebuild_required & e)'):]
assert retry.index('memory_clear_all(st);') < retry.index('run_prefill_multimodal(st, io, n_cache_hit, false)')
assert 'if (allow_replay) return run_prefill_multimodal(st, io, n_cache_hit, false);' in retry
assert 'if (n_cache_hit) *n_cache_hit = 0;' in retry
finish = body(multimodal, 'static void multimodal_finish_request(')
assert 'memory_clear_all(st);' in finish[finish.index('catch ('):]
print('Default query replay safety source invariants: OK')
