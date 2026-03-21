# STT local (faster-whisper)

Servico local de transcricao para usar no app com `USE_REMOTE_STT=true`.

## 1) Subir API local com Docker

```bash
cd stt_server
cp .env.example .env
# Recomendado: -d (detached). Sem -d, Ctrl+C para o container — não é “erro” da API.
docker compose up -d --build stt
docker compose ps
docker compose logs -f --tail=50 stt
```

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

## 2) Expor com Cloudflare Tunnel (opcional)

Voce pode expor a API local para o celular fora da rede local sem abrir porta no roteador.

### Opcao A: Quick Tunnel (teste rapido)

```bash
docker run --rm --network host cloudflare/cloudflared:latest tunnel --url http://localhost:8000
```

Vai aparecer uma URL `https://...trycloudflare.com`. Use ela no app:

```env
USE_REMOTE_STT=true
REMOTE_STT_URL=https://SEU_SUBDOMINIO.trycloudflare.com/stt/transcribe
REMOTE_STT_TOKEN=troque-este-token
```

### Opcao B: Tunnel nomeado (producao)

1. No painel Cloudflare Zero Trust, crie um Tunnel e copie o token.
2. Coloque o token em `stt_server/.env`:

```env
CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoi...
```

3. Suba STT + tunnel:

```bash
docker compose --profile tunnel up -d --build
```

No Cloudflare, aponte o hostname para `http://stt:8000`.

### Erro no cloudflared: `context canceled` / `Incoming request ended abruptly`

Isso quase sempre significa que **alguém fechou a conexão HTTP antes do STT terminar** (não é “falha do túnel” sozinho).

1. **Timeout no app (Flutter)** — o cliente cancela após `REMOTE_STT_TIMEOUT_SECONDS`. Whisper em CPU na **primeira** requisição pode levar **vários minutos** (baixar/carregar modelo). Aumente no `.env` do app:
   ```env
   REMOTE_STT_TIMEOUT_SECONDS=300
   ```
   ou até `600` se precisar.
   Também vale ativar no servidor:
   ```env
   PRELOAD_MODEL=true
   ```
   (carrega o modelo no startup, evitando primeira requisição lenta).

2. **STT lento** — use `STT_QUALITY_PROFILE=fast` ou `MODEL_SIZE=base` temporariamente, ou **aqueça** o servidor com um `curl` de teste após subir o Docker (primeira transcrição carrega o modelo).

3. **Origin no painel do túnel** — `http://127.0.0.1:8000` só funciona se o **cloudflared** rodar na **mesma máquina** onde a porta `8000` está publicada. Se o STT estiver só dentro de uma rede Docker sem bind na host, use o IP da bridge ou `host.docker.internal` conforme o seu setup.

4. **Limites no edge Cloudflare** — requisições HTTP muito longas podem ser cortadas por políticas de timeout no proxy (varia por plano/config). Se mesmo com STT rápido ainda cancelar perto de ~100s, vale checar em **Zero Trust → o túnel → rota do hostname → configurações avançadas** (timeouts / origin) ou reduzir o tempo por requisição (`REMOTE_STT_CHUNK_SECONDS` menor no app = arquivos menores = resposta mais cedo).

Você também pode aquecer manualmente o servidor (carrega o modelo sem esperar um áudio real):

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
