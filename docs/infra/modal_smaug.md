# MOM Smaug on Modal

This deployment keeps the Android app talking only to Supabase. Modal is private GPU compute behind the server boundary.

## Runtime shape

`MOM app -> Supabase mom-brain -> authenticated Modal Server -> llama.cpp -> Smaug`

The default model is the Q4_K_M GGUF quantization of `failspy/Smaug-Llama-3-70B-Instruct-abliterated-v3`, served from a persistent Modal Volume on one H100. The selected quant is about 42.5 GB and is the balanced-quality GGUF published for this model.

The Modal Server is proxy-authenticated by default. Do not set `unauthenticated=True` in production.

## 1. Authenticate Modal locally

```bash
python -m pip install -U modal
modal setup
```

## 2. Seed the model once

```bash
modal run infra/modal/mom_smaug.py::seed_model
```

This downloads the GGUF to the persistent `mom-smaug-models` Volume. Subsequent GPU containers reuse it instead of downloading the model on every cold start.

## 3. Deploy the GPU server

```bash
modal deploy infra/modal/mom_smaug.py
```

Record the authenticated server URL printed by Modal. The llama.cpp API is OpenAI-compatible and exposes chat completions at:

```text
<modal-server-url>/v1/chat/completions
```

## 4. Create a proxy token for Supabase

```bash
modal workspace proxy-tokens create
```

Store the returned `wk-...` token ID and `ws-...` token secret securely. The secret is only displayed once.

Supabase should send them to Modal as:

```text
Modal-Key: wk-...
Modal-Secret: ws-...
```

Never ship either value in the Flutter application or repository.

## 5. Supabase cutover contract

`mom-brain` remains the only public brain endpoint used by the app. Its provider layer should be configured with these server-side values:

```text
MOM_BRAIN_PROVIDER=modal
MODAL_API_BASE=<modal-server-url>/v1
MODAL_PROXY_TOKEN_ID=wk-...
MODAL_PROXY_TOKEN_SECRET=ws-...
MOM_MODEL=failspy/Smaug-Llama-3-70B-Instruct-abliterated-v3
```

Do not switch `MOM_BRAIN_PROVIDER` until the Modal health/chat smoke test succeeds. The existing provider should remain available during rollout so the app is never deliberately left without a brain endpoint.

## 6. Smoke test before cutover

Test Modal directly with the proxy token, then test through `mom-brain`. Minimum proof:

1. Modal returns a non-empty OpenAI-compatible chat completion.
2. `mom-brain` preserves the server-authoritative MOM prompt and ignores client `system_prompt`.
3. A real app request returns a completion.
4. Only after those pass should Modal become the active provider.

## Cost behavior

The server uses one H100, keeps at most one container active, and scales down after five idle minutes. Model weights stay on the Modal Volume while GPU compute scales to zero.
