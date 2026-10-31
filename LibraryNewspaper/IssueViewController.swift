import UIKit

final class IssueViewController: UIViewController, ZoomablePageViewDelegate {

    private let store: LibraryStore
    private let issue: IssueInfo
    private var pageIndex: Int
    private var articles: [ArticleInfo] = []
    private var chromeVisible = true

    private let pageView = ZoomablePageView()
    private let toolbar = UIView()
    private let pageLabel = UILabel()
    private let slider = UISlider()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    init(store: LibraryStore, issue: IssueInfo, startPage: Int = 1) {
        self.store = store
        self.issue = issue
        self.pageIndex = max(0, min(issue.pages.count - 1, startPage - 1))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = issue.title
        view.backgroundColor = .black
        automaticallyAdjustsScrollViewInsets = false

        setupPageView()
        setupToolbar()
        setupNavigationItems()

        articles = store.articles(for: issue)
        showPage(at: pageIndex)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(!chromeVisible, animated: animated)
        applyChrome()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override var prefersStatusBarHidden: Bool {
        return !chromeVisible
    }

    // MARK: - Setup

    private func setupPageView() {
        pageView.delegate = self
        pageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageView)

        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: view.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupToolbar() {
        toolbar.backgroundColor = UIColor(white: 0.05, alpha: 0.88)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        previousButton.setTitle("‹", for: .normal)
        previousButton.titleLabel?.font = UIFont.systemFont(ofSize: 28)
        previousButton.tintColor = .white
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        previousButton.addTarget(self, action: #selector(previousPage), for: .touchUpInside)

        nextButton.setTitle("›", for: .normal)
        nextButton.titleLabel?.font = UIFont.systemFont(ofSize: 28)
        nextButton.tintColor = .white
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addTarget(self, action: #selector(nextPage), for: .touchUpInside)

        pageLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pageLabel.textColor = UIColor(white: 0.9, alpha: 1)
        pageLabel.textAlignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = false
        slider.minimumTrackTintColor = UIColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 1)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        toolbar.addSubview(previousButton)
        toolbar.addSubview(pageLabel)
        toolbar.addSubview(slider)
        toolbar.addSubview(nextButton)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            previousButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            previousButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 40),

            nextButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            nextButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 40),

            pageLabel.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 4),
            pageLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: 66),

            slider.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 4),
            slider.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -4),
            slider.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor)
        ])
    }

    private func setupNavigationItems() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Articles", style: .plain, target: self, action: #selector(showArticles)),
            UIBarButtonItem(title: "Text", style: .plain, target: self, action: #selector(showPageText))
        ]
    }

    // MARK: - Paging

    private func showPage(at index: Int) {
        guard index >= 0, index < issue.pages.count else { return }
        pageIndex = index
        let page = issue.pages[index]

        UIView.transition(with: pageView, duration: 0.18, options: .transitionCrossDissolve, animations: {
            self.pageView.configure(issue: self.issue, page: page, articles: self.articles)
        }, completion: nil)

        updateToolbar()
        prefetchNeighbour(of: index)
    }

    private func prefetchNeighbour(of index: Int) {
        let next = index + 1
        guard next < issue.pages.count else { return }
        ImageLoader.shared.loadImage(for: issue.pages[next].imageURL, maxPixelSize: 3200) { _ in }
    }

    private func updateToolbar() {
        pageLabel.text = "\(pageIndex + 1) / \(issue.pages.count)"
        slider.maximumValue = Float(max(issue.pages.count - 1, 1))
        slider.value = Float(pageIndex)
        previousButton.isEnabled = pageIndex > 0
        nextButton.isEnabled = pageIndex < issue.pages.count - 1
    }

    @objc private func previousPage() {
        showPage(at: pageIndex - 1)
    }

    @objc private func nextPage() {
        showPage(at: pageIndex + 1)
    }

    @objc private func sliderChanged() {
        showPage(at: Int(slider.value.rounded()))
    }

    // MARK: - Chrome

    private func toggleChrome() {
        chromeVisible = !chromeVisible
        navigationController?.setNavigationBarHidden(!chromeVisible, animated: true)
        setNeedsStatusBarAppearanceUpdate()
        applyChrome()
    }

    private func applyChrome() {
        let alpha: CGFloat = chromeVisible ? 1 : 0
        UIView.animate(withDuration: 0.2, animations: {
            self.toolbar.alpha = alpha
        }, completion: { _ in
            self.toolbar.isHidden = !self.chromeVisible
        })
    }

    // MARK: - Article actions

    private func showArticle(_ article: ArticleInfo) {
        let controller = ArticleViewController(article: article, issue: issue)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func showArticles() {
        guard !articles.isEmpty else {
            let alert = UIAlertController(title: "No articles",
                                          message: "This issue has no article data. Add JSON files to its articles/ folder.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let controller = ArticleListViewController(articles: articles)
        controller.onSelect = { [weak self] article in
            guard let self = self else { return }
            self.dismiss(animated: true, completion: {
                self.showPage(at: article.pageNumber - 1)
                self.showArticle(article)
            })
        }
        controller.modalPresentationStyle = .popover
        controller.preferredContentSize = CGSize(width: 360, height: 440)
        if let popover = controller.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
            popover.permittedArrowDirections = .any
        }
        present(controller, animated: true, completion: nil)
    }

    @objc private func showPageText() {
        let page = issue.pages[pageIndex]
        let text = store.ocrText(for: issue, page: page)
        let article = ArticleInfo(id: "page-\(page.number)",
                                  pageNumber: page.number,
                                  headline: "Page \(page.number)",
                                  bounds: .zero,
                                  text: text)
        navigationController?.pushViewController(ArticleViewController(article: article, issue: issue), animated: true)
    }

    // MARK: - ZoomablePageViewDelegate

    func pageView(_ pageView: ZoomablePageView, didSelect article: ArticleInfo) {
        showArticle(article)
    }

    func pageView(_ pageView: ZoomablePageView, didRequestPageOffset offset: Int) {
        showPage(at: pageIndex + offset)
    }

    func pageViewDidRequestChromeToggle(_ pageView: ZoomablePageView) {
        toggleChrome()
    }
}
