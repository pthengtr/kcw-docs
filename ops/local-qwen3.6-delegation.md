# Local Qwen3.6-27B (vLLM) — agent delegation playbook

For Cursor / coding agents deciding whether to send work to the **local** OpenAI-compatible model instead of a stronger remote model.

Tested on the DGX Spark box (`vllm-worker` Docker container) on **2026-09-03/04**.

| Item | Value |
|------|--------|
| Endpoint | `http://127.0.0.1:8000/v1` |
| Model id | `qwen3.6-27b` |
| Weights | `Qwen/Qwen3.6-27B-FP8` |
| Tools | auto tool choice, parser `qwen3_coder` |
| Reasoning parser | `qwen3` (thinking **off** by default) |
| Limits | max model len **98304**, max seqs **4**, batched tokens **8192** |
| Phase A | **25 pass / 1 partial / 0 fail** (26 probes) |
| Phase B | **6h soak**, **2037** requests, **0** errors, gold **175/175** |

## How to call it

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:8000/v1", api_key="local")
resp = client.chat.completions.create(
    model="qwen3.6-27b",
    messages=[...],
    tools=tools,  # optional
    temperature=0.2,
)
```

Do not assume thinking / reasoning content is enabled (`enable_thinking` defaults false).

## Decision rules

### Delegate to local Qwen

- **code** — small Python utilities, clear bugfixes, SQL drafts, mechanical language translation
- **tools** — single / parallel tool calls, first hop of multi-tool flows, schema-safe args under messy input
- **instruction** — strict JSON, tight format constraints, personas, ignore jailbreak-style overlays
- **long_context** — fact extract from medium docs, needle-in-haystack, simple multi-doc join
- **agentic** — task breakdown, dependency-aware plans, retry after tool errors
- **knowledge** — stable library facts; refuses invented stdlib APIs (hallucination probe passed)
- **thai** — Thai → English, Thai-only replies, mixed EN/TH instructions

### Delegate only with review

- **reasoning / arithmetic** — multi-step tax / money math near-missed (`21.6` vs correct `22`). Parent agent must verify numbers.

### Do not leave alone without a watcher

- Nothing failed every probe, but **do not** trust unreviewed financial math or execute long plans blindly.
- Keep concurrency **≤ 2–3** (server max-num-seqs=4). Soak validated concurrency **1** for hours.

## Practical guidance

- **Safe defaults:** code edits with a clear spec, SQL drafts, JSON-constrained replies, tool loops, Thai/EN, medium docs, planning drafts, stdlib facts.
- **Always verify:** multi-step arithmetic, money/tax math, final SQL against schema/data, long agent plans before executing.
- **Long jobs:** Phase B supports multi-hour mixed workloads; still checkpoint agent work every **30–60 min**.
- **Ops:** if port `8000` RSTs / no GPU load, `docker restart vllm-worker` and wait for `Application startup complete` (~5–10 min). Model load uses ~28.5 GiB GPU.

## Phase A latency (short suite)

`n=26` — min **0.4s**, p50 **4.4s**, p95 **60.8s**, max **84.9s** (heavy planning replies).

## Phase B soak (6h + marathon)

| Metric | Result |
|--------|--------|
| Requests | 2037 |
| Errors | 0 (0.0%) |
| Gold probes (`17*19`) | 175/175 |
| Tool-call probes | 349/349 |
| Latency | min 0.27s · p50 2.49s · p95 48.54s · max 127.52s |
| Drift | early p50 2.49s → late p50 2.50s (stable) |

Workload mix: json / reason / summary / tool / marathon / code / gold probes.

## Per-test results (Phase A)

| Category | ID | Title | Verdict | Seconds | Why |
|---|---|---|---|---:|---|
| reasoning | `reason_math` | Multi-step arithmetic word problem | **partial** | 0.9 | near-miss: `21.6` (want `22`) |
| reasoning | `reason_logic` | Syllogism | **pass** | 3.0 | |
| reasoning | `reason_grid` | Tiny grid puzzle | **pass** | 0.6 | |
| code | `code_python` | Python function with edge cases | **pass** | 4.4 | |
| code | `code_sql` | SQL from schema | **pass** | 13.0 | |
| code | `code_debug` | Fix buggy snippet | **pass** | 7.1 | |
| code | `code_translate` | Python to TypeScript | **pass** | 4.9 | |
| tools | `tool_single` | Single tool call | **pass** | 5.3 | |
| tools | `tool_chain_first` | First hop of tool chain | **pass** | 3.5 | |
| tools | `tool_parallel` | Parallel tool calls | **pass** | 8.8 | |
| tools | `tool_bad_schema` | Coerce invalid args | **pass** | 5.3 | |
| instruction | `instr_json` | Strict JSON object | **pass** | 3.8 | |
| instruction | `instr_bullets` | Short bullets only | **pass** | 3.2 | |
| instruction | `instr_persona` | Questions-only persona | **pass** | 20.5 | |
| instruction | `instr_injection` | Ignore injection | **pass** | 0.4 | |
| long_context | `ctx_summarize` | Summarize filler + facts | **pass** | 9.6 | |
| long_context | `ctx_needle` | Needle in haystack | **pass** | 3.4 | |
| long_context | `ctx_crossref` | Cross-document reference | **pass** | 0.7 | |
| agentic | `agent_breakdown` | Task breakdown | **pass** | 84.9 | |
| agentic | `agent_self_correct` | Recover from tool error | **pass** | 3.6 | |
| agentic | `agent_plan_deps` | Plan with dependencies | **pass** | 60.8 | |
| knowledge | `know_python` | Library fact | **pass** | 0.5 | |
| knowledge | `know_trap` | Hallucination trap | **pass** | 0.9 | |
| thai | `thai_translate` | Thai to English | **pass** | 1.4 | |
| thai | `thai_reply` | Reply entirely in Thai | **pass** | 6.1 | |
| thai | `thai_mixed` | Mixed-language instruction | **pass** | 8.7 | |

## Related harness (Spark box, not in this repo)

Capability runners live on the Spark machine under `/home/spark/qwen3_capability_test/` (`test_qwen.py`, `soak_qwen.py`, `test_results.json`, `soak_results.jsonl`). Re-run when the model or vLLM flags change.
