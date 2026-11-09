# Live AI evidence (real model + real speech)

Captured 2026-11-09 against the **packaged** self-contained demo (`AnchorDemo-0.2.0.zip`: double-click
`anchor_app.exe`, backend auto-starts) on this machine. The demo database is synthetic; no real
participant data was used.

## Setup used

- LLM configured at runtime via `PUT /api/v1/providers` (same call the app's **Settings → AI 接入**
  makes): base `https://api.deepseek.com`, model `deepseek-chat`, a personal DeepSeek key
  (masked by the API as `sk-…c9e2`; not stored in this repository, not included in the release zip).
- ASR: `auto` → `windows-sapi` (Windows System.Speech, zh-CN recognizer). No key.

## Provider state

```json
{
  "llm": {"configured": true, "base_url": "https://api.deepseek.com", "model": "deepseek-chat",
          "key_hint": "sk-…c9e2", "mode": "http", "engine": "http"},
  "asr": {"configured": true, "mode": "offline", "engine": "windows-sapi"}
}
```

`POST /providers/test` → `llm.ok=true`, latency 922 ms, `reply_sample: "你好！很高兴见到你。"`

## Real conversation (text)

- User: 我今天有点闷，陪我说说话吧
- Anchor: **好呀，我陪您说说话。您阳台上那些花，今天开了吗？** (model-generated; not a template)

## Real voice input (audio → ASR → reply)

- Spoken WAV (SAPI TTS): “今天天气不错，我想出去走走。”
- Backend transcript: **今天天气不错** (System.Speech cuts at the pause — real recognition, partial by
  the recognizer, not fabricated)
- Anchor reply: **是啊，阳光挺好的。您阳台上那些花，今天晒着太阳了吧？**

## Reproduce

1. Start the packaged app (or `scripts\run_backend.ps1` with `ANCHOR_ASR_PROVIDER=auto`).
2. In the app: Settings → AI 接入 → 填入 DeepSeek 预设 → paste key → 保存 → 测试连接.
3. Talk: type or press 开始说话; the transcript and reply come from the real ASR/LLM.

Without a key the UI labels replies “离线模板回复”; without a recognizer/ASR provider the mic is
disabled with an honest message. WER and dialect quality remain unmeasured (`docs/measurement.md`).
