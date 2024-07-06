// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:developer';
// import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rtmp_broadcaster/camera.dart';
import 'package:wakelock/wakelock.dart';

class CameraExampleHome extends StatefulWidget {
  @override
  _CameraExampleHomeState createState() {
    return _CameraExampleHomeState();
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection? direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
    default:
      return Icons.camera;
  }
}

void logError(String code, String message) =>
    log('Error: $code\nError Message: $message');

class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver {
  CameraController? controller;
  String? imagePath;
  Icon buttonIcon = const Icon(Icons.watch);

  String? videoPath;
  String? url;
  bool enableAudio = true;
  bool useOpenGL = true;
  TextEditingController _textFieldController =
      TextEditingController(text: "rtmp://192.168.1.71:1935/live/");

  bool get isStreaming => controller?.value.isStreamingVideoRtmp ?? false;
  bool isVisible = true;

  bool get isControllerInitialized => controller?.value.isInitialized ?? false;

  bool get isStreamingVideoRtmp =>
      controller?.value.isStreamingVideoRtmp ?? false;

  bool get isRecordingVideo => controller?.value.isRecordingVideo ?? false;

  bool get isRecordingPaused => controller?.value.isRecordingPaused ?? false;

  bool get isStreamingPaused => controller?.value.isStreamingPaused ?? false;

  bool get isTakingPicture => controller?.value.isTakingPicture ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Wakelock.disable();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    // App state changed before we got the chance to initialize.
    if (controller == null || !isControllerInitialized) {
      return;
    }
    if (state == AppLifecycleState.paused) {
      isVisible = false;
      if (isStreaming) {
        await pauseVideoStreaming();
      }
    } else if (state == AppLifecycleState.resumed) {
      isVisible = true;
      if (controller != null) {
        if (isStreaming) {
          await resumeVideoStreaming();
        } else {
          onNewCameraSelected(controller!.description);
        }
      }
    }
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;
    if (controller != null) {
      if (controller!.value.isRecordingVideo ?? false) {
        buttonIcon = const Icon(Icons.watch);
        color = Colors.red;
      } else if (controller!.value.isStreamingVideoRtmp ?? false) {
        buttonIcon = const Icon(Icons.stop);
        color = Colors.blue;
      }
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Camera example'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color: color,
                  width: 3.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: Center(
                  child: _cameraPreviewWidget(),
                ),
              ),
            ),
          ),
          _captureControlRowWidget(),
          _toggleAudioWidget(),
          _cameraTogglesRowWidget(),
        ],
      ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !isControllerInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller!.value.aspectRatio,
      child: CameraPreview(controller!),
    );
  }

  /// Toggle recording audio
  Widget _toggleAudioWidget() {
    return Padding(
      padding: const EdgeInsets.only(left: 25),
      child: Row(
        children: <Widget>[
          const Text('Enable Audio:'),
          Switch(
            value: enableAudio,
            onChanged: (bool value) {
              enableAudio = value;
              if (controller != null) {
                onNewCameraSelected(controller!.description);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    if (controller == null) return Container();
    return FloatingActionButton(
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
      onPressed:
          controller != null && isControllerInitialized && !isStreamingVideoRtmp
              ? onVideoStreamingButtonPressed
              : null,
      child: buttonIcon,
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    final List<Widget> toggles = <Widget>[];

    if (cameras.isEmpty) {
      return const Text('No camera found');
    } else {
      for (CameraDescription cameraDescription in cameras) {
        toggles.add(
          SizedBox(
            width: 90.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: (CameraDescription? cld) =>
                  isRecordingVideo ? null : onNewCameraSelected(cld),
            ),
          ),
        );
      }
    }

    return Row(children: toggles);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onNewCameraSelected(CameraDescription? cameraDescription) async {
    if (cameraDescription == null) return;

    if (controller != null) {
      await stopVideoStreaming();
      await controller?.dispose();
    }
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: enableAudio,
      androidUseOpenGL: useOpenGL,
    );

    // If the controller is updated then update the UI.
    controller!.addListener(() async {
      if (mounted) setState(() {});

      if (controller != null) {
        if (controller!.value.hasError) {
          showInSnackBar('Camera error ${controller!.value.errorDescription}');
          await stopVideoStreaming();
        } else {
          try {
            final Map<dynamic, dynamic> event =
                controller!.value.event as Map<dynamic, dynamic>;
            log('Event $event');
            final String eventType = event['eventType'] as String;
            if (isVisible && isStreaming && eventType == 'rtmp_retry') {
              showInSnackBar('BadName received, endpoint in use.');
              await stopVideoStreaming();
            }
          } catch (e) {
            print(e);
          }
        }
      }
    });

    try {
      await controller!.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onVideoStreamingButtonPressed() {
    startVideoStreaming().then((String? url) {
      if (mounted) setState(() {});
      showInSnackBar('Streaming video to $url');
      Wakelock.enable();
    });
  }

  void onStopStreamingButtonPressed() {
    stopVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video not streaming to: $url');
    });
  }

  void onPauseStreamingButtonPressed() {
    pauseVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video streaming paused');
    });
  }

  void onResumeStreamingButtonPressed() {
    resumeVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video streaming resumed');
    });
  }

  Future<String> _getUrl() async {
    // Open up a dialog for the url
    String result = _textFieldController.text;

    return await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Url to Stream to'),
            content: TextField(
              controller: _textFieldController,
              decoration: const InputDecoration(hintText: "Url to Stream to"),
              onChanged: (String str) => result = str,
            ),
            actions: <Widget>[
              TextButton(
                child:
                    Text(MaterialLocalizations.of(context).cancelButtonLabel),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
                onPressed: () {
                  Navigator.pop(context, result);
                },
              )
            ],
          );
        });
  }

  Future<String?> startVideoStreaming() async {
    await stopVideoStreaming();
    if (controller == null) {
      return null;
    }
    if (!isControllerInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (controller?.value.isStreamingVideoRtmp ?? false) {
      return null;
    }

    // Open up a dialog for the url
    String myUrl = await _getUrl();

    try {
      url = myUrl;
      await controller!.startVideoStreaming(url!);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return url;
  }

  Future<void> stopVideoStreaming() async {
    if (controller == null || !isControllerInitialized) {
      return;
    }
    if (!isStreamingVideoRtmp) {
      return;
    }

    try {
      await controller!.stopVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  Future<void> pauseVideoStreaming() async {
    if (!isStreamingVideoRtmp) {
      return null;
    }

    try {
      await controller!.pauseVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> resumeVideoStreaming() async {
    if (!isStreamingVideoRtmp) {
      return null;
    }

    try {
      await controller!.resumeVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description ?? "No description found");
    showInSnackBar(
        'Error: ${e.code}\n${e.description ?? "No description found"}');
  }
}

class CameraApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

List<CameraDescription> cameras = [];

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();
  } on CameraException catch (e) {
    logError(e.code, e.description ?? "No description found");
  }
  runApp(CameraApp());
}
