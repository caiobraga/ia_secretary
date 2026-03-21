import json
import os
import tempfile
import time
from threading import Lock
from typing import Any, Dict, Optional

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from faster_whisper import WhisperModel

# Modelo: tiny < base < small < medium < large-v3 (maior = melhor PT-BR, mais RAM/tempo)
MODEL_SIZE = os.getenv("MODEL_SIZE", "small")
MODEL_DEVICE = os.getenv("MODEL_DEVICE", "cpu")
MODEL_COMPUTE_TYPE = os.getenv("MODEL_COMPUTE_TYPE", "int8")
API_TOKEN = os.getenv("API_TOKEN", "")
DEFAULT_LANGUAGE = os.getenv("DEFAULT_LANGUAGE", "pt")
DEFAULT_VAD_FILTER = os.getenv("DEFAULT_VAD_FILTER", "true").lower() != "false"

# Perfil: ajusta beam/best_of/patience/condição sem precisar tunar cada variável.
# fast = latência; balanced = padrão; accurate = máxima precisão (CPU mais lento).
_STT_PROFILES: Dict[str, Dict[str, Any]] = {
    "fast": {
        "beam": 1,
        "best_of": 1,
        "patience": 1.0,
        "condition_previous": False,
        "compression_ratio_threshold": 2.4,
        "log_prob_threshold": -1.0,
        "no_speech_threshold": 0.6,
    },
    "balanced": {
        "beam": 3,
        "best_of": 3,
        "patience": 1.0,
        "condition_previous": True,
        "compression_ratio_threshold": 2.3,
        "log_prob_threshold": -1.0,
        "no_speech_threshold": 0.5,
    },
    "accurate": {
        "beam": 5,
        "best_of": 5,
        "patience": 1.2,
        "condition_previous": True,
        "compression_ratio_threshold": 2.2,
        "log_prob_threshold": -1.0,
        "no_speech_threshold": 0.45,
    },
}

STT_QUALITY_PROFILE = os.getenv("STT_QUALITY_PROFILE", "fast").lower().strip()
if STT_QUALITY_PROFILE not in _STT_PROFILES:
    STT_QUALITY_PROFILE = "fast"
_profile = _STT_PROFILES[STT_QUALITY_PROFILE]


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or str(raw).strip() == "":
        return default
    return int(raw)


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None or str(raw).strip() == "":
        return default
    return float(raw)


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.lower() not in ("false", "0", "no", "")


BEAM_SIZE = _env_int("BEAM_SIZE", _profile["beam"])
BEST_OF = _env_int("BEST_OF", _profile["best_of"])
PATIENCE = _env_float("PATIENCE", _profile["patience"])
CONDITION_ON_PREVIOUS = _env_bool(
    "CONDITION_ON_PREVIOUS_TEXT",
    bool(_profile["condition_previous"]),
)
COMPRESSION_RATIO_THRESHOLD = _env_float(
    "COMPRESSION_RATIO_THRESHOLD",
    float(_profile["compression_ratio_threshold"]),
)
LOG_PROB_THRESHOLD = _env_float(
    "LOG_PROB_THRESHOLD",
    float(_profile["log_prob_threshold"]),
)
NO_SPEECH_THRESHOLD = _env_float(
    "NO_SPEECH_THRESHOLD",
    float(_profile["no_speech_threshold"]),
)

# Opcional: JSON para VadOptions (ex.: {"min_silence_duration_ms": 400, "threshold": 0.5})
VAD_PARAMETERS: Optional[Dict[str, Any]] = None
_raw_vad = os.getenv("VAD_PARAMETERS_JSON", "").strip()
if _raw_vad:
    try:
        VAD_PARAMETERS = json.loads(_raw_vad)
        if not isinstance(VAD_PARAMETERS, dict):
            VAD_PARAMETERS = None
    except json.JSONDecodeError:
        VAD_PARAMETERS = None

# Palavras/nomes que o modelo deve favorecer (separadas por vírgula), ex.: "Acme, sprint, backlog"
STT_HOTWORDS = os.getenv("STT_HOTWORDS", "").strip() or None
PRELOAD_MODEL = _env_bool("PRELOAD_MODEL", False)

app = FastAPI(title="IA Secretary Local STT")
model = None
_model_lock = Lock()


def _get_model() -> WhisperModel:
    global model
    if model is not None:
        return model
    with _model_lock:
        if model is None:
            model = WhisperModel(
                MODEL_SIZE,
                device=MODEL_DEVICE,
                compute_type=MODEL_COMPUTE_TYPE,
            )
    return model


def _check_auth(authorization: Optional[str]) -> None:
    if not API_TOKEN:
        return
    if authorization != f"Bearer {API_TOKEN}":
        raise HTTPException(status_code=401, detail="unauthorized")


@app.on_event("startup")
def startup_event() -> None:
    # Opcional: pré-carrega o modelo para evitar timeout/cancel no primeiro request via tunnel.
    if PRELOAD_MODEL:
        _get_model()


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "model": MODEL_SIZE,
        "device": MODEL_DEVICE,
        "compute_type": MODEL_COMPUTE_TYPE,
        "quality_profile": STT_QUALITY_PROFILE,
        "beam_size": BEAM_SIZE,
        "best_of": BEST_OF,
        "model_loaded": model is not None,
        "preload_model": PRELOAD_MODEL,
    }


@app.post("/warmup")
def warmup(authorization: Optional[str] = Header(default=None)) -> dict:
    _check_auth(authorization)
    started = time.time()
    _get_model()
    return {"ok": True, "duration_ms": int((time.time() - started) * 1000)}


@app.post("/stt/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: str = Form(DEFAULT_LANGUAGE),
    vad_filter: bool = Form(DEFAULT_VAD_FILTER),
    prompt: Optional[str] = Form(None),
    authorization: Optional[str] = Header(default=None),
) -> dict:
    _check_auth(authorization)

    started = time.time()
    suffix = ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        m = _get_model()
        lang = (language or DEFAULT_LANGUAGE or "pt").strip()
        transcribe_kw: Dict[str, Any] = {
            "language": lang if lang else None,
            "task": "transcribe",
            "vad_filter": vad_filter,
            "initial_prompt": prompt,
            "beam_size": BEAM_SIZE,
            "best_of": max(BEST_OF, BEAM_SIZE),
            "patience": PATIENCE,
            "condition_on_previous_text": CONDITION_ON_PREVIOUS,
            "compression_ratio_threshold": COMPRESSION_RATIO_THRESHOLD,
            "log_prob_threshold": LOG_PROB_THRESHOLD,
            "no_speech_threshold": NO_SPEECH_THRESHOLD,
        }
        # Não fixar temperature=0: o padrão do faster-whisper tenta fallbacks com temperaturas
        # maiores quando o áudio é difícil (melhor recall em PT ruidoso).
        if VAD_PARAMETERS is not None:
            transcribe_kw["vad_parameters"] = VAD_PARAMETERS
        if STT_HOTWORDS:
            transcribe_kw["hotwords"] = STT_HOTWORDS

        segments, info = m.transcribe(tmp_path, **transcribe_kw)
        text = " ".join(segment.text.strip() for segment in segments).strip()
        return {
            "text": text,
            "language": getattr(info, "language", language),
            "duration_ms": int((time.time() - started) * 1000),
        }
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
