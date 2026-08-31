import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;

void registerWebcam() {
  try {
    js.context.callMethod('eval', [
      // Shadow DOM Element Finder
      "window.findElGlobally = function(id) {"
      "  var el = document.getElementById(id);"
      "  if (el) return el;"
      "  function search(node) {"
      "    if (!node) return null;"
      "    if (node.id === id) return node;"
      "    if (node.shadowRoot) {"
      "      var found = search(node.shadowRoot);"
      "      if (found) return found;"
      "    }"
      "    var child = node.firstChild;"
      "    while (child) {"
      "      var found = search(child);"
      "      if (found) return found;"
      "      child = child.nextSibling;"
      "    }"
      "    return null;"
      "  }"
      "  return search(document.body);"
      "};"

      // 1. Dynamic Script Loader for TF.js and COCO-SSD
      "if (typeof tf === 'undefined') {"
      "  var tfScript = document.createElement('script');"
      "  tfScript.src = 'https://cdn.jsdelivr.net/npm/@tensorflow/tfjs';"
      "  tfScript.onload = function() { loadCocoSsd(); };"
      "  document.head.appendChild(tfScript);"
      "} else {"
      "  loadCocoSsd();"
      "}"
      
      "function loadCocoSsd() {"
      "  if (typeof cocoSsd === 'undefined') {"
      "    var cocoScript = document.createElement('script');"
      "    cocoScript.src = 'https://cdn.jsdelivr.net/npm/@tensorflow-models/coco-ssd';"
      "    cocoScript.onload = function() { initCocoModel(); };"
      "    document.head.appendChild(cocoScript);"
      "  } else {"
      "    initCocoModel();"
      "  }"
      "}"
      
      "window.cocoModel = null;"
      "function initCocoModel() {"
      "  if (typeof cocoSsd !== 'undefined') {"
      "    cocoSsd.load().then(function(model) {"
      "      window.cocoModel = model;"
      "      console.log('COCO-SSD Model Loaded successfully in browser.');"
      "      runCocoDetection();"
      "    });"
      "  }"
      "}"
      
      "window.currentDetections = [];"
      "function runCocoDetection() {"
      "  var video = window.findElGlobally('webcam-video-el');"
      "  if (video && video.readyState === 4 && window.cocoModel) {"
      "    window.cocoModel.detect(video).then(function(predictions) {"
      "      window.currentDetections = predictions;"
      "    }).catch(function(err) {"
      "      console.warn('Detection error: ', err);"
      "    });"
      "  }"
      "  setTimeout(runCocoDetection, 200);"
      "}"

      // 2. Dynamic Script Loader for MediaPipe Hands
      "if (typeof Hands === 'undefined') {"
      "  var mpHandsScript = document.createElement('script');"
      "  mpHandsScript.src = 'https://cdn.jsdelivr.net/npm/@mediapipe/hands/hands.js';"
      "  mpHandsScript.onload = function() { initMediaPipeHands(); };"
      "  document.head.appendChild(mpHandsScript);"
      "} else {"
      "  initMediaPipeHands();"
      "}"
      
      "window.mpHands = null;"
      "function initMediaPipeHands() {"
      "  if (typeof Hands !== 'undefined' && !window.mpHands) {"
      "    window.mpHands = new Hands({"
      "      locateFile: function(file) { return 'https://cdn.jsdelivr.net/npm/@mediapipe/hands/' + file; }"
      "    });"
      "    window.mpHands.setOptions({"
      "      maxNumHands: 1,"
      "      modelComplexity: 1,"
      "      minDetectionConfidence: 0.50,"
      "      minTrackingConfidence: 0.50"
      "    });"
      "    window.mpHands.onResults(onHandPoseResults);"
      "    console.log('MediaPipe Hands Initialized successfully.');"
      "    runHandTracking();"
      "  }"
      "}"
      
      "window.currentHandLandmarks = null;"
      "window.gestureHistory = [];"
      
      "function onHandPoseResults(results) {"
      "  if (results.multiHandLandmarks && results.multiHandLandmarks.length > 0) {"
      "    var landmarks = results.multiHandLandmarks[0];"
      "    window.currentHandLandmarks = landmarks;"
      "    var handShape = classifyHandShape(landmarks);"
      "    trackSosSequence(handShape);"
      "    if (window.onSignGestureDetected) {"
      "      window.onSignGestureDetected(handShape);"
      "    }"
      "  } else {"
      "    window.currentHandLandmarks = null;"
      "    if (window.onSignGestureDetected) {"
      "      window.onSignGestureDetected('NONE');"
      "    }"
      "  }"
      "}"
      
      "function classifyHandShape(lm) {"
      "  function getDistance(a, b) {"
      "    return Math.sqrt(Math.pow(a.x - b.x, 2) + Math.pow(a.y - b.y, 2));"
      "  }"
      "  var indexExtended = getDistance(lm[8], lm[5]) > (getDistance(lm[6], lm[5]) * 1.15);"
      "  var middleExtended = getDistance(lm[12], lm[9]) > (getDistance(lm[10], lm[9]) * 1.15);"
      "  var ringExtended = getDistance(lm[16], lm[13]) > (getDistance(lm[14], lm[13]) * 1.15);"
      "  var pinkyExtended = getDistance(lm[20], lm[17]) > (getDistance(lm[18], lm[17]) * 1.15);"
      "  var thumbDistanceToPalm = getDistance(lm[4], lm[5]);"
      "  var thumbFolded = thumbDistanceToPalm < 0.08;"
      "  var extendedCount = (indexExtended ? 1 : 0) + (middleExtended ? 1 : 0) + (ringExtended ? 1 : 0) + (pinkyExtended ? 1 : 0);"
      "  if (indexExtended && !middleExtended && !ringExtended && !pinkyExtended) return 'POINTING';"
      "  if (extendedCount >= 3 && !thumbFolded) return 'PALM_OPEN';"
      "  if (extendedCount >= 3 && thumbFolded) return 'THUMB_FOLDED';"
      "  if (extendedCount <= 1) return 'FIST';"
      "  return 'UNKNOWN';"
      "}"
      
      "function trackSosSequence(shape) {"
      "  if (!shape || shape === 'UNKNOWN') return;"
      "  var now = Date.now();"
      "  window.gestureHistory.push({ shape: shape, time: now });"
      "  window.gestureHistory = window.gestureHistory.filter(function(item) { return now - item.time < 3000; });"
      "  var hasPalm = false;"
      "  var hasThumbFolded = false;"
      "  var hasFist = false;"
      "  var palmTime = 0;"
      "  var thumbFoldedTime = 0;"
      "  for (var i = 0; i < window.gestureHistory.length; i++) {"
      "    var item = window.gestureHistory[i];"
      "    if (item.shape === 'PALM_OPEN' && !hasPalm) {"
      "      hasPalm = true;"
      "      palmTime = item.time;"
      "    } else if (item.shape === 'THUMB_FOLDED' && hasPalm && !hasThumbFolded && item.time > palmTime) {"
      "      hasThumbFolded = true;"
      "      thumbFoldedTime = item.time;"
      "    } else if (item.shape === 'FIST' && hasThumbFolded && !hasFist && item.time > thumbFoldedTime) {"
      "      hasFist = true;"
      "    }"
      "  }"
      "  if (hasPalm && hasThumbFolded && hasFist) {"
      "    console.log('UNIVERSAL GESTURE SOS DETECTED!');"
      "    if (window.onSosGestureDetected) {"
      "      window.onSosGestureDetected();"
      "      window.gestureHistory = [];"
      "    }"
      "  }"
      "}"
      
      "function runHandTracking() {"
      "  var video = window.findElGlobally('webcam-video-el');"
      "  if (video && video.readyState === 4 && window.mpHands) {"
      "    window.mpHands.send({ image: video }).catch(function(err) {});"
      "  }"
      "  setTimeout(runHandTracking, 200);"
      "}"

      // 3. Global frame capture helper
      "window.getWebcamFrame = function() {"
      "  var video = window.findElGlobally('webcam-video-el');"
      "  if (!video) return null;"
      "  var canvas = document.createElement('canvas');"
      "  canvas.width = video.videoWidth || 640;"
      "  canvas.height = video.videoHeight || 480;"
      "  var ctx = canvas.getContext('2d');"
      "  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);"
      "  return canvas.toDataURL('image/jpeg', 0.95);"
      "};"

      // 4. Proximity calculator based on bounding box size of detected objects
      "window.getWebcamProximity = function() {"
      "  var maxProximity = 0.0;"
      "  if (window.currentDetections && window.currentDetections.length > 0) {"
      "    var video = window.findElGlobally('webcam-video-el');"
      "    var vw = (video && video.videoWidth) ? video.videoWidth : 640;"
      "    for (var i = 0; i < window.currentDetections.length; i++) {"
      "      var d = window.currentDetections[i];"
      "      if (d.score > 0.40) {"
      "        var bboxWidth = d.bbox[2];"
      "        var ratio = bboxWidth / vw;"
      "        var p = Math.min(1.0, ratio * 1.5);"
      "        if (p > maxProximity) maxProximity = p;"
      "      }"
      "    }"
      "  }"
      "  return maxProximity;"
      "};"

      // 5. Bounding box coordinates extractor
      "window.getDetectedObstacles = function() {"
      "  var video = window.findElGlobally('webcam-video-el');"
      "  if (!video || !window.currentDetections) return '[]';"
      "  var vw = video.videoWidth || 640;"
      "  var vh = video.videoHeight || 480;"
      "  var list = [];"
      "  for (var i = 0; i < window.currentDetections.length; i++) {"
      "    var d = window.currentDetections[i];"
      "    if (d.score > 0.40) {"
      "      list.push({"
      "        'class': d.class,"
      "        'score': d.score,"
      "        'x': d.bbox[0] / vw,"
      "        'y': d.bbox[1] / vh,"
      "        'w': d.bbox[2] / vw,"
      "        'h': d.bbox[3] / vh"
      "      });"
      "    }"
      "  }"
      "  return JSON.stringify(list);"
      "};"

      // 6. Speech Recognition APIs
      "window.initSpeechRecognition = function() {"
      "  var SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;"
      "  if (!SpeechRecognition) {"
      "    console.warn('Speech Recognition not supported in this browser.');"
      "    return;"
      "  }"
      "  window.recognition = new SpeechRecognition();"
      "  window.recognition.continuous = true;"
      "  window.recognition.interimResults = true;"
      "  window.recognition.lang = 'th-TH';"
      "  window.recognition.onresult = function(event) {"
      "    var interim_transcript = '';"
      "    var final_transcript = '';"
      "    for (var i = event.resultIndex; i < event.results.length; ++i) {"
      "      if (event.results[i].isFinal) {"
      "        final_transcript += event.results[i][0].transcript;"
      "      } else {"
      "        interim_transcript += event.results[i][0].transcript;"
      "      }"
      "    }"
      "    if (window.onSpeechResult) {"
      "      window.onSpeechResult(final_transcript, interim_transcript);"
      "    }"
      "  };"
      "  window.recognition.onerror = function(event) {"
      "    console.error('Speech Recognition Error: ', event.error);"
      "    if (window.onSpeechError) {"
      "      window.onSpeechError(event.error);"
      "    }"
      "  };"
      "  window.recognition.onend = function() {"
      "    if (window.onSpeechEnd) {"
      "      window.onSpeechEnd();"
      "    }"
      "  };"
      "};"
      "window.startSpeechRecognition = function() {"
      "  if (!window.recognition) window.initSpeechRecognition();"
      "  if (window.recognition) {"
      "    try {"
      "      window.recognition.abort();"
      "    } catch(e) {}"
      "    setTimeout(function() {"
      "      try {"
      "        window.recognition.start();"
      "      } catch(e) {"
      "        console.warn('Speech recognition start failed: ', e);"
      "      }"
      "    }, 50);"
      "  }"
      "};"
      "window.stopSpeechRecognition = function() {"
      "  if (window.recognition) {"
      "    try {"
      "      window.recognition.stop();"
      "    } catch(e) {}"
      "    try {"
      "      window.recognition.abort();"
      "    } catch(e) {}"
      "  }"
      "};"
    ]);
  } catch (e) {
    // Ignore error
  }

  ui_web.platformViewRegistry.registerViewFactory(
    'webcam-view',
    (int viewId) {
      final videoElement = html.VideoElement()
        ..autoplay = true
        ..id = 'webcam-video-el'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.pointerEvents = 'none';
      
      html.window.navigator.mediaDevices?.getUserMedia({
        'video': {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'facingMode': 'environment'
        }
      }).then((stream) {
        videoElement.srcObject = stream;
        js.context.callMethod('initCocoModel');
        js.context.callMethod('initMediaPipeHands');
      }).catchError((error) {
        html.window.console.warn('Error accessing webcam inside iframe: $error');
      });
      
      return videoElement;
    },
  );
}

