# `speech_to_text` / `USE_SYSTEM_SPEECH_TO_TEXT` e o beep no Android

O projeto usa o pacote **[speech_to_text](https://github.com/csdcorp/speech_to_text)** ([pub.dev](https://pub.dev/packages/speech_to_text)), que no Android delega para o **`SpeechRecognizer`** / serviço de reconhecimento do sistema.

## Dá para usar só o sistema **sem** beep?

**Não de forma suportada.** O autor do plugin respondeu explicitamente:

> *"For Android it is built into the OS level speech recognition system and **there is no API to disable it**."*  
> — [sowens-csd em #278](https://github.com/csdcorp/speech_to_text/issues/278)

Ou seja: o som não é gerado pelo Dart do plugin; vem da stack do Android/Google para esse fluxo de reconhecimento. O `SpeechListenOptions` (ex. `onDevice`, `listenMode`) **não** expõe flag para silenciar esse beep.

Discussões relacionadas:

- [How to mute the beep sound for SpeechRecognizer? #278](https://github.com/csdcorp/speech_to_text/issues/278)  
- [Request to Add Option to Disable Notification Sound on Android #512](https://github.com/csdcorp/speech_to_text/issues/512)  

Workarounds **não oficiais** (modo Não perturbar, hacks de volume, OEM) são frágeis e não são integrados neste app.

## Alternativas neste projeto (sem beep típico do SpeechRecognizer)

| Modo | Notas |
|------|--------|
| **Vosk** (padrão Android sem `USE_SYSTEM_SPEECH_TO_TEXT`) | Offline, sem esse beep. |
| **`USE_GOOGLE_CLOUD_STT` + token** | Áudio via `AudioRecord` + API Google (pacote `flutter_google_stt`), não usa o `SpeechRecognizer` do beep. |
| **STT remoto** (`record` + HTTP) | Gravação em chunks + Whisper no servidor (`REMOTE_STT_URL`). |

Conclusão: **`USE_SYSTEM_SPEECH_TO_TEXT=true` implica `speech_to_text` no caminho atual; no Android o beep é limitação da plataforma, não algo que o repositório csdcorp possa corrigir só em Dart.**

---

## Tutoriais “Speech to text **sem o pop-up**” (ex. [Imobilis / DECOM UFOP](https://www2.decom.ufop.br/imobilis/tutorial-android-speech-to-text-sem-o-pop-up/))

Esse tipo de tutorial costuma ensinar a **não** abrir a `Activity` do Google com `startActivityForResult(RecognizerIntent…)`, e em vez disso usar:

- `SpeechRecognizer.createSpeechRecognizer(context)`
- `setRecognitionListener(…)`
- `startListening(Intent com ACTION_RECOGNIZE_SPEECH)`

Assim o reconhecimento corre **em segundo plano**, sem o **diálogo visual** (“pop-up”) do assistente de voz.

### Já estamos a fazer isso no projeto?

**Sim, indiretamente.** O plugin **speech_to_text** (versão em uso no projeto, ex. 7.3.x) faz exactamente esse caminho no Android: cria o `SpeechRecognizer`, regista o listener no próprio plugin e chama `speechRecognizer?.startListening(recognizerIntent)` — **não** usa `startActivityForResult` para o fluxo normal de escuta.

Trecho de referência no código do plugin (`SpeechToTextPlugin.kt`):

```kotlin
speechRecognizer?.startListening(recognizerIntent)
```

Portanto **não é necessário** duplicar em Kotlin no `android/` do app o código do tutorial da UFOP só para “tirar o pop-up”: o `USE_SYSTEM_SPEECH_TO_TEXT` + `speech_to_text` **já segue o padrão “sem Activity de voz”**.

Se ainda vires um ecrã ou bolha de voz, pode ser comportamento de **fabricante/OEM**, outra parte da app, ou confusão com o **beep** (som) — que, como acima, **não** é o mesmo problema que o pop-up e **não** tem API oficial para desligar.
