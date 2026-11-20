import Foundation
@main struct DeveloperTermCorrectionTests {
 static func main() {
  for (input, expected) in [
    ("ギター部に保存します", "GitHubに保存します"),
    ("ギターブに保存します", "GitHubに保存します"),
    ("ギターに保存します", "GitHubに保存します"),
    ("LitHubへプッシュしてください", "GitHubへプッシュしてください"),
    ("ギターのリポジトリ", "GitHubのリポジトリ"),
    ("きっとハブにコミットする", "GitHubにコミットする")
  ] { precondition(DeveloperTermCorrection.apply(input) == expected) }
  for text in ["ギター部に入部します", "ギター部の練習", "ギターを弾きます", "ギターのコード", "ギターを保存します", "LitHubの記事を読みます", "ギターハブ", "GitHubに保存します", "ギターに興味があります"] {
   precondition(DeveloperTermCorrection.apply(text) == text, text)
  }
  print("PASS: GitHub repository context corrections and musical instrument preservation")
 }
}
