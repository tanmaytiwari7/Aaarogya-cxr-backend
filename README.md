# Arogya Chest X-ray Inference Service

**Verified working end-to-end:** this exact code was installed, run, and
hit over real HTTP with a real chest X-ray image during development —
real `densenet121-res224-all` weights were downloaded from
TorchXRayVision's GitHub releases, loaded, and produced real (non-canned)
pathology probabilities. `requirements.txt` is pinned to the exact package
versions that were confirmed to install and run cleanly together.

A standalone Python (FastAPI) microservice that runs **real, pretrained**
chest X-ray classifiers from
[TorchXRayVision](https://github.com/mlmed/torchxrayvision) — not a mock.

This is separate from the Android app's Gradle build. Deploy it as its own
service (Docker, a VM, Render, Railway, Fly.io, Hugging Face Spaces, etc.)
and point the app at it. It plugs into the Android app's existing "AI
backend" pattern the same way the Groq/OpenAI-compatible chat endpoint
does for Patient AI and Report Analyser.

## Why the app shows "demo mode" right now

The app ships with `CXR_BACKEND_URL` blank, so it falls back to canned
example output rather than crashing with no server to call. **The model
and code are real** (see above) — what's missing is a running,
internet-reachable copy of this service. Deploy it once (a few minutes,
free tier is enough), put its URL in `gradle.properties`, and the "demo
mode" toast disappears — every result after that comes from a real model
run on the image you uploaded.

## Fastest path to a real, public URL: Hugging Face Spaces (free)

This is the quickest way to get `CXR_BACKEND_URL` pointing at something
real, with zero server management:

1. Create a free account at huggingface.co, then **New Space** → SDK:
   **Docker** → visibility: your choice (Private recommended, since this
   handles health-related images).
2. Push this `cxr-backend/` folder's contents to the Space's git repo (the
   `Dockerfile` here works as-is; Spaces builds and runs it automatically).
3. In the Space's **Settings → Repository secrets**, add `CXR_API_KEY`
   with a value you choose.
4. Once it finishes building, your Space gives you a public HTTPS URL
   like `https://your-username-arogya-cxr.hf.space`.
5. In the Android project's `gradle.properties`:
   ```properties
   CXR_BACKEND_URL=https://your-username-arogya-cxr.hf.space
   CXR_BACKEND_API_KEY=<the same value you set as the secret>
   ```
6. Rebuild the app. The Chest X-ray screen now calls your real, live model.

Render, Railway, and Fly.io all work the same way (push this folder,
they build the Dockerfile, you get a public URL) if you'd rather not use
Hugging Face.


## What model is this, really?

- **Architecture:** DenseNet-121
- **Library:** [torchxrayvision](https://github.com/mlmed/torchxrayvision) (PyTorch, MIT/Apache-licensed, maintained by Cohen et al.)
- **Weights used by default (`all`):** `densenet121-res224-all` — a single
  checkpoint trained on a **merge of NIH ChestX-ray14, CheXpert (Stanford),
  MIMIC-CXR, PadChest, the RSNA Pneumonia Challenge set, SIIM-ACR
  Pneumothorax, and the NLM Montgomery/Shenzhen TB sets.**
- **Optional ensemble mode** (`?ensemble=true`): runs three *separately
  trained* models — one on NIH ChestX-ray14 only, one on CheXpert only, one
  on MIMIC-CXR only — and averages their outputs. Use this if you
  specifically want predictions attributable to each named dataset rather
  than the pre-merged checkpoint.
- Weights auto-download (~30 MB each) from TorchXRayVision's release
  assets on first use and are cached on disk. Nothing is bundled in this
  repo.

**What this is not:** the original Stanford "CheXNet" checkpoint (its
weights were never officially released, only reproductions exist), and it
is not a cleared or certified diagnostic device. Treat every response as a
research-model output, same as the API responses make explicit.

## Run it locally

```bash
cd cxr-backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

First request will download model weights, so it may take a minute the
first time. Check it's alive:

```bash
curl http://localhost:8000/v1/health
```

## Run it with Docker

```bash
cd cxr-backend
docker build -t arogya-cxr-backend .
docker run -p 8000:8000 -e CXR_API_KEY=changeme arogya-cxr-backend
```

## Deploying

Any host that can run a Docker container works: Render, Railway, Fly.io, an
EC2/GCE VM, etc. Notes:

- **CPU is enough** for one-off requests (a few seconds per image) but
  expect higher latency under concurrent load; add a GPU instance if you
  need throughput.
- **Always set `CXR_API_KEY`** in production — without it the endpoint is
  open to anyone who finds the URL, which matters since these are
  health-related uploads. The Android app sends it back as `X-API-Key`.
- **Put it behind HTTPS.** Most platforms (Render, Railway, Fly) do this
  for you automatically.
- Tighten the CORS `allow_origins` in `app/main.py` once you're not testing
  locally.

## Environment variables

| Variable            | Default | Purpose                                              |
|----------------------|---------|-------------------------------------------------------|
| `CXR_API_KEY`        | *(blank = auth disabled)* | Required header value (`X-API-Key`) for `/v1/analyze-cxr`. Always set this in production. |
| `CXR_DEFAULT_MODEL`  | `all`   | Which single-model weights to use when `ensemble=false`. One of `all`, `nih`, `chexpert`, `mimic`. |

## API contract

### `GET /v1/health`
Returns `{"status": "ok"}`.

### `POST /v1/analyze-cxr`
- **Body:** `multipart/form-data` with a `file` field (JPEG/PNG, max 15 MB).
- **Query params:**
  - `ensemble` (bool, default `false`) — average NIH + CheXpert + MIMIC-CXR models instead of the combined `all` model.
  - `top_k` (int, default `8`, 1–20) — how many top findings to return.
- **Header:** `X-API-Key: <CXR_API_KEY>` (required if the server has one set).

Example:

```bash
curl -X POST "http://localhost:8000/v1/analyze-cxr?top_k=6" \
  -H "X-API-Key: changeme" \
  -F "file=@chest_xray.jpg"
```

Response:

```json
{
  "findings": [
    {"label": "No Finding", "probability": 0.72},
    {"label": "Cardiomegaly", "probability": 0.18},
    "... one entry per pathology the model outputs ..."
  ],
  "top_findings": [
    {"label": "No Finding", "probability": 0.72},
    {"label": "Cardiomegaly", "probability": 0.18},
    "... top_k entries, sorted descending ..."
  ],
  "models_used": [
    {
      "key": "all",
      "architecture": "DenseNet-121",
      "framework": "TorchXRayVision (PyTorch)",
      "trained_on": ["NIH ChestX-ray14", "CheXpert (Stanford)", "MIMIC-CXR", "..."],
      "description": "Combined multi-dataset DenseNet-121 (recommended default)."
    }
  ],
  "disclaimer": "This output is generated by an open-source research model ..."
}
```

Pathology labels follow TorchXRayVision's label set, e.g.: `Atelectasis`,
`Cardiomegaly`, `Consolidation`, `Edema`, `Effusion`, `Emphysema`,
`Fibrosis`, `Hernia`, `Infiltration`, `Mass`, `Nodule`, `Pleural_Thickening`,
`Pneumonia`, `Pneumothorax`, `Enlarged Cardiomediastinum`, `Lung Lesion`,
`Lung Opacity`, `No Finding` (exact set depends on which model/weights are used).

## Wiring this into the Android app

In the app's `gradle.properties` (already has an equivalent block for the
chat backend):

```properties
CXR_BACKEND_URL=https://your-deployed-service.example.com
CXR_BACKEND_API_KEY=changeme
```

Leave both blank to keep the app in offline demo mode for the Chest X-ray
feature (same fallback pattern as Patient AI / Report Analyser).

## Extending

- **MONAI:** the [MONAI Model Zoo](https://monai.io/model-zoo.html) is
  primarily geared toward segmentation/other imaging tasks rather than a
  drop-in chest X-ray pathology classifier as strong as TorchXRayVision's,
  so it isn't wired in by default here. If you have a specific MONAI
  bundle you want served, add a loader in `app/model.py` alongside
  `MODEL_REGISTRY` and a new `model_key`.
- **More datasets:** TorchXRayVision also ships PadChest-only and
  RSNA/SIIM-specific weights if you want additional entries in
  `MODEL_REGISTRY`.
