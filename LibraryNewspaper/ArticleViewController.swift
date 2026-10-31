import UIKit

final class ArticleViewController: UIViewController {

    private let article: ArticleInfo
    private let issue: IssueInfo

    init(article: ArticleInfo, issue: IssueInfo) {
        self.article = article
        self.issue = issue
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = issue.title
        view.backgroundColor = UIColor(white: 0.99, alpha: 1)
        automaticallyAdjustsScrollViewInsets = false

        let textView = UITextView(frame: view.bounds)
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 22, bottom: 48, right: 22)
        textView.attributedText = makeContent()
        view.addSubview(textView)
    }

    private func makeContent() -> NSAttributedString {
        let content = NSMutableAttributedString()

        let headlineStyle = NSMutableParagraphStyle()
        headlineStyle.paragraphSpacing = 8
        content.append(NSAttributedString(string: article.headline + "\n", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 26),
            .foregroundColor: UIColor(white: 0.08, alpha: 1),
            .paragraphStyle: headlineStyle
        ]))

        let meta = "\(issue.title) · Page \(article.pageNumber)"
        let metaStyle = NSMutableParagraphStyle()
        metaStyle.paragraphSpacing = 18
        content.append(NSAttributedString(string: meta + "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
            .paragraphStyle: metaStyle
        ]))

        let body = article.text.isEmpty
            ? "No text was found for this article. Add a transcription to the OCR folder or include a \"text\" value in the article JSON."
            : article.text

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 5
        bodyStyle.paragraphSpacing = 14
        content.append(NSAttributedString(string: body, attributes: [
            .font: UIFont(name: "Georgia", size: 18) ?? UIFont.systemFont(ofSize: 18),
            .foregroundColor: UIColor(white: 0.12, alpha: 1),
            .paragraphStyle: bodyStyle
        ]))

        return content
    }
}
