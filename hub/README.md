# Local JupyterHub harness for testing the notebook container

Runs JupyterHub as a container on the docker-ce daemon inside WSL2 (no Docker
Desktop) and spawns the repo's notebook image (`jupyter-ai:local`, built from
the root `Dockerfile`) as one sibling container per user via DockerSpawner.

Verified working: hub 6.2.0 + dockerspawner 14.0.0 spawning
`jupyter-ai:local` (jupyterhub 6.2.0, jupyterlab 4.6.6); lab page 200 and all
`jupyter_ai*` extensions present in the spawned container; jupyter-ai chat
persona answering via the Sands AI gateway (DeepSeek V4.1 Flash and
Qwen3.8 27B, HTTPS + scoped virtual key).

## Files

| file | role |
|---|---|
| `Dockerfile.jupyterhub` | hub image = `quay.io/jupyterhub/jupyterhub:6.2.0` + `dockerspawner==14.0.0` |
| `jupyterhub_config.py` | DockerSpawner wiring; baked into the hub image |
| `docker-compose.yml` | hub container on `jupyterhub-network`, docker.sock mounted, port `127.0.0.1:8000` only |
| `smoke-test.sh` | E2E: login (dummy auth + xsrf) → spawn → wait ready → lab 200 → `/api/status` → jupyter-ai extensions |

## Run

From Windows (docker CLI with `DOCKER_HOST=tcp://127.0.0.1:2375` pointing at
the WSL engine) or from inside WSL — the config is baked into the image, so
either side works:

```bash
docker compose -f hub/docker-compose.yml up -d --build
# browser: http://localhost:8000  (any username, any password)
```

```bash
# scripted E2E (run inside WSL, or anywhere with curl+docker):
cd hub && ./smoke-test.sh
```

The `jupyterhub` version inside `DOCKER_NOTEBOOK_IMAGE` must match
`JUPYTERHUB_VERSION` in `Dockerfile.jupyterhub` (both 6.2.0 today); bump them
together with `requirements.txt`.

## How it works

```mermaid
flowchart LR
    B[Windows browser<br/>localhost:8000] -->|WSL2 localhost forwarding| P
    subgraph docker-ce in WSL2
        P[configurable-http-proxy<br/>hub container :8000] --> H[JupyterHub 6.2.0<br/>+ dockerspawner]
        H -->|/var/run/docker.sock<br/>docker SDK] D[dockerd]
        D --> S[jupyter-smoke<br/>jupyter-ai:local :8888]
        P -->|/user/smoke/*| S
        H <-.->|hub API :8081 via network DNS| S
    end
```

- Sibling containers join `jupyterhub-network`; the hub is reached by container
  name (`hub_connect_ip=jupyterhub`), never via host ports — this is the fix
  for the classic WSL2 "spawned container can't reach the hub / redirect loop"
  failure (`hub_ip=127.0.0.1` inside a container is wrong).
- No `Spawner.cmd` override needed: docker-stacks `start-notebook.py` sees
  `JUPYTERHUB_API_TOKEN` and execs `start-singleuser.py`
  → `jupyterhub-singleuser`.
- Each user gets a named volume at `/home/jovyan/work`; a fresh volume
  inherits uid-1000 ownership from the image, so no root container needed.
- Hub state persists in the `jupyterhub-data` volume (sqlite + cookie secret).

## WSL2 / environment traps hit here

- **docker-ce inside WSL, not Docker Desktop.** Windows `docker` CLI talks to
  it via `DOCKER_HOST=tcp://127.0.0.1:2375`. Over that TCP endpoint
  `docker exec`/`docker run` attach streams are dropped (no output) — use WSL
  curl or logs/inspect instead.
- **Docker client proxy config reaches build and run.** A dead `proxies.default`
  in `~/.docker/config.json` is injected into every `RUN` and every `docker run`,
  which breaks `pip install` and all in-container HTTP (`urllib` honors
  `http_proxy`). Fix it in the client config; stripping the variables inside a
  Dockerfile also breaks builds on hosts whose proxy actually works.