String? getCapturedFrame() {
  try {
    final frame = js.context.callMethod('getWebcamFrame');
    return frame as String?;
  } catch (e) {
    return null;
  }
}

double getProximityValue() {
  try {
    final proximity = js.context.callMethod('getWebcamProximity');
    return (proximity as num).toDouble();
  } catch (e) {
    return 0.0;
  }
}

String getDetectedObstacles() {
  try {
    final obstaclesJson = js.context.callMethod('getDetectedObstacles');
    return obstaclesJson as String;
  } catch (e) {
    return "[]";
  }
}

void registerSosGestureCallback(void Function() callback) {
  js.context['onSosGestureDetected'] = () {
    callback();
  };
}

void registerSignGestureCallback(void Function(String gesture) callback) {
  js.context['onSignGestureDetected'] = js.JsFunction.withThis((thisArg, dynamic gesture) {
    callback(gesture.toString());
  });
}

void startLiveSpeech() {
  try {
    js.context.callMethod('startSpeechRecognition');
  } catch (e) {
    // ignore
  }
}

void stopLiveSpeech() {
  try {
    js.context.callMethod('stopSpeechRecognition');
  } catch (e) {
    // ignore
  }
}

void registerSpeechCallbacks({
  required void Function(String finalTranscript, String interimTranscript) onResult,
  required void Function(String error) onError,
  required void Function() onEnd,
}) {
  js.context['onSpeechResult'] = js.JsFunction.withThis((thisArg, dynamic finalT, dynamic interimT) {
    onResult(finalT.toString(), interimT.toString());
  });
  js.context['onSpeechError'] = js.JsFunction.withThis((thisArg, dynamic error) {
    onError(error.toString());
  });
  js.context['onSpeechEnd'] = js.JsFunction.withThis((thisArg) {
    onEnd();
  });
}
