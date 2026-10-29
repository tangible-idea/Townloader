import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Dart 쪽 `ShareIntake` 와 같은 채널 이름.
  private static let shareChannelName = "townloader/share"

  private var shareChannel: FlutterMethodChannel?
  private var ocrChannel: FlutterMethodChannel?

  /// Dart 가 준비되기 전에 들어온 공유 링크. `getInitialShare` 호출 때 한 번 넘기고 비운다.
  private var pendingShare: String?
  private var dartReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let messenger = registrar(forPlugin: "TownloaderShare")?.messenger() {
      let channel = FlutterMethodChannel(name: Self.shareChannelName, binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self, call.method == "getInitialShare" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self.dartReady = true
        result(self.pendingShare)
        self.pendingShare = nil
      }
      shareChannel = channel
    }

    if let messenger = registrar(forPlugin: "TownloaderOcr")?.messenger() {
      let channel = FlutterMethodChannel(name: "townloader/ocr", binaryMessenger: messenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "recognize", let data = call.arguments as? FlutterStandardTypedData else {
          result(FlutterMethodNotImplemented)
          return
        }
        TextRecognizer.recognize(data.data, completion: result)
      }
      ocrChannel = channel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 공유 확장이 여는 `townloader://share?url=...` 을 받는다.
  /// 앱이 꺼져 있다 켜진 경우에도 이 메서드가 불리므로 여기 한 곳에서 처리한다.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme == "townloader", url.host == "share" else {
      return super.application(app, open: url, options: options)
    }
    let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "url" })?.value
    guard let link, !link.isEmpty else { return false }

    if dartReady {
      shareChannel?.invokeMethod("onShare", arguments: link)
    } else {
      pendingShare = link
    }
    return true
  }
}

/// Dart 쪽 `TextRecognizer` 의 iOS 구현. Apple Vision 으로 사진의 글자를 줄마다 읽는다.
enum TextRecognizer {
  static func recognize(_ data: Data, completion: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = UIImage(data: data)?.cgImage else {
        DispatchQueue.main.async {
          completion(FlutterError(code: "bad_image", message: "Couldn't decode the image.", details: nil))
        }
        return
      }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["ko-KR", "en-US"]
      request.usesLanguageCorrection = true
      do {
        try VNImageRequestHandler(cgImage: image).perform([request])
      } catch {
        DispatchQueue.main.async {
          completion(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      // Vision 의 좌표는 왼쪽 아래가 원점이라 위가 0 이 되도록 뒤집는다.
      let lines: [[String: Any]] = (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let box = observation.boundingBox
        return ["text": text, "top": 1 - box.maxY, "height": box.height]
      }
      DispatchQueue.main.async { completion(lines) }
    }
  }
}
