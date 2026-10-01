//
//  StickerGacha.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  エネルギーを使って、ランダムなシールを手に入れる「ガチャ」の処理。
//  全シール（StickerCatalog.all）が常に同じ確率で出る。
//
//  役割分担:
//    - StickerGacha（このファイル）: 値段の確認・抽選・シールの受け渡し
//    - EnergyStore                 : エネルギーの消費
//    - StickerStore                : 出たシールの保管（ストレージへ直送）
//    - ガチャ画面                    : 演出と結果の表示（このファイルは画面に関与しない）

import Foundation

// MARK: - StickerGacha

/// ガチャの抽選を行う名前空間。
// case のない enum を名前空間として使う理由は ScoreBoard.swift を参照
enum StickerGacha {

    // MARK: まわし方

    /// ガチャのまわし方。値段と出る枚数は EnergyTuning で調整する。
    enum Pull {
        /// 1回まわす。
        case single
        /// 10連でまわす。おまけ付き。
        case ten

        /// 値段（kcal）。
        var price: Double {
            switch self {
            case .single: return EnergyTuning.gachaPrice
            case .ten:    return EnergyTuning.gachaPrice * Double(EnergyTuning.tenPullCount)
            }
        }

        /// 出るシールの枚数（おまけ込み）。
        var count: Int {
            switch self {
            case .single: return 1
            case .ten:    return EnergyTuning.tenPullCount + EnergyTuning.tenPullBonus
            }
        }
    }

    // MARK: 抽選

    /// ガチャをまわす。エネルギーが足りなければ何もせず nil を返す。
    /// 出たシールはストレージへ直送され、同じ配列が戻り値として返る（画面の演出用）。
    ///
    /// ★ 「シールを渡す → エネルギーを減らす」の順にしている理由 ★
    ///   2つの保存のあいだでアプリが終了された場合、逆の順だと
    ///   「エネルギーだけ減ってシールが手に入らない」ことが起きる。
    ///   子ども向けアプリなので、万一のときは子どもが損をしない側に倒している。
    /// - Returns: 出たシールの絵文字（出た順）。エネルギー不足なら nil
    static func pull(_ pull: Pull) -> [String]? {
        let energy = EnergyStore.shared
        guard energy.canAfford(pull.price) else { return nil }

        let results = draw(count: pull.count)
        StickerStore.shared.addStickersToStorage(results)
        energy.spend(pull.price)
        return results
    }

    /// 全シールから均等な確率で count 枚を選ぶ（同じシールが何度出てもよい）。
    // ⚠️ 変更注意: 「全シールが同じ確率」はガチャ画面にも表示する約束。
    //   確率を変えるときは画面の説明文も合わせて直すこと。
    static func draw(count: Int) -> [String] {
        (0..<count).compactMap { _ in StickerCatalog.all.randomElement() }
    }
}
