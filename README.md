# IA Secretary

Always-on AI secretary for **Android** and **iOS**: no normal UI, continuous listening, and transcripts saved to **Supabase** (calendars, events, reminders schema ready).

## Behavior

- **No normal interface** – The app shows a transparent screen. It runs like a headless assistant.
- **Android** – Starts on **boot** or when you **tap the app icon**. Foreground service keeps it listening when you leave the app.
- **iOS** – Starts when you **tap the app icon**. Listens while the app is in the foreground.
- **Backend** – Voice is transcribed and each phrase is inserted into Supabase table `voice_transcripts`. You can later use Edge Functions or triggers to create events, reminders, or meeting notes from this table.

## Sign-in (email, no verification)

On first launch the app shows a minimal sign-in screen:

- **Email + password** – Sign up (create account) or sign in. No email verification: turn **off** “Confirm email” in Supabase so users are signed in immediately after sign-up.
- In Supabase Dashboard: **Authentication** → **Providers** → **Email** → disable **Confirm email**.

After sign-in you see the transparent “listening” screen and the app starts sending transcripts. **Session is persisted by Supabase** (secure storage), so the next launch goes straight to listening. The last email is saved locally to pre-fill the login form if you ever need to sign in again.

## Supabase setup

1. **Create tables**  
   In Supabase SQL Editor, run `supabase/voice_transcripts.sql` (voice data and RLS).

2. **Email auth without verification**  
   In Supabase Dashboard: **Authentication** → **Providers** → **Email** → disable **Confirm email** so sign-up signs the user in immediately.

3. **Use your project keys**  
   In `lib/src/config.dart` the defaults are set to your project.  
   If you prefer the standard **anon** key (JWT starting with `eyJ...`), get it from **Settings** → **API** → **Project API keys** → **anon public**, and set it in config or build with:

   ```bash
   flutter run --dart-define=SUPABASE_URL=https://ehteyunafhexqjwyjkpi.supabase.co --dart-define=SUPABASE_ANON_KEY=your_anon_jwt_here
   ```

## Config

- **`lib/src/config.dart`** – `supabaseUrl` and `supabaseAnonKey`. Your URL and the key you shared are already set as defaults. If Supabase rejects requests, switch to the **anon** JWT from the dashboard.
- **`.env`** – Variáveis de ambiente (na raiz do projeto). Ex.: `GOOGLE_CLOUD_SPEECH_API_KEY` para usar a API em nuvem e evitar o beep. Use `.env.example` como modelo.
- **STT remoto local (recomendado para melhor qualidade)** – veja `stt_server/README.md` e configure `USE_REMOTE_STT=true` + `REMOTE_STT_URL`.

## Permissions

On first run the app requests:

- **Microphone** – required for listening  
- **Notifications** (Android) – for the foreground service

## Android: notificação silenciosa e bateria

O app usa um **Foreground Service** para ouvir em segundo plano; o Android exige uma notificação. O canal já está configurado como **silencioso** (sem som nem vibração). Para garantir que não apite e que o sistema não feche o app:

1. **Notificação sem barulho**  
   Configurações → Apps → **IA Secretary** → Notificações → toque na categoria do serviço (ex.: "IA Secretary") → escolha **Silencioso** e desative **Exibir como banner** se quiser. O ícone continua na barra (obrigatório), mas sem som nem vibração.

2. **Bateria (importante)**  
   Para o Android não encerrar o app após alguns minutos: Configurações → Apps → **IA Secretary** → Bateria → marque como **Não otimizado** (ou "Sem restrições"). Caso contrário, o sistema pode matar o processo para economizar energia.

3. **Ponto verde (Android 12+)**  
   O indicador de câmera/microfone ativo é do sistema e não pode ser desativado por software; aparece como confirmação de que o serviço está ativo.

4. **Beep ao iniciar/parar a escuta**  
   No **Android**, o app tenta primeiro o **Vosk** (reconhecimento local, **sem beep**). Na primeira execução o modelo em português (~32 MB) é baixado; depois tudo roda no aparelho e **não há beep**. Se o Vosk falhar (ex.: sem internet na primeira vez), o app usa o reconhecimento do sistema (speech_to_text), que emite beep a cada início de escuta.

### Vosk (Android – local, sem beep)

- **Reconhecimento 100% no aparelho**, sem nuvem e **sem beep** (não muta o sistema).
- Na primeira vez que a escuta inicia, o app baixa o modelo pequeno em PT (`vosk-model-small-pt-0.3`, ~32 MB). É preciso internet nessa hora; depois o modelo fica em cache.
- Se o download ou a inicialização do Vosk falhar, o app volta para o reconhecimento do sistema (speech_to_text), que tem beep.

