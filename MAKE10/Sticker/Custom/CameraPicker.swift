//
//  CameraPicker.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/07.
//
//  シールづくりで写真を撮るカメラの画面。iOS に用意されたカメラ画面を SwiftUI から使う。
//
//  ★ 写真はアプリの外に保存しない ★
//    撮った写真は写真アプリに入らず、シールを作るまでメモリの中だけにある。
//    シールになるときは 400px の画像に描き直すので、撮った場所などの情報（Exif）も残らない。
//
//  ★ 撮影を確かめるのは実機で ★
//    シミュレータでもカメラの画面は開くが、映像が出ずシャッターも切れない（Xcode 27 で確認）。

import AVFoundation
import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {

    /// 写真を撮ったときに呼ばれる。キャンセルしたときは呼ばれない。
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// この端末でカメラを使えるか。
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// カメラの許可を「許可しない」にしているか（まだ聞いていないときは false）。
    static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// カメラ画面からの知らせを受ける係（UIKit の仕組みなので、クラスにする必要がある）。
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