- **Port published on 127.0.0.1 only**: dummy auth + a docker-socket-mounted
  hub must never face the LAN; WSL2 localhost forwarding still serves the
  Windows browser. LAN access would additionally need `netsh portproxy` +
  firewall rules (and a real authenticator first).
- **Scripted hub auth**: a static admin token via `JupyterHub.services`
  api_token 403'd here on 6.2.0; cause unconfirmed (the inspected source does
  register the configured token before generating a replacement, so this
  should have worked). `smoke-test.sh` sidesteps it with the browser
  cookie/xsrf flow, which needs no tokens.
- 16 GB WSL2 RAM: the notebook image is 14 GB on disk; spawn takes ~30 s.

## Test-only knobs

- `DOCKER_NOTEBOOK_IMAGE` (default `jupyter-ai:local`), `DOCKER_NOTEBOOK_PULL_POLICY`,
  `SPAWN_MEM_LIMIT` (e.g. `8G`), `JUPYTERHUB_ADMIN`.
- Dummy authenticator + `remove=True` (containers deleted on stop): local
  testing only, never production.

## Kernels: Python 3.12 fallback

The server, `jupyter-ai` and the MCP tool stack run on the base 3.13 interpreter.
The image also ships a conda env `/opt/conda/envs/py312` (Python 3.12.16)
registered as kernelspec **`python312`** ("Python 3.12"), with the same Python
science stack as the base (numpy, pandas, scipy, matplotlib, seaborn,
scikit-learn, statsmodels, sympy, numba, bokeh, altair, ipywidgets; R/Julia
stay 3.13-side). `mamba create -p` keeps the base env untouched; cost is a
254 MB solve at build time.

Verified 2026-11-24 on the rebuilt image: launcher shows the "Python 3.12"
notebook and console cards; a cell reports `PY 3.12.16 /opt/conda/envs/py312`,
numpy 2.5.5 / pandas 3.1.1 / matplotlib 3.11.2, and an inline chart renders.

MCP tool state on the same image, measured with `fastmcp.Client` against
`localhost:3001/mcp`:

| notebook state | abs path | rel path |
|---|---|---|
| not open in Lab (no frontend doc) | create/insert/read/cell-id all OK; insert reports "inserted … on disk" | same, all OK |
| open in Lab (live YDoc) | all OK; insert goes through the YDoc, lands on disk after autosave, and returns an **empty** MCP result (no `success`/`cellId`) | same |

So: every operation succeeds in both states and both path forms, but on the
live-YDoc path the write tools give no confirmation payload — verify the file
(or the tab), not the response text. `cell_index` is 1-based; opening a
cell-less notebook in the frontend adds an empty first cell, so index 1 can
resolve to that new empty cell if you race the save.

Why not just switch the base: docker-stacks publishes exactly one Python minor
(CI has no Python axis; `ARG PYTHON_VERSION=3.13` in
`docker-stacks-foundation`), so `quay.io/jupyter/datascience-notebook:python-3.12`
is frozen at **2025-08-12** (Python 3.12.11, conda R/Julia 15 months old, no
upstream rebuilds). An extra env gets 3.12 on a maintained base. Full
requirements resolve on 3.12 unchanged (uv solve → same versions), so the env
needs no pin divergence.

## Model provider: Sands AI gateway

The notebook image ships one opencode provider (root `opencode.config.json` →
`~/.config/opencode/opencode.json`): provider id `litellm`, label **Sands**,
`npm: "@ai-sdk/openai-compatible"`. Nothing secret and no endpoint is baked in —
`baseURL` and `apiKey` resolve from `OPENAI_API_BASE` / `OPENAI_API_KEY`, which
`startup-env.sh` (installed as `start-notebook.d/10-ai-gateway-env.sh`) exports
from **`/home/jovyan/.env`**, the documented deployment contract:

```bash
cat > /home/jovyan/.env << 'EOF'
OPENAI_API_BASE=https://<gateway-host>/v1
OPENAI_API_KEY=<virtual key>
EOF
```

