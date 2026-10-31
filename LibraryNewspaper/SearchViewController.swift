import UIKit

final class SearchViewController: UITableViewController, UISearchBarDelegate {

    private let store: LibraryStore
    private let searchBar = UISearchBar()
    private var results: [SearchHit] = []
    private var pendingSearch: DispatchWorkItem?

    init(store: LibraryStore) {
        self.store = store
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Search"
        automaticallyAdjustsScrollViewInsets = false

        searchBar.delegate = self
        searchBar.placeholder = "Search all issues"
        searchBar.searchBarStyle = .minimal
        searchBar.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
        tableView.tableHeaderView = searchBar

        tableView.rowHeight = 76
        tableView.tableFooterView = UIView()
    }

    // MARK: - Search

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        pendingSearch?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.results = self.store.search(searchText)
            self.tableView.reloadData()
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        results = store.search(searchBar.text ?? "")
        tableView.reloadData()
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let hit = results[indexPath.row]

        cell.textLabel?.attributedText = highlighted(hit.headline, query: searchBar.text ?? "")
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.text = "\(hit.issue.title) · Page \(hit.pageNumber) — \(hit.snippet)"
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let hit = results[indexPath.row]
        let controller = IssueViewController(store: store, issue: hit.issue, startPage: hit.pageNumber)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func highlighted(_ text: String, query: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 15),
            .foregroundColor: UIColor(white: 0.1, alpha: 1)
        ])
        guard !query.isEmpty else { return attributed }

        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            attributed.addAttribute(.foregroundColor,
                                    value: UIColor(red: 0.1, green: 0.45, blue: 0.9, alpha: 1),
                                    range: NSRange(found, in: text))
            searchRange = found.upperBound..<text.endIndex
        }
        return attributed
    }
}
