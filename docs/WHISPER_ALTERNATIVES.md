# Whisper removido do app

O **Whisper foi removido** do projeto porque a biblioteca nativa (`libwhisper.so`) causava **crash** em vários dispositivos Android durante a transcrição.

## Reconhecimento de voz sem beep (atual)

Use **Vosk** (padrão no Android quando `USE_SYSTEM_SPEECH_TO_TEXT` não está ativo):
- Reconhecimento local, sem beep, estável.
- Fale de forma um pouco mais pausada para melhor precisão.

## Se no futuro quiser Whisper de volta

1. **whisper_ggml_plus** (on-device)  
   Quando o build Android do pacote for corrigido (erro de link `liblog`), dá para adicionar de novo e usar `WhisperController` + `transcribe(audioPath: path, lang: 'pt')`.

2. **Whisper via API OpenAI** (nuvem)  
   Usar **flutter_whisper_api**: gravar áudio, enviar para a API, receber texto. Sem lib nativa no device; requer API key e internet.