Point `OPENAI_API_BASE` at your gateway's `/v1`. If the gateway presents a
private root CA, mount the PEM under `/home/jovyan/.certs/`; `startup-env.sh`
merges it into a bundle and exports `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE` and
`CURL_CA_BUNDLE` — then pass the same file to `curl --cacert` below.

Model allowlist — exactly two, everything else is removed from the registry:

| model id | picker label | limit (context / output) | input budget |
|---|---|---|---|
| `deepseek-v4.1-flash` | `Sands/DeepSeek V4.1 Flash (Sands)` | 327680 / 65536 | 262144 |
| `Qwen/Qwen3.8-27B` | `Sands/Qwen3.8 27B (Sands)` | 655360 / 131072 | 524288 |

`context` is the **total** window: opencode's compaction threshold is
`context − min(limit.output, OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX)`, so
`context = input + output`. That env flag defaults to 32000 and caps every
request's `max_tokens`; the Dockerfile raises it to 131072 so each model's own
`limit.output` decides (verified by capturing request bodies: 65536 and 131072).

`disabled_providers: ["opencode", "openai"]` is mandatory. `OPENAI_API_KEY` is
also the trigger for opencode's built-in OpenAI provider — leaving it enabled
re-adds `gpt-4o`/`gpt-5`/… to the picker and would send the gateway key and the
prompt to `api.openai.com`.

Never wire the gateway **master key**. Mint a short-lived, model-scoped virtual
key (master key → `/key/generate`; the secret is in the response's `key` field,
not `token`) and strip any trailing CR/LF — a stray character is interpolated
into the JSONC config and opencode prints it verbatim in the parse error:

```bash
curl -X POST --cacert <private-root-ca>.crt \
  -H "Authorization: Bearer $MASTER" -H "Content-Type: application/json" \
  -d '{"key_alias":"jupyter-ai-<date>","models":["deepseek-v4.1-flash","Qwen/Qwen3.8-27B"],"max_budget":5,"budget_duration":"1d","duration":"24h"}' \
  https://<gateway-host>/key/generate
```

Hand it to the hub — the spawner forwards it into every spawned container:

```bash
OPENAI_API_BASE=https://<gateway-host>/v1 OPENAI_API_KEY=sk-… \
  docker compose -f hub/docker-compose.yml up -d
```

Verified end-to-end (2026-11-26, the image built from this repo):
picker lists exactly the three rows above; a chat turn creates a notebook via
the Jupyter MCP tools and answers with the model name; switching to Qwen and
sending a prompt replies from `Qwen/Qwen3.8-27B` (attributed in
`~/.local/share/opencode/log/opencode.log`); the composer meter reads
`of 328k` / `of 655k` for the two models.

opencode 1.19.6 uses the **v1 config schema** (`provider` singular,
`npm: "@ai-sdk/openai-compatible"`, `options.baseURL/apiKey`); the current
docs' `providers`/`package`/`settings` shape is silently dropped with the log
line "Omitted native setting that cannot be represented in V1".

## Agent notebook tools: frontend dependency (fixed)

Symptom seen in chat: `✗ Jupyter_MCP_Server_read_notebook_cells` →
`Error calling tool 'read_notebook_cells': 'content'`, same for
`read_notebook` / `get_cell_id_from_index`, and
`{"success":false,"error":"Command timed out after 10.0 seconds"}` for
`insert_cell` / `run_all_cells`.

Measured with one controlled client per image (`old-probe` =
`jupyter_ai_tools` 0.7.0, no RTC; `new-probe` = this image), calling the MCP
server on port 3001 with an absolute path
`/home/jovyan/work/sample_charts.ipynb` vs the root-relative
`sample_charts.ipynb`, notebook rendered in a browser tab where noted:

| client state | absolute path | relative path |
|---|---|---|
| old, no browser | reads `'content'` KeyError, writes 10 s timeout | same failures |
| old, notebook rendered in tab | **reads `'content'` KeyError, `insert_cell` 10 s timeout** | all succeed |
| new, no browser | all succeed (file) | all succeed |
| new, notebook rendered in tab | all succeed | all succeed |