### Google Cloud Speech-to-Text (opcional, desativado por padrão)

O plugin usa **gRPC em streaming**, que exige **OAuth 2 access token**, não a “chave de API” da tela de Credenciais. O app obtém o token nesta ordem: (1) JSON da conta de serviço no projeto (Opção 3); (2) `GOOGLE_CLOUD_SPEECH_API_KEY` no `.env` (Opção 2). Se usar só a API Key do Console, aparecerá erro `UNAUTHENTICATED`.

**Opção 1 – Usar o reconhecimento do sistema (recomendado)**  
Deixe no **`.env`** a linha vazia ou apagada:
```env
GOOGLE_CLOUD_SPEECH_API_KEY=
```
O app usará o reconhecimento do Android (com beep, mas sem configurar nada no Google Cloud).

**Onde pegar o valor:** não use Chave de API (dá erro). Não crie "Cliente Android". Use a Opção 2 (token no PC) ou deixe vazio (Opção 1).

**Opção 2 – Token para teste (~1 h) – no seu PC**  
1. Instale o [Google Cloud SDK (gcloud)](https://cloud.google.com/sdk/docs/install).
2. Ative a API no Console: **APIs e serviços** → **Biblioteca** → **Speech-to-Text API** → Ativar.
3. No terminal **no seu PC**, use o **projeto certo** (o mesmo onde você ativou a API) e depois pegue o token:
   ```bash
   # Listar seus projetos (anote o PROJECT_ID que tem Speech-to-Text ativa)
   gcloud projects list

   # Usar o projeto correto (substitua SEU_PROJECT_ID pelo id do projeto)
   gcloud config set project SEU_PROJECT_ID

   # Login (abre o navegador uma vez)
   gcloud auth application-default login

   # Definir o projeto de cota (obrigatório para Speech-to-Text com token de usuário)
   gcloud auth application-default set-quota-project SEU_PROJECT_ID

   # Imprimir o access token — esse é o valor que vai no .env
   gcloud auth application-default print-access-token
   ```
   O último comando imprime **só** o token: uma única linha, começa com `ya29.` (é um OAuth 2 access token). Copie **toda** essa linha, sem espaços no início/fim.
4. No projeto do app, abra o arquivo **`.env`** e cole o token:
   ```env
   GOOGLE_CLOUD_SPEECH_API_KEY=COLE_O_TOKEN_AQUI
   ```
   O token expira em cerca de 1 hora; depois é preciso gerar outro. Serve para testar “sem beep”.

**Opção 3 – Conta de serviço (recomendado; sem renovar token à mão)**  
Coloque o JSON da conta de serviço na **raiz do projeto** com o nome **`ia-rag-473917-94c6821ccc2d.json`** (o arquivo está no `.gitignore`). O app carrega o JSON e gera o access token na inicialização. Se o JSON estiver presente, o app usa esse token e ignora `GOOGLE_CLOUD_SPEECH_API_KEY`. O token expira em ~1 h; ao reabrir o app um novo é obtido automaticamente. Se não for usar conta de serviço, remova a linha `- ia-rag-473917-94c6821ccc2d.json` da seção `assets` do `pubspec.yaml` para o build não falhar sem o arquivo.

## Run

- **Android:** `flutter run` or install the APK. After boot or opening the app, it listens and shows “IA Secretary – Listening…” in the notification shade.
- **iOS:** `flutter run`. Open the app from the home screen to start listening.

## Data flow

- App listens (speech in **Portuguese**, locale `pt_BR`) → speech_to_text → **insert into `public.voice_transcripts`** (`user_id`, `text`, `is_final`, `created_at`).
- Your existing tables (`calendars`, `events`, `reminders`, `meeting_notes`, `action_items`) are unchanged. You can add an Edge Function or `pg_net`/cron that reads from `voice_transcripts` and creates events/reminders/notes when the text matches certain patterns or after AI processing.

## Project structure

- `lib/main.dart` – Supabase init, auth screen vs transparent home, foreground task (Android), voice service.
- `lib/src/secretary_service.dart` – Voice listening (pt_BR) and Supabase insert into `voice_transcripts`.
- `lib/src/auth_service.dart` – Sign-in: email + password (sign up / sign in, no verification).
- `lib/src/auth_screen.dart` – Minimal UI: email, password, Sign up / Sign in; remembers last email.
- `lib/src/stored_credentials.dart` – Saves last email locally (no password).
- `lib/src/config.dart` – Supabase URL and anon key.
- `supabase/voice_transcripts.sql` – Table + RLS for voice data.
- `android/.../BootReceiver.kt` – Starts the app on boot (Android only).
