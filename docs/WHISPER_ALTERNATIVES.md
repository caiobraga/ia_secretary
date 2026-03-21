# Whisper removido do app

O **Whisper foi removido** do projeto porque a biblioteca nativa (`libwhisper.so`) causava **crash** em vários dispositivos Android durante a transcrição.

## STT com Whisper (servidor)

O app envia áudio para **`REMOTE_STT_URL`** (ex. `stt_server` atrás de um túnel HTTPS). Whisper on-device no APK foi removido (crash).

**Segmentação:** o fim do segmento é por **silêncio** (nível do microfone via plugin `record`), com teto **`REMOTE_STT_MAX_SEGMENT_SECONDS`** (padrão 15s). Ajuste `REMOTE_STT_SILENCE_END_MS` se cortar cedo ou tarde demais. `REMOTE_STT_CHUNK_SECONDS` é legado e não define mais o corte.

## Reconhecimento de voz sem beep (atual)

Use **Vosk** (padrão no Android quando `USE_SYSTEM_SPEECH_TO_TEXT` não está ativo):
- Reconhecimento local, sem beep, estável.
- Fale de forma um pouco mais pausada para melhor precisão.

## Se no futuro quiser Whisper de volta

1. **whisper_ggml_plus** (on-device)  
   Quando o build Android do pacote for corrigido (erro de link `liblog`), dá para adicionar de novo e usar `WhisperController` + `transcribe(audioPath: path, lang: 'pt')`.

2. **Whisper via API OpenAI** (nuvem)  
   Usar **flutter_whisper_api**: gravar áudio, enviar para a API, receber texto. Sem lib nativa no device; requer API key e internet.
