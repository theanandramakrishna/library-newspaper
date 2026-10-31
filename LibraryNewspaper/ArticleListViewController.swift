import UIKit

final class ArticleListViewController: UITableViewController {

    private let articles: [ArticleInfo]
    var onSelect: ((ArticleInfo) -> Void)?

    init(articles: [ArticleInfo]) {
        self.articles = articles
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Articles"
        tableView.rowHeight = 56
        tableView.tableFooterView = UIView()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return articles.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let article = articles[indexPath.row]
        cell.textLabel?.text = article.headline
        cell.textLabel?.numberOfLines = 2
        cell.detailTextLabel?.text = "Page \(article.pageNumber)"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        onSelect?(articles[indexPath.row])
    }
}
