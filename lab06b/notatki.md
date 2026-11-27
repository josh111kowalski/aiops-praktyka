## przed filtrem: 
┌─────────────────────────────┬───────┬─────────────────┐
│           Target            │ Type  │ Vulnerabilities │
├─────────────────────────────┼───────┼─────────────────┤
│ loadgen/requirements.txt    │  pip  │        0        │
├─────────────────────────────┼───────┼─────────────────┤
│ orders-api/requirements.txt │  pip  │        0        │
├─────────────────────────────┼───────┼─────────────────┤
│ orders-api/uv.lock          │  uv   │       10        │
├─────────────────────────────┼───────┼─────────────────┤
│ payments/go.mod             │ gomod │        2        │
├─────────────────────────────┼───────┼─────────────────┤
│ worker/requirements.txt     │  pip  │        0        │
└─────────────────────────────┴───────┴─────────────────┘

## po filtrze 
orders-api/uv.lock (uv)

Total: 4 (HIGH: 3, CRITICAL: 1)

payments/go.mod (gomod)

Total: 1 (HIGH: 1, CRITICAL: 0)