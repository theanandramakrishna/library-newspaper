import UIKit

class PageViewController: UIViewController {

    let issueId: String

    init(issueId: String) {
        self.issueId = issueId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupPageView()
    }

    func setupPageView() {
        title = "Issue Details"
        view.backgroundColor = .white

        let scrollView = UIScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 3.0
        view.addSubview(scrollView)

        let contentView = UIView(frame: view.bounds)
        scrollView.addSubview(contentView)

        loadPages(scrollView: scrollView, contentView: contentView)
    }

    func loadPages(scrollView: UIScrollView, contentView: UIView) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let issuePath = URL(fileURLWithPath: documentsPath).appendingPathComponent("NewsFiles").appendingPathComponent(issueId)

        guard FileManager.default.fileExists(atPath: issuePath.path) else {
            showError("Issue not found")
            return
        }

        let pagesPath = issuePath.appendingPathComponent("pages")
        let articlesPath = issuePath.appendingPathComponent("articles")

        var yPosition: CGFloat = 0

        do {
            let pageFiles = try FileManager.default.contentsOfDirectory(atPath: pagesPath.path)
            for pageFile in pageFiles {
                if pageFile.hasSuffix(".jpg") || pageFile.hasSuffix(".jpeg") {
                    let pagePath = pagesPath.appendingPathComponent(pageFile)

                    let imageView = UIImageView(frame: CGRect(x: 0, y: yPosition, width: contentView.bounds.width, height: 0))
                    imageView.contentMode = .scaleAspectFit
                    imageView.clipsToBounds = true
                    imageView.isUserInteractionEnabled = true

                    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(pageTapped(_:)))
                    imageView.addGestureRecognizer(tapGesture)

                    if let imageData = try? Data(contentsOf: pagePath), let image = UIImage(data: imageData) {
                        imageView.image = image
                        imageView.frame = CGRect(x: 0, y: yPosition, width: contentView.bounds.width, height: image.size.height * (contentView.bounds.width / image.size.width))

                        contentView.addSubview(imageView)

                        yPosition += imageView.frame.height
                    }
                }
            }
        } catch {
            showError("Failed to load pages: \(error)")
        }

        do {
            let articleFiles = try FileManager.default.contentsOfDirectory(atPath: articlesPath.path)
            for articleFile in articleFiles {
                if articleFile.hasSuffix(".json") {
                    let articlePath = articlesPath.appendingPathComponent(articleFile)
                    if let data = try? Data(contentsOf: articlePath), let article = parseArticle(data: data) {
                        addArticleAnnotation(view: contentView, article: article)
                    }
                }
            }
        } catch {
            print("Failed to load articles: \(error)")
        }

        contentView.frame = CGRect(x: 0, y: 0, width: contentView.bounds.width, height: yPosition)
        scrollView.contentSize = contentView.bounds.size
    }

    func parseArticle(data: Data) -> ArticleModel? {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(ArticleModel.self, from: data)
        } catch {
            print("Error parsing article: \(error)")
            return nil
        }
    }

    func addArticleAnnotation(view: UIView, article: ArticleModel) {
        let frame = article.bounds
        let articleView = UIView(frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height))
        articleView.backgroundColor = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.3)
        articleView.tag = Int(article.id)
        articleView.isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(articleTapped(_:)))
        articleView.addGestureRecognizer(tapGesture)

        view.addSubview(articleView)
    }

    @objc func pageTapped(_ sender: UITapGestureRecognizer) {
        guard let imageView = sender.view as? UIImageView else { return }
        let pageVC = PageContentViewController()
        pageVC.image = imageView.image
        navigationController?.pushViewController(pageVC, animated: true)
    }

    @objc func articleTapped(_ sender: UITapGestureRecognizer) {
        guard let articleView = sender.view else { return }
        let articleId = articleView.tag

        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let issuePath = URL(fileURLWithPath: documentsPath).appendingPathComponent("NewsFiles").appendingPathComponent(issueId)
        let articlesPath = issuePath.appendingPathComponent("articles")

        let articleFile = "article_\(articleId).json"
        let articlePath = articlesPath.appendingPathComponent(articleFile)

        if let data = try? Data(contentsOf: articlePath), let article = parseArticle(data: data) {
            let articleVC = ArticleDetailViewController()
            articleVC.article = article
            navigationController?.pushViewController(articleVC, animated: true)
        }
    }

    func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension PageViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return scrollView.subviews.first
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {

    }
}