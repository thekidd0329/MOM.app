from __future__ import annotations

import os
import subprocess
from pathlib import Path

import modal

APP_NAME = "mom-smaug"
PORT = 8000
MODEL_REPO = os.environ.get(
    "MOM_MODEL_REPO",
    "tensorblock/Smaug-Llama-3-70B-Instruct-abliterated-v3-GGUF",
)
MODEL_FILE = os.environ.get(
    "MOM_MODEL_FILE",
    "Smaug-Llama-3-70B-Instruct-abliterated-v3-Q4_K_M.gguf",
)
MODEL_ALIAS = os.environ.get(
    "MOM_MODEL_ALIAS",
    "failspy/Smaug-Llama-3-70B-Instruct-abliterated-v3",
)
MODEL_DIR = Path("/models/smaug")
MODEL_PATH = MODEL_DIR / MODEL_FILE

# Pin the llama.cpp CUDA image so a moving upstream tag cannot silently change
# MOM's production inference runtime.
LLAMA_IMAGE = (
    modal.Image.from_registry(
        "ghcr.io/ggml-org/llama.cpp:server-cuda13-b9445@sha256:f92150249e1913ef96e744b5d78f6291f0e4399a7925ffc7b1d0680d82506551",
        add_python="3.12",
    )
    .entrypoint([])
    .pip_install("huggingface_hub==0.34.4")
)

MODEL_VOLUME = modal.Volume.from_name("mom-smaug-models", create_if_missing=True)
app = modal.App(APP_NAME)


@app.function(
    image=LLAMA_IMAGE,
    volumes={"/models": MODEL_VOLUME},
    timeout=60 * 60,
    cpu=2,
    memory=4096,
)
def seed_model() -> dict[str, str]:
    """Download the selected public GGUF once into persistent Modal storage."""
    from huggingface_hub import hf_hub_download

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    path = hf_hub_download(
        repo_id=MODEL_REPO,
        filename=MODEL_FILE,
        local_dir=str(MODEL_DIR),
    )
    MODEL_VOLUME.commit()
    return {"repo": MODEL_REPO, "file": MODEL_FILE, "path": path}


@app.server(
    image=LLAMA_IMAGE,
    gpu="H100",
    volumes={"/models": MODEL_VOLUME},
    port=PORT,
    routing_region="us-west",
    startup_timeout=10 * 60,
    scaledown_window=5 * 60,
    target_concurrency=2,
    max_containers=1,
    # Modal Servers require proxy authentication by default. Keep it that way:
    # only Supabase should be able to spend GPU compute.
    unauthenticated=False,
)
class SmaugServer:
    @modal.enter()
    def start(self) -> None:
        if not MODEL_PATH.exists():
            raise RuntimeError(
                "Smaug weights are not seeded. Run: "
                "modal run infra/modal/mom_smaug.py::seed_model"
            )

        self.proc = subprocess.Popen(
            [
                "/app/llama-server",
                "--model",
                str(MODEL_PATH),
                "--alias",
                MODEL_ALIAS,
                "--host",
                "0.0.0.0",
                "--port",
                str(PORT),
                "--ctx-size",
                "8192",
                "--n-gpu-layers",
                "999",
                "--parallel",
                "2",
            ]
        )

    @modal.exit()
    def stop(self) -> None:
        if getattr(self, "proc", None) is not None:
            self.proc.terminate()
