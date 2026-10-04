//
//  ThanksNotebookView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の画面本体。手帳のページ（きょう／カレンダー／まとめ）を切り替える入れ物。
//  いまは「きょう」のページだけ。カレンダー・まとめと付箋のタブは順に足していく
//  （docs/SPEC_thanks_notebook.md を参照）。

import SwiftUI

// MARK: - ThanksNotebookView

struct ThanksNotebookView: View {
    var body: some View {
        ThanksTodayView()
    }
}
