import UIKit

struct ArticleModel {
    let id: Int
    let headline: String
    let bounds: CGRect
    let textFile: String

    enum CodingKeys: String, CodingKey {
        case id, headline, bounds, textFile
    }
}

class ArticleDetailViewController: UIViewController {

    var article: ArticleModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
    }

    func setupUI() {
        view.backgroundColor = .white

        navigationItem.title = "Article"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeButtonTapped))

        let scrollView = UIScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        view.addSubview(scrollView)

        let contentView = UIView(frame: CGRect(x: 0, y: 0, width: scrollView.bounds.width - 20, height: 0))
        scrollView.addSubview(contentView)

        loadArticleContent(scrollView: scrollView, contentView: contentView)
    }

    func loadArticleContent(scrollView: UIScrollView, contentView: UIView) {
        guard let article = article else { return }

        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let issuePath = URL(fileURLWithPath: documentsPath).appendingPathComponent("NewsFiles")

        let textPath = issuePath.appendingPathComponent(issueId(for: article.id)).appendingPathComponent("ocr").appendingPathComponent(article.textFile)

        if let textData = try? Data(contentsOf: textPath), let text = String(data: textData, encoding: .utf8) {

            let titleLabel = UILabel()
            titleLabel.text = article.headline
            titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
            titleLabel.numberOfLines = 0
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.textColor = .black
            contentView.addSubview(titleLabel)

            let textLabel = UILabel()
            textLabel.text = text
            textLabel.font = UIFont.systemFont(ofSize: 14)
            textLabel.numberOfLines = 0
            textLabel.lineBreakMode = .byWordWrapping
            textLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(textLabel)

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
                titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

                textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
                textLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
                textLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
                textLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
            ])

            contentView.frame = CGRect(x: 0, y: 0, width: contentView.bounds.width, height: 0)
            contentView.setNeedsLayout()
            contentView.layoutIfNeeded()

            scrollView.contentSize = contentView.bounds.size
        }
    }

    func issueId(for articleId: Int) -> String {
        return String(format: "issue_%d", articleId)
    }

    @objc func closeButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
}

extension ArticleDetailViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {

    }
}