import UIKit

class PageContentViewController: UIViewController {

    var image: UIImage?

    override func viewDidLoad() {
        super.viewDidLoad()

        setupPageContentView()
    }

    func setupPageContentView() {
        view.backgroundColor = .white

        navigationItem.title = "Page View"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeButtonTapped))

        let scrollView = UIScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 3.0
        view.addSubview(scrollView)

        let contentView = UIView(frame: view.bounds)
        scrollView.addSubview(contentView)

        if let image = image {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])

            scrollView.contentSize = image.size
        }
    }

    @objc func closeButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
}

extension PageContentViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return scrollView.subviews.first
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {

    }
}