//
//  StickerCutout.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/07.
//
//  写真から、写っている人や物だけを切り抜いて、背景を透明にする。
//
//  ★ 端末の中だけで処理する ★
//    iOS の Vision という仕組みを使う。写真はどこにも送られない（通信もしない）。
//
//  ★ VNGenerateForegroundInstanceMaskRequest とは？ ★
//    写真の中から「手前にあるもの」を見つけて、その形の型（マスク）を作る、iOS 17 からの機能。
//    何が写っているかは見分けない（「犬」とは判断せず、「手前に何かある」とだけ見る）。
//    手前のものが見つからない写真（一面の空など）では、結果が空になる。

import CoreImage
import UIKit
import Vision

enum StickerCutout {

    /// 写真の背景を透明にした画像を返す。切り抜けなかったときは nil。
    /// 時間がかかる処理なので、画面が止まらないよう別の流れ（Task.detached）で動かす。
    /// - Parameter image: 向きが「上」にそろった写真（CustomStickerMakerView.shrunk を通したもの）
    static func cutout(_ image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            makeCutout(cgImage)
        }.value
    }

    /// ★ nonisolated にしている理由 ★
    ///   このアプリはふだんすべてを画面の流れ（MainActor）で動かしている。そのままだと、
    ///   切り抜きの間は画面が止まってしまうので、この関数だけ画面の流れから外す。
    nonisolated private static func makeCutout(_ cgImage: CGImage) -> UIImage? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }   // 手前のものが見つからなかった
            // croppedToInstancesExtent を false にして、もとの写真と同じ大きさのまま受け取る
            // （大きさが同じなら、切り抜いても絵の位置がずれない）
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                        from: handler,
                                                        croppedToInstancesExtent: false)
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            print("StickerCutout: 切り抜きエラー: \(error.localizedDescription)")
            return nil
        }
    }
}
