import UIKit

final class LibraryViewController: UITableViewController {

    private let store: LibraryStore
    private var issues: [IssueInfo] = []
    private let emptyStateView = UIView()

    init(store: LibraryStore) {
        self.store = store
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "News Library"
        view.backgroundColor = .white

        tableView.rowHeight = 84
        tableView.tableFooterView = UIView()
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 74, bottom: 0, right: 0)
        tableView.register(IssueCell.self, forCellReuseIdentifier: IssueCell.reuseIdentifier)

        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Search",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(showSearch))

        buildEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reloadIssues()
    }

    // MARK: - Data

    @objc private func refreshPulled() {
        reloadIssues()
        refreshControl?.endRefreshing()
    }

    private func reloadIssues() {
        store.reload()
        issues = store.issues()
        tableView.reloadData()
        emptyStateView.isHidden = !issues.isEmpty
    }

    // MARK: - Actions

    @objc private func showSearch() {
        let search = SearchViewController(store: store)
        navigationController?.pushViewController(search, animated: true)
    }

    // MARK: - Empty state

    private func buildEmptyState() {
        emptyStateView.frame = view.bounds
        emptyStateView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        emptyStateView.backgroundColor = .white

        let title = UILabel()
        title.text = "No issues yet"
        title.font = UIFont.boldSystemFont(ofSize: 22)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let message = UILabel()
        message.text = "Copy issue folders into\nDocuments/NewsFiles on this iPad.\n\nEach issue folder needs a pages/ folder\nand an optional issue.json, articles/\nand ocr/ folder."
        message.font = UIFont.systemFont(ofSize: 15)
        message.textColor = UIColor(white: 0.35, alpha: 1)
        message.textAlignment = .center
        message.numberOfLines = 0
        message.translatesAutoresizingMaskIntoConstraints = false

        let reload = UIButton(type: .system)
        reload.setTitle("Reload", for: .normal)
        reload.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        reload.translatesAutoresizingMaskIntoConstraints = false
        reload.addTarget(self, action: #selector(refreshPulled), for: .touchUpInside)

        emptyStateView.addSubview(title)
        emptyStateView.addSubview(message)
        emptyStateView.addSubview(reload)
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor, constant: -80),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            message.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor, constant: 32),
            message.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor, constant: -32),
            reload.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 24),
            reload.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor)
        ])
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return issues.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: IssueCell.reuseIdentifier, for: indexPath) as! IssueCell
        let issue = issues[indexPath.row]
        cell.configure(with: issue)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let issue = issues[indexPath.row]
        let controller = IssueViewController(store: store, issue: issue)
        navigationController?.pushViewController(controller, animated: true)
    }
}

final class IssueCell: UITableViewCell {

    static let reuseIdentifier = "IssueCell"

    private let thumbnail = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let metaLabel = UILabel()

    private var thumbnailURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        accessoryType = .disclosureIndicator
        backgroundColor = .white

        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.backgroundColor = UIColor(white: 0.92, alpha: 1)
        thumbnail.layer.cornerRadius = 3
        thumbnail.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = UIColor(white: 0.35, alpha: 1)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = UIFont.systemFont(ofSize: 12)
        metaLabel.textColor = UIColor(white: 0.55, alpha: 1)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnail)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 44),
            thumbnail.heightAnchor.constraint(equalToConstant: 60),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnail.image = nil
        thumbnailURL = nil
    }

    func configure(with issue: IssueInfo) {
        titleLabel.text = issue.title
        subtitleLabel.text = issue.subtitle.isEmpty ? issue.displayDate : "\(issue.subtitle)"
        metaLabel.text = "\(issue.pageCount) pages" + (issue.subtitle.isEmpty ? "" : " · \(issue.displayDate)")

        guard let firstPage = issue.pages.first else { return }
        thumbnailURL = firstPage.imageURL

        ImageLoader.shared.loadImage(for: firstPage.imageURL, maxPixelSize: 160) { [weak self] image in
            guard let self = self, self.thumbnailURL == firstPage.imageURL else { return }
            self.thumbnail.image = image
        }
    }
}
