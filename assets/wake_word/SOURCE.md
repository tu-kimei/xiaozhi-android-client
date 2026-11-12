# Local wake-word model

Upstream: https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models

Release archive: `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2`.
The upstream model card declares Apache License 2.0; see MODEL_CARD.md and LICENSE.

Only the int8 encoder/joiner, fp32 decoder and token table are bundled. The files
are renamed locally to encoder.int8.onnx, joiner.int8.onnx and decoder.onnx.
`bpe_vocab.json` contains the original SentencePiece piece scores. The Dart
Viterbi tokenizer was compared against the original SentencePiece processor for
English phrases including Hey Doradino, Hey Dora Dino, Hello Robot and Hey Siri.
`default_keywords.txt` is a reproducible reference fixture; the app generates
its keyword configuration locally from the selected phrase.

Documentation: https://k2-fsa.github.io/sherpa/onnx/kws/index.html
