# STT local (faster-whisper)

Servico local de transcricao para usar no app com `USE_REMOTE_STT=true`. O modelo é **Whisper** (via Hugging Face / faster-whisper), não Ollama.

## 1) Subir API local com Docker

```bash
cd stt_server
cp .env.example .env
# Edite .env: API_TOKEN (nunca commite).
# Recomendado: -d (detached). Sem -d, Ctrl+C para o container — não é “erro” da API.
docker compose up -d --build stt
docker compose ps
docker compose logs -f --tail=50 stt
```

Na **raiz** do repositório `ia_secretary` (outra máquina: clone do repo e mesmo `.env` em `stt_server/.env`):

```bash
docker compose --env-file stt_server/.env up -d --build stt
```

O `--env-file` garante que `API_TOKEN` (e outras variáveis) do `stt_server/.env` entram na interpolação do Compose quando o comando não é executado dentro de `stt_server/`.

Teste:

```bash
# Em algumas maquinas Linux, "localhost" tenta IPv6 (::1) e pode fechar conexao.
curl http://127.0.0.1:8000/health
```

### Docker: mensagens duplicadas no terminal

Se cada linha do Uvicorn aparecer **duas vezes**, em geral é efeito de **attach** / terminal / versão do Docker Compose — o processo continua **um só** (`--workers 1`). Confirme com:

```bash
docker compose top stt
```

Deve aparecer **um** processo principal `uvicorn` (além de threads internas).

### Docker: `Waiting for connections to close` ao parar

Significa que ainda havia **requisição HTTP aberta** (ex. transcrição longa). Opções: esperar terminar, `Ctrl+C` de novo, ou `docker compose stop -t 0 stt` para forçar (pode cortar a transcrição). O `stop_grace_period: 120s` no `docker-compose.yml` dá mais tempo antes do kill.

### Aviso `HF_TOKEN` / Hugging Face Hub (**opcional**)

**Não é obrigatório.** O modelo instala e o servidor funciona **sem** `HF_TOKEN` — downloads anónimos são suportados.

Sem token o Hub só mostra o aviso *"unauthenticated requests"* e pode aplicar **rate limit** mais apertado (primeiro download ou muitos pedidos podem ser mais lentos). Com token isso melhora e o aviso some.

Se quiser, crie um token em [Hugging Face → Settings → Access Tokens](https://huggingface.co/settings/tokens) e no `stt_server/.env`:

```env
HF_TOKEN=hf_...
```

## 2) DNS na Cloudflare apontando para a EC2 (sem Tunnel)

Não há comando `git`/CLI obrigatório na Cloudflare depois do commit: o código só muda na VM (`git pull` + `docker compose up -d --build` no servidor).

No **painel Cloudflare** (zona do domínio, ex. `anaaisecretary.com`):

1. **DNS → Records**
   - Para o hostname do STT (ex. `audio`), crie ou edite um registo **A** com **IPv4 address** = **IP público** da EC2 (idealmente **Elastic IP** fixo).
   - **Proxy status**: **DNS only** (nuvem cinzenta) se quiseres HTTPS direto na EC2 com Let’s Encrypt; **Proxied** (laranja) só se souberes configurar a origem (porta 443, certificado ou modo SSL compatível).

2. **Se antes usavas Cloudflare Tunnel** para esse hostname:
   - **Zero Trust → Networks → Tunnels** → abre o túnel → **Public Hostname** que apontava para `audio...` → **Remove** essa rota (ou apaga o túnel). Enquanto o hostname continuar ligado ao Tunnel, o registo **A** na zona pode ser ignorado ou conflitar com o comportamento esperado.

3. **AWS Security Group**: abre **443** (e **80** se usar redirect HTTP→HTTPS) para `0.0.0.0/0`; o STT em Docker escuta em **8000** só em localhost se colocares **Nginx/Caddy** à frente com reverse proxy para `127.0.0.1:8000`.

4. No app, `REMOTE_STT_URL=https://audio.SEU_DOMINIO/stt/transcribe` (HTTPS na borda ou na VM).

**Primeira requisição lenta / timeouts no app:** no `.env` do app Flutter, `REMOTE_STT_TIMEOUT_SECONDS=300` (ou mais); no servidor, `PRELOAD_MODEL=true`. Aquecimento opcional:

```bash
curl -X POST -H "Authorization: Bearer SEU_TOKEN" http://127.0.0.1:8000/warmup
```

## Endpoint

`POST /stt/transcribe` (multipart/form-data)

- `file`: audio (`wav` 16k mono recomendado)
- `language`: `pt` (default)
- `vad_filter`: `true` (default)
- `prompt`: opcional — **use só frases muito curtas** (lista de termos). Prompt longo + áudio em chunks faz o modelo **repetir o prompt** na transcrição.
- Header opcional: `Authorization: Bearer <API_TOKEN>`

Resposta:

```json
{
  "text": "texto transcrito",
  "language": "pt",
  "duration_ms": 1200
}
```

## Config do app (.env)

```env
USE_REMOTE_STT=true
REMOTE_STT_URL=https://SEU_DOMINIO/stt/transcribe
REMOTE_STT_TOKEN=troque-este-token
REMOTE_STT_LANGUAGE=pt
REMOTE_STT_VAD_FILTER=true
REMOTE_STT_CHUNK_SECONDS=2
# Opcional: até ~96 caracteres no app; evite parágrafos longos.
REMOTE_STT_PROMPT=secretaria, reuniao, agenda
```

## Qualidade da transcricao (o que mudou)

Antes o padrao era agressivo em **velocidade** (`base` + `beam_size=1` + `temperature=0` implícito), o que **prejudica** português coloquial e áudio ruídoso.

Agora:

- **`MODEL_SIZE` padrão no compose:** `small` (melhor PT-BR que `base` em troca de RAM/tempo).
- **`STT_QUALITY_PROFILE`:** `fast` | `balanced` | `accurate` — ajusta `beam_size`, `best_of`, `patience`, `condition_on_previous_text` e limiares anti-alucinação.
- **Sem `temperature=0` fixo:** o faster-whisper usa a sequência padrão de temperaturas quando a frase é difícil (melhor recall).
- **`STT_HOTWORDS`:** termos separados por vírgula (nomes, produtos, jargão).
- **`VAD_PARAMETERS_JSON`:** ajuste fino do VAD se cortar demais a fala.

Exemplo `.env` no servidor para **máxima precisão** (CPU lento):

```env
MODEL_SIZE=small
STT_QUALITY_PROFILE=accurate
STT_HOTWORDS=sua empresa, sprint, backlog, reuniao
```

Ou com **GPU**:

```env
MODEL_DEVICE=cuda
MODEL_COMPUTE_TYPE=float16
MODEL_SIZE=medium
STT_QUALITY_PROFILE=balanced
```

`GET /health` retorna `quality_profile`, `beam_size`, `best_of` para conferir o que está ativo.

## Latência vs qualidade

- **App em chunks** (STT remoto): o padrão do compose é `STT_QUALITY_PROFILE=fast` para a inferência não ficar atrás de cada janela de áudio. No app, `REMOTE_STT_CHUNK_SECONDS` menor (ex. `1.2`–`1.5`) faz o texto aparecer mais cedo (mais requisições).
- `STT_QUALITY_PROFILE=fast` + `MODEL_SIZE=small` → bom equilíbrio latência/PT-BR na maioria dos casos.
- `balanced` + `small` → mais lento (~várias vezes o decode), use se priorizar precisão e o servidor aguentar.
- `accurate` + `small`/`medium` → máxima precisão; latência alta.