Two distinct defects, in order of what actually bit us:

1. **Path form (the trigger).** In the RTC-free frontend path the tools pass the
   path verbatim to `jupyterlab-ai-commands:get-notebook-content`. An absolute
   filesystem path does not match the open document, which is keyed by its
   root-relative path — so even a perfectly healthy, fully rendered frontend
   fails for `/home/jovyan/work/foo.ipynb` while `foo.ipynb` succeeds. The
   2026-11-23 turn echoed the absolute path that `create_notebook` returns in
   its success message, so every follow-up call used it.
2. **No error handling / no fallback (the amplifier).** `jupyter_ai_tools` 0.7.0
   does `payload["content"]` on the failed reply (`KeyError('content')`, no
   check, no path normalization for the frontend) and gives writes a fixed 10 s
   wait (`Command timed out after 10.0 seconds`). The same failures also occur
   with no browser at all, because in that configuration the tools depend
   entirely on a live frontend that has the notebook open.

Not the trigger: the chat tab's stuck notebook spinner seen during that turn.
It produces the same signature, but the absolute path alone reproduces every
observed failure on a healthy frontend, so the spinner is not needed to explain
them.

Fix shipped in the image (see `requirements.txt` + `requirements-overrides.txt`):

- `jupyter-ai[rtc]` → `jupyter-collaboration` (`jupyter_server_ydoc`) makes
  `rtc_available()` true. **This is what fixes the path-form trigger**: reads
  then go through `DiskAdapter` → `normalize_filepath()` (absolute and relative
  both work, nothing to match in the browser), and writes go to the live YDoc
  when a room exists, else straight to the file. The frontend is no longer in
  the read path at all.
- `jupyter-ai-tools==0.8.0` + `jupyterlab-commands-toolkit==0.3.1` (installed
  past jupyter-ai's `<0.8.0` / `<0.3.0` pins via `uv pip install --overrides`):
  this supplies the disk/YDoc fallback, real error messages instead of
  `KeyError('content')`, structured `error_code`s (`no_web_client` /
  `not_acknowledged` / `timeout`), and the `insert_index is None` fix in the
  RTC write path (0.7.0 crashed there with
  `'NoneType' object cannot be interpreted as an integer`).
- `run_all_cells` / `run_cell` still need a frontend kernel: without a web
  client they now return `{"error_code":"no_web_client", ...}` immediately
  instead of stalling 10 s.

Verify with the MCP server directly (no browser needed), inside a spawned
container — use **both** path forms, since the old bug was path-dependent:

```bash
docker exec -i jupyter-<user> python3 - <<'PY'
import asyncio
from fastmcp import Client
async def main():
    async with Client("http://localhost:3001/mcp") as c:
        for p in ("/home/jovyan/work/p.ipynb", "p.ipynb"):
            for n, a in [("create_notebook", {"file_path": p}),
                         ("insert_cell", {"file_path": p, "content": "print(1)"}),
                         ("read_notebook_cells", {"notebook_path": p}),
                         ("get_cell_id_from_index", {"file_path": p, "cell_index": 1})]:
                r = await c.call_tool(n, a)
                txt = r.content[0].text if r.content else "<empty result>"
                print(p, n, "->", txt[:120])
asyncio.run(main())
PY
```

Expected on this image: every call succeeds for both forms (creates the file
once; `create_notebook` on the second form reports "already exists"). When the
notebook is open in a Lab tab, `insert_cell` prints `<empty result>` — the
write still lands via the YDoc → autosave, so confirm on disk. Indexing
`r.content[0]` without that guard raises `IndexError` on this path.

`cell_index` is **1-based** (the number JupyterLab shows). Passing `0` raises
`ValueError: No cell_id found, use insert_cell based on cell index` even when
the cell `id` is present in the file — that is a probe bug, not a tool defect.

