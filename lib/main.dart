import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:socket_io_client/socket_io_client.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title = ""}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isPlaying = false;
  bool isRecording = false;
  FlutterSoundPlayer _mPlayer = FlutterSoundPlayer();
  FlutterSoundRecorder _mRecorder = FlutterSoundRecorder();
  bool _mPlayerIsInited = false;
  bool _mRecorderIsInited = false;
  bool _mplaybackReady = false;
  String connectedId = "NO ID";

  bool _shouldReadBuffer = true;
  // StreamSocket streamSocket = StreamSocket();

  StreamSubscription _mRecordingDataSubscription;
  IO.Socket socket;
  @override
  void initState() {
    super.initState();

    configSocket();

    _mPlayer.openAudioSession().then((value) {
      _mPlayerIsInited = true;
    });
    _mPlayer.setVolume(1);
    _openRecorder();
  }

  void configSocket() {
    socket = IO.io(
        'http://45.149.79.146:5634',
        OptionBuilder()
            .enableAutoConnect()
            .setTransports(['websocket']).setQuery({}).build());
    socket.onConnect((data) {
      print('connect : $data');
    });

    socket.on(
        'message',
        (data) => setState(() {
              connectedId = data.toString();
            }));
    socket.onDisconnect((_) => print('disconnect'));
    socket.on('audio-transfer', (data) {
      feedHim(Uint8List.fromList(data.toString().codeUnits));
    });
  }

  Future<void> _openRecorder() async {
    await _mRecorder.openAudioSession();
    setState(() {
      _mRecorderIsInited = true;
    });
  }

  Future<void> record() async {
    assert(_mRecorderIsInited);

    final audioPackets = BytesBuilder();
    final int packetLength = 20000;
    var recordingDataController = StreamController<Food>();
    _mRecordingDataSubscription =
        recordingDataController.stream.listen((buffer) {
      if (buffer is FoodData) {
        if (audioPackets.length <= packetLength) {
          audioPackets.add(buffer.data);
        } else {
          socket.emit(
              "audio-transfer", String.fromCharCodes(audioPackets.toBytes()));
          audioPackets.clear();
        }
      }
    });
    PermissionStatus status = await Permission.microphone.request();
    if (status != PermissionStatus.granted)
      throw RecordingPermissionException("Microphone permission not granted");

    await _mRecorder.startRecorder(
      toStream: recordingDataController.sink,
      codec: Codec.pcm16,
      sampleRate: tSampleRate,
      numChannels: 1,
    );
  }

  Future<void> stopRecorder() async {
    await _mRecorder.stopRecorder();
    if (_mRecordingDataSubscription != null) {
      await _mRecordingDataSubscription.cancel();
      _mRecordingDataSubscription = null;
    }
    _mplaybackReady = true;
  }

  Future<void> feedHim(Uint8List buffer) async {
    if (_shouldReadBuffer) {
      _shouldReadBuffer = false;
      await _mPlayer
          .feedFromStream(buffer)
          .then((value) => _shouldReadBuffer = true);
    }
  }

  void play() async {
    assert(_mPlayerIsInited && _mPlayer.isStopped);
    _mPlayer.setVolume(1);
    await _mPlayer.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: tSampleRate,
    );
  }

  Future<void> stopPlayer() async {
    await _mPlayer.stopPlayer();
  }

  @override
  void dispose() {
    stopPlayer();
    _mPlayer.closeAudioSession();
    _mPlayer = null;

    stopRecorder();
    _mRecorder.closeAudioSession();
    _mRecorder = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(connectedId),
            ElevatedButton(
              onPressed: () {
                isRecording ? stopRecorder() : record();
                setState(() {
                  isRecording = !isRecording;
                });
              },
              child: Text(isRecording ? "STOP" : "START" + " RECORDING"),
            ),
            ElevatedButton(
              onPressed: () {
                isPlaying ? stopPlayer() : play();
                setState(() {
                  isPlaying = !isPlaying;
                });
              },
              child: Text(isPlaying ? "STOP" : "START" + " PLAYING"),
            )
          ],
        ),
      ),
    );
  }
}

const int tSampleRate = 48000;
const int blockSize = 4096;

// class StreamSocket {
//   final _socketResponse = StreamController<String>();
//
//   void Function(String) get addResponse => _socketResponse.sink.add;
//
//   Stream<String> get getResponse => _socketResponse.stream;
//
//   void dispose() {
//     _socketResponse.close();
//   }
// }
