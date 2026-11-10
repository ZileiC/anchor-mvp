import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anchor_app/models/models.dart';
import 'package:anchor_app/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transport double: the handler decides what comes back, including when.
class StubTransport implements HttpTransport {
  StubTransport(this.handler);

  final Future<TransportResponse> Function(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  )
  handler;

  @override
  Future<TransportResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    required Duration timeout,
  }) => handler(method, url, headers, body);
}

TransportResponse jsonResponse(Object? payload, {int status = 200}) =>
    TransportResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );

TransportResponse errorResponse(
  String code,
  String message, {
  int status = 400,
  Map<String, Object?> extra = const <String, Object?>{},
}) => jsonResponse(<String, Object?>{
  'error': <String, Object?>{'code': code, 'message': message, ...extra},
}, status: status);

ApiClient stubApi(
  Future<TransportResponse> Function(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  )
  handler, {
  String? token,
}) => ApiClient(
  baseUrl: 'http://127.0.0.1:8077',
  transport: StubTransport(handler),
)..token = token;

void main() {
  group('requests', () {
    test('dev login posts the user id and returns the token', () async {
      String? sentAuth;
      String? sentMethod;
      Uri? sentUrl;
      String? sentBody;
      final api = stubApi((method, url, headers, body) async {
        sentMethod = method;
        sentAuth = headers['Authorization'];
        sentUrl = url;
        sentBody = body;
        return jsonResponse(<String, Object?>{
          'access_token': 'abc123',
          'token_type': 'bearer',
          'expires_in': 86400,
        });
      });

      final token = await api.devLogin(1);

      expect(token.accessToken, 'abc123');
      expect(token.expiresIn, 86400);
      expect(sentMethod, 'POST');
      expect(sentUrl.toString(), 'http://127.0.0.1:8077/api/v1/dev/login');
      expect(sentBody, contains('"user_id":1'));
      expect(sentAuth, isNull);
    });

    test('sends the bearer token once signed in', () async {
      String? sentAuth;
      final api = stubApi((method, url, headers, body) async {
        sentAuth = headers['Authorization'];
        return jsonResponse(<String, Object?>{
          'id': 1,
          'role': 'senior',
          'display_name': '林秀兰',
          'timezone': 'Asia/Shanghai',
          'locale': 'zh-CN',
          'senior_id': 1,
        });
      }, token: 'tok');
      final profile = await api.me();
      expect(sentAuth, 'Bearer tok');
      expect(profile.displayName, '林秀兰');
      expect(profile.isSenior, isTrue);
    });

    test('decodes UTF-8 responses instead of mojibake', () async {
      final api = stubApi((method, url, headers, body) async {
        return TransportResponse(
          200,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'items': <Object?>[
                  <String, Object?>{
                    'id': 1,
                    'fact': '喜欢在阳台种花',
                    'approval_state': 'approved',
                  },
                ],
              }),
            ),
          ),
        );
      }, token: 'tok');

      final memories = await api.memories();
      expect(memories, hasLength(1));
      expect(memories.first.fact, '喜欢在阳台种花');
    });

    test('passes device_id as a query parameter', () async {
      Uri? sentUrl;
      final api = stubApi((method, url, headers, body) async {
        sentUrl = url;
        return jsonResponse(<String, Object?>{
          'eligible': true,
          'reasons': <String>[],
          'cap_remaining': 1,
          'local_time': '10:00',
          'local_date': '2026-03-10',
          'designated_device_ok': true,
        });
      }, token: 'tok');
      await api.checkinEligibility(deviceId: 'dev-1');
      expect(sentUrl!.queryParameters['device_id'], 'dev-1');
    });
  });

  group('parsing', () {
    test('a turn with a dial action is parsed completely', () async {
      final api = stubApi((method, url, headers, body) async {
        return jsonResponse(<String, Object?>{
          'turn_id': 7,
          'transcript': '给美打电话',
          'reply_text': '要给 Mei 打电话吗？',
          'intent': 'call',
          'stopped': false,
          'action': <String, Object?>{
            'type': 'dial',
            'contact_id': 3,
            'label': 'Mei',
            'phone': '13800000000',
            'requires_confirmation': true,
          },
          'ask': null,
          'captions': <Object?>[
            <String, Object?>{
              'role': 'senior',
              'text': '给美打电话',
              'at': '2026-03-10T01:30:00Z',
            },
          ],
        });
      }, token: 'tok');

      final turn = await api.turn('session-1', text: '给美打电话');
      expect(turn.intent, 'call');
      expect(turn.action, isNotNull);
      expect(turn.action!.isDial, isTrue);
      expect(turn.action!.phone, '13800000000');
      expect(turn.action!.requiresConfirmation, isTrue);
      expect(turn.captions.single.isSenior, isTrue);
      expect(turn.stopped, isFalse);
    });

    test('consent snapshot stays private and copies the version', () async {
      final api = stubApi((method, url, headers, body) async {
        return jsonResponse(<String, Object?>{
          'version': 4,
          'items': <Object?>[
            <String, Object?>{
              'capability': 'share_topic',
              'topic': 'mood',
              'allowed': false,
              'version': 4,
            },
          ],
        });
      }, token: 'tok');
      final snapshot = await api.consents();
      expect(snapshot.version, 4);
      expect(snapshot.shareTopicAllowed('mood'), isFalse);
      expect(snapshot.shareTopicAllowed('meals'), isFalse);
      expect(snapshot.cloudProcessing, isFalse);
      expect(snapshot.anySharing, isFalse);
    });

    test('digests accept the list shape and the single-digest shape', () {
      final listShape = DigestList.fromResponse(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'id': 1,
            'status': 'approved',
            'period_start': '2026-03-02',
            'period_end': '2026-03-09',
            'items': <Object?>[
              <String, Object?>{
                'topic': 'meals',
                'text': '你这周提到自己做了粥。',
                'evidence_ids': <Object?>[11],
              },
            ],
          },
        ],
      });
      expect(listShape.digests, hasLength(1));
      expect(listShape.latest!.highlights.single.topic, 'meals');
      expect(listShape.latest!.highlights.single.evidenceIds, <int>[11]);

      final singleShape = DigestList.fromResponse(<String, Object?>{
        'status': 'insufficient_data',
        'message': '这周的信息还不够，先不下结论。',
        'items': <Object?>[],
      });
      expect(singleShape.digests.single.isInsufficientData, isTrue);
    });

    test('an empty caregiver list keeps the insufficient-information note', () {
      final list = DigestList.fromResponse(<String, Object?>{
        'items': <Object?>[],
        'note': 'insufficient_information',
      });
      expect(list.digests, isEmpty);
      expect(list.insufficientInformation, isTrue);
    });

    test('a digest never exposes more than three highlights', () {
      final digest = Digest.fromJson(<String, Object?>{
        'id': 9,
        'status': 'approved',
        'items': <Object?>[
          for (var index = 0; index < 5; index++)
            <String, Object?>{'topic': 'mood', 'text': '第 $index 条'},
        ],
      });
      expect(digest.items, hasLength(5));
      expect(digest.highlights, hasLength(3));
    });
  });

  group('error mapping', () {
    test('the backend envelope becomes a structured ApiException', () async {
      final api = stubApi((method, url, headers, body) async {
        return errorResponse('not_found', 'Nothing here', status: 404);
      }, token: 'tok');
      await expectLater(
        api.me(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'not_found')
              .having((error) => error.statusCode, 'status', 404)
              .having((error) => error.isFeatureUnavailable, 'missing', isTrue),
        ),
      );
    });

    test('conflict keeps the session id from the envelope', () async {
      final api = stubApi((method, url, headers, body) async {
        return errorResponse(
          'conflict',
          'A conversation is already open.',
          status: 409,
          extra: <String, Object?>{'session_id': 'abc-123'},
        );
      }, token: 'tok');
      try {
        await api.openSession();
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.code, 'conflict');
        expect(error.conflictSessionId, 'abc-123');
      }
    });

    test('provider failures carry their recovery hints', () async {
      final api = stubApi((method, url, headers, body) async {
        return errorResponse(
          'provider_unavailable',
          'Speech provider unavailable',
          status: 503,
          extra: <String, Object?>{
            'recovery': <Object?>['retry', 'type_instead'],
          },
        );
      }, token: 'tok');
      try {
        await api.turn('s', text: '你好');
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.recovery, <String>['retry', 'type_instead']);
        expect(error.statusCode, 503);
      }
    });

    test('a bare FastAPI 404 still maps to not_found', () async {
      final api = stubApi((method, url, headers, body) async {
        return jsonResponse(<String, Object?>{
          'detail': 'Not Found',
        }, status: 404);
      }, token: 'tok');
      try {
        await api.digests();
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.code, 'not_found');
        expect(error.isFeatureUnavailable, isTrue);
      }
    });

    test('a socket failure becomes the offline code', () async {
      final api = stubApi((method, url, headers, body) async {
        throw const SocketException('connection refused');
      }, token: 'tok');
      try {
        await api.me();
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.isOffline, isTrue);
        expect(error.recovery, contains('type_instead'));
      }
    });

    test('a timeout becomes the offline code', () async {
      final api = stubApi((method, url, headers, body) async {
        throw TimeoutException('slow');
      }, token: 'tok');
      await expectLater(
        api.me(),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', isTrue),
        ),
      );
    });
  });

  group('tts', () {
    test('POST /tts returns the raw mp3 bytes untouched', () async {
      // 0xFF 0xFB is an mp3 frame header and is invalid UTF-8 on purpose: the
      // client must return the body as bytes, never decode it as text.
      final mp3 = Uint8List.fromList(<int>[0xFF, 0xFB, 0x90, 0x64, 0x00, 0xFF]);
      String? sentMethod;
      Uri? sentUrl;
      String? sentBody;
      String? sentAccept;
      String? sentContentType;
      String? sentAuth;
      final api = stubApi((method, url, headers, body) async {
        sentMethod = method;
        sentUrl = url;
        sentBody = body;
        sentAccept = headers['Accept'];
        sentContentType = headers['Content-Type'];
        sentAuth = headers['Authorization'];
        return TransportResponse(200, mp3);
      }, token: 'tok');

      final audio = await api.ttsSpeech(text: '你好', voice: null, rate: '-12%');

      expect(sentMethod, 'POST');
      expect(sentUrl.toString(), 'http://127.0.0.1:8077/api/v1/tts');
      expect(sentAccept, 'audio/mpeg');
      expect(sentContentType, 'application/json; charset=utf-8');
      expect(sentAuth, 'Bearer tok', reason: 'POST /tts needs the login token');
      expect(jsonDecode(sentBody!), <String, Object?>{
        'text': '你好',
        'voice': null,
        'rate': '-12%',
      });
      expect(audio, mp3);
    });

    test('a 503 keeps the provider_unavailable envelope', () async {
      final api = stubApi((method, url, headers, body) async {
        return errorResponse(
          'provider_unavailable',
          'Speech provider unavailable',
          status: 503,
          extra: <String, Object?>{
            'recovery': <Object?>['retry', 'type_instead'],
          },
        );
      }, token: 'tok');

      await expectLater(
        api.ttsSpeech(text: '你好'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'provider_unavailable')
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.recovery, 'recovery', contains('retry')),
        ),
      );
    });

    test('an empty 200 body is an error, not silence', () async {
      final api = stubApi(
        (method, url, headers, body) async =>
            TransportResponse(200, Uint8List(0)),
        token: 'tok',
      );

      await expectLater(
        api.ttsSpeech(text: '你好'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'empty_audio'),
        ),
      );
    });

    test('a late audio response after Stop is discarded', () async {
      final completer = Completer<TransportResponse>();
      final api = stubApi(
        (method, url, headers, body) => completer.future,
        token: 'tok',
      );

      final pending = api.ttsSpeech(text: '不要再说');
      api.nonce.bump();
      completer.complete(
        TransportResponse(200, Uint8List.fromList(<int>[0xFF, 0xFB])),
      );

      await expectLater(pending, throwsA(isA<ApiCancelled>()));
    });
  });

  group('transcribe', () {
    test('POST /transcribe sends the clip and returns the words', () async {
      String? sentMethod;
      Uri? sentUrl;
      String? sentBody;
      String? sentAuth;
      final api = stubApi((method, url, headers, body) async {
        sentMethod = method;
        sentUrl = url;
        sentBody = body;
        sentAuth = headers['Authorization'];
        return jsonResponse(<String, Object?>{
          'text': ' 十二 ',
          'provider': 'siliconflow',
        });
      }, token: 'tok');

      final text = await api.transcribe(
        audioB64: 'UklGRg==',
        audioMime: 'audio/wav',
      );

      expect(sentMethod, 'POST');
      expect(sentUrl.toString(), 'http://127.0.0.1:8077/api/v1/transcribe');
      expect(sentAuth, 'Bearer tok');
      expect(jsonDecode(sentBody!), <String, Object?>{
        'audio_b64': 'UklGRg==',
        'audio_mime': 'audio/wav',
      });
      expect(text, '十二');
    });

    test('the mime type defaults to audio/wav, the contract value', () async {
      String? sentBody;
      final api = stubApi((method, url, headers, body) async {
        sentBody = body;
        return jsonResponse(<String, Object?>{'text': '好'});
      }, token: 'tok');

      await api.transcribe(audioB64: 'UklGRg==');

      expect(jsonDecode(sentBody!), <String, Object?>{
        'audio_b64': 'UklGRg==',
        'audio_mime': 'audio/wav',
      });
    });

    test('a 503 keeps the provider_unavailable envelope', () async {
      final api = stubApi((method, url, headers, body) async {
        return errorResponse(
          'provider_unavailable',
          'Speech recognition is not available',
          status: 503,
          extra: <String, Object?>{
            'recovery': <Object?>['retry', 'type_instead'],
          },
        );
      }, token: 'tok');

      await expectLater(
        api.transcribe(audioB64: 'UklGRg=='),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'provider_unavailable')
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.recovery, 'recovery', contains('retry')),
        ),
      );
    });

    test('a 422 is a validation error, not a transcript', () async {
      final api = stubApi((method, url, headers, body) async {
        return errorResponse(
          'validation_error',
          'Unreadable audio',
          status: 422,
        );
      }, token: 'tok');

      await expectLater(
        api.transcribe(audioB64: 'not-wav'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'validation_error')
              .having((e) => e.statusCode, 'status', 422),
        ),
      );
    });

    test(
      'a 200 without text is an empty transcript, never invented words',
      () async {
        final api = stubApi(
          (method, url, headers, body) async =>
              jsonResponse(<String, Object?>{}),
          token: 'tok',
        );

        expect(await api.transcribe(audioB64: 'UklGRg=='), isEmpty);
      },
    );
  });

  group('request nonce', () {
    test('a reply that arrives after Stop is discarded', () async {
      final completer = Completer<TransportResponse>();
      final api = stubApi(
        (method, url, headers, body) => completer.future,
        token: 'tok',
      );

      final pending = api.turn('session-1', text: '你好');
      api.nonce.bump();
      completer.complete(
        jsonResponse(<String, Object?>{
          'transcript': '你好',
          'reply_text': '你好呀',
          'intent': 'chat',
          'stopped': false,
          'captions': <Object?>[],
        }),
      );

      await expectLater(pending, throwsA(isA<ApiCancelled>()));
    });

    test('stop itself is never discarded', () async {
      final api = stubApi((method, url, headers, body) async {
        return jsonResponse(<String, Object?>{'state': 'stopped'});
      }, token: 'tok');
      api.nonce.bump();
      await api.stopSession('session-1');
    });
  });

  group('providers', () {
    test(
      'GET /providers parses the effective engines and the masked key',
      () async {
        Uri? sentUrl;
        final api = stubApi((method, url, headers, body) async {
          sentUrl = url;
          return jsonResponse(<String, Object?>{
            'llm': <String, Object?>{
              'configured': true,
              'base_url': 'https://api.deepseek.com',
              'model': 'deepseek-chat',
              'key_hint': 'sk-…abcd',
              'mode': 'http',
              'engine': 'http',
            },
            'asr': <String, Object?>{
              'configured': true,
              'base_url': null,
              'model': 'whisper-1',
              'key_hint': null,
              'mode': 'offline',
              'engine': 'windows-sapi',
            },
            'updated_at': '2026-03-10T01:30:00Z',
          });
        }, token: 'tok');

        final providers = await api.providers();

        expect(sentUrl.toString(), 'http://127.0.0.1:8077/api/v1/providers');
        expect(providers.llm.configured, isTrue);
        expect(providers.llm.usesHttp, isTrue);
        expect(providers.llm.keyHint, 'sk-…abcd');
        expect(providers.asr.isWindowsSapi, isTrue);
        expect(providers.asr.configured, isTrue);
        expect(providers.updatedAt, '2026-03-10T01:30:00Z');
      },
    );

    test('PUT /providers sends only the fields that changed', () async {
      String? sentMethod;
      String? sentBody;
      final api = stubApi((method, url, headers, body) async {
        sentMethod = method;
        sentBody = body;
        return jsonResponse(<String, Object?>{
          'llm': <String, Object?>{
            'configured': true,
            'mode': 'http',
            'engine': 'http',
            'key_hint': 'sk-…test',
          },
          'asr': <String, Object?>{'configured': false, 'engine': 'none'},
        });
      }, token: 'tok');

      await api.updateProviders(
        const ProviderUpdate(
          llm: ProviderSectionUpdate(
            baseUrl: 'https://api.deepseek.com',
            model: 'deepseek-chat',
          ),
        ),
      );

      expect(sentMethod, 'PUT');
      expect(jsonDecode(sentBody!), <String, Object?>{
        'llm': <String, Object?>{
          'base_url': 'https://api.deepseek.com',
          'model': 'deepseek-chat',
        },
      });
    });

    test('a reset sends clear:true on its own', () async {
      String? sentBody;
      final api = stubApi((method, url, headers, body) async {
        sentBody = body;
        return jsonResponse(<String, Object?>{});
      }, token: 'tok');

      await api.updateProviders(
        const ProviderUpdate(asr: ProviderSectionUpdate(clear: true)),
      );

      expect(jsonDecode(sentBody!), <String, Object?>{
        'asr': <String, Object?>{'clear': true},
      });
    });

    test(
      'POST /providers/test sends the recorded clip and parses both halves',
      () async {
        String? sentBody;
        final api = stubApi((method, url, headers, body) async {
          sentBody = body;
          return jsonResponse(<String, Object?>{
            'llm': <String, Object?>{
              'ok': true,
              'latency_ms': 25,
              'reply_sample': '你好。',
              'error': null,
            },
            'asr': <String, Object?>{
              'ok': true,
              'latency_ms': 120,
              'text_sample': '今天天气很好',
              'error': null,
            },
          });
        }, token: 'tok');

        final result = await api.testProviders(
          audioB64: 'UklGRg==',
          audioMime: 'audio/wav',
        );

        expect(jsonDecode(sentBody!), <String, Object?>{
          'audio_b64': 'UklGRg==',
          'audio_mime': 'audio/wav',
        });
        expect(result.llm.ok, isTrue);
        expect(result.llm.replySample, '你好。');
        expect(result.asr.textSample, '今天天气很好');
      },
    );

    test(
      'without a clip the server reports no_sample, not a failure',
      () async {
        String? sentBody;
        final api = stubApi((method, url, headers, body) async {
          sentBody = body;
          return jsonResponse(<String, Object?>{
            'llm': <String, Object?>{'ok': false, 'error': 'not_configured'},
            'asr': <String, Object?>{'ok': false, 'reason': 'no_sample'},
          });
        }, token: 'tok');

        final result = await api.testProviders();

        expect(sentBody, isNull);
        expect(result.llm.error, 'not_configured');
        expect(result.asr.ok, isFalse);
        expect(result.asr.reason, 'no_sample');
      },
    );
  });
}
