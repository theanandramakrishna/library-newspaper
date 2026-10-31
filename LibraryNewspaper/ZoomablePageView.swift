import UIKit

protocol ZoomablePageViewDelegate: AnyObject {
    func pageView(_ pageView: ZoomablePageView, didSelect article: ArticleInfo)
    func pageView(_ pageView: ZoomablePageView, didRequestPageOffset offset: Int)
    func pageViewDidRequestChromeToggle(_ pageView: ZoomablePageView)
}

/// Displays one replica page: pinch-zoom, double-tap zoom, tappable article
/// regions and edge swipes for page turns.
final class ZoomablePageView: UIView, UIScrollViewDelegate {

    weak var delegate: ZoomablePageViewDelegate?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let overlayContainer = UIView()
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)

    private var articleButtons: [UIButton] = []
    private var pageArticles: [ArticleInfo] = []
    private var imagePixelSize: CGSize = .zero
    private var isAdjustingZoom = false

    var showsArticleHighlights = true {
        didSet { updateArticleChrome() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .black
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        overlayContainer.backgroundColor = .clear
        overlayContainer.isUserInteractionEnabled = true
        contentView.addSubview(overlayContainer)

        spinner.hidesWhenStopped = true
        spinner.color = .white
        spinner.frame = bounds
        spinner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(spinner)

        let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        leftSwipe.direction = .left
        addGestureRecognizer(leftSwipe)

        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        rightSwipe.direction = .right
        addGestureRecognizer(rightSwipe)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    // MARK: - Content

    func configure(issue: IssueInfo, page: PageInfo, articles: [ArticleInfo]) {
        pageArticles = articles.filter { $0.pageNumber == page.number }
        clearArticleButtons()

        imagePixelSize = .zero
        imageView.image = nil
        contentView.frame = CGRect(origin: .zero, size: CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1)))
        imageView.frame = contentView.bounds
        overlayContainer.frame = contentView.bounds

        if let cached = ImageLoader.shared.cachedImage(for: page.imageURL) {
            apply(image: cached, page: page)
        } else {
            spinner.startAnimating()
            ImageLoader.shared.loadImage(for: page.imageURL, maxPixelSize: 3200) { [weak self] image in
                guard let self = self, self.spinner.isAnimating else { return }
                guard let image = image else {
                    self.spinner.stopAnimating()
                    return
                }
                self.apply(image: image, page: page)
            }
        }
    }

    private func apply(image: UIImage, page: PageInfo) {
        spinner.stopAnimating()

        imagePixelSize = image.size
        contentView.frame = CGRect(origin: .zero, size: image.size)
        imageView.frame = contentView.bounds
        overlayContainer.frame = contentView.bounds
        imageView.image = image

        buildArticleButtons(page: page)
        applyFitZoom()
    }

    private func buildArticleButtons(page: PageInfo) {
        clearArticleButtons()

        let scaleX = page.width > 0 ? imagePixelSize.width / CGFloat(page.width) : 1
        let scaleY = page.height > 0 ? imagePixelSize.height / CGFloat(page.height) : 1

        for (index, article) in pageArticles.enumerated() {
            let rect = CGRect(x: article.bounds.minX * scaleX,
                              y: article.bounds.minY * scaleY,
                              width: article.bounds.width * scaleX,
                              height: article.bounds.height * scaleY)

            let button = UIButton(type: .custom)
            button.frame = rect
            button.tag = index
            button.addTarget(self, action: #selector(articleTapped(_:)), for: .touchUpInside)
            button.layer.cornerRadius = 2
            overlayContainer.addSubview(button)
            articleButtons.append(button)
        }
        updateArticleChrome()
    }

    private func clearArticleButtons() {
        articleButtons.forEach { $0.removeFromSuperview() }
        articleButtons.removeAll()
    }

    private func updateArticleChrome() {
        let scale = max(scrollView.zoomScale / max(scrollView.minimumZoomScale, 0.0001), 1)
        let borderWidth = showsArticleHighlights ? 1.0 / scale : 0
        for button in articleButtons {
            button.layer.borderWidth = borderWidth
            button.layer.borderColor = UIColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 0.9).cgColor
            button.backgroundColor = showsArticleHighlights
                ? UIColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 0.08)
                : UIColor.clear
        }
    }

    // MARK: - Zoom

    private func fitScale() -> CGFloat {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / imagePixelSize.width, bounds.height / imagePixelSize.height)
    }

    private func applyFitZoom() {
        guard imagePixelSize.width > 0 else { return }
        isAdjustingZoom = true
        let fit = fitScale()
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = max(fit * 5, 1.0)
        scrollView.zoomScale = fit
        isAdjustingZoom = false
        centerContent()
        updateArticleChrome()
    }

    private func centerContent() {
        let zoomedSize = CGSize(width: contentView.bounds.width * scrollView.zoomScale,
                                height: contentView.bounds.height * scrollView.zoomScale)
        let insetX = max((bounds.width - zoomedSize.width) / 2, 0)
        let insetY = max((bounds.height - zoomedSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        spinner.frame = bounds
        if imagePixelSize.width > 0 && !isAdjustingZoom {
            if abs(fitScale() - scrollView.minimumZoomScale) > 0.0001 {
                applyFitZoom()
            } else {
                centerContent()
            }
        }
    }

    // MARK: - Gestures

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        guard scrollView.zoomScale <= scrollView.minimumZoomScale * 1.02 else { return }
        delegate?.pageView(self, didRequestPageOffset: recognizer.direction == .left ? 1 : -1)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale * 1.05 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: contentView)
            let target = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 2.5)
            let size = CGSize(width: scrollView.bounds.width / target,
                              height: scrollView.bounds.height / target)
            let rect = CGRect(x: point.x - size.width / 2,
                              y: point.y - size.height / 2,
                              width: size.width,
                              height: size.height)
            scrollView.zoom(to: rect, animated: true)
        }
    }

    @objc private func handleSingleTap() {
        delegate?.pageViewDidRequestChromeToggle(self)
    }

    @objc private func articleTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < pageArticles.count else { return }
        delegate?.pageView(self, didSelect: pageArticles[sender.tag])
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return contentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isAdjustingZoom else { return }
        centerContent()
        updateArticleChrome()
    }
}
